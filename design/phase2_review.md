# Phase 2 review: the model — `TestSpace`, rules, feasibility

Date: 2026-09-26. Branch `feature/phase2-model`, stacked on
`feature/one-oh` (PR #52); retarget to `release/1.0` once #52 merges.
Plan: `design/20260926_implementation_plan.md`, Phase 2.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1, 2 | `TestSpace`, `Invalid`, `Partition`, `hasinvalid`, value identity, `active_tables` (negative-row rule selection) | `src/space.jl` |
| 3, 4 | `Constraint`, `forbid`/`require` in pattern, named, and whole-case forms, `@forbid`/`@require`, `ConstraintError` | `src/constraints.jl` |
| 5 | Tabulation into `RuleTable`s, lazy above `tabulation_limit`, whole-case always lazy | `src/constraints.jl`, `src/rule_table.jl` (new: the index-space boundary) |
| 6 | `Feasibility`, `violates`, `completable`, `dead`, `classify`, deletion search, `ResourceLimitError` | `src/feasibility.jl` |
| 7 | `isallowed`, `explain`, unexported `classify(space, targets)` | `src/explain.jl` |
| 8 | Tests | `test/test_space.jl`, `test_constraints.jl`, `test_feasibility.jl`, `test_explain.jl`; adapter `test/fixture_model.jl`; 12 Phase 2 pending lines flipped in `test_fixtures.jl` |

Exports added: `TestSpace`, `Invalid`, `Partition`, `hasinvalid`,
`Constraint`, `forbid`, `require`, `@forbid`, `@require`, `parameters`,
`ConstraintError`, `ResourceLimitError`, `isallowed`, `explain`.

Full suite: 332,527 pass, 31 broken/skipped, 0 failures, about 5 minutes.
The broken count fell from 43 by exactly the 12 Phase 2 lines. Aqua green.
The model tests also pass on Julia 1.10.12, the floor.

## Independent checks

- Every table matches brute-force evaluation of its rule, and valid
  ordinary and negative rows match the checker on every fixture up to
  10^4 rows and on 40 random problems.
- `classify` agrees with the checker's `classify_target` on all pairs of
  every fixture (negative targets included) and on 100 random problems;
  for `:forbidden` the rule sets match; for `:implied` the checker
  confirms the rule set is sufficient and minimal on sampled targets.
- The index-space search agrees with brute-force enumeration on 11,785
  targets from 200 random problems; every witness satisfies every table;
  small-limit answers are correct or `:unknown`, never wrong.
- Node budget is exact: a search needing N nodes succeeds iff the limit is
  at least N (hand-counted: Astra 3, `limit_exhaustion` 21845 from empty).

## Transcript of the acceptance examples

```
# Rule forms, all compiling to one Constraint
TestSpace with 3 parameters, 12 combinations, 2 constraints
  mode:   :fast, :exact
  solver: :none, :lu, :qr
  tol:    0.001, 1.0e-6

Any[Set([(1, 2), (1, 3)]), Set([(2, 1)]), "lazy"]

# The solver example: 3 direct, 2 implied
(mode = :fast, solver = :lu) => forbidden rules=[1] minimal=not_applicable
(mode = :fast, solver = :qr) => forbidden rules=[1] minimal=not_applicable
(mode = :exact, tol = 0.001) => forbidden rules=[2] minimal=not_applicable
(solver = :lu, tol = 0.001) => implied rules=[1, 2] minimal=verified
(solver = :qr, tol = 0.001) => implied rules=[1, 2] minimal=verified

# explain
infeasible: no valid case contains (solver = :lu, tol = 0.001); rules 1 and 2 together exclude it (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
forbidden by rule 2 (exact mode needs a tight tolerance)
completable, e.g. (mode = :exact, solver = :lu, tol = 1.0e-6)
allowed: (mode = :exact, solver = :lu, tol = 1.0e-6) is a valid case
false

# Astra: A == B, B == C
infeasible: no valid case contains (A = 1, C = 2); rules 1 and 2 together exclude it (rule 1: @require(A == B); rule 2: @require(B == C))

# Opus: os/gpu/driver
infeasible: no valid case contains (os = :windows, gpu = true); rules 1 and 2 together exclude it (rule 1: @forbid(gpu && driver == :none); rule 2: @forbid(os == :windows && driver == :cuda))

# Disconnected components
infeasible: no valid case contains (free = 1,); rules 1 and 2 together exclude it (rule 1: @forbid(a == b); rule 2: @forbid(a != b))
completable, e.g. (a = 3, b = 3, c = 2, d = 2, e = 1)
witness valid: true

# nothing is a value; heterogeneous domain
forbidden by rule 1 (@forbid(x === 1.0 && y === nothing))
allowed: (x = 1, y = nothing) is a valid case

# unknown under a limit, then retry
unknown: feasibility_limit = 1 reached; retry with a larger limit
completable, e.g. (x1 = 4, x2 = 4, x3 = 4, x4 = 4, x5 = 4, x6 = 4, x7 = 4, x8 = 4)

# Negative rows
false false true
completable, e.g. (n = Invalid(-1), m = 2)

# Errors in the user's vocabulary
ArgumentError: parameter `tol` lists `1.0` twice (contract §2.5)
ArgumentError: rule 1 (@forbid(mode == :a && solver == :b)) names `solver`, which is not a parameter of this space. The parameters are mode. If `solver` is a variable, write `$solver` to use its value.
no error
ArgumentError: parameter `n` has only Invalid values; it needs at least one ordinary value (contract §5.2)
ArgumentError: parameter `s` has both the Symbol :tiny and the partition Partition(:tiny). Rules see a partition by its name, so the two could not be told apart (contract §4.4).
ArgumentError: rule 1 on (n) returned 1, which is not a Bool, for (n = 1,). A rule must return true or false (contract §12.15).
```

(The "no error" line is the demo's fault: `n / 0` on an `Int` is `Inf` in
Julia, so the predicate did not throw. Exception wrapping in
`ConstraintError` is covered by `test_constraints.jl`.)

## Pending tests after this phase (31)

| Phase | Count | What |
|:--|--:|:--|
| 3 | 14 + 4 gate lines | generation on every fixture, dead ends, `bench12`, `ResourceLimitError` from generation; IPOG `@test_broken` and GND `@test_skip` per strength |
| 4 | 5 | typed values preserved in results, `must_include`, `stronger` |
| 5 | 3 | coverage/report |
| 6 | 5 | negative generation, partitions kept, negative must-include |

Note: the plan's Phase 2 step 2 asks generation on wrapper spaces to
raise an unsupported-feature error. Generation does not accept a
`TestSpace` at all until Phase 3/4, so there is nothing to guard yet.

## Decisions made where the plan or contract was silent (for review)

1. **File layout:** `src/rule_table.jl` holds the index-space `RuleTable`
   (scope, tabulated `Set` or lazy memoized function). It is the boundary
   between the model and the search, and Phase 3's engines consume it.
2. **`space.values` is a `Vector{AbstractVector}`** (each a copy keeping
   the user's element type), not the plan's "tuple of vectors".
3. **Macro name rule, literal reading of §12.6:** any bare identifier not
   in call position is a parameter name, so `tol < Inf` fails with the
   unknown-name error suggesting `$Inf`. Dotted names (`Base.isodd`,
   `p.field`) are read from the caller, so a parameter's field needs
   `getproperty(p, :field)`. Variables bound by `->`, generators, and
   comprehensions are recognized as local; `let` bindings are not (use the
   function form). Parameters become gensym arguments, so a parameter
   named `size` does not shadow `Base.size` inside its own rule.
   Review question: keep the literal rule, or exempt identifiers that
   resolve to a `Base` constant?
4. **Labels:** the macro cannot see raw source, so labels use Julia's
   expression printing (`1e-3` prints as `0.001`; `$x` prints as `$x`).
   With a reason, the label is `"reason: @forbid(...)"`. An unlabeled rule
   is `"rule k on (a, b)"`.
5. **Nested wrappers** are rejected when the wrapper is built, earlier
   than "when the space is built" (§4.12).
6. **Feasibility budget accounting (§3.13, §3.14):** each deletion trial
   runs with `min(feasibility_limit, remaining explanation budget)` and
   its nodes count against `explanation_limit`; a trial ending `:unknown`
   keeps its rule and the result is `:unresolved`, naming which limit
   decided. `:verified` only when every kept rule had a feasible trial
   with a witness.
7. **`completable(f, partial; limit)`** accepts a per-call limit override
   so a retry can reuse the caches, which is sound because only proven
   answers are cached.
8. **Naming:** the public result of `explain` has `outcome`; the records
   from `classify` have `status`. Index-space types are
   `IndexExplanation`/`IndexClassification`, unexported.
9. **Explain on two `Invalid` values** returns `:forbidden` with no rules
   and a sentence saying a case holds at most one (§1.27, §5.7).
10. **Per-call cache key is `(p, v)`**, not `p`, since a parameter can hold
    two `Invalid` values.
11. **Checker adapter:** `CheckPartition(n)` becomes
    `Partition(n, Returns(n))`; a checker rule whose scope covers every
    parameter becomes a whole-case (lazy) rule, which is the checker's own
    definition; the semantics are identical.
12. **Leniency:** `constraints` also accepts a tuple or a single
    `Constraint`; `hasinvalid` accepts vectors; `from_indices` accepts
    partial index vectors.
