= Language Assumptions
<language-assumptions>
We start by showcasing how the analysis works on a three-address-code
representation where each statement can only operate on either locals or
paths (field dereferences). The statements on which we will focus for
this discussion are the following:

- $mono("var ") x$ representing a declaration of a local variable
  without initialiser.

- $mono("var ") x = y$ representing a declaration with initialization
  from another variable $y$.

- $x = y$ representing the assignment of $y$ (already initialized) to
  $x$.

- $x = mono("null")$ representing an assignment of `null` to $x$
  (literals are always atomic).

- $m \( overline(X) \)$ representing a call to a method $m$ with a list
  of arguments
  $overline(X) = { x_1 \, #h(0em) x_2 \, #h(0em) dots.h #h(0em) \, x_n }$.

- $x = m \( overline(X) \)$ representing a call to a method $m$ binding
  the result to $x$.

Other statement from the Kotlin languages are allowed for as long as
they operate exclusively on atomic path expressions, hence achieving a
three-address code form. For example, the statement:
$ mono("var ") x = f \( g \( x \) \, y \) $ Can be extracted into the
following sequence of three-address-code statements without compromising
execution semantics: $  & mono("var ") t_0 = g \( x \)\
 & mono("var ") x = f \( t_0 \, y \) $ Since in the actual
implementation will work on a Kotlin at the frontend level, it would
generally not be practical to transform the AST to three-address-code.
#link(<sec:supporting-aggregated-expressions>)[6] showcases an extension
of the analysis that would allow us to work with standard aggregated.

We denote by $italic(V a r)$ the set of local variables and by
$italic(P a t h)$ the set of paths that can be denoted in the program. A
path is either a local variable or a field access rooted at a local
variable (e.g. $x . f$). For simplicity we treat all paths as atomic in
the equations. Field accesses are handled by the same rules as
variables.

A method call carries additional information about each parameter:
whether the method #emph[borrows] the argument (i.e. does not take
ownership) or #emph[consumes] it (takes ownership). This information is
assumed to be given by the method signature.

= Uniqueness Type Lattice
<uniqueness-type-lattice>
Uniqueness types describe the precondition and postcondition constraints
of a path:

- if the path is #emph[unique] we assume that no other alias must exist,
  if it is #emph[shared] we assume that it may be an alias;

- if the path is #emph[borrowed] we must ensure that it is not aliased
  further by the current function, if it is #emph[unmanaged] we can
  assign it elsewhere.

Additionally the lattice contains a top element $sans("Moved")$ that
denotes a unique path which has been moved, and hence cannot be used.

Formally, we denote the set of types as:
$ italic(T y p e) = { \( sans("Unique") \, #h(0em) sans("Free") \) \, #h(0em) \( sans("Unique") \, #h(0em) sans("Borrowed") \) \, #h(0em) \( sans("Shared") \, #h(0em) sans("Free") \) \, #h(0em) \( sans("Shared") \, #h(0em) sans("Borrowed") \) \, #h(0em) sans("Moved") } . $
The partial order $subset.eq.sq$ is defined by the following relations
(all transitive closures are implied):
$  & \( sans("Unique") \, sans("Free") \) subset.eq.sq \( sans("Unique") \, sans("Borrowed") \) \, & #h(2em) & \( sans("Unique") \, sans("Free") \) subset.eq.sq \( sans("Shared") \, sans("Free") \) \,\
 & \( sans("Shared") \, sans("Free") \) subset.eq.sq \( sans("Shared") \, sans("Borrowed") \) \, & #h(2em) & \( sans("Unique") \, sans("Borrowed") \) subset.eq.sq \( sans("Shared") \, sans("Borrowed") \) \,\
 & \( sans("Shared") \, sans("Borrowed") \) subset.eq.sq sans("Moved") . $
The greatest lower bound (meet) $inter.sq$ and least upper bound (join)
$union.sq$ are derived from this order.

= Type Environment
<type-environment>
A type environment $cal(U)$ is a partial map from paths to types:
$ cal(U) : italic(P a t h) arrow.r italic(T y p e) . $ We write
$cal(U) \[ x \]$ for the type of path $x$ in $cal(U)$, and
$cal(U) \[ x arrow.r.bar t \]$ for the environment that agrees with
$cal(U)$ except at $x$, where it maps to $t$.

= Environment Initialization
<environment-initialization>
The initial environment $cal(U)$ flowing through each intermediate
statement will be the empty environment $nothing$. The environment
flowing through the first statement $cal(U)_0$ should reflect the
method's parameters' specifications. For example, for the following
method declaration:
$ mono("fun m(") sans("Unique") mono(" Ref ") x mono(", ") sans("Unique") #h(0em) sans("Borrowed") mono(" Ref ") y mono(") ") $
The flow object for the starting statement will be
$ cal(U)_0 = { x arrow.r.bar \( sans("Unique") \, #h(0em) sans("Free") \) \, #h(0em) y arrow.r.bar \( sans("Unique") \, #h(0em) sans("Borrowed") \) } $

= Data-Flow Equations
<data-flow-equations>
For every statement $s$ we define the #emph[incoming] environment
$cal(U)_(upright("in")) \( s \)$ and the #emph[outgoing] environment
$cal(U)_(upright("out")) \( s \)$ satisfying the data-flow equations:
$ cal(U)_(upright("out")) \( s \) = sans("traverse") \( s \) \, #h(2em) cal(U)_(upright("in")) \( s \) = sans("join") #scale(x: 120%, y: 120%)[\(] sans("pred") \( s \) #scale(x: 120%, y: 120%)[\)] \, $
where $sans("pred") \( s \)$ is the set of control-flow predecessors of
$s$; the function $sans("traverse")$ defines the effect of each kind of
statement; the function $sans("join")$ combines the outgoing
environments of all predecessors into a single environment that will be
the incoming environment of $s$.

== Traverse Function
<sec:traverse>
The $sans("traverse")$ function describes how the execution of a single
statement modifies the output environment $cal(U)_(upright("out"))$ in
relation to the input environment $cal(U)_(upright("in"))$.

$
"traverse"(mono("var ") x) &= cal(U)_"in"(s)[x |-> "Moved"] \
"traverse"(x = y) &= cases(
  cal(U)_"in"(s)[x |-> ("Unique", "Borrowed"), y |-> "Moved"] &"if y is (Unique, Borrowed)",
  cal(U)_"in"(s)[x |-> ("Shared", "Free"), y |-> ("Shared", "Free")] &"if y is (Unique, Free)",
  cal(U)_"in"(s)[x |-> ("Shared", "Borrowed"), y |-> "Moved"] &"if y is (Shared, Borrowed)",
  cal(U)_"in"(s)[x |-> ("Shared", "Free")] &"if y is (Shared, Free)"
) \
"traverse"(x = mono("null")) &= cal(U)_"in"(s)[x |-> ("Unique", "Free")] \
"traverse"(m(overline(X))) &= "chain"(cal(U)_"in"(s), overline(X)) \
"traverse"(x = m(overline(X))) &= cases(
  "chain"(cal(U)_"in"(s), overline(X))[x |-> ("Unique", "Free")] &"if m returns Unique",
  "chain"(cal(U)_"in"(s), overline(X))[x |-> ("Shared", "Free")] &"if m returns Shared"
)
$



== Handling Method Arguments
<sec:evaluate>
The helper function $sans("chain") \( cal(U) \, overline(X) \)$
processes the list of arguments
$overline(X) = x_1 \, x_2 \, dots.h \, x_n$ in order and returns an
updated environment. It uses the known parameter passing modes (borrowed
vs. consumed) of the called method.

$
"chain"(cal(U)_1, emptyset) &= cal(U)_1 \
"chain"(cal(U)_1, x dot overline(X)) &= cases(
  "chain"(cal(U)_1, overline(X)) &"if " cal(U)_1(x) = "Moved",
  "chain"(cal(U)_1, overline(X)) &"if " cal(U)_1(x) = ("Shared", \_),
  "chain"(cal(U)_1, overline(X)) &"if " cal(U)_1(x) = ("Unique", \_) " and parameter " x " is borrowed",
  "chain"(cal(U)_1[x |-> "Moved"], overline(X)) &"if " cal(U)_1(x) = ( "Unique", \_ ) " and parameter " x " is consumed"
)
$

In the third case, a unique variable that is borrowed remains unique; in
the fourth case, a unique variable that is consumed becomes
$sans("Moved")$ because ownership has been transferred and the variable
can no longer be used safely.

== Join of Predecessor Environments
<sec:join>
Let $P = { p_1 \, #h(0em) p_2 \, #h(0em) dots.h \, #h(0em) p_n }$ be the
list of all predecessors of a statement $s$. The function
$sans("join") \( P \)$ combines the output environment of each
predecessor pointwise by taking the meet (greatest lower bound) of the
types for each path. If a path does not appear in some predecessor, it
is assumed to be absent (which we treat as not contributing any
constraint). The join is computed by iteratively inserting each
predecessor environment into an accumulating result.

$ sans("join") \( overline(P) \) & = sans("join") \( nothing \, #h(0em) overline(P) \)\
sans("join") \( cal(U)_1 \, #h(0em) nothing \) & = cal(U)_1\
sans("join") \( cal(U)_1 \, #h(0em) p dot.op overline(P) \) & = sans("join") \( sans("merge") \( cal(U)_1 \, med cal(U)_(upright("out")) \( p \) \) \, overline(P) \) $

The auxiliary function
$sans("merge") \( cal(U)_1 \, #h(0em) cal(U)_2 \)$ merges the bindings
of $cal(U)_2$ into $cal(U)_1$. For each binding $x arrow.r.bar t$ in
$cal(U)_2$, if $x$ is already in $cal(U)_1$ we replace its type by the
meet of the existing type and $t$; otherwise we simply add
$x arrow.r.bar t$ to the accumulated result $cal(U)_1$.

$ sans("merge") \( cal(U)_1 \, #h(0em) nothing \) & = cal(U)_1\
sans("merge") \( cal(U)_1 \, #h(0em) \( x arrow.r.bar t \) dot.op cal(U)_2 \) & = cases(delim: "{", sans("merge") \( cal(U)_1 \[ x arrow.r.bar \( t #h(0em) inter.sq #h(0em) cal(U)_2 \[ x \] \) \] \, #h(0em) cal(U)_2 \) & upright("if ") x in "dom" \( R \), sans("merge") \( cal(U)_1 \[ x arrow.r.bar t \] \, #h(0em) cal(U)_2 \) & upright("otherwise")) $

= Supporting Aggregated Expressions
<sec:supporting-aggregated-expressions>

