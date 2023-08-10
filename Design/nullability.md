# Nullability

Nullability is of direct interest since the Kotlin contracts allow to specify nullability checks (see [this KEEP][1]). Thus we need to model nullable types in Viper.

This document presents two possible encoding of nullable types and discusses them.

## First approach

A simple first approach would be to just use the built-in null value of Viper.
Let's see how this works on a very simple example:

```kotlin
fun null_check(x: Any?): Boolean {
    if (x == null) {
        return true
    } else {
        return false
    }
}
```

This function is a simple null check for which a contract can be written in order for the compiler to do better analysis.

With the first approach this could be translated to Viper as follows:

```viper
field val: Ref

method null_check2(x: Ref) returns (ret: Bool) 
    requires x != null ==> acc(x.val)
    requires x != null ==> acc(x.val)
    ensures ret <==> x != null
{
    if (x == null) {
        ret := false
    } else {
        ret := true
    }
}
```

This is somewhat straight-forward and let's one prove the relationship between the input and the output. One disadvantage is that access to the field needs to be restricted.

There are, however, more drawbacks of this approach. One of which is modeling values that are not heap-based such as `Int`. Since these do not have a null value, they need to be boxed onto the stack. Then one needs to handles regular `Int`'s differently from `Int?`'s. This gets even more complicated when a nullable `Int` gets passed as a method parameter since this would mean it needs to be cloned because when the callee changes the value of the `Int?` (and thus its value on the heap) the `Int?` keeps in the caller must not be changed.

A third argument as to why not go with this approach is that for the start of the project we want to reason about the heap as little as possible.

Instead of dealing with all these complications we present a second more elegant representation.


[1]: https://github.com/Kotlin/KEEP/blob/3490e847fe51aa6deb869654029a5a514638700e/proposals/kotlin-contracts.md

## Second Approach

Instead of using the built-in null value of Viper's `Ref` type, we define a new domain:

```viper
domain Nullable[T] {
    function null_val(): Nullable[T]
    function nullable_of(val: T): Nullable[T]
    function val_of_nullable(x: Nullable[T]): T

    axiom some_not_null {
        forall x: T :: { nullable_of(x) }
            nullable_of(x) != null_val()
    }
    axiom val_of_nullable_of_val {
        forall x: T :: { val_of_nullable(nullable_of(x)) }
            val_of_nullable(nullable_of(x)) == x
    }
    axiom nullable_of_val_of_nullable {
        forall x: Nullable[T] :: { nullable_of(val_of_nullable(x)) }
            x != null_val() ==> nullable_of(val_of_nullable(x)) == x
    }
}
```

This domain models how nullable types behave. This allows for far more convenient translation and in addition one need not reason about permissions.

```viper
method null_check(x: Nullable[Ref]) returns (ret: Bool)
    ensures ret <==> x != null_val()
{
    if (x == null_val()) {
        ret := false
    } else {
        ret := true
    }
}
```

This also allows passing integers to other methods naturally without the aforementioned problems.

```viper
method pass_nullable_parameter(x: Nullable[Int])
    ensures x == old(x)
{
    some_method(x)
}
```

For more examples see the the `nullability.kt` and `nullability.vpr` files the the `Examples` directory.


## Automatic conversion

One problem that still needs to be solved in the conversion from nullable types to non-nullable types and back (both approaches face the same problem).

### From T to T?

In Kotlin code like `var x: Int? = 3` is totally valid.
`x` is of type `Int?`, `3` is of type `Int` and since `Int` is a subtype of `Int?` it can be assigned.
This is not so easy in Viper, however, as we have not solved subtyping yet. This means conversion functions need to be inserted as is `x := nullable_of(3)`.
One could imagine that this could be handled even without solving the general case of subtyping. Whenever an expression of a nullable type is expected but a non-nullable expression is given, insert a conversion function.

### From T? to T

The reverse also needs to be handles. Especially interesting are the cases where the compiler does a smart cast as in:

```kotlin
fun smart_cast(x: Int?): Int {
    if (x == null) {
        return 0
    } else {
    // Compiler infers that since x is not null it has to be of type Int.
        return x
    }
}
```

Here we need to extract this smart cast information from the compiler and also insert a explicit cast with `val_of_nullable`.