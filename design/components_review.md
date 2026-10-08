## Overall assessment

The core architecture is sound. The next improvement should be clearer ownership of shared policy and operation state. The main components are recognizable, and the separation between constructing cases and measuring their coverage is especially valuable.

The maintenance risk sits between those components: several callers reconstruct row policy, target definitions, index mappings, and proof metadata themselves. That makes a semantic change require coordinated edits across generation, measurement, and diagnosis.

I reviewed the implementation, tests, contract, and phase notes. My recommendations, in priority order, follow.

## Component boundaries

 Component                       Assessment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Domain model and constraints    Good separation between user values and integer-indexed rules. Constraint syntax
                                 processing deserves its own file.
──────────────────────────────  ───────────────────────────────────────────────────────────────────────────────────────────
 Feasibility solver              The strongest boundary: explicit search budgets, witnesses, explanations, and unresolved
                                 results.
──────────────────────────────  ───────────────────────────────────────────────────────────────────────────────────────────
 Generation and engines          Sensible shared entry point and engine reuse. Request and negative generation know too
                                 much about surrounding internals.
──────────────────────────────  ───────────────────────────────────────────────────────────────────────────────────────────
 Measurement                     Valuable independence from generation. Row preparation, counting, and progress reporting
                                 are too tightly coupled.
──────────────────────────────  ───────────────────────────────────────────────────────────────────────────────────────────
 Reporting and diagnosis         Appropriate consumers of the core, but repeated measurement and flattened proof metadata
                                 weaken their interfaces.
──────────────────────────────  ───────────────────────────────────────────────────────────────────────────────────────────
 Realization and export          Clear responsibilities and explicit side effects. Little architectural change needed.

## 1. Give row policy and search construction one owner

Highest architectural priority.

The ordinary/negative distinction determines candidate values, applicable rules, rule-number mappings, and cache sharing. Those decisions appear in three different forms:

FeasibilityContext and feasibility_for (src/explain.jl:20) construct searches by row kind.

_negative_request (src/invalid.jl:52) renumbers rules, constructs a partial TestSpace, shares memo tables, and constructs another request.

_isolate (src/diagnose.jl:611) assembles applicable rules, candidate orderings, additional isolation rules, and memo tables again.

These differences have legitimate purposes, but each caller must understand the model and solver representations deeply. Negative generation is particularly exposed: changing TestSpace construction or memo ownership requires understanding its subspace construction.

Recommendation: extract a small internal layer around the existing context that owns:

Candidates and applicable rules for one row kind.
Parameter and rule mappings for projected problems.
Shared predicate memo ownership.
Construction of searches with additional rules or preferred candidate order.

Keep the choice of which row kinds to search with the caller. Coverage and follow-up isolation intentionally ask different questions.

The existing reuse of ordinary engines for negative generation is worth preserving; make the projection boundary explicit.

## 2. Separate the coverage specification from a generation request

Request (src/request.jl:59) currently combines coverage configuration, seeds, engine representation, search state, contexts, and limits. Its file also owns group validation, target enumeration, classification, and design validation.

Measurement consequently reaches into generation-oriented machinery for the definition of what coverage means. See _measure (src/measure.jl:517) and TargetList (src/request.jl:382).

Recommendation: introduce an internal coverage specification containing the validated strength, stronger groups, parameter subsets, and target-ordering rules. Both generation and measurement should consume it.

Then a generation request becomes a smaller composition of:

Coverage specification.
Seeds.
Search context.
Engine-facing index mappings.

This would also give negative-target projection and ordering a clearer home.

Preserve independent coverage counting and the independent test oracle. Sharing the definition of requested coverage should not mean trusting an engine’s bookkeeping when auditing its result.

## 3. Prepare measurement inputs once per operation

This is a concrete example of component coupling causing unnecessary work.

report (src/report.jl:184) measures the requested strength, then _bonus starts another measurement. Each measurement converts and validates the same rows, deduplicates them, builds matrices, and creates a fresh feasibility context. design_sizes (src/report.jl:616) repeats the pattern for pairs and triples.

I instrumented a whole-case predicate on a three-parameter binary space. Reporting a four-row design called the predicate 12 times across only eight possible complete assignments. This demonstrates repeated work; it does not establish a runtime bottleneck.

Additionally, _coverage calls _measure, which builds both progress curves even when the caller only needs coverage.

Recommendation: separate:

Preparing and validating rows.
Measuring a coverage specification.
Collecting optional progress information.

A prepared input should retain indexed rows, row kinds, duplicates, rejections, and original positions. A report can reuse that input and its measurement context for base and bonus coverage.

Keep this state local to the reporting operation. The current decision to keep caches out of TestSpace is good.

## 4. Preserve the scope of explanations when combining them

This is an API clarity and evidence-model issue, rather than an incorrect isolation result.

_followup (src/diagnose.jl:684) unions the proofs from different row kinds and combines their minimal statuses. The field documentation (src/diagnose.jl:428) explicitly defines verification per kind, but the returned fields no longer say which rules belong to which proof.

I reproduced a result with:

rules = [1, 2]
minimal = :verified

where rule 1 alone excludes the suspect across all eligible row kinds. The individual proofs meet the documented narrower definition; their union is not globally minimal.

Recommendation: retain proof records containing the row kind, rules, other suspects, and minimality status. Expose the union as a sufficient combined explanation.

If the public API promises global minimality, perform deletion checks against the combined question. Otherwise, make the narrower meaning explicit in the field name or returned structure.

Small internal result types would also help _isolate, whose found, unknown, and proven results currently share a large named tuple with sentinel values. Focus on preserving invariants and proof provenance.

## 5. Remove unused engine code before consolidating active algorithms

There is removable historical machinery in the production source.

Repository searches found no callers for helpers such as:

pairs_in_entry
combination_histogram, most_to_cover, and most_common_value
fill_missing_test_set_values! and cover_remaining_by_creating_cases

Other paths survive through tests or those unused helpers: first_match_for_parameter, fill_consistent_matches, multi_way_coverage, and the old n_way_coverage wrapper. See src/coverage_matrix.jl:93, src/parameter_order.jl:34, and src/greedy_tuples.jl:246.

Recommendation: remove unused internals, move intentional reference implementations into test support, and preserve useful behavioral checks through the supported entry points. This reduces the amount of code a maintainer must understand before changing an engine.

The classic IPOG implementation is still used by the unconstrained fast path (src/parameter_order.jl:475). Evaluate any consolidation of that path with benchmarks and deterministic-output checks. Its duplication has a stronger justification than the unused helpers.

## 6. Share row parsing while keeping each API’s policy explicit

_coverage_row (src/measure.jl:195) and _diagnosis_row (src/diagnose.jl:261) are nearly the same parser. Seed handling and excursion baselines repeat parts of that work.

The shared mechanics include tuple/vector length checks, conversion to indices, missing parameters, and contextual error messages. The acceptance policies differ:

Seeds may be partial.
Coverage records invalid rows.
Diagnosis must accept observations that violate constraints.

Recommendation: extract a small assignment-normalization helper with an explicit completeness requirement and error context. Leave validity and rejection policy in each caller.

This is a straightforward reduction in duplication without creating a generic input-processing framework.

## 7. Isolate the constraint macro frontend

The macro walker (src/constraints.jl:263) handles lexical bindings, lambdas, generators, interpolation, destructuring, and several expression forms. That is substantial language-processing code sharing a file with constraint representation and rule compilation.

Recommendation: move it into a dedicated frontend file whose output is an ordinary Constraint. Keep syntax and hygiene tests together, and retain explicit predicate constructors as the escape hatch for complex expressions.

The supported language explains much of this complexity. Isolating it will make changes easier to review; simplifying it carelessly could remove valid behavior.

## What I would preserve

Several choices are doing useful architectural work:

Integer-indexed rules separate solver logic from heterogeneous user values.
Feasible, infeasible, and unresolved outcomes remain distinct.
Search and explanation budgets have separate meanings.
Generated rows undergo validation.
Measurement can audit externally supplied cases.
The brute-force test oracle (test/checker.jl:1) shares no implementation with the package.
Realization and export have narrow responsibilities.

The current single-module organization is workable. Clearer internal ownership can be achieved with a few focused types and functions.

## Suggested sequence

Small cleanup: remove unused helpers, extract common row parsing, isolate macro code.
Core refactor: separate coverage specifications and centralize search/projection construction.
Consumer cleanup: reuse prepared measurement inputs and preserve scoped proof records.
Then reassess engine duplication using benchmarks.

The desired outcome is that changing negative-row semantics or target definitions has one obvious implementation owner.

Verification: the full suite produced 308,204 passing assertions, with one Aqua error caused by sandbox access to Julia’s cache. All Aqua checks passed when rerun with that access approved. I also ran the focused probes described above. No repository files were changed.



