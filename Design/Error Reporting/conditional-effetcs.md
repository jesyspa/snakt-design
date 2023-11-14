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


Sample messages:

| Left-Hand Side      | Right-Hand Side                 | Message                                                                             |
| ------------------- | ------------------------------- | ----------------------------------------------------------------------------------- |
| Bool/Null Predicate | Type Assertion                  | `The type assertion '{0}' might not hold due to potential '{1}' return value`.      |
| *                   | Nullability Checks              | `The null/non-null check '{0}' might not hold due to potential '{1}' return value.` |
| *                   | All the rest/Compound Statement | `The boolean expression '{0}' might not hold due to a potential '{1}' return value.`  |

Where `{0}` is the `booleanExpression` in the rhs of implication and `{1}` can be: `true`, `false`, `null`, `non-null`.

## Implementation

> NOTE: this part is still work in progress.

We start implementing the generic message. We need to output the boolean expression `e` that may fail. Thus, we have to 
provide to the error interpreter (`VerificatiofailrInterpreter`) its FIR representation.

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
    data class ConditionalEffect(val booleanExpression: ???)
}
```

*OPEN QUESTION*:
Here we have the first problem to solve, what is the type of `booleanExpression`? It should be a `FirBasedSymbol<*>`,
but the contract description visitor does not allow accessing the FIR’s symbol of a condition when visiting a 
conditional effect.

