# Predicates folding/unfolding

- The main problem is to know when to keep a unique-predicate unfolded and when to fold it back.
- This is less problematic for shared predicates since folding back is not necessary.
- Thanks to the annotation system, we know that when something is passed to a function expecting a unique argument, it
  must be in std form. This means that all the sup-paths have at least default permissions.
- The rule of thumb should be: if a reference is unique at some point in the annotation system, at the corresponding
  point of the Viper encoding its unique-predicate should hold or we should be able to obtain it after applying some
  fold/unfold.
- We can keep track of the assertion that holds at a certain point inside a `PredCtx`. The context can contain:
    - `acc(p, write)`
    - `uniqueT(p)`
    - `acc(p, wildcard)`
    - `acc(sharedT(p), wildcard)`
- when converting a Kotlin statement, we can identify 3 phases:
    - [Phase 1](#reading-the-context): the necessary `fold`, `unfold`, `inhale` and `exhale` statements are added by
      looking at the `PredCtx`.
    - [Phase 2](#updating-the-context): the statement is converted and the `PredCtx` is updated
    - [Phase 3](#additional-viper-statements): some other Viper statements might be added

## Reading the context

- Assignments `p = exp`. We need to access `p` with write permissions, there are 3 alternatives:
    - The `PredCtx` contains `acc(p, write)` -> nothing to do.
    - If the `PredCtx` contains a unique-predicate that after several unfoldings can provide write access to `p`, these
      unfoldings are performed.
    - otherwise access is inhaled.
- Assignments `... = p`. We need to access `p` with at least read permissions, there are 3 alternatives:
    - The `PredCtx` contains `acc(p, write)` or `acc(p, wildcard)` -> nothing to do.
    - If the `PredCtx` contains a predicate that after several unfoldings can provide access to `p`, these unfoldings
      are performed.
    - otherwise access is inhaled.
- when a path `p` is passed to a function expecting a unique, we can look at the `PredCtx` to understand what to do.
  There can be 3 (or 4) cases:
    - The needed predicate is in the `PredCtx` -> nothing to do
    - The `PredCtx` contains the predicate of a sub-path -> we need unfold it
    - The `PredCtx` contains the predicates and access of several sup-paths -> we need to fold them starting from the
      longest sup-paths to the shorter ones.
    - The program is not well-typed -> should be detected before Viper conversion.

## Updating the context

- At the beginning of a method, the `PredCtx` contains the predicates required by the function
- `p = q`:
    - unfoldings performed in the previous phase are reflected into the `PredCtx`
    - if the `PredCtx` contains the predicate of `p` or any sup-path `p.*` , they are removed.
    - if the `PredCtx` contains the access to any sup-path `p.*` , they are removed.
    - if the `PredCtx` contains the **unique**-predicate of `q` or any sup-path `q.*` , a substitution similar to the
      one described in the annotation system is applied.
    - if the `PredCtx` contains the **write** access of any sup-path `q.*` , a substitution similar to the one described
      in the annotation system is applied.
- call:
    - The annotation system guarantees that the same unique predicate is not required twice
    - The annotation system guarantees that if a unique-predicate is required, unique-predicates from its sup-paths are
      not
      required.
    - Foldings/unfoldings performed in the read-phase are also performed inside the ctx.
    - Predicates passed to non-borrowed unique/shared positions are removed from the context.
- `p = m(...)`:
    - first the call is performed
    - if the `PredCtx` contains the access to any sup-path `p.*` , they are removed.
    - if the `PredCtx` contains the predicate of `p` or any sup-path `p.*` , they are removed.
    - if the function returns a unique, we can add that predicate to the `PredCtx`.
    - the shared predicated of the returned value can be added to the `PredCtx`

## Additional Viper statements

- Assignments `p = exp`: if the access to `p` has been inhaled, we need to exhale it.
- When a unique reference is passed to a function expecting a shared argument, its unique predicate must be exhaled
  after the call.
- When a unique reference is passed to a function expecting a borrowed-shared argument, its unique predicate must be
  exhaled and inhaled after the call.

# Problems and TODOs

These are problems and cases to work on that are known but not covered by previous chapters. This has been done to
keep everything as simple as possible.

- Currently, contexts (Δ) are not implemented in the plugin. Understanding when to perform `inhale` and `exhale` after
  passing unique references where shared (maybe borrowed) is expected can be difficult with `PredCtx`. These operations
  can also be added later.
- For the moment this is not considering super-classes, it shouldn't be a problem to include them. In the case handling
  super-classes becomes problematic, we can get rid of them by flattening hierarchies.
- The document doesn't consider nullable references. They can be included by adding a flag to the elements inside
  a `PredCtx`.