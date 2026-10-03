# Engines

A covering design comes from one of two engines, chosen with the `engine`
keyword of [`covering`](@ref), [`all_pairs`](@ref), and the other covering
functions. Both keep the same promise: every returned case is valid, every
feasible combination is covered, and every excluded combination is reported
(contract §1.3, §1.4). They differ in how they search, whether they use
randomness, and how long they take. [`excursions`](@ref) and
[`full_factorial`](@ref) are strategies, not engines, and take no `engine`.

- [`IPOG`](@ref), the default, is deterministic and fast.
- [`GND`](@ref) is a seeded greedy search. It is much slower, and it gives
  shorter designs only on some spaces.

## IPOG

IPOG, the in-parameter-order generator, covers the first few parameters,
then adds one parameter at a time. Each step first gives the new parameter
a value in the existing cases, choosing values that cover the most new
combinations, and then adds cases for the combinations still missing. The
[IPOG](ipog.md) page describes the algorithm.

IPOG uses no randomness (§9.4). For the same inputs, the same package
version, and the same Julia version, it returns the same cases in the same
order, in every run and every process (§9.1).

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

## What both engines do with rules

Before generating, the call classifies every combination at the
requested strengths as required or excluded, with the rules that exclude it
([Constraints](../explain/constraints.md)). While generating, each engine
sets a value only when the partial case can still be completed into a valid
case: IPOG checks this at each of its placement steps, and GND while
building each candidate. Neither engine can reach a dead end. Before
returning, generation checks every case against the rules and every
required combination against the cases; a failed check is an internal
error, never a returned design (§1.21). A search that reaches
`feasibility_limit` throws a [`ResourceLimitError`](@ref) rather than
return a design it cannot certify (§3.6).

## How long the designs are

Both engines produce compact designs. Neither promises a minimum number of
cases, and neither promises to be shorter than the other (§8.1). The case
counts measured for this release:

| Space | Strength | IPOG | GND, seed 0 |
|:--|:--|--:|--:|
| 15 parameters × 4 values, no rules | 4 | 958 | 936 |
| `bench12`: 12 parameters, four rules | 2 | 22 | 25 |
| `bench12` | 3 | 93 | 96 |
| four constrained spaces on which the 0.4 IPOG failed | 2, 2, 3, 3 | 12, 16, 30, 60 | 12, 15, 30, 64 |
| 10 parameters × 8 values, no rules | 2 | 113 | 100 |

The first four rows are the package benchmark (`benchmark/run.jl`; the
Phase 3 results are in `design/benchmark_results_phase3.md` in the
repository). The last row was measured in the study that preceded this
release, and the example below repeats it. GND was shorter by more than a
case only where the combinations are large or many: at strength 4, by 22
cases (about 2 percent), and with eight values per parameter, by 13 cases
(about 12 percent). On the
constrained spaces the two engines were within a few cases of each other,
mostly in IPOG's favor, and for ten four-valued parameters, pairwise, IPOG
was one case shorter.

```@example engines
using UnitTestDesign
four = fill(1:4, 10)    # ten parameters with four values each
eight = fill(1:8, 10)   # ten parameters with eight values each
(four_values = (IPOG = length(all_pairs(four...)), GND = length(all_pairs(four...; engine = GND()))),
 eight_values = (IPOG = length(all_pairs(eight...)), GND = length(all_pairs(eight...; engine = GND()))))
```

Other seeds give other designs, of slightly different lengths:

```@example engines
[length(all_pairs(eight...; engine = GND(seed = s))) for s in 0:4]
```

The same seed, or the same `rng`, gives the same design, and a caller's
generator is not advanced:

```@example engines
using Random
rng = Xoshiro(2024)
before = copy(rng)
a = all_pairs(four...; engine = GND(rng = rng))
b = all_pairs(four...; engine = GND(rng = rng))
(same_design = a == b, rng_unchanged = rng == before, recorded_seed = a.seed,
 seed_repeats = all_pairs(four...; engine = GND(seed = 3)) == all_pairs(four...; engine = GND(seed = 3)))
```

## How long they take

GND is much slower, because it scores every candidate against every
uncovered combination. On the benchmark space of fifteen four-valued
parameters at strength 4, which has 349,440 combinations to cover, IPOG took
about 4 seconds and GND about 4 minutes (236 to 252 seconds) on a laptop
(Apple M2, Julia 1.13); on the CI runner IPOG took 6.8 seconds, and GND is
left out of that job for time. On `bench12` the laptop times were 1.4 ms
for IPOG against 21 ms for GND at strength 2, and 17 ms against 0.30 s at
strength 3. Both engines spend extra time on rules, since every placement
asks whether the case can still be completed; see [what rules
cost](../explain/constraints.md#What-rules-cost).

## Which to choose

- **Use IPOG** unless you have a reason not to. It is the default, it is
  deterministic, it is fast, and on most spaces measured its designs were
  as short as GND's or shorter.
- **Try GND** when each case is expensive to run and the design is large:
  high strength, or parameters with many values. Generate both, compare
  `length`, and keep the shorter; a few percent fewer cases can matter when
  each is a long simulation. [`design_sizes`](@ref) takes an `engine`
  keyword to compare strategies under either engine.
- **Use GND with several seeds** when you want designs that differ but keep
  the same guarantee, for instance to vary the cases a nightly job runs.
  The seed is in the result and in the report, so a failing design can be
  regenerated.

Neither engine promises the same design across package versions, or after
you add a value or a rule (§9.8, §9.9). When the exact cases matter, save
them and pass them back as `must_include`, which keeps every saved case and
adds only what an edit requires (§9.10); see [Commit a design as
data](../howto/commit_design.md).

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
