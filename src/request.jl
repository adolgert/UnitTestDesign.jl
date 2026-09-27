# The internal request: what an engine consumes and what it returns.
#
# Phase 3 step 1 of design/20260926_implementation_plan.md. This is the
# second index-space boundary (the first is rule_table.jl). An engine sees
# only integers: parameter `i` has values `1:arity[i]` (engine positions),
# a partial row is a Vector{Int} with 0 for unset, a design is a matrix
# with one column per case (the layout coverage_matrix.jl already uses).
# Engine positions map to space value indices through `candidates`, so
# domains with non-contiguous ordinary values (Phase 6) need no engine
# change.

"""
    Request(space; strength = 2, stronger = [], must_include = [],
            feasibility_limit = 1_000_000, explanation_limit = 1_000_000)

Everything an engine needs to produce a design for `space`, in index space.

Fields an engine reads:
- `arity::Vector{Int}`: values per parameter, engine positions `1:arity[i]`.
- `strength::Int`: the base strength.
- `groups::Vector{Pair{Vector{Int}, Int}}`: parameter index groups with
  their strength, the base group (all parameters at `strength`) first,
  then each `stronger` group (contract §11). Groups at the base strength
  are dropped (§11.7); a group listed twice keeps its highest strength
  (§11.8).
- `must_include::Matrix{Int}`: one column per must-include row, `0` for
  unset, engine positions, in the order given (§10.5).
- `dead(request, partial)`: the only feasibility question an engine asks.

Bookkeeping for the caller: `space`, `candidates` (engine position `k` of
parameter `i` is space value index `candidates[i][k]`), `n_must_include`,
`feasibility_limit`, `explanation_limit`, and `feasibility` (the shared
`Feasibility`, whose caches live as long as the request, §3.5).
"""
struct Request
    space::TestSpace
    candidates::Vector{Vector{Int}}
    arity::Vector{Int}
    strength::Int
    groups::Vector{Pair{Vector{Int}, Int}}
    must_include::Matrix{Int}
    feasibility::Feasibility
    feasibility_limit::Int
    explanation_limit::Int
end

function Request(space::TestSpace; strength::Integer = 2, stronger = [], must_include = [],
                 feasibility_limit::Integer = 1_000_000, explanation_limit::Integer = 1_000_000)
    _check_limit(:feasibility_limit, feasibility_limit)
    _check_limit(:explanation_limit, explanation_limit)
    n = length(space.names)
    strength >= 1 || throw(ArgumentError("strength must be at least 1, got $strength (contract §11.1)"))
    strength <= n || throw(ArgumentError(
        "strength $strength is larger than the number of parameters, $n (contract §11.2)"))
    for (i, name) in enumerate(space.names)
        isempty(invalid_indices(space, i)) || throw(ArgumentError(
            "parameter `$name` has an Invalid value; generation with Invalid or Partition values " *
            "is not supported yet (contract §0.2)"))
        any(v -> v isa Partition, space.values[i]) && throw(ArgumentError(
            "parameter `$name` has a Partition value; generation with Invalid or Partition values " *
            "is not supported yet (contract §0.2)"))
    end
    candidates = [copy(ordinary_indices(space, i)) for i in 1:n]
    arity = length.(candidates)
    groups = _groups(space, strength, stronger)
    feasibility = Feasibility(candidates, space.tables; limit = feasibility_limit)
    request = Request(space, candidates, arity, strength, groups, zeros(Int, n, 0), feasibility,
                      Int(feasibility_limit), Int(explanation_limit))
    seeds = _must_include_matrix(request, must_include)
    return Request(space, candidates, arity, strength, groups, seeds, feasibility,
                   Int(feasibility_limit), Int(explanation_limit))
end

n_must_include(request::Request) = size(request.must_include, 2)

"""
    _groups(space, strength, stronger)

Validate `stronger` (contract §11.3–§11.9) and return the group list, base
group first. Names or 1-based indices; each entry `names => s`.
"""
function _groups(space::TestSpace, strength::Integer, stronger)
    n = length(space.names)
    groups = Pair{Vector{Int}, Int}[collect(1:n) => Int(strength)]
    seen = Dict{Vector{Int}, Int}()
    for entry in stronger
        entry isa Pair || throw(ArgumentError(
            "each `stronger` entry is `names => strength`, for example `(:a, :b, :c) => 3`; got $entry"))
        members, s = entry
        idx = Int[]
        for m in members
            if m isa Symbol
                push!(idx, parameter_index(space, m))
            elseif m isa Integer
                1 <= m <= n || throw(ArgumentError(
                    "`stronger` group $members names parameter $m, but the space has $n parameters"))
                push!(idx, Int(m))
            else
                throw(ArgumentError("`stronger` group members are names or indices; got $m"))
            end
        end
        length(unique(idx)) == length(idx) || throw(ArgumentError(
            "`stronger` group $members lists a parameter twice (contract §11.5)"))
        s isa Integer || throw(ArgumentError("`stronger` strength for $members must be an integer"))
        s >= strength || throw(ArgumentError(
            "`stronger` group $members has strength $s, below the base strength $strength (contract §11.6)"))
        s <= length(idx) || throw(ArgumentError(
            "`stronger` group $members has strength $s, above its size $(length(idx)) (contract §11.6)"))
        s == strength && continue   # a no-op (§11.7)
        key = sort(idx)
        seen[key] = max(get(seen, key, 0), Int(s))
    end
    for (key, s) in sort(collect(seen); by = first)
        push!(groups, key => s)
    end
    return groups
end

"""
    _must_include_matrix(request, rows) -> Matrix{Int}

Validate must-include rows (contract §10.1–§10.4): each a `NamedTuple`
(partial allowed) or a `Tuple`/`AbstractVector` (positional, complete).
Values are matched by identity; a row that violates an applicable rule is
an `ArgumentError` naming the rule; a partial row must be completable, and
an exhausted search is a `ResourceLimitError` (distinct from infeasible).
"""
function _must_include_matrix(request::Request, rows)
    space = request.space
    n = length(space.names)
    columns = Vector{Int}[]
    for (r, row) in enumerate(rows)
        if row isa Tuple || row isa AbstractVector
            length(row) == n || throw(ArgumentError(
                "must_include row $r has $(length(row)) values; the space has $n parameters"))
        elseif !(row isa NamedTuple)
            throw(ArgumentError("must_include row $r is a $(typeof(row)); use a NamedTuple or a Tuple"))
        end
        idx = try
            case_indices(space, row isa NamedTuple ? row : Tuple(row))
        catch err
            err isa ArgumentError || rethrow()
            throw(ArgumentError("must_include row $r: " * err.msg))   # §10.2 names the row
        end
        any(i -> idx[i] != 0 && !(idx[i] in request.candidates[i]), 1:n) && throw(ArgumentError(
            "must_include row $r uses an Invalid or Partition value; not supported yet (contract §0.2)"))
        positions = _positions(request, idx)
        if violates(request.feasibility, _space_indices(request, positions))
            rules = violated_rules(request.feasibility, _space_indices(request, positions))
            labels = join((_rule_ref(space.constraints[k], k) for k in rules), ", ")
            throw(ArgumentError("must_include row $r, $(from_indices(space, idx)), breaks $labels (contract §10.3)"))
        end
        if any(==(0), positions)
            status, _ = completable(request.feasibility, _space_indices(request, positions))
            status == :unknown && throw(ResourceLimitError(
                "checking whether must_include row $r can be completed", request.feasibility_limit,
                :feasibility_limit))
            status == :infeasible && throw(ArgumentError(
                "must_include row $r, $(from_indices(space, idx)), has no valid completion (contract §10.4); " *
                "explain(space, row) names the rules"))
        end
        push!(columns, positions)
    end
    return isempty(columns) ? zeros(Int, n, 0) : reduce(hcat, columns)
end

"Engine positions from space value indices (0 stays 0)."
function _positions(request::Request, idx::AbstractVector{<:Integer})
    return Int[idx[i] == 0 ? 0 : something(findfirst(==(idx[i]), request.candidates[i]))
               for i in eachindex(request.candidates)]
end

"Space value indices from engine positions (0 stays 0)."
function _space_indices(request::Request, positions::AbstractVector{<:Integer})
    return Int[positions[i] == 0 ? 0 : request.candidates[i][positions[i]]
               for i in eachindex(request.candidates)]
end

"""
    dead(request, partial) -> Bool

`true` only when the partial row (engine positions, `0` unset) is proven
to have no valid completion; `false` only with a completion witness; throws
`ResourceLimitError` when the budget runs out (plan Phase 3 step 1,
contract §3.6). This is the predicate that replaces `disallow` at every
engine site.
"""
function dead(request::Request, partial::AbstractVector{<:Integer})
    f = request.feasibility
    key = _checked_key(f, _space_indices(request, partial))
    status, _ = _completable(f, key, f.limit)
    status === :unknown && throw(ResourceLimitError(
        "placing a value: the feasibility search for $(from_indices(request.space, key))",
        f.limit, :feasibility_limit))
    return status === :infeasible
end

"""
    witness(request, partial) -> Vector{Int}

A complete row (engine positions) extending `partial`, or throws:
`ResourceLimitError` on an exhausted search, an `ErrorException` if the
partial is infeasible (callers ask `dead` first).
"""
function witness(request::Request, partial::AbstractVector{<:Integer})
    status, w = completable(request.feasibility, _space_indices(request, partial))
    status == :unknown && throw(ResourceLimitError(
        "completing the row $(from_indices(request.space, _space_indices(request, partial)))",
        request.feasibility_limit, :feasibility_limit))
    status == :infeasible && error("internal error: asked for a witness of an infeasible row $partial")
    return _positions(request, w)
end

isconstrained(request::Request) = !isempty(request.feasibility.tables)

"""
    targets(request) -> Vector{Vector{Int}}

Every target of the request as a partial row in engine positions: for each
group `(G, s)`, each `s`-subset of `G`, each assignment (contract §1.8).
The union over groups, deduplicated, in a fixed order (base group first,
subsets in `combinations` order, assignments with the first parameter
varying fastest).
"""
function targets(request::Request)
    n = length(request.arity)
    out = Vector{Int}[]
    seen = Set{Vector{Int}}()
    for (members, s) in request.groups
        for subset in combinations(members, s)
            ranges = (1:request.arity[i] for i in subset)
            for assignment in Iterators.product(ranges...)
                row = zeros(Int, n)
                for (i, v) in zip(subset, assignment)
                    row[i] = v
                end
                if !(row in seen)
                    push!(seen, row)
                    push!(out, row)
                end
            end
        end
    end
    return out
end

"""
    Excluded

One target the design does not need to cover: `target` (engine positions),
`status` (`:forbidden` or `:implied`), `rules` (constraint positions in the
space), `minimal` (`:verified`, `:unresolved`, or `:not_applicable`).
"""
struct Excluded
    target::Vector{Int}
    status::Symbol
    rules::Vector{Int}
    minimal::Symbol
end

"""
    classify_targets(request) -> (required, excluded)

Classify every target (contract §1.4): `required` is the list of targets an
engine must cover, `excluded` the `Excluded` records. An `:unknown` target
is a `ResourceLimitError`: generation never returns an uncertified design
(§3.6). An unconstrained request classifies nothing and requires
everything.
"""
function classify_targets(request::Request)
    all_targets = targets(request)
    isconstrained(request) || return all_targets, Excluded[]
    f = request.feasibility
    required = Vector{Int}[]
    excluded = Excluded[]
    for t in all_targets
        e = explain_partial(f, _space_indices(request, t); explanation_limit = request.explanation_limit)
        if e.outcome == :unknown
            throw(ResourceLimitError("classifying target $(from_indices(request.space, _space_indices(request, t)))",
                                     request.feasibility_limit, :feasibility_limit))
        elseif e.outcome == :allowed || e.outcome == :completable
            push!(required, t)
        elseif e.outcome == :forbidden
            push!(excluded, Excluded(t, :forbidden, e.rules, :not_applicable))
        else
            push!(excluded, Excluded(t, :implied, e.rules, e.minimal))
        end
    end
    return required, excluded
end

"""
    Design

What `generate(engine, request)` returns: `matrix` (parameters × cases,
engine positions, complete), `strategy` (`:covering`, `:excursion`,
`:full_factorial`), `engine::Symbol`, `seed` (GND's seed or `nothing`),
`required::Int` and `covered::Int` (targets, for covering designs),
`excluded::Vector{Excluded}`, `n_must_include::Int`, and `notes` (strategy
specific: an excursion's dropped rows, a full factorial's candidate and
accepted counts) as a `NamedTuple`.
"""
struct Design
    matrix::Matrix{Int}
    strategy::Symbol
    engine::Symbol
    seed::Union{Nothing, Int}
    required::Int
    covered::Int
    excluded::Vector{Excluded}
    n_must_include::Int
    notes::NamedTuple
end

"""
    covers(matrix, target) -> Bool

Whether some column of `matrix` contains the partial row `target`.
"""
function covers(matrix::AbstractMatrix{<:Integer}, target::AbstractVector{<:Integer})
    for j in axes(matrix, 2)
        ok = true
        for i in eachindex(target)
            if target[i] != 0 && matrix[i, j] != target[i]
                ok = false
                break
            end
        end
        ok && return true
    end
    return false
end

"""
    validate_design(request, matrix, required; strategy) -> Int

Final validation (plan Phase 3 step 6, contract §1.21): every row is
complete and within arity, every row passes every applicable rule
(including lazy ones, through `isallowed` on the space), must-include rows
come first in the given order, and for a covering design every required
target is covered. Returns the number of required targets covered. A
failure is an `ErrorException` beginning "internal error", naming the row
or target.
"""
function validate_design(request::Request, matrix::AbstractMatrix{<:Integer}, required;
                         strategy::Symbol = :covering)
    n = length(request.arity)
    size(matrix, 1) == n || error("internal error: design has $(size(matrix, 1)) rows for $n parameters")
    for j in axes(matrix, 2)
        row = matrix[:, j]
        for i in 1:n
            1 <= row[i] <= request.arity[i] ||
                error("internal error: case $j has value position $(row[i]) for parameter $(request.space.names[i])")
        end
        case = from_indices(request.space, _space_indices(request, row))
        isallowed(request.space, case) || error("internal error: case $j, $case, breaks a rule")
    end
    seeds = request.must_include
    for s in axes(seeds, 2)
        s <= size(matrix, 2) || error("internal error: must_include row $s is missing from the design")
        for i in 1:n
            seeds[i, s] == 0 || seeds[i, s] == matrix[i, s] ||
                error("internal error: must_include row $s was changed at parameter $(request.space.names[i])")
        end
    end
    covered = 0
    if strategy == :covering
        # The rows' projections onto each target's parameters, built once per
        # parameter set, so the check is linear in targets plus rows.
        projections = Dict{Vector{Int}, Set{Vector{Int}}}()
        for t in required
            support = findall(!=(0), t)
            seen = get!(() -> Set(matrix[support, j] for j in axes(matrix, 2)), projections, support)
            if t[support] in seen
                covered += 1
            else
                error("internal error: required target $(from_indices(request.space, _space_indices(request, t))) is not covered")
            end
        end
    end
    return covered
end

"""
    to_cases(request, matrix) -> Vector{NamedTuple}

The design as named cases with the space's values (wrappers kept).
"""
function to_cases(request::Request, matrix::AbstractMatrix{<:Integer})
    return [from_indices(request.space, _space_indices(request, matrix[:, j])) for j in axes(matrix, 2)]
end
