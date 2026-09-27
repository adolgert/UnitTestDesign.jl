# Benchmark fixtures and procedure for Phase 3

Recorded at the Phase 1 gate (2026-09-26) so that Phase 3 measures the
engines the same way before and after the constraint fix.

## Fixtures

1. **Unconstrained, high strength.** 15 parameters, each with 4 values,
   strength 4. Both engines. This is the case where IPOG's cost is
   dominated by the coverage matrix and GND's by candidate scoring.
2. **Constrained, pairwise and three-way.** Fable's 12-parameter
   configuration example, checked in as `test/fixtures/fable12.jl` when
   Phase 3 lands. Only its statistics survive in
   `design/interface_fable.md` (line 721): 12 parameters, full factorial
   331776 of which 207360 are valid, 590 two-way interactions, 4
   uncoverable (3 forbidden directly, 1 by implication), four rules, one
   of them over three parameters. Phase 3 defines a concrete fixture with
   those statistics (or as close as a hand-written one gets) and records
   its definition; the fixture, not the prose, is then the reference.
   Both engines, strengths 2 and 3, verified by `test/checker.jl` after
   each run.
3. **Repaired cases.** The random problems that crash IPOG or hang GND on
   the prior revision (see issue #51). These have no "before" number;
   record only the "after" so later phases can detect regressions.

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

## Procedure

1. Check out the prior revision (`main` at commit `d46122d`, before
   `release/1.0`) and run fixtures 1 and 2 on the fixtures it handles
   without crashing. Record the table.
2. Check out the Phase 3 branch and run all three fixtures. Record the
   table.
3. Run the same script three times on the CI runner used for the release
   and record the spread. The regression tolerance is set from that
   observed variation (twice the observed spread, rounded up), not
   guessed in advance.
4. Ordinary correctness tests assert completion and coverage only; no
   test asserts machine-dependent seconds. Limit exhaustion and
   progress-guarantee regressions go in the deterministic suite.

The benchmark script lives at `benchmark/run.jl` when Phase 3 lands and
writes a Markdown table that is pasted into the Phase 3 review.
