# Full factorial: every valid row (plan Phase 3 step 5, Phase 6 step 1;
# contract §7.2–§7.4).
#
# The candidate count is checked against `limit` before anything is
# enumerated (§7.3): the ordinary product plus, for each parameter, its
# invalid values times the product of the other parameters' ordinary values.
# Candidates are then visited one at a time, in the 0.4 order (the last
# parameter varies fastest): the ordinary rows, kept when they pass every
# rule, then for each parameter in order and each of its invalid values in
# domain order, the rows holding that value beside ordinary values, kept
# when they pass the rules whose scope omits the parameter (§5.5). A
# multiple-invalid row is never a candidate (§5.7), and a rejected row is
# never stored (§7.4). The result is a materialized matrix.

"""
    _advance!(row, arity) -> Bool

Step `row` (engine positions) to the next row of the product of
`1:arity[i]`, the last parameter fastest (the 0.4 order). Returns `false`,
leaving `row` at all ones, after the last row.
"""
function _advance!(row::Vector{Int}, arity::AbstractVector{<:Integer})
    for i in length(row):-1:1
        if row[i] < arity[i]
            row[i] += 1
            return true
        end
        row[i] = 1
    end
    return false
end

"""
    full_factorial_rows(arity) -> iterator

Every row of the product of `1:arity[i]`, as a fresh `Vector{Int}` of engine
positions, the last parameter varying fastest (the 0.4 order). Lazy: rows
are made one at a time.
"""
full_factorial_rows(arity::AbstractVector{<:Integer}) = FullFactorialRows(collect(Int, arity))

"The iterator of `full_factorial_rows`; its state is the current row."
struct FullFactorialRows
    arity::Vector{Int}
end

Base.IteratorSize(::Type{FullFactorialRows}) = Base.SizeUnknown()
Base.eltype(::Type{FullFactorialRows}) = Vector{Int}

function Base.iterate(rows::FullFactorialRows, state = nothing)
    if state === nothing
        any(<(1), rows.arity) && return nothing
        state = ones(Int, length(rows.arity))
    else
        _advance!(state, rows.arity) || return nothing
    end
    return copy(state), state
end

# Append to `kept` each candidate row that no rule forbids and that is not in
# `seen`; return how many candidates no rule forbids. One row buffer is
# stepped in place, so a rejected candidate is never stored.
function _accept_rows!(kept::Vector{Int}, request::Request, seen::Set{Vector{Int}})
    arity = request.arity
    n = length(arity)
    row = ones(Int, n)
    idx = zeros(Int, n)
    accepted = 0
    while true
        for i in 1:n
            idx[i] = request.candidates[i][row[i]]
        end
        if !violates(request.feasibility, idx)
            accepted += 1
            (isempty(seen) || !(row in seen)) && append!(kept, row)
        end
        _advance!(row, arity) || break
    end
    return accepted
end

# Append to `kept` each negative candidate row (one invalid value, ordinary
# values elsewhere) that its applicable rules allow and that is not in `seen`;
# return how many its rules allow. For each parameter `p`, in order, and each
# invalid value of `p`, in domain order, the other parameters run through
# their ordinary values, the last fastest, under the negative-row search of
# that value, which omits every rule that reads `p` (§5.5).
function _accept_negative_rows!(kept::Vector{Int}, request::Request, seen::Set{Vector{Int}})
    arity = request.arity
    n = length(arity)
    idx = zeros(Int, n)
    accepted = 0
    for p in 1:n, position in (arity[p] + 1):length(request.candidates[p])
        widths = copy(arity)
        widths[p] = 1
        odometer = ones(Int, n)
        t = zeros(Int, n)
        t[p] = request.candidates[p][position]
        f, _ = feasibility_for(request.context, t)
        while true
            for i in 1:n
                idx[i] = i == p ? request.candidates[p][position] : request.candidates[i][odometer[i]]
            end
            if !violates(f, idx)
                accepted += 1
                row = copy(odometer)
                row[p] = position
                (isempty(seen) || !(row in seen)) && append!(kept, row)
            end
            _advance!(odometer, widths) || break
        end
    end
    return accepted
end

"""
    check_full_factorial_limit(space, limit) -> BigInt

The number of candidate rows of a full factorial of `space` (contract §7.3):
the product of the parameters' ordinary value counts, plus, for each
parameter, its number of `Invalid` values times the product of the other
parameters' ordinary value counts. Multiple-invalid rows are no candidates
(§5.7). It is counted as a `BigInt`, so it never overflows. A count above
`limit` throws the `ResourceLimitError` that gives the count, split into
ordinary and negative candidates when the space has `Invalid` values, and
the keyword `limit`. `limit` is checked first: a positive integer within
`Int`. `full_factorial` calls this before it builds the request, so the
refusal comes before any must-include search; `generate_full_factorial` calls
it again for callers that build the request themselves.
"""
function check_full_factorial_limit(space::TestSpace, limit)
    limit = _check_integer(:limit, limit, 1, "§7.3")
    ordinary = [big(length(ordinary_indices(space, i))) for i in eachindex(space.names)]
    count = prod(ordinary; init = big(1))
    negative = big(0)
    for p in eachindex(ordinary)
        others = prod((ordinary[q] for q in eachindex(ordinary) if q != p); init = big(1))
        negative += length(invalid_indices(space, p)) * others
    end
    candidates = count + negative
    if candidates > limit
        split = negative == 0 ? "" :
            " ($(_grouped(count)) ordinary and $(_grouped(negative)) with one Invalid value)"
        throw(ResourceLimitError(
            "enumerating a full factorial of $(_grouped(candidates)) candidate rows$split", limit, :limit))
    end
    return candidates
end

"""
    generate_full_factorial(request; limit = 10^6) -> Design

The must-include rows, in the order given with duplicates kept (contract
§10.5), then every other valid row of the request's space once (§7.2): the
valid ordinary rows, then the valid negative rows, for each parameter in
order and each of its invalid values in domain order; a valid row equal to
a must-include row is not repeated, and no row holds two invalid values.
Before enumerating, a candidate count above `limit` throws
`ResourceLimitError` giving the count and the keyword `limit` (§7.3,
`check_full_factorial_limit`). Candidates are enumerated one at a time, the
last parameter fastest, and only valid rows are kept (§7.4). `notes` reports
`candidates` (ordinary and single-invalid) and `accepted` (the valid rows
found, ordinary and negative) separately. A partial must-include row is
completed by its feasibility witness, as a negative row when it holds an
`Invalid` (§7.9).
"""
function generate_full_factorial(request::Request; limit = 10^6)
    n = length(request.arity)
    candidates = check_full_factorial_limit(request.space, limit)
    must = Vector{Int}[]
    for s in axes(request.must_include, 2)
        row = request.must_include[:, s]
        any(==(0), row) && (row = witness(request, row))
        push!(must, row)
    end
    seen = Set(must)
    kept = reduce(vcat, must; init = Int[])
    accepted = _accept_rows!(kept, request, seen)
    accepted += _accept_negative_rows!(kept, request, seen)
    matrix = reshape(kept, n, :)
    validate_design(request, matrix, Vector{Int}[]; strategy = :full_factorial)
    # Completeness (plan Phase 3 step 6): the distinct rows are the accepted rows.
    distinct = size(matrix, 2) - length(must) + length(seen)
    distinct == accepted || error(
        "internal error: the full factorial has $distinct distinct valid cases, but $accepted were accepted")
    return Design(matrix, :full_factorial, :FullFactorial, nothing, 0, 0, Excluded[],
                  n_must_include(request), (candidates = Int(candidates), accepted = accepted))
end
