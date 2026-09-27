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
