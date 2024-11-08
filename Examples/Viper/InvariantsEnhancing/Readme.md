In this directory, we demonstrate which invariants should be added
in order to prove some properties.

Currently, three examples are given:
```kotlin
fun String.isSorted(): Boolean {
    var idx = 1
    while (idx < length) {
        if (this[idx - 1] > this[idx]) return false
        idx = idx + 1
    }
    return true
}

fun String.lessThan(other: String): Boolean {
    var idx = 0
    while (idx < length && idx < other.length) {
        if (this[idx] < other[idx]) return true
        idx = idx + 1
    }
    return length < other.length
}

fun String.isSubstringOnGivenPos(idx: Int, other: String): Boolean {
    var checkIdx = 0
    if (idx + other.length > length) return false
    if (idx < 0) return false
    while (checkIdx < other.length) {
        if (this[idx + checkIdx] != other[checkIdx]) return false
        checkIdx = checkIdx + 1
    }
    return true
}
```

Note that for the second sample we don't prove any properties only making it not fail verification.

You can find original output of our plugin in [original.vpr](./original.vpr).
The modified version is stored in [main.vpr](./main.vpr).

Use `Project tool window | context menu of a file | Compare Files` in Intellij to see the diff.
