using Test
using TestItemRunner

# Guards on the type stability of the feasibility search's hot paths: a rule
# check (`forbids(f, k, partial)`, and `_violates` over every table) that finds
# its verdict in a tabulated table or in the memo allocates nothing, and the
# one dynamic call a check may make, a lazy rule's evaluation on a memo miss,
# lands in code that allocates nothing beyond what the predicate allocates,
# when the domains' element types are concrete. The search's entry points
# infer concrete return types. Translating to the caller's vocabulary reads
# values with their domains' types: a result's rows behind one barrier, and a
# measurement's listed targets through one reading per support. Allocation
# counts differ between Julia versions, so these tests assert zero only where
# zero is the design, and bound the rest between the counts before and after
# the change they guard, measured on Julia 1.10 and 1.13.

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


@testitem "stability: a result's rows are read with their domains' types" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, TestCases, generate_full_factorial, row_type, _cases, _pick
    # Eight domains of eight types, more than a tuple built by ntuple or map
    # is inferred for.
    space = TestSpace((a = 1:4, b = [:w, :x, :y, :z], c = [true, false], d = [1.0, 2.0, 3.0],
                       e = ["p", "q", "r"], f = Int32[1, 2, 3, 4], g = ['a', 'b'], h = UInt8[1, 2]);
                      constraints = [forbid((a = 1, b = :y)), forbid((c, d) -> c && d == 2.0, :c, :d)])
    domains = (space.values...,)
    @test (@inferred _pick(domains, (2, 1, 1, 3, 2, 4, 1, 2))) === (2, :w, true, 3.0, "q", Int32(4), 'a', 0x02)
    request = Request(space)
    design = generate_full_factorial(request)
    n = size(design.matrix, 2)
    T = row_type(space, false)
    # The rows take their vector and nothing more.
    @test allocated(_cases, T, domains, request.candidates, design.matrix) <=
          allocated(k -> Vector{T}(undef, k), n) + 1024
    # The result takes about 55 bytes a row; reading each row with
    # from_indices took 1.3 KB.
    @test allocated(TestCases, request, design) <= 2 * sizeof(T) * n
    # A full factorial takes about 470 bytes a row, generation included; 1.9 KB before.
    @test allocated(full_factorial, space) <= 1000 * n
end


@testitem "stability: a measurement names a support's targets with one reading" setup=[StabilitySetup] begin
    using UnitTestDesign: _Named, _values, from_indices
    space = stability_space()
    t = [2, 0, 1, 0, 2]
    named = _Named(space, [1, 3, 5])
    @test named(t) === from_indices(space, t) === (a = 2, c = true, e = :q)
    @test (@inferred _values(named, t)) === (2, true, :q)
    # A measurement holds the _Named of a support as an abstract type, so
    # naming a target is one dynamic call, which allocates the NamedTuple:
    # 64 bytes, where from_indices took 544.
    @test allocated(n -> n[](t), Ref{Any}(named)) <= 128
    # coverage of no rows lists every target as missing: about 780 bytes a
    # target on Julia 1.13 and 930 on 1.10, where naming each with
    # from_indices took 1.2 KB and 1.5 KB.
    wide = TestSpace(NamedTuple{Tuple(Symbol(:x, i) for i in 1:8)}(Tuple(1:4 for _ in 1:8)))
    listed = length(coverage(NamedTuple[], wide; strength = 2).ordinary.missing)
    @test listed == 28 * 16
    @test allocated(s -> coverage(NamedTuple[], s; strength = 2), wide) <= 1100 * listed
end



@testitem "stability: a row is read with one lookup per value" setup=[StabilitySetup] begin
    using UnitTestDesign: value_index, case_indices, _row_indices
    # Eight types, more than inference splits a loop over the row's fields into.
    space = TestSpace((a = 1:4, b = [:w, :x, :y, :z], c = [true, false], d = [1.0, 2.0, 3.0],
                       e = ["p", "q", "r"], f = Int32[1, 2, 3, 4], g = ['a', 'b'], h = UInt8[1, 2]))
    row = (a = 2, b = :x, c = false, d = 2.0, e = "q", f = Int32(3), g = 'b', h = 0x01)
    @test (@inferred value_index(space, 5, "q")) == 2
    @test (@inferred case_indices(space, row)) == [2, 2, 2, 2, 2, 3, 2, 1]
    # Reading a row allocates its index vector, 128 bytes, and nothing per
    # value. Before, case_indices took 608 bytes for this row, and
    # _row_indices 736 to 1104.
    vector = allocated(n -> zeros(Int, n), 8)
    @test allocated(case_indices, space, row) <= vector
    @test allocated(case_indices, space, Tuple(row)) <= vector
    @test allocated((s, r) -> _row_indices(s, r; what = "row", complete = true), space, row) <= vector
    @test allocated((s, r) -> _row_indices(s, r; what = "row", complete = true), space, Tuple(row)) <= vector
end
