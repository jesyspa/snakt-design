# Name Mangling

When converting FIR to Viper, we need to ensure that names
do not conflict.  However, we would prefer short names over
long names.  By registering all names used in the program
and attempting to find cases when they can be shortened
without collisions, we can make the generated code much more
readable.

Goals:
* Names are globally unique.
* Names are generally short enough to read at a glance.

Non-goals:
* Optimising often-used names to be shorter.

## Name structure

We regard our names as consisting of two parts:
1. A *namespace* that specifies the context a name is in.
2. A *local name*  that is unique within the namespace.

Note that namespace names may themselves contain names: for
example, a function may be namespaced within a class, which
itself has a namespace.

Local names may also contain names: for example, the name of
a function may contain the types of its parameters.
However, to make the program tractable we assume that local
names are guaranteed to be unique in their full form.  Local
names may also have shorter forms, that should be used if
they do not collide.

### Example

Let us consider the following Kotlin program:

```kotlin
class A(val x: Int) {
    fun foo(): Int = ...
}

class B {
    var x: Int
        get() { ... }
        set(v) { ... }
}

fun A() { ... }

fun foo(x: Int, B: Int) { ... }

fun foo() {
    val x: Int = ...
}
```

When converting the `foo()` function, we can see the
following namespaces:
* The package.
* The classes `A` and `B`.
* The function `foo()`.
* The parameters of other functions.

This is not an exhaustive list of the namespaces in the
resulting program: new symbols are generated in the
translation to Viper, and these symbols often get their own
namespaces.  This includes namespaces for return values and
labels.

We can identify the possible local names in this example:
* `class A` -> `class_A`, `A` (same for `B`)
* `fun A()` -> `fun_A_takes_Unit_returns_Unit`,
  `fun_A_takes_Unit`, `fun_A`, `A` (same for the `foo`
  overloads, including in `A`)
* `val x` in `A` -> `field_x`, `x`
* Getter of `var x` in `B` -> `prop_x_getter`, `prop_x`, `x`
* Setter of `var x` in `B` -> `prop_x_setter`, `prop_x`, `x`
* Parameter `x` in `fun foo(...)`: `x`

## Approach

We can regard the name mangling problem as a series of
algorithms of the following form:

1. We have a set of objects `X`.
2. Each `x: X` has a list of preferred names `x.names`,
   where each preferred name is marked primary or secondary.
  * We are guaranteed that all primary names are unique.
  * Secondary names may clash.
3. We create a map from names to objects, indicating which
   objects laid a claim to what name.
4. We resolve the claims.  For each `x: X`:
  * If `x` has a secondary name claimed by no other
    object, it gets that name.
  * Otherwise, `x` gets its primary name.
  * Note that if two objects claimed the same name as
    primary, the uniqueness invariant was violated, so the
    algorithm fails.

We run this algorithm repeatedly:
1. For every namespace, we resolve local names.
2. We resolve qualified names that appear in namespaces.
3. We resolve the remaining qualified names.

### Annotated example

Let us return to the example above, with the preferred names
annotated:
```kotlin
// A: A, class_A
// x: x, field_x
class A(val x: Int) {
    // foo: foo, fun_foo, fun_foo_takes_Unit, fun_foo_takes_Unit_returns_Int
    fun foo(): Int = ...
}

// B: class_B, B
class B {
    // get x: x, prop_x, prop_x_getter
    // set x: x, prop_x, prop_x_setter
    var x: Int
        get() { ... }
        set(v) { ... }
}

// A: A, fun_A, fun_A_takes_Unit, fun_A_takes_Unit_returns_Unit
fun A() { ... }

// foo: foo, fun_foo, fun_foo_takes_ABC, fun_foo_takes_ABC_returns_XYZ
// x: x
// B: B
fun foo(x: Int, B: Int) { ... }

// foo: foo, fun_foo, fun_foo_takes_Unit, fun_foo_takes_Unit_returns_Unit
fun foo() {
    // x: x
    val x: Int = ...
}
```

We start by resolving global names, which are necessary for
namespace names.  The global entities are `class A`, `class
B`, `fun A`, `fun foo(...)`, and `fun foo()`; for each, we
pick the shortest name that isn't claimed by anything else.
We end up with the following selection:
* `class A` -> `class_A`
* `class B` -> `B`
* `fun A` -> `fun_A`
* `fun foo(...)` -> `fun_foo_takes_x_B`
* `fun foo()` -> `fun_foo_takes_Unit`

This lets us resolve all namespace names that depend on
names in the program, namely for `class A` and `class B`.
(Note that while `fun foo()` is a namespace, the name
of that namespace is `local`.)

We then resolve the local names per namespace.  The
interesting case here is in `class B`, where the getter and
setter of `x` collide.

Every namespace-name pair is now unique, so we get the
following code, with unique names.  (Note that we compile
properties to fields or methods; we do so here for B.x to
demonstrate.)
```kotlin
class class_A(val class_A_x: Int) {
    fun class_A_foo(): Int = ...
}

class B {
    fun B_prop_x_getter(): Int { ... }
    fun B_prop_x_setter(param_v: Int) { ... }
}

fun fun_A() { ... }

fun fun_foo_takes_x_B(param_x: Int, param_B: Int) { ... }

fun fun_foo_takes_Unit() {
    val param_x: Int = ...
}
```

We could run the algorithm again on namespace-name pairs,
and this may be worth doing to remove bulky namespace names
when they aren't necessary.  However, more thought is needed
to see when that will make life easier.
