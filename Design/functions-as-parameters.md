# Translating functions as parameters

The `callsInPlace` annotation limits what a function can do with a function
that has been passed to it.  We thus need to be able to deal with instances
of function types as parameters even if we decide to deal with lambdas only
by inlining.

We can model objects of function type as references with an associated counter
of the number of times that they have been invoked.  (Strictly speaking, we could
perhaps use this counter only when we are actually interested in this number
of calls; however, uniformity may make our life easier.)

```
field FunctionObject_num_calls: Int
predicate FunctionObject(this) {
  acc(this.FunctionObject_num_calls)
}

function FunctionObject_get_num_calls(this: Ref): Int
  requires FunctionObject(this)
{
  unfolding FunctionObject(this) in this.FunctionObject_num_calls
}

method invokeFunctionObject(this: Ref)
  requires FunctionObject(this)
  ensures FunctionObject(this)
  ensures FunctionObject_get_num_calls(this) = old(FunctionObject_get_num_calls(this)) + 1
```

When parameters and return values come into the picture, the situation becomes
more complicated.  To account for the fact that the function object may modify
the fields of any objects passed to it, we need to give their permissions to
the function object, and then have it return them as a postcondition.
Consider example `function_object_impure` in `function-objects.vpr` for a
situation where this is important.
This can, however, be done simply by exhaling and then again inhaling these
permissions.

This handling of side effects is not complete.  Viper knows that the fields of
references passed to a function object may change, but does not take into
account that the function object may be a lambda with captured references; see
`function_object_capture` for an example of unsoundness here.
