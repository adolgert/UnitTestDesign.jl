# Commit a design as data

Generated cases can change when the space changes or the package is
upgraded, and a suite that compares failures across commits needs the same
cases every time. Commit the cases to the test file as a literal, the way a
manifest pins package versions, and add one test that fails when the
committed cases no longer cover the space.

## 1. Print the cases as Julia

```@example lockfile
using UnitTestDesign

space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])

cases = all_pairs(space)
print(repr(collect(cases)))
```

Paste that into the test file. For a diff with one case per line, print the
rows one at a time instead: `foreach(row -> println(repr(row), ","), cases)`.

## 2. Test the committed cases, and test that they are current

In `test/runtests.jl`, keep the space and the committed cases together:

```julia
using UnitTestDesign, Test

space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])

committed = [(mode = :fast, solver = :none, tol = 0.001), (mode = :exact, solver = :none, tol = 1.0e-6), (mode = :exact, solver = :lu, tol = 1.0e-6), (mode = :exact, solver = :qr, tol = 1.0e-6), (mode = :fast, solver = :none, tol = 1.0e-6)]

@testset "the committed design is current" begin
    @test iscomplete(coverage(committed, space))          # nothing missing
    @test all(case -> isallowed(space, case), committed)  # no row a rule now forbids
end

@testset "solver" begin
    for (; mode, solver, tol) in committed
        # the test body
    end
end
```

The test file now shows every case that runs, a reviewer sees any change
to them in the diff, and the cases no longer depend on the package version
or its engines. The first check fails when the space asks for a combination
the committed cases lack. The second fails when a new rule forbids a
committed case: [`coverage`](@ref) lists such a row as rejected but does not
count it as missing, so `iscomplete` alone would pass. A value removed from
a domain makes `coverage` throw, naming the row.

## 3. When the space changes, the test says so

Add a solver to the space, and the committed cases fall short:

```@example lockfile
committed = collect(cases)       # what the test file holds

grown = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr, :cholesky], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])

coverage(committed, grown)
```

In the test run, the first check fails with the count:

```text
  Expression: iscomplete(coverage(committed, space))
   Evaluated: iscomplete(covers 11 of 13 feasible pairs, 2 missing)
```

and `coverage(committed, space)` names the missing pairs. A new rule that
forbids a committed case shows up the other way:

```@example lockfile
stricter = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        forbid((mode = :fast, tol = 1e-3); reason = "fast mode is retired at loose tolerance"),
    ])

coverage(committed, stricter)
```

```@example lockfile
(iscomplete(coverage(committed, stricter)), all(case -> isallowed(stricter, case), committed))
```

## 4. Regenerate with the old cases first

Pass the committed cases as `must_include`. They keep their rows and their
order, and the generator adds rows only for what they leave uncovered:

```@example lockfile
updated = all_pairs(grown; must_include = committed)
```

Rows 1 to 5 are the committed cases, unchanged; row 6 is new. Print the
result again and replace the literal. Regenerating from scratch would also
cover the space, but may reorder or replace every row, so any comparison
with earlier runs would be lost.

Regenerate when either check fails, which happens when a value or a rule
changes, and when you raise the strength, passing the new strength to
`coverage` in the test as well. Drop a row the rules now forbid before
passing the rest as `must_include`, which refuses it. Do not regenerate for
a package upgrade: the committed cases, not the generator's output, are the
record, and the checks measure them against the current space whatever
version made them.

## Pitfall: every value must print as code that reads back

`repr` writes what `show` prints. Symbols, numbers, strings, `nothing`,
Base types such as `Float32`, and [`Invalid`](@ref) values read back as the
same values. A [`Partition`](@ref) prints as `Partition(:tiny)`, which is
not a call that constructs one; in the committed literal, write its name,
`:tiny`, which `coverage` and `must_include` accept. A function or a struct
defined in your tests may print with a module prefix, or not as code at
all. Choose values with a literal form, and build large inputs in the test
body from a label. Check the round trip once:

```@example lockfile
eval(Meta.parse(repr(committed))) == committed
```
