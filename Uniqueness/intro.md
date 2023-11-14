# Uniqueness and borrowing annotations in Kotlin


## Motivation

In Kotlin, objects can and often are widely shared.  This
is an important part of the design of the language, and
allows for space savings via reuse.  However, the fact that
an object may be modified via another reference to it means
that it can be hard to impose guarantees locally.  For
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
required that `y` is a unique reference when the function is
called, and hence `runIfXNonNull` will "consume" the `y`
reference and make it inaccessible.  On the call-site,
the situation looks as follows:

```kotlin
unique val y = Y(myX)
runIfXNonNull(y) { ... }
// y cannot be used anymore
```

*Note:* The astute reader will notice that there is another
design choice possible here: instead of making `y`
inaccessible, we can make `y` non-`unique`.  We expand on
the considerations later.

To permit passing `unique` values to functions without
losing access to them,  we introduce the keyword `inPlace`
that indicates that a certain reference does not leak from
the scope it is declared in; that is, that every copy made
of this reference lives no longer than the reference itself.

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

In this document we focus on teh practical uses and
implementation challenges of this proposal.  We describe the
syntax and semantics of our proposed feature in full and
then propose an MVP that contains the majority of the logic
and can be expressed using the contracts DSL.


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

* On return types and getters:
```kotlin
class X {
    fun clone(): unique X { ... }
    val prop: X
        get() unique = ...
}
```

The `inPlace` keyword may be used on read-only variable and
parameter declarations, where it may be combined with the
`unique`
keyword:
```kotlin
fun example(inPlace unique x: X) {
    inPlace val y = x
}
```

There needs to be syntax for specifying that the `this`
parameter is in place; we do not yet have a suggestion for
this.

The function `forgetUniqueness` has the following siganture:

```kotlin
fun<R> forgetUniqueness(r: R): R
```


## Semantics

In this section we describe in detail the intended results
of using the `unique` and `inPlace` keywords.  We focus on
the guarantees a programmer can expect about the resulting
code, without explicitly specifying what operations are
permitted or how these guarantees are ensured.

Throughout this section we will conflate variables and
parameters, using "variable" to refer to both.

### Accessibility

In standard Kotlin, any variable that is in scope can be
used.  In the presence of borrowing, this breaks down.
When a `unique` variable is borrowed we cannot provide the
guarantees that it should have, and hence we must ensure
that it is not accessed.  For example:

```kotlin
class X(val x: Int)
class Y(var xref: X?)

fun example(inPlace unique y: Y, f: () -> Unit): X =
    if (y.xref != null) {
        f()
        y.xref
    }
    else X(0)

// elsewhere:
unique val y = getUniqueY()
example(y) { y.xref = null }
```

If we permitted this code to compile, the smart cast in
`example` would be permitted (since `y` is `unique`) but in
fact the call to `f` will have changed the value to null.

We call a variable *accessible* if its value can be used in
a certain context and *inaccessible* otherwise.


### `unique`

A variable marked `unique` has the following property:
whenever the variable is accessible and non-null, it is the
only reference to the object that it refers to.

In particular, the only way to modify the fields of an
object referred to by a `unique` variable `x` is using an
explicit access to `x`.  This means that we can assume that
any modification can be detected from the program text,
allowing us to make stronger assumptions.

These modifications can come in two forms.  Aside from
direct writes to the variable, the value of the variable may
be borrowed by an `inPlace` variable.  When the borrow is
returned, the value may have changed.

A function with a return type marked `unique` returns a
reference that is either `null` or that is the only
reference to the return value.

### `inPlace`

A variable marked `inPlace` can be initialised from a
`unique` variable and "borrows" the value: that is, the
original `unique` variable becomes inaccessible for the
duration of the borrow, which lasts for as long as the
`inPlace` variable exists.

A variable that is `inPlace` guarantees that any copies made
of its value exist only for as long as the variable itself
does: that is, any copies must themselves be `inPlace`.
This ensures that once the borrow ends, if the value was
originally copied from a `unique` variable, that variable
again satisfies the rule for a `unique` variable.

Note that this is exactly the rule that already exists for
`callsInPlace` functions.  We simply extend this to
variables of any types, and introduce an interaction between
`inPlace` variables and `unique` variables.


### `forgetUniqueness`

A variable that is `unique` can lose its uniqueness via
sharing.  `forgetUniqueness` does this explicitly: it
returns a copy of the passed value and the original variable
loses the `unique` predicate.

*Note:* Another option is to make the original variable
inaccessible, we should see what is preferable.


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

