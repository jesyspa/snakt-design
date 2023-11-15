# Uniqueness and borrowing annotations in Kotlin


## Introduction

In Kotlin, objects can and often are widely shared.  This
is an important part of the design of the language, and
allows for space savings via reuse.  However, the fact that
an object may be modified via another reference to it means
that it can be hard to reason about its value.  For
example, users are often surprised that code like the
following does not permit a smart cast:

```kotlin
class X(val x: Int)
class Y(var xref: X?)

fun runIfXNonNull(y: Y, f: (X) -> Unit) {
  if (y.xref != null)
      f(y.xref) // error, need to use f(y.xref!!)
}
```

Here, the compiler cannot assume that `y.xref` will not
change between the `if` and the call to `f`.  The
programmer, who may know that this cannot happen, is unhappy
to have to write the cast explicitly.

We propose adding two keywords, `unique` and `inPlace`, to
Kotlin that would allow more user-friendly behaviour in
these cases.

By marking a reference `unique`, a user can indicate that
the reference is the only way to access the object it refers
to.  The above code, with `y` marked `unique`, thus
compiles:

```kotlin
fun runIfXNonNull(unique y: Y, f: (X) -> Unit) {
  if (y.xref != null)
      f(y.xref) // no problem
}
```

There is, however, a problem with this function: we have
required that `y` be a unique reference when the function is
called, and hence `runIfXNonNull` will "consume" the `y`
reference and make it inaccessible.  On the call-site,
the situation looks as follows:

```kotlin
unique val y = Y(myX)
runIfXNonNull(y) { ... }
// y cannot be used anymore
```

*Note:* A possible alternative design choice is to make `y`
non-unique after the call.  We discuss this choice in the
Design Choices section.

To permit passing `unique` values to functions without
losing access to them,  we introduce the keyword `inPlace`
that indicates that the value of a certain variable does not
leak from the scope it is declared in; that is, that every
copy made of this variable lives no longer than the
reference itself.

This makes the following code valid:

```kotlin
fun borrow(inPlace y: Y) = ...

unique val y = Y(myX)
borrow(y)
// y is still unique, we can do:
runIfXNonNull(y) { ... }
```

Coming back to our previous example, the `y` parameter of
`runIfXNonNull` should be marked with both `unique` and
`inPlace`: `unique` to permit the smartcast and `inPlace` to
ensure that the reference is only borrowed and `y` can
continue to be used in the caller:

```kotlin
fun runIfXNonNull(inPlace unique y: Y, f: (X) -> Unit) {
  if (y.xref != null)
      f(y.xref) // no problem
}
```

In this document we introduce this proposal at a high level.
We describe the syntax and semantics of our proposed feature
in full and then propose an MVP that contains the majority
of the logic and can be expressed using the contracts DSL.


## Syntax

In this proposal, we introduce the keywords `unique` and
`inPlace` and a function `forgetUniqueness`.

The `unique` keyword may be used in the following contexts:

* On variable and parameter declarations:
```kotlin
fun example(unique x: X) {
    unique var y = x.clone()
    y = x.clone()
}
```

* On function return types and getters:
```kotlin
class X {
    fun clone(): unique X { ... }
    val prop: X
        get() unique = ...
}
```

The `inPlace` keyword may be used on the declarations of
read-only variables and parameters:
```kotlin
fun example(inPlace unique x: X) {
    inPlace val y = x
}
```

There needs to be syntax for specifying that the `this`
parameter is `inPlace`; we do not yet have a suggestion for
this.

The function `forgetUniqueness` has the following signature:

```kotlin
fun <R> forgetUniqueness(r: R): R
```


## Semantics

In this section we describe in detail the intended results
of using the `unique` and `inPlace` keywords.  We focus on
the guarantees a programmer can expect about the resulting
code, and give an overview of what operations are and are
not permitted.

Throughout this section we will conflate variables and
parameters, using "variable" to refer to both.

### High-level semantics

Our proposal is built on three fundamental ideas:
- There are restrictions on what can be done with `unique`
  variables which allow for stronger static analysis of
  them.
- Some of these restrictions can be temporary lifted by
  *borrowing* the `unique` variable using an `inPlace` variable.
- While a `unique` variable is borrowed from, it is not
  *accessible*: it cannot be read from or written to.

The following example demonstrates the interplay between
these three ideas:

```kotlin
class X(val x: Int)
class Y(var xref: X?)

fun example(inPlace unique y2: Y, f: () -> Unit): X =
    if (y2.xref != null) {
        f()
        y2.xref
    }
    else X(0)

// elsewhere:
unique val y1 = getUniqueY()
val x = example(y1) { y1.xref = null }
```

If we analyse `example` in isolation, the smartcast of
`y.xref` from `X?` to `X` is valid under our rules since
`y2` is `unique`.

If we also consider the call-site, we see that because
`y1.xref` is set to `null` by the lambda, the program as a
whole is incorrect: `example` may return `null` even though
its type is `X`.

Our third idea resolves this: `y1` is borrowed by `y2`,
and thus it is inaccessible in the lambda and we reject this
code.

TODO: inaccessibility arises also when we move/consume a
unique value.  This needs to be worked into the text
somehow.

### Guarantees

A variable `x` marked `unique` has the following property:
whenever `x` is accessible and non-null, it is the only
reference to the object that `x` refers to.

A function with a return type marked `unique` returns a
reference that is either `null` or that is the only
reference to the return value.

The value of a variable `x` marked `inPlace` does not leak
past the lifetime of `x`.  That is, if we follow the value
originating from `x` in the data flow graph, no path it
takes may outlive `x`.

### Restrictions

TODO: permitted operations

## MVP proposal

To test the feasibility of this approach we propose a
contract-based implementation adding the following
contracts:

```kotlin
interface InPlace : Effect
interface Unique : Effect
fun <R> ContractBuilder.inPlace(r: R): InPlace
fun <R> ContractBuilder.unique(r: R): Unique
fun <R> ContractBuilder.returnsUnique(): Unique
```

This set of contracts allows expressing the primary features
described here, but restricted only to parameters and return
values rather than to arbitrary variables.  We believe that
this will cover many use-cases and will be a good test for
whether this feature is useful and feasible as a whole.

The existing `callsInPlace` contract will not be changed,
but will imply the `inPlace` effect.


## Details

TODO:
* Two questions:
    1. What are the rules?
    2. How do we put them in kotlinc?
* We have a paper in progress about 1.
* kotlinc already has a lot of support for callsInPlace,
  this looks like it should be comparable in difficulty.

Some more design points:
* Why make variables inaccessible after they have been
  passed as unique?

## Open design questions

- How fine-grained are the accessibility restrictions that
  `inPlace` results in?  If you pass `y.x` as `inPlace`, can
  you still use other members of `y`?
- Is `forgetUniqueness` mandatory, or can unique variables
  implicitly lose uniqueness?
- How does uniqueness/inPlaceness interact with function
  overriding?
- Can `unique` and/or `inPlace` be extended to also apply to
  properties?  (see `classes.md`)
- Can `inPlace` support usage counting like `callsInPlace`
  does?
- What impact will the changes coming from Valhalla have on
  this?
- How can these changes be used for our Viper translation?
- How can `unique` interact with data structures?
- How can `inPlace` be used on `var` variables?

