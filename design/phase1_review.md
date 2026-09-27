# Phase 1 review: specification, checker, and scaffolding

Date: 2026-09-26. Branch `feature/one-oh`, PR into `release/1.0`.
Plan: `design/20260926_implementation_plan.md`, Phase 1.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1 | `release/1.0` cut from `main` at `d46122d`; issue #51 opened | GitHub |
| 2 | The contract, 168 numbered clauses in 14 sections | `docs/src/dev/contract.md`, linked from `docs/make.jl` |
| 3 | Independent checker (value space, no code shared with `src/`) | `test/checker.jl`, verified by `test/test_checker.jl` |
| 4 | Random problem generator and gate; fixture inventory | `test/random_problems.jl`, `test/test_random_problems.jl`, `test/fixtures.jl`, `test/test_fixtures.jl` |
| 5 | `1.0.0-DEV`, `julia = "1.10"`, CI matrix `1.10 / 1.11 / 1`, `.gitignore`, design files moved | `Project.toml`, `.github/workflows/ci.yml`, `design/` |
| 6 | Dependents check and changelog skeleton | `design/release_notes_1.0_draft.md` |
| gate | Benchmark fixtures and procedure for Phase 3 | `design/benchmark_procedure.md` |

## How to run

```
julia --project -e 'using Pkg; Pkg.test()'                       # full suite, ~4 min
julia --project=test -e 'using TestItemRunner; TestItemRunner.run_tests(pwd(); filter = ti -> occursin("checker", ti.filename))'
```

Replace `"checker"` with `"fixtures"` or `"random_problems"` for the other
groups. The `test/` project needs a one-time
`Pkg.develop(path="."); Pkg.instantiate()` (then revert the `[sources]`
entry Julia 1.13 writes into `test/Project.toml`).

## Checker verification (step 3)

- 13 test items, 221 assertions, against hand-enumerated fixtures.
- Fable's solver example by hand: 5 valid rows of 12, 11 feasible pairs, 3
  directly forbidden `(fast, lu)`, `(fast, qr)`, `(exact, 1e-3)`, 2
  implied `(lu, 1e-3)`, `(qr, 1e-3)`. Matches the plan.
- Astra's `A == B`, `B == C`: `(A = 1, C = 2)` is implied; Opus's
  os/gpu/driver: `(windows, gpu)` is implied.
- The tests were shown to fail when the checker was broken four ways
  (rules applied to negative rows; type dropped from identity; wrappers
  passed to rules; any rule counted as a direct forbid).

## Random gate (step 4), multiplier 1.0, fixed seeds, 500 problems per strength

| | Pairwise | Three-way |
|:--|--:|--:|
| Problems with an implied infeasible target | 188 | 190 |
| IPOG `BoundsError` (the one expected failure) | 201 | 194 |
| ... on problems with implied targets | 188 | 190 |
| ... greedy dead ends without implied targets | 13 | 4 |
| IPOG designs returned, all checker-complete | 299 | 306 |
| GND skipped (would hang; pending Phase 3) | 188 | 190 |
| GND run, all checker-complete | 312 | 310 |

The IPOG crash rate (about 40%) is far above Opus's 8.6% / 13.8%. The
generator's conditional `!=` and `<` rules force values, and forced values
chain into implied exclusions in about a third of draws; 10% of draws also
plant a two-rule chain deliberately. The shape (parameters, values, rules,
scope, share of `!=`/`<`) matches Opus's. **Review question:** keep the
harder distribution, or weaken the rules so GND is exercised on more
problems before Phase 3? (My recommendation: keep it. Phase 3 must pass
all of it either way, and the harder problems are the ones that matter.)

Expected-failure policy: only `BoundsError` at index 0 from IPOG is
recorded, with `@test_broken`, so Phase 3 flips it to an unexpected pass.
A ceiling on the crash count (50% at 500 problems, widened for small runs)
catches a regression in the problems IPOG handles today. GND is skipped
exactly when the checker finds an implied target, recorded with
`@test_skip`; on every other problem it must return a checker-complete
design, and its attempt-cap error is an ordinary failure. A watchdog on
`disallow` calls turns an unexpected hang into a failure. Nothing else is
masked. The 13 + 4 greedy dead ends (IPOG crashes with no implied target)
are frozen as four explicit fixtures so Phase 3 must handle them too.

The multiplier can be forced for a full CI run with the environment
variable `UNITTESTDESIGN_TEST_LONGER=1.0`, which wins over the CI default
of 0.2 (as does an explicit `--longer`).

## Pending tests and their activation phase

All in `test/test_fixtures.jl` as `@test_skip` with a `pending: Phase N`
comment, plus the two gate lines in `test/test_random_problems.jl`.

| Phase | Count | What |
|:--|--:|:--|
| 2 | 12 | `explain`/classify for Astra, Fable, Opus; `completable` on the unsatisfiable component; witness combination; whole-case implication; `unknown` at limit 1; mixed-type storage; `1` beside `Invalid(1)`; rules see partition names; five constructions rejected |
| 3 | 14 + 2 gate | generation for the three examples (closes #51), empty design for the unsatisfiable space, witness space, whole-case, `ResourceLimitError` at limit 1, overlapping groups, the four greedy dead ends, `bench12` at strengths 2 and 3; IPOG `@test_broken` and GND `@test_skip` at both strengths |
| 4 | 5 | mixed value types preserved in results; three `must_include` cases; `stronger` keyword |
| 5 | 3 | Fable coverage/report; coverage under a limit; identity-keyed coverage |
| 6 | 5 | negative targets covered separately; partial row with `Invalid` completed as negative; partition wrappers kept; a space with no valid ordinary row accepts a negative must-include and rejects an ordinary one |

Only the IPOG `BoundsError` is an expected failure (`@test_broken`). The
legacy `BoundsError` on the dead-end and `bench12` fixtures is asserted
with `@test_throws` today because it is the documented defect; Phase 3
replaces those lines with completeness checks.

## Dependents (step 6)

No registered package depends on UnitTestDesign at run time (General
registry `Deps.toml`/`WeakDeps.toml` searched by UUID; JuliaHub
`reversedeps: []`). Test-only users: BijectiveHilbert.jl and
CompetingClocks.jl (both the maintainer's), and the unregistered
LinearMaxwellVlasov.jl. Every use destructures, indexes, or splats rows,
which works on tuple rows. Decision: the changelog is enough for the
positional return-type change. Follow-ups: run CompetingClocks' tests
against `release/1.0` before registering (no compat bound); raise
BijectiveHilbert's `^0.3` bound.

## Decisions made where the plan was silent (for review)

From the contract (clause in brackets); say at review if you want another:

1. `feasibility_limit` defaults to 1,000,000 nodes, one budget per query
   shared across connected components, no run-wide cap [3.3, 3.4].
   `explanation_limit` is separate, same default, per excluded target [3.13].
2. Two successful runs differing only in `feasibility_limit` return
   identical results [3.8].
3. The error type is `ResourceLimitError`, exported; the full-factorial
   size guard throws it too [3.7, 7.3].
4. "Direct" means a rule whose scope lies inside the target's parameters
   forbids it; everything else infeasible is "implied" [1.4].
5. `coverage` throws on malformed rows (incomplete, unknown name,
   out-of-domain value) but accepts, lists, and ignores rule-violating
   rows [1.13, 1.14]. The checker lists malformed rows as rejected instead
   of throwing; the Phase 2 adapter should keep that difference in mind.
6. A partition may be written as the wrapper or by its name anywhere a
   user supplies a value [2.11]; `rng` is a required keyword of `realize`;
   `realize(cases)` returns a plain `Vector` [4.7, 4.9].
7. Domains must be `AbstractVector` or `Tuple`; `missing` is an ordinary
   value like `nothing`; inside `@forbid`/`@require`, `nothing` and
   `missing` denote the values, so parameters cannot have those names
   [2.6, 2.9, 12.7].
8. Row order in a result: must-include, then ordinary, then negative [5.12].
9. GND: a caller-supplied `rng` is copied at the start of each call and
   never advanced, and the recorded seed is then `nothing` [9.6].
10. Tabulation happens at `TestSpace` construction, in rule order, with a
    `tabulation_limit` keyword (default 10^5) and one warning per rule
    [12.18, 12.19].
11. The plan contradicts itself on `values_excursion`/`pairs_excursion`/
    `triples_excursion`: the decisions table calls them deprecated
    aliases that warn, Phase 4 step 5 calls them thin aliases (no
    warning). The contract follows the decisions table (deprecated) [13.1].
12. A space with no valid ordinary row returns an empty ordinary design,
    not an error; negative rows can still exist there and are unaffected
    [1.24].
13. Strength must be at least 1; a group listed twice acts as its highest
    strength; output and docs never call a count "minimal", "optimal", or
    "fewest" [11.1, 11.8, 8.4].

## Benchmark plan for Phase 3

See `design/benchmark_procedure.md`. Fable's 12-parameter example
survives only as statistics, but its arities are recoverable from them
(product 331776 and 590 pairs give 4,4,4,4,3,3,3,3,2,2,2,2), so a
replacement fixture `bench12` is frozen in `test/fixtures.jl` whose
checker statistics match the recorded ones exactly: 207360 valid rows, 3
directly forbidden pairs, 1 implied pair `(p1 = 2, p2 = 2)`. Legacy
baseline on it: IPOG throws `BoundsError` at both strengths; GND does not
return within 20 million rule calls.

## Review round 1 (2026-09-26)

Six suggestions received; all accepted and applied:

1. GND attempt-cap errors are ordinary failures; IPOG crashes have a
   ceiling as well as the `@test_broken`.
2. Contract §1.24 restricted to ordinary rows; fixture
   `empty_ordinary_negative_seed` added.
3. "Implied" now means "infeasible with no direct rule match"; a single
   wider-scope rule can cause it (checker docs and contract §1.4).
4. Contract §2.3 keeps identity absolute for stored choices, keys, and
   returned cases, and names the permitted output projections (partition
   name in rules, textual rendering, JSON encoding).
5. Harder random distribution kept; dead ends frozen as fixtures;
   `UNITTESTDESIGN_TEST_LONGER` override added.
6. `bench12` frozen with its legacy baseline.
