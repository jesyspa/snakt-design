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

`Unique` annotation grant us full access to the mutable part of a class predicate. This eliminates the risk of
verification errors caused by accessing the same predicate twice due to aliasing.

## Unique parameters

Assuming we are able to check the correctness of the alias burying annotations, some issues in the Kotlin to Viper
encoding can be solved.

```kt
class A(var a: Int)

fun f(a1: @Unique A, a2: @Unique A) {}
```

Since `a1` and `a2` are `Unique`, we can be sure that the references passed to `f` are unaliased and so the verification
cannot fail due to the condition `require A(a1) && A(a2)`

```
predicate A(this: Ref){
    acc(this.a)
}

method f (a1: Ref, a2: Ref)
requires A(a1) && A(a2)
ensures A(a1) && A(a2)
```

## Unique return values

```kt
fun f1(): @Unique A {}
```

can be encoded as

```
method f1 () returns (ret: Ref)
ensures A(ret)
```

## Unique fields

By representing classes as predicates, encoding `Unique` fields should be straightforward.

```kt
class B(var x: @Unique A)
```

can be encoded as

```
field x: Ref

predicate B(this: Ref) {
    acc(this.x) &&
    A(this.x)
}
```

## Borrowed parameters

As described before a function must ensure that a borrowed parameter is not further aliased when it returns.
Since both unique and shared references can be passed as borrowed, we need to make a distinction between them.
One thing we can do is to create multiple instances of the function in order to cover all the cases.

```kt
fun f(a1: @Borrowed A, a2: @Borrowed A) {}
```

```
method f$unique$unique (a1: Ref)
requires A(a1) && A(a2)
ensures A(a1) && A(a2)

method f$unique$shared (a1: Ref)
requires A(a1)
ensures A(a1)

method f$shared$unique (a1: Ref)
requires A(a2)
ensures A(a2)

method f$shared$shared (a1: Ref)
```

# Conclusion

**Pros:**

- Lightweight annotations.
- We are able to prove properties of mutable objects if they are unique (e.g. `List` size) also when borrowed.
- Since borrowed parameters can be unique or shared, many already existing functions don't need to change too much.

**Drawbacks:**

- Encoding of functions with `Borrowed` parameters is not easy.
- The way borrowed parameters are handled will create an exponential number of function instances. This may slow down
  the encoding and the verification.
- Since `Borrowed` parameters can also be shared, it is not possible to perform smart casts for them.
