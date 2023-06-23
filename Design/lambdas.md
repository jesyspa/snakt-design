# Translating lambdas

Consider a function like 

```
fun foo(): Int {
  var x = 0
  bar() { e(x) }
  return x
}
```

We may want to be able to say something about the value of `x` after the call to `bar`.
A simple solution is to impose an invariant, but this is rather weak.  In reality,
we want to somehow relate the value of `x` to the behaviour of `bar`.
Consider the following example:

```
fun sumup(n: Int): Int {
  var sum: Int = 0
  forEach(1..n) {
    sum += it
  }
  return sum
}
```

The `forEach` function is inline, so we can approach this example by unfolding its definition.
However, here we want to explore what happens if we try to reason about this abstractly,
without the help of inlining.



