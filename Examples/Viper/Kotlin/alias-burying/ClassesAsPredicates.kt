@Target(AnnotationTarget.TYPE, AnnotationTarget.FUNCTION)
annotation class Unique

@Target(AnnotationTarget.TYPE, AnnotationTarget.FUNCTION)
annotation class Borrowed

class B(val z: Int, var w: Int)
class A(val x: Int, var y: Int, val r1: B, val r2: @Unique B) {
    @Borrowed
    fun f() {
        val n: Int = this.x
        this.r2.w = n
        this.y = this.r2.w
    }
}

fun main() {
    val a: @Unique A = A(1, 2, B(3, 4), B(5, 6))
    println("a.x = ${a.x} | a.r2.w = ${a.r2.w} | a.y = ${a.y}")
    a.f()
    println("a.x = ${a.x} | a.r2.w = ${a.r2.w} | a.y = ${a.y}")
}