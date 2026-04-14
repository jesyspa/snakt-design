# Kotlin Immutable Fields in Viper
The core goal is to map Kotlin fields to Viper based on whether they are stable (pure) or heap-dependent. By using the static type at the access point, we decide whether to use a Viper function, a method, or a direct field access.

## Stability through Viper Functions
For fields that are guaranteed to be immutable and final (closed), we use Viper functions.
- Advantage: Functions are pure and do not require heap permissions (acc) to evaluate.
- Construction: The relationship between the constructor argument and the field is established in the constructor's postcondition: `ensures A_field(res) == field_val`.
- Subtype Specificity: For covariant overrides, the function uses implications to refine the return type: `ensures subtype(this, SubClass) ==> subtype(result, SpecificType)`

## Static Type Dispatch Logic
Instead of generating complex ternary case distinctions at every call site, the verifier chooses the access method based on the static type of the field.


| Field Characteristic (at Static Type) 	| Viper Construct 	| Reasoning                                                                                                                	|
|---------------------------------------	|-----------------	|--------------------------------------------------------------------------------------------------------------------------	|
| Closed val                            	| Function Call   	| The value is stable and guaranteed not to be overridden by a mutable implementation.                                     	|
| Open val                              	| Method Call     	| Since it's open, a subclass might implement it with a custom getter or a var, requiring a method to abstract the access.	|
| Closed var                            	| Viper Field     	| Direct heap access is used. This requires the verifier to manage permissions.                                 	|
| Open var                              	| Method Call     	| To support dynamic dispatch and potential setters in subclasses, we wrap the access in a method.                         	|
| Getter exists | Method Call | If there is a custom getter, then we always must use a method.


### Constructor
In this example we have a closed class with a closed immutable field. This, can be represented by 
```kotlin
class A(val field: Int)
```

```viper
function field_closed(rec: Ref) returns (ret: Ref)
    ensures subtype(ret, Int)

method constructor_A(f_param: Ref) returns (res: Ref)
    ensures field_closed(res) == f_param
```

In the constructor, we must fix the function output to the supplied value.

### Open Val
When a field is open, it might be overridden by a var or a custom getter in a subclass. At the call site, if the static type is the open class, we must use a Viper Method to allow for this potential dynamic behavior.

```kotlin
open class Shape{
    open val sides: Int = 0
}
class Triangle() : Shape() {
    override val sides : Int = 3
}

class Square() : Shape() {
    override val sides: Int = 4
}

fun main(x: Shape) {
    val s1 = x.sides
    if (x is Triangle) {
        val s2 = s.sides
    }
}
```

Since the types can be covariantely overwritten, we need to make sure that the necessary type information is present. However in this example this is not really relevant.
```viper

method sides_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int) // default, because of open

function sides_closed(this: Ref) returns (ret: Ref)
    ensures subtype(this, Triangle) ==> subtype(ret, Int)
    ensures subtype(this, Square) ==> subtype(ret, Int)

method main(x: Ref) {
    var s1 := sides_open(x)
    if (...) {
        var s2 := sides_closed(x)
    }
}
```


### Covariant Overwrites
```kotlin
open class Meat
class Salami : Meat()

open class Sandwich {
    open val ingredient: Meat = Meat()
}

class SalamiSandwich : Sandwich() {
    override val ingredient: Salami = Salami()
}

fun test(s: SalamiSandwich) {
    val i = s.ingredient 
}
```
We need to add the type information as a postcondition to the method/function. 

```viper
// Method for the open base class
method ingredient_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Meat)

// Function for the closed subclass access
function ingredient_closed(this: Ref) returns (ret: Ref)
    ensures subtype(this, SalamiSandwich) ==> subtype(ret, Salami)

method test(s: Ref) {
    requires subtype(s, SalamiSandwich)
    // Static type is SalamiSandwich (closed): use Function
    var i := ingredient_closed(s)
}
```

### Mutable Inheritance Overriding val with var 

```kotlin
interface Test {
    val field: Int
}

class Mutable(override var field: Int) : Test

class Immutable(override val field: Int) : Test

fun test(x: Test) {
    val r1 = x.field
    when(x){
        is Mutable -> x.field
        is Immutable -> x.field
    }
}
```
In this example we show, how based on the static type we decide which construct to use.

```viper
field f_Mutable: Ref

method field_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int)

function field_closed(this: Ref) returns (ret: Ref)

method test(x: Ref)
    requires subtype(x, Test)
    {
        var r1 := field_open(x)

        if () {
            // Mutable
            var r2 := x.f_Mutable
        }
        if () {
            // Immutable
            var r2 := field_closed(x)
        }
    }
```


## Idea: Read is Always a Method Call

### Problem 1
When we perform a smart cast or simlar, we do not get information over the cast. The following program will fail to verify

```kotlin
fun test(x: Test) {
    val r1 = x.field
    when(x){
        is Mutable -> x.field
        is Immutable -> {
            val r2 = x.field
            verify(r1==r2) // this will fail, because we are missing information from the first read.
            }
    }
}
```


At the moment there is a missing connection between multiple reads if the type information in between changed. Respectively, when we use the `field_open` read, we learn nothing about the the potential values of different types. For example in the example above the equality `r1 == r2` should hold. However at the moment this would not verify. 

### Suggestion 1: Add Subtype Distinction in Open Read Method
A solution would be, to add the known (final) subtype cases to the method for the field access. The above example would change to this:

```
field f_Mutable: Ref

method field_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int) // default for potentially unknown subclasses
    ensures subtype(this, Immutable) ==> subtype(ret, Int)
    ensures subtype(this, Immutable) ==> ret == field_closed(this)

function field_closed(this: Ref) returns (ret: Ref)
```

With this approach the `field_closed` function would never require to be called explicitely. We can also remove the postcondition from the function, since this information is now also given by the `field_open` method.

So the `test` function would be routhly translated into: 
```
method test(x: Ref)
    requires subtype(x, Test)
    {
        var r1 := field_open(x)

        if () {
            // Mutable
            var r2 := x.f_Mutable
        }
        if () {
            // Immutable
            var r2 := field_open(x)
        }
    }
```

### Problem 2: Mutable fields
About the same problem remains as before just only for mutable fields. In the case, where `x` is unique and we want to assert that `r1` and `r2` are equal, it will fail. 

### Suggestion 2: All Read Accesses are Method Calls

We could also add postconditions for final mutable fields, that say, if it is of this type and the receiver has write permissions(which means that it is unique), then the result will be the same as in the viper field.

This would then look like this:
```viper
field f_Mutable: Ref

method field_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int)
    ensures subtype(this, Mutable) ==> subtype(ret, Int)
    ensures subtype(this, Mutable) && [perm(this.f_Mutable) == write ==> ret == this.f_Mutable, true]
    ensures subtype(this, Immutable) ==> subtype(ret, Int)
    ensures subtype(this, Immutable) ==> ret == field_closed(this)

function field_closed(this: Ref) returns (ret: Ref)
```

With this approach every read could be just a call to the method. And properties could be verified that requires some relation between two reads where in between type information was updated. The program would simplify to this:

```
method test(x: Ref)
    requires subtype(x, Test)
    {
        var r1 := field_open(x)

        if () {
            // Mutable
            var r2 := field_open(x)
        }
        if () {
            // Immutable
            var r2 := field_open(x)
        }
    }
```
An Additional benefit is, that this would remove the need of a havoc method. Because if the object is shared, then no permissions are available and therefore the method call gives no information about the value of the return type.

I put together the code for this example and showed how some things could be verified. I used the viper online tool from ETH.  [HERE](https://viper.ethz.ch/viperonline/tool/silver?key=20260414181255ff2512377d325bc4de2d51]