# Name Mangling

When converting FIR to Viper, we need to ensure that 
**Viper names** (string representations) do not 
conflict.  However, we would prefer short names over
long names.  By registering all **mangled names** 
(the symbolic form before being assigned a Viper-compatible 
string) used in the program and attempting to shorten 
their corresponding **Viper names** whenever possible 
without collisions, we make the generated code much more readable.

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
Each **mangled name** has an ordered list of *candidate* 
strings (shortest first).  
A *candidate* is a symbolic form that 
renders to the final viper name and **knows which 
other names it depends on**.  
We expose two operations:  
```currentCandidate(x): string``` - returns the currently selected 
string (candidate) for ```x```.  
```deleteCurrentCandidate(x): string``` - advances ```x``` to 
the next candidate (or applies a deterministic fallback if 
the list is exhausted) and returns the new current string. 
  
The final **Viper name** for ```x``` is simply the 
```currentCandidate(x): string```.  

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
We can identify the possible *candidates* for each 
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

We maintain a **dependence graph** G over names. There is a 
directed edge $x \to y$ iff determining the string representation 
of $x$ requires the string representation of $y$.  
$G$ is a DAG (see **Constraints**).

### Initialization 
1. For each name ```x```, build its candidate list.
2. Build ```G```. 
### Main Loop
Repeat until there are no conflicts: 
1. **Detect conflicts**  
Group names by ther current string and define 
$$\text{Conflicted} := \{ x| \exists y \neq x:
currentCandidate(x) = currentCandidate(y)\}$$.  
If ```Conflicted``` is empty, we are done.
2. **Choose names to fix**  
Invoke  
```FixSet = chooseNamesForFix(Conflicted)```
where $\text{FixSet} \subseteq \text{Conflicted}, \text{FixSet}
\neq \emptyset$
3. **Advance candidates**  
For each $x \in \text{FixSet}$, call ```deleteCurrentCandidate(x)```
to move to the next candidate (or fallback).

### Walkthrough: assigning a name to `A.foo()`

We illustrate how a **mangled name** becomes a concrete 
**Viper name** using `A.foo()`.  
**Candidate lists**:  
```class A```: ```["A", "class_A"]```  
```fun A()```: ```["A", "f_A", "f_A_takes_Unit", 
"f_A_takes_Unit_returnsUnit"]```  
```fun foo()```: ```["foo()", "f_foo()", "f_foo_takes_Unit"]```  
```fun A.foo()```: ```["A_foo()", "f_A_foo()", "f_A_foo_takes_Unit"]```

#### Iteration 1 — initial conflicts

```class A``` $\to$ ```"A"```  
```fun A()``` $\to$ ```"A"```  
```FixSet = [class A()]```

After iteration, for ```class A``` change candidate:  
```"A"``` $\to$ ```"class_A"```.  
**Affected string:**  
```A_foo()``` $\to$ ```class_A_foo()```
