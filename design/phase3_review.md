# Phase 3 review: engines that keep the promise

Date: 2026-09-27. Branch `feature/phase3-engines`, stacked on
`feature/phase2-model` (PR #53) and `feature/one-oh` (PR #52).
Plan: `design/20260926_implementation_plan.md`, Phase 3.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1 | `Request` (arity, strength, groups, must-include matrix, `dead`, `witness`, `targets`, `classify_targets`), `Design`, `Excluded`, `validate_design`, `to_cases` | `src/request.jl`; engine structs in `src/engines.jl` |
| 2 | IPOG on `dead()` at the three sites; `ipog_multi_way` rewritten full-width; unconstrained fast path kept | `src/parameter_order.jl`, `src/coverage_matrix.jl` |
| 3 | GND on `dead()`, progress guarantee, `GND(; seed = 0, candidates = 50, rng)`, `M` deprecated | `src/greedy_tuples.jl`, `src/engines.jl` |
| 4 | `build_excursion(arity, distance, base, dead)`, dropped rows reported, forbidden base is an error | `src/excursions.jl` |
| 5 | Incremental full factorial with a 10^6 candidate limit, candidate and accepted counts | `src/full_factorial.jl` |
| 6 | Final validation in every `generate` | `src/request.jl` |
| 7 | `disallow`, `wrap_disallow`, `Counter`, `generate_tuples`, the `nothing` sentinel removed; positional API routed through `Request` | `src/factorial_interface.jl` |
| 8 | Random gate on both engines and strengths, all Phase 3 fixtures flipped | `test/test_random_problems.jl`, `test/test_fixtures.jl` |
| 9 | Benchmark script and results, 0.4 comparison | `benchmark/run.jl`, `design/benchmark_results_phase3.md` |

Full suite: 271,840 pass, 13 broken/skipped (the Phase 4–6 lines: 5 + 3 + 5),
0 failures, about 5 minutes. Aqua green. Docs build clean after the two
`disallow` examples became plain code blocks (Phase 7 rewrites them).

## Acceptance gate

- **Random gate, multiplier 1.0, fixed seeds:** 500 pairwise and 500
  three-way problems, both engines, every design complete by the oracle,
  `required == covered == checker feasible`, every excluded target's
  status and direct rules matching the checker. 0 errors. The gate items
  take 54 s. One `--randseed` run also passed.
- **Issue #51** (os/gpu/driver): both engines return 6 cases covering all
  13 required pairs, with `(windows, gpu)` reported as implied and the
  two direct pairs by rule. Closed.
- **Targeted regressions:** the four greedy dead ends, `bench12` at both
  strengths, `disconnected_unsat` (empty design, 16 excluded),
  `whole_case_connects` (the single valid row), overlapping groups with a
  rule across them (a 0.4 bug found during the rewrite: values set for one
  group were invisible to the next, giving invalid rows), the GND progress
  path (triggers on 14 of 20 seeds with `candidates = 1` on a constructed
  space, never on the fixtures at 50), must-include rows first and
  unchanged, caller's `stronger`/`wayness` unmutated.
- **A limited search never returns an incomplete design:** at
  `feasibility_limit = 1` classification throws `ResourceLimitError`; at
  `feasibility_limit = 100` on a space where every target classifies but a
  placement search runs out, both engines throw during placement.
  Sweeping the limit from 1 to 10^6, every call either throws or returns
  a design the checker accepts, and all returned designs are identical.
- **`disallow` removed:** passing it is an ordinary `MethodError`.

## Benchmarks (laptop; CI-runner measurement pending)

Julia 1.13.1, Apple M2, 1 thread, commit b955f50, GND seed 0. Median of 5
warm runs; cold start reported separately in the results file.

Fixture 1, 15 × 4 at strength 4, identical designs on 0.4 and new:

| Revision | Engine | Cases | Median | Allocations |
|:--|:--|--:|--:|--:|
| 0.4 | IPOG | 958 | 3.48 s | 181.7 M |
| new | IPOG | 958 | 3.95–4.09 s | 199.4 M |
| 0.4 | GND | 936 | 239 s | 76.4 M |
| new | GND | 936 | 236–252 s | 91.3 M |

IPOG pays 14–18% for building the 349,440-target list and validating;
the core is unchanged. GND is unchanged.

Fixture 2, `bench12` (no 0.4 baseline: its IPOG throws, its GND never
returns):

| Strategy | Cases | Median | Feasibility queries | Rule checks |
|:--|--:|--:|--:|--:|
| IPOG, strength 2 | 22 | 1.4 ms | 817 | 717 |
| GND, strength 2 | 25 | 21 ms | 26,837 | 35,549 |
| IPOG, strength 3 | 93 | 17 ms | 6,616 | 3,325 |
| GND, strength 3 | 96 | 0.30 s | 106,528 | 134,252 |
| full factorial | 207,360 | 0.83 s | | 1,150,848 |

Proposed regression tolerance: 35% on time for calls of 10 ms or more
(twice the observed 16% spread, rounded up), no time gate below 10 ms,
allocation counts exact per Julia version. Not to be enforced until
re-derived on the CI runner.

## Decisions and findings for review

1. **`ipog_multi_way` rewritten** rather than patched: rows stay full
   width in the space's parameter order, parameters are added with
   stronger-group members first, and required targets are grouped by
   their last parameter in that order so mixed strengths are covered in
   one pass. This fixed the overlapping-group bug above and made
   `ipog_inner`, `add_tests_to_seeds`, `WayWork`, `reorder_disallow`,
   `keep_allowed`, `putative_allowed`, and `ipog_bytuple_instrumented`
   dead code, now deleted.
2. **Excursion groups:** `distance` is the base group's distance and each
   `stronger` group `(G, s)` allows up to `s` changes within `G`, the 0.4
   `wayness` semantics. A request for an excursion is built with
   `strength = distance`.
3. **Full-factorial order** stays 0.4's (last parameter fastest); the
   contract requires the same set as full-strength covering, not order.
4. **Lazy memo memory** (the Phase 2 review's open question): with one
   whole-case rule, generation on `bench12` retains 98 k entries, 26 MB;
   on fixture 1 through strength 4, 394 k entries, 128 MB. The memo grows
   with work done, not the product. Decision needed: keep, bound, or move
   into the request. My recommendation: move it into the request
   (per-call lifetime, like the search caches) in Phase 4, since a
   long-lived space in a test suite should not retain generation work.
5. **Performance candidates, not optimized this round:**
   `validate_design` on full factorial is 92% of the call, dominated by
   the value round trip (`from_indices` 55%, `case_indices` 30%); `forbids`
   allocates a runtime-length tuple per check (2–3%); unconstrained
   requests build the full target list they do not need. Phase 4 or 5.
6. **Positional seeds** now match values by identity (type and `isequal`),
   where 0.4 used `indexin`; duplicate values in a positional domain are an
   error (§2.5). `wayness` is translated but does not warn yet (Phase 4).
7. **`generate` is unexported** and `Excursion` remains only as an
   internal marker; Phase 4 defines the public `covering`, `excursions`,
   and `full_factorial` over a `TestSpace`.

## Pending tests after this phase (13)

| Phase | Count | What |
|:--|--:|:--|
| 4 | 5 | typed values preserved in results, `must_include`, `stronger` keyword |
| 5 | 3 | coverage/report |
| 6 | 5 | negative generation, partitions kept, negative must-include |

## Review round 1

Four findings applied. Measurements: Julia 1.13.1, Apple M2, 1 thread,
median of 5 warm calls after one discarded call, same method as above.

### 1. Excursions have one distance and no groups

Decision 2 above is withdrawn. `generate_excursion(request; distance, from)`
takes one `distance`, an integer of at least 0, and every row after the
must-include rows is within Hamming distance `distance` of the base. Nothing
widens it. Distance 0 returns the must-include rows and the base. A distance
above the parameter count is clamped, and `notes.distance` records the
clamped value. A request with any `stronger` group is an `ArgumentError`:
"excursions take a single distance; stronger groups apply to covering
designs". `build_excursion` and `excursion_subsets` no longer take `groups`,
and `_validate_excursion` checks the Hamming distance itself instead of a set
of allowed change sets.

Excursion distance is not covering strength. The request's `strength` is
never read, so the caller builds the request with the default strength. The
positional routing now builds `Request(space; strength = 1, stronger,
must_include)` and passes `distance = n_way`, so `pairs_excursion([1, 2, 3])`
returns its three rows instead of failing §11.2. `stronger` (from `wayness`)
is passed through so that the excursion refuses it; 0.4's
`pairs_excursion(...; wayness)` is now that error.

Contract §7.5–§7.7 now state: one distance, distance 0, the clamp, no groups
(with the error text), every non-must-include row within the distance, strength
unused, dropped rows reported, and base validity (partial, `Invalid`, or
rule-breaking bases are errors naming the cause; the base is never dropped).

Tests: the group tests are gone, replaced by the refusal (distance 0, 1 and
2, any base; a group at the base strength is no group). A new distance 0 test
covers the base alone, must-include rows plus base, and the forbidden-base
error. A new oracle test uses a five-parameter space with three rules (one
whole-case), two bases, and distances 1, 2, n and n + 2. In each case no row
exceeds min(d, n), the rows are exactly the oracle's valid rows within the
distance, and kept + dropped equals the product rows within the distance.

### 2. Explanations are kept

`Excluded` has a fifth field, `limit::Union{Nothing, Pair{Symbol, Int}}`,
taken from `IndexExplanation.limit` through the same `_limit_pair` that
`explain` uses. On Fable's solver space with `explanation_limit = 1`, the two
implied pairs record `minimal = :unresolved`, `limit = :explanation_limit => 1`.
Forbidden and verified targets record `nothing`. A report can print
"explanation unresolved: explanation_limit = 1 reached" without searching
again.

An infeasible partial must-include row now carries its explanation (§10.4).
The row is explained by `explain_partial` on the request's `Feasibility`,
under the request's `explanation_limit`. The clause comes from
`_print_exclusion`, which was factored out of `show(::Explanation)`, so it
reads word for word like `explain`:

```
ArgumentError: must_include row 1, (solver = :lu, tol = 0.001), has no valid
completion: rules 1 and 2 together exclude it (rule 1: @require(mode == :exact
|| solver == :none); rule 2: exact mode needs a tight tolerance) (contract §10.4)
```

A single rule reads "rule 1 (a is never 1) excludes it". A search that was
cut short appends "; whether each rule is needed is unresolved:
explanation_limit = 1 reached". The error type is still `ArgumentError`. The
§10.3 message (a row that breaks a rule directly) now shares
`_broken_rules` with the excursion base error and the validation error.

### 3. The lazy-rule memo belongs to the request

Design:
- `_LazyRule` has no memo. A `RuleTable`'s `lazy` evaluates the predicate on
  every call, and the `Bool` check and `ConstraintError` wrapping are
  unchanged. `forbids(table, partial)` is therefore unmemoized. `isallowed`,
  tests, and the checker use it.
- `Feasibility` owns `rule_memo`, one `Dict{NTuple{N,Int},Bool}` per lazy
  table (`nothing` for a tabulated one). Every rule check it makes goes
  through `forbids(f, k, partial)`: `violates`, `violated_rules`, the direct
  check, forward-checking prunes, and so the request's classification,
  engine placements, must-include checks, and final validation. The key is
  built with `Val(N)`, so the memo path is type-stable. A throwing
  evaluation stores nothing.
- A verdict depends on the table alone, not on the rule set, so the
  `Feasibility` objects of one operation share the dicts through a new
  `memos` keyword. Deletion trials share their parent's memo, as they shared
  the space's before. A `FeasibilityContext` (one `explain`/`classify` call)
  owns one memo per space rule and hands it to every row kind's
  `Feasibility`.
- `memo_size(space)` is gone. `memo_size(f::Feasibility)`,
  `memo_size(request)`, and `memo_size(context)` replace it. The request holds
  the `Feasibility`, so the memo is released with the request.
- Contract §3.5 and §12.19 now say the memo is part of the operation context
  (a request, or one `explain`/`classify` call), shared by that operation's
  searches, deletion trials, and validation, and released with it. A
  `TestSpace` retains nothing from any operation.

Tests (new item in `test/test_request.jl`, 10 parameters of 3 values, one
whole-case rule and one scoped rule):
- `Base.summarysize(space)` is identical before and after `generate`.
- `memo_size(request)` is 0 before generation and positive after.
- Validation adds no entries: every row was checked during generation.
- A second `Request` starts at 0, and generating on it leaves the first
  unchanged.
- Ten alternating IPOG/GND generations at strengths 2 and 3 on the same
  space leave `summarysize(space)` constant all ten times.
- Full factorial memoizes exactly 3^10 verdicts on its request.
- `explain` and `classify` leave the space's size unchanged, and a
  `FeasibilityContext` starts empty.

`test/test_explain.jl` now shows that a second `explain` call evaluates the
rule again (the 2,000-value probe goes from 2,000 to 4,000 predicate calls).
It also shows that within one context each tuple is evaluated once
(`calls == memo_size(context) <= 18`). `test/test_feasibility.jl` covers
sharing, the `memos` validation, and throw-stores-nothing.

The benchmark's memo section, rerun (whole-case rule `forbid(case -> false)`
added, one fresh request per row, single first calls):

| Space | After | Cases | Time (s) | `summarysize(space)` | `memo_size(request)` | `summarysize(request.feasibility)` | Nodes |
|:--|:--|--:|--:|--:|--:|--:|--:|
| bench12 | (before) | – | – | 5,440 | – | – | – |
| bench12 | IPOG, 2 | 22 | 0.314 | 5,440 | 982 | 978,768 | 6,800 |
| bench12 | IPOG, 3 | 93 | 0.075 | 5,440 | 4,870 | 5,710,288 | 54,583 |
| bench12 | GND, 2 | 25 | 0.108 | 5,440 | 36,558 | 25,997,320 | 146,828 |
| bench12 | GND, 3 | 96 | 0.623 | 5,440 | 85,380 | 96,593,480 | 497,731 |
| fixture 1 | (before) | – | – | 3,864 | – | – | – |
| fixture 1 | IPOG, 2 | 33 | 0.124 | 3,864 | 4,451 | 3,453,768 | 23,968 |
| fixture 1 | IPOG, 3 | 177 | 0.395 | 3,864 | 47,666 | 54,020,808 | 359,151 |
| fixture 1 | IPOG, 4 | 958 | 9.86 | 3,864 | 389,417 | 392,836,232 | 3,886,299 |

The space no longer grows. Before this change it grew from 5,696 to
25,695,808 bytes on `bench12` and from 4,144 to 127,930,416 on fixture 1.
It is also 256 and 280 bytes smaller at rest (the empty memo dict is gone). Node
counts are identical to the Phase 3 run, so the searches are unchanged.
`summarysize(request.feasibility)` is the request's whole search state: the
completability memo and component witness caches as well as the lazy memo.
It is 393 MB after one strength-4 IPOG call on fixture 1, of which the lazy
memo is about 120 MB (389 k entries at about 300 bytes). All of it is freed
with the request. Bounding per-request state is a separate question for
Phase 4/5 if a real space needs it.

Timings without lazy rules are unchanged (`bench12`: IPOG 1.38 ms / 16.3 ms,
GND 20.7 ms / 0.32 s at strengths 2 / 3; fixture 1 IPOG strength 4 4.03 s).

### 4. Validation in index space

`validate_design` no longer builds values. For each column it checks every
entry against the arity, maps it to space value indices in one reused
buffer, and calls `_violates(request.feasibility, idx)`. That is `violates`
without re-copying and re-checking a key whose entries are candidates by
construction. The row is complete, so every table is consulted, and lazy ones
go through the request's memo. The must-include-first check and the coverage
recount over hash sets are unchanged. Values appear only in `to_cases` and in
the failure message, which now names the rules ("internal error: case 5,
(mode = :fast, solver = :qr, tol = 1.0e-6), breaks rule 1 (...)").

`generate_full_factorial` on `bench12` (207,360 of 331,776 rows valid),
measured on this machine immediately before and after the change:

| | Whole call | Allocated | `validate_design` | Allocated | Share |
|:--|--:|--:|--:|--:|--:|
| before | 0.732 s | 734.6 MiB | 0.661 s | 568.3 MiB | 90% |
| after | 0.076 s | 191.7 MiB | 0.022 s | 25.3 MiB | 29% |

The whole call is 9.6× faster, and validation 30×. The review's 0.83 s /
92% came from the benchmark run. The remaining validation allocation is
`forbids`' runtime-length key tuple (32 bytes × 4 tables × 207,360 rows),
left alone as instructed. On fixture 1 (unconstrained) validation is
unchanged at 0.09 s: it is the coverage recount there, not rule checks.

One reporting change: the request's `stats.evaluations` now includes the
final validation's checks (rows × tables), because validation runs through
the request's `Feasibility`. The "Rule checks" column of fixture 2 rises by
exactly that. IPOG 717 → 805 and 3,325 → 3,697, GND 35,549 → 35,649 and
134,252 → 134,636, full factorial 1,150,848 → 1,980,288. Nodes and queries
are unchanged.

Streaming the recount (not done; the list is kept as the certification). For
an unconstrained request, `classify_targets` is only `targets(request)`,
which builds the 349,440-target list on fixture 1 at strength 4 in 0.469 s
and 506 MiB allocated (57 MiB retained). The classic `ipog` path does not
use the list. Only `validate_design` reads it, plus `length(required)`. A
streamed recount would, for each group and each `s`-subset, count the
distinct projections of the rows and compare the count with the product of
the arities. That is the same certification (every assignment of every
support appears), with no list. A prototype in the scratchpad gives 349,440
covered in 0.041 s and 144 MiB, against 0.090 s and 240 MiB for the current
recount with the list. So streaming would save the whole 0.47 s list and
about 0.05 s of recount: roughly 0.52 s of the 4.03 s call (13%), which would
bring IPOG within a few percent of 0.4's 3.48 s. It applies only when every
target is required (unconstrained, no must-include rows). Overlapping groups
need their shared targets counted once, and GND and constrained requests need
the list anyway (GND covers from it, and classification visits every target
regardless). Recommended for Phase 5 together with the other performance
candidates.

### Suite after round 1

Full suite: 270,373 pass, 13 broken (the same Phase 4–6 lines), 0 failures,
about 5 minutes. Aqua green. Pass totals are not comparable run to run:
`test_combinations.jl` and `test_parameter_order.jl` run time-budgeted random
loops, and two runs of the unchanged HEAD gave 269,760 and 271,487. The
changed files, counted alone in the same environment, went from 143 to 187
(excursions), 127 to 131 (positional interface), 157 to 179 (request), 415 to
455 (constraints), and 102,638 to 102,656 (explain and feasibility). Docs
build clean from a scratch copy of the `docs/` environment with the
repository developed into it, with the same missing-docstrings warning as
before. `docs/Manifest.toml` is untouched.
