# Interaction coverage and the evidence

This page says what a covering design guarantees, why that guarantee is
worth having, and where the evidence for it stops. It ends with the evidence
you can gather about your own suite.

## What interaction coverage means

Pick any two parameters, and one value for each: `mode = :exact` and
`solver = :qr`, say. That is a *pair*, a 2-way combination. A suite of test
cases *covers* the pair when at least one case holds both values. More
generally, a ``t``-way combination fixes ``t`` parameters to one value each,
and ``t`` is the *strength*. The word also has a plain use: in a result's
summary line, such as
`5 cases (lower bound 4) · strength 2 · IPOG · 3 parameters · 12 combinations`,
it counts the full product, every way to give each parameter a value. The
lower bound beside the count is the fewest cases any design could have: the
4 feasible pairs of `mode` and `solver` each need a case of their own.

A combination is *feasible* when some valid case contains it. Rules can make
a combination impossible, and then no suite needs to cover it (see
[Constraints](constraints.md)). The *interaction coverage* of a suite at
strength ``t`` is the share of feasible ``t``-way combinations it covers. A
pairwise design, from [`all_pairs`](@ref), covers every feasible pair; a
three-way design covers every feasible triple.

Interaction coverage is a property of the inputs. It is not line or branch
coverage, which say what code ran, and a suite can have complete interaction
coverage of a model whose values miss a branch entirely (see [Choosing values
and oracles](values_and_oracles.md)).

## Why a few parameters at a time

Kuhn, Wallace, and Gallo (2004) studied the failure reports of several
software systems and asked how many input parameters had to take particular
values together to trigger each failure. In the systems they studied, most
failures needed only one or two parameters, and none needed more than six.
Later NIST work collected more studies of the same kind (Kuhn, Kacker, and
Lei, 2010). If a failure needs a particular pair of values, a suite that
covers every pair runs it. That is the argument for covering designs.

It is an observation about the systems studied, not a law. Your code may
have a failure that needs four parameters together, or a failure that no
value you listed can trigger.

## Random suites at the same budget

The fair comparison for a design is a random suite of the same size, since a
random suite is the cheapest thing to generate. A short calculation says how
it does. Suppose every parameter has ``v`` values and there are no rules. A
random case contains one particular ``t``-way combination with probability
``v^{-t}``, so a suite of ``N`` random cases contains it with probability

```math
P(\text{covered}) = 1 - \left(1 - v^{-t}\right)^{N}.
```

The block below applies the formula to the design sizes the default engine
gives, pairwise, for several numbers of parameters and values.

```@example evidence
using UnitTestDesign
println("parameters × values   designed pairwise cases   pairs a random suite of that size covers")
for (k, v) in [(5, 4), (10, 4), (10, 8), (40, 4), (40, 8)]
    N = length(all_pairs(fill(1:v, k)...))
    share = round(Int, 100 * (1 - (1 - 1 / v^2)^N))
    println(lpad(k, 10), " × ", rpad(v, 6), lpad(N, 26), lpad("$share%", 44))
end
```

A designed suite covers all of the pairs, and a random suite of the same size
covers an expected 64 to 95 percent of them. Two facts explain the pattern.

- A pairwise design must hold all ``v^2`` combinations of any two
  parameters, so it has at least ``v^2`` cases. A random suite of that size
  contains any particular pair with probability at least
  ``1 - (1 - v^{-2})^{v^2}``, which is about ``1 - 1/e``, or 63 percent.
  Arcuri and Briand (2012) make this argument in detail: random testing
  finds interaction faults more often than coverage figures alone suggest.
- The number of cases a design needs grows only with the logarithm of the
  number of parameters. As parameters are added, a random suite of the
  design's size therefore covers a larger share, which is why it reaches 93
  to 95 percent at forty parameters.

The last few combinations are the expensive ones to hit by chance. In a
simulation made while this release was designed, random suites needed four
to six times as many cases as the design to cover every pair (for ten
four-valued parameters, a median of 106 random cases against the design's
28).

With rules, a sensible random suite draws from the valid cases, and the
chance of covering a combination depends on how many valid cases contain it.
If ``V`` valid cases exist and ``k`` of them contain a combination, a suite
of ``N`` draws contains it with probability ``1 - (1 - k/V)^N``. Here is a
small solver space. It has five valid cases, and each holds a pair that no
other case holds, so the pairwise design needs all five. The first block
measures the design with [`report`](@ref).

```@example evidence
space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
cases = all_pairs(space)
r = report(cases)
```

The second block counts, for each feasible pair, the valid cases that
contain it, and applies the formula to every prefix length of the design.

```@example evidence
valid = collect(full_factorial(space))      # every valid case
names = keys(first(valid))
holders = Int[]                             # valid cases holding each feasible pair
for i in eachindex(names), j in (i + 1):length(names)
    for pair in unique((row[i], row[j]) for row in valid)
        push!(holders, count(row -> (row[i], row[j]) == pair, valid))
    end
end
random_share(n) = sum(k -> 1 - (1 - k / length(valid))^n, holders) / length(holders)

println("cases   pairs the design's first cases cover   pairs random valid cases cover (expected)")
for point in r.prefix
    expected = round(point.feasible * random_share(point.cases); digits = 1)
    println(lpad(point.cases, 5), lpad("$(point.covered) of $(point.feasible)", 39),
            lpad("$expected of $(point.feasible)", 44))
end
```

The design's column is the prefix curve that `report` printed. For one or two
cases the columns agree, because every valid case holds three pairs. They
part at the end, where a random suite keeps drawing cases it already has.

A simulation with [`coverage`](@ref) agrees with the formula, and shows how
rarely luck gives the whole guarantee: five random valid cases cover every
feasible pair only when they happen to be the five different ones, a chance
of ``5!/5^5``, about 4 percent.

```@example evidence
using Random
rng = Xoshiro(1)
shares = map(1:2000) do _
    part = coverage(rand(rng, valid, length(cases)), space).ordinary
    part.covered / part.feasible
end
(mean_share = sum(shares) / length(shares), all_pairs_covered = count(==(1), shares) / length(shares))
```

## What designs buy

So the honest claim is not that a design finds many times more faults. At
equal budget, a designed suite covers every feasible combination where a
random suite covers most of them, and the difference shrinks as parameters
are added. What a design buys is the guarantee itself.

- Nothing is left to luck: every feasible combination at the requested
  strength runs, in a suite of known size.
- You get an exact list of what was impossible and which rules made it so,
  which is a check on your own rules.
- Extension is deterministic: pass the old cases as `must_include`, and the
  design keeps them and adds cases only for the combinations they leave
  uncovered.

That matters most when each run is expensive (a long simulation, a CI job, a
hardware test), when someone needs the claim written down, and when
parameters are few and have many values, where random suites do worst (64
percent for five four-valued parameters, above). It may also matter when
rules are tight, since random sampling of valid cases makes some feasible
combinations rare while a design treats all of them alike. That last point
is a hypothesis, not a measured result.

## What the evidence does not show

- It does not show that pairwise testing finds some fixed fraction of the
  faults in *your* code. The fault studies describe other systems.
- The comparison with random suites counts which combinations run, not
  which faults are caught. A fault is caught only when some case reaches it
  and the check notices, so a weak oracle limits any design (see [Choosing
  values and oracles](values_and_oracles.md)).
- We know of no study that compares designed, random, and exhaustive
  suites by fault detection on Julia code, for instance with mutation
  analysis. That case study is future work (see
  [Non-goals](../dev/non_goals.md)).

## Your own evidence

The measurements the package makes about your suite are more relevant than
any study.

- [`report`](@ref) states the guarantee with its coverage figures measured
  from the rows, lists every excluded combination with the rules that
  exclude it, gives the bonus coverage at the next strength (a pairwise
  design covers some of the triples too), and prints the prefix curve. The
  prefix curve says how much the first ``k`` cases cover, which is what you
  need when a quick CI job runs only part of a design.
- [`coverage`](@ref) measures any set of rows, including a hand-written
  suite, and names the combinations it misses. See [Audit and extend an
  existing suite](../howto/audit_existing.md).
- [`design_sizes`](@ref) shows the case counts and coverage of each strategy
  before you commit to one.

## References

- Arcuri, A., and L. Briand. "Formal analysis of the probability of
  interaction fault detection using random testing." *IEEE Transactions on
  Software Engineering* 38(5), 2012.
- Kuhn, D. R., R. N. Kacker, and Y. Lei. *Practical Combinatorial Testing.*
  NIST Special Publication 800-142, 2010.
- Kuhn, D. R., D. R. Wallace, and A. M. Gallo. "Software fault interactions
  and implications for software testing." *IEEE Transactions on Software
  Engineering* 30(6), 2004.
