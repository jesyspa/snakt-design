# Generics

There are two primary ways of implementing generics: monomorphisation and type erasure.
With monomorphisation, we generate separate Viper code for every instatiation of a
generic, while with type erasure we treat generic types as being akin to `Any?`,
with the extra restrictions placed afterwards.

There are a number of questions here:
1. How do we represent objects of a generic type?
2. How do we represent a generic function when verifying it?
3. How do we represent a generic function when calling it?

## Last-resort approach: monomorphise everything

Let us begin by dealing with the most heavy-handed solution to the problem:
we can forget about generics entirely, instead monomorphising every usage of
every function and class and verifying them separately.  This is the choice
made by C++ with regards to type-checking templates, for example.

There are two main downsides:
1. Verification of the monomorphised code cannot guarantee that a function is correctly,
   only that its instantiations are correct, which is weaker.
2. Verification has to be done for every instantiation separately, which can result in
   duplicate work.

We thus want to find an approach where a function can at least be verified without
being instantiated.
To this end, we need a representation for type parameters and for types that
depend on type parameters.

## `Any?`-based object representation

A straightforward approach is to represent type parameters as being represented the same
way as the `Any?` type, with any additional type information being added as preconditions
and postconditions on any functions and methods involved.  Note that as in the case of
casting primitive types to `Any?`, this involves wrapping primitive types in a reference
(cf. `object-model.md`).

Calling a generic function thus involves exhaling type-specific permissions on the arguments
and then inhaling type-specific permissions on the return value; this can be wrapped in a
method that is essentially an instantiation of the generic function.  (This is still better
than monomorphising everything, as the verification only has to happen once, and that is
the expensive part.)

## Value types in a non-dependent context

The above representation can be used across the board, but it is less powerful than one would
like when it comes to value types.  Consider the following example:

```kotlin
class A<T>(val x: T, val y: T)
```

We would like `A<A<Int>>` to be a value type: there is no reason to perform any heap allocation.
However, this involves a special, monomorphic version of `A` to be generated when it is instantiated
with a value type, including all associated functions.  Viper has some limited support for this,
as domains can have parameters, but it is not clear in how far it addresses this problem.
