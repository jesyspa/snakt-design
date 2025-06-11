## Purity Checker

We want to introduce a notion of validity to our `ExpEmbedding` nodes.
The first violation of validity would be the existence of an impure `assert` statement.
 

Every `ExpEmbedding` implements a new `children` property (`:Sequence<ExpEmbedding>`) and the function `isValid()`. 

---

### Preorder

We define an extension function `ExpEmbedding.preorder()` that traverses the `ExpEmbedding` tree and returns an iterable sequence in the graph's preorder. SnaKt stores information about FIR source elements by encapsulating an embedding in a `WithPosition` node. To enable accurate positioning in diagnostic reporting, we introduce a new helper:
```kotlin
class PositionedExpEmbedding(val embedding: ExpEmbedding, val source: KtSourceElement?)
```
`preorder()` should then return a sequence of `PositionedExpEmbedding` where each element contains the nearest `withPosition` parent.

---

### ExpEmbedding.checkValidity()

To check the validity of the graph, we obtain it using the `preorder` function. We call `preorder()` and ask each node to self-validate.

---

### isValid

```kotlin
interface ExpEmbedding {
    // ...
    
    fun children(): Sequence<ExpEmbedding> = emptySequence()
    
    fun isValid(): Boolean = true
}
```
We want to be able to ask a node to self-validate. We do this via a `isValid()` call.
The default local rule simply returns `true` (noop). (For any `ExpEmbedding` other than `Assert`, there is currently nothing that can violate validity.)



#### Self-validation of `Assert`

For an `Assert` node, validity is violated if the expression inside is impure. We pass the expression inside the `assert` to a special visitor.

```kotlin
data class Assert(val exp: ExpEmbedding) : ExpEmbedding {
    // ...

    override fun children(): Sequence<ExpEmbedding> = sequenceOf(exp)

    override fun isValid(): Boolean {
        /*---error reporting here---*/
        return exp.accept(ExprPurityVisitor)
    } 
        
}
``` 

---

### Functionality of `ExprPurityVisitor`

The `ExprPurityVisitor` is responsible for analyzing expressions and determining whether they are pure. It should return `false` for impure constructs and `true` for pure ones, recursively traversing the expression tree as necessary.

---

## Error Reporting

Each time a validity rule is violated, we want to emit an error message, highlighting the node that is in violation. We introduce a notion of context to our purity checker, which currently consists of the `ErrorCollector` and the FIR source element.


```kotlin
interface PurityContext {
    val source: KtSourceElement?
    val errorCollector: ErrorCollector
}
```

We recall that preorder() returns a `Sequence<PositionedExpEmbedding>`. So, when calling `isValid()`, we pass a `PurityContext` instance for each node, containing both the position information and the `errorCollector`.

A node like `assert` then calls `addPurityError()` if the validity check fails:

```kotlin
ctx.errorCollector.addPurityError(ctx.source!!, "Assert condition is impure")
```