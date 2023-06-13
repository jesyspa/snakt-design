fun pre(predicate: () -> Bool): Bool = true
fun post(predicate: () -> Bool): Bool = true

fun sum(n: Int): Int {

    pre { 0 <= n }

    var res = 0
    for (i in 0..n) {

        invariants {
            { i <= (n + 1) },
            { res == (i = 1) * i / 2}
        }

        res += i
    }

    return res.post { it == n * (n + 1) / 2}
}

fun recursiveSum(n: Int): Int {
    pre { 0 <= n }
    return if (n == 0) { 
        0 
    } else {
        n + recursiveSum(n - 1)
    }.post { it == n * (n + 1) / 2 }
}