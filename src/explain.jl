# The public questions about assignments: `isallowed`, `explain`, and
# `classify` over a TestSpace (plan Phase 2 step 7; contract §1.4,
# §1.25–§1.27, §3, §5.5). They translate between the caller's vocabulary and
# index space (space.jl) and ask the feasibility layer (feasibility.jl).


"""
    FeasibilityContext(space; feasibility_limit = 1_000_000)

The feasibility searches of one public call (contract §3.5: caches are local
to one call). It holds one `Feasibility` per row kind: ordinary
rows, and negative rows with a given invalid value at a given parameter.
Each has its own candidates and active rule set (§5.5), so no cached answer
crosses from one kind to another. Build one per call and pass it to
`feasibility_for`; drop it when the call returns.
"""
struct FeasibilityContext
    space::TestSpace
    feasibility_limit::Int
    searches::Dict{Tuple{Int, Int}, Tuple{Feasibility, Vector{Int}}}
end

function FeasibilityContext(space::TestSpace; feasibility_limit = 1_000_000)
    _check_limit(:feasibility_limit, feasibility_limit)
    return FeasibilityContext(space, Int(feasibility_limit),
        Dict{Tuple{Int, Int}, Tuple{Feasibility, Vector{Int}}}())
end

function _check_limit(keyword::Symbol, limit)
    (limit isa Integer && limit >= 1) || throw(ArgumentError(
        "$keyword must be a positive Int; got $(repr(limit)) (contract §3.3, §3.13)"))
    return nothing
end

"The parameters whose value in `idx` is an `Invalid`, in parameter order."
_invalid_parameters(space::TestSpace, idx::AbstractVector{<:Integer}) =
    [p for p in eachindex(idx) if idx[p] != 0 && idx[p] in space.invalid[p]]

"""
    feasibility_for(context::FeasibilityContext, idx) -> (f::Feasibility, rules::Vector{Int})
    feasibility_for(space, idx; feasibility_limit = 1_000_000) -> (f, rules)

The feasibility search that decides the partial index vector `idx` (see
`case_indices`), and `rules`, the constraint position of each of `f`'s
tables, so that `rules[k]` is the space's rule behind table `k`.

- With no `Invalid` value in `idx`, the row is ordinary: every parameter takes
  its ordinary values, and every rule applies (contract §5.4).
- With one `Invalid` value `v` at parameter `p`, the row is negative:
  parameter `p` takes only `v`, the others their ordinary values, and only the
  rules whose scope omits `p` apply (§5.5, §12.22).
- Two or more `Invalid` values are an `ArgumentError`: no such row is valid
  (§5.7).

The context form reuses one search per row kind, keyed by `(p, v)`, with
`(0, 0)` for ordinary rows. The space form builds a fresh search.
"""
function feasibility_for(context::FeasibilityContext, idx::AbstractVector{<:Integer})
    space = context.space
    n = length(space.names)
    length(idx) == n || throw(ArgumentError(
        "an index vector for this space has $n entries; got $(length(idx))"))
    bad = _invalid_parameters(space, idx)
    length(bad) > 1 && throw(ArgumentError(
        "the assignment has Invalid values for $(join(space.names[bad], ", ")); a case " *
        "holds at most one Invalid value (contract §5.7)"))
    p = isempty(bad) ? 0 : only(bad)
    v = p == 0 ? 0 : Int(idx[p])
    return get!(context.searches, (p, v)) do
        candidates = [q == p ? [v] : space.ordinary[q] for q in 1:n]
        rules = active_rules(space, p)
        (Feasibility(candidates, space.tables[rules]; limit = context.feasibility_limit), rules)
    end
end

feasibility_for(space::TestSpace, idx::AbstractVector{<:Integer}; feasibility_limit = 1_000_000) =
    feasibility_for(FeasibilityContext(space; feasibility_limit), idx)


## isallowed

"""
    isallowed(space::TestSpace, case) -> Bool

Whether the complete `case` is a valid row of `space` (contract §1.25). `case`
is a `NamedTuple` naming every parameter, in any order, or a `Tuple` of values
in parameter order. Values are matched by identity, and a
[`Partition`](@ref) may be written by its name (§2.11).

An ordinary row is valid when no rule excludes it. A row with one
[`Invalid`](@ref) value, at parameter `p`, is valid when no rule whose scope
omits `p` excludes it; rules that read `p` are not evaluated (§5.5). A row
with two or more `Invalid` values is never valid (§5.7).

`isallowed` evaluates rules on the one row and never searches (§3.9). A
partial case, an unknown name, or a value outside its parameter's domain is
an `ArgumentError`; use [`explain`](@ref) for partial assignments.

```julia
space = TestSpace((mode = [:fast, :exact], tol = [1e-3, 1e-6]);
    constraints = [forbid((mode = :exact, tol = 1e-3))])
isallowed(space, (mode = :exact, tol = 1e-6))  # true
isallowed(space, (:exact, 1e-3))               # false
```
"""
function isallowed(space::TestSpace, case::Union{NamedTuple, Tuple})
    idx = case_indices(space, case)
    unset = space.names[idx .== 0]
    isempty(unset) || throw(ArgumentError(
        "isallowed takes a complete case, but $(repr(case)) has no value for " *
        "$(join(unset, ", ")). Use explain for a partial assignment (contract §1.25)."))
    bad = _invalid_parameters(space, idx)
    length(bad) > 1 && return false
    p = isempty(bad) ? 0 : only(bad)
    return !any(t -> forbids(t, idx), active_tables(space, p))
end


## explain

"""
    Explanation

The result of [`explain`](@ref): why an assignment is or is not part of a
valid row (contract §1.26). It prints as one sentence. Fields:

- `assignment`: the assignment explained, as a `NamedTuple` in parameter
  order, with values as the domain stores them.
- `outcome`: one of
  - `:allowed`, a complete, valid row;
  - `:forbidden`, excluded directly: `rules` names every rule whose scope is
    entirely assigned and which excludes the assignment. An assignment with
    more than one `Invalid` value is forbidden with no rule (§1.27);
  - `:completable`, part of the valid row `witness`;
  - `:infeasible`, part of no valid row, though no rule excludes it directly:
    `rules` is a set of rules proven to exclude it together (§1.4);
  - `:unknown`, undecided within `feasibility_limit` (§1.7).
- `rules`: positions of the rules in the space's `constraints`, in order.
- `labels`: each rule's label: its reason, its macro source text, or its
  position and scope (§12.3).
- `minimal`: for `:infeasible`, `:verified` when removing any one of `rules`
  was shown to make the assignment completable, and `:unresolved` when a
  limit stopped that check; then `rules` is still sufficient, but may hold
  a rule it does not need (§3.15, §3.16). `:not_applicable` otherwise.
- `witness`: for `:completable` and `:allowed`, a valid row containing the
  assignment, as a `NamedTuple`; otherwise `nothing`.
- `limit`: the limit that decided an `:unknown` outcome or an `:unresolved`
  explanation, as `keyword => value`; otherwise `nothing`.
"""
struct Explanation
    assignment::NamedTuple
    outcome::Symbol
    rules::Vector{Int}
    labels::Vector{String}
    minimal::Symbol
    witness::Union{Nothing, NamedTuple}
    limit::Union{Nothing, Pair{Symbol, Int}}
end

"""
    explain(space::TestSpace, assignment; feasibility_limit = 1_000_000,
            explanation_limit = 1_000_000) -> Explanation

Say whether `assignment` can appear in a valid row of `space`, and why not
when it cannot (contract §1.26). `assignment` is a `NamedTuple` naming some
or all parameters, or a complete `Tuple` in parameter order. The result is an
`Explanation`, which prints as a sentence:

```julia
space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
explain(space, (solver = :lu, tol = 1e-3))
# infeasible: no valid case contains (solver = :lu, tol = 0.001); rules 1 and 2
# together exclude it (rule 1: @require(mode == :exact || solver == :none);
# rule 2: exact mode needs a tight tolerance)
explain(space, (solver = :lu,))
# completable, e.g. (mode = :exact, solver = :lu, tol = 1.0e-6)
```

An assignment with one [`Invalid`](@ref) value, at parameter `p`, is judged
against negative rows: rules that read `p` do not apply (§1.27, §5.5). One
with more than one is forbidden, and the result says so rather than naming a
rule.

Deciding a partial assignment may search the rows that complete it, up to
`feasibility_limit` nodes; a search that reaches the limit gives `:unknown`
(§1.7, §3.3). When the assignment is infeasible, a deletion search looks for
the rules that exclude it, within `explanation_limit` nodes; the assignment
stays infeasible even if that search is cut short (§3.13–§3.16).
"""
function explain(space::TestSpace, assignment::Union{NamedTuple, Tuple};
                 feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    context = FeasibilityContext(space; feasibility_limit)
    _check_limit(:explanation_limit, explanation_limit)
    idx = case_indices(space, assignment)
    shown = from_indices(space, idx)
    if length(_invalid_parameters(space, idx)) > 1
        return Explanation(shown, :forbidden, Int[], String[], :not_applicable, nothing, nothing)
    end
    f, active = feasibility_for(context, idx)
    e = explain_partial(f, idx; explanation_limit)
    rules = active[e.rules]
    return Explanation(shown, e.outcome, rules, [rule_label(space, k) for k in rules], e.minimal,
        e.witness === nothing ? nothing : from_indices(space, e.witness),
        _limit_pair(e.limit, context.feasibility_limit, explanation_limit))
end

_limit_pair(::Nothing, feasibility_limit, explanation_limit) = nothing
_limit_pair(keyword::Symbol, feasibility_limit, explanation_limit) =
    keyword => (keyword === :feasibility_limit ? feasibility_limit : Int(explanation_limit))

# A rule with neither reason nor source text is labeled "rule k on (scope)"
# by `rule_label` (contract §12.3); the sentences then use that label alone.
_unlabeled(k::Int, label::String) = startswith(label, "rule $k on ")
_rule_phrase(k::Int, label::String) = _unlabeled(k, label) ? label : "rule $k ($label)"
_rule_numbers(rules) = (length(rules) == 1 ? "rule " : "rules ") * join(rules, ", ", " and ")
_rule_details(rules, labels) =
    "(" * join((_unlabeled(k, l) ? l : "rule $k: $l" for (k, l) in zip(rules, labels)), "; ") * ")"

function Base.show(io::IO, e::Explanation)
    shown = sprint(show, e.assignment; context = io)
    if e.outcome === :allowed
        print(io, "allowed: ", shown, " is a valid case")
    elseif e.outcome === :forbidden && isempty(e.rules)
        print(io, "forbidden: ", shown, " has more than one Invalid value, and a case holds at most one")
    elseif e.outcome === :forbidden
        if length(e.rules) == 1
            print(io, "forbidden by ", _rule_phrase(only(e.rules), only(e.labels)))
        else
            print(io, "forbidden by ", _rule_numbers(e.rules), " ", _rule_details(e.rules, e.labels))
        end
    elseif e.outcome === :completable
        print(io, "completable, e.g. ")
        show(io, e.witness)
    elseif e.outcome === :infeasible
        print(io, "infeasible: ", isempty(e.assignment) ? "the space has no valid case" :
                                  "no valid case contains " * shown, "; ")
        if length(e.rules) == 1
            print(io, _rule_phrase(only(e.rules), only(e.labels)), " excludes it")
        else
            print(io, _rule_numbers(e.rules), " together exclude it ", _rule_details(e.rules, e.labels))
        end
        if e.minimal === :unresolved
            print(io, "; whether each rule is needed is unresolved: ", e.limit.first, " = ",
                  _grouped(e.limit.second), " reached")
        end
    else
        print(io, "unknown: ", e.limit.first, " = ", _grouped(e.limit.second),
              " reached; retry with a larger limit")
    end
end


## classify

"""
    Classification

One target's classification from `classify(space, targets)` (contract §1.2,
§1.4, §1.7). Fields:

- `target`: the target as a `NamedTuple` in parameter order, with values as
  the domain stores them.
- `status`: `:required` (some valid row contains it; `witness` is one),
  `:forbidden` (rules whose scope lies within the target exclude it
  directly), `:implied` (infeasible with no direct rule; `rules` is a proven
  sufficient set), or `:unknown` (undecided within `feasibility_limit`).
- `rules`, `labels`: rule positions in the space's `constraints` and their
  labels. Every direct rule for `:forbidden`; the deletion search's set for
  `:implied`; empty otherwise.
- `minimal`, `limit`: as in `Explanation`.
- `witness`: a valid row containing a `:required` target, else `nothing`.
"""
struct Classification
    target::NamedTuple
    status::Symbol
    rules::Vector{Int}
    labels::Vector{String}
    minimal::Symbol
    witness::Union{Nothing, NamedTuple}
    limit::Union{Nothing, Pair{Symbol, Int}}
end

"""
    classify(space::TestSpace, targets; feasibility_limit = 1_000_000,
             explanation_limit = 1_000_000) -> Vector{Classification}

Classify each target, a partial assignment written as a `NamedTuple`, as
required, forbidden, implied or unknown (see `Classification`),
with results in the order of `targets` (contract §1.2, §1.4, §1.7, §9.7).
A target with one [`Invalid`](@ref) value is a negative target and is judged
against negative rows (§5.5, §6.2); a target with more than one is an
`ArgumentError`.

Each target gets its own `feasibility_limit` budget (§3.4) and its own
`explanation_limit` budget for the deletion search (§3.13). Answers are
cached for the duration of the call only (§3.5). Not exported: coverage
measurement uses it.
"""
function classify(space::TestSpace, targets::AbstractVector;
                  feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    context = FeasibilityContext(space; feasibility_limit)
    _check_limit(:explanation_limit, explanation_limit)
    return Classification[_classify_one(context, target, explanation_limit) for target in targets]
end

function _classify_one(context::FeasibilityContext, target, explanation_limit)
    space = context.space
    target isa NamedTuple || throw(ArgumentError(
        "a target is a NamedTuple of some parameters' values, such as (mode = :fast,); " *
        "got $(repr(target))"))
    idx = case_indices(space, target)
    f, active = feasibility_for(context, idx)
    c = IndexClassification(explain_partial(f, idx; explanation_limit))
    rules = active[c.rules]
    return Classification(from_indices(space, idx), c.status, rules,
        [rule_label(space, k) for k in rules], c.minimal,
        c.witness === nothing ? nothing : from_indices(space, c.witness),
        _limit_pair(c.limit, context.feasibility_limit, explanation_limit))
end
