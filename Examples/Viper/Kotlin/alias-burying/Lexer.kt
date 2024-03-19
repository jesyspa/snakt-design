// example from https://onlinelibrary.wiley.com/doi/abs/10.1002/spe.370 (Alias Burying paper)

class File

class Buffer(private var file: @Unique File?) {

    @BorrowedUnique
    fun atEOF(): Boolean {
        //...
        return false
    }

    @BorrowedUnique
    fun sync() {
        //...
    }

    @BorrowedUnique
    fun getFile(): @Unique File? {
        val temp = file
        file = null
        return temp
    }
}

class Lexer(private var buf: @Unique Buffer) {

    @BorrowedUnique
    fun isDone(): Boolean {
        return buf.atEOF()
    }

    @BorrowedUnique
    fun replace(file: @Unique File): @Unique File? {
        buf.sync()
        val old = buf.getFile()
        buf = Buffer(file)
        return old
    }
}