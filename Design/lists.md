# Lists

Viper’s built-in sequence type `Seq[T]` represents immutable finite sequences of elements of type `T`

It would be cool to have a `nonEmpty` contract on lists that works as a precondition for certain list functions.
This can be used to find cases when certain values are known not to be null (e.g. first returns `T?` in general,
but returns `T` if the list is non-empty).

The kotlin type `List<T>` can be encoded as `Seq[T]`

## Encoding List initializers

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

## Encoding List operations

### Encoding in viper syntax

Some Koltin list operations maybe encoded directly with viper syntax

| Kotlin | Viper |
|---|---|
| `l.sublist(x, y)` (maybe also `slice`) | `l[x..y]` |
| `l[x]` | `l[x]` |
| `l1 + l2` | `l1 ++ l2` |
| `l.size()` | `\|l\|` |
| `l.contains(e)` | `e in l` |

### Preconditions and Postconditions
Since one our goal is to add contracts based on the non-emptiness of a list,
it can be useful to add some pre/post conditions to the most used list operations.

| Interesting operations | preconditions | postconditions |
|---|---|---|
| `size` | | `res == \|l\|` |
| `isEmpty` (opposite for `isNotEmpty`) | | `(res == true => \|l\| == 0) && (res == false => \|l\| > 0)` |
| `distinct`, `distinctBy`, `drop`, `dropLast`, `take`, `takeLast`, `filter` ... | | `\|res\| <= \|l\|` |
| `first`, `last`, `max`, ... | `\|l\| > 0` | |
| `firstOrNull`, `lastOrNull` | | `res != null => \|l\| > 0` |
| `forEach` | | something about number of calls in place realated to the size of the list |
| `map`, `mapIndexed`, `reversed`, `sortedBy`, ... | | `\|res\| == \|l\|` |
| `single` | `\|l\| == 1` | |
| `l.zip(l1)` | | `(\|res\| <= \|l\|) && (\|res\| <= \|l1\|)` |

## Extra notes
- maybe we can get stronger postconditions for `filter` functions by using the Viper `in` operator
- we are still not supporting Kotlin ranges, but it's interesting to know that Viper also has them with the following
  syntax `[1..10]`

# New contracts ideas

### `isEmpty` condition

```
fun empty (l: List<Int>): Boolean {
    contract {
        returns(true) implies (isEmpty(l))
        returns(false) implies (!isEmpty(l))
    }
}
```

### `nonEmpty` precondition

```
fun verifiedFirst (l: List<Int>): Int {
    contract {
        precondition(nonEmpty(l))
    }
}
```

Is there any difference between this and statically verify `assert(l.size != 0)` ??

maybe it can be interesting having something like this

```
fun firstOrNull (l: List<T>): T? {
    contract {
        nonEmpty(l) implies (returnsNotNull)
    }
}
```