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
find different failures. There is opportunity for test selection tools
in the Julia testing ecosystem, so let's make a recipe for how test
selection would work, in three steps.

1. Every test, manual or generated, needs to be recorded by the
   test framework so that the framework can observe the test run
   and select it to include in the test suite.

2. There has to be a way to measure each of those tests, as criteria
   for inclusion in the production test suite. These can be measurements
   of resource usage, such as runtime or memory requirements, but
   they can also be code coverage of the individual tests.

3. Finally, the test selection framework will use those criteria to
   prioritize or exclude tests from later test runs. This can be used
   to reduce the size of a test suite or it can be used to choose the
   tests that have most often failed in the past and run them first.

All three of these steps are challenging. For the first step, the Julia
framework considers the `@testset` the smallest unit of testing, so a test
automation tool would need to generate many `@testset` instances. While
the main framework won't record and replay tests, optional frameworks
such as [Jute.jl](https://github.com/fjarri/Jute.jl) can.

For the second step, it can be difficult to record coverage of individual
tests. The classic measure is line coverage, and, while Julia has built-in
ways to measure coverage for invocation of whole applications, the same
facility isn't available for testing coverage of individual tests.

The other challenge of coverage is that line coverage isn't a strong indicator
of how thorough testing is. Correlation between coverage and fault-finding
diminishes above sixty percent coverage. There is an alternative kind of
coverage, called mutation coverage, that has better support as an indicator
of testing thoroughness. This technique introduces errors, mutations, into
the code on the fly. Then it runs unit tests against that code
in order to ask which unit tests find the error. This is a different technique
from mutation testing ([Vimes.jl](https://github.com/MikeInnes/Vimes.jl)), but
it uses the same tools. The trouble with mutation coverage is that it's very
slow. There aren't known methods for calculating mutation coverage and
then updating it incrementally when there is a change to the code.

The last step is test selection. We run tests at different times for different
reasons, and there are different tests we might like to select. For
instance, we would run all of the tests during acceptance testing. For
continuous integration on Github, maybe it's better to run less
resource-intensive tests in order to save computing time. For checkout testing,
when you first install software on your local computer, you might choose
to run tests that will interact more closely with architecture-specific
machine instructions. And a most common choice is to select first for testing
those that failed most recently, because that's the bug you
were fixing. So a good test selection tool would be situation-specific.
