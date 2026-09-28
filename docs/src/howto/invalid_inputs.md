# Test invalid inputs

A function should reject some inputs with a documented error, and a rule
that keeps those inputs out of one test must not mean they are never
tested. There are two patterns, shown here side by side: a second space for
combinations that are invalid together, and [`Invalid`](@ref) values for
values that are invalid on their own.

The function under test builds a grid and checks its arguments:

```@example invalid
using UnitTestDesign, Test

function grid(n, spacing, boundary)
    n >= 1 || throw(ArgumentError("n must be at least 1, got $n"))
    spacing > 0 || throw(ArgumentError("spacing must be positive, got $spacing"))
    boundary in (:open, :periodic) || throw(ArgumentError("unknown boundary $boundary"))
    boundary == :periodic && n < 2 && throw(ArgumentError("a periodic grid needs two points"))
    return range(0; step = spacing, length = n)
end
nothing # hide
```

## Pattern 1: a second space with its own oracle

One predicate describes the unsupported combination. The space for the
correctness test forbids it, and a second space for the rejection test
requires it, so the two cannot drift apart:

```@example invalid
needs_two(n, boundary) = n == 1 && boundary == :periodic
domains = (n = [1, 2, 50], spacing = [0.1, 1.0], boundary = [:open, :periodic])

valid = TestSpace(domains; constraints = [
    forbid(needs_two, :n, :boundary; reason = "a periodic grid needs two points")])
rejected = TestSpace(domains; constraints = [require(needs_two, :n, :boundary)])

all_pairs(rejected)
```

The rejected space holds only the forbidden combination, beside every value
of the other parameters; everything else is excluded, which is the point.
Each space gets its own oracle:

```@example invalid
@testset "grid" begin
    for (; n, spacing, boundary) in all_pairs(valid)
        @test length(grid(n, spacing, boundary)) == n
    end
    for case in all_pairs(rejected)
        @test !isallowed(valid, case)                  # the valid test excludes it
        @test_throws ArgumentError grid(case...)
    end
end
nothing # hide
```

[`explain`](@ref) says why a combination is out of the valid test:

```@example invalid
explain(valid, (n = 1, boundary = :periodic))
```

## Pattern 2: `Invalid` values in one space

When a single value is bad on its own, mark it with `Invalid` in the same
space as the good values:

```@example invalid
space = TestSpace((
        n        = [1, 2, 50, Invalid(0), Invalid(-3)],
        spacing  = [0.1, 1.0, Invalid(0.0), Invalid(NaN)],
        boundary = [:open, :periodic, Invalid(:closed)],
    );
    constraints = [forbid(needs_two, :n, :boundary; reason = "a periodic grid needs two points")])

cases = all_pairs(space)
```

Rows marked `!` are negative rows. Each holds exactly one invalid value,
beside ordinary values of the other parameters, and together they put
every invalid value beside every feasible value of every other parameter. The
ordinary rows come first and cover every feasible pair of ordinary values,
as if the invalid values were absent. A rule that reads the invalid
parameter does not apply to a negative row, so row 7 may pair
`Invalid(0)` with `:periodic`. No row holds two invalid values, so the
first check that fails cannot hide a second.

The test body branches on [`hasinvalid`](@ref). A row keeps the wrapper, so
unwrap it before the call:

```@example invalid
raw(x) = x isa Invalid ? x.value : x

@testset "grid with Invalid" begin
    for case in cases
        (; n, spacing, boundary) = map(raw, case)
        if hasinvalid(case)
            @test_throws ArgumentError grid(n, spacing, boundary)
        else
            @test length(grid(n, spacing, boundary)) == n
        end
    end
end
nothing # hide
```

[`report`](@ref) states the two guarantees apart, ordinary first, then
negative after "negative:", and gives each progress figure in both parts:

```@example invalid
report(cases)
```

The ordinary prefix curve reaches 100% at row 6, while the negative
targets are covered only by the last rows. A suite that runs a prefix of
the cases runs few negative rows.

## Which to prefer

- Use a second space when the invalid input is a combination of values
  that are each fine alone, which is what a rule describes. The rejection
  test gets exactly the combinations the correctness test excludes.
- Use `Invalid` when a value is bad by itself, such as a zero size or an
  unknown option. Each invalid value is tried beside every value of the
  other parameters, one invalid value per case.

The two combine: the `Invalid` space above keeps the `needs_two` rule for
its ordinary rows, and the second space still tests that rule's rejection.

## Pitfall: `@test_throws ArgumentError` accepts any argument error

A negative case passes if any check throws, including a check on a
parameter that was valid. Test that the error names the parameter that
holds the invalid value. `findfirst` on a row gives that parameter's name,
and `@test_throws` with a string checks the message:

```@example invalid
message = (n = "n must be", spacing = "spacing must be", boundary = "unknown boundary")

@testset "each rejection names its parameter" begin
    for case in filter(hasinvalid, cases)
        (; n, spacing, boundary) = map(raw, case)
        bad = findfirst(x -> x isa Invalid, case)      # such as :spacing
        @test_throws message[bad] grid(n, spacing, boundary)
    end
end
nothing # hide
```
