## Overview

We want to express Kotlin properties as Viper fields as much as possible
for Viper to be able to prove more.
However, there are many obstacles because there exist
_open and custom getters and/or setters_ in Kotlin.

For example, consider the following piece of code:
```kotlin

interface Foo {
    val bar: Int?
}

fun func(foo: Foo) {
    if (foo.bar != null)
        verify(foo.bar != null)
}
```

Unfortunately, neither Kotlin itself nor our plugin should be able to verify
such a statement. Indeed, there might be an implementation of `Foo` looking
like this:
```kotlin
class Baz: Foo {
    private var deception = false
    override val bar: Int?
        get() = if (deception) null else { deception = true; 0 }
}
```

Note that this might happen even in case the field is initially
declared with the default getter:

```kotlin
open class Foo {
    open val bar: Int? = 0
}
```

Therefore, in some contexts instead of direct field access we need to call
some method.

## Proposed algorithm

### Registering properties

For each declared property in each class, let's generate
1. if the property has custom (or abstract) getter or setter, __viper access methods__.
2. if the property has default getter and setter, and it is final, __viper field__.
3. if the property has default getter and setter, but it is not final, __both field and access methods__.

### Lookup (determining the right method or field by given type and property)

1. 1. First, let's find the lowest type (it may be both interface and class) 
in the class hierarchy which declares this property
(which is still higher than the given type).
   2. There might be cases when we cannot choose the single type 
(consider interface inherited from other two interfaces).
In such a case we should choose the type with the narrowest type of property.
   3. If there is still more than option let's prefer classes to interfaces.
For example, it might be useful in very strange cases like
       ```kotlin
       interface A {
           val f: Int
       }
       
       abstract class B {
           val f: Int = 4
       }
       
       abstract class C: A, B()
       ```
      Here, although `C` is not final we can use Viper field for the field access to property `f`.

    __NOTE__: lookup by name is discouraged. There should be a FIR way to do this.
Most likely similar algorithm is already implemented somewhere in the repo.
Reason (`C` here inherits `A`'s `f`):
    ```kotlin
    interface A {
        val f: Int
            get() = 4
    }

    open class B {
        private val f: Int = 3
    }

    class C: B(), A
    ```
2. The rest is simple:
   1. We use Viper field if the found property has it and either it is final or our type is final.
   2. Otherwise, we use the method.

## Side notes

1. If we deal with casts honestly (i.e. change the `TypeEmbedding` of `ExpEmbedding`),
then we might suddenly change our policy on how we're accessing properties of the same
object. This is most likely undesirable (for example, this might be a reason not to change
`ExpEmbedding` while upcasting).
2. In some cases we may know some additional information about the object.
For example, here
    ```kotlin
    open class A {
        open val f: Int = 4
    }
    
    fun createA() {
        val a = A()
        TODO("... code continues ...")
    }
    ```
    we know that although `a` is of open class `A` we're allowed to access its `f` as a viper field.
    But it is unclear whether it is possible/worth to utilize this kind of information.
3. 