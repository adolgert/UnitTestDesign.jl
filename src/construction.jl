# The `Construction` engine (plan §5.4, Phase 2): a covering engine whose
# designs are the catalog's algebraic arrays (construction_catalog.jl), for a
# space of an exact shape, and a seed under a few rules. It is exported since
# Phase 3 (plan §3, §6.1), `Auto` runs it where it fits, and `_engine_registry`
# lists it, so the oracle loops check it.
#
# How it enters the pipeline (plan §4.1, §5.4):
#
# - Exact shape. Every parameter has the same number of values, or there are
#   at most t + 1 parameters (the zero-sum array, exact for any value counts),
#   with no rules, no must-include rows and no `stronger` groups: the array
#   is the design.
# - Seeded. The same shapes with rules, must-include rows or `stronger`
#   groups: the caller's must-include rows first, unchanged (contract §10.5),
#   then catalog rows that no rule forbids and, with must-include rows, that
#   hold a target those and the rows before don't (§9.10, §10.6), as further
#   seeds of IPOG's general path, which adds what they leave uncovered, the
#   `stronger` targets included (§4.1, stage 2, "Extend"). Partial
#   must-include rows are completed first, as IPOG completes them, when that
#   leaves fewer catalog rows to keep. At full strength with must-include
#   rows the design is IPOG's, every valid row (§7.8).
#   Probe 11 found this never worse than IPOG with a few rules. With
#   `stronger` groups the seed is the strongest group's own array, on its
#   parameters, when that array is at strength 2 or 3 and no smaller than the
#   base one: seeded with the base array, IPOG's rows for a group whose bound
#   dominates come on top of it.
# - Anything else, mixed value counts on more than t + 1 parameters above
#   all, is refused (`fit` says why); a negative sub-request it refuses goes
#   to IPOG (`_prepare_for`), and `generate` refuses the whole request by name
#   (`_check_fit`).
#
# Its plan (`_ConstructionPlan`, plan §4.2) holds the fit and the entry it
# builds, looked up once per request; `Auto` and `recommend` read the plan
# through `_known_rows`, `_at_bound` and `_plan_line`, never the entry.
#
# It uses no randomness (contract §9.4): the lookup and the builders are
# functions of the shape alone.

"""
Use when every parameter has the same number of values, or there are only
`strength + 1` parameters, and you want the design built from a catalog of
algebraic constructions: often far fewer cases than [`IPOG`](@ref), built in
milliseconds, and an orthogonal array, which shows every combination exactly
once, where the catalog has one: for a prime-power number q of values, at
least the strength, on at most q + 1 parameters, and for `strength + 1`
parameters. Other orthogonal arrays exist that it doesn't build, such as 100
cases for 4 parameters of 10 values.

    Construction()

The catalog engine (plan §5.4). For a space whose parameters all have the
same number of values, or that has at most `strength + 1` parameters, it
chooses the smallest array the catalog's constructions give for that shape,
from sizes alone: orthogonal arrays on prime-power numbers of values, the
zero-sum array for `strength + 1` parameters of any sizes, Kleitman and
Spencer's arrays for two values, cover starters, products of arrays, and at
strength 3 the LFSR array and its copies, small group arrays and recursions.
The array is the design when the space has no rules, no must-include rows and
no `stronger` groups. Otherwise the catalog's rows that no rule forbids seed
IPOG, which adds what they leave uncovered, after the must-include rows; a
catalog row that holds nothing the must-include rows and the rows before it
don't is left out, so a result passed back as `must_include` for the same
space gains no cases. Partial must-include rows are completed first, as IPOG
completes them, when that leaves out more of the catalog's rows, as for a
design passed back after parameters were added or removed. With `stronger`
groups the seed is often the strongest group's own array, on that group's
parameters. Above strength 3 the catalog offers only the arrays that meet the
lower bound, the zero-sum and orthogonal arrays.

It refuses, with its reason, a space it has no array for, such as
parameters with different numbers of values (more than `strength + 1` of
them): naming it is then an `ArgumentError` that suggests `IPOG()` or
[`Auto`](@ref)`()`, which cover any request. `Auto()` uses it where it fits
and is smaller. The result's record says which array it built,
`cases.record.ordinary.catalog`, with its source and whether it is an
orthogonal array. It uses no randomness (contract §9.4); its arrays are
those of the package version, so a later version may build a smaller one
(§9.8).
"""
struct Construction <: CoveringEngine
end

engine_record(::Construction) = EngineRecord(:Construction, nothing)

# As the caller writes it, also inside a wrapper's display: "Compact(Construction(); …)".
Base.show(io::IO, ::Construction) = print(io, "Construction()")

"""
    _ConstructionPlan

`Construction`'s plan for a request (`_prepare`): `engine`; `fit`; `entry`,
the catalog entry it builds (`nothing` when the fit is `:unsupported`); and
`members`, the parameters that entry covers (`nothing` for all of them).
"""
struct _ConstructionPlan <: _Plan
    engine::Construction
    fit::Fit
    entry::Union{Nothing, CatalogEntry}
    members::Union{Nothing, Vector{Int}}
end

"""
    _prepare(::Construction, profile) -> _ConstructionPlan

`Construction`'s fit, the catalog entry it builds, and the parameters that
entry covers, from the profile alone (plan §4.2): no target is listed and
nothing is built. The entry is the base strength's array, or, seeded with
`stronger` groups, the first of the strongest group's (see the file
header). The lookup costs well under a millisecond for the shapes of plan
§5.4's tables and about 2 ms at strength 3 on 250 parameters of 25 values.
"""
function _prepare(engine::Construction, p::Profile)
    refuse(reason) = _ConstructionPlan(engine, Fit(:unsupported, reason), nothing, nothing)
    t, k = p.strength, nparameters(p)
    t >= 1 || return refuse("a base strength of 0, where only `stronger` groups carry targets; " *
                            "the catalog builds for a base strength")
    entry = _catalog_entry(t, p.arity)
    if entry === nothing
        return refuse(allequal(p.arity) ?
                      "no catalog entry for $k parameters of $(first(p.arity)) values at strength $t" :
                      "mixed value counts on $k parameters; the catalog covers equal value counts, " *
                      "or t + 1 = $(t + 1) parameters")
    end
    if t > 3
        # Above strength 3 the catalog has only the zero-sum array and the Bush
        # array, which fused can be hundreds of times the best known size, so it
        # offers only the arrays at the lower bound (p2-construction's judgment
        # call 4, option b, decided for Phase 3).
        bound = _describe(entry).lower_bound
        entry.rows == bound || return refuse(
            "the catalog's array for $k parameters of $(first(p.arity)) values at strength $t ($(entry.name)) " *
            "has $(entry.rows) rows, above the lower bound of $bound; above strength 3 " *
            "the catalog offers only arrays at the lower bound")
    end
    if isempty(p.rules) && p.n_must_include == 0 && length(p.groups) == 1
        f = p.n_invalid == 0 ? Fit(:exact, "$(entry.name): $(entry.rows) rows"; rows = entry.rows) :
                               Fit(:exact, "$(entry.name): $(entry.rows) ordinary rows, then the negative rows")
        return _ConstructionPlan(engine, f, entry, nothing)
    end
    members = nothing
    if length(p.groups) > 1
        s = maximum(last, view(p.groups, 2:length(p.groups)))
        group = first(first(g for g in view(p.groups, 2:length(p.groups)) if last(g) == s))
        own = s <= 3 ? _catalog_entry(s, p.arity[group]) : nothing
        if own !== nothing && own.rows >= entry.rows
            entry, members = own, group
        end
    end
    extras = String[]
    members === nothing || push!(extras, "on the `stronger` group of $(length(members)) parameters at strength $(entry.t)")
    isempty(p.rules) || push!(extras, "the rows a rule forbids dropped")
    p.n_must_include > 0 && push!(extras, "after the must-include rows")
    f = Fit(:seeded, "$(entry.name), $(entry.rows) rows as seeds" * join((", " * x for x in extras)) *
                     "; IPOG adds what they leave uncovered")
    return _ConstructionPlan(engine, f, entry, members)
end

fit(engine::Construction, p::Profile) = _prepare(engine, p).fit

# For an exact shape the array's rows are known before building it, and an
# orthogonal or zero-sum array meets the lower bound, the product of the `t`
# largest value counts (`_describe`), so no design has fewer: `Auto` then
# builds it alone.
_known_rows(plan::_ConstructionPlan) = plan.fit.kind === :exact ? (plan.entry::CatalogEntry).rows : nothing
_at_bound(plan::_ConstructionPlan) =
    plan.fit.kind === :exact && (plan.entry::CatalogEntry).rows == _describe(plan.entry::CatalogEntry).lower_bound
_plan_line(plan::_ConstructionPlan) =
    plan.fit.kind === :exact ? _exact_reason(plan.entry::CatalogEntry, plan.fit.rows === nothing) : plan.fit.reason

"""
    _exact_reason(entry, negative) -> String

The line on an exact shape's plan (`_plan_line`, which `Auto` and `recommend`
show): its size and construction, from `_describe`, as "49 rows: Bush
orthogonal array, every combination exactly once" or "76 rows: Tripling
(tripling from 5 columns)"; with `negative`, a space with `Invalid` values,
the rows are the ordinary ones, and the negative rows follow.
"""
function _exact_reason(entry::CatalogEntry, negative::Bool)
    d = _describe(entry)
    name = startswith(lowercase(d.family), lowercase(d.name)) ? "" : " ($(d.name))"
    return "$(d.rows) $(negative ? "ordinary rows" : "rows"): $(d.family)$name" *
           (d.orthogonal ? ", every combination exactly once" : "") * (negative ? ", then the negative rows" : "")
end

"""
    _engine_rows(entry, arity) -> Matrix{Int}

The catalog's array as an engine's rows: parameters × cases, the symbols
`0:v-1` as engine positions `1:v`, the array's first `length(arity)` columns
in parameter order. A zero-sum array on unequal value counts has its columns
largest first (`_catalog_entry`), so each goes back to its parameter, the
first of equal counts first.
"""
function _engine_rows(entry::CatalogEntry, arity::AbstractVector{<:Integer})
    A = _build(entry)
    k = length(arity)
    size(A, 2) == k || error("internal error: the catalog built $(size(A, 2)) columns for $k parameters")
    order = isempty(entry.sizes) ? collect(1:k) : sortperm(arity; rev = true)
    rows = Matrix{Int}(undef, k, size(A, 1))
    for (c, p) in enumerate(order), r in axes(A, 1)
        rows[p, r] = A[r, c] + 1
    end
    return rows
end

"""
    cover_ordinary(::Construction, request::Request, targets::RequiredTargets) -> Matrix{Int}

The catalog's rows for `request` (plan §5.4). For an exact shape, the array
itself. Seeded, the request's must-include rows first (contract §10.5), then
the catalog's rows that no rule forbids (`_allowed_rows`) and, when there are
must-include rows, that hold a target they and the rows kept before don't
(`_new_coverage_rows`, §9.10), and then IPOG's general path (`ipog_multi_way`)
with all of them as must-include rows, which completes a partial row, adds
rows until every required target is covered, and keeps each row completable
(`dead`). Partial must-include rows are first completed by IPOG's steps on
them alone (`_complete_seeds`), and the catalog's rows filtered against what
the completed rows hold, when that keeps fewer of them; otherwise they stay
partial. At full strength with must-include rows the design is every valid
row after them (`full_strength_rows`, §7.8), as IPOG gives it. The request
records only its own must-include rows (§10.5); the catalog's are ordinary
rows. A request `fit` refuses is an `ArgumentError`.
"""
cover_ordinary(engine::Construction, request::Request, targets::RequiredTargets) = _cover(engine, request, targets)

"""
    _execute(plan::_ConstructionPlan, request, targets) -> (matrix, (catalog = …,))

`cover_ordinary`'s rows for the plan's entry, with the catalog's array in
the notes (plan §5.4, "Balance"): `_describe(entry)`, and `seeded`, whether
the array seeded IPOG rather than being the design. `orthogonal` is the
design's: true only when the design is the array and the array shows every
combination exactly once, so never for a space with `Invalid` values, whose
negative rows repeat ordinary combinations. A plan whose fit is
`:unsupported` is an `ArgumentError`.
"""
function _execute(plan::_ConstructionPlan, request::Request, targets::RequiredTargets)
    f = plan.fit
    f.kind === :unsupported && throw(ArgumentError("Construction() does not cover this request: $(f.reason)"))
    entry, members = plan.entry::CatalogEntry, plan.members
    d = _describe(entry)
    seeded = f.kind === :seeded
    orthogonal = d.orthogonal && !seeded && !_has_invalid(request.space)   # the negative rows repeat combinations
    notes = (catalog = (name = d.name, family = d.family, source = d.source, rows = d.rows,
                        lower_bound = d.lower_bound, orthogonal = orthogonal, seeded = seeded),)
    return _construction_rows(request, targets, f, entry, members), notes
end

"The rows of `cover_ordinary(::Construction, …)` for the plan `_prepare` made."
function _construction_rows(request::Request, targets::RequiredTargets, f::Fit, entry::CatalogEntry,
                       members::Union{Nothing, Vector{Int}})
    must = request.must_include
    # At full strength every target is a whole row, so the design is the
    # must-include rows, completed, and every valid row they don't hold,
    # whatever the engine (contract §7.8, §11.2): IPOG's rows, where the
    # catalog's would repeat a completed partial row.
    size(must, 2) > 0 && request.strength == length(request.arity) &&
        return full_strength_rows(request, _target_list(targets))
    if members === nothing
        rows = _engine_rows(entry, request.arity)
        f.kind === :exact && return rows
    else
        rows = zeros(Int, length(request.arity), entry.rows)   # the group's array, the others unset
        rows[members, :] .= _engine_rows(entry, request.arity[members])
    end
    kept = isconstrained(request) ? _allowed_rows(request, rows) : rows
    isdead = isconstrained(request) ? (row -> dead(request, row)) : Returns(false)
    arity, order = copy(request.arity), ipog_order(request.arity, request.groups)
    buckets = _ipog_buckets(_target_list(targets), order)
    if size(must, 2) > 0
        partial = _new_coverage_rows(must, kept, targets)
        # Partial must-include rows hold only what they set, so a design passed
        # back with parameters added or dropped kept about the whole array
        # after it (the maintainer's follow-up 2). Completed first, as IPOG
        # completes them, they show what they will hold, and the catalog's rows
        # are kept only for what that leaves uncovered. When that keeps no
        # fewer, the rows stay partial, for IPOG to complete beside the
        # catalog's rows: an early completion then only takes from IPOG the
        # entries it would fill with targets the catalog's rows leave.
        if any(==(0), must)
            completed = _complete_seeds(arity, buckets, isdead, must, order)
            fewer = _new_coverage_rows(completed, kept, targets)
            size(fewer, 2) < size(partial, 2) && ((must, partial) = (completed, fewer))
        end
        kept = partial
    end
    return _ipog_multi_way(arity, buckets, isdead, hcat(must, kept), order)
end

"""
    _allowed_rows(request, rows) -> Matrix{Int}

The rows (columns of `rows`) that no rule forbids, in order: a complete row
checked as `validate_design` checks it, a partial one kept when it is not
`dead`, a resolved answer or a `ResourceLimitError` (contract §3.6, §3.8).
"""
function _allowed_rows(request::Request, rows::Matrix{Int})
    keep = Int[]
    for j in axes(rows, 2)
        row = view(rows, :, j)
        allowed = any(==(0), row) ? !dead(request, row) : !_violates(request.feasibility, _space_indices(request, row))
        allowed && push!(keep, j)
    end
    return rows[:, keep]
end

"""
    _new_coverage_rows(must, rows, targets) -> Matrix{Int}

The rows (columns of `rows`, in order) that each hold a required target that
neither the must-include rows `must` nor the rows kept before it hold: with
must-include rows the catalog's rows cover only what those leave uncovered
(contract §9.10, §10.6), so a `Construction()` result passed back as
`must_include` gains no rows, and a must-include row equal to a catalog row
is not repeated. Greedy in the catalog's order, so deterministic. A row
holds the targets on the supports it sets in full; a partial must-include
row holds only those, since its completion is IPOG's to choose, which is why
`_construction_rows` passes completed rows (`_complete_seeds`) where they
leave out more.
"""
function _new_coverage_rows(must::Matrix{Int}, rows::Matrix{Int}, targets::RequiredTargets)
    held = falses(last(targets.offsets))      # by id, offsets[s] + code + 1, as in `RequiredTargets`
    for j in axes(must, 2)
        _hold!(held, view(must, :, j), targets)
    end
    keep = Int[]
    for j in axes(rows, 2)
        _hold!(held, view(rows, :, j), targets) && push!(keep, j)
    end
    return rows[:, keep]
end

"Mark in `held` the required targets that `row` holds (`_new_coverage_rows`); whether one was not marked before."
function _hold!(held::BitVector, row::AbstractVector{Int}, targets::RequiredTargets)
    new = false
    for (s, support) in enumerate(supports(targets))
        any(p -> row[p] == 0, support) && continue
        code = _code(row, support, targets.arity)
        isrequired(targets, s, code) || continue
        id = targets.offsets[s] + code + 1
        new |= !held[id]
        held[id] = true
    end
    return new
end
