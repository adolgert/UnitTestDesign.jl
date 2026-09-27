
# Guide

!!! note
    This page is being rewritten for 1.0. The examples below use the 1.0
    spellings; see [`covering`](@ref) for the full set of inputs and keywords.

## Kinds of test generation

A function has multiple arguments, and each argument can take multiple values.
We choose one of the following strategies to ensure different combinations of
argument values are tested by the test cases.

* Combinatorial coverage - Makes test cases that include combinations of argument values.

    - [`all_values`](@ref): Every value of every argument is used at least once.
    - [`all_pairs`](@ref): Every pair of values is used at least once.
    - [`all_triples`](@ref): Every triple of values is used at least once.
    - [`covering`](@ref): Generate test sets with any coverage level, `strength`.

* Excursions from a single parameter set - Start from a base set of arguments, keep them fixed, and vary one or more arguments.

    - [`excursions`](@ref): Every case within `distance` changed arguments of a
      base case, `distance = 1` for one at a time, `2` for pairs, and so on.
      This is not a covering guarantee.

* Full factorial - Make a test case for every possible combination of parameters.

    - [`full_factorial`](@ref): Generates all combinations of parameters, filtering
      those that aren't permitted.

## Same interface for all test generators

### Increase coverage for subsets of parameters

Sometimes there are a few parameters that are more important to test
fully. In that case, choose a base-level coverage for the whole test set,
such as the 2-way coverage of all-pairs. Then pass a separate argument
to request that the subset of parameters have greater coverage.

For instance, this requests that the first, third, and fourth parameters
have 3-way coverage, meaning full-factorial, while the second parameter has
only 2-way coverage. This is more meaningful when there are lots of parameters.
```@example
using UnitTestDesign  # hide
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    stronger = [(1, 3, 4) => 3]
    )
```

The `stronger` argument is a list of `group => strength` pairs. A group lists
parameters by position for positional arguments, or by name for a named
space, and the strength is the coverage level for that group, so "3" means
all triples. This means that, were you to have 40 parameters, you could
request that parameters `3:6` and parameters `25:30` be covered with triples.
```julia
array_of_forty_parameters = fill(1:4, 40)
test_set = all_pairs(
    array_of_forty_parameters...;
    stronger = [3:6 => 3, 25:30 => 3]
    )
```
The 0.4 keyword `wayness = Dict(3 => [[1, 3, 4]])` still works, with a
deprecation warning.


## Exclude forbidden combinations of parameters

Keep the test engine from making tests that aren't allowed for
your function. In 0.4 you passed it a filter function, one that returns `true`
whenever a parameter combination is forbidden.

0.4 syntax; the 1.0 manual replaces `disallow` with constraints on a `TestSpace`.

```julia
disallow(n, level, value, kind) = level == "high" && kind == :optim
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    disallow = disallow
    )
```

In 0.4 that function had to accept `nothing` for parameters not yet chosen,
and a generator could fail on rules that forbid combinations. In 1.0 a rule
sees only complete values of the parameters it names, and generation either
covers every combination that some allowed test contains or stops with a
`ResourceLimitError`.


## Must-include test cases

If there are particular tests that must be run, these already include
some of the tuples that should be covered. You can pass the must-run
test cases, and they will be included among the test cases, first and in order.

```@example
using UnitTestDesign  # hide
must_test = [(1, "mid", 3.7, :relax), (1, "mid", 4.9, :relax)]
test_cases = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];
    must_include = must_test
    )
```

The must-run cases are a list of tuples or vectors of arguments. The 0.4
keyword `seeds` still works, with a deprecation warning.
