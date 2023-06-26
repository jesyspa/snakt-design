# Translating functions as parameters

The `callsInPlace` annotation limits what a function can do with a function
that has been passed to it.  We thus need to be able to deal with instances
of function types as parameters even if we decide to deal with lambdas only
by inlining.

We can model function types as a domain in Viper:

```
domain FunctionObject {}

method invokeFunctionObject(this: FunctionObject)
```

When parameters and return values come into the picture, the situation becomes
more complicated.  To account for the fact that the function object may modify
the fields of any objects passed to it, we need to give their permissions to
the function object, and then have it return them as a postcondition.
Consider example `function_object_impure` in `function-objects.vpr` for a
situation where this is important.

This handling of side effects is not complete.  Viper knows that the fields of
references passed to a function object may change, but does not take into
account that the function object may be a lambda with captured references; see
`function_object_capture` for an example of unsoundness here.
