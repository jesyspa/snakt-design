## !First Concept! for the Purity Checker

We want a call of `checkValidity()` on an arbitrary `ExpEmbedding` node to return `true` if all `assert` statements present contain only pure statements, and `false` as soon as one of them is impure. We split the logic into traversal and validation, currently only focussing on the validation of expressions appearing inside of `assert`nodes.

Every `ExpEmbedding` implements a new `children` property and the functions `checkValidity` and `checkOwnValidity`.

The default for `children` is an empty immutable list (`emptyList()`); when overridden it must still be an immutable list referencing the children’s subsequent embeddings.

| **Embedding** | **Child Node(s)** |
| --- | --- |
| Assert | `exp` |
| Block | `exps[]` |
| Assign | `lhs`, `rhs` |
| DirectResult | `subexpressions` |
| Passthrough | `inner` |
| If | `condition`, `thenBranch`, `elseBranch` |
| While | `condition`, `body` |
| MethodCall | `args` |
| Elvis | `left`, `right` |

---

### checkValidity

```kotlin
fun checkValidity(): Boolean =
    children().all { it.checkValidity() } && checkOwnValidity()

```

`checkValidity` is responsible only for traversing; the above is the default implementation every `ExpEmbedding` inherits.

---

### checkOwnValidity

```kotlin
interface ExpEmbedding {
    fun children(): List<ExpEmbedding> = emptyList()
    fun checkOwnValidity(): Boolean = true
}

```

The default local rule just returns `true`.

---

### Only validating `Assert`

```kotlin
data class Assert(val exp: ExpEmbedding) : ExpEmbedding {

    override fun children(): List<ExpEmbedding> = listOf(exp)

    override fun checkValidity(): Boolean =
        checkOwnValidity()                       // stop traversal here

    override fun checkOwnValidity(): Boolean =
        PurityRules.isExpressionValid(exp)
}

```

`Assert` ends the traversal and validates only itself.

---

### PurityRules

`assert` can only contain embeddings evaluating to a boolean, so for the validation I can restrict myself to:

```kotlin
private val pureSpecialFunctions: Set<MangledName> = place a pure Subset of the FullySpecialKotlionFunctions here

object PurityRules {
    fun isExpressionValid(e: ExpEmbedding): Boolean = when (e) {
        is LiteralEmbedding -> true
        is VariableEmbedding -> true
        is MethodCall -> {
            val calleePure = e.method.name in pureSpecialFunctions
            calleePure && e.args.all(::isExpressionValid)
        } // for now no other methods, Pure annotation follows
        
        // always forbidden inside verify(...)
        is Assert,
        is Assign         -> false

        else -> e.children().all(::isExpressionValid)   // covers DirectResult, etc.
    }
}

```

By splitting traversal and validation like this, adapting to future changes (e.g., pure-method annotations) should be simpler than with the previous purity-checker class. I opted to implement `children` for all nodes so that individual `checkValidity` overrides are rarely needed, and because the whole mechanism is stateless I can simply call `checkValidity` on the root of the tree.

I am assuming that I don’t need to check whether asserts only contain BooleanTypeEmbeddings, because it already throws errors, when something doesn’t evaluate to a boolean.
It would not work for strings afaik. I also haven’t found out how to check which operation is used inside an assert (≤,<, ==) but I honestly think, that that wouldn’t be necessary since we don’t check the type anyway.

So, this would be the first idea.