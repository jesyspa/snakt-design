## Concept for the Purity Checker

We want to introduce a notion of validity to our `ExpEmbedding` nodes.
The first violation of validity would be the existence of an impure `assert` statement.
 

Every `ExpEmbedding` implements a new `children` property (`:Sequence<ExpEmbedding>`) and the function `isValid()`. 

---

### Preorder

We define an extension function `ExpEmbedding.preorder()` that traverses the `ExpEmbedding` tree and returns an iterable sequence of the nodes in preorder. 

### checkValidity

To check the validity of the graph, we obtain it using the `preorder` function. We filter all embeddings for which we want to check validity and call `isValid()` on them.

```kotlin
fun ExpEmbedding.checkValidity(): Boolean =
    preorder()
        .filterIsInstance<Assert>()
        .all { it.isValid() }
```

---

### isValid

```kotlin
interface ExpEmbedding {
    // ...
    
    fun children(): Sequence<ExpEmbedding> = emptySequence()
    
    fun isValid(): Boolean = true
}
```
We want to be able to ask a node to self-validate. We do this via a `isValid` call.
The default local rule simply returns `true`. (For any `ExpEmbedding` other than `Assert`, there is currently nothing that can violate validity.)



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

The `ExprPurityVisitor` is responsible for traversing `Assert` expressions and verifying their purity. It should reject any construct that either cannot appear inside an `assert` or is impure (currently `return false`). At the same time, it should accept expressions that are pure in the base cases (`return true`) and recursively traverse the expression tree down to its leaves where necessary.

Sure! Here's the polished English version in a code block for easy copying:

Got it — you liked the visual style of the indentation, just not the fact that Markdown ignores it.

To preserve the indentation *and* make it render properly, we can wrap it in a **code block**. That way, the indentation is preserved exactly as you intended, and it's still readable in Markdown renderers like GitHub or GitLab.

Here’s the version with indentation that **renders as-is**:


## Diagnostics Reporting

In order to be able to run tests in the first place, we want to use the `DiagnosticReporter`. The reporter and context live inside the `ViperPoweredDeclarationChecker` and are not propagated further.

The pipeline from processing a `FirSimpleFunction` declaration all the way to checking individual `Assert` expressions is:

```
ViperPoweredDeclarationChecker.check()
    → ProgramConverter.registerForVerification()
        → StmtConversionContext.convertMethodWithBody()
            → ExpEmbedding.checkValidity()
                → Assert.isValid()
```

The `isValid()` call then does its thing using the `ExprPurityVisitor`, as mentioned before, and produces a result for a single expression. Based on this result, we want to emit a diagnostic message such as:

```
[Purity] verify(true) - expression is pure
```

Since the `DiagnosticReporter` is not available in `isValid`, we decided it's unnecessary to propagate all the data required for a `reportOn()` call—especially when the only varying components are the `expr` and whether or not it is pure. Instead, we define a lambda:

```
reportPurityDiag: (String, String) -> Unit
```

This allows us to pass only the essential information, while the surrounding context (which doesn't change) remains fixed within the `ViperPoweredDeclarationChecker`.

To propagate this lambda, we’ve opted to use `context` parameters—function signatures are already cluttered in places, and no single function other than `Assert.isValid()` actually needs `reportPurityDiag`.

To access a clear-text version of the expression inside an `Assert`, we take advantage of the fact that `FirStatement` elements are wrapped in a `withPosition` container during conversion. This wrapper stores useful source information alongside the corresponding `ExpEmbedding`. Using it, we can retrieve the original source representation via `getElementTextInContextForDebug()`, which allows us to generate a meaningful error message.