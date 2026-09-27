# The public result type (plan Phase 4 step 1, contract §1.18–§1.24).
#
# A TestCases is a vector of rows plus the bookkeeping generation already
# knows. It never performs a search (§1.22): everything here is copied from
# the Request and the Design.

"""
    Exclusion

One target a design did not need to cover, in the user's vocabulary
(contract §1.4): `target` (a partial `NamedTuple`), `status` (`:forbidden`
or `:implied`), `rules` (constraint positions in the space), `labels` (their
display labels), `minimal` (`:verified`, `:unresolved`, `:not_applicable`),
and `limit` (`keyword => value` when a limit cut the explanation short,
else `nothing`).
"""
struct Exclusion
    target::NamedTuple
    status::Symbol
    rules::Vector{Int}
    labels::Vector{String}
    minimal::Symbol
    limit::Union{Nothing, Pair{Symbol, Int}}
end

"""
    TestCases{T} <: AbstractVector{T}

The cases a generation call returns. `T` is a `NamedTuple` type for named
spaces and a `Tuple` type for positional calls (§1.18); each field's type is
the element type of the stored domain, so a `Vector{Int}` domain gives an
`Int` field and an `Any[1, 1.0]` domain gives an `Any` field (§2.4).
`collect(cases)` is a plain `Vector{T}`.

Fields (§1.19), all recorded at generation and never recomputed (§1.22):
`cases`, `space`, `strategy` (`:covering`, `:excursion`, `:full_factorial`),
`strength`, `stronger` (as `names => strength` pairs, base group excluded),
`engine::Symbol`, `seed`, `n_must_include`, `required` and `covered`
(ordinary target counts; zero for non-covering strategies), `excluded`
(`Exclusion`s), `positional::Bool`, and `notes` (strategy specific: an
excursion's `base`, `distance`, `dropped`, `never_appear`; a full
factorial's `candidates`, `accepted`). Negative bookkeeping arrives in
Phase 6 and is kept separate.
"""
struct TestCases{T} <: AbstractVector{T}
    cases::Vector{T}
    space::TestSpace
    strategy::Symbol
    strength::Int
    stronger::Vector{Pair{Tuple{Vararg{Symbol}}, Int}}
    engine::Symbol
    seed::Union{Nothing, Int}
    n_must_include::Int
    required::Int
    covered::Int
    excluded::Vector{Exclusion}
    positional::Bool
    notes::NamedTuple
end

Base.size(tc::TestCases) = size(tc.cases)
Base.getindex(tc::TestCases, i::Int) = tc.cases[i]
Base.IndexStyle(::Type{<:TestCases}) = IndexLinear()
Base.collect(tc::TestCases) = copy(tc.cases)

"The element type for rows of `space`: a NamedTuple type, or a Tuple type when positional."
function row_type(space::TestSpace, positional::Bool)
    types = Tuple{(eltype(v) for v in space.values)...}
    return positional ? types : NamedTuple{Tuple(space.names), types}
end

"""
    TestCases(request, design; positional = false)

Build the public result from an engine's `Design`. Rows come from
`to_cases`; positional results drop the names (§1.18). Exclusions are
translated into names and labels.
"""
function TestCases(request::Request, design::Design; positional::Bool = false)
    space = request.space
    T = row_type(space, positional)
    named = to_cases(request, design.matrix)
    cases = positional ? T[Tuple(values(c)) for c in named] : T[c for c in named]
    stronger = Pair{Tuple{Vararg{Symbol}}, Int}[
        Tuple(space.names[g]) => s for (g, s) in request.groups[2:end]]
    excluded = Exclusion[
        Exclusion(from_indices(space, _space_indices(request, e.target)), e.status, e.rules,
                  [rule_label(space, k) for k in e.rules], e.minimal, e.limit)
        for e in design.excluded]
    return TestCases{T}(cases, space, design.strategy, request.strength, stronger, design.engine,
                        design.seed, design.n_must_include, design.required, design.covered,
                        excluded, positional, design.notes)
end
