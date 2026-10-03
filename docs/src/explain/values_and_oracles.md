# Choosing values and oracles

A covering design answers one question: which combinations of the values you
listed should run. It does not choose the values, and it does not know the
right answers. Those two jobs are yours, and they decide how much a design is
worth. This page is about doing them well.

## Values stand for classes

Few parameters really take only a handful of values. A tolerance is any
positive float, a size is any integer, and a matrix is any matrix. When you
write `tol = [1e-3, 1e-6]` you are not saying that only two tolerances
matter. You are choosing one *representative* from each of two *equivalence
classes*: sets of inputs you expect to reveal the same faults. If a function
fails for every `tol < 1e-8`, then `1e-9` and `1e-12` are equivalent for
finding that fault, and one of them is enough.

Classes come from three places.

- **The specification.** Documented ranges, special cases, and modes: "a
  negative tolerance is an error", "`:exact` ignores the tolerance".
- **The code.** Every threshold and branch splits a domain. If the code
  switches algorithms at 1,000 rows, then 999, 1,000 and 1,001 rows are
  worth separate values.
- **The types.** Empty collections, zero, one, negative numbers, `NaN`,
  `Inf`, `-0.0`, `nothing`, `missing`, a non-ASCII string, a `Float32` where
  a `Float64` is usual, a view where an `Array` is usual.

Faults gather at edges, so pick values *on* and *next to* each boundary, not
only in the middle of each class. Off-by-one errors live there.

Two warnings go with every design. First, the guarantee is relative to the
values you chose. A class you did not list is invisible: no design will cover
it, and no coverage figure will report it as missing. Second, every value
costs cases. When every pair is allowed, a pairwise design needs at least as
many cases as the product of the two largest domains, so a parameter with ten
values beside one with eight needs at least 80 cases. Keep domains to the
classes that matter, and move extra attention to where the risk is.

Writing down the parameters and their classes this way is the
category-partition method of Ostrand and Balcer (1988); a covering design is
one way to choose which combinations of classes to run.

## Where to spend cases

There are two ways to test one part of the space harder than the rest. The
first is to add values, such as a corner case, to the parameters that carry
the risk. The second is to raise the strength for a group of parameters with
`stronger`. Here forty four-valued parameters are covered pairwise, all
triples of parameters 3 to 6 are covered too, and the cost lands between
the pairwise and the three-way designs:

```@example spend
using UnitTestDesign
domains = fill(1:4, 40)
(pairs = length(all_pairs(domains...)),
 pairs_with_one_strong_group = length(all_pairs(domains...; stronger = [3:6 => 3])),
 triples = length(all_triples(domains...)))
```

## Configurations, not only functions

The parameters need not be the arguments of one function. The same idea
applies to anything with interacting choices: the options of a solver, the
fields of a parameter file, command-line flags, the jobs of a CI matrix
(see [Plan a CI matrix](../howto/ci_matrix.md)), or the settings of a
simulation campaign. A parameter can even stand for a choice about the shape
of test data, such as which column of a generated CSV holds missing values.

## When a combination makes no sense

Sometimes a combination is not a valid input: a fast mode that takes no
solver, or a GPU driver on a machine with no GPU. Write a rule that forbids
it, and the design leaves it out and says so. When only a few combinations of
two parameters are valid, you can instead merge them into one parameter
whose values are the valid pairs. Rules are easier to read and to change once
there are more than a few parameters. [Constraints](constraints.md) explains
what a rule means.

## Random values inside a class

One defense against a misjudged class is to stop choosing a single
representative. A [`Partition`](@ref) is a named value that stands for a
whole class and draws a concrete member when the test runs. The design
covers the classes by name; [`realize`](@ref) draws the members from a
generator you seed. This places combinatorial testing and random testing on
one continuum: the design decides which classes meet, and the draws explore
inside each class. Keep the labeled rows beside the realized inputs, because
coverage is measured on the labels, not on the drawn values. The example
below uses partitions, and [Combine with property-based
testing](../howto/property_based.md) goes further.

## The oracle problem

A design can produce hundreds of cases, and a person cannot compute the
expected answer for each. The check has to work for any case the design
supplies. This is the hardest part of moving from hand-written tests to
generated ones, and it has a name in the testing literature: the oracle
problem (Barr et al., 2015). An oracle is anything that decides whether an
output is right. It helps to write a check not as

```julia
@test result == expected(case)
```

but as a relation between the case and the result,

```julia
@test holds(result, case)
```

because relations are far easier to come by than expected values. The useful
kinds, roughly from strongest to weakest:

- **Known answers.** A few cases you checked by hand, or that a paper or a
  specification gives. Put them in `must_include`, so they run first and
  count toward coverage, and let the design add the rest.
- **Differential testing.** Compare with another implementation that should
  agree: an earlier version of the function, a slow and obvious algorithm, a
  different method for the same quantity (numerical against symbolic
  integration), or a library in another language.
- **Invariants.** Properties the output must have whatever the input: the
  result is sorted, a probability lies in ``[0, 1]``, mass is conserved, the
  output has the input's shape. Inverse problems give strong invariants: feed
  the answer to the forward problem and recover the input.
- **Metamorphic relations.** Change the input in a known way and predict how
  the output changes. Reversing an interval negates an integral; scaling a
  data set scales its mean; permuting the rows of a table leaves its sum
  alone; for some `f`, `f(a, b) == f(2a, b/2)`. Metamorphic testing has found
  real faults in programs whose correct output nobody could compute (Segura
  et al., 2016). A related check is continuity: nearby inputs should give
  nearby outputs.
- **Crash-freedom.** The call returns, throws nothing unexpected, and gives
  finite numbers. It is the weakest oracle and it is free, so apply it
  everywhere. For inputs that *should* fail, list them as
  [`Invalid`](@ref) values and check that the error comes; see [Test
  invalid inputs](../howto/invalid_inputs.md).

## How designs fit each oracle

A design does not change what an oracle can detect. It changes which inputs
the oracle sees.

- A known answer covers the combinations in its own case. As a
  must-include case it also saves the design from covering them again.
- A differential or invariant check applies to every case, so the design
  decides which combinations of options the check sees. This is where
  interaction coverage pays: a fault that needs `mode = :exact` together
  with `solver = :qr` is exercised by a pairwise design, whatever the other
  options are.
- A metamorphic relation turns each case into two runs, the source and its
  follow-up. When there are several relations, make the relation a
  parameter of the space. Then every relation meets every pair of other
  options, and the design spends no case applying two relations where one
  would do.
- Crash-freedom is checked on every case at no cost, and a design is a cheap
  way to make sure every pair of options has been run at least once.

The example below puts these together for a trapezoid-rule integrator. The
interval is a parameter whose values are classes, each a `Partition` that
draws a random interval of its kind: forward, reversed, negative,
straddling zero, empty, and wide. The metamorphic relation is a parameter
too. A straight line has an exact answer, which gives a differential check
for that integrand, and every case checks that the result is finite.

```@example oracles
using UnitTestDesign, Random, Test

function trapezoid(f, a, b; n = 16)
    h = (b - a) / n
    return h * ((f(a) + f(b)) / 2 + sum(f(a + k * h) for k in 1:(n - 1); init = 0.0))
end

space = TestSpace(
    (interval = [
         Partition(:unit, Returns((0.0, 1.0))),
         Partition(:reversed, rng -> (1 + rand(rng), rand(rng))),
         Partition(:negative, rng -> (-2 - rand(rng), -rand(rng))),
         Partition(:straddles, rng -> (-rand(rng), rand(rng))),
         Partition(:empty, rng -> (x = randn(rng); (x, x))),
         Partition(:wide, rng -> (0.0, 1e3 * (1 + rand(rng))))],
     integrand = [:line, :cubic, :wiggle],
     n = [1, 2, 64],
     relation = [:reverse, :scale]))

cases = all_pairs(space)
```

```@example oracles
integrands = Dict(:line => x -> 2x + 1, :cubic => x -> x^3, :wiggle => x -> sin(5x))
line_exact(a, b) = (b^2 + b) - (a^2 + a)

@testset "trapezoid" begin
    for input in realize(cases; rng = Xoshiro(1))
        f = integrands[input.integrand]
        a, b = input.interval
        result = trapezoid(f, a, b; n = input.n)
        @test isfinite(result)                                   # crash-freedom
        if input.relation == :reverse                            # metamorphic
            @test trapezoid(f, b, a; n = input.n) ≈ -result rtol = 1e-9 atol = 1e-9
        else
            @test trapezoid(x -> 3f(x), a, b; n = input.n) ≈ 3result rtol = 1e-9 atol = 1e-9
        end
        if input.integrand == :line                              # differential
            @test result ≈ line_exact(a, b) rtol = 1e-9 atol = 1e-9
        end
    end
end
nothing # hide
```

The cases cover every pair of interval class, integrand, panel count, and
relation. The draws change with the seed; the pairs of classes do not.
When a case fails, keep `cases` (the labeled rows) beside the realized
inputs: [Diagnose a failure](../howto/diagnose.md) works from the labels.

## Checking the values themselves

The design guarantees coverage of the model you wrote, so it is fair to ask
whether the model is right. Two measurements answer that, and neither is
part of this package.

- **Code coverage per case.** If two values of a parameter always take the
  same branches, one of them may be redundant. If some branch is never
  taken, a class may be missing. Julia measures line coverage for a whole
  process, so measuring it per case means running cases separately.
- **Mutation analysis.** Inject small faults into the code under test and
  count how many the suite catches. This measures values and oracles
  together, since a fault is caught only when some case reaches it and some
  check notices. It is slow, because every mutant needs a run of the suite.

A related question is which tests to run when. A quick CI job might run the
first few cases of a design and the release check all of them. The prefix
curve of [`report`](@ref) says how much of the interaction coverage each
prefix buys; [Interaction coverage and the evidence](coverage_evidence.md)
shows how to read it.

## References

- Barr, E. T., M. Harman, P. McMinn, M. Shahbaz, and S. Yoo. "The oracle
  problem in software testing: A survey." *IEEE Transactions on Software
  Engineering* 41(5), 2015.
- Ostrand, T. J., and M. J. Balcer. "The category-partition method for
  specifying and generating functional tests." *Communications of the ACM*
  31(6), 1988.
- Segura, S., G. Fraser, A. B. Sanchez, and A. Ruiz-Cortés. "A survey on
  metamorphic testing." *IEEE Transactions on Software Engineering* 42(9),
  2016.
