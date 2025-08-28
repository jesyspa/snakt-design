## Name mangling

When converting FIR to Viper, we need to ensure that names do not conflict. However, we would prefer short names over long names. By registering all names used in the program and attempting to find cases when they can be shortened without collisions, we can make the generated code much more readable.

Goals:

- Names are globally unique.
- Names are generally short enough to read at a glance.

Non-goals:

- Optimising often-used names to be shorter.

Algorithm:

1. Traverse the program and add mangled names.
2. Build a directed dependency graph where each vertex is a pair $(x, \text{version})$, with $x$ being a mangled name and $\text{version} \in \{\text{short}, \text{medium}, \text{long}\}$. Add an edge $(x, v_x) \to (y, v_y)$ if representing $(x, v_x)$ requires knowing the representation of $(y, v_y)$. To check this, we simply analyze the specific cases.
3. Obtain a topological sort of the dependency graph (given the nature of dependencies on mangled name components, this graph should be acyclic).
4. Traverse the dependency graph in the topological order. Upon entering a vertex, compute $s(n, v)$ (with no cycles in the dependency graph, there should be sufficient information for this). Attempt to replace the current version (for `n.basename`) with $v$. If there are no conflicts in the graph and $v$ is a more beneficial version, make the change.
5. When resolving a name, examine its `basename` and output the representation based on its assigned version.
