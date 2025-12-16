# Converting an ExpEmbedding into SSA form

In order to translate pure Kotlin functions into Viper functions their body must
be translated into a single expression. Therefore, reassignments of variables may
not happen on the Viper level which is why the ExpEmbedding must be translated
into SSA form. The most commonly employed approach to transform a program into SSA
form is described in the below paper by Cyrton et al.:

https://dl.acm.org/doi/10.1145/115372.115320

However, this approach requires knowledge of the whole CFG. The current
version of SnaKt with its embedding representation does not provide this. Therefore,
we will rely on an algorithm by Braun et al., which can be used to directly transform
a program into SSA form from its AST:

https://c9x.me/compile/bib/braun13cc.pdf

Note however, that this algorithm relies on recursive calls to preceding nodes
in the AST, which due to the structure of the embeddings in SnaKt, we will
avoid by carrying enough state into child nodes. 

To explain our adaption of this algorithm further, we will follow the structure
in the paper. First we will explain how to translate a single block into SSA
form and then elaborate on how we can extend this to an arbitrary program.

## Converting a Block to SSA form

The only condition in the above paper for translating a basic block into SSA form
is to traverse the expressions in the block in program order. As the embedding
representation of a block in SnaKt already does this upon calling .toViper()
we can perform the necessary transformations at this stage. There are two components
responsible for this. The SSAConverter holds state and provides functionality to perform
an SSA transformation. The PureLinearizer, which exists to linearize an ExpEmbedding into
a Viper expression, will call out to the SSAConverter if necessary. The following will be
introduced:
- A mapping from source variables to a list of new variable definitions, where each variable 
definition represents a reassignment of the original source variable. This mapping is on a
per-block basis (important later).
- When reading a variable, the PureLinearizer will resolve the variable name to the variable
name holding the latest definition of the original source variable in the current block by
calling out to the SSAConverter.
- When encountering an assignment, the PureLinearizer will call out to the SSAConverter to
make note of this reassignment and save the new defining expression of the source variable.

Overall this will result in the following translation behaviour:
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

## What about branching?

It is important to note, that in the current version of this SSA transformation
we assume that our program does not contain any back-edges in its CFG. When
encountering a source variable that has no defining expression in the current
block we can therefore safely assume, that the full defining expression must 
exist in some previously traversed block. Therefore, introducing the following
state in the SSAConverter will suffice to resolve any variable usage to a 
defining expression:
- A mapping from a block to their predecessors. This mapping is established when
we encounter an instruction that branches from one block into another. To achieve
this, we need to call out to the Linearizer when encountering such instructions.
- The information about a basic block needs to be extended to hold information
under what condition a block is traversed.

The action on encountering an assignment to a variable remains the same as above.
When reading a variable, that has no defining expression in the current basic
block, we do the following:
- If the basic block only has one predecessor, use the current definition
of the source variable of that block
- If there is more than one predecessor, use the conditional information tracked
to construct a $\Phi$ function selecting the correct upstream value of the variable.
use this $\Phi$ function as the current defining expression of the variable.

Overall this approach will result in the following translation behaviour:

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
let x_2 == (x_0 + 3) in
let y_0 == ((x_0 == 1) ? x_1 : x_2) in
y_0
```
Note, that the ternary condition results from the if condition. That is, if the 
if_condition is true, we use x_1, otherwise we use x_2.

## Partial operations problem
Consider the following example:
```kotlin
@Pure
fun safeDivide(val x: Int, val y: Int): Int {
    var res = 0
    if (y != 0) {
        res = x / y
    } else {
        res = -1
    }
    return res
}
```
using the above, this translates to:
```viper
function safeDivide(x: Int, y: Int): Int {
  let res_0 == (0) in
  let res_1 == (x / y) in
  let res_2 == (-1) in
  let res_3 == ((y != 0) ? res_1 : res_2) in
    res_3
}
```
This code will not verify because y might be 0, and Viper will attempt to verify the division x / y
 unconditionally. Therefore, for partial operations like division, we must lift the ternary check 
 directly into the corresponding variable definitions. A resulting translation might look like the 
 following:
```viper
function safeDivide(x: Int, y: Int): Int {
  let res_0 == (0) in
  let res_1 == ((y != 0) ? x / y : res_0) in
  let res_2 == (-1) in
  let res_3 == ((y != 0) ? res_1 : res_2) in
    res_3
}
```
Note: It is still to be determined, if we can identify partial operations. If not, we can
lift the ternary check directly into the variable definition regardless of the operation
that is being performed.