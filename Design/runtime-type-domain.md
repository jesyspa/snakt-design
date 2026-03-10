# Runtime Type Domain

The runtime type domain is the backbone of SnaKt's Viper encoding. It provides
a unified representation of all Kotlin values as Viper `Ref`, with type
information tracked separately through domain functions and axioms.

This document describes the domain as implemented in
`formver.compiler-plugin/core/.../domains/RuntimeTypeDomain.kt`.

## Motivation

Kotlin has a rich type system with nullable types, class hierarchies, generics,
and primitive types. Viper's built-in type system is much simpler. Rather than
encoding each Kotlin type as a separate Viper type (which would require boxing,
casting, and permission reasoning), all Kotlin values are represented as `Ref`
with a separate domain tracking type information.

This design was chosen over alternatives like parametric `Nullable[T]` domains
(see [nullability](nullability.md)) because it:
- Avoids boxing/unboxing complexity for primitives
- Eliminates permission reasoning for nullable values
- Provides a single uniform encoding for subtyping, casting, and null checks
- Enables smart casts via axioms rather than explicit conversions

Earlier prototypes of a multi-domain approach can be found in `Domains/*.vpr`.

## Domain structure

```viper
domain RuntimeType {
    // Subtyping and type tracking
    function isSubtype(t1: RuntimeType, t2: RuntimeType): Bool
    function typeOf(r: Ref): RuntimeType
    function nullable(t: RuntimeType): RuntimeType

    // Special values
    function nullValue(): Ref
    function unitValue(): Ref

    // Built-in type constants (unique ensures distinctness)
    unique function intType(): RuntimeType
    unique function boolType(): RuntimeType
    unique function charType(): RuntimeType
    unique function stringType(): RuntimeType
    unique function unitType(): RuntimeType
    unique function nothingType(): RuntimeType
    unique function anyType(): RuntimeType
    unique function functionType(): RuntimeType

    // One per user-defined class:
    // unique function <className>(): RuntimeType
}
```

## Subtyping axioms

Subtyping is a partial order:

```viper
axiom subtype_reflexive    { forall t :: isSubtype(t, t) }
axiom subtype_transitive   { forall t1, t2, t3 ::
    isSubtype(t1, t2) && isSubtype(t2, t3) ==> isSubtype(t1, t3) }
axiom subtype_antisymmetric { forall t1, t2 ::
    isSubtype(t1, t2) && isSubtype(t2, t1) ==> t1 == t2 }
```

All non-nullable types are subtypes of `Any`:

```viper
axiom { isSubtype(intType(), anyType()) }
axiom { isSubtype(boolType(), anyType()) }
// ... etc. for all built-in and user-defined types
```

`Nothing` is the bottom type:

```viper
axiom supertype_of_nothing { forall t :: isSubtype(nothingType(), t) }
axiom nothing_empty        { forall r :: !isSubtype(typeOf(r), nothingType()) }
```

## Nullable type axioms

See [nullability](nullability.md) for the design context. The key axioms:

```viper
axiom nullable_idempotent       { forall t :: nullable(nullable(t)) == nullable(t) }
axiom nullable_supertype        { forall t :: isSubtype(t, nullable(t)) }
axiom nullable_preserves_subtype { forall t1, t2 ::
    isSubtype(t1, t2) ==> isSubtype(nullable(t1), nullable(t2)) }
axiom nullable_any_supertype    { forall t :: isSubtype(t, nullable(anyType())) }
axiom any_not_nullable_type_level { forall t :: !isSubtype(nullable(t), anyType()) }
```

Null value:

```viper
axiom type_of_null               { isSubtype(typeOf(nullValue()), nullable(nothingType())) }
axiom any_not_nullable_value_level { !isSubtype(typeOf(nullValue()), anyType()) }
```

Smart cast axioms (enable reasoning after null checks):

```viper
axiom null_smartcast_value_level { forall r, t ::
    isSubtype(typeOf(r), nullable(t)) ==> r == nullValue() || isSubtype(typeOf(r), t) }
axiom null_smartcast_type_level  { forall t1, t2 ::
    isSubtype(t1, anyType()) && isSubtype(t1, nullable(t2)) ==> isSubtype(t1, t2) }
```

## Unit axioms

```viper
axiom type_of_unit      { isSubtype(typeOf(unitValue()), unitType()) }
axiom uniqueness_of_unit { forall r ::
    isSubtype(typeOf(r), unitType()) ==> r == unitValue() }
```

## Injection functions

Since all values are `Ref`, primitive types need bijective mappings. Each
injection provides a `toRef`/`fromRef` pair with three axioms:

```viper
// Example for Int:
function intToRef(v: Int): Ref
function intFromRef(r: Ref): Int

axiom { forall v: Int :: isSubtype(typeOf(intToRef(v)), intType()) }
axiom { forall v: Int :: intFromRef(intToRef(v)) == v }
axiom { forall r: Ref :: isSubtype(typeOf(r), intType()) ==> intToRef(intFromRef(r)) == r }
```

Available injections:
- `Int` <-> `Ref` (Viper `Int`)
- `Bool` <-> `Ref` (Viper `Bool`)
- `Char` <-> `Ref` (Viper `Int` — characters as code points)
- `String` <-> `Ref` (Viper `Seq[Int]`)

Arithmetic and other operations are implemented as `InjectionImageFunction`s:
Viper functions that unwrap `Ref` arguments via `fromRef`, apply the native
operation, and re-wrap via `toRef`.

## User-defined class types

Each class in the program gets a unique type function added to the domain:

```viper
unique function c$Foo(): RuntimeType
```

Subtype relationships between classes are also added as axioms based on the
class hierarchy.

## Compiler-side representation

`TypeEmbedding` pairs a `PretypeEmbedding` (the base type) with
`TypeEmbeddingFlags` (currently just a `nullable` boolean):

```kotlin
data class TypeEmbedding(val pretype: PretypeEmbedding, val flags: TypeEmbeddingFlags)
data class TypeEmbeddingFlags(val nullable: Boolean)
```

`flags.adjustRuntimeType(exp)` wraps with `nullable(...)` when the flag is set.
`flags.adjustInvariant(inv)` wraps with `IfNonNullInvariant` — generating
`(x != nullValue()) ==> invariant(x)`.

## Naming convention

In generated Viper output, domain functions are prefixed with `df$rt$`:
- `df$rt$isSubtype(...)`, `df$rt$typeOf(...)`, `df$rt$nullable(...)`
- `df$rt$nullValue()`, `df$rt$unitValue()`
- `df$rt$intToRef(...)`, `df$rt$intFromRef(...)`
- `df$rt$intType()`, `df$rt$c$Foo()`, etc.

Special arithmetic/comparison functions use the `sp$` prefix:
- `sp$plusInts(...)`, `sp$minusInts(...)`, `sp$notBool(...)`, etc.
