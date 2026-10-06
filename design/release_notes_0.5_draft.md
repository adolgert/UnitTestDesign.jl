# UnitTestDesign.jl 0.5.0 release notes (draft)

Started in Phase 1 (step 6). Phase 8 fills in the changelog below.

2026-09-27: the release is 0.5.0, not 1.0.0; the maintainer wants to use a
0.x version before calling it 1.0. This file was
`release_notes_1.0_draft.md`, and the release branch is `release/0.5`.

## Dependents check (Phase 1, 2026-09-26)

Question: which Julia packages depend on UnitTestDesign
(UUID `239896fa-e45a-40e8-9993-3c434b0bc450`, registered version 0.4.0),
either at run time (`[deps]`/`[weakdeps]`) or for tests only (`[extras]` +
`[targets].test`, or `test/Project.toml`)?

### Result

- **No registered package depends on UnitTestDesign at run time.** No
  `Deps.toml` or `WeakDeps.toml` in the General registry mentions its UUID.
- **Two registered packages use it for tests only. Both belong to the
  maintainer.**
- **One unregistered third-party repository uses it for tests only.**

| Repository | In General? | How it declares UnitTestDesign | Compat bound | What it calls | Effect of the positional return-type change |
|:--|:--|:--|:--|:--|:--|
| [adolgert/BijectiveHilbert.jl](https://github.com/adolgert/BijectiveHilbert.jl) | Yes (`91e7fc40-…`) | `test/Project.toml` `[deps]` | `"^0.3"` | `for (A, I, C, D, B) in all_pairs(...)` in `test/test_simple2d.jl`, `test/test_hamilton.jl`, `test/test_global_gray.jl` | None for now. The bound already excludes 0.4 and 0.5. Destructuring works on tuple rows once the bound is raised. |
| [adolgert/CompetingClocks.jl](https://github.com/adolgert/CompetingClocks.jl) | Yes (`5bb9b785-…`) | `test/Project.toml` `[deps]` | none | `design = faster ? all_pairs : full_factorial`, then `length`, `eachindex`, `configurations[idx]`, `configuration[1:5]...`, `configuration[6]` in `test/gauntlet/experiments.jl`. The test suite reaches it through `test/gauntlet/test_travel.jl` (`run_experiments(true)`). | With no bound, its next CI run resolves 0.5. Indexing, range slicing, and splatting work on tuples, and `TestCases <: AbstractVector` provides `length`, `eachindex`, and `getindex`, so it should keep working. Verify by running its tests against `release/0.5`. |
| [jwscook/LinearMaxwellVlasov.jl](https://github.com/jwscook/LinearMaxwellVlasov.jl) | No | main `Project.toml` `[extras]` + `[targets].test` | none | `for params ∈ all_pairs(...)`, then `(kz, ω, n, pow, diffbool) = params` in `test/integrals/Parallel.jl`; `for (ωT, kz, n, pow, dFdv) ∈ all_pairs(...)` in `test/integrals/DiracDelta.jl`. `using UnitTestDesign` with no calls found in `test/integrals/Parallel_unittest4.jl` and `test/tensors/Brambilla.jl`. | It will resolve 0.5 because it has no bound. Destructuring works on tuple rows, so it should keep working. |

Other matches that are not package dependents:

- The maintainer's private repositories `adolgert/localnotes` and
  `adolgert/TestDesignTalk` (these have Project/Manifest files and call
  `all_pairs`, `full_factorial`, and `values_excursion`), plus
  `adolgert/JuliaTestDeps`, a research repository that lists UnitTestDesign
  in `test/Project.toml` but has no `using` statement in indexed code. None of
  them is in General.
- Mentions only: `hendri54/hendri54.github.io` (testing notes) and
  `sosiristseng/gensjulia` (devtools list); PkgEval and PackageCompiler logs
  for UnitTestDesign itself (`JuliaCI/NanosoldierReports`,
  `maleadt/packagecompiler_report`); registry mirrors that contain only
  `U/UnitTestDesign/Package.toml` (`hyperpolymath/julia-ecosystem`,
  `codedownio/General`, `barche/TestRegistry`); lists of package names.
  All other search hits were unrelated fuzzy matches (for example
  `UnitTestDesigner` in TypeScript and the R package Chicago).

### Sources and method

1. **JuliaHub package page**:
   <https://juliahub.com/ui/Packages/General/UnitTestDesign> redirects (302) to
   <https://platform.juliahub.com/ui/Packages/General/UnitTestDesign>. The
   fetched page is a JavaScript shell with no content (only a "JuliaHub"
   heading), so its Dependents section could not be read.
2. **JuliaHub package metadata**:
   <https://juliahub.com/docs/General/UnitTestDesign/stable/pkg.json>
   (HTTP 200) reports `"version": "0.4.0"`, `"release_date": "Apr 2025"`, and
   `"reversedeps": []`. JuliaHub takes reverse dependencies from registry
   `[deps]`, so this source does not show test-only use.
3. **General registry, full-text search.** The Pkg server's registry list
   (<https://pkg.julialang.org/registries>, redirected to
   `https://us-east.pkg.julialang.org/registries.conservative`) gave General at tree
   `d9c301067819fbe67759ae9bb9d8f3db98cba734`. I downloaded
   `https://us-east.pkg.julialang.org/registry/23338594-aafe-5451-b93e-139f81909106/d9c301067819fbe67759ae9bb9d8f3db98cba734`
   and ran `grep -r` over every file for the UUID and for the name. The
   registry has 14,415 packages, 14,371 `Deps.toml` files, and 1,808
   `WeakDeps.toml` files. The only matches were `Registry.toml` and
   `U/UnitTestDesign/Package.toml`. The local copy
   `~/.julia/registries/General.tar.gz` (tree
   `cd1b2a6e81ebddaa99743f9971752ccad0b4a080`, 2026-09-23) gave the same
   result. `LinearMaxwellVlasov` is not in `Registry.toml`.
4. **GitHub code search** used the authenticated API
   (`gh api -X GET search/code -f q=...`) because the web page
   <https://github.com/search?q=239896fa-e45a-40e8-9993-3c434b0bc450&type=code>
   requires sign-in and could not be fetched. Queries and totals:
   - `239896fa-e45a-40e8-9993-3c434b0bc450`: 16 results. They were General's
     `Package.toml`, three registry mirrors, this repository, and the
     Project/Manifest files named above. None was a `Deps.toml`.
   - `UnitTestDesign filename:Project.toml`: 9 results, the same set.
   - `using UnitTestDesign`: 58 results. The Julia files outside this repository
     are in BijectiveHilbert (3), CompetingClocks (1), LinearMaxwellVlasov (4),
     localnotes (1), and TestDesignTalk (1).
   - `import UnitTestDesign`: 59 results. None was a Julia import outside this
     repository.
   - `UnitTestDesign language:Julia`: 26 results, the same Julia set.
   - `UnitTestDesign`: 175 results over 2 pages. Nothing new.
5. **Other checks.** <https://juliapackages.com/p/unittestdesign> shows "Used
   By Packages: No packages found." That site says it was last updated two
   years ago, so it may be stale. `adolgert/JuliaTestDeps`
   `data/testusebyname.csv`, a 2025 scan of test dependencies in
   GitHub-hosted registered packages, records `UnitTestDesign,1`.

Limits: GitHub code search covers only GitHub, only default branches, and
only repositories it has indexed. Packages hosted elsewhere or registered
only in private registries would not appear. The registry records `[deps]`
and `[weakdeps]` but not test dependencies.

### Decision: announcement for the positional return-type change

**The changelog is enough. No separate announcement is needed.** No
registered package depends on UnitTestDesign at run time. The two
registered test-only users belong to the maintainer, who can update them
directly. The only third-party user (LinearMaxwellVlasov.jl, unregistered)
only destructures rows in `for` loops. Every call pattern found works on
`TestCases{Tuple{...}}` with tuple rows: iteration with destructuring,
`length`, `eachindex`, integer and range indexing of a row, and splatting.
The change would break code that mutates a row, `push!`es onto the result,
or checks `isa Vector`. The search found no such code. The general Discourse
announcement planned for Phase 8, step 4, is unaffected.

Maintainer follow-ups (not announcements): run the CompetingClocks.jl tests
against `release/0.5` before registering, since it has no compat bound.
BijectiveHilbert.jl's `"^0.3"` bound already lags 0.4, so raise it when
convenient.

---

## 0.5.0 changelog (skeleton; Phase 8 fills in)

0.5.0 is a breaking release. Under Julia's semantic versioning a minor bump
before 1.0 is breaking: a compat bound of `"0.4"` or `"^0.4"` means
`[0.4.0, 0.5.0)`, so packages that declare it are not upgraded to 0.5
automatically and must raise the bound to use it. Packages with no bound
resolve 0.5 on their next update.

### Breaking changes

- Positional calls (`all_pairs(a, b, c)`, `all_triples`, `all_values`,
  `full_factorial`, the excursion functions) return `TestCases{Tuple{...}}`
  instead of `Vector{Vector{Any}}`. Each case is a tuple that keeps domain
  values and their types. TODO: migration note (`collect` gives a plain
  vector; rows are immutable tuples).
- `disallow` removed (not deprecated). Passing it raises the ordinary
  unknown-keyword error. Use `constraints` on a `TestSpace`. TODO: before/after
  example.
- `Counter`, `generate_tuples`, and `Excursion` removed from the public
  surface.
- TODO (Phase 8): confirm any others, such as the `julia = "1.10"` floor.

### Deprecations

Each warns once through `Base.depwarn`. TODO: state the release that removes
them.

| Deprecated | Replacement |
|:--|:--|
| `all_tuples` | `covering` |
| `n_way =` | `strength =` |
| `seeds =` | `must_include =` |
| `wayness =` | `stronger =` |
| `GND(M = ...)` | `GND(candidates = ...)` |

### New API

- TODO (Phase 8): `TestSpace`, constraints (`forbid`/`require`,
  `@forbid`/`@require`), `covering`, `TestCases`, `explain`, `coverage`,
  `missing_interactions`, `report`, `design_sizes`, `excursions`, `Invalid`,
  `Partition`/`realize`, `diagnose`, `github_matrix`. Final list and
  one-line descriptions come from the Phase 8 docs.

### New engines, and the lower bound (solver plan, Phase 3)

Added 2026-10-04 by the solver plan's Phase 3
(`design/20261003_solver_plan.md`, §6). The default engine is still `IPOG()`.

- `Auto(; goal = :balanced, seed = 0, effort = 1)`, an engine that chooses.
  `goal = :fast` is IPOG; `:balanced` keeps the smaller of IPOG's design and
  the catalog's array, and is never larger than IPOG where it builds both
  (above 100,000 combinations it may build the catalog's array alone, which
  was never larger on the package's benchmarks, though that is measured,
  not guaranteed); `:compact` then removes rows with the reducer. The
  result's `record.ordinary.chose` says what it ran, and
  `record.ordinary.starts` what each start gave. Its choice may change
  between releases (contract §9.8).
- `Construction()`, algebraic covering arrays from a catalog (orthogonal
  arrays, cover starters, products, the LFSR array and recursions), for
  spaces whose parameters all have the same number of values or that have
  `strength + 1` parameters; it seeds IPOG under rules. It refuses other
  spaces with the reason.
- `Compact(inner; seed = 0, effort = 1)`, a row reducer around any engine:
  fewer cases for expensive tests, seeded, budgets in steps.
- `recommend(space; …)` says what `Auto` would run, why, and how many cases
  each goal can give where that is known without running; it returns a
  `Recommendation`.
- `design_sizes(space; engine = [IPOG(), Auto(goal = :compact)])` compares
  engines, one row per engine per strength, and shows an engine that
  doesn't cover a request as that row's status. `DesignSizes` gains an
  `engines` field, the engines' constructor calls, and each of its rows an
  `engine` field (`nothing` for an excursion or a full factorial).
- Every covering result states a proven lower bound beside its count, and
  says "minimal" when the count meets it: the summary line reads
  `5 cases (lower bound 4) · …` or `9 cases (minimal) · …`, and `report`
  prints a `size:` line with the proof. `TestCases` and `Report` gain a
  `record` field holding the bound, its proof and whether the count meets
  it, whether the engine is randomized, the engine's configuration (`engine`:
  each engine's name, constructor call, seed and settings, nested for
  `Compact`'s inner engine and `Auto`'s candidates), and the stages that ran
  (`ordinary`: what `Auto` chose, the catalog's array, the reducer's run;
  `negative`: which engine covered each `Invalid` value's negative rows).
  The bound, the proof and "minimal" are the package's own, never an
  engine's. `report`'s seed line names the constructor call that repeats
  the cases, such as `Compact(GND(seed = 17); seed = 3, effort = 2)`.
  Contract §8.4 now allows "minimal" when a count equals a proven bound, and
  §8.7 defines the bound.
- The error for an `engine` that isn't one names covering engines generally
  ("a covering engine such as IPOG(), Construction(), Compact(IPOG()) or
  Auto()"), and an engine that refuses a request suggests `IPOG()` or
  `Auto()`.

### IPOG's core (solver plan, Phase 4)

Added 2026-10-06 by the solver plan's Phase 4
(`design/20261003_solver_plan.md`, §5.5).

- `IPOG()` has one engine for every request, in place of 0.4's classic
  algorithm and the general one 0.5 added for rules, must-include rows and
  `stronger` groups. It finds the best value for each case by lookup
  (Kleine and Simos's FIPOG) instead of scanning every combination, and
  holds one step's combinations at a time.
- Its speed depends on the rules. Without rules, or with a few, a whole call
  is about 10 to 95 times faster where the engine it replaced took more than
  a second (8 parameters of 64 values at strength 2: 1.7 s to 0.045 s;
  strength 6 on 20 three-valued parameters: 5.6 minutes to 5.7 s). On
  heavily constrained models it can be slower and take more memory, because
  it builds four designs and each asks the feasibility search. Over the
  benchmark's constrained models at strength 2, whole calls took longer at
  68 of 907 points, up to about three times as long, and the engine alone
  took up to about five times as long, the most with rules that read the
  whole case. Peak memory rose on some: 5.3 to 8.1 GiB on the largest cart
  model at strength 2, about 630 to 1,250 MiB on a ct-comp model at strength
  3 (the solver plan's quiet re-measurement). Its Phase 5, the feasibility
  memo by component, is meant to reduce this cost.
- Its cases change. It runs four members of the IPOG family, two tie-break
  rules by two orders of vertical growth, and keeps the design with the
  fewest cases. Over the package's benchmark grid, against the engine it
  replaced, that has as many cases or fewer at 96.7% of 1,826 points and 2%
  fewer in total; at about 3% of the points it has more, usually by one to
  four cases, by up to about 9%, and by 160 (5.6%) for ten 4-valued
  parameters at strength 5 (3,030 where the engine it replaced gave
  2,870). A rule that excludes nothing no longer changes the design. The
  result's `record.ordinary.member` names the member kept.
- A call succeeds only when `feasibility_limit` is enough for each design
  `IPOG()` builds, so a call can need a larger limit than before: of 150
  random constrained problems, tried at limits that are powers of two, one
  needed 16 where the engine it replaced needed 4. A larger limit still
  never changes the cases of a call that succeeded (contract §3.8).
- `Construction()`'s seeded path and `Auto` start from the same engine, so
  their designs change with it.

### Fixed

- Constraint handling: implicit constraints crashed IPOG and hung GND.
  Closes [#51](https://github.com/adolgert/UnitTestDesign.jl/issues/51).
  TODO (Phase 8): describe the fix and the guarantee.
