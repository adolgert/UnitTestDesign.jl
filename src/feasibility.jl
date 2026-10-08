# Feasibility in index space: whether a partial assignment extends to a
# valid row (with a witness), under a node budget, and why a target is
# excluded when it does not. Plan Phase 2 step 6; Phase 3's request layer
# consumes `dead`, and the public `explain` and the unexported `classify`
# over a `TestSpace` are thin wrappers over `explain_partial` and `classify`
# here. (`isallowed` reads the rule tables directly and never searches.)
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
# `forbids(f, t, partial)` call: a bit test for a tabulated table, a lookup
# in the operation's memo (evaluating the predicate on a miss) for a lazy
# one. After a node assigns `x`, forward checking checks each surviving
# candidate of the one unset parameter of every table of `x` that has one
# left, so the checks a node causes are at most the sum of those
# parameters' candidate counts. The direct check adds at most one check per
# table, and the initial prune the same sum once per component.

"""
Use when a call may stop at a search or size limit: catch this error, or retry
with the keyword it names set higher; it never carries a partial result.

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
`forbids` call by `violates`, `violated_rules`, the direct check that every
`completable` question and `explain_partial` makes, and forward-checking
prunes. A check of a tabulated table is a bit test and a check of a lazy one
a lookup in the operation's memo, evaluating the predicate on a miss, so
`evaluations` bounds the predicate calls from above. `memo_hits` counts the
questions answered with no search after the direct check found nothing:
every constrained component left to solve was in its cache (a cached
infeasible one settles the question), or none was left.
"""
mutable struct SearchStats
    queries::Int      # `completable` questions asked, cached or not
    memo_hits::Int    # questions answered from the component caches, with no search
    last_nodes::Int   # nodes spent by the most recent question
    total_nodes::Int  # nodes spent by every question
    evaluations::Int  # rule checks (`forbids` calls) by every question and check
end

SearchStats() = SearchStats(0, 0, 0, 0, 0)


"""
    RuleMemo(n)

One operation's verdicts for one lazy table whose scope has `n` parameters
(contract §3.5, §12.19): `verdicts` maps the scope's value indices, in scope
order, to `true` when the rule forbids them. `key` is where `forbids(f, k,
partial)` gathers those indices to look them up, so a check that finds its
verdict allocates nothing; a verdict is stored under a copy of `key`. One key
type serves every scope, however long, so the check has no dynamic dispatch,
and `length(verdicts)` counts the tuples evaluated through the memo.
"""
struct RuleMemo
    verdicts::Dict{Vector{Int}, Bool}
    key::Vector{Int}
end

RuleMemo(n::Int) = RuleMemo(Dict{Vector{Int}, Bool}(), zeros(Int, n))


# Backtracking state, one per `Feasibility`, reused by every question that
# searches. `work` is the witness under construction: a component's tables
# read only that component's parameters, so components share it without
# interference. `alive[p][k]` says whether `candidates[p][k]` survives forward
# checking, `live[p]` counts the survivors, and `trail` records removals so a
# backtrack can undo them. `limit` and `nodes` are the current question's
# budget and spending.
mutable struct _Search
    const work::Vector{Int}
    const alive::Vector{Vector{Bool}}
    const live::Vector{Int}
    const trail::Vector{Tuple{Int, Int}}
    limit::Int
    nodes::Int
end

# A map into value indices from another numbering, the request's engine
# positions (`_mapped_completable`), checked against the candidates once.
# `map` is the map the table was made from, `nothing` before the first
# mapped question. For parameter `i` and position `k` of `map[i]`,
# `values[first[i] + k + 1]` is `map[i][k]` when that is one of `i`'s
# candidates and -1 when it is not; `k = 0`, unset, reads 0. A deletion
# trial shares its parent's: it has the same candidates.
mutable struct _Mapped
    map::Union{Nothing, Vector{Vector{Int}}}
    const first::Vector{Int}
    const values::Vector{Int}
end

_Mapped() = _Mapped(nothing, Int[], Int[])

# The answers of the all-unset sub-assignments, one per `Feasibility`
# (review p5-perf 1 and 2; plan §12.3 item 8). `cached` counts the
# constrained components whose all-unset sub-assignment is cached feasible,
# and `witness` holds their witness values beside each free parameter's
# first candidate. Once every constrained component's is (`cached ==
# length(f.constrained)`), a question starts from `witness` and looks up
# only the components that hold an assigned parameter, since each of the
# others would find its all-unset entry.
mutable struct _Unset
    cached::Int
    const witness::Vector{Int}
end


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

The caches are kept by component (plan §5.6; IPOG-C's constraint groups and
solving history, Yu et al. 2013). `witness_cache[c]` maps component `c`'s
sub-assignment, the assignment's values at `components[c]` in that order, to
the component's witness values in the same order, or to `nothing` when the
component is proven to have no valid completion. Nothing is cached for a whole
assignment: a question's answer is assembled from its components', so a
question whose assigned parameters lie outside every table's scope stores
nothing once its constrained components' sub-assignments are cached, and only
a component that spans every parameter has full-width keys: a whole-case
table's, or one that scoped rules link through every parameter (a chain of
pair rules, the equality ladder, a model whose rules connect all its
parameters). An unconstrained component's cache is never written: all of
them share one empty `Dict`.

A question visits only the constrained components (`constrained`, in
order), and its witness is the assignment merged with `template`, each free
parameter's first candidate (0 at a constrained component's parameters,
which the caches or the search fill; empty when no parameter is free, and
the assignment is copied), without a branch per parameter (review p5-perf
1). Once every constrained component's all-unset sub-assignment is cached
feasible (`unset`), the witness starts from those components' witnesses
instead, and only the components that hold an assigned parameter are
looked up, since each of the others would find its all-unset entry (plan
§12.3 item 8). So a question the caches answer costs a pass over the
assignment, the direct check, a check of each constrained component for an
assigned parameter, and a lookup per component the question partly assigns,
not one per component: a component it assigns fully isn't looked up, since
the direct check decided it (`_look_up!`). Before every all-unset answer is
cached, it costs the pass, the direct check, and a lookup per constrained
component it doesn't assign fully.

Scratch, reused by every question so that a cache hit allocates nothing:
`key` holds the question (`_checked_key`, or `_mapped_key!` for a row in a
request's engine positions), `subkeys[c]` component `c`'s sub-assignment
for a lookup, `pending` the components left to search, and `search` the
backtracking state, whose `work` vector holds a feasible answer's witness
(`_witness`); a caller that keeps a witness copies it. `mapped` is the
table through which a request's rows are converted and checked
(`_mapped_completable`). So even a question answered from the caches writes
to the object: a `Feasibility` is not safe to share between tasks or
threads. The package never shares one: each is built inside one call, in a
`Request`, a `FeasibilityContext` or a deletion trial, and never on a
`TestSpace`.

Fields: `candidates`, `tables`, `limit`, the component structure
(`components`, `component_of`, `component_tables`, `param_tables`,
`constrained`, `template`), `witness_cache`, `rule_memo`, `stats`, the
scratch `key`, `subkeys`, `pending` and `search`, `mapped`, and `unset`, the
all-unset sub-assignments' witnesses.

The lazy-rule memo (contract §3.5, §12.19). `rule_memo[k]` is `nothing` for
a tabulated table and, for a lazy one, a `RuleMemo` from the scope's value
indices to the rule's verdict. Every rule check made through this object
(`violates`, `violated_rules`, the searches, and a request's final
validation) goes through `forbids(f, k, partial)`, which evaluates a lazy
predicate at most once per tuple. A verdict depends on the table alone, not
on the rule set, so the `Feasibility` objects of one operation may share the
memos: pass `memos`, aligned with `tables`, to reuse them (a deletion trial
does, and so does each row kind of a `FeasibilityContext`). Otherwise each
lazy table gets a fresh, empty memo. The memo lives as long as the operation
that holds this object and never on the `TestSpace`.
"""
struct Feasibility
    candidates::Vector{Vector{Int}}
    tables::Vector{RuleTable}
    limit::Int
    components::Vector{Vector{Int}}
    component_of::Vector{Int}
    component_tables::Vector{Vector{Int}}
    param_tables::Vector{Vector{Int}}
    constrained::Vector{Int}           # the components with a table, in order
    template::Vector{Int}              # a free parameter's first candidate, 0 elsewhere; empty if none is free
    witness_cache::Vector{Dict{Vector{Int}, Union{Nothing, Vector{Int}}}}
    rule_memo::Vector{Union{Nothing, RuleMemo}}
    stats::SearchStats
    key::Vector{Int}
    subkeys::Vector{Vector{Int}}
    pending::Vector{Int}
    search::_Search
    mapped::_Mapped
    unset::_Unset
end

"An empty verdict memo for a lazy table, `nothing` for a tabulated one."
_rule_memo(table::RuleTable) = table.lazy === nothing ? nothing : RuleMemo(length(table.scope))

"""
    rule_memos(tables) -> Vector{Union{Nothing, RuleMemo}}

One fresh verdict memo per table (`nothing` for a tabulated table), to pass
as `memos` to every `Feasibility` of one operation over (subsets of) these
tables.
"""
rule_memos(tables::AbstractVector) = Union{Nothing, RuleMemo}[_rule_memo(t) for t in tables]

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
            memos[k] isa RuleMemo && length(memos[k].key) == length(t.scope) && t.lazy !== nothing && continue
            throw(ArgumentError("memos[$k] does not fit table $k"))
        end
    end
    return _Feasibility(cands, rules, Int(limit), collect(Union{Nothing, RuleMemo}, memos), nothing)
end

"""
    _Feasibility(cands, rules, limit, memos, parent) -> Feasibility

The rest of `Feasibility`'s construction, from validated parts it keeps as
given: the candidates, the rule tables and the memos aligned with them. A
deletion trial (`_deletion_search`) builds its search here from its
`parent`'s: the same candidates, which never change, and a subset of the
parent's tables and memos, so nothing needs checking again (review p5-perf
3). Its components are those of its own rules, as `Feasibility` would find
them; a parameter alone in its component in both reuses the parent's vector
for it, which nothing changes, and it shares the parent's table of a
request's map (`_Mapped`), which depends on the candidates alone. Otherwise
`parent` is `nothing`.
"""
function _Feasibility(cands::Vector{Vector{Int}}, rules::Vector{RuleTable}, limit::Int,
                      memos::Vector{Union{Nothing, RuleMemo}}, parent::Union{Nothing, Feasibility})
    n = length(cands)
    components, component_of = _connected_components(n, rules, parent)
    # A parameter in no scope, and a component without a table, share one
    # empty list of tables, never written.
    none = Int[]
    component_tables = fill(none, length(components))
    param_tables = fill(none, n)
    for (k, t) in enumerate(rules)
        isempty(t.scope) && continue
        c = component_of[first(t.scope)]
        component_tables[c] === none && (component_tables[c] = Int[])
        push!(component_tables[c], k)
        for p in t.scope
            param_tables[p] === none && (param_tables[p] = Int[])
            push!(param_tables[p], k)
        end
    end
    # Only constrained components are looked up and searched; the others
    # share one empty cache, sub-assignment and survivor list, never written.
    constrained = [!isempty(ts) for ts in component_tables]
    unwritten = Dict{Vector{Int}, Union{Nothing, Vector{Int}}}()
    caches = [constrained[c] ? Dict{Vector{Int}, Union{Nothing, Vector{Int}}}() : unwritten
              for c in eachindex(components)]
    no_values, no_survivors = Int[], Bool[]
    subkeys = [constrained[c] ? zeros(Int, length(components[c])) : no_values for c in eachindex(components)]
    alive = [constrained[component_of[p]] ? Vector{Bool}(undef, length(cands[p])) : no_survivors for p in 1:n]
    search = _Search(zeros(Int, n), alive, zeros(Int, n), Tuple{Int, Int}[], Int(limit), 0)
    firsts = [constrained[component_of[p]] ? 0 : cands[p][1] for p in 1:n]
    template = all(constrained) ? Int[] : firsts
    mapped = parent === nothing ? _Mapped() : parent.mapped   # the same candidates
    return Feasibility(cands, rules, limit, components, component_of,
        component_tables, param_tables, findall(constrained), template, caches,
        memos, SearchStats(), zeros(Int, n), subkeys, Int[], search, mapped, _Unset(0, copy(firsts)))
end

"""
Union-find over table scopes. Components ordered by smallest member, members
ascending. A component of one parameter reuses `shared`'s vector for it when
that is a component of one parameter too (a deletion trial's parent's).
"""
function _connected_components(n::Int, tables::Vector{RuleTable}, shared::Union{Nothing, Feasibility} = nothing)
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
    members = zeros(Int, n)   # the size of the component whose root is p
    for p in 1:n
        members[root(p)] += 1
    end
    components = Vector{Int}[]
    label = zeros(Int, n)
    component_of = zeros(Int, n)
    for p in 1:n
        r = root(p)
        if label[r] == 0
            if members[r] == 1 && shared !== nothing && length(shared.components[shared.component_of[p]]) == 1
                push!(components, shared.components[shared.component_of[p]])
                label[r] = length(components)
                component_of[p] = label[r]
                continue
            end
            push!(components, sizehint!(Int[], members[r]))
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

# Production reads `f.components` directly; this stays as a convenience for the tests.
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
must be assigned), through the operation's memo: a tabulated table is a bit
test, and a lazy table's predicate is evaluated at most once per tuple of
scoped value indices, then read from `f.rule_memo[k]` (contract §12.19). An
evaluation that throws stores nothing. A check that finds its verdict in the
memo allocates nothing; a miss evaluates the rule, one dynamic call, and
stores a copy of the key. Callers count the check in `f.stats.evaluations`.
"""
function forbids(f::Feasibility, k::Int, partial::AbstractVector{<:Integer})
    table = f.tables[k]
    table.lazy === nothing && return _forbidden_bit(table, partial)
    memo = f.rule_memo[k]::RuleMemo
    key = memo.key
    for (j, p) in enumerate(table.scope)
        key[j] = partial[p]
    end
    verdict = get(memo.verdicts, key, nothing)
    verdict === nothing || return verdict
    verdict = table.lazy(key)::Bool
    memo.verdicts[copy(key)] = verdict
    return verdict
end

"""
    memo_size(f::Feasibility) -> Int

The number of lazy-rule verdicts memoized in `f.rule_memo`, summed over its
tables: `0` when every table is tabulated. Memos shared with other
`Feasibility` objects of the same operation (see `memos`) are counted as
they stand. The answer caches are not counted; `cache_entries` counts them.
Not exported; the benchmarks and tests read it.
"""
memo_size(f::Feasibility) = sum((length(m.verdicts) for m in f.rule_memo if m !== nothing); init = 0)

"""
    cache_entries(f::Feasibility) -> Int

The answers `f` keeps: the entries of its component caches (`witness_cache`),
one per sub-assignment of a constrained component that a search resolved.
Not exported; the benchmarks and tests read it.
"""
cache_entries(f::Feasibility) = sum(length, f.witness_cache; init = 0)

"Whether component `c` has a table, so that it must be solved (§3.4)."
_constrained(f::Feasibility, c::Int) = !isempty(f.component_tables[c])

"""
Validate a partial assignment and copy it into `f.key`, which it returns:
the object's buffer, which the next question overwrites (see `Feasibility`).
"""
function _checked_key(f::Feasibility, partial::AbstractVector{<:Integer})
    n = length(f.candidates)
    length(partial) == n || throw(ArgumentError(
        "a partial assignment has one entry per parameter: expected $n, got $(length(partial))"))
    key = copyto!(f.key, partial)
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

Answers are cached by component: each searched component's witness, or
`nothing` when it has none, in `f.witness_cache`, keyed by that component's
sub-assignment, so a later question that shares the sub-assignment costs no
nodes, and a question whose every constrained component is cached (or fully
assigned) needs no search. The direct check runs for every question. The
witness is a function of `partial` alone: the order of earlier questions and
the size of the limit never change it (§3.8, §9.3). It is a fresh vector,
which the caller may keep.
"""
function completable(f::Feasibility, partial::AbstractVector{<:Integer}; limit::Integer = f.limit)
    limit >= 1 || throw(ArgumentError("feasibility_limit must be a positive Int, got $limit"))
    status = _completable(f, _checked_key(f, partial), Int(limit))
    return status, status === :feasible ? copy(_witness(f)) : nothing
end

"""
    dead(f::Feasibility, partial) -> Bool

The engines' predicate (plan Phase 3 step 1): `true` only when `partial`
is proven to have no valid completion, `false` only when a witness exists.
When the search reaches `f.limit` it throws `ResourceLimitError` naming
`feasibility_limit`, never guessing either way (contract §1.7, §3.6). A
question the caches answer allocates nothing. Once every constrained
component's all-unset sub-assignment is cached, it costs a pass over the
assignment, the direct check, a check of each constrained component for an
assigned parameter, and a lookup per component the question partly assigns
(one it assigns fully, the direct check decided); before that, the pass, the
direct check, and a lookup per constrained component it doesn't assign fully
(see `Feasibility`). One that searches allocates the entries it stores and,
until they reach their largest size, the growth of the object's search
buffers (the trail of pruned candidates and the list of components to
search).
"""
function dead(f::Feasibility, partial::AbstractVector{<:Integer})
    key = _checked_key(f, partial)
    status = _completable(f, key, f.limit)
    status === :unknown && throw(ResourceLimitError(
        "the feasibility search for the partial assignment $key", f.limit, :feasibility_limit))
    return status === :infeasible
end

"""
    _mapped_completable(f::Feasibility, map, positions) -> Symbol

The internal question (`_completable`, at `f.limit`) for a partial row
given in another numbering: `positions[i]` is 0, unset, or a position in
`map[i]`, which holds the value index of parameter `i` there. A request asks
this way with its engine positions and its `candidates` (`dead(request,
partial)`). `_mapped_key!` writes the value indices into the object's key
and checks them as `_checked_key` checks an assignment, so the request
neither touches the key nor relies on its rows fitting the search, and a
question the caches answer allocates nothing.
"""
function _mapped_completable(f::Feasibility, map::Vector{Vector{Int}}, positions::AbstractVector{<:Integer})
    return _completable(f, _mapped_key!(f, map, positions), f.limit)
end

"""
`positions` through `map` (see `_mapped_completable`), checked and written
into `f.key`, which it returns. The checks are `_checked_key`'s: the row has
one entry per parameter, and each nonzero position is within its
parameter's map and maps to one of `f.candidates`. The value indices come
from `f.mapped`, the table of `map` made the first time it is given
(`_map!`), which says for each position whether its value index is a
candidate. So the check reads one entry a parameter without a branch (an
unset parameter reads its 0), and costs less than converting the row alone
did, whose branch on an unset entry half-assigned rows mispredict (the
maintainer's review, R2).

The table is kept by the map's identity (`mapped.map === map`), so pass the
same map object every time: another object, even an equal one, rebuilds the
table (a caller that alternated two would rebuild it at every question), and
a map changed in place after it was given is used stale, without an error.
A request's `candidates` is one object for the request's life and never
changes (`Request`).
"""
function _mapped_key!(f::Feasibility, map::Vector{Vector{Int}}, positions::AbstractVector{<:Integer})
    n = length(f.candidates)
    Base.require_one_based_indexing(positions)
    length(positions) == n || _mapped_error(f, map, positions)
    mapped = f.mapped
    mapped.map === map || _map!(mapped, f, map)
    first, values, key = mapped.first, mapped.values, f.key
    valid = true
    @inbounds for i in 1:n
        k = Int(positions[i])
        start = first[i]
        inside = k % UInt < (first[i + 1] - start) % UInt   # 0 ≤ k ≤ length(map[i])
        v = values[ifelse(inside, start + k + 1, 1)]
        valid &= inside & (v >= 0)
        key[i] = v
    end
    valid || _mapped_error(f, map, positions)
    return key
end

"The table of `map` for `f`'s candidates, made in `mapped` (see `_Mapped`)."
function _map!(mapped::_Mapped, f::Feasibility, map::Vector{Vector{Int}})
    n = length(f.candidates)
    length(map) == n || throw(ArgumentError(
        "a map has one list of value indices per parameter: expected $n, got $(length(map))"))
    mapped.map = nothing   # until the table is whole
    first, values = empty!(mapped.first), empty!(mapped.values)
    push!(first, 0)
    for i in 1:n
        push!(values, 0)
        for v in map[i]
            push!(values, v in f.candidates[i] ? v : -1)
        end
        push!(first, length(values))
    end
    mapped.map = map
    return mapped
end

"The error for a row `_mapped_key!` rejects: the first entry that fails its check."
@noinline function _mapped_error(f::Feasibility, map::Vector{Vector{Int}}, positions::AbstractVector{<:Integer})
    n = length(f.candidates)
    length(positions) == n || throw(ArgumentError(
        "a partial row has one entry per parameter: expected $n, got $(length(positions))"))
    for (i, k) in enumerate(positions)
        k == 0 && continue
        1 <= k <= length(map[i]) || throw(ArgumentError(
            "parameter $i is at position $k, outside its $(length(map[i])) mapped value indices"))
        v = map[i][k]
        v in f.candidates[i] || throw(ArgumentError(
            "parameter $i is at position $k, value index $v, which is not among its candidates $(f.candidates[i])"))
    end
    error("internal error: the partial row $positions was rejected with no entry outside its candidates")
end

# The internal question: `:feasible`, `:infeasible` or `:unknown`. `key` is
# validated, and may be `f.key`; it is only read. The witness of a feasible
# answer is `_witness(f)`, the object's scratch, which the next question
# overwrites: a caller that keeps it copies it. (The status alone is
# returned because a tuple of a status and a witness or `nothing` is a union
# of tuple types, which a call returns boxed: 32 bytes a question.)
#
# Nothing is cached for the whole assignment (plan §5.6): the direct check
# runs every time, then each constrained component that is not fully
# assigned is looked up by its sub-assignment, and only the components not
# found are searched. Once every constrained component's all-unset
# sub-assignment is cached feasible (`f.unset`), a component that holds no
# assigned parameter would find that entry, so it isn't looked up: its
# witness values come from `f.unset.witness`, and only the components the
# question assigns are looked up (plan §12.3 item 8). That changes no
# answer, witness, node count or counter: a skipped component would find a
# feasible entry, so the same components are searched, in the same order. A
# question asked again therefore finds every component it needs in the
# caches and costs no nodes, as a whole-assignment memo's hit did, and its
# answer and witness are those it had the first time.
function _completable(f::Feasibility, key::Vector{Int}, limit::Int)
    stats = f.stats
    stats.queries += 1
    stats.last_nodes = 0
    _violates(f, key) && return :infeasible
    search = f.search
    witness = search.work
    pending = empty!(f.pending)
    unset = f.unset
    # Cached components first: they cost no nodes, and a cached infeasible
    # component settles the question at once.
    if unset.cached == length(f.constrained)
        # Every constrained component's all-unset sub-assignment is cached:
        # start from their witnesses, and look up only the components that
        # hold an assigned parameter. (`ifelse`, not a branch: half-assigned
        # rows would mispredict it.)
        _merge!(witness, key, unset.witness)
        for c in f.constrained
            params = f.components[c]
            _any_assigned(key, params) || continue
            for p in params   # its unset parameters back to 0, for the cache or the search
                @inbounds witness[p] = key[p]
            end
            _look_up!(f, c, key, witness, pending) === :infeasible || continue
            stats.memo_hits += 1
            return :infeasible
        end
    else
        # The assignment, with each free parameter's first candidate where it
        # is unset; a constrained component's unset parameters stay 0 for the
        # caches or the search to fill.
        isempty(f.template) ? copyto!(witness, key) : _merge!(witness, key, f.template)
        for c in f.constrained
            _look_up!(f, c, key, witness, pending) === :infeasible || continue
            stats.memo_hits += 1
            return :infeasible
        end
    end
    if isempty(pending)   # a query with no component left to solve searches nothing
        stats.memo_hits += 1
        return :feasible
    end
    search.limit = limit
    search.nodes = 0
    empty!(search.trail)
    status = :feasible
    for c in pending
        status = _solve_component!(search, f, c)
        status === :unknown && break   # the budget is spent; store nothing
        # `subkeys[c]` still holds the sub-assignment: no search writes it.
        f.witness_cache[c][copy(f.subkeys[c])] = status === :feasible ? witness[f.components[c]] : nothing
        if status === :feasible && all(iszero, f.subkeys[c])   # its all-unset entry, stored once
            for p in f.components[c]
                unset.witness[p] = witness[p]
            end
            unset.cached += 1
        end
        status === :infeasible && break
    end
    stats.last_nodes = search.nodes
    stats.total_nodes += search.nodes
    return status
end

"Whether some parameter of `params` is assigned in `key`."
function _any_assigned(key::Vector{Int}, params::Vector{Int})
    for p in params
        @inbounds key[p] == 0 || return true
    end
    return false
end

"`witness` gets `key`'s assigned values and `base`'s where `key` is unset, without a branch per parameter."
@inline function _merge!(witness::Vector{Int}, key::Vector{Int}, base::Vector{Int})
    @inbounds for p in eachindex(witness, key, base)
        v = key[p]
        witness[p] = ifelse(v == 0, base[p], v)
    end
    return witness
end

"""
Component `c`'s answer from its cache, for `_completable`: `:infeasible`
when the cache holds `nothing` for its sub-assignment; otherwise its witness
values are written into `witness` (`:found`), it is fully assigned, which the
direct check decided (`:found`), or it goes on `pending` (`:missing`).
"""
@inline function _look_up!(f::Feasibility, c::Int, key::Vector{Int}, witness::Vector{Int}, pending::Vector{Int})
    params = f.components[c]
    _all_assigned(key, params) && return :found  # `_violates` checked it
    cached = get(f.witness_cache[c], _subkey!(f, c, key), missing)
    cached === nothing && return :infeasible
    if cached === missing
        push!(pending, c)
        return :missing
    end
    for (k, p) in enumerate(params)
        @inbounds witness[p] = cached[k]
    end
    return :found
end

"The witness of the last question `f` answered `:feasible`: `f`'s scratch, not a copy."
_witness(f::Feasibility) = f.search.work

"Whether every parameter of `params` is assigned in `key`."
function _all_assigned(key::Vector{Int}, params::Vector{Int})
    for p in params
        key[p] == 0 && return false
    end
    return true
end

"Component `c`'s sub-assignment of `key`, gathered into `f.subkeys[c]`, which it returns."
function _subkey!(f::Feasibility, c::Int, key::Vector{Int})
    sub = f.subkeys[c]
    for (k, p) in enumerate(f.components[c])
        sub[k] = key[p]
    end
    return sub
end

function _solve_component!(s::_Search, f::Feasibility, c::Int)
    params = f.components[c]
    for p in params
        if s.work[p] == 0
            fill!(s.alive[p], true)
            s.live[p] = length(f.candidates[p])
        end
    end
    # The initial prune: tables already down to one unset parameter.
    for t in f.component_tables[c]
        y = _sole_unassigned(f.tables[t], s.work)
        y > 0 && !_prune!(s, f, t, y) && return :infeasible
    end
    return _backtrack!(s, f, params)
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
function _prune!(s::_Search, f::Feasibility, t::Int, y::Int)
    cands = f.candidates[y]
    alive = s.alive[y]
    stats = f.stats
    for k in eachindex(cands)
        alive[k] || continue
        s.work[y] = cands[k]
        stats.evaluations += 1
        if forbids(f, t, s.work)
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
function _forward_check!(s::_Search, f::Feasibility, x::Int)
    for t in f.param_tables[x]
        y = _sole_unassigned(f.tables[t], s.work)
        y > 0 && !_prune!(s, f, t, y) && return false
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

function _backtrack!(s::_Search, f::Feasibility, params::Vector{Int})
    x = 0
    fewest = typemax(Int)
    for p in params
        if s.work[p] == 0 && s.live[p] < fewest
            fewest = s.live[p]
            x = p
        end
    end
    x == 0 && return :feasible
    cands = f.candidates[x]
    alive = s.alive[x]
    for k in eachindex(cands)
        alive[k] || continue
        s.nodes >= s.limit && return :unknown
        s.nodes += 1
        s.work[x] = cands[k]
        mark = length(s.trail)
        if _forward_check!(s, f, x)
            result = _backtrack!(s, f, params)
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
  is the assignment itself, unless asked with `witness = false`.
- `:forbidden`: `rules` lists every table, in table order, whose scope is
  entirely assigned and which forbids the assignment (§1.4 *direct*).
- `:completable`: `witness` is a valid complete row extending it, unless
  asked with `witness = false`.
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
    explain_partial(f::Feasibility, partial; explanation_limit = 1_000_000, witness = true) -> IndexExplanation

Why `partial` is or is not part of a valid row, as one of the five outcomes
of contract §1.26 (see `IndexExplanation`). The direct check comes first, so a
complete or partial assignment that some fully assigned table forbids is
`:forbidden` with every such rule. A complete assignment that no table
forbids is `:allowed`. Otherwise `completable` decides between
`:completable`, `:unknown`, and `:infeasible`; only a proven infeasible
assignment gets a deletion search, whose budget is `explanation_limit`
(§3.13). Infeasibility never depends on that budget (§3.15).

With `witness = false`, an `:allowed` or `:completable` answer carries no
witness (`nothing`), so no full-width row is copied for it: classification
keeps none (`_classify_target`). Everything else is the same: the questions
asked, in the same order, the outcome, its rules, and its cost.
"""
function explain_partial(f::Feasibility, partial::AbstractVector{<:Integer};
                         explanation_limit::Integer = 1_000_000, witness::Bool = true)
    explanation_limit >= 1 || throw(ArgumentError(
        "explanation_limit must be a positive Int, got $explanation_limit"))
    key = _checked_key(f, partial)
    nodes, evaluations = f.stats.total_nodes, f.stats.evaluations
    cost(trials = (0, 0)) = (f.stats.total_nodes - nodes + trials[1],
                             f.stats.evaluations - evaluations + trials[2])
    direct = _violated_rules(f, key)
    isempty(direct) ||
        return IndexExplanation(:forbidden, direct, :not_applicable, nothing, nothing, cost()...)
    all(!=(0), key) &&
        return IndexExplanation(:allowed, Int[], :not_applicable, witness ? copy(key) : nothing, nothing, cost()...)
    status = _completable(f, key, f.limit)
    if status === :feasible
        return IndexExplanation(:completable, Int[], :not_applicable, witness ? copy(_witness(f)) : nothing,
                                nothing, cost()...)
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
        trial = _Feasibility(f.candidates, f.tables[trial_rules], f.limit, f.rule_memo[trial_rules], f)
        status = _completable(trial, key, min(f.limit, remaining))
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

- `:required`: feasible; `witness` is a valid row containing it, or
  `nothing` when the explanation was asked with `witness = false` (as
  classification asks, `_classify_target`).
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

"The status of each outcome of `explain_partial`: the one place a search outcome becomes a status."
const _STATUS_OF_OUTCOME = (allowed = :required, completable = :required,
    forbidden = :forbidden, infeasible = :implied, unknown = :unknown)

IndexClassification(e::IndexExplanation) = IndexClassification(_STATUS_OF_OUTCOME[e.outcome],
    e.rules, e.minimal, e.witness, e.limit, e.nodes, e.evaluations)

"""
    _status(f::Feasibility, partial) -> Symbol

The status `IndexClassification` gives `partial` (`:required`, `:forbidden`,
`:implied` or `:unknown`), without its rules, witness or effort: for
counting, which keeps none of them. It reaches the outcome as
`explain_partial` does, the direct check and then `completable`, and skips
the deletion search. That search's trials are fresh `Feasibility` objects
that share only the rule memo, so skipping it leaves `f`'s answer caches as
`explain_partial` would, and every later answer the same.
"""
function _status(f::Feasibility, partial::AbstractVector{<:Integer})
    key = _checked_key(f, partial)
    _violates(f, key) && return _STATUS_OF_OUTCOME.forbidden
    all(!=(0), key) && return _STATUS_OF_OUTCOME.allowed
    status = _completable(f, key, f.limit)
    status === :feasible && return _STATUS_OF_OUTCOME.completable
    status === :unknown && return _STATUS_OF_OUTCOME.unknown
    return _STATUS_OF_OUTCOME.infeasible
end

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
