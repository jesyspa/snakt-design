# Heap-dependent expressions in pure functions

In this document, we will discuss the design and implementation of heap-dependent
 expressions in pure functions. We will take a look at the Viper encoding prior to 
 this change, how to extend it to support heap-dependent expressions, and finally, 
 what limitations arise from the designed encoding. More detailed information
 can be found in the Bachelor's thesis of Alexander Falter.

## Viper encoding prior and problem definition

The current encoding translates the body of a pure function into a chain of 
let-bindings. On the right hand side of a let-bound variable, there is, disregarding
the Ternary guard introduced in https://github.com/JetBrains/SnaKt/pull/62, a value, 
a local, a function call, or a  Ternary expression that only contains local variables 
(cf. below). To extend  this encoding to support heap-dependent expressions, the 
following must be kept in mind:

- Predicates: In SnaKt, we guard accesses to the heap using predicates. In this design, 
we will rely on the shared predicate providing access to immutable fields of a class.
While this poses some limitations, we will explain the reasoning behind this in a 
later section.
- Unfolding: For heap accesses to be valid, the corresponding predicate containing 
permissions to the accessed location must be unfolded. In a pure function body, 
we cannot use an unfold statement as we must construct a single expression (and 
hence cannot use a statement). Therefore, we will rely on the Viper 'unfolding... in'
expression to temporarily unfold a predicate in an expression.
- Field access embedding: On the embedding level, field accesses are modelled 
as FieldAccess embeddings. The receiver of these embeddings may either be a 
variable or, in the case of a nested field access, another FieldAccess embedding.

Consider the encoding prior to this design, where ei is an expression and ri is 
either a value or a local:
```viper
let t1 := e1 in
let t2 := e2 in
...
let tn := en in
    (some condition) ? r1 : ((some_other_condition) ? r2 : r3)
```
We want to extend this encoding to support heap accesses. Throughout this design,
we will assume that heap accesses made in a function are pure. That is, we are 
only dealing with reads from the heap, as writes are inherently impure. Any 
function body not satisfying this constraint is rejected by the purity checker.

## Translation

When translating field accesses in a Kotlin function that is being translated
into a Viper method, SnaKt generally splits the accessed path into single
accesses. Namely, for each intermediary access, an anonymous variable is
introduced. For pure functions, we will follow the exact same strategy. The only
difference is that, instead of declaring and assigning local variables, we will
let-bind each individual access to a new anonymous variable. The following code
blocks show a Kotlin function using a nested field access and its Viper
encoding. Note that this translation is not valid, as we need to ensure
permissions to access the fields are present. We will discuss how to propagate
these field permissions in a later section.

**A Kotlin function using a nested field access to read from a class:**
```kotlin
class OuterBox(innerBox: InnerBox)
class InnerBox(value: Int)

@Pure
fun getInnerValue(outerBox: OuterBox): Int {
    return outerBox.innerBox.value
}
```

**Viper translation:**
```viper
field innerBox: Ref
field value: Int

function getInnerValue(outerBox: Ref): Int
{
    let anon1$0 == (outerBox.innerBox) in
    let anon2$0 == (anon1$0.value) in
        anon2$0
}
```

## Access dependencies

We will use the shared predicate to ensure necessary permissions for field accesses in
pure functions are present. The reasoning behind, and limitations arising from,
this choice of predicate will be discussed later as future work. 

When translating into a Viper method, before accessing a field, SnaKt unfolds
the shared predicate required for this field access. This is not possible in a
function, as we cannot use an unfold statement. Hence, we rely on Viper's
`unfolding in` expression to ensure all permissions are present upon access.
When let-binding an expression, we will associate *access dependencies* with
the variable being let-bound. The access dependencies specify under what
condition what shared predicates must be unfolded for a let-bound reference to
be accessible. We can determine what access dependencies must be associated
with a new let-binding based on the expression that is being let-bound. The
exact nature of this will be discussed in the implementation details. The
following table shows the access dependencies associated with each let-bound
variable of the provided Kotlin code snippet.

With the access dependencies collected, we can wrap any field accesses in
`unfolding in` expressions to ensure all permissions are present for a field
access. Namely, for a field access, we create a (potentially) nested ternary
expression that, for every condition collected as an access dependency, unfolds
the corresponding predicates and then accesses the field. As an illustration,
the Viper code block below shows the translation of the Kotlin snippet. Note
that this code will not verify, as we have no assurance that the shared
predicates accessed are present in the verification context. We will discuss
how to establish these preconditions later.

**A Kotlin function conditionally returning the value of the current- or the
next node depending on whether a next node exists:**
```kotlin
class Node(val value: Int, val next: Node?)

@Pure
fun getThisOrNext(head: Node): Int {
    val next = head.next
    val headVal = head.value
    val returnExp = next?.value ?: headVal
    return returnExp
}
```

**Access dependencies for each variable:**

| **Variable** | **Condition** | **Predicate to Unfold** |
| :---         | :---           | :---                    |
| `next`       | `true`         | `{head}`                |
| `headVal`    | `true`         | `{head}`                |
| `returnExp`  | `next == null` | `{head}`                |
|              | `next != null` | `{head, next}`          |

**Viper translation:**
```viper
function getThisOrNext(head: Ref): Int
{
  let next == (unfolding nodeShared(head) in head.next) in
  let headVal == (unfolding nodeShared(head) in head.value) in
  let returnExp == ((next != null) 
    ? (unfolding nodeShared(head) in 
       unfolding nodeShared(next) in next.value) 
    : (unfolding nodeShared(head) in headVal)) 
  in
    returnExp
}
```

## Choice of predicate

Instead of using the shared predicate, which only grants permissions to immutable 
fields of a class, one could have created another predicate, say the pure predicate, 
granting wildcard permissions to all fields of a class. We decided against this for
the following reasons:

1. Complexity of converting the shared predicate to another: With the shared predicate 
already being present, to obtain another predicate, one would typically convert the 
shared predicate into another predicate using a lemma function or method. As the shared 
predicate is class specific, it is non trivial to define one (or multiple) Lemma 
functions handling this conversion.
2. Prevent loss of information: With the shared predicate already being present and 
the verifier associating information with it, introducing another predicate raises 
the question of whether information can be 'transferred' to the other predicate. Especially
for recursive predicates, this becomes a hard problem to solve. Consider the following 
Viper example:

```Viper
field val: Int
field next: Ref

predicate sharedPredicate(curr: Ref) {
    acc(curr.val, wildcard) &&
    acc(curr.next, wildcard) &&
    (curr.next != null ==> acc(sharedPredicate(curr.next)))
}

predicate purePredicate(curr: Ref) {
    acc(curr.val, wildcard) &&
    acc(curr.next, wildcard) &&
    (curr.next != null ==> acc(purePredicate(curr.next)))
}

method convertSharedToPure(curr: Ref)
    requires acc(sharedPredicate(curr), wildcard)
    ensures acc(purePredicate(curr), wildcard)
{
    inhale acc(curr.mutableVal, wildcard)
    unfold acc(sharedPredicate(curr), wildcard)
    if (curr.next != null) {
        convertSharedToPure(curr.next)
    }
    fold acc(purePredicate(curr), wildcard)
}

method test_loss_of_info(head: Ref)
    requires head != null
    requires acc(sharedPredicate(head), wildcard)
    requires unfolding acc(sharedPredicate(head), wildcard) in head.val == 42 
{
    convertSharedToPure(head)
    assert unfolding acc(pure_predicate(head), wildcard) in head.val == 42
}
```

In this example, we defined another predicate (named the purePredicate) and a 
method converting the shared predicate into the other predicate. We then tried 
to verify the assertion that holds in the precondition. However, this will not 
verify. Keeping the shared predicate will prevent such loss of information:

## Constructing the precondition of a function

Note that all reference types for which we need to require the shared predicate 
can be found in the function's parameters. Furthermore, because the predicate 
also contains the predicates for any references within the parameters, no 
extra predicates need to be acquired to ensure that potentially nested heap 
accesses in the function body work.

## Using a function

There are three points where a Viper function may be used: In a Viper method,
in another Viper function, or in a specification. In the following, we will
discuss all necessary steps to ensure the precondition of a pure function is
satisfied in all of these cases.

### In a Method

As discussed previously regarding let bindings, in a method, SnaKt stores all
field accesses in anonymous variables and unfolds all necessary predicates with
`wildcard` permissions. This also holds for any field access made in the
argument provided to a function. Further, as required shared predicates of a
pure function are directly dependent on the arguments passed to it, and as
unfolding a predicate with `wildcard` permissions does not cause the
verification context to lose `wildcard` permissions to the predicate, all shared
predicates necessary to satisfy the precondition of a pure function are present
in a calling method at call-site. As an illustration, consider the following
Kotlin code and its Viper translation.

**A Kotlin function calling a pure Kotlin function:**
```kotlin
class Node(val value: Int, val next: Node?)

fun getLastIndex(node: Node): Int {
    val len = length(node.next)
    return len
}
```

**Viper translation:**
```viper
method getLastIndex(node: Ref) returns (res: Int)
{
    inhale acc(sharedPredicate(node), wildcard)
    unfold acc(sharedPredicate(node), wildcard)
    var anon0: Ref := node.next
    var len: Int := length(anon0)
    res := len
}
```

### In Another Pure Function

To satisfy the precondition of a pure function called in another pure function,
we can treat the callee similar to a field access. Namely, we will propagate all
necessary access dependencies as before and wrap the calling expression with the
corresponding `unfolding in` expressions to satisfy the callee's precondition.
Note that when a pure function obtains a reference by calling another pure
function that unfolds some predicates to return said reference, the
corresponding access dependencies are not propagated to the caller. This
limitation regarding references will be addressed as future work. For all other
cases, the following pure Kotlin function and its Viper translation illustrate
an example of a pure function being called.

**A pure Kotlin function calling another pure Kotlin function:**
```kotlin
class Node(val value: Int, val next: Node?)

@Pure
fun isSecondToLastIndex(node: Node, index: Int): Boolean {
    // isLastIndex requires the shared predicate of node.next
    return isLastIndex(node.next, index + 1) 
}
```

**Viper translation:**
```viper
function isSecondToLastIndex(node: Ref, index: Int): Bool 
    requires acc(nodeShared(node), wildcard)
{
    let anon0 == (
        unfolding acc(nodeShared(node), wildcard) in
        node.next
    ) in
        isLastIndex(anon0, index + 1)
}
```

### In a Specification

To use a pure function in a specification, we need to guarantee that the shared
predicates required by the pure function can be inferred in the specification.
Further, for verification, we have to unfold any shared predicate corresponding
to an argument to access values that might be associated with it. To ensure all
necessary predicates are present, consider the following specifications:

* **Precondition:** In a precondition, we have to add the shared predicates
  required to the precondition as well and delegate the responsibility of
  guaranteeing their presence to the calling context.
* **Postcondition:** If the postcondition using the pure function is part of a
  method, the corresponding shared predicate can be inhaled at the beginning
  of the method. If it is part of a function, the corresponding shared
  predicate will be part of the precondition, as established for heap
  preconditions.
* **Loop-Invariant:** For a loop-invariant, the predicate's presence can be
  guaranteed in the same way it is being done for postconditions. Note that in
  the current state, pure functions do not support loops. We will discuss loop
  support further as future work.

As an illustration, consider the following code defining a Kotlin function that
uses another function in its precondition. To do so, the shared predicate of
`node` must be required. The resulting translation is shown below. Notice that,
even though it is not necessary for permissions, the predicate of `node.next` is
still unfolded to guarantee inference of any values that might be associated
with it.

**A Kotlin function using a function in its precondition:**
```kotlin
class Node(val value: Int, val next: Node?)

fun getNextValue(node: Node): Int {
    preconditions {
        // Assuming a length function accepting null
        length(node.next) != 0
    }
    return node.next?.value ?: (-1)
}
```

**Viper translation:**
```viper
method getNextValue(node: Ref) returns (res: Int)
    requires acc(sharedNode(node), wildcard)
    requires 
        unfolding sharedNode(node) in
        unfolding sharedNode(node.next) in
        length(node.next) != 0
{
    if (node.next != null) {
        unfold acc(sharedNode(node), wildcard)
        res := node.next.value
    } else {
        res := (-1)
    }
}
```

## Limitations

In this section, we will discuss limitations the designed encoding has, and what 
conceptual work needs to be done to overcome them.

### Guarantees when calling a function

Consider:

```kotlin
@Pure
fun getNext(node: Node): Node? {
    return node.next
}

@Pure
fun getNextValueOrDefault(node: Node): Int {
    val nextNode = getNext(node)
    return if(nextNode == null) 0 : nextNode.value
}
```
with the Viper translation:
```
function getNext(node: Ref): Ref
    requires acc(sharedPredicate(node), wildcard)
{
    unfolding acc(sharedPredicate(node), wildcard) in node.next
}

function getNextValueOrDefault(node: Ref): Int
    requires acc(sharedPredicate(node), wildcard)
{
    let nextNode == (getNext(node)) in
    let anon0 == (nextNode.value) in
    let anon1 == (0) in
    let anon2 == (nextNode == null ? anon1 : anon0) in
        anon2
}
```

In the let-binding of `anon0` the verification context is not holding sufficient
permissions to access the value of `nextNode`. In general, we have no guarantee
of unfolds happening in a function and hence cannot deduce what must be unfolded
for returns of functions to be used. To mitigate this issue, one might associate
such information with a function. The complexity of this is to be determined.
