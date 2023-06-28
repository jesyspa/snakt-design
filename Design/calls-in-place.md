# `callsInPlace` contract

The `callsInPlace` construct applies to a parameter `fo` of function type and guarantees two properties:
1. `fo` is not stored past the duration of the function call; we refer to this as that the variable _does not escape_.
2. (Optionally) `fo` is called a specific number of times: once, at least once, or at most once.

We can model objects of function type as references with an associated `num_calls` field that is
incremented every time the function object is invoked.

We use the encoding described in `function-as-parameters.md` for objects of function type.

## Escape

Instead of marking objects that may not escape, we can mark objects that may escape, treating that as a
precondition for calling functions from which escape is possible.  This precondition does not involve
ownership, and so can be modelled with an opaque Boolean-valued function.

We need to choose what types do and do not require escape permissions.  There are two possibilities:
1. Annotate only function objects.  This may mean that casting function objects to `Any` (if Kotlin
   even allows that?) would require a may-escape precondition.
2. Annotate all objects.  This involves getting duplicability information for fields; it is unclear
   how to do this.

It seems like option 1 is likely to be a better trade-off as real-life examples don't generally involve
casting the function objects.

## Number of calls

The calls to `fo` should be tracked via a counter to allow us to determine the number of times that
it is called.  We track this using a counter on the function object.

A non-obvious difficulty here is that the counter is monotonically increasing, which we need to make
sure to specify at all points (e.g. loop invariants).

Note that due to the partial correctness property of Viper, a possible false negative occurs in the
following:

```kotlin
fun foo(fo: () -> Unit) {
  contract {
    callsInPlace(fo, EXACTLY_ONCE)
  }
  while (true) {}
}
```

We could partially mitigate this by ending the function with `refute false`, which would ensure that
Viper cannot verify that `foo` does not terminate.  However, short of requiring a termination proof
we cannot avoid this entirely.