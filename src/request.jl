# The internal request: what an engine consumes and what it returns.
#
# Phase 3 step 1 of design/20260926_implementation_plan.md. This is the
# second index-space boundary (the first is rule_table.jl). An engine sees
# only integers: parameter `i` has values `1:arity[i]` (engine positions),
# a partial row is a Vector{Int} with 0 for unset, a design is a matrix
# with one column per case (the layout GND's coverage_matrix.jl uses).
# Engine positions map to space value indices through `candidates`, so
# domains with non-contiguous ordinary values need no engine change. The
# positions after `arity[i]` are the parameter's `Invalid` values, which only
# negative rows hold (contract §5): must-include rows, and the rows that
# negative generation (invalid.jl) adds. An engine never sees them.

"""
    Request(space; strength = 2, stronger = [], must_include = [],
            feasibility_limit = 1_000_000, explanation_limit = 1_000_000)

Everything an engine needs to produce a design for `space`, in index space.

Fields an engine reads:
- `arity::Vector{Int}`: ordinary values per parameter, engine positions
  `1:arity[i]`.
- `strength::Int`: the base strength.
- `groups::Vector{Pair{Vector{Int}, Int}}`: parameter index groups with
  their strength, the base group (all parameters at `strength`) first,
  then each `stronger` group (contract §11). Groups at the base strength
  are dropped (§11.7); a group listed twice keeps its highest strength
  (§11.8).
- `must_include::Matrix{Int}`: one column per must-include row, `0` for
  unset, engine positions, in the order given (§10.5). A column may hold
  one invalid position (a negative row, §7.9); `generate` hands an engine
  only the ordinary columns.
- `dead(request, partial)`: the only feasibility question an engine asks.

Bookkeeping for the caller: `space`; `candidates`, where engine position
`k` of parameter `i` is space value index `candidates[i][k]`: positions
`1:arity[i]` are the ordinary values in domain order, and the positions
after them the parameter's `Invalid` values in domain order;
`n_must_include`, `feasibility_limit`, `explanation_limit`; `feasibility`,
the shared `Feasibility` of ordinary rows; and `context`, the
`FeasibilityContext` whose searches decide negative rows (§5.5), one per
invalid value, keyed `(p, v)` as in `feasibility_for`, with `feasibility`
itself under `(0, 0)`. The request is the operation context of one
generation (contract §3.5, §12.19): the feasibility caches and the lazy-rule
memo live in `feasibility` and `context`, which share one memo, are shared
by the must-include checks, the engine's searches and the final validation,
and are released with the request. The space retains nothing.
`memo_size(request)` counts the memoized verdicts.

Values are the space's, wrappers included: a [`Partition`](@ref) is an
ordinary value, which rules and targets see by its name (§4.5), and an
[`Invalid`](@ref) value is a candidate only of negative rows (§5).

Internally a request may have base strength 0 (negative generation's
sub-request, invalid.jl): its base group then has no targets, and only its
`stronger` groups do. The keyword constructor keeps the public floor of 1
(§11.1).
"""
struct Request
    space::TestSpace
    candidates::Vector{Vector{Int}}
    arity::Vector{Int}
    strength::Int
    groups::Vector{Pair{Vector{Int}, Int}}
    must_include::Matrix{Int}
    feasibility::Feasibility
    context::FeasibilityContext
    feasibility_limit::Int
    explanation_limit::Int
end

function Request(space::TestSpace; strength = 2, stronger = [], must_include = [],
                 feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    # Keyword values are checked before they are compared or converted.
    feasibility_limit = _check_limit(:feasibility_limit, feasibility_limit)
    explanation_limit = _check_limit(:explanation_limit, explanation_limit)
    n = length(space.names)
    strength = _check_strength(strength, n)
    groups = _groups(space, strength, stronger)
    feasibility = Feasibility(_candidates(space, 0, 0), space.tables; limit = feasibility_limit)
    request = _request(space, strength, groups, zeros(Int, n, 0), feasibility, feasibility_limit,
                       explanation_limit)
    return _with_must_include(request, _must_include_matrix(request, must_include))
end

"""
    _request(space, strength, groups, must_include, feasibility, feasibility_limit,
             explanation_limit) -> Request

A request from parts, with no validation: the candidates (ordinary positions,
then invalid ones), the ordinary arity, and a negative-row context that shares
`feasibility`'s lazy-rule memo and holds `feasibility` as its ordinary search.
`feasibility`'s tables must be `space.tables`, in order.
"""
function _request(space::TestSpace, strength::Int, groups, must_include::Matrix{Int},
                  feasibility::Feasibility, feasibility_limit::Int, explanation_limit::Int)
    n = length(space.names)
    candidates = [[ordinary_indices(space, i); invalid_indices(space, i)] for i in 1:n]
    arity = [length(ordinary_indices(space, i)) for i in 1:n]
    searches = Dict{Tuple{Int, Int}, Tuple{Feasibility, Vector{Int}}}(
        (0, 0) => (feasibility, collect(eachindex(space.tables))))
    context = FeasibilityContext(space, feasibility_limit, searches, feasibility.rule_memo)
    return Request(space, candidates, arity, strength, groups, must_include, feasibility, context,
                   feasibility_limit, explanation_limit)
end

"The same request with other must-include rows (engine positions, one column each)."
_with_must_include(r::Request, must_include::AbstractMatrix{<:Integer}) =
    Request(r.space, r.candidates, r.arity, r.strength, r.groups, Matrix{Int}(must_include),
            r.feasibility, r.context, r.feasibility_limit, r.explanation_limit)

n_must_include(request::Request) = size(request.must_include, 2)

"A base strength for a space of `n` parameters: an integer from 1 to `n` (contract §11.1, §11.2)."
function _check_strength(strength, n::Integer)
    strength = _check_integer(:strength, strength, 1, "§11.1")
    strength <= n || throw(ArgumentError(
        "strength $strength is larger than the number of parameters, $n (contract §11.2)"))
    return strength
end

# Instrumentation, not called in src/: benchmark/run.jl reports it, and the tests read all three methods.
"The lazy-rule verdicts memoized by this request so far (contract §12.19)."
memo_size(request::Request) = memo_size(request.feasibility)

"""
    _groups(space, strength, stronger)

Validate `stronger` (contract §11.3–§11.9) and return the group list, base
group first. `stronger` is a vector (or tuple) of entries `group => s`, each
group a tuple, vector or range of names or 1-based indices. Shapes are
checked before anything is iterated or converted, so a malformed value is an
`ArgumentError` naming `stronger`.
"""
function _groups(space::TestSpace, strength::Integer, stronger)
    n = length(space.names)
    stronger isa Pair && throw(ArgumentError(
        "stronger is a vector of `group => strength` pairs; wrap a single group in a vector: " *
        "stronger = [$(repr(stronger))] (contract §11.3)"))
    stronger isa Union{AbstractVector, Tuple} || throw(ArgumentError(
        "stronger is a vector of `group => strength` pairs, such as [(:a, :b, :c) => 3]; " *
        "got $(repr(stronger)) (contract §11.3)"))
    groups = Pair{Vector{Int}, Int}[collect(1:n) => Int(strength)]
    seen = Dict{Vector{Int}, Int}()
    for entry in stronger
        entry isa Pair || throw(ArgumentError(
            "each `stronger` entry is `names => strength`, for example `(:a, :b, :c) => 3`; got $entry"))
        members, s = entry
        members isa Union{AbstractVector, Tuple} || throw(ArgumentError(
            "each `stronger` group is a tuple or vector of parameter names or indices, such as " *
            "(:a, :b, :c) => 3; got $(repr(entry)) (contract §11.3)"))
        idx = Int[]
        for m in members
            if m isa Symbol
                push!(idx, parameter_index(space, m))
            elseif m isa Integer && !(m isa Bool)
                1 <= m <= n || throw(ArgumentError(
                    "`stronger` group $members names parameter $m, but the space has $n parameters"))
                push!(idx, Int(m))
            else
                throw(ArgumentError("`stronger` group members are names or indices; got $(repr(m))"))
            end
        end
        length(unique(idx)) == length(idx) || throw(ArgumentError(
            "`stronger` group $members lists a parameter twice (contract §11.5)"))
        s isa Integer && !(s isa Bool) || throw(ArgumentError(
            "`stronger` strength for $members must be an integer, got $(repr(s)) (contract §11.6)"))
        s >= strength || throw(ArgumentError(
            "`stronger` group $members has strength $s, below the base strength $strength (contract §11.6)"))
        s <= length(idx) || throw(ArgumentError(
            "`stronger` group $members has strength $s, above its size $(length(idx)) (contract §11.6)"))
        s == strength && continue   # a no-op (§11.7)
        key = sort(idx)
        seen[key] = max(get(seen, key, 0), Int(s))
    end
    for (key, s) in sort(collect(seen); by = first)
        push!(groups, key => s)
    end
    return groups
end

"""
    _must_include_matrix(request, rows) -> Matrix{Int}

Validate must-include rows (contract §10.1–§10.4): each a `NamedTuple`
(partial allowed) or a `Tuple`/`AbstractVector` (positional, complete).
Values are matched by identity. A row with one [`Invalid`](@ref) value, at
`p`, is a negative row, judged and completed under the negative-row policy
(§5.5, §7.9): rules that read `p` do not apply, and the other parameters take
ordinary values. A row without one is ordinary (§7.9), and a row with two or
more is an `ArgumentError` (§5.7, §10.3). A row that violates an applicable
rule is an `ArgumentError` naming the rule; a partial row must be
completable, and an exhausted search is a `ResourceLimitError` (distinct from
infeasible). A proven infeasible partial row is an `ArgumentError` carrying
its explanation: the rules that together exclude it and their labels, in the
words `explain` uses, from the same deletion search under
`explanation_limit`.
"""
function _must_include_matrix(request::Request, rows)
    space = request.space
    n = length(space.names)
    columns = Vector{Int}[]
    for (r, row) in enumerate(rows)
        idx = _row_indices(space, row; what = "must_include row $r", section = "§10.1", complete = false)
        bad = _invalid_parameters(space, idx)
        length(bad) > 1 && throw(ArgumentError(
            "must_include row $r, $(from_indices(space, idx)), has Invalid values for " *
            "$(join(space.names[bad], ", ", " and ")); a row holds at most one Invalid value " *
            "(contract §5.7, §10.3)"))
        positions = _positions(request, idx)
        f, active = feasibility_for(request.context, idx)
        if violates(f, idx)
            throw(ArgumentError("must_include row $r, $(from_indices(space, idx)), breaks " *
                                "$(_broken_rules(request, positions)) (contract §10.3)"))
        end
        if any(==(0), idx)
            status, _ = completable(f, idx)
            status == :unknown && throw(ResourceLimitError(
                "checking whether must_include row $r can be completed", request.feasibility_limit,
                :feasibility_limit))
            status == :infeasible && throw(ArgumentError(
                "must_include row $r, $(from_indices(space, idx)), has no valid completion: " *
                "$(_infeasible_clause(request, positions)) (contract §10.4)"))
        end
        push!(columns, positions)
    end
    return isempty(columns) ? zeros(Int, n, 0) : reduce(hcat, columns)
end

"Whether a row (engine positions) holds an invalid position: a negative row, or a multiple-invalid one."
_holds_invalid(request::Request, row::AbstractVector{<:Integer}) =
    any(i -> row[i] > request.arity[i], eachindex(row))

"""
    _feasibility(request, row) -> Feasibility

The search that decides `row` (engine positions, `0` unset) under its row
policy: the request's ordinary `feasibility`, or, for a row holding an invalid
position at `p`, the negative-row search of `feasibility_for(request.context,
…)`, where rules that read `p` do not apply (§5.5). At most one invalid
position is allowed.
"""
function _feasibility(request::Request, row::AbstractVector{<:Integer})
    # A negative row's search, once built, is found by its kind `(p, v)`
    # without converting the row; `feasibility_for` builds it, and rejects a
    # row with two invalid positions.
    p = 0
    for i in eachindex(row)
        row[i] > request.arity[i] || continue
        p == 0 || return first(feasibility_for(request.context, _space_indices(request, row)))
        p = i
    end
    p == 0 && return request.feasibility
    found = get(request.context.searches, (p, request.candidates[p][row[p]]), nothing)
    found === nothing || return first(found)
    return first(feasibility_for(request.context, _space_indices(request, row)))
end

"""
Every applicable rule a row (engine positions, at most one invalid position)
breaks directly, in the space's numbering, as a phrase naming each. A negative
row is judged under the negative policy (§5.5).
"""
function _broken_rules(request::Request, row::AbstractVector{<:Integer})
    idx = _space_indices(request, row)
    f, active = feasibility_for(request.context, idx)
    rules = active[violated_rules(f, idx)]
    return join((_rule_ref(request.space.constraints[k], k) for k in rules), ", ", " and ")
end

"""
    _infeasible_clause(request, partial) -> String

Why the partial row (engine positions), proven infeasible, has no valid
completion: the deletion search of `explain_partial` under the request's
`explanation_limit`, on the search of the row's kind, as the clause `explain`
prints ("rules 1 and 2 together exclude it (rule 1: …; rule 2: …)", with the
limit when the set is unresolved).
"""
function _infeasible_clause(request::Request, partial::AbstractVector{<:Integer})
    idx = _space_indices(request, partial)
    f, active = feasibility_for(request.context, idx)
    e = explain_partial(f, idx; explanation_limit = request.explanation_limit)
    e.outcome === :infeasible ||
        error("internal error: $partial was proven infeasible, then explained as $(e.outcome)")
    rules = active[e.rules]
    labels = [rule_label(request.space, k) for k in rules]
    limit = _limit_pair(e.limit, request.feasibility_limit, request.explanation_limit)
    return sprint(_print_exclusion, rules, labels, e.minimal, limit)
end

"Engine positions from space value indices (0 stays 0)."
function _positions(request::Request, idx::AbstractVector{<:Integer})
    return Int[idx[i] == 0 ? 0 : something(findfirst(==(idx[i]), request.candidates[i]))
               for i in eachindex(request.candidates)]
end

"Space value indices from engine positions (0 stays 0)."
_space_indices(request::Request, positions::AbstractVector{<:Integer}) =
    _space_indices!(zeros(Int, length(request.candidates)), request, positions)

"`_space_indices` written into `idx`, which it returns."
function _space_indices!(idx::Vector{Int}, request::Request, positions::AbstractVector{<:Integer})
    for i in eachindex(request.candidates)
        idx[i] = positions[i] == 0 ? 0 : request.candidates[i][positions[i]]
    end
    return idx
end

"""
    dead(request, partial) -> Bool

`true` only when the partial row (engine positions, `0` unset) is proven
to have no valid completion; `false` only with a completion witness; throws
`ResourceLimitError` when the budget runs out (plan Phase 3 step 1,
contract §3.6). This is the predicate that replaces `disallow` at every
engine site. A partial row with an invalid position is judged under the
negative-row policy (§5.5); an engine's rows never hold one.

The row's value indices are written into the search's own buffer
(`f.key`): every engine position maps to one of the search's candidates, so
the key needs no other check. A question the caches answer allocates
nothing (plan §5.6).
"""
function dead(request::Request, partial::AbstractVector{<:Integer})
    f = _feasibility(request, partial)
    key = _space_indices!(f.key, request, partial)
    status = _completable(f, key, f.limit)
    status === :unknown && throw(ResourceLimitError(
        "placing a value: the feasibility search for $(from_indices(request.space, key))",
        f.limit, :feasibility_limit))
    return status === :infeasible
end

"""
    witness(request, partial) -> Vector{Int}

A complete row (engine positions) extending `partial`, or throws:
`ResourceLimitError` on an exhausted search, an `ErrorException` if the
partial is infeasible (callers ask `dead` first). A partial row with an
invalid position is completed as a negative row, with ordinary values
elsewhere (§7.9).
"""
function witness(request::Request, partial::AbstractVector{<:Integer})
    status, w = completable(_feasibility(request, partial), _space_indices(request, partial))
    status == :unknown && throw(ResourceLimitError(
        "completing the row $(from_indices(request.space, _space_indices(request, partial)))",
        request.feasibility_limit, :feasibility_limit))
    status == :infeasible && error("internal error: asked for a witness of an infeasible row $partial")
    return _positions(request, w::Vector{Int})
end

isconstrained(request::Request) = !isempty(request.feasibility.tables)

"""
    _group_supports(groups) -> (supports, shares)
    _supports(groups) -> supports

The parameter sets that carry targets (contract §1.8): for each group
`(G, s)`, each `s`-subset of `G` in `combinations` order, the base group
first. A subset that two groups share is listed once, where it first
appears, so that a target arising from two groups is one target. Each
subset is sorted, since every group's members are. A group at strength 0 (a
negative sub-request's base group, invalid.jl) has no subsets. `shares[g]`
lists the positions in `supports` of group `g`'s subsets, so that a
measurement gives each group its share of the counts (§1.15) without
listing the subsets again.
"""
function _group_supports(groups)
    supports = Vector{Int}[]
    position = Dict{Vector{Int}, Int}()
    shares = Vector{Int}[]
    for (members, s) in groups
        share = Int[]
        if s > 0   # a base group at strength 0 has no targets (see `Request`)
            for subset in combinations(members, s)
                k = get!(position, subset) do
                    push!(supports, subset)
                    length(supports)
                end
                push!(share, k)
            end
        end
        push!(shares, share)
    end
    return supports, shares
end

_supports(groups) = first(_group_supports(groups))

"""
    TargetList(request) <: AbstractVector{Vector{Int}}

Every target of the request as a partial row in engine positions, computed
on demand rather than stored: for each support (`_supports`), each
assignment of engine positions, the first parameter varying fastest, which
is `_decode!` of the codes 0, 1, 2, … with the ordinary arity as radix. The
order is fixed by the space and the request (contract §9.7). `offsets[k]`
counts the targets before support `k`; the last entry is the total, checked
against `Int` overflow. Each index gives a fresh vector, which the caller
may keep.

It is the request's layout of targets: target `offsets[s] + code + 1` is
code `code` on support `s`, and that number is its id. Classification walks
it support by support and code by code (`_classify_targets`), the targets
(`RequiredTargets`), the coverage index and the certifier's recount
(`validate_design`) read it, and no target is ever listed from it in
production. An unconstrained request requires every target, so its targets
are this list itself, never materialized (plan Phase 3 review, round 1,
item 4).
"""
struct TargetList <: AbstractVector{Vector{Int}}
    arity::Vector{Int}
    supports::Vector{Vector{Int}}
    offsets::Vector{Int}
end

function TargetList(request::Request)
    supports = _supports(request.groups)
    offsets = zeros(Int, length(supports) + 1)
    for (k, support) in enumerate(supports)
        block = 1
        for p in support
            block = Base.checked_mul(block, request.arity[p])
        end
        offsets[k + 1] = Base.checked_add(offsets[k], block)
    end
    return TargetList(copy(request.arity), supports, offsets)
end

Base.size(list::TargetList) = (last(list.offsets),)
Base.IndexStyle(::Type{TargetList}) = IndexLinear()

function Base.getindex(list::TargetList, i::Int)
    @boundscheck checkbounds(list, i)
    k = searchsortedlast(list.offsets, i - 1)
    return _decode!(zeros(Int, length(list.arity)), i - 1 - list.offsets[k], list.supports[k], list.arity)
end

# Production iterates `TargetList` directly; this stays as a convenience for the tests.
"""
    targets(request) -> Vector{Vector{Int}}

Every target of the request as a partial row in engine positions: for each
group `(G, s)`, each `s`-subset of `G`, each assignment (contract §1.8).
The union over groups, deduplicated, in a fixed order (base group first,
subsets in `combinations` order, assignments with the first parameter
varying fastest). `collect(TargetList(request))`.
"""
targets(request::Request) = collect(TargetList(request))

"""
    Excluded

One target the design does not need to cover: `target` (engine positions),
`status` (`:forbidden` or `:implied`), `rules` (constraint positions in the
space), `minimal` (`:verified`, `:unresolved`, or `:not_applicable`), and
`limit`, the limit that left an `:unresolved` explanation unresolved, as
`keyword => value` (from `IndexExplanation.limit`, as in `Explanation`), or
`nothing`. A report can then say "explanation unresolved:
explanation_limit = N reached" without searching again.
"""
struct Excluded
    target::Vector{Int}
    status::Symbol
    rules::Vector{Int}
    minimal::Symbol
    limit::Union{Nothing, Pair{Symbol, Int}}
end

"""
    classify_targets(request, list = TargetList(request)) -> (required, excluded)

Every target classified (contract §1.4), as lists, for tests and benchmark
scripts: `required`, the targets an engine must cover, and `excluded`, the
`Excluded` records, each in target order, every target of `list` in one of
the two. An unconstrained request classifies nothing and requires
everything: `required` is then `list` itself, never materialized. A
constrained request returns a `Vector` of the required targets, each a
fresh full-width row of engine positions. An `:unknown` target is a
`ResourceLimitError` (§3.6).

Generation keeps no such list: `_Classified` calls `_classify_targets`,
which this calls, and keeps its `RequiredTargets`, so both ask the same
questions in the same order and agree target for target.
"""
function classify_targets(request::Request, list::TargetList = TargetList(request))
    isconstrained(request) || return list, Excluded[]
    targets, excluded = _classify_targets(request, list)
    return _required_list(targets), excluded
end

"""
    _classify_targets(request, layout::TargetList) -> (targets::RequiredTargets, excluded)

Classify every target of `layout`, the request's `TargetList` (contract
§1.4): `targets`, what an engine must cover (`RequiredTargets`), and
`excluded`, the `Excluded` record of each target no valid row holds, in
target order. The walk is the layout's order, support by support and code by
code, so the feasibility questions come in target order, as they always have
(their caches' effort, and so every `Excluded` explanation and node count,
depend on it). Each target is decoded into one reused row (`_decode!`) and
its space value indices into another, so the walk keeps and allocates
nothing per target beyond the feasibility question (`_classify_target`); a
required target leaves no trace but its count. What is kept is the excluded
targets' ids, `offsets[s] + code + 1`, ascending, from which the targets
count each support and build their bits (`RequiredTargets`).

An unconstrained request asks nothing: every target is required, and the
targets are `layout` itself. An `:unknown` target is a `ResourceLimitError`
naming it (§3.6).
"""
function _classify_targets(request::Request, layout::TargetList)
    isconstrained(request) || return RequiredTargets(request, layout), Excluded[]
    f = request.feasibility
    active = collect(eachindex(f.tables))
    excluded = Excluded[]
    ids = Int[]
    target = zeros(Int, length(layout.arity))   # one target in engine positions, reused
    idx = zeros(Int, length(layout.arity))      # the same target as space value indices
    for (s, support) in enumerate(layout.supports)
        for code in 0:(ncombinations(layout, s) - 1)
            _decode!(target, code, support, layout.arity)
            for p in support
                idx[p] = request.candidates[p][target[p]]
            end
            e = _classify_target(request, f, active, target, idx, "classifying target")
            e === nothing && continue
            push!(excluded, e)
            push!(ids, layout.offsets[s] + code + 1)
        end
        for p in support
            target[p] = idx[p] = 0
        end
    end
    return RequiredTargets(layout, ids), excluded
end

"""
    _classify_target(request, f, active, target, idx, what) -> Union{Nothing, Excluded}

Classify one target (contract §1.4) with the search `f`, whose table `k` is
the space's rule `active[k]`, through `IndexClassification`: `nothing` when
some valid row of `f`'s kind contains it (it is required), otherwise its
`Excluded` record, with `target` (engine positions) and its rules in the
space's numbering. `idx` is the target as space value indices. An unknown
answer throws `ResourceLimitError`, naming the target after `what` (§3.6).
Ordinary targets (`_classify_targets`) and negative targets (invalid.jl) are
classified here. Neither `target` nor `idx` is kept: the record copies
`target`, and the search copies `idx` (`explain_partial`), so a caller may
pass buffers it reuses.
"""
function _classify_target(request::Request, f::Feasibility, active::Vector{Int},
                          target::AbstractVector{<:Integer}, idx::AbstractVector{<:Integer}, what)
    c = IndexClassification(explain_partial(f, idx; explanation_limit = request.explanation_limit))
    c.status === :unknown && throw(ResourceLimitError("$what $(from_indices(request.space, idx))",
                                                      request.feasibility_limit, :feasibility_limit))
    c.status === :required && return nothing
    return Excluded(collect(Int, target), c.status, active[c.rules], c.minimal,
                    _limit_pair(c.limit, request.feasibility_limit, request.explanation_limit))
end

"""
    RequiredTargets(layout::TargetList, excluded::Vector{Int})
    RequiredTargets(request, layout::TargetList)
    RequiredTargets(request, required::Vector{Vector{Int}})

The targets an engine must cover, as the engine protocol asks for them (plan
§4.2, `CoveringEngine`). For each support `s` of the request, the parameter
sets that carry targets (`supports`, in target order), each combination of
engine positions has a code, the mixed-radix code `_code(row, supports(t)[s],
request.arity)` that orders the targets in `TargetList` (contract §9.7). The
codes on support `s` are `0:ncombinations(t, s) - 1`, `_decode!` turns one
back into a row, and `isrequired(t, s, code)` says whether it is a required
target; `nrequired(t, s)` counts them. All four answer in constant time and
allocate nothing, `isrequired` once its bits are built (below).

`layout` is the request's `TargetList`: its arity, supports and offsets,
the immutable description of where each combination's bit and count go,
its id `offsets[s] + code + 1`. Classification walks it and keeps it here
(`_Classified`), and the coverage index and the certifier read it, so none
of them builds it again. No target is listed. What classification keeps is
`excluded`, the ids of the combinations that are not required, ascending:
every other combination of the layout is a required target.

- From classification, `RequiredTargets(layout, excluded)`, with the ids of
  the targets it excluded (`_classify_targets`; a negative sub-request's,
  `cover_negative`): a support's count is its combinations less its
  excluded ones, and the bits are built the first time `isrequired` or the
  coverage index asks (`_required_bits`), every combination but the
  excluded ones, so the lower bound without must-include rows never pays
  for them. The ids cost eight bytes per excluded target, beside the
  `Excluded` record contract §1.4 keeps for each.
- Unconstrained, `RequiredTargets(request, layout)`: every target is
  required, `list` is the layout itself, nothing is counted or excluded,
  `isrequired` is always `true`, and the bits, all set, are built only for
  the coverage index.
- From a list, `RequiredTargets(request, required)`, in any order, for tests
  and benchmark scripts: the request's `TargetList` is built, each target's
  bit is marked and counted in one pass, and the other combinations' ids
  are kept as excluded. Misuse is an internal error.

Once built, the bits never change, and every reader shares them: two
engines that run on one `RequiredTargets` (`Auto`'s starts, `design_sizes`'
engines) build them once. The build is not locked: the package runs nothing
concurrently inside a call, and a `RequiredTargets` lives in one call.
Engines read the four functions above; GND's coverage matrix and
`full_strength_rows`, which need the required targets as rows, decode them
from their codes in target order (`_required_matrix`, `_required_list`).
The certifier reads the layout and `excluded`, never the bits, which
engines and the coverage index hold by reference (`_recount`).
"""
mutable struct RequiredTargets{L <: Union{Nothing, TargetList}}
    const list::L                      # the layout itself when every target is required; `nothing` otherwise
    const layout::TargetList
    const counts::Vector{Int}          # the required targets on each support; empty when every target is required
    const excluded::Vector{Int}        # the ids, offsets[s] + code + 1, of the combinations not required, ascending
    bits::Union{Nothing, BitVector}    # bit id set for a required target; `nothing` until first asked for
end

# Every target of a TargetList is required, so there is nothing to mark or count.
function RequiredTargets(request::Request, layout::TargetList)
    layout.arity == request.arity || error("internal error: a TargetList of another request")
    return RequiredTargets(layout, layout, Int[], Int[], nothing)
end

function RequiredTargets(layout::TargetList, excluded::Vector{Int})
    counts = [ncombinations(layout, s) for s in eachindex(layout.supports)]
    s = 1
    for (k, id) in enumerate(excluded)
        1 <= id <= length(layout) && (k == 1 || id > excluded[k - 1]) ||
            error("internal error: excluded target id $id is not on the layout, or out of target order")
        while layout.offsets[s + 1] < id
            s += 1
        end
        counts[s] -= 1
    end
    return RequiredTargets(nothing, layout, counts, excluded, nothing)
end

function RequiredTargets(request::Request, required::Vector{Vector{Int}})
    every = TargetList(request)
    position = Dict(support => k for (k, support) in enumerate(every.supports))
    counts = zeros(Int, length(every.supports))
    bits = falses(length(every))
    support = Int[]   # one target's support, reused
    for t in required
        _support!(support, t, every.arity, "required")
        k = get(position, support, 0)
        k == 0 && error("internal error: required target $t is on no support of the request")
        b = every.offsets[k] + _code(t, every.supports[k], every.arity) + 1
        bits[b] && error("internal error: required target $t is listed twice")
        bits[b] = true
        counts[k] += 1
    end
    return RequiredTargets(nothing, every, counts, findall(!, bits), bits)
end

"Write into `support` the parameters target `t` sets, checking it is a full-width row of engine positions."
function _support!(support::Vector{Int}, t::AbstractVector{<:Integer}, arity::Vector{Int}, what::String)
    length(t) == length(arity) || error("internal error: $what target $t is not a full-width row")
    empty!(support)
    for i in eachindex(t)
        t[i] == 0 && continue
        1 <= t[i] <= arity[i] || error("internal error: $what target $t is not in engine positions")
        push!(support, i)
    end
    return support
end

"The number of combinations on support `s` of `list`."
ncombinations(list::TargetList, s::Integer) = list.offsets[s + 1] - list.offsets[s]

"The parameter sets that carry targets, in target order; `s` in the other functions indexes them. Not to be changed."
supports(t::RequiredTargets) = t.layout.supports

"The number of combinations on support `s`: its codes are `0:ncombinations(t, s) - 1`."
ncombinations(t::RequiredTargets, s::Integer) = ncombinations(t.layout, s)

"Whether the combination whose code is `code` on support `s` is a required target."
@inline function isrequired(t::RequiredTargets{TargetList}, s::Integer, code::Integer)
    @boundscheck 0 <= code < ncombinations(t, s) || throw(BoundsError(t, (s, code)))
    return true
end

@inline function isrequired(t::RequiredTargets, s::Integer, code::Integer)
    @boundscheck 0 <= code < ncombinations(t, s) || throw(BoundsError(t, (s, code)))
    return @inbounds _required_bits(t)[t.layout.offsets[s] + code + 1]
end

"""
    _required_bits(targets) -> BitVector

The required bit of every combination, by id `offsets[s] + code + 1`: built
the first time it is asked for, every combination but the excluded ones (all
of them for a `TargetList`), and then kept and shared, never changed
(`RequiredTargets`). The coverage index holds these bits, not a copy.
"""
@inline function _required_bits(t::RequiredTargets)
    bits = t.bits
    bits === nothing || return bits
    return _build_required_bits!(t)
end

@noinline function _build_required_bits!(t::RequiredTargets)
    bits = trues(last(t.layout.offsets))
    for id in t.excluded
        bits[id] = false
    end
    t.bits = bits
    return bits
end

"The number of required targets on support `s`, or on every support."
nrequired(t::RequiredTargets{TargetList}, s::Integer) = ncombinations(t, s)
nrequired(t::RequiredTargets, s::Integer) = t.counts[s]
nrequired(t::RequiredTargets) = length(t.layout) - length(t.excluded)

"""
    _required_list(targets) -> Vector{Vector{Int}}
    _required_matrix(targets) -> Matrix{Int}

Every required target, in target order, decoded from its code: as fresh
full-width rows of engine positions, `0` off the target's support, which
`classify_targets` returns and `full_strength_rows` sorts; or as the columns
of one matrix, parameters × targets, from which GND builds its coverage
matrix (`_Greedy`). Read through `isrequired`, so the bits are built if no
one has asked yet.
"""
function _required_list(t::RequiredTargets)
    layout = t.layout
    list = Vector{Vector{Int}}(undef, nrequired(t))
    j = 0
    for (s, support) in enumerate(layout.supports), code in 0:(ncombinations(layout, s) - 1)
        isrequired(t, s, code) || continue
        list[j += 1] = _decode!(zeros(Int, length(layout.arity)), code, support, layout.arity)
    end
    j == length(list) || error("internal error: $j required targets, counted $(length(list))")
    return list
end

function _required_matrix(t::RequiredTargets)
    layout = t.layout
    matrix = zeros(Int, length(layout.arity), nrequired(t))
    j = 0
    for (s, support) in enumerate(layout.supports), code in 0:(ncombinations(layout, s) - 1)
        isrequired(t, s, code) || continue
        _decode!(view(matrix, :, j += 1), code, support, layout.arity)
    end
    j == size(matrix, 2) || error("internal error: $j required targets, counted $(size(matrix, 2))")
    return matrix
end

"""
    _NegativeTargets

A request's negative targets, classified (contract §6.1–§6.5, §6.7) with no
required one listed. They are numbered 1, 2, … in target order (§9.7), the
order of the walk that `coverage` makes (`_walk_support!`): for each support
of `layout`, the request's `TargetList`, each parameter `p` of it with
`Invalid` values and each of those values, every assignment of ordinary
values to the rest of the support, the first parameter fastest.

- `layout`: the request's `TargetList`, whose supports the walk goes over.
- `required`: how many negative targets are required.
- `excluded`: the `Excluded` record of each excluded one, in target order,
  its `target` holding the invalid position (§1.4, §6.7); and `ids`, their
  numbers, ascending, which the certifier reads (`_recount`).
- For each invalid value, in parameter order and then domain order (`slot`):
  `count`, its targets other than `(p = v)` alone, which are its negative
  sub-request's targets in the same order (`_negative_request`);
  `sub_excluded`, the ids of its excluded ones on that sub-request's layout
  (`RequiredTargets`); and `alone`, whether the target `(p = v)` alone, a
  target only at strength 1, is `:required`, `:excluded` or `:none`.

`classify_negative_targets` lists the same targets for tests and scripts.
"""
struct _NegativeTargets
    layout::TargetList
    required::Int
    excluded::Vector{Excluded}
    ids::Vector{Int}
    first::Vector{Int}                 # parameter p's first invalid value's slot; its values follow
    count::Vector{Int}
    sub_excluded::Vector{Vector{Int}}
    alone::Vector{Symbol}
end

"The slot, in `_NegativeTargets`, of the invalid value at engine position `position` of parameter `p`."
_slot(negative::_NegativeTargets, request::Request, p::Int, position::Int) =
    negative.first[p] + position - request.arity[p] - 1

"""
    Design

What `generate(engine, request)` returns: `matrix` (parameters × cases,
engine positions, complete), `strategy` (`:covering`, `:excursion`,
`:full_factorial`), `engine::Symbol`, `seed` (a randomized engine's seed or
`nothing`), `required::Int` and `covered::Int` (ordinary targets, for
covering designs), `excluded::Vector{Excluded}` (ordinary),
`n_must_include::Int`, `notes` (strategy specific: an excursion's dropped
rows, a full factorial's candidate and accepted counts) as a `NamedTuple`,
and the negative bookkeeping, kept
apart from the ordinary (contract §1.19, §5.10): `negative_required::Int`
and `negative_covered::Int` (negative targets, §6) and
`negative_excluded::Vector{Excluded}`, whose targets hold the invalid
position; and `record`, what the result records of how it was made, as
[`TestCases`](@ref)'s `record` documents it: whether the engine is randomized,
a covering design's lower bound with its proof and whether the rows meet it
(`_bound_record`), the engine's configuration, and the stages that ran
(`_covering_record`). The nine-argument constructor leaves the negative
bookkeeping empty, and both short forms record no bound and no engine
(`_NO_BOUND`), as for an excursion or a full factorial.
"""
struct Design
    matrix::Matrix{Int}
    strategy::Symbol
    engine::Symbol
    seed::Union{Nothing, Int}
    required::Int
    covered::Int
    excluded::Vector{Excluded}
    n_must_include::Int
    notes::NamedTuple
    negative_required::Int
    negative_covered::Int
    negative_excluded::Vector{Excluded}
    record::NamedTuple
end

"The record of a design that has no lower bound and no engine: an excursion or a full factorial, which use no randomness."
const _NO_BOUND = (randomized = false, lower_bound = nothing, minimal = false, proof = "", engine = nothing,
                   ordinary = nothing, negative = nothing)

Design(matrix, strategy, engine, seed, required, covered, excluded, n_must_include, notes) =
    Design(matrix, strategy, engine, seed, required, covered, excluded, n_must_include, notes,
           0, 0, Excluded[], _NO_BOUND)

Design(matrix, strategy, engine, seed, required, covered, excluded, n_must_include, notes,
       negative_required, negative_covered, negative_excluded) =
    Design(matrix, strategy, engine, seed, required, covered, excluded, n_must_include, notes,
           negative_required, negative_covered, negative_excluded, _NO_BOUND)

"""
    validate_design(request, matrix, targets; strategy, negative = []) -> Int

Final validation (plan Phase 3 step 6, contract §1.21), in index space:
every row is complete and within its candidates, every row passes its
applicable rules (`violates` on the complete row, so every applicable table
is consulted, lazy ones through the request's memo, §12.19): every rule for
an ordinary row (§5.4), the rules that omit `p` for a negative row with its
invalid value at `p` (§5.5), and no row holds two invalid values (§5.7).
Must-include rows come first in the given order, and for a covering design
every required ordinary target in `targets` is covered by an ordinary row,
and every required negative target in `negative` by a negative row, each
recounted from the rows (§5.9, `_recount`). Returns the number of required
ordinary targets covered. A failure is an `ErrorException` beginning
"internal error", naming the row or target. Values are never looked up; only
`to_cases` converts rows to values.

`targets` is generation's: classification's `RequiredTargets`, recounted on
the request's layout against the ids of the excluded targets; and so is
`negative`, the `_NegativeTargets`, recounted in the negative targets' order
on the same layout. Tests and scripts may pass a `TargetList`, every target
required, and lists of required targets as `classify_targets` and
`classify_negative_targets` return them; a list is recounted target by
target, the same certification by other arithmetic.
"""
function validate_design(request::Request, matrix::AbstractMatrix{<:Integer}, targets;
                         strategy::Symbol = :covering, negative = Vector{Int}[])
    n = length(request.arity)
    size(matrix, 1) == n || error("internal error: design has $(size(matrix, 1)) rows for $n parameters")
    f = request.feasibility
    idx = zeros(Int, n)   # one row's space value indices, reused
    negative_rows = falses(size(matrix, 2))
    for j in axes(matrix, 2)
        invalid = 0
        for i in 1:n
            v = matrix[i, j]
            1 <= v <= length(request.candidates[i]) ||
                error("internal error: case $j has value position $v for parameter $(request.space.names[i])")
            v > request.arity[i] && (invalid += 1)
            idx[i] = request.candidates[i][v]
        end
        if invalid == 0
            # Every entry is a candidate, so this is `violates(f, idx)` without
            # its copy and check of the key.
            _violates(f, idx) && error("internal error: case $j, $(from_indices(request.space, idx)), breaks " *
                                       _broken_rules(request, matrix[:, j]))
        else
            invalid == 1 || error("internal error: case $j, $(from_indices(request.space, idx)), holds " *
                                  "more than one Invalid value (contract §5.7)")
            g, _ = feasibility_for(request.context, idx)
            _violates(g, idx) && error("internal error: case $j, $(from_indices(request.space, idx)), breaks " *
                                       _broken_rules(request, matrix[:, j]))
            negative_rows[j] = true
        end
    end
    seeds = request.must_include
    for s in axes(seeds, 2)
        s <= size(matrix, 2) || error("internal error: must_include row $s is missing from the design")
        for i in 1:n
            seeds[i, s] == 0 || seeds[i, s] == matrix[i, s] ||
                error("internal error: must_include row $s was changed at parameter $(request.space.names[i])")
        end
    end
    strategy == :covering || return 0
    # Only ordinary rows cover ordinary targets, and only negative rows cover
    # negative targets (§5.9).
    ordinary = any(negative_rows) ? matrix[:, .!negative_rows] : matrix
    covered = _recount(request, ordinary, targets)
    _nrequired(negative) == 0 || _recount(request, matrix[:, negative_rows], negative)
    return covered
end

"The number of negative targets `validate_design` must find covered: a list's length, or the classified count."
_nrequired(negative) = length(negative)
_nrequired(negative::_NegativeTargets) = negative.required

_uncovered(request::Request, t) = error(
    "internal error: required target $(from_indices(request.space, _space_indices(request, t))) is not covered")

"""
    _recount(request, matrix, targets::RequiredTargets) -> Int

The certifier's recount (contract §1.21): the number of required targets
that the rows, the columns of `matrix`, hold, or an internal error naming
the first required target, in target order, that none holds. For each
support of the layout, in order, it marks the code (`_code`) of each row's
combination on the support, then walks the support's codes: a code no row
holds must be the id of a target classification excluded.

It trusts two things, both classification's. The layout, `targets.layout`,
is the request's `TargetList`: its supports are every set of parameters that
carries targets (contract §1.8, `_supports`), and code `code` on support `s`
is the target `_decode!` makes of it, so a row holds that target exactly
when its code on `s` is `code`, the rows' entries having been checked within
the ordinary arity. `targets.excluded` is the ids of the targets
classification excluded, each with its `Excluded` record (§1.4); it walked
this layout and put each target in exactly one class, so the required
targets are the layout's combinations less those ids, as an unconstrained
request's are all of them. The recount reads nothing else: not the required
bits, which engines and the coverage index hold by reference, and no
engine's index or buffers. Engines share the layout and never change it
(the engine protocol; test_engines.jl checks each leaves it, and the counts
and bits, as they were). Its buffers are a bit per combination of the
largest support and, on failure, the target it names.
"""
function _recount(request::Request, matrix::AbstractMatrix{<:Integer}, targets::RequiredTargets)
    layout, excluded = targets.layout, targets.excluded
    layout.arity == request.arity || error("internal error: the targets are not the request's")
    seen = falses(maximum(s -> ncombinations(layout, s), eachindex(layout.supports); init = 0))
    next = 1   # the first excluded id not yet reached
    covered = 0
    for (s, support) in enumerate(layout.supports)
        n = ncombinations(layout, s)
        fill!(view(seen, 1:n), false)
        for j in axes(matrix, 2)
            seen[_code(view(matrix, :, j), support, layout.arity) + 1] = true
        end
        for code in 0:(n - 1)
            if next <= length(excluded) && excluded[next] == layout.offsets[s] + code + 1
                next += 1   # excluded: no row need hold it
            elseif seen[code + 1]
                covered += 1
            else
                _uncovered(request, _decode!(zeros(Int, length(layout.arity)), code, support, layout.arity))
            end
        end
    end
    next == length(excluded) + 1 || error("internal error: the excluded ids are not the layout's, in target order")
    return covered
end

"""
    _recount(request, matrix, negative::_NegativeTargets) -> Int

The certifier's recount of the negative targets (contract §1.21, §6, §5.9):
the number of required negative targets that the negative rows, the columns
of `matrix`, hold, or an internal error naming the first, in target order,
that none holds. The negative targets are numbered 1, 2, … in the order of
§9.7 (`_NegativeTargets`): for each support of the layout, each parameter
`p` of it and each of `p`'s invalid values `v`, in engine positions after
its ordinary ones, the block of every assignment of ordinary values to the
rest of the support, by code on the rest. For each block it marks the code
of each row that holds `v` at `p`, then walks the block's codes: a code no
row holds must be the number of a target classification excluded.

It trusts what the ordinary recount trusts, the layout, whose supports the
negative targets lie on as well, and `negative.ids`, the numbers of the
negative targets classification excluded, each with its `Excluded` record
(§1.4, §6.7), every other negative target being required; and checks the
count of required ones against classification's. Each negative row holds
exactly one invalid value and ordinary values elsewhere, checked before, so
its code on a block's rest is on the block. Its buffers are a bit per
combination of the largest support and the rest of one support.
"""
function _recount(request::Request, matrix::AbstractMatrix{<:Integer}, negative::_NegativeTargets)
    layout, ids, arity = negative.layout, negative.ids, request.arity
    layout.arity == arity || error("internal error: the negative targets are not the request's")
    seen = falses(maximum(s -> ncombinations(layout, s), eachindex(layout.supports); init = 0))
    rest = Int[]   # the support but p
    number = 0     # the targets met so far
    next = 1       # the first excluded number not yet reached
    covered = 0
    for support in layout.supports, p in support, v in (arity[p] + 1):length(request.candidates[p])
        empty!(rest)
        n = 1
        for q in support
            q == p && continue
            push!(rest, q)
            n *= arity[q]
        end
        fill!(view(seen, 1:n), false)
        for j in axes(matrix, 2)
            matrix[p, j] == v && (seen[_code(view(matrix, :, j), rest, arity) + 1] = true)
        end
        for code in 0:(n - 1)
            number += 1
            if next <= length(ids) && ids[next] == number
                next += 1   # excluded: no row need hold it
            elseif seen[code + 1]
                covered += 1
            else
                target = _decode!(zeros(Int, length(arity)), code, rest, arity)
                target[p] = v
                _uncovered(request, target)
            end
        end
    end
    next == length(ids) + 1 && covered == negative.required ||
        error("internal error: the negative targets' excluded numbers and count are not the request's")
    return covered
end

# Every target of a TargetList is required.
_recount(request::Request, matrix::AbstractMatrix{<:Integer}, required::TargetList) =
    _recount(request, matrix, RequiredTargets(request, required))

# A list of full-width targets, from tests and scripts (`classify_targets`,
# `classify_negative_targets`): the rows' projections onto each target's
# parameters, built once per parameter set, so the check is linear in
# targets plus rows. Names the first uncovered target in the list's order.
function _recount(request::Request, matrix::AbstractMatrix{<:Integer}, required)
    covered = 0
    projections = Dict{Vector{Int}, Set{Vector{Int}}}()
    for t in required
        support = findall(!=(0), t)
        seen = get!(() -> Set(matrix[support, j] for j in axes(matrix, 2)), projections, support)
        t[support] in seen || _uncovered(request, t)
        covered += 1
    end
    return covered
end

"""
    to_cases(request, matrix) -> Vector{NamedTuple}

The design as named cases with the space's values (wrappers kept).
"""
function to_cases(request::Request, matrix::AbstractMatrix{<:Integer})
    return [from_indices(request.space, _space_indices(request, matrix[:, j])) for j in axes(matrix, 2)]
end
