# For AI agents

This page is for coding agents that write tests, and for the people who review
them.

**The decision rule.** Use UnitTestDesign when the code under test has several
discrete options, each with a few representative values, and running every
combination is too slow or too many to review: `all_pairs` returns a compact
set of cases in which every pair of values appears, and names the combinations
the rules exclude. If the full product is small and each run is cheap, loop
over `Iterators.product` or call `full_factorial` instead. If the inputs are
values you can generate but not list (strings, arrays, arbitrary floats), or
the goal is to find the one value that breaks a routine, use property-based
testing or fuzzing.

**When you report.** Quote the summary line and the `coverage` sentence as
printed, rather than paraphrasing them. The package promises that every
feasible combination is covered and makes no promise about the number of
cases, so report the count as a count, not as a best possible. Results repeat
exactly under the same package and Julia versions; a new release or an edited
space may change every case, so commit the list (pattern 3) when it must not
change.

## Pattern 1: a function with options

Name the parameters, write the rules as constraints, and loop a `@testset`
over the cases. A case splats into keyword arguments.

```@example agents
using UnitTestDesign, Test, LinearAlgebra

# The code under test: `solver` applies only in :exact mode.
function solve(A, b; mode, solver, tol)
    tol > 0 || throw(ArgumentError("tol must be positive"))
    mode == :exact || return A \ b
    return (solver == :lu ? lu(A) : solver == :qr ? qr(A) : A) \ b
end

space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
cases = all_pairs(space)
```

```@example agents
A = [4.0 1.0; 1.0 3.0]
b = [1.0, 2.0]
@testset "solve" begin
    @testset "$case" for case in cases
        x = solve(A, b; case...)
        @test norm(A * x - b) <= case.tol * norm(b)
    end
end
nothing # hide
```

## Pattern 2: generic code across types

Types are values, so a domain can list them. A function-form rule names its
parameters explicitly, which reads better than a macro when the rule tests
types.

```@example agents
# The code under test: sums `v` in an accumulator of type S.
function sum_as(::Type{S}, v::AbstractVector) where {S}
    s = zero(S)
    for x in v
        s += x
    end
    return s
end

types = TestSpace(
    (elt = [Int8, UInt8, Int32, Float32, Float64], acc = [Int64, Float64, BigInt],
     n = [0, 1, 100]);
    constraints = [
        forbid(:elt, :acc; reason = "an integer accumulator cannot hold a float sum") do elt, acc
            elt <: AbstractFloat && acc <: Integer
        end,
    ])

@testset "sum_as" begin
    for (; elt, acc, n) in all_pairs(types)
        s = sum_as(acc, elt.(1:n))
        @test s isa acc
        @test s == n * (n + 1) ÷ 2
    end
end
nothing # hide
```

## Pattern 3: commit the design as data

Generate once and print the cases as a Julia literal:

```@example agents
print(repr(collect(cases)))
```

Paste that literal into the test file, so a reviewer sees every case in the
diff and nothing is generated at test time. Keep two checks: that the
committed cases still cover the space, which fails when someone adds a value
or a rule that the list no longer covers, and that every committed case is
still allowed. The second is needed because `coverage` lists a row that a new
rule forbids as rejected, not as missing, so `iscomplete` alone stays `true`.

```@example agents
const CASES = [(mode = :exact, solver = :qr, tol = 1.0e-6), (mode = :exact, solver = :lu, tol = 1.0e-6), (mode = :exact, solver = :none, tol = 1.0e-6), (mode = :fast, solver = :none, tol = 0.001), (mode = :fast, solver = :none, tol = 1.0e-6)]

@testset "committed cases" begin
    @test iscomplete(coverage(CASES, space))          # nothing missing
    @test all(case -> isallowed(space, case), CASES)  # no case a rule now forbids
    for case in CASES
        x = solve(A, b; case...)
        @test norm(A * x - b) <= case.tol * norm(b)
    end
end
nothing # hide
```

When the check fails, `all_pairs(space; must_include = CASES)` keeps the
committed cases and adds only what the edited space needs.

## The one-line check

```julia
iscomplete(coverage(cases, space))
```

It measures the cases against the space from the rows alone, independent of
how they were made, and is `true` only when every feasible combination is
covered and none is unresolved. A row a rule forbids is listed as rejected
and does not make it `false`; check rows with `isallowed(space, case)`. Print
`coverage(cases, space)` to see what is missing, and
`explain(space, combination)` to see why a combination is excluded.
