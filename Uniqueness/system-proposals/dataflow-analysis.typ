#title("Uniqueness Data-Flow Analysis")

= Uniqueness Type Lattice
<uniqueness-type-lattice>
Uniqueness types describe the constraints on a path at every point in the execution of the control-flow graph:

- if the path is #emph[unique] no other alias must exist, whereas if it is #emph[shared] it may be aliased;

- if the path is #emph[local] we must ensure that it is not aliased further by the current function, if it is #emph[global] we can assign it elsewhere.

Additionally the lattice contains a top element #emph[moved] that denotes a unique path which has been moved, and hence cannot be used.

Formally, we denote the set of types as:
#let unique = $mono("U")$
#let shared = $mono("S")$
#let global = $mono("G")$
#let local = $mono("L")$
#let moved = $mono("M")$
$ 
& "Type" = {\
& quad ((unique)"nique", (global)"obal"), ((unique)"nique", (local)"ocal"), \
& quad ((shared)"hared", (global)"obal"), ((shared)"hared", (local)"ocal"), \
& quad (moved)"oved"\
& } 
$

The partial order $subset.eq$ is defined by the following relations (all transitive closures are implied):
$ 
(unique, global) & subset.eq (unique, local) \
(shared, global) & subset.eq (shared, local) \
(unique, global) & subset.eq (shared, global) \
(unique, local) & subset.eq (shared, local) \
(shared, local) & subset.eq moved 
$

The greatest lower bound (meet) $inter$ and least upper bound (join) $union.sq$ are derived from this order.

= Type Environment
<type-environment>
#let Env = $cal(U)$
A type environment $Env$ is a partial map from paths to types:
#let Path = $italic("Path")$
#let Type = $italic("Type")$
$ 
Env : Path -> Type
$
We write $Env[x]$ for the type of path $x$ in $Env$, and $Env[x |-> t]$ for the environment that agrees with $Env$ except at $x$, where it maps to $t$.

= Environment Initialization
<environment-initialization>
The initial environment $Env$ flowing through each intermediate statement will be the empty environment $nothing$. The environment flowing through the first statement $Env_0$ should reflect the method's parameters' specifications. For example, for the following method declaration:
```kotlin
fun m(unique Ref x, unique local Ref y)
```
The flow object for the starting statement will be
$ 
Env_0 = { x |-> (unique, global), y |-> (unique, local) } 
$

= Data-Flow Equations
<data-flow-equations>
#let Envin = $Env_("in")$
#let Envout = $Env_("out")$
For every statement $s$ we define the #emph[incoming] environment $Envin(s)$ and the #emph[outgoing] environment $Envout(s)$ satisfying the data-flow equations: 

#let transfer = $italic("transfer")$
#let pred = $italic("predecessors")$
#let join = $italic("join")$
$
Envout(s) &= transfer(s) quad \
Envin(s) &= join(pred(s))
$
where $pred(s)$ is the set of control-flow predecessors of $s$; the function $transfer(s)$ defines the effect of each kind of statement; the function $join({p_1,...,p_n})$ combines the outgoing environments of all predecessors into a single environment that will be the incoming environment of $s$.

== Transfer Function
<sec:transfer>
The $transfer(s)$ function describes how the execution of a single statement modifies the output environment $Envout$ in relation to the input environment $Envin$.

#let hole = $cal(E)$
#let type = $italic("type")$
#let default = $italic("default")$
#let restore = $italic("restore")$
$
transfer(y : (unique, global) = hole[x]) & = Envin[x |-> moved, y |-> default(y)] \ 
transfer(y : (unique, local) = hole[x]) & = Envin[x |-> moved, y |-> default(y)] \ 
transfer(y : (shared, global) = hole[x]) & = Envin[y |-> default(y)] \ 
transfer(y : (shared, local) = hole[x]) & = Envin[x |-> moved, y |-> default(y)] \ 
transfer("enter" f(... hole[x] : (unique, global) ...)) & = Envin[x |-> moved] \ 
transfer("enter" f(... hole[x] : (unique, local) ...)) & = Envin[x |-> moved] \ 
transfer("enter" f(... hole[x] : (shared, global) ...)) & = Envin \ 
transfer("enter" f(... hole[x] : (shared, local) ...)) & = Envin[x |-> moved] \ 
transfer("exit" f(... hole[x] ...)) & = Envin[x |-> default(x)] \ 
$

The $default$ function retrieves the default uniqueness type for a particular path. The evaluation context hole (denoted $hole$) abstracts over the surrounding expression, allowing us to specify the effect of evaluating a particular path $x$ at a specific value position (e.g. on the right‑hand side of an assignment) without detailing the full expression, because the uniqueness transformation depends only on the kind of operation and the type annotations of the involved paths.

== Join of Predecessor Environments
<sec:join>
Let $P = { p_1, p_2, ..., p_n }$ be the list of all predecessors of a statement $s$. The function $join(P)$ combines the output environment of each predecessor point-wise by taking the meet (greatest lower bound) of the types for each path. If a path does not appear in some predecessor, it is assumed to be absent (which we treat as not contributing any constraint). The join is computed by iteratively inserting each predecessor environment into an accumulating result.

#let merge = $italic("merge")$
$ 
join(nothing) & = {} \
join(p dot P) & = merge(Envout(p), join(P))
$

The auxiliary function $merge(Env_1, Env_2)$ merges the bindings of $Env_2$ into $Env_1$. For each binding $x |-> t$ in $Env_2$, if $x$ is already in $Env_1$ we replace its type by the meet of the existing type and $t$; otherwise we simply add $x |-> t$ to the accumulated result $Env_1$.

#let domain = $italic("domain")$
$ 
merge(Env_1, nothing) & = Env_1 \
merge(Env_1, (x |-> t) dot Env_2) & = cases(
  merge(Env_1[x |-> (t inter Env_2[x])], Env_2) & "if" x in domain(R), 
  merge(Env_1[x |-> t], Env_2) & "otherwise"
) 
$

