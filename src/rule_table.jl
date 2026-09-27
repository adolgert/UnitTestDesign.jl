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
    RuleTable(scope, forbidden, lazy)

`scope::Vector{Int}` lists the parameter indices the rule reads, in the
order the predicate expects them. `forbidden` is either a
`Set{NTuple{N,Int}}` of value-index tuples (in scope order) that the rule
forbids, when the rule was tabulated, or `nothing` when it is evaluated
lazily. `lazy` is then a function from an `NTuple{N,Int}` of value indices
to `Bool` (`true` = forbidden), already memoized by the model layer; it is
`nothing` when the rule was tabulated. Exactly one of `forbidden` and
`lazy` is `nothing`. A whole-case rule has `scope == 1:arity` and is
always lazy (contract §12.20).
"""
struct RuleTable
    scope::Vector{Int}
    forbidden::Union{Nothing, Set}
    lazy::Union{Nothing, Function}
    function RuleTable(scope, forbidden, lazy)
        (forbidden === nothing) == (lazy === nothing) &&
            throw(ArgumentError("a RuleTable is either tabulated or lazy"))
        new(collect(Int, scope), forbidden, lazy)
    end
end

RuleTable(scope, forbidden::Set) = RuleTable(scope, forbidden, nothing)
RuleTable(scope, lazy::Function) = RuleTable(scope, nothing, lazy)

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
from `partial` in scope order.
"""
function forbids(table::RuleTable, partial::AbstractVector{<:Integer})
    key = ntuple(k -> Int(partial[table.scope[k]]), length(table.scope))
    if table.forbidden !== nothing
        return key in table.forbidden
    else
        return table.lazy(key)::Bool
    end
end
