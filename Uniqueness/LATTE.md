# Latte: Lightweight Aliasing Tracking for Java

[LATTE][1] is system for uniqueness and aliasing that aims to be more usable and
impose low overhead on developers.

## Annotations sets

- All fields and return values must be annotated with either `Unique` or `Shared`.
- Method parameters (including the receiver) must be annotated with one of the three annotations
  (`Unique`, `Borrowed`, `Shared`).
- Variable declarations are not annotated since it is possible to infer their annotations.
  The [paper][1] also provides formal rules to infer annotations.

## Annotations meaning

- A `Shared` annotation denotes that the variable can be accessed by outside objects,
  untracked aliases may exist.
- `Borrowed` denotes that the value of the variable is borrowed. Specifically, its value is unique in the current
  context
  and no new aliases may be added to the heap.
- `Unique` denotes ownership, the value is only stored at this location.

## Encoding

Encoding with this approach should be straightforward

### Parameters

```kt
fun f1(a: @Unique A) {}
fun f2(a: @Borrowed A) {}
fun f3(a: A) {} // shared can be the default annotation
```

```
method f1(a: Ref)
requires A(a)

method f2(a: Ref)
requires A(a)
ensures A(a)

method f3(a: Ref) 
// if needed, access will be inhaled in the body and exhaled right after
// if a unique reference is passed, it necessary to exhale A since the uniqueness is lost
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
- Lightweight annotations

**Drawbacks:**

- It is not possible to borrow shared references
- Already existing functions that allow shared parameters cannot be annotated as borrowed, even if they don't create
  aliases.

[1]: https://arxiv.org/pdf/2309.05637.pdf