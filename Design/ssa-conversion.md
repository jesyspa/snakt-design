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

To explain our adaption of this algorithm further, we will follow the structure
in the paper. First we will explain how to translate a single AST block into SSA
form and then elaborate on how we can extend this to an arbitrary program.

## SnaKt block vs. AST block

In the following explanations we will distinct between two types of blocks:
1. The SnaKt block, where we mean the block ExpEmbedding in SnaKt containing
a sequence of embeddings
2. The AST block, where we mean the basic block in a program containing a sequence
of statements adhering to the definition in the paper (and in literature in general)

## Translating an AST block into SSA form

Adapting the approach from the paper we will do the following while traversing
an AST block:

- Maintain a mapping from source variables to a list of defining expressions:
The last expression in this list represents the most recent defining expression
we encountered for that source variable, the one before-hand the 2nd most recent
and so on. For each of those defining expressions for a source variable $x$, we 
will introduce a let binding, binding from  $x_i$ (where i is the index of the 
definition in the list) to the expression.
- When encountering a variable read, we substitute $x_i$, where i is the most recent
index in the above described list, as the variable that is being read from,
s. t. the most recent encountered version of the variable is read
- When encountering a variable assignment, we update the list to hold the 
RHS of the assignment as the latest encountered defining expression

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

### Implmentation details
- The state will be held in the SSAConverter
- Upon variable reads and assignments control-flow will be passed to the PureLinearizer.

## What about multiple AST blocks

The problem we are facing while employing the algorithm from the paper in SnaKt
is that SnaKt blocks differ from AST blocks. We can get around this by doing
the following:

Whenever we traverse an embedding, that branches into another AST block, we make
note of the topology of the AST (that is what new blocks exist and under what
conditions we branch into those). We then translate each of those AST blocks as
described above and as described in the paper (inserting $\Phi$ functions when
joining two AST blocks and if necessary).

Overall this will result in the following translation behaviour:

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

### Implementation details
- The AST blocks and the corresponding topology will be maintained in the SSAConverter
- Control-flow will be passed to the linearizer upon encountering embeddings, that
create new AST blocks

### A note on previously defined variables
As we are constructing the whole AST topology (in the sense of the paper) on the fly
and as we are for now assuming no backwards edges in the CFG, we can search in the
variable mappings of preceding AST blocks to find the value of an undefined variable
in the current AST block. If at a later stage we are allowing backwards edges in the
CFG of our program we have to introduce lazily evaluated phi functions as described
in the paper.

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