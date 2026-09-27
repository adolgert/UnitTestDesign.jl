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
