# Negative generation (plan Phase 6 step 1; contract §5, §6, §7.9, §10).
#
# The covering design is built over ordinary values only (`generate` in
# engines.jl, `cover_ordinary`). Then, for each invalid value `v` of each
# parameter `p`, in parameter order and then domain order, the negative
# targets of §6 are classified by the negative-row search (`feasibility_for`
# with `p = v`: candidates `[v]` at `p`, ordinary values elsewhere, the rules
# whose scope omits `p`, §5.5, §6.2), and rows covering the feasible ones are
# generated with the same engine.
#
# The rows come from a sub-request. No active rule reads `p`, so a negative
# row at `(p, v)` is `p = v` beside any valid assignment of the other
# parameters under the active rules, and its targets `(p = v, a)` are the
# targets `a` of a request over the other parameters: at strength `s - 1`,
# with each `stronger` group `G` that contains `p` as `G \ {p}` at `s_G - 1`
# (§6.1, §6.3); groups without `p` add nothing (§6.5). `_negative_request`
# builds that request over a sub-space of the other parameters that reuses
# the space's domains and its active rule tables, renumbered, and shares the
# request's lazy-rule memo (§3.5). The engine covers the sub-request's
# required targets, and `p = v` is inserted at its position. A base strength
# of 1 gives the sub-request strength 0: its base group has no targets and
# only its groups do (see `Request`). At strength 1 with no group containing
# `p` there is no sub-request: the one target `(p = v)` takes one witness row
# (§6.4), never a strength-0 public call.
#
# Negative must-include rows count toward the negative targets they hold
# (§10.6): those at `(p, v)` are the sub-request's must-include rows, so the
# engine completes a partial one (§7.9) and covers only what they leave.


"`row` (engine positions over the parameters other than `p`) with `p` at `position` inserted."
function _with_invalid(row::AbstractVector{<:Integer}, p::Int, position::Int)
    out = Vector{Int}(undef, length(row) + 1)
    out[1:(p - 1)] .= view(row, 1:(p - 1))
    out[p] = position
    out[(p + 1):end] .= view(row, p:length(row))
    return out
end

"""
    _negative_request(request, p, seeds) -> Request

The request whose covering design gives the negative rows with their invalid
value at `p` (see the file header): over the parameters other than `p`, in
order; with the rules whose scope omits `p` (§5.5), their tables renumbered
and their lazy-rule memo shared with `request` (§3.5); at base strength
`request.strength - 1`, which may be 0; with each `stronger` group `G` that
contains `p` as `G \\ {p}` at its strength less one. `seeds` are its
must-include rows, engine positions over the other parameters. Nothing is
validated or tabulated again, and no predicate is called.
"""
function _negative_request(request::Request, p::Int, seeds::AbstractMatrix{<:Integer})
    space = request.space
    n = length(space.names)
    others = [q for q in 1:n if q != p]
    renumber = zeros(Int, n)
    renumber[others] = 1:(n - 1)
    active = active_rules(space, p)
    tables = RuleTable[RuleTable(renumber[t.scope], t.forbidden, t.lazy) for t in space.tables[active]]
    subspace = TestSpace(Val(:parts), (names = space.names[others], values = space.values[others],
        constraints = space.constraints[active], tables = tables, tabulation_limit = space.tabulation_limit,
        ordinary = space.ordinary[others], invalid = space.invalid[others]))
    stronger = [renumber[filter(!=(p), members)] => s - 1 for (members, s) in request.groups[2:end]
                if p in members]
    groups = _groups(subspace, request.strength - 1, stronger)
    feasibility = Feasibility(_candidates(subspace, 0, 0), tables;
                              limit = request.feasibility_limit, memos = request.feasibility.rule_memo[active])
    return _request(subspace, request.strength - 1, groups, Matrix{Int}(seeds), feasibility,
                    request.feasibility_limit, request.explanation_limit)
end

"""
    _classify_negative(request, target) -> Union{Nothing, Excluded}

Classify one negative target (engine positions, one invalid position) with
the negative-row search of its invalid value (`feasibility_for`, §6.2):
`nothing` when it is required, else its `Excluded` record with the rules in
the space's numbering (§1.4, §6.7). An unknown answer throws
`ResourceLimitError` (§3.6, §6.7).
"""
function _classify_negative(request::Request, target::AbstractVector{<:Integer})
    idx = _space_indices(request, target)
    f, active = feasibility_for(request.context, idx)
    return _classify_target(request, f, active, target, idx, "classifying the negative target")
end

"""
    _negative_order(ranks, target) -> Tuple

The sort key that puts negative targets in the order `coverage` measures them
(§9.7): by support, in the order of `_supports(request.groups)` (`ranks`),
then by the invalid parameter, its value, and the other values with the first
parameter varying fastest. So a result's negative exclusions list as
`coverage(cases).negative.excluded` does.
"""
function _negative_order(ranks::Dict{Vector{Int}, Int}, arity::Vector{Int}, target::Vector{Int})
    support = findall(!=(0), target)
    p = only(q for q in support if target[q] > arity[q])
    rest = [target[q] for q in reverse(support) if q != p]
    return (ranks[support], p, target[p], rest)
end

"""
    cover_negative(engine, request, columns) -> (; seeds, rows, required, excluded)

Negative generation (contract §6.7). For each invalid value `v` of each
parameter `p`, in parameter order and then domain order: classify its
negative targets (§6.1–§6.5) by the negative-row search, stopping with
`ResourceLimitError` on any unknown; record the infeasible ones; and cover
the feasible ones with `engine` through `_negative_request`, whose
must-include rows are the negative must-include rows at `(p, v)` (the
request's must-include `columns` that hold an invalid value). At strength 1
the target `(p = v)` alone is required when a valid negative row with
`p = v` exists, and takes one witness row unless a must-include or generated
row already holds `p = v` (§6.4).

Returns, in engine positions: `seeds`, each negative must-include column's
completed row, by column; `rows`, the generated negative rows, in `(p, v)`
order; `required`, every required negative target; and `excluded`, the
`Excluded` negative targets in the order `coverage` lists them. The caller
validates the rows (`validate_design`).
"""
function cover_negative(engine, request::Request, columns::Vector{Int})
    space = request.space
    n = length(space.names)
    must = request.must_include
    seeds = Dict{Int, Vector{Int}}()
    rows = Vector{Int}[]
    required = Vector{Int}[]
    excluded = Excluded[]
    for p in 1:n, position in (request.arity[p] + 1):length(request.candidates[p])
        at = [j for j in columns if must[p, j] == position]
        others = [q for q in 1:n if q != p]
        added = 0
        alone = nothing   # the target (p = v) at strength 1, when it is required
        if request.strength == 1
            t = zeros(Int, n)
            t[p] = position
            e = _classify_negative(request, t)
            e === nothing ? (push!(required, t); alone = t) : push!(excluded, e)
        end
        if request.strength > 1 || any(g -> p in g.first, request.groups[2:end])
            sub = _negative_request(request, p, must[others, at])
            sub_required = Vector{Int}[]
            for target in TargetList(sub)
                t = _with_invalid(target, p, position)
                e = _classify_negative(request, t)
                if e === nothing
                    push!(required, t)
                    push!(sub_required, target)
                else
                    push!(excluded, e)
                end
            end
            matrix = try
                cover_ordinary(engine, sub, sub_required)
            catch err
                err isa ResourceLimitError || rethrow()
                value = space.values[p][request.candidates[p][position]]
                throw(ResourceLimitError("generating the negative rows with $(space.names[p]) = " *
                                         "$(repr(value)): $(err.what)", err.limit, err.keyword))
            end
            for (k, j) in enumerate(at)
                seeds[j] = _with_invalid(matrix[:, k], p, position)
            end
            for k in (length(at) + 1):size(matrix, 2)
                push!(rows, _with_invalid(matrix[:, k], p, position))
                added += 1
            end
        else
            for j in at
                row = must[:, j]
                seeds[j] = any(==(0), row) ? witness(request, row) : row
            end
        end
        if alone !== nothing && isempty(at) && added == 0
            push!(rows, witness(request, alone))
        end
    end
    ranks = Dict(support => k for (k, support) in enumerate(_supports(request.groups)))
    sort!(excluded; by = e -> _negative_order(ranks, request.arity, e.target))
    return (; seeds, rows, required, excluded)
end
