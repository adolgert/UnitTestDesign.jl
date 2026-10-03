# Audit and extend an existing suite

A package already has hand-written tests that call a function with
particular options, and you want to know which combinations they leave out
before adding more. Write the existing calls as rows, measure them against
a space with [`coverage`](@ref), and let the generator add only the rows
that are missing.

## 1. Write the existing calls as rows

Suppose `runtests.jl` already calls an interpolation routine three ways:

```julia
interpolate(xs, ys; method = :linear, boundary = :error)                     # Float64, uniform grid
interpolate(xs, ys; method = :cubic,  boundary = :extrapolate)               # Float64, uniform grid
interpolate(xs_irregular, ys; method = :linear, boundary = :clamp)           # Float64, irregular grid
```

Each call becomes a `NamedTuple` that names every parameter of the space,
including the ones the call sets implicitly, such as the grid and the
element type:

```@example audit
using UnitTestDesign

existing = [
    (method = :linear, boundary = :error,       grid = :uniform,   T = Float64),
    (method = :cubic,  boundary = :extrapolate, grid = :uniform,   T = Float64),
    (method = :linear, boundary = :clamp,       grid = :irregular, T = Float64),
]

space = TestSpace((
        method   = [:nearest, :linear, :cubic],
        boundary = [:error, :clamp, :extrapolate],
        grid     = [:uniform, :irregular],
        T        = [Float64, Float32],
    );
    constraints = [@forbid(method == :nearest && boundary == :extrapolate)])
nothing # hide
```

## 2. Measure them

```@example audit
coverage(existing, space)
```

The three tests hold 16 of the 36 pairs that some valid case can hold. The
list names the missing pairs, and `excluded:` counts the pair the rule
forbids, which no case needs. This is interaction coverage, a statement
about combinations of values, not about which lines of code ran.

[`missing_interactions`](@ref) gives the missing pairs as data, one
`NamedTuple` each, for writing targeted tests by hand or for a script to
act on:

```@example audit
first(missing_interactions(existing, space), 5)
```

## 3. Top up to pairs

Pass the existing rows as `must_include`. They come first, in the order
given, and the generator adds rows only for the pairs they miss:

```@example audit
pairs = all_pairs(space; must_include = existing)
```

The summary says "3 must-include": rows 1 to 3 are the existing tests,
unchanged, and rows 4 to 8 are the tests to add. A must-include row that
breaks a rule is an error naming the row and the rule, so a stale test
cannot slip in unnoticed.

```@example audit
coverage(pairs)
```

## 4. Extend to triples

The same move takes the pairwise suite to triples. Pass the pairwise rows as
must-include rows to [`all_triples`](@ref):

```@example audit
triples = all_triples(space; must_include = pairs)
coverage(triples)
```

```@example audit
triples[1:length(pairs)] == pairs
```

The first 8 rows are the pairwise suite, in its order, so the existing
tests and the new pairwise rows stay where they were, and the triples add
12 more.

## Pitfall: values must match the domain exactly

Values match by identity, the same type and `isequal`. An existing test
that passes the string `"linear"` where the domain holds the symbol
`:linear`, or `1` where it holds `1.0`, is not in the domain, and
`coverage` says which row and parameter:

```@example audit
try
    coverage([(method = "linear", boundary = :error, grid = :uniform, T = Float64)], space)
catch err
    showerror(stdout, err)
end
```

Write the rows with the values the space uses, or add the value to the
domain if the function really accepts both.
