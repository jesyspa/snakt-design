# A formalism for `unique` and `inPlace`

We start with a minimal imperative language with integers,
booleans, and objects.  We do not yet track mutability.

## Types

There are three primitive types `Unit`, `Int`, and
`Boolean`.

Every program furthermore has a set of classes `Class`.  A
class is a set of fields, with each field defined by its
name and class.  Classes may be directly or indirectly
self-referential.

Notation: for a class type `X`, `fields(X)` is a set of
name, type tuples.  For a premitive type `X`, `fields(X)` is
empty.

## Basic operations

There are constants for the values of `Unit`, `Int`, and
`Boolean`.  For uniformity, we consider constants to be
nullary functions.

Arithmetic and comparison operations on integers and logical
operations on booleans are defined as unary and binary
functions.

## Expression syntax

An expression `e` is one of the following:
- A declaration `var x: X = e`, optionally with annotations
  `unique` (denoted `:_1`) and/or `inPlace` (denoted `:^*`).
- A variable `x`
- A variable assignment `x = e`
- A sequence of statements `e_1; ...; e_n`
- A function call `f(e_1, ..., e_n)`
- An if expression `if e_1 then e_2 else e_3`
- A field access `e.x`
- A field assignment `e_1.x = e_2`

## Lifetimes

We assume there is a join semillatice of lifetimes
`Lifetime` with a bottom element ⟂ and a top element ⊤.

Typing judgements may be annotated with a lifetime
annotation.  A lack of annotation is the same as an
annotation with ⊤.

There is a subtraction operation on sets of lifetimes:
```
L - n = { not l <= n | l in L }
L - N = intersection of L - n for all n in N
```

There is a special lifetime placeholder `*` that denotes
that denotes some non-⊤ lifetime.

## Uniqueness annotations

Typing judgements may be annotated with one of two
uniqueness anotations, 1 or ω.  A lack of annotation is
the same as an annotation with ω.

## Variable contexts

A context is a set of judgements of the form `x_L :^l_u X`
where `x` is a variable, `L` is a set of lifetimes, `l` is a
lifetime, `u` is a uniqueness annotation, and `X` is a type.
`l` and `u` may be dropped, in which case they have default
values ⊤ and ω respectively. `L` may be dropped, in
which case it is taken to be the empty set.

Informally, this should be read as "variable `x` is of type
`X` and unicity `u`, may not leak beyond lifetime `l`, and
may not be used until after lifetimes `L` have ended."

As is common, we will omit curly braces for the context.  We
will also drop the curly braces for `L` when it does not
cause confusion.

## Typing judgements

We use flow typing.  A typing judgement is of the form
```
Γ_0 ⊢ n< e :^l_u T>m ⊣ Γ_1
```
where `Γ_0` and `Γ_1` are contexts, `e` is an expression,
`n`, `m`, and `l` are lifetimes, and `u` is a uniqueness
annotation.
We require that `n < m` always.

Informally, this should be read as: starting in a context
`Γ_0`, if the lifetime `n` is complete and we are within
lifetime `m`, the term `e` has type `T` and uniquenes `u`,
and may not be leaked outside `l`.

## Typing rules

The following inference rules give a derivation system for
typing judgements:

```
TODO: there should be a coherence condition here of some sort.
   Γ_0 ⊢ n<e :^l_u T>m ⊣ Γ_1
-------------------------------
Γ_0, Δ ⊢ n<e :^l_u T>m ⊣ Γ_1, Δ


Γ_0, x_L' :^l_u X ⊢ n< e :^k_v T >m ⊣ Γ_1   L' = L - n
------------------------------------------------------
     Γ_0, x_L :^l_u X ⊢ n< e :^k_v T >m ⊣ Γ_1


             Γ_0 ⊢ n<e :^l_u X>k ⊣ Γ_1
-----------------------------------------------------
Γ_0 ⊢ n,k<val x :^l_u X = e : Unit>m ⊣ x :^l_u X, Γ_1


            m ≤ l
-------------------------------
x :^l X ⊢ n<x :^l X>m ⊣ x :^l X


               m ≤ k ≤ l
---------------------------------------
x :^l_1 X ⊢ n<x :^k_1 X>m ⊣ x_k :^l_1 X


TODO: figure out what to do with self-referential updates
          Γ_0 ⊢ n<e :^l_u X>m ⊣ Γ_1
--------------------------------------------------
Γ_0, x :^l_u X ⊢ n<x = e : Unit>m ⊣ Γ_1, x :^l_u X


TODO: see whether we need to include all past stuff
Γ_i ⊢ mi<e_(i+1) :^l(i+1)_u(i+1) X_(i+1)>m(i+1) ⊣ Γ_(i+1)
---------------------------------------------------------
      Γ_0 ⊢ m0<e_1; ...; e_n :^ln_un X_n>mn ⊣ Γ_n


TODO: A function call `f(e_1, ..., e_n)`.  Similar to above,
but some design questions to go.

TODO: coherence conditions
        Γ_0 ⊢ n<e_c :_uc Boolean>mc ⊣ Γ_c
          Γ_c ⊢ mc<e_1 :^l_u X>m ⊣ Γ_1
          Γ_c ⊢ mc<e_2 :^l_u X>m ⊣ Γ_2
---------------------------------------------------
Γ_0 ⊢ n<if e_c then e_1 else e_2 :^l_u>m ⊣ Γ_1, Γ_2


Γ_0 ⊢ n<e :^⟂_u X>k ⊣ Γ_1
    y : Y ∈ Fields(X)
-------------------------
 Γ_0 ⊢ k<e.y : Y>m ⊣ Γ_1


    Γ_0 ⊢ n<e_1 :^⟂_u X>k ⊣ Γ_1
      Γ_1 ⊢ k<e_2 : Y>m ⊣ Γ_2
         y : Y ∈ Fields(X)
----------------------------------
Γ_0 ⊢ k<e_1.y = e_2 : Unit>m ⊣ Γ_2
```
