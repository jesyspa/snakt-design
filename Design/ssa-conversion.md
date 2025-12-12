# Converting an ExpEmbedding into SSA form

In order to translate pure Kotlin functions into Viper functions their body must be translated into a single expression. Therefore, reassignments of variables may not happen on the Viper level which is why the ExpEmbedding must be translated into SSA form.

## Converting a Block to SSA form

Assuming we have a block embedding with no branching, converting into SSA form is quite straight-forward:
- Traverse the ExpressionEmbeddings in the block in order
- As soon as a reassignment is found introduce a new variable and assign it the RHS of the reassignment.
- In subsequent usages of the 'original' variable use the newly introduced version.
In code this may look like the following:
```kotlin
var x = 1
x = x + 1
return x
```
translates to:
```viper
let x_0 == (1) in
let x_1 == (x_0 + 1) in
x_1
```
Note: An optimized encoding of the above example could be created by assigning 1 + 1 directly to x_0. In general, if no usages occur between two reassignments of the same variable we can omit one assignment.

## What about branching?

To convert an arbitrary program into SSA form, we will adhere to the following conversion algorithm:

https://dl.acm.org/doi/10.1145/115372.115320

The key idea is the following: Whenever a join in the control flow graph (CFG) of the program is encounterd and if it is necessary, a $\Phi$  function is assigned to the next 'version' of a variable. This $\Phi$  function selects the correct upstream (upstream in the CFG that is) value of the variable based on the execution path taken to reach that block. The efficient identification of necessary locations for $\Phi$ functions is determined using dominance frontiers, ensuring they are only inserted where distinct definitions actually collide. The dominance frontier of a node d is the set of nodes that are not strictly dominated by d, but have an immediate predecessor that is. A conversion may look like the following:

```kotlin
var x = 0
if (x == 1) {
    x = x + 2
} else {
    x = x + 3
}
val y = x
return y
```
translates to:
```viper
let x_0 == (0) in
let x_1 == (x_0 + 2) in
let x_2 == (x_0 + 3)
let y_0 == ((x_0 == 1) ? x_1 : x_2) in
y_0
```
Implementation note: To perform this translation two things are required:
- A CFG topology (already given by the ExpEmbedding structure)
- A map between variable definitions and the blocks they occur in 