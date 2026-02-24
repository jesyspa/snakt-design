#title("Uniqueness Data-Flow Analysis")

This document defines a forward, intra-procedural data-flow analysis for uniqueness over Kotlin FIR control-flow graphs.  At each control-flow node, the analysis tracks an abstract environment mapping paths to uniqueness facts. A fact records whether the path is `unique` or `shared`, whether it is `local` to the current function or may escape the current function, and whether the path has been `moved`.

= Syntax Definition
<syntax>

We assume we are operating on the standard Kotlin FIR CFG nodes defined in:

```kotlin
package org.jetbrains.kotlin.fir.resolve.dfa.cfg
```

The syntax described below is an abstract syntax for the CFG shapes relevant to this analysis.

== Paths
<paths>

Paths are syntactic units representing variable locations and field locations. The syntax can be described as a list of symbols:

#let Path = $italic("Path")$
#let Symbol = $italic("Symbol")$
#let path = $p$
$
    Symbol & ::= x | y | z | ... \
    Path path & ::= Symbol | Symbol . Path
$

A single-component path represents a local variable, while a multi-component path represents a field access.

#let subpaths = $italic("subpaths")$

For a path $path$, the set $subpaths(path)$ contains $path$ itself together with every descendant field path rooted at $path$.

== Uniqueness Types
<uniqueness-type-lattice>

#let BorrowLevel = $italic("Borrow-Level")$
#let UniqueLevel = $italic("Unique-Level")$
#let blevel = $b$
#let ulevel = $u$

Uniqueness types describe the aliasing constraints known for a path at a given CFG point. A usable path has two components:
/ The aliasing status of the path: described by $UniqueLevel$. A path is #emph[unique] if no other accessible alias of that path may exist. A path is #emph[shared] if aliases may exist.
/ The locality of the path: described by $BorrowLevel$. A path is #emph[local] if it may not be aliased outside the current dynamic scope. A path is #emph[global] if it may escape the dynamic scope.

Additionally, the lattice contains a distinguished element #emph[moved]. This denotes a path that is temporarily or permanently unavailable because its unique value has been moved away or is inaccessible during a borrow. The set of possible abstract values is:

#let Type = $italic("Type")$
#let type = $t$
#let global = $mono("G")$
#let local = $mono("L")$
#let moved = $mono("M")$
#let shared = $mono("S")$
#let unique = $mono("U")$
$
    Type type & ::= (UniqueLevel, BorrowLevel) | moved \
    BorrowLevel blevel & ::= global | local \
    UniqueLevel ulevel & ::= unique | shared
$

The partial order $subset.eq$ is defined by the following relations:
$
    (unique, global) & subset.eq (unique, local) \
    (shared, global) & subset.eq (shared, local) \
    (unique, global) & subset.eq (shared, global) \
    (unique, local) & subset.eq (shared, local) \
    (shared, local) & subset.eq moved
$

The transitive closure of $subset.eq$, together with the induced greatest lower bound (meet) $inter$ and least upper bound (join) $union$, provides the lattice used by the analysis.

== Control-Flow Nodes

We assume we are operating on a generic Kotlin control-flow graph representing the body of a function declaration.

#let fun = $mono("fun")$
#let node = $n$
#let predecessors = $italic("predecessors")$
#let successors = $italic("successors")$

Every node $node$ of the graph has a set $successors(node)$ of immediate successor nodes and a set $predecessors(node)$ of immediate predecessor nodes. We designate nodes using the expressions and statements to which they correspond. The syntax relevant to this analysis is the following:

#let Assignment = $italic("Assignment")$
#let Call = $italic("Call")$
#let Declaration = $italic("Declaration")$
#let Expression = $italic("Expression")$
#let Node = $italic("Node")$
#let Parameter = $italic("Parameter")$
#let Statement = $italic("Statement")$
#let expression = $e$
$
    Node node & ::= Declaration | Parameter | Expression | Statement | Call | Assignment | * \
    Declaration & ::= fun Path( Parameter ... ) { Statement ... } | * \
    Parameter & ::= Path: Type \
    Expression expression & ::= Path | Call | * \
    Statement & ::= Assignment | Call | * \
    Call & ::= Path(Expression ...) \
    Assignment & ::= Path = Expression
$

Other CFG constructs, including branches and loops, are handled through the predecessor and successor relation of the underlying CFG together with the join operator defined below.

== Evaluation Context

#let hole = $cal("E")$
Each source-level statement or expression may correspond to multiple CFG nodes. To describe the exact evaluation point, we use an evaluation hole denoted by $hole$. A hole pattern is written as $hole[Expression]$ and matches the subexpression currently being evaluated while preserving its surrounding context. For example, consider the assignment:
$
    v = m(f(x, y, z))
$

The pattern $v = hole[expression]$ matches the following CFG nodes in dominance order:
$
    v = hole[x] -> v = hole[y] -> v = hole[z] -> v = hole[f(x, y, z)] -> v = hole[m(f(x, y, z))]
$

Evaluation holes can also specify the expected abstract type of the inner expression using the $:$ operator. For example,
$
    v = hole[expression : type]
$

only binds $expression$ if the analysis currently classifies it with abstract value $type$.

== Uniqueness Typing Environment
<type-environment>

#let env = $cal("U")$

A typing environment $env$ is a partial map from paths to abstract values:
$
    env : Path -> Type
$

/ To read: the value associated with a path $path_1$, we write $env[path_1]$.
/ To update: a path $path_1$ to abstract value $type_1$, we write $env[path_1 |-> type_1]$.
/ To remove: an explicit binding for $path_1$, we write $env without path_1$.

#let copy = $italic("copy")$
In addition to the basic operations, we adopt the shorthand $copy(env, path_1, path_2)$ to copy every explicit binding rooted at $path_2$ to the corresponding path rooted at $path_1$.

#let default = $italic("default")$
#let domain = $italic("domain")$
If a path $path_1$ is not explicitly present in $env$, the analysis falls back to its declared abstract type:
$
    env[path_1] = default(path_1) "if" path_1 in.not domain(env)
$

Here, $default(path)$ denotes the abstract value implied by the declaration of $path$.

The environment must satisfy one additional consistency condition: if a path is $moved$, then all of its descendant paths are also $moved$. Formally, for any path $path_1$ and any path $path_2 in subpaths(path_1)$, we require:
$
    env[path_1] = moved => env[path_2] = moved
$

= Data-Flow Equations
<data-flow-equations>

#let envin = $env_("in")$
#let envout = $env_("out")$
For every CFG node $node$, we define an incoming environment $envin(node)$ and an outgoing environment $envout(node)$:

#let join = $italic("join")$
$
    envin(node) &= join(predecessors(node))
$

The distinguished entry node is treated separately in the initialization section below. For every non-entry node, $join(predecessors(node))$ combines the outgoing environments of its predecessors into a single incoming environment. The outgoing environment is then determined by the pattern-matching rules in the next section.

= Environment Initialization
<environment-initialization>

#let entry = $node_0$
Let $entry$ be the entry node of the function body. The environment flowing into $entry$ is the parameter environment $env_0$, derived from the declared annotations of the function's parameters. For example, for the declaration
```kotlin
fun m(unique Ref x, unique local Ref y)
```

the entry environment is
$
    env_0 = {x |-> (unique, global), y |-> (unique, local)}
$
and we define
$
    envin(entry) = env_0
$

All later environments are derived from the transfer and join rules.

== Transfer Rules
<sec:transfer>

The outgoing environment of a node is defined by the following pattern-matching rules. For the sake of brevity, let $envin$ represent the input typing environment of the statement on the left-hand side of the rule.
$
    envout(path_1 = hole[path_2 : (unique, blevel)]) &=
      copy(envin, path_1, path_2)[path_2 |-> moved] \
    envout(path_1 = expression) &=
      envin without path_1 \
    envout("enter" f(expression ... hole[path_1 : (unique, local)] expression ...)) &=
      envin[path_1 |-> moved] \
    envout("exit" f(expression ... hole[path_1 : (unique, local)] expression ...)) &=
      envin without path_1 \
    envout("enter" f(expression ... hole[path_1 : (unique, global)] expression ...)) &=
      envin[path_1 |-> moved] \
    envout(node) &=
      envin(node)
$

If a call contains multiple unique arguments, the call-entry and call-exit rules are applied independently to each matching argument position.

== Join of Predecessor Environments
<sec:join>
#let npreds = $cal("P")$
Let $npreds = predecessors(node)$ be the list of predecessor nodes of a CFG node $node$. The function $join(npreds)$ combines their outgoing environments pointwise. The empty join is the empty environment:
$
    join(nothing) = {}
$

#let merge = $italic("merge")$
For a non-empty predecessor list, $join$ folds a binary merge operator over predecessor environments:
$
    join(node_1 dot npreds) = merge(envout(node_1), join(npreds))
$

Where $merge$ is defined as:
$
    merge(env_1, {}) &=
      env_1 \
    merge(env_1, {path_1 |-> type_1} union env_2) &=
      merge(env_1[path_1 |-> (env_1[path_1] union type_1)], env_2) "if" path_1 in domain(env_1) \
    merge(env_1, {path_1 |-> type_1} union env_2) &=
      merge(env_1[path_1 |-> type_1], env_2)
$

If a path appears in both environments, the merged environment keeps the meet of the two abstract values; if it appears in exactly one environment, that explicit binding is preserved. Paths absent from both environments remain absent and therefore fall back to
$default(path)$.
