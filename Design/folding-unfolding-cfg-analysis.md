# Problem
- We want to add the fold/unfolds on the field access expression. But during the translation from Fir to ExpEmbedding, we do not know if it needs to be folded or unfolded. The main reason is, that to fold back, we need to know if after the current statement is finished the path is partially moved or not.

## Examples
Classes:
```kotlin
class A(
    var field: @Unique Int
)

class B(
    var a : @Unique A
    var a2: @Unique A
)

```


### Read vs Write
```kotlin
fun test1(b: @Unique B) {
    val x = b.a
}
fun test2(b: @Unique B) {
    b.a = A()
}
```
The first problem is that when we transform the `firExpression` to the `ExpEmbedding` we don't know if the field access is a read or a write. 
- In the `test1`, we need to only `unfold` - a `fold` would be wrong here, because `b` is partially moved. 
- In the `test2`, we don't only need to `unfold` but also `fold` back.

### Double Read
We can not just fold back everytime we have read out a value, because of this counter example

```kotlin
fun consume(a: @Unique A) : Int

fun test3(b: @Unique B) {
    val x = consume(b.a2) + b.a.field
}
```
For the left part of the `+`, we need to `unfold(b)` to have access to the unique predicate of `b.a2`. After we embedded the `consume(b.a2)`, we can not do `fold(b)` because we are lacking permissions. 
So then when we want to perform the `b.a.field`, we only need to do `unfold(b.a)`, because `b` is already unfolded.

After it, we need to fold `b.a` but not `b`. 




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