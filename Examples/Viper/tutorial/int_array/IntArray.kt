public class IntArray(size: Int) {
    public inline constructor(size: Int, init: (Int) -> Int) 
    public operator fun get(index: Int): Int
    public operator fun set(index: Int, value: Int): Unit
    public val size: Int
}

fun IntArray.count(): Int 

fun IntArray.count(predicate: (Int) -> Boolean): Int

fun IntArray.first(): Int
fun IntArray.first(predicate: (Int) -> Boolean): Int

fun IntArray.isEmpty(): Boolean
fun IntArray.isNotEmpty(): Boolean