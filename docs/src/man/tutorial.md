# Tutorial

This tutorial builds a test in five levels, and each level adds one idea:
a one-line call, named parameters, constraints, must-include cases and
strength, and inspection. A worked example at the end puts them together.
Every block on this page runs when the documentation is built, and the output
under it is what it printed.

## Level 0: one line

Give `all_pairs` a list of values for each argument of the function under
test:

```@example tutorial
using UnitTestDesign

cases = all_pairs([1, 2, 3], ["a", "b"], [1.0, 2.0])
```

The three lists have 3 × 2 × 2 = 12 combinations. The six cases hold every
*pair* of values: each value of the first argument appears beside each value
of the second, each value of the first beside each value of the third, and each
value of the second beside each value of the third. The summary line says what
was asked (strength 2, which means pairs), which engine built it (IPOG, the
default), and how large the full product is. The columns are named `p1`, `p2`,
`p3` because the arguments have no names yet.

`cases` is a vector of tuples, so a test loops over it:

```@example tutorial
using Test

scaled(n, unit, x) = string(n * x, " ", unit)     # stands in for the code under test

@testset "scaled" begin
    for (n, unit, x) in cases
        number, suffix = split(scaled(n, unit, x))
        @test parse(Float64, number) == n * x
        @test suffix == unit
    end
end
nothing # hide
```

Pairs matter because many bugs need two things at once: an `if` on one option
inside a branch on another. The saving grows with the number of parameters.
Four parameters of three values each have 81 combinations, and every pair of
their values fits in 10 cases:

```@example tutorial
all_pairs([1, 2, 3], ["low", "mid", "high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim])
```

Which values to list is the most important decision in this kind of testing,
and no function makes it for you. [Choosing values and
oracles](../explain/values_and_oracles.md) explains how to pick
representatives, boundaries, and a check that knows the right answer.

## Level 1: named parameters

Naming the parameters unlocks everything that follows: rules, partial
must-include cases, groups of parameters that need a higher strength, and
readable test names. Give `name => values` pairs, or a `NamedTuple` of lists:

```@example tutorial
all_pairs(:mode => [:fast, :exact], :solver => [:none, :lu, :qr], :tol => [1e-3, 1e-6])
```

The cases are now `NamedTuple`s. The rest of this tutorial tests this
function:

```@example tutorial
using LinearAlgebra

"""
Solve `A x = b`. In `:fast` mode, iterate until the residual is below `tol`,
ignoring `solver`. In `:exact` mode, meant for tight tolerances, factor `A`
with `solver`.
"""
function solve(A, b; mode = :exact, solver = :lu, tol = 1e-6)
    tol > 0 || throw(ArgumentError("tol must be positive, got $tol"))
    if mode == :fast                                  # Jacobi iteration
        x = zero(b)
        while norm(A * x - b) > tol * norm(b)
            x = x + (b - A * x) ./ diag(A)
        end
        return x
    end
    F = solver == :lu ? lu(A) : solver == :qr ? qr(A) : A
    return F \ b
end
nothing # hide
```

When the same parameters feed several designs, or need rules, put them in a
[`TestSpace`](@ref):

```@example tutorial
space = TestSpace((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]))
```

```@example tutorial
cases = all_pairs(space)
```

A case splats into keyword arguments, and its fields read by name. The check
here is an oracle that needs no reference answer: the residual must be below
the tolerance.

```@example tutorial
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

## Level 2: constraints

Look at the cases above. `solve` ignores `solver` in fast mode, so the cases
with `mode = :fast` and `solver = :lu` or `:qr` repeat what
`solver = :none` already tests, while taking the place of combinations that
matter. And exact mode is meant for tight tolerances, so `mode = :exact` with
`tol = 1e-3` is not a configuration anyone runs. Constraints say so, in three
spellings. A pattern forbids one exact combination:

```@example tutorial
forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance")
```

An expression over bare parameter names either forbids the combinations that
make it true (`@forbid`) or allows only those (`@require`):

```@example tutorial
@forbid mode == :fast && solver != :none
```

```@example tutorial
@require mode == :exact || solver == :none
```

`@require e` is the same rule as `@forbid !(e)`; having both verbs keeps the
intent visible. In a macro, a bare name is a parameter, and `$x` takes the
value of a variable `x` from the surrounding code. When the logic is too big
for one expression, list the names and write a function:

```@example tutorial
forbid(:mode, :solver) do mode, solver
    mode == :fast && solver != :none
end
```

A rule only ever sees complete values of the parameters it names, drawn from
their lists. The `solver` rule is the common pattern for a *dependent
parameter*: an option that applies only when another has some value gets a
sentinel value (`:none`) and one `@require`.

Rules belong to the space:

```@example tutorial
space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])

cases = all_pairs(space)
```

Every case satisfies both rules, and every pair of values that some valid case
can hold appears in a case. The second line says what was left out. Three
pairs are forbidden by a rule that names them. Two more are impossible: no
single rule covers both of their parameters, but together the rules leave no
valid case that holds them. [`explain`](@ref) says why:

```@example tutorial
explain(space, (solver = :lu, tol = 1e-3))
```

`solver = :lu` needs exact mode, and exact mode needs `tol = 1e-6`. You never
write that third rule; the package finds it, and does not ask for a case that
cannot exist. `explain` takes any partial or complete assignment:

```@example tutorial
explain(space, (mode = :fast, solver = :lu))
```

```@example tutorial
explain(space, (solver = :lu,))
```

A rule that names a parameter the space lacks is an error when the space is
built, and the message names what went wrong:

```@example tutorial
try
    TestSpace((mode = [:fast, :exact], solver = [:none, :lu, :qr]);
              constraints = [@forbid(mode == :fast && solvr != :none)])
catch err
    showerror(stdout, err)
end
```

The test loop does not change, and it now runs only valid cases:

```@example tutorial
@testset "solve" begin
    @testset "$case" for case in cases
        x = solve(A, b; case...)
        @test norm(A * x - b) <= case.tol * norm(b)
    end
end
nothing # hide
```

[Constraints](../explain/constraints.md) describes exactly what a rule
excludes and how the package decides that a combination is impossible.

## Level 3: must-include cases and strength

### Top up tests you already have

Suppose the suite already has two hand-written cases. [`coverage`](@ref)
measures their interaction coverage, which pairs they hold (this is not line
coverage):

```@example tutorial
handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
               (mode = :exact, solver = :lu, tol = 1e-6)]
coverage(handwritten, space)
```

Pass them as `must_include`. They come first, in the order given, and the
design adds cases only for what they miss:

```@example tutorial
topped = all_pairs(space; must_include = handwritten)
```

A must-include case may be partial; the package completes it with valid
values:

```@example tutorial
all_pairs(space; must_include = [(mode = :fast,), (solver = :qr,)])
```

A must-include case that breaks a rule is an error that names the case and the
rule:

```@example tutorial
try
    all_pairs(space; must_include = [(mode = :fast, solver = :lu, tol = 1e-6)])
catch err
    showerror(stdout, err)
end
```

### Strength

`all_pairs` is strength 2. [`all_values`](@ref) is strength 1 (every value
appears at least once), [`all_triples`](@ref) is strength 3, and [`covering`](@ref)
takes any `strength`. With four parameters:

```@example tutorial
wide = (n = [1, 2, 3], level = ["low", "mid", "high"], tol = [1.0, 3.7, 4.9],
        kind = [:greedy, :relax, :optim])
all_triples(wide)
```

Often only a few parameters interact strongly. `stronger` raises the strength
for a group of them and keeps pairs for the rest:

```@example tutorial
all_pairs(wide; stronger = [(:n, :tol, :kind) => 3])
```

The group's three parameters have three values each, so its triples are all
27 of their combinations, and the pairs with `level` fit into those same cases.
A positional call names the group by position, `stronger = [(1, 3, 4) => 3]`,
and several groups may be listed, such as
`stronger = [(3, 4, 5, 6) => 3, (25, 26, 27) => 3]` for 30 parameters.

To go from pairs to triples without losing the cases you have, pass them as
`must_include`:

```@example tutorial
triples = all_triples(space; must_include = cases)
coverage(triples)
```

### Excursions

When there is one known-good configuration, [`excursions`](@ref) varies it:
every valid case within `distance` changed parameters of the base. This is
not a covering design; it promises only that distance.

```@example tutorial
excursions(space; from = (mode = :exact, solver = :lu, tol = 1e-6), distance = 1)
```

!!! note "Choosing an engine"
    [`IPOG`](@ref), the default, builds cases one parameter at a time and uses
    no randomness. [`GND`](@ref) builds each case from random candidates
    drawn from a fixed seed, so it too gives the same cases on every run, and
    `GND(seed = 7)` gives a different design with the same guarantee. GND is
    slower, and in the package's benchmarks it gave a shorter design only at
    high strength. Both cover every feasible combination; neither promises a
    minimum number of cases. See [Engines](engines.md).

```@example tutorial
all_pairs(space; engine = GND(seed = 7))
```

## Level 4: inspection

### Before committing: `design_sizes`

[`design_sizes`](@ref) runs each strategy and says how many cases it gives
and what it covers, so you can choose before writing the test:

```@example tutorial
design_sizes(wide)
```

The share column is each design's size as a share of the valid cases. The
pairs and triples columns are what each design covers, so a strength-2 design
also reports the triples it happens to hold.

### Exporting cases

A result of named cases is a Tables.jl table:

```@example tutorial
using DataFrames
DataFrame(cases)
```

[`github_matrix`](@ref) writes the cases as a GitHub Actions matrix, one job
per case. See [Plan a CI matrix](../howto/ci_matrix.md).

```@example tutorial
github_matrix(cases)
```

### Invalid inputs

Mark a value [`Invalid`](@ref) to test that the function rejects it. The
design covers the ordinary values as before, then adds negative cases, each
holding exactly one invalid value, marked `!`, so one error cannot hide
another. A rule that reads `tol` does not apply to a case whose `tol` is
invalid:

```@example tutorial
negative = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr],
     tol = [1e-3, 1e-6, Invalid(0.0), Invalid(-1.0)]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
negcases = all_pairs(negative)
```

[`hasinvalid`](@ref) tells a test body which kind of case it has, and the
value inside the marker is its `value` field:

```@example tutorial
unwrap(x) = x isa Invalid ? x.value : x

@testset "solve with bad tolerances" begin
    for case in negcases
        args = map(unwrap, case)
        if hasinvalid(case)
            @test_throws ArgumentError solve(A, b; args...)
        else
            x = solve(A, b; args...)
            @test norm(A * x - b) <= args.tol * norm(b)
        end
    end
end
nothing # hide
```

See [Test invalid inputs](../howto/invalid_inputs.md).

### Classes of values

A [`Partition`](@ref) names a class of values and draws a concrete one when
the test runs. The design, the rules and `coverage` all see the name;
[`realize`](@ref) draws the values from a random number generator you pass:

```@example tutorial
using Random

sized = TestSpace((n = [Partition(:small, rng -> rand(rng, 2:5)),
                        Partition(:large, rng -> rand(rng, 200:300))],
                   solver = [:lu, :qr]))
labeled = all_pairs(sized)
```

```@example tutorial
realize(labeled; rng = Xoshiro(1))
```

See [Combine with property-based testing](../howto/property_based.md).

### After a failure

[`diagnose`](@ref) takes the cases and which of them passed, and ranks the
combinations that appear only in failing cases. Here a bug fails every case
with `method = :newton` on a sparse matrix:

```@example tutorial
suite = all_pairs((n = [10, 100, 1000], method = [:newton, :bicg, :gmres],
                   tol = [1e-3, 1e-6], sparse = [false, true]))
passed = [!(c.method == :newton && c.sparse) for c in suite]
diagnose(suite, passed)
```

The true cause ranks first. The ranking is a set of hypotheses, not a proof:
the other suspects appeared only in failing cases, so nothing yet says whether
they work. [`followups`](@ref) proposes a case to separate each one. See
[Diagnose a failure](../howto/diagnose.md).

### Check the claim: `coverage` and `report`

`coverage` of a result measures it again, from its rows alone, at the strength
it was built for. [`iscomplete`](@ref) is the one-line check that every
feasible combination is covered and none is unresolved:

```@example tutorial
coverage(cases)
```

```@example tutorial
iscomplete(coverage(cases))
```

[`report`](@ref) is the full account: the guarantee, measured from the rows;
each excluded combination with the rules that exclude it; the triples the
pairwise design covers as a bonus; how much the first cases cover, for a suite
that runs only some of them; and the seed.

```@example tutorial
report(cases)
```

## A worked example: generic code across types

Julia code is often generic, so one function is really one function per
combination of argument types, and the types are parameters to test. This
example tests a Hilbert curve index, which maps a point `(x, y)` on a grid to
its position `z` along a space-filling curve, and back. The code has many
branches, and its author worried about signed and unsigned integers, integer
sizes, and zero-based against one-based counting.

```@example hilbert
struct Simple2D{T} end

function encode_hilbert_zero(::Simple2D{T}, X::Vector{A})::T where {A, T}
    x = X[1]
    y = X[2]
    z = zero(T)
    if x == zero(A) && y == zero(A)
        return z
    end
    rmin = convert(Int, floor(log2(max(x, y))) + 1)
    w = one(A) << (rmin - 1)
    while rmin > 0
        z <<= 2
        if rmin & 1 == 1  # odd
            if x < w
                if y >= w
                    x, y = (y - w, x)
                    z += one(T)
                end
            else
                if y < w
                    x, y = ((w << 1) - x - one(w), w - y - one(w))
                    z += T(3)
                else
                    x, y = (y - w, x - w)
                    z += T(2)
                end
            end
        else  # even
            if x < w
                if y >= w
                    x, y = (w - x - one(w), (w << 1) - y - one(w))
                    z += T(3)
                end
            else
                if y < w
                    x, y = (y, x - w)
                    z += one(T)
                else
                    x, y = (y - w, x - w)
                    z += T(2)
                end
            end
        end
        rmin -= 1
        w >>= 1
    end
    z
end

function decode_hilbert_zero!(::Simple2D{T}, X::Vector{A}, z::T) where {A, T}
    r = z & T(3)
    x, y = [(zero(A), zero(A)), (zero(A), one(A)), (one(A), one(A)), (one(A), zero(A))][r + 1]
    z >>= 2
    rmin = 2
    w = one(A) << 1
    while z > zero(T)
        r = z & T(3)
        if rmin & 1 != 0
            if r == 1
                x, y = (y, x + w)
            elseif r == 2
                x, y = (y + w, x + w)
            elseif r == 3
                x, y = ((w << 1) - x - one(A), w - y - one(A))
            end
        else
            if r == 1
                x, y = (y + w, x)
            elseif r == 2
                x, y = (y + w, x + w)
            elseif r == 3
                x, y = (w - x - one(A), (w << 1) - y - one(A))
            end
        end
        z >>= 2
        rmin += 1
        w <<= 1
    end
    X[1] = x
    X[2] = y
end

# The same functions, counting from one.
encode_hilbert(gg::Simple2D{T}, X::Vector{A}) where {A, T} =
    encode_hilbert_zero(gg, X .- one(A)) + one(T)

function decode_hilbert!(gg::Simple2D{T}, X::Vector{A}, h::T) where {A, T}
    decode_hilbert_zero!(gg, X, h - one(T))
    X .+= one(A)
end
nothing # hide
```

The parameters are the integer type of the coordinates, the integer type of
the index, whether counting starts at zero or one, the length of the
coordinate vector (the code accepts one longer than it needs), and the number
of bits per coordinate. A domain can hold types. Two rules say that the index
and the coordinates must have room for the bits the curve uses:

```@example hilbert
using UnitTestDesign, Test

ints = [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128]
space = TestSpace(
    (axis = ints, index = ints, offset = [0, 1], dims = [2, 3, 4], bits = [2, 3, 4, 5]);
    constraints = [
        @forbid(bits * dims > log2(typemax(index))),
        @forbid(bits * dims > log2(typemax(axis))),
    ])
cases = all_pairs(space)
```

`typemax` and `log2` are called, so the macro reads them as functions; `index`,
`axis`, `bits` and `dims` are parameters. The test decodes the first and last
few indices and encodes them again, which must give back the same index, of
the same type:

```@example hilbert
@testset "Hilbert round trip" begin
    for (A, I, C, D, B) in cases
        gg = Simple2D{I}()
        last = (one(I) << (B * D)) - one(I) + I(C)
        mid = one(I) << (B * D - 1)
        X = zeros(A, D)
        for hl in vcat(C:min(mid, 5), max(mid + 1, last - 5):last)
            h = I(hl)
            if C == 0
                decode_hilbert_zero!(gg, X, h)
                @test encode_hilbert_zero(gg, X) === h
            else
                decode_hilbert!(gg, X, h)
                @test encode_hilbert(gg, X) === h
            end
        end
    end
end
nothing # hide
```

When this test was first written, there were no rules: it called `all_pairs`
on the five lists and skipped a case with `continue` when the types were too
small. `coverage` shows what that cost. Of the 100 cases, 64 ran, and they
missed 62 pairs that a valid case could have held:

```@example hilbert
unconstrained = all_pairs(ints, ints, [0, 1], [2, 3, 4], [2, 3, 4, 5])
ran = [row for row in unconstrained if isallowed(space, row)]
coverage(ran, space)
```

With the rules in the space, every one of those pairs is in a case that runs,
and the report lists the pairs that no case can hold, each with its rule:

```@example hilbert
report(cases)
```
