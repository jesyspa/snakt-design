# Distinguish between BorrowedUnique and BorrowedShared

This approach takes inspiration from [Alias-Burying](alias-burying.md) and [LATTE](LATTE.md). In Alias-Burying, a `Borrowed` parameter can be `Unique`
or `Shared` while in LATTE a `Borrowed` parameter can only be `Unique`.
In this approach, the distinction between _borrowed-shared_ and _borrowed-unique_ is made explicit.

## Annotations sets

- All fields and return values must be annotated with either `Unique` or `Shared`.
- Method parameters (including the receiver) must be annotated with one of the four annotations
  (`Unique`, `BorrowedUnique`, `BorrowedShared`, `Shared`).
- It should be possible to infer annotations of variable declarations

## Annotations meaning

- A `Shared` annotation denotes that the variable can be accessed by outside objects,
  untracked aliases may exist.
- `BorrowedUnique` method parameter has to be `Unique` (or `BorrowedUnique`) and ensures that no further aliases are
  created.
- `BorrowedShared` method parameter can be `Unique` or `Shared`. Differently from a `Shared` parameter,
  a `BorrowedShared` grants that no further aliases are created.
- `Unique` denotes ownership, the value is only stored at this location.

## Encoding

Encoding with this approach should be easy

### Parameters

```kt
fun f1(a: @Unique A) {}
fun f2(a: @BorrowedUnique A) {}
fun f3(a: A) {} // shared can be the default annotation
fun f4(a: @BorrowedShared A) {}
```

```
method f1(a: Ref)
requires A(a)

method f2(a: Ref)
requires A(a)
ensures A(a)

method f3(a: Ref) 
// if needed, access will be inhaled in the body and exhaled right after
// if a unique reference is passed, it is necessary to exhale A since the uniqueness is lost

method f4(a: Ref)
// if a unique reference is passed,
// it is NOT needed to exhale A since the method grants that no further aliases will be created
```

### Return values

```kt
fun f(): @Unique A {}
```

```
method f() returns (ret: Ref)
ensures A(ret)
```

### Fields

```kt
class B(var x: @Unique A, var y: A)
```

```
predicate B(this: Ref){
    acc(this.x) && A(this.x) &&
    acc(this.y)
    // if needed, A(this.y) will be inhaled in the body and exhaled right after
}
```

## Conclusion

**Pros:**

- Easy to encode
- Doesn't slow down the encoding/verification
- Allows borrowed shared parameters

**Drawbacks:**

- More complicated annotations system than Alias-Burying or LATTE