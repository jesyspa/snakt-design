# Extension of `unique` to class fields

This is a rough draft of a possible extension of the
uniqueness proposal.  There are still many unresolved
questions here.

## Syntax

We permit the following additional uses of `unique`:

* On classes:
```kotlin
unique class X {
    ...
}
```

* On properties of classes marked `unique`:
```kotlin
unique class X {
    unique var a: A = ...
}
```

## Semantics

When a class `X` is marked unique, all uses of `X` are
automatically marked unique as well: that is, all cases
where `X` appears as the type of a variable, parameter,
property, or where it is a return type.

A property marked `unique` has a `unique` backing field.
This has implications beyond declaring the getter `unique`:
the default getter returns a borrowed (`inPlace`) reference
to the field which makes the object as a whole inaccessible
while it exists.  We treat this as a special case

## Open questions

* How do we express the special status of getters for
  `unique` properties?  Should this be part of the general
  syntax so it can be used for other things as well?
