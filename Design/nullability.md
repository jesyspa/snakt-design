# Nullability

Nullability is of direct interest since the Kotlin contracts allow to specify
nullability checks (see [this KEEP][1]). We need to model nullable types in
Viper so that the verifier can reason about null safety.

[1]: https://github.com/Kotlin/KEEP/blob/3490e847fe51aa6deb869654029a5a514638700e/proposals/kotlin-contracts.md

## Approaches considered

### Parametric `Nullable[T]` domain

The first approach considered was a parametric Viper domain that wraps values:

```viper
domain Nullable[T] {
    function null_val(): Nullable[T]
    function nullable_of(val: T): Nullable[T]
    function val_of_nullable(x: Nullable[T]): T

    axiom some_not_null {
        forall x: T :: nullable_of(x) != null_val()
    }
    axiom val_of_nullable_of_val {
        forall x: T :: val_of_nullable(nullable_of(x)) == x
    }
    axiom nullable_of_val_of_nullable {
        forall x: Nullable[T] ::
            x != null_val() ==> nullable_of(val_of_nullable(x)) == x
    }
}
```

This gives a clean separation: `T` is the non-nullable type, `Nullable[T]` is
the nullable wrapper, and `nullable_of`/`val_of_nullable` convert between them.

Drawbacks:
- **Primitive boxing**: `Int` has no null value in Viper, so `Int?` would need
  heap boxing. Passing `Int?` as a parameter then requires cloning to avoid
  aliasing side effects.
- **Permission reasoning**: accessing the wrapped value requires heap
  permissions, adding complexity we want to avoid.
- **Explicit conversion**: every nullable-to-non-nullable transition needs an
  explicit `val_of_nullable` call, and vice versa.

A prototype of this approach exists in `Domains/Nullable.vpr` (with a companion
`Casting` domain for type conversions).

### Built-in Viper `null`

A simpler alternative: use Viper's built-in `null` reference directly. A
function `null_check(x: Any?): Boolean` would translate to:

```viper
method null_check(x: Ref) returns (ret: Bool)
    requires x != null ==> acc(x.val)
    ensures ret <==> x != null
```

Drawbacks:
- Requires permission reasoning for field access behind null checks.
- Primitives still need boxing onto the heap.
- Conflates Viper's `null` (a `Ref` value) with Kotlin's `null` (a value in
  any nullable type).

### Unified `Ref` with runtime type tracking (chosen)

The approach adopted is to represent **all** Kotlin values as Viper `Ref`, with
type information tracked through the [runtime type domain](runtime-type-domain.md).
Nullable types are handled by a `nullable(t)` type wrapper in the domain,
rather than by wrapping values.

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

Advantages over the alternatives:
- No boxing/unboxing for primitives — injection functions (`intToRef`/`intFromRef`)
  handle the Viper-level representation transparently.
- No permission reasoning for null checks — everything is value-level.
- Smart casts fall out of axioms rather than requiring explicit conversions.
- Nullable and non-nullable types share the same Viper type (`Ref`), so
  parameter passing, assignment, and comparison work uniformly.

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
