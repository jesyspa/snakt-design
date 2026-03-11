# `callsInPlace` contract

The `callsInPlace` construct applies to a parameter `fo` of function type and
guarantees two properties:
1. `fo` is not stored past the duration of the function call; we refer to this
   as that the variable _does not escape_.
2. (Optionally) `fo` is called a specific number of times: once, at least once,
   or at most once.

## Scope

Verifying the _correctness_ of `callsInPlace` declarations is a non-goal for
this project. That is, we do not check that a function's implementation actually
calls `fo` the declared number of times. Instead, the goal is to _use_
`callsInPlace` information to improve verification of calling code — for
example, knowing that a lambda is called exactly once lets us reason about
definite assignment and variable initialization in the caller.

## Implementation status

**`callsInPlace` is currently not encoded.** The contract visitor recognises
the FIR node (`KtCallsEffectDeclaration`) but returns `true`, which is then
filtered out by `getPostconditions`. No Viper constraints are generated.

Inline functions sidestep the issue: their lambda bodies are inlined directly
into the caller, so the callsInPlace guarantee is trivially satisfied by
construction. The contract only matters for non-inline higher-order functions,
where function objects are currently represented as havoc'd references (see
[function objects](#function-object-encoding) below).

## Intended encoding

We can model objects of function type as references with an associated
`num_calls` field that is incremented every time the function object is invoked.
See [functions-as-parameters](functions-as-parameters.md) for the full encoding.

Note: the encoding below is designed to _assume_ the declared invocation
guarantees in calling code, not to verify the callee's implementation.

### Escape tracking

Instead of marking objects that may not escape, we can mark objects that _may_
escape, treating that as a precondition for calling functions from which escape
is possible. This precondition does not involve ownership, and so can be
modelled with an opaque Boolean-valued function.

We need to choose what types do and do not require escape permissions:
1. Annotate only function objects. This may mean that casting function objects
   to `Any` would require a may-escape precondition.
2. Annotate all objects. This involves getting duplicability information for
   fields; it is unclear how to do this.

Option 1 is likely a better trade-off as real-life examples don't generally
involve casting function objects.

### Invocation counting

The calls to `fo` should be tracked via a counter to allow us to determine
the number of times it is called. We track this using a counter on the
function object:

```viper
field FunctionObject_num_calls: Int
predicate FunctionObject(this: Ref) {
  acc(this.FunctionObject_num_calls)
}

method invokeFunctionObject(this: Ref)
  requires FunctionObject(this)
  ensures FunctionObject(this)
  ensures FunctionObject_get_num_calls(this) == old(FunctionObject_get_num_calls(this)) + 1
```

The invocation kind maps to postconditions on the counter:
- `EXACTLY_ONCE`: `num_calls == old(num_calls) + 1`
- `AT_LEAST_ONCE`: `num_calls >= old(num_calls) + 1`
- `AT_MOST_ONCE`: `num_calls <= old(num_calls) + 1`

A non-obvious difficulty is that the counter is monotonically increasing,
which we need to specify at all points (e.g. loop invariants).

### Partial correctness caveat

Due to the partial correctness property of Viper, a false negative occurs in:

```kotlin
fun foo(fo: () -> Unit) {
    contract { callsInPlace(fo, EXACTLY_ONCE) }
    while (true) {}
}
```

We could partially mitigate this by ending the function with `refute false`,
which would ensure that Viper cannot verify that `foo` does not terminate.
However, short of requiring a termination proof we cannot avoid this entirely.

## Function object encoding

Currently, non-inline function object calls produce a **havoc**: the result
is a fresh anonymous variable with only its type constrained. Arguments
passed to the function object are evaluated but their values are discarded.

For example, `g(true, 0)` where `g: (Boolean, Int) -> Int` produces:

```viper
var anon$0: Ref
inhale df$rt$isSubtype(df$rt$typeOf(p$g), df$rt$functionType())
inhale df$rt$isSubtype(df$rt$typeOf(anon$0), df$rt$intType())
ret$0 := anon$0
```

This means:
- The verifier cannot reason about the relationship between arguments and
  return value.
- Postconditions that depend on function object behaviour cannot be proven.
- Any property that the function object is supposed to establish must be
  assumed rather than verified.

Creating actual function objects (with predicate, counter, and parameter
passing) is blocked on the TODO in `LambdaExp.toViperStoringIn`.

## What works today

Inline functions with lambdas work correctly because the lambda body is
substituted directly into the caller. The `callsInPlace(EXACTLY_ONCE)`
contract on stdlib functions like `run`, `let`, `with`, `also`, `apply`
is irrelevant — these are all inline, so the body is always inlined exactly
once. Verification of these patterns is tested in
`verification/inlining/` and `verification/stdlib_replacement_tests.kt`.
