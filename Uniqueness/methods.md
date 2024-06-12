# Methods

Within a method, the following elements are annotated as follows:

- The arguments have to be either `unique` or `shared`, in addition they can also be `borrowed`.
- The receiver has to be either `unique` or `shared`, in addition it can also be `borrowed`.
- The return value has to be either `unique` or `shared`.

## Return

- All the methods have to ensure access to the immutable predicate of the returned reference.
- In addition, a method returning a `unique` reference in Kotlin will also ensure access to the mutable predicate of the
  returned reference.

**Kotlin**

```kt
@Unique
fun return_unique(): T {
    return T()
}

fun return_shared(): T {
    return T()
}
```

**Viper**

```
predicate T(this: Ref) { ... }
predicate UniqueT(this: Ref) { ... }

method return_unique()
returns(ret: Ref)
ensures acc(T(ret), wildcard)
ensures UniqueT(ret)

method return_shared()
returns(ret: Ref)
ensures acc(T(ret), wildcard)
```

## Arguments conditions

The following table summarizes how the annotations on the arguments are encoded in the conditions of the method

|                | Unique  | Unique Borrowed | Shared  | Shared Borrowed |
|----------------|:-------:|:---------------:|:-------:|:---------------:|
| Requires Read  | &check; |     &check;     | &check; |     &check;     |
| Ensures Read   | &check; |     &check;     | &check; |     &check;     |
| Requires Write | &check; |     &check;     | &cross; |     &cross;     |
| Ensures Write  | &cross; |     &check;     | &cross; |     &cross;     |

**Kotlin**

```kt
fun arg_unique(@Unique t: T) {}
fun arg_shared(@Shared t: T) {}
fun arg_unique_b(@Unique @Borrowed t: T) {}
fun arg_shared_b(@Shared @Borrowed t: T) {}
```

**Viper**

```
method arg_unique(t: Ref)
requires acc(UniqueT(t))
requires acc(T(t), wildcard)
ensures acc(T(t), wildcard)

method arg_shared(t: Ref)
requires acc(T(t), wildcard)
ensures acc(T(t), wildcard)

method arg_unique_b(t: Ref)
requires acc(UniqueT(t))
requires acc(T(t), wildcard)
ensures acc(UniqueT(t))
ensures acc(T(t), wildcard)

method arg_shared_b(t: Ref)
requires acc(T(t), wildcard)
ensures acc(T(t), wildcard)
```

## Method calls

Method calls are straightforward in most of the cases, there are only two cases that require particular attention:

- When a `unique` reference is passed to a function expecting a `shared` argument, it is necessary to `exhale`
  the mutable predicate after the call since uniqueness is lost.
- When a `unique` reference is passed to a function expecting a `shared` and `borrowed` argument, it is necessary
  to `exhale` and `inhale` the mutable predicate after the call since the function can modify it.

**Kotlin**

```kt
fun call_unique(@Unique t: T) {
    arg_unique_b(t)
    arg_unique(t)
}

fun call_shared(@Unique tu: T, @Shared ts: T) {
    arg_shared_b(tu)
    arg_shared_b(ts)
    arg_shared(tu)
    arg_shared(ts)
}
```

**Viper**

```
method call_unique(t: Ref)
requires UniqueT(t)
requires acc(T(t), wildcard)
ensures acc(T(t), wildcard)
{
    arg_unique_b(t)
    arg_unique(t)
}

method call_shared(tu: Ref, ts: Ref)
requires UniqueT(tu)
requires acc(T(tu), wildcard)
requires acc(T(ts), wildcard)
ensures acc(T(tu), wildcard)
ensures acc(T(ts), wildcard)
{
    arg_shared_b(tu)
    exhale UniqueT(tu)
    inhale UniqueT(tu)
    
    arg_shared_b(ts)

    arg_shared(tu)
    exhale UniqueT(tu)
    
    arg_shared(ts)
}
```
