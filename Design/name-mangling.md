# Name Mangling

When converting FIR to Viper, we need to ensure that **Viper names** 
(string representations)
do not conflict. However, we would prefer short names over
long names.  By registering all **mangled names** (the symbolic 
form before being assigned a Viper-compatible string) used 
in the program and attempting to shorten their corresponding 
**Viper names** whenever possible without collisions, we make 
the generated code much more readable.

Goals:
* Viper names are globally unique.
* Viper names are generally short enough to read at a glance.

Non-goals:
* Optimising often-used names to be shorter.

Constraints:
* The dependency graph must be acyclic. At the time of writing 
this documentation, cycles cannot occur, but new 
subclasses of ```MangledName``` must be added carefully to avoid 
introducing cycles.

## From Mangled to Viper Names
We regard each **mangled name** as consisting of three components:
1. *Basename* — a symbolic identifier that denotes the core of the name.
It is not a string by itself but a symbolic value.
2. *Scope* — a symbolic identifier that specifies the context
in which the name exists. Like the basename, it is not
initially a string but a symbolic value.
3. *Type* — a string that indicates the category or kind of the name.

Note that *basename* and *scope* may themselves contain **mangled names**: 
for example, a function may be namespaced within a class, which
itself has a scope.

From each **mangled name**, a corresponding **Viper name** in one 
of three possible forms:
1. ```basename_reqiredScope```
2. ```type_basename_requiredScope```
3. ```type_basename_fullScope```

Where:  
**fullScope** — string representation of *Scope*.  
**requiredScope** — string representation of the essential part 
of *Scope* (currently, only classes).  
**optionalScope** — string representation of all remaining parts 
of *Scope*, including the *Type* and any non-essential elements.

### Example

Let us consider the following Kotlin program:

```kotlin
class A(val x: Int) {
    fun foo(): Int = ...
}

class B {
    var x: Int
        get() { ... }
        set(v) { ... }
}

fun A() { ... }

fun foo(x: Int, B: Int) { ... }

fun foo() {
    val x: Int = ...
}
```
When converting the **mangled name** of A.foo() method, we have 
following parts:  
1. ```basename =  "foo()"```
2. ```scope = classA.name```, where classA.name initially
symbolic value
4. ```type = "f"```, because foo() - function
    
We can identify the possible **viper names** for each
**mangled name** :
* `class A` -> `class_A`, `A` (same for `B`)
* `fun A()` -> `fun_A_takes_Unit_returns_Unit`,
  `fun_A_takes_Unit`, `fun_A`, `A` (same for the `foo`
  overloads, including in `A`)
* `val x` in `A` -> `field_x`, `x`
* Getter of `var x` in `B` -> `prop_x_getter`, `prop_x`, `x`
* Setter of `var x` in `B` -> `prop_x_setter`, `prop_x`, `x`
* Parameter `x` in `fun foo(...)`: `x`

## Algorithm

We work with two graphs:

a **dependency graph** whose vertices are pairs 
$(x, \text{version})$,  where $x$ is a mangled name 
and $\text{version} \in \{\text{short}, \text{medium}, 
\text{long}, \ldots\}$.  
Edges encode that rendering $(x, v_x)$ requires the representation 
of $(y, v_y)$.

a **conflict graph** with the **same set of vertices** 
$(x, \text{version})$.  
Edges encode that two different vertices cannot be assigned 
simultaneously, because their resulting strings would collide.

### Procedure

1. **Pick sinks in the dependency graph.**  
   Take all vertices with out-degree $0$ (no unresolved dependencies).

2. **Fix the version indicated by the sink vertex.**  
   For each sink $(x, v)$, we attempt to **assign version $v$** to $x$.  
   The assignment is allowed iff **all** of the following hold:
  - **No collisions** are created with already assigned strings.
  - **Basename fairness:** no other name with the **same basename** has
    already been assigned a **strictly shorter** version than $v$.
  - **Feasibility:** after the assignment, there is **no** vertex in
    the conflict graph for which **all** versions become banned
    (i.e., every vertex still has at least one admissible version).

   **Group assignment by basename.**  
   If we assign $x$ version $v$, then **for all** $y$ with 
   $y.\!basename = x.\!basename$ we also assign **version $v$** 
   (provided they are not fixed yet). In other words, versions 
   are assigned **in groups** per basename, not one-by-one.

   After committing, update the affected subtrees in the dependency graph.

3. **Prune resolved vertices.**  
   Remove **all vertices whose basename got fixed** (i.e., all
   $(y, \cdot)$ with $y.\!basename = x.\!basename$), together
   with incident edges.

5. **Repeat until stable.**  
   Return to Step 1 while conflicts remain or further assignments
   are possible.



### Walkthrough: assigning a name to `A.foo()` (first iterations)

We illustrate how a **mangled name** becomes a concrete **Viper name** 
using `A.foo()`.  
A key rule: **all entities that share the same basename must receive 
the same version.**  
So decisions are made in **groups per basename**, not individually.



**Components (symbolic at the start).**
- $basename = \text{"foo()"}$ — symbolic identifier (not a string yet).
- $scope = A$ — points to class `A` (symbolic until `A` is named).
- $type = \text{"f"}$ — category “function”.

**Version–to–form mapping (preference short → long).**
- $short \;\mapsto\; basename\_\!requiredScope$
- $medium \;\mapsto\; type\_basename\_\!requiredScope$
- $long \;\mapsto\; type\_basename\_\!fullScope$

Concretely for $A.foo()$ (these become **strings only after $A$ is 
named**):
- $short:\; foo()_A$
- $medium:\; fun\_foo()_A$
- $long:\; fun\_foo()_{\langle fullScope(A)\rangle}$



#### Iteration 1 — $(A, short)$ as a sink

At the very beginning, $(A, short)$ is an sink in the 
dependency graph: out-degree $0$.  
By the procedure, we now *attempt to fix* basename `"A"` at version $short$.

Group assignment for basename `"A"` includes:
- class `A` → `"A"`
- function `A()` → `"A"` (since its requiredScope is empty at top level)

Conflict check:
- both would become the same string `"A"` → **collision**.

Assignment fails.  
Since `"A"` is not fixed, $(A, short)$ is pruned as unassignable.  
Next, the dependency graph still contains $(A, medium)$ and $(A, long)$.


#### Iteration 2 — $(A, medium)$ as a sink

Now $(A, medium)$ is a new sink.  
We attempt to fix basename `"A"` at version $medium$.

Group assignment:
- class `A` → `"class_A"`
- function `A()` → `"fun_A"`

Checks succeed:
- no collisions,
- we haven’t fixed `"A"` before with a shorter version,
- feasibility preserved.

Commit group assignment: $basename = \text{"A"} \mapsto medium$.  
Remove all vertices with basename `"A"` from the dependency graph.


#### Iteration 3 — $(A.foo(), short)$ as a sink

With `A` resolved, the vertices for `A.foo()` become sinks.  
We now process $(A.foo(), short)$.

Group assignment for basename `"foo()"` includes:
- method `A.foo()` → `"foo()_A"`
- top-level `foo()` → `"foo()"` (requiredScope empty)
- possibly others (e.g. `B.foo()` → `"foo()_B"`)

Suppose these strings don’t collide.  
Checks succeed, so we can commit.

Commit group assignment: $basename = \text{"foo()"} \mapsto short$.  
Remove all `"foo()"` vertices.


#### Iteration 4 — possible fallback later

If later a collision is detected in the conflict graph (e.g. two 
unrelated `foo()` collapsing to the same string),  
the algorithm will eventually reach $(foo(), medium)$ as a sink, 
and then reassign the entire basename-group `"foo()"` to $medium$:
- `"fun_foo()_A"`, `"fun_foo()"`, …

If still needed, escalation to $(foo(), long)$ is possible.


Thus, the algorithm never “tries shorter first by hand”:  
we simply process sink vertices $(x,v)$ in turn,  
and the group assignment either succeeds (commit) or fails (discard 
this vertex and continue with another sink).
