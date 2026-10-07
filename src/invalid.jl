# Negative generation (plan Phase 6 step 1; contract §5, §6, §7.9, §10).
#
# The covering design is built over ordinary values only (`generate` in
# engines.jl, `_run`). Then every negative target of §6 is
# classified by the negative-row search of its invalid value (`feasibility_for`
# with `p = v`: candidates `[v]` at `p`, ordinary values elsewhere, the rules
# whose scope omits `p`, §5.5, §6.2), in target order, by the walk `coverage`
# makes (`_classify_negative`), keeping the excluded ones and their ids and
# counting the rest (`_NegativeTargets`), as the ordinary targets are kept.
# Then, for each invalid value `v` of each parameter `p`, in parameter order
# and then domain order, the same engine covers the required targets at
# `(p, v)` on a sub-request over the other parameters (`NegativeProjection`,
# `_negative_request`), the excluded ones found on its own layout from their
# targets (`_sub_excluded`). No active rule
# reads `p`, so a negative row at `(p, v)` is `p = v` beside a valid row of the
# sub-space, and it holds a target at `(p, v)` exactly when that row holds the
# target without `p`: those are the sub-request's required targets, and
# `parent_row` puts `p = v` back into each row. At strength 1 with no group
# containing `p` there is no sub-request: the one target `(p = v)` takes one
# witness row (§6.4), never a strength-0 public call. An engine whose plan's
# fit refuses a sub-request hands it to its fallback (`_prepare_for`,
# `_fallback`): IPOG, or for `Compact` its inner engine's fallback reduced,
# `Compact(IPOG())`. The result's record keeps, for each invalid value, the
# stage that covered its sub-request.
#
# Negative must-include rows count toward the negative targets they hold
# (§10.6): those at `(p, v)` are the sub-request's must-include rows, so the
# engine completes a partial one (§7.9) and covers only what they leave.


"""
    NegativeProjection(space, p)

The space as the negative rows with their invalid value at parameter `p`
see it (see the file header), with the maps back to `space`. `subspace` has
the parameters other than `p`, in order, and the rules whose scope omits `p`
(`active_rules`, §5.5), in order. Its parameter `j` is `space`'s parameter
`kept[j]`, and `space`'s parameter `q` is its parameter `renumber[q]` (`0`
for `p`). Its rule `i` is `space`'s rule `rules[i]` (`parent_rule`). It
reuses `space`'s names, domains, value indices, `Constraint`s and rule
tables, each table's scope renumbered; nothing is validated, tabulated or
evaluated again. A kept parameter has the same ordinary values in the same
order, so a sub-request's engine positions are `space`'s, and `parent_row`
puts the invalid position back at `p`.

Building one checks that each projected scope is its rule's scope mapped
elementwise, in the order the rule gave it. That order is the order of the
predicate's arguments and of a tabulated rule's forbidden tuples
(`_tabulate`), so a scope is never sorted. There is no check for a
whole-case rule: its scope is every parameter, `p` included, so
`active_rules` never keeps one; if it did, its projected scope would hold
`0`, which fails the scope check here and `Feasibility`'s own.

A rule number that leaves a sub-request is the sub-space's, and goes
through `parent_rule` before a message or record names it. None leaves
today: negative targets are classified on the space's own searches
(`classify_negative_targets`), a sub-request's `ResourceLimitError` names
values, not rules, and an error from a lazy rule's predicate names the rule
as the space did when it tabulated it (`_LazyRule`).
"""
struct NegativeProjection
    space::TestSpace
    p::Int
    kept::Vector{Int}
    renumber::Vector{Int}
    rules::Vector{Int}
    subspace::TestSpace
end

function NegativeProjection(space::TestSpace, p::Int)
    n = length(space.names)
    kept = [q for q in 1:n if q != p]
    renumber = zeros(Int, n)
    renumber[kept] = eachindex(kept)
    rules = active_rules(space, p)
    tables = RuleTable[RuleTable(renumber[t.scope], t.low, t.radix, t.forbidden, t.lazy) for t in space.tables[rules]]
    for (i, t) in enumerate(tables)
        scope = space.tables[rules[i]].scope
        [get(kept, j, 0) for j in t.scope] == scope || error(
            "internal error: rule $(rules[i]) reads parameters $scope, which became $(t.scope) without " *
            "parameter $p; a projected scope keeps the rule's parameters in the rule's order")
    end
    subspace = TestSpace(Val(:parts), (names = space.names[kept], values = space.values[kept],
        constraints = space.constraints[rules], tables = tables, tabulation_limit = space.tabulation_limit,
        ordinary = space.ordinary[kept], invalid = space.invalid[kept], lookup = space.lookup[kept]))
    return NegativeProjection(space, p, kept, renumber, rules, subspace)
end

"The space's number for rule `i` of the projection's sub-space."
parent_rule(pr::NegativeProjection, i::Integer) = pr.rules[i]

"`row` (engine positions over the sub-space) as a row of the space, with `position` at `p`."
function parent_row(pr::NegativeProjection, row::AbstractVector{<:Integer}, position::Int)
    out = Vector{Int}(undef, length(pr.renumber))
    out[pr.kept] = row
    out[pr.p] = position
    return out
end

"""
    _negative_request(request, projection, seeds) -> Request

The request whose covering design gives the negative rows with their invalid
value at `projection.p` (see the file header): over the projection's
sub-space, sharing the lazy-rule memos of its rules with `request` (§3.5);
at base strength `request.strength - 1`, which may be 0; with each
`stronger` group `G` that contains `p` as `G \\ {p}` at its strength less one.
So, for each invalid value `v` of `p`, its targets are the negative targets
at `(p, v)` other than `(p = v)` alone, without `p` (a test pins this): the
engine is given the required ones, and reads the strength and the groups for
its parameter order. They are the same targets but not always in the same
order: `_groups` sorts the groups again without `p`, so where one group
without `p` becomes a prefix of another (`[1, 2, 3, 4]` sorts before
`[1, 2, 4]`, but without 4 `[1, 2]` sorts before `[1, 2, 3]`), their supports
come in the other order. So `cover_negative` finds the excluded ones on the
sub-request's layout from the targets themselves (`_sub_excluded`); the
groups keep `_groups`' order, which IPOG's parameter order, and so its rows,
depend on. `seeds` are its must-include rows, engine positions over the other
parameters. Nothing is validated or tabulated again, and no predicate is
called.

It checks that `request`'s rule tables are the projection's space's, in
order, so that `request`'s `k`-th memo is that of the space's rule `k`; and
that the sub-request holds those memos themselves.
`Feasibility` checks that each memo fits its table, but two lazy rules of
the same arity could be swapped and share verdicts without a sign.
"""
function _negative_request(request::Request, pr::NegativeProjection, seeds::AbstractMatrix{<:Integer})
    space, p, subspace = pr.space, pr.p, pr.subspace
    tables, memos = request.feasibility.tables, request.feasibility.rule_memo
    length(tables) == length(space.tables) && all(k -> tables[k] === space.tables[k], eachindex(tables)) ||
        error("internal error: the request's rule tables are not the projected space's, in order, so the " *
              "negative rows at $(space.names[p]) cannot share its lazy-rule memos")
    stronger = [pr.renumber[filter(!=(p), members)] => s - 1 for (members, s) in request.groups[2:end]
                if p in members]
    groups = _groups(subspace, request.strength - 1, stronger)
    feasibility = Feasibility(_candidates(subspace, 0, 0), subspace.tables;
                              limit = request.feasibility_limit, memos = memos[pr.rules])
    sub = _request(subspace, request.strength - 1, groups, Matrix{Int}(seeds), feasibility,
                   request.feasibility_limit, request.explanation_limit)
    for i in eachindex(pr.rules)
        sub.feasibility.rule_memo[i] === memos[parent_rule(pr, i)] || error(
            "internal error: the negative rows at $(space.names[p]) do not share rule " *
            "$(parent_rule(pr, i))'s lazy-rule memo with the request")
    end
    return sub
end

"""
    _NegativeIds(request)

Negative generation's `_Record` for the walk that `coverage` makes
(`_walk_support!`): each negative target is classified by the negative-row
search of its invalid value (`feasibility_for`, §6.2) through
`_classify_target`, and numbered in the walk's order. A required one is
counted; an excluded one keeps its `Excluded` record (§1.4, §6.7) and its
number, and, unless it is `(p = v)` alone, its record's position under its
invalid value (`_NegativeTargets`). The target is written in engine
positions into one reused row, so nothing is kept or made per required
target beyond its feasibility question. An unknown answer throws
`ResourceLimitError` (§3.6, §6.7).
"""
mutable struct _NegativeIds <: _Record
    const request::Request
    const target::Vector{Int}          # the target in engine positions, reused
    walked::Int                        # the targets met so far: the last one's number
    required::Int
    const excluded::Vector{Excluded}
    const ids::Vector{Int}
    const first::Vector{Int}
    const count::Vector{Int}
    const excluded_at::Vector{Vector{Int}}
    const alone::Vector{Symbol}
end

function _NegativeIds(request::Request)
    n = length(request.arity)
    first = zeros(Int, n)
    values = 0
    for p in 1:n
        first[p] = values + 1
        values += length(request.candidates[p]) - request.arity[p]
    end
    return _NegativeIds(request, zeros(Int, n), 0, 0, Excluded[], Int[], first, zeros(Int, values),
                        [Int[] for _ in 1:values], fill(:none, values))
end

function _classify!(record::_NegativeIds, context::FeasibilityContext, support::Vector{Int}, t::Vector{Int})
    request, target = record.request, record.target
    record.walked += 1
    p = 0   # the parameter that holds the invalid value
    for q in support
        target[q] = something(findfirst(==(t[q]), request.candidates[q]))
        target[q] > request.arity[q] && (p = q)
    end
    slot = record.first[p] + target[p] - request.arity[p] - 1
    alone = length(support) == 1   # (p = v) alone; any other target is its sub-request's
    alone || (record.count[slot] += 1)
    f, active = feasibility_for(context, t)
    e = _classify_target(request, f, active, target, t, "classifying the negative target")
    for q in support
        target[q] = 0
    end
    if e === nothing
        record.required += 1
        alone && (record.alone[slot] = :required)
        return :required
    end
    push!(record.excluded, e)
    push!(record.ids, record.walked)
    alone ? (record.alone[slot] = :excluded) : push!(record.excluded_at[slot], length(record.excluded))
    return e.status
end

"""
    _classify_negative(request, layout::TargetList) -> _NegativeTargets

Classify every negative target of `request` (§6.1–§6.5), in target order
(§9.7), by the walk that `coverage` makes over the supports of `layout`, the
request's `TargetList`, with no rows (`_walk_support!`), keeping what
`_NegativeTargets` describes. An unknown answer throws `ResourceLimitError`
(§3.6, §6.7). `_Classified` calls it the first time negative generation asks
(`_negative_targets!`).
"""
function _classify_negative(request::Request, layout::TargetList)
    layout.arity == request.arity || error("internal error: a TargetList of another request")
    record = _NegativeIds(request)
    for (_, support) in _each_support(layout.supports)
        _walk_support!(record, request.context, support, :negative, nothing)
    end
    return _NegativeTargets(layout, record.required, record.excluded, record.ids, record.first, record.count,
                            record.excluded_at, record.alone)
end

"""
    _sub_excluded(negative, slot, projection, layout) -> Vector{Int}

The ids, ascending, on `layout`, the `TargetList` of the negative
sub-request at `slot`'s invalid value `(p, v)`, of the negative targets at
`(p, v)` that classification excluded, other than `(p = v)` alone. Each such
target without `p` (`projection.kept`) is a target of the sub-request
(`_negative_request`), found on its layout from the parameters it sets and
their values (`_target_ids`), not from where the walk met it: the
sub-request's groups are sorted again without `p`, so its supports need not
come in the order the walk met them at `(p, v)`.
"""
function _sub_excluded(negative::_NegativeTargets, slot::Int, pr::NegativeProjection, layout::TargetList)
    at = negative.excluded_at[slot]
    isempty(at) && return Int[]
    return _target_ids(layout, (view(negative.excluded[k].target, pr.kept) for k in at), "excluded negative")
end

"""
    _NegativeList(request)

The `_Record` of `classify_negative_targets`: each negative target
classified as `_NegativeIds` classifies it, and kept in `required`, in
engine positions, or in `excluded`, as an `Excluded` record.
"""
struct _NegativeList <: _Record
    request::Request
    required::Vector{Vector{Int}}
    excluded::Vector{Excluded}
end

function _classify!(record::_NegativeList, context::FeasibilityContext, support::Vector{Int}, t::Vector{Int})
    request = record.request
    f, active = feasibility_for(context, t)
    target = _positions(request, t)
    e = _classify_target(request, f, active, target, t, "classifying the negative target")
    if e === nothing
        push!(record.required, target)
        return :required
    end
    push!(record.excluded, e)
    return e.status
end

"""
    classify_negative_targets(request) -> (required, excluded)

Every negative target of `request` classified (§6.1–§6.5), as lists, for
tests and scripts: in target order (§9.7), by the walk that `coverage` makes
over its supports with no rows (`_walk_support!`), `required`, the targets
some valid negative row holds, in engine positions, and `excluded`, the
`Excluded` records of the rest, as a result's negative exclusions list them
and as `coverage(cases).negative.excluded` does. An unknown answer throws
`ResourceLimitError` (§3.6, §6.7). The negative counterpart of
`classify_targets`. Generation lists no required target: it keeps
`_classify_negative`'s `_NegativeTargets`, from the same questions in the
same order.
"""
function classify_negative_targets(request::Request)
    record = _NegativeList(request, Vector{Int}[], Excluded[])
    for (_, support) in _each_support(_supports(request.groups))
        _walk_support!(record, request.context, support, :negative, nothing)
    end
    return record.required, record.excluded
end

"""
    cover_negative(engine, request, columns, negative = _classify_negative(request, TargetList(request)))
        -> (; seeds, rows, bound, stages)

Negative generation (contract §6.7). First classify every negative target
(`_classify_negative`), stopping with `ResourceLimitError` on any unknown:
`negative`, which `generate` makes once for the request and shares with
every engine that covers it (`_Classified`). Then, for each invalid value `v`
of each parameter `p`, in parameter order and then domain order, cover the
required targets at `(p, v)` with `engine` through `_negative_request`, whose
must-include rows are the negative must-include rows at `(p, v)` (the
request's must-include `columns` that hold an invalid value), and whose
targets are those at `(p, v)` without `p`, required or excluded as they are
here: `RequiredTargets` on the sub-request's `TargetList`, checked to hold
as many targets as the walk met at `(p, v)`, from the ids there of the
excluded ones, found from their targets (`_sub_excluded`). The
sub-request's plan is prepared once: `engine`'s, or its fallback's where
that refuses the sub-request, which may have base strength 0
(`_prepare_for`, plan §4.2). At strength 1 the target `(p = v)` alone, when
it is required, takes one witness row unless a must-include or generated
row already holds `p = v` (§6.4).

Returns, in engine positions: `seeds`, each negative must-include column's
completed row, by column; `rows`, the generated negative rows, in `(p, v)`
order; `bound`, a number of negative rows that no design can have fewer of
(plan §4.1); and `stages`, one per invalid value in the same order, for the
result's record (`negative`): `(parameter, value, rows, stage)`, the
parameter's name, the invalid value as its `repr`, the design's rows that
hold it (its must-include rows, generated rows and witness row), and the
sub-request's stage (`_run`: the engine that covered it, its rows and what it
found), or `nothing` without a sub-request. A negative row holds one invalid value (§5.7) and covers only
negative targets (§5.9), so the rows at different `(p, v)` are different
rows, and the bound is the sum over `(p, v)` of the sub-request's
`_ordinary_bound`, its must-include rows being the negative ones at
`(p, v)`, and at least one row when the target `(p = v)` alone is required.
The caller validates the rows against `negative` (`validate_design`).
"""
function cover_negative(engine, request::Request, columns::Vector{Int},
                        negative::_NegativeTargets = _classify_negative(request, TargetList(request)))
    space = request.space
    n = length(space.names)
    must = request.must_include
    seeds = Dict{Int, Vector{Int}}()
    rows = Vector{Int}[]
    stages = NamedTuple[]
    bound = 0
    for p in 1:n
        positions = (request.arity[p] + 1):length(request.candidates[p])   # p's invalid values
        isempty(positions) && continue
        # One projection serves every invalid value of p. Without a sub-request
        # (strength 1, no group holding p), the one target at (p, v) is (p = v).
        pr = request.strength > 1 || any(g -> p in g.first, request.groups[2:end]) ?
             NegativeProjection(space, p) : nothing
        for position in positions
            slot = _slot(negative, request, p, position)
            at = [j for j in columns if must[p, j] == position]
            alone = negative.alone[slot] === :required   # (p = v), a target at strength 1
            added = 0
            stage = nothing
            value = space.values[p][request.candidates[p][position]]
            if pr !== nothing
                sub = _negative_request(request, pr, must[pr.kept, at])
                # Every target here but (p = v) alone is p = v beside a target
                # of the sub-request, required or excluded as it is here; not
                # always in the same order (`_negative_request`), so the
                # excluded ones are found on its layout from their targets.
                layout = TargetList(sub)
                length(layout) == negative.count[slot] || error("internal error: the negative targets at " *
                    "$(space.names[p]) = $(repr(value)) are not its sub-request's $(length(layout)) targets")
                sub_targets = RequiredTargets(layout, _sub_excluded(negative, slot, pr, layout))
                bound += max(_ordinary_bound(sub, sub_targets).rows, alone ? 1 : 0)
                matrix, stage = try
                    # An engine that can't cover the sub-request hands it to its fallback (plan §4.2).
                    _run(_prepare_for(engine, Profile(sub)), sub, sub_targets)
                catch err
                    err isa ResourceLimitError || rethrow()
                    throw(ResourceLimitError("generating the negative rows with $(space.names[p]) = " *
                                             "$(repr(value)): $(err.what)", err.limit, err.keyword))
                end
                for (k, j) in enumerate(at)
                    seeds[j] = parent_row(pr, matrix[:, k], position)
                end
                for k in (length(at) + 1):size(matrix, 2)
                    push!(rows, parent_row(pr, matrix[:, k], position))
                    added += 1
                end
            else
                negative.count[slot] == 0 || error("internal error: negative targets at " *
                                                   "$(space.names[p]) = $(repr(value)) without a sub-request")
                bound += max(length(at), alone ? 1 : 0)
                for j in at
                    row = must[:, j]
                    seeds[j] = any(==(0), row) ? witness(request, row) : row
                end
            end
            witnessed = alone && isempty(at) && added == 0
            if witnessed
                row = zeros(Int, n)
                row[p] = position
                push!(rows, witness(request, row))
            end
            push!(stages, (parameter = space.names[p], value = repr(value), rows = length(at) + added + witnessed,
                           stage = stage))
        end
    end
    return (; seeds, rows, bound, stages)
end
