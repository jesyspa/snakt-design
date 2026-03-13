# Predicates folding/unfolding

## Expected Behaviour
Deciding what has to be unfolded can be quite involved. We construct a recursive class such that every possible order of field accesses are possible. We ignore that this datastructure is infinite. 

```kotlin
class A(
    @Unique @Borrowed var mu : A,
    @Unique val iu : A,
    @Unique @Borrowed var ms : A,
    val is : A
)
```

We use the following abbreviations:
- um: Unique and Mutable
- ui: Unique and Immutable
- sm: Shared and Mutable
- si: Shared and Immutable


### Floatchart
This is how the diagram should be read:
- The color of the nodes is the result of the uniquness type system.
- The circles represent objects, while the rectangles represent the fields of the object.
- The Uniqueness Type text inside the box, is the declared uniqueness type of the field.
- The arrow from `object -action-> field`, means what action needs to be performed to access `field` on `object`.
- To access a deeper field, follow the arrows and execute the actions in the order of traversal.
- To not let the diagram explode we use dotted arrows, to indicate that we reached a situation which is equivalent to an already seen one.


```mermaid
graph LR
    A_u((Class A <br/> Unique)) -- unique --> B_um_ui["um<br/>Mutable / Unique <br/> ui<br/>Immutable / Unique"]

    A_s((Class A <br/> Shared)) -- shared --> Bb_si_ui["si<br/>Immutable / Shared <br/> ui<br/>Immutable / Unique"]
    A_s -- havoc --> Bb_sm_um["sm<br/>Mutable / Shared <br/> um<br/>Mutable / Unique"]


    B_um_ui -.-> info23("Equivalent with A Unique")



    A_u -- shared --> B_sm_si["sm<br/>Mutable / Shared <br/>si<br/>Immutable / Shared"]

    Bb_si_ui -.-> info5(Equivalent with A Shared)
    Bb_sm_um -.-> info6(Equivalent with A Shared)
    B_sm_si -.-> info4(Equivalent with A Shared)
        subgraph Legend ["Uniquness Types"]
                direction TB
            Shared["Shared"]
            Unique["Unique"]
    end

    %% ANCHOR THE LEGEND
    %% Use ~~~ for an invisible link to Class A to keep it nearby
    info23 ~~~ Legend



classDef unique fill:blue
classDef shared fill:red

class Shared shared
class Unique unique
class A_u unique
class A_s shared
class B_um_ui unique
class C_um_ui unique
class B_sm shared
class C_sm shared
class C_si shared
class B_si shared
class B_sm_si shared
%% class C_um_sm shared
%% class C_ui_si shared
class D1 shared
class D9 shared
class D10 shared
class Bb_si shared
class Bb_ui shared
class Bb_sm shared
class Bb_um shared
class Bb_si_ui shared
class Bb_sm_um shared

```

#### Mealy State Machine
The way to get the necessary actions can be expressed as a Mealy state machine. The input is the accessed path. The action `unfold` mean, that we need to unfold the path that was read so far (without the field that is responsible for the transmission). Thi first transmission is performed according to the uniquness of the receiver.


```mermaid
graph LR
    %% Node Definitions
    Start((Start))
    Unique([Unique])
    Shared([Shared])
    A([ ])
    B([ ])
    C([ ])



    %% Styling
    %% style Start fill:#f9f,stroke:#333,stroke-width:2px
    %% style Unique fill:#dfd,stroke:#080,stroke-width:2px
    %% style Shared fill:#ddf,stroke:#008,stroke-width:2px

    %% Initial Transitions
    Start --Unique/_--> Unique
    Start --Shared/_--> Shared

    %% Transitions for Unique
    Unique -->|Unique <br/> Unfold-Unique| C
    C -.-> Unique
    
    %% Bridging Transitions
    Unique -->|Shared <br/> Unfold-Shared| Shared

    %% Transitions for Shared
    Shared --Immutable <br/> Unfold-Shared--> B
    Shared --Mutable <br/> havoc--> A
    A -.-> Shared
    B -.-> Shared
```
(Due to an issue with the rendering engine, useless nodes were inserted)

## Takeaways
- If the reciever is shared, we will never unfold a unique predicate. This is convienient, because the shared predicates do not need to be folded back.
- All the unique predicates that need to be unfolded are always in the beginning of the path. It can not happen that for a single path we have a unfolding pattern like this: unfold-Unique ... unfold-Shared ... unfold-Unique


## When to Unfold
The fundamental difference between the shared and unique predicate is, that the shared can be unfolded as many times. Therefore with the shared predicate we can be much less careful and also perform strictly speaking unnecessary unfolds.

The issue with unique predicates is the following. Assume that everything is unique. We provide two code snippets:
```kotlin
// first
var b = (root.left == null)

// second
var tmp = root.left
```
In the first snippet we want to unfold `unique(root)` once and the fold it back. In the second snippet we only want to unfold `unique(root)`.
To know wheather the predicate must be fold back, we need to know if after the access it is moved or not. This information comes from the CFG flow analysis. To be able to use them here we need to translate the flow analysis information first into the fir AST and then into the expEmbeddings. The mapping from fir Elements to CFG nodes is one to many. If we reverse the this mapping and store the first and last node for each fir Element, we will know which paths are moved/owned before and after each fir Element. The problem is when the an path becomes moved. In the second snipped `root.left` does not mecome moved after the `root.left` but only after the assignment. This makes sense, because in the first example `root.left` should never become moved.

The conclusion is, that we can not unfold the unique predicates on the field access level, because in the first snippet we are suppost to fold it back, whereas in the second we are not. However the information available on the field embedding level is the same for each snippet.


# Unfolding Strategy

The unfolding strategy is divided into two parts: The **Shared Unfolding** part and the **Unique Unfolding** part.

## Shared Unfolding
This contains all the field accesses that either require the shared predicate or a havoc call. This potential unfolds can be inserted on the field access level. Also it is not possible to perform this earlier. Because if the traversal of the path contains a havoc call, the result will be stored in a anonyous variable. This variable will only be known, once the call is inserted. So the unfold of shared predicates, where the shared predicate comes from the havoc call, must be inserted on the field access level.

## Unique Unfolding
This contains all the unique predicate unfolds. This will be performed on the statement level. On the statement level the following is done:
1. Extract all the used paths (we refer to them as "used paths")
2. Use the result of the uniqueness analysis and the Mearly FSM to associate each field access of each used path with an action.
3. Extract all the prefixes which contain only `Unfold-Unique` actions.
4. Make them unique and order them according to their length
5. Insert the unfold statements.




# Unique Folding Strategy

In the folding strategy we only need to consider unique predicates. Because the shared predicates are unfodled with wildcard permission, which means we still have access to the predicate.
The folding strategy works closely together with the Unique Unfolding strategy.
1. Get all the used paths
2. Extract all the prefixes which are unique and not partially moved
3. Order the prefixes by their length starting with the longest.
4. Add fold statements for the corresponding unique predicate.


# Outdated


## Prerequisites
- To unfold and fold correctly, we need information from the uniqueness checker. This includes:
  - Knowing if the receiver of field access is shared or unique.
  - For a given path, is the corresponding object partially moved.






## General Remarks
- The main problem is to know when to keep a unique-predicate unfolded and when to fold it back.
- This is less problematic for shared predicates since folding back is not necessary.
- The Kt-to-Viper encoding should be done only if the program is well-typed according to our annotation system.
- Thanks to the annotation system, we know that when something is passed to a function expecting a unique argument, it
  must be in std form. This means that all the sup-paths have at least default permissions.
- The rule of thumb should be: if a reference is unique at some point in the annotation system, at the corresponding
  point of the Viper encoding its unique-predicate should hold, or we should be able to obtain it after applying some
  fold/unfold. 

## Fields
Folding is closely related to field access. Therefore, we provide an overview of all possible field accesses.

| Receiver - R | Field - F | Mutable | Access Policy          | Reading        | Writing     |
|--------------|-----------|---------|------------------------|----------------|-------------|
| unique       | unique    | val     | ALWAYS_READABLE        | res := R.F     | not allowed |
| unique       | unique    | var     | BY_RECEIVER_UNIQUENESS | res := R.F     | R.F := res  |
| unique       | shared    | val     | ALWAYS_READABLE        | res := R.F     | not allowed |
| unique       | shared    | var     | BY_RECEIVER_UNIQUENESS | res := havoc() | removed     |
| shared       | unique    | val     | ALWAYS_READABLE        | res := R.F     | not allowed |
| shared       | unique    | var     | BY_RECEIVER_UNIQUENESS | res := havoc() | removed     |
| shared       | shared    | val     | ALWAYS_READABLE        | res := R.F     | not allowed |
| shared       | shared    | var     | BY_RECEIVER_UNIQUENESS | res := havoc() | removed     |

** for writing, when we write "removed" we mean that the write to the field itself is removed however potential side 
effects of such a write are preserved.


We will now go through every access policy and explain the corresponding folding mechanimss.

### ALWAYS_READABLE
These are all immutable fields. Hence, we only need to consider reading such fields.

To read, the shared predicate of the receiver must be unfolded. We do not need to fold it back, because we unfold with
wildcard permission and can therefore unfolding as many times as we want.

### BY_RECEIVER_UNIQUENESS
These are the fields that are mutable. The state of the receiver is important.

**Case: Receiver is Shared**

Reading: No predicate must be unfolded. The value always comes from a havoc method.
Writing: No predicate must be unfolded. The writing is never performed.

**Case: Receiver is Unique**

Unclear if this is actually the case:
Both reading and writing are handled the same way. We need to handle this case earlier in the translation, because we
need to know the full accessed path. The necessary fold and unfolds are figured out during the translation to ``ExpEmbeddings`` 
or on a sperarate pass on the ``ExpEmbeddings``. We work on the level of statements. 

For every statement the following is performed:
1. extract the paths used in the statement. Using the results from the uniqueness checker, perform the following:
  - for every prefix of the path:
    - if the prefix is unique, keep it.
    - if the prefix is unique, except the last field, keep it.
    - otherwhise discard it
2. Remove the last field of each path and make them unique.
3. Order them increasing by the length of the path.
4. For every prefix of every path, check if the prefix is partially moved, otherwise add an unfold statement.

5. The actual statement is translated.

6. Find the written to path, remove the last field. Check for each prefix, starting from the longest:
  - If the prefix is not partially moved: add a fold statement for this path.
7. If there is no written to path, then fold everything unfolded before but in reversed order.


Note: the previous two steps could be combined by just do step 6 for every occurring path. 

Note:Method calls can be handled the same way as statements.


Branches:

For if-else branches the following procedure is performed
1. Extract the condition and consider it a statement. 
2. Step 6 is performed at the beginning of both branches. If there is no else branch, create an "empty branch"

Loops: 
- Loops are much more complicated. Especially when we have borrowed datastructures in the function.
- Loops are discussed in [another document](folding-unfolding-while.md)

#### Examples
Consider the following class. All the fields are mutable and unique and have the same type.
We assume that every accessed field is unique.
````
A
├── first
│   ├── first
│   │   ├── ..
│   │   └── ..
│   └── second
│       ├── ..
│       └── ..
└── second
    ├── first
    │   ├── ..
    │   └── ..
    └── second
        ├── ..
        └── ..
````
Example 1. Deep to Shallow
````kotlin
// partially moved: {}
// 1. extracted paths: {first.first}
// 2. without last: {first}
// 3. done
// 4. unfold (A), unfold (first)
var x = first.first // 5.
// 6. partially moved: {first}
// 8. done, 9. done

// continues

// partially moved: {first}
// 1. extract paths: {first}
// 2. without last: {A}
// 3. done
// 4. A is already unfolded (since first is partially moved)
first = x
// written to: first, without last: A
// partially moved: {}
// A is not partially moved anymore
fold(A)
````
Example 2
````kotlin
// partially moved: {}
// 1. extracted paths: {first.first}
// 2. without last: {first}
// 3. done
// 4. unfold (A), unfold (first)
var x = first.first // 5.
// 6. partially moved: {first}
// 8. done, 9. done

// continues

// partially moved: {first}
// 1. extract paths: {first, x.first}
// 2. without last: {A, x}
// 3. done
// 4. unfold (x)
first = x.first
// written to: first, without last: A
// partially moved: {x}
// A is not partially moved anymore
// fold(A)
````
Example 3
````kotlin
// partially moved: {}
// 1. extracted paths: {first.first}
// 2. without last: {first}
// 3. done
// 4. unfold(A) unfold(first)
first.first = A()
// written to: first.first, without last: first
// partially moved: none
fold(first)
fold(A)
````
Example 4
````kotlin
// partially moved: {}
// extracted path: first.first, without last: first, 
// unfold(A), unfold(first)
var x = first.first
// partially moved: first


// path: first.second, without last: first
// since first is partially moved, we do not need to unfold it.
var y = first.second
// partially moved: first
// no written to path

// path: first.first, without last: first, nothing to fold
// partially moved: first
first.first = A()
// written to: first.first, without last: first
// partially moved: first, nothing to fold


// path: first.second, without last: first, nothing to fold
first.second = y
// partially moved: none
// path: first.second, without last: first
// fold(first)
// fold(A)
````

LinkedList Example

The implementation does not focus on efficiency etc. It is just a simple example.
````kotlin

class Node(
  @Unique var next : Node?,
  var value: Int)


class LinkedList(
  @Unique var head: Node?
)

fun lengthRecursiveHelper(@Unique @Borrowed n : Node) : Int {
    // paths: n.next, without last: n, unfold(n)
  if (n.next == null) { 
      // fold(n)
    return 1
  } else {
    // written to path: none
    // fold(n)
    
      // paths: n.next, without last: n, unfold(n)
    return lengthRecursiveHelper(n.next) + 1
    // written to none
    // method call, n.next was borrowed, so reverse the unfolds
    // partially moved: none
    // fold(n)
  }
}


fun lengthRecursive(@Unique @Borrowed l : LinkedList) : Int {
    // paths l.head, without last: l, unfold(l)
  if (l.head == null) {
      // extracted paths: l.head, without last: l
      // partially moved: none
      // fold(l)
    return 0
  } else {
      // extracted paths: l.head, without last: l
      // partially moved: none
      // fold(l)
      
      // paths l.head, without last: l, unfold(l)
      return lengthRecursiveHelper(l.head)
      // partially moved: none
      // fold(l)
  }
}


fun insert(@Unique @Borrowed l : LinkedList, value : Int) {
  // no path
  @Unique var newNode = Node(null, value)
    
    
  // paths: newNode.next, l.head without last: newNode, l, unfold(newNode), unfold(l)
  newNode.next = l.head
  // partially moved: l
  // fold(newNode)
  
  // paths l.head, without last: l
  // partially moved: l
  l.head = newNode
  // partially moved: none
  // fold(l)
}

// same as `insert`
fun insertNode(@Unique @Borrowed l : LinkedList, @Unique node: Node) {
  node.next = l.head
  l.head = node
}


fun insertSecond(@Unique @Borrowed l : LinkedList, value : Int) { 
  // not paths
  @Unique var newNode = Node(null, value)
    
  // paths: l.head, without last: l
  // partially moved: none
  // unfold(l)
  var firstNode = l.head
  // partially moved: l
  // noting to fold.
    
  // no paths
  if (firstNode == null) {
    
      // partially moved: l
      // paths: l.head, without last: l, already unfolded
      l.head = newNode
      // extracted paths: l.head, without last: l
      // partially moved: none
      // fold(l)
  } else {
    
      // partially moved: l
      // paths: firstNode.next, without last: firstNode
      // unfold(firstNode)
      var secondNode = firstNode.next
      // extracted paths: firstNode.next, without last: firstNode
      // partially moved: l, firstNode

      // extracted paths: newNode.next, without last: newNode
      // unfold (newNode)
      newNode.next = secondNode
      // extracted paths: newNode.next, without first: newNode
      // partially moved: l, firstNode
      // fold(newNode)
    
      // extracted paths: firstNode
      firstNode.next = newNode
      // extracted paths: firstNode.next, without first: firstNode
      // partially moved: l
      // fold(firstNode)


      // extracted path: l.head, without last: l
      // nothing to unfold, because l is partially moved
      l.head = firstNode
      // extracted paths: l.head, without last: l
      // partially moved: none
      // fold(l)
  }
}

fun insertLastRecursiveHelper(@Unique @Borrowed current : Node, @Unique node : Node) {
  if (current.next == null) {
    current.next = node
    return
  }
  insertLastRecursiveHelper(current.next, node)
}

fun insertLastRecursive(@Unique @Borrowed l : LinkedList, @Unique node : Node) {
  @Unique var current = l.head
  if (current == null) {
    l.head = current
    insertNode(l, node)
    return
  }
  insertLastRecursiveHelper(current, node)
  l.head = current
}


@Unique
fun popFirst(@Unique @Borrowed l: LinkedList) : Node? {
  // extracted paths: l.head, without last: l
  // unfold(l)
  @Unique var result = l.head
  // partially moved: l
  
  // no extracted paths
  if (result == null) {

    // extracted paths: l.head, without last: l
    // partially moved: l
    l.head = result // necessary since l is borrowed.
    // partially moved: none
    // fold(l)
    return null
  }
  // extracted paths: l.head, result.next, without last: l, result
  // partially moved: l
  // unfold(result)
  l.head = result.next
  // partially moved: result.next
  //fold(l)
  
  // extracted path: result.next, without last: result
  // unfolded: result
  result.next = null
  // written to path: result.next, without last: result
  // partially moved: none
  // fold(result)
  return result
}

fun reverse(@Unique @Borrowed l: LinkedList) {
  // extracted paths: none
  val currentHead = popFirst(l)
  // extracted paths: none
  if (currentHead == null) {
    return
  }
  // extracted paths: none
  reverse(l)
  // extracted paths: none
  insertLast(l, currentHead)
}
````

#### Remarks
- We do not need to bother with method calls. Because the uniqueness checker will make sure that we are allowed to call that method.
So, if a method expects a unique argument, the corresponding object cannot be partially moved; hence we must already have the predicate.
- If a part of an object is borrowed, then we will see it in the path and unfold it. After the function call, the uniqueness checker
will inform the folder that it is no longer moved. Hence, we will fold it back.
