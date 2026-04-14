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
| Open val                              	| Method Call     	| Since it's open, a subclass might implement it with a custom getter or a var, requiring a method to abstract the access. 	|
| Closed var                            	| Viper Field     	| Direct heap access is used. This requires the verifier to manage permissions (acc(a.f)).                                 	|
| Open var                              	| Method Call     	| To support dynamic dispatch and potential setters in subclasses, we wrap the access in a method.                         	|

## Limitations
- Non-Sealed Structures: <br>
Overridable val fields on non-sealed structures generally cannot be pure functions because they might be overridden by a var in a subclass, which is inherently heap-dependent.
- Manual Logic: <br>Custom getters and setters are always translated into Viper methods to account for the logic inside the get() and set() blocks.
- Verification Limitations:<br> Under this static-type-based approach, certain proofs (like verifying that x == y after a smart cast from a base interface to a specific class) may not be supported by default if the base access was a method and the specific access is a function.



## Examples

### Constructor
```kotlin
class A(val field: Int)
```

```viper
function field_closed(rec: Ref) returns (ret: Ref)
    requires subtype(rec, A)
    ensures subtype(ret, Int)

method constructor_A(f_param: Ref) returns (res: Ref)
    ensures res != null && isType(res, A)
    ensures field_closed(res) == f_param
```

### Dynamic Dispatch Open Val
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

This should generate the following viper code
```viper

method sides_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int) // default, because of open
    ensures subtype(this, Triangle) ==> ret == sides_closed(this)
    ensures subtype(this, Square) ==> ret == sides_closed(this)

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

```viper
// Method for the open base class
method ingredient_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Meat)
    ensures subtype(this, SalamiSandwich) ==> ret == ingredient_closed(this)

// Function for the closed subclass access
function ingredient_closed(this: Ref) returns (ret: Ref)
    ensures subtype(this, SalamiSandwich) ==> subtype(ret, Salami)

method test(s: Ref) {
    requires subtype(s, SalamiSandwich)
    // Static type is SalamiSandwich (closed): use Function
    var i := ingredient_closed(s)
}
```

## Mutable Inheritance Overriding val with var 

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


```viper
field f_Mutable: Ref

method field_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int)
    ensures subtype(this, Immutable) ==> ret == field_closed(this)

function field_closed(this: Ref) returns (ret: Ref)
    ensures subtype(ret, Int)

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