# Class as predicates
We are trying to encode classes as described in the
[first encoding of class-hierarchies.md](class-hierarchies.md#first-encoding).

## Current status of class encoding
We are considering 3 kinds of fields:
- `val` fields are included in the predicate with `wildcard` permission;
- `var` fields are not included in the predicate, to access them it is necessary to `inhale` the permission and then
`exhale` it. Doing this doesn't allow us todo some verification;
- special fields are included in the predicate with `write` permission (for now the only special field is `size`).

This kind of encoding allows us to represent recursive classes such as `class Rec(cur: Int, next: rec?)` and gives
the opportunity of being able to preserve information about fields (differently form inhaling and exhaling while
accessing a field).

The following hierarchy:
```kotlin
open class Baz

class Foo(val x: Int, var y: Int)

class Bar(val foo: Foo) : Baz()
```
is encoded as follows:
```
field foo: Ref
field x: Int
field y: Int

predicate Bar(this: Ref) {
  acc(this.foo, wildcard) &&
  acc(Foo(this.foo), write) &&
  acc(Baz(this), write)
}

predicate Baz(this: Ref) {
  true
}

predicate Foo(this: Ref) {
  acc(this.x, wildcard)
}
```

# Opened problems
This kind of encoding has still many opened problems that will be described.
## When to unfold
When representing classes as predicates, in order to access a field of a class it is necessary to unfold the
corresponding predicate. The first approach that we considered is to use some getter functions:
```kotlin
open class A {
    val x: Int = 1
}
open class B : A()
class C : B()
```

```
function A$get$x(this: Ref): Int
  requires acc(A(this), write)
{
  (unfolding acc(A(this), write) in
    this.x)
}

function B$get$x(this: Ref): Int
  requires acc(B(this), write)
{
  (unfolding acc(B(this), write) in
    A$get$x(this))
}

function C$get$x(this: Ref): Int
  requires acc(C(this), write)
{
  (unfolding acc(C(this), write) in
    B$get$x(this))
}
```
Accessing fields in that way opens a new problem:
```kotlin
open class A {
    val x = C(1)
}
class B : A()
class C(val y: Int)

fun f(b: B) {
    val u = b.x
    val v = u.y
}
```
Here after accessing `b.x` we got permission only to `B(b)`, so in order to access `u.y` it is necessary to
`unfold B(b)` and then fold it back in order to satisfy the postcondition. 
To do so probably we'll need to store the "parent" of `u` somehow and then recursively unfold "parents" before accessing
`u.y`. The "parent" of a given variable can be intended as the predicate application to unfold before accessing the
variable, since the argument of the predicate application can also have a "parent" this process is recursive.
The resulting viper code should be something like this:
```
method f(b: Ref)
requires B(b)
ensures B(b)
{
    var u: Ref
    var v: Int
    u := B$get$x(b)
    unfold B(b)
    v := C$get$y(u)
    fold B(b)
}
```

Alternatively we can try to require `B(b)` with `wildcard` permission, so that is not necessary to fold it back.
```
method f(b: Ref)
requires acc(B(b), wildcard)
ensures acc(B(b), wildcard)
{
    var u: Ref
    var v: Int
    u := B$get$x(b)
    unfold acc(B(b), wildcard)
    v := u.y
}
```
One last approach can be splitting write and read predicates.


## Aliasing
It is still not clear how to handle aliasing when representing classes as predicates.
To illustrate the problem we can use the following example:
```kotlin
class Bar
fun aliasing(a: Bar, b: Bar) {
    // ...
}
```
If encoded in the following way, the verification will fail with a call like `inhale Bar(a); aliasing(a, a)`
```
method aliasing(a: Ref, b: Ref)
    requires Bar(a)
    requires Bar(b)
    ensures Bar(a)
    ensures Bar(b)
```
A possible solution can be using pre/postconditions which take care of aliasing possibility:
```
method aliasing(a: Ref, b: Ref)
    requires Bar(a)
    requires a !=b  ==> Bar(b)
    ensures Bar(a)
    ensures a !=b  ==> Bar(b)
```
Doing this will add a number of conditions proportional to the square of the number of arguments, moreover is not clear
if this approach can be used for more complex situations. The next section shows an example with a cast in which writing
the right pre/postconditions is not trivial.

The aliasing problem is relevant when having to deal with predicates that require `write` access,
otherwise accessing a predicate with `wildcard` permission does not give any issue.

## Getting missing permissions after a cast
This section will show some ideas for getting the missing permissions after a cast. Since the aliasing problem is showed
in the previous section, problems related to aliasing will be ignored.
```kotlin
open class Bar { val x: Int = 1 }
class Foo : Bar() { val y: Int = 2 }

fun f(bar: Bar) : Int {
    val foo = bar as Foo
    return foo.y
}

fun cast(bar: Bar): Foo = bar as Foo
```
Getting missing permissions in the right way becomes a problem when dealing with predicates that contain some `write`
access permissions (e.g. `List.size`), if it is not necessary to have `write` permissions probably the best option is
to access the predicate with `wildcard` permission.

```
method f(bar: Ref)
    returns (ret: Int)
    requires acc(Bar(bar), wildcard)
    ensures acc(Bar(bar), wildcard)
{
    var foo: Ref
    foo := bar
    inhale acc(Foo(foo), wildcard)
    ret := unfolding acc(Foo(foo), wildcard) in foo.y
}

method cast(bar: Ref)
    returns (ret: Ref)
    requires acc(Bar(bar), wildcard)
    ensures acc(Bar(bar), wildcard)
    ensures acc(Foo(ret), wildcard)
{
    ret := bar
    inhale acc(Foo(ret), wildcard)
}
```

If it is needed to have `write` permissions, in order to access the field `y` it is necessary to `inhale`
the missing permissions. To do so there are some possibilities:

### Inhale and fold
```
method f(bar: Ref)
    returns (ret: Int)
    requires Bar(bar)
    ensures Bar(bar)
{
    var foo: Ref
    foo := bar
    inhale acc(foo.y)
    fold Foo(foo)
    ret := Foo$get$y(foo)
    unfold Foo(foo)
}

method cast(bar: Ref)
    returns (ret: Ref)
    requires Bar(bar)
    // ensuring Bar(bar) is an aliasing problem
    ensures Foo(ret)
{
    ret := bar
    inhale acc(ret.y)
    fold Foo(ret)
}

```
### Ignore and inhale/exhale
```
method f(bar: Ref)
    returns (ret: Int)
    requires Bar(bar)
    ensures Bar(bar)
{
    var foo: Ref
    foo := bar
    inhale acc(foo.y)
    ret := foo.y
    exhale acc(foo.y)
}

method cast(bar: Ref)
    returns (ret: Ref)
    requires Bar(bar)
    // ensuring Bar(bar) is an aliasing problem
    ensures Foo(ret)
{
    ret := bar
    exhale Bar(ret)
    inhale Foo(ret)
}
```
### Magic wands
Since our goal is to get some missing permissions and at the same time we have to be careful of not inhaling permissions
we already have, magic wands seems to be an option to take into consideration.
A magic wand instance `A --* B` abstractly represents a resource which, if combined with the resources represented by 
`A`, can be exchanged for the resources represented by `B`. Magic wands are more complicated than this and using
them will require more in-depth study.
```
method f(bar: Ref)
    returns (ret: Int)
    requires Bar(bar)
    ensures Bar(bar)
{
    var foo: Ref
    foo := bar
    inhale Bar(foo) --* Foo(foo)
    apply Bar(foo) --* Foo(foo)
    ret := Foo$get$y(foo)
    unfold Foo(foo)
}

method cast(bar: Ref)
    returns (ret: Ref)
    requires Bar(bar)
    // ensuring Bar(bar) is an aliasing problem
    ensures Foo(ret)
{
    ret := bar
    inhale Bar(ret) --* Foo(ret)
    apply Bar(ret) --* Foo(ret)
}
```

# Conclusion
Summing up all these considerations, it seems that most of the problems come up when we want to access a predicate with
`write` permissions and for the moment we are only interested in having `write` permission for the `size` field of
`List`. Maybe we can consider to redesign the way lists are treated by making them pure in the viper representation.
Let take the function `add` as example, which currently is encoded in the following way (predicates are still not used):
```
method add(this: Ref, local$element: Int)
  returns (ret: Bool)
  requires acc(this.special$size, write)
  requires this.special$size >= 0
  ensures acc(this.special$size, write)
  ensures this.special$size >= 0
  ensures this.special$size == old(this.special$size) + 1
```
This is the pure way:
```
method add(this: Ref, local$element: Int)
  returns (ret: Ref)
  requires acc(List(this), wildcard)
  ensures acc(List(this), wildcard)
  ensures acc(List(ret), wildcard)
  ensures unfolding acc(List(this), wildcard) in
    unfolding acc(List(ret), wildcard) in
    this.size + 1 == ret.size
```
Doing this may solve some problems, but it will require some work to be done, because currently pre/postconditions 
are just injected to the method translation, while this will require to make list methods special and rewrite them.
