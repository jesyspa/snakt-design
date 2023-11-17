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
This contract may not be satisfied because the implication `returns(null) implies (x is Int)` is false when we
are returning a `null` but `x` is not of type `Int`. In this case, `x: Any?`, so let’s assume that we have 
`mayReturnNonNull(null)`, therefore, `x = null`, the premises hold, but the conclusion is wrong (`x is Int`),
that’s because `x = null \not\in Int`.


---
Type: Return not null with type assertion (1)

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun notNullWithTypeAssertion1(x: Any?): Any? {
    contract {
        returnsNotNull() implies (x is Int)
    }
    return x
}
```
This contract may not be satisfied because the implication `returnsNotNull() implies (x is Int)` is false when we are
returning a non-value and `x` is not of type `Int`. As an example: `notNullWithTypeAssertio1("Hello!")`, we are 
returning a non-null value, but `x` is a `String`.

---
Type: Returns not null with type assertion (2)

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun notNullWithTypeAssertion2(x: Any?, y: Int): Any? {
    contract {
        returnsNotNull() implies (x is Int)
    }
    return y
}
```
This contract may not be satisfied because we are always returning a non-null value (`y: Int`), but since `x: Any?` 
it may not be of type `Int` (`x` in input could be a `Bool?`, `Char`, …): `notNullWithTypeAssertion(null, 42)`.

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
The premise of this contract is not satisfied with its actual implementation, we have a contradiction.
The contract claims that a `false` return value guarantees `seq` is not `null`, but the function’s logic does not 
support this guarantee. If `seq = null` then the returning condition is `false`, satisfying the implication premises,
but this contradicts the conclusion (`seq != null`).

---
Type: Returns true with type assertion

Code: 
```kotlin
@OptIn(ExperimentalContracts::class)
fun returnsTrueWithTypeAssertion<!>(x: Any?): Boolean {
    contract {
        returns(true) implies (x is Int)
    }
    return (x == null)
}
```
This contract may not be satisfied due to a contradiction. We return `true` when `x` is equal to null, therefore,
the implication’s premises hold. But, since `null \not\in Int` then the conclusion does not hold, leading to a
contradiction.

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
This contract may not be satisfied because the implication may be false. We are always returning from the function,
but `x: Any` may not be of type `Int`.


## Implementation

We start implementing the generic message. We need to output the boolean expression `e` that may fail. Thus, we have to 
provide to the error interpreter (`VerificatioErrorInterpreter`) its FIR representation.

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