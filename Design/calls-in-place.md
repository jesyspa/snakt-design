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

Since we trust the `callsInPlace` declaration, the encoding does not need to
track or verify invocation counts. Instead, we assume the declared guarantees
at the call site.

For `EXACTLY_ONCE`, the caller can assume:
- The lambda body executes exactly once.
- Variables assigned in the lambda are definitely assigned after the call.
- Side effects of the lambda occur exactly once.

For `AT_LEAST_ONCE` and `AT_MOST_ONCE`, weaker assumptions apply accordingly.

The main challenge is encoding this for non-inline functions, where the lambda
body is not substituted into the caller. We need a function object encoding
that lets the caller assume the effects of the lambda body have been applied
the declared number of times. See
[functions-as-parameters](functions-as-parameters.md) for the function object
encoding.

### Escape tracking

The non-escape guarantee (property 1) means the function object is not stored
past the call. This is relevant for ownership and permission reasoning: the
caller retains full ownership of any captured state.

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

Creating actual function objects (with predicate and parameter passing) is
blocked on the TODO in `LambdaExp.toViperStoringIn`.

## What works today

Inline functions with lambdas work correctly because the lambda body is
substituted directly into the caller. The `callsInPlace(EXACTLY_ONCE)`
contract on stdlib functions like `run`, `let`, `with`, `also`, `apply`
is irrelevant — these are all inline, so the body is always inlined exactly
once. Verification of these patterns is tested in
`verification/inlining/` and `verification/stdlib_replacement_tests.kt`.
