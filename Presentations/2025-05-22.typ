#import "@preview/touying:0.6.1": *
#import themes.dewdrop: *

#show: dewdrop-theme.with(
  navigation: "none",
  footer-right: "",
  config-info(
    title: "SnaKt",
    subtitle: "Viper-powered formal verification for Kotlin",
    author: [Komi Golov (jesyspa)\ JetBrains],
    date: "PLD Lightning Talks, 2025-05-22",
  )
)

#show link: set text(fill: blue)

#title-slide()

== Formal verification

#columns(2)[
  ```kotlin
  // Kotlin
  fun sumTo(n: Int): Int {
    preconditions { n > 0 }
    postconditions { ret ->
      ret == n * (n-1) / 2
    }
    var r = 0
    var i = 0
    while (i < n) {
      invariant { r == i * (i-1) / 2 }
      r += i
      i += 1
    }
    return r
  }
  ```
  #colbreak()

  #pause
  ```kotlin
  // Viper
  method sumTo(n: Int) returns (r: Int)
    requires n > 0
    ensures r == n * (n-1) / 2
  {
    var i: Int = 0
    while (i < n)
      invariant k == i * (i-1) / 2
    {
      r := r + i
      i := i + 1
    }
  }
  ```
  #pause
  Goals: minimal annotations, gradual verification, proof of concept.
]

== Difficulty 1: Type System

#columns(2)[
  ```kotlin
  // Pair class definition:
  class Pair(val x: Int, val y: Int)

  // Pair construction:
  val p = Pair(3, 5)
  ```

  What type information do we have? #pause
  1. `p` is a reference.
  2. `p` refers to a `Pair`
  3. `p.x` and `p.y` are `Int`s we can read.

  #pause
  Note: in Kotlin, `Int <: Any`, so everything is a reference.
  #colbreak()

  #pause
  ```kotlin
  field x: Ref
  field y: Ref

  predicate IsPair(r: Ref) {
    subType(typeOf(r), PairType())
    acc(r.x, read) && acc(r.y, read)
    IsInt(r.x) && IsInt(r.y)
  }

  method NewPair(x: Ref, y: Ref)
    returns (r: Ref)
    requires IsInt(x) && IsInt(y)
    ensures IsPair(r)
    ensures r.x == x, r.y == y
  ```
]


== Difficulty 2: Mutability

#columns(2)[
  ```kotlin
  class MutPair(var x: Int, var y: Int)

  // later
  val p = MutPair(3, 5)
  f(p)
  val saved = p.x
  g()
  assert(p.x == saved) // ?
  ```

  #pause
  That `assert` can fail!
  `f` can store `p` and `g` can modify it. #pause
  And there's more:
  - Do we have permission to read `p.x`? #pause
    - If yes: what permissions does `g` have?
    - If no: what do we translate the read to? #pause
  - Things are even worse for writes.
  #colbreak()
  
  #pause
  *Solution 1:* Do not reason about mutable heap values. 
  Make no assumptions, prove nothing about your programs. :(

  #pause
  *Solution 2:* Uniqueness type system.
  - References marked `unique` don't alias.
  - Full permissions are tracked for `unique` references,
    verification possible.
  - Notion of `borrow`ing also required. #pause
  - Worked out by Protopapa [1].
  - Implementation still WIP, could be a thesis or internship project.

  #pause
  Want to know more? Send me a DM.
]


== Bibliography

[0]: F. Protopapa,
  #link("https://thesis.unipd.it/handle/20.500.12608/70919")[_Verifying Kotlin Code with Viper by Controlling Aliasing_],
  master thesis at Padua University, 2024.