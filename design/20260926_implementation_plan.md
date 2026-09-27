# UnitTestDesign.jl 1.0: Implementation Plan

Date: 2026-09-26. Prepared from `interface_synthesis.md` and the decisions
in `20260926_answers.md`. One release, eight phases, a review at the end of
each phase. Every phase ends with the test suite green and the package
usable, so a review can run the code, not just read it.

Revised after the plan review: correctness and wrapper semantics are fixed
in Phase 1; implementation remains in eight phases and one release.

## Decisions carried into this plan

From your answers:

- **Option 3 (the friendly product), plus four picks from Option 4:**
  `diagnose`, `Invalid`, `Partition`, `github_matrix`. Nothing else from
  Option 4: no runner, no outcome files, no `as_code`, no TOML, no
  rolling coverage, no `max_cases`.
- **`disallow` is deleted**, not deprecated. `nothing` never denotes an
  unassigned parameter in user cases; it remains a legitimate domain value.
- **No evidence track.** The case study and mutation analysis wait until
  after this release.
- **The synthesis's leans decide every open question** (its Section
  "Questions the best version must answer"). The ones that shape code:
  - Constraints live in the `TestSpace`; generation calls accept a
    `constraints =` convenience that builds a space.
  - All rule forms compile to one internal `Constraint` (scope, predicate,
    polarity, label), tabulated over the scope. Whole-case predicates are
    allowed as an escape hatch with a documented cost.
  - Exclusions are attributed honestly: a named rule for direct
    exclusions, a deletion search for implied ones, `unknown` when a search
    limit is hit. Never an invented cause.
  - `TestCases{T} <: AbstractVector{T}` preserves domain values and their
    concrete types without numeric promotion. Homogeneous domains have
    concrete field types; heterogeneous domains may use union or abstract
    field types. Since this is 1.0, the positional path changes its return type too
    (`Vector{Vector{Any}}` becomes `TestCases{Tuple{...}}`).
  - `show` computes only bookkeeping; verification and curves live in
    `report` and `coverage`.
  - Deterministic across runs (GND gets a fixed default seed); not
    promised across versions; stable across edits only through
    `must_include`.
  - Outcomes enter only through the pure function `diagnose(cases, passed)`.
  - Julia target is the latest LTS, 1.10, and nothing earlier: `julia = "1.10"`
    in `Project.toml`, CI runs on 1.10 (LTS), 1.13, and the latest release, and
    the code uses 1.10 features freely (package extensions, `Returns`,
    `@NamedTuple`) with no compatibility shims for older versions.
  - Vocabulary: `TestSpace`, `constraints`, `must_include` (alias `seeds`),
    `strength` (alias `n_way`), `stronger`, `TestCases`, `covering` as the
    general entry point (alias `all_tuples`), `coverage`, `explain`,
    `report`, `design_sizes`.

Small choices I made where the synthesis left two names or was silent.
Say so at the Phase 1 review if you want a different one:

| Choice | Pick | Why |
|:--|:--|:--|
| Planning function | `design_sizes` | Fable-led option; the name says what the table contains |
| Realizing a `Partition` at run time | `realize(case; rng)` | Draws are explicit and seeded by the caller, never hidden in iteration |
| Constraints in positional calls | Not supported; use a space | Rules need names; positional users get every other feature |
| `Invalid` values and rules | In a row whose invalid parameter is `p`, rules mentioning `p` are not applied; all other rules still apply | Contract and coverage meaning reviewed in Phase 1; implemented in Phase 6 |
| The 0.4 `seeds`/`n_way`/`wayness`/`all_tuples`/`*_excursion`/`GND(M=)` spellings | Kept one version as deprecated aliases that warn | Cheap, and it keeps registered users compiling |
| `generate_tuples`, `Excursion`, `Counter` | Removed from the public surface | No user-facing purpose once the request is internal |

Branching: merge `fix/gnd-match-condition` to `main` first (its commit
message already says only what it fixes). Then one branch, `release/1.0`,
with one PR per phase into it, and one PR from it to `main` in Phase 8.

## The target, in one screen

```julia
using UnitTestDesign

space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])

cases = all_pairs(space)                     # TestCases{NamedTuple}, 5 cases
explain(space, (solver = :lu, tol = 1e-3))   # infeasible: the two rules together
coverage(handwritten, space)                 # what an existing suite misses
all_pairs(space; must_include = handwritten) # keep them, add a compact set covering the gaps
report(cases)                                # excluded list, bonus coverage, prefix curve
design_sizes(space)                          # cases per strength, before committing
diagnose(cases, passed)                      # ranked suspects after a run (experimental)
github_matrix(cases)                         # JSON for a workflow's include: list
all_pairs([1, 2, 3], ["a", "b"], [1.0, 2.0]) # positional still works; returns TestCases{Tuple}
```

Final layout of `src/` (new files marked):

```
UnitTestDesign.jl   exports, includes
space.jl        *   TestSpace, value identity, Partition and Invalid wrappers
constraints.jl  *   Constraint, forbid/require, @forbid/@require, tabulation
feasibility.jl  *   violates, completable (with witness and limit), classify targets
request.jl      *   internal request: arity, strength, groups, dead(), must_include
combinations.jl     (kept)
coverage_matrix.jl  (kept; dead-partial predicate replaces disallow)
parameter_order.jl  IPOG (kept; three sites use the predicate)
greedy_tuples.jl    GND (kept; progress guarantee, seed, candidates)
excursions.jl       explicit base, distance
full_factorial.jl   incremental enumeration, materialized result, size guard
testcases.jl    *   TestCases{T}, show, Tables-compatible iteration
interface.jl    *   covering, all_pairs..., excursions, full_factorial, deprecations
measure.jl      *   coverage, missing_interactions, report, design_sizes
invalid.jl      *   one-invalid-per-case generation
partition.jl    *   realize
diagnose.jl     *   diagnose, followups
export.jl       *   github_matrix
```

`coverage_set.jl` goes away: the independent checker in `test/` takes over
its role, and `measure.jl` works in value space.

---

## Phase 1: Specification, checker, and scaffolding

Goal: write down the contract everything else is judged against, and put
the tests in place that will fail until the engines keep it.

Steps:

1. **Merge the GND branch to `main`; cut `release/1.0`.** Open one issue,
   "Implicit constraints crash IPOG and hang GND," with Opus's
   os/gpu/driver example, so Phase 3 has something to close.
2. **Write `docs/src/dev/contract.md`.** The six-point semantic contract
   from the synthesis (valid case; feasible combination; every returned
   case valid and every required combination covered; exclusions reported
   and attributed; user code never sees a partial case; `unknown` under
   limits). Add value identity (concrete type and `isequal`, duplicates
   rejected, singleton domains allowed, `nothing` is a value), the
   determinism boundary, must-include ordering, `stronger` validation
   rules, and the "not now" list (runner, outcome files, model inference,
   CLI, serialization framework, solver, shrinking, fixture catalog,
   `as_code`, TOML, `max_cases`). This page is the spec; later phases cite it.
   Resolve these details here, before engine work:

   - **Resource limits.** Feasibility has three states. Generation must
     resolve every target and placement decision or stop with a clear
     resource-limit error; it never returns an uncertified design.
     Measurement and explanation may return `unknown`, and must not claim
     complete coverage or an exact percentage with unresolved targets.
     Document the `feasibility_limit` keyword, its default node budget,
     accounting across component searches, and how to retry with a larger
     budget. Explanation limits are separate: proven infeasibility remains
     proven even if finding a smaller explanation exhausts its budget.
   - **Identity.** Preserve each supplied value and its concrete type in
     storage, rules, results, and coverage keys. For example, `Any[1, 1.0]`
     contains two choices. No promotion may merge them. Identity of
     `Invalid(x)` includes the marker and the wrapped value's type and
     `isequal`; `Invalid(x)` and `x` are distinct choices.
   - **Partitions.** Within a parameter, partition names are unique;
     reject a raw Symbol equal to a partition name to avoid ambiguous rule
     patterns. Rules and coverage see the name; returned cases retain the
     wrapper until explicit `realize`. Nested wrappers are unsupported.
     Realization preserves the tuple or named-tuple shape and makes no
     additional coverage claim about the sampled concrete values.
   - **Negative cases.** Each parameter must have at least one ordinary
     value (a `Partition` counts); reject domains containing only `Invalid`
     values. Ordinary rows satisfy every rule. A negative row contains
     exactly one `Invalid` value at parameter `p` and satisfies all rules
     whose scopes omit `p`. Whole-case rules therefore do not apply to
     negative rows. Only ordinary rows contribute to ordinary coverage;
     report negative coverage separately. Rows violating either applicable
     rule set contribute no coverage.
   - **Negative targets.** For each invalid value at `p`, each requested
     group containing `p` with strength `s` requires every feasible
     `(s-1)`-way combination on the other parameters in that group.
     Feasibility uses the negative-row rules above and ordinary values in
     every other parameter. Union these targets across the base and
     stronger groups. At strength 1, the empty combination requires one
     valid completion per invalid value, if one exists. Report impossible
     negative targets and stop generation on unresolved ones. Groups
     omitting `p` add no negative targets; their ordinary coverage is
     already required of the ordinary design.
   - **Strategy boundaries.** Full factorial enumerates ordinary and
     single-invalid rows satisfying their applicable rules; excursions
     use the same row-validity policy within their distance bound. Neither
     includes multiple-invalid rows. Must-include rows use the same policy;
     partial rows must admit a completion, and keep assigned values intact.
     A partial row without an `Invalid` marker is completed as an ordinary
     row; negative completion must be requested explicitly with the marker.
   - **Honest size claims.** Engines produce compact designs, with no
     minimum-case-count guarantee. Deletion search produces a sufficient
     explanation, labeled inclusion-minimal only when verified; it does
     not promise a minimum-size rule set.
3. **Write the independent checker, `test/checker.jl`.** Value-space, no
   shared code with the engines. `check_design(cases, space; strength,
   stronger)` enumerates the full product for small spaces, computes the
   valid set and the feasible combinations by brute force, and returns
   separate ordinary and negative results with valid rows, missing targets,
   and rejected rows. Implement the Phase 1 policies independently of
   production feasibility and tabulation. Verify the oracle itself against
   hand-enumerated fixtures using plain test data in Phase 1; add an adapter
   for the production space type in Phase 2. It is the oracle for Phases 3–6.
4. **Write the random problem generator, `test/random_problems.jl`.**
   Opus's shape: 3–8 parameters, 2–4 values, 1–4 scoped rules over 2–3
   parameters, half of them written with `!=` or `<`. A `@testitem` runs
   500 pairwise and 500 three-way problems through IPOG and GND, scaled by
   `test_run_multiplier()`, with a fixed seed and `seed_mod()`. Record
   a narrowly scoped expected failure for the known legacy engine defect;
   keep future-API tests explicitly pending until their phase. Do not mask
   arbitrary exceptions as expected failures. The random gate is mandatory
   in Phase 3. Add a deterministic fixture inventory for disconnected
   unsatisfiable components, exhausted limits, heterogeneous values,
   partial seeds, overlapping stronger groups, and wrapper interactions.
5. **Bump `Project.toml`** to `1.0.0-DEV`, `julia = "1.10"` (the latest LTS;
   nothing earlier is supported). Set the CI matrix to `'1.10'`, `'1.13'`,
   and `'1'`, replacing the `lts` alias so the floor is explicit. Add `.DS_Store`, `Manifest.toml`, `.vscode/`
   to `.gitignore`. Move `interface_*.{md,pdf,tex}`, `interface_synthesis.*`,
   `z3_example.jl`, and the two dated files into `design/` so the root is clean.
6. **Check registered dependents** on JuliaHub and record the result in
   the Phase 8 release notes draft. This is the only input to whether the
   positional return-type change needs an announcement beyond the changelog.

Acceptance gate: review the contract, deprecation list, fixture inventory,
and dependent-package findings. Run the checker against hand-enumerated
ordinary and negative examples and run the existing suite. List pending
tests with their activation phase; only the known legacy regression is an
expected failure. Record benchmark fixtures, hardware/runtime metadata to
collect, and the measurement procedure for Phase 3.

---

## Phase 2: The model: `TestSpace`, rules, feasibility

Goal: a pure, engine-independent layer that answers every question about a
space. No generation yet. Everything here is testable by hand.

Steps:

1. **`TestSpace`** (`space.jl`). Constructors: `TestSpace(nt::NamedTuple;
   constraints)` and `TestSpace(pairs::Pair{Symbol}...; constraints)`.
   Validation with messages in the user's vocabulary: names distinct;
   each domain nonempty and ordered; duplicate values rejected by concrete
   type and `isequal` ("parameter `tol` lists `1.0` twice"). Fields:
   `names`, `values` (a tuple of vectors), `constraints`, and the tabulated
   tables from step 5. Copy domains without promoting their values.
   Accessors: `parameters(space)`, `arity(space)`,
   `Base.length` is the full product (as `BigInt`-safe `prod`).
2. **`Invalid(x)` and `Partition(name, draw)` wrappers** are defined here
   using the Phase 1 identity and collision rules. A rule or pattern sees
   a partition's name (a `Symbol`). Validate domains and wrappers now;
   implement negative-row rule selection in the model so feasibility and
   measurement share it. Generation and realization arrive in Phase 6;
   until then generation on wrapper spaces fails with an explicit
   unsupported-feature error rather than applying ordinary semantics.
3. **`Constraint`** (`constraints.jl`): `scope::Tuple{Vararg{Symbol}}`,
   `predicate`, `polarity` (`:forbid`/`:require`, kept for display; both
   normalize to "forbidden combinations" at tabulation), `label` (reason
   and/or source text). Constructors:
   - `forbid(pattern::NamedTuple; reason)` — exact partial assignment.
   - `forbid(names::Symbol...; reason) do values... end` and the same for
     `require`.
   - `forbid(f; reason)` with no names is the whole-case escape hatch: `f`
     receives the complete case as a `NamedTuple`.
   Construction errors name the parameter and list the space's names.
   A predicate that returns anything but `Bool` is an error; an exception
   thrown by a predicate is rethrown with the rule's label and arguments.
4. **`@forbid` and `@require`.** Fable's design: free identifiers that are
   not in call position are parameter names; `$x` interpolates from the
   caller; the source text is kept. The unknown-name error suggests
   `$name` if a variable was meant. The macros produce the same
   `Constraint` as step 3, so nothing downstream knows they exist.
5. **Tabulation.** For each rule, evaluate once per combination of its
   scope's domains and store the forbidden index tuples in a `Set`. Above
   a threshold (default 10^5 evaluations, configurable) evaluate lazily
   with a memo and warn once, suggesting a narrower scope. Whole-case
   rules are always lazy. Tabulation order is fixed so reports are stable.
   Evaluate ordinary values (partition names included); negative-row
   checks select only tables whose scopes omit the invalid parameter.
6. **Feasibility** (`feasibility.jl`). `violates(partial_idx)` fires only
   when a rule's whole scope is assigned. `completable(partial_idx; limit)`
   is backtracking with forward checking that returns `(true, witness)`,
   `(false, nothing)`, or `:unknown` when `limit` nodes are exceeded.
   Solve every constrained connected component, including components with
   no assigned parameter. Cache witnesses for independent components and
   combine them into a complete witness; only unconstrained parameters may
   be filled freely. An unsatisfiable component makes the whole completion
   infeasible. Memo keys include the assignments and active rule set, so
   negative rows, deletion searches, and diagnosis cannot reuse stale
   answers. Never cache an exhausted search as infeasible.
   `classify(space, targets)` labels each target combination `required`,
   `forbidden` (which rule), `implied` (a proven sufficient rule set found
   by deletion search), or `unknown`. Claim inclusion-minimality only if
   every remaining rule is verified necessary. If explanation search hits
   its limit, retain the last proven sufficient set and mark minimality
   unresolved; target feasibility and explanation quality are separate.
7. **`isallowed(space, case)` and `explain(space, partial)`.** Five
   outcomes: `allowed`, `forbidden` (with the rule), `completable` (with a
   witness), `infeasible` (with rules), `unknown`. The result prints a
   sentence and carries fields.
8. **Tests** (`test/test_space.jl`, `test_constraints.jl`,
   `test_feasibility.jl`): Astra's `A == B`, `B == C` example; Fable's
   solver example (3 direct, 2 implied, listed by name); Opus's
   os/gpu/driver example; `nothing` as a real value; the `!=` rule that
   silently over-forbade in 0.4 now forbids exactly two pairs; the macro
   error message; the threshold warning; `unknown` with `limit = 1`;
   determinism of tabulation order. Add fixtures where the assigned
   parameter is unconstrained but a separate component is unsatisfiable,
   where two satisfiable components need non-default witness values, and
   where a whole-case predicate connects them. Check type-preserving
   identity, wrapper collisions, active rule sets, and retries after limits.

Acceptance gate: all model tests and the full suite pass. Review executable
examples of all rule forms, the solver example's 3 direct and 2 implied
exclusions, the disconnected-component fixtures, and `unknown` followed by
a successful retry. Inspect witness validity and explanation status fields.

---

## Phase 3: Engines that keep the promise

Goal: IPOG and GND return certified designs or clear errors, terminate under
configured limits, and remove `disallow`. Random problems go green.

Steps:

1. **Internal request** (`request.jl`). One struct the engines consume:
   `arity`, `strength`, `groups` (index tuples with their strength, base
   group included), `dead(partial_idx)::Bool` (true only for proven
   infeasibility, false only with a completion witness; throws a
   resource-limit error on `unknown`), `must_include` as an index matrix
   with `0` for unset, the feasibility budget and run-local memo, and
   the classified target list from Phase 2. One entry point,
   `generate(engine, request)`, returns the index matrix plus bookkeeping:
   which targets were covered, how many rows came from `must_include`,
   and the engine's seed. All target classifications must be resolved
   before a result is returned. Validate feasibility of the whole space
   even when there are no targets; a proven empty space returns an empty
   design unless must-include requirements make the request impossible.
2. **IPOG.** Replace `disallow` at the three sites
   (`choose_last_parameter_filter!`, `insert_tuple_into_tests_filter`,
   `fill_remaining_missing_values_filter!`) with `dead`. Because every
   site commits a value only when the row stays completable, the
   completability invariant holds by induction; the initial combinations
   and each pushed tuple are completable because the feasibility pass
   removed the rest. The unconstrained `ipog` fast path stays. In
   `ipog_multi_way`, copy the groups, accept ranges and tuples, and treat a
   group at the base strength as a no-op instead of asserting.
3. **GND.** `allowed_argmax` uses `dead`. Progress guarantee: if no
   candidate in a round covers anything, build one directly from the
   first uncovered target with a stored or newly proven witness, so the
   `error("Could not construct...")` path and the attempt cap go away.
   `GND(; seed = 0, candidates = 50, rng = nothing)`: a fixed default
   seed, `M` accepted with a deprecation warning, the seed recorded in the
   result. Exhausting a witness-search budget raises the same resource-limit
   error; it never drops the target or retries indefinitely.
   `n_way_coverage_init` and the instrumented IPOG variant are
   deleted if no test uses them.
4. **Excursions.** `build_excursion(arity, distance, base_idx, dead)`
   with an explicit base; rows that are dead are dropped and *reported*
   in the bookkeeping (which values never appear); a forbidden base is an
   error naming the rule.
5. **Full factorial.** Enumerate candidates incrementally and retain only
   accepted rows; the public return remains a materialized `TestCases`.
   There is no lazy public result in this release. Before enumeration,
   refuse a candidate product above `limit = 10^6`, giving its count;
   report candidate and accepted counts separately. Phase 6 extends the
   count to the ordinary product plus all single-invalid products.
6. **Final validation** inside `generate`: every row complete, every row
   passes every applicable rule (including lazy predicates), no target
   classification remains unknown, and every required target is covered.
   Validate against the requested strategy: covering targets, excursion
   distance, or full-factorial completeness. Phase 6 validates ordinary
   and negative coverage separately. A limit raises a resource-limit error;
   an invariant failure raises an internal error naming the row or target.
7. **Delete** `wrap_disallow`, the `disallow` keyword, `Counter`,
   `seeds_to_integers`' sentinel handling, and documentation of `nothing`
   as a partial-assignment sentinel; retain examples using it as a real
   value. Single-valued parameters are allowed; a strength
   larger than the parameter count is an `ArgumentError`; equal to it is
   a full factorial under the applicable row policy.
8. **Turn on the random problems.** Both engines, both strengths, every
   result checked by `test/checker.jl`. Close the Phase 1 issue.
9. **Performance baseline.** Benchmark 15 four-valued parameters at
   strength 4 and a checked-in fixture for Fable's 12-parameter constrained
   example. Record Julia version, hardware, thread count, engine seed,
   compilation policy, allocations, and median of repeated warm runs;
   report cold-start compilation separately. Measure the prior revision
   on fixtures it handles correctly, and establish a baseline for repaired
   constrained cases. Use stable CI runners to set an explicit regression
   tolerance from observed variation. Ordinary correctness tests assert
   completion and coverage, not machine-dependent seconds. Include limit
   exhaustion and progress regressions in the deterministic suite.

Acceptance gate: all 1,000 random problems pass for each engine at the
full multiplier, targeted regressions pass, and the full suite is green.
Review the benchmark command, environment, before/after results, and chosen
regression tolerance, plus the removal of `disallow`. Demonstrate that a
limited search raises an error rather than returning an incomplete design.

---

## Phase 4: The public interface and the result type

Goal: the 1.0 surface, with the old spellings deprecated and every
existing test rewritten against it.

Steps:

1. **`TestCases{T} <: AbstractVector{T}`** (`testcases.jl`). Fields:
   `cases::Vector{T}`, `space`, `strategy` (`:covering`, `:excursion`,
   `:full_factorial`), `strength`, `stronger`, `engine` (name and seed),
   `n_must_include`, `excluded` (direct with rule labels, implied with
   rules and explanation status), and `covered` (count of required targets,
   from bookkeeping). Generated designs have no unknown target status;
   analysis results may. Keep separate ordinary and negative bookkeeping
   as specified in Phase 1. `T` is a `NamedTuple` type for named spaces and
   a `Tuple` type for positional calls. Preserve domain values and their
   concrete types without conversion. Homogeneous domains use concrete
   field types; heterogeneous domains may use union or abstract field types.
   `Any[1, 1.0]` must remain two distinct choices through generation,
   collection, rule evaluation, and coverage. `collect` gives a plain vector.
2. **`covering(space; strength = 2, stronger = [], must_include = [],
   engine = IPOG(), constraints = [])`** (`interface.jl`), with
   `all_values`, `all_pairs`, `all_triples` as fixed strengths. Each
   accepts a `TestSpace`, a `NamedTuple` of domains, `Symbol => values`
   pairs, or bare positional vectors (which build a space named
   `p1, p2, ...` and return tuples). `constraints =` on named domain input
   builds the space; on a `TestSpace` it is an error ("constraints belong
   to the space"). Expose the Phase 1 `feasibility_limit` on generation
   and analysis entry points, and document resource-limit errors and retry.
   Positional calls reject `constraints =`; use a named space for rules.
3. **`must_include`.** Named: `NamedTuple`s, partial allowed, an existing
   `TestCases` accepted. Positional: tuples or vectors. Validated by name
   and value before generation with messages that name the case, the
   parameter, and the offending value; a case violating the applicable
   row policy is an error. A partial case must have a proven completion;
   after Phase 6, a partial case containing `Invalid` uses the negative-row
   policy. Limit exhaustion is distinct from an infeasible must-include.
   Must-include cases come first, in the order given; duplicates kept.
   `seeds` accepted with a deprecation warning.
4. **`stronger = [(:a, :b, :c) => 3]`** validated per the contract: names
   exist, distinct within a group, group strength at least the base
   and at most the group size, overlapping groups combine by union, the
   caller's vector untouched. A group at base strength is a no-op, matching
   Phase 3. Positional: `[(1, 3, 4) => 3]`. `wayness`
   accepted with a deprecation warning and translated.
5. **`excursions(space; from = nothing, distance = 1, must_include)`**
   and `full_factorial(space; limit)`; `values_excursion`,
   `pairs_excursion`, `triples_excursion` kept as thin aliases. The
   docstring for `excursions` states its promise (within `distance` of
   the base) and that it is not a covering guarantee.
6. **`show(io, ::TestCases)`.** One summary line ("5 cases · strength 2 ·
   IPOG · 3 parameters · 12 combinations, 5 valid" when the valid count
   is cheap, otherwise just the product), then "excluded: 3 pairs
   forbidden, 2 impossible under the constraints; see
   report(cases)", then an aligned table truncated like a `DataFrame`.
   Nothing is computed at display time that generation did not already know.
7. **Tables.** A vector of `NamedTuple`s already satisfies Tables.jl's
   row-table interface; add a test that `DataFrame(cases)` and
   `CSV.write` work (both are already test dependencies).
8. **Deprecations and removals.** `all_tuples`, `n_way`, `seeds`,
   `wayness`, `GND(M=)` warn once via `Base.depwarn`. `generate_tuples`,
   `Excursion`, `Counter` removed. `disallow` is not a keyword anywhere;
   passing it hits the ordinary unknown-keyword error.
9. **Rewrite existing tests** (`test_factorial_interface.jl`,
   `test_excursions.jl`, `test_full_factorial.jl`, `nonfunctional.jl`,
   `cli.jl`) against the new surface. Add deterministic tests for
   heterogeneous domains, partial and duplicate must-includes, overlapping
   stronger groups, and preservation of caller-owned inputs. Aqua stays green.

Acceptance gate: run generation, explanation, and display examples from
the target screen (measurement and add-on calls remain pending until their
phases). Review the transcript and deprecation warnings; confirm typed-value
preservation, Tables interoperability, targeted regressions, Aqua, and the
full suite pass. Display must perform no feasibility searches.

---

## Phase 5: Measure and explain: `coverage`, `report`, `design_sizes`

Goal: the claim is checkable in one line, and the package says what it
promised, what it left out, and what a design would cost.

Steps:

1. **`coverage(cases, space; strength = 2, stronger = [])`**
   (`measure.jl`), for any iterable of `NamedTuple`s (or tuples for a
   positional space), independent of the generator's bookkeeping.
   Returns a `Coverage` with `covered`, `feasible`, `missing` (named
   combinations), `unknown`, and a per-group breakdown. Separate ordinary
   and negative coverage according to Phase 1; rows violating their
   applicable rules contribute nothing and are listed; duplicates count
   once. Negative rows never increase ordinary coverage. Implement the
   result structure now and activate wrapper inputs in Phase 6.
   `coverage(cases::TestCases)` reads the space and request from the
   result. `coverage(cases::TestCases)` measures at `cases.strength` and
   `cases.stronger`; for a result whose strength is 0 (an excursion or a
   full factorial) it is an `ArgumentError` asking for `strength =`, and
   `report(cases)` on such a result measures at strength 2 and says so in
   its guarantee line. Prints "covers 11 of 11 feasible pairs" or the
   missing list when classification is resolved. With unknown targets,
   report known counts and unresolved targets without an exact percentage
   or completeness claim.
2. **`missing_interactions(cases, space; ...)`** returns
   `coverage(...).missing` when classification is resolved; otherwise raise
   a resource-limit error directing the caller to `coverage` for the known
   missing and unresolved targets. An empty list must not hide uncertainty.
3. **`report(cases::TestCases)`**: the guarantee line, the excluded list
   with attribution, bonus coverage at strength+1, the prefix curve
   ("first 5 of 10 cover 73%"), and the seed. Returns a `Report` whose
   fields serialize; printing is the display. This is where the
   verification Astra keeps out of `show` happens. Apply the same unknown
   policy to bonus coverage and prefix curves. When no strength+1 targets
   exist, mark bonus coverage not applicable.
4. **`design_sizes(space; strengths = 1:3, distances = 1:2)`**: one row
   per strategy with the case count, share of the valid product, and
   pairs and triples covered, computed by running IPOG per strength. Full
   factorial reports total and valid counts when the product is below
   the Phase 3 limit, otherwise the total only. Omit shares when the valid
   count is unknown; report a strategy's resource-limit status rather than
   an invented case count. Skip strengths exceeding the parameter count.
5. **Top-up and extend as recipes**, tested but not new functions:
   `all_pairs(space; must_include = existing)` and
   `all_triples(space; must_include = cases)`. A test asserts that the
   existing cases survive in order and that the result is complete.
6. **Tests**: `coverage` of hand-written cases against the checker;
   `coverage` of every generated covering design is complete; `report` numbers
   agree with the checker on the random problems; `design_sizes`
   reproduces Fable's 10-of-81 example. Test limit exhaustion in coverage,
   missing-interaction queries, bonus reports, and planning; verify that
   unresolved denominators never print as exact percentages.

Acceptance gate: review checked outputs for the solver example, a
hand-written suite with gaps, and a limited search with unresolved targets.
Run audit/top-up/extend examples and compare their results to the independent
checker. All measurement tests and the full suite pass.

---

## Phase 6: `Invalid`, `Partition`, `diagnose`, `github_matrix`

Goal: implement the four Option 4 features using the Phase 1 contract,
with matching docstrings and `diagnose` labeled experimental.

Steps:

1. **`Invalid(x)`** (`invalid.jl`). Generation: the covering design is
   built over valid values only; then, for each invalid value `v` of
   parameter `p`, build the negative targets specified in Phase 1 for the
   base and all stronger groups containing `p`. Generate completions over
   the other parameters' ordinary values under the applicable rules, then
   insert `p = v` at its original parameter position. At strength 1, use
   one witness for the empty target; do not call a strength-0 public API.
   Pairwise generation pairs the invalid value with every feasible ordinary
   value of every other parameter. Report infeasible targets and stop on
   unresolved feasibility, exactly as for ordinary generation. The
   case keeps the wrapper (`n = Invalid(-1)`) so a test body can branch
   on `hasinvalid(case)`; `show` marks the rows; `report` and `coverage`
   state the two guarantees separately. Rules mentioning `p` are not
   applied in rows where `p` is invalid. Activate wrapper support in
   generation, must-includes, full factorial, excursions, and measurement,
   removing the temporary unsupported-feature errors from Phase 2.
2. **`Partition(name, draw)`** (`partition.jl`). Coverage is over names.
   `realize(case; rng)` preserves tuple or named-tuple shape, substituting
   `draw(rng)` for each partition; `realize(cases; rng)` maps over the vector. A
   fixed-value label is `Partition(:tiny, Returns(1e-9))`. Nothing is
   inferred from a function-valued domain; only the wrapper triggers this.
   Preserve `Invalid` markers and ordinary values during realization;
   nested wrappers remain rejected. Coverage is measured on the original
   labeled cases, so callers retain those alongside realized inputs.
3. **`diagnose(cases, passed::AbstractVector{Bool}; strength)`**
   (`diagnose.jl`). For sizes 1 to `strength`, list combinations present
   in at least one failing case and no passing case; rank by failures
   containing them, then by size, with a deterministic tie-break. Include
   pass/fail counts and group candidates with identical observed occurrence
   patterns as observationally indistinguishable. Every candidate is
   unverified by passing cases; do not add a redundant "masked" flag.
   Validate outcome length and handle no failures, all failures, and
   conflicting outcomes for duplicate cases explicitly.
   `followups(diagnosis)` attempts to find a valid case containing each
   suspect and no other suspect using the Phase 2 witness search with
   temporary forbidden tables. These isolation conditions always apply,
   including when they mention an invalid parameter. Return per-suspect
   status: `found` with a
   witness, `inseparable` with a proven explanation, or `unknown` when the
   search limit is exhausted. Nested suspects and constraints may make
   isolation impossible. Prefer small changes from a failing case as a
   heuristic, with no minimum-distance guarantee. Use the appropriate
   ordinary or negative row policy; distinguish observational equivalence
   from proven inability to isolate a suspect. Docstrings
   say: experimental; hypotheses, not proof; multiple faults and
   intermittent failures can confuse the ranking.
4. **`github_matrix(cases; io = stdout)`** (`export.jl`). Emits
   `{"include": [...]}` using an established JSON encoder added as an
   explicit dependency. Accept named rows with strings, finite real numbers,
   booleans, and `nothing` (JSON null); encode Symbols as strings.
   Reject unsupported values, non-finite numbers, and wrappers with a
   message naming the row and field; callers explicitly map those values
   to supported data first. Validate all rows before writing to `io`.
   Warns above 256 jobs. The docstring shows the workflow YAML that reads
   it with `fromJSON`.
5. **Tests**: check ordinary and negative guarantees with the independent
   oracle, including strength 1, mixed strengths, infeasible negative
   targets, wrapper collisions, and invalid-only domain rejection.
   Verify `realize` determinism under a seeded `Xoshiro` and preservation
   of positional shape. Opus's newton/sparse example checks ranking and
   every follow-up that can be isolated; nested and constrained suspects
   exercise `inseparable` and limited searches exercise `unknown`.
   Parse exported JSON and compare values, including quotes, backslashes,
   control characters, Unicode, nulls, empty results, and rejected
   unsupported/non-finite values. Do not rely only on a fixture string.

Acceptance gate: run all four feature examples and the complete target
screen. Review separate ordinary/negative coverage, realization output,
diagnosis statuses for found/inseparable/unknown cases, and parsed matrix
JSON. Wrapper integration tests, targeted regressions, and the full suite
pass with no wrapper feature tests pending.

---

## Phase 7: Documentation and first contact

Goal: a README that leads with the situation, a manual organized as
tutorial, how-to, explanation, and reference, and every example a doctest.

Steps:

1. **README first screen**: the promise sentence ("Describe the
   configurations your code must handle; it tells you which combinations
   your tests exercise, and supplies a compact set of additional cases
   covering the rest"), Fable's decision table with Opus's three "use something else"
   rows, one named example with its printed summary, install line.
2. **Tutorial** (`man/tutorial.md`): Fable's levels 0–4 in order, each
   adding one concept, ending with `coverage` and `report`.
3. **How-to guides**, one page each, by job: test a function with many
   options; test generic code across types (the Julia-specific pitch);
   plan a CI matrix with `github_matrix`; run a simulation campaign;
   audit and extend an existing suite (`coverage`, `must_include`);
   diagnose a failure; test invalid inputs (a second space *and*
   `Invalid`, side by side); combine with property-based testing
   (`Partition`, and the no-API pattern); commit a design as data (the
   lockfile pattern using `repr(collect(cases))` plus one `coverage` test).
4. **Explanation**: choosing values and oracles, moved from the paper's
   "How to Use"; interaction coverage and what the evidence shows,
   including the random-at-equal-budget formula; the constraint
   semantics in plain words; engines page corrected (GND is shorter only
   at high arity; deterministic vs seeded); IPOG page kept.
5. **Reference**: autodocs, with every exported docstring beginning
   with the situation it serves ("Use when..."). Deprecated names
   documented in a migration table (0.4 → 1.0), including the deleted
   `disallow` and how to rewrite it as a rule.
6. **Developer pages**: the contract from Phase 1, non-goals, contributing.
7. **Agent one-pager** (`docs/src/man/agents.md`, also linked from the
   README): the decision rule, three canonical patterns, and the
   one-line check (`coverage`).
8. **Doctests on.** `DocMeta.setdocmeta!` and `doctest = true` in
   `docs/make.jl`; a `@testitem` runs `Documenter.doctest` in the test
   suite so CI fails on a stale example.

Acceptance gate: build rendered docs (`julia --project=docs docs/make.jl`)
and run doctests and the full suite. Review the README, migration table,
and examples for limits, negative coverage, and unresolved diagnosis.
Check that no example promises a minimum case count, minimum explanation,
or unconditional follow-up isolation.

---

## Phase 8: Release 1.0

Steps:

1. Full matrix green (1.10, 1.13, latest release, three OSes), Aqua,
   doctests, deterministic regressions, the full random-problem gate, and
   benchmark results within the Phase 3 tolerance on the documented runner.
2. `CHANGELOG.md` for 1.0.0: breaking changes (return type, `disallow`
   removed, `Counter` removed), deprecations with their replacements, new
   API, the constraint fix with the issue number.
3. Set `version = "1.0.0"`; prepare PR `release/1.0` → `main` with the
   validation results and rendered documentation. Keep it unmerged for review.
4. Draft a short Discourse announcement (the promise sentence, the
   decision table, the constraint fix) for you to post or not.
5. **Pre-publication acceptance gate.** Review the changelog, release PR,
   final CI results, benchmark report, and announcement draft. The user's
   Phase 8 review must approve release before merge or registration.
6. **After approval:** merge the release PR, register with
   `@JuliaRegistrator register` on the merge commit, and verify that TagBot
   tags and docs deploy to `stable`. Report the released version and URLs;
   the Discourse announcement remains a draft for you to post or not.

Completion check: registration, tag, and stable docs correspond to the
approved release commit. Surface any external automation failure explicitly.

---

## Order of work inside a phase

Execute each phase through its acceptance gate, then present its concrete
artifacts for the user's review before beginning the next phase. Session
count is an estimate, not a completion criterion. For behavior changes,
write or update focused `@testitem`s and run them as each step lands. Run
the full suite (`julia --project -e 'using Pkg; Pkg.test()'`) at the phase
gate, and earlier when integration changes warrant it; avoid a full-suite
run after every small edit. Commit coherent changes with their checks.
Each review includes the phase PR, commands and results, example outputs,
and any explicitly pending tests assigned to a later phase. No tests remain
pending at release. If implementation conflicts with the contract, retain
the contract and raise the concrete conflict at review; do not silently
change the semantics to make a test pass.
