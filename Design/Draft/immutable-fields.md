# Immutable fields
The general idea is to represent immutable field as viper functions. Viper function are pure, hence when reading from a field, the same result will be returned.

This has the advantage, that we do not need to care about permissions.

## Examples
### Simple
The most simplest example would look like this:
```kotlin
class A() {
    val field : Int = 5
}
```
When translating to viper, the result should look like this:

```viper
function A_field(rec: Ref) returns (ret : Ref)
    requires subtype(rec, A)
    ensres subtype(ret, Int)
```

Note: How could we use the fact that the value is statically known? This should verify 
```kotlin
fun main() {
    val a = A()
    verify(a.field == 5)
}
```


### Multiple Classes with equal Name
```kotlin
class A() {
    val field : Int = 5
}
class B() {
    val field : Int = 6
}
```
This could be handled with two viper functions, but even with one it would be possible. This however only works, because they have the same type (Int).


### Construction

```kotlin
class A(val field: Int)

fun main() {
    val a = A(5)
}
```
When fields appear in the constructor, then the postcondition of the constructor should ensure, that the value is preserved.

```viper
method constructorA(field: Ref) returns (ret: Ref) 
    ensures A_field(ret) = field
```

multiple constructors should not be an issue, since just the equality must be added to the postcondition.


### Inheritance
General Idea:
- if a field can not be overwritten, it get its function.
- otherwhise it gets a method? 

```kotlin
open class Shape {
    open val sides: Int = 0
}

class Triangle : Shape() {
    override val sides: Int = 3
}

class Square : Shape() {
    override val sides: Int = 4
}
```

```viper
function shape_size(this: Ref) returns (ret: Ref) 
    ensures subtype(ret, Int)
```

```kotlin
fun test() {
    val t = Triangle()
    t.sides // get's translated into call to `shape_size`
}

fun unknown(s: Shape) {
    s.sides
    // What should happen here? Do we need a "dynamic dispatch method?"
}
```



### Overriding with more specific type

```kotlin
open class Meat()

class Salami() : Meat()
class Ham() : Meat()
class Beef() : Meat()

open class Sandwich() {
    open val ingredient: Meat = Meat()
}

class SalamiSandwich : Sandwich() {
    override val ingredient: Salami = Salami()
}

class HamSandwich : Sandwich() {
    override val ingredient: Ham = Ham()
}

class BeefSandwich : Sandwich() {
    override val ingredient: Beef = Beef()
}
```


```viper
function Sandwich_ingredient(this: Ref) returns (ret: Ref)
    ensures subtype(this, SalamiSandwich) ==> subtype(ret, Salami)
    ensures subtype(this, HamSandwich) ==> subtype(ret, HamSandwich)
    ensures subtype(this, BeefSandwich) ==> subtype(ret, BeefSandwich)
    ensures subtype(ret, Meat) // base case
```

Problems:
- must know all the subtypes, is this something we want to be capeable off?


```kotlin
open class Meat()

class Salami() : Meat()
class Ham() : Meat()
class Beef() : Meat()

sealed class Sandwich() {
    open val ingredient: Meat = Meat()
}

class SalamiSandwich : Sandwich() {
    override val ingredient: Salami = Salami()
}

class HamSandwich : Sandwich() {
    override val ingredient: Ham = Ham()
}

class BeefSandwich : Sandwich() {
    override val ingredient: Beef = Beef()
}

fun test(a: Sandwich) {
    val i = a.ingredient
    // do some stuff
    val ii = a.ingredient
    verify(i == ii) 
}
```


## Idea: Dynamic Dispatch Method


```kotlin
open class A()
open class B(): A()
open class C(): B()

class Super(){
    open val field : A
}

class Mid1() : Super() {
    override val field: B = B()
}

class Mid2() : Super() {
    override val field: B = C()
}

class Mid3() : Super() {
    override val field: C = C()
}

class Mid4() : Super() {
    // This is a var field
    override var field : D = D()
}

fun main(s : Super) {
    a.field // what should be done here?
}

// viper

function Mid1_field(a: Ref) returns (ret: Ref)
    ensures subtype(ret, B)

function Mid2_field(a: Ref) returns (ret: Ref)
    ensures subtype(ret, B)

function Mid3_field(a: Ref) returns (ret: Ref)
    ensures subtype(ret, C)

method super_field(a: Ref) returns (ret: Ref) 
    ensures isType(a, Mid1) ==> Mid1_field(a)
    ensures isType(a, Mid2) ==> Mid2_field(a)
    ensures isType(a, Mid3) ==> Mid3_field(a)
    ensures subtype(ret, A) //default condition, Is this really needed?
```


# Conclusions


## Overrideable val fields on non-sealed structures can never be represented using function

This can be seen in this example: 

```kotlin
interface Test {
    val field : Any
}

class A : Test {
    override val field: Any = Any()
}

class B : Test {
    override var field : Any = Any()
}

fun main(t: Test) {
    t.field
}
```
- If `t` is actually of type `A` we want to call a viper function. 
- If `t` is of type `B` we want to have a normal field access.
- This case distinction can not be made with a function, because the function is pure, but we might return different values for different reads (in the `B` case)
- This case distinction can not be made with a method, because in viper, the method body is ignored. Hence information can only be enceded via postconditions which have to be pure.

> Question: What should be done in this situations?
