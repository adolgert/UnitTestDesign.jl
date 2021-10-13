# Testing Methods

## Partition testing

We've pretended, so far, that every function takes parameters that are
selected from discrete, finite choices. Functions arguments can be floating-point
values, integers from infinite sets, vectors of values, or trees of trees of values.
*Partition testing* whittles down the nearly-infinite possible values into
subsets which are likely to find the same faults in the function-under-test.

If a function integrates a value from `a` to `b`, then we could partition the
possible `a` and `b` test values into those that are both negative, both positive,
one negative and one positive. We could make a separate case for when they are
very nearly equal or equal. That would make five partitions for these two
variables. For each of those five partitions, we guess that it would be enough
to choose some example value for testing.

```julia
test_set = all_pairs(
    [:neg, :pos, :split, :near, :far], [0.1, 0.01, 0.001], [:RungeKutta, :Midpoint]
    )
ab = Dict(:neg => (-3, -2), :pos => (2, 3), :split => (-2, 3),
    :near => (4.999, 5), :far => (0, 1e7)
)
for test_case in test_set
    a, b = ab[test_case[1]]
    result = custom_integrate(a, b, test_case[2:end]...)
    @test result == compare_with_symbolic_integration(a, b)
end
```

## Random testing

Random testing side-steps the work, and fallibility, of partition testing
by choosing input values randomly from their domain. If `a` can be any number
between 0 and infinity, then let a random number generator pick it.

Random testing isn't blind to understanding what can go wrong in a function.
It's no reason to forget to test edge cases. There is a procedure for
constructing random tests that are biased towards finding edge cases.

1. Identify the whole domain of each parameter and the set of parameters.
2. Assign weights to bias selection on that domain.
3. Sample from the parameters, given the weights.

For instance, if a parameter were a string, you wouldn't generate from all
random strings. You'd sample first for a string length, with assurance that
lengths 0 and 1 are included. Then you'd draw values in the string.

The test case generation in this library can help bias random testing.
For instance, you could assign one partition to edge cases near `a=0`,
one partition to general cases for `0.1 < a < 1000`, and one partition to
high cases, `1e7 < a < Inf`. Let the test case generator say which of
the low, mid, or high cases to choose, and then randomly choose values
within each test case.


## Test selection

We can generate a lot of tests. How do we know they are a good set
of tests? I'd like to make lots of tests and then keep only those
that are sufficiently different from the others that they would
find different failures. I don't see any of these tools currently in
Julia.

One measure is line coverage of code. We use all-pairs in order to
to generate tests that cover every path through the code. An if-then
in the code makes its decision based on variables which, in some way,
depend on input parameters. If we include every combination of parameters,
we will tend to cover more of the decisions of the if-thens.

A better measure is mutation analysis,
e.g. [Vimes.jl](https://github.com/MikeInnes/Vimes.jl).
This technique introduces errors
into the code, on the fly. Then it runs unit tests against that code
in order to ask which unit tests find the same failures. If two unit
tests consistently find the same failures, then delete one of them
and keep the other.
