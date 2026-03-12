#title("Uniqueness Data-Flow Analysis")

= Syntax Definition
<syntax>

We assume to be operating on a standard Kotlin CFG as provided by:
```kotlin
package org.jetbrains.kotlin.fir.resolve.dfa.cfg
```
Any program-level syntax reported in the following sections has a correspondent `CFGNode<*>` class within this package.

== Paths
<paths>
Paths are syntactical units representing variable locations and field locations. The syntax can be described as a list of symbols:
#let Symbol = $italic("Symbol")$
#let Path = $italic("Path")$
#let path = $cal("path")$
$
Symbol & ::= x | y | z | ... \
Path path & ::= Symbol | Symbol . Path
$
A component of the path can be any name that is not already used by the language. A single-component path represents a local variable, while a multiple-components path represents a field access.
#let subpaths = $italic("subpaths")$
We use the function $subpaths(path)$ to retrieve the subcomponents of a path.

== Uniqueness Types
<uniqueness-type-lattice>
#let UniqueLevel = $italic("Unique-Level")$
#let ulevel
#let BorrowLevel = $italic("Borrow-Level")$
#let blevel
Uniqueness types describe the constraints on the shareability of a path at any given point in the execution of the control-flow graph. Informally, the uniqueness of a path is characterized by:
/ The aliasing status of the path : described by $UniqueLevel$. If a path is #emph[unique] no other alias of that path can exist. If a path is #emph[shared] it may have been aliased by another path. 
/ The ability to alias the path : described by $BorrowLevel$. If a path is #emph[local] it cannot be aliased further outside of the current function. If a path is #emph[global] it may be assigned elsewhere.

Additionally the type lattice contains a top element #emph[moved] that denotes a unique path which has been moved to another path. After a unique path has been moved (assigned) to a unique variable. it can no longer be used or aliased, enforcing the invariant of the second variable.

We denote the set of possible types of a path as:
#let Type = $italic("Type")$
#let type = $cal(t)$
#let unique = $mono("U")$
#let shared = $mono("S")$
#let global = $mono("G")$
#let local = $mono("L")$
#let moved = $mono("M")$
$ 
Type & ::= (UniqueLevel, BorrowLevel) | (moved)"oved" \
UniqueLevel & ::= (unique)"nique" | (shared)"hared" \
BorrowLevel & ::= (global)"lobal" | (local)"ocal"
$

The partial order $subset.eq$ is defined by the following relations:
$ 
(unique, global) & subset.eq (unique, local) \
(shared, global) & subset.eq (shared, local) \
(unique, global) & subset.eq (shared, global) \
(unique, local) & subset.eq (shared, local) \
(shared, local) & subset.eq moved 
$

The transitive closure of $subset.eq$, the greatest lower bound (meet) $inter$, and least upper bound (join) $union$ follow from this order.

#let default = $italic("default")$

== Control-Flow Nodes
We assume to be operating on a generic Kotlin control-flow graph representing the body of a function declaration.
#let fun = $mono("fun")$
#let successors = $italic("successors")$
#let predecessors = $italic("predecessors")$
Every node $n$ of the graph has a set of $successors(n)$ representing the nodes that execute immediately after $n$, as well as a set $predecessors(n)$ representing the set of nodes executing immediately before $n$. To designate a node in the control-flow graph we will use the high-level expressions and statements to which it corresponds. The constructs that are relevant to this analysis are the following:
#let Declaration = $italic("Declaration")$
#let Expression = $italic("Expression")$
#let Statement = $italic("Statement")$
#let Call = $italic("Call")$
#let CallTail = $italic("Call-Tail")$
#let Assignment = $italic("Assignment")$
#let Parameter = $italic("Parameter")$
$
Declaration & ::= fun Path( Parameter... ) { Statement... } \
Parameter & ::= Path: Type \
Expression & ::= Path | Call | * \
Statement & ::= Assignment | Call | * \
Call & ::= Path(Expression...) \
Assignment & ::= Path = Expression
$

=== Evaluation Context

#let hole = $cal(E)$
Note that for each statement and expression in the program there may be multiple control-flow nodes. To enable a finer-grained description of the current execution step we rely on the notion of evaluation hole denoted as $hole$. A hole pattern takes as input a pattern matching the expression that is currently being evaluated using the form $hole[Expression]$. This pattern allow us to match control-flow nodes while also referencing the context. For example, consider the assignment:
$
v = m(f(x, y, z))
$
For this statement, the pattern $v = hole[Expression]$ matches the following control-flow nodes:
$
v = hole[x] -> v = hole[y] -> v = hole[z] -> v = hole[f(x, y, z)] -> v = hole[m(f(x, y, z))]
$

== Uniqueness Typing Environment
<type-environment>
#let Env = $cal(U)$
A type environment $Env$ is a partial map from paths to types:
$ 
Env : Path -> Type
$
/ To read an element of the environment: we write $Env[x]$ for retrieving the type of path $x$ in $Env$. 
/ To update an element of the environment : we write $Env[x |-> t]$, which produces a copy of the environment $Env$ associating the path $x$ to type $t$. 

Assigning a parent path to $moved$ automatically moves the $subpaths$ as well, maintaining the property:
$
Env[x] = moved => Env[x...f] = moved "for" x...f in subpaths(x)
$

= Data-Flow Equations
<data-flow-equations>
#let Envin = $Env_("in")$
#let Envout = $Env_("out")$
For every statement $s$ we define the #emph[incoming] environment $Envin(s)$ and the #emph[outgoing] environment $Envout(s)$ satisfying the data-flow equations: 

#let transfer = $italic("transfer")$
#let join = $italic("join")$
$
Envout(n) &= transfer(n) quad \
Envin(n) &= join(predecessors(n))
$
where:
- The $transfer(n)$ function defines the effect of each kind of statement; 
- The $join({p_1,...,p_n})$ function combines the outgoing environments of all predecessors into a single environment that will be the incoming environment of $s$.

== Environment Initialization
<environment-initialization>
The initial environment $Env$ flowing through each intermediate statement will be the empty environment $nothing$. The environment flowing through the first statement $Env_0$ should reflect the method's parameters' specifications. For example, for the following method declaration:
```kotlin
fun m(unique Ref x, unique local Ref y)
```
The flow object for the starting statement will be
$ 
Env_0 = {x |-> (unique, global), y |-> (unique, local)} 
$

== Transfer Function
<sec:transfer>
The $transfer(s)$ function describes how the execution of a single statement modifies the output environment $Envout$ in relation to the input environment $Envin$ with the following rules:
#let type = $italic("type")$
#let reroot = $italic("reroot")$
#let var = $italic("var")$
$
transfer(n) = Envin \
transfer(y  = hole[x : (unique, \_)]) & = Envin[x |-> moved] union {y.f |-> Envin[x...f] | x...f in subpaths(x)} \
transfer(y = \_) & = Envin[y |-> default(y)] \
transfer("enter" f(... hole[x : (unique, \_)] ...)) & = Envin[x |-> moved] \ 
transfer("exit" f(... hole[x] ...)) & = Envin[x |-> default(x)] \
$
where:
- The pattern $x : t$ matches a path $x$ that satisfies the uniqueness type $t$.

== Join of Predecessor Environments
<sec:join>
Let $P = { p_1, p_2, ..., p_n }$ be the list of all predecessors of a statement $s$. The function $join(P)$ combines the output environment of each predecessor point-wise by taking the meet (greatest lower bound) of the types for each path. If a path does not appear in some predecessor, it is assumed to be absent (which we treat as not contributing any constraint). The join is computed by iteratively inserting each predecessor environment into an accumulating result.

#let merge = $italic("merge")$
transfer(node) = envin \
transfer(path_1  = hole[path_2 : (unique, blevel)]) & = envin[path_2 |-> moved] union {path_1 . path_3 |-> envin[path_2 . path_3] | path_3 in subpaths(path_2)} \
transfer(path_1 = expression) & = envin[path_2 |-> default(path_1)] \
// TODO: Clarify "enter" and "exit"
transfer("enter" f(expression ... hole[path_1 : (unique, \_)] expression ...)) & = envin[path_1 |-> moved] \ 
transfer("exit" f(expression ... hole[path_1] expression ...)) & = envin[path_2 |-> default(x)] \
The auxiliary function $merge(Env_1, Env_2)$ merges the bindings of $Env_2$ into $Env_1$. For each binding $x |-> t$ in $Env_2$, if $x$ is already in $Env_1$ we replace its type by the meet of the existing type and $t$; otherwise we simply add $x |-> t$ to the accumulated result $Env_1$.

#let domain = $italic("domain")$
$ 
merge(Env_1, nothing) & = Env_1 \
merge(Env_1, (x |-> t) dot Env_2) & = cases(
  merge(Env_1[x |-> (t inter Env_2[x])], Env_2) & "if" x in domain(R), 
  merge(Env_1[x |-> t], Env_2) & "otherwise"
) 
$

