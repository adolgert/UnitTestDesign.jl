
# UnitTestDesign

A [Julia](http://julialang.org) package to generate test cases for unit tests.
This provides **all-pairs** and higher-order algorithms.

## Install

```
pkg> add https://github.com/adolgert/UnitTestDesign.jl
```

## Description

If we have a function-under-test that takes four arguments, each of which
can have three possible values, then there are 81 possible combinations of
inputs. The [`all_pairs`](@ref) function selects 10 inputs that contain every pair
parameter values at least once.

```julia-repl
julia> using UnitTestDesign
julia> test_cases = all_pairs([1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim])
10-element Array{Array{Any,1},1}:
 [1, "low", 1.0, :greedy]
 [1, "mid", 3.7, :relax]
 [1, "high", 4.9, :optim]
 [2, "low", 3.7, :optim]
 [2, "mid", 1.0, :greedy]
 [2, "high", 1.0, :relax]
 [3, "low", 4.9, :relax]
 [3, "mid", 1.0, :optim]
 [3, "high", 3.7, :greedy]
 [2, "mid", 4.9, :greedy]
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
