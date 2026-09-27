# Phase 4 review: the public interface and the result type

Date: 2026-09-27. Branch `feature/phase4-interface`, stacked on
`feature/phase3-engines` (PR #54). Plan: Phase 4.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1 | `TestCases{T} <: AbstractVector{T}`, `Exclusion` | `src/testcases.jl` |
| 2 | `covering`, `all_values`/`all_pairs`/`all_triples` over a `TestSpace`, a `NamedTuple`, pairs, or positional vectors; `constraints =` convenience; `feasibility_limit`/`explanation_limit` on every entry point | `src/interface.jl` (replaces `factorial_interface.jl`) |
| 3 | `must_include`: partial rows, an existing `TestCases`, positional tuples; first, in order, duplicates kept | `src/interface.jl`, `src/request.jl` |
| 4 | `stronger` validated, caller's vector untouched; `wayness` translated with a warning | same |
| 5 | `excursions(space; from, distance, must_include)`, `full_factorial(space; limit)`; `*_excursion` deprecated aliases | same |
| 6 | `show`: summary line, excluded line, aligned table truncated like a `DataFrame`, no search at display time | `src/testcases.jl` |
| 7 | Tables: `DataFrame(cases)` and `CSV.write` tested for named results; positional recipe documented | `test/test_testcases.jl` |
| 8 | Deprecations via `Base.depwarn`: `all_tuples`, `n_way`, `seeds`, `wayness`, `*_excursion`, `GND(M=)`; `Excursion`, `Counter`, `generate_tuples` removed; `disallow` is a `MethodError` | `src/interface.jl`, `src/engines.jl` |
| 9 | Existing tests rewritten; 5 Phase 4 fixture lines flipped; Aqua green | `test/test_interface.jl`, `test_excursions.jl`, `test_full_factorial.jl`, `nonfunctional.jl` |
| CI | Matrix is Julia 1.10 (LTS), 1.13, and latest, on ubuntu; 1.13 on macOS and Windows | `.github/workflows/ci.yml`; plan text updated |

## Transcript of the target screen

```
5 cases · strength 2 · IPOG · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible under the constraints; see report(cases)
    mode    solver  tol
 1  :exact  :qr     1.0e-6
 2  :exact  :lu     1.0e-6
 3  :exact  :none   1.0e-6
 4  :fast   :none   0.001
 5  :fast   :none   1.0e-6

infeasible: no valid case contains (solver = :lu, tol = 0.001); rules 1 and 2 together exclude it (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
5 cases (2 must-include) · strength 2 · IPOG · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible under the constraints; see report(cases)
    mode    solver  tol
 1  :fast   :none   0.001
 2  :exact  :qr     1.0e-6
 3  :exact  :none   1.0e-6
 4  :exact  :lu     1.0e-6
 5  :fast   :none   1.0e-6

6 cases · strength 2 · IPOG · 3 parameters · 12 combinations
6 cases · strength 2 · IPOG · 3 parameters · 12 combinations
    p1  p2   p3
 1  1   "a"  1.0
 2  1   "b"  2.0
 3  2   "a"  2.0
 4  2   "b"  1.0
 5  3   "a"  1.0
 6  3   "b"  2.0

8 cases · strength 2, 3 within (a, b, c) · IPOG · 4 parameters · 16 combinations
    a  b  c  d
 1  2  2  1  1
 2  1  2  2  2
 3  2  1  2  1
 4  1  1  1  2
 5  2  2  2  2
 6  1  2  1  1
 7  1  1  2  1
 8  2  1  1  2

2 cases · excursion, distance 1 from (mode = :fast, solver = :none, tol = 0.001) · 3 parameters · 12 combinations, 3 rows dropped
    mode   solver  tol
 1  :fast  :none   0.001
 2  :fast  :none   1.0e-6

5 cases · full factorial · 3 parameters · 12 combinations, 5 valid
    mode    solver  tol
 1  :fast   :none   0.001
 2  :fast   :none   1.0e-6
 3  :exact  :none   1.0e-6
 4  :exact  :lu     1.0e-6
 5  :exact  :qr     1.0e-6

5 cases · strength 2 · GND seed 3 · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible under the constraints; see report(cases)
    mode    solver  tol
 1  :exact  :none   1.0e-6
 2  :fast   :none   0.001
 3  :exact  :qr     1.0e-6
 4  :exact  :lu     1.0e-6
 5  :fast   :none   1.0e-6

Exclusion[(mode = :fast, solver = :lu): forbidden by rule 1 (@require(mode == :exact || solver == :none)), (mode = :fast, solver = :qr): forbidden by rule 1 (@require(mode == :exact || solver == :none)), (mode = :exact, tol = 0.001): forbidden by rule 2 (exact mode needs a tight tolerance), (solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance), (solver = :qr, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)]
5×3 DataFrame
 Row │ mode    solver  tol
     │ Symbol  Symbol  Float64
─────┼─────────────────────────
   1 │ exact   qr       1.0e-6
   2 │ exact   lu       1.0e-6
   3 │ exact   none     1.0e-6
   4 │ fast    none     0.001
   5 │ fast    none     1.0e-6
┌ Warning: all_tuples is deprecated; use covering, which takes the same inputs, with `strength` for `n_way`
│   caller = top-level scope at phase4_demo2.jl:10
└ @ Core /private/tmp/claude-501/-Users-adolgert-dev-UnitTestDesign-jl/6692e0b5-629d-427b-b70e-4d9f0abeae19/scratchpad/phase4_demo2.jl:10
4
ArgumentError: constraints belong to the space: build TestSpace(...; constraints) instead (contract §12.12)
MethodError
ArgumentError: must_include row 1, (mode = :fast, solver = :lu, tol = 1.0e-6), breaks rule 1 (@require(mode == :exact || solver == :none)) (contract §10.3)
ArgumentError: must_include row 1: `sovler` is not a parameter of this space; the parameters are mode, solver, tol
```

(The `DataFrame` and deprecation lines ran in the test environment, which
has DataFrames; the demo's own environment does not.)

## Independent checks

- Every input form of `covering`/`all_pairs` gives a design the oracle
  accepts; heterogeneous domains keep their values and types through
  generation (`Any[1, 1.0]` gives an `Any` field with both values distinct
  by `===`).
- `show` performs no search: a test wraps a lazy rule in a counter and
  swaps every rule table for one that throws, for all five result kinds.
- Each deprecation warns once per call site under `--depwarn=yes`, checked
  in a subprocess, on Julia 1.13 and 1.10.
- Top-up recipe: `all_pairs(space; must_include = existing)` keeps the
  existing rows first and is complete.

## Decisions for review

1. **Field types** follow the stored domain's element type: `Vector{Int}`
   gives `Int`, `[nothing, :x]` gives `Union{Nothing, Symbol}`, `Any[...]`
   gives `Any`. Deterministic and simple; a narrower union is possible but
   would depend on the values drawn.
2. **`copy(cases)` and slices return a plain `Vector{T}`** (Base's default
   for a read-only `AbstractVector`); writing into a result throws.
3. **`TestCases.strength` is 0** for excursions and full factorials, which
   have no strength; `show` never prints it for them. Review round 1 fixed
   what Phase 5 does with it (contract §1.12).
4. **Excursion notes** are translated to values in the constructor:
   `notes.base` is a row of type `T`, `notes.never_appear` is
   `name => value` pairs.
5. **Positional results are not a Tables row table** (they are tuples).
   The docstring gives `DataFrame(cases, parameters(cases.space))` and the
   `NamedTuple` broadcast for CSV. Phase 7 makes this a recipe.
6. **`excursions` and `full_factorial` accept `constraints =`** on named
   input, read as "generation calls" in §12.12; passing `stronger` to
   either is an `ArgumentError` per §7.5 rather than a `MethodError`.
7. **The excluded line** said "impossible because constraints combine"
   even when a single wider-scope rule causes an implied exclusion; the
   per-exclusion line says "impossible because of rule k". Wording
   question for the review. Resolved in review round 1: the summary now
   says "impossible under the constraints".
8. **`show` adds** a row-number column, "(2 must-include)" after the
   count, and "strength 2, 3 within (a, b, c)" for stronger groups.
9. **CSV and `nothing`:** CSV.jl refuses `nothing`; the docstring gives the
   `transform` that writes it as an empty field.
10. **One deprecated spelling per line** in the subprocess test: Julia
    1.10 warns twice for two deprecated spellings on one line, 1.13 once.

## Pending tests after this phase (8)

| Phase | Count | What |
|:--|--:|:--|
| 5 | 3 | coverage/report |
| 6 | 5 | negative generation, partitions kept, negative must-include |

## Review round 1

Five findings, all applied.

1. **A deprecated keyword never weakens an explicit request.**
   `covering(...; strength = 2, n_way = 1)` gave strength 1, because the
   default `strength = 2` could not be told from an explicit 2. `strength`,
   `stronger` and `must_include` now default to `nothing` (omitted) in
   `covering`, `all_values`/`all_pairs`/`all_triples` and the shared
   pipeline; an omitted strength is 2. A keyword with its alias is an
   `ArgumentError` whatever the values, including an empty
   `must_include = []` beside `seeds`:
   - "pass strength only; n_way is its deprecated alias (contract §11.10)"
   - "pass must_include only; seeds is its deprecated alias (contract §10.8)"
   - "pass stronger only; wayness is its deprecated form (contract §11.10)"
   - "pass candidates only; M is its deprecated alias (contract §13.1)",
     from `GND(candidates = 50, M = 70)`, now that `candidates` defaults to
     `nothing` (50)
   - "pass distance only; n_way is its deprecated alias for an excursion
     (contract §7.5)": found in the same audit. `values_excursion(...;
     distance = 1, n_way = 2)` silently gave distance 2. `_excursions` now
     takes the alias's default distance as an argument and `distance =
     nothing` as omitted.

   Contract §13.2 now states the rule and lists the five pairs. The
   `covering` docstring says so. An explicit `strength = nothing` is read
   as omitted.
2. **`must_include` is read once.** `_must_include_rows` collects the
   caller's rows once, validates that `Vector` and hands it to `Request`.
   Before, a positional call iterated the rows to check them and then
   passed the same iterator on, so `Iterators.Stateful([(2, 2, 2)])` gave
   `n_must_include == 0` and lost the row. A `TestCases` is unwrapped to a
   `Vector` there too. A non-iterable or a non-vector collection
   (`must_include = 5`, `= :a`) is now "must_include is a list of rows,
   such as a vector of NamedTuples or tuples; got 5 (contract §10.1)"
   rather than a row-1 error.
3. **Implied-exclusion wording.** The excluded line now reads "2
   impossible under the constraints" because one wider-scope rule can
   imply an exclusion alone. Direct ones stay "3 pairs forbidden". The
   per-`Exclusion` line still names the cause ("impossible because rules 1
   and 2 combine", "impossible because of rule 2"). The changes are in the
   `TestCases` docstring, the exact-text tests, the transcript above and
   the plan's Phase 4 step 6. The contract never had the phrase. A new
   test shows one three-parameter rule giving "excluded: 1 pair impossible
   under the constraints".
4. **Search budgets.** The `covering` docstring now gives the two
   outcomes separately. `feasibility_limit` exhaustion throws
   `ResourceLimitError`: raise it when generation cannot finish.
   `explanation_limit` exhaustion returns the same certified rows, with
   implied exclusions at `minimal = :unresolved` and `limit =
   :explanation_limit => N` (§3.15–§3.16): raising it only makes the
   attribution more precise. `full_factorial` said "as for covering"; it
   now says that both budgets apply only to partial must-include rows, and
   that an exhausted explanation still gives the no-completion
   `ArgumentError`, marked unresolved. `excursions` points to it.
5. **Strength 0 and Phase 5.** The `TestCases` docstring says `strength`
   is 0 for excursions and full factorials and that measuring such a
   result needs an explicit strength. Plan Phase 5 step 1 and contract
   §1.12 now say `coverage(cases::TestCases)` measures at `cases.strength`
   and `cases.stronger`. For strength 0 it is an `ArgumentError` asking for
   `strength =`, and `report(cases)` measures at strength 2 and says so.
   §1.19 says the recorded strength is 0 for a strategy that has none.

New tests (`test/test_interface.jl` unless noted):
- every alias pair, with `strength = 2, n_way = 1`,
  `all_pairs(...; seeds = [...], must_include = [...])`, an empty side on
  every entry point, `GND(candidates, M)`, and an excursion's `distance`
  with `n_way`. Each alias alone still works.
- `Iterators.Stateful` and a generator, named and positional, for
  `all_pairs` (both engines), `excursions` and `full_factorial`. The row
  comes first and `n_must_include == 1`.
- `all_pairs(space; explanation_limit = 1)` on the solver space, both
  engines. The design is complete by the checker and has the same rows as
  the default. Both implied exclusions are unresolved at
  `:explanation_limit => 1`, and the excluded line adds "2 with an
  unresolved explanation". For a must-include row with no completion,
  `all_pairs`, `excursions` and `full_factorial` still throw and say the
  explanation is unresolved.
- the one-rule implied exclusion (`test/test_testcases.jl`).

Suite: the interface and `TestCases` items pass, 853 of 853, or 864 with
the Aqua item. The full `Pkg.test()` on Julia 1.13 gives 272,474 passed, 8
broken and 0 failed in 5 min 22 s. The 8 broken are the pending Phase 5 and 6
tests above.
