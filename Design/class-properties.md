This document describes designs notes regarding the issue
[KOTLIN-FORMVER-T-101](https://jetbrains.team/p/kotlin-formver/issues/101).

The terminology contained in this document can be found at the following
[link](https://kotlinlang.org/spec/kotlin-spec.html#class-declaration).

## Overview

Problem:

We would like to help Viper verifying the value of class' **read-only properties**.

```kotlin
class Point(val x: Int, val y: Int)

fun testPoint() {
    val p = Point(10, 20)
    // Viper is not able to verify the following boolean formula.
    assert(p.x == 10 && p.y == 20) 
}
```

Goal:

To do so, we need to create new post-conditions on classes constructors
in the Viper code.

Open questions:

- [ ]   What to do with _primary_ constructors?

- [ ]   What about _secondary_ constructors?
  - [ ] What to do with read-only properties initialized by function calls?

- [ ]   What to do with inheritance?

- [ ]   How `init` blocks can be represented in Viper and generate new
        post-conditions accordingly?

## Examples / Test Cases

The document is designed around the following test cases.

Case #1: Read-only Properties in Primary Constructor

```kotlin
class Point(val x: Int, val y: Int)

fun primaryConstructor() {
  val p = Point(x = 10, y = 20)
  // Should verify sucessfully
  verify(p.x == 10 && p.y == 20) 
}
```

Generalization: All classes defining primary constructors with read-only
properties.

---

Case #2: Read-only Properties in Secondary Constructors

```kotlin
class Point(val x: Int, val y: Int) {
  constructor(z: Int) : this(x = z, y = z)
}

fun secondaryConstructor() {
  val p = Point(z = 10)
  // Should verify sucessfully
  verify(p.x == 10 && p.y == 10)
}
```

Generalization: All classes defining a primary constructor, along with
secondary constructors. 

---

Case #3: Inheritance - Adding new Properties

```kotlin
open class Point2D(val x: Int, val y: Int)
class Point3D(x: Int, y: Int, val z: Int) : Point2D(x, y)

fun inheritanceOne() {
  val p = Point3D(10, 20, 30)
  // Should verify successfully
  verify(p.x == 10 && p.y == 20 && p.z == 30)
}
```

Generalization: Parent classes defining primary constructors, and
children classes adding new read-only properties.
---

Case #3': Inheritance - Override in constructor
Since Case #3 might be tricky to implement, this case is introduced.

```kotlin
open class Point2D {
    val x = 0
    val y = 0    
}
class Point3D(override val x: Int, override val y: Int, val z: Int)

fun inheritanceTwo() {
    val p = Point3D(5, 5, 5)
    verify(p.x == 5 && p.y == 5 && p.z == 5)
}
```
---

Case #4: Init Blocks

```kotlin
class C(arg: Int) {
  val i: Int
  init {
    i = arg * arg
  }
}

fun initiBlocks() {
  val c = C(arg = 16)
  // Should verify successfully
  verify(c.i == 256)
}
```

Generalization: All classes defining an `init`  block to initialize
in-class body read-only properties.

---

Case #5: Primary Constructors with Init Blocks

```kotlin
class S(val a: Int, arg: Int) {
    val b: Int
    init {
        b = arg
    }
}

fun primaryCtorWithInit() {
  val s = S(a = 10, arg = 20)
  verify(s.a == 10 && s.arg == 20)
}
```

Generalization: All classes defining an `init`  block to initialize
in-class body read-only properties with primary constructors. 

