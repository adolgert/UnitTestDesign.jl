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
  generation (`Any[1, 1.0]` gives a `Union{Int64, Float64}` field, since
  review round 2, with both values distinct by `===`).
- `show` performs no search: a test wraps a lazy rule in a counter and
  swaps every rule table for one that throws, for all five result kinds.
- Each deprecation warns once per call site under `--depwarn=yes`, checked
  in a subprocess, on Julia 1.13 and 1.10.
- Top-up recipe: `all_pairs(space; must_include = existing)` keeps the
  existing rows first and is complete.

## Decisions for review

1. **Field types** come from the parameter's values, not the domain's
   element type: `Union{unique(typeof.(domain))...}`, which is one concrete
   type when the values share it. `[1, 2, 3]` and `Any[1, 2]` give `Int`,
   `Any[1, 1.0]` gives `Union{Int64, Float64}`, `[nothing, :x]` gives
   `Union{Nothing, Symbol}`, and `[1, Invalid(1)]` gives
   `Union{Int64, Invalid{Int64}}`. The type depends on the whole domain,
   never on the values drawn, so it stays deterministic. Changed in review
   round 2; the first version used the domain's `eltype`, so `Any[1, 2]`
   gave an `Any` field, against §2.4.
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

## Review round 2

Five findings, all applied.

1. **The full-factorial limit comes before any search.** `full_factorial`
   built the `Request` before `generate_full_factorial` compared the
   candidate count with `limit`, and the `Request` checks a partial
   must-include row with a feasibility search. With eight candidates,
   `limit = 1` and a partial row under a rule, the caller got a
   `feasibility_limit` error and advice to raise it, for an enumeration that
   was refused anyway. `check_full_factorial_limit(arity, limit)` now holds
   the check. It validates `limit`, counts the product as a `BigInt`, and
   throws the `ResourceLimitError` that names the count and `:limit`.
   `full_factorial` calls it with the space's ordinary arities before it
   builds the `Request`. `generate_full_factorial` calls it again for
   callers that build their own request. The docstring now says the count
   comes before any row is looked at, must-include rows included.
2. **Keyword values are checked before they are sorted or converted.** One
   check, `_check_integer(keyword, value, least, section)`, reads every
   integer keyword. It accepts an `Integer` other than `Bool` that is at
   least `least` and fits in an `Int`, and returns it as an `Int`. Anything
   else is an `ArgumentError` of the form "KEYWORD must be ACCEPTED, got
   VALUE (contract §N)". `_check_limit` is that check with a least value
   of 1. Every generation pipeline checks its keywords before it builds the
   space. `Request` also dropped the `::Integer` annotations on its limits,
   which had turned `feasibility_limit = 1.5` into a `TypeError` before
   `_check_limit` could run. The audit found these problems:

   | Keyword | Malformed value | Before | Now |
   |:--|:--|:--|:--|
   | `wayness` | `Dict(3 => …, :a => …)` | `MethodError` from `isless` in `sort` | keys checked before sorting |
   | `GND(candidates)` | `1.5`, `big(2)^70` / `:a` / `2.0`, `true` | `InexactError` / `MethodError` / read as 2, 1 | `ArgumentError` |
   | `GND(seed)` | `1.5`, `typemax(UInt64)` / `:a`, `nothing` / `-1` | `InexactError` / `MethodError` / a `DomainError` from `Xoshiro` at generation on Julia 1.10 | `ArgumentError`; a seed is at least 0 |
   | `GND(M)` | `1.5` | `InexactError` | `ArgumentError` naming `M` |
   | `GND(rng)` | `:a` | `MethodError` from `convert` | `ArgumentError` |
   | `strength` | `true` | read as 1 | `ArgumentError` |
   | `n_way` | `1.5` | the message named `strength` | names `n_way` |
   | `distance` | `true` / `big(10)^30` | read as 1 / `InexactError` | `ArgumentError` / the parameter count (§7.5) |
   | `limit` | `true` / `big(10)^30` | read as 1 / `InexactError` once exceeded | `ArgumentError` |
   | `feasibility_limit`, `explanation_limit` | `1.5`, `:a` / `big(10)^30` / `true` | `TypeError` / `InexactError` / read as 1 | `ArgumentError` |
   | `from` | a wrong length; an unknown name or value | messages that did not name `from` | name `from` |
   | `from` | a `NamedTuple` on a positional call | accepted | `ArgumentError`, as for `must_include` rows |
   | `stronger` | `:a`, `[:a => 3]` | `MethodError` from `iterate` | `ArgumentError` |
   | `stronger` | `(1, 2, 3) => 3`, unwrapped | "each entry … got (1, 2, 3)" | "wrap a single group in a vector" |
   | `stronger` | `[5 => 3]` | a bare index read as a group | a group is a tuple or vector |

   The new messages:
   - "`wayness` is a Dict{Int, Vector{Vector{Int}}} from a strength to
     parameter index groups, such as Dict(3 => [[3, 4, 5, 6]]); got the key
     :a, which is not an integer strength (contract §11.10)"
   - "candidates must be a positive integer, got 1.5 (contract §9.5)", and
     "… that fits in an Int, got 1180591620717411303424 …" for `big(2)^70`
   - "M must be a positive integer, got 1.5 (contract §9.5)"
   - "seed must be an integer of at least 0, got -1 (contract §9.5)"
   - "rng must be a random number generator, an AbstractRNG such as
     Xoshiro(1), got :a (contract §9.6)"
   - "strength must be a positive integer, got 0 (contract §11.1)", which
     replaces "strength is an integer of at least 1" and the `Request`'s
     "strength must be at least 1"
   - "n_way must be a positive integer, got 1.5 (contract §11.1)"
   - "distance must be an integer of at least 0, got 1.5 (contract §7.5)",
     and for the aliases "n_way, an excursion's distance, must be an
     integer of at least 0, got 1.5 (contract §7.5)"
   - "limit must be a positive integer, got 1.5 (contract §7.3)"
   - "feasibility_limit must be a positive integer, got 1.5 (contract §3.3,
     §3.13)", which replaces "must be a positive Int;"
   - "`from` has 2 values; the space has 3 parameters, p1, p2, p3, and the
     base is a complete row (contract §7.6)"
   - "`from` is a NamedTuple; a positional call takes the base as a tuple or
     vector of values in argument order, one for each of p1, p2, p3
     (contract §7.6)"
   - "the excursion base `from`: `d` is not a parameter of this space; the
     parameters are a, b, c", with the same prefix for a value outside the
     domain
   - "stronger is a vector of `group => strength` pairs, such as [(:a, :b,
     :c) => 3]; got :a (contract §11.3)"; "… wrap a single group in a
     vector: stronger = [(1, 2, 3) => 3] (contract §11.3)"; "each
     `stronger` group is a tuple or vector of parameter names or indices,
     such as (:a, :b, :c) => 3; got :a => 3 (contract §11.3)"

   Integer types other than `Int` still work: `GND(seed = UInt8(3))`,
   `strength = Int32(3)` and `limit = Int32(8)` are read as `Int`s. The
   contract now says what GND accepts (§9.5). `TestSpace`'s
   `tabulation_limit` was not changed. It already rejects a non-integer
   with its own `ArgumentError`, and only `true` or an integer beyond `Int`
   gets through it.
3. **Field types come from the values (§2.4).** `row_type` used each stored
   domain's `eltype`, so `Any[1, 2]` gave an `Any` field. `field_type(domain)
   = Union{unique(typeof(v) for v in domain)...}` now gives the fields
   below. Rows are still built with `convert(T, …)`. Every value already
   has its field's type, so nothing is converted: `1` stays an `Int` and
   `1.0` a `Float64`.

   | Domain | Field type |
   |:--|:--|
   | `[1, 2, 3]` | `Int64` |
   | `Any[1, 2]` | `Int64` |
   | `Any[1, 1.0]` | `Union{Float64, Int64}` |
   | `[nothing, :x]` | `Union{Nothing, Symbol}` |
   | `[1, Invalid(1)]` | `Union{Int64, Invalid{Int64}}` |

   `DataFrame(cases)` columns follow. A space of `Any[1, 2]`,
   `Any[1, 1.0]` and `[nothing, :x]` gives columns of `Int64`,
   `Union{Int64, Float64}` and `Union{Nothing, Symbol}`, and the union
   column holds both `Int64` and `Float64` cells. The `TestCases`
   docstring, decision 1 above and the tests that asserted `Any` are
   updated. §2.4 already allowed a `Union`. It now also says that a shared
   concrete type is used whatever the domain's element type (`Any[1, 2]`
   gives `Int`), and names the union of the values' concrete types.
4. **One-parameter results in Phase 5's default.** An excursion or a full
   factorial may have one parameter, where strength 2 does not exist.
   Contract §1.12 and plan Phase 5 step 1 now say `report(cases)` measures
   such a result at strength `min(2, parameter count)`. Plan Phase 5 step 6
   adds `report` on one-parameter excursions and full factorials: "cover
   this boundary in Phase 5 tests".
5. **Full-factorial docstring and duplicates.** The docstring said "each
   once", but duplicate must-include rows are kept (§10.5). It now says:
   the must-include rows first, in the order given with duplicates kept,
   then each remaining valid row once, and a valid row equal to a
   must-include row is not repeated. The `excursions` docstring had the same
   "each once" and now says the same. Its `must_include` item adds that the
   rows are kept as given, duplicates included (§7.11). The
   `generate_full_factorial` docstring changed to match. Contract §7.2 had
   "each once" too, and now places the must-include rows first with their
   duplicates.

Contract edits: §1.12 (`min(2, parameter count)`), §2.4 (values, not the
domain's element type), §7.2 (must-include duplicates), §9.5 (the accepted
`seed` and `candidates`).

New tests:
- `test/test_interface.jl`, a new item, "keyword values are checked before
  they are sorted or converted". It asserts the exact message for every
  row of the table above: `wayness` with mixed and `Float64` keys and a
  mixed `Integer` key type; `candidates`, `M`, `seed` and `rng`, including
  a seed beside `rng` and `seed = nothing` with `rng`; `strength` and
  `n_way`; `distance` and an excursion alias's `n_way`, with a `BigInt`
  distance clamped to the parameter count; `limit`; both search budgets on
  all six entry points; `from` by length, positional `NamedTuple`,
  unknown name, value outside the domain and wrong type; and `stronger` by
  shape, group and strength. Other integer types are accepted.
- `full_factorial`, in the same file. A space with a lazy rule
  (`tabulation_limit = 1`), a partial must-include row, `limit = 1` and
  `feasibility_limit = 1` throws the `:limit` error naming "8 candidate
  rows", and the rule is never evaluated. With `limit = 8` the same call
  searches and throws `:feasibility_limit`.
- `full_factorial` and `excursions` with a duplicated must-include row. Both
  copies come first, and the remaining rows appear once each, never a third
  copy. There are named and positional cases.
- `test/test_testcases.jl`, a new item, "field types come from the values".
  It checks `field_type` and `row_type` (named and positional) for the five
  domains. It checks that generated covering, full-factorial and
  excursion-base values keep `===` in `Union` fields. It checks the
  `Invalid`, `Partition` and mixed-type fields of the display test. The
  Tables item adds the mixed `DataFrame` columns.

Suite: the interface, `TestCases` and full-factorial items pass, 1,063 of
1,063, or 1,074 with the Aqua item. The full `Pkg.test()` on Julia 1.13
gives 273,137 passed, 8 broken and 0 failed in 5 min 30 s. The 8 broken are
the pending Phase 5 and 6 tests. One change came after that run started: a
fast path in `field_type` that returns a domain's concrete `eltype` without
scanning its values. The same answer comes either way, and the targeted run
above, which came after it, covers it. Julia 1.10 gives the same field types,
the same `BigInt` count, and the same `wayness` and `seed` messages, checked
by a script rather than the suite.
