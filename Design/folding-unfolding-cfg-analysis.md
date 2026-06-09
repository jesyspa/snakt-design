# Related Work
- `Nagini`: The verifier for Python does not provide automated fold + unfolds. The user needs to write it themselves.
- `Prusti`: The verifier for Rust does provide automated fold + unfolds. They leverage pack and unpack statements given by the compiler which allow them to infer the necessary folds+unfolds.
- `Gobra`: The verifier for Go does also reley a lot on user provided fold and unfolds statements.

# Problem
- We want to add the fold/unfolds on the field access expression. But during the translation from Fir to ExpEmbedding, we do not know if it needs to be folded or unfolded. The main reason is, that to fold back, we need to know if after the current statement is finished the path is partially moved or not.

## When to fold and unfold
I think the best way to connect the uniqueness information to the predicate state is the following:
- If variable is unique, then we have access to the predicate.
- If a variable is partially moved, then the predicate is unfolded.

## When to decide?
I think the best place to decide the folds+unfolds is in the translation from the `Fir` to `ExpEmbedding`. Since, the uniqueness analysis runs on the `Fir` it generates facts based on the `Fir` embeddings. So to use this information, we need to query it with `Fir` embeddings. If we do it in the `ExpEmbedding` or even later, we would need some way to extract the initial `Fir` embedding, which would be error prone and cumbersome. 


## Examples
Classes:
```kotlin
class A(
    var field: @Unique Int
)

class B(
    var a1: @Unique A
    var a2: @Unique A
)

```


### Unused Reads
```kotlin
fun test1(b: @Unique B) {
    val x = b.a
}
fun test2(b: @Unique B) {
    b.a
}
```
The first problem is that when we transform the `firExpression` to the `ExpEmbedding` we don't know what is happening to the field. 
- In the `test1`, we need to only `unfold` - a `fold` would be wrong here, because `b` is partially moved. 
- In the `test2`, we need to do a `unfold` as well as a `fold`.

But during the embedding of the property, we see the following uniqueness information:
- `test1`: `b.a` is unqiue in both the in and out state.
- `test2`: `b.a` is unique in both the in and out state.

### Unknown Variable
```kotlin
fun test3() {
    val x = A(5).field
}
```
The expected viper would look like this:

```viper
anon := con_A(5)
unfold(Unique(anon))
x := anon.field
```

But if we perform the naive statement level approach, we would extract the paths, see that for the field access we need to unfold the receiver and then add the unfold statement with the receiver. Which would result in about following viper code:
```viper
unfold(Unique(con_A(5)))
anon := con_A(5)
x := anon.field
```
Which is not even valid viper code. 

If we want to do it on the statement level and support this, then some book keeping has to be done. One could add the unfold statement with a `Shared` ExpEmbedding which refers to the result of the constructor. But this would not really be clean and probably introduce some bugs.

### Complex receiver
```kotlin
fun test4(b1: @Unique B, b2: @Unique B, cond : Boolean) {
    val x = (if (cond) b1 else b2).a1
}
```
This is a similar example as before. When looking at the assignment, we can not decide what variable needs to be unfolded, because the receiver is complex.


### Multiple Reads
```kotlin
fun consume(a1: @Unique A, a2: @Unique A) : Unit

fun test5(b: @Unique B) {
    consume(b.a1, b.a2)
}
```
The expected viper for this would be:

```viper
unfold(unique(b))
consume(b.a1, b.a2)
```
Doing this on a statement level would be finde, because the path extractor will realize that there is a common prefix and only unfold it once. However if we move the fold/unfold decision to the field access, then it becomes unclear how to stop the double unfolds.

During translation of these two field accesses the uniqueness information will be the same for both. Hence they will perform the same unfold.


### Nested Function Calls

```kotlin
fun borrow(b: @Unique @Borrowed B) : Int
fun helper(a: @Unique A, value: Int)

fun test6(b: @Unique B) {
    helper(b.a1, borrow(b))
}
```
This code is actually fine. With both approaches (statement level vs field access level decision  making) this will result in issues.

The generated viper could would look like this:

```viper
unfold(unique(b))
arg1 := b.a1
arg2 := borrow(b)
helper(arg1, arg2)
```
Viper would complain here, because when calling `borrow` it needs to have access to the `unqiue` predicate of `b`.

At the moment, I don't see what a general solution without introducing new problems could be.

### Receiver Contains Statements
```
class C(
    var b : @Unique B,
)

fun test7(c1: @Unique C, c2: @Unique C, cond: Boolean) {
    val x = (if (cond) {
        val y = c1.b
        y.a1
    } else {
        c1.b.a1
    }).field
}
```
This is just a nightmare...


## Should we pivot to a normalized program form?
Complex receivers are a nightmare. What if we transform the program into a form, where every receiver is jsut a variable. This would result in the following:
- If we want to still do the analysis on the `Fir` level, we would need to transform the `Fir` AST which involes moving around a lot of information and will be error prone.
- If we want to do the transformation on the `ExpEmbedding` level, we must move the analysis also there, because now we have variables that do not exist in the `Fir`.

## Path Abstraction
What is our path abstraction? A path is an ordered list, where the first element is special:
- The first element can be a variable or a method call/constructor.
- All the other elements must be a property access.
The first element could also be a complex expression like in `test4`, but such complex expression must always be simplified and transformed into mulitple paths.

## Information Needed to Fold and Unfold

### Unfold
Since there is no clear bounday between statements in SnaKt we want to unfold on the field access level. 


### Fold


## CFG Analysis

### Unfolds
We are working on the level of statements. For each statement we need to do the following: 
```kotlin
fun unfolds(stmt) {
    val unfoldedPaths = mutableMapOf()
    val firFieldAccessUnfolds = mutableMapOf()
    for (path in stmt.pathsInExecutionOrder) {
        // We need to look at the prefix.
        // Because when the path is a.b.c
        // if we need to unfold something, then we need to only unfold a.b
        val prefix = path.dropLast(1)
        val uniqueness = prefix.uniquenessTypeIn

        if (uniqueness == Shared) {
            // nothing to unfold
        }
        if (uniqueness == Partially Moved) {
            // path = `a.b` and prefix = `a` and `a.b2` = moved
            // in this situation `a` is already unfolded
        }

        if (uniqueness == Unique) {
            // we need to unfold this path, 
            // iff we have seen it the first time. Otherwhise it was already unfolded.

            if (unfoldedPaths.contains(prefix)) continue
            unfold.add(prefix)

            val firFieldAccess = getCorresondingFirElement(path[-2], path[-1])

            firFieldAccessUnfolds(firFieldAccess)

        }
    }
}

```


### Folds
For folds we should be able to do it backwards. For all the paths that are afterwards unique we can fold them when we first see them (when traversing the statement backwards)

```kotlin
fun folds(stmt) {
    val foldedPaths = mutableMapOf()
    val firFieldAccessFold = mutableMapOf()
    for (path in stmt.pathsInRecersedExecutionOrder) {
        // We need to look at the prefix.
        // Because when the path is a.b.c
        // if we need to unfold something, then we need to only unfold a.b
        val prefix = path.dropLast(1)
        val uniqueness = prefix.uniquenessTypeOut

        if (uniqueness == Shared) {
            // nothing to unfold
        }
        if (uniqueness == Partially Moved) {
            // path = `a.b` and prefix = `a` and `a.b2` = moved
            // in this situation `a` can not be folded
        }

        if (uniqueness == Unique) {
            // we need to unfold this path, 
            // iff we have seen it the first time. Otherwhise it was already unfolded.

            if (foldedPaths.contains(prefix)) continue


            foldedPaths.add(prefix)

            val firFieldAccess = getCorresondingFirElement(path[-2], path[-1])

            firFieldAccessFolds(firFieldAccess)

        }
    }
}

```


## Additional Advatages
With the plan to actually insert the folds on the statement level (the old plan), there would be some annoying situations

```kotlin
fun test4() {
    val x = A().field
}
```
On the statement level, we kind of need to do `unfold(A())`. However this is not possible for many reasons. 

But with the new approach, we would be in the following situation
- During the fir -> ExpEmbedding translation, we created a `FieldAccess` `ExpEmbedding` that contains the information that it needs to unfold the receiver. 
- This could look like this: 
```
FieldAccess(
    receiver = MethodCall(...), 
    field = Field(...), 
    unfoldReceiver = true
)
```
When we translate this `ExpEmbedding` to viper, we can first convert the receiver which will get us a variable. Then we can use this variable to add the unfold statement and finally, we can add the field access.



## To Keep in Mind
During the `toViper` translation we usually expect that a expression is returned. For example when we access a field we want that the `toViper` function returns a expression that can be used in for example a function argument. However, if we need to add a `fold` after it, we can not really look return the expression, because we need to ad it to the linearizer before we can add the fold. 
Solution: It should always be possible to just add a assignment statement where we assign the result to an anon variable, then add the fold and return the new anon variable. This might lead to some unnecessary assignments.

## Open Questions
### How should a FirSafeCallExpression be treated?

```
a.nullable?.field
```
For the field access `(a.nullable).field` we have the following:
- If we execute the field access, then we know that `a.nullable != null` hence we can unfold the receiver. 


For the field access `(a.nullable)` we might need to `fold` if it is `null`
- At the moment I believe we can treat it very similar to a field access. At least for unfolding. 
