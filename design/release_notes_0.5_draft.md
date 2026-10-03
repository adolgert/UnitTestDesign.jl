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

### Fixed

- Constraint handling: implicit constraints crashed IPOG and hung GND.
  Closes [#51](https://github.com/adolgert/UnitTestDesign.jl/issues/51).
  TODO (Phase 8): describe the fix and the guarantee.
