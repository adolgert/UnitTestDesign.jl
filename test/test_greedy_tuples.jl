using Test
using TestItemRunner

# GND through the internal Request (plan Phase 3 step 3). Every design is
# checked by the independent oracle, test/checker.jl: every row valid and
# every feasible target covered (contract §1.3).


@testitem "argmin_rand" setup=[UTSetup] begin
    using Random
    ar_cases = [
        [[1,2,3,1,4], [1,4]],
        [[-5, -7, -6, -3], [2]],
        [[0, -1, -2, -2], [3, 4]],
        [[1,1,1,1], [1,2,3,4]]
    ]
    ar_rng = Xoshiro(342234 ⊻ seed_mod())
    for ar_case in ar_cases
        values = Set{Int}()
        for i in 1:100
            idx = UnitTestDesign.argmin_rand(ar_rng, ar_case[1])
            push!(values, idx)
        end
        res = sort([x for x in values])
        @test res == ar_case[2]
    end
end


@testitem "GND: the three named examples" setup=[Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    for (f, feasible, excluded) in ((astra_chain, 6, 6), (fable_solver, 11, 5), (opus_gpu, 13, 3))
        request = Request(test_space(f))
        design = generate(GND(), request)
        result = check_design(to_cases(request, design.matrix), f.space)
        @test complete(result)
        @test result.ordinary.counts.feasible == feasible
        @test (design.required, design.covered, length(design.excluded)) == (feasible, feasible, excluded)
        @test (design.strategy, design.engine, design.seed, design.n_must_include) == (:covering, :GND, 0, 0)
    end
    # Astra: only (1, 1, 1) and (2, 2, 2) are valid, and both are needed.
    request = Request(test_space(astra_chain))
    @test Set(to_cases(request, generate(GND(), request).matrix)) == Set(valid_rows(astra_chain.space))
    # Fable: the two implied pairs are excluded with rules 1 and 2.
    design = generate(GND(), Request(test_space(fable_solver)))
    @test count(e -> e.status == :implied && e.rules == [1, 2], design.excluded) == 2
    @test count(e -> e.status == :forbidden, design.excluded) == 3
end


@testitem "GND: fixtures" setup=[Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    function run_gnd(f; strength = 2, stronger = [], engine = GND())
        request = Request(test_space(f); strength, stronger)
        design = generate(engine, request)
        cases = to_cases(request, design.matrix)
        return cases, check_design(cases, f.space; strength, stronger), design
    end

    # Both components need their last values: a = b = 3 and c = d = :y.
    cases, result, _ = run_gnd(disconnected_witness)
    @test complete(result)
    @test all(c -> c.a == 3 && c.b == 3 && c.c == :y && c.d == :y, cases)
    # A whole-case rule joins them; one valid row remains.
    cases, result, _ = run_gnd(whole_case_connects)
    @test complete(result)
    @test cases == valid_rows(whole_case_connects.space)
    @test cases == [(a = 3, b = 3, c = :y, d = :y, e = 2)]
    # Only the row of all 4s is valid; its 28 pairs are the feasible targets.
    cases, result, design = run_gnd(limit_exhaustion)
    @test complete(result)
    @test cases == valid_rows(limit_exhaustion.space)
    @test design.required == 28

    # Overlapping stronger groups: the union of their targets, 35 feasible.
    for stronger in (overlapping_groups.request.stronger, overlapping_groups.request.stronger_twice)
        _, check, d = run_gnd(overlapping_groups; stronger)
        @test complete(check)
        @test check.ordinary.counts.feasible == 35
        @test d.required == 35
        @test length(d.excluded) == 5
    end

    # The greedy dead ends that crash the 0.4 IPOG.
    for f in (dead_end_pairwise_1, dead_end_pairwise_2, dead_end_threeway_1, dead_end_threeway_2)
        k = f.request.strength
        for seed in 0:2
            _, check, d = run_gnd(f; strength = k, engine = GND(; seed))
            @test complete(check)
            @test d.covered == check.ordinary.counts.feasible
        end
    end
end


@testitem "GND: overlapping stronger groups with a rule across them (§1.3, §1.8, §11.8)" setup=[Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    # The regression IPOG's test of the same name guards: in 0.4 a value set
    # for the group (a, b, c) could clash through the rule (a = 1, d = 1) with
    # the group (b, c, d), and rows broke a rule. GND builds each row with every
    # value visible to `dead`, so no row breaks either rule, whatever the draws.
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2);
                      constraints = [forbid((b = 2, c = 2)), forbid((a = 1, d = 1))])
    oracle = CheckSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2),
                        [((:b, :c), (b, c) -> b == 2 && c == 2), ((:a, :d), (a, d) -> a == 1 && d == 1)])
    stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3]
    for seed in 0:9
        request = Request(space; stronger)
        design = generate(GND(; seed), request)
        check = check_design(to_cases(request, design.matrix), oracle; stronger)
        @test complete(check)
        @test design.required == design.covered == check.ordinary.counts.feasible
        @test length(design.excluded) == check.ordinary.counts.forbidden + check.ordinary.counts.implied
    end
end


@testitem "GND: bench12 at strengths 2 and 3" setup=[Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    # design/benchmark_procedure.md fixture 2. The 0.4 GND never returned on
    # it; the implied pair (p1 = 2, p2 = 2) is now excluded, not chased. The
    # case counts are recorded, not asserted beyond a loose bound; the
    # benchmark itself belongs to benchmark/run.jl.
    space = test_space(bench12)
    for (k, feasible, forbidden, implied, bound) in ((2, 586, 3, 1, 40), (3, 5702, 92, 26, 140))
        request = Request(space; strength = k)
        design = generate(GND(), request)
        result = check_design(to_cases(request, design.matrix), bench12.space; strength = k)
        @test complete(result)
        @test design.required == feasible == result.ordinary.counts.feasible
        @test count(e -> e.status == :forbidden, design.excluded) == forbidden
        @test count(e -> e.status == :implied, design.excluded) == implied
        # Every implied target contains (p1 = 2, p2 = 2).
        @test all(e -> e.status == :forbidden || e.target[1:2] == [2, 2], design.excluded)
        @test size(design.matrix, 2) <= bound
    end
end


@testitem "GND: an empty space gives an empty design (§1.24)" setup=[Checker] begin
    using UnitTestDesign: Request, generate
    request = Request(test_space(disconnected_unsat))
    design = generate(GND(), request)
    @test size(design.matrix) == (3, 0)
    @test (design.required, design.covered) == (0, 0)
    # Every pair is excluded: 3·2 + 3·2 + 2·2 targets.
    @test length(design.excluded) == 16
    @test all(e -> e.status in (:forbidden, :implied), design.excluded)
    result = check_design(UnitTestDesign.to_cases(request, design.matrix), disconnected_unsat.space)
    @test complete(result)
    @test result.ordinary.counts.feasible == 0
end


@testitem "GND: an exhausted feasibility limit throws, and a retry succeeds (§3.6–§3.8)" setup=[Checker] begin
    using UnitTestDesign: Request, generate, ResourceLimitError
    space = test_space(limit_exhaustion)
    request = Request(space; feasibility_limit = limit_exhaustion.request.small_limit)
    @test_throws ResourceLimitError generate(GND(), request)
    err = try generate(GND(), request) catch e; e end
    @test err.keyword == :feasibility_limit
    request = Request(space; feasibility_limit = limit_exhaustion.request.default_limit)
    @test size(generate(GND(), request).matrix, 2) == 1
end


@testitem "GND: the progress guarantee covers a target no candidate reaches" setup=[Checker] begin
    using UnitTestDesign: Request, generate, to_cases, classify_targets, gnd_cover
    # (a = 1, b = 1) is feasible only in the row of all 1s: every c must be 1
    # when a = 1 and b = 1. The must-include rows, a design for the space
    # where (a = 1, b = 1) is forbidden outright, cover every other pair, so
    # GND starts with that one target uncovered. A candidate reaches it only
    # if its second target parameter comes before any c drawn as 2, which a
    # single candidate per round (`candidates = 1`) usually misses. The 0.4
    # GND then drew again, without bound; now the round builds its row from
    # the uncovered target itself.
    cs = [Symbol(:c, i) for i in 1:10]
    domains = [:a => [1, 2], :b => [1, 2], (c => [1, 2] for c in cs)...]
    rare = TestSpace(domains...;
        constraints = [forbid((a, b, c) -> a == 1 && b == 1 && c != 1, :a, :b, c) for c in cs])
    others = TestSpace(domains...; constraints = [forbid((a = 1, b = 1))])
    other_request = Request(others)
    seeds = to_cases(other_request, generate(GND(), other_request).matrix)
    request = Request(rare; must_include = seeds)
    required, _ = classify_targets(request)
    @test length(required) == 4 * 66
    runs = [gnd_cover(GND(; seed, candidates = 1), request, required) for seed in 0:19]
    @test all(size(matrix, 2) == length(seeds) + 1 for (matrix, _) in runs)
    @test all(matrix[:, end] == ones(Int, 12) for (matrix, _) in runs)
    @test all(taken <= 1 for (_, taken) in runs)
    # Most single candidates miss; the progress guarantee then builds the row.
    @test sum(taken for (_, taken) in runs) >= 1
    # Through the entry point, with the checker.
    checker = CheckSpace([:a, :b, cs...], [[1, 2] for _ in 1:12],
        [((:a, :b, c), (a, b, x) -> a == 1 && b == 1 && x != 1) for c in cs])
    for seed in 0:4
        design = generate(GND(; seed, candidates = 1), request)
        cases = to_cases(request, design.matrix)
        @test complete(check_design(cases, checker))
        @test cases[1:length(seeds)] == seeds
    end
end


@testitem "GND design size is competitive" begin
    using UnitTestDesign: Request, generate
    # Before the scoring fix in most_matches_existing, GND chose most values
    # at random and needed 36-38 cases here, compared with 28 for IPOG.
    arity = fill(4, 10)
    space = TestSpace((Symbol(:p, i) => 1:4 for i in 1:10)...)
    for seed in 1:3
        design = generate(GND(; seed), Request(space))
        @test size(design.matrix, 2) <= 32
        @test design.covered == UnitTestDesign.total_combinations(arity, 2)
    end
end


@testitem "GND: unconstrained coverage at strengths 1 to 3 and with a stronger group" setup=[IndexCoverage, Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    domains = [[1, 2], [1, 2, 3], [1, 2], [1, 2, 3]]
    names = [:a, :b, :c, :d]
    checker = CheckSpace(names, domains)
    space = TestSpace(Pair.(names, domains)...)
    for k in 1:3, seed in 0:2
        request = Request(space; strength = k)
        design = generate(GND(; seed), request)
        @test complete(check_design(to_cases(request, design.matrix), checker; strength = k))
        @test design.required == UnitTestDesign.total_combinations(length.(domains), k)
    end
    # The 0.4 n_way_coverage_multi test: 3-way within (1, 3, 4, 5), pairwise elsewhere.
    arity = [2, 3, 4, 2, 2, 3]
    names = [Symbol(:p, i) for i in 1:6]
    checker = CheckSpace(names, [collect(1:a) for a in arity])
    space = TestSpace(Pair.(names, [1:a for a in arity])...)
    stronger = [(:p1, :p3, :p4, :p5) => 3]
    request = Request(space; strength = 2, stronger)
    design = generate(GND(), request)
    @test complete(check_design(to_cases(request, design.matrix), checker; strength = 2, stronger))
    rows = [design.matrix[:, j] for j in axes(design.matrix, 2)]
    @test coverage_by_tuple([r[[1, 3, 4, 5]] for r in rows], 3) ==
          UnitTestDesign.total_combinations(arity[[1, 3, 4, 5]], 3)
end


@testitem "GND: strength equal to the parameter count returns the valid rows (§7.8)" setup=[Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    for f in (fable_solver, opus_gpu, astra_chain, whole_case_connects)
        n = length(f.input.names)
        request = Request(test_space(f); strength = n)
        cases = to_cases(request, generate(GND(), request).matrix)
        @test length(cases) == length(valid_rows(f.space))
        @test Set(cases) == Set(valid_rows(f.space))
    end
    # With must-include rows: they come first and are not repeated.
    request = Request(test_space(fable_solver); strength = 3,
                      must_include = [(mode = :exact, solver = :qr, tol = 1e-6), (solver = :lu,)])
    cases = to_cases(request, generate(GND(), request).matrix)
    @test cases[1:2] == [(mode = :exact, solver = :qr, tol = 1e-6), (mode = :exact, solver = :lu, tol = 1e-6)]
    @test length(cases) == 5
    @test Set(cases) == Set(valid_rows(fable_solver.space))
end


@testitem "GND: must-include rows come first and unchanged (§10.5)" setup=[IndexCoverage, Checker] begin
    using UnitTestDesign: Request, generate, to_cases
    space = test_space(fable_solver)
    seeds = [(mode = :exact, solver = :qr, tol = 1e-6), (solver = :lu,),
             (mode = :exact, solver = :qr, tol = 1e-6), (tol = 1e-3,)]
    request = Request(space; must_include = seeds)
    design = generate(GND(), request)
    cases = to_cases(request, design.matrix)
    @test design.n_must_include == 4
    @test cases[1] == seeds[1]
    @test cases[3] == seeds[1]  # duplicates kept
    @test cases[2] == (mode = :exact, solver = :lu, tol = 1e-6)  # its only completion
    @test cases[4].tol == 1e-3 && cases[4].mode == :fast && cases[4].solver == :none
    @test complete(check_design(cases, fable_solver.space))
    # Complete must-include rows on a larger unconstrained space.
    space = TestSpace((Symbol(:p, i) => 1:4 for i in 1:8)...)
    seeds = [Tuple(fill(1, 8)), (1, 2, 3, 4, 1, 2, 3, 4), Tuple(fill(4, 8))]
    request = Request(space; must_include = seeds)
    cases = to_cases(request, generate(GND(), request).matrix)
    @test [Tuple(c) for c in cases[1:3]] == seeds
    @test coverage_by_tuple([collect(Tuple(c)) for c in cases], 2) == 16 * 28
end


@testitem "GND: determinism and the engine's generator (§9.5, §9.6)" setup=[Checker] begin
    using Random
    using UnitTestDesign: Request, generate
    request = Request(test_space(bench12))
    a = generate(GND(seed = 7), request)
    b = generate(GND(seed = 7), Request(test_space(bench12)))
    @test a.matrix == b.matrix
    @test a.seed == 7
    engine = GND(seed = 7)
    @test generate(engine, request).matrix == generate(engine, request).matrix

    rng = Xoshiro(1)
    before = copy(rng)
    engine = GND(rng = rng)
    c = generate(engine, request)
    @test rng == before
    @test c.seed === nothing
    @test generate(engine, request).matrix == c.matrix
    # The copy is taken at each call, so the caller's state decides the draws.
    @test generate(GND(rng = Xoshiro(1)), request).matrix == c.matrix

    @test_deprecated GND(M = 3)
    # Under --depwarn=error the deprecated keyword throws instead.
    @test Base.JLOptions().depwarn == 2 || GND(M = 3).candidates == 3
    design = generate(GND(candidates = 3), request)
    @test design.covered == design.required
end
