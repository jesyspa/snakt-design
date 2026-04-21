# Kotlin Immutable Fields in Viper
The core goal of this design is to represent immutable fields differently than mutable fields. Since, immutable fields can not change their value, we want to map them to viper functions.
Mutable fields should generally be treated as heap-dependent and use a viper field. 

Unfortunately, only looking at the declaration of the field is not enough. For example, an **immutable** field defined on an interface could be overritten by a **mutable** field.

Therefore we need to make the distinction not only on immutable vs mutable but also on open (can be overwritten) vs closed (can not be overwritten).

# Overview
This document consists of three parts: First, we will propose the simple system and discuss some shortcommings. 

Second, we will suggest some improvements on how to improve the handling of subtyping. 

And Finally, we propose some ideas to unify mutable and immutable field accesses, as well as the havoc system. 

## Assumptions
For simplicity, we assume that every reference that is hold is unique.

## 1. Basic System
First, we want to see to which viper construct different kind of field accesses should be mapped. 

| Field Characteristic (at Static Type) 	| Viper Construct 	| Reasoning                                                                                                                	|
|---------------------------------------	|-----------------	|--------------------------------------------------------------------------------------------------------------------------	|
| Open val/var                              	| Method Call     	| Since it's open, a subclass might implement it with a custom getter or a var, requiring a method to abstract the access.	|
| Closed val*                            	| Function Call   	| The value guaranteed not to be overridden.                                     	|
| Closed var*                           	| Viper Field     	| Direct heap access is used. This requires the verifier to manage permissions.                               	|

*For these two cases we also need to analyze getters. If there are getters defined by the user, then this getters have to be called instead of the call to the function/access to the viper field.

### Dispatch
For this system, we will use the static type to choose the used viper construct. So that means, that if the static type is an interface then always the method is called. Even though the interface might not even have a default implementation for the accessed field.

### Example Closed Fields
Let's have a look at closed fields
```kotlin
class A(){
    val immut : Int = 1
    var mut: Int = 2
    val getter: Int 
        get() = 3
}

fun test(a: A) {
    val l_immut = a.immut
    val l_mut = a.mut
    val l_getter = a.getter
}
```
Since all fields are defined on a class they are closed.

For the immutable field `val immut` we create a viper function:
```viper
function field_immut_closed(this: Ref) : (ret: Ref) 
    requires isType(this, A)
    ensures subtype(ret, Int)

method test(a: Ref){
    var l_immut = field_immut_closed(a)
}
```
We can ensure the subtype relation. Viper function are always pure, which means that given the same receiver it will always return the same return value. 

For the mutable field `var mut` we will use a viper field.
```viper
field field_mut: Ref

method test(a: Ref) {
    // unfold
    var l_mut = a.field_mut
}
```
This works similar to the classical system. Depending on if the reference to `a` is shared, we might need to use a `havoc` call. 

For the mutable field `var getter` we need to call the getter which will be implemented as a method (because it could have side effects).

### Example Open Fields
Open fields are rather simple. We can not reason about the value, because the field can be overwritten and accessing it might even produce side effects.

```kotlin
open class B() {
    open val immut : X = X()
    open var mut : X = X()
}
```
Both field must be translated into a viper method, because the field could be overwritten. Hence we know nothing about the resulting value between reads. Also we can only ensure a subtype relation, because the field could be overwritten with a subtype.

```viper
method field_immut_closed(this: Ref) (ret: Ref)
    requires subtype(this, B)
    ensures subtype(ret: X)

method field_mut_open(this: Ref) (ret: Ref)
    requires subtype(this, B)
    ensures subtype(ret: X)

method test(a: Ref) {
    var l_immut = field_immut_open(a)
    var l_mut = field_mut_open(a)
}
```

### Constructor
In the previous system, when initializing a immutable field the postcondition of the constructor ensured that the value of the corresponding viper field is equal to the provided value. 

With the new system this will change. Now we need to ensure the output of the `field_immut_closed` function.

```
method con(immut: a) : (ret: Ref) 
    ensures field_immut_closed(ret) == immut //assigning the field
```

Otherwhise the constructor remains the same.

### Inheritance
For the inheritance, we will look at this running example:
```kotlin
open class Shape{
    open val property: X = X() 
    open val color: RGB = RGB(255,255,255) 
}

class Triangle() : Shape() {
    override val property : Y = Y()
    override var color : RGBA = RGB(255,0,0,1) 
}

class Square() : Shape() {
    override val property: Z = Z()
    override val color : HSV = HSV(360, 50, 50)
}

fun test(x: Shape) {
    val p_shape = x.property
    if (x is Triangle) {
        val x_triangle = x.sides
        x.color = RGBA(255,0,255,1) 
    }
    if (x is Square) {
        val x_square = x.sides
        val x_color = x.color
    }
}
```
We have `Y <: X` and `Z <: X` but neihter `Y <: Z` nor `Z <: Y`

For every field, we need to create a function if it is open and a method if it is closed. 

For the field `property` we need the following viper constructs:
```viper
function triangle_field_property_closed(this: Ref) : (ret: Ref)
    requires subtype(this, Triangle) 
    ensures subtype(ret, Y)

function square_field_property_closed(this: Ref) : (ret: Ref)
    requires subtype(this, Square) 
    ensures subtype(ret, Z)

method field_property_open(this: Ref) : (ret : Ref)
    requires subtype(this, Shape)
    ensures subtype(ret, X)
```
Since the closed fields have different types. We must ensure the correct type in the postcondition. 


The closed is used, when we know that the accesses field is final (for `Square` and `Triangle`). 

For the field `color` we need the following viper constructs. For the sake of example we have that `Triangle` has it as mutable property, where `Square` has it as immutable.

```viper
//Used for Triangle
field field_color : Ref 

// Used for Square
function square_field_color_closed(a: Ref) : (ret: Ref) 
    requires subtype(this, Square) 
    ensures subtype(ret, HSV)

method triangle_field_color_open(a: Ref) : (ret: Ref)
    requires subtype(ret, Triangle)
    ensure subtype(ret, RGB)
```

The `test` method would then be translated into:

```viper
method test(x: Ref) {
    var prop_shape = field_property_open(x)
    if (*) {
        // x is Triangle
        var prop_triangle := field_property_closed(x)
        
        // unfold
        x.field_color := RGB(255,0,255,1) 
    }

    if (*) {
        // x is Square
        var prop_square := field_property_closed(x)
        var prop_color := field_color_closed(x)
    }
}
```

### Functions without Postcondition
The postconditions on the functions are not that nice. They could also be moved to an axiom. For example the postconditions of `triangle_field_property_closed` could be transformed into this axiom:

```viper
axiom property_field {
    forall this: Ref :: { triangle_field_property_closed(this) }
        isType(this, Triangle) ==> subtye(triangle_field_property_closed(this), Y)
    }
```


### Limitations
Due to the simplicity of this approach, we miss out on some connections. In the above example we can not verify that `prop_shape == prop_square` (reference equality). Even though, when we read ``prop_square``, we know that the initial read `field_property_open` must have returned the same as `field_property_closed` will. 

This problem will be approached in the system #2. 


## 2. Type Case Distinction
This design is an extension of #1. We now want to add a type distinction to the open methods. The idea is to add all the known subtypes to the postcondition of the `open` method. Also for the closed cases we will also add the value returned by the `closed` method to the post condition. Such that we can always call the `open` method. For the above example this would look like this:

```viper
function field_property_closed(this: Ref) : (ret: Ref)
    ensures isType(this, Triangle) ==> subtype(ret, Y)
    ensures isType(this, Square) ==> subtype(ret, Z)

method field_property_open(this: Ref) : (ret : Ref)
    ensures subtype(ret, X) //open cases
    
    ensures isType(this, Triangle) ==> ret == field_property_closed(this)
    ensure isType(this, Triangle) ==> subtype(ret, Y)
    
    ensures isType(this, Square) ==> ret == field_property_closed(this)
    ensure isType(this, Square) ==> subtype(ret, Z)
```

Now we can just call `field_property_open` instead of chooseing between the open and closed construct.

With the approach we make the decision based on this:
- immutable: Call `open` method
- mutable + open: Call `open` method 
- mutable + closed: Use viper field


So the `test` method of the running example would look like this:
```viper
method test(x: Ref) {
    // type is Shape, hence immutable field
    var prop_shape = field_property_open(x)
    if (*) {
        // x is Triangle, hence the field is immutable
        var prop_triangle := field_property_open(x)
        
        // color is mutable and closed
        // unfold
        x.field_color := RGBA(255,0,255,1) 
    }

    if (*) {
        // x is Square, field is immutable
        var prop_square := field_property_open(x)
    }
}
```

This approach allows us to verify some that `prop_shape == prop_square`. Because when assigning the ``prop_shape``, we have this case distinction for the different types. 


### Pure Context
Unfortunately, there are still situations where we need to call the function. In pure context, we are not allowed to call methods. 

### Move into Axiom
Similar as before, we are able to move the subtyping information out of the postconditions into an axiom. 

```viper
axiom property_field {
    forall this: Ref :: { field_property_closed(this) }
        isType(this, Triangle) ==> subtye(field_property_closed(this), Y)
        isType(this, Square) ==> subtye(field_property_closed(this), Z)
}

function field_property_closed(this: Ref) : (ret: Ref)

method field_property_open(this: Ref) : (ret : Ref)
    ensures subtype(ret, X)
    ensures isType(this, Triangle) ==> ret == field_property_closed(this)
    ensures isType(this, Square) ==> ret == field_property_closed(this)
```

## 3. Represent Every Field Read as Method Call
The last stage of the design propsal is to also the reading of mutable + closed fields as method calls. Then every reading field access would be the same method call. 

For this the postcondition of the `open` method must be updated:

```viper
method field_color_open(this: Ref) returns (ret: Ref)
    ensures subtype(ret, RGB)
    ensures isType(this, Triangle) ==> [perm(this.f_Mutable) == write ==> ret == this.field_color, true]
    ensure isType(this, Triangle) ==> subtype(this, RGBA)
    ensures isType(this, Square) ==> ret == field_color_closed(this)
```
The interesting case is, when the type is `Triangle`.  Then we ensure  

`[perm(this.f_Mutable) == write ==> ret == this.field_color, true]`

This is a Inhale-exhale assertions, the first part is used when the statement is inhaled and the second is used when the statement is exhaled. 
When the caller makes the read access, we will inhale the implication. Meaning that, if we have write access to the field (it was unique), we will learn that the result is what is stored in the field. On the other hand, if we do not have write access, meaning we read a mutable field from a shared object, then we will learn nothing about the fields value. Which is equivalen to havocing the field.

### Remarks
- Adding havoc to this method call as well, might be too much. 
- When there are some missing permissions (because of some mistakes in the conversion), we will get an error probabilty much later on, because the read value does not match the field. Until know, the error would happen at the field read because permissions where missing. This will make the debugging experience worse.
- Additionally, we know what needs to be havoced and what not. It makes sense to directly do this in the plugin and not transfer the responsibility to viper. 
- On the other hand, having just one method for field read lookes quite elegant... 
