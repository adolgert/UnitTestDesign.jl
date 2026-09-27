# Phase 5 review: measure and explain

Date: 2026-09-27. Branch `feature/phase5-measure`, stacked on
`feature/phase4-interface` (PR #55). Plan: Phase 5.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1 | `coverage(cases, space; strength, stronger, limits)` and `coverage(cases::TestCases)`; `Coverage` with ordinary and negative parts, per-group breakdown, rejected rows, unknown targets; `iscomplete` | `src/measure.jl` |
| 2 | `missing_interactions`, throwing `ResourceLimitError` on unresolved targets | `src/measure.jl` |
| 3 | `report(cases)` → `Report`: guarantee line, excluded list, bonus at strength + 1, prefix curve, seed | `src/report.jl` |
| 4 | `design_sizes(space; strengths, distances)` → `DesignSizes` table | `src/report.jl` |
| 5 | Top-up and extend recipes tested | `test/test_measure.jl` |
| 6 | Tests against the checker on fixtures and random problems; 3 Phase 5 fixture lines flipped | `test/test_measure.jl`, `test/test_report.jl` |
| — | `src/coverage_set.jl` deleted; streamed recount for unconstrained requests (fixture 1 IPOG 4.0 s → 3.3 s) | `src/request.jl` |

Exports added: `coverage`, `Coverage`, `iscomplete`, `missing_interactions`,
`report`, `Report`, `design_sizes`, `DesignSizes`.

## Independent checks

- `coverage` of hand-written rows agrees with the checker on every fixture
  (covered, feasible, missing set, excluded statuses and rules, rejected
  rows); `coverage(all_pairs(space))` is complete on every fixture and on
  100 random problems at strengths 2 and 3 with both engines, with the
  counts equal to the generation bookkeeping.
- `report` agrees with the checker on 50 random problems: bonus at
  strength 3 equals the checker's triple coverage of the same rows; the
  prefix curve is nondecreasing and matches the checker at 1, n/2, and n.
- The negative part agrees with the checker, including two invalid
  parameters and `stronger` groups (generation of negative rows is Phase 6).
- Fable's `design_sizes` example reproduces exactly: 81 / 3 / 10 / 31 / 9 / 33.
- No percentage or "complete" is ever printed with an unresolved target.

## Transcript of the acceptance examples

```
# coverage of a hand-written suite
covers 6 of 11 feasible pairs, 5 missing: (mode = :exact, solver = :none), (mode = :exact, solver = :qr), (mode = :fast, tol = 1.0e-6), (solver = :none, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)
excluded: 3 pairs forbidden, 2 impossible under the constraints
1 duplicate row counted once

# missing_interactions
NamedTuple[(mode = :exact, solver = :none), (mode = :exact, solver = :qr), (mode = :fast, tol = 1.0e-6), (solver = :none, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)]
# top-up
covers 11 of 11 feasible pairs
excluded: 3 pairs forbidden, 2 impossible under the constraints
1 duplicate row counted once

# report
5 cases cover all 11 feasible pairs of a 12-combination space (3 pairs forbidden, 2 impossible under the constraints)
excluded:
  (mode = :fast, solver = :lu): forbidden by rule 1 (@require(mode == :exact || solver == :none))
  (mode = :fast, solver = :qr): forbidden by rule 1 (@require(mode == :exact || solver == :none))
  (mode = :exact, tol = 0.001): forbidden by rule 2 (exact mode needs a tight tolerance)
  (solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
  (solver = :qr, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
bonus: 5 of 5 feasible triples covered
prefix curve:
  first 1 of 5 cover 27% (3 of 11)
  first 2 of 5 cover 45% (5 of 11)
  first 3 of 5 cover 63% (7 of 11)
  first 4 of 5 cover 90% (10 of 11)
  first 5 of 5 cover 100% (11 of 11)
seed: none (IPOG uses no randomness)

# design_sizes
strategy        cases   share  pairs  triples
full_factorial      5  100.0%  11/11      5/5  valid 5 of 12
covering(1)         3   60.0%   8/11      3/5
covering(2)         5  100.0%  11/11      5/5
covering(3)         5  100.0%  11/11      5/5
excursions(1)       2   40.0%   5/11      2/5
excursions(2)       3   60.0%   7/11      3/5
case counts are the rows each strategy produced with IPOG, not lower bounds

# Fable's example
strategy        cases   share  pairs  triples
full_factorial     81  100.0%  54/54  108/108  valid 81 of 81
covering(1)         3    3.7%  18/54   12/108
covering(2)        10   12.3%  54/54   39/108
covering(3)        31   38.3%  54/54  108/108
excursions(1)       9   11.1%  30/54   28/108
excursions(2)      33   40.7%  54/54   76/108
case counts are the rows each strategy produced with IPOG, not lower bounds

# extend pairs to triples
true 5 of 5
# under a limit
covers 28 of at least 28 feasible pairs; 420 pairs unresolved (feasibility_limit = 1); no exact percentage
false
ResourceLimitError: resolving 420 targets for missing_interactions (coverage with the same arguments lists the 0 missing known so far and the 420 unresolved) re
ArgumentError: coverage(cases) measures at the result's strength, but an excursion has none; pass the strength to measure, such as coverage(cases; strength = 2) (contract §1.12)
2 cases within distance 1 of (mode = :fast, solver = :none, tol = 0.001); 3 rows dropped; never appear: mode = :exact, solver = :lu, solver = :qr; not a covering design; measured at strength 2, the cases cover 5 of 11 feasible pairs (3 pairs forbidden, 2 impossible under the constraints); 6 pairs missing
```

Timings on `bench12`: `coverage` of the IPOG design 0.13 ms (strength 2),
0.77 ms (strength 3); `report` 4 ms / 22 ms; `design_sizes` 1.4 s;
`coverage` of the 207,360-row full factorial 0.56 s.

## Decisions for review

1. **`missing_interactions` returns ordinary then negative missing
   targets**, so an empty list never hides a missing negative target.
2. **`coverage` does not go through `Request`** (which refuses wrappers);
   it uses the same target enumeration (tested equal) and so already
   measures `Partition` spaces over names and negative rows.
3. **Bonus coverage** is the base group at strength + 1 only, without
   `stronger` groups; "not applicable" only when strength + 1 exceeds the
   parameter count; a space with no feasible targets there reports "0 of 0".
4. **`report`'s `excluded`** is what generation recorded for covering
   results and what the report measured for excursions and full
   factorials, which record none. Under a tight limit the recorded
   exclusions (proven at generation) still print while the guarantee
   says this measurement could not resolve them.
5. **`design_sizes`** marks an excursion whose default base breaks a rule
   as `:invalid_base` rather than throwing (`bench12`'s default base
   does), takes a `from` keyword, and prints "case counts are the rows
   each strategy produced with IPOG, not lower bounds" (§8.3).
6. **Percentages round down** (2 of 3 prints 66%), so 100% appears only
   when everything is covered.
7. **`Report` is plain data except `coverage.space`**, which holds the
   rule predicates; full serialization must skip the space.
8. **On a `TestCases`, passing `strength` explicitly drops the result's
   `stronger` groups** unless `stronger` is also passed.
9. **`iscomplete`** is exported though not in the §13.1 table; rejected
   rows do not affect it (§1.16).
10. The old index-space coverage helpers the engine tests used moved into
    a test snippet in `test/runtests.jl`.

## Pending tests after this phase (5)

| Phase | Count | What |
|:--|--:|:--|
| 6 | 5 | negative generation, partitions kept, negative must-include |
