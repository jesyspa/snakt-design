# Heap-dependent expressions in pure functions

For a pure function, heap-dependent expressions do not violate purity per se.
In general, as long as we only read from the heap and can ensure that no
aliasing references exist, the function body remains pure. To add support for
these function bodies, we will introduce a new predicate granting permissions
to all relevant fields used within them. We will require this predicate for
all encountered reference types in the function's precondition and unfold it
to allow the accesses made within the function. Any functions violating the
purity assumption will be rejected by the purity checker.

## The pure predicate

The pure predicate is nearly equivalent to the shared predicate, with the only
difference being that it also acquires permissions on mutable fields. Consider
the following example:

```kotlin
data class Node(val next: Ref, var value: Int)
```
This class has the corresponding pure predicate:
```viper
predicate purePredicate(this: Ref) {
    acc(this.next, wildcard) &&
    acc(this.value, wildcard) &&
    (this.next != null ==> acc(purePredicate(this.next), wildcard))
}
```

## Constructing the precondition

Note that all reference types for which we need to require the pure predicate
can be found in the function's parameters. Furthermore, because the predicate
also contains the predicates for any references within the parameters, no extra
predicates need to be acquired to ensure that potentially nested heap accesses
in the function body work. However, the predicate only contains the predicates
of nested references if they are non-null (see the predicate definition above).
We will discuss the implications of this constraint in the "Nested field
accesses" section.

## Translation

We will unfold all necessary predicates before an access. As an optimization,
we want to keep track of previously unfolded predicates to avoid unfolding them
again (although it is possible to do so). This ensures that there are
sufficient permissions for all accesses made in the function. However, this
approach comes with some limitations. To elaborate further, consider the
following examples:

### Simple field accesses

For this simple case, we can clearly see that the approach yields a working
function.

```kotlin
@Pure
fun getFirstValue(node: Node): Int {
    return node.value
}
```
translates to:
```viper
function getValue(node: Ref): Int
    requires acc(purePredicate(node), wildcard)
{
    unfolding purePredicate(node) in
        node.value
}
```

### Nested field accesses

In the example below, we must also unfold the predicate of the reference to
`next` to ensure the access made to the next node is valid. In general, nested
field accesses can be understood as a path. When encountering a nested field
access, we need to unfold all predicates for the types on the path that have
not been previously unfolded. A natural consideration is to simply unfold as
much as possible at the beginning of the function. This, however, would not
work for the example below, as unfolding the predicates implicitly assumes that
the path does not contain a null reference. Below, this is only true in the
`else` branch of the ternary operator (or the Elvis operator in the Kotlin
version); hence, an on-demand solution is required.

```kotlin
@Pure
fun getThisOrNextValue(node: Node): Int {
    return node.next?.value ?: node.value
}
```

```Viper
function getThisOrNextValue(node: Ref): Int 
    requires acc(purePredicate(node), wildcard)
{
    unfolding purePredicate(node) in 
        node.next == null ? 
            node.val : 
            unfolding purePredicate(node.next) in node.next.val
}
```

### Function calls to self

Even though we are unfolding the predicate required by the called function,
this translation still works. This is because, in a verification context,
unfolding a predicate with wildcard permissions does not cause that context to
lose wildcard permissions to the predicate. 

```kotlin
@Pure
fun length(node: Node): Int {
    return if (node.next == null) {
        1
    } else {
        length(node.next)
    }
}
```

```Viper
function length(node: Ref): Int 
    requires acc(purePredicate(node), wildcard)
{
    unfolding purePredicate(node) in 
        node.next == null ? 
            1 : 
            length(node.next)
}
```

### Limitations

Note that we are acquiring more permissions than necessary. We solely infer the
required predicates from the function's parameters. While this approach significantly
simplifies the problem, it has some limitations. An access to a class might only occur
under certain conditions in the function, or not at all. We still require permissions for
the pure predicate in those cases, which could potentially cause verification
to fail even though the function is valid.

## When the function gets used

There are three possible places where a function may be used: in another
function, in a method, or in a specification. We will detail these use cases
below.

### In another function

In this case, we need to unfold predicates in a similar way as we did for
field accesses before calling the function. Note that any pure predicates
required by the called function must either be directly available in the
caller's precondition or be contained within the predicates in the caller's
precondition.

```kotlin
@Pure
fun isLastIndex(node: Node, index: Int): Bool {
    return if (length(node) == index + 1) {
        true 
    } else {
        false
    }
}
```

```Viper
function isLastIndex(node: Ref, index: Int): Bool 
    requires acc(purePredicate(node), wildcard)
{
    unfolding purePredicate(node) in 
        length(node) == index + 1 ? 
            true : false
}
```

### In a method

Analogous to SnaKt's existing permission system, we will inhale all relevant
permissions before the function gets called and exhale them after the function
was called. Note, however, that we do not unfold them (as we require them to be
present in the function).

```kotlin
fun getLastIndex(node: Node): Int {
    val len = length(node)
    return len - 1
}
```

```Viper
method getLastIndex(node: Ref) returns (res: Int)
{
    inhale acc(purePredicate(node), wildcard)
    var len: Int := length(node)
    exhale acc(pure_list(node), wildcard)
    res := len - 1
}
```

### In a specification

If a function is used in a specification, that context must also require the
predicates from the function's precondition to ensure the specification is
valid.

```kotlin
fun getFirstValue(node: Node): Int {
    preconditions {
        length(node) > 0
    }
    return node.value
}
```

```Viper
method getFirstValue(node: Ref) returns (res: Int)
    requires acc(purePredicate(node), wildcard)
    requires length(node) > 0
{
    inhale acc(sharedPredicate(node), wildcard)
    res := node.value
}
```