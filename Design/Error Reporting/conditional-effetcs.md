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

We start implementing the generic message.

In our test suite, we always get a `PostconditionViolated` error from Viper. The error contains which assertion failed 
to hold during the analysis. The offending node is always an *implication* node. Thus, we can embed a new source-role
into that implication.

```kotlin
data class Implies(
    override val left: ExpEmbedding,
    override val right: ExpEmbedding,
    override val sourceRole: SourceRole? = null
) : BinaryBooleanExpression
```

The new source-role assigned during the visit of a conditional effect will be called `SourceRole.ConditionalEffect`.

```kotlin
enum class SourceRole {
    // ...
    data class ConditionalEffect : SourceRole {
        fun ErrorReason.getLhsRole(): SourceRole = ...
        fun ErrorReason.getRhsRole(): SourceRole = ...
    }
}
```

The `Implies` node is built by the `ContractDescriptionConversionVisitor::visitConditionalEffectDeclaration` function.
Since the function explores both the left and right-hand sides of the implication, they will contain existing source 
roles. We can build the warning message using both fetched source roles during the error reporting. We do not need
any additional data to be stored in `ConditionalEffect`, since the implication sides contains source roles as embedded
information (thanks to the previous PRs).

```kotlin
private fun DiagnosticReporter.reportVerificationErrorUserFriendly(
        source: KtSourceElement?,
        error: VerificationError,
        context: CheckerContext,
    ) {
        when (val role = error.getInfoOrNull<SourceRole>()) {
            // ... - other cases
            is SourceRole.ConditionalEffect -> with(role) {
                val lhsRole = error.reason.getLhsRole()
                val rhsRole = error.reason.getRhsRole()
                TODO("How do we interpret these roles?")
            }
        }
    }
```

TODO: this part is still **working in progress**:

* The next thing is defining how to interpret the source roles from both sides to produce the warning message.
* How to format the output message.