# Classes and Hierarchies

Kotlin as object-oriented programming languages follow the class paradigm. Therefore, the language
has a system of class hierarchies built-in, similar to Java (classes can be extended one, 
but they can implement several interfaces).

Let us consider a possible encoding of classes and their hierarchies in Viper.

## Class Encoding

```kotlin
class A(var foo: Int, val bar: Int)
```

Starting from the above example, we can create a Viper's field for each class' field, using the _name mangling_ technique.
For each class, we also define a new Viper's predicate for representing a class. Therefore, a reference type is a 
reference to a given class `C` if and only if the associated predicate is true. The predicate is built by giving access 
to the fields that the class declares. The example below shows a possible encoding.

```viper
// Each field is declared as: 
// field {ClassName}_{PropertyName}: {PropertyType};

field A_foo: Int;
field A_bar: Int;

predicate A(this: Ref) 
{
    acc(this.A_foo) && acc(this.A_bar)
}
```

We can now build the class constructors using Viper's method. For the moment, we focus on the default constructor 
provided automatically by Kotlin when declaring class fields.

```viper
method A_new(foo: Int, bar: Int) returns (this: Ref)
    requires true
    ensures A(this)
    ensures unfolding A(this) in this.A_foo == foo
    ensures unfolding A(this) in this.A_bar == bar
{
    this := new(A_foo, A_bar)
    this.A_foo := foo
    this.A_bar := bar
    fold A(this)
}
```

The `A_new` method guarantees that the returned reference satisfies the predicate representing an instance of
class `A`.

### Fields/Properties Encoding

Kotlin desugars the class fields declared with `val` and `var` (inside the constructor) into getters and setters. 
Therefore, is reasonable to model getters/setters to access/modify the fields. 
The property getters can be modelled as pure functions (when the getter is not [overridden][0], 
see the notes below the document). The example below re-use the definition of class `A` seen previously.

```viper
method A_set_foo(this: Ref, foo: Int)
    requires A(this)
    ensures A(this)
    ensures unfolding A(this) in this.A_foo == foo
{
    unfold A(this)
    this.A_foo := foo
    fold A(this)
}

function A_get_foo(this: Ref): Int
    requires A(this)
    ensures unfolding A(this) in result == this.A_foo
{
    unfolding A(this) in this.A_foo
}

function A_get_bar(this: Ref): Int
    requires A(this)
    ensures unfolding A(this) in result == this.A_bar
{
    unfolding A(this) in this.A_bar
}
```

[0]: https://kotlinlang.org/docs/properties.html#backing-fields

## Hierarchy

Class hierarchy is an important aspect to model for Kotlin classes. For the moment, I am omitting the fact each class 
inherits from the `Any` class implicitly. By default, Kotlin classes are closed to extension, but they can be made open 
using the `open` keyword.

```kotlin
open class A(val foo: Int, val bar: Int)

class B(val zig: Int, foo: Int, bar: Int): A(foo, bar)
```

The above Kotlin code is desugared into:

```kotlin
open class A(val foo: Int, val bar: Int)

class B: A {
    val zig: Init
    constructor(zig: Int, foo: Int, bar: Int) : super(foo, bar) {
        this.zig = zig
    }
}
```

From this point we can have different encoding for class hierarchies. Two main encoding are proposed:

1. Encode the sub-class predicate as an extension to the parent one, adding it in conjunction (referred as Encoding 1,
see the file `Examples/Viper/Kotlin/classes/encoding_1.vpr`).

    ```viper
    field A_foo: Int;
    field A_bar: Int;

    field B_zig: Int; 

    predicate A(this: Ref) {
        acc(this.A_foo) && acc(this.A_bar)
    }

    predicate B(this: Ref) {
        acc(this.B_zig) && A(this)
    }
    ```

2. Define a special field `__super` in Viper, and encode the sub-class predicate using the previous rules, but 
with `__super` field satisfying the parent class predicate (referred as Encoding 2, see the 
file `Examples/Viper/Kotlin/classes/encoding_2.vpr`). Currently, this approach does not offer a way
to perform downcasting.

    ```viper
    field __super: Ref;

    field A_foo: Int;
    field A_bar: Int;

    field B_zig: Int;

    predicate A(this: Ref) {
        acc(this.A_foo) && acc(this.A_bar)
    }

    predicate B(this: Ref) {
        acc(this.__super) && acc(this.B_zig) && A(this.__super)
    }
    ```

__TODO__: list pros and cons of both approaches.

## Overriding

__TODO__

## Additional Notes

There are some cases where the user could re-define how a getter of a property works, as shown in the
example below.

```kotlin
class Foo {
    var accessCounter: Int = 0
    val foo: Int
        get() {
            accessCounter += 1
            return accessCounter
        }
}
```

In this case, we can't generate a getter as a Viper function, since we modify a field belonging to the class.