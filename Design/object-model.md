# Translating Kotlin objects to Viper

Consider a Kotlin function such as `indexOf` below.  Translating such a function involves
choosing some representation for arrays of `T`, for elements of `T` itself, and for integers.

```kotlin
fun Array<T>.indexOf(element: T): Int {
    if (element == null) {
        for (index in indices) {
            if (this[index] == null) {
                return index
            }
        }
    } else {
        for (index in indices) {
            if (element == this[index]) {
                return index
            }
        }
    }
    return -1
}
```

There's a few things to note here:
- `T` may be a nullable type.
- `Array<T>` has an associated iterator type and corresponding functions.

There seem to be a number of levels of information that we can have about a reference:
1. The reference nominally belongs to a particular class, and hence has a certain place
   in a type hierarchy.  This is opaque: it doesn't say anything at the Viper level,
   but may be useful for e.g. validating smart casts.
2. The reference belongs to a particular class and hence methods that take a reference
   will have particular behaviour for it.  (Another option is for those methods to take
   the information as provided by points 1 or 3; this may be more compact, really, but it's
   not clear it can be used to express all properties (e.g. injectivity, relation between
   different methods)).
3. The reference belongs to a particular class and has associated fields that we can
   gain access to (read-only or read-write).

## Existing approaches

There are a number of prior compilers that map industry-level programming languages to Viper.
These use a variety of different approaches for representing objects.

### Gobra (Go → Viper)

Anton:
- My impression is that Gobra compiles primitives to primitives and references to references.
- Since access permissions have to be specified explicitly anyway, the type system is in some
  sense ignored by the verifier: you can't have type-incorrect programs because they will be
  rejected, but the types do not give much extra information about what you _can_ do.
- Gobra requires annotation of variables that can be captured.  It isn't clear whether we need
  something similar: I don't think Kotlin has pointers to locals, but the behaviour of
  lambdas may still be relevant.


TODO:
- Validate that this understanding is correct.
- (How) does it deal with constantness?
- (How) does it deal with inheritance?
- (How) does it deal with purity?
- Gobra provides first-class predicates.  How do they work?  What are they for?  Do we need them?

### Prusti (Rust → Viper), heap encoding

A more elaborate description can be found [here][0].

The heap-based encoding places all Rust values in the heap.  For Rust this makes sense,
since Rust allows the programmer to make a reference to any variable or member, while
Viper only allows references to the heap.

Primitive types are encoded as a heap value with a single field that represents the underlying
value (`val_int` for `i*` and `u*` types, `val_bool` for `bool`, `val_ref` for references, etc).
Composite types are represented as heap values with fields for their components.
Each type is additionally encoded using a predicate that specifies the permissions one
has to the fields, as well as the legal values these fields can take.
These predicates are built inductively from the predicates for the members.
Enumeration types are encoded using an explicit discriminator.

The primary problem with this encoding seems to be the limited possibilities of quantifying
over Rust values.  Any quantification has to happen over references and then be constrained
by predicates, which is inconvenient.  Viper functions also cannot contain postconditions
about the heap, and so it is not possible to return objects encoded this way from such a function.

**Question:** How does Prusti deal with immutability here?  A reference `p: &i32` can be
encoded as a fractionally-owned predicate, but what does Prusti do to inform the SMT solver
that calling `foo(p: &i32)` as `foo(&x)` does not change the value of `x`?

[0]: https://viperproject.github.io/prusti-dev/dev-guide/encoding/types-heap.html

### Prusti (Rust → Viper), snapshot encoding

A more elaborate description can be found [here][1].

The snapshot-based encoding uses domains to create an abstract representation of Rust values
(called "snapshots") that it then relates to heap values, allowing one to construct a snapshot
value from a heap value.
The snapshots are axiomatised to behave the same way as the Rust types do by imposing injectivity
and surjectivity constraints.

A significant advantage of this approach is that snapshot values can be compared using ==
equality in Viper.

Note that this encoding is specifically of _values_, not types.  There is no Viper representation
of the type system in Rust (in contrast to Python below).

[1]: https://viperproject.github.io/prusti-dev/dev-guide/encoding/types-snap.html

### Nagini (Python → Viper)

A more elaborate description can be found in [the PhD thesis of Marco Eilers][3], or in
[the paper that chapter is based on][2].

Nagini encodes the type hierarchy of Python in Viper via an axiomatisation.
Noteworthy here is that the type relations (e.g. `issubtype`) are encoded as functions,
rather than predicates, which means that they are not constrained by linearity.
These functions are opaque, with their behaviour defined using a set of axioms.

The encoding of fields is complicated and dependent on the runtime behaviour of the program.
Given Kotlin's statically typed nature, this part of the encoding does not seem to be
particularly useful to us.

[2]: https://link.springer.com/chapter/10.1007/978-3-319-96145-3_33
[3]: https://pm.inf.ethz.ch/publications/Eilers2022.pdf

### VerCors (Viper extension)

[The documentation][4] contains some further information, thuogh there doesn't seem to be
a single description of the translation.

The type system seems to be an extension of Viper's, with a number of tools for modelling
classes.  However, permissions still have to be specified explicitly.  In this sense there
is not that much new here compared to Viper itself.

[4]: https://github.com/utwente-fmt/vercors/wiki

## Feasible approaches for Kotlin

Let us outline the possibilities for translating the object-oriented part of Kotlin
into Viper.

### Assume accessibility, assume disjointness

The most straightforward translation maps primitive types to primitive types and class types
to references, with every value accompanied with a predicate that provides access permissions.

The above function signature is then translated as follows (ignoring polymorphism for the moment):

```
// Kotlin
fun Array<T>.indexOf(element: T): Int

// Viper
method Array_indexOf(this: Ref, element: Ref): Int
    requires Array_pred(this)
    ensures Array_pred(this)
```

This approach assumes that functions are never passed aliasing data; see the `aliasing_problem`
method in `Examples/Viper/Kotlin/aliasing.vpr` for an example of when Viper can validate a
postcondition that does not hold if this assumption is violated.
Since Kotlin does not impose any restrictions on aliasing, this approach is fundamentally unsound.
However, given we are making a tool to provide warnings to the user it may be that we can accept this.

The class predicates can be built inductively much the same way they are in the heap-based encoding
of Prusti.

A problem with this approach is that calling a polymorphic function with a primitive as a type parameter
requires some kind of trick, since the implementation is specified as taking a `Ref`.

More broadly, this overapproximates what kind of things we need to model as references.  Immutable types
like `Result` can probably be treated as values, and this may make our life easier.

### Inhale accessibility on read

An alternative approach that permits for aliasing, but can verify much less, is to inhale and exhale
permissions of possibly aliasing locations on an as-needed basis.  This is demonstrated in method
`aliasing_inhale_exhale` in `Examples/Viper/Kotlin/aliasing.vpr`, where by exhaling the permissions
to `x.f` and `y.f` whenever we are not using them we allow for the possibility for these to alias.
However, note that we then also allow for `x.f` and `y.f` to be modified by any other thread:
`aliasing_inhale_exhale_problem` shows that we cannot show even quite simple properties in this context.

### Abstract representation for value types

The above two approaches translate all Kotlin classes into Viper references (see `class-hierarchies.md`
for a more detailed description).  This encoding is not the easiest to work with: we need access
permissions for all members that we want to read or write, and we cannot permit aliasing.

Instead, we can choose to model classes that behave like values using Viper domains.
This involves a number of conditions:
1. All fields of the class must be immutable.
2. The class must be final.
3. The class must not extend any other class.

**Note**: There's still work to be done to determine that these conditions are sufficient.
Some other things that may be worth asking:
1. May the class implement interfaces?
2. Are there language features (pointer comparison?) that can cause us problems?

For example, consider the following Kotlin code.

```kotlin
class A(val x: Int, val y: Int)

fun sum(a: A): Int = a.x + a.y
```

We can translate this into Viper as follows.

```
domain A {
    function A_new(x: Int, y: Int): A
    function A_get_x(a: A): Int
    function A_get_y(a: A): Int

    axiom ax_A_get_x {
        forall x: Int, y: Int :: A_get_x(A_new(x, y)) == x
    }
    axiom ax_A_get_y {
        forall x: Int, y: Int :: A_get_y(A_new(x, y)) == y
    }
}

function sum(a: A): Int
{
    A_get_x(a) + A_get_y(a)
}
```

It may be necessary to add some kind of axiom to be able to conclude that `get_x` and `get_y` together
determine the instance they are applied to.

Note that objects of such classes can still be cast to something of type `Any`.  It isn't quite clear
how we should model that.  A similar issue arises when passing such values to polymorphic functions.

This approach is similar to Prusti's snapshot encoding, but we do not build a heap structure that corresponds
to the snapshot.  We expect this not to be necessary, since such classes are by construction immutable,
and so we can always treat them as values.  (The classes may contain references, but these are still
immutable, though they may refer to mutable data structures.)