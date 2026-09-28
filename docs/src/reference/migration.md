# Migration from 0.4

UnitTestDesign 0.5 is a breaking release. Most 0.4 code still runs, with
deprecation warnings, but three things change under it: `disallow` is gone,
positional calls return a [`TestCases`](@ref) of tuples instead of a
`Vector{Vector{Any}}`, and [`GND`](@ref) gives the same cases on every call.
This page lists every removed and deprecated spelling, with its replacement
and a before-and-after example. The "after" code runs when the manual is
built.

## Compat bounds

Under Julia's semantic versioning a minor release before 1.0 is breaking. A
compat entry of `UnitTestDesign = "0.4"` or `"^0.4"` means `[0.4.0, 0.5.0)`,
so Pkg never upgrades a package that declares it to 0.5. Raise the bound to
`"0.5"` after making the changes below. A project with no compat entry for
UnitTestDesign gets 0.5 at its next update.

## The table

| 0.4 | 0.5 | Status |
|:--|:--|:--|
| `disallow = f` | `constraints = [...]` on a [`TestSpace`](@ref) or on named domains | removed |
| `all_tuples(...; n_way = k)` | [`covering`](@ref)`(...; strength = k)` | deprecated |
| `n_way = k` | `strength = k` | deprecated |
| `seeds = rows` | `must_include = rows` | deprecated |
| `wayness = Dict(3 => [[3, 4, 5, 6]])` | `stronger = [(3, 4, 5, 6) => 3]` | deprecated |
| `values_excursion(...)` | [`excursions`](@ref)`(...; distance = 1)` | deprecated |
| `pairs_excursion(...)` | `excursions(...; distance = 2)` | deprecated |
| `triples_excursion(...)` | `excursions(...; distance = 3)` | deprecated |
| `engine = Excursion()` | `excursions(...; distance = k)` | removed |
| `GND(M = m)` | `GND(candidates = m)` | deprecated |
| `GND()`, a new design on every call | `GND()` is `GND(seed = 0)`, the same design on every call | changed |
| `Counter = T` | nothing: drop the keyword | removed |
| `generate_tuples(engine, ...)` | `covering` or `excursions` | removed |
| positional result `Vector{Vector{Any}}` | `TestCases{Tuple{...}}`, a read-only vector of tuples | changed |

A *deprecated* spelling still works. It warns through `Base.depwarn`, which
Julia shows under `--depwarn=yes`, as `Pkg.test` runs, and it will be
removed in the next breaking release. Passing a deprecated keyword together
with its replacement (`n_way` and `strength`, `seeds` and `must_include`,
`wayness` and `stronger`, `M` and `candidates`) is an `ArgumentError`, even
when one of them is at its default value.

A *removed* spelling fails with Julia's ordinary error: `disallow` and
`Counter` with a `MethodError` for an unsupported keyword, `Excursion` and
`generate_tuples` with an `UndefVarError`.

## `disallow` becomes rules on a space

In 0.4 a `disallow` function received every argument of a row. The
generator also called it on partial rows, passing `nothing` for the
arguments not yet chosen, so a rule that did more than compare values
needed a guard:

```julia
# 0.4
disallow(n, level, value, kind) =
    value !== nothing && kind !== nothing && value > 4 && kind == :optim

all_pairs([1, 2, 3], ["low", "mid", "high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
          disallow = disallow)
```

In 0.5 the parameters have names, and a rule names the ones it reads:

```@example migration
using UnitTestDesign

domains = (n = [1, 2, 3], level = ["low", "mid", "high"], value = [1.0, 3.7, 4.9],
           kind = [:greedy, :relax, :optim])
space = TestSpace(domains; constraints = [@forbid(value > 4 && kind == :optim)])

cases = all_pairs(space)
```

The guard is gone. A rule receives values of the parameters it names and
nothing else, and only once each of them has a value: it never sees
`nothing` as a placeholder. If a domain lists `nothing`, a rule receives it
as a real value.

The same rule has three other spellings. Each builds a
[`Constraint`](@ref), and each allows the same rows:

```@example migration
spellings = [
    forbid(:value, :kind) do v, k
        v > 4 && k == :optim
    end,
    require(:value, :kind) do v, k
        v < 4 || k != :optim
    end,
    # A whole-case rule receives the complete row, as `disallow` did. It is
    # the most direct translation and the slowest to search; prefer names.
    forbid(case -> case.value > 4 && case.kind == :optim),
]
all(full_factorial(domains; constraints = [rule]) == full_factorial(space) for rule in spellings)
```

A positional call takes no rules. Name the parameters, with a `TestSpace`
as above or with named domains and `constraints =`, as in
`all_pairs(domains; constraints = spellings[1:1])`. The same goes for
`full_factorial(...; disallow = f)`, which becomes `full_factorial(space)`.

To check a rule, ask the space; [`explain`](@ref) names the rules that
exclude a combination:

```@example migration
explain(space, (value = 4.9, kind = :optim))
```

[Constraints](../explain/constraints.md) describes what a rule may read and
how rules combine.

## `all_tuples` and `n_way`

```julia
# 0.4
all_tuples([1, 2, 3], ["a", "b"], [true, false], [:p, :q]; n_way = 3)
```

```@example migration
covering([1, 2, 3], ["a", "b"], [true, false], [:p, :q]; strength = 3)
```

[`all_values`](@ref), [`all_pairs`](@ref) and [`all_triples`](@ref) are
unchanged: `covering` at strength 1, 2 and 3.

## `seeds`

```julia
# 0.4
must_test = [[1, "mid", 3.7, :relax], [1, "mid", 4.9, :relax]]
all_pairs([1, 2, 3], ["low", "mid", "high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
          seeds = must_test)
```

```@example migration
must_test = [(1, "mid", 3.7, :relax), (1, "mid", 4.9, :relax)]
all_pairs([1, 2, 3], ["low", "mid", "high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
          must_include = must_test)
```

A positional call takes tuples or vectors. A named call takes `NamedTuple`s,
which may be partial and are then completed, or a previous `TestCases`,
which is kept and topped up with the rows it misses.

## `wayness`

`wayness` was a `Dict` from strength to lists of argument positions.
`stronger` is a vector of `group => strength` pairs:

```julia
# 0.4
all_pairs([1, 2], [1, 2], [1, 2], [1, 2]; wayness = Dict(3 => [[2, 3, 4]]))
```

```@example migration
all_pairs([1, 2], [1, 2], [1, 2], [1, 2]; stronger = [(2, 3, 4) => 3])
```

With named parameters, a group lists names:
`stronger = [(:level, :value, :kind) => 3]`.

## Excursions

```julia
# 0.4
values_excursion([:a, :b, :c], [1, 2, 3])
pairs_excursion([:a, :b], [1, 2], [1, 2], ["a", "b"])
all_tuples([:a, :b], [1, 2], [1, 2]; n_way = 2, engine = Excursion())
```

```@example migration
excursions([:a, :b, :c], [1, 2, 3]; distance = 1)
```

```@example migration
excursions([:a, :b], [1, 2], [1, 2], ["a", "b"]; distance = 2)
```

The base is still the first value of each parameter unless you pass one as
`from`. An excursion is not a covering design: it guarantees only that
every row is within `distance` changes of the base.

## `GND`

```julia
# 0.4
all_pairs([1, 2, 3], ["a", "b"], [true, false]; engine = GND(M = 100))
all_pairs([1, 2, 3], ["a", "b"], [true, false]; engine = GND(rng = MersenneTwister(1)))
```

```@example migration
all_pairs([1, 2, 3], ["a", "b"], [true, false]; engine = GND(candidates = 100, seed = 1))
```

In 0.4 `GND()` drew from a fresh, unseeded generator, so each call gave
different cases. In 0.5 `GND()` means `GND(seed = 0)` and each call gives
the same cases. Pass `seed` to choose another design, or `rng` to draw from
your own generator, which is copied, not advanced.

## `Counter`, `Excursion` and `generate_tuples`

```julia
# 0.4
all_pairs(params...; Counter = Int8)
all_tuples(params...; engine = Excursion(), n_way = 1)
generate_tuples(IPOG(), 2, params, nothing, nothing, nothing, Int)
```

Drop `Counter`. Call `excursions` in place of the `Excursion()` engine, and
`covering` in place of `generate_tuples`:

```@example migration
params = ([1, 2, 3], ["a", "b"], [true, false])
covering(params...; strength = 2, engine = IPOG())
```

## The return type of positional calls

A positional call returned a `Vector{Vector{Any}}` in 0.4:

```julia
# 0.4
cases = all_pairs([1, 2, 3], ["a", "b"], [true, false])   # Vector{Vector{Any}}
cases[1][1] = 10                  # rows were mutable vectors
push!(cases, [4, "c", true])      # and so was the result
```

In 0.5 it returns a [`TestCases`](@ref), a read-only vector of tuples that
keep each value's type:

```@example migration
cases = all_pairs([1, 2, 3], ["a", "b"], [true, false])
typeof(cases)
```

What still works: iteration with destructuring, indexing, `length`,
`eachindex`, `first`, `last`, and splatting a row into a call.

```@example migration
for (x, label, flag) in cases
    # run one test with x, label and flag
end
(length(cases), cases[2], cases[2][1], first(cases))
```

What changes: a row is an immutable tuple, so `cases[1][1] = 10` is an
error, and the result is not a `Vector`, so `push!(cases, row)` is an error
and `cases isa Vector` is `false`. `collect(cases)` is a plain, mutable
vector of the rows, and `[collect(Any, row) for row in cases]` rebuilds the
0.4 shape exactly:

```@example migration
rows = collect(cases)
push!(rows, (4, "c", true))
(typeof(rows), length(rows))
```

A positional result's parameters are named `p1`, `p2`, …. Pass the names to
build a table:

```@example migration
using DataFrames
DataFrame(cases, parameters(cases.space))
```

or name the parameters in the call, and each row is a `NamedTuple`:

```@example migration
all_pairs((x = [1, 2, 3], label = ["a", "b"], flag = [true, false]))
```

## Values: `nothing`, types, and wrappers

In 0.4 `nothing` meant "not chosen yet" inside `disallow`. In 0.5 `nothing`
and `missing` are ordinary values, and every value keeps its identity and
type: `Any[1, 1.0]` is two values, and no value is converted.

```@example migration
all_pairs((n = [nothing, 1], s = [missing, "x"]))
```

Two wrapper values are new. [`Invalid`](@ref)`(x)` marks a value the code
should reject: generation adds negative cases, each holding one invalid
value beside valid ones, and [`hasinvalid`](@ref) tells a test body which
kind of case it has.

```@example migration
negative = all_pairs(TestSpace((n = [1, 2, Invalid(-1)], mode = [:a, :b])))
```

```@example migration
count(hasinvalid, negative)
```

[`Partition`](@ref)`(name, draw)` stands for a class of values;
[`realize`](@ref) draws a concrete value for each partition at run time.
Returned rows keep both wrappers. See
[Test invalid inputs](../howto/invalid_inputs.md) and
[Combine with property-based testing](../howto/property_based.md).
