# Contracts
Information about how contracts work can be found here:
https://github.com/Kotlin/KEEP/blob/master/proposals/kotlin-contracts.md


## Encoding simple effects
Actually there are only 5 different simple effects which can be easily encoded
- `returns()` &rarr; Since we are not interested in proving termination, this effects does not give us any information
  and can be ignored
- `returnsNotNull()` &rarr; `ensures ret != null`
- `returns(true)` &rarr; `ensures ret == true`
- `returns(false)` &rarr; `ensures ret == false`
- `returns(null)` &rarr; `ensures ret == null`

## Encoding conditional effects
Conditional effects can be obtained by attaching a boolean expression to another SimpleEffect effect
with the function implies.
The syntax is the following: `simpleEffect implies booleanExpression`
and can be encoded as `ensures simpleEffect ==> booleanExpression`

example: `returns(false) implies (b)` &rarr; `ensures ret == false ==> b`


## Encoding calls in place
TODO

## FirContractDescription structure
- A `FirSimpleFunction` contains the infos about the contracts in the field `contractDescription`
- `contractDescription.effects` is a list of `FirEffectDeclaration` which represent the effects of the contract
- an object of type `FirEffectDeclaration` has a field called `effect` of type `KtEffectDeclaration`,
  in order to distinguish between different types of effects we have to do pattern matching on this field:
  - is `KtReturnsEffectDeclaration` &rarr; the effect is a `SimpleEffect` and we can understand which kind of
    `SimpleEffect` from the field `value.name`, in particular
    - `returns()` has `value.name = "WILDCARD"`
    - `returnsNotNull()` has `value.name = "NOT_NULL"`
    - `returns(true)` has `value.name = "TRUE"`
    - `returns(false)` has `value.name = "FALSE"`
    - `returns(null)` has `value.name = "NULL"`
  - is `KtConditionalEffectDeclaration` &rarr; the effect is a `ConditionalEffects`
    - `effect.effect.value.name` contains the value of the `SimpleEffect` which is the left part of the implication
    - `effect.condition` contains the boolean expression which is the right part of the implication
      (even though `implies` takes a `Boolean` argument, actually only a subset of valid Kotlin expressions is accepted:
      namely, null-checks (`== null`, `!= null`), instance-checks (`is`, `!is`), logic operators (`&&`, `||`, `!`)
  - is `KtCallsEffectDeclaration` &rarr; the effect is `CallsInPlace`
