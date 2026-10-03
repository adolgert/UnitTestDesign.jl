using Test
using TestItemRunner

# Full factorial (plan Phase 3 step 5, Phase 4 step 5; contract §7.2–§7.4):
# `full_factorial(input...; limit, must_include)`, which returns a TestCases.


@testitem "full factorial: unconstrained is the full product, last parameter fastest" setup=[IndexCoverage] begin
    space = TestSpace((a = [1, 2], b = [:x, :y, :z], c = [true, false]))
    cases = full_factorial(space)
    @test length(cases) == 12
    @test Set(cases) == Set(NamedTuple{(:a, :b, :c)}(t) for t in Iterators.product([1, 2], [:x, :y, :z], [true, false]))
    # The 0.4 order.
    @test cases[1:4] == [(a = 1, b = :x, c = true), (a = 1, b = :x, c = false),
                         (a = 1, b = :y, c = true), (a = 1, b = :y, c = false)]
    @test cases.notes == (candidates = 12, accepted = 12)
    @test (cases.strategy, cases.engine, cases.seed, cases.n_must_include) == (:full_factorial, :FullFactorial, nothing, 0)
    @test (cases.required, cases.covered, isempty(cases.excluded)) == (0, 0, true)
    # The same space as a NamedTuple, as pairs, and positionally.
    @test collect(full_factorial((a = [1, 2], b = [:x, :y, :z], c = [true, false]))) == collect(cases)
    @test collect(full_factorial(:a => [1, 2], :b => [:x, :y, :z], :c => [true, false])) == collect(cases)
    positional = full_factorial([1, 2], [:x, :y, :z], [true, false])
    @test positional isa TestCases{Tuple{Int, Symbol, Bool}}
    @test collect(positional) == [Tuple(c) for c in cases]
    # The iterator is lazy and in the same order.
    rows = collect(UnitTestDesign.full_factorial_rows([2, 3, 2]))
    @test rows[1:3] == [[1, 1, 1], [1, 1, 2], [1, 2, 1]]
    # Iterators.product varies its first range fastest, so reverse the ranges and each tuple.
    @test rows == vec([collect(reverse(t)) for t in Iterators.product(1:2, 1:3, 1:2)])
    @test length(collect(UnitTestDesign.full_factorial_rows([2, 5, 4, 3]))) == 120
    @test isempty(collect(UnitTestDesign.full_factorial_rows([2, 0, 3])))
    # 0.4: five parameters, and four with ranges.
    cases = full_factorial((1:k for k in [2, 3, 4, 2, 2])...)
    @test length(cases) == 96 && allunique(cases)
    @test test_coverage(reduce(hcat, [collect(c) for c in cases]), [2, 3, 4, 2, 2], 5).finish == 0
    @test length(full_factorial([1:2, 1:2, 1:3, 1:2]...)) == 24
    @test collect(full_factorial([1])) == [(1,)]
end


@testitem "full factorial: constrained equals the checker's valid rows" setup=[Checker] begin
    for f in (astra_chain, fable_solver, opus_gpu, disconnected_witness, whole_case_connects,
              dead_end_pairwise_1, dead_end_pairwise_2, dead_end_threeway_1, dead_end_threeway_2,
              overlapping_groups)
        cases = full_factorial(test_space(f))
        valid = valid_rows(f.space)
        @test length(cases) == length(valid)
        @test Set(cases) == Set(valid)
        @test cases.notes == (candidates = prod(length.(f.input.domains)), accepted = length(valid))
        @test isempty(check_design(collect(cases), f.space).ordinary.rejected)
    end
    # 0.4: the rule x3 == 4 && x5 == 1 removes 2·3·2 rows.
    space = TestSpace((Symbol(:p, i) => 1:k for (i, k) in enumerate([2, 3, 4, 2, 2]))...;
                      constraints = [forbid((p3 = 4, p5 = 1))])
    cases = full_factorial(space)
    @test length(cases) == 96 - 12
    @test cases.notes == (candidates = 96, accepted = 84)
    # Named domains with constraints build the space.
    cases = full_factorial((a = [1, 2, 3], b = [7, 8], c = [true, false]);
                           constraints = [forbid((b, c) -> b == 7 && c == false, :b, :c)])
    @test length(cases) == 9 && all(r -> !(r.b == 7 && !r.c), cases)
    # An empty space: no rows, every candidate rejected.
    cases = full_factorial(test_space(disconnected_unsat))
    @test isempty(cases)
    @test cases.notes == (candidates = 12, accepted = 0)
end


@testitem "full factorial: bench12, 207360 of 331776" setup=[Checker] begin
    cases = full_factorial(test_space(bench12))
    @test cases.notes == (candidates = 331776, accepted = 207360)
    @test length(cases) == 207360
    @test allunique(cases)
    valid = Set(valid_rows(bench12.space))
    @test all(in(valid), cases)
end


@testitem "full factorial: the limit refuses before enumerating (§7.3)" begin
    # A lazy whole-case rule records each row it sees; the limit stops before any.
    seen = Ref(0)
    space = TestSpace((Symbol(:p, i) => [1, 2] for i in 1:21)...;
                      constraints = [forbid(case -> (seen[] += 1; false))])
    @test_throws ResourceLimitError full_factorial(space)
    err = try full_factorial(space) catch e; e end
    @test err.keyword == :limit
    @test err.limit == 10^6
    message = sprint(showerror, err)
    @test occursin("2_097_152 candidate rows", message)
    @test occursin("`limit = 1_000_000`", message)
    @test seen[] == 0
    # A small limit on a small space.
    small = TestSpace((a = [1, 2], b = [:x, :y, :z], c = [true, false]))
    err = try full_factorial(small; limit = 5) catch e; e end
    @test err isa ResourceLimitError
    @test occursin("12 candidate rows", sprint(showerror, err))
    @test length(full_factorial(small; limit = 12)) == 12
    @test_throws ArgumentError full_factorial(small; limit = 0)
    @test_throws ArgumentError full_factorial(small; limit = 1.5e6)
    # The count is exact beyond Int.
    err = try full_factorial(fill(1:10, 20)...) catch e; e end
    @test occursin("100_000_000_000_000_000_000 candidate rows", sprint(showerror, err))
end


@testitem "full factorial: must-include rows first, not repeated" setup=[Checker] begin
    space = test_space(fable_solver)
    seeds = [(mode = :exact, solver = :qr, tol = 1e-6), (solver = :lu,), (mode = :exact, solver = :qr, tol = 1e-6)]
    cases = full_factorial(space; must_include = seeds)
    @test cases.n_must_include == 3
    @test cases[1:3] == [seeds[1], (mode = :exact, solver = :lu, tol = 1e-6), seeds[1]]
    # The other three valid rows follow, once each.
    @test length(cases) == 3 + 3
    @test Set(cases) == Set(valid_rows(fable_solver.space))
    @test cases.notes == (candidates = 12, accepted = 5)
    # Positional must-include rows are complete.
    cases = full_factorial([1, 2], [:a, :b]; must_include = [[2, :b]])
    @test collect(cases) == [(2, :b), (1, :a), (1, :b), (2, :a)]
end
