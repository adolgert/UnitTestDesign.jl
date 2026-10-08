# Phase 6 review: `Invalid`, `Partition`, `diagnose`, `github_matrix`

Date: 2026-09-27. Branch `feature/phase6-features`, stacked on
`feature/phase5-measure` (PR #56). Plan: Phase 6.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1 | Negative generation: negative targets per §6 classified through the negative-row search, covered by a sub-request over the other parameters with the same engine, `p = v` inserted; rows ordered must-include, ordinary, negative; separate negative bookkeeping on `Design` and `TestCases`; `!` row marker; two guarantees in `report` | `src/invalid.jl`, `src/request.jl`, `src/engines.jl`, `src/testcases.jl`, `src/report.jl` |
| 1 | Wrappers in must-include (negative policy for a row with one `Invalid`), full factorial (ordinary then single-invalid rows; the limit counts both), excursions (may reach an `Invalid` value); the temporary unsupported-feature errors removed | `src/request.jl`, `src/full_factorial.jl`, `src/excursions.jl`, `src/interface.jl` |
| 2 | `realize(case; rng)`, `realize(cases; rng)`; wrappers kept in results; `rng` required; a draw returning a wrapper is an error | `src/partition.jl` |
| 3 | `diagnose(cases, passed; strength)` → `Diagnosis` with ranked, grouped suspects and explicit statuses; `followups(d)` → `found`/`inseparable`/`indistinguishable`/`unknown` | `src/diagnose.jl` |
| 4 | `github_matrix(cases; io)` with JSON.jl 1.x as a dependency; every row validated before writing; wrappers, non-finite numbers, `missing`, collections rejected naming row and field; warning above 256 jobs | `src/export.jl`, `Project.toml` |
| 5 | Tests against the oracle on both parts, random gate extended with an `Invalid` value, parsed-JSON comparisons; the last 5 pending fixture lines flipped | `test/test_invalid.jl`, `test_partition.jl`, `test_diagnose.jl`, `test_export.jl` |

Exports added: `realize`, `diagnose`, `followups`, `github_matrix`.
No pending tests remain in the suite.

## Independent checks

- Ordinary and negative guarantees hold by the oracle on every wrapper
  fixture, on spaces with two invalid parameters and with an invalid
  value inside a `stronger` group, at strengths 1–3, both engines; 100
  random problems with one `Invalid` value pass on both parts.
- `coverage(cases)` of every generated negative design is complete on
  both parts, and its `negative.excluded` equals the result's.
- `realize` is deterministic under a seeded `Xoshiro`, draws once per
  partition in parameter order, preserves positional shape, and passes
  `Invalid` through.
- Opus's newton/sparse example ranks the faulty pair first and finds an
  isolating case for each suspect with one change from a failing case;
  nested and constrained suspects give `indistinguishable`/`inseparable`;
  `feasibility_limit = 1` gives `unknown`.
- Exported JSON is parsed back and compared for quotes, backslashes,
  control characters, Unicode, `null`, booleans, integers, floats, and
  the empty result; every rejection leaves the output empty.

## Transcript of the complete target screen

```
# The target screen
5 cases · strength 2 · IPOG · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible under the constraints; see report(cases)
    mode    solver  tol
 1  :exact  :qr     1.0e-6
 2  :exact  :lu     1.0e-6
 3  :exact  :none   1.0e-6
 4  :fast   :none   0.001
 5  :fast   :none   1.0e-6

infeasible: no valid case contains (solver = :lu, tol = 0.001); rules 1 and 2 together exclude it (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
covers 6 of 11 feasible pairs, 5 missing
5 cases (2 must-include) · strength 2 · IPOG · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible under the constraints; see report(cases)
    mode    solver  tol
 1  :fast   :none   0.001
 2  :exact  :lu     1.0e-6
 3  :exact  :none   1.0e-6
 4  :exact  :qr     1.0e-6
 5  :fast   :none   1.0e-6

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

strategy        cases   share  pairs  triples
full_factorial      5  100.0%  11/11      5/5  valid 5 of 12
covering(1)         3   60.0%   8/11      3/5
covering(2)         5  100.0%  11/11      5/5
covering(3)         5  100.0%  11/11      5/5
excursions(1)       2   40.0%   5/11      2/5
excursions(2)       3   60.0%   7/11      3/5
case counts are the rows each strategy produced with IPOG, not lower bounds

1 failure of 5 cases; 3 suspects in 1 group (hypotheses, not proof)
1. (solver = :qr,) — in 1 of 1 failure — indistinguishable from (mode = :exact, solver = :qr) and (solver = :qr, tol = 1.0e-6)

3-element Vector{UnitTestDesign.Followup}:
 (solver = :qr,): inseparable; every valid case holding it also holds (mode = :exact, solver = :qr), under rule 1 (@require(mode == :exact || solver == :none))
 (mode = :exact, solver = :qr): indistinguishable; every case holding it holds (solver = :qr,)
 (solver = :qr, tol = 1.0e-6): indistinguishable; every case holding it holds (solver = :qr,)

{"include":[{"mode":"exact","solver":"qr","tol":1.0e-6},{"mode":"exact","solver":"lu","tol":1.0e-6},{"mode":"exact","solver":"none","tol":1.0e-6},{"mode":"fast","solver":"none","tol":0.001},{"mode":"fast","solver":"none","tol":1.0e-6}]}
6 cases · strength 2 · IPOG · 3 parameters · 12 combinations
    p1  p2   p3
 1  1   "a"  1.0
 2  1   "b"  2.0
 3  2   "a"  2.0
 4  2   "b"  1.0
 5  3   "a"  1.0
 6  3   "b"  2.0


# Invalid
9 cases · strength 2 · IPOG · 3 parameters · 16 combinations · 8 negative targets
excluded: 1 pair forbidden; see report(cases)
     n            m   k
 1   1            :b  1
 2   10           :a  1
 3   1            :a  2
 4   1            :b  2
 5   10           :a  2
 6!  Invalid(-1)  :a  2
 7!  Invalid(-1)  :b  1
 8!  Invalid(0)   :a  2
 9!  Invalid(0)   :b  1

9 cases cover all 11 feasible pairs of a 16-combination space (1 pair forbidden); negative: covers 8 of 8 feasible pairs
excluded:
  (n = 10, m = :b): forbidden by rule 1 (@forbid(n == 10 && m == :b))
bonus: 5 of 6 feasible triples covered
prefix curve:
  first 2 of 9 cover 54% (6 of 11)
  first 4 of 9 cover 90% (10 of 11)
  first 5 of 9 cover 100% (11 of 11)
  first 6 of 9 cover 100% (11 of 11)
  first 8 of 9 cover 100% (11 of 11)
  first 9 of 9 cover 100% (11 of 11)
seed: none (IPOG uses no randomness)

true 8 8
14 (candidates = 16, accepted = 14)

# Partition
6 cases · strength 2 · IPOG · 2 parameters · 6 combinations, 6 valid
    size              mode
 1  Partition(:tiny)  :a
 2  Partition(:tiny)  :b
 3  Partition(:huge)  :a
 4  Partition(:huge)  :b
 5  1.0               :a
 6  1.0               :b

[(size = 1.0e-6, mode = :a), (size = 1.0000000000000001e-7, mode = :b), (size = 1.0e8, mode = :a), (size = 1.0e8, mode = :b), (size = 1.0, mode = :a), (size = 1.0, mode = :b)]
true
ArgumentError: realize needs the keyword rng, a random number generator such as realize(cases; rng = Xoshiro(1)); no draw uses the global generator (contract §4.7)
ArgumentError: github_matrix: row 1, field `size`: Partition(:tiny) is a Partition wrapper; realize the case, or write the partition's name. Map it to a supported type first: a String, a Symbol, a Bool, a finite Integer or AbstractFloat, or nothing.
```

## Decisions for review

1. **Negative rows via a sub-request** over the other parameters at
   strength `s - 1` with the groups containing `p` reduced by one, sharing
   the request's lazy memo; a sub-space is built from parts so no rule is
   re-tabulated. `Request` accepts base strength 0 internally for these
   sub-requests only (no base targets); the public floor stays 1.
2. **`!` marks negative rows** in the table; a covering result over a
   space with `Invalid` values always shows "· N negative targets", even 0.
3. **Excursions** change a parameter to its other values in domain order,
   `Invalid` values included; rows with two invalid values are neither
   candidates nor counted as dropped.
4. **`diagnose`** considers only the base strength, not `stronger` groups;
   includes `Invalid` values in suspects; plain rows default to
   `min(2, n)`. At strength 3, supersets of a strong suspect crowd the
   ranking (162 suspects in 52 groups in one example); folding supersets
   into the smaller suspect is a possible refinement.
5. **`indistinguishable`** means "this suspect contains another suspect"
   (decided without a search, across groups); **`inseparable`** means an
   exhausted search proved it, naming the rules and other suspects.
   `followups` takes `explanation_limit` and `prefer = :nearest | :domain`.
6. **The two-fault test** deliberately shows the docstring's caveat: an
   innocent pair ranks above both true faults.
7. **`github_matrix`** does not use `plain`: the plan requires rejecting
   wrappers rather than stringifying them. Invalid UTF-8 strings are
   rejected because JSON.jl would write them raw. JSON.jl compat is `"1"`.
8. **`docs/Manifest.toml`** (tracked, from 0.3.0) lacks JSON; Phase 7
   regenerates it.
9. A pre-existing display bug (an excursion base with Union-typed fields
   printing as `@NamedTuple{…}((…))`) was fixed on the way.

## Review round 1

Date: 2026-09-27. Three findings, applied on the same branch.

| # | Finding | Change | Where |
|:--|:--|:--|:--|
| 1 | `followups` searched only ordinary completions for a suspect with no `Invalid` value, so a lone `(b = 2,)` on `n = [1, Invalid(0)]` with `forbid((n = 1, b = 2))` was reported "inseparable; no valid case holds it" although the failing row `(n = Invalid(0), b = 2)` is valid under §5.5 and isolates it | Every kind of case that could hold the suspect is searched (`_row_kinds`): ordinary, then for each parameter the suspect leaves out and each invalid value of it, the negative kind, with `feasibility_for`'s `(p, v)` candidates and active rules plus the isolation tables (§3.17). `:nearest` keeps the fewest changes across kinds, ties to the kind searched first (ordinary); `:domain` takes the first kind with a case. `:inseparable` only when every kind is proven, its proof the union of theirs, and `show` names the kinds. `Followup` gains `kind` (`:ordinary`, `:negative`, `:none`) and `searched` | `src/diagnose.jl`, contract §3.17 |
| 2 | The prefix curve, bonus and `design_sizes` counted ordinary targets only, so `(a = [1, Invalid(0)], b = [1, Invalid(0)])` printed "first 1 of 3 cover 100%" with both negative targets missing | `coverage`'s negative marking now records each row's first projections too (a negative row counts only on supports holding its invalid parameter), giving `Report.prefix_negative`; the bonus measures the negative part (`bonus.negative`); `design_sizes` rows carry `negative_cases`, `negative_pairs`, `negative_triples` and the table prints "4 + 3" and "9/9 + 4/4" with a legend line. With `Invalid` values the ordinary figures are labeled "of ordinary pairs"; without, every line prints as before | `src/measure.jl`, `src/report.jl`, contract §3.12, §5.10 |
| 3 | `github_matrix` wrote `NamedTuple` keys unchecked, so a field named `Symbol(String(UInt8[0xff]))` gave invalid UTF-8 JSON | Each row's names are checked before its values: nonempty and valid UTF-8, "row K, field name Symbol("\xff"): not valid UTF-8, …". GitHub's other key rules are documented, not enforced | `src/export.jl` |

### Transcripts

The reviewer's follow-up example, at strength 1 and at the default strength 2:

```
julia> space = TestSpace((n = [1, Invalid(0)], b = [1, 2]); constraints = [forbid((n = 1, b = 2))]);

julia> rows = [(n = 1, b = 1), (n = Invalid(0), b = 1), (n = Invalid(0), b = 2)];

julia> followups(diagnose(rows, [true, true, false]; space, strength = 1))
1-element Vector{UnitTestDesign.Followup}:
 (b = 2,): found negative case (n = Invalid(0), b = 2), failing case 3 itself

julia> followups(diagnose(rows, [true, true, false]; space))
2-element Vector{UnitTestDesign.Followup}:
 (b = 2,): inseparable; every valid case holding it also holds (n = Invalid(0), b = 2), under rule 1 on (n, b); searched ordinary cases and negative cases with n = Invalid(0)
 (n = Invalid(0), b = 2): indistinguishable; every case holding it holds (b = 2,)
```

Before the fix both printed "(b = 2,): inseparable; no valid case holds it: rule 1 on (n, b) excludes it".

The reviewer's two-domain example:

```
julia> space = TestSpace((a = [1, Invalid(0)], b = [1, Invalid(0)]));

julia> report(all_pairs(space))
3 cases cover all 1 feasible pairs of a 4-combination space; negative: covers 2 of 2 feasible pairs
bonus coverage not applicable: strength 3 exceeds the number of parameters, 2
prefix curve:
  first 1 of 3 cover 100% of ordinary pairs (1 of 1); negative 0 of 2
  first 2 of 3 cover 100% of ordinary pairs (1 of 1); negative 1 of 2
  first 3 of 3 cover 100% of ordinary pairs (1 of 1); negative 2 of 2
seed: none (IPOG uses no randomness)

julia> design_sizes(space)
strategy        cases   share      pairs  triples
full_factorial  1 + 2  100.0%  1/1 + 2/2        —  valid 3 of 4
covering(1)     1 + 2  100.0%  1/1 + 2/2        —
covering(2)     1 + 2  100.0%  1/1 + 2/2        —
excursions(1)   1 + 2  100.0%  1/1 + 2/2        —
excursions(2)   1 + 2  100.0%  1/1 + 2/2        —
cells with + read ordinary + negative: rows without and with an Invalid value, and the targets each kind covers
case counts are the rows each strategy produced with IPOG, not lower bounds
```

The "# Invalid" transcript above now reads, from the bonus line on:

```
bonus: 5 of 6 feasible triples covered; negative: 4 of 8
prefix curve:
  first 2 of 9 cover 54% of ordinary pairs (6 of 11); negative 0 of 8
  first 4 of 9 cover 90% of ordinary pairs (10 of 11); negative 0 of 8
  first 5 of 9 cover 100% of ordinary pairs (11 of 11); negative 0 of 8
  first 6 of 9 cover 100% of ordinary pairs (11 of 11); negative 2 of 8
  first 8 of 9 cover 100% of ordinary pairs (11 of 11); negative 6 of 8
  first 9 of 9 cover 100% of ordinary pairs (11 of 11); negative 8 of 8
```

so its bonus line had been hiding that half of the negative triples are
uncovered.

### Tests

- `test_diagnose.jl`: `check_followups` enumerates the valid rows by kind
  (ordinary and negative, the latter valid under §5.5) and checks each found
  case against the rows of the kind it names, each inseparable claim against
  both kinds, and `searched` against the kinds that could hold the suspect.
  New items: the reviewer's example (both `prefer` modes, both strengths, a
  tie that an ordinary case wins), and an exhaustive sweep over every outcome
  vector of the valid rows of three small spaces with `Invalid` values and
  rules (random outcomes above 8 rows), at strengths 1 and 2, both `prefer`
  modes. With `_row_kinds` reduced to the ordinary kind the sweep fails at
  the brute-force inseparable check, as the old code would have.
- `test_report.jl`: the two-domain lines; `invalid_beside_ordinary`'s bonus
  and prefix lines; every ordinary and negative prefix point and the bonus
  against the oracle (`check_design`) on three spaces, strengths 1–2, both
  engines; bounds under `feasibility_limit = 1`; `design_sizes` on
  `invalid_beside_ordinary` exactly, each negative figure against the oracle
  measure of the design each strategy produces, and `nothing` for a stopped
  strategy. The two `plain` data-shape assertions gained the new fields; no
  exact-text test changed.
- `test_export.jl`: an invalid-UTF-8 name in row 1 and in row 2, a bad name
  beside a bad value (the name is reported), an empty name, a `TestSpace`
  name; each leaves the `IOBuffer` empty. Names with quotes, backslashes,
  newlines, Unicode, spaces, a leading digit and a dot round-trip through
  `JSON.parse`.
- Counts: the diagnose, report and export items go from 886 to 33,125
  passing assertions (the exhaustive sweep is most of it); the full suite
  passes 309,720 of 309,720 in 7m34s, 0 failures, 0 broken, Aqua included.
  The docstring doctests pass under Documenter in a scratch environment,
  and the new paths run on Julia 1.10.

### Decisions for review

1. **`Followup` fields.** `kind` is `:none` for every status but `:found`.
   `searched` lists the kinds as `NamedTuple()` (ordinary) and `(p = v,)`;
   `show` names them only when more than one was searched, so every
   existing line is unchanged. A found negative case prints as "found
   negative case (…)".
2. **Combined proof.** An `:inseparable` suspect with several kinds
   reports the union of the kinds' rules and suspects, each needed by some
   kind's proof; `minimal` is `:verified` only when every kind's is,
   `:unresolved` when any is, else `:not_applicable` (a directly forbidden
   kind has no deletion search).
3. **Search cost.** `:nearest` searches every kind from each start (up to 5)
   unless a failing case itself isolates the suspect; a space with many
   invalid values multiplies the searches for ordinary suspects.
4. **Data shape.** `Report.bonus` gains `negative`, `Report` gains
   `prefix_negative`, `DesignSizes` gains `has_invalid` and each row the
   three negative fields, for every space (zeros without `Invalid` values),
   so `plain(report)` and `plain(design_sizes(…))` change shape. The share
   in `design_sizes` stays `cases / valid` over both kinds.
5. **GitHub key names.** `matrix.<name>` needs a name that starts with a
   letter or `_` and holds only letters, digits, `-` and `_` (GitHub's
   contexts reference); any other name works as `matrix['<name>']`, so only
   empty and invalid-UTF-8 names are rejected. `repr` of an invalid-UTF-8
   `Symbol` throws in Julia 1.13, so the message builds `Symbol("\xff")`
   from the `String`.
6. **Not changed.** "cover all 1 feasible pairs" (plural after 1) in the
   guarantee predates this round and is left for Phase 7.
