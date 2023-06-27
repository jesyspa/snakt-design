# Guessing loop invariants

The overall approach to guessing loop invariants is still unclear.  Here are some
thoughts on particular kinds.

## Class membership

As a first approximation, it probably makes sense to assume that any information
we have about class membership is going to be set in stone.  This is not quite
true: a loop could involve us going between different derived classes of one base
class.

## Invocation monotonicity

We need to ensure that the count of the number of calls of a function object is
non-decreasing.  It may seem like a simple monotonicity condition comparing the
new and old value of the number of codes would solve this.  However, Viper doesn't
actually support this kind of thing in loop invariants: it can't conclude that the
loop as a whole doesn't decrease the value.

Instead, we can put a label just before the loop and show that the value before
the loop is a lower bound on the number of calls after each iteration.

