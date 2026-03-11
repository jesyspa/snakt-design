# Nullability

Nullability is of direct interest since the Kotlin contracts allow to specify
nullability checks (see [this KEEP][1]). We need to model nullable types in
Viper so that the verifier can reason about null safety.

[1]: https://github.com/Kotlin/KEEP/blob/3490e847fe51aa6deb869654029a5a514638700e/proposals/kotlin-contracts.md

## Encoding

All Kotlin values are represented as Viper `Ref`, with type information tracked
through the [runtime type domain](runtime-type-domain.md). Nullability is
handled at the type level: a `nullable(t)` wrapper in the domain marks types
that admit null, and `nullValue()` is a distinguished domain constant
representing null.

A nullable parameter `x: Int?` is encoded as:

```viper
method f(p$x: Ref) returns (ret$0: Ref)
{
    inhale df$rt$isSubtype(df$rt$typeOf(p$x), df$rt$nullable(df$rt$intType()))
    ...
}
```

The value `p$x` is just a `Ref`. The `inhale` establishes that its runtime type
is a subtype of `Int?`. No boxing, no permissions, no wrapper types.

Note that `nullValue()` is a domain function, not Viper's built-in `null`. We
do not use Viper's `null` — all null comparisons and null literals compile to
`df$rt$nullValue()`.

### Early alternatives

Two alternative approaches were considered early in the project:

1. **Parametric `Nullable[T]` domain**: wrap nullable values in a `Nullable[T]`
   domain with `nullable_of`/`val_of_nullable` conversion functions. Rejected
   because it requires boxing primitives onto the heap and permission reasoning
   for field access. A prototype exists in `Domains/Nullable.vpr`.

2. **Built-in Viper `null`**: use `null` as a `Ref` value directly. Rejected
   because it conflates Viper's `null` (a `Ref` value) with Kotlin's `null`
   (which can appear in any nullable type, including `Int?`), and still requires
   boxing and permission reasoning.

The chosen approach avoids both problems: `nullValue()` is a distinguished `Ref`
constant in the domain, and the `nullable(t)` type wrapper handles subtyping
without wrapping values.

## Pretypes and types

In the compiler plugin, nullability is separated into two layers:

- A **pretype** (`PretypeEmbedding`) represents a Kotlin type without
  nullability (or other flags). For example, `Int`, `Boolean`, `Foo`,
  `(Int) -> Int` are all pretypes. Pretypes determine the structure of the
  Viper encoding: injection functions, class predicates, field access, etc.

- A **type** (`TypeEmbedding`) pairs a pretype with `TypeEmbeddingFlags`,
  which currently contains a single `nullable` flag. The type determines the
  full Viper encoding: runtime type assertions include `nullable()` when the
  flag is set, and type invariants are wrapped with a non-null guard.

This separation is intentional and enforced: `PretypeEmbedding` is not a subtype
of `TypeEmbedding`, preventing one from being used where the other is expected.
A pretype can be promoted to a type via `asTypeEmbedding()` (non-nullable) or
`asNullableTypeEmbedding()`.

The flags affect two things:

1. **Runtime type**: `TypeEmbeddingFlags.adjustRuntimeType` wraps the pretype's
   runtime type with `nullable()` when the flag is set.

2. **Type invariants**: `TypeEmbeddingFlags.adjustInvariant` wraps invariants
   with `IfNonNullInvariant`, adding `exp != nullValue() ==> invariant`. This
   ensures class predicates and other invariants only apply when the value is
   non-null.

## How nullability works

### Null literal

`null` in Kotlin becomes `df$rt$nullValue()`, a domain function returning `Ref`.
Its type is `Nothing?`:

```viper
axiom type_of_null { isSubtype(typeOf(nullValue()), nullable(nothingType())) }
```

Since `Nothing?` is a subtype of every nullable type (via `nullable_preserves_subtype`
and `supertype_of_nothing`), `null` can be assigned to any `T?` variable.

### Null checks

`x == null` becomes `p$x == df$rt$nullValue()`. This is plain reference equality
in Viper — no unwrapping needed.

### Smart casts

When a null check like `if (x != null)` guards a branch, the Kotlin compiler
produces a `FirSmartCastExpression` that narrows `T?` to `T`. The plugin
translates this as a no-op `Cast` (just changes the type annotation). The
verifier can prove the narrowing via the `null_smartcast_value_level` axiom:

```viper
// If r has type T?, then either r is null or r has type T
axiom null_smartcast_value_level {
    forall r: Ref, t: RuntimeType ::
        isSubtype(typeOf(r), nullable(t)) ==>
        r == nullValue() || isSubtype(typeOf(r), t)
}
```

In the non-null branch, the solver knows `r != nullValue()`, so it concludes
`isSubtype(typeOf(r), t)` — the smart cast holds.

### Nullable type invariants

When a type is nullable, its invariants (e.g. class predicate access) are
wrapped with an implication: the invariant only applies when the value is
non-null. For example, a `Foo?` parameter inhales:

```viper
inhale p$foo != df$rt$nullValue() ==> acc(p$c$Foo$shared(p$foo), wildcard)
```

### Elvis operator (`?:`)

`x ?: default` becomes a conditional on whether `x` is null:

```viper
if (p$x != df$rt$nullValue()) {
    ret$0 := p$x
} else {
    ret$0 := <default>
}
```

The special case `x ?: return e` (early return in the null branch) is also
supported.

### Safe call operator (`?.`)

`x?.method()` becomes:

```viper
if (p$x != df$rt$nullValue()) {
    ret$0 := method(p$x)
} else {
    ret$0 := df$rt$nullValue()
}
```

The receiver is evaluated once via a sharing mechanism to prevent
double-evaluation. Safe call chains (`a?.b()?.c()`) nest naturally.

## Examples

### Smart cast after null check

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

Note that `p$n` is used directly as `ret$0` in the non-null branch — no
unwrapping call. The postcondition `isSubtype(typeOf(ret$0), intType())` is
proven by the solver using `null_smartcast_value_level`.

### Elvis operator

```kotlin
fun elvisOperator(x: Int?): Int = x ?: 3
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

Note the guarded `inhale` for the class predicate — it only applies when
`p$foo` is non-null.
