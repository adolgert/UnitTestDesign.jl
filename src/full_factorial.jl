# Full factorial: every valid row (plan Phase 3 step 5; contract §7.2–§7.4).
#
# The candidate count is checked against `limit` before anything is
# enumerated (§7.3). Candidates are then visited one at a time, in the 0.4
# order (the last parameter varies fastest), and only the rows that pass
# every rule are kept (§7.4); a rejected row is never stored. The result is a
# materialized matrix. Phase 6 adds the single-invalid products to the count.

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

"""
    generate_full_factorial(request; limit = 10^6) -> Design

Every valid row of the request's space, once, after the must-include rows
(contract §7.2, §10.5); a valid row equal to a must-include row is not
repeated. Before enumerating, a candidate product above `limit` throws
`ResourceLimitError` giving the count and the keyword `limit` (§7.3).
Candidates are enumerated one at a time, the last parameter fastest, and
only valid rows are kept (§7.4). `notes` reports `candidates` (the product)
and `accepted` (the valid rows found) separately. A partial must-include
row is completed by its feasibility witness.
"""
function generate_full_factorial(request::Request; limit::Integer = 10^6)
    limit >= 1 || throw(ArgumentError("limit must be a positive Int, got $limit"))
    arity = request.arity
    n = length(arity)
    candidates = prod(BigInt, arity)
    candidates > limit && throw(ResourceLimitError(
        "enumerating a full factorial of $(_grouped(candidates)) candidate rows", Int(limit), :limit))
    must = Vector{Int}[]
    for s in axes(request.must_include, 2)
        row = request.must_include[:, s]
        any(==(0), row) && (row = witness(request, row))
        push!(must, row)
    end
    seen = Set(must)
    kept = reduce(vcat, must; init = Int[])
    accepted = _accept_rows!(kept, request, seen)
    matrix = reshape(kept, n, :)
    validate_design(request, matrix, Vector{Int}[]; strategy = :full_factorial)
    # Completeness (plan Phase 3 step 6): the distinct rows are the accepted rows.
    distinct = size(matrix, 2) - length(must) + length(seen)
    distinct == accepted || error(
        "internal error: the full factorial has $distinct distinct valid cases, but $accepted were accepted")
    return Design(matrix, :full_factorial, :FullFactorial, nothing, 0, 0, Excluded[],
                  n_must_include(request), (candidates = Int(candidates), accepted = accepted))
end
