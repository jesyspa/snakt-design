# Converting an `ExpEmbedding` into SSA Form

When converting a pure Kotlin function into a Viper function, we must
translate the function body into a single expression. This is realized as a
chain of `let` bindings. In these bindings, variable reassignments cannot
occur. We therefore need to translate the code into Static Single Assignment
(SSA) form to avoid variable reassignments.

## Theoretical Background

The most fundamental algorithm for translating a program into SSA form is
described by Cytron et al. [1].

However, this algorithm relies on the availability of a Program's Control
Flow Graph (CFG), which is not the case for SnaKt. We will therefore
implement an adaptation of the algorithm working on AST nodes, developed by
Braun et al. [2]. In the following, we will discuss the state introduced
for this adaptation as well as the mechanics of the overall algorithm.

## Introduced State

### `SSAVariableName` and `SSAAssignment`

To uniquely identify assignments, we introduce the `SSAVariableName`. This
name is a combination of the original source variable name and a unique
index. For every new assignment encountered, we create a new
`SSAVariableName` with a unique index. An `SSAAssignment` is defined as a
pair consisting of an `SSAVariableName` and the expression defining that
specific version of the source variable.

### SSA-Graph

In the AST representation used by Braun et al., a block is a sequence of
statements [2]. That is, a block only contains linear code. This is not true
in SnaKt. In SnaKt, a block is a sequence of `ExpEmbedding`s, which
may contain—among other things—branching embeddings. The main challenge we
have to overcome is bridging the gap between the SnaKt representation of a
block and the paper's representation.

We hence introduce a graph topology similar to the AST representation
required by Braun et al. There are three types of nodes in this graph:

- `SSAStartNode`: Represents the start of the graph.
- `SSABlockNode`: Represents a block of linear code. This node maintains
  a reference to its predecessor, the full condition that must be met for
  this node to be encountered, and a mapping from source variable names to
  `SSAVariableName`s to identify the latest valid version of a
  source variable at this block.
- `SSAJoinNode`: Represents a control-flow join in the graph. This node
  maintains references to its left and right predecessors, a lookup cache,
  and a local branching condition. This condition is necessary for control
  flow to reach this node from its left predecessor.

### `SSAConverter`

The `SSAConverter` stores a reference to an `SSABlockNode` responsible for
translating statements in the current block of code.

Additionally, it is responsible for creating the resulting chain of `let`
bindings after the whole function body is traversed. It therefore,
stores a list of `SSAAssignment`s and a list of pairs consisting of
return expressions and the full conditions required for control flow to
reach those returns. Note that since the conditions are not mutually exclusive,
the order of the list is relevant.

## Actions While Traversing an `ExpEmbedding`

While traversing an `ExpEmbedding`, the following cases are relevant for the
SSA conversion:

### Encountering an Assignment

When an assignment to a source variable is encountered, the `SSAConverter`:
1. Delegates to the current `SSABlockNode` to update its map from source
   variable names to `SSAVariableName`s to hold a fresh `SSAVariableName` for
   the source variable on the left side of the assignment.
2. Adds an `SSAAssignment` consisting of the new `SSAVariableName` and the
   right side of the assignment as its defining expression.

### Encountering a Variable Usage

When a variable is used in an expression, we need to resolve the source variable
name to the `SSAVariableName` that holds the current defining expression
for the source variable, so that we can substitute this name into the
variable usage. To do so, the `SSAConverter` looks up the `SSAVariableName` 
via the current `SSABlockNode`.

Analogous to the algorithm by Braun et al. the `SSABlockNode` finds the name as follows:
- If it has a mapping for the source variable, that version is returned.
- Otherwise, it looks up the name in its predecessor.

If the search reaches an `SSAJoinNode`, the node performs the following:
- If it has an `SSAVariableName` for the source variable in its cache, it
  returns it.
- Otherwise, it looks up the name in both its predecessors. If both
  predecessors agree on the name (i.e., they return the same
  `SSAVariableName`), that name is returned. Otherwise, the `SSAJoinNode`
  delegates to the `SSAConverter` to create a new `SSAAssignment` where the
  defining expression is a ternary expression. This expression selects the
  value from the left predecessor if the local branching condition is met,
  and otherwise selects the value from the right predecessor. This new
  variable name is then cached at the node for future lookups.

If the search reaches the `SSAStartNode`, it returns the original name being
searched for. This serves as a fallback to the source variable name if no
`SSAAssignment` can be found.

### Encountering a Branch

When encountering a branch (namely, an `IfEmbedding`), the `SSAConverter`
does the following:

1. Creates a new `SSABlockNode` for each branch to handle the translation.
2. Initiates translation of each branch with these `SSABlockNode` instances
   as the head nodes.
3. Creates an `SSAJoinNode` to join both of the newly created `SSABlockNode`
   branches.
4. Creates another `SSABlockNode` succeeding the `SSAJoinNode` to translate
   anything following the branch.

## After the Function Body is Traversed

After the whole function body is traversed, the `SSAConverter` is called to
construct the resulting chain of `let` bindings. To do this, all collected
return expressions are first folded into a single return expression.
Specifically, the single return expression is a (potentially nested) ternary
expression: If the condition for the first return expression is met, it
resolves to that expression; if the condition for the second is met (and not
the first), it resolves to the second, and so on.

With this expression constructed, the collected `SSAAssignment`s are
folded into a chain of `let` bindings, where the outermost `let` binding
holds the first assignment, the second outermost `let` binding holds the
second assignment etc. Consequently, the innermost `let` binding holds the last
assignment, with the previously constructed return expression as its body.
This overall expression is then returned as the function's body.

## A Note on Side-Effects

Consider the following Kotlin example:

```kotlin
var x = 1
x = x + run {x = x + 2; x} + run {x = x + 3; x}
```

While at first glance those expressions and their side-effect in current
scope may cause issues, we can check that as long as we traverse the
expression in the program order it is being evaluated in, we will construct
the assignments one after the other and use the correct definition
accordingly.

## Literature
[1] Cytron, R.; Ferrante, J.; Rosen, B. K.; Wegman, M. N.; Zadeck, F. K.(1991). [Efficientlycomputing static single assignment form and the controldependence graph](https://www.cs.utexas.edu/~pingali/CS380C/2010/papers/ssaCytron.pdf)

[2] Braun, M.; Buchwald, S.; Hack, S.; Leißa, R.; Mallon, C.; Zwinkau, A.(2013). [Simple and Efficient Construction of Static Single Assignment Form](https://c9x.me/compile/bib/braun13cc.pdf)