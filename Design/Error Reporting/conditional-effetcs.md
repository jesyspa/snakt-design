Some terminology, as reported by the Kotlin’s Contract KEEP document:

> If the effect is observed, then the condition is guaranteed to be true.

```kotlin
contract {
    returns() implies (booleanExpression)
}
```

---

## Conditional Effects Warning

### Overview

* How the warning messages for conditional effects should look like?

* What level of detail is appropriate for displaying the messages?

Right now, our test-suite has contracts using conditional effects of the following kind:

* `returns() implies false`

* `returns() implies (x is Unit)`

* `returns() implies (a !is IntHolder)`

However, the right-hand side of the implication can be a compound boolean expression. Therefore, the warning message
may not easy to build.

To begin with, an easy solution is breaking down the problem as such:

1. Use a generic warning message like: `The boolean expression 'e' might not hold` (where `e` is the implication’s
    right-hand side).

2. Specialize the message according to the boolean expression:
    
    a. *Type Assertion* (`is`, `!is`).

    b. *Nullability checks* (`== null`, `!= null`).

    c. *Compound Statements*: a generic message similar to the previous one.


### Contracts

Type: Returns null with type assertion

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun mayReturnNonNull(x: Any?): Any? {
    contract {
        returns(null) implies (x is Int)
    }
    return x
}
```

Generalization:

* Implication: `returns(null) => (x is T)`
* Failing implication: `returns(null)` holds true, `(x is T)` holds false (T implies F = F)
* Counter-example: 
    * `x` is of type different from `T`.
    * the function returns a `null` value.
    * the type assertion predicate does not hold because the target variable (`x`) is not the expected type (`T`).

Concrete counter-example:
* We invoke the function `mayReturnNonNull(null)`.
* The function returns `x`, and so `null`.
* The implication’s premises hold (we returned `null`).
* The implication’s conclusion does not hold, since `null !is Int`.

---

Type: Returns not-null with type assertion (1)

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun notNullWithTypeAssertion1(x: Any?): Any? {
    contract {
        returnsNotNull() implies (x is Int)
    }
    return x
}

@OptIn(ExperimentalContracts::class)
fun notNullWithTypeAssertion2(x: Any?, y: Int): Any? {
    contract {
        returnsNotNull() implies (x is Int)
    }
    return y
}
```

Generalization:

* Implication: `returnsNotNull() => (x is T)`
* Failing implication: `returnsNotNull()` holds true, `(x is T)` holds false (T implies F = F).
* Counter-example: 
    * `x` is of type different from `T`.
    * the function returns a non-`null` value.
    * the type assertion predicate does not hold because the target variable (`x`) is not the expected type (`T`).

Concrete counter-example (for `notNullWithTypeAssertion1`):
* We invoke the function `notNullWithTypeAssertion1("Hello")`.
* The function returns `x`, and so `"Hello"`.
* The implication’s premises hold (we returned a value different from `null`).
* The implication’s conclusion does not hold, since `"Hello" !is Int`.

Concrete counter-example for `notNullWithTypeAssertion2`:
* We invoke the function `notNullWithTypeAssertion2(x = null, y = 42)`.
* The function returns `y`, and so `42`.
* The implication’s premises hold (we returned a value different from `null`).
* The implication’s conclusion does not hold, since `x = null` and `x !is Int`.

---

Type: Returning boolean with nullability condition

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun isNullOrEmptyWrong(seq: CharSequence?): Boolean {
    contract {
        returns(false) implies (seq != null)
    }
    return seq != null && seq.length > 0
}
```

Generalization:

* Implication: `returns(bool) => (x != null)`
* Failing implication: `returns(bool)` holds true, `(x != null)` holds false (T implies F = F)
* Counter-example: 
    * we return the expected boolean value.
    * the nullability condition does not hold.

Concrete counter-example:
* We invoke the function `isNullOrEmptyWrong(null)`.
* The function returns `seq != null && seq.length > 0`.
* Since `seq = null`, the returned boolean expression is `false`.
* The implication’s premises hold (we returned `false`).
* The implication’s conclusion does not hold, since `seq` is `null`.

---

Type: Returns boolean with type assertion

Code: 
```kotlin
@OptIn(ExperimentalContracts::class)
fun returnsTrueWithTypeAssertion(x: Any?): Boolean {
    contract {
        returns(true) implies (x is Int)
    }
    return (x == null)
}
```

Generalization:

* Implication: `returns(bool) => (x is T)`
* Failing implication: `returns(bool)` holds true, `(x is T)` holds false (T implies F = F)
* Counter-example: 
    * `x` is of type different from `T`.
    * the function returns the expected `bool` value.
    * the type assertion predicate does not hold because the target variable (`x`) is not the expected type (`T`).

Concrete counter-example:
* We invoke the function `returnsTrueWithTypeAssertion(null)`.
* The function returns `x == null`, so `true`.
* The implication’s premises hold (we returned `true`).
* The implication’s conclusion does not hold, since `null !is Int`.

---

Type: Empty returns with type assertion

```kotlin
@OptIn(ExperimentalContracts::class)
fun emptyReturnsWithTypeAssertion(x: Any?) {
    contract {
        returns() implies (x is Int)
    }
}
```

Generalization:

* Implication: `returns() => (x is T)`
* Failing implication: `returns()` holds true, `(x is T)` holds false (T implies F = F)
* Counter-example: 
    * `x` is of type different from `T`.
    * the function returns.
    * the type assertion predicate does not hold because the target variable (`x`) is not the expected type (`T`).

Concrete counter-example:
* We invoke the function `emptyReturnsWithTypeAssertion(null)`.
* The function returns.
* The implication’s premises hold.
* The implication’s conclusion does not hold, since `null !is Int`.

## Implementation

We start implementing the generic message. The generic message looks like this:

>  `{0} implies '{1}' condition, although the latter might not hold.`

The placeholders are:
* `{0}` can be:
    * `Returning a 'x' value`, where `x` can be a boolean value, or `null`, `non-null`.
    * `The returning function`, when the ‘returns’ effect is empty.

* `{1}` is the right-hand side of the implication.

### Example 1

As an example:

```kotlin
@OptIn(ExperimentalContracts::class)
fun notNullWithTypeAssertion2(x: Any?, y: Int): Any? {
    contract {
        <!CONDITIONAL_EFFECT_ERROR!>returnsNotNull() implies (x is Int)<!>
    }
    return y
}
```

In the conditional effect marked with the annotation `CONDITIONAL_EFFECT_ERROR`, we will output:

> `Returning a ‘non-null’ values implies ‘x is Int’ condition, although the latter might not hold.`

### Example 2

As an example:

```kotlin
@OptIn(ExperimentalContracts::class)
fun emptyReturnsWithTypeAssertion(x: Any?) {
    contract {
        <!CONDITIONAL_EFFECT_ERROR!>returns() implies (x is Int)<!>
    }
}
```

In the conditional effect marked with the annotation `CONDITIONAL_EFFECT_ERROR`, we will output:

> `The returning function implies ‘x is Int’ condition, although the latter might not hold.`


### Code

For conditional effects, we always get a `PostconditionViolated` error from Viper. The error contains which assertion 
failed to hold during the analysis. The offending node is always an *implication* node. 
Thus, we can embed a new source role, called `SourceRole.ConditionalEffect`, into the implication embedding.

```kotlin
// org/jetbrains/kotlin/formver/embeddings/expression/Boolean.kt
data class Implies(
    override val left: ExpEmbedding,
    override val right: ExpEmbedding,
    override val sourceRole: SourceRole? = null
) : BinaryBooleanExpression

// org/jetbrains/kotlin/formver/embeddings/SourceRole.kt
sealed interface SourceRole {
    // ...
    data class ConditionalEffect(val effect: ReturnsEffect, val condition: Condition) : SourceRole
}
```

The `Implies` node is built by the `ContractDescriptionConversionVisitor::visitConditionalEffectDeclaration` function.

Thanks to the previous PRs on warning messages, some `ExpEmbedding`s already have a `SourceRole` on them. 
This means, that when we explore the lhs of a conditional effect, the created `ExpEmbedding` will have a source role
already. However, this is not always the case for the rhs, that may not have any source role. Thus, we need to 
add new source roles for the missing rhs (those roles are defined in a new `Condition` interface, extending
the existing `SourceRole` interface, check this [PR](https://github.com/jesyspa/kotlin/pull/189#discussion_r1399312174)):

*   *type conditions* (e.g., `x is T` / `x !is T`): we add new source role `SourceRole.Condition.IsType`, defined as 
    follows:

    ```kotlin
    // org/jetbrains/kotlin/formver/embeddings/SourceRole.kt

    data class IsType(
        val targetVariable: FirBasedSymbol<*>, 
        val expectedType: ConeKotlinType, 
        val negated: Boolean = false // used for '!is' case
    ) : Condition
    ```

*   *null/not-null conditions* (e.g., `x == null` / `x != null`): we add the new source role 
    `SourceRole.Condition.IsNull`, defined as follows:

    ```kotlin
    // org/jetbrains/kotlin/formver/embeddings/SourceRole.kt

    data class IsNull(
        val targetVariable: FirBasedSymbol<*>,
        val negated: Boolean = false // used for '!= null' case
    ) : Condition
    ```

*   *boolean conditions* (e.g., `true` / `false`): we add the new source role `SourceRole.ConstantCondition`, defined as
    follows:

    ```kotlin
    // org/jetbrains/kotlin/formver/embeddings/SourceRole.kt

    data class Constant(val literal: Boolean) : Condition
    ```

*   *compound conditions* (e.g., `A && B`, `A || B`, `!A`): we add the following new source roles:

    ```kotlin
    // org/jetbrains/kotlin/formver/embeddings/SourceRole.kt

    /* Models && condition. */
    data class Conjuction(val lhs: SourceRole, val rhs: SourceRole) : Condition  

    /* Models || condition. */
    data class Disjunction(val lhs: SourceRole, val rhs: SourceRole) : Condition 

    /* Models ! condition. */
    data class Negation(val arg: Condition) : Condition
    ```

*   *parameter references* (e.g., variables of `Boolean` type): to support them, we implement the new interface
    `Condition` in the existing `SourceRole.FirSymbolHolder`:

    ```kotlin
    data class FirSymbolHolder(val firSymbol: FirBasedSymbol<*>) : SourceRole, Condition
    ```

These definitions allow inspecting conditions at a deeper level during the error reporting phase.

Since the function `visitConditionalEffectDeclaration` explores both left and right-hand sides of the implication, 
they will contain their respective source roles defined above. Specifically, the lhs will be an instance of
`SourceRole.ReturnsEffect` and the rhs an `SourceRole.Condition` instead. We use the lhs (`effect`) and rhs (`cond`) 
roles to build a new `SourceRole.ConditionalEffect`.

```kotlin
override fun visitConditionalEffectDeclaration(
    conditionalEffect: KtConditionalEffectDeclaration<ConeKotlinType, ConeDiagnostic>,
    data: ContractVisitorContext,
): ExpEmbedding {
    val effect = conditionalEffect.effect.accept(this, data)
    val cond = conditionalEffect.condition.accept(this, data)
    val role = SourceRole.ConditionalEffect(
        effect.sourceRole as ReturnsEffect, 
        cond.sourceRole as Condition
    )
    return Implies(effect, cond, role)
}
```

### Generating the warning

During the error reporting phase, we can build the warning message using both fetched source roles.

```kotlin
private fun DiagnosticReporter.reportVerificationErrorUserFriendly(
        source: KtSourceElement?,
        error: VerificationError,
        context: CheckerContext,
    ) {
        when (val role = error.getInfoOrNull<SourceRole>()) {
            // ... - other cases
            is SourceRole.ConditionalEffect -> {
                val (effectRole, condRole) = role
                TODO("How do we interpret the roles from lhs and rhs?")
            }
        }
    }
```

To generate a warning message, we can use the `effectRole: SourceRole.ReturnsEffect` and the 
`condRole: SourceRole.Condition` we fetched from the conditional effect. 

The warning message is made of two parts, the first (`{0}`) describing the `returns` clause and the second (`{1}`)
describing the condition. So, we propose two new extension functions that “stringify” their representation. We call
these two functions (defined in `VerifierErrorInterpreter`) `describe`.

```kotlin
private fun ReturnsEffect.describe(): String = when (this) {
        is ReturnsEffect.Bool -> "Returning a $bool value"
        is ReturnsEffect.Null -> {
            val msg = when (negated) {
                true -> "non-null"
                false -> "true"
            }
            "Returning a $msg value"
        }
        ReturnsEffect.Wildcard -> "The returning function"
    }

private fun Condition.describe(): String = when (this) {
    is Condition.Conjunctive -> "(${lhs.describe()} && ${rhs.describe()})"
    is Condition.Disjunctive -> "(${lhs.describe()} || ${rhs.describe()})"
    is Condition.Negation -> "!${arg.describe()}"
    is Condition.Constant -> literal.toString()
    is Condition.IsNull -> buildString {
        append(targetVariable.rendered)
        when (negated) {
            true -> append(" != ")
            false -> append(" == ")
        }
        append("null")
    }
    is Condition.IsType -> buildString {
        append(targetVariable.rendered)
        when (negated) {
            true -> append(" !is ")
            false -> append(" is ")
        }
        append(expectedType.rendered)
    }
    is SourceRole.FirSymbolHolder -> firSymbol.rendered
}

// Utility functions
private val ConeKotlinType.rendered: String
    get() = FirDiagnosticRenderers.RENDER_TYPE.render(this)

private val FirBasedSymbol<*>.rendered: String
    get() = FirDiagnosticRenderers.DECLARATION_NAME.render(this)
```

Having defined the `describe` functions, the final code will look like as it follows:

```kotlin
private fun DiagnosticReporter.reportVerificationErrorUserFriendly(
    source: KtSourceElement?,
    error: VerificationError,
    context: CheckerContext,
) {
    when (val role = error.getInfoOrNull<SourceRole>()) {
        // ...
        is SourceRole.ConditionalEffect -> {
            val (returnEffect, condition) = role
            reportOn(
                source, PluginErrors.CONDITIONAL_EFFECT_ERROR, returnEffect.describe(), condition.describe(), context
            )
        }
    }
}
```