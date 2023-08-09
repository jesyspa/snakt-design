# Contracts
Given a method
- contracts are represented in the FIR as a function call with a single lambda expression as argument s.t. 
  - `calleeReference.name == 'contract'`
  - `calleeReference.resolvedSymbol.callableId.packageName == 'kotlin.contracts'`
  - `calleeReference.resolvedSymbol.callableId.callableName == 'contract'`
- the contract must be the first statement of the method block
- it is not possible to have more than one contract for a method, but the lambda passed to the contract can have multiple lines and each line is an effect 

So given the body of a method, it contains a contract iff the first statement of that block is a contract

`MethodConversionContext` can be edited in the following way:
- adding a parameter for an easier access to the effects
- the method `convertBody` already ignores contracts
- creating a method that returns a list of expressions (maybe empty) corresponding to the effects of the contract, this list will be passed to `toMethod` as the list of post conditions
- translating the effects:
  - `returns()` Since we are not interested in proving termination, this effects does not give us any information
  - `returnsNotNull()` can be translated in a viper NeCmp exp
  - `returns(smth)` can be translated in a viper EqCmp exp
  - `returns(smth) implies (BoolExp)` can be translated in a viper implies expr

In order to understand how the effects are represented in the FIR, let take this example into consideration

```Kotlin
@OptIn(ExperimentalContracts::class)
fun contract(b: Boolean): Boolean {
  contract {
    returns()
    returnsNotNull()
    retruns(true)
    returns(false) implies (b)
  }
  if (b) {
    return false
  } else {
    return true
  }
}
```

## effects in the FIR
in an object of type FirSimpleFunction which contains a contract
- `declaration.body.statements[0].call.argumentList.arguments[0].expression.anonymousFunction.body.statements` contains the list of effects
- an easier way to access the effects list is `declaration.contractDescription.effects`, but in order to access it, probably we'll need to add another parameter to `MethodConversionContext`
  - `returns()` has `value.name = "WILDCARD"`
  - `returnsNotNull()` has `value.name = "NOT_NULL"`
  - `returns(true)` has `value.name = "TRUE"`
  - `returns(false) implies (BoolExp)` has `effect.value.name = "FALSE"` and `effect.condition.name = b`
- we can distinguish between simpleEffect, conditionalEffect and CallsInPlace with pattern matching on the type