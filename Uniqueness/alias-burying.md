# Dealing with aliasing

This document outlines the issue of aliasing and provides a summary of a potential solution, as detailed in the paper [
*Alias Burying: Unique Variables Without Destructive Reads*](https://onlinelibrary.wiley.com/doi/abs/10.1002/spe.370).
It then shows how the solution can be employed to refine the verification process achieved by converting Kotlin into
Viper.

# Aliasing problem overview

As described in [The Geneva Convention](https://dl.acm.org/doi/pdf/10.1145/130943.130947) aliasing between references
can make it difficult to verify simple programs.
Let's consider the following Hoare formula: $$\{x = true\} y := false \{x = true\}$$ If $x$ and $y$ refers to the same
reference (they are aliased) the formula is not valid.

The set of (object address) values associated with variables during the execution of a method is a context. It is only
meaningful to speak of aliasing occurring within some context; if two instance variables refer to a single object, but
one of them belongs to an object that cannot be reached from anywhere in the system, then the
aliasing is irrelevant.

Within any method, objects may be accessed through paths rooted at any of:

- Self
- An anonymous locally constructed object
- A method argument
- A result returned by another method
- A (global) variable accessible from the method scope
- A local method variable bounded to any of the above

An object is **aliased** with respect to some context if two or more such paths to it exist.

# Aliasing problem while encoding Kotlin into Viper

The problem described above is reflected in Kotlin and its encoding into Viper.

Let's consider this example:

```kotlin
class A(var a: Int)

fun f(a1: A, a2: A) {}

fun main(a3: A) {
    f(a3, a3)
}
```

Since aliasing is allowed in Kotlin, it is not possible to represent `A` as a predicate and require the predicate to be
true in preconditions and postconditions. In fact doing that would make the encoding of `main` not to verify.

```
field a: Int

predicate A(this: Ref){
    acc(this.a)
}

method f (a1: Ref, a2: Ref)
requires A(a1) && A(a2)
ensures A(a1) && A(a2)

method use_f (a3: Ref)
requires A(a3)
ensures A(a3)
{
    f(a3, a3) // does not verify
}
```

Aliasing is also problematic for the static analyzer used by IntelliJ IDEA

```kt
class A(var a: Boolean = false)

fun f(a1: A, a2: A) {
    a1.a = true
    a2.a = false
    // suggestion: Condition '!a1.a' is always false 
    if (!a1.a) {
        println("ALIASED!")
    }
}

fun main() {
    val a1 = A()
    f(a1, a1) // prints "ALIASED!"
}
```

# Uniqueness

The value of a *unique* variable is either `null` or it refers to an *unshared* object. This specific situation is
identified as the *uniqueness invariant*.
It is easy to see that problems previously described could be solved by annotating a variable as *unique*. Additionally,
uniqueness could be utilized to perform compile-time garbage collection.

# Destructive reads

We are most likely not going to choose the "destructive reads" approach, but it's worth mentioning.
In this approach, a *unique* variable is atomically set to null at the same time its value is read. This action
maintains the *uniqueness invariant*. However, programming with destructive reads can be awkward, and furthermore, this
approach is unsuitable for Kotlin due to null-safety requirements.

# Alias burying

Alias burying keeps the *uniqueness invariant* but only require it to be true when it is needed. So the *uniqueness
invariant* is thus not actually true at every point in the program, but the points when it is false are ‘uninteresting’.

The single most useful feature of uniqueness is that when one reads the value of a unique variable, one knows that if
the value is not null, the object referenced is not accessible through any other variable.
When a unique field of an object is read, all aliases of the field are made undefined.

## Checked annotations

The simple *alias burying* rule suffers from having a global effect: a read of a unique field can potentially make a
great number of variables undefined, many not even in scope. Here we describe how the analysis uses checked annotations
on procedures and preemptive alias burying so that it can work correctly knowing only about local aliases.

*Lattice for annotations and variable state*
$$
\top = \text{undefined} \\ \sqcup \\
\flat = \text{borrowed shared} \\ \sqcup \\
\sharp = \text{owned shared} \\ \sqcup \\
\bot = \text{owned unique}
$$

- The annotation on a parameter must be from the set $\{\bot, \sharp, \flat\}$
- The annotation on the return value must be from the set $\{\bot, \sharp\}$
- The annotation on a field must be from the set $\{\bot, \sharp\}$

The ordering in the lattice means that a value with a particular annotation is included in the higher annotations as
well. For example, a *unique* value may be passed to a procedure expecting a *shared* parameter, but a *borrowed* value
cannot be.

The interface annotations may be read as obligations and dual privileges:

- **Unique parameters:** The caller of a procedure must ensure that parameters declared unique are indeed unaliased. A
  procedure may assume unique parameters are unaliased.

- **Borrowed parameters:** A procedure must ensure that a borrowed parameter is not further aliased when it returns. A
  caller may assume that a borrowed actual parameter will not be further aliased when the procedure returns.

- **Unique return values:** A procedure must ensure that a return value declared unique is indeed unaliased. A caller
  may assume that a unique return value is unaliased.

- **Unique on proc entry:** The caller of a procedure must ensure that any unique field read or written by the
  procedure (or by a procedure it calls, recursively) is unaliased at the point of call. A procedure may assume that the
  first time it reads or writes a unique field, the field has no (live) aliases.

- **Unique on proc exit:** A procedure must ensure that any unique field it reads or writes during its execution is
  unaliased upon procedure exit, and that no fields have been made undefined. A caller may assume that a procedure does
  not create any aliases of unique fields or make fields undefined.

## Checking a procedure

If all procedures fulfill these responsibilities, then the only potentially live variables that may be made undefined
due to alias burying in a procedure are variables set by this procedure. Thus assuming we can check a procedure, we can
check a program.

The analysis uses an abstract store semantic and is described in [Solving Shape-Analysis Problems in Languages with
Destructive Updating](https://dl.acm.org/doi/pdf/10.1145/271510.271517). This
topic can be explored more deeply if we decide to go for this approach.

# Alias burying and Viper

The first simple idea can be to create a function in Viper tin order to represent unique references:

```
function is_unique(r: Ref) : Bool
```

## Unique parameters

Assuming we are able to check the correctness of the alias burying annotations, some issues in the Kotlin to Viper
encoding can be solved.

Defining function `f` with `unique` annotations solves the accessing problems since we are sure that `a1` and `a2` will
not be aliased.

```kt
class A(var a: Int)

fun f(a1: unique A, a2: unique A) {}
```

Since annotations are checked, we can be sure that the references passed to `f` are unaliased and so the verification
cannot fail due to the condition `require A(a1) && A(a2)`

```
function is_unique(r: Ref) : Bool

predicate A(this: Ref){
    acc(this.a)
}

method f (a1: Ref, a2: Ref)
requires A(a1) && A(a2) 
requires is_unique(a1) && is_unique(a2)
ensures A(a1) && A(a2)
```

## Borrowed parameters

As described before a function must ensure that a borrowed parameter is not further aliased when it returns.
One thing we can do is to require the class predicate to be true in the case the reference passed is `unique` and inhale
it when the reference is not guaranteed to be `unique` but we need write access.

```kt
fun f(a1: borrowed A) {
    a1.a = 42
}

fun use_f(a1: unique A) {
    f(a1)
}
```

```
method f (a1: Ref)
requires is_unique(a1) ==> A(a1)
ensures is_unique(a1) ==> A(a1)

// added to show that we can prove something when a unique ref is passed
ensures is_unique(a1) ==> unfolding A(a1) in a1.a == 42
{
    if (!is_unique(a1)){
        inhale A(a1)
    }
    unfold A(a1)
    a1.a := 42
    fold A(a1)
    if (!is_unique(a1)){
        exhale A(a1)
    }
}

method use_f (a1: Ref)
requires A(a1) && is_unique(a1)
ensures A(a1)
{
    f(a1)
    // this assertion verifies because a1 is unique
    assert unfolding A(a1) in a1.a == 42
}
```

## Unique return values

```kt
fun f1(): unique A { }
```

can be encoded as

```
method f1 () returns (ret: Ref)
ensures is_unique(ret) && A(ret)
```

## Unique fields

By representing classes as predicates, encoding `unique` fields should be straightforward.

```kt
class B(var x: unique A)
```

can be encoded as

```
field x: Ref

predicate B(this: Ref) {
    acc(this.x) &&
    A(this.x) &&
    is_unique(this.x)
}
```
