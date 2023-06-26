# `callsInPlace` contract

The `callsInPlace` construct applies to a parameter `fo` of function type and guarantees two properties:
1. `fo` is not stored past the duration of the function call; we refer to this as that the variable _does not escape_.
2. (Optionally) `fo` is called a specific number of times: once, at least once, or at most once.

## Escape

General thoughts:
- It's not clear whether escape analysis is best done in Viper or directly on the data flow graph.
- In Viper, we can represent it as a predicate that we must keep throughout the method.
  A method call through which the variable can escape consumes this predicate without returning it,
  making the proof invalid.  This approach has some issues:
  + This approach is assymetric: when verifying a method `foo` that has this guarantee, we need to
    take this predicate as a precondition, but when using `foo` this predicate is only necessary
    if the passed parameter is one for which such an obligation exists.
  + It thus seems like some kind of data flow analysis may be necessary anyway; what the preconditions
    of `foo` should be depends on what is passed to it, which is much more dynamic than what we'd like.
  + Marco Eilers' thesis has some material on the matter of showing more complicated properties
    than simple correctness.  This may be relevant.
- There may be an alternative approach that we're simply missing.  It could be useful to ask the
  Viper folks directly.

## Number of calls

The calls to `fo` should be tracked via a counter to allow us to determine the number of times that
it is called.

Some thoughts:
- It may be worth putting this counter into a reference so we can pass it to the `invoke` method directly.
- Monotonicity is an important property, and it is not obvious how to deal with this in loop invariants.