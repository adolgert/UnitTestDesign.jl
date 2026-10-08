# UnitTestDesign.jl

Describe the configurations your code must handle; it tells you which
combinations your tests exercise, and supplies a compact set of additional
cases covering the rest.

```
pkg> add UnitTestDesign
```

That installs 0.5, which needs Julia 1.10 or later.

## When to use it

| If you have… | Use… |
|:--|:--|
| Several parameters, a few representative values for each, and bugs that plausibly live in *combinations* of them (an `if` on one option inside a branch on another) | A covering design: [`all_pairs`](@ref), [`all_triples`](@ref), or [`covering`](@ref) |
| The same, but each run is cheap and the full product is small | Every combination: [`full_factorial`](@ref), or `Iterators.product` |
| One known-good configuration, and a question about which single or paired changes break it | [`excursions`](@ref) |
| Hand-written tests already, and a question about which combinations they miss | [`coverage`](@ref), then `must_include` to add cases for the gaps |
| Classes of input to combine, and values to draw within each class | A covering design over [`Partition`](@ref)s picks each parameter's class; a generator draws the value |
| **Use something else:** values you can generate but not list (strings, trees, arbitrary floats), cheap runs, and a hunt for the one input that breaks a routine | Property-based testing, which explores values and shrinks failures ([Supposition.jl](https://github.com/Seelengrab/Supposition.jl)), or fuzzing |
| **Use something else:** a question of how much each factor affects an outcome | Design of experiments. Orthogonal arrays and fractional factorials are balanced for estimation; covering designs are not. |
| **Use something else:** a sweep over continuous parameters | Space-filling samples, such as Sobol sequences or Latin hypercubes |

## Example

A solver takes a mode, a factorization and a tolerance. The factorization
applies only in exact mode, and exact mode needs a tight tolerance. Write the
parameters and those two rules as a [`TestSpace`](@ref), and ask for every
pair of values:

```@example home
using UnitTestDesign

space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])

cases = all_pairs(space)
```

The five cases hold every pair of values that some valid case can hold. The
excluded line counts the pairs that no valid case can hold, and
[`explain`](@ref) names the rules behind one of them, a pair that neither rule
mentions on its own:

```@example home
explain(space, (solver = :lu, tol = 1e-3))
```

[`coverage`](@ref) measures the interaction coverage of tests you already
have:

```@example home
handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
               (mode = :exact, solver = :lu, tol = 1e-6)]
coverage(handwritten, space)
```

and `must_include` keeps those cases first and adds cases for the missing
pairs:

```@example home
all_pairs(space; must_include = handwritten)
```

Each case is a `NamedTuple`, so a test loops over them, here with `solve` as
the function under test:

```@example home
using LinearAlgebra # hide
solve(A, b; mode, solver, tol) = (mode == :fast ? A : solver == :lu ? lu(A) : solver == :qr ? qr(A) : A) \ b # hide
A = [4.0 1.0; 1.0 3.0]; b = [1.0, 2.0] # hide
using Test

@testset "solve" begin
    for (; mode, solver, tol) in cases
        @test solve(A, b; mode, solver, tol) ≈ A \ b
    end
end
nothing # hide
```

The saving grows with the number of parameters. Four parameters of three
values each have 81 combinations, and every pair of their values fits in 9
cases:

```@example home
all_pairs([1, 2, 3], ["low", "mid", "high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim])
```

## What it promises

- Every returned case is valid: it satisfies every constraint.
- Every combination the design asks for (every pair of values at strength 2,
  every triple at strength 3) that at least one valid case contains appears in
  at least one returned case. You never write the rules that other rules
  imply.
- Every combination it leaves out is attributed: *forbidden* by rules it
  names, or *impossible* because the rules it names combine.
- An unknown is never disguised. If a search reaches its budget, generation
  stops with a [`ResourceLimitError`](@ref) that names the limit, and
  `coverage` reports the combination as unresolved, with its counts as bounds
  and no percentage. Nothing is called covered, excluded or complete that was
  not decided.
- The same call, under the same package and Julia versions, gives the same
  cases. [`Auto`](@ref)`()`, the default engine, uses no randomness;
  [`GND`](@ref) draws from a fixed default seed. To keep a list of cases
  across releases and edits, commit it, or pass it back as `must_include`.

The designs are compact, with no promise of a minimum number of cases. Each
result states a proven lower bound beside its count, and says "minimal" when
the count meets it. The default engine, [`Auto`](@ref)`()`, chooses for
your space between IPOG's design and an algebraic array from a catalog,
[`recommend`](@ref) says what it would choose, and [`design_sizes`](@ref)
shows how many cases each strategy gives before you choose one. The full statement is the [contract](dev/contract.md).

## The manual

- **[Tutorial](man/tutorial.md)**: the example above, built up one idea at a
  time, from a one-line call to checking what a design covers.
- **How-to guides**, one per job:
  [test a function with many options](howto/many_options.md),
  [test generic code across types](howto/generic_types.md),
  [plan a CI matrix](howto/ci_matrix.md),
  [run a simulation campaign](howto/simulation_campaign.md),
  [audit and extend an existing suite](howto/audit_existing.md),
  [diagnose a failure](howto/diagnose.md),
  [test invalid inputs](howto/invalid_inputs.md),
  [combine with property-based testing](howto/property_based.md), and
  [commit a design as data](howto/commit_design.md).
- **Explanation**, for why it works this way:
  [choosing values and oracles](explain/values_and_oracles.md),
  [interaction coverage and the evidence](explain/coverage_evidence.md),
  [constraints](explain/constraints.md),
  [engines](man/engines.md), and [IPOG](man/ipog.md).
- **Reference**: [every exported name](reference.md), and the
  [migration table from 0.4](reference/migration.md). 0.5 is a breaking
  release: `disallow` is gone in favor of constraints, and positional calls
  return a `TestCases` of tuples.
- **[For AI agents](man/agents.md)**: the decision rule, three patterns, and
  the one-line check, on one page.
- **Developer**: the [contract](dev/contract.md), the
  [non-goals](dev/non_goals.md), and [contributing](contributing.md).
