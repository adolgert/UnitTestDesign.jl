
# Guide

## Kinds of test generation

* Combinatorial coverage - Makes the shortest test sets to cover all options.

    - [`all_values`](@ref): Every value is used at least once.
    - [`all_pairs`](@ref): Every pair of values is used at least once.
    - [`all_triples`](@ref): Every triple of values is used at least once.
    - [`all_tuples`](@ref): Generate test sets with arbitrary coverage level.

* Excursions from a single parameter set

    - [`values_excursion`](@ref): Tries each parameter, one at a time.
    - [`pairs_excursion`](@ref): Tries pairs of parameters, two at a time.
    - [`triples_excursion`](@ref): Tries three parameters away from the original set.
    - [`all_tuples`](@ref): This function works for general excursions, too.

* Full factorial - Every combinations of parameters.

    - [`full_factorial`](@ref): Generates all combinations of parameters, filtering
      those that aren't permitted.

## Same interface for all test generators

### Increase coverage for subsets of parameters

Sometimes there are a few parameters that are more important to test
fully. In that case, choose a base-level coverage for the whole test set,
such as the 2-way coverage of all-pairs. Then pass a separate argument
to request that the subset of parameters have greater coverage.

For instance, this requrests that the first, third, and fourth parameters
have 3-way coverage, meaning full-factorial, while the second parameter has
only 2-way coverage. This is more meaningful when there are lots of parameters.
```@example
using UnitTestDesign  # hide
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    wayness = Dict(3 => [[1, 3, 4]])
    )
```

The wayness argument is a dictionary, where the dictionary keys are
the higher coverage levels, so "3" means
all triples. The dictionary values are an array of arrays of parameter indices which,
together, should be covered at the given level. This means that, were you to have 40
parameters, you could request that parameters `[3:6]` and parameters `[25:30]` be
covered with triples.
```julia
array_of_forty_parameters = fill(1:4, 40)
test_set = all_pairs(
    array_of_forty_parameters...;
    wayness = Dict(3 => [[3:6], [25:30]])
    )
```


## Exclude forbidden combinations of parameters

Keep the test engine from making tests that aren't allowed for
your function. Pass it a filter function, one that returns `true`
whenever a parameter combinations is forbidden.

```@example
using UnitTestDesign  # hide
disallow(n, level, value, kind) = level == "high" && kind == :optim
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    disallow = disallow
    )
```

There are *two problems* with excluding values.

1. The `disallow` function needs to handle possible `nothing` arguments.
   The generator will call this function on partially-constructed argument lists,
   and it will pass `nothing` for those arguments that have not yet been chosen.

2. The generator *may fail to find a solution* if there is a disallow list.
   Both the IPOG and GND generators can get stuck when there are rules that
   forbid combinations. It depends on the combinations and some luck. When it
   does fail, you will see the code try to access a vector at location 0.

There are papers that solve these problems by pairing tuple generation with
logic solvers. That sounds great. It isn't implemented here.


## Seed test cases

If there are particular tests that must be run, these already include
some of the tuples that should be covered. You can pass the must-run
test cases, and they will be included among the test cases.

```@example
using UnitTestDesign  # hide
must_test = [[1, "mid", 3.7, :relax], [1, "mid", 4.9, :relax]]
test_cases = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    seeds = must_test
    )
```

The must-run cases are a list of arrays of arguments.
