
# Features

## Coverage levels

- [`all_values`](@ref): Every value is used at least once.
- [`all_pairs`](@ref): Every pair of values is used at least once.
- [`all_triples`](@ref): Every triple of values is used at least once.
- [`all_tuples`](@ref): Generate test sets with arbitrary coverage level.

Increase coverage for a subset of the parameters by adding a dictionary
that lists the indices of sets of parameters to cover.

```julia
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    wayness = Dict(3 => [[1, 3, 4]])
    )
```

The dictionary keys are the higher coverage levels, so "3" means
all triples. The dictionary values are lists of sets of parameters which,
together, should be covered at the given level.

## Multiple generators

- [`IPOG`](@ref): The in-parameter-order generator is fast and gives the same result every time.
- [`GND`](@ref): This greedy, non-deterministic generator searches for shorter answers and can be slow.

They are both called [greedy generators.](man/greedy.md)

```julia
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    generator = IPOG()
    )
```

For the greedy, non-deterministic generator, you can set the random
number generator to make it repeatable, or set the number of candidate
test cases it generates each time it looks for a test case. A higher
`M` will make it run longer and possibly find a smaller test set.

```julia
rng = Random.MersenneTwister(979024)
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    generator = GND(rng = rng, M = 100)
    )
```

## Exclude forbidden combinations of parameters

If, for instance, this function can't be called with "high" and `:optim`,
then pass a filter function. This filter returns `true` for any combination
that should be forbidden.

```julia
disallow(n, level, value, kind) = level == "high" && kind == :optim
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    filter = disallow
    )
```


## Seed test cases

If there are particular tests that must be run, these already include
some of the tuples that should be covered. You can pass the must-run
test cases, and they will be included among the test cases.

```julia
must_test = [[1, "mid", 3.7, :relax], [1, "mid", 4.9, :relax]]
test_cases = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    seeds = must_test
    )
```
