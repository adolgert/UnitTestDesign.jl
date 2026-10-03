# The adapter from the checker's inputs to the production model.
#
# Plan Phase 2, step 8. Fixtures (fixtures.jl) and random problems
# (random_problems.jl) are written for the independent checker (checker.jl),
# which shares no code with src/. This file turns the same inputs into a
# production `TestSpace`, so a test can ask the model and the oracle the same
# question. It is the only file in the `Checker` module that loads
# UnitTestDesign; checker.jl stays independent of it.
#
# Mapping:
#   CheckInvalid(x)              -> Invalid(x)
#   CheckPartition(name)         -> Partition(name, Returns(name))
#   rule (scope, predicate)      -> forbid(predicate, scope...), a listed-names
#                                   rule; the checker's predicate is true for a
#                                   forbidden combination, as forbid's is.
#   rule whose scope names every -> forbid(case -> predicate(case[s] for s in scope...)),
#   parameter                       a whole-case rule, as the checker defines
#                                   it (checker.jl, INPUT FORMAT). Its values
#                                   reach the predicate in the checker's scope
#                                   order.
# Parameter names, domain order and rule order are kept, so value index k of
# parameter p is the same value on both sides and rule k is rule k.
#
# This file expects the names from checker.jl, random_problems.jl and
# fixtures.jl in scope; the `Checker` test module in test_checker.jl includes
# all four.

using UnitTestDesign: UnitTestDesign, TestSpace, Invalid, Partition, forbid

export test_space, model_value, model_rows, checker_row

"The production value for a checker domain value."
model_value(x::CheckInvalid) = Invalid(model_value(x.value))
model_value(x::CheckPartition) = Partition(x.name, Returns(x.name))
model_value(x) = x

"The production rule for a checker rule over the parameters `names`."
function model_rule(names, (scope, predicate))
    scope = scope isa Symbol ? (scope,) : Tuple(scope)
    if length(scope) == length(names) && issetequal(scope, names)
        return forbid(case -> predicate((case[s] for s in scope)...))
    end
    return forbid(predicate, scope...)
end

"""
    test_space(fixture::Fixture; kwargs...)
    test_space(space::CheckSpace; kwargs...)
    test_space(input::NamedTuple; kwargs...)

A production `TestSpace` for a fixture, a checker space (such as a random
problem's `problem.space`), or an input `(names, domains, rules)`. Keywords go
to `TestSpace`. Inputs the model rejects throw its `ArgumentError`.
"""
function test_space(input::NamedTuple; kwargs...)
    rules = [model_rule(input.names, r) for r in input.rules]
    domains = [Any[model_value(x) for x in d] for d in input.domains]
    return TestSpace(Pair.(input.names, domains)...; constraints = rules, kwargs...)
end
test_space(f::Fixture; kwargs...) = test_space(f.input; kwargs...)
test_space(cs::CheckSpace; kwargs...) =
    test_space((names = cs.names, domains = cs.domains, rules = cs.rules); kwargs...)

"""
    model_rows(space::TestSpace) -> (; ordinary, negative)

The valid ordinary and negative rows of a production space, by brute force
over its RuleTables, as sorted index vectors (the checker's order).
"""
function model_rows(space::TestSpace)
    ordinary, negative = Vector{Int}[], Vector{Int}[]
    for key in Iterators.product((eachindex(v) for v in space.values)...)
        row = collect(key)
        bad = [p for p in eachindex(row) if row[p] in UnitTestDesign.invalid_indices(space, p)]
        length(bad) > 1 && continue
        p = isempty(bad) ? 0 : only(bad)
        tables = UnitTestDesign.active_tables(space, p)
        any(t -> UnitTestDesign.forbids(t, row), tables) && continue
        push!(p == 0 ? ordinary : negative, row)
    end
    return (ordinary = sort!(ordinary), negative = sort!(negative))
end

"An index row read back as checker values, to compare with `valid_rows`."
checker_row(cs::CheckSpace, row) =
    NamedTuple{Tuple(cs.names)}(Tuple(cs.domains[p][row[p]] for p in eachindex(row)))
