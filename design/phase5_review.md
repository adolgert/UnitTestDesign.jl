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

## Review round 1

Date: 2026-09-27. Five findings, and the release renamed from 1.0.0 to
0.5.0.

### 1. Excursion guarantee with must-include rows outside the radius

`_guarantee` (`src/report.jl`) claimed every row of an excursion was within
the distance, so `excursions(space; distance = 0, must_include = [far])`
reported "2 cases within distance 0" although `far` differs from the base in
three parameters. Must-include rows are exempt (§7.5, §7.9), and the
guarantee now counts them apart:

```
1 must-include row kept first, then 1 case within distance 0 of (mode = :fast, solver = :none, tol = 0.001); never appears: solver = :qr; not a covering design; measured at strength 2, the cases cover 6 of 11 feasible pairs (3 pairs forbidden, 2 impossible under the constraints); 5 pairs missing
```

Without must-include rows the wording is unchanged ("3 cases within
distance 1 of …"); covering and full-factorial guarantees keep "N
must-include rows kept first" in their tail. When a must-include row is the
base, it is not repeated (§7.11) and the line reads "1 must-include row kept
first, then 0 cases within distance 0 of …". The regression test checks the
line, `n_cases`, and that `report`'s counts equal `coverage(ex; strength =
2)` and the checker's (6 of 11, prefix 3 then 6).

### 2. Reporting uses its own exclusions

`report` showed generation's recorded exclusions for covering results, so a
design generated with `explanation_limit = 1` still printed "explanation
unresolved" after a report with the default budget, while the guarantee
line (from the fresh measurement) disagreed with the list. Policy, now in
the `report` docstring and contract §1.23: **the report is the
verification.** `Report.excluded` is the fresh measurement's
`coverage.ordinary.excluded`, classified and explained with the report's
own `feasibility_limit` and `explanation_limit`. Generation's exclusions are
a fallback used only for targets the fresh measurement left unknown; they
go in a new field, `Report.recorded`, and print with the suffix "(recorded
at generation)".

- Generated with `explanation_limit = 1`, reported with the default: both
  implied exclusions are `:verified`, and the printed report is identical to
  the report of a design generated with the default.
- Generated with the default, reported with `explanation_limit = 1`: the
  report shows its own unresolved explanations ("(explanation unresolved:
  explanation_limit = 1 reached)", "2 with an unresolved explanation" in the
  guarantee), not generation's verified ones. Raising the report's budget
  is the way to see verified explanations.
- `limit_exhaustion` reported with `feasibility_limit = 1`: `excluded` is
  empty, `recorded` holds generation's 420 exclusions, each printed with
  "(recorded at generation)".

This supersedes decision 4 above.

### 3. `coverage(cases::TestCases; strength)` keeps the stored groups

Passing `strength` used to drop `cases.stronger` even at the stored
strength: for the solver space's strength-2 design with `(mode, solver,
tol) => 3`, `coverage(cases; strength = 2)` measured 16 targets (11
feasible, 5 excluded) where `coverage(cases)` measures 28 (16 feasible, 12
excluded); the review's probe saw 32 vs 24 on its own space. Both now
measure the 28. The rule, in the `coverage` docstring
and contract §1.12: an explicit `strength` replaces the stored strength and
keeps `cases.stronger` unless `stronger` is passed too; a stored group whose
strength is below the requested strength is an `ArgumentError`:

```
stronger group (mode, solver) => 2 is below the requested strength 3; pass stronger = [] to drop it (contract §1.12)
```

An explicit `stronger` replaces the stored groups and `stronger = []` drops
them. A stored group at the requested strength adds nothing (§11.7).
`missing_interactions(cases::TestCases; strength)` goes through the same
path. `report` takes no `strength`, so it is unchanged. Tests cover keeping
(same counts and groups as `coverage(cases)`), the error on a named and a
positional result, `stronger = []`, and an explicit `stronger`. This
supersedes decision 8.

### 4. `plain`: a representation with no executable state

`Report` keeps rule predicates through `coverage.space`. New unexported
`UnitTestDesign.plain(::Report)`, `plain(::Coverage)`,
`plain(::DesignSizes)` return nested `NamedTuple`s and `Vector`s whose
leaves are `Int`, `Float64`, `String`, `Symbol`, `Bool` or `nothing`. The
space becomes its names, each domain's values as `repr`, and its rule
labels; targets and rows keep values of those types and use `repr` for
others (`"Invalid(0)"`, `"Partition(:tiny)"`, `"'x'"`); positional rows are
named by the space; `stronger` groups become `(names, strength)`; an
exclusion's `limit` becomes `(keyword, value)`; a `DesignSizes` total above
`typemax(Int)` becomes a string of digits. Sample, from
`plain(report(all_pairs(space)))` on the solver space:

```
keys: (:guarantee, :strategy, :n_cases, :strength, :coverage, :excluded, :recorded, :bonus, :prefix, :seed, :engine, :n_must_include)
coverage.space: (names = [:mode, :solver, :tol], domains = [[":fast", ":exact"], [":none", ":lu", ":qr"], ["0.001", "1.0e-6"]], rules = ["@require(mode == :exact || solver == :none)", "exact mode needs a tight tolerance"])
excluded[4]: (target = (solver = :lu, tol = 0.001), status = :implied, rules = [1, 2], labels = ["@require(mode == :exact || solver == :none)", "exact mode needs a tight tolerance"], minimal = :verified, limit = nothing)
```

The `Report` docstring now says its fields are plain data except
`coverage.space`, that `plain(report)` has no executable state, and that
Phase 6's JSON support will use it (this replaces decision 7). The shallow
field-type test is replaced by a round trip, `eval(Meta.parse(repr(x))) ==
x`, on five reports (covering, excursion with a must-include row, stronger
groups under `explanation_limit = 1`, `limit_exhaustion` under
`feasibility_limit = 1`, positional), a hand-written `Coverage` with a
rejected tuple row, a space with `Invalid`, `Partition`, `Char` and `Int32`
values, and three `DesignSizes`, with a recursive check that no value is a
`Function`, `TestSpace`, `Constraint` or `RuleTable`.

### 5. Executable documentation examples

The `report` example said bonus 3 of 5 (it is 5 of 5) and the
`design_sizes` example said 9 pairwise cases and 9/54 at strength 1 (they
are 10 and 18/54). Seven examples are now `jldoctest` blocks, with output
pasted from running them:

| Docstring | Example |
|:--|:--|
| `report` (`src/report.jl`) | solver space, full report |
| `design_sizes` (`src/report.jl`) | Fable's example, full table |
| `coverage` (`src/measure.jl`) | hand-written rows, top-up, extend to triples |
| `Coverage` (`src/measure.jl`) | a duplicate and a rule-breaking row |
| `missing_interactions` (`src/measure.jl`) | hand-written rows |
| `isallowed` (`src/explain.jl`) | `true`, `false` |
| `explain` (`src/explain.jl`) | infeasible and completable |

Each is self-contained (`setup = :(using UnitTestDesign)`), since Documenter
gives each docstring a fresh sandbox. `doctest(UnitTestDesign; manual =
false)` passes from a scratch copy of the docs environment (Documenter
0.25.5, `Pkg.develop(path = repo)`; `docs/Manifest.toml` untouched); a
deliberately wrong expected output in each of the three files made it fail,
so all seven run. Left as `julia` blocks, being illustrative: the
`covering`, `all_values`, `all_pairs`, `all_triples`, `excursions`,
`full_factorial` and `TestSpace` examples (their count comments, 3, 5, 12
and 9 rows, were checked and are right) and the `TestCases` CSV recipe. The
output-only blocks in the `Exclusion`, `TestCases` and `Coverage` (limit)
docstrings were checked against the current output; the abbreviated ones
stay illustrative.

### Version: 0.5.0, not 1.0.0

The maintainer wants a 0.x release before calling anything 1.0.
`Project.toml` is `0.5.0-DEV`. "1.0" meaning this release became "0.5" in
`docs/src/dev/contract.md` (intro, §0.2, §13.1, §14.1 and its table),
`docs/src/man/guide.md`, `docs/src/man/examples.md`, the first-line
comments of `src/interface.jl`, `test/test_interface.jl` and
`test/checker.jl`; `README.md` and `docs/src/index.md` name no release
(their `1.0` is a domain value). `design/release_notes_1.0_draft.md` is now
`design/release_notes_0.5_draft.md` (`git mv`), titled 0.5.0, with a
"0.5.0 changelog" that notes a 0.x minor bump is breaking under Julia's
semver, so `"0.4"`/`"^0.4"` users are not upgraded automatically. The
implementation plan has a dated note under its title, "Phase 8: Release
0.5", `version = "0.5.0"`, and `release/0.5`; `design/benchmark_procedure.md`
names `release/0.5`. The phase reviews and `benchmark_results_phase3.md` are
historical and keep `release/1.0`. No deprecation message promises removal
in a version (they say "X is deprecated; use Y"); contract §13.2 says "the
next breaking release".

### Suite

`julia --project -e 'using Pkg; Pkg.test()'`: 277,525 passed, 5 broken
(the Phase 6 pending tests above), 0 failed, 0 errored, 6 min 21 s. Aqua
(`test_static.jl`, 11 checks) passes. The report and measure items alone:
1,754 passed.
