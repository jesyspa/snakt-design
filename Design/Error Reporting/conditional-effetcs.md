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
fun <!VIPER_TEXT!>mayReturnNonNull<!>(x: Any?): Any? {
    contract {
        <!VIPER_VERIFICATION_ERROR!>returns(null) implies (x is Int)<!>
    }
    return x
}
```
Expected message: This contract cannot be verified because `x` can be a non-null value, therefore the condition
`x is Int` might not hold.

---
Type: Return not null with type assertion

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun <!VIPER_TEXT!>mayReturnNull<!>(x: Any?): Any? {
    contract {
        <!VIPER_VERIFICATION_ERROR!>returnsNotNull() implies (x is Int)<!>
    }
    return x
}
```
Expected message: This contract cannot be verified because `x` can be a null value, therefore the condition `x is Int`
might not hold.

---
Type: Returning boolean with nullability condition

Code:
```kotlin
@OptIn(ExperimentalContracts::class)
fun <!VIPER_TEXT!>isNullOrEmptyWrong<!>(seq: CharSequence?): Boolean {
    contract {
        <!VIPER_VERIFICATION_ERROR!>returns(false) implies (seq != null)<!>
    }
    return seq != null && seq.length > 0
}
```
The premise of this contract is not satisfied with its actual implementation, we have a contradiction.
The contract claims that a `false` return value guarantees `seq` is not `null`, but the function’s logic does not support this guarantee. The solution of this contract would be to switch to an `||` statement

---
Type: Empty Returns with type assertion

Code: 
```kotlin
@OptIn(ExperimentalContracts::class)
fun <!VIPER_TEXT!>unverifiableTypeCheck<!>(x: Int?): Boolean {
    contract {
        <!VIPER_VERIFICATION_ERROR!>returns() implies (x is Unit)<!>
    }
    return x is String
}
```
This contract cannot be verified because the type assertion of the conditional effect might not hold. The function’s return statement is asserting that `x` is a `String` not a `Unit`.

## Implementation

We start implementing the generic message. We need to output the boolean expression `e` that may fail. Thus, we have to 
provide to the error interpreter (`VerificatioErrorInterpreter`) its FIR representation.

In our test suite, we always get a `PostconditionViolated` error from Viper. The error contains which assertion went
wrong during the analysis. The offending node is always an implication node. Thus, we can embed a new source-role
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
roles. We can build the warning message using both fetched source roles.

TODO: this part is still **working in progress**:

* The next thing is defining how to interpret the source roles from both sides to produce the warning message.
* How to format the output message.