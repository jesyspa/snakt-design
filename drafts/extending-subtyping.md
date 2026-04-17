# Extending the existing subtyping

The current support of subtyping in SnaKt faces certain limitations when it is used in the following situations:

- Casts (from a supertype to a subtype)
- Implicit upcasts (from a subtype to a supertype)
- Reasoning about incompatibleness of different types.

These stem from two fundamental ways in which we handle subtyping at the moment. First, the way we encode subtyping relations between different types, and second, how permissions for heap locations are established for these types.

This document proposes a new approach, which was inspired by PM's Nagini verifier for Python. Using this approach, we can verify programs like the following:

```kotlin
open class Super(open val a: Int) {}
data class Sub1(@override val a: Int, val b: Int) : Super(a) {}
data class Sub2(@override val a: Int, val c: Int) : Super(a) {}

/** Returns a copy of the given object */
fun copy(obj: Sub1): Sub1 {
    postconditions<Sub1> {
        it == obj // structural equality
    }
    return Sub1(obj.a, obj.b)
}
```

## The current subtyping

Based on the previous example, let's discuss how it is being translated right now and why it cannot be verified.

Currently, we encode subtyping using the following elements in our runtime type domain:

**Domain**: Runtime Type Domain `RT` - which holds all existing runtime types.

**Functions**: 

- `isSubtype(t1: RT, t2: RT): Bool` - Core predicate describing the subtyping relation between two types
- `typeOf(r: Ref): RT` - Returns the runtime type of a memory location in the program
- `nullable(t: RT): RT` - Wraps a type into nullable

**Structural Axioms**:

- `subtypeReflexive` - reflexivity of subtyping
- `subtypeTransitive` - transitivity of subtyping
- `subtypeAntisymmetric` - antisymmetry of subtyping

**Nullability Axioms**:

- `nullableIdempotent` - idempotency of nullable
- `nullableSupertype` - a type is a subtype of its nullable type
- `nullablePreservesSubtype` - nullable preserves subtyping hierarchy
- `nullableAnySupertype` - every type is a subtype of `Any?`
- `anyNotNullableTypeLevel` - a nullable type cannot be a subtype of `Any`
- `anyNotNullableValueLevel` - `null` is not a subtype of `Any`

**Smartcasts, Nothing, Null and Unit Axioms**:

- `supertypeOfNothing` - `Nothing` is the bottom type
- `nothingEmpty` - No location can have type nothing
- `nullSmartcastValueLevel` - a location of a nullable type is either `null` or of the wrapped type
- `typeOfNull` - `null` has type `nothing`
- `typeOfUnit` - `unit` is of type `Unit`
- `uniquenessOfUnit` - `unit` is unique

These axioms form the basis on which we encode a program.

Additional types are being added by explicitly stating their subtyping hierarchy in unnamed axioms. For our example:

- `intType() <: anyType()`
- `superType() <: anyType()`
- `sub1Type() <: anyType()`
- `sub2Type() <: anyType()`
- `sub1Type() <: superType()`
- `sub2Type() <: superType()`

In order to describe access to the fields of the used types, we also encode the following access predicates:

```
predicate Super$shared(this: Ref) {
  true
}

predicate Sub1$shared(this: Ref) {
  acc(this.a, wildcard) &&
  isSubtype(typeOf(this.a), intType()) &&
  acc(this.b, wildcard) &&
  isSubtype(typeOf(this.b), intType()) &&
  acc(Super$shared(this), wildcard)
}
```

Our function from above will now be encoded as:

```
method copy(obj: Ref)
  returns (ret$0: Ref)
  requires isSubtype(typeOf(obj), sub1Type())
  ensures isSubtype(typeOf(ret$0), sub1Type())
  ensures acc(Sub1$shared(ret$0), wildcard)
  ensures ret$0 == obj
{
  var anon$0: Ref
  var anon$1: Ref
  inhale acc(Sub1$shared(obj), wildcard)
  unfold acc(Sub1$shared(obj), wildcard)
  anon$0 := obj.a
  unfold acc(Sub1$shared(obj), wildcard)
  anon$1 := obj.b
  ret$0 := constrSub1(anon$0, anon$1)
}
```

As discussed in previous issues, we would like to assert permissions in preconditions. This is necessary, as we would like to call functions, which include casts and field accesses, in pure contexts. Otherwise, a comparision between objects could neveer be used in specifications. This results in: 

```
method copy(obj: Ref)
  returns (ret$0: Ref)
  requires isSubtype(typeOf(obj), sub1Type())
  requires acc(Sub1$shared(obj), wildcard) // new
  ensures isSubtype(typeOf(ret$0), sub1Type())
  ensures acc(Sub1$shared(ret$0), wildcard)
  ensures ret$0 == obj
{
  var anon$0: Ref
  var anon$1: Ref
  unfold acc(Sub1$shared(obj), wildcard)
  anon$0 := obj.a
  anon$1 := obj.b
  ret$0 := constrSub1(anon$0, anon$1)
}
```

If we try to verify this code, it will not hold. The verifier complains that `ensures ret$0 == obj` cannot be verified. This is expected, as we would not expect the newly generated class to have the same reference as the old one.

We need to update this function to use structural equality instead. We can reuse the automatically generated equals method for this. The reasoning behind this is discussed in equality_issue.md. 

The automatically generated Kotlin function is:

```kotlin
override fun Sub1.equals(other: Any?): Boolean {
    if (other !is Sub1) return false
    return a == other.a && b == other.b
}
```

The Viper equivalent would be:

```viper
function Sub1$equals(self: Ref, other: Ref): Bool 
    requires acc(Sub1$shared(self), wildcard)
    requires isSubtype(typeOf(self), sub1Type())
    requires isSubtype(typeOf(other), sub1Type()) ==>
        acc(Sub1$shared(other), wildcard)
{
    isSubtype(typeOf(other), sub1Type()) &&
        (unfolding acc(Sub1$shared(self), wildcard) in
            unfolding acc(Sub1$shared(other), wildcard) in
                intFromRef(self.a) == intFromRef(other.a) &&
                intFromRef(self.b) == intFromRef(other.b))
}
```

As defined in the Kotlin code, the function accepts `other` of type `Any`. However, to access the fields of other, a cast needs to be performed. This is a problem, we require additional permissions after a cast. Futhermore, these are only required if the given object is of the corresponding type. Currently, we resolve this by inhaling the additional permissions after the Kotlin cast. However, this would again result in an inpure function.

We resolve this by using a trick here: We condition the required permissions on the actual type of `other`. The updated code is:

```viper
method copy(obj: Ref)
  returns (ret$0: Ref)
  requires isSubtype(typeOf(obj), sub1Type())
  requires acc(Sub1$shared(obj), wildcard) // new
  ensures isSubtype(typeOf(ret$0), sub1Type())
  ensures acc(Sub1$shared(ret$0), wildcard)
  ensures Sub1$equals(ret$0, obj)
{
  var anon$0: Ref
  var anon$1: Ref
  unfold acc(Sub1$shared(obj), wildcard)
  anon$0 := obj.a
  unfold acc(Sub1$shared(obj), wildcard)
  anon$1 := obj.b
  ret$0 := constrSub1(anon$0, anon$1)
}
```

This verifies without any problems :)

However, let's consider another code example:

```kotlin
fun foo() {
    val sub1 = Sub1(1, 2)
    val sub2 = Sub2(1, 2)
    // L1
    val areEquals = sub1 == sub2
}
```

To my enormous disappointment, this code cannot be verified. The verifier complains that `requires isSubtype(typeOf(other), sub1Type()) ==> acc(Sub1$shared(other), wildcard)` does not hold at point L1. This is somewhat surprising, as we can clearly tell from the Kotlin code that `Sub1` and `Sub2` are not subtypes of each other.

Our axioms however define subtyping as an **uninterpreted function** and the verifier applies an open-world assumption. Our information at point L1 is the following: 

- **Hierarchy**: Super <: Any, Sub1 <: Super, Sub2 <: Super
- **Locations**: typeOf(sub1) <: Sub1, typeOf(sub2) <: Sub2

This means the verifier cannot guarantee that there is a diamond relation with a `class SubSub` with SubSub <: Sub1 and SubSub <: Sub2, and that `sub1` is actually of type SubSub. This cannot be the case in Kotlin, as the classes are final, but this is never declared in the verifier.

This problem could partially be resolved by introducing an axiom of finalness. However, if we change to `val sub2 = Super(1)`, the same error occurs again, as the verifier cannot guarantee that `sub2` is not actually of type Sub1.

The next approach would be to introduce exact types: This means, we update the known information at point L1 to:

- **Hierarchy**: Super <: Any, Sub1 <: Super, Sub2 <: Super
- **Locations**: typeOf(sub1) == Sub1, typeOf(sub2) == Sub2

This now allows us to verify the function if we only pass types that are in one continuous hierarchy, i.e. lie on a single inheritance chain. But again, it cannot prove the previous code example. If we combine both appraoches, everything in this document so far can be verified, but one can easily construct more complicated hierarchies which cannot be verified. We continue here by disregarding the finalness and keeping the exact type approach in min. The reason will become clear in the next section.

## Introducing non-inheritance reasoning

The underlying problem of all previous approaches is that the verifier cannot automatically infer non-subtyping based on our axiomatization. Thus, we need to introduce some reasoning that allows us to prove `T !is S` for arbitrary types `T` and `S`. 

To implement this, I looked at the work done for other verifiers, especially Nagini by PM. 

### Nagini's approach to subtyping

Nagini uses a similar approach to express types and subtyping relations as SnaKt, but it differs in the following: instead of having one *subtypeOf* function to express inheritance between objects, it declares direct parent relations using a specific `extends_` function and then derives subtyping and non-subtyping relations based on that.

The most important elements:

- `extends_` - declares a direct (single step) parent relation
- `issubtype` - describes subtyping between different types, same as in SnaKt, inferred from `extends_`
- `isnotsubtype` - describes incompatible types, inferred from `extends_`

For `extends_`, it is important to understand that it is only used to declare direct steps and consequently never describes transitive steps. In our previous example, it would be used for `extends_(Super, Any)`, `extends_(Sub1, Super)`, and `extends_(Sub2, Super)` and nothing else (excluding primitive types). It is axiomatized by: 

```viper
axiom extendsImpliesSubtype {
    forall sub, super_ ::
        extends_(sub, super_) ==> issubtype(sub, super_)
}
```

`issubtype` is equivalent to SnaKt's `isSubtype`.

The main addition is `isnotsubtype`, which expresses that two types are incompatible. It is derived automatically by reusing the `siblingExclusion` axiom:

```viper
axiom siblingExclusion {
    forall sub, sub2, super_ ::
        extends_(sub, super_) && extends_(sub2, super_) && sub != sub2
        ==> isnotsubtype(sub, sub2) && isnotsubtype(sub2, sub)
}
```

The exclusion is then propagated back to the subtyping function using the `exclusionPropagation` axiom:

```viper 
axiom exclusionPropagation {
    forall sub, middle, super_ ::
        issubtype(sub, middle) && isnotsubtype(middle, super_)
        ==> !issubtype(sub, super_)
}
```

This allows us to conclude that types lower in the hierarchy are still not subtypes of a previously excluded type.

### Proposed changes

In order to support reasoning about negative subtyping between arbitrary types, we should make the following changes:

1. The creation of a new instance of an object returns accurate type information.
2. The existent subtyping encoding is extended to match Nagini's approach.

#### Application to our example

If we extend our previous encoding by these axioms, what do we gain? Let's consider two cases:

```kotlin
fun foo() {
    val sup = Super(1)
    val sub1 = Sub1(1, 2)
    val sub2 = Sub2(1, 2)

    // L2

    // Case 1:
    val eq1 = sub1 == sup

    // Case 2:
    val eq2 = sub1 == sub2
}
```

At point L2, we now have the following information:

- **Hierarchy**: Super <: Any, Sub1 <: Super, Sub2 <: Super, Super </: Sub1, Super </: Sub2, Sub2 </: Sub1, Sub1 </: Sub2 
- **Locations**: typeOf(sup) == Super, typeOf(sub1) == Sub1, typeOf(sub2) == Sub2

Again, we need to satisfy the following before the comparison:

```viper
requires acc(Sub1$shared(self), wildcard)
requires isSubtype(typeOf(self), sub1Type())
requires isSubtype(typeOf(other), sub1Type()) ==> acc(Sub1$shared(other), wildcard)
```

The first two hold trivially. For the third, we need to do a case distinction:

- Case 1: typeOf(sup) == Super && Super </: Sub1 ==> typeOf(sup) </: Sub1 ==> (isSubtype(typeOf(other), sub1Type()) ==> acc(Sub1$shared(other), wildcard))
- Case 2: typeOf(sub2) == Sub2 && Sub2 </: Sub1  ==> typeOf(sub2) </: Sub1 ==> (isSubtype(typeOf(other), sub1Type()) ==> acc(Sub1$shared(other), wildcard))

Thus, both cases hold.

### Required considerations for Kotlin

Of course, Kotlin's subtyping system is not equal to Python's, and we need to consider their different approaches to subtyping. For example, in Kotlin, one could easily construct the following:

```kotlin
interface A 
interface B : A 

class Foo : B, A 
```

If we encode this with a naive approach that translates all subtyping relations directly to `extends_`, this would result in a contradiction: the verifier would infer from the `extends_` that B <: A, Foo <: B, Foo <: A for the positive, and B </: Foo and Foo </: B for the negative subtyping.

Thus, we must prevent translations of redundant inheritance relations from Kotlin. Luckily, this is not difficult, as it maps directly to the graph problem of **transitive reduction** with known solutions.

This also requires some modifications to the existing axioms, as we need to express the `extends_` to various special types (e.g. `Any`), without introducing redundant inheritance.

To my current knowledge, this is the only limitation we need to consider.

## Additional benefits

If this approach is implemented as proposed, we would also gain benefits in the handling of permissions in general. Consider a case where we perform a cast in Kotlin:

```kotlin
fun foo(sup: Super): Int {
    var counter = sup.a

    if (sup is Sub1) {
        counter += sup.b
    } else if (sup is Sub2) {
        counter *= sup.b
    }

    return counter
}
```

Previously, this would have been translated the following way:

```viper
method foo(sup: Ref)
  returns (ret$0: Ref)
  requires isSubtype(typeOf(sup), superType())
  requires acc(Super$shared(sup), wildcard)
  ensures isSubtype(typeOf(ret$0), intType())
{
  var l0$counter: Ref
  var anon$0: Ref
  unfold acc(Super$shared(sup), wildcard)
  anon$0 := sup.a
  if (isSubtype(typeOf(sup), sub1Type())) {
    var anon$1: Ref
    inhale acc(Sub1$shared(sup), wildcard)
    unfold acc(Sub1$shared(sup), wildcard)
    anon$1 := sup.b
    l0$counter := anon$0 + anon$1
  } elseif (isSubtype(typeOf(sup), sub2Type())) {
    var anon$2: Ref
    inhale acc(Sub2$shared(sup), wildcard)
    unfold acc(Sub2$shared(sup), wildcard)
    anon$2 := sup.c
    l0$counter := anon$0 + anon$2
  }
  ret$0 := l0$counter
}
```

> Note: This code is not equal to the actually generated one. Variables, labels and type-related inhales were omitted.

As one can see, this function changes the permission environment for each cast, but this is actually not necessary. Instead, we can apply conditional rules and move the permission handling into the preconditions, as done before:

```viper
method foo(sup: Ref)
  returns (ret$0: Ref)
  requires isSubtype(typeOf(sup), superType())
  requires acc(Super$shared(sup), wildcard)
  requires (isSubtype(typeOf(sup), sub1Type())) ==> acc(Sub1$shared(sup), wildcard)
  requires (isSubtype(typeOf(sup), sub2Type())) ==> acc(Sub2$shared(sup), wildcard)
  ensures isSubtype(typeOf(ret$0), intType())
{
  var l0$counter: Ref
  var anon$0: Ref
  unfold acc(Super$shared(sup), wildcard)
  anon$0 := sup.a
  if (isSubtype(typeOf(sup), sub1Type())) {
    var anon$1: Ref
    unfold acc(Sub1$shared(sup), wildcard)
    anon$1 := sup.b
    l0$counter := anon$0 + anon$1
  } elseif (isSubtype(typeOf(sup), sub2Type())) {
    var anon$2: Ref
    unfold acc(Sub2$shared(sup), wildcard)
    anon$2 := sup.c
    l0$counter := anon$0 + anon$2
  }
  ret$0 := l0$counter
}
```

This leaves us with a **pure** function! No inhales are needed anymore, as the translation between the two functions can easily be achieved. 

Now we only need to consider what happens when we actually want to call this function in another function:

```kotlin
fun bar() {
    val sup = Super(1)
    foo(sup)
}
```

To our convenience, nothing has to be changed! Based on our previous changes to the typing system, the verifier can infer the exact type of `sup`, and thus only requires `acc(Super$shared(sup), wildcard)`, which is always guaranteed by the constructor.

The other case is: 

```kotlin
fun bar(sup: Super) {
    foo(sup)
}
```

This case is not as trivial, unfortunately. Recall, that foo requires multiple different permission conditioned on the runtime type of `sup`. This function however only holds the permission related to the Super type. Thus, the verifier complains that it might not have enough permissions to call `foo(sup)`, if the runtime type of `sup` is a strict subtype of Super. `bar` must consequently also hold the conditioned permissions. Luckily, we have all the information at hand to propagate this. We treat the call to a function which has conditional permissions as if the conditional permissions occurred in the function itself, and propagate them to the preconditions. This allows a sound call to `foo(sup)`.

Concretely, `bar` is translated as follows, lifting `foo`'s conditional permissions into `bar`'s own preconditions:

```viper
method bar(sup: Ref)
  requires isSubtype(typeOf(sup), superType())
  requires acc(Super$shared(sup), wildcard)
  requires (isSubtype(typeOf(sup), sub1Type())) ==> acc(Sub1$shared(sup), wildcard)
  requires (isSubtype(typeOf(sup), sub2Type())) ==> acc(Sub2$shared(sup), wildcard)
{
  foo(sup)
}
```

When `bar` is called in turn, the same propagation applies to its caller, and so on — until a call site is reached where the exact type of the argument is known (e.g. directly after construction), at which point the relevant conditional permission collapses to a concrete one and the chain terminates.

A harder case is mutual recursion:

```kotlin
fun rec1(sup: Super) {
    rec2(sup)
}

fun rec2(sup: Super) {
    rec1(sup)
}
```

As the subtyping relation defined by us (and including the extension with the Nagini axioms) forms a forms a well-founded partial order with finite ascending chains, the calculation of this might be cumbersome, but it is always possible. This should probably be an extension to this work.

Why is this sound in Kotlin? To do this, we must have the guarantee that we actually know the exact type of each instance at some point, in order to not end up in a recursive loop of propagated conditional permissions. But this is guaranteed, as every object in Kotlin is created at some point, and at this point, the dynamic type can be found in the JVM. This, of course, excludes the type erasure in the case of generics, but as demonstrated by Nagini, this can also be handled with an even broader extension of the Runtime Type domain. However, this is beyond the scope of this proposal.

## Conclusion

The proposed extensions to the type encodings of SnaKt make a nice addition, which extends our reasoning capabilities about subtyping noticeably. Furthermore, they would integrate nicely with the existing approach of upcasts, and thus introduce a subtyping system to SnaKt in which permission changes do not alter the environment and thus can be used in pure functions.

As a nice addition, we could also let a user overwrite equals functions in classes, which was a limitation in my other topics.