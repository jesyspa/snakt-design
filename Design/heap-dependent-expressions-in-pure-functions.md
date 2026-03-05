# Heap-dependent expressions in pure functions

For a pure function, heap-dependent expressions do not violate purity per se.
In general, as long as we only read from the heap, the function body remains
pure. To add support for such function bodies we will rely on the previously
introduced shared predicate. This predicate grants wildcard permissions to
all immutable fields of a class allowing us to access those. We will require
all necessary shared predicates in the precondition of a pure function and
strategically use 'unfolding in' to ensure heap-accesses in the function are
valid.

## The used access predicate

For now we will limit the implementation to make use of the already provided
shared predicate. While only granting permissions to immutable fields, this
approach is chosen for three reasons:
1. Convert from shared to another predicate: With the shared predicate already
being present to obtain another predicate, one would typically convert the
shared predicate into another predicate using a lemma function or method. As the shared
predicate is class specific it is non trivial to define one (or multiple) lemma
functions handling this conversion.
2. Prevent loss of information: With the shared predicate already being present
and the verifier associating information with it introducing another predicate
raises the question of whether or not information can be 'transferred' to the
other predicate. Especially for recursive predicates this becomes a hard
problem to solve. Consider the following Viper example:

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

In this exmaple we defined another predicate (named the purePredicate) and a lemma method
converting the shared predicate into the other predicate. We then tried to verify the
assertion that holds in the precondition. However, this will not verify. Keeping the shared
predicate will prevent such loss of information

3. Extra permissions: Building another predicate that also supports access to
mutable fields will cause us to inhale permissions to said fields. For these
inhale statements there is no argument for their validity. Hence, the whole 
verification relies on a potentially false assumption. This should be avoided
as much as possible.

## Constructing the precondition of a function

Note that all reference types for which we need to require the shared predicate
can be found in the function's parameters. Furthermore, because the predicate
also contains the predicates for any references within the parameters, no extra
predicates need to be acquired to ensure that potentially nested heap accesses
in the function body work. However, the predicate only contains the predicates
of nested references if they are non-null (see the predicate definition above).
We will discuss the implications of this constraint in the "Nested field
accesses" section.

## Translation

The current encoding looks like the following: 

let t1 := e1 in
let t2 := e2 in
...
let tn := en in
    (some condition) ? r1 : ((some_other_condition) ? r2 : r3)

In this encoding ei is either a linear expression or a ternary expression.
Note however, that if ei is a ternary expressions by definition of the encoding it
may only have local variables (namely previously introduced let-bound variables)
in its then or else branch. Hence, the function body expressoin
can start with 'unfolding in' expressions unfolding all necessary predicates
to grant access to all fields required in the definitions of any let-bound variable.
The expression of the innermost let-binding is different. It is a potentially nested
Ternary expression. ri can be any expression including field accesses on let-bound
variables. Here, it makes sense to unfold the necessary shared predicates
right at the place where they are needed as the verifier then knows under what
conditions this unfold may happen.

In SnaKt, we construct the previously described encoding by tracking two things:
- A list of pairs of variable names and their definition (we call this an 
`SSAAssignment`), where each pair will be translated into a let-bound variable.
- A list of pairs of encountered return expressions and the conditions under which
they are encountered. These pairs will result in the innermost Ternary expression
described above, where the Ternary expression will resolve to the first collected
return expression if its condition is met, to the second if the condition for the first
is not met but the one for the second is met and so on.

To introduce the previously described translation we will do the following:
- For each `SSAAssignment` we will associate what predicates must be unfolded for
this let-bound variable to be defined. Namely, while translating definitions of
let-bound variables we will use the already existing 'hierarchyUnfoldPath' to
determine the class information of any shared predicate that we have to unfold
for this `SSAAssignment` to bevalid
- After collecting all information of the function body we will insert the
necessary 'unfolding in' expressions directly at the field accesses in return
expressions. As we collected the class information for all `SSAAssignemnts` we
can infer any further predicates that need to be unfolded if a field of a
let-bound variable is accessed.

To further elaborate on this approach consider the examples in the following
subsections

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
    unfolding sharedPredicate(node) in
        node.value
}
```

### Nested field accesses

In the example below, we must also unfold the predicate of the reference to
`next` to ensure the access made to the next node is valid. In general, nested
field accesses can be understood as a path. When encountering a nested field
access, we need to unfold all predicates for the types on the path that have
not been previously unfolded. A natural consideration is to simply unfold as
much as possible at the beginning of the function. This, however, would not
work for the example below, as unfolding the predicates implicitly assumes that
the path does not contain a null reference. Below, this is only true in the
`else` branch of the ternary operator (or the Elvis operator in the Kotlin
version); hence, an on-demand solution is required.

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
    unfolding sharedPredicate(node) in 
        node.next == null ? 
            node.val : 
            unfolding sharedPredicate(node.next) in node.next.val
}
```

### Function calls to self

Even though we are unfolding the predicate required by the called function,
this translation still works. This is because, in a verification context,
unfolding a predicate with wildcard permissions does not cause that context to
lose wildcard permissions to the predicate. 

```kotlin
@Pure
fun length(node: Node): Int {
    return if (node.next == null) {
        1
    } else {
        length(node.next)
    }
}
```

```Viper
function length(node: Ref): Int 
    requires acc(sharedPredicate(node), wildcard)
{
    unfolding sharedPredicate(node) in 
        node.next == null ? 
            1 : 
            length(node.next)
}
```

### Limitations

There is a severe limitation in verification capibilities arising from the fact
that conditional assignments write results to intermediate values regardless
of the conditoin that must be met for these to hold. Consider the following
example:

@Pure
fun getNextValueOrDefault(node: Node): Int {
    val defaultOrValue = if (node.next == null) {
        -1
    } else {
        node.next.value
    }
    return defaultOrValue
}
```

This will translate to:

```Viper
function getNextValueOrDefault(node: Ref): Int 
    requires acc(sharedPredicate(node), wildcard)
{
    unfolding sharedPredicate(node) in
    unfolding sharedPredicate(node.next) in
    let anon1 == (-1) in
    let anon2 == (node.next.value) in
    let anon3 == ((node.next == null) ? anon1 : anon2) in
        anon3
}
```

Clearly, this won't verify due to insufficient permissions to the shared predicate
of node.next. Hence, this is a limitation of this approach. However note, that 
the concious user can avoid this by boxing nullity checks into the return expression.
For an example of this please note the code in 'Nested Field Accesses' above

## When the function gets used

There are three possible places where a function may be used: in another
function, in a method, or in a specification. We will detail these use cases
below.

### In another function

In this case, we need to unfold predicates in a similar way as we did for
field accesses before calling the function. Note that any shared predicates
required by the called function must either be directly available in the
caller's precondition or be contained within the predicates in the caller's
precondition.

```kotlin
@Pure
fun isLastIndex(node: Node, index: Int): Bool {
    return length(node) == index + 1 
}
```

```Viper
function isLastIndex(node: Ref, index: Int): Bool 
    requires acc(sharedPredicate(node), wildcard)
{
    unfolding sharedPredicate(node) in 
        length(node) == index + 1 ? 
            true : false
}
```

Further, consider the example calling a function with a heap access as a parameter.
These cases will be handled in the same way field accesses are handled as described
above:

```kotlin
@Pure
fun isNextLastIndex(node: Node, index: Int): Boolean {
    return isLastIndex(node.next, index + 1) 
}
```

```
function isNextLastIndex(node: Ref, index: Int): Bool 
    requires acc(sharedPredicate(node), wildcard)
{
    unfolding sharedPredicate(node) in 
        isLastIndex(node.next, index + 1)
}
```

### In a method

As the shared predicate is present in a method and is being unfolded on field accesses
with wildcard permissions it remains in the verification context. Hence, we can call
the function without any additional work

```kotlin
fun getLastIndex(node: Node): Int {
    val len = length(node)
    return len - 1
}
```

```Viper
method getLastIndex(node: Ref) returns (res: Int)
{
    inhale acc(sharedPredicate(node), wildcard)
    var len: Int := length(node)
    res := len - 1
}
```

### In a specification

If a function is used in a specification, that context must also require the
predicates from the function's precondition to ensure the specification is
valid. If the specification is the one of a function, then the predicate will
be required in the precondition by the translation methodology described above.
If the specification is part of a method however, we must add the shared predicate
to the precondition of said function. However, note that any caller will have the
shared predicate directly available (as described in the subsection above). Hence,
we can safely add the shared predicate as a requirement into the precondition
without causing verification errors.

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
    res := node.value
}
```