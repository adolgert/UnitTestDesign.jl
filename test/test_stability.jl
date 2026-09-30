using Test
using TestItemRunner

# Guards on the type stability of the feasibility search's hot paths: a rule
# check (`forbids(f, k, partial)`, and `_violates` over every table) that finds
# its verdict in a tabulated table or in the memo allocates nothing, and the
# one dynamic call a check may make, a lazy rule's evaluation on a memo miss,
# lands in code that allocates nothing beyond what the predicate allocates,
# when the domains' element types are concrete. The search's entry points
# infer concrete return types. Allocation counts differ between Julia
# versions, so these tests assert zero only where zero is the design.

@testsnippet StabilitySetup begin
    using UnitTestDesign: Feasibility, forbids, _violates, _candidates
    using Base.CoreLogging: with_logger, NullLogger

    # Every domain has a concrete element type and no predicate allocates, so
    # a check allocates nothing anywhere. With tabulation_limit = 12, rule 1
    # (9 combinations) is tabulated, rule 2 (18) is lazy, and rule 3 is a
    # whole-case rule, always lazy.
    stability_space() = with_logger(NullLogger()) do
        TestSpace((a = [1, 2, 3], b = [:x, :y, :z], c = [true, false], d = 1:3, e = [:p, :q]);
            constraints = [forbid((a = 1, b = :y)),
                           forbid((a, d, e) -> a == 2 && d == 1 && e == :q, :a, :d, :e),
                           forbid(row -> row.a == 3 && row.e == :p)],
            tabulation_limit = 12)
    end

    "Bytes allocated by `g(args...)`, after a first call has compiled it and filled any memo."
    function allocated(g, args...)
        g(args...)
        return @allocated g(args...)
    end
end


@testitem "stability: a rule check allocates nothing" setup=[StabilitySetup] begin
    space = stability_space()
    @test space.tables[1].lazy === nothing
    @test space.tables[2].lazy !== nothing && length(space.tables[3].scope) == 5
    f = Feasibility(_candidates(space, 0, 0), space.tables)
    key = [2, 1, 1, 2, 2]   # (a = 2, b = :x, c = true, d = 2, e = :q): no rule forbids it
    # A tabulated table, then a scoped lazy one and a whole-case one, whose
    # verdicts the second call reads from the memo.
    @test allocated(forbids, f, 1, key) == 0
    @test allocated(forbids, f, 2, key) == 0
    @test allocated(forbids, f, 3, key) == 0
    # The direct check reads every table.
    @test allocated(_violates, f, key) == 0
    @test !_violates(f, key) && f.stats.evaluations > 0
end


@testitem "stability: a lazy rule's evaluation allocates only what its predicate does" setup=[StabilitySetup] begin
    # A memo miss calls the table's `lazy` function: for a space's rule, a
    # `_LazyRule`, whose evaluation is concrete when the domains' element
    # types are. These predicates allocate nothing, so neither does the
    # evaluation.
    space = stability_space()
    scoped, whole = space.tables[2].lazy, space.tables[3].lazy
    @test allocated(scoped, [2, 1, 2]) == 0
    @test allocated(whole, [3, 1, 1, 2, 1]) == 0
    @test scoped([2, 1, 2]) && !scoped([2, 2, 2]) && whole([3, 1, 1, 2, 1])
end


@testitem "stability: the search's entry points infer their return types" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, TargetList, IndexExplanation, dead, explain_partial, _status, _completable
    space = stability_space()
    request = Request(space; strength = 2)
    f = request.feasibility
    key = [2, 0, 0, 1, 0]
    @test (@inferred forbids(f, 1, [1, 2, 0, 0, 0])) isa Bool
    @test (@inferred forbids(f, 3, [3, 1, 1, 1, 1])) isa Bool
    @test (@inferred _violates(f, key)) isa Bool
    @test (@inferred dead(f, key)) isa Bool
    @test (@inferred dead(request, [1, 0, 0, 0, 0])) isa Bool
    @test (@inferred _status(f, key)) isa Symbol
    @test (@inferred explain_partial(f, key)) isa IndexExplanation
    @test (@inferred Union{Tuple{Symbol, Vector{Int}}, Tuple{Symbol, Nothing}} _completable(f, key, 100)) isa Tuple
    @test (@inferred TargetList(request)[3]) isa Vector{Int}
end
