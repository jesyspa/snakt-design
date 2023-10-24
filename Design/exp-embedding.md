# Representing Kotlin code: `ExpEmbedding`

A significant difference between Kotlin and Viper is that while Kotlin is
generally an expression-oriented language, with constructs like `if`, `when`,
and `try-catch` being permitted within expressions, Viper is the opposite,
requiring many constructs (in particular method calls) to be their own
statement.  This requires a flattening step as part of the conversion: an
expression like `f() + 1` is converted into

```
var anon1: Int
anon1 := f()
// result: anon1 + 1
```

There are a few things that are annoying here:

1. This linearisation logic is spread throughout the conversion logic, meaning
   that choices about when a result should be placed in a local variable have to
   be made ad-hoc and complicate the conversion as a whole.
2. The imperative nature of conversions means that any kind of nested structures
   are hard to combine.  For example, when we deal with `inhale` and `exhale` or
   `unfold` and `fold` statements, we would often like to simply associate them
   with the innermost statement containing the relevant expression.  However,
   when we are restricted to constructing statements one-by-one, we instead have
   to work around this.  This makes converting a statement like `x.y.z`
   complicated: we should be able to perform this as a single expression, but
   end up instead treating `x.y` as a single statement since it must be enclosed
   in an `inhale`/`exhale`` pair.
3. The conversion process is not pure.  The order in which FIR expressions are
   converted can influence the resulting program, which has lead to bugs before.
4. Sometimes this process gives suboptimal results.  For example, the result of
   a method call is always assigned to an anonymous variable.  However, we could
   have identified that `x = f()` can be converted to Viper almost as-is if we
   could look at the big picture instead of making the choice when converting
   the method call `f()`.
5. Similarly, this means we sometimes introduce scopes when we could have avoided
   it.

We can resolve these issues by splitting the conversion process into an
*embedding* step and a *linearization* step.  `ExpEmbedding` becomes the
intermediate representation, with FIR function bodies embedded into
`ExpEmbedding`, and then linearized into `Stmt`s and `Exp`s.

Note that there are really three places where we generate Viper expressions:
1. The body of a Kotlin function.
2. A Kotlin contract.
3. An axiom for a domain.

In this document, we focus on solving the problem for the first case.  The
situation for the other two cases is quite different, as we cannot produce
auxillary statements in those cases; the whole result must be a single
expression.

## `ExpEmbedding` design considerations

The question of which operations we want to perform in the embedding of FIR into
`ExpEmbedding`, versus which we want to perform as part of `ExpEmbedding`
linearization, is key to the design.

Our guiding principle is that all questions of resolution (name, type embedding,
property implementation, etc.) are best handled during the embedding process,
which has a tree as its result.  The linearization is then entirely focused on
collapsing that tree into a Viper data structure.


### Linearization Context

Linearization takes an `ExpEmbedding` and produces a Viper representation that
will generally include `Stmt`s, `Declaration`s, and an `Exp` that contains the
result of the expression.

In order to maintain the side outputs, we provide the linearization functions
with a context to write the results to.  This is essentially the same system
as we have been using with `SeqnBuilder` so far.

The context also provides functions for deferring certain operations until a
later point.  This allows us to implement `inhale`/`exhale` and `unfold/fold`
pairs more flexibly.  In particular, when we discover that we should perform
such a pair of operations, we typically do not want to emit the corresponding
statements immediately.

For `inhale`/`exhale` consider the expression `a.x + a.x` where `x` is a `var`
property with a default implementation.  The following code is a possible
valid compilation, but is needlessly complicated:
```
var anon1: Int
var anon2: Int
inhale acc(a.x)
anon1 := a.x
exhale acc(a.x)
inhale acc(a.x)
anon2 := a.x
exhale acc(a.x)
// result: anon1 + anon2
```

Trying to `inhale` the access immediately, however, causes an issue with a double
inhale:
```
var anon1: Int
inhale acc(a.x)
inhale acc(a.x)
anon1 := a.x + a.x
exhale acc(a.x)
exhale acc(a.x)
// result: anon1 + anon2
```

To resolve this, we instead add `acc(a.x)` to the list of expressions that should
be inhaled before the next added statement and exhaled immediately after it.
We add this expression twice, but can deduplicate it when building the `inhale`
statement.

A downside to this approach is that we must be sure that the access to `a.x` is in
fact contained in this statement.  It is not clear how to resolve this without
having the linearization process explicitly walk the tree.

For `unfold`/`fold`, we perform a similar transformation.  Consider the following
code:

```
class Foo(xs: List<Int>)
fun test(foo: Foo): Int {
   val ys = foo.xs
   if (ys.isNotEmpty()) ys[0]
   else 0
}
```

Here, the predicate of `Foo` should be left unfolded until the end of the scope
where `ys` exists.  We implement this by adding the predicate to a list of what
should be unfolded for this scope; the `unfold` statement is added directly before
the next statement to be added, and the fold statements is added after the scope
is complete.

This approach of explicit tracking of inhaled assumptions and unfolded predicates
also makes it possible to query the context for what assumptions are inhaled and
what predicates are unfolded, which allows us to prevent inhaling or unfolding
twice.


### Special nodes

In addition to nodes representing embeddings of statements and expressions, we
also require a number of special-purpose nodes that provide the linearization
algorithm with extra information.

These nodes can be seen as wrapping an `ExpEmbedding` with extra information; each
contains exactly one `ExpEmbedding` child as a subtree.

#### `Inhaling`

This node contains an assumption and ensures that the subtree is processed with
the assumption inhaled.

#### `Unfolding`

This node contains a predicate reference and ensures that the subtree, as well
as the rest of the scope, is processed with the predicate unfolded.

This node somewhat breaks our tree-based representation, since it has effects 
that are visible in later nodes.  Due to the special nature of lists, it is not
clear whether we can currently do better than this.

#### `Scoped`

This node introduces a new scope and processes the subtree in that scope.

Ideally, we would like this node to identify when this new scope is unneccessary
and fold duplicate scopes this way.

#### `WithPosition`

This node introduces a new position for all subnodes.


### Propagating results

A Kotlin expression evaluates to some value.  During linearization, it may
happen that this value ends up being computed deep inside the linearized form.
For example:

```
// Kotlin
val x = if (b) 1 else 0

// Viper
var x: Int
if (b) {
   x := 1
} else {
   x := 0
}
```

Here, we cannot directly provide a Viper `Exp` that contains the result of the
`if` expression, since `if` in Viper is a `Stmt`.  Instead, to interpret the
`if` expression by itself as a Viper `Exp` we introduce a temporary "result"
variable `anon1` and assign the result to that.  However, this results in the
following redundant code:

```
var x: Int
var anon1: Int
if (b) {
   anon1 := 1
} else {
   anon1 := 0
}
x := anon1
```

In the current design, we could set `x` to be the result variable and only
create an anonymous one if no result variable is present.  However, this would
require *every* expression to handle result variables: the implementation of
addition would have to look as follows:

```
// Pretend for this example that we have a dedicated `FirPlusExpression`
fun convertPlus(e: FirPlusExpression, ctx: LinearizationContext): Exp {
   val left = convert(e.left, ctx.withoutResult())
   val right = convert(e.right, ctx.withoutResult())
   return if (ctx.resultVar != null) {
      ctx.addStatement(Assign(ctx.resultVar, Plus(left, right)))
      ctx.resultVar
   } else {
      Plus(left, right)
   }
}
```

This kind of duplication would prevent redundancy in the code, but is
inconvenient to write out manually.

To resolve this problem, we require `ExpEmbedding` to provide two functions
for obtaining the value:

```
interface ExpEmbedding {
   val type: TypeEmbedding
   fun toViperExp(ctx: LinearizationContext): Exp
   fun toViperStmt(resultHolder: LValue, ctx: LinearizationContext)
}
```

Most implementations will require only one of the two to be implemented,
with the other provided automatically:

```
interface DirectResultExpEmbedding : ExpEmbedding {
   fun toViperStmt(resultHolder: LValue, ctx: LinearizationContext) {
      val result = this.toViperExp(ctx)
      ctx.addStatement(Assign(resultHolder, result))
   }
}

interface NestedResultExpEmbedding : ExpEmbedding {
   fun toViperExp(ctx: LinearizationContext): Exp {
      val var = ctx.freshVar(type)
      this.toViperStmt(var, ctx)
      return var
   }
}
```


## Design result

The above suggests the following, fairly minimal, `ExpEmbedding` interface:

```
interface ExpEmbedding {
   val type: TypeEmbedding
   fun withType(newType: TypeEmbedding): ExpEmbedding
   fun LinearizationContext.toViperExp(): Exp
   fun LinearizationContext.toViperStmt(resultHolder: LValue)
   // Special-purpose functions like the currently present `ignoreCasts`
}
```

We suggest making `toViperExp` and `toViperStmt` extension functions of
`LinearizationContext` because throughout the code, having the context as a
receiver has generally worked well; its functions are very often used, and
many scoping functions replace the context, which makes this style more
consistent.

The interesting work ends up largely in `LinearizationContext`.  The special
functions present correspond closely with the special nodes outlined above.

```
interface LinearizationContext {
   val position: Position

   fun newVar(type: TypeEmbedding): VarEmbedding
   fun withNewVar(
      type: TypeEmbedding, action: LinearizationContext.(v: VarEmbedding) -> Exp
   ): Exp

   fun withInhaledAssumption(e: Exp, action: LinearizationContext.() -> Unit)
   fun withUnfoldedPredicate(p: Predicate, action: LinearizationContext.() -> Unit)
   fun withNewScope(action: LinearizationContext.() -> Unit)
   fun withPosition(pos: Position, action: LinearizationContext.() -> Unit)

   fun addStatement(stmt: Stmt)
   fun addDeclaration(decl: Declaration)
}
```

The `defer` functions can be kept as an implementation detail of the context.

The `withX` functions could be made generic, with the result of the action being
returned in each case.  It is not clear whether this would be useful for anything,
so we do not include it at present.

There is some wrapper code necessary to ensure that the linearization process can
be started; this should be easy to do.

## Big picture

To convert convert a FIR function body to a Viper `Stmt.Seqn`, we proceed in two
steps.  We set up the `StmtConversionVisitor` and a `StmtConversionContext`
(which may be worth renaming to `EmbedFirElementVisitor` and `EmbedFirElementContext`)
and use that to convert the `FirBlock` body to an `ExpEmbedding.Block`.
We then set up a `LinearizationContext` and use that to convert this block into
a `Stmt.Seqn`, which works as the method body.

The way to translate the function header into a signature with contracts and all
is unchanged.
