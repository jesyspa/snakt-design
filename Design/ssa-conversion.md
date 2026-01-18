# Converting an ExpEmbedding into SSA form

When converting a pure Kotlin function into a Viper function, we have to translate
the program into a single expression. This is realised in a chain of let bindings.
In those, variable reassignments cannot occur. We therefore need to translate
the code into SSA form to avoid any reassigning that might happen.

## Theoretical background

The most fundamental algorithm for translating a program into SSA form is described
by Cyrton et al. [1].

However, this algorithm relies on the CFG of the program to be available, which
is not the case for SnaKt. We will therefore implement an adaptation of the algorithm
working on AST nodes, developed by Braun et al. [2]

## SnaKt block vs. AST block

In the AST representation used by Braun et al. a block is a sequence of statements [2].
That is, a block only contains linear code. This is not true in SnaKt. In SnaKt
a block is a sequence of ExpEmbeddings, which contain - among other things - also
branching embeddings. The main challenge we have to overcome therefore is to
bridge the gap between the SnaKt representation of a block and the paper's representation of a block.
In the following, we will call the SnaKt version a 'SnaKt block' and the Braun et al.
version an 'AST block'

## Local value numbering

Before converting our structure into one compatible with the paper's algorithm, 
let us first assume that we have a single AST block we can traverse in program order
and discuss any changes we have to make to the local value numbering algorithm [2]
to create something similar for SnaKt.

The key difference is that, as we are not swapping variables in place, but rather
track *all* assignments to construct a linear let chain out of potentially non-linear
code. We therefore need to maintain all assignments rather than only the 
most recent as the paper does. 

We will introduce the following:
- The SSAConverter maintains a list of assignments in its scope.
An assignment is a mapping between source variable and defining expression
- The last expression in this list mapping a source variable to a defining expression
represents the most recent defining expression we encountered for that source variable
in the SSAConverter's scope, the one before that the 2nd most recent and so on. 
- When encountering a variable assignment, we update the list to hold the 
RHS of the assignment as the latest encountered defining expression. Further, we give
this assignment a unique index. This index will be shared across SSAConverters such
that when we are constructing the overall expression, each assignment has a unique
per source variable index we can identify it by. In the resulting expression this
assignment will therefore be held by the variable $x_i$, where x denotes the source 
variable name and i the index of the assignment.
- With the above established when encountering a VariableEmbedding during translation
of some ExpEmbedding we can resolve its source variable to the name that will carry
the most recent definition in the resulting expression. 

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

In the above we have assumed linear code consisting of a single AST block. To
support any branching that might occur while translating an ExpEmbedding,
we will construct the same topology AST blocks have between SSAConverters.
To do so we will introduce the following for every SSAConverter:
- A list of preceding SSAConverters
- A list of succeeding SSAConverters

Consider an If-Embedding being translated. The PureLinearizer will modify
the relationships between SSAConverters, such that we have a 'diamond' shape.
Namely we will have the following SSAConverters:
- The current SSAConverter of the PureLinearizer will persist
- Two SSAConverters will be introduced to translate everything in the scope
of the branches (one for the then- and one for the 
else branch)
- One SSAConverter will be introduced representing a join node behind the
two branches

The current SSAConverter will have the two branch SSAConverters as its successors.
These will have the joining SSAConverter as their successor and the joining converter
will have any successor the current SSAConverter might have as its successor.
Predecessors will be established accordingly.

After this relationship between SSAConverters is established the delegating PureLinearizer
will initiate the translation of both the then and else branch. After that it will update its SSAConverter
to be the joining SSAConverter as this shall hold the variable definitions for any
assignments occurring after the branch. Note that as the PureLinearizer is being copied
with adjusted position information when a WithPosition-Embedding, which encapsulates
an If-Embedding, is traversed rather than updating the reference to the SSAConverter,
we will update an object holding the actual reference. This allows the change
to be propagated to the PureLinearizer object translating any statements after the branch.

For now, the implementation will restrict to the above case of an If-Embedding, only
introducing support for ```if``` and ```when``` Kotlin statements. However, as 
we are saving lists as predecessors and successors this approach can easily
be extended to support more complex control-flow constructs if necessary.

## Phi expressions

Consider a SSAConverter succeeding the then and else branch of an if statement.
Further imagine, that both branches modify a variable $x$. If in the scope of this
SSAConverter $x$ is being used, we must be able to resolve to either the name defined
in the then branch or the name of the else branch depending on previous control flow.
This can be achieved as follows:

Each SSAConverter holds a boolean expression under which it is being traversed. This condition
can be extracted from the if-statement upon constructing the topology between SSAConverters.
Note, that in the case of nested branching the innermost SSAConverter will only hold the condition
of the innermost if, the 2nd innermost only the condition of the 2nd innermost if and so on. 
We will call this condition local branching condition. As the created topology between
SSAConverters ensures that there is a joining converter present for any branching,
only storing the 'local' condition is sufficient (and makes the resulting expression cleaner).

For the above described case we can now collect the variable definitions for $x$ from
every preceding SSAConverter together with their local branching condition.
With this information we can construct a ternary expression selecting the
correct value of $x$ depending on the local branching conditions. We call this
resulting expression *phi expression*. 

## Resolving a variable to its definition

With a topology between SSAConverters as described above and the capability
to resolve variable names in local scope, we can now adapt the full algorithm
from Braun et al. [2] to resolve a variable name to the name in the resulting
expression holding its most recent definition:

```
def resolveVariableName(toResolve: VariableName):

    # Adapted local value numbering as described above
    if this SSAConverter holds a definition x for toResolve:
        return x

    # Adapted global value numbering
    else:
        resolveVariableNameRecursively(toResolve)
```
with:
```
def resolveVariableNameRecursively(toResolve: VariableName):

    # Sole predecessor must hold the corresponding definition
    if this SSAConverter only has one predecessor pre:
        return resolveVariableName(pre)

    # Multiple predecessors have definitions
    else:
        incomingNames := resolveVariableName(toResolve) for all predecessors
        phiExpression := phi expression selecting the correct name from all incoming names
        add an assignment of phiExpression to toResolve in this converter
        return the name holding this assignment
```

## (Early) returns
In our function we may have multiple return statements at any branch. We need to
construct a single return expression from these returns. Note, that the
SSAConverter in scope of the branch of the return expression will hold this expression as its body.
To construct the overall expression, we will consider the global branching condition
of an SSAConverter. That is in the case of nested branching the global branching condition -
contrary to the local branching condition - will hold the conjunction of all conditions
that need to be satisfied for control flow to reach this statement. We can then
construct an overall return expression by:

1. Creating a dependency graph traversal ordering of all SSAConverters
2. Collecting all return expressions and their global branching conditions in dependency order
3. Create a ternary expression that resolves to the first return expression
if the first global branching condition is met, to the second return expression if
the second global branching condition is met etc.

This will result in a single return expression we can use.

## Putting it all together

We now have a topology between SSAConverters holding variable names and their definitions
as well as an overall return expression.
To construct a single expression from this we can do the following:

1. Create a dependency graph traversal ordering of all SSAConverters
2. Collect all assignments in that ordering
3. Create a single chain of let bindings, where the outermost let-binding
holds the first assignment and the 2nd outermost let-binding as its body etc.
Consequently, the innermost let binding holds the last assignment and the
overall return expression as its body.

This will result in a single expression we can use in a Viper function.

## Literature
[1] Cytron, R.; Ferrante, J.; Rosen, B. K.; Wegman, M. N.; Zadeck, F. K. (1991). 
[Efficiently computing static single assignment form and the control dependence graph]
(https://www.cs.utexas.edu/~pingali/CS380C/2010/papers/ssaCytron.pdf)

[2] Braun, M.; Buchwald, S.; Hack, S.; Leißa, R.; Mallon, C.; Zwinkau, A. (2013). 
[Simple and Efficient Construction of Static Single Assignment Form]
(https://c9x.me/compile/bib/braun13cc.pdf)