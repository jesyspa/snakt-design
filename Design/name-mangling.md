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

Local names may also contain names: for example, the naem of
a function may contain the types of its parameters.
However, to make the program tractable we assume that local
names are guaranteed to be unique.

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

