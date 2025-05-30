## Concept for the Purity Checker

We want to introduce a notion of validity to our `ExpEmbedding` nodes.
The first violation of validity would be the existence of an impure `assert` statement.
 

Every `ExpEmbedding` implements a new `children` property (`:Sequence<ExpEmbedding>`) and the function `checkOwnValidity`. 
Example below

| **Embedding** | **children**                            |
| ------------- | --------------------------------------- |
| Assert        | `exp`                                   |
| Block         | `exps[]`                                |
| Assign        | `lhs`, `rhs`                            |
| DirectResult  | `subexpressions`                        |
| Passthrough   | `inner`                                 |
| If            | `condition`, `thenBranch`, `elseBranch` |
| While         | `condition`, `body`                     |
| MethodCall    | `args`                                  |

---

### Preorder

We define an extension function `ExpEmbedding.preorder()` that traverses the `ExpEmbedding` tree and returns an iterable sequence of the nodes in preorder.

```kotlin
fun ExpEmbedding.preorder(): Sequence<ExpEmbedding> = sequence {
    val stack = ArrayDeque<Iterator<ExpEmbedding>>()
    stack.addFirst(sequenceOf(this@preorder).iterator())

    while (stack.isNotEmpty()) {
        val it = stack.first()
        if (it.hasNext()) {
            val node = it.next()
            yield(node)

            val childIter = node.children().iterator()
            if (childIter.hasNext()) stack.addFirst(childIter)
        } else {
            stack.removeFirst()
        }
    }
}
```

### checkValidity

To check the validity of the graph, we obtain it using the `preorder` function. We filter all embeddings for which we want to check validity and call `checkOwnValidity` on them.

```kotlin
fun ExpEmbedding.checkValidity(): Boolean =
    preorder()
        .filterIsInstance<Assert>()
        .all { it.checkOwnValidity() }
```

---

### checkOwnValidity

```kotlin
interface ExpEmbedding {
    // ...
    
    fun children(): Sequence<ExpEmbedding> = emptySequence()
    
    fun checkOwnValidity(): Boolean = true
}
```
We want to be able to ask a node to self-validate. We do this via a `checkOwnValidity` call.
The default local rule simply returns `true`. (For any `ExpEmbedding` other than `Assert`, there is currently nothing that can violate validity.)



#### Self-validation of `Assert`

For an `Assert` node, validity is violated if the expression inside is impure. We pass the expression inside the `assert` to a special visitor.

```kotlin
data class Assert(val exp: ExpEmbedding) : ExpEmbedding {
    // ...

    override fun children(): Sequence<ExpEmbedding> = sequenceOf(exp)

    override fun checkOwnValidity(): Boolean = 
        exp.accept(ExprPurityVisitor)
}
``` 

---

### Functionality of `ExprPurityVisitor`

The `ExprPurityVisitor` is responsible for traversing `Assert` expressions and verifying their purity. It should reject any construct that either cannot appear inside an `assert` or is impure (currently `return false`). At the same time, it should accept expressions that are pure in the base cases (`return true`) and recursively traverse the expression tree down to its leaves where necessary.