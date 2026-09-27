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
(Superseded by review round 1, item 1: the positional generators now
refuse wrapper values.)

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
   resolve to a `Base` constant? (Answered in review round 1: keep `$Inf`
   explicit. The binding forms were rewritten, item 2.)
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


## Review round 1

Date: 2026-09-27. Four findings, all applied. Full suite after the round:
see the totals at the end of this section.

### 1. Wrapper guard on legacy generation

Before: `all_pairs(Any[1, Invalid(0)], Any[1, Invalid(0)])` returned rows
with two `Invalid` values. Now `all_tuples` (so `all_values`, `all_pairs`,
`all_triples` and the three excursions, every engine) and the public
`full_factorial(parameters...; disallow)` call `_reject_wrappers`, which
throws an `ArgumentError` for the first domain holding an `Invalid` or
`Partition`:

```
ArgumentError: parameter 1 lists Invalid(0), but generation with Invalid or
Partition values is not supported yet; it arrives in a later release phase
(contract §0.2). A TestSpace accepts these values for isallowed and explain.
```

It is an `ArgumentError`, not a new exception type, so the temporary guard
adds no public surface; the helper carries a "Remove in Phase 6" comment.
`nothing`, `missing`, and a plain `Symbol` such as `:tiny` still generate.

Found on the way: `full_factorial(d1, d2)` with exactly two domains
dispatched to the internal `full_factorial(arity, disallow)` and threw a
`MethodError`, so the guard (and two-parameter full factorials in general)
never ran. The internal method is now typed
`(arity::AbstractVector{<:Integer}, disallow::Function)`; its callers and
`test_full_factorial.jl` pass exactly those types.

Tests: `test/test_legacy_guard.jl` (new; marked pending Phase 6, when
negative generation replaces the guard): nine calls across `all_pairs`
(IPOG and GND), `all_values`, `all_triples`, `full_factorial` (three
domains, two domains, with `disallow`), `pairs_excursion` and
`values_excursion`, each naming the parameter position; and ordinary
domains with `nothing` and `missing` still generating.

### 2. Macro binding forms

Before: `@forbid((x -> x > n)(1))` said "reads no parameter", because a
callee that was an expression was left unwalked, and
`@forbid(let x = n; x > 1 end)` took `x` for a parameter. The walker in
`src/constraints.jl` is rewritten around a `_RuleWalk` state with explicit
scopes, walking subexpressions in source order so the scope keeps the
order of first appearance.

Supported binding forms, each with Julia's scoping:

- `->`: a single argument, a tuple, `(x; kw) ->`, typed and splatted
  arguments, destructuring, and default values (a default sees the
  arguments before it; a type annotation is the caller's).
- anonymous `function (args) ... end`, read like `->`.
- `let a = x, b = y; body end`: each right side sees the enclosing scope
  and the bindings before it (so `let n = n + 1` reads the parameter `n`);
  the body sees them all. The review's wording, "each binding's right side
  is walked in the outer scope", was implemented as Julia's sequential
  `let`, which agrees with it for a single binding.
- generators and comprehensions, including filters, products
  (`x in xs, y in ys`: every iterator in the outer scope) and nested
  levels (`for x in xs for y in f(x)`: a later iterator sees earlier
  variables).
- `do` blocks: the call, then the block as an anonymous function.

Also: a callee that is an expression is walked (`(x -> x > n)(1)`,
`$f(x)`), which makes `(f ∘ g)(n)` read `f` and `g` as parameters, as the
literal rule says; a field of a computed value, `(; a = n).a`, walks the
value, while a dotted *name* (`Base.isodd`, `p.field`) stays the caller's;
`f(x; tol)` and `(; tol)` keep the keyword name when `tol` is a
parameter; a nonstandard string literal (`r"a+"`) is a value. Labels no
longer carry `#= file:line =#` comments from macro calls.

Rejected when the macro expands, with an `ArgumentError` naming the form
and ending "For anything else, use the function form forbid(f, names...)"
(or `require(...)`): assignments outside a `let` binding (`=`, `+=`, ...),
`for`, `while`, `try`, quoted expressions, `global`/`local`/`const`,
macro calls other than string literals, named function definitions (in an
expression or a `let`), `where` clauses, and any other head not listed
above. Kept: identifiers in call position are calls, dotted names are the
caller's, `nothing`/`missing`/`true`/`false` are values, and `$Inf` stays
explicit (`@forbid(x < Inf)` still has scope `(x, Inf)`).

Regression list (`test_constraints.jl`, "macro binding forms follow
Julia's scoping"): each macro rule's scope and table equal those of the
explicit `forbid(pred, names...)`, and each table forbids some but not all
combinations: the lambda call, `let`, sequential `let` with a shadowed
parameter, a generator (`any(v > n for v in (1, 2))`), a comprehension
with a filter, a product generator, nested generator levels, the shadowed
lambda `(n -> n)(m) > n` (scope `(m, n)`, value `m > n`), `$t` inside a
lambda (captured at build time), an anonymous `function`, a `do` block,
positional and keyword defaults, `(x; w = m) ->`, and a named tuple with
`(; m)`. A second item checks thirteen rejected forms for the guidance
text.

Contract §12.6 now lists the supported binding forms and says other forms
are rejected with a pointer to the function form.

### 3. What the feasibility budget bounds

Contract §3.3 now says what a node is and is not: rule evaluations of
tabulation and the search's rule checks (a check is one consultation of
one rule on one assignment of its scope: a table lookup, or a memoized
evaluation for a lazy rule) are not counted; the checks one node causes are
at most the sum, over the rules it touches, of the domain size of the
parameter each has left; a query's checks before its first node are at
most one per applicable rule plus that sum over every applicable rule; and
a separate evaluation budget is deferred until the Phase 3 benchmarks show
a need.

Counter design: `SearchStats.evaluations` counts every `forbids` call made
through a `Feasibility`: the direct check (`violates`, `violated_rules`,
and the checks inside `completable` and `explain_partial`) and every
forward-checking prune. `IndexExplanation` and `IndexClassification` gain
`nodes` and `evaluations`: the cost of that one answer, including its
deletion trials (which run on their own `Feasibility` objects and are
summed in). The public `Explanation` and `Classification` carry the same
two `Int` fields. That was the smaller change than a `stats` field: the
counters are per `Feasibility`, shared across the targets of one
`classify` call, so a stats snapshot would have needed per-answer deltas
anyway. Costs depend on what the call had already cached, so the
determinism test now compares answers without them.

Hand count (Astra, `A == B`, `B == C`): from nothing, 3 nodes and 4
checks; `(A = 1, B = 2)` is forbidden with 0 nodes and 1 check;
`(A = 1, B = 1, C = 1)` is allowed with 0 nodes and 2 checks; `(A = 1,
C = 2)` is infeasible with 0 search nodes and 3 checks, plus 2 nodes and 4
checks in the two deletion trials (7 in all).

The 2,000-value probe (`x in 1:2000`, a unary rule forbidding `x < 2000`,
lazy because `tabulation_limit = 1000`): `explain(space, (;);
feasibility_limit = 1)` is **`:completable`, not `:unknown`**, with the
witness `x = 2000`, 1 node and 2,000 checks. The accounting is right: all
2,000 checks happen in the initial prune, before the first node, and the
one node assigns the one survivor. The predicate runs 2,000 times on the
first call and 0 times on a second call (the memo answers), which still
reports 2,000 checks. With a two-parameter scope (`a in 1:2`, the same rule
on `(a, x)`) the checks follow a node: at limit 1 the answer is
`:unknown` after 1 node and 2,000 checks, because the answer needs two
assignments; at limit 2 it is `:completable` with 2 nodes and 2,000
checks.

### 4. Lazy-cache ownership

Contract §12.19 now says a lazy rule's memo is part of the space's
tabulation (a table built on demand): it lives as long as the space, is
keyed by value indices so every call on the space shares it, and holds at
most one entry per combination of its scope's ordinary values (the full
product for a whole-case rule); it is not a search cache. §3.5 says
*search* caches are local to one call and points to §12.19.
`design/benchmark_procedure.md` ("What to record") now asks Phase 3 to
record `Base.summarysize(space)` and `memo_size(space)` before and after
generation on `bench12` and on the 15×4 fixture, each with a whole-case
rule, and to decide from that measurement whether to keep, bound, or move
the memo into the request context. It also asks for nodes and checks
beside the timings.

`UnitTestDesign.memo_size(space)` (unexported, `src/space.jl`) returns the
number of memoized entries across the space's lazy tables. Tests: it is 0
before any question, grows across two `explain` calls on a whole-case
rule, stays within the 18-row product, does not grow when a question is
repeated, is 0 for a fully tabulated space after `explain` and
`classify`, and counts a scoped rule made lazy by `tabulation_limit`.

### Suite after round 1

`julia --project -e 'using Pkg; Pkg.test()'` on Julia 1.13.1: 334,312 pass,
31 broken/skipped (unchanged: the pending lines of later phases), 0
failures, 5 min 10 s. Aqua green. The constraints, legacy-guard,
feasibility and explain test files also pass on Julia 1.10.12, the floor.

