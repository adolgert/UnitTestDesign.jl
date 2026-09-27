# Excursions: every valid row within a distance of a base row (plan Phase 3
# step 4; contract §7.5–§7.7, §7.11).
#
# The change sets. The base group allows changes of up to `distance`
# parameters. Each `stronger` group `(G, s)` of the request (its groups after
# the base group) also allows changes of up to `s` parameters within `G`,
# which is how the 0.4 `wayness` levels of `build_excursion_multi` worked:
# a group's strength is its distance. The request's own base strength is not
# used; build the request with `strength = distance` so that its `stronger`
# validation (§11.6, §11.7) compares group strengths with the distance.
#
# Order (the 0.4 order). The base first, then the change sets sorted by size
# and then lexicographically, and within a set every combination of the
# other values of its parameters, the last parameter varying fastest. With
# the base at the first value of each parameter this is exactly the 0.4
# `build_excursion` order.

using Combinatorics: combinations

"""
    excursion_subsets(n, distance, groups = []) -> Vector{Vector{Int}}

The sets of parameters an excursion row may change, sorted by size and then
lexicographically: every nonempty subset of `1:n` with at most `distance`
members, and for each `group => s` every nonempty subset of `group` with at
most `s` members.
"""
function excursion_subsets(n::Integer, distance::Integer, groups = Pair{Vector{Int}, Int}[])
    subsets = Set{Vector{Int}}()
    for k in 1:min(distance, n), c in combinations(1:n, k)
        push!(subsets, c)
    end
    for (members, s) in groups
        sorted = sort(collect(Int, members))
        for k in 1:min(s, length(sorted)), c in combinations(sorted, k)
            push!(subsets, c)
        end
    end
    return sort!(collect(subsets); by = x -> (length(x), x))
end

"""
    build_excursion(arity, distance, base, dead; groups = []) -> (; matrix, dropped)

Every row that differs from `base` (engine positions) in at most `distance`
parameters, or within a `groups` entry `members => s` in at most `s` of its
members, with each changed parameter taking every other value. The base
comes first, then the rows in the order of `excursion_subsets`, the last
changed parameter varying fastest. `dead(row)` is asked of each complete
row; rows it rejects are left out and counted in `dropped`. The base is
included without asking; the caller checks it (contract §7.6).
"""
function build_excursion(arity::AbstractVector{<:Integer}, distance::Integer,
                         base::AbstractVector{<:Integer}, dead; groups = Pair{Vector{Int}, Int}[])
    n = length(arity)
    length(base) == n || throw(ArgumentError("the base has $(length(base)) entries for $n parameters"))
    others = [[v for v in 1:arity[i] if v != base[i]] for i in 1:n]
    kept = Vector{Int}[collect(Int, base)]
    dropped = 0
    for subset in excursion_subsets(n, distance, groups)
        # The last parameter of the subset varies fastest, as in 0.4.
        ranges = Tuple(others[i] for i in reverse(subset))
        for combo in Iterators.product(ranges...)
            row = collect(Int, base)
            for (j, i) in enumerate(reverse(subset))
                row[i] = combo[j]
            end
            if dead(row)
                dropped += 1
            else
                push!(kept, row)
            end
        end
    end
    return (matrix = reduce(hcat, kept), dropped = dropped)
end

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
        idx = case_indices(request.space, from)
        unset = request.space.names[idx .== 0]
        isempty(unset) || throw(ArgumentError(
            "the excursion base `from` must be a complete row (contract §7.6); it has no value for " *
            join(unset, ", ")))
        for i in 1:n
            idx[i] in request.candidates[i] || throw(ArgumentError(
                "the excursion base `from` has the Invalid value $(repr(request.space.values[i][idx[i]])) " *
                "at `$(request.space.names[i])`; the base must be an ordinary row (contract §7.6)"))
        end
        return _positions(request, idx)
    end
    throw(ArgumentError("the excursion base `from` is a NamedTuple, a Tuple, or nothing; got a $(typeof(from))"))
end

"Every rule a complete row (engine positions) breaks, as a phrase naming each."
function _broken_rules(request::Request, row::AbstractVector{<:Integer})
    rules = violated_rules(request.feasibility, _space_indices(request, row))
    return join((_rule_ref(request.space.constraints[k], k) for k in rules), ", ", " and ")
end

"""
    _complete_toward(request, partial, preferred) -> Vector{Int}

A valid completion of `partial` that takes `preferred[i]` wherever it can:
each unset parameter, in parameter order, gets the first value that keeps
the row completable, trying `preferred[i]` and then its other values in
order. `partial` must be completable; assigned values never change
(contract §7.10).
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

The must-include rows, then the base, then every valid row that differs from
the base in at most `distance` parameters (contract §7.5), and within each
`stronger` group `(G, s)` of the request in at most `s` parameters of `G`.
Rows that break a rule are dropped and reported: `notes.dropped` counts
them and `notes.never_appear` lists the `(parameter, position)` pairs whose
value appears in no returned row (§7.7). An excursion makes no covering
claim. An excursion row equal to a must-include row is not repeated
(§7.11); a partial must-include row is completed toward the base.

`from` is `nothing` (the first ordinary value of each parameter), a complete
`NamedTuple` or `Tuple` of values, or a `Vector{Int}` of engine positions. A
base that breaks a rule is an `ArgumentError` naming the rules (§7.6).

`notes` also records `base` (engine positions) and `distance`.
"""
function generate_excursion(request::Request; distance::Integer = 1, from = nothing)
    distance >= 0 || throw(ArgumentError("the excursion distance must be at least 0, got $distance"))
    space = request.space
    base = excursion_base(request, from)
    if violates(request.feasibility, _space_indices(request, base))
        throw(ArgumentError(
            "the excursion base $(from_indices(space, _space_indices(request, base))) breaks " *
            _broken_rules(request, base) * "; choose a valid base with `from` (contract §7.6)"))
    end
    groups = request.groups[2:end]
    isdead = row -> violates(request.feasibility, _space_indices(request, row))
    excursion = build_excursion(request.arity, distance, base, isdead; groups = groups)
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
    _validate_excursion(request, matrix, length(must), base, distance, groups)
    notes = (dropped = excursion.dropped, never_appear = never_appear(request.arity, matrix),
             base = base, distance = Int(distance))
    return Design(matrix, :excursion, :Excursion, nothing, 0, 0, Excluded[], n_must_include(request), notes)
end

"""
    never_appear(arity, matrix) -> Vector{Tuple{Int, Int}}

The `(parameter, position)` pairs whose value is in no column of `matrix`,
by parameter and then position.
"""
function never_appear(arity::AbstractVector{<:Integer}, matrix::AbstractMatrix{<:Integer})
    out = Tuple{Int, Int}[]
    for i in eachindex(arity)
        present = falses(arity[i])
        for j in axes(matrix, 2)
            present[matrix[i, j]] = true
        end
        for v in 1:arity[i]
            present[v] || push!(out, (i, v))
        end
    end
    return out
end

# Strategy validation (plan Phase 3 step 6): every row after the must-include
# rows is the base or changes an allowed set of parameters, and none repeats
# an earlier row, must-include rows included (§7.11).
function _validate_excursion(request::Request, matrix, n_must, base, distance, groups)
    n = length(base)
    allowed = Set(excursion_subsets(n, distance, groups))
    seen = Set{Vector{Int}}(matrix[:, j] for j in 1:n_must)
    for j in (n_must + 1):size(matrix, 2)
        row = matrix[:, j]
        changed = findall(i -> row[i] != base[i], 1:n)
        (isempty(changed) || changed in allowed) || error(
            "internal error: excursion case $j changes $(request.space.names[changed]), " *
            "beyond distance $distance of the base")
        row in seen && error("internal error: excursion case $j repeats an earlier case")
        push!(seen, row)
    end
    return nothing
end
