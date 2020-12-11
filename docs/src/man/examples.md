# Examples

## Test parameter generation

For a small test set, generate tests is quick.

```julia
test_set = all_pairs(
    [(-3, -2),  (2, 3), (-2, 3), (4.999, 5), (0, 1e7)],
    [0.1, 0.01, 0.001],
    [:RungeKutta, :Midpoint]
    )
for test_case in test_set
    a, b = test_case[1]
    result = custom_integrate(a, b, test_case[2:end]...)
    @test result == compare_with_symbolic_integration(a, b)
end
```


## Save larger test suites instead of regenerating

For a larger test set, it can be worthwhile to make test suites
and save them.
```julia
wide_test = all_triples(fill(1:4, 30)...)
JLD.save("test_artifact.jld", "wide_test", wide_test)
```
These could then be made available for testing through
[Pkg.Artifacts](https://julialang.github.io/Pkg.jl/v1.5/artifacts/).


## Test data generation

We use combinatoric testing because it finds all code paths. Code
paths are lines of code chosen by the same if-then decision.
Some code has few code paths but many branches. For instance,
`data_frame = all_data_frame[data_frame[:, :time] > 10]` has two
branches, one for times less than ten and one for times greater than ten.

This library will create test data as easily as it creates test cases.

```@example
using UnitTestDesign  # hide
using DataFrames
names = ["time", "event", "who", "location"]
at = all_triples([0.1, 5.1, 10.9], [:infect, :recover], [10, 11], ["forest", "home"])
DataFrame(Dict(names[i] => [row[i] for row in at] for i in 1:length(names))...)
```

## Excursions

If you want to start with a single test that you know is a common
way to call a function, then an excursion can generate variations
around that common way. It picks one parameter and walks through
its values. Then another. If you choose a pair-wise excursion, it
walks all pairs away from the initial value.

```@example
using UnitTestDesign  # hide
values_excursion([1, 2], [true, false], ["c", "b", "a"])
```

## Filtering a factorial

The full-factorial test generates every possible test. If some combinations
of parameters aren't interesting or allowed for a function, you can
exclude them by using an extra argument.
```@example
using UnitTestDesign  # hide
disallow = (a, b, c) -> b == 7 && c == false
full_factorial([1, 2, 3], [7, 8], [true, false]; disallow = disallow)
```
