
# UnitTestDesign

A [Julia](http://julialang.org) package to generate parameters for unit tests
and test data for unit tests. You tell it possible values for each parameter of a function,
and it selects combinations of parameters that are most likely to find
problems in that function.

* [All-pairs](http://pairwise.org/), all-triples, and higher-order coverage of test cases.
* Combinatorial excursions from a base test case.
* Convenient ways to avoid uninteresting parameter combinations,
  add necessary test cases, and increase coverage for subsets of parameters.

## Install

```
pkg> add UnitTestDesign
```

## Description
Write a unit test using the [`all_pairs`](@ref) function.

```julia
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim]
    )
for test_case in test_set
    test_result = function_under_test(test_case...)
    @test test_result == known_result(test_case)
end
```
This package doesn't help write the code that knows what the
[correct test result](https://en.wikipedia.org/wiki/Test_oracle) should be.

In order to test every possible input to the function above, you would
need 81 tests, but this generates 10 tests that are more likely to find
most faults because they include every combination of each pair of parameter
values.

```@repl
using UnitTestDesign
test_cases = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim])
```
