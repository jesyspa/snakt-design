# Lists
It can be possible to verify some properties regarding lists by adding some pre- / post-conditions to stdlib functions
or allowing the user to express them with new kinds of contracts.

## Pre-conditions and Post-conditions
Since one of our goals is to add contracts based on the non-emptiness of a list,
it can be useful to add some pre- / post-conditions to the most used list operations.

| Interesting operations                                                         | pre-conditions | post-conditions                                                          |
|--------------------------------------------------------------------------------|----------------|--------------------------------------------------------------------------|
| `add`                                                                          |                | `\|res\| == \|l\| + 1`                                                   |
| `isEmpty` (opposite for `isNotEmpty`)                                          |                | `(res == true => \|l\| == 0) && (res == false => \|l\| > 0)`             |
| `distinct`, `distinctBy`, `drop`, `dropLast`, `take`, `takeLast`, `filter` ... |                | `\|res\| <= \|l\|`                                                       |
| `first`, `last`, `max`, ...                                                    | `\|l\| > 0`    |                                                                          |
| `firstOrNull`, `lastOrNull`                                                    |                | `res != null => \|l\| > 0`                                               |
| `forEach`                                                                      |                | something about number of calls in place related to the size of the list |
| `map`, `mapIndexed`, `reversed`, `sortedBy`, ...                               |                | `\|res\| == \|l\|`                                                       |
| `single`                                                                       | `\|l\| == 1`   |                                                                          |
| `l.zip(l1)`                                                                    |                | `(\|res\| <= \|l\|) && (\|res\| <= \|l1\|)`                              |

## Encoding as Seq

Viper’s built-in sequence type `Seq[T]` represents immutable finite sequences of elements of type `T`
The kotlin type `List<T>` can be encoded as `Seq[T]`

### Encoding initializers

Kotlin immutable lists can be initialized in the following ways:

```kotlin
val l1 = listOf(1, 2, 3)
val l2 = List(3) { it }
val l3 = emptyList<Int>()
```

These initialization can be encoded in viper as follows

```
var l1: Seq[Int]
l1 := Seq(1, 2, 3)

// I don't know if it makes sense to inline the initializer
var l2: Seq[Int]
inhale(|l2| == 3)

var l3: Seq[Int]
l3 := Seq()
```

### Operation that can be encoded directly with Viper syntax

Some Koltin list operations maybe encoded directly with viper syntax

| Kotlin                                 | Viper      |
|----------------------------------------|------------|
| `l.sublist(x, y)` (maybe also `slice`) | `l[x..y]`  |
| `l[x]`                                 | `l[x]`     |
| `l1 + l2`                              | `l1 ++ l2` |
| `l.size()`                             | `\|l\|`    |
| `l.contains(e)`                        | `e in l`   |

## Encoding as Predicate

List can also be encoded as predicates in the following way:

```
predicate List(l: Ref) {
    acc(l.size, write) && l.size >= 0
}
```
Then pre- / post-conditions can be added to stdlib functions by unfolding the predicate.
For example `isEmpty` function can be encoded as follows:
```
method isEmpty(xs: Ref) returns(res: Bool)
    requires List(xs)
    ensures List(xs)
    ensures res == false ==> unfolding List(xs) in xs.size > 0
    ensures res == true ==> unfolding List(xs) in xs.size == 0
    ensures old(unfolding List(xs) in xs.size) == unfolding List(xs) in xs.size
```

### Aliasing problem

Representing `List` as predicates with write access on the `size` field introduces the aliasing problem:
Let consider the `zip` function, encoding it in the following way is not correct:
```
method zip(this: Ref, xs: Ref) returns (res: Ref)
    requires List(this)
    requires List(xs)
    // other conditions...
    
method aliasing(a: Ref)
requires List(a)
{
    var res: Ref
    res := zip(a, a)
    //The pre-condition of method zip might not hold. There might be insufficient permission to access List(xs)
}
```

In order to solve the problem, `zip` has to be encoded considering the aliasing possibility:
```
method zip(this: Ref, xs: Ref) returns (res: Ref)
    requires List(this)
    requires this != xs ==> List(xs)
    ensures List(this)
    ensures this != xs ==> List(xs)     
    ensures List(res)
    // other conditions...
```

Since `List` predicate is a type invariant, the aliasing problem may occur also in a user-defined function.
For now, we will live with this problem. Example:

```Kotlin
fun sameSize(xs: List<Int>, ys: List<Int>) : Boolean {
    return xs.size == ys.size
}
```
In Viper is encoded as:
```
method sameSize(xs: Ref, ys: Ref) returns(res: Bool)
requires List(xs)
requires List(ys)
ensures List(xs)
ensures List(ys)
{
    var size_xs: Int
    var size_ys: Int

    unfold List(xs)
        size_xs := xs.size
    fold List(xs)

    unfold List(ys)
        size_ys := ys.size
    fold List(ys)

    res := size_xs == size_ys
}
```
Calling this method by passing two arguments that are aliased will lead to a Viper error.
A possible solution to this problem is presented in the next section.

## New contracts ideas
Since our approach is to verify each function independently of the others, we need to allow the user to express some
conditions on its own functions, otherwise most of the information will be lost when a user-defined function is called.

### `isEmpty` condition

```
fun empty (l: List<Int>): Boolean {
    contract {
        returns(true) implies (isEmpty(l))
        returns(false) implies (!isEmpty(l))
    }
}
```
This can be extended to specify the exact size or a comparison between the size and an integer

### `nonEmpty` pre-condition

```
fun verifiedFirst (l: List<Int>): Int {
    contract {
        precondition(nonEmpty(l))
    }
}
```

### `unchangedSize` post-condition
Let consider the following example:
```Kotlin
fun addIfMutable(l: List<Int>) {
    when (l){
        is MutableList<Int> -> l.add(1)
    }
}
```
In the example we can see that we can never be sure that the size of a `List`
 does not change. It can be useful to allow the user to express that a parameter will not change in the function.
```
fun notChanged(l: List<Int>) {
  contract {
      unchagedSize(l)
  }
  // operations that do not modify the size of l
}
```

### `nonAliasing` pre-condition
```
fun nonAliasing(xs: List<Int>, ys: List<Int>) {
  contract {
      nonAliasing(xs, ys)
  }
}
```