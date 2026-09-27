# Benchmark fixtures and procedure for Phase 3

Recorded at the Phase 1 gate (2026-09-26) so that Phase 3 measures the
engines the same way before and after the constraint fix.

## Fixtures

1. **Unconstrained, high strength.** 15 parameters, each with 4 values,
   strength 4. Both engines. This is the case where IPOG's cost is
   dominated by the coverage matrix and GND's by candidate scoring. It
   needs no definition beyond these numbers: no rules, and the values of
   each parameter are `1:4`, so nothing is checked in for it. Its product,
   4^15, is far above the checker's `CHECK_MAX_PRODUCT` of 10^6, so its
   4-way coverage (1365 parameter groups × 256 values = 349440 targets)
   must be counted directly rather than by `test/checker.jl`.
2. **Constrained, pairwise and three-way.** `bench12` in
   `test/fixtures.jl`. It is a *replacement* for Fable's 12-parameter
   configuration example, whose definition was not kept; only its
   statistics survive (`design/interface_fable.md`, line 721). The
   replacement matches every recorded statistic exactly, and
   `test/test_fixtures.jl` asserts them with the checker:

   | | Recorded (Fable) | `bench12` (checker) |
   |:--|--:|--:|
   | Parameters | 12 | 12, arities 4,4,4,4,3,3,3,3,2,2,2,2 |
   | Full factorial | 331776 | 331776 |
   | Valid rows | 207360 | 207360 |
   | Two-way interactions | 590 | 590 (586 feasible) |
   | Uncoverable pairs | 4 | 4 |
   | ... directly forbidden | 3 | 3: `(p1=2, p9=2)`, `(p5=1, p6=1)`, `(p7=1, p10=1)` |
   | ... only by implication | 1, `(p1 = 2, p2 = 2)` | 1, `(p1 = 2, p2 = 2)` |
   | Rules | 4, one over three parameters | 4, one over `(p1, p2, p9)` |
   | Three-way targets | not recorded | 5702 feasible, 92 forbidden, 26 implied |

   The arities are the only twelve from 2 to 4 with that product, and they
   give 590 pairs. Parameter `pk` takes the values `1:arity`. The fixture,
   not the prose, is the reference. Both engines, strengths 2 and 3,
   verified by `test/checker.jl` after each run (about 3 s pairwise and 8 s
   three-way for the checker on this machine).

   **Legacy baseline** (recorded 2026-09-26, prior engines at commit
   `62ab8df`, identical to `d46122d` in `src/`): Julia 1.13.1, macOS
   (arm64-apple-darwin27.0.0), 8 × Apple M2, 1 thread, a laptop, not a CI
   runner.

   | Engine | Strength 2 | Strength 3 |
   |:--|:--|:--|
   | IPOG | `BoundsError` at index 0, 2 ms warm (2.2 s cold) | `BoundsError` at index 0, 24 ms warm |
   | GND (`rng = Xoshiro(0)`) | never returns: exceeded a 20,000,000-call `disallow` watchdog after 47 s | the same, after 46 s |

   IPOG builds rows with `p1 = 2, p2 = 2` and then finds no `p9` for them
   (1 of its 21 rows pairwise, 6 of 91 three-way). GND loops without
   raising its attempt-cap error. So the prior revision has no "before"
   number for this fixture; it joins fixture 3. The IPOG failure was
   asserted with `@test_throws BoundsError` in `test/test_fixtures.jl`
   until Phase 3 replaced it with completeness tests for both engines;
   the GND hang is recorded here only.
3. **Repaired cases.** The random problems that crash IPOG or hang GND on
   the prior revision (see issue #51), `bench12`, and the four greedy
   dead ends frozen in `test/fixtures.jl` (`dead_end_pairwise_1`,
   `dead_end_pairwise_2`, `dead_end_threeway_1`, `dead_end_threeway_2`),
   on which IPOG crashes although no target is implied. These have no
   "before" number; record only the "after" so later phases can detect
   regressions.

## What to record for every measurement

- Julia version (`VERSION`), OS, CPU model, thread count
  (`Threads.nthreads()`), and whether the run is a stable CI runner or a
  laptop.
- Package revision (commit hash) and the engine seed (GND default is 0).
- Compilation policy: the first call is discarded as a cold start and
  reported separately; timings are the median of at least 5 warm runs
  using `@timed` (or BenchmarkTools if it is added as a test dependency),
  with allocations and bytes.
- The case count of the returned design, so a speedup is never bought
  with a larger design unnoticed.
- Retained memory of lazy-rule memos (Phase 2 review round 1). A lazy
  rule's memo belongs to the `TestSpace` and outlives every call (contract
  §12.19), unlike the per-call search caches (§3.5). Record
  `Base.summarysize(space)` and `UnitTestDesign.memo_size(space)` before
  and after generation for two spaces: `bench12` with an added whole-case
  rule, and the 15-parameter, 4-value fixture 1 with a whole-case rule. A
  whole-case memo is bounded by the product of the ordinary domains
  (331776 rows for `bench12`, 4^15 for fixture 1), so the second is the one
  that can grow without a practical bound. The decision to keep the memo on
  the space, bound it, or move it into the request context is taken from
  this measurement, not in advance.
- The search effort alongside the time: nodes and rule checks
  (`Explanation.nodes`, `.evaluations`, or the `SearchStats` of the
  request's feasibility searches). A separate evaluation budget (§3.3) is
  added only if checks per node turn out to dominate.

## Procedure

1. Check out the prior revision (`main` at commit `d46122d`, before
   `release/1.0`) and run fixture 1, the one it handles without crashing.
   Record the table. Fixture 2's legacy baseline is the failure recorded
   above.
2. Check out the Phase 3 branch and run all three fixtures. Record the
   table.
3. Run the same script three times on the CI runner used for the release
   and record the spread. The regression tolerance is set from that
   observed variation (twice the observed spread, rounded up), not
   guessed in advance.
4. Ordinary correctness tests assert completion and coverage only; no
   test asserts machine-dependent seconds. Limit exhaustion and
   progress-guarantee regressions go in the deterministic suite.

The benchmark script lives at `benchmark/run.jl` and writes Markdown tables
that are pasted into the Phase 3 review. Its header gives the commands for
this revision and for the prior one. The Phase 3 results, with the 0.4
comparison and the proposed tolerance, are in
`design/benchmark_results_phase3.md`.
