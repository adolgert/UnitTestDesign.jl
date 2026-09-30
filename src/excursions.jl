# Excursions: every valid row within a distance of a base row (plan Phase 3
# step 4; contract §7.5–§7.7, §7.11).
#
# One distance. An excursion row differs from the base in at most `distance`
# parameters (Hamming distance), and nothing else widens that: an excursion
# has no groups, and a request with `stronger` groups is refused, since
# `stronger` belongs to covering designs. Excursion distance is not covering
# strength. The request's `strength` is not read; build the request with the
# default strength, or `strength = 1`, which every space accepts (§11.2).
#
# Order (the 0.4 order). The base first, then the change sets sorted by size
# and then lexicographically, and within a set every combination of the
# other values of its parameters, in domain order, the last parameter varying
# fastest. With the base at the first value of each parameter this is
# exactly the 0.4 `build_excursion` order.
#
# Row policy (§7.5, §7.6). The base is an ordinary row. A changed parameter
# may take an `Invalid` value, which makes a negative row, judged under the
# negative policy (§5.5). A row with two `Invalid` values is no candidate:
# it is neither returned nor counted as dropped (§5.7).

using Combinatorics: combinations

"""
    excursion_subsets(n, distance) -> Vector{Vector{Int}}

The sets of parameters an excursion row may change, sorted by size and then
lexicographically: every nonempty subset of `1:n` with at most `distance`
members. Empty for distance 0.
"""
function excursion_subsets(n::Integer, distance::Integer)
    return [c for k in 1:min(distance, n) for c in combinations(1:n, k)]
end

"""
    build_excursion(arity, distance, base, dead; skip = row -> false) -> (; matrix, dropped)
    build_excursion(choices, distance, base, dead; skip = row -> false)

Every row that differs from `base` (engine positions) in at most `distance`
parameters, with each changed parameter taking every other value: every
position in `1:arity[i]`, or in `choices[i]`, in that order. The base comes
first, then the rows in the order of `excursion_subsets`, the last changed
parameter varying fastest. A row for which `skip(row)` holds is no candidate
and is left out uncounted. `dead(row)` is asked of each other complete row;
rows it rejects are left out and counted in `dropped`. The base is included
without asking; the caller checks it (contract §7.6). Distance 0 is the base
alone; a distance above `length(arity)` acts as `length(arity)`.
"""
function build_excursion(arity::AbstractVector{<:Integer}, distance::Integer,
                         base::AbstractVector{<:Integer}, dead; skip = Returns(false))
    return build_excursion([collect(1:a) for a in arity], distance, base, dead; skip)
end

function build_excursion(choices::AbstractVector{<:AbstractVector{<:Integer}}, distance::Integer,
                         base::AbstractVector{<:Integer}, dead; skip = Returns(false))
    n = length(choices)
    length(base) == n || throw(ArgumentError("the base has $(length(base)) entries for $n parameters"))
    distance >= 0 || throw(ArgumentError("the excursion distance must be at least 0, got $distance"))
    others = [[v for v in choices[i] if v != base[i]] for i in 1:n]
    kept = Vector{Int}[collect(Int, base)]
    dropped = 0
    for subset in excursion_subsets(n, distance)
        # The last parameter of the subset varies fastest, as in 0.4.
        ranges = Tuple(others[i] for i in reverse(subset))
        for combo in Iterators.product(ranges...)
            row = collect(Int, base)
            for (j, i) in enumerate(reverse(subset))
                row[i] = combo[j]
            end
            skip(row) && continue
            if dead(row)
                dropped += 1
            else
                push!(kept, row)
            end
        end
    end
    return (matrix = reduce(hcat, kept), dropped = dropped)
end

"The engine positions of each parameter in domain order: ordinary and invalid values interleaved as the domain lists them."
_domain_positions(request::Request) = [sortperm(c) for c in request.candidates]

"""
    excursion_base(request, from) -> Vector{Int}

The base row in engine positions. `nothing` is the first ordinary value of
each parameter (contract §7.6). A `Vector{Int}` is taken as engine
positions. A `NamedTuple` or `Tuple` is read in the caller's vocabulary and
must be complete and ordinary.
"""
function excursion_base(request::Request, from)
    n = length(request.arity)
    from === nothing && return ones(Int, n)
    if from isa AbstractVector{<:Integer}
        length(from) == n || throw(ArgumentError(
            "the excursion base `from` has $(length(from)) positions; the space has $n parameters"))
        for i in 1:n
            1 <= from[i] <= request.arity[i] || throw(ArgumentError(
                "the excursion base `from` gives parameter `$(request.space.names[i])` position " *
                "$(from[i]), outside 1:$(request.arity[i])"))
        end
        return collect(Int, from)
    elseif from isa NamedTuple || from isa Tuple
        idx = try
            case_indices(request.space, from)
        catch err
            err isa ArgumentError || rethrow()
            throw(ArgumentError("the excursion base `from`: " * err.msg))   # names the keyword (§7.6)
        end
        unset = request.space.names[idx .== 0]
        isempty(unset) || throw(ArgumentError(
            "the excursion base `from` must be a complete row (contract §7.6); it has no value for " *
            join(unset, ", ")))
        for i in 1:n
            idx[i] in ordinary_indices(request.space, i) || throw(ArgumentError(
                "the excursion base `from` has the Invalid value $(repr(request.space.values[i][idx[i]])) " *
                "at `$(request.space.names[i])`; the base must be an ordinary row (contract §7.6)"))
        end
        return _positions(request, idx)
    end
    throw(ArgumentError("the excursion base `from` is a NamedTuple, a Tuple, or nothing; got a $(typeof(from))"))
end

"""
    _complete_toward(request, partial, preferred) -> Vector{Int}

A valid completion of `partial` that takes `preferred[i]` wherever it can:
each unset parameter, in parameter order, gets the first value that keeps
the row completable, trying `preferred[i]` and then its other ordinary
values in order. A partial row with an `Invalid` value is completed as a
negative row, under the negative policy (§5.5, §7.9). `partial` must be
completable; assigned values never change (contract §7.10).
"""
function _complete_toward(request::Request, partial::AbstractVector{<:Integer},
                          preferred::AbstractVector{<:Integer})
    row = collect(Int, partial)
    for i in eachindex(row)
        row[i] == 0 || continue
        for v in Iterators.flatten(((preferred[i],), (w for w in 1:request.arity[i] if w != preferred[i])))
            row[i] = v
            dead(request, row) || break
            row[i] = 0
        end
        row[i] == 0 && error("internal error: must_include row $partial has no completion")
    end
    return row
end

"""
    generate_excursion(request; distance = 1, from = nothing) -> Design

The must-include rows, then the base, then every valid row, ordinary or
negative, that differs from the base in at most `distance` parameters
(contract §7.5). A changed parameter takes each of its other values in
domain order, `Invalid` values included; a row with one `Invalid` value is
judged under the negative policy (§5.5), and a row with two is no candidate:
never returned, and not counted as dropped (§5.7). `distance` is one
integer of at least 0: 0 gives the must-include rows and the base alone, and
a distance above the parameter count acts as the parameter count. Every row
after the must-include rows is within `distance` of the base; nothing
widens it. An excursion has no groups: a request with `stronger` groups is
an `ArgumentError`. The request's `strength` is not used; build it with the
default strength (or `strength = 1`, which a one-parameter space needs).

Rows within the distance that break a rule are dropped and reported:
`notes.dropped` counts them and `notes.never_appear` lists the
`(parameter, position)` pairs whose value appears in no returned row (§7.7).
An excursion makes no covering claim. An excursion row equal to a
must-include row is not repeated (§7.11); a partial must-include row is
completed toward the base.

`from` is `nothing` (the first ordinary value of each parameter), a complete
`NamedTuple` or `Tuple` of values, or a `Vector{Int}` of engine positions. The
base is an ordinary row: one with an `Invalid` value, or one that breaks a
rule, is an `ArgumentError` naming the cause (§7.6).

`notes` also records `base` (engine positions) and `distance` (after
clamping to the parameter count).
"""
function generate_excursion(request::Request; distance::Integer = 1, from = nothing)
    distance >= 0 || throw(ArgumentError("the excursion distance must be at least 0, got $distance"))
    length(request.groups) == 1 || throw(ArgumentError(
        "excursions take a single distance; stronger groups apply to covering designs"))
    space = request.space
    distance = Int(min(distance, length(request.arity)))
    base = excursion_base(request, from)
    if violates(request.feasibility, _space_indices(request, base))
        throw(ArgumentError(
            "the excursion base $(from_indices(space, _space_indices(request, base))) breaks " *
            _broken_rules(request, base) * "; choose a valid base with `from` (contract §7.6)"))
    end
    # Each row under its own policy (§5.4, §5.5); two invalid values are no candidate (§5.7).
    isdead = row -> violates(_feasibility(request, row), _space_indices(request, row))
    multiple = row -> count(i -> row[i] > request.arity[i], eachindex(row)) > 1
    choices = _domain_positions(request)
    excursion = build_excursion(choices, distance, base, isdead; skip = multiple)
    must = Vector{Int}[]
    for s in axes(request.must_include, 2)
        row = request.must_include[:, s]
        any(==(0), row) && (row = _complete_toward(request, row, base))
        push!(must, row)
    end
    seen = Set(must)
    rows = copy(must)
    for j in axes(excursion.matrix, 2)
        row = excursion.matrix[:, j]
        row in seen || push!(rows, row)
    end
    matrix = reduce(hcat, rows)
    validate_design(request, matrix, Vector{Int}[]; strategy = :excursion)
    _validate_excursion(request, matrix, length(must), base, distance)
    notes = (dropped = excursion.dropped, never_appear = never_appear(choices, matrix),
             base = base, distance = distance)
    return Design(matrix, :excursion, :Excursion, nothing, 0, 0, Excluded[], n_must_include(request), notes)
end

"""
    never_appear(choices, matrix) -> Vector{Tuple{Int, Int}}

The `(parameter, position)` pairs whose value is in no column of `matrix`,
by parameter and then position: every position in `choices[i]`, in that
order.
"""
function never_appear(choices::AbstractVector{<:AbstractVector{<:Integer}}, matrix::AbstractMatrix{<:Integer})
    out = Tuple{Int, Int}[]
    for i in eachindex(choices)
        present = Set(view(matrix, i, :))
        for v in choices[i]
            v in present || push!(out, (i, v))
        end
    end
    return out
end

# Strategy validation (plan Phase 3 step 6): every row after the must-include
# rows is within Hamming distance `distance` of the base, and none repeats an
# earlier row, must-include rows included (§7.11).
function _validate_excursion(request::Request, matrix, n_must, base, distance)
    n = length(base)
    seen = Set{Vector{Int}}(matrix[:, j] for j in 1:n_must)
    for j in (n_must + 1):size(matrix, 2)
        row = matrix[:, j]
        changed = findall(i -> row[i] != base[i], 1:n)
        length(changed) <= distance || error(
            "internal error: excursion case $j changes $(request.space.names[changed]), " *
            "beyond distance $distance of the base")
        row in seen && error("internal error: excursion case $j repeats an earlier case")
        push!(seen, row)
    end
    return nothing
end
