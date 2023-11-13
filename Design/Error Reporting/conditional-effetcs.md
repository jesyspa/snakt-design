Some terminology, as reported by the Kotlin’s Contract KEEP document:

> If the effect is observed, then the condition is guaranteed to be true.

```kotlin
contract {
    returns() implies (booleanExpression)
}
```

---

## Conditional Effects Warning

Right now, our test-suite has contracts using conditional effects, of the following kind:

* `returns() implies false`

* `returns() implies (x is Unit)`

* `returns() implies (a !is IntHolder)`

However, the right-hand side of the implication can be a compound boolean expression. Therefore, the warning message
may not easy to build.

To begin with an easy solution, we have two ideas:

1. Use a generic warning message like: `The boolean expression 'e' might not hold` (where `e` is the implication’s
    right-hand side).

2. Customize the message according to the boolean expression:
    
    a. *Type Assertion* (`is`, `!is`).
    
    b. *Boolean Singleton/Literal* (boolean variable, or constants `true/false`). This should be relevant when
        we get a false implication (`true -> false`).

    c. *Nullability checks* (`== null`, `!= null`).

    d. *Compound Statements*: a generic message similar to the previous one.


Sample messages:

| Right-Hand Side           | Message                                                                   |
| ------------------------- | ------------------------------------------------------------------------- |
| Type Assertion            | `The inferenced type of 'x' may/may not be of type 'T'.`                  |
| Boolean Singleton/Literal | `The conditional effect might not hold due a possible false implication.` |
| Nullability Checks        | `The variable 'x' might be null/notnull.`                                 |
| Compound Statement        | `The boolean expression 'e' might not hold.`                              |