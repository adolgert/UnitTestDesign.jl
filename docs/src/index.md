
# UnitTestDesign

A [Julia](http://julialang.org) package to generate test cases for unit tests.
This provides **all-pairs** and higher-order algorithms.

* All-pairs, all-triples, and higher-order coverage of test cases.
* Combinatorial excursions from a base test case.
* Convenient ways to avoid uninteresting parameter combinations,
  add necessary test cases, and increase coverage for subsets of parameters.

## Install

```
pkg> add https://github.com/adolgert/UnitTestDesign.jl
```

## Description

If we have a function-under-test that takes four arguments, each of which
can have three possible values, then there are 81 possible combinations of
inputs. The [`all_pairs`](@ref) function selects 10 inputs that contain every pair
parameter values at least once.

```@repl
using UnitTestDesign
test_cases = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim])
```

Each item in this array is a set of parameters for unit testing the function.
This test set is an example of all-pairs because we can pick any two parameters (second and fourth),
pick any of the values for those parameters ("mid" and :relax), and find
them in one of the test cases (the 2nd one).

Use a test set for unit testing:

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
