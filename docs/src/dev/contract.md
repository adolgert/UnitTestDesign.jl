# Contract

This page specifies what UnitTestDesign.jl 0.5 promises. It is the reference
for implementation, tests, documentation, and review. Clauses are numbered so
that code, tests, and reviews can cite them ("contract §3.4"). Each clause
states one requirement.

## 0. Conventions and terms

**0.1** "Must" and "must not" are requirements. "Error" means the call throws.
Invalid input throws an `ArgumentError` whose message uses the caller's
vocabulary (parameter names, values, case positions), unless a clause names
another exception.

**0.2** Clauses describe the 0.5 release. A phase that has not yet implemented
a clause must raise an explicit unsupported-feature error for inputs that need
it. It must not apply different semantics in the meantime.

**0.3** When implementation and contract conflict, the contract stands until a
review changes it. Tests are not edited to match a divergent implementation.

**0.4** Terms used below:

| Term | Meaning |
|:--|:--|
| parameter | A named dimension of the space. Its name is a `Symbol`. |
| domain | The ordered list of values a parameter may take. |
| value | One element of a domain, also called a choice. |
| ordinary value | Any value that is not an `Invalid`. A `Partition` is ordinary. |
| invalid value | A value wrapped as `Invalid(x)`. |
| assignment | Values for some parameters (partial) or all parameters (complete). |
| case, row | A complete assignment. Results contain rows. |
| ordinary row | A row with no invalid value. |
| negative row | A row with exactly one invalid value. |
| multiple-invalid row | A row with two or more invalid values. |
| rule | A constraint: scope, predicate, polarity, label (§12.1). |
| scope | The tuple of parameter names a rule reads. |
| applicable rules | The rules a row must satisfy (§5.4, §5.5). |
| valid row | A row that satisfies its applicable rules (§1.1). |
| combination | An assignment of ordinary values to a set of parameters. |
| group | A set of parameters with a strength. The base group is every parameter at the base strength. |
| target | A combination (or negative combination, §6) that a request asks to cover. |
| feasible | Contained in at least one valid row of the matching kind. |
| request | A space plus strategy, strength, `stronger`, `must_include`, engine, and limits. |

## 1. The semantic contract

### The six points

**1.1** An ordinary row is valid if and only if it satisfies every rule. A
negative row is valid under the policy of §5.5. A multiple-invalid row is
never valid.

**1.2** A combination is required if and only if it is feasible: at least one
valid row contains it. Infeasible combinations need no coverage, and the user
never has to write an implied rule. With rules `A == B` and `B == C` over
`(1, 2)`, the pair `(A = 1, C = 2)` is infeasible and not required.

**1.3** Every returned row is valid, and every required combination appears in
at least one returned row. This holds at the base strength, within every
`stronger` group, and for the negative targets of §6.

**1.4** Every target that is not required is reported with one of three
attributions:

- *direct*: one or more applicable rules whose scope lies within the target's
  parameters forbid it. Every such rule is named, in rule order.
- *implied*: no rule forbids it directly, and a deletion search found a set of
  rules proven sufficient to exclude it (§3.13–§3.16). The set may be a
  single rule whose scope reaches beyond the target's parameters.
- *unknown*: a resource limit prevented a conclusion; the target is neither
  required nor excluded (§1.7).

**1.5** The package never invents a cause. It names a rule only when that rule
takes part in a proven exclusion.

**1.6** User code never sees a partial case. A rule is evaluated only when
every parameter in its scope is assigned (§12.14).

**1.7** If a resource limit prevents a conclusion, the answer is `unknown`. It
is never reported as "infeasible", "feasible", or "complete" (§3).

### Targets and measurement

**1.8** Ordinary targets: for each group `(G, s)`, every assignment of
ordinary values to every `s`-subset of `G`. The request's targets are the
union over the base group and all `stronger` groups. A combination that
arises from two groups is one target.

**1.9** A target is covered by a set of rows when at least one valid row of the
matching kind contains it. Ordinary targets are covered only by valid
ordinary rows; negative targets only by valid negative rows (§5.9).

**1.10** A covered target is feasible, with the covering row as witness.
Measurement never needs a search to classify a covered target.

**1.11** Duplicate rows count once toward coverage.

**1.12** `coverage(cases, space; strength, stronger)` measures the supplied
rows against the space, independent of any generator bookkeeping.
`coverage(cases::TestCases)` uses the space and request stored in the result:
it measures at `cases.strength` and `cases.stronger`. For a result whose
strength is 0 (an excursion or a full factorial, §1.19),
`coverage(cases::TestCases)` is an `ArgumentError` asking for `strength =`,
and `report(cases)` measures at strength `min(2, parameter count)`, so at
strength 1 for a one-parameter space, and says so in its guarantee line. An
explicit `strength` replaces `cases.strength` and keeps `cases.stronger`
unless `stronger` is passed too. A stored group whose strength is below the
requested strength is an `ArgumentError` naming the group ("stronger group
(a, b, c) => 3 is below the requested strength 4; pass stronger = [] to drop
it"). An explicit `stronger` replaces the stored groups, and `stronger = []`
drops them.

**1.13** Rows given to `coverage` must be complete, use only the space's
parameter names, and use only domain values (§2.11). Anything else is an
input error naming the row and parameter.

**1.14** A row that violates its applicable rules, or has more than one
invalid value, is accepted as input, contributes no coverage, and is listed
in the result.

**1.15** A coverage result reports, for ordinary and negative targets
separately: covered, feasible, missing (named combinations), infeasible (with
attribution), unknown, and a breakdown per group.

**1.16** A coverage result is complete only when it has no unknown targets and
no missing targets.

**1.17** Coverage describes the rows supplied. It says nothing about test
outcomes; callers who want coverage by cases that ran or passed supply those
rows.

### Results and display

**1.18** Generation returns `TestCases{T} <: AbstractVector{T}`. `T` is a
`NamedTuple` type for named spaces and a `Tuple` type for positional calls.
`collect(cases)` returns a plain `Vector{T}`.

**1.19** A `TestCases` records its space, strategy (`:covering`, `:excursion`,
`:full_factorial`), strength (0 for a strategy that has none), `stronger`
groups, engine name and seed, the number of must-include rows, the excluded
targets with attribution and explanation status, and covered-target counts,
with ordinary and negative bookkeeping kept separate.

**1.20** A generated `TestCases` contains no target whose status is unknown
(§3.6).

**1.21** Before returning, generation checks every row against its applicable
rules and every required target against the rows. A failed check is an
internal error naming the row or target, never a returned result.

**1.22** `show` prints only what generation already recorded. It performs no
feasibility search, rule evaluation, or coverage recount. It shows the count
of valid rows in the full product only when that count is already known.

**1.23** Independent verification, bonus coverage at strength + 1, and the
prefix curve belong to `report` and `coverage`, never to `show`. The report
is the verification: the excluded targets it lists, with their rules and
explanation status, come from its own measurement under its own
`feasibility_limit` and `explanation_limit`, not from generation's
bookkeeping. Exclusions recorded at generation are a fallback, listed only
for targets the report's measurement left unknown, and each is identified
as recorded at generation.

**1.24** If the space is proven to have no valid ordinary row, covering
generation returns a result with no generated ordinary rows and reports every
ordinary target as excluded. This is not an error. Such a space can still
have valid negative rows, because a negative row skips every rule whose scope
contains its invalid parameter (§5.5). With `a` in `[1, Invalid(0)]`, `b` in
`[1]`, and a rule forbidding `(a = 1, b = 1)`, no ordinary row is valid, but
`(a = Invalid(0), b = 1)` is a valid negative row. Negative targets, negative
generation, and negative must-include rows are unaffected and follow §5, §6,
and §10. Ordinary must-include rows, and only they, fail validation: a
complete one under §10.3, and a partial one, which has no completion, under
§10.4.

### Checking assignments

**1.25** `isallowed(space, case)` accepts only complete rows and returns `true`
exactly when the row is valid. A partial assignment is an input error.

**1.26** `explain(space, assignment)` accepts complete or partial assignments
and returns one of five outcomes, each printable as a sentence and carrying
fields: `allowed`; `forbidden`, naming every rule whose whole scope is
assigned and which the assignment violates; `completable`, with one witness
row; `infeasible`, with a proven sufficient rule set and its minimality status;
`unknown`, naming the limit reached.

**1.27** `explain` applies the negative-row policy (§5.5) to an assignment that
contains one `Invalid`. An assignment with more than one is `forbidden`, and
the result says so rather than naming a rule.

## 2. Value identity

**2.1** Two values are the same choice if and only if
`typeof(a) === typeof(b) && isequal(a, b)`. Every stage that compares values
uses this rule: domain validation, pattern matching, must-include validation,
coverage keys, and diagnosis.

**2.2** `Any[1, 1.0]` is two choices. `Float32(1)` and `1.0` are different
choices. `0.0` and `-0.0` are different choices. `NaN` and `NaN` are the same
choice.

**2.3** Each supplied value is stored as given. Stored choices, tabulation
keys, coverage keys, and the values in returned cases keep their identity
(§2.1): no stage (storage, tabulation, rule evaluation, generation, result
construction, coverage) may promote, convert, or merge them. The documented
projections below are the only exceptions, each confined to its purpose:

- Rules, patterns, and targets see a `Partition` as its name (§4.5, §12.14).
  The name is the partition's identity (§2.13) and cannot equal another
  choice of the same parameter (§4.3, §4.4), so this merges nothing.
- `show` and `report` print a textual rendering of each value.
- `github_matrix` (§13.1) encodes values as JSON: a `Symbol` becomes a
  string, `nothing` becomes null, and `Invalid` and `Partition` wrappers are
  rejected.

A projection serves predicates and output, never identity. No stage compares,
deduplicates, or looks up choices by their projection, so two distinct
choices never become one because their projections coincide: `:x` and `"x"`
remain two choices even though `github_matrix` writes both as `"x"`.

**2.4** A value read from a returned row has the same concrete type as the
domain value and is `isequal` to it. Result element types are chosen so that
storing a value never converts it: a parameter whose values share one concrete
type gets that type, whatever the domain's element type (`Any[1, 2]` gives
`Int`); otherwise a `Union` of the values' concrete types (`Any[1, 1.0]` gives
`Union{Int64, Float64}`) or an abstract field type.

**2.5** A domain that lists the same choice twice is an error naming the
parameter and the value ("parameter `tol` lists `1.0` twice"). The same value
in two different domains is allowed.

**2.6** A domain must be a nonempty, ordered, finite collection: an
`AbstractVector` (ranges included) or a `Tuple`. Unordered collections such as
`Set` and `Dict` are errors. Domain order is preserved.

**2.7** A domain with a single value is allowed.

**2.8** Domains are copied when the space is built. Values themselves are not
copied. Mutating a value after building a space is unsupported.

**2.9** `nothing` and `missing` are ordinary values. No value denotes an
unassigned parameter. A partial assignment is written by omitting names from
a `NamedTuple`.

**2.10** Parameter names are distinct `Symbol`s, and a space has at least one
parameter. Positional calls name their parameters `p1`, `p2`, and so on.

**2.11** Wherever a caller writes a value in an assignment (patterns,
must-include rows, `from`, `explain`, `isallowed`, `coverage` rows), it must
match a domain value by §2.1. A `Partition` may be written either as the
wrapper or as its name (§4.5). An unmatched value is an error naming the
parameter, the value, and the domain.

**2.12** `Invalid(x)` and `Invalid(y)` are the same choice if and only if `x`
and `y` are the same choice by §2.1. `Invalid(x)` and `x` are different
choices; a domain may contain both.

**2.13** A `Partition`'s identity is its name. Its draw function is not part of
its identity.

## 3. Resource limits

### Feasibility

**3.1** Every feasibility question has one of three answers: *feasible*, with a
witness (a valid row containing the assignment); *infeasible*, proven by an
exhausted search; or *unknown*, because the search reached its limit.

**3.2** An unknown answer is never stored, cached, reported, or acted on as
feasible or infeasible.

**3.3** The keyword `feasibility_limit`, a positive `Int`, bounds each search.
Its default is `1_000_000` nodes. A node is one tentative assignment of one value to one
parameter in the backtracking search, counting assignments that are later
undone. Nothing else is a node. In particular, rule evaluations are not
counted against the limit: neither those of tabulation when the space is
built (§12.18) nor the rule checks a search makes, where a check is one
consultation of one rule on one assignment of its scope (a table lookup, or
a memoized evaluation for a lazily evaluated rule, §12.19). A search checks
rules in two places: the direct check, once per applicable rule whose scope
the queried assignment completes, and forward checking, which after each
node checks every rule that reads the assigned parameter and has exactly one
unassigned parameter left, once per surviving value of that parameter (an
initial prune does the same for every rule before the first node). So the
checks one node causes are at most the sum, over the rules it touches, of
the domain size of the parameter each has left, and a query's checks before
its first node are at most one per applicable rule plus that sum over every
applicable rule. `explain` and `classify` report the nodes and checks each
answer took. A separate budget for rule evaluations is deferred until the
Phase 3 benchmarks show a need for one.

**3.4** The budget belongs to one query: one completability question about one
assignment under one active rule set. Every connected component solved for
that query, including components with no assigned parameter, draws on the
same budget. An answer found in the run-local cache costs no nodes. There is
no run-wide total.

**3.5** Cache keys include the assignment and the active rule set. Search
caches are local to one call. An exhausted search is never cached as
infeasible. A lazily evaluated rule's memo (§12.19) is part of the operation
context too: a generation request, or one `explain` or `classify` call. The
operation's searches and its final validation share it, and it is released
with the operation. A `TestSpace` retains nothing from any operation.

**3.6** Generation resolves every target classification, the whole-space
feasibility check, every must-include completion, and every placement decision.
If any query is unknown, generation throws a resource-limit error. It never
returns a design with an unresolved target, never drops a target, and never
retries without bound.

**3.7** The resource-limit error is a distinct exception type,
`ResourceLimitError`. It names the operation, the limit and its value, and the
assignment or target being resolved, and suggests the keyword to raise. It
does not carry a usable design.

**3.8** To retry, call again with a larger limit, for example
`all_pairs(space; feasibility_limit = 10_000_000)`. Raising the limit never
changes a resolved answer; it can only resolve unknown ones. Two successful
generation calls that differ only in `feasibility_limit` return identical
results.

**3.9** Entry points that search accept `feasibility_limit`: `covering` and its
fixed-strength forms, `excursions`, `explain`, `coverage`,
`missing_interactions`, `report`, `design_sizes`, and `followups`.
`isallowed` and `full_factorial` evaluate only complete rows and do not search.

### Measurement and explanation under limits

**3.10** Measurement may return unknown targets. With any unknown target it
reports the known counts and lists the unresolved targets. It must not claim
complete coverage or print a single exact percentage; it may print bounds.

**3.11** `missing_interactions` returns the missing list only when every target
is resolved. Otherwise it throws `ResourceLimitError` and directs the caller to
`coverage` for the known missing and unresolved targets. An empty list never
hides uncertainty.

**3.12** `report` applies §3.10 to bonus coverage and to the prefix curve.
`design_sizes` reports a strategy's resource-limit status in place of a case
count or share. Both apply §3.10 to the ordinary and the negative figures
separately (§5.10).

**3.13** Explanation of implied exclusions has its own budget, the keyword
`explanation_limit::Int`, default `1_000_000` nodes, shared by all deletion
trials for one excluded target. Every entry point that attributes exclusions
accepts it.

**3.14** The deletion search starts from the full applicable rule set, which is
proven to exclude the target, and tries removing one rule at a time, in rule
order. A rule is removed only when the target is proven infeasible without
it. A trial that ends unknown keeps the rule.

**3.15** Proven infeasibility stays proven. Classifying a target as infeasible
never depends on the explanation search. When `explanation_limit` runs out,
the result keeps the last proven sufficient set and marks its minimality
unresolved.

**3.16** An explanation is labeled inclusion-minimal only when removing each of
its rules was verified to make the target feasible, with a witness.

**3.17** `followups` reports `unknown` for a suspect whose isolation search
reaches the limit. The search covers every kind of row that could hold the
suspect: for a suspect with no `Invalid` value, ordinary rows and the
negative rows at each invalid value of each parameter it leaves out (§5.5);
for a suspect with one, the negative rows at that value. The isolation
conditions (no other suspect) apply to every kind, including rules that
name the invalid parameter. A suspect is `inseparable` only when every kind
is proven to hold no isolating row, and `unknown` when no kind yields one
and some kind's search reaches the limit.

## 4. Partitions

**4.1** `Partition(name::Symbol, draw)` is a named choice. `draw(rng)` returns a
concrete value at run time. A fixed value is `Partition(:tiny, Returns(1e-9))`.
A name that is not a `Symbol` is an error.

**4.2** A `Partition` is an ordinary value. It satisfies the requirement of
§5.2.

**4.3** Partition names are unique within a parameter. A repeated name is an
error.

**4.4** A raw `Symbol` equal to a partition name in the same domain is an
error. The same `Symbol` in a different parameter's domain is allowed.

**4.5** Rules, patterns, coverage keys, reports, and display use the name.
Predicates receive the name as a `Symbol`.

**4.6** Returned rows hold the `Partition` wrapper. Iterating, indexing, or
displaying a `TestCases` never calls `draw`.

**4.7** `realize(case; rng)` substitutes `draw(rng)` for each `Partition`, in
parameter order, one call each. `rng` is a required keyword; no draw uses the
global random number generator.

**4.8** `realize` preserves shape: a `Tuple` stays a `Tuple` of the same length,
a `NamedTuple` keeps its names and order. Ordinary values and `Invalid`
markers pass through unchanged.

**4.9** `realize(cases; rng)` realizes each row in order with the same `rng`
and returns a plain `Vector`, not a `TestCases`.

**4.10** For a given case and `rng` state, `realize` is deterministic.

**4.11** Realization makes no coverage claim about the drawn values. Coverage is
measured on the labeled rows, which callers keep alongside the realized
inputs.

**4.12** Nested wrappers are unsupported. `Invalid(Partition(...))` and
`Invalid(Invalid(x))` are errors when the space is built. A `draw` that
returns a wrapper is an error at realization.

**4.13** Nothing is inferred from function-valued domains. A function in a
domain is an ordinary value; only the `Partition` wrapper triggers drawing.

## 5. Negative rows

**5.1** `Invalid(x)` marks `x` as an invalid value of the parameter whose
domain contains it. `hasinvalid(case)` is `true` exactly when a row contains
an `Invalid`.

**5.2** Every parameter has at least one ordinary value. A domain containing
only `Invalid` values is an error.

**5.3** A row is ordinary, negative, or multiple-invalid (§0.4).

**5.4** An ordinary row must satisfy every rule.

**5.5** A negative row whose invalid value is at parameter `p` must satisfy
every rule whose scope omits `p`. Rules whose scope contains `p` are not
evaluated for that row.

**5.6** Whole-case rules have every parameter in scope, so they never apply to
negative rows.

**5.7** Multiple-invalid rows are never valid. No strategy generates them,
they contribute no coverage, and a must-include row with more than one
`Invalid` is an error.

**5.8** Predicates never receive an `Invalid` wrapper. A pattern that names an
`Invalid` value is an error, because it could never apply.

**5.9** Only valid ordinary rows contribute to ordinary coverage. Only valid
negative rows contribute to negative coverage. A negative row never increases
ordinary coverage, including for the combinations among its ordinary values.

**5.10** Ordinary and negative coverage are reported separately in `coverage`,
`report`, and the `TestCases` bookkeeping. Every progress and planning figure
separates the two parts: `report`'s guarantee, bonus coverage and prefix
curve, and `design_sizes`'s case counts and pair and triple coverage. For a
space with `Invalid` values an ordinary figure is labeled as ordinary and
printed beside its negative figure, so no ordinary figure reads as the
whole.

**5.11** A row that violates its applicable rules contributes to neither kind of
coverage.

**5.12** In a generated result, generated ordinary rows precede generated
negative rows. Must-include rows precede both (§10.5).

## 6. Negative targets

**6.1** For each invalid value `v` of parameter `p`, and each requested group
`(G, s)` with `p` in `G` (the base group included), the negative targets are
every assignment `(p = v, a)` where `a` assigns ordinary values to an
`(s-1)`-subset of the other parameters of `G`.

**6.2** A negative target is feasible when some valid negative row (§5.5) with
`p = v` and ordinary values in every other parameter contains it.

**6.3** Negative targets are the union across the base group and all `stronger`
groups. A target that arises from two groups is one target.

**6.4** At strength 1 the subset is empty, so each invalid value has one target,
`(p = v)` alone. It is feasible when at least one valid negative completion
exists, and covering it takes one such row.

**6.5** A group that omits `p` adds no negative targets for `p`. Its ordinary
targets are already required of the ordinary rows.

**6.6** Example: at strength 2 with no `stronger` groups, each invalid value
appears with every feasible ordinary value of every other parameter.

**6.7** Generation covers every feasible negative target. Infeasible negative
targets are reported with attribution under §1.4. An unresolved negative
target stops generation under §3.6.

## 7. Strategy boundaries

**7.1** There are three strategies: covering, excursion, and full factorial.
The covering guarantee (§1.3) belongs to covering alone.

**7.2** `full_factorial` returns every valid ordinary row and every valid
negative row, each once, ordinary rows first. It never returns a
multiple-invalid row. Must-include rows precede them, in the order given with
duplicates kept (§10.5); a valid row equal to a must-include row is not
repeated.

**7.3** `full_factorial(space; limit = 10^6)` counts candidate rows before
enumerating: the ordinary product plus, for each parameter, its invalid
values times the product of the other parameters' ordinary values. Above
`limit` it throws `ResourceLimitError` giving the count and the keyword. The
result reports candidate and accepted counts separately.

**7.4** `full_factorial` enumerates incrementally and keeps only accepted rows.
Its result is a materialized `TestCases`.

**7.5** `excursions(space; from, distance = 1, must_include)` returns the
must-include rows, then the base, then every valid row, ordinary or
negative, that differs from the base in at most `distance` parameters, each
once. An excursion has exactly one distance, an integer of at least 0; a
negative distance is an error. Distance 0 returns the must-include rows and
the base alone. A distance above the parameter count is the parameter count.
Every returned row other than a must-include row is within Hamming distance
`distance` of the base (the number of parameters whose values differ), and
nothing widens it: an excursion has no groups, and a request with `stronger`
groups is an `ArgumentError` ("excursions take a single distance; stronger
groups apply to covering designs"). Excursion distance is not covering
strength: `strength` plays no part in an excursion, and a positional call's
`n_way` is its distance. It never returns a multiple-invalid row.

**7.6** `from` is a complete, valid, ordinary row. Omitted, it is the first
ordinary value of each parameter. A base that is partial, contains an
`Invalid`, or violates a rule is an error naming the cause, the rules it
breaks for a violation. The base is never dropped or replaced, at any
distance.

**7.7** A row within the distance that violates a rule is left out. Excursions
report how many rows were left out and the values that never appear in the
result. They make no covering claim, and their docstring says so.

**7.8** Without must-include rows, covering at strength equal to the parameter
count returns, as a set, the same rows as `full_factorial`: every valid
ordinary row and every valid negative row.

**7.9** Must-include rows follow the same row policy under every strategy
(§10). A partial must-include row without an `Invalid` is completed as an
ordinary row. A partial row with one `Invalid` at `p` is completed as a
negative row, with ordinary values elsewhere. Negative completion happens
only when the caller writes the marker.

**7.10** Completion never changes an assigned value.

**7.11** An excursion row identical to a must-include row is not repeated.

## 8. Honest size claims

**8.1** Engines produce compact designs. There is no promise of a minimum
number of rows, and no promise that one engine is smaller than another.

**8.2** Topping up an existing suite adds the rows the engine finds, not the
fewest possible.

**8.3** `design_sizes` reports the rows each engine produced. They are not
lower bounds.

**8.4** Documentation, docstrings, and printed output must not describe a case
count as minimal, optimal, or fewest.

**8.5** An implied-exclusion explanation is a sufficient rule set. It is
labeled inclusion-minimal only under §3.16. No clause promises a
minimum-size rule set.

**8.6** `diagnose` returns hypotheses, not proofs. `followups` prefers small
changes from a failing case, with no minimum-distance guarantee.

## 9. Determinism

**9.1** For identical inputs, the same package version, and the same Julia
version, generation returns identical results (rows, order, and bookkeeping)
in every run and process.

**9.2** Identical inputs means the same parameter names and order, the same
domain values in the same order, the same rules in the same order, and the
same request.

**9.3** No result may depend on hash iteration order, object addresses, thread
scheduling, the global random number generator, or the clock.

**9.4** IPOG uses no randomness.

**9.5** `GND(; seed = 0, candidates = 50, rng = nothing)` seeds a fresh
generator from `seed` at the start of every call, so repeated calls with the
same engine agree. The seed is recorded in the result and printed by
`report`. `seed` is an integer of at least 0 and `candidates` a positive
integer, each within `Int`; another value is an `ArgumentError` naming the
keyword.

**9.6** If `rng` is given, GND uses a copy of it at the start of every call,
leaves the caller's generator unadvanced, and records the seed as `nothing`.

**9.7** Lists in results (excluded targets, missing targets, unknown targets,
explanations) appear in an order fixed by the space and request, never by
hashing.

**9.8** Determinism across package versions is not promised. Any release may
change rows, their order, or their count while keeping every guarantee.

**9.9** Stability under edits is not promised. Changing a name, a value, value
order, a rule, or rule order may change every generated row.

**9.10** The one mechanism for stability is `must_include`. Passing a previous
result as `must_include` keeps every one of its rows, in order, and adds rows
only for targets those rows leave uncovered. Rows the edited space no longer
allows are errors under §10.

## 10. Must-include rows

**10.1** Named requests accept `NamedTuple`s, complete or partial, or a
`TestCases` whose parameter names all belong to the space (its rows are
partial if the space has more names). Positional requests accept tuples or
vectors whose length is the parameter count; a positional must-include row is
always complete.

**10.2** Every row is validated by name and value before generation begins.
Unknown names, out-of-domain values, and wrong lengths are errors naming the
row's position, the parameter, and the value.

**10.3** A complete row that violates its applicable rules, or has more than
one `Invalid`, is an error naming the violated rules.

**10.4** A partial row must have a proven completion. A proven infeasible
partial row is an error carrying its explanation. An unknown result throws
`ResourceLimitError`, which is distinct from infeasibility.

**10.5** Must-include rows come first in the result, in the order given, with
duplicates kept. A partial row is replaced, in place, by its completion.

**10.6** Must-include rows count toward coverage; generated rows cover what
remains. Duplicates count once (§1.11).

**10.7** The caller's collection is never mutated.

**10.8** `seeds` is a deprecated alias for `must_include`.

## 11. Strength and `stronger`

**11.1** `strength` is an integer of at least 1. Zero or a negative value is an
error.

**11.2** A strength greater than the parameter count is an `ArgumentError`. A
strength equal to it is a full factorial under the row policy (§7.8).

**11.3** `stronger` is a vector of `group => s` pairs. A named group is a tuple
or vector of `Symbol`s. A positional group is a tuple, vector, or range of
parameter indices.

**11.4** Every name in a group exists in the space, or every index lies in
`1:n`. Otherwise it is an error naming the group.

**11.5** Names within a group are distinct; a repeat is an error naming the
group.

**11.6** A group's strength is at least the base strength and at most the
group's size; otherwise it is an error naming the group.

**11.7** A group at the base strength is accepted and adds nothing.

**11.8** Overlapping groups combine by the union of their targets (§1.8).
Obligations never multiply. A group listed twice acts as its highest strength.

**11.9** The caller's `stronger` vector and its groups are never mutated. The
result records a copy.

**11.10** `n_way` is a deprecated alias for `strength`. `wayness` is deprecated
and translated: `Dict(3 => [[3, 4, 5, 6]])` becomes `[(3, 4, 5, 6) => 3]`.

## 12. Constraint forms and evaluation

### One representation

**12.1** Every rule compiles to one internal `Constraint` with a scope (a tuple
of parameter names), a predicate, a polarity (`:forbid` or `:require`), and a
label. Nothing downstream of construction distinguishes the surface forms.

**12.2** A `forbid` rule excludes rows where its predicate is `true`. A
`require` rule excludes rows where its predicate is `false`. Polarity is kept
for display.

**12.3** The label is the `reason`, the macro's source text, or both. A rule
with neither is labeled by its position in `constraints` and its scope.

### Surface forms

| Form | Example | Scope |
|:--|:--|:--|
| Pattern | `forbid((os = :mac, gpu = true); reason = "...")` | the pattern's names |
| Listed names | `require(:rows, :cols) do r, c; r == c end` | the listed names |
| Macro | `@forbid mode == :fast && solver != :none` | free identifiers |
| Whole case | `forbid(; reason = "...") do case; big(case) end` | every parameter |

**12.4** A pattern forbids rows whose values at the pattern's names are the same
choices (§2.1) as the pattern's values. Pattern values must be domain values.
There is no `require` pattern form.

**12.5** A listed-names rule receives the values of its scope positionally, in
the listed order. The names are distinct and there is at least one.

**12.6** In `@forbid` and `@require`, every free identifier not in call position
names a parameter. The scope lists them in order of first appearance.
`$x` interpolates the caller's `x` when the rule is built. Names bound inside
the expression are local, with Julia's scoping, when they are bound by one
of these forms: the arguments of `->` and of an anonymous `function`
(including keyword arguments and `do`-block arguments), `let` bindings, and
the variables of generators and comprehensions. Any other form that binds or
assigns a name or runs statements (an assignment outside a `let` binding,
`for`, `while`, `try`, `global`, `local`, a quoted expression, a macro call)
is an error when the macro expands, and the message points to the function
form `forbid(f, names...)`.

**12.7** In a macro rule, `nothing` and `missing` denote those values, not
parameter names. A parameter may not be named `nothing` or `missing`.

**12.8** A macro rule naming a parameter the space lacks is an error at space
construction. The message lists the space's names and suggests `$name` if a
variable was meant.

**12.9** A whole-case rule, `forbid(f; reason)` or `require(f; reason)`,
receives the complete row as a `NamedTuple`. Its scope is every parameter.

**12.10** Lambda argument-name rules are not supported. `disallow` is removed;
passing it is an ordinary unknown-keyword error.

### Where rules live

**12.11** Rules belong to the `TestSpace`. `coverage`, `explain`, `isallowed`,
excursions, and planning read them from the space.

**12.12** Generation calls given named domains (a `NamedTuple` or pairs)
accept `constraints =` and build the space. Given a `TestSpace`,
`constraints =` is an error ("constraints belong to the space"). Positional
calls reject `constraints =`.

**12.13** Construction errors name the parameter and list the space's names.

### Evaluation

**12.14** A rule is evaluated only when every parameter in its scope is
assigned, and only with ordinary values. Partitions are passed by name.

**12.15** A predicate must return a `Bool`. Any other return value, including
`missing` and `nothing`, is an error naming the rule.

**12.16** An exception thrown by a predicate is rethrown as an error naming the
rule's label and argument values, with the original exception as its cause.
An exception never means forbidden or allowed.

**12.17** Predicates must be deterministic and free of observable side effects.
They may be called more than once. Apart from tabulation (§12.18), call order
and count are unspecified.

**12.18** When the space is built, each scoped rule within
`tabulation_limit` (§12.19) is tabulated: evaluated exactly once per
combination of its scope's ordinary values, and the forbidden combinations
are stored. Rules are tabulated in the order given; within a rule,
combinations follow `Iterators.product` over the scope's domains in scope
order.

**12.19** A rule whose scope product exceeds `tabulation_limit` (a `TestSpace`
keyword, default `10^5` evaluations) is evaluated lazily with a memo. The
package warns once per rule and suggests a narrower scope. A lazy rule's memo
belongs to the operation context (§3.5): a generation request, or one
`explain` or `classify` call. It is keyed by value indices, shared by all of
that operation's feasibility searches, deletion trials, and final
validation, and released with the operation. Within an operation it holds
at most one entry per combination of the scope's ordinary values (the full
product of the ordinary domains for a whole-case rule), so a predicate is
evaluated at most once per combination per operation. A `TestSpace` retains
nothing from any operation: its size is the same before and after any call.
`isallowed`, which checks one row, may evaluate lazy rules without a memo.

**12.20** Whole-case rules are always evaluated lazily, memoized per row.

**12.21** Cost of whole-case rules, documented in their docstring: they connect
every parameter into one component, and deciding feasibility may search up to
the product of the unassigned domains, bounded by `feasibility_limit`.

**12.22** For a negative row at `p`, only rules whose scope omits `p` are
consulted (§5.5).

**12.23** Predicates compare values however the user writes them. `n == 1`
matches both `1` and `1.0`. Only patterns compare by identity (§12.4).

## 13. Vocabulary

**13.1** The 0.5 public names:

| Name | Kind | Status | Notes |
|:--|:--|:--|:--|
| `TestSpace` | type | new | Parameters, domains, rules. `parameters(space)`, `arity(space)`, `length(space)` (full product). |
| `constraints` | keyword | new | Rules for a space. |
| `forbid`, `require` | functions | new | Pattern, listed-names, and whole-case forms (§12). |
| `@forbid`, `@require` | macros | new | Bare-name rules (§12.6). |
| `must_include` | keyword | new | Replaces `seeds`. |
| `seeds` | keyword | deprecated | Alias for `must_include`. |
| `strength` | keyword | new | Replaces `n_way`. |
| `n_way` | keyword | deprecated | Alias for `strength`. |
| `stronger` | keyword | new | Replaces `wayness` (§11). |
| `wayness` | keyword | deprecated | Translated to `stronger`. |
| `TestCases` | type | new | Result of every generator. |
| `covering` | function | new | General entry point. |
| `all_tuples` | function | deprecated | Alias for `covering`. |
| `all_values`, `all_pairs`, `all_triples` | functions | kept | `covering` at strength 1, 2, 3. |
| `excursions` | function | new | Explicit base and distance (§7.5). |
| `values_excursion`, `pairs_excursion`, `triples_excursion` | functions | deprecated | Thin aliases for `excursions` at distance 1, 2, 3. |
| `full_factorial` | function | kept | Size guard (§7.3). |
| `coverage` | function | new | Measurement (§1.12). |
| `missing_interactions` | function | new | §3.11. |
| `explain`, `isallowed` | functions | new | §1.25–§1.27. |
| `report` | function | new | Verification, excluded list, bonus coverage, prefix curve, seed. |
| `design_sizes` | function | new | Cases per strategy before committing. |
| `diagnose` | function | experimental | `diagnose(cases, passed)`: ranked suspects; a pure function of cases and outcomes. |
| `followups` | function | experimental | Isolating cases per suspect: found, inseparable, or unknown. |
| `github_matrix` | function | new | JSON for a workflow `include:` list; validates every row before writing. |
| `Invalid`, `hasinvalid` | type, function | new | §5, §6. |
| `Partition`, `realize` | type, function | new | §4. |
| `ResourceLimitError` | exception | new | §3.7. |
| `IPOG()` | engine | kept | Default engine. |
| `GND(; seed = 0, candidates = 50, rng = nothing)` | engine | changed | Fixed default seed (§9.5). |
| `GND(M = ...)` | keyword | deprecated | Alias for `candidates`. |

**13.2** Deprecated names warn through `Base.depwarn` and are scheduled for
removal in the next breaking release. A keyword given together with its
deprecated alias (`strength` and `n_way`, `must_include` and `seeds`,
`stronger` and `wayness`, an excursion's `distance` and `n_way`, GND's
`candidates` and `M`) is an `ArgumentError`, whatever their values: a keyword
passed at its default value counts as passed, and neither one overrides the
other.

**13.3** Removed outright, with no alias: `disallow`, `generate_tuples`,
`Excursion`, and the `Counter` keyword.

**13.4** The positional path changes its return type:
`all_pairs([1, 2], ["a", "b"])` returns `TestCases{Tuple{...}}` where 0.4
returned `Vector{Vector{Any}}`. Rows are immutable tuples.

**13.5** In prose, the measured quantity is called *interaction coverage*, to
distinguish it from line coverage.

## 14. Not now

**14.1** The following are outside 0.5. Proposals for them need a new review.

| Item | Status in 0.5 |
|:--|:--|
| Test runner | None. Outcomes enter only through `diagnose(cases, passed)`. |
| Outcome files | None. |
| Model inference | None. The user writes the space. |
| Command-line interface | None. |
| Serialization framework | None. Rows are Tables.jl rows; `github_matrix` is the one exporter. |
| Solver (Z3, SAT) | None. Backtracking over tabulated rules. Rules stay data, so an extension remains possible. |
| Shrinking | None. |
| Fixture catalog | None. |
| `as_code` | None. Use `repr(collect(cases))`. |
| TOML specifications | None. |
| `max_cases` | None. |
| Rolling coverage across CI runs | None. |
| Evidence track (case study, mutation analysis) | Deferred until after 0.5. |

**14.2** Behavior not stated in this contract is not promised.
