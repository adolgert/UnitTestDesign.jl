# Engines

There are many algorithms to create covering test sets.
This library implements two, and you can select which one to use
with a keyword argument.

- [`IPOG`](@ref): **Default** The in-parameter-order generator is fast and gives the same result every time.
- [`GND`](@ref): This greedy generator searches for shorter answers and can be slow. It draws random candidates from a fixed default seed, so it gives the same result for the same inputs.

Excursions are not an engine; use [`excursions`](@ref).

For instance, this example has ten parameters which can each take
one of four values.
```@example greedy_fours
using Random  # hide
using UnitTestDesign # hide
parameters = fill(collect(1:4), 10)
fast_and_longer = all_pairs(parameters...; engine = IPOG())
```

```@example greedy_fours
rng = Random.MersenneTwister(9790242)
slow_and_short = all_pairs(parameters...; engine = GND(rng = rng, candidates = 50))
```
