// Example from https://arxiv.org/pdf/2309.05637.pdf with BorrowedUnique/BorrowedShared distinction

class Node(var value: @Unique Any?, var next: @Unique Node?)

class Stack(var root: @Unique Node?) {
    @BorrowedUnique
    fun push(value: @Unique Any?) {
        val r = this.root
        this.root = null
        val n = Node(value, r)
        this.root = n
    }

    @BorrowedUnique
    fun pop(): @Unique Any? {
        val value: Any?
        if (this.root == null) {
            value = null
        } else {
            value = this.root!!.value
            val next = this.root!!.next
            this.root = next
        }
        return value
    }
}
