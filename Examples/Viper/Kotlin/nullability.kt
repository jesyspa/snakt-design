fun null_check(x: Any?): Boolean {
    if (x == null) {
        return true
    } else {
        return false
    }
}

fun return_nullable(b: Boolean): Int? {
    if (b) {
        return null
    } else {
        return 0
    }
}

fun smart_cast(x: Int?): Int {
    if (x == null) {
        return 0
    } else {
        return x
    }
}

fun some_method(x: Int?) {}

fun pass_nullable_parameter(x: Int?) {
    smart_cast(x)
}
