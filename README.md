# UnitTestDesign

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://adolgert.github.io/UnitTestDesign.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://adolgert.github.io/UnitTestDesign.jl/dev)
[![Build Status](https://github.com/adolgert/UnitTestDesign.jl/workflows/CI/badge.svg)](https://github.com/adolgert/UnitTestDesign.jl/actions)
[![Coverage](https://codecov.io/gh/adolgert/UnitTestDesign.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/adolgert/UnitTestDesign.jl)

Describe the configurations your code must handle; it tells you which
combinations your tests exercise, and supplies a compact set of additional
cases covering the rest.

```
pkg> add UnitTestDesign
```

That installs 0.5 once 0.5 is registered. Until then, install the release
branch with `pkg> add https://github.com/adolgert/UnitTestDesign.jl#release/0.5`.
It needs Julia 1.10 or later.

## When to use it

| If you have… | Use… |
|:--|:--|
| Several parameters, a few representative values for each, and bugs that plausibly live in *combinations* of them (an `if` on one option inside a branch on another) | A covering design: `all_pairs`, `all_triples`, or `covering(space; strength)` |
| The same, but each run is cheap and the full product is small | Every combination: `full_factorial`, or `Iterators.product` |
| One known-good configuration, and a question about which single or paired changes break it | `excursions` |
| Hand-written tests already, and a question about which combinations they miss | `coverage`, then `must_include` to add cases for the gaps |
| Classes of input to combine, and values to draw within each class | A covering design over `Partition`s picks each parameter's class; a generator draws the value |
| **Use something else:** values you can generate but not list (strings, trees, arbitrary floats), cheap runs, and a hunt for the one input that breaks a routine | Property-based testing, which explores values and shrinks failures ([Supposition.jl](https://github.com/Seelengrab/Supposition.jl)), or fuzzing |
| **Use something else:** a question of how much each factor affects an outcome | Design of experiments. Orthogonal arrays and fractional factorials are balanced for estimation; covering designs are not. |
| **Use something else:** a sweep over continuous parameters | Space-filling samples, such as Sobol sequences or Latin hypercubes |

## Example

A solver takes a mode, a factorization and a tolerance. The factorization
applies only in exact mode, and exact mode needs a tight tolerance. Write the
parameters and those two rules as a `TestSpace`, and ask for every pair of
values:

```julia-repl
julia> using UnitTestDesign

julia> space = TestSpace(
           (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
           constraints = [
               @require(mode == :exact || solver == :none),
               forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
           ]);

julia> cases = all_pairs(space)
5 cases (lower bound 4) · strength 2 · IPOG · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible under the constraints; see report(cases)
    mode    solver  tol
 1  :exact  :qr     1.0e-6
 2  :exact  :lu     1.0e-6
 3  :exact  :none   1.0e-6
 4  :fast   :none   0.001
 5  :fast   :none   1.0e-6

julia> explain(space, (solver = :lu, tol = 1e-3))
infeasible: no valid case contains (solver = :lu, tol = 0.001); rules 1 and 2 together exclude it (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)

julia> handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
                      (mode = :exact, solver = :lu, tol = 1e-6)];

julia> coverage(handwritten, space)
covers 6 of 11 feasible pairs, 5 missing: (mode = :exact, solver = :none), (mode = :exact, solver = :qr), (mode = :fast, tol = 1.0e-6), (solver = :none, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)
excluded: 3 pairs forbidden, 2 impossible under the constraints
```

The five cases hold every pair of values that some valid case can hold. The
excluded line counts the pairs that no valid case can hold, and `explain` names
the rules behind one of them, a pair that neither rule mentions on its own.
`coverage` measures the interaction coverage of tests you already have, and
`all_pairs(space; must_include = handwritten)` keeps those two cases first and
adds cases for the five missing pairs. Each case is a `NamedTuple`, so a test
loops over them:

```julia
@testset "solve" begin
    for (; mode, solver, tol) in cases
        @test solve(A, b; mode, solver, tol) ≈ A \ b
    end
end
```

The saving grows with the number of parameters: four parameters of three
values each have 81 combinations, and `all_pairs` covers every pair of their
values in 9 cases.

## What it promises

- Every returned case is valid: it satisfies every constraint.
- Every combination the design asks for (every pair of values at strength 2,
  every triple at strength 3) that at least one valid case contains appears in
  at least one returned case. You never write the rules that other rules
  imply.
- Every combination it leaves out is attributed: *forbidden* by rules it
  names, or *impossible* because the rules it names combine.
- An unknown is never disguised. If a search reaches its budget, generation
  stops with a `ResourceLimitError` that names the limit, and `coverage`
  reports the combination as unresolved, with its counts as bounds and no
  percentage. Nothing is called covered, excluded or complete that was not
  decided.
- The same call, under the same package and Julia versions, gives the same
  cases. `IPOG`, the default engine, uses no randomness; `GND` draws from a
  fixed default seed. To keep a list of cases across releases and edits,
  commit it, or pass it back as `must_include`.

The designs are compact, with no promise of a minimum number of cases. Each
result states a proven lower bound beside its count, and says "minimal" when
the count meets it. `Auto()` chooses among the engines for your space,
`recommend` says what it would choose, and `design_sizes` shows how many cases
each strategy gives before you choose one. The full statement is the
[contract](docs/src/dev/contract.md).

* [Documentation](https://adolgert.github.io/UnitTestDesign.jl/stable), with a
  [tutorial](docs/src/man/tutorial.md) that builds up the example above
* [A one-page guide for AI coding agents](docs/src/man/agents.md)
* [JuliaCon 2021 talk](https://www.youtube.com/watch?v=3KIE3yrQ3lw) (YouTube;
  it shows 0.4, and the ideas carry over)

## By situation

### A function with many options

Name its parameters, list a few representative values for each, add the rules
for combinations it does not accept, and loop a `@testset` over
`all_pairs(space)`. See [Test a function with many
options](docs/src/howto/many_options.md).

### Generic code across types

Types are values, so a parameter's domain can be `[Int8, UInt64, Float32,
BigInt]`, and a rule can say which element and accumulator types go together.
See [Test generic code across types](docs/src/howto/generic_types.md).

### A CI matrix

`github_matrix(all_pairs(space))` writes the cases as a GitHub Actions
`include:` list, so every pair of operating system, Julia version and option
runs in some job. See [Plan a CI matrix](docs/src/howto/ci_matrix.md).

### A simulation campaign

When each case is a cluster job, write the cases to a table, run them, and
measure what ran with `coverage`. See [Run a simulation
campaign](docs/src/howto/simulation_campaign.md).

### An existing test suite

`coverage(existing, space)` names the combinations your tests miss, and
`all_pairs(space; must_include = existing)` keeps your tests and adds cases for
the gaps. See [Audit and extend an existing
suite](docs/src/howto/audit_existing.md).

### A failure to explain

`diagnose(cases, passed)` ranks the combinations that appear only in failing
cases, and `followups` proposes a case to separate each one. The ranking is a
set of hypotheses, not a proof. See [Diagnose a
failure](docs/src/howto/diagnose.md).

### Invalid inputs

Mark a value `Invalid(x)` and each negative case holds exactly one invalid
value, so one error cannot hide another. See [Test invalid
inputs](docs/src/howto/invalid_inputs.md).

### Property-based testing alongside

A `Partition` names a class of values and draws a concrete value at run time,
so the design chooses the classes and a generator chooses within them. See
[Combine with property-based testing](docs/src/howto/property_based.md).

### A design to commit

Print the cases with `repr(collect(cases))`, paste them into a test file, and
keep two checks: `iscomplete(coverage(CASES, space))` and
`all(case -> isallowed(space, case), CASES)`. The second catches a new rule
that forbids a committed case, which `coverage` lists as rejected rather than
missing. See [Commit a design as data](docs/src/howto/commit_design.md).

## Upgrading from 0.4

0.5 is a breaking release.

- `disallow` is gone. Name the parameters and write the rule as a constraint:
  `disallow = (n, level, value, kind) -> level == "high" && kind == :optim`
  becomes `all_pairs((n = …, level = …, value = …, kind = …); constraints =
  [@forbid(level == "high" && kind == :optim)])`. A rule sees only complete
  values, never `nothing` for a parameter not yet chosen.
- Positional calls such as `all_pairs([1, 2], ["a", "b"])` return a
  `TestCases{Tuple{...}}`, a read-only vector of tuples, where 0.4 returned a
  `Vector{Vector{Any}}`. Loops, destructuring, indexing and `f(case...)` work
  as before; code that modifies a row or pushes onto the result does not.
- `n_way`, `seeds`, `wayness`, `all_tuples`, `values_excursion`,
  `pairs_excursion`, `triples_excursion` and `GND(M = …)` still work, with a
  deprecation warning. Their replacements are `strength`, `must_include`,
  `stronger`, `covering`, `excursions(…; distance)` and
  `GND(candidates = …)`.
- `generate_tuples`, `Excursion` and the `Counter` keyword are removed.

The [migration table](docs/src/reference/migration.md) lists every change.
