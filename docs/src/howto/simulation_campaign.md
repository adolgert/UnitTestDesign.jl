# Run a simulation campaign

A simulation model has several parameters, each run takes minutes or
hours, and the full product runs to hundreds of runs. Compare the sizes of
the designs before choosing one, raise the strength for the parameters that
interact most, and write the cases to a file that drives the campaign.

## 1. Describe the model's parameters

```@example campaign
using UnitTestDesign

space = TestSpace((
        R0          = [0.9, 1.5, 3.0],
        population  = [1_000, 100_000, 10_000_000],
        contact     = [:homogeneous, :household, :network],
        vaccination = [0.0, 0.3, 0.7],
        stepper     = [:euler, :rk4, :adaptive],
        seasonal    = [false, true],
    );
    constraints = [
        forbid((contact = :network, population = 10_000_000);
               reason = "the network model is too slow at this size"),
    ])
nothing # hide
```

## 2. Compare the designs

[`design_sizes`](@ref) runs each strategy and measures what it covers,
before you commit to one:

```@example campaign
design_sizes(space)
```

Each row is one design: how many runs it takes, its share of the 432 valid
runs, and how many of the feasible pairs and triples it holds. Pairs take
13 runs; triples take 43. The counts are the rows the engine produced for
this space, not lower bounds, and another engine may give a different
count.

## 3. Raise the strength where it matters

Transmission, contact structure, and vaccination are the parameters most
likely to interact, so ask for every triple of those three and every pair
of the rest:

```@example campaign
cases = all_pairs(space; stronger = [(:R0, :contact, :vaccination) => 3])
report(cases)
```

The guarantee line states the combined claim: every feasible pair, and
every feasible triple within the group, 146 combinations in all. The
`bonus:` line says how many of the space's triples came along anyway.

## 4. Make the design reproducible

The default engine, [`IPOG`](@ref), uses no randomness, so the same space
gives the same cases. [`GND`](@ref) draws candidate rows at random; give it
a seed, and the same seed gives the same cases, and `report` prints it:

```@example campaign
gnd = all_pairs(space; stronger = [(:R0, :contact, :vaccination) => 3],
                engine = GND(seed = 20260927))
gnd == all_pairs(space; stronger = [(:R0, :contact, :vaccination) => 3],
                 engine = GND(seed = 20260927))
```

## 5. Write the rows

A named result is a table, one column per parameter:

```@example campaign
using DataFrames
first(DataFrame(cases), 5)
```

To drive the campaign from a file, write it with CSV.jl, which is not part
of this documentation's build:

```julia
using CSV
CSV.write("campaign.csv", cases)
```

CSV is text: a `Symbol` such as `:network` is written as `network` and reads
back as a string. If the space holds [`Partition`](@ref) values, write the
labeled rows for the record and [`realize`](@ref) them in the job that runs
each case.

## Pitfall: the seed is not the record

Identical inputs give identical cases for the same package version and the
same Julia version. A later release may change the rows, their order, or
their count while keeping every guarantee, and so may any edit to the space.
Keep the file of rows, not the seed, as the record of what the campaign
ran, and see [Commit a design as data](commit_design.md) for keeping those
rows when the space grows.
