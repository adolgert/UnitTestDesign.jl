# UnitTestDesign.jl: Secondary plan after the components review

Date: 2026-09-28. Prepared from `design/components_review.md` (the external
architecture review) and `design/components_review_verification.md` (its
claim-by-claim verification, with probes in `design/components_review_probes/`).
Branch state: `feature/phase7-docs` at `4d9d424`, Phase 7 complete,
`release/0.5` exists, Phase 8 (release) not started. The line numbers refer
to the tree at `4d9d424`.

Revised 2026-09-28 after the plan review, and again 2026-09-30 after a
readiness check that opened every anchor and asked, for each step, whether
it could be built without a question. The 2026-09-30 revision:

- records the seven decisions as made, all as recommended;
- corrects decision 1's account of why the exclusion record depends on
  `feasibility_limit`, and adds the contract sentence that says so (Stage A
  step 1);
- gives Stage A step 2 the contract sentences it needs, since §3.5 and
  §12.19 name `classify`, not `coverage`;
- defines what `Followup.proofs` holds for every status, and gives `show` a
  concrete format that never presents a union as minimal (Stage E1);
- fixes Stage B's test ranges, its `matcher` instruction and its grep gate,
  and keeps `misses`;
- makes Stage C's row reader, memo scope and counts-only path concrete;
- records two Stage D blockers, with a recommendation for each, to settle
  before Stage D starts;
- adds one before/after snapshot script for Stages C, D and E2, because the
  benchmark fingerprint cannot see what those stages promise not to change;
- corrects about a dozen anchors;
- adds a map of the structure the plan leaves behind, at the end, for
  learning the code afterwards.

The aim, beyond fixing what the review and its verification found: each
stage leaves one owner for one concern. Where a fix had a simpler and a
more elaborate form, this revision takes the simpler one.

## What the verification changed about the review

The review's structure holds and none of its claims is fabricated. The
priorities shift:

- **Sections 5, 6 and 7 (cleanup) are accurate and low risk.** Section 5 has
  more to delete than the review lists. Section 6's shared core already
  exists (`case_indices`), so the helper is a 20-line wrapper. Section 7 is a
  file move of an already sealed region.
- **Section 4 is the one place where documentation is false today.** The
  `followups` docstring promises minimality without the per-kind qualifier
  its own field doc carries, and the reproduced case shows why that matters.
- **Section 1's substance is the negative sub-request projection**, not a
  general layer. Rule policy already has one owner (`active_rules`); what is
  repeated is the hand assembly of searches, and what is fragile is
  `_negative_request`, which can fail silently.
- **Section 2's substance is duplicated target ordering and negative-target
  enumeration**, not `Request`'s field list. Measurement never uses
  `TargetList` or `Request`.
- **Section 3 is sound but modest.** The larger avoidable cost is that the
  bonus and size measurements compute and discard full lists and
  explanations.
- **IPOG consolidation should not happen in this plan.** The classic and
  constrained cores produce different designs, and the constrained core was
  slower in the one high-strength run.

## Decisions (made 2026-09-30)

All seven recommendations were accepted.

1. **Contract §3.8 and the exclusion record.** §3.8 is narrowed to what
   does not depend on the limit: the rows, their order, the counts, and
   which targets are excluded with which status. Which sufficient rule set
   an implied exclusion names, and its `minimal` and `limit`, may depend on
   both limits, and the contract says why (Stage A step 1).

   The mechanism: the deletion search (§3.14) runs one trial per rule, and
   each trial's search is capped at `feasibility_limit` or at what remains
   of `explanation_limit`, whichever is smaller
   (`src/feasibility.jl:684`). A smaller `feasibility_limit` can stop a
   trial that would have dropped a rule, and an earlier trial that ends
   unknown keeps its rule, so a different, unverified set survives. Probe
   `08a`: `rules = [2, 3, 4, 5, 6, 7]`, `:verified` at the default limit;
   `rules = [1]`, `:unresolved`, `limit = :feasibility_limit => N` at
   limits 6 through 14. The earlier revision said a limit-independent
   record would mean giving up the deletion search. That was wrong: bounding
   trials by `explanation_limit` alone would also do it, at the cost of an
   exception to §3.3's "bounds each search" and of the behavior pinned at
   `test/test_feasibility.jl:398-400` and `test/test_diagnose.jl:333-335`.
   Not chosen.

   A related observation, no action: the deletion search, in rule order,
   kept a six-rule explanation where a one-rule one exists. §8.5 permits
   this. Changing the deletion order would change every explanation.
2. **`followups` minimality stays per kind of case.** `Followup` gains
   `proofs`, one `FollowupProof` per kind searched, so a reader can see
   which rules and suspects each kind's proof needs. The union fields keep
   their meaning and today's values. `show` prints the per-kind proofs
   whenever they differ, so it never presents a union as if it were minimal
   (Stage E1). Not chosen: a global deletion pass over the union.
3. **Classification is shared at the index level.** `IndexClassification`
   and `_STATUS_OF_OUTCOME` (`src/feasibility.jl:717-731`) become the one
   owner of the mapping from a search outcome to a status. `Classification`
   (the unexported `classify`), `Excluded` (generation,
   `src/request.jl:439-445`) and `Exclusion` (measurement,
   `src/testcases.jl:31-38`) are records built from it. A feasibility-only
   entry serves counting. `_classify_one` (`src/explain.jl:380-393`)
   already works this way and is the model. Stage C step 3. Not chosen:
   deleting `classify(space, ...)` and `Classification`.
4. **Observations with two `Invalid` values in `diagnose` are accepted,
   ranked and documented** (Stage A step 4), since §8.6 says `diagnose`
   returns hypotheses about what was observed. Tested at
   `test/test_diagnose.jl:344-368`. Not chosen: rejecting them like
   `must_include`.
5. **`isallowed` and `explain` accept vector rows**, through the one row
   reader (Stage C step 1). This widens the accepted input of two public
   functions after 0.5. Not chosen: documenting the difference.
6. **Sequencing.** Stages A and E1 go before the 0.5 release PR, because
   0.5 publishes the contract and the result types. Stage B goes before 0.5
   if time allows, otherwise after. Stages C, D, E2 and F go after 0.5.
   Branches: the phase PRs are stacked (#52 targets `release/0.5`; each
   later phase targets the one before; #58 is Phase 7 on
   `feature/phase7-docs`). Stages A and E1 stack on `feature/phase7-docs`
   the same way and reach `release/0.5` with the stack.
7. **Stage C's cache policy.** Within one `report` or `design_sizes` call,
   the measurements share prepared rows and the lazy-rule memo
   (`FeasibilityContext.memos`, `src/explain.jl:24`), and each measurement
   keeps its own answer cache (`FeasibilityContext.searches`, `:23`). A
   shared answer cache could change a figure when `feasibility_limit`
   binds: `_completable` stores each solved component's witness before a
   later component of the same query ends unknown
   (`src/feasibility.jl:440-449`), so a second measurement sharing that
   cache has more budget left and can resolve a target the first left
   unknown. With separate answer caches every measured figure stays
   identical under any limit. The predicate-call saving is still complete,
   because within measurement a lazy predicate runs only on a memo miss
   (`src/feasibility.jl:270-275`). Not chosen: sharing whole contexts and
   documenting the refinement.

## Stage A: make the documentation true (before 0.5)

Goal: every promise in the contract, the docstrings and the explainer pages
matches what the code does today, and each reworded promise has a test that
would fail if the code contradicted it. Wording and tests only, plus one
renamed local variable. Follow-up proof semantics are the one exception:
they ship with their field in Stage E1.

Steps:

1. **Contract §3.8, §3.14, and the two limit keywords.** Per decision 1.
   - §3.8 (`docs/src/dev/contract.md:318-321`), replacing its last
     sentence: "Two successful generation calls that differ only in
     `feasibility_limit` return the same rows in the same order, the same
     `required`, `covered`, `negative_required` and `negative_covered`
     counts, and exclude the same targets with the same status. An implied
     exclusion's explanation may differ: which sufficient rule set it names,
     its `minimal`, and its `limit` depend on both limits (§3.14)."
   - §3.14 (`contract.md:350-353`), a new last sentence: "Each trial is a
     search bounded by `feasibility_limit` and by what remains of
     `explanation_limit`, whichever is smaller. A trial stopped by either
     keeps its rule, and the explanation's `limit` names the keyword that
     stopped it."
   - `feasibility_limit` in `src/interface.jl:361-362`: "a larger value
     never changes the rows of a result that already succeeded, though an
     implied exclusion's explanation may differ (§3.8)."
   - `explanation_limit` in `src/interface.jl:363-368`: an unresolved
     explanation's `limit` is `:explanation_limit => N` when the deletion
     budget ran out and `:feasibility_limit => N` when a trial reached the
     feasibility limit (`src/feasibility.jl:678, 692`).

   Test: the probe `08a` scenario as a `@testitem`, at the default limit
   and at `feasibility_limit` 6, 10 and 14. Assert that the rows, the four
   counts, and the excluded targets with their statuses are equal across
   limits. For each implied exclusion, check that its rules are sufficient
   by brute force: build `TestSpace(domains; constraints =
   space.constraints[e.rules])` and check that every row of its product
   that holds the target is disallowed. (`isallowed` takes no rule subset,
   `src/explain.jl:139`.) Do not assert that the rule sets are equal. The
   readiness check ran this at limits 6, 14 and 10^6, and it passes.
2. **The memo promise.** Today a lazy-rule memo lives for one operation,
   and `report` and `design_sizes` run several (probe `03a`: `report` made
   12 predicate calls on 8 distinct assignments). The constraints page
   (`docs/src/explain/constraints.md:249-252`) says the memo lasts the whole
   call for "a measurement such as `coverage`", and the contract (§3.5,
   `contract.md:302-303`; §12.19, `:765-767`) names only "a generation
   request, or one `explain` or `classify` call".
   - In §3.5 and §12.19, replace that phrase with: "one generation request,
     or one call to `explain`, `classify`, `coverage`,
     `missing_interactions` or `followups`. `report` and `design_sizes` run
     several such operations: `report` measures the rows twice (for the
     guarantee, then for the bonus), and `design_sizes` generates each
     design and measures it at strengths 2 and 3. Each operation has its
     own memo."
   - On the constraints page: "each answer is remembered until that one
     call returns: a generation, an `explain`, a `coverage` or a
     `followups` call. `report` and `design_sizes` run several of these,
     each with its own memo."
   - `src/constraints.jl:840-843`, which lists "a request, or one explain or
     classify call", to match.

   Stage C step 6 changes these sentences again. Test: a whole-case
   predicate that counts its calls, and one `coverage` call at strength 3:
   at most one call per distinct complete assignment (probe `03a` saw 8
   calls on 8 assignments). No test counts predicate calls in measurement
   today.
3. **The `Report` guarantee.** `src/report.jl:29`, `:100` and `:108`,
   `docs/src/man/tutorial.md:445` and
   `docs/src/explain/coverage_evidence.md:190` say the guarantee is
   measured from the rows. The coverage figures are. The rest of the line
   is carried from generation (`_guarantee`, `src/report.jl:312-338`): the
   must-include count, an excursion's distance, base, dropped rows and
   never-appearing values, a full factorial's "every valid row", and the
   GND seed. Reword each place to "its coverage figures measured from the
   rows", and list in the `Report` field doc which parts are recorded at
   generation.
4. **`diagnose` takes observations as given.** Per decision 4. Add to §8.6
   (`contract.md:566-567`) and to the `diagnose` docstring
   (`src/diagnose.jl:154-163`): "`diagnose` takes the cases and outcomes as
   observed. A case that breaks a rule, or holds more than one `Invalid`
   value, is ranked like any other. A failing case that broke the rules can
   leave a suspect that no valid case holds, which `followups` reports as
   `inseparable` with no other suspects." The behavior is tested at
   `test/test_diagnose.jl:300-307` (a rule-breaking case) and `:344-368`
   (two `Invalid` values).
5. **Predicates that throw during a search.** Add to §12.16
   (`contract.md:748-750`): "A tabulated rule's predicate runs when the
   space is built (§12.18), so its exception surfaces there. A lazily
   evaluated rule's predicate, including every whole-case rule, runs during
   searches and row checks, so its exception surfaces from whichever call
   evaluated it: a generation, `isallowed`, `explain`, `coverage`,
   `report`, `design_sizes` or `followups`." The wrapping happens in
   `_evaluate_rule` (`src/constraints.jl:722-728`), reached from a search
   through `_memo_forbids` (`src/feasibility.jl:270-275`). Add the lazy
   case to `docs/src/explain/constraints.md:242-244`, which describes only
   the tabulated one.
   Test, in the test item at `test/test_constraints.jl:431-468` (which
   today reaches the rule only through the internal `forbids`): a whole-case
   rule that throws on one assignment, reached through `explain` and
   through `coverage`, each giving a `ConstraintError`. For `coverage`, pass
   rows that avoid the throwing assignment, so the error comes from a target
   search and not from reading the rows.
6. **Stale text, and one name that says the opposite of what it holds.**
   - `src/greedy_tuples.jl:244` and `test/test_greedy_tuples.jl:324` say
     the benchmark scripts use `n_way_coverage`; they do not. Remove the
     claim. (Stage B deletes the function.)
   - `src/explain.jl:370-371` says coverage measurement uses `classify`; it
     does not (`_classify!`, `src/measure.jl:358-374`, maps outcomes
     itself). New text: "Not exported; the tests use it." Stage C step 3
     adds the sentence about the shared classification.
   - `src/feasibility.jl:4-6` calls `classify` public; it is not exported.
     Say "the unexported `classify`".
   - `src/parameter_order.jl:9`: the docstring gives
     `choose_last_parameter!(taller, arity, n_way)`; the method is
     `choose_last_parameter!(taller, allc, matcher = case_partial_cover)`
     (`:14`). Write the real signature. (Stage B drops `matcher`.)
   - `src/parameter_order.jl:478` names the dead-row predicate `alive`.
     Rename it `isdead`, the name of the `_Greedy` field that holds the
     same predicate (`src/greedy_tuples.jl:102`, built at `:112`).
   - `test/test_parameter_order.jl:48`: qualify the comment, which holds for
     one case.
7. **The escape hatch.** One paragraph in "What the macros treat as a name"
   (`docs/src/explain/constraints.md:205-234`) pointing to `forbid(f,
   names...)` for expressions the macro rejects, matching the `@forbid`
   docstring (`src/constraints.jl:226-230`) and §12.6.

Acceptance gate: doctests, the docs build and the full suite green; the
contract diff reviewed by you; steps 1, 2 and 5 each have a test that would
fail if the code contradicted the new wording.

Size: one session.

### Implementation notes (2026-09-30)

Done on `feature/stage-a-docs-truth`. Adjustments to the steps above, and
why:

- **Step 1, §3.14.** The proposed "the explanation's `limit` names the
  keyword that stopped it" is ambiguous when several trials stop. The code
  (`src/feasibility.jl:676-692`) names `:explanation_limit` when that
  budget stopped a trial or left one untried, and `:feasibility_limit`
  otherwise. The clause says that rule. The existing
  "A trial that ends unknown keeps the rule" stays, so the new text does
  not repeat it. The `explanation_limit` keyword doc also says that each
  trial is bounded by `feasibility_limit`.
- **Step 1, test.** The plan names no file; the item is in
  `test/test_interface.jl`, beside the `explanation_limit` item. The space
  has one exclusion, `(w = 1, v = 1)`. Besides the checks listed, the item
  asserts that at limits 6, 10 and 14 this exclusion is `:unresolved` with
  `limit = :feasibility_limit => N`, which tests the new §3.14 sentence.
  It does not assert that rule sets are equal.
- **Step 2, test.** In `test/test_measure.jl`. The space has four
  parameters and a whole-case rule that forbids something, so the one
  `coverage` call has missing targets, an implied exclusion and deletion
  trials. It asserts that the logged assignments are all distinct, the
  exact form of "at most one call per distinct assignment". With the memo
  disabled, the same call makes 48 calls on 24 assignments, so the test
  catches a lost memo.
- **Step 3.** The header comment of `src/report.jl` also said `report`
  never trusts the bookkeeping. It now says which parts of the line are
  copied from the result, and that recorded exclusions are a fallback.
- **Step 4.** The two tests already covering the behavior now cite §8.6 in
  comments. No new test, as planned.
- **Step 5.** §12.16's list of calls adds `missing_interactions`, which
  searches through `coverage` and is public. The constraints page gives
  its shorter list as examples ("such as"). The new sentence is in the
  tabulated-rule paragraph, which already describes the lazy fallback.
- **Step 6.** The `src/feasibility.jl` header also called `isallowed` a
  thin wrapper over that file; it reads the rule tables directly
  (`src/explain.jl:139-149`) and never searches. The same sentence now
  says so. The `n_way_coverage` docstring says that only the tests call it.
- **Step 7.** The paragraph is at the end of "What the macros treat as a
  name", after the examples, and names `require(f, names...)` beside
  `forbid(f, names...)`.

No conflict between the code and the contract turned up beyond what the
plan anticipated. No behavior changed: `src/` differs only in docstrings,
comments and the one renamed local.

Verification: the full suite passed with 303,579 passes and no failures,
and the docs build exits 0. The count is below the 305,788 baseline
because three items loop for 30 seconds each (`test/test_combinations.jl:51`,
`test/test_parameter_order.jl:94, 115`), so their counts depend on machine
load, and a docs build ran alongside. Without those three items the count
is deterministic: 146,344 at `cc3f760` and 146,367 here. The difference,
23, is the new assertions: 17 for step 1, 3 for step 2 and 3 for step 5.

## Stage E1: the public proof record (before 0.5)

Goal: a follow-up proof says which rules and suspects came from which kind
of case, `minimal` means what the docstrings say, and the printed line
never presents a union as minimal. One change: the record, its contents,
the documentation, the display and the tests land together. No existing
field changes value; the printed line changes only when kinds' proofs
differ.

Steps:

1. **The record.**

   ```julia
   struct FollowupProof
       searched::NamedTuple                     # NamedTuple() or (p = v,)
       rules::Vector{Int}                       # the space's rule numbers
       labels::Vector{String}
       others::Vector{NamedTuple}               # the other suspects in the proof
       minimal::Symbol                          # :verified, :unresolved, :not_applicable
       limit::Union{Nothing, Pair{Symbol, Int}}
   end
   ```

   `searched` names the kind of case with the convention of
   `Followup.searched` (`src/diagnose.jl:434-438`). It is not called
   `kind`, because `Followup.kind` already means `:ordinary` or `:negative`
   for a found case (`:414-416`). `Followup` gains
   `proofs::Vector{FollowupProof}` as its last field (`:440-453`), and
   `_no_case` (`:456-458`) defaults it to empty. Unexported, like
   `Followup`, and listed in the `@docs` block for the `diagnose` types
   (`docs/src/reference.md:108-112`).
2. **Contents.** For an `:inseparable` suspect that was searched, one proof
   per kind, in the order of `searched`, so that `proofs[i].searched ==
   searched[i]`. Empty for every other status, and for a suspect with two
   `Invalid` values, which is `:inseparable` without a search (`:655`).
   This follows the "otherwise empty" rule of `others` and `rules`
   (`:421-427`). A `:found` suspect has no proofs, even when a kind searched
   before the case was found was proven inseparable (`:668-679`): the case
   settles the question. The same holds for `:unknown` (`:680-682`).
3. **Population.** `_followup` (`:647-695`) builds each proof from the
   per-kind result it already keeps (`:664-674`): `searched` from the kind
   loop, `labels` with `rule_label` as `:694` does, and `others` mapped from
   positions in `d.suspects` to combinations as `:693` does. The per-kind
   result itself is unchanged; Stage E2 replaces it.
4. **The union fields keep today's values.** `rules` and `others` are the
   sorted unions (`:685-686`). `minimal` is `:unresolved` when any proof
   is, `:verified` when all are, and `:not_applicable` otherwise
   (`:687-689`). `limit` is the first non-`nothing` proof limit
   (`:690-691`); a proof's `limit` is set exactly when it is `:unresolved`
   (a direct exclusion has none, `src/feasibility.jl:645-646`; the deletion
   search sets one only when it gives up verification, `:676-679, 690-692`),
   so this is also the first
   unresolved proof's limit. The union is sufficient but need not be
   minimal as a whole (probe `04` Examples A, B, D). `proofs` is where
   minimality is exact.
5. **Documentation.**
   - The `followups` docstring (`:495-499`): `minimal` is judged per kind of
     case, as the field doc already says (`:428-431`); the union of the
     proofs is sufficient but need not be minimal; `proofs` holds each
     kind's proof.
   - The `Followup` docstring documents `proofs` and states step 4's rule
     for `minimal`, including that one directly forbidden kind
     (`:not_applicable`) makes the union `:not_applicable` unless another
     kind is unresolved. Today that rule is written only in
     `design/phase6_review.md:294-298`.
   - A `FollowupProof` docstring.
   - Contract §3.17 (`contract.md:363-371`), one sentence: "An
     `inseparable` follow-up gives one proof per kind of row searched; each
     proof's minimality is judged within its kind (§3.16), and the union of
     the proofs is sufficient but need not be minimal."
   - `docs/src/howto/diagnose.md`: a short new example with one `Invalid`
     value whose kinds need different rules (probe `04` Example A), showing
     `proofs`. The existing inseparable example (`:108-120`) has no
     `Invalid` values.
6. **Display.** In `show` (`:713-751`; the inseparable branch is
   `:725-745`), the line stays one line, because a `Vector{Followup}`
   prints one element per line.
   - One proof, or several with the same `rules` and `others` (probe `04`,
     "B reversed"): today's text, unchanged. The union is then each kind's
     proof, so its `minimal` is exact.
   - Several proofs that differ: after "inseparable; ", one clause per
     proof, joined by "; ". Each clause is "in KIND, " followed by today's
     text for a single proof: "no valid case holds it: …" when it has no
     other suspects, otherwise "every valid case holding it also holds …,
     under …", each with its own unresolved note. KIND is `_kinds_phrase`
     (`:704-711`) of that one kind, such as "ordinary cases" or "negative
     cases with n = Invalid(0)". The trailing "; searched …" is dropped,
     since each clause names its kind.

   Probe `04` Example C then prints:
   `(b = 2,): inseparable; in ordinary cases, no valid case holds it: rule 1 on (n, b) excludes it; in negative cases with n = Invalid(0), every valid case holding it also holds (n = Invalid(0), b = 2)`.
   The test that pins today's union line for this case
   (`test/test_diagnose.jl:400-402`) is rewritten to it, deliberately.
   Move the single-proof text into one helper,
   `_print_proof(io, rules, labels, others, minimal, limit)`, used by both
   forms.
7. **Tests.**
   - Probe `04` Examples A, B, B reversed and D as `@testitem`s. Extend the
     existing Example C test (`test/test_diagnose.jl:391-402`, in the item
     at `:372-414`) rather than duplicating it. Assert the union fields (Example A: `rules = [1, 2]`,
     `:verified`), the per-kind proofs (Example A: ordinary `rules = [2]`;
     negative at `n`, `rules = [1]`), and the printed lines.
   - Extend `check_followups` (`test/test_diagnose.jl:94-130`), whose
     inseparable branch (`:120-124`) today checks only that no valid row
     isolates the suspect, to check each proof by brute force within its
     kind: its rules and other suspects alone leave no isolating valid case
     of that kind, and, when it is `:verified`, dropping any one part leaves
     one. The random sweep (the item at `:416-445`) then exercises every
     proof.
   - One case per branch of step 4's `minimal` rule across kinds. No test
     covers this today: every assertion on `minimal` at
     `test/test_diagnose.jl:295, 333, 339` uses a space with no `Invalid`
     values.
   - A kind left `:unresolved`: Example A with the smallest
     `explanation_limit` that leaves one kind unresolved, asserting that
     proof's `limit` and the union's.
   - `proofs` is empty for `:found` (the setup at
     `test/test_diagnose.jl:377-389`, where one kind is proven inseparable
     before the other finds a case), `:indistinguishable`, `:unknown`, and
     two `Invalid` values.

Acceptance gate: `test_diagnose` green; doctests and the docs build green;
the docstring, contract and how-to changes reviewed with Stage A's.

Size: one session.

## Stage B: delete dead code (optional before 0.5)

Goal: obsolete implementations that survive only because obsolete tests
call them are removed. Independent oracles, instrumentation and deliberate
test support stay. Generated designs do not change.

Steps:

1. **Delete these, with their docstrings and tests.** Nothing public or
   documented depends on any of them: none is exported now
   (`src/UnitTestDesign.jl:14-27`) or was at v0.4.0, none is in contract
   §13.1, and none appears in `docs/src`, the README or the tests that list
   names (`test/test_doctests.jl:23`, `test/test_interface.jl:686-707`,
   `test/test_static.jl`).

   | Delete | Definition, with docstring | Tests to remove |
   |:--|:--|:--|
   | `pairs_in_entry` | `src/combinations.jl:103-114` | none |
   | `combination_number` | `src/combinations.jl:100` | the item `test/test_combinations.jl:22-29` |
   | `combination_histogram`, `most_to_cover`, `most_common_value` | `src/coverage_matrix.jl:93-104, 107-109, 142-148` | none |
   | `all_combinations_matrix` | `src/coverage_matrix.jl:43-57` | none |
   | `parameter_cnt` | `src/coverage_matrix.jl:85-90`, and the unused local that calls it at `:265` | none |
   | `first_match_for_parameter` | `src/coverage_matrix.jl:279-291` | the item `test/test_coverage_matrix.jl:190-200` |
   | `fill_consistent_matches` | `src/coverage_matrix.jl:294-312` | the items `test_coverage_matrix.jl:203-215, 218-230, 233-245` |
   | `remove_combinations!` | `src/coverage_matrix.jl:386-406` | the item `test_coverage_matrix.jl:283-295` |
   | `multi_way_coverage` | `src/coverage_matrix.jl:409-446` | the items `test_coverage_matrix.jl:298-302, 305-312` |
   | `fill_missing_test_set_values!`, `cover_remaining_by_creating_cases` | `src/parameter_order.jl:30-48, 51-66` | none |
   | `n_way_coverage`, and the one-argument `_Greedy(mc)` | `src/greedy_tuples.jl:239-252, 118` | the item `test/test_greedy_tuples.jl:322-332`; lines `:213-215` of the item at `:205-220` (keep `:216-218`, which test `generate(GND)`, and drop the now unused `using Random` at `:206`) |
   | `covers` | `src/request.jl:533-550` | none |
   | `never_appear(arity::AbstractVector{<:Integer}, _)` | `src/excursions.jl:226-227`; reword the shared docstring (`:218-225`) for the one remaining method | none |
   | `full_factorial_rows`, `FullFactorialRows` and its three `Base` methods | `src/full_factorial.jl:33-58` | `test/test_full_factorial.jl:25-31` |

2. **The `matcher` parameters become fixed calls to the matcher each
   production caller uses today.**
   - `choose_last_parameter!(taller, allc, matcher = case_partial_cover)`
     (`src/parameter_order.jl:14`): its only caller (`:191`) takes the
     default. Drop the parameter; call `case_partial_cover` at `:18`.
   - `insert_tuple_into_tests(test_set, allc, matcher =
     case_compatible_with_tuple)` (`:88`): its callers (`:193`,
     `test/test_coverage_matrix.jl:169`) take the default. Drop it; call
     `case_compatible_with_tuple` at `:95` and `:105`.
   - `matches_from_missing(mc, entry, missing_param, matcher =
     case_compatible_with_tuple)` (`src/coverage_matrix.jl:264`). Careful:
     the default is not what production uses. Both production callers pass
     `case_partial_cover` (`src/parameter_order.jl:18` and `:241`). Drop
     the parameter and call `case_partial_cover` at `:270`. Fixing it to the
     declared default instead would change classic IPOG output. The one
     test that used the default (`test/test_coverage_matrix.jl:184`)
     expects `[2, 2]`, which holds under `case_partial_cover` too.
   - Update the `choose_last_parameter!` docstring signature that Stage A
     step 6 wrote.

   These edits touch reachable engine code (classic `ipog`,
   `src/parameter_order.jl:475-476`), which is why the gate includes the
   fingerprint.
3. **Keep, and say why in a comment:**
   - `misses` (`src/coverage_matrix.jl:222`). It is one of five tuple states
     that the docstring at `:201-218` defines as a partition, and a test
     checks that they are mutually exclusive
     (`test/test_coverage_matrix.jl:6-22`). The other four are used.
     Deleting it would leave both the description and the test incomplete.
   - `memo_size` (instrumentation, `benchmark/run.jl:231`), `plain`
     (documented in the `Report` docstring, `src/report.jl:77`),
     `targets(request)` and `components(f)` (test conveniences).
4. **The reference sweep is a report, not a gate.** Move probe `05a` to
   `benchmark/reference_sweep.jl`. Take the repository root from
   `@__DIR__` instead of the hard-coded path (`05a:5`), and print to
   standard output instead of writing next to the script (`:6`). It runs
   by hand at reviews; its output is a list for a person to judge. It
   cannot be a test: Julia reaches methods through dispatch, iteration
   protocols, callbacks and operators with no textual reference to the
   definition, and per-name counts cannot tell a used method from an unused
   one of the same function.
5. **A guard for the oracle's independence.** A `@testitem` that fails if
   `test/checker.jl` mentions `UnitTestDesign` outside comments (item 14
   below).

Acceptance gate:
- The full suite and Aqua green, and the docs build green.
- No call or qualified reference to a deleted function remains. Check with
  a fixed-string `git grep` for `name(` and for `UnitTestDesign.name`, one
  name at a time, over `src/`, `test/`, `docs/`, `benchmark/` and `paper/`.
  A plain-name grep hits English words and local variables.
- `methods(never_appear)` and `methods(_Greedy)` each have one method
  fewer.
- The benchmark fingerprint is unchanged (`benchmark/run.jl:144-156`).

Size: one session.

## Stage C: measurement with one row reader, one preparation, one classification

Goal: a caller's row is read by one function. A `report` or `design_sizes`
call prepares each set of rows once and keeps one lazy-rule memo for all
its measurements. The mapping from a search outcome to a status has one
owner, and counting does not build what it discards.

Invariant: every `Coverage`, `Report` and `DesignSizes` field is identical
before and after, under any limit, checked by the snapshot (see "The
before/after snapshot" below). Deliberate changes: `isallowed` and
`explain` accept vector rows (decision 5), and some input-error messages
take one common wording (step 1).

Steps:

1. **One row reader.** In `src/space.jl`, beside `case_indices`:

   ```julia
   _row_indices(space, row; what, section = nothing, complete) -> Vector{Int}
   ```

   It accepts a `NamedTuple`, a `Tuple` or an `AbstractVector` (read as a
   tuple). It owns the four input errors. Each starts with `what`, such as
   "coverage row 3", and ends with "(contract SECTION)" when `section` is
   given:
   - not a row: "WHAT is a T; a row is a NamedTuple, or a tuple or vector
     with one value per parameter";
   - wrong length: "WHAT has k values; the space has n parameters (a, b,
     c)";
   - a name or value error from `case_indices`: "WHAT: " followed by that
     message;
   - missing values, when `complete`: "WHAT, (…), has no value for `a` and
     `b`; it must name every parameter".

   Each caller keeps its own policy outside the reader:
   - which kinds of row it accepts, such as `excursion_base`'s ordinary-only
     check (`src/excursions.jl:115-119`);
   - the positional rule that rejects a `NamedTuple` (for `from`,
     `src/interface.jl:225-228`; also the positional `must_include` rows);
   - the `Vector{Int}` branch of `excursion_base` (`:95-103`), which takes
     engine positions, not values.

   | Today | `what` | `section` | `complete` |
   |:--|:--|:--|:--|
   | `_coverage_row` (`src/measure.jl:195-219`) | "coverage row k" | §1.13 | yes |
   | `_diagnosis_row` (`src/diagnose.jl:261-284`) | "diagnose case k" | none | yes |
   | the row branch of `_must_include_matrix` (`src/request.jl:203-215`) | "must_include row r" | §10.1 | no |
   | `_from_row` and the reading half of `excursion_base` (`src/interface.jl:222-239`, `src/excursions.jl:105-114`) | "the excursion base `from`" | §7.6 | yes |
   | `isallowed` (`src/explain.jl:139-144`) | "the case" | §1.25 | yes |
   | `explain` (`:247`) | "the assignment" | §1.26 | no |
   | `_classify_one` (`:382-385`) | "the target" | none | no |

   Tests whose pinned wording changes are rewritten in the same commit:
   `test/test_interface.jl:435`, `:652-655` and `:663-665`, the `from`
   messages, which today use a different subject and phrasing. The other
   pins keep passing, because they match a prefix or a fragment:
   `test/test_measure.jl:288, 329-337`, `test/test_diagnose.jl:515-518`,
   `test/test_interface.jl:256-272, 659-662`,
   `test/test_request.jl:124-174`, `test/test_invalid.jl:215, 227`. Run the
   full suite to catch any other pin.

   One collection reader, `_row_list(input; what, fix)`, replaces
   `_coverage_rows` (`src/measure.jl:168-184`), the collection branch of
   `_diagnosis_input` (`src/diagnose.jl:215-227`) and `_must_include_rows`
   (`src/interface.jl:103-115`). It collects an iterable once, rejects a
   single row with "wrap a single row in a vector" and the corrected call
   that `fix` writes, and rejects anything that is not a collection. Those
   messages keep today's wording. The checks that come first and belong to
   one caller stay in that caller: `coverage` given the space first,
   `diagnose` given a `TestSpace`.

   Update the `isallowed` and `explain` docstrings
   (`src/explain.jl:113-114`, `:211-212`) to say a vector is accepted.
2. **Prepared rows and the memo scope** (decision 7).
   - Rename `_read_rows` (`src/measure.jl:236-264`) to
     `_prepare_rows(space, memos, rows)` and return a `PreparedRows` struct:
     `kept`, `duplicates`, `rejected`, `slots`, and the original row
     positions. Preparing checks each row with `violated_rules` (`:257`),
     which consults the lazy-rule memo but no answer cache, so the result
     can be shared.
   - `_measure(prepared, space; strength, stronger, memos,
     feasibility_limit, explanation_limit, curves)` builds its own
     `FeasibilityContext` with a fresh answer cache around the memo it is
     given. `curves = false` skips the prefix curves, which only `report`'s
     base measurement uses. (The review calls them "progress" figures.)
   - `FeasibilityContext` (`src/explain.jl:20-31`) gains a constructor that
     takes the memo: `FeasibilityContext(space, memos; feasibility_limit)`.
   - `report` (`src/report.jl:184-199`) prepares once and passes one memo
     to its base and bonus measurements.
   - `design_sizes` (`src/report.jl:559-593`) keeps one memo for the whole
     call and passes it to every measurement. Each design's rows are
     prepared once for its two strengths (`_size_row`, `:622-633`), at the
     strength and groups `coverage(cases; strength = s)` uses today
     (`_measured_request`, `src/measure.jl:667-683`). Its generations stay
     ordinary generation calls with their own memos: sharing across them
     would mean threading a memo through the public generators, which is
     not in this plan.

   Why each measurement keeps its own answer cache: see decision 7. §3.5
   allows sharing within one call.
3. **One index-level classification** (decision 3).
   - `IndexClassification` and `_STATUS_OF_OUTCOME`
     (`src/feasibility.jl:717-731`) own the mapping from outcome to status.
   - `_classify!` (`src/measure.jl:358-374`) and `_classify_target`
     (`src/request.jl:483-496`) build their records from an
     `IndexClassification` instead of testing outcomes inline.
     `_classify_one` (`src/explain.jl:380-393`) already does.
   - A feasibility-only entry, `_status(f, key) -> Symbol`, gives the status
     without the deletion search: the direct check, then `completable` (the
     body of `explain_partial`, `src/feasibility.jl:636-657`, without its
     last two lines). This is safe for every figure, because deletion trials
     never touch `f`'s answer caches: each trial is a fresh `Feasibility`
     that shares only the rule memo (`:682-684`).
   - The `classify` docstring (`src/explain.jl:370-371`) then says that
     `classify`, generation and coverage measurement share
     `IndexClassification`.
4. **A counts-only measurement** for `_bonus` (`src/report.jl:226-236`) and
   the size counts (`:616-620`). Both keep only counts but today receive
   full missing lists and explanations. On a 30 by 5 `all_pairs` design the
   bonus built 287,305 missing-target NamedTuples and spent about 41% of its
   samples in `from_indices` (probe `03c`). `_Lists` (`src/measure.jl:340-346`)
   gets a counting sibling, `_Counts`, and `_classify!` dispatches on which
   one it is given. With `_Counts` it calls `_status` and increments a
   counter, so nothing is materialized. The measurement returns each part's
   `(covered, feasible, unknown)`; the unknown count is still kept.
5. **Tests.**
   - Probe `03b` as a property test over the random problems: base and
     bonus figures are equal whether the memo is shared or not, including
     under tight limits (`test/test_report.jl:188-212, 530-541`).
   - Probe `03a` as a `@testitem`: within one `report` call, a whole-case
     predicate is evaluated at most once per distinct assignment. For
     `design_sizes`: its predicate calls, minus those of the same
     generation calls made alone, are at most the number of distinct
     assignments.
   - An allocation check for the counts-only path on the 30 by 5 bonus
     example, with a bound well below today's, because identical figures
     will not catch a path that quietly materializes every target.
   - The snapshot, written at the start of this stage, before any code
     change, and diffed at the end.
6. **Docs.** After this stage, one `report` call keeps one memo, and one
   `design_sizes` call keeps one for its measurements. In §3.5, §12.19, the
   constraints page and `src/constraints.jl:840-843`, an operation becomes
   "one generation request, or one call to `explain`, `classify`,
   `coverage`, `missing_interactions`, `report` or `followups`.
   `design_sizes` keeps one memo for all its measurements; each design it
   generates is a separate generation request with its own."

Acceptance gate: the snapshot diff is empty for the measurement corpus; the
checker comparisons and the random-problem gate are green; the
predicate-count and allocation tests pass; apart from new tests, the only
test changes are the rewritten message pins listed in step 1.

Size: two sessions.

## Stage D: the negative sub-request projection and shared target order (after C)

Goal: the negative sub-request has one owner and fails loudly when it is
built wrong, and the order of targets is defined once.

Invariant: for every call that succeeds, no generated row, count or
exclusion changes, in value or order, and no measured list changes. This
is checked by the snapshot's generation and measurement corpora, which
include spaces with `Invalid` values. If D-1 is settled with option (B), a
call that fails at `feasibility_limit` may name a different target in its
error.

**Settle before starting.** The readiness check found two blockers.

- **D-1. Negative target order cannot be shared "by construction" without
  a choice.**
  - Generation walks negative targets by invalid value first. For each
    parameter `p` and invalid value `v` it builds a sub-request and
    classifies `TargetList(sub)` in order (`src/invalid.jl:131-146`). That
    order is also the order in which the engine receives its required
    targets (`:143-156`).
  - Generation then sorts its exclusions into measurement order with
    `_negative_order` (`:96-101`, sort at `:180-181`).
  - Measurement walks by support first (`src/measure.jl:450-456`).
  - A shared enumerator still leaves a merge between the two walks. The
    options:
    - (A) Keep the per-value walk and keep a sort, keyed by the shared
      definition.
    - (B), recommended. Classify every negative target first, in
      measurement order, with the shared enumerator. Then build each
      (`p`, `v`) sub-request from the required targets at (`p`, `v`).

  Why (B):
  - Ordinary generation already works this way (`classify_targets`, then
    the engine; `src/request.jl:458-470`), so both paths read alike, and
    `_negative_order` and the sort go.
  - The readiness check compared, for each (`p`, `v`), today's
    `TargetList(sub)` order with measurement order restricted to (`p`,
    `v`). They agree, apart from the strength-1 target `(p = v)`, which
    today is handled separately (`src/invalid.jl:136-141`) and is a
    one-element block in measurement. So rows do not move. Confirm this
    with a test before relying on it.
  - The cost: when both an engine run for an earlier (`p`, `v`) and the
    classification of a later target would reach `feasibility_limit`, the
    error names the classification instead of the engine run.
- **D-2. The gate as first written could not see the invariant.**
  - The benchmark fingerprint (`benchmark/run.jl:144-156`, hash at `:152`)
    covers one unconstrained space with no `Invalid` values. It is
    generated by classic `ipog` (`src/parameter_order.jl:475-476`), which
    touches neither `TargetList` nor negative generation.
  - The random-problem gate compares against the oracle, not against the
    previous revision.
  - Resolved by the snapshot, whose generation corpus includes `Invalid`
    values, stronger groups containing an invalid parameter, a lazy rule
    that is active in a negative sub-request, and negative must-include
    rows.

Stage C edits `src/measure.jl:340-421`, so re-anchor this stage's
`measure.jl` references when it starts.

Steps:

1. **A projection type** in `src/invalid.jl`. It holds the parent space,
   the invalid parameter `p`, the kept parameter indices, the parent rule
   numbers of the active rules (`active_rules(space, p)`,
   `src/space.jl:485`), and the position map that `_with_invalid`
   (`src/invalid.jl:32-38`) assumes. Functions: build it from `(space, p)`;
   map a sub-space rule number to the parent's; map sub-request positions
   to parent positions. It checks, with messages, when built:
   - the parent request's tables are `space.tables` in order:
     `request.feasibility.tables[k] === space.tables[k]`.
     (`src/request.jl:94` states this; nothing checks it.)
   - each sub-request memo is the parent's:
     `sub.feasibility.rule_memo[k] === request.feasibility.rule_memo[active[k]]`.
     The `Feasibility` constructor already checks each memo's count, shape
     and laziness (`src/feasibility.jl:184-191`). What goes unchecked is
     identity: two lazy rules of the same arity could be swapped and
     silently share verdicts.
   - each projected scope is the parent scope mapped elementwise, in the
     order the rule gave it. That order is the predicate's argument order:
     `_tabulate` keeps `c.scope` as written (`src/constraints.jl:809`), and
     `_LazyRule` receives `values[scope]` in that order (`:817`). Scopes are
     not sorted, and the projection must not sort them.

   There is no whole-case check. `active_rules` keeps only rules whose scope
   omits `p`, and a whole-case rule's scope is every parameter, so one
   cannot be active; if one were, `Feasibility` would already throw
   (`src/feasibility.jl:177-178`). Say so in a comment.
2. **A checked sub-space constructor.** Today `_negative_request` builds the
   parts (`src/invalid.jl:54-59`) and passes all seven `TestSpace` fields
   positionally to `TestSpace(Val(:parts), ...)` (`:60-62`;
   `src/space.jl:266-274`), its only caller. The internal constructor
   instead takes a `NamedTuple` of parts and checks `keys(parts) ==
   fieldnames(TestSpace)` before calling `new(parts...)`, so an added field
   fails at the first negative generation in the suite. `TestSpace` is not
   parametric, and the readiness check confirmed the pattern works. A test
   builds a projected sub-space and compares every field with the expected
   projection.
3. **One candidates helper**, in `src/space.jl`: `_candidates(space, p, v)`
   gives `v` at `p` and each other parameter's ordinary values; with
   `p = 0`, every parameter's ordinary values. It replaces:
   - `src/explain.jl:94` and `src/diagnose.jl:618`, which are the same
     expression;
   - `src/request.jl:80`, which becomes `_candidates(space, 0, 0)`;
   - `src/invalid.jl:66`, which becomes `_candidates` of the sub-space with
     `p = 0`.

   The `copy` calls go, because `Feasibility` copies its candidates
   (`src/feasibility.jl:168`).
4. **Rule numbers leaving the sub-request** map back through the projection
   before any message or record is built. Nothing reports them today (probe
   `01a` shows the divergence), so this is a guard. The sub-space holds the
   parent's `Constraint` objects (`src/invalid.jl:61`), so a test checks
   `request.space.constraints[parent_rule(pr, i)] ===
   sub.space.constraints[i]` for every sub-space rule.
5. **Tests for memo sharing.** Use a lazy rule that is active in a negative
   sub-request. `test/test_invalid.jl` has none today: `two_invalid()`
   (`:81-84`) has a rule over all three parameters, which is never active
   in a sub-request. Test three things: a combination the parent already
   evaluated is not evaluated again; a combination new to the sub-request
   is evaluated at most once; and the memo dictionaries are the same
   objects (`===`). Count calls with a closure, as probe `03a` does.
6. **Target order, defined once.**
   - (a) **One mixed-radix code.** Measurement codes value indices, with
     radix = full domain length (`src/measure.jl:274-281`, radix at
     `:476`). `TargetList` and `_recount` code engine positions, with
     radix = ordinary arity (`src/request.jl:394, 404-415, 643-647`). The
     order is the same (first parameter fastest); only the radix differs.
     - Move `_code(idx, support, radix)` to `src/space.jl` as the one
       encoder, and add its inverse, `_decode!(row, code, support, radix)`,
       beside it. `TargetList.getindex` calls `_decode!`; `_recount` calls
       `_code` with the ordinary arity.
     - `_measure_block!`'s odometer (`src/measure.jl:387-421`) stays,
       because it steps one reused buffer lazily. A test checks that it
       visits codes 0, 1, 2, … in `_decode!` order.
     - The column-major accumulation at `src/measure.jl:305-313` stays as
       it is, for speed.
     - `TargetList` keeps returning a fresh vector per index, because
       callers keep it (`src/request.jl:467`, `src/invalid.jl:150`,
       `src/greedy_tuples.jl:108`).
   - (b) **One negative-target enumerator,** per D-1.
   - (c) **The support-to-group mapping computed once**
     (`src/measure.jl:486-494`).

   The equivalence argument in the comment at `src/invalid.jl:11-24`
   becomes code. There is no coverage-specification type in this plan:
   after (a) to (c) the shared pieces are three functions, and bundling
   them is a later choice.

   Allocation check, independent of Stage C: `coverage` of a complete
   design on the large example. No target is classified there, so
   allocations come only from projections and enumeration. Keep
   `test/test_measure.jl:621-634` and the `same_exclusions` tests as
   regressions, and the checker comparisons as the independent check.

Acceptance gate:
- The snapshot diff is empty for the generation and measurement corpora.
- The random-problem gate is green, and the benchmark fingerprint is
  identical.
- `test_invalid`, `test_request` and `test_measure` are green.
- The projection, memo-sharing, rule-mapping, order-agreement and
  allocation tests pass.

Size: three sessions.

## Stage E2: typed isolation results (after E1)

Goal: `_isolate`'s three outcomes are three types instead of one tuple
with placeholder values, and the unknown result carries the limit that
caused it.

Steps:

1. Replace the eight-field named tuple that `_isolate` returns
   (`src/diagnose.jl:623-644`; docstring `:606-609`) with three small
   structs:
   - found: witness, from, changes;
   - proof: the index-space form of `FollowupProof`, with rule numbers,
     suspect positions, minimal and limit;
   - unknown: limit.

   `_followup` (`:647-695`) collects typed results. The unknown result
   carries its limit, so `:680-682` no longer rebuilds it, and the untyped
   `proofs = []` and `best = nothing` (`:663-664`) go.

   Today the named tuple fills its unused fields with placeholder values
   (`none`, `:623-624`). Nothing misreads them, because every reader checks
   `status` first (`:668, 673`), but a reader has to know that. An
   inseparable proof can also legitimately hold `rules = Int[]` and
   `minimal = :not_applicable` (probe `04` Example C), so the placeholders
   look like real values.
2. Tests: the Stage E1 tests keep passing, and a new test checks that the
   unknown result's `limit` equals the limit that stopped the search.

Acceptance gate: `test_diagnose` green, and the snapshot diff empty for the
follow-up corpus. `Followup` has no `==`, so the comparison is on the
snapshot's text.

Size: half a session.

## Stage F: the macro frontend file (after 0.5)

Goal: the constraint macro walker lives in its own file with one
constructor path, and its hygiene is tested from a bare module.

Steps:

1. Move `src/constraints.jl:195-660` to `src/constraint_macros.jl`, included
   right after `constraints.jl` (`src/UnitTestDesign.jl:30`). Keep
   `source = :macro`, which `_check_rule` reads for the `$name` hint
   (`constraints.jl:765-767`). Update the header of `constraints.jl`
   (`:1-11`), which describes the macro form.
2. `_macro_rule` (`:651-659`) calls `_function_rule` (`:178-192`) instead
   of repeating the `Negated` wrap and the reason label (`:655-656` versus
   `:189-191`).
   - `_function_rule(polarity, f, names, reason; text = nothing)` gains one
     keyword. With `text`, the label is "reason: text", or `text` alone
     when there is no reason, and the source is `:macro`. Without it,
     behavior is unchanged.
   - `_macro_rule` keeps its empty-scope check (`:652-654`) first.
     `_function_rule`'s own checks (`:179-188`) cannot fire for macro input.
   - After this, the new file depends on `Constraint`, `Negated`,
     `_reason_label` and `_function_rule`.

   Test: a rule written with the macro and the same rule written with
   `forbid(f, names...)` have equal fields except `label` and `source`. The
   two predicates are different closures (probe `06`), so compare them by
   evaluating both on every combination of the scope, and check that both
   are `Negated` for `require`.
3. Hygiene tests: expand `@forbid` in a module that only did `import
   UnitTestDesign`, and evaluate a module-qualified call, not only check
   its scope (`test/test_constraints.jl:124, 139` check scope only).
4. Leave `test/test_constraints.jl` as one file. The review's "keep syntax
   and hygiene tests together" is the status quo.

Acceptance gate: `test_constraints` green with its existing tests
unchanged; the new tests pass; doctests unchanged.

Size: half a session.

## The before/after snapshot (Stages C, D and E2)

`benchmark/snapshot.jl` writes a text dump of a fixed corpus: for each case,
the result's fields, one per line, printed with `repr` in a fixed order.
Run it at the stage's base commit (in a `git worktree`) and at the stage's
head, then `diff` the two outputs. The stage's invariant holds when the
diff is empty. Comparing text avoids needing `==` on `Coverage`, `Report`
or `Followup`, which have none. The script uses only the public API, so it
runs on both commits.

The corpus has three parts, each run at the default limits and at a tight
`feasibility_limit` and `explanation_limit`:

- **Generation:** `covering` at strengths 1 to 3 with IPOG and with GND
  (fixed seeds), `excursions` and `full_factorial`. The spaces have
  tabulated and lazy rules, `Invalid` values, stronger groups that contain
  an invalid parameter, and ordinary and negative must-include rows. Record
  the rows, the counts, `excluded`, `negative_excluded` and `notes`.
- **Measurement:** `coverage`, `report` and `design_sizes` on those results
  and on hand-written row sets with duplicates and rejected rows.
- **Follow-ups:** `diagnose` and `followups` on the probe `04` spaces and
  on fixed seeds of the `test_diagnose` random sweep.

Draw spaces from `test/random_problems.jl` with fixed seeds, and from the
probe spaces. Write it in Stage C before any code change, and extend it as
later stages need.

## Not in this plan, and why

- **IPOG consolidation.** Classic `ipog` and `ipog_multi_way(...,
  Returns(false))` with the same parameter order gave an identical matrix
  in 0 of 13 configurations and equal size in 5 of 13. The constrained
  core ranged from 2 rows smaller to 5 larger, and one noisy run on
  benchmark fixture 1 (15 by 4, strength 4) took 5.82 s against 3.41 s
  (probe `05b`). Consolidating would change every unconstrained design,
  break the benchmark's cross-revision fingerprint equality and contradict
  `docs/src/man/ipog.md:133-135`. §9.8 allows it. If you want it, it is a
  separate, benchmark-gated decision after 0.5.
- **A general search builder** with extra rules or a preferred candidate
  order. It has one consumer, `_isolate`.
- **A coverage-specification type.** See Stage D step 6.
- **One memo across `design_sizes`' generations.** The measurements share
  one (Stage C step 2); the generations are public generator calls. In
  probe `03a`, 45 of `design_sizes`' 136 predicate calls came from
  generation.
- **Moving the checker into its own test module.** Stage B step 5 adds the
  cheap guard instead.
- **A dead-code test.** See Stage B step 4 for why textual reference counts
  cannot gate a Julia code base.

## Things worth your attention beyond the review

Found during verification or the readiness check. Each has a disposition.

1. **`feasibility_limit` changes the exclusion record of a successful
   generation**, against §3.8 as written (probe `08a`). Decision 1; Stage A
   step 1.
2. **The `followups` docstring contradicts its field doc**, and `show`
   prints a `:verified` union with no caveat (`src/diagnose.jl:495-499`
   versus `:428-431`; `:725-745`). The non-minimality also affects `others`
   and depends on rule order. Decision 2; Stage E1.
3. **`report`'s guarantee line carries unmeasured generation metadata**,
   while its docstring says "checked by measuring them" (`src/report.jl:29`
   versus `:312-338`). Stage A step 3.
4. **The user docs promise a memo that lasts the whole call**, but `report`
   and `design_sizes` do not keep one (`docs/src/explain/constraints.md:249-252`).
   Stage A step 2, then Stage C step 6.
5. **More dead code than the review lists.** Stage B deletes `covers`,
   `remove_combinations!`, `full_factorial_rows`, a `never_appear` method
   and `parameter_cnt`, and keeps `misses` (Stage B step 3). Classification
   is mapped in three places (Stage C step 3). The stale text is in Stage A
   step 6.
6. **The negative sub-request can fail silently.** All seven `TestSpace`
   fields are passed positionally (`src/invalid.jl:60-62`). Table and memo
   identity are unchecked (`src/request.jl:94`). Sub-space rule numbers
   diverge from the parent's with no map back, and nothing tests memo
   sharing across the sub-request. Stage D steps 1 to 5. The exclusion of
   whole-case rules is not silent: a leaked one would throw.
7. **The row readers disagree.** `isallowed` and `explain` reject vector
   rows (`src/explain.jl:139, 243`) while every other entry point accepts
   them. Messages have drifted (`src/request.jl:206`,
   `src/excursions.jl:114`). A `Vector{Int}` means values in the public
   `excursions(from = ...)` but engine positions in `generate_excursion`
   (`src/excursions.jl:95-103`). Decision 5; Stage C step 1.
8. **Lazy and whole-case predicates run inside the solver** and can throw
   from it (`src/feasibility.jl:264-275`). Stage A step 5. That rule
   evaluations are counted but not budgeted is already stated in §3.3
   (`contract.md:277-281, 291-292`); no action.
9. **The bonus and size measurements compute and discard explanations**
   (`src/report.jl:232-235, :617`). Stage C step 4.
10. **`_isolate` uses placeholder values, and its unknown result drops its
    limit.** In addition, the union's `minimal` is `:not_applicable` when
    some kind is directly forbidden and none is unresolved, which hides a
    verified per-kind proof. Stage E1 documents the rule and makes the
    per-kind proofs visible; Stage E2 adds the types.
11. **`diagnose` accepts rule-breaking observations, and the contract never
    says so** (§8.6; `src/diagnose.jl:154-163`). Decision 4; Stage A step 4.
12. **The include order is not a layering order.** `measure.jl` and
    `report.jl` depend on `interface.jl`; `design_sizes` calls the public
    generators; `combinations` is used at `src/request.jl:359` and
    `src/measure.jl:488` before its import at `src/combinations.jl:3`. No
    action. A comment in `src/UnitTestDesign.jl` listing the forward
    references would save the next reader the search. Stage D step 6 moves
    `_code` to `space.jl`, which removes one such reference.
13. **There are two integer index spaces**: value indices and engine
    positions (`src/request.jl:4-12, 292-302`). No action. This decides
    the shape of the shared code in Stage D step 6(a).
14. **The oracle's independence is only a convention.** `test/checker.jl`
    is included into the same module as `test/fixture_model.jl`, which
    imports the package (`test/test_checker.jl:10-15`;
    `fixture_model.jl:28`). `fixture_model.jl`'s `model_rows` brute-forces
    over the package's own rule tables, so comparisons against it are not
    independent. The oracle also names no rules for implied targets and has
    no limits (`checker.jl:70-71`), so explanations, minimality and unknown
    handling are never oracle-checked. Stage B step 5 adds a guard. Stages
    C, D and E rely on the package's own consistency and on the snapshot,
    not on the oracle, for those parts.
15. **A shared answer cache can change bounded results.** `_completable`
    caches each solved component's witness even when the whole query ends
    unknown (`src/feasibility.jl:440-449`). So sharing a `Feasibility`
    across measurements or operations can resolve a target that a separate
    search leaves unknown. The result stays sound, but a reported figure
    changes. Decision 7 keeps answer caches separate for that reason.

## Order of work

| Stage | Content | Size | When | Invariant or change |
|:--|:--|:--|:--|:--|
| A | Documentation truth | 1 session | Before the 0.5 release PR | Wording and tests; one local variable renamed |
| E1 | Public proof record | 1 session | Before the 0.5 release PR | `Followup` gains `proofs`; existing fields unchanged; `show` changes only when kinds' proofs differ |
| B | Dead code | 1 session | Before 0.5 if time allows, else after | Designs unchanged (fingerprint); each `matcher` fixed to what its callers pass today |
| C | Row reader, prepared rows, shared classification, counts-only | 2 sessions | After 0.5 | Every measured figure identical (snapshot); `isallowed` and `explain` accept vectors; some input-error wording unified |
| D | Projection, target order | 3 sessions | After C; settle D-1 first | Rows, counts, exclusions and order identical for successful calls (snapshot) |
| E2 | Typed isolation results | half a session | After E1 | No `Followup` value changes (snapshot) |
| F | Macro frontend file | half a session | After 0.5, any time | No `Constraint` field changes; predicates equal by evaluation |

Each stage is its own PR. Stages A and E1 stack on `feature/phase7-docs`,
like the phase PRs (decision 6). The conventions from "Order of work inside
a phase" in `design/20260926_implementation_plan.md` apply: focused
`@testitem`s as each step lands, the full suite at the stage gate, coherent
commits, and no silent change to contract semantics. Where a stage finds
that the code and the contract disagree, the contract wins until you decide
otherwise at the stage review. Stages C, D and E2 end with the snapshot
diff, because their invariants are about figures, rows and order that must
not move. C and D also run the random-problem gate, which checks against
the oracle, and the benchmark fingerprint, which covers unconstrained IPOG
and speed.

## The structure this plan leaves behind

One owner per concern once every stage has landed, for reading the code
afterwards:

| Concern | Owner after the plan | Today |
|:--|:--|:--|
| Reading one caller's row into value indices | `_row_indices` (`space.jl`) | seven readers in six files |
| Reading a caller's collection of rows | `_row_list` | three |
| The candidate values of one kind of row | `_candidates(space, p, v)` (`space.jl`) | four expressions |
| Target order (the mixed-radix code) | `_code` and `_decode!` (`space.jl`) | `TargetList`, `_recount` and measurement, each by hand |
| Whether an assignment extends to a valid row | `completable` and `explain_partial` (`feasibility.jl`) | unchanged |
| From a search outcome to required, forbidden, implied or unknown | `IndexClassification` (`feasibility.jl`) | three places |
| A status with no explanation, for counting | `_status` (`feasibility.jl`) | none; every count built an explanation |
| What one call remembers | `FeasibilityContext`: one lazy-rule memo per public call, one answer cache per measurement (`explain.jl`) | one memo per measurement |
| Rows made ready for measurement | `PreparedRows` (`measure.jl`) | a tuple, rebuilt for each measurement |
| Negative targets, in one order | one enumerator, used by generation and measurement | two walks and a sort |
| The space as one kind of negative row sees it | the projection type (`invalid.jl`) | seven fields passed positionally |
| Why a suspect cannot be isolated, per kind | `FollowupProof`, and typed isolation results (`diagnose.jl`) | a union, and a named tuple with placeholder values |
| Rules written with macros | `constraint_macros.jl`, through `_function_rule` | a second copy of the construction |

The files, in include order (`src/UnitTestDesign.jl:29-49`), are also a
reasonable reading order:
- `rule_table.jl`, `constraints.jl` and `constraint_macros.jl` for rules;
- `space.jl` for the vocabulary, the indices and the row reader;
- `feasibility.jl` for search and classification in index space;
- `explain.jl` for the per-call context and the public questions;
- `request.jl` and `engines.jl` for generation;
- `measure.jl` and `report.jl` for measurement;
- the older index engines;
- `invalid.jl` for negative rows;
- `interface.jl` for the public generators;
- `diagnose.jl`.
