using Test
using TestItemRunner

# Full factorial through the internal Request (plan Phase 3 step 5; contract
# §7.2–§7.4).


@testitem "full factorial: unconstrained is the full product, last parameter fastest" begin
    using UnitTestDesign: Request, generate_full_factorial, to_cases
    space = TestSpace((a = [1, 2], b = [:x, :y, :z], c = [true, false]))
    request = Request(space)
    design = generate_full_factorial(request)
    cases = to_cases(request, design.matrix)
    @test length(cases) == 12
    @test Set(cases) == Set(NamedTuple{(:a, :b, :c)}(t) for t in Iterators.product([1, 2], [:x, :y, :z], [true, false]))
    # The 0.4 order.
    @test cases[1:4] == [(a = 1, b = :x, c = true), (a = 1, b = :x, c = false),
                         (a = 1, b = :y, c = true), (a = 1, b = :y, c = false)]
    @test design.notes == (candidates = 12, accepted = 12)
    @test (design.strategy, design.engine, design.seed, design.n_must_include) ==
          (:full_factorial, :FullFactorial, nothing, 0)
    @test (design.required, design.covered, isempty(design.excluded)) == (0, 0, true)
    # The iterator is lazy and in the same order.
    rows = collect(UnitTestDesign.full_factorial_rows([2, 3, 2]))
    @test rows[1:3] == [[1, 1, 1], [1, 1, 2], [1, 2, 1]]
    # Iterators.product varies its first range fastest, so reverse the ranges and each tuple.
    @test rows == vec([collect(reverse(t)) for t in Iterators.product(1:2, 1:3, 1:2)])
    @test length(collect(UnitTestDesign.full_factorial_rows([2, 5, 4, 3]))) == 120
    @test isempty(collect(UnitTestDesign.full_factorial_rows([2, 0, 3])))
    # 0.4: five parameters.
    space = TestSpace((Symbol(:p, i) => 1:k for (i, k) in enumerate([2, 3, 4, 2, 2]))...)
    design = generate_full_factorial(Request(space))
    @test size(design.matrix, 2) == 96
    @test UnitTestDesign.test_coverage(design.matrix, [2, 3, 4, 2, 2], 5).finish == 0
end


@testitem "full factorial: constrained equals the checker's valid rows" setup=[Checker] begin
    using UnitTestDesign: Request, generate_full_factorial, to_cases
    for f in (astra_chain, fable_solver, opus_gpu, disconnected_witness, whole_case_connects,
              dead_end_pairwise_1, dead_end_pairwise_2, dead_end_threeway_1, dead_end_threeway_2,
              overlapping_groups)
        request = Request(test_space(f))
        design = generate_full_factorial(request)
        cases = to_cases(request, design.matrix)
        valid = valid_rows(f.space)
        @test length(cases) == length(valid)
        @test Set(cases) == Set(valid)
        @test design.notes == (candidates = prod(length.(f.input.domains)), accepted = length(valid))
        @test isempty(check_design(cases, f.space).ordinary.rejected)
    end
    # 0.4: the rule x3 == 4 && x5 == 1 removes 2·3·2 rows.
    space = TestSpace((Symbol(:p, i) => 1:k for (i, k) in enumerate([2, 3, 4, 2, 2]))...;
                      constraints = [forbid((p3 = 4, p5 = 1))])
    design = generate_full_factorial(Request(space))
    @test size(design.matrix, 2) == 96 - 12
    @test design.notes == (candidates = 96, accepted = 84)
    # An empty space: no rows, every candidate rejected.
    design = generate_full_factorial(Request(test_space(disconnected_unsat)))
    @test size(design.matrix) == (3, 0)
    @test design.notes == (candidates = 12, accepted = 0)
end


@testitem "full factorial: bench12, 207360 of 331776" setup=[Checker] begin
    using UnitTestDesign: Request, generate_full_factorial
    request = Request(test_space(bench12))
    design = generate_full_factorial(request)
    @test design.notes == (candidates = 331776, accepted = 207360)
    @test size(design.matrix, 2) == 207360
    @test allunique(eachcol(design.matrix))
    valid = Set(collect(Tuple(r)) for r in valid_rows(bench12.space))
    @test all(j -> design.matrix[:, j] in valid, axes(design.matrix, 2))
end


@testitem "full factorial: the limit refuses before enumerating (§7.3)" begin
    using UnitTestDesign: Request, generate_full_factorial, ResourceLimitError
    # A lazy whole-case rule records each row it sees; the limit stops before any.
    seen = Ref(0)
    space = TestSpace((Symbol(:p, i) => [1, 2] for i in 1:21)...;
                      constraints = [forbid(case -> (seen[] += 1; false))])
    request = Request(space)
    @test_throws ResourceLimitError generate_full_factorial(request)
    err = try generate_full_factorial(request) catch e; e end
    @test err.keyword == :limit
    @test err.limit == 10^6
    message = sprint(showerror, err)
    @test occursin("2_097_152 candidate rows", message)
    @test occursin("`limit = 1_000_000`", message)
    @test seen[] == 0
    # A small limit on a small space.
    request = Request(TestSpace((a = [1, 2], b = [:x, :y, :z], c = [true, false])))
    err = try generate_full_factorial(request; limit = 5) catch e; e end
    @test err isa ResourceLimitError
    @test occursin("12 candidate rows", sprint(showerror, err))
    @test size(generate_full_factorial(request; limit = 12).matrix, 2) == 12
    @test_throws ArgumentError generate_full_factorial(request; limit = 0)
    # The count is exact beyond Int.
    big = TestSpace((Symbol(:p, i) => 1:10 for i in 1:20)...)
    err = try generate_full_factorial(Request(big; strength = 1)) catch e; e end
    @test occursin("100_000_000_000_000_000_000 candidate rows", sprint(showerror, err))
end


@testitem "full factorial: must-include rows first, not repeated" setup=[Checker] begin
    using UnitTestDesign: Request, generate_full_factorial, to_cases
    space = test_space(fable_solver)
    seeds = [(mode = :exact, solver = :qr, tol = 1e-6), (solver = :lu,), (mode = :exact, solver = :qr, tol = 1e-6)]
    request = Request(space; must_include = seeds)
    design = generate_full_factorial(request)
    cases = to_cases(request, design.matrix)
    @test design.n_must_include == 3
    @test cases[1:3] == [seeds[1], (mode = :exact, solver = :lu, tol = 1e-6), seeds[1]]
    # The other three valid rows follow, once each.
    @test length(cases) == 3 + 3
    @test Set(cases) == Set(valid_rows(fable_solver.space))
    @test design.notes == (candidates = 12, accepted = 5)
end
