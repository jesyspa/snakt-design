## Name Mangling

### 1. Registration of Types

- Types are registered to track unique identifiers for variables.

### 2. Registration of Names

- Names (e.g., variable basenames) are registered within scopes.
- Each name is associated with a type, allowing for type-based disambiguation during resolution.

### 3. Assigning Output Versions to Types

- For each type, select a single output version from $\{short, medium, long\}$ used for all variables of that type.
- This assignment is reduced to a graph problem: specifically, the **Maximal Independent Set of Minimal Weight (MWIS)**.
- For simplicity, we approximate MWIS using a greedy algorithm.
- The reduction proceeds in two steps:
    1. Name mangling → Minimal Weight Independent Traversal (MWIT)
    2. MWIT → MWIS

### Step 1: Name Mangling to Minimal Weight Independent Traversal (MWIT)

Define a graph $G = (V, E)$:

- Vertices $V$: Pairs $(t, v)$ where $t$ is a type and $v \in \{\text{short}, \text{medium}, \text{long}\}$.
- Edges $E$: An edge exists between $(t, v)$ and $(t', v')$ if:
    - $t = t'$ (same type, different versions), or
    - $\exists x \in t, x' \in t' :s(t,v,x)=s(t',v',x')$, where $s$ is the string representation function (i.e., potential name collision in output).

Partitions for MWIT: For each type $t$, the partition is  $\{(t, \text{short}), (t, \text{medium}), (t, \text{long})\}$ .

The MWIT solution selects exactly one version per partition (type), ensuring no conflicts (no adjacent vertices selected) while minimizing the total length of all variable string representations.

### Step 2: MWIT to Maximal Independent Set of Minimal Weight (MWIS)

For our setup, the MWIT solution coincides with the MWIS solution:

- In MWIS, from each partition, at most one vertex is selected (due to edges between same-type vertices).
- However, at least one per partition must be selected, as there exists an independent set covering all types:  $\{(t, \text{long}) \mid \forall t\} .$
- Thus, MWIS selects exactly one vertex per partition, minimizing the total string length for variables.

### Greedy Algorithm for MWIS

- Initialize the independent set with  $\{(t, \text{long}) \mid \forall t\}$ .
- Sort remaining vertices by gain:

$\text{gain}(t, v) = |t| \cdot \ell(\text{long}) - \sum_{x \in t} \ell(s(t, v, x))$

where $|t|$  is the number of variables of type $t$ , $\ell$ is the length function, and $s(t, v, x)$ is the string representation of $x$ under version $v$.
- Iteratively add vertices with positive gain if they do not violate independence.
- Heuristics can be added if needed.

### 4. Name Resolution

- During resolution, inspect the variable's type and output the mangled name using the assigned version.
- If the type is null, fallback to the scope's basename.

## Definitions of Mentioned Optimization Problems

### Maximal Independent Set (MIS)

An independent set in a graph $G = (V, E)$ is a subset of vertices with no two adjacent. A maximal independent set is an independent set that cannot be extended by adding another vertex (i.e., every non-selected vertex is adjacent to at least one selected vertex). In our context, we require coverage across partitions.

### Minimal Weight Independent Set (MWIS)

Given a weighted graph where each vertex has a weight (cost), find an independent set that minimizes the total weight.

### Maximal Independent Set of Minimal Weight (MWIS, extended)

Combines maximality with minimal total weight. In our reduction, maximality ensures one selection per type (partition), while minimizing aggregate string lengths.

### Minimal Weight Independent Traversal (MWIT)

A variant of independent set problems tailored for partitioned graphs. It traverses partitions, selecting one vertex per partition to form an independent set of minimal total weight. In our case, it ensures exactly one version per type with no collisions.
