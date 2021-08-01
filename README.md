# UnitTestDesign

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://adolgert.github.io/UnitTestDesign.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://adolgert.github.io/UnitTestDesign.jl/dev)
[![Build Status](https://github.com/adolgert/UnitTestDesign.jl/workflows/CI/badge.svg)](https://github.com/adolgert/UnitTestDesign.jl/actions)
[![Coverage](https://codecov.io/gh/adolgert/UnitTestDesign.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/adolgert/UnitTestDesign.jl)

Chooses function arguments to make unit testing faster and more effective.

* [Documentation](http://computingkitchen.com/UnitTestDesign.jl/stable/)
* [JuliaCon2021 Gentle Introduction](https://www.youtube.com/watch?v=3KIE3yrQ3lw) (YouTube Link)

This package generates parameter values for unit tests, chooses software configurations for integration testing, or generates test datasets. If the system-under-test takes a long time to run or has many possible parameters or many possible values each parameter can take, this library chooses combinations of parameters that are more likely to find faults in the code. It assumes that code will break when there are _interactions_ between different parameter choices, so it generates test data that covers all possible interactions among two parameters, the **all-pairs** algorithm, or three parameters, the **all-triples** algorithm, or higher-order combinatorial interactions.


## Installation

```
pkg> add UnitTestDesign
```

## Example

```julia
test_set = all_pairs(
    [1, 2, 3], ["low", "mid" ,"high"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim]
    )
for test_case in test_set
    test_result = function_under_test(test_case...)
    @test test_result == known_result(test_case)
end
```
