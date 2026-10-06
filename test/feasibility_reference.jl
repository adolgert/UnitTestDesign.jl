# The feasibility answer caches as they were before Phase 5 (31bef0f,
# src/feasibility.jl:424–605), kept as the reference that the caches by
# component are checked against (test_feasibility.jl, "the caches by
# component answer as the whole-assignment memo did"). Plan §5.6.
#
# `ReferenceCaches(f)` reads only what a `Feasibility` fixes for its lifetime
# (candidates, tables, components and their tables) and checks rules through
# `forbids(f, k, partial)`, which keeps no answer and counts nothing. Its
# caches and counters are its own: the whole-assignment `memo`, one
# `witness_cache` per component, and the counters of `SearchStats`. The code
# below is 31bef0f's `_completable`, `_violates` and backtracking search with
# `f.memo`, `f.witness_cache` and `f.stats` read from the reference instead;
# the search is unchanged, line for line. Include it in a test item:
# `include(joinpath(@__DIR__, "feasibility_reference.jl"))`.

using UnitTestDesign: Feasibility, RuleTable, forbids, assigned

mutable struct ReferenceCaches
    const f::Feasibility
    const memo::Dict{Vector{Int}, Union{Nothing, Vector{Int}}}
    const witness_cache::Vector{Dict{Vector{Int}, Union{Nothing, Vector{Int}}}}
    queries::Int
    memo_hits::Int
    last_nodes::Int
    total_nodes::Int
    evaluations::Int
end

ReferenceCaches(f::Feasibility) = ReferenceCaches(f, Dict{Vector{Int}, Union{Nothing, Vector{Int}}}(),
    [Dict{Vector{Int}, Union{Nothing, Vector{Int}}}() for _ in f.components], 0, 0, 0, 0, 0)

_ref_constrained(r::ReferenceCaches, c::Int) = !isempty(r.f.component_tables[c])

function _ref_violates(r::ReferenceCaches, key::Vector{Int})
    for (k, t) in enumerate(r.f.tables)
        assigned(t, key) || continue
        r.evaluations += 1
        forbids(r.f, k, key) && return true
    end
    return false
end

"31bef0f's `_completable(f, key, limit)`, on the reference's caches; `key` is not modified."
function reference_completable(r::ReferenceCaches, key::Vector{Int}, limit::Int)
    f = r.f
    r.queries += 1
    r.last_nodes = 0
    if haskey(r.memo, key)
        r.memo_hits += 1
        witness = r.memo[key]
        return witness === nothing ? (:infeasible, nothing) : (:feasible, witness)
    end
    key = copy(key)   # the memo keeps it
    if _ref_violates(r, key)
        r.memo[key] = nothing
        return (:infeasible, nothing)
    end
    witness = copy(key)
    pending = Int[]
    for c in eachindex(f.components)
        params = f.components[c]
        if !_ref_constrained(r, c)
            for p in params
                witness[p] == 0 && (witness[p] = f.candidates[p][1])
            end
            continue
        end
        all(p -> key[p] != 0, params) && continue
        cached = get(r.witness_cache[c], key[params], missing)
        if cached === missing
            push!(pending, c)
        elseif cached === nothing
            r.memo[key] = nothing
            return (:infeasible, nothing)
        else
            witness[params] .= cached
        end
    end
    status = :feasible
    nodes = 0
    if !isempty(pending)
        search = _RefSearch(r, witness, limit)
        for c in pending
            params = f.components[c]
            status = _ref_solve_component!(search, c)
            if status === :feasible
                r.witness_cache[c][key[params]] = witness[params]
            elseif status === :infeasible
                r.witness_cache[c][key[params]] = nothing
                break
            else
                break
            end
        end
        nodes = search.nodes
    end
    r.last_nodes = nodes
    r.total_nodes += nodes
    if status === :feasible
        r.memo[key] = witness
        return (:feasible, witness)
    elseif status === :infeasible
        r.memo[key] = nothing
        return (:infeasible, nothing)
    else
        return (:unknown, nothing)
    end
end

mutable struct _RefSearch
    const r::ReferenceCaches
    const work::Vector{Int}
    const alive::Vector{Vector{Bool}}
    const live::Vector{Int}
    const trail::Vector{Tuple{Int, Int}}
    const limit::Int
    nodes::Int
end

function _RefSearch(r::ReferenceCaches, work::Vector{Int}, limit::Int)
    n = length(r.f.candidates)
    return _RefSearch(r, work, [Bool[] for _ in 1:n], zeros(Int, n), Tuple{Int, Int}[], limit, 0)
end

function _ref_solve_component!(s::_RefSearch, c::Int)
    f = s.r.f
    params = f.components[c]
    for p in params
        if s.work[p] == 0
            s.alive[p] = fill(true, length(f.candidates[p]))
            s.live[p] = length(f.candidates[p])
        end
    end
    for t in f.component_tables[c]
        y = _ref_sole_unassigned(f.tables[t], s.work)
        y > 0 && !_ref_prune!(s, t, y) && return :infeasible
    end
    return _ref_backtrack!(s, params)
end

function _ref_sole_unassigned(table::RuleTable, work::Vector{Int})
    y = 0
    for p in table.scope
        if work[p] == 0
            y == 0 || return -1
            y = p
        end
    end
    return y
end

function _ref_prune!(s::_RefSearch, t::Int, y::Int)
    f = s.r.f
    cands = f.candidates[y]
    alive = s.alive[y]
    for k in eachindex(cands)
        alive[k] || continue
        s.work[y] = cands[k]
        s.r.evaluations += 1
        if forbids(f, t, s.work)
            alive[k] = false
            s.live[y] -= 1
            push!(s.trail, (y, k))
        end
    end
    s.work[y] = 0
    return s.live[y] > 0
end

function _ref_forward_check!(s::_RefSearch, x::Int)
    f = s.r.f
    for t in f.param_tables[x]
        y = _ref_sole_unassigned(f.tables[t], s.work)
        y > 0 && !_ref_prune!(s, t, y) && return false
    end
    return true
end

function _ref_undo!(s::_RefSearch, mark::Int)
    while length(s.trail) > mark
        y, k = pop!(s.trail)
        s.alive[y][k] = true
        s.live[y] += 1
    end
end

function _ref_backtrack!(s::_RefSearch, params::Vector{Int})
    x = 0
    fewest = typemax(Int)
    for p in params
        if s.work[p] == 0 && s.live[p] < fewest
            fewest = s.live[p]
            x = p
        end
    end
    x == 0 && return :feasible
    cands = s.r.f.candidates[x]
    alive = s.alive[x]
    for k in eachindex(cands)
        alive[k] || continue
        s.nodes >= s.limit && return :unknown
        s.nodes += 1
        s.work[x] = cands[k]
        mark = length(s.trail)
        if _ref_forward_check!(s, x)
            result = _ref_backtrack!(s, params)
            result === :infeasible || return result
        end
        _ref_undo!(s, mark)
        s.work[x] = 0
    end
    return :infeasible
end

"""
31bef0f's `_deletion_search(f, key, explanation_limit)`, each trial a fresh
`Feasibility` over the kept rules minus one, asked through a fresh
`ReferenceCaches`. Returns the kept rules, `:verified` or `:unresolved`, the
limit that stopped it, and the trials' (nodes, rule checks).
"""
function reference_deletion_search(f::Feasibility, key::Vector{Int}, explanation_limit::Int)
    keep = collect(eachindex(f.tables))
    remaining = explanation_limit
    verified = true
    limit = nothing
    nodes = evaluations = 0
    for r in eachindex(f.tables)
        if remaining <= 0
            verified = false
            limit = :explanation_limit
            break
        end
        trial_rules = filter(!=(r), keep)
        trial = ReferenceCaches(Feasibility(f.candidates, f.tables[trial_rules]; limit = f.limit,
                                            memos = f.rule_memo[trial_rules]))
        status, _ = reference_completable(trial, key, min(f.limit, remaining))
        remaining -= trial.last_nodes
        nodes += trial.total_nodes
        evaluations += trial.evaluations
        if status === :infeasible
            keep = trial_rules
        elseif status === :unknown
            verified = false
            limit = remaining <= 0 ? :explanation_limit : :feasibility_limit
        end
    end
    return keep, verified ? :verified : :unresolved, limit, (nodes, evaluations)
end
