# Feasibility in index space: whether a partial assignment extends to a
# valid row (with a witness), under a node budget, and why a target is
# excluded when it does not. Plan Phase 2 step 6; Phase 3's request layer
# consumes `dead`, and the public `explain`, `isallowed` and `classify`
# over a `TestSpace` are thin wrappers over `explain_partial` and `classify`
# here.
#
# Everything in this file is index space (see rule_table.jl). Parameters
# are `1:n`, values are the integers listed in `candidates`, and a partial
# assignment is a `Vector{Int}` with `0` for unset. Rule numbers are
# positions in `f.tables`; a caller that passes a filtered table list (a
# negative row, contract §5.5; a deletion trial) maps them back itself.
#
# The node budget (contract §3.3, §3.4). A node is one tentative assignment
# of one value to one parameter in the backtracking search, counting
# assignments that are later undone. Nothing else costs a node: the
# `violates` check, forward-checking prunes (including the initial prune
# before the first assignment), filling an unconstrained parameter with its
# first candidate, and every cache hit are free. One `completable` call has
# one budget, shared by every connected component it solves. A search that
# needs N nodes succeeds exactly when the limit is at least N.
#
# Rule checks are not budgeted but are counted (contract §3.3). A check is one
# `forbids(f, t, partial)` call: a set lookup for a tabulated table, a lookup
# in the operation's memo (evaluating the predicate on a miss) for a lazy
# one. After a node assigns `x`, forward checking checks each surviving
# candidate of the one unset parameter of every table of `x` that has one
# left, so the checks a node causes are at most the sum of those
# parameters' candidate counts. The direct check adds at most one check per
# table, and the initial prune the same sum once per component.

"""
    ResourceLimitError(what, limit, keyword)

A search or enumeration stopped at a resource limit before reaching a
conclusion (contract §3.7). `what` names the operation and the assignment or
target being resolved, `limit` is the value that was reached, and `keyword`
is the keyword that raises it, such as `:feasibility_limit`. The error never
carries a partial result. Retry the call with a larger value of `keyword`
(§3.8); raising a limit never changes an answer that was already resolved.
"""
struct ResourceLimitError <: Exception
    what::String
    limit::Int
    keyword::Symbol
end

function Base.showerror(io::IO, err::ResourceLimitError)
    larger = err.limit > typemax(Int) ÷ 10 ? typemax(Int) : 10 * err.limit
    print(io, "ResourceLimitError: ", err.what, " reached `", err.keyword, " = ",
        _grouped(err.limit), "` before finishing. Retry with a larger limit, for example `",
        err.keyword, " = ", _grouped(larger), "`.")
end

"Digits of `n` in groups of three, joined by underscores, as Julia writes them."
function _grouped(n::Integer)
    digits = string(abs(n))
    groups = String[]
    stop = length(digits)
    while stop > 0
        pushfirst!(groups, digits[max(1, stop - 2):stop])
        stop -= 3
    end
    return (n < 0 ? "-" : "") * join(groups, "_")
end


"""
Counters for one `Feasibility`, for tests and for reporting search effort.
`evaluations` counts every rule check made through the object: each
`forbids` call by `violates`, `violated_rules`, the direct check of
`completable` and `explain_partial`, and forward-checking prunes. A check of a
tabulated table is a set lookup and a check of a lazy one a lookup in the
operation's memo, evaluating the predicate on a miss, so `evaluations` bounds
the predicate calls from above.
"""
mutable struct SearchStats
    queries::Int      # `completable` questions asked, cached or not
    memo_hits::Int    # questions answered from the whole-assignment memo
    last_nodes::Int   # nodes spent by the most recent question
    total_nodes::Int  # nodes spent by every question
    evaluations::Int  # rule checks (`forbids` calls) by every question and check
end

SearchStats() = SearchStats(0, 0, 0, 0, 0)


"""
    Feasibility(candidates, tables; limit = 1_000_000)

A run-local search context for one active rule set (contract §3.4, §3.5).

- `candidates[i]` lists the value indices parameter `i` may take, in the
  order the search tries them. The model passes the ordinary indices; for a
  negative row with its invalid value at `p`, it passes that single invalid
  index at `p` and a `tables` list without the rules whose scope contains
  `p` (§5.5, §12.22).
- `tables` is the active rule set as `RuleTable`s. Rule numbers reported by
  this file are positions in `tables`.
- `limit` is the `feasibility_limit`: the node budget of each `completable`
  question (§3.3, §3.4). It must be positive.

The candidates and tables are fixed for the object's lifetime, so a
`Feasibility` is built per active rule set, and its caches are keyed by
the assignment alone: the key's rule-set part is the object itself (§3.5).
A negative row, a deletion trial, or any other change of rule set builds its
own `Feasibility`, so no answer leaks between rule sets. Caches hold only
proven answers, feasible with a witness or infeasible; an exhausted search
is never stored (§3.2, §3.5).

Parameters that share a table scope are connected; a whole-case table links
every parameter. Each connected component with at least one table is
solved separately. A parameter in no scope forms an unconstrained singleton
component, the only kind of parameter the search fills freely (with its
first candidate). Components are ordered by their smallest parameter, with
parameters ascending (`components`).

Fields: `candidates`, `tables`, `limit`, the component structure
(`components`, `component_of`, `component_tables`, `param_tables`),
`memo` (whole assignment ⇒ witness, or `nothing` for proven infeasible),
`witness_cache` (one `Dict` per component: the component's sub-assignment
⇒ the component's witness values, or `nothing`), `rule_memo`, and `stats`.

The lazy-rule memo (contract §3.5, §12.19). `rule_memo[k]` is `nothing` for
a tabulated table and, for a lazy one, a `Dict{NTuple{N,Int},Bool}` from the
scope's value indices to the rule's verdict. Every rule check made through
this object (`violates`, `violated_rules`, the searches, and a request's
final validation) goes through `forbids(f, k, partial)`, which evaluates a
lazy predicate at most once per tuple. A verdict depends on the table alone,
not on the rule set, so the `Feasibility` objects of one operation may share
the dicts: pass `memos`, aligned with `tables`, to reuse them (a deletion
trial does, and so does each row kind of a `FeasibilityContext`). Otherwise
each lazy table gets a fresh, empty dict. The memo lives as long as the
operation that holds this object and never on the `TestSpace`.
"""
struct Feasibility
    candidates::Vector{Vector{Int}}
    tables::Vector{RuleTable}
    limit::Int
    components::Vector{Vector{Int}}
    component_of::Vector{Int}
    component_tables::Vector{Vector{Int}}
    param_tables::Vector{Vector{Int}}
    memo::Dict{Vector{Int}, Union{Nothing, Vector{Int}}}
    witness_cache::Vector{Dict{Vector{Int}, Union{Nothing, Vector{Int}}}}
    rule_memo::Vector{Union{Nothing, Dict}}
    stats::SearchStats
end

"An empty verdict memo for a lazy table, `nothing` for a tabulated one."
_rule_memo(table::RuleTable) =
    table.lazy === nothing ? nothing : Dict{NTuple{length(table.scope), Int}, Bool}()

"""
    rule_memos(tables) -> Vector{Union{Nothing, Dict}}

One fresh verdict memo per table (`nothing` for a tabulated table), to pass
as `memos` to every `Feasibility` of one operation over (subsets of) these
tables.
"""
rule_memos(tables::AbstractVector) = Union{Nothing, Dict}[_rule_memo(t) for t in tables]

function Feasibility(candidates::AbstractVector, tables::AbstractVector; limit::Integer = 1_000_000,
                     memos = nothing)
    limit >= 1 || throw(ArgumentError("feasibility_limit must be a positive Int, got $limit"))
    cands = Vector{Int}[collect(Int, c) for c in candidates]
    n = length(cands)
    for (i, c) in enumerate(cands)
        isempty(c) && throw(ArgumentError("parameter $i has no candidate values"))
        all(>(0), c) || throw(ArgumentError("parameter $i has a candidate value index below 1: $c"))
        allunique(c) || throw(ArgumentError("parameter $i lists a candidate value index twice: $c"))
    end
    rules = collect(RuleTable, tables)
    for (k, t) in enumerate(rules)
        all(p -> 1 <= p <= n, t.scope) || throw(ArgumentError(
            "table $k has scope $(t.scope), outside the $n parameters"))
        allunique(t.scope) || throw(ArgumentError("table $k repeats a parameter in its scope $(t.scope)"))
    end
    if memos === nothing
        memos = rule_memos(rules)
    else
        length(memos) == length(rules) || throw(ArgumentError(
            "memos has $(length(memos)) entries for $(length(rules)) tables"))
        for (k, t) in enumerate(rules)
            memos[k] === nothing && t.lazy === nothing && continue
            memos[k] isa Dict{NTuple{length(t.scope), Int}, Bool} && t.lazy !== nothing && continue
            throw(ArgumentError("memos[$k] does not fit table $k"))
        end
    end
    components, component_of = _connected_components(n, rules)
    component_tables = [Int[] for _ in components]
    param_tables = [Int[] for _ in 1:n]
    for (k, t) in enumerate(rules)
        isempty(t.scope) && continue
        push!(component_tables[component_of[first(t.scope)]], k)
        for p in t.scope
            push!(param_tables[p], k)
        end
    end
    return Feasibility(cands, rules, Int(limit), components, component_of,
        component_tables, param_tables,
        Dict{Vector{Int}, Union{Nothing, Vector{Int}}}(),
        [Dict{Vector{Int}, Union{Nothing, Vector{Int}}}() for _ in components],
        collect(Union{Nothing, Dict}, memos), SearchStats())
end

"Union-find over table scopes. Components ordered by smallest member, members ascending."
function _connected_components(n::Int, tables::Vector{RuleTable})
    parent = collect(1:n)
    function root(i)
        while parent[i] != i
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for t in tables, k in 2:length(t.scope)
        a, b = root(t.scope[1]), root(t.scope[k])
        a == b || (parent[max(a, b)] = min(a, b))
    end
    components = Vector{Int}[]
    label = zeros(Int, n)
    component_of = zeros(Int, n)
    for p in 1:n
        r = root(p)
        if label[r] == 0
            push!(components, Int[])
            label[r] = length(components)
        end
        push!(components[label[r]], p)
        component_of[p] = label[r]
    end
    return components, component_of
end

function Base.show(io::IO, f::Feasibility)
    print(io, "Feasibility(", length(f.candidates), " parameters, ", length(f.tables),
        " tables, ", length(f.components), " components, limit = ", f.limit, ")")
end

"""
    components(f::Feasibility) -> Vector{Vector{Int}}

The connected components of the parameters: parameters that share a table
scope are connected, and a whole-case table connects all of them (contract
§12.21). A parameter in no scope is an unconstrained singleton component.
Components are ordered by smallest parameter, with parameters ascending.
"""
components(f::Feasibility) = [copy(c) for c in f.components]

"""
    forbids(f::Feasibility, k, partial) -> Bool

Whether table `k` of `f` forbids the values assigned in `partial` (its scope
must be assigned), through the operation's memo: a tabulated table is a set
lookup, and a lazy table's predicate is evaluated at most once per tuple of
scoped value indices, then read from `f.rule_memo[k]` (contract §12.19). An
evaluation that throws stores nothing. Callers count the check in
`f.stats.evaluations`.
"""
function forbids(f::Feasibility, k::Int, partial::AbstractVector{<:Integer})
    table = f.tables[k]
    table.lazy === nothing && return forbids(table, partial)
    return _memo_forbids(f.rule_memo[k], table, partial)
end

function _memo_forbids(memo::Dict{NTuple{N, Int}, Bool}, table::RuleTable,
                       partial::AbstractVector{<:Integer}) where {N}
    scope = table.scope
    key = ntuple(j -> Int(partial[scope[j]]), Val(N))
    return get!(() -> table.lazy(key)::Bool, memo, key)
end

"""
    memo_size(f::Feasibility) -> Int

The number of lazy-rule verdicts memoized in `f.rule_memo`, summed over its
tables: `0` when every table is tabulated. Dicts shared with other
`Feasibility` objects of the same operation (see `memos`) are counted as
they stand. Not exported; the benchmarks and tests read it.
"""
memo_size(f::Feasibility) = sum((length(m) for m in f.rule_memo if m !== nothing); init = 0)

"Whether component `c` has a table, so that it must be solved (§3.4)."
_constrained(f::Feasibility, c::Int) = !isempty(f.component_tables[c])

"Validate a partial assignment and return it as a fresh `Vector{Int}`."
function _checked_key(f::Feasibility, partial::AbstractVector{<:Integer})
    n = length(f.candidates)
    length(partial) == n || throw(ArgumentError(
        "a partial assignment has one entry per parameter: expected $n, got $(length(partial))"))
    key = collect(Int, partial)
    for i in 1:n
        v = key[i]
        (v == 0 || v in f.candidates[i]) || throw(ArgumentError(
            "parameter $i is assigned value index $v, which is not among its candidates $(f.candidates[i])"))
    end
    return key
end


"""
    violates(f::Feasibility, partial) -> Bool

True when some table whose scope is entirely assigned in `partial` forbids
it. A table with any unset parameter in its scope is never evaluated
(contract §1.6, §12.14). This is the direct check only; `completable` also
proves exclusions that need a search.
"""
violates(f::Feasibility, partial::AbstractVector{<:Integer}) = _violates(f, _checked_key(f, partial))

function _violates(f::Feasibility, key::Vector{Int})
    for (k, t) in enumerate(f.tables)
        assigned(t, key) || continue
        f.stats.evaluations += 1
        forbids(f, k, key) && return true
    end
    return false
end

"""
    violated_rules(f::Feasibility, partial) -> Vector{Int}

Every table, in table order, whose scope is entirely assigned in `partial`
and which forbids it: the *direct* attribution of contract §1.4 and §1.26.
Empty when `violates(f, partial)` is false.
"""
violated_rules(f::Feasibility, partial::AbstractVector{<:Integer}) =
    _violated_rules(f, _checked_key(f, partial))

function _violated_rules(f::Feasibility, key::Vector{Int})
    rules = Int[]
    for (k, t) in enumerate(f.tables)
        assigned(t, key) || continue
        f.stats.evaluations += 1
        forbids(f, k, key) && push!(rules, k)
    end
    return rules
end


"""
    completable(f::Feasibility, partial; limit = f.limit) -> (status, witness)

Whether `partial` extends to a complete row that satisfies every table in
`f`, taking unset parameters from their candidates (contract §3.1).

- `(:feasible, witness)`: `witness` is a complete row extending `partial`
  (assigned values unchanged, contract §7.10) that no table forbids.
- `(:infeasible, nothing)`: proven by an exhausted search.
- `(:unknown, nothing)`: the search spent `limit` nodes without a
  conclusion (§1.7). Never cached (§3.2, §3.5); ask again with a larger
  `limit`, or build a `Feasibility` with one, to resolve it (§3.8).

If `violates(f, partial)` holds, the answer is `:infeasible` at once.
Otherwise every constrained connected component is solved, including
components with no assigned parameter, so an unsatisfiable component
anywhere makes the completion infeasible (§3.4). Unconstrained parameters
take their first candidate.

The search is backtracking with forward checking: after each tentative
assignment, every table with exactly one unset parameter left removes that
parameter's forbidden candidates, and an emptied candidate list backtracks.
The next parameter is the unset one with the fewest remaining candidates,
ties to the lowest index; values are tried in candidate order. The node
budget (`limit`, one per call, shared across components) counts tentative
assignments, including undone ones (§3.3, §3.4).

Answers are cached: the whole assignment in `f.memo`, and each component's
witness in `f.witness_cache`, keyed by that component's sub-assignment, so
a later question that shares it costs no nodes. The witness is a function of
`partial` alone: the order of earlier questions and the size of the limit
never change it (§3.8, §9.3).
"""
function completable(f::Feasibility, partial::AbstractVector{<:Integer}; limit::Integer = f.limit)
    limit >= 1 || throw(ArgumentError("feasibility_limit must be a positive Int, got $limit"))
    status, witness = _completable(f, _checked_key(f, partial), Int(limit))
    return status, witness === nothing ? nothing : copy(witness)
end

"""
    dead(f::Feasibility, partial) -> Bool

The engines' predicate (plan Phase 3 step 1): `true` only when `partial`
is proven to have no valid completion, `false` only when a witness exists.
When the search reaches `f.limit` it throws `ResourceLimitError` naming
`feasibility_limit`, never guessing either way (contract §1.7, §3.6).
"""
function dead(f::Feasibility, partial::AbstractVector{<:Integer})
    key = _checked_key(f, partial)
    status, _ = _completable(f, key, f.limit)
    status === :unknown && throw(ResourceLimitError(
        "the feasibility search for the partial assignment $key", f.limit, :feasibility_limit))
    return status === :infeasible
end

# The internal question: `key` is validated and owned by the caller, and the
# returned witness is the memo's own vector, not a copy.
function _completable(f::Feasibility, key::Vector{Int}, limit::Int)
    stats = f.stats
    stats.queries += 1
    stats.last_nodes = 0
    if haskey(f.memo, key)
        stats.memo_hits += 1
        witness = f.memo[key]
        return witness === nothing ? (:infeasible, nothing) : (:feasible, witness)
    end
    if _violates(f, key)
        f.memo[key] = nothing
        return (:infeasible, nothing)
    end
    witness = copy(key)
    pending = Int[]
    # Free parameters and cached components first: they cost no nodes, and
    # a cached infeasible component settles the question at once.
    for c in eachindex(f.components)
        params = f.components[c]
        if !_constrained(f, c)
            for p in params
                witness[p] == 0 && (witness[p] = f.candidates[p][1])
            end
            continue
        end
        all(p -> key[p] != 0, params) && continue  # fully assigned; `_violates` checked it
        cached = get(f.witness_cache[c], key[params], missing)
        if cached === missing
            push!(pending, c)
        elseif cached === nothing
            f.memo[key] = nothing
            return (:infeasible, nothing)
        else
            witness[params] .= cached
        end
    end
    search = _Search(f, witness, limit)
    status = :feasible
    for c in pending
        params = f.components[c]
        status = _solve_component!(search, c)
        if status === :feasible
            f.witness_cache[c][key[params]] = witness[params]
        elseif status === :infeasible
            f.witness_cache[c][key[params]] = nothing
            break
        else
            break  # :unknown, the budget is spent; store nothing
        end
    end
    stats.last_nodes = search.nodes
    stats.total_nodes += search.nodes
    if status === :feasible
        f.memo[key] = witness
        return (:feasible, witness)
    elseif status === :infeasible
        f.memo[key] = nothing
        return (:infeasible, nothing)
    else
        return (:unknown, nothing)
    end
end

# Backtracking state for one `completable` question. `work` is the witness
# under construction: a component's tables read only that component's
# parameters, so components share it without interference. `alive[p][k]`
# says whether `candidates[p][k]` survives forward checking, `live[p]` counts
# the survivors, and `trail` records removals so a backtrack can undo them.
mutable struct _Search
    const f::Feasibility
    const work::Vector{Int}
    const alive::Vector{Vector{Bool}}
    const live::Vector{Int}
    const trail::Vector{Tuple{Int, Int}}
    const limit::Int
    nodes::Int
end

function _Search(f::Feasibility, work::Vector{Int}, limit::Int)
    n = length(f.candidates)
    return _Search(f, work, [Bool[] for _ in 1:n], zeros(Int, n), Tuple{Int, Int}[], limit, 0)
end

function _solve_component!(s::_Search, c::Int)
    f = s.f
    params = f.components[c]
    for p in params
        if s.work[p] == 0
            s.alive[p] = fill(true, length(f.candidates[p]))
            s.live[p] = length(f.candidates[p])
        end
    end
    # The initial prune: tables already down to one unset parameter.
    for t in f.component_tables[c]
        y = _sole_unassigned(f.tables[t], s.work)
        y > 0 && !_prune!(s, t, y) && return :infeasible
    end
    return _backtrack!(s, params)
end

"The one unset parameter of a table's scope; 0 if none is unset, -1 if several are."
function _sole_unassigned(table::RuleTable, work::Vector{Int})
    y = 0
    for p in table.scope
        if work[p] == 0
            y == 0 || return -1
            y = p
        end
    end
    return y
end

# Remove from `y` every surviving candidate that table `t` forbids, given the
# rest of its scope is assigned. False when no candidate survives.
function _prune!(s::_Search, t::Int, y::Int)
    cands = s.f.candidates[y]
    alive = s.alive[y]
    stats = s.f.stats
    for k in eachindex(cands)
        alive[k] || continue
        s.work[y] = cands[k]
        stats.evaluations += 1
        if forbids(s.f, t, s.work)
            alive[k] = false
            s.live[y] -= 1
            push!(s.trail, (y, k))
        end
    end
    s.work[y] = 0
    return s.live[y] > 0
end

# After assigning `x`, prune through every table of `x` that now has one
# unset parameter. A table that becomes fully assigned needs no check: it had
# `x` as its one unset parameter, so `x`'s value already survived it.
function _forward_check!(s::_Search, x::Int)
    for t in s.f.param_tables[x]
        y = _sole_unassigned(s.f.tables[t], s.work)
        y > 0 && !_prune!(s, t, y) && return false
    end
    return true
end

function _undo!(s::_Search, mark::Int)
    while length(s.trail) > mark
        y, k = pop!(s.trail)
        s.alive[y][k] = true
        s.live[y] += 1
    end
end

function _backtrack!(s::_Search, params::Vector{Int})
    x = 0
    fewest = typemax(Int)
    for p in params
        if s.work[p] == 0 && s.live[p] < fewest
            fewest = s.live[p]
            x = p
        end
    end
    x == 0 && return :feasible
    cands = s.f.candidates[x]
    alive = s.alive[x]
    for k in eachindex(cands)
        alive[k] || continue
        s.nodes >= s.limit && return :unknown
        s.nodes += 1
        s.work[x] = cands[k]
        mark = length(s.trail)
        if _forward_check!(s, x)
            result = _backtrack!(s, params)
            result === :infeasible || return result
        end
        _undo!(s, mark)
        s.work[x] = 0
    end
    return :infeasible
end


"""
    IndexExplanation

The index-space answer of `explain_partial`, which `explain(space, ...)` turns
into an `Explanation` (contract §1.26). `outcome` is one of

- `:allowed`: the assignment is complete and no table forbids it; `witness`
  is the assignment itself.
- `:forbidden`: `rules` lists every table, in table order, whose scope is
  entirely assigned and which forbids the assignment (§1.4 *direct*).
- `:completable`: `witness` is a valid complete row extending it.
- `:infeasible`: proven to have no valid completion, though no table forbids
  it directly. `rules` is a proven sufficient set from the deletion search
  (§3.13–§3.15), in table order, possibly one rule whose scope reaches
  beyond the assigned parameters (§1.4 *implied*).
- `:unknown`: the feasibility search reached its limit (§1.7).

`minimal` is `:verified` when removing each rule in `rules` was shown to
make the assignment feasible with a witness (§3.16), `:unresolved` when some
removal could not be decided within a limit, and `:not_applicable` for every
outcome but `:infeasible`. `limit` names the keyword whose limit decided the
result: `:feasibility_limit` for `:unknown`; for an `:unresolved` explanation,
`:explanation_limit` when the deletion search ran out of budget, otherwise
`:feasibility_limit` when a trial reached its own limit; `nothing` when no
limit mattered.

`nodes` and `evaluations` are what this answer cost (contract §3.3): the
nodes of its completability search plus those of every deletion trial, and
the rule checks (`forbids` calls, see `SearchStats`) of its direct check,
search, and deletion trials. An answer found in `f`'s caches costs no nodes,
so these depend on the questions asked before; the answer itself does not.
"""
struct IndexExplanation
    outcome::Symbol
    rules::Vector{Int}
    minimal::Symbol
    witness::Union{Nothing, Vector{Int}}
    limit::Union{Nothing, Symbol}
    nodes::Int
    evaluations::Int
end

"""
    explain_partial(f::Feasibility, partial; explanation_limit = 1_000_000) -> IndexExplanation

Why `partial` is or is not part of a valid row, as one of the five outcomes
of contract §1.26 (see `IndexExplanation`). The direct check comes first, so a
complete or partial assignment that some fully assigned table forbids is
`:forbidden` with every such rule. A complete assignment that no table
forbids is `:allowed`. Otherwise `completable` decides between
`:completable`, `:unknown`, and `:infeasible`; only a proven infeasible
assignment gets a deletion search, whose budget is `explanation_limit`
(§3.13). Infeasibility never depends on that budget (§3.15).
"""
function explain_partial(f::Feasibility, partial::AbstractVector{<:Integer};
                         explanation_limit::Integer = 1_000_000)
    explanation_limit >= 1 || throw(ArgumentError(
        "explanation_limit must be a positive Int, got $explanation_limit"))
    key = _checked_key(f, partial)
    nodes, evaluations = f.stats.total_nodes, f.stats.evaluations
    cost(trials = (0, 0)) = (f.stats.total_nodes - nodes + trials[1],
                             f.stats.evaluations - evaluations + trials[2])
    direct = _violated_rules(f, key)
    isempty(direct) ||
        return IndexExplanation(:forbidden, direct, :not_applicable, nothing, nothing, cost()...)
    all(!=(0), key) && return IndexExplanation(:allowed, Int[], :not_applicable, key, nothing, cost()...)
    status, witness = _completable(f, key, f.limit)
    if status === :feasible
        return IndexExplanation(:completable, Int[], :not_applicable, copy(witness), nothing, cost()...)
    elseif status === :unknown
        return IndexExplanation(:unknown, Int[], :not_applicable, nothing, :feasibility_limit, cost()...)
    end
    rules, minimal, limit, trials = _deletion_search(f, key, Int(explanation_limit))
    return IndexExplanation(:infeasible, rules, minimal, nothing, limit, cost(trials)...)
end

# The deletion search of contract §3.14–§3.16 for `key`, which is proven
# infeasible under all of `f.tables`. Rules are tried in table order. Each
# trial is a fresh `Feasibility` over the kept rules minus one, sharing `f`'s
# lazy-rule memo (a verdict depends on no rule set), with its own `f.limit`
# budget, capped by what remains of `explanation_limit`, which all of this
# target's trials share. A trial proving infeasibility drops the rule; a
# feasible trial (with a witness) proves the rule necessary; an unknown trial
# keeps the rule unverified. The kept set is sufficient by construction, and
# a rule proven necessary stays necessary as others are dropped, because
# fewer rules allow more rows. Also returns the trials' cost, (nodes, rule
# checks).
function _deletion_search(f::Feasibility, key::Vector{Int}, explanation_limit::Int)
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
        trial = Feasibility(f.candidates, f.tables[trial_rules]; limit = f.limit,
                            memos = f.rule_memo[trial_rules])
        status, _ = _completable(trial, key, min(f.limit, remaining))
        remaining -= trial.stats.last_nodes
        nodes += trial.stats.total_nodes
        evaluations += trial.stats.evaluations
        if status === :infeasible
            keep = trial_rules
        elseif status === :unknown
            verified = false
            limit = remaining <= 0 ? :explanation_limit : :feasibility_limit
        end
    end
    return keep, verified ? :verified : :unresolved, limit, (nodes, evaluations)
end


"""
    IndexClassification

One target's classification in index space, which `classify(space, ...)` turns
into a `Classification` (contract §1.2, §1.4, §1.7). `status` is

- `:required`: feasible; `witness` is a valid row containing it.
- `:forbidden`: `rules` lists every table, in table order, whose scope lies
  within the target's assigned parameters and which forbids it (*direct*).
- `:implied`: proven infeasible with no direct rule; `rules` is a proven
  sufficient set from the deletion search, and `minimal` its status
  (`:verified` or `:unresolved`, §3.16).
- `:unknown`: the feasibility search reached its limit; neither required
  nor excluded.

`minimal` is `:not_applicable` except for `:implied`. `limit`, `nodes` and
`evaluations` are as in `IndexExplanation`.
"""
struct IndexClassification
    status::Symbol
    rules::Vector{Int}
    minimal::Symbol
    witness::Union{Nothing, Vector{Int}}
    limit::Union{Nothing, Symbol}
    nodes::Int
    evaluations::Int
end

const _STATUS_OF_OUTCOME = (allowed = :required, completable = :required,
    forbidden = :forbidden, infeasible = :implied, unknown = :unknown)

IndexClassification(e::IndexExplanation) = IndexClassification(_STATUS_OF_OUTCOME[e.outcome],
    e.rules, e.minimal, e.witness, e.limit, e.nodes, e.evaluations)

"""
    classify(f::Feasibility, targets; explanation_limit = 1_000_000) -> Vector{IndexClassification}

Classify each target, a partial assignment, as `:required`, `:forbidden`,
`:implied`, or `:unknown` (see `IndexClassification`). Results follow the order
of `targets` (§9.7). Each target has its own feasibility budget, `f.limit`
(§3.4), and its own `explanation_limit` for the deletion search (§3.13);
answers proven for one target are cached in `f` for the next.
"""
function classify(f::Feasibility, targets::AbstractVector{<:AbstractVector{<:Integer}};
                  explanation_limit::Integer = 1_000_000)
    return IndexClassification[IndexClassification(explain_partial(f, t; explanation_limit)) for t in targets]
end
