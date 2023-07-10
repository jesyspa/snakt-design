# Classes and Hierarchies

Kotlin as object-oriented programming languages follow the class paradigm. Therefore, the language
has a system of class hierarchies similar to Java (classes can be extended once,
but they can implement several interfaces).

Let us consider some possible class encodings of classes and their hierarchies in Viper.

## Class Encoding

We have analyzed three possible class encodings. The encoding differs in how class fields are modelled in Viper's heap.
Each encoding can be found inside the `Examples/Viper/Kotlin/classes/` folder.

### First Encoding

Let us take in consideration a Kotlin's class named `A`, defining two fields `foo: Int` (`foo` of type `Int`)
and `bar: Int`.

```kotlin
class A(var foo: Int, val bar: Int)
```

Starting from the example above, we can create a Viper's field for each class' field, using a _name mangling_ technique
(shown in the code Listing below).

A first possible encoding consists of defining, for each class, a new _Viper predicate_. Therefore,
a _Viper's reference_ type is a _Kotlin's reference_ to a given class `C` if and only if the associated predicate
holds true. The predicate is built by giving access to the fields that the class `C` declares.

The encoding can be found inside the file `Examples/Viper/Kotlin/classes/encoding_1.vpr`.

The example below shows a possible Viper translation of the pre-defined class `A`.

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

We can now build the _class constructors_ using _Viper's method_. For the moment, we just focus on the default
constructor, automatically provided by Kotlin when declaring class fields.

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

#### Fields/Properties

Kotlin desugars the class fields declared with `val` and `var` (used inside the constructor) into getters and setters.
Therefore, is reasonable to model getters/setters functions/methods to access/modify the fields.
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

#### Class Hierarchy

With the first encoding is possible to define class hierarchy relationships extending predicates. For example,
given two class `A` and `B`, where `B <: A` (read as "_B extends A_"), we can define `B`'s predicate as follows.

```viper
predicate A(this: Ref) { /* ... */ }

predicate B(this: Ref) { A(this) && /* ... */ }
```

The `B` predicate is a strengthen version of `A`, inheriting all the access predicates defined in the latter. More
concretely, let us see an example of converting a Kotlin's class hierarchy in Viper.

```kotlin
open class A(val foo: Int, val bar: Int)

class B(val zig: Int, foo: Int, bar: Int): A(foo, bar)
```

The equivalent Viper code is the following:

```viper

// Declare A's fields
field A_foo: Int;
field A_bar: Int;

// Declare B's field(s)
field B_zig: Int;

predicate A(this: Ref) {
    acc(this.A_foo) && acc(this.A_bar)
}

predicate B(this: Ref) {
    A(this) && acc(this.B_zig)
}

// The A's constructor is left unchanged from before

method B_new(zig: Int, foo: Int, bar: Int) returns (this: Ref)
    requires true
    ensures B(this)
    ensures unfolding B(this) in this.B_zig == zig
    ensures unfolding B(this) in (unfolding A(this) in this.A_foo == foo)
    ensures unfolding B(this) in (unfolding A(this) in this.A_bar == bar)
{
    this := new(A_foo, A_bar, B_zig)
    this.B_zig := zig
    this.A_foo := foo
    this.A_bar := bar
    fold A(this)
    fold B(this)
}
```

As the reader may notice, the use of predicates causes a lot of verbosity in class constuctor post-conditions. The
situation can get worse if we have a long relationship chain of classes (`D <: C <: B <: A`).

### Second Encoding

The second encoding differs from the first introducing the definition of a `__super` link to the parent's class.
Each child class predicate has access to a `__super` reference field, and the reference must satisfy the parent's class
predicate.

Using the same class hierarchy defined in the [first encoding](#First_Encoding), let us see the corresponding
Viper's example.

The encoding can be found inside the file `Examples/Viper/Kotlin/classes/encoding_2.vpr`.

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

// The A's constructor is left unchanged from before

method B_new(zig: Int, foo: Int, bar: Int) returns (this: Ref)
    requires true
    ensures B(this)
    ensures B_get_zig(this) == zig
    ensures B_get_foo(this) == foo
    ensures B_get_bar(this) == bar
{
    var super: Ref
    super := A_new(foo, bar)

    this := new(__super, B_zig)
    this.__super := super
    this.B_zig := zig

    fold B(this)
}

```

The `B`'s class constructor now it calls the `A`'s class constructor on the `__super` reference.
In this way instances of class `B` can access fields declared in class `A` using the _super_ link (e.g. `this.__super`).

### Third Encoding

The third and last encoding does not make use of any predicates, since their usage involves understanding where
the `fold` and `unfold` statement should be placed into Viper's code. Thus, how do we encode a given Kotlin class?
When modelling classes, it is useful to keep the information about the current reference's type. It is possible
modelling a class hierarchy using a set of inference rules specifing how class hierarchies should "_behave_". That
is as a _partial order_.

The file `Examples/Viper/Kotlin/classes/classes.vpr` defines a new `KClass` Viper's domain to model Kotlin classes.
The file contains all the axioms required to model the class hierarchies as partial order. In addition,
it also contains an utility function to perform the type-casting, that is `as`.

```viper
function as(obj: Ref, klass: KClass): Ref
    requires IsSubType(GetType(obj), klass)
```
For each Kotlin file defining new classes, we extend the `KClass` domain, adding the necessary _subtype_ relationships.

Now, there are two possible way of keeping the class information about a Viper's reference:

1. We encode a new Viper's field called `_kclass: KClass`, thas is accessible by instances of given classes.
This requires the accessibility predicate each time we want to access the `_kclass`, therefore it may be verbose,

2. We rely on the inhaling capabilities of Viper, stating that, using a class constructor's post-condition, the type
of the returned reference is of the type we are interested into.

```viper
domain KClass_1 {
    unique function KClass_A(): KClass

    /* ... */
}

field A_foo: Int;

method A_new(foo: Int) returns (this: Ref)
    ensures acc(this.A_foo)
    ensures this.A_foo == foo
    ensures GetType(this) == KClass_A()
{
    this := new(A_foo)
    this.A_foo := foo
    inhale GetType(this) == KClass_A() // <- Inhaling the class type
}
```

Through this encoding is possible to encode Kotlin's `is` operator pretty easily, we just need to check that a given
reference type is a _sub-class_ (using the `IsSubType` function) of a given class. See the example below.

```kotlin
open class A
class B(): A()

fun doMagic(a: A) {
    if (a is B) {
        println("a is an instance of B")
    }
    else {
        println("a is not an instance of B")
    }
}

```

```viper
method doMagic(a: Ref)
requires IsSubType(GetType(a), KClass_A())
{
    if (IsSubType(GetType(a), KClass_B())) {
        // println("a is an instance of B")
    }
    else {
        // println("a is not an instance of B")
    }
}
```
