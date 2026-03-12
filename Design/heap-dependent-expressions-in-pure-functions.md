# Heap-dependent expressions in pure functions

In this document, we will discuss the design and implementation of heap-dependent
 expressions in pure functions. We will take a look at the Viper encoding prior to 
 this change, how to extend it to support heap-dependent expressions, and finally, 
 what limitations arise from the designed encoding.

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

For this section, assume that the shared predicate is present in the function's context.
We will see later how to achieve this.

The core idea behind translation is to create a let-bound variable for each field access 
and associate the necessary predicate accesses to make the field access valid with said 
let-bound variable. Notice that the receiver of a field access is always a local variable, 
as the receiver is either a local variable directly, or the result of translating the 
receiver is a local variable. Whenever a new let-bound variable is introduced, we will 
associate any necessary predicate accesses with it. Namely, when the following expressions 
are let-bound to a new variable, we will do the following:
- Local variable: If the let-bound expression is a local variable, we will add all the 
predicate accesses from said variable to the variable of the let-binding being introduced.
- Field access: If the let-bound expression is a field access, we will combine the 
predicate accesses on record for the receiver (a local variable) with the predicate 
accesses necessary for the field access.
- Ternary expression: Recall that by construction, a Ternary expression will only resolve 
between two locals. Hence, if a Ternary expression is encountered, we will associate 
the union of the predicate accesses on record for both locals.
- Function call: Note that a function call, by construction, will only have locals as 
parameters. We will record the union of the predicate accesses on record for every 
parameter as the predicate accesses associated with the let-bound variable.

When let-binding an expression, we will calculate the predicate accesses 
based on the rules above. If the let-bound expression is a field access 
or a function call, we will wrap the expression in a sequence of unfoldings 
in expressions, unfolding all predicate accesses calculated. The following subsections 
discuss a few examples. Again, note that throughout these examples we will disregard 
the Ternary guard introduced in https://github.com/JetBrains/SnaKt/pull/62, as this 
will be wrapped around the expression at a later point in translation.

### Simple field accesses

For this simple case, we can clearly see that the approach yields a working
function.

```kotlin
@Pure
fun getFirstValue(node: Node): Int {
    return node.value
}
```
translates to:
```viper
function getValue(node: Ref): Int
    requires acc(sharedPredicate(node), wildcard)
{
    let anon0 == (unfolding acc(sharedPredicate(node), wildcard) in node.value) in
        anon0
}
```

### Nested field accesses

In this example, we can see the different accesses being split into different 
anonymous variables. Note that this encoding would not verify, as the verifier
has no guarantee that unfolding the shared predicate of node yields the shared 
predicate of anon0, as this is only the case if `node.next != null`. However, 
the Ternary guard added later in translation will establish this guarantee.

```kotlin
@Pure
fun getThisOrNextValue(node: Node): Int {
    return node.next?.value ?: node.value
}
```

```Viper
function getThisOrNextValue(node: Ref): Int 
    requires acc(sharedPredicate(node), wildcard)
{
    let anon0 == (unfolding acc(sharedPredicate(node), wildcard) in node.next) in
    let anon1 == (unfolding acc(sharedPredicate(node), wildcard) in unfolding acc(sharedPredicate(anon0), wildcard) in anon0.value) in
    let anon2 == (anon0 != null ? anon1 : null) in 
    let anon3 == (unfolding acc(sharedPredicate(node), wildcard) in node.value) in
    let anon4 == (anon2 != null ? anon2 : anon3) in
        anon4
}
```

### Function calls

For function calls, the necessary predicate accesses are associated with the 
variable let-bound to a function call. If the function returns a reference, 
these predicate accesses are used for later accesses on the reference. Notice 
that the unfold before calling id seems unnecessary at first glance. However, 
we will see later that the precondition will require the sharedPredicate of 
node.next to be available, making this unfold necessary. Also note that there 
are now guarantees on the unfolds happening in the called function. This limitation 
will be discussed in 'Limitations'.

```kotlin
@Pure
fun id(maybeNode: Node?): Node? = maybeNode

@Pure
fun getNextValueFromId(node: Node): Int {
    val nextNode = id(node.next)
    return if (nextNode == null) 0 else nextNode.value
}
```

```Viper
function id(node: Ref): Ref {
    node
}

function getNextValueFromId(node: Ref): Int {
    let anon0 == (unfolding acc(sharedPredicate(node), wildcard) in node.next) in
    let nextNode == (unfolding acc(sharedPredicate(node), wildcard) in (id(anon0))) in
    let anon1 == (0) in
    let anon2 == (unfolding acc(sharedPredicate(node), wildcard) in unfolding acc(sharedPredicate(nextNode), wildcard) in nextNode.value) in
    let anon3 == (nextNode == null ? anon1 : anon2) in
        anon3
}
```

## The used predicate

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

There are three possible places where a function may be used: In another
function, in a method, or in a specification. We will detail these use cases
below.

### In another function

In this case, we need to unfold predicates in a similar way as we did for 
field accesses before calling the function. Note that any shared predicates 
required by the called function must either be directly available in the caller's 
precondition or be contained within the predicates in the caller's precondition. 
Hence, unfolding all collected accesses on call-site is sufficient to guarantee 
a satisfied precondition (assuming the call is guarded against null reference 
appropriately).

```kotlin
@Pure
fun isSecondToLastIndex(node: Node?s, index: Int): Boolean {
    return isLastIndex(node.next, index + 1) 
}
```

```
function isSecondToLastIndex(node: Ref, index: Int): Bool 
    requires acc(sharedPredicate(node), wildcard)
{
    let anon0 == (unfolding acc(sharedPredicate(node), wildcard) in node.next) in
        isLastIndex(anon0, index + 1)
}
```

### In a method

As the shared predicate is present in a method and is being unfolded on field 
accesses with wildcard permissions, it remains in the verification context. Hence, 
we can call the function without any additional work.

```kotlin
fun getLastIndex(node: Node): Int {
    val len = length(node.next)
    return len - 1
}
```

```Viper
method getLastIndex(node: Ref) returns (res: Int)
{
    inhale acc(sharedPredicate(node), wildcard)
    unfold acc(sharedPredicate(node), wildcard)
    var anon0: Ref := node.next
    var len: Int := length(anon0)
    res := len
}
```

### In a specification

If a function is used in a specification, the unfolding logic is slightly changed.
We cannot introduce an anonymous variable for a function's parameter. Instead, 
we need to use the unfolding in expression to unfold all necessary predicates.
This is already implemented in SnaKt and does not need further consideration. 
Further, if the specification is a precondition, we need to require the shared 
predicate of any parameter to satisfy the precondition of the called function.

```kotlin
fun getFirstValue(node: Node): Int {
    preconditions {
        length(node) > 0
    }
    return node.value
}
```

```Viper
method getFirstValue(node: Ref) returns (res: Int)
    requires acc(sharedPredicate(node), wildcard)
    requires length(node) > 0
{
    inhale acc(sharedPredicate(node), wildcard)
    unfold acc(sharedPredicate(node), wildcard)
    res := node.value
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