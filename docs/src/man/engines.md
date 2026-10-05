# Engines

A covering design comes from an engine, chosen with the `engine` keyword of
[`covering`](@ref), [`all_pairs`](@ref), and the other covering functions.
Every engine keeps the same promise: every returned case is valid, every
feasible combination is covered, and every excluded combination is reported
(contract §1.3, §1.4). Generation checks the cases against the rules and the
combinations before it returns them, whichever engine made them (§1.21).
The engines differ in how many cases they give, how long they take, and
whether they use randomness. [`excursions`](@ref) and
[`full_factorial`](@ref) are strategies, not engines, and take no `engine`.

| Engine | What it does | Randomness | Use when |
|:--|:--|:--|:--|
| [`IPOG`](@ref)`()`, the default | Builds the design one parameter at a time | none | tests are cheap, or for any space at all |
| [`Auto`](@ref)`()` | The smaller of IPOG's design and the catalog's array | none | you want fewer cases at little cost |
| `Auto(goal = :compact)` | That, then the row reducer | seeded | each case is expensive |
| [`Construction`](@ref)`()` | An algebraic array from a catalog | none | every parameter has the same number of values |
| [`Compact`](@ref)`(inner)` | Removes rows from `inner`'s design | seeded | each case is expensive, with an engine you choose |
| [`GND`](@ref)`()` | A seeded greedy search | seeded | you want designs that differ but keep the guarantee |

[`recommend`](@ref) says, before anything is generated, what `Auto` would
run for your space and why.

## The size of a design, and its lower bound

No engine promises a minimum number of cases (§8.1). Every covering result
does state a lower bound beside its count: no design for the same request
can have fewer cases than this, though the fewest a design can have may be
more. Each case holds exactly one combination of any set of parameters, so
the combinations of one set need a case each; a must-include row is a case
of every design; and the negative rows of each [`Invalid`](@ref) value are
bounded the same way and added. The summary line shows the bound, and says
"minimal" when the count meets it, which proves that no design has fewer
cases (§8.4, §8.7):

```@example engines
using UnitTestDesign
all_pairs(fill(1:3, 4)...)
```

```@example engines
all_pairs(fill(1:3, 4)...; engine = Auto())
```

`cases.record` holds the bound, its proof in words, and whether the count
meets it, beside the engine's configuration and what each stage did (see
[What a result records](#What-a-result-records)); [`report`](@ref) prints
the bound on its "size:" line. Where rules
exclude combinations, the bound counts only the feasible ones. A count above
the bound is not necessarily above the minimum: for 8 binary flags the bound
is 4, and the smallest design that exists has 6 cases, by Kleitman and
Spencer's theorem on pairwise arrays of two values (Kleitman and Spencer
1973; Colbourn 2004, p. 127), which `Auto()` builds.

## IPOG

IPOG, the in-parameter-order generator, covers the first few parameters,
then adds one parameter at a time. Each step first gives the new parameter
a value in the existing cases, choosing values that cover the most new
combinations, and then adds cases for the combinations still missing. The
[IPOG](ipog.md) page describes the algorithm.

IPOG uses no randomness (§9.4). For the same inputs, the same package
version, and the same Julia version, it returns the same cases in the same
order, in every run and every process (§9.1). It covers any request: rules,
must-include rows, `stronger` groups and `Invalid` values.

## Auto

`Auto` chooses the engine from the request. `goal` says what your tests
cost, which the space can't tell:

| `goal` | Runs | For |
|:--|:--|:--|
| `:fast` | IPOG alone, the same cases as `engine = IPOG()` | cheap tests |
| `:balanced`, the default | the smaller of IPOG's design and the catalog's array, where the catalog applies | most uses |
| `:compact` | that, then the row reducer with `effort` | expensive tests |

`:balanced` is never larger than `:fast` wherever it builds IPOG's design
too, and costs little more: where the catalog applies, building its array
takes milliseconds. Where every parameter has the same number of values it
is often a quarter smaller or more. On spaces whose parameters have
different numbers of values the catalog seldom applies, and `:balanced`
gives IPOG's cases. So `:fast` is what `IPOG()` already does, and not a
recommendation.

How `:balanced` chooses, from the request alone:

- where the catalog doesn't apply (different numbers of values on more than
  `strength + 1` parameters), it runs IPOG;
- where the catalog's array has as many cases as the lower bound, no design
  has fewer, so it builds the array without running IPOG;
- where the space has at most 100,000 combinations to cover, counted before
  the rules, it builds both and keeps the one with fewer cases, IPOG's on a
  tie, so that it gives IPOG's cases unless the catalog's are fewer;
- above that, it builds the catalog's array for a shape the catalog builds
  exactly (every parameter with the same number of values, or `strength + 1`
  parameters, with no rules, no must-include rows other than negative ones,
  and no `stronger` groups), and runs IPOG otherwise. In the package's
  benchmarks no such space had a catalog array larger than IPOG's design,
  but there the two are not compared, so that is measured, not guaranteed.

`:compact` reduces that winner once, with the row reducer of
[`Compact`](@ref), unless the space is past the reducer's limits (below),
when it returns the winner as it is and the record's `chose` names the
winner alone. The negative rows of a space with `Invalid` values are chosen
the same way, for each invalid value, and the record keeps each choice.

```@example engines
eight = fill(1:7, 8)          # eight parameters with seven values each
(IPOG = length(all_pairs(eight...)), Auto = length(all_pairs(eight...; engine = Auto())))
```

```@example engines
recommend(eight...)
```

The result records what `Auto` chose, `cases.record.ordinary.chose`, and
each start it ran, with its size and what it built,
`cases.record.ordinary.starts`; the summary line names it, as "Auto:
Construction()". The choice depends only on the request, never on the
clock, a limit, or which other packages are loaded (§9.12), but a later
version may choose differently (§9.8). `:fast` and `:balanced` use no
randomness; `:compact` draws from `seed`, 0 by default, which the result
records (§9.11).

## Construction

`Construction` builds the design from a catalog of algebraic constructions,
for a space whose parameters all have the same number of values, or that
has at most `strength + 1` parameters. It chooses the smallest array the
catalog has for the shape, from sizes alone, without searching:

- orthogonal arrays (Bush) for a prime-power number of values, which show
  every combination exactly once: the fewest cases possible, and the balance
  a designed experiment wants;
- the zero-sum array for `strength + 1` parameters of any sizes, also at the
  lower bound;
- Kleitman and Spencer's arrays for two values, which are the smallest that
  exist;
- cover starters, products of arrays, projection, tripling and fusion at
  strength 2; the LFSR array and its copies, group arrays, the ordered design
  and doubling recursions at strength 3.

Above strength 3 it offers only the arrays that meet the lower bound, the
zero-sum and orthogonal arrays, and refuses the rest. For 2 to 12 values and
3 to 20 parameters at strength 2, the catalog's array equals the smallest
known at 104 of 198 shapes and is within 10% of it at 166.

With rules, must-include rows or `stronger` groups, the catalog's rows seed
IPOG: those that no rule forbids are kept, after the must-include rows,
except a row that holds nothing the must-include rows and the rows before it
don't, so a result passed back as `must_include` for the same space gains no
cases; then IPOG adds what they leave uncovered. Partial must-include rows,
such as a design passed back after parameters were added or removed, are
first completed as IPOG would complete them, when that shows more of the
catalog's rows to be unneeded. With `stronger` groups the seed is often the
strongest group's own array, on that group's parameters, which IPOG extends
to the others. With a few rules this is much smaller than
IPOG alone; as rules forbid more of the array it helps less, which is why
`Auto` builds both. A space it has no array for, such as parameters with different numbers
of values, is refused with the reason, in an `ArgumentError` that suggests
`IPOG()` or `Auto()`. With `Invalid` values the ordinary cases are the
catalog's, and the negative rows of each invalid value cover a request one
strength lower on the other parameters; where the catalog has no array for
that request, as at strength 1, those rows are IPOG's, though the result
names `Construction`. The negative rows repeat some of the array's
combinations, so the record of such a design never calls it an orthogonal
array. The result's record names the array:

```@example engines
cases = all_pairs(eight...; engine = Construction())
cases.record.ordinary.catalog
```

`Construction` uses no randomness (§9.4).

## Compact

`Compact(inner; seed = 0, effort = 1)` runs `inner`, then removes rows from
its design, after the tabu searches TCA and FastCA: it deletes the row whose
removal uncovers the fewest combinations, repairs the design at that size by
changing one value of a case or copying in a case from the start, and
repeats while each repair succeeds, stopping at the lower bound the result
records. Every case it writes is checked against the rules on its own, so it
never searches, can't stop at `feasibility_limit`, and its cases don't
depend on it (§3.8). Must-include rows stay first and unchanged. The
negative rows of a space with `Invalid` values are reduced too, for each
invalid value; where `inner` refuses that request, as `Construction()` does
at strength 1, IPOG's rows for it are reduced, as `Compact(IPOG())` would.

On 100 random spaces of 4 to 12 parameters with 2 to 7 values, at strength
2, it reached the lower bound, and so proved its design minimal, on 92, in
under 50 ms each. From the catalog's array it ends lower than from IPOG's
design. `seed` seeds a fresh generator for every call, so the same seed
gives the same cases; `effort` multiplies its two budgets, of steps and of
combinations read, never seconds (§9.11). Beyond 2²⁵ combinations to cover,
or 65,535 cases, it returns `inner`'s design unreduced. The result's record
says what it did, `cases.record.ordinary.reducer`, and what `inner` did,
`cases.record.ordinary.start`.

## GND

GND builds the design one case at a time, in the manner of the AETG
generator (Cohen et al., 1997). For each new case it draws `candidates`
random candidate cases. Each candidate starts from the parameter with the
most uncovered combinations and sets the others in a random order, giving
each the value that covers the most uncovered combinations. GND keeps the
candidate that covers the most, and repeats until every required
combination is covered.

```julia
GND(; seed = 0, candidates = 50, rng = nothing)
```

- **`seed`**: every call seeds a fresh generator from `seed`, so repeated
  calls with the same inputs return the same design (§9.5). The default is
  0. The seed is recorded in the result, as `cases.seed`, and
  [`report`](@ref) prints it. Another seed gives another design with the
  same guarantee.
- **`rng`**: to draw from your own generator instead, pass it as `rng`. GND
  copies it at the start of every call and never advances it, so two calls
  with the same `rng` agree and your generator is left as it was (§9.6).
  The recorded seed is then `nothing`.
- **`candidates`**: the number of candidate cases drawn for each new case.
  More candidates mean more work per case and do not reliably give a
  shorter design. The 0.4 keyword `M` still works, with a deprecation
  warning, and means `candidates`.

**The progress guarantee.** If no candidate covers anything new, GND builds
the case from the first uncovered combination instead. That combination is
feasible, since only feasible combinations are required, so it can be
completed into a valid case that covers it. Every round therefore covers at
least one combination, and GND stops after at most as many rounds as there
are required combinations. There is no retry limit and no "could not
construct a case" error.

Other seeds give other designs, of slightly different lengths, and the same
`rng` gives the same design without advancing it:

```@example engines
[length(all_pairs(fill(1:8, 10)...; engine = GND(seed = s))) for s in 0:4]
```

```@example engines
using Random
rng = Xoshiro(2024)
before = copy(rng)
four = fill(1:4, 10)
a = all_pairs(four...; engine = GND(rng = rng))
b = all_pairs(four...; engine = GND(rng = rng))
(same_design = a == b, rng_unchanged = rng == before, recorded_seed = a.seed)
```

## What a result records

A covering result keeps how its cases were made in `cases.record`. The
lower bound, its proof, and whether the count meets it (`minimal`) are the
package's own, proved at generation and checked against the cases; no
engine sets them. `cases.record.engine` is the engine's configuration, the
whole tree of it: each engine's name, constructor call, seed and settings,
with an engine it wraps or chooses among nested inside. The seed line of
[`report`](@ref) names that call, which with the same request gives the same
cases:

```@example engines
nine = fill(1:3, 4)
cases = all_pairs(nine...; engine = Compact(GND(seed = 17); seed = 3, effort = 2))
cases.record.engine
```

```@example engines
report(cases)
```

`cases.record.ordinary` is the stage that made the ordinary cases: the
engine's call, the cases it made, and what it reports, which for `Compact`
is its inner engine's stage, `start`, and the reducer's run, `reducer`; for
`Auto`, each start it ran, `starts`, which one it kept, `kept`, and what it
chose, `chose`; and for `Construction`, its array, `catalog`:

```@example engines
cases.record.ordinary
```

With `Invalid` values, `cases.record.negative` has one entry for each
invalid value: the parameter, the value, the cases that hold it, and the
stage that covered its negative combinations, a request one strength lower
on the other parameters. Its `engine` says which engine ran there: the same
one, or IPOG where the engine has nothing for that request, as
`Construction` has nothing at strength 1:

```@example engines
flagged = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3))
all_pairs(flagged; engine = Construction()).record.negative
```

## What every engine does with rules

Before generating, the call classifies every combination at the requested
strengths as required or excluded, with the rules that exclude it
([Constraints](../explain/constraints.md)). While generating, IPOG, GND and
the catalog's seeded path set a value only when the partial case can still
be completed into a valid case; the reducer writes only cases it has checked
whole. No engine can reach a dead end. Before returning, generation checks
every case against the rules and every required combination against the
cases; a failed check is an internal error, never a returned design
(§1.21). A search that reaches `feasibility_limit` throws a
[`ResourceLimitError`](@ref) rather than return a design it cannot certify
(§3.6).

## How long the designs are

Cases for some spaces at this release, with the lower bound each result
records. "Compact" is `Auto(goal = :compact)` at its default effort and seed.

| Space | Strength | IPOG | GND, seed 0 | `Auto()` | Compact | Lower bound |
|:--|--:|--:|--:|--:|--:|--:|
| 8 binary flags | 2 | 9 | 8 | 6 | 6 | 4 |
| 3 parameters × 6 values | 2 | 40 | 40 | 36 | 36 | 36 |
| 8 × 7 values | 2 | 79 | 73 | 49 | 49 | 49 |
| 10 × 8 values | 2 | 113 | 100 | 78 | 78 | 64 |
| 20 × 10 values | 2 | 217 | 200 | 155 | 155 | 100 |
| 12 × 3 values | 3 | 74 | 68 | 53 | 53 | 27 |
| 6 × 6 values | 3 | 363 | 340 | 276 | 271 | 216 |
| `smooth`: 4 × 3 values, two rules | 2 | 13 | 12 | 12 | 11 | 9 |
| `bench12`: 12 parameters, four rules | 2 | 22 | 25 | 22 | 18 | 16 |
| `bench12` | 3 | 93 | 96 | 93 | 71 | 64 |
| 15 × 4 values (fixture 1) | 4 | 958 | 936 | 958 | 826 | 256 |

Where every parameter has the same number of values, the catalog is far
below IPOG: over a sample of 132 such shapes at strength 2, IPOG returns a
median of 30% more cases, and over 70 at strength 3, 38% more. On spaces of
parameters with different numbers of values, `Auto()` is IPOG, and the
reducer is what removes cases: on 100 random such spaces at strength 2 it
saved 9% of IPOG's cases on average. No design for `smooth` has fewer
than 11 cases, which an exhaustive search over its 57 valid cases shows (the
package's tests repeat it), and none for 8 binary flags has fewer than 6, by
Kleitman and Spencer's theorem. Those results have the fewest cases
possible, though their bounds are lower, and the package, which calls a
count minimal only when it meets its bound, doesn't say so (§8.4).

## What a smaller design gives up

A pairwise design covers some triples by accident, and a smaller one covers
fewer: `bench12`'s 22 IPOG cases cover 61.7% of its feasible triples, and
the reduced 18 cover 55.9%. When tests are cheap, the larger design is
arguably the better one: it finds more of the failures that need three
values together. [`report`](@ref)'s "bonus" line counts these triples for
any result, and [`all_triples`](@ref) covers them all. This is why no
default reduces a design.

## What a call costs, and where it stops

The time of a warm call on an Apple M2 laptop with Julia 1.13, and the
peak memory of the process, which includes about 310 MiB for Julia and the
package. A call is slower when a garbage collection lands in it, and a peak
moves with the collector: where two figures are given, both were measured. "Compact" is `Auto(goal =
:compact)`; "one rule" is a single rule forbidding one pair. A first call
also compiles: about a tenth of a second for a small space, and 3 seconds
for a space of 250 parameters, for its row type.

| Space | Strength | Engine | Cases (lower bound) | Warm call | Peak memory |
|:--|--:|:--|:--|:--|:--|
| 10 × 3 values | 2 | IPOG; `Auto()`; compact | 17; 15; 14 (9) | under 1 ms; under 1 ms; 20 ms | 310 MiB |
| 50 × 4 values | 2 | IPOG; `Auto()`; compact | 46; 40; 38 (16) | 9 ms; 9 ms; 0.14 s | 324 MiB |
| 250 binary | 2 | IPOG; IPOG, one rule | 17; 19 (4) | 0.11 s; 0.95 s | 460 MiB; 1.9 GiB |
| 250 × 4 values | 2 | IPOG; `Auto()` | 63; 52 (16) | 0.79 s; 6 to 20 ms | 460 MiB |
| 8 × 64 values | 2 | IPOG; `Auto()` | 7168; 4096, minimal | 1.6 s; 1 ms | 310 MiB |
| 30 × 4 values | 3 | IPOG; IPOG, one rule; compact | 256; 263; 178 (64) | 0.33 s; 1.0 s; 14 s | 334 MiB; 850 MiB; 320 MiB |
| 15 × 4 values | 4 | IPOG; compact | 958; 826 (256) | 1.0 s; 13 s | 350 MiB |
| 20 binary | 6 | IPOG; IPOG, one rule | 376; 400 (64) | 3.6 s; 10 to 13 s | 635 MiB; 4.3 to 7.1 GiB |

(`benchmark/engine_costs.jl` repeats these.) What grows, and what stops a
call that is too large; a design that can't be certified is not returned:

- **Strength and width.** The combinations to cover grow with the number of
  parameters to the power of the strength, and IPOG's time with them and
  with the cases. The supported scale is 250 parameters, 64 values and
  strength 4, with strengths 5 and 6 on about 20 parameters; strength 6 on
  20 three-valued parameters took 19 minutes at the start of this release's
  work.
- **Rules.** With any rule, every required combination keeps full-width
  bookkeeping: at least 24 bytes per parameter for each combination, and
  a process's peak measured several times that. Twenty binary parameters at
  strength 6 with one rule peaked at 4.3 to 7.1 GiB, where 24 bytes per
  parameter per combination comes to 1.1 GiB, and the CASA benchmark models
  at strength 3 passed 2 GiB from 55 parameters up. At
  the start of this release's work, 200 options with 24 rules took 3
  seconds and 1.4 GiB, and 400 options with 46 rules 19 seconds and 6.2 GiB. A rule that reads the whole case is checked
  only on complete cases, which makes its search far longer than a scoped
  rule's ([what rules cost](../explain/constraints.md#What-rules-cost)).
- **`feasibility_limit`** (1,000,000 nodes per question by default) stops a
  search that can't decide whether a combination or a partial case has a
  valid completion, with a [`ResourceLimitError`](@ref) that names it.
  Raise it to finish; a larger limit never changes the cases of a call that
  succeeded (§3.8).
- **Memory** has no limit in the package: a request too large for the
  machine fails as the operating system fails it.
- **The reducer** returns its start unreduced beyond 2²⁵ combinations to
  cover or 65,535 cases, and its budgets count work: at the default effort
  it takes up to about 20 seconds at strength 3 on larger spaces, such as
  30 parameters of 4 values, and at strengths 4 to 6.
- **Certification** reads every case for every set of `strength`
  parameters, whichever engine made the design.

## Which to choose

- **Use IPOG** when tests are cheap. It is the default, it is deterministic,
  it is fast, and it covers any request.
- **Use `Auto()`** when cases cost something to run: it is never larger
  than IPOG where it builds both (and above 100,000 combinations, on the
  package's benchmarks, it never was), and much smaller when every
  parameter has the same number of values. [`recommend`](@ref) shows what
  it would do.
- **Use `Auto(goal = :compact)`**, or `Compact` around an engine you choose,
  when each case is expensive, such as a simulation or a hardware run. Its
  lower bound tells you how far from the minimum the design can be.
- **Use `Construction()`** when you want the catalog's array itself, such as
  an orthogonal array for a designed experiment.
- **Use GND with several seeds** when you want designs that differ but keep
  the same guarantee, for instance to vary the cases a nightly job runs.

[`design_sizes`](@ref) compares engines on your space, one row per engine:

```@example engines
design_sizes(fill(1:5, 6)...; strengths = 2:3, distances = Int[], engine = [IPOG(), Auto(), Auto(goal = :compact)])
```

No engine promises the same design across package versions, or after you
add a value or a rule (§9.8, §9.9); `Auto`'s choice and the catalog's arrays
may change too. When the exact cases matter, save them and pass them back
as `must_include`, which keeps every saved case and adds only what an edit
requires (§9.10); see [Commit a design as data](../howto/commit_design.md).

## Before 0.5

Two things changed in GND for 0.5. The 0.4 release scored candidate values
against the wrong number of known parameters, so once enough parameters
were set its choices were effectively random. Fixing the score shrank GND's
designs by 17 to 35 percent (for ten four-valued parameters, pairwise, from
36 to 38 cases down to 30; for ten eight-valued parameters, from about 152
down to 100). And the 0.4 `GND()` drew from an unseeded generator, so two
identical calls gave different designs; the fixed default seed replaces it.
Comparisons made with 0.4 therefore understate GND, and the 0.4 version of
this page, which said GND gives shorter designs in general, overstated it.

## Reference

- Cohen, D. M., S. R. Dalal, M. L. Fredman, and G. C. Patton. "The AETG
  system: An approach to testing based on combinatorial design." *IEEE
  Transactions on Software Engineering* 23(7), 1997.
- Colbourn, C. J. "Combinatorial aspects of covering arrays." *Le
  Matematiche* 59, 2004. The catalog's other constructions and their sources
  are listed in the package's source, `src/construction_arrays.jl`.
- Lin, J., C. Luo, S. Cai, K. Su, D. Hao, and L. Zhang. "TCA: An efficient
  two-mode meta-heuristic algorithm for combinatorial test generation."
  ASE 2015.
- Lin, J., S. Cai, C. Luo, Q. Lin, and H. Zhang. "Towards more efficient
  meta-heuristic algorithms for combinatorial test generation." ESEC/FSE
  2019.
