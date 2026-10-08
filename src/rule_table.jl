# The index-space form of one rule. This is the boundary between the model
# (space.jl, constraints.jl: names, values, predicates) and the feasibility
# search (feasibility.jl: integers only). Both sides are written against
# this file, so its fields and the two functions below are fixed.
#
# A RuleTable never sees a value or a name. Parameters are 1-based indices
# into the space's parameter list and values are 1-based indices into that
# parameter's domain. A partial assignment is a Vector{Int} with 0 for
# "unset"; a table is consulted only when every parameter in its scope is
# nonzero (contract §1.6, §12.14).

"""
    RuleTable(scope, forbidden::AbstractSet)
    RuleTable(scope, lazy::Function)

`scope::Vector{Int}` lists the parameter indices the rule reads, in the
order the predicate expects them. A table is tabulated or lazy, and `lazy`
is `nothing` exactly when it is tabulated.

A tabulated table is built from the set of value-index tuples (in scope
order) that the rule forbids, and keeps one bit for each tuple of the
smallest box that holds them all, so that a check is arithmetic and one bit
test however long the scope. At scope position `j` the box spans the indices
`low[j]` to `low[j] + radix[j] - 1`, the smallest and largest among the
forbidden tuples, and `forbidden[c + 1]` is set when the tuple whose code is
`c` is forbidden. The code reads a tuple's offsets into the box, `index -
low[j]`, as a number whose first digit varies fastest, digit `j` in radix
`radix[j]`, the order of `_code` (space.jl). A tuple outside the box is
allowed. The box holds at most the product of the scope's domain lengths
(value indices count `Invalid` values), and a space tabulates a rule only
when its scope has at most `tabulation_limit` combinations of ordinary values
(`_tabulate`): at the default of `10^5`, with no `Invalid` value in the scope,
a table holds at most 12.5 KB of bits. The table of a single tuple, such as
the isolation tables of `followups`, holds one bit.

A lazy table is a function `lazy` from the scope's value indices, a
`Vector{Int}` in scope order, to `Bool` (`true` = forbidden); `low`, `radix`
and `forbidden` are empty. The vector may be a memo's scratch key, rewritten
by the next check, so `lazy` must not keep it. A whole-case rule has
`scope == 1:arity` and is always lazy (contract §12.20). `lazy` is the one
field whose type is not concrete, so evaluating a lazy rule is one dynamic
call; a space's lazy rules are `_LazyRule`s (constraints.jl), whose
evaluation is concrete behind it.

A table holds no state that an operation changes: `lazy` evaluates the
predicate each time it is called. The memo of a lazy rule's verdicts
belongs to the operation's `Feasibility` (feasibility.jl, contract §3.5,
§12.19), so a `TestSpace` retains nothing from any operation.
"""
struct RuleTable
    scope::Vector{Int}
    low::Vector{Int}
    radix::Vector{Int}
    forbidden::BitVector
    lazy::Union{Nothing, Function}
    function RuleTable(scope, low::Vector{Int}, radix::Vector{Int}, forbidden::BitVector, lazy)
        if lazy === nothing
            length(low) == length(radix) == length(scope) && length(forbidden) == prod(radix) ||
                throw(ArgumentError(
                    "a tabulated RuleTable has a box extent per scope position and one bit per code"))
        else
            isempty(low) && isempty(radix) && isempty(forbidden) || throw(ArgumentError(
                "a lazy RuleTable has no forbidden bits"))
        end
        new(collect(Int, scope), low, radix, forbidden, lazy)
    end
end

function RuleTable(scope, forbidden::AbstractSet)
    n = length(scope)
    for key in forbidden
        length(key) == n && all(>=(1), key) || throw(ArgumentError(
            "a forbidden tuple has one value index, at least 1, per scope position; got $(repr(key))"))
    end
    low = Int[isempty(forbidden) ? 1 : minimum(key -> key[j], forbidden) for j in 1:n]
    radix = Int[isempty(forbidden) ? 0 : maximum(key -> key[j], forbidden) - low[j] + 1 for j in 1:n]
    bits = falses(foldl(Base.checked_mul, radix; init = 1))
    for key in forbidden
        code, stride = 0, 1
        for j in 1:n
            code += (key[j] - low[j]) * stride
            stride *= radix[j]
        end
        bits[code + 1] = true
    end
    return RuleTable(scope, low, radix, bits, nothing)
end

RuleTable(scope, lazy::Function) = RuleTable(scope, Int[], Int[], falses(0), lazy)

"""
    forbidden_tuples(table) -> Union{Nothing, Set}

The value-index tuples, in scope order, that a tabulated table forbids, as
the `Set` it was built from; `nothing` for a lazy table. For tests and
inspection: the search reads the bits.
"""
function forbidden_tuples(table::RuleTable)
    table.lazy === nothing || return nothing
    n = length(table.scope)
    tuples = Set{NTuple{n, Int}}()
    offsets = zeros(Int, n)
    for c in findall(table.forbidden)
        _decode!(offsets, c - 1, collect(1:n), table.radix)
        push!(tuples, Tuple(offsets .+ table.low .- 1))
    end
    return tuples
end

"""
    assigned(table, partial) -> Bool

True when every parameter in the table's scope is set (nonzero) in
`partial`.
"""
assigned(table::RuleTable, partial::AbstractVector{<:Integer}) =
    all(i -> partial[i] != 0, table.scope)

"""
    forbids(table, partial) -> Bool

True when the rule forbids the values assigned in `partial`. Must only be
called when `assigned(table, partial)` holds; the scoped values are read
from `partial` in scope order. A lazy table is evaluated without a memo;
searches ask `forbids(f::Feasibility, t, partial)`, which memoizes lazy
verdicts for the operation.
"""
function forbids(table::RuleTable, partial::AbstractVector{<:Integer})
    table.lazy === nothing && return _forbidden_bit(table, partial)
    return table.lazy(Int[partial[p] for p in table.scope])::Bool
end

"A tabulated table's verdict on `partial`: its bit for the scoped values, `false` outside its box."
function _forbidden_bit(table::RuleTable, partial::AbstractVector{<:Integer})
    low, radix = table.low, table.radix
    code, stride = 0, 1
    for (j, p) in enumerate(table.scope)
        offset = Int(partial[p]) - low[j]
        0 <= offset < radix[j] || return false
        code += offset * stride
        stride *= radix[j]
    end
    return table.forbidden[code + 1]
end
