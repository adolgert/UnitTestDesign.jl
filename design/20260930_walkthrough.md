# Walk-through guide: the secondary plan, as built

Date: 2026-09-30. The secondary plan (`design/20260928_secondary_plan.md`)
is implemented on a stack of local branches from `feature/phase7-docs`
(`4d9d424`). This guide is for reading the result in depth: where each
concern now lives, what a user can see change, the evidence, and the
judgment calls left for you. Line numbers refer to `feature/review-fixes`.
Each stage section of the plan ends with "Implementation notes": the
adjustments made and why.

## 1. The branches

Each branch is stacked on the one above it. None is pushed, and no PR is
open.

| Stage | Branch | Head | Commits | What it did | Gate |
|:--|:--|:--|--:|:--|:--|
| A | `feature/stage-a-docs-truth` | `feb699b` | 10 | Contract, docstrings and pages say what the code does; a test for each reworded promise. The first commit adds the review, the verification, the probes and the plan under `design/` | Wording and tests only |
| E1 | `feature/stage-e1-proof-record` | `2fb7712` | 3 | `FollowupProof` and `Followup.proofs`; `show` prints per-kind proofs when they differ | Existing `Followup` fields identical on 7,255 `followups` calls |
| B | `feature/stage-b-dead-code` | `78d324b` | 9 | 17 dead definitions and their tests deleted; each `matcher` fixed to what production passes; reference sweep moved to `benchmark/` | Fingerprint and every benchmark case count unchanged |
| C | `feature/stage-c-measurement` | `17b175e` | 13 | One row reader; prepared rows; one memo per `report` or `design_sizes` call; one outcome-to-status owner; counts-only path; the snapshot script | Snapshot byte-identical |
| D | `feature/stage-d-projection` | `eb1b0f9` | 14 | `NegativeProjection`; checked parts constructor; `_candidates`; generation classifies negative targets by coverage's walk; one mixed-radix code | Snapshot identical except two planned lines |
| E2 | `feature/stage-e2-isolation` | `aa6e6c6` | 4 | `_isolate` returns `_Found`, `_Proof` or `_Unknown`, and reads its status from `IndexClassification` | Snapshot byte-identical |
| F | `feature/stage-f-macros` | `4703234` | 5 | Macro walker moved to `constraint_macros.jl`; `_macro_rule` builds through `_function_rule` | Snapshot byte-identical; field check on 47 rules |
| Review | `feature/review-fixes` | `5f5d2b3` | 8 | Fixes from an independent review of the whole stack; this guide | Snapshot byte-identical |
| Stability | `feature/stability-and-display` | see `git log` | 10 | Type-stability fixes in the core (section 7), and every follow-up line notes an unresolved proof in parentheses | Snapshot byte-identical |

Useful commands:

```sh
git log --reverse --oneline feature/phase7-docs..feature/review-fixes   # every commit, in order
git diff 4d9d424 feature/review-fixes --stat -- src test docs benchmark
git diff feature/stage-b-dead-code feature/stage-c-measurement -- src   # one stage
julia --project=. benchmark/snapshot.jl > out.txt                     # the before/after dump, about 2 min
julia --project=. benchmark/reference_sweep.jl                          # unreferenced definitions, for a person to judge
```

`src/` changed by +1,537/−1,407 lines across 18 files, measured at the Stage F
head. 477 of the added lines are the unchanged move to
`src/constraint_macros.jl`.

## 2. A tour of the new structure

The plan's last section, "The structure this plan leaves behind", is the map:
one owner per concern, with anchors. This section follows the main paths
through it in the order a call takes them.

**Reading what the caller wrote.** Every row a caller writes goes through
`_row_indices` (`src/space.jl:494`). That includes a `coverage` or `diagnose`
row, a must-include row, `from`, and the argument of `isallowed`, `explain`
and `classify`. The reader owns the four input errors. Every collection of
rows goes through `_row_list` (`:549`). What a caller accepts beyond the
shape of a row stays with that caller: an ordinary `from`, no `NamedTuple` in
a positional call, a `NamedTuple` target for `classify`. `github_matrix` and
`realize` still read rows on their own; they were out of scope.

**What a call remembers.** `FeasibilityContext` (`src/explain.jl:25`) holds
two things.
- `memos`: the lazy-rule memo. One lives for each operation, and `report` and
  `design_sizes` now share one across their measurements
  (`src/report.jl:191`, `:565`).
- `searches`: the answer cache. Each measurement has its own
  (`FeasibilityContext(space, memos; …)`, `:32`); decision 7 and its
  implementation note explain why.

**Classifying one target.** `explain_partial` (`src/feasibility.jl:641`)
gives one of five outcomes. The table `_STATUS_OF_OUTCOME` (`:733`) turns an
outcome into required, forbidden, implied or unknown. Four callers read that
status through `IndexClassification` (`:722`): generation
(`_classify_target`, `src/request.jl:481`), measurement (`_classify!`,
`src/measure.jl:369`), `classify` (`src/explain.jl:388`) and `followups`
(`_isolate`, `src/diagnose.jl:677`). Counting needs no explanation, so it
uses `_status` (`src/feasibility.jl:750`): the direct check, then
completability, and no deletion search.

**Measuring.** The path runs in this order:
1. `_prepare_rows` (`src/measure.jl:207`) sorts the rows once into a
   `PreparedRows` (`:191`).
2. `_measure` (`:568`) lists targets; `_measure_counts` (`:600`) only counts
   them.
3. For each support, `_measure_support!` (`:477`) marks the rows'
   projections (`_projections`, `:273`) and then walks the targets with
   `_walk_support!` (`:455`) and `_measure_block!` (`:402`).
4. Each target the rows don't cover goes to `_classify!` on a `_Record`:
   `_Lists` (`:334`) builds the lists, `_Counts` (`:351`) only counts.

**Generating negative rows.** `cover_negative` (`src/invalid.jl:203`) works
the way ordinary generation does: classify, then cover.
1. `classify_negative_targets` (`:176`) classifies every negative target
   with the same walk measurement uses, through the `_NegativeTargets`
   record (`:145`). This is why exclusions list in `coverage`'s order with
   no sort.
2. For each parameter, one `NegativeProjection` (`:54`) describes the space
   as rows with an invalid value there see it. `_negative_request` (`:114`)
   builds the sub-request from it and checks table and memo identity.
3. The engine covers the required targets for each invalid value.
4. `parent_row` (`:86`) maps each generated row back into the full space.

**Target order.** One mixed-radix code, `_code` and `_decode!`
(`src/space.jl:592, 601`), first parameter fastest.
- `TargetList` (`src/request.jl:391, 407`) decodes and `_recount` (`:595`)
  encodes.
- Measurement's odometer steps through the same order in place. A test ties
  the two together (`test/test_measure.jl:654`).
- `_group_supports` (`src/request.jl:347`) gives the supports and each
  group's share of them, in one pass.

**Follow-ups.** `_followup` (`src/diagnose.jl:713`) calls `_isolate` once per
kind of case, and each call returns a typed result: `_Found`, `_Proof` or
`_Unknown` (`:633-655`). An inseparable suspect keeps one `FollowupProof`
per kind (`:401`). `show` (`:815`, through `_print_proof`, `:796`) prints
the union's line when the proofs agree, and one clause per kind when they
differ.

**Rules.** `forbid(f, names...)`, `require(...)` and the macros all build
through `_function_rule` (`src/constraints.jl:184`). The macro walker is in
`src/constraint_macros.jl`, and its `_macro_rule` (`:472`) passes the
source text as `text`.

**Tools.**
- `benchmark/snapshot.jl` prints about 5,800 generation, measurement and
  follow-up results as text; see the plan's snapshot section.
- `benchmark/reference_sweep.jl` lists definitions nothing references, for a
  person to judge.
- `test/test_checker.jl` has a guard that fails if the oracle
  (`test/checker.jl`) mentions the package outside comments.

## 3. What a user can see change

The contract and the docs:
- §3.8 is narrowed. The rows, their order, the counts, and which targets are
  excluded with which status do not depend on `feasibility_limit`. An implied
  exclusion's explanation (its rule set, `minimal` and `limit`) may depend on
  it. The added §3.14 sentence says why: deletion trials are bounded by both
  limits.
- §3.5 and §12.19 define the memo's operation to include `coverage`,
  `missing_interactions`, `followups` and `report`. `design_sizes` keeps one
  memo for its measurements.
- §3.17: follow-up minimality is judged per kind of case.
- §8.6: `diagnose` takes observations as given.
- §12.16: where a throwing predicate surfaces.
- The `Report.guarantee` field doc now says which parts are measured and which
  are recorded at generation.

API and output:
- `Followup` has a new last field, `proofs::Vector{FollowupProof}`, and
  `FollowupProof` is a new unexported, documented type.
- `show(::Followup)` prints one clause per kind of case when the kinds' proofs
  differ. In the snapshot's random sweep that is 5,799 of 10,017 inseparable
  follow-ups. The line is unchanged when there is one proof or the proofs
  agree.
- `isallowed` and `explain` accept a vector row, read as the tuple of its
  values.
- Input-error wording is unified through `_row_indices`. Changes that tests
  pin: the `excursions(from = …)` shape messages now begin "the excursion
  base `from` …"; an incomplete `from` or `isallowed` row now says "has no
  value for `b` and `c`; it must name every parameter" (`isallowed` still
  points to `explain`); must-include length errors name the parameters.
  `diagnose` accepts any collection of cases, such as a tuple of rows or an
  iterator.
- `coverage` now reports a malformed row before an invalid `strength` or
  `stronger` group, when a call has both.
- Behavior that changes only in failing calls, allowed by §3.6 and §3.7 and
  by §12.17:
  - Negative generation now classifies every negative target before it runs
    any engine. A call that fails at `feasibility_limit` can therefore name a
    different target in its `ResourceLimitError`. The snapshot shows this in
    two lines, where "generating the negative rows with n = Invalid(0) …"
    became "classifying the negative target (m = Invalid(0), e = 2) …".
  - Counting runs no deletion search. A lazy predicate that throws only on an
    assignment reached by a deletion trial therefore no longer throws from
    `report`'s bonus or from `design_sizes`.

Cost:

| Measure | Before | After |
|:--|--:|--:|
| `report`'s bonus on a 30 by 5 `all_pairs` design | 1,007,801,136 B, 0.66 s | 224,613,920 B, about 0.27 s |
| Lazy predicate calls in one `report` (probe `03a`; 8 distinct assignments) | 12 to 16 | 8 |
| Lazy predicate calls in `design_sizes` | 136 | 53 |
| `coverage` of a complete 30 by 5 design | 849,872 B | 595,840 B |
| Negative generation, 4,000 invalid values at each of two parameters | 0.25 s | 0.28 s |

The stack briefly made that last figure 1.45 s, through a scan that is
quadratic in the number of invalid values. The review found it, and the
review branch fixed it (`7210bb6`).

## 4. The evidence

- **Full test suite.**
  - 305,788 passes at `4d9d424`, and 345,332 at the review head on Julia
    1.13.
  - On Julia 1.10 (CI's other version): 366,774 at the review head, from a
    clean environment. The 1.13 manifest can't be merged under 1.10's Pkg.
  - Three time-boxed test items make the counts vary with machine load.
- **Docs build** (`warnonly = false`, doctests on): exits 0 at every stage.
- **Benchmark fingerprint** (fixture 1, IPOG): `7a2b2a3b6f737644`, 958 cases,
  at the base and after Stages B, C, D and F. Every case, query, node,
  rule-check and memo figure in the benchmark report matched the base.
- **Snapshot** (`benchmark/snapshot.jl`; 5,804 cases and 383,501 lines at the
  end).
  - Byte-identical before and after Stages C, E2 and F and the review fixes.
  - After Stage D, identical except the two planned error lines.
  - The snapshot catches a mistakenly shared answer cache (Stage C part 1
    checked this) and a sorted projected scope (Stage D part 1).
- **Independent review** of the whole stack: an old-versus-new differential
  run over 250 random spaces and a list of edge cases, byte-identical apart
  from deliberate wording. It found no correctness bug; its findings and
  their fixes are the review branch.
- **Behavior checks.**
  - The contract's promises that changed have tests: §3.8 by brute force on
    the probe `08a` space; the memo scope by counting predicate calls; §12.16
    through `explain` and `coverage`.
  - Each follow-up proof is checked by brute force within its kind, across
    the random sweep.

## 5. Judgment calls for you

Each was made to keep the plan's intent, and each is recorded in that
stage's implementation notes.

1. **Decision D-1, option (B)** (`8970047`). Generation classifies all
   negative targets first, as ordinary generation does, and `_negative_order`
   and its sort are gone. A test pins the agreement that keeps rows unmoved
   (`test/test_invalid.jl:627`, "invalid: a negative sub-request's targets
   are the negative targets at its value, in target order"). The cost is the
   error-naming change in section 3, which can arise in two ways: an engine
   run against a later classification, and classifications at two invalid
   values.
2. **A search state is built only when something is left to solve**
   (`81c9335`, `_completable`). This was outside the plan. It is what lets the
   counts-only path allocate less, and it changes no node, cache or counter.
3. **The `coverage` error order** in section 3.
4. **`misses` is kept** (Stage B). It is one of a documented five-state
   partition that has an exclusivity test.
5. **The display of an unresolved proof.** Settled: you said the old output
   need not be kept. Every `Followup` line now gives the note in
   parentheses, " (whether each rule is needed is unresolved: …)", both on
   the union's line and in each kind's clause (`9e6c961`, `943790e`). So
   "; " only ever separates clauses. `explain` and the must-include error
   keep their own form, where nothing follows the note.
6. **Stage B extras.** The `matches_from_missing` docstring was rewritten,
   since it described a return value the function doesn't have. A local
   `matches` that shadowed a function was removed. The reference sweep keeps
   the probe's five tables as optional arguments.
7. **The oracle guard is strict.** A docstring or string in
   `test/checker.jl` that mentions the package also fails it.
8. **Tests that reach internals.**
   - Stage E2's test calls `_isolate` with its eight positional arguments,
     because through `followups` a carried limit can't be told apart from a
     rebuilt one.
   - Stage D's agreement test uses `TargetList` and `parent_row`.
9. **Candidates the plan didn't list, left alone.**
   - `build_excursion(arity, …)` (`src/excursions.jl`) is called only by
     tests.
   - `github_matrix` and `realize` read rows their own way and reject vector
     rows.
   - `_print_exclusion` gained a keyword, `parenthesized`, that only
     `diagnose` passes, and always as `true`.
   - `to_cases` (`src/request.jl`) is no longer called from `src/`, since
     `TestCases` builds its rows behind a barrier (section 7); only tests
     call it.
   - `cover_negative` still scans the negative must-include columns once per
     invalid value.
10. **Squash candidates.** Stage A's `5864721` corrects the wording of
    `480d415`. Stage D's `4c89a2d` is a readability-only follow-up to
    `8970047`.

## 6. Not done, and next steps

- **Nothing is pushed and no PR is open.** Decision 6 has Stages A and E1
  going in before 0.5, as PRs stacked on #58 (`feature/phase7-docs`) the way
  the phase PRs are. Stages B to F are ready as later PRs, or as one
  post-0.5 series. Each contract change should go through your review before
  it reaches `release/0.5`: §3.5, §3.8, §3.14, §3.17, §8.6, §12.16 and
  §12.19.
- **For the Phase 8 changelog:** `Followup.proofs` and `FollowupProof`, the
  narrowed §3.8, vector rows in `isallowed` and `explain` (after 0.5 if C
  ships later), and the changed input-error wording.
- **The scratch files** of this work (baselines, probes, logs) are in the
  session's scratchpad, not the repository. The snapshot can be regenerated
  at any commit with `benchmark/snapshot.jl`. A worktree needs a copy of the
  gitignored `Manifest.toml`.

## 7. Type stability

None of the plan's gates tested type stability, so it was audited after the
stack was built. The audit ran JET from a scratch directory: 0.12.2 on
Julia 1.13 and 0.9.18 on 1.10. It also used `@code_warntype` on about 90
method signatures, a scan for `Core.Box`, and profiles. It compared the code
before the plan (`4d9d424`) with the code after it (`5f5d2b3`).

**The stack introduced no hot-path instability.** The runtime-dispatch sites
in the hot code were the same before and after it, on both Julia versions.
The search's inner loops, IPOG, GND's rounds and the measurement walk were
already clean. The audit found seven pre-existing instabilities, and
`feature/stability-and-display` fixes them:

| | Where | Fix | Before → after |
|:--|:--|:--|:--|
| A1 | The tabulated rule check, `forbids` | `RuleTable` is concrete: a `BitVector` over the smallest box that holds the forbidden tuples (`src/rule_table.jl:50`), so a check is arithmetic plus a bit test (`_forbidden_bit`, `:134`). `forbidden_tuples(t)` decodes it for inspection | 20 → 7 ns and 1 → 0 allocations per check; a space with a 64,000-combination rule builds in 0.78 ms instead of 6.8 |
| A2 | The lazy-rule memo, typed `Vector{Union{Nothing, Dict}}` | One concrete `RuleMemo` (`src/feasibility.jl:102`): a `Dict{Vector{Int}, Bool}` looked up through a reused scratch key, so a hit allocates nothing | A scoped check 22 → 12 ns, a whole-case check 48 → 24 ns, 0 allocations |
| A3 | `_LazyRule` and `_evaluate_rule` | `_LazyRule{N, Names, Whole, F, D<:Tuple}` (`src/constraints.jl:389`) holds the predicate and a tuple of domains, so evaluation is concrete behind the one dynamic call on a memo miss. Tabulation goes through the same type, and `_evaluate_rule` is gone | A whole-case miss 617 → 7.5 ns, a scoped one 147 → 3.5 ns |
| A7 | `explain_partial`, `witness` | The witness is narrowed to `Vector{Int}`, which Julia 1.10 doesn't infer from the status | No cost; JET is clean on 1.10 |
| A4 | `from_indices`, which built every NamedTuple with names known only at run time | In measurement, a listed target is named by one `_Named` per support (`src/space.jl:659-674`). `TestCases` builds its rows as their element type behind one barrier (`_cases`, `src/testcases.jl:231`) | A listed target ~1 µs → 0.1–0.16 µs; listing ~2× faster; `full_factorial` of 276,000 rows 459 → ~45 ms |
| A5 | Reading a row's values, one dispatch per value | The space keeps one lookup per parameter, by identity key and by partition name (`_lookup`, `src/space.jl:172`; field `lookup`). A miss falls back to today's comparison, so results and messages are unchanged | An 8-parameter row 337 → 107 ns; `isallowed` on every case of a design 0.27 → 0.06 s |
| A6 | `build_excursion`, product iteration over a tuple whose length is known only at run time | An odometer, as in `full_factorial` (`src/excursions.jl:65-76`) | `excursions` of a 14×5 space at distance 2: 3.96 → 0.61 ms |

**Gates.**
- The snapshot is byte-identical to the one from before the stability work.
- The suite passes on Julia 1.13 and 1.10, and the docs build passes.
- The fingerprint and every benchmark count are unchanged.
- The dispatch sites left on hot paths are deliberate barriers, each hit once
  per operation, not once per step of the inner loop:
  - a lazy-rule memo miss (`src/feasibility.jl:294`);
  - one call per listed target (`src/measure.jl:381`);
  - building a `_Named`, once per support (`src/space.jl:667`);
  - `_cases`, once per result (`src/testcases.jl:231`).

**Guards** are in `test/test_stability.jl`, using only `Test` and Base, as you
decided: no JET in the repository.
- Zero-allocation assertions on the rule check and `_violates`. These fail on
  the old code, because `@inferred` alone can't see a dispatch inside a
  function whose return type still infers.
- Allocation bounds on naming a listed target, reading a row and building a
  result's rows.
- `@inferred` on the search's entry points, `TargetList` and `value_index`.

**Decisions for you.**
1. **Compile latency.** Typing the rules and the domains moves cost from run
   time to compile time:
   - about 2.5 ms per tabulated rule when a space is built (40 rules:
     72 → 171 ms);
   - about 10 ms per lazy rule on first use;
   - about 14 ms per distinct tuple of domain types for `_Named`: +70 ms on
     the first `coverage` of the Fable space, and +550 ms on a space with
     nine domain types at strength 3.

   The alternatives are an untyped tabulation path, which brings back a
   second evaluation routine, and domains held as `NTuple{K, AbstractVector}`,
   which keeps first-call latency at today's level but makes listing 10–15%
   slower and leaves `_values` uninferred.
2. **The memo's key type.** A `Vector{Int}` key has one code path and never
   overflows. An `Int` mixed-radix code is faster on a hit (9.6 against
   11.2 ns over 3 parameters, and 12.9 against 23.7 ns over 10), but a
   whole-case rule over many parameters overflows it, so it needs a second
   path.
3. **The space is bigger.** It holds a value lookup per parameter, roughly
   doubling `summarysize` for small spaces, and it takes 3–15% longer to
   build.
4. **Not stability, but visible in profiles:**
   - Each row read formats a "coverage row k" label (27% of `coverage` of a
     full factorial). `lazy"…"` would remove that.
   - The 17 GB that fixture 1's classic IPOG allocates comes from the
     coverage-matrix code copying columns (`mc.allc[:, col]`). That code is
     concrete; it is simply allocation-heavy.
5. **A lazy table's function now receives a `Vector{Int}`,** which may be the
   memo's scratch key, so it must not keep it. This is internal, and the
   docstring says so.
