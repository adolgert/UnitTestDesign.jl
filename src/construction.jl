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
#   then catalog rows that no rule forbids, as further seeds of IPOG's
#   general path, which adds what they leave uncovered, the `stronger`
#   targets included (§4.1, stage 2, "Extend"). Probe 11 found this never
#   worse than IPOG with a few rules. With `stronger` groups the seed is the
#   strongest group's own array, on its parameters, when that array is at
#   strength 2 or 3 and no smaller than the base one: seeded with the base
#   array, IPOG's rows for a group whose bound dominates come on top of it.
# - Anything else, mixed value counts on more than t + 1 parameters above
#   all, is refused (`fit` says why); a negative sub-request it refuses goes
#   to IPOG (`_engine_for`), and `generate` refuses the whole request by name
#   (`_check_fit`).
#
# It uses no randomness (contract §9.4): the lookup and the builders are
# functions of the shape alone.

"""
Use when every parameter has the same number of values, or there are only
`strength + 1` parameters, and you want the design built from a catalog of
algebraic constructions: often far fewer cases than [`IPOG`](@ref), built in
milliseconds, and an orthogonal array, which shows every combination exactly
once, where one exists.

    Construction()

The catalog engine (plan §5.4). For a space whose parameters all have the
same number of values, or that has at most `strength + 1` parameters, it
chooses the smallest array the catalog's constructions give for that shape,
from sizes alone: orthogonal arrays on prime-power numbers of values, the
zero-sum array for `strength + 1` parameters of any sizes, Kleitman and
Spencer's arrays for two values, cover starters, products of arrays, and at
strength 3 the LFSR array and its copies, small group arrays and recursions.
The array is the design when the space has no rules, no must-include rows
and no `stronger` groups. Otherwise the catalog's rows that no rule forbids
seed IPOG, which adds what they leave uncovered, after the must-include
rows. Above strength 3 the catalog offers only the arrays that meet the
lower bound, the zero-sum and orthogonal arrays.

It refuses, with its reason, a space it has no array for, such as
parameters with different numbers of values (more than `strength + 1` of
them): naming it is then an `ArgumentError` that suggests `IPOG()` or
[`Auto`](@ref)`()`, which cover any request. `Auto()` uses it where it fits
and is smaller. The result's record says which array it built,
`cases.record.catalog`, with its source and whether it is an orthogonal
array. It uses no randomness (contract §9.4); its arrays are those of the
package version, so a later version may build a smaller one (§9.8).
"""
struct Construction <: CoveringEngine
end

engine_record(::Construction) = EngineRecord(:Construction, nothing)

# As the caller writes it, also inside a wrapper's display: "Compact(Construction(); …)".
Base.show(io::IO, ::Construction) = print(io, "Construction()")

"""
    _construction_plan(profile) -> (fit, entry, members)

`fit(Construction(), profile)`, the catalog entry it builds, and the
parameters that entry covers (`nothing` for all of them), from the profile
alone (plan §4.2): no target is listed and nothing is built. The entry is
the base strength's array, or, seeded with `stronger` groups, the first of
the strongest group's (see the file header). The lookup costs well under a
millisecond for the shapes of plan §5.4's tables and about 2 ms at strength
3 on 250 parameters of 25 values.
"""
function _construction_plan(p::Profile)
    t, k = p.strength, nparameters(p)
    t >= 1 || return Fit(:unsupported, "a base strength of 0, where only `stronger` groups carry targets; " *
                                       "the catalog builds for a base strength"), nothing, nothing
    entry = _catalog_entry(t, p.arity)
    if entry === nothing
        return Fit(:unsupported, allequal(p.arity) ?
                   "no catalog entry for $k parameters of $(first(p.arity)) values at strength $t" :
                   "mixed value counts on $k parameters; the catalog covers equal value counts, " *
                   "or t + 1 = $(t + 1) parameters"), nothing, nothing
    end
    if t > 3
        # Above strength 3 the catalog has only the zero-sum array and the Bush
        # array, which fused can be hundreds of times the best known size, so it
        # offers only the arrays at the lower bound (p2-construction's judgment
        # call 4, option b, decided for Phase 3).
        bound = _describe(entry).lower_bound
        entry.rows == bound || return Fit(:unsupported,
            "the catalog's array for $k parameters of $(first(p.arity)) values at strength $t ($(entry.name)) " *
            "has $(entry.rows) rows, above the lower bound of $bound; above strength 3 " *
            "the catalog offers only arrays at the lower bound"), nothing, nothing
    end
    if isempty(p.rules) && p.n_must_include == 0 && length(p.groups) == 1
        p.n_invalid == 0 && return Fit(:exact, "$(entry.name): $(entry.rows) rows"; rows = entry.rows), entry, nothing
        return Fit(:exact, "$(entry.name): $(entry.rows) ordinary rows, then the negative rows"), entry, nothing
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
    return Fit(:seeded, "$(entry.name), $(entry.rows) rows as seeds" * join((", " * x for x in extras)) *
                        "; IPOG adds what they leave uncovered"), entry, members
end

fit(::Construction, p::Profile) = first(_construction_plan(p))

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
the catalog's rows that no rule forbids (`_allowed_rows`), and then IPOG's
general path (`ipog_multi_way`) with all of them as must-include rows, which
completes a partial row, adds rows until every required target is covered,
and keeps each row completable (`dead`). The request records only its own
must-include rows (§10.5); the catalog's are ordinary rows. A request `fit`
refuses is an `ArgumentError`.
"""
cover_ordinary(engine::Construction, request::Request, targets::RequiredTargets) =
    first(_cover_with_notes(engine, request, targets))

"""
    _cover_with_notes(::Construction, request, targets) -> (matrix, (catalog = …,))

`cover_ordinary`'s rows, with the catalog's array in the result's record
(plan §5.4, "Balance"): `_describe(entry)`, and `seeded`, whether the array
seeded IPOG rather than being the design. `orthogonal` is the design's: true
only when the design is the array and the array shows every combination
exactly once, so never for a space with `Invalid` values, whose negative
rows repeat ordinary combinations.
"""
function _cover_with_notes(engine::Construction, request::Request, targets::RequiredTargets)
    f, entry, members = _construction_plan(Profile(request))
    f.kind === :unsupported && throw(ArgumentError("Construction() does not cover this request: $(f.reason)"))
    return _construction_cover(request, targets, f, entry::CatalogEntry, members)
end

"""
    _construction_cover(request, targets, fit, entry, members) -> (matrix, notes)

`_cover_with_notes(::Construction, …)` for a plan `_construction_plan` already
made, which `Auto` hands over rather than look the shape up again.
"""
function _construction_cover(request::Request, targets::RequiredTargets, f::Fit, entry::CatalogEntry,
                             members::Union{Nothing, Vector{Int}})
    d = _describe(entry)
    seeded = f.kind === :seeded
    orthogonal = d.orthogonal && !seeded && !_has_invalid(request.space)   # the negative rows repeat combinations
    notes = (catalog = (name = d.name, family = d.family, source = d.source, rows = d.rows,
                        lower_bound = d.lower_bound, orthogonal = orthogonal, seeded = seeded),)
    return _construction_rows(request, targets, f, entry, members), notes
end

"The rows of `cover_ordinary(::Construction, …)` for the plan `_construction_plan` made."
function _construction_rows(request::Request, targets::RequiredTargets, f::Fit, entry::CatalogEntry,
                       members::Union{Nothing, Vector{Int}})
    if members === nothing
        rows = _engine_rows(entry, request.arity)
        f.kind === :exact && return rows
    else
        rows = zeros(Int, length(request.arity), entry.rows)   # the group's array, the others unset
        rows[members, :] .= _engine_rows(entry, request.arity[members])
    end
    seeds = hcat(request.must_include, isconstrained(request) ? _allowed_rows(request, rows) : rows)
    isdead = isconstrained(request) ? (row -> dead(request, row)) : Returns(false)
    return ipog_multi_way(request.arity, _target_list(targets), isdead, seeds;
                          order = ipog_order(request.arity, request.groups))
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
