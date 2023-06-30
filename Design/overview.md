# Kotlin to Viper translation

We aim to verify [Kotlin Contracts][0] using a translation of Kotlin into Viper.
Once we have a prototype, we will look into extending the set of available contracts.

Foreseeable difficulties:
- How do we represent Kotlin objects in Viper? (`object-model.md`)
- How do we deal with permissions? (partially covered in `object-model.md`)
- How do we translate for loops and other control flow constructs? (`control-flow.md`)
- How do we guess loop invariants? (`invariants.md`)
- How do we translate lambdas and higher-order functions? (`lambdas.md`, `functions-as-parameters.md`)
- How do we deal with parametric polymorphism?
- How do we deal with dynamic dispatch?
- How do we deal with exceptions?

Contracts currently in Kotlin:
- `returns`
- `x == null` and `x != null`
- `x is T`
- `callsInPlace` with invocation kind (`calls-in-place.md`)

We are considering the following new contracts:
- Collection is non-empty
- Index is in bounds for collection
- Key is in dictionary
- Function terminates
- Function does not return

We are at present not looking at concurrency or coroutines, though we do consider
these to be interesting topics for future work.

[0]: https://github.com/Kotlin/KEEP/blob/3490e847fe51aa6deb869654029a5a514638700e/proposals/kotlin-contracts.md
