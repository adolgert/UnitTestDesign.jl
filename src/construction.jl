# The `Construction` engine (plan §5.4, Phase 2): a covering engine whose
# designs are the catalog's algebraic arrays (construction_catalog.jl), for a
# space of an exact shape, and a seed under a few rules. It is internal until
# Phase 3 names engines for users (plan §3, §11); `UnitTestDesign.Construction()`
# reaches it, and `_engine_registry` lists it, so the oracle loops check it.
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
    Construction()

The catalog engine (plan §5.4; internal until Phase 3, decision D7): for a
space whose parameters all have the same number of values, or that has at
most `strength + 1` parameters, the smallest algebraic covering array the
catalog has (`_catalog_entry`), chosen from sizes alone, with no search and
no randomness. Under rules, must-include rows or `stronger` groups the array
seeds IPOG's general path. `fit` says which, and why it refuses the rest.
"""
struct Construction <: CoveringEngine
end

engine_record(::Construction) = EngineRecord(:Construction, nothing)

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
function cover_ordinary(engine::Construction, request::Request, targets::RequiredTargets)
    f, entry, members = _construction_plan(Profile(request))
    f.kind === :unsupported && throw(ArgumentError("Construction() does not cover this request: $(f.reason)"))
    if members === nothing
        rows = _engine_rows(entry::CatalogEntry, request.arity)
        f.kind === :exact && return rows
    else
        rows = zeros(Int, length(request.arity), entry.rows)   # the group's array, the others unset
        rows[members, :] .= _engine_rows(entry::CatalogEntry, request.arity[members])
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
