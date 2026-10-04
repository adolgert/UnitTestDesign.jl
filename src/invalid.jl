# Negative generation (plan Phase 6 step 1; contract §5, §6, §7.9, §10).
#
# The covering design is built over ordinary values only (`generate` in
# engines.jl, `cover_ordinary`). Then every negative target of §6 is
# classified by the negative-row search of its invalid value (`feasibility_for`
# with `p = v`: candidates `[v]` at `p`, ordinary values elsewhere, the rules
# whose scope omits `p`, §5.5, §6.2), in target order, by the walk `coverage`
# makes (`classify_negative_targets`). Then, for each invalid value `v` of
# each parameter `p`, in parameter order and then domain order, the same
# engine covers the required targets at `(p, v)` on a sub-request over the
# other parameters (`NegativeProjection`, `_negative_request`). No active rule
# reads `p`, so a negative row at `(p, v)` is `p = v` beside a valid row of the
# sub-space, and it holds a target at `(p, v)` exactly when that row holds the
# target without `p`: those are the sub-request's required targets, and
# `parent_row` puts `p = v` back into each row. At strength 1 with no group
# containing `p` there is no sub-request: the one target `(p = v)` takes one
# witness row (§6.4), never a strength-0 public call. An engine whose `fit`
# refuses a sub-request hands it to its fallback, IPOG (`_engine_for`).
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
at `(p, v)` other than `(p = v)` alone, without `p`, in the same order (a
test pins this): the engine is given the required ones, and reads the
strength and the groups for its parameter order. `seeds` are its
must-include rows, engine positions over the other parameters. Nothing is
validated or tabulated again, and no predicate is called.

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
    _NegativeTargets(request)

Negative generation's `_Record` for the walk that `coverage` makes
(`_walk_support!`): each negative target is classified by the negative-row
search of its invalid value (`feasibility_for`, §6.2) through
`_classify_target`, and kept in `required`, in engine positions, or in
`excluded`, as an `Excluded` record with the rules in the space's numbering
(§1.4, §6.7). An unknown answer throws `ResourceLimitError` (§3.6, §6.7).
"""
struct _NegativeTargets <: _Record
    request::Request
    required::Vector{Vector{Int}}
    excluded::Vector{Excluded}
end

function _classify!(record::_NegativeTargets, context::FeasibilityContext, support::Vector{Int}, t::Vector{Int})
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

Classify every negative target of `request` (§6.1–§6.5), in target order
(§9.7), by the walk that `coverage` makes over its supports with no rows
(`_walk_support!`): `required`, the targets some valid negative row holds,
in engine positions, and `excluded`, the `Excluded` records of the rest,
so that a result's negative exclusions list as
`coverage(cases).negative.excluded` does. An unknown answer throws
`ResourceLimitError` (§3.6, §6.7). The negative counterpart of
`classify_targets`.
"""
function classify_negative_targets(request::Request)
    record = _NegativeTargets(request, Vector{Int}[], Excluded[])
    for support in _supports(request.groups)
        _walk_support!(record, request.context, support, :negative, nothing)
    end
    return record.required, record.excluded
end

"""
    cover_negative(engine, request, columns) -> (; seeds, rows, required, excluded)

Negative generation (contract §6.7). First classify every negative target
(`classify_negative_targets`), stopping with `ResourceLimitError` on any
unknown. Then, for each invalid value `v` of each parameter `p`, in
parameter order and then domain order, cover the required targets at
`(p, v)` with `engine` through `_negative_request`, whose must-include rows
are the negative must-include rows at `(p, v)` (the request's must-include
`columns` that hold an invalid value). An engine whose `fit` refuses that
sub-request, which may have base strength 0, hands it to its fallback
(`_engine_for`, plan §4.2). At strength 1 the target `(p = v)` alone, when
it is required, takes one witness row unless a must-include or generated
row already holds `p = v` (§6.4).

Returns, in engine positions: `seeds`, each negative must-include column's
completed row, by column; `rows`, the generated negative rows, in `(p, v)`
order; `required`, every required negative target, and `excluded`, the
`Excluded` negative targets, each in target order, as `coverage` lists them.
The caller validates the rows (`validate_design`).
"""
function cover_negative(engine, request::Request, columns::Vector{Int})
    space = request.space
    n = length(space.names)
    must = request.must_include
    required, excluded = classify_negative_targets(request)
    # The required targets at each (p, v), in target order. A negative target
    # holds one invalid position, v at p.
    targets = Dict{Tuple{Int, Int}, Vector{Vector{Int}}}()
    for t in required
        p = findfirst(q -> t[q] > request.arity[q], eachindex(t))
        push!(get!(() -> Vector{Int}[], targets, (p, t[p])), t)
    end
    seeds = Dict{Int, Vector{Int}}()
    rows = Vector{Int}[]
    for p in 1:n
        positions = (request.arity[p] + 1):length(request.candidates[p])   # p's invalid values
        isempty(positions) && continue
        # One projection serves every invalid value of p. Without a sub-request
        # (strength 1, no group holding p), the one target at (p, v) is (p = v).
        pr = request.strength > 1 || any(g -> p in g.first, request.groups[2:end]) ?
             NegativeProjection(space, p) : nothing
        for position in positions
            at = [j for j in columns if must[p, j] == position]
            here = get(targets, (p, position), Vector{Int}[])
            added = 0
            if pr !== nothing
                sub = _negative_request(request, pr, must[pr.kept, at])
                # Every target here but (p = v) alone is p = v beside a target of the sub-request.
                sub_required = [t[pr.kept] for t in here if count(!=(0), t) > 1]
                matrix = try
                    # An engine that can't cover the sub-request hands it to its fallback (plan §4.2).
                    cover_ordinary(_engine_for(engine, sub), sub, RequiredTargets(sub, sub_required))
                catch err
                    err isa ResourceLimitError || rethrow()
                    value = space.values[p][request.candidates[p][position]]
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
                for j in at
                    row = must[:, j]
                    seeds[j] = any(==(0), row) ? witness(request, row) : row
                end
            end
            alone = findfirst(t -> count(!=(0), t) == 1, here)   # (p = v), a target at strength 1
            if alone !== nothing && isempty(at) && added == 0
                push!(rows, witness(request, here[alone]))
            end
        end
    end
    return (; seeds, rows, required, excluded)
end
