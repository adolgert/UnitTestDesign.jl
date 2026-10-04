# The internal request: what an engine consumes and what it returns.
#
# Phase 3 step 1 of design/20260926_implementation_plan.md. This is the
# second index-space boundary (the first is rule_table.jl). An engine sees
# only integers: parameter `i` has values `1:arity[i]` (engine positions),
# a partial row is a Vector{Int} with 0 for unset, a design is a matrix
# with one column per case (the layout coverage_matrix.jl already uses).
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
    _holds_invalid(request, row) || return request.feasibility
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
function _space_indices(request::Request, positions::AbstractVector{<:Integer})
    return Int[positions[i] == 0 ? 0 : request.candidates[i][positions[i]]
               for i in eachindex(request.candidates)]
end

"""
    dead(request, partial) -> Bool

`true` only when the partial row (engine positions, `0` unset) is proven
to have no valid completion; `false` only with a completion witness; throws
`ResourceLimitError` when the budget runs out (plan Phase 3 step 1,
contract §3.6). This is the predicate that replaces `disallow` at every
engine site. A partial row with an invalid position is judged under the
negative-row policy (§5.5); an engine's rows never hold one.
"""
function dead(request::Request, partial::AbstractVector{<:Integer})
    f = _feasibility(request, partial)
    key = _checked_key(f, _space_indices(request, partial))
    status, _ = _completable(f, key, f.limit)
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

An unconstrained request requires every target, so `classify_targets`
returns this list without building it, and `validate_design` recounts it one
support at a time (plan Phase 3 review, round 1, item 4).
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
    classify_targets(request) -> (required, excluded)

Classify every target (contract §1.4): `required` is the list of targets an
engine must cover, `excluded` the `Excluded` records. An `:unknown` target
is a `ResourceLimitError`: generation never returns an uncertified design
(§3.6). An unconstrained request classifies nothing and requires
everything: `required` is then the `TargetList` itself, never materialized,
and `validate_design` recounts it one support at a time. A constrained
request returns a `Vector` of the required targets, in target order.
"""
function classify_targets(request::Request)
    all_targets = TargetList(request)
    isconstrained(request) || return all_targets, Excluded[]
    f = request.feasibility
    active = collect(eachindex(f.tables))
    required = Vector{Int}[]
    excluded = Excluded[]
    for t in all_targets
        e = _classify_target(request, f, active, t, _space_indices(request, t), "classifying target")
        e === nothing ? push!(required, t) : push!(excluded, e)
    end
    return required, excluded
end

"""
    _classify_target(request, f, active, target, idx, what) -> Union{Nothing, Excluded}

Classify one target (contract §1.4) with the search `f`, whose table `k` is
the space's rule `active[k]`, through `IndexClassification`: `nothing` when
some valid row of `f`'s kind contains it (it is required), otherwise its
`Excluded` record, with `target` (engine positions) and its rules in the
space's numbering. `idx` is the target as space value indices. An unknown
answer throws `ResourceLimitError`, naming the target after `what` (§3.6).
Ordinary targets (`classify_targets`) and negative targets (invalid.jl) are
classified here.
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
    RequiredTargets(request, required)

The targets an engine must cover, as the engine protocol asks for them (plan
§4.2, `CoveringEngine`). For each support `s` of the request, the parameter
sets that carry targets (`supports`, in target order), each combination of
engine positions has a code, the mixed-radix code `_code(row, supports(t)[s],
request.arity)` that orders the targets in `TargetList` (contract §9.7). The
codes on support `s` are `0:ncombinations(t, s) - 1`, `_decode!` turns one
back into a row, and `isrequired(t, s, code)` says whether it is a required
target; `nrequired(t, s)` counts them. All four answer in constant time and
allocate nothing.

`required` is what `classify_targets` returned, or a negative sub-request's
targets (`cover_negative`): a `TargetList`, every target required, or a
`Vector` of the required targets as full-width partial rows, in any order.
It is kept as given, and IPOG and GND read it through `_target_list`. For a
`Vector` the constructor marks each target's bit, one bit for every
combination of every support, in one pass. Phase 5 builds those bits in
classification in place of the list (plan §5.6); an engine written against
the four functions doesn't change then.
"""
struct RequiredTargets{L <: AbstractVector{Vector{Int}}}
    list::L
    arity::Vector{Int}
    supports::Vector{Vector{Int}}
    offsets::Vector{Int}    # as in TargetList: offsets[s] combinations come before support s
    counts::Vector{Int}     # the required targets on each support; empty for a TargetList
    bits::BitVector         # bit offsets[s] + code + 1 is set for a required target; empty for a TargetList
end

# Every target of a TargetList is required, so there is nothing to mark or count.
RequiredTargets(::Request, required::TargetList) =
    RequiredTargets(required, required.arity, required.supports, required.offsets, Int[], BitVector())

function RequiredTargets(request::Request, required::Vector{Vector{Int}})
    every = TargetList(request)
    position = Dict(support => k for (k, support) in enumerate(every.supports))
    counts = zeros(Int, length(every.supports))
    bits = falses(length(every))
    support = Int[]   # one target's support, reused
    for t in required
        length(t) == length(every.arity) || error("internal error: required target $t is not a full-width row")
        empty!(support)
        for i in eachindex(t)
            t[i] == 0 && continue
            1 <= t[i] <= every.arity[i] || error("internal error: required target $t is not in engine positions")
            push!(support, i)
        end
        k = get(position, support, 0)
        k == 0 && error("internal error: required target $t is on no support of the request")
        b = every.offsets[k] + _code(t, every.supports[k], every.arity) + 1
        bits[b] && error("internal error: required target $t is listed twice")
        bits[b] = true
        counts[k] += 1
    end
    return RequiredTargets(required, every.arity, every.supports, every.offsets, counts, bits)
end

"The parameter sets that carry targets, in target order; `s` in the other functions indexes them. Not to be changed."
supports(t::RequiredTargets) = t.supports

"The number of combinations on support `s`: its codes are `0:ncombinations(t, s) - 1`."
ncombinations(t::RequiredTargets, s::Integer) = t.offsets[s + 1] - t.offsets[s]

"Whether the combination whose code is `code` on support `s` is a required target."
@inline function isrequired(t::RequiredTargets{TargetList}, s::Integer, code::Integer)
    @boundscheck 0 <= code < ncombinations(t, s) || throw(BoundsError(t, (s, code)))
    return true
end

@inline function isrequired(t::RequiredTargets, s::Integer, code::Integer)
    @boundscheck 0 <= code < ncombinations(t, s) || throw(BoundsError(t, (s, code)))
    return @inbounds t.bits[t.offsets[s] + code + 1]
end

"The number of required targets on support `s`, or on every support."
nrequired(t::RequiredTargets{TargetList}, s::Integer) = ncombinations(t, s)
nrequired(t::RequiredTargets, s::Integer) = t.counts[s]
nrequired(t::RequiredTargets) = length(t.list)

"The required targets as `classify_targets` lists them, for the engines that read the list (IPOG, GND)."
_target_list(t::RequiredTargets) = t.list

"""
    Design

What `generate(engine, request)` returns: `matrix` (parameters × cases,
engine positions, complete), `strategy` (`:covering`, `:excursion`,
`:full_factorial`), `engine::Symbol`, `seed` (GND's seed or `nothing`),
`required::Int` and `covered::Int` (ordinary targets, for covering designs),
`excluded::Vector{Excluded}` (ordinary), `n_must_include::Int`, `notes`
(strategy specific: an excursion's dropped rows, a full factorial's candidate
and accepted counts) as a `NamedTuple`, and the negative bookkeeping, kept
apart from the ordinary (contract §1.19, §5.10): `negative_required::Int`
and `negative_covered::Int` (negative targets, §6) and
`negative_excluded::Vector{Excluded}`, whose targets hold the invalid
position. The nine-argument constructor leaves the negative bookkeeping
empty.
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
end

Design(matrix, strategy, engine, seed, required, covered, excluded, n_must_include, notes) =
    Design(matrix, strategy, engine, seed, required, covered, excluded, n_must_include, notes,
           0, 0, Excluded[])

"""
    validate_design(request, matrix, required; strategy, negative = []) -> Int

Final validation (plan Phase 3 step 6, contract §1.21), in index space:
every row is complete and within its candidates, every row passes its
applicable rules (`violates` on the complete row, so every applicable table
is consulted, lazy ones through the request's memo, §12.19): every rule for
an ordinary row (§5.4), the rules that omit `p` for a negative row with its
invalid value at `p` (§5.5), and no row holds two invalid values (§5.7).
Must-include rows come first in the given order, and for a covering design
every required ordinary target is covered by an ordinary row, and every
required negative target in `negative` by a negative row, each recounted
from the rows (§5.9). Returns the number of required ordinary targets
covered. A failure is an `ErrorException` beginning "internal error",
naming the row or target. Values are never looked up; only `to_cases`
converts rows to values.
"""
function validate_design(request::Request, matrix::AbstractMatrix{<:Integer}, required;
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
    covered = _recount(request, ordinary, required)
    isempty(negative) || _recount(request, matrix[:, negative_rows], negative)
    return covered
end

_uncovered(request::Request, t) = error(
    "internal error: required target $(from_indices(request.space, _space_indices(request, t))) is not covered")

# The rows' projections onto each target's parameters, built once per
# parameter set, so the check is linear in targets plus rows.
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

# Every target of an unconstrained request is required. For each support, a
# row's projection onto it, whose entries were checked against the arity
# above, has the code (`_code`) whose target `TargetList` decodes: its
# position within the support's block. The support is covered exactly when
# every code appears. The same certification as the list, with no list.
function _recount(request::Request, matrix::AbstractMatrix{<:Integer}, required::TargetList)
    for (k, support) in enumerate(required.supports)
        seen = falses(required.offsets[k + 1] - required.offsets[k])
        for j in axes(matrix, 2)
            seen[_code(view(matrix, :, j), support, required.arity) + 1] = true
        end
        missed = findfirst(!, seen)
        missed === nothing || _uncovered(request, required[required.offsets[k] + missed])
    end
    return length(required)
end

"""
    to_cases(request, matrix) -> Vector{NamedTuple}

The design as named cases with the space's values (wrappers kept).
"""
function to_cases(request::Request, matrix::AbstractMatrix{<:Integer})
    return [from_indices(request.space, _space_indices(request, matrix[:, j])) for j in axes(matrix, 2)]
end
