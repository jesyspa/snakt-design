# Name Mangling

When converting FIR to Viper, we need to ensure that names
do not conflict.  However, we would prefer short names over
long names.  By registering all names used in the program
and attempting to find cases when they can be shortened
without collisions, we can make the generated code much more
readable.

Goals:
* Names are globally unique.
* Names are generally short enough to read at a glance.

Non-goals:
* Optimising often-used names to be shorter.

Constraints:
* The dependency graph must be acyclic. At the time of writing 
this documentation, cycles cannot occur, but new 
subclasses of MangledName must be added carefully to avoid 
introducing cycles.

## Name structure

We regard our names as consisting of two parts:
1. A *namespace* that specifies the context a name is in.
2. A *local name*  that is unique within the namespace.

Note that namespace names may themselves contain names: for
example, a function may be namespaced within a class, which
itself has a namespace.

Local names may also contain names: for example, the name of
a function may contain the types of its parameters.
However, to make the program tractable we assume that local
names are guaranteed to be unique in their full form.  Local
names may also have shorter forms, that should be used if
they do not collide.

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

When converting the `foo()` function, we can see the
following namespaces:
* The package.
* The classes `A` and `B`.
* The function `foo()`.
* The parameters of other functions.

This is not an exhaustive list of the namespaces in the
resulting program: new symbols are generated in the
translation to Viper, and these symbols often get their own
namespaces.  This includes namespaces for return values and
labels.

We can identify the possible local names in this example:
* `class A` -> `class_A`, `A` (same for `B`)
* `fun A()` -> `fun_A_takes_Unit_returns_Unit`,
  `fun_A_takes_Unit`, `fun_A`, `A` (same for the `foo`
  overloads, including in `A`)
* `val x` in `A` -> `field_x`, `x`
* Getter of `var x` in `B` -> `prop_x_getter`, `prop_x`, `x`
* Setter of `var x` in `B` -> `prop_x_setter`, `prop_x`, `x`
* Parameter `x` in `fun foo(...)`: `x`
  
## Algorithm

1. Traverse the program and add mangled names.
2. Build a directed dependency graph where each vertex is a
pair $(x, \text{version})$, with $x$ being a mangled name
and $\text{version} \in \{\text{short}, \text{medium}, \text{long}\}$
(there may be additional versions depending on the type of name).
Add an edge $(x, v_x) \to (y, v_y)$ if representing
$(x, v_x)$ requires knowing the representation of $(y, v_y)$.
To check this, we simply analyze the specific cases.
3. Obtain a topological sort of the dependency graph (given the
nature of dependencies on mangled name components, this graph
should be acyclic).
4. Traverse the dependency graph in the topological order.
Upon entering a vertex, compute $s(n, v)$ (with no cycles
in the dependency graph, there should be sufficient information for this).
Attempt to replace the current version (for `n.basename`) with $v$.
If there are no conflicts with already assigned names and $v$ is a more
beneficial version, make the change.
5. When resolving a name, examine its `basename` and output the representation
based on its assigned version.

### Annotated example

Let us return to the example above, with the preferred names
annotated:
```kotlin
// A: A, class_A
// x: x, field_x
class A(val x: Int) {
    // foo: foo, fun_foo, fun_foo_takes_Unit, fun_foo_takes_Unit_returns_Int
    fun foo(): Int = ...
}

// B: class_B, B
class B {
    // get x: x, prop_x, prop_x_getter
    // set x: x, prop_x, prop_x_setter
    var x: Int
        get() { ... }
        set(v) { ... }
}

// A: A, fun_A, fun_A_takes_Unit, fun_A_takes_Unit_returns_Unit
fun A() { ... }

// foo: foo, fun_foo, fun_foo_takes_ABC, fun_foo_takes_ABC_returns_XYZ
// x: x
// B: B
fun foo(x: Int, B: Int) { ... }

// foo: foo, fun_foo, fun_foo_takes_Unit, fun_foo_takes_Unit_returns_Unit
fun foo() {
    // x: x
    val x: Int = ...
}
```

We construct a dependency graph where each node represents a possible 
version of a name (for classes, fields, parameters: short/medium; for functions: 
*_with_takes and *_takes_returns). An edge $(x, v_x) → (y, v_y)$ indicates that 
choosing the representation of $x$ in version $v_x$ depends on the representation of $y$ 
in version v_y.

Once the graph is built, we perform a topological sort. This determines a safe 
order to traverse the graph such that all dependencies are resolved before a node 
is processed. Traversing the nodes in topological order, we attempt to assign the 
shortest available version of each name that does not conflict with previously 
assigned names.

Following this procedure on our example, the topological order leads us to first 
assign names to global entities (class A, class B, fun A, fun foo(...), fun foo()), 
which then allows us to resolve names that depend on them, such as methods inside 
classes and property getters/setters. Because the assignments respect dependencies 
and avoid collisions at each step, the resulting names are both unique and 
as short as possible:

* `class A` -> `class_A`
* `class B` -> `B`
* `fun A` -> `fun_A`
* `fun foo(...)` -> `fun_foo_takes_x_B`
* `fun foo()` -> `fun_foo_takes_Unit`

Local names inside these namespaces, such as method and parameter names, 
are then resolved in the same way, producing the final unique names shown in the 
code above.
```kotlin
class class_A(val class_A_x: Int) {
    fun class_A_foo(): Int = ...
}

class B {
    fun B_prop_x_getter(): Int { ... }
    fun B_prop_x_setter(param_v: Int) { ... }
}

fun fun_A() { ... }

fun fun_foo_takes_x_B(param_x: Int, param_B: Int) { ... }

fun fun_foo_takes_Unit() {
    val param_x: Int = ...
}
```
