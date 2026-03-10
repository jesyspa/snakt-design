# Nullability

Nullability is of direct interest since the Kotlin contracts allow to specify
nullability checks (see [this KEEP][1]). Thus we need to model nullable types in
Viper.

This document presents the encoding of nullable types used in the implementation.
An earlier version of this document discussed two possible encodings; see git
history for the original text.

[1]: https://github.com/Kotlin/KEEP/blob/3490e847fe51aa6deb869654029a5a514638700e/proposals/kotlin-contracts.md

## Overview

The implementation uses a **unified `Ref` type** for all Kotlin values. Every
Kotlin value — whether `Int`, `Boolean`, a class instance, or `null` — is
represented as a Viper `Ref`. Type information is tracked separately via a
`RuntimeTypeDomain` that provides:

- A `RuntimeType` domain with subtyping (`isSubtype`), type-of (`typeOf`), and
  nullability (`nullable`) functions.
- A special `nullValue()` constant of type `Ref`.
- Injection functions to convert between Viper primitive types and `Ref` (e.g.
  `intToRef`/`intFromRef`).

This avoids the complications of the originally proposed `Nullable[T]` parametric
domain (boxing primitives, reasoning about permissions) and unifies nullable and
non-nullable types into a single representation.

## RuntimeTypeDomain

The domain is defined in
`SnaKt/formver.compiler-plugin/core/.../domains/RuntimeTypeDomain.kt`.

### Core functions

```viper
domain RuntimeType {
    function isSubtype(t1: RuntimeType, t2: RuntimeType): Bool
    function typeOf(r: Ref): RuntimeType
    function nullable(t: RuntimeType): RuntimeType

    function nullValue(): Ref
    function unitValue(): Ref

    unique function intType(): RuntimeType
    unique function boolType(): RuntimeType
    unique function charType(): RuntimeType
    unique function stringType(): RuntimeType
    unique function unitType(): RuntimeType
    unique function nothingType(): RuntimeType
    unique function anyType(): RuntimeType
    unique function functionType(): RuntimeType
    // unique function *Type(): RuntimeType  — one per user-defined class
}
```

### Key axioms

**Subtyping** is a partial order (reflexive, transitive, antisymmetric):

```viper
axiom subtype_reflexive { forall t :: isSubtype(t, t) }
axiom subtype_transitive {
    forall t1, t2, t3 ::
        isSubtype(t1, t2) && isSubtype(t2, t3) ==> isSubtype(t1, t3)
}
axiom subtype_antisymmetric {
    forall t1, t2 ::
        isSubtype(t1, t2) && isSubtype(t2, t1) ==> t1 == t2
}
```

**Nullable type** properties:

```viper
// Wrapping is idempotent: Int?? is the same as Int?
axiom nullable_idempotent {
    forall t :: nullable(nullable(t)) == nullable(t)
}

// Non-nullable is a subtype of nullable
axiom nullable_supertype {
    forall t :: isSubtype(t, nullable(t))
}

// Subtyping lifts through nullable
axiom nullable_preserves_subtype {
    forall t1, t2 :: isSubtype(t1, t2) ==> isSubtype(nullable(t1), nullable(t2))
}

// Any? is the top type
axiom nullable_any_supertype {
    forall t :: isSubtype(t, nullable(anyType()))
}

// Nullable types are NOT subtypes of Any (this separates null from non-null)
axiom any_not_nullable_type_level {
    forall t :: !isSubtype(nullable(t), anyType())
}
```

**Null value** axioms:

```viper
// null has type Nothing?
axiom type_of_null {
    isSubtype(typeOf(nullValue()), nullable(nothingType()))
}

// null is not a subtype of Any (value level)
axiom any_not_nullable_value_level {
    !isSubtype(typeOf(nullValue()), anyType())
}
```

**Smart cast** axioms (these are what enable null-check reasoning):

```viper
// Value-level: if r has nullable type T?, then r is null or r has type T
axiom null_smartcast_value_level {
    forall r: Ref, t: RuntimeType ::
        isSubtype(typeOf(r), nullable(t)) ==>
        r == nullValue() || isSubtype(typeOf(r), t)
}

// Type-level: if t1 is a non-nullable type (subtype of Any) and also
// subtype of T?, then t1 is a subtype of T
axiom null_smartcast_type_level {
    forall t1, t2 ::
        isSubtype(t1, anyType()) && isSubtype(t1, nullable(t2)) ==>
        isSubtype(t1, t2)
}
```

**Other structural axioms:**

```viper
// Nothing has no inhabitants
axiom nothing_empty { forall r :: !isSubtype(typeOf(r), nothingType()) }

// Nothing is a subtype of every type (bottom type)
axiom supertype_of_nothing { forall t :: isSubtype(nothingType(), t) }

// Unit has exactly one value
axiom type_of_unit { isSubtype(typeOf(unitValue()), unitType()) }
axiom uniqueness_of_unit {
    forall r :: isSubtype(typeOf(r), unitType()) ==> r == unitValue()
}
```

## Injection functions

Since all values are `Ref`, primitive types need injection/projection functions
to convert between their Viper-native type and `Ref`. These are defined in
`SnaKt/formver.compiler-plugin/core/.../domains/Injection.kt`.

Each injection (e.g. for `Int`) provides:

```viper
function intToRef(v: Int): Ref
function intFromRef(r: Ref): Int
```

With three axioms guaranteeing a bijection:

```viper
// Type preservation
axiom { forall v: Int :: isSubtype(typeOf(intToRef(v)), intType()) }

// Round-trip: native → Ref → native
axiom { forall v: Int :: intFromRef(intToRef(v)) == v }

// Round-trip: Ref → native → Ref (when type matches)
axiom {
    forall r: Ref ::
        isSubtype(typeOf(r), intType()) ==> intToRef(intFromRef(r)) == r
}
```

The same pattern applies to `Bool`, `Char` (represented as `Int` in Viper), and
`String` (represented as `Seq[Int]`).

Arithmetic and other operations on `Ref` are implemented as
`InjectionImageFunction`s that unwrap arguments, apply the native Viper
operation, and re-wrap the result.

## Compiler-side representation

In the compiler plugin, nullable types are represented by `TypeEmbedding`:

```kotlin
data class TypeEmbedding(val pretype: PretypeEmbedding, val flags: TypeEmbeddingFlags)
data class TypeEmbeddingFlags(val nullable: Boolean)
```

- `getNullable()` returns a copy with `nullable = true`.
- `getNonNullable()` returns a copy with `nullable = false`.
- `flags.adjustRuntimeType(runtimeType)` wraps with `nullable(...)` when the
  flag is set.

Type invariants for nullable types are wrapped with `IfNonNullInvariant`, which
generates `(exp != nullValue()) ==> invariant(exp)`. This ensures that
invariants (e.g. class predicate access) are only required when the value is
non-null.

## Null literal

The `null` literal is represented as `NullLit` with type `Nothing?`:

```kotlin
data object NullLit : LiteralEmbedding {
    override val type = buildType { isNullable = true; nothing() }
    override fun toViper(ctx) = RuntimeTypeDomain.nullValue(...)
}
```

In Viper output: `df$rt$nullValue()`.

## Null checks and smart casts

A null comparison `x == null` becomes `p$x == df$rt$nullValue()`. When this
comparison appears as a condition in `if` or `when`, the Kotlin compiler produces
a `FirSmartCastExpression` in the non-null branch.

The plugin handles smart casts in `StmtConversionVisitor.visitSmartCastExpression`:

- If the smart cast is from `T?` to `T` (only nullability changes), it produces
  a simple `Cast` that changes the type without emitting Viper code.
- If the smart cast changes the base type (e.g. `Any` to `Foo`), it inhales
  the invariants of the new type.

The SMT solver can then prove that in the non-null branch, `x != nullValue()`,
and the `null_smartcast_value_level` axiom gives `isSubtype(typeOf(x), T)`.

## Elvis operator (`?:`)

`x ?: default` is translated to:

```viper
if (p$x != df$rt$nullValue()) {
    ret := p$x
} else {
    ret := <default>
}
```

This is implemented as an `Elvis` embedding that wraps the left operand in a
null check via `notNullCmp()`.

The special case `x ?: return e` (elvis with early return) is also supported:
the right branch produces a return statement instead of an expression.

## Safe call operator (`?.`)

`x?.method()` is translated to:

```viper
if (p$x != df$rt$nullValue()) {
    ret := method(p$x)
} else {
    ret := df$rt$nullValue()
}
```

The receiver is evaluated once using a `share()` mechanism to prevent
double-evaluation of side-effectful expressions. The result type is the nullable
version of the method's return type.

Safe call chains like `a?.b()?.c()` nest: each `?.` produces an `if` with the
next `?.` in the non-null branch.

## Examples

### Null check with smart cast

```kotlin
fun smartcastReturn(n: Int?): Int =
    if (n != null) n else 0
```

```viper
method f$smartcastReturn$TF$NT$Int(p$n: Ref) returns (ret$0: Ref)
    ensures df$rt$isSubtype(df$rt$typeOf(ret$0), df$rt$intType())
{
    inhale df$rt$isSubtype(df$rt$typeOf(p$n), df$rt$nullable(df$rt$intType()))
    if (!(p$n == df$rt$nullValue())) {
        ret$0 := p$n
    } else {
        ret$0 := df$rt$intToRef(0)
    }
}
```

### Elvis operator

```kotlin
fun elvisOperator(x: Int?): Int {
    return x ?: 3
}
```

```viper
method f$elvisOperator$TF$NT$Int(p$x: Ref) returns (ret$0: Ref)
    ensures df$rt$isSubtype(df$rt$typeOf(ret$0), df$rt$intType())
{
    inhale df$rt$isSubtype(df$rt$typeOf(p$x), df$rt$nullable(df$rt$intType()))
    if (p$x != df$rt$nullValue()) {
        ret$0 := p$x
    } else {
        ret$0 := df$rt$intToRef(3)
    }
}
```

### Safe call on a method

```kotlin
class Foo { fun f() {} }
fun testSafeCall(foo: Foo?) = foo?.f()
```

```viper
method f$testSafeCall$TF$NT$Foo(p$foo: Ref) returns (ret$0: Ref)
    ensures df$rt$isSubtype(df$rt$typeOf(ret$0), df$rt$nullable(df$rt$unitType()))
{
    inhale df$rt$isSubtype(df$rt$typeOf(p$foo), df$rt$nullable(df$rt$c$Foo()))
    inhale p$foo != df$rt$nullValue() ==> acc(p$c$Foo$shared(p$foo), wildcard)
    if (p$foo != df$rt$nullValue()) {
        var anon$0: Ref
        anon$0 := f$c$Foo$f$TF$T$Foo(p$foo)
        ret$0 := anon$0
    } else {
        ret$0 := df$rt$nullValue()
    }
}
```

### Nullable parameter passing

```kotlin
fun passNullableParameter(x: Int?): Int? {
    useNullableTwice(x)
    return x
}
```

```viper
method f$passNullableParameter$TF$NT$Int(p$x: Ref) returns (ret$0: Ref)
    ensures df$rt$isSubtype(df$rt$typeOf(ret$0), df$rt$nullable(df$rt$intType()))
{
    inhale df$rt$isSubtype(df$rt$typeOf(p$x), df$rt$nullable(df$rt$intType()))
    var anon$0: Ref
    anon$0 := f$useNullableTwice$TF$NT$Int(p$x)
    ret$0 := p$x
}
```

## Open questions

- **Nullable type aliases**: Cases like `typealias T = Int?; typealias S = T?`
  are handled by `nullable_idempotent` but haven't been tested explicitly.
- **Not-null assertion (`!!`)**: The implementation status of this operator
  should be verified.
