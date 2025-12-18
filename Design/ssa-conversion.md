# Converting an ExpEmbedding into SSA form

When converting a pure Kotlin function into a Viper function, we have to translate
the program into a single expression. This is realised in a chain of let bindings.
In those, variable reassignments may not occur. We therefore need to translate
the code into SSA form to avoid any reassigning that might happen.

## Theoretical background

The most common algorithm for translating a program into SSA form is described
in a paper by Cryton et al. 

https://www.cs.utexas.edu/~pingali/CS380C/2010/papers/ssaCytron.pdf

However, this algorithm relies on the CFG of the program to be available, which
is not the case for SnaKt. We will therefore implement an adaption of the algorithm
working on AST nodes developed by Braun et al.:

https://c9x.me/compile/bib/braun13cc.pdf

## SnaKt block vs. AST block

In the AST representation used in the paper a block is a sequence of statements.
That is a block only contains linear code. This is not true in SnaKt. In SnaKt
a block is a sequence of ExpEmbeddings, which contain - among other things - also
branching embeddings. The main challenge we have to overcome therefore is to
use the SnaKt representation of a block as the paper's representation of a block.
In the following we will call the SnaKt version a SnaKt block and the paper's
version an AST block.

## Local value numbering

Before converting our structure into one, we can run the paper's algorithm on,
let's first assume that we have a single AST block we can traverse in program order
and discuss any changes we have to make to the paper's algorithm to use this
in SnaKt.

The key difference is, that as we are not swapping variables in place, but rather
track *all* assignments to construct a linear let chain out of potentially non
linear code. We therefore need to maintain all assignments rather than only the 
most recent as the paper does. 

Looking at the implementation we will introduce the following:
- The SSAConverter maintains a list of assignments. An assignment is a mapping
between source variable and defining expression
- The last expression in this list mapping a source variable to a defining expression
represents the most recent defining expression we encountered for that source variable, 
the one before-hand the 2nd most recent and so on. 
- When encountering a variable read, we substitute a variable holding the most
recent definition for that source variable into the expression
- When encountering a variable assignment, we update the list to hold the 
RHS of the assignment as the latest encountered defining expression

### A note on side-effects

Think of the following Kotlin example:

```kotlin
var x = 1
x = x + run {x = x + 2; x} + run {x = x + 3; x}
```

While at first glance those expressions and their side-effect in current scope
may cause issues, we can check that as long as we traverse the expression in 
the program order it is being evaluated in, we will construct the assignments
one after the other and use the correct definition accordingly.

## SnaKt block to AST block

To create a topology in the paper's sense the following state will be introduced
in the SSAConverter:
- A list of preceding SSAConverters
- A list of succeeding SSAConverters

As soon as a control flow embedding is traversed by the linearizer, the follwing
algorithm creates the desired topology:

```pseudo-code
def traverseControlFlowEmbedding(embedding):

    subblocks     <- list of subblocks in embedding (*)
    joinConverter <- SSAConverter(predecessors: {}, successors: this.ssaConverter.successors)
    newConverters <- {}

    for every subblock in subblocks:
        newConverters.add(SSAConverter(predecessors: this.ssaConverter, successors: joinConverter))

    joinConverter.predecessors <- newConverters
    this.ssaConverter.successors <- newConverters
    this.ssaConverter <- joinConverter

    for every subblock in subblocks:
        translate(linearizer: Linearizer(ssaConverter: newConverters[subblock]))
```
*(\*)* A subblock is any block the embedding has branches into (e.g. an if-embedding
has two subblocks - the then block and else block)

The resulting topology between SSAConverters is similar to the topology between
AST blocks. We can therefore directly use the global value numbering algorithm
described in the paper on this construct to convert into SSA form.

## Putting it all together

After the whole embedding is linearized we have a topology of SSAConverters
holding variable assignments in their scope. From this topology we can
construct the let chain by traversing the SSAConverters from the top-level
SSAConverter in dependency order (that is only traverse into one SSAConverter
if all its predecessors have already been traversed into). During this traversal
we can construct an ordered list of assignments, which we can then translate into
a let chain. A few cases need considering:

### Conditions

To distinct under what condition a variable assignment is valid (and to construct
the $\Phi$ functions mentioned in the paper) the SSAConverter will additionally
to the above also hold a 'branching predicate', which evaluates to true iff.
the subblock represented by the SSAConverter is being branched into.

### (Early) returns

To handle early returns each SSAConverter holds their return expression (currently
implemented as body, but should probably be renamed). In combination with the above
information on when a SSAConverter is being traversed into, we can construct
the overall return expression during the above mentioned dependency traversal by
combining each encountered return expression into one overarching ternary expression
that returns the expression from a subblock if their condition is met. If a SSAConverter
holds no return expression we do not need to integrate that case into the overarching
expression.