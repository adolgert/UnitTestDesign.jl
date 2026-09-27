using Test
using Random

using TestItemRunner

# IPOG: the classic unconstrained `ipog`, the constrained mixed-strength core
# `ipog_multi_way`, and `generate(IPOG(), request)` (plan Phase 3 steps 2, 6
# and 7). Engine results on fixtures are checked by the independent oracle
# (test/checker.jl) through `setup=[Checker]`.

@testsnippet IPOGSetup begin
    using UnitTestDesign: Request, Design, generate, to_cases, classify_targets, targets,
        ipog_multi_way, ipog_order, validate_design

    "A request over parameters p1, p2, ... with values 1:arity[i], so positions are values."
    positional_request(arity; kwargs...) =
        Request(TestSpace((Symbol(:p, i) => 1:a for (i, a) in enumerate(arity))...); kwargs...)

    """
    Generate with IPOG for a fixture at its strength, and check the design with
    the oracle. Returns the request, the design, the named cases, and the check.
    """
    function ipog_fixture(f; strength = get(f.request, :strength, 2), stronger = [], kwargs...)
        request = Request(test_space(f); strength = strength, stronger = stronger, kwargs...)
        design = generate(IPOG(), request)
        cases = to_cases(request, design.matrix)
        return request, design, cases, check_design(cases, f.space; strength = strength, stronger = stronger)
    end
end


@testitem "ipog base" begin
    ip232 = UnitTestDesign.ipog([2, 3, 2], 2)
    @test size(ip232) == (3, 6)
    @inferred UnitTestDesign.ipog([2, 3, 2], 2)
    ip2324 = UnitTestDesign.ipog([2, 3, 2, 4, 7, 2], 2)
    @test size(ip2324) == (6, 28)
end


@testitem "ipog_multi_way covers every pair without rules" setup=[IPOGSetup] begin
    arity = [2, 3, 2]
    required, _ = classify_targets(positional_request(arity))
    im232 = ipog_multi_way(arity, required, Returns(false))
    @test size(im232) == (3, 6)
    @test UnitTestDesign.test_coverage(im232, arity, 2) == (start = 16, finish = 0)
    @inferred ipog_multi_way(arity, required, Returns(false))
    # The same size as the classic algorithm.
    @test size(ipog_multi_way([2, 3, 2, 4, 7, 2], targets(positional_request([2, 3, 2, 4, 7, 2])),
                              Returns(false))) == (6, 28)
end


@testitem "ipog_order: stronger groups first, then larger domains" setup=[IPOGSetup] begin
    @test ipog_order([2, 3, 2, 4], [[1, 2, 3, 4] => 2]) == sortperm([2, 3, 2, 4], rev = true) == [4, 2, 1, 3]
    @test ipog_order([2, 3, 2, 3], [[1, 2, 3, 4] => 2, [1, 3, 4] => 3]) == [4, 1, 3, 2]
    @test ipog_order([2, 2, 2], [[1, 2, 3] => 1]) == [1, 2, 3]
end


@testitem "ipog with must-include rows: they come first (§10.5)" setup=[IPOGSetup] begin
    seed232 = [2 1; 3 3; 1 2]
    request = positional_request([2, 3, 2]; must_include = [Tuple(seed232[:, j]) for j in 1:2])
    design = generate(IPOG(), request)
    # total cases doesn't change.
    @test size(design.matrix) == (3, 6)
    # the test cases come first.
    @test design.matrix[:, 1:2] == seed232
    @test design.n_must_include == 2
    @test UnitTestDesign.test_coverage(design.matrix, [2, 3, 2], 2).finish == 0
end


@testitem "ipog never returns a forbidden pair" setup=[IPOGSetup] begin
    space = TestSpace((p1 = 1:2, p2 = 1:3, p3 = 1:2); constraints = [forbid((p2 = 3, p3 = 2))])
    design = generate(IPOG(), Request(space))
    ex232 = design.matrix
    # There are no tuples that are [x, 3, 2].
    @test !any(sum(ex232 .== [0, 3, 2], dims = 1) .== 2)
    @test design.required == design.covered == 15
    @test length(design.excluded) == 1 && only(design.excluded).status == :forbidden
    @test (design.strategy, design.engine, design.seed, design.notes) == (:covering, :IPOG, nothing, (;))
end


@testitem "long random of ipog_multi_way" setup=[UTSetup, IPOGSetup] begin
    using Random

    rng = Xoshiro(90714134 ⊻ seed_mod())
    test_time = 30 * test_run_multiplier()
    max_n = 10
    max_arity = 7
    start_time = time()
    while time() - start_time < test_time
        n = rand(rng, 3:max_n)
        local arity
        arity = rand(rng, 2:max_arity, n)
        k = rand(rng, 2:minimum([3, n]))
        required, _ = classify_targets(positional_request(arity; strength = k))
        r1 = ipog_multi_way(arity, required, Returns(false))
        cover1 = UnitTestDesign.test_coverage(r1, arity, k)
        @test cover1.finish == 0
    end
end


@testitem "all combinations long random, with a forbidden pair" setup=[UTSetup, IPOGSetup] begin
    using Random

    rng = Xoshiro(2424324 ⊻ seed_mod())
    test_time = 30 * test_run_multiplier()
    max_n = 10
    max_arity = 7
    start_time = time()
    while time() - start_time < test_time
        n = rand(rng, 3:max_n)
        local arity
        arity = rand(rng, 2:max_arity, n)
        arity[2] = maximum([3, arity[2]]) # make sure it's >=3.
        k = rand(rng, 2:minimum([3, n]))
        space = TestSpace((Symbol(:p, i) => 1:a for (i, a) in enumerate(arity))...;
                          constraints = [forbid((p2 = 3, p3 = 2))])
        design = generate(IPOG(), Request(space; strength = k))
        r2 = design.matrix
        out_arity = vec(maximum(r2, dims = 2))
        @test out_arity == arity
        all_combos = UnitTestDesign.all_combinations(arity, k)
        combo_cnt = size(all_combos, 2)
        compare = zeros(Int, n)
        compare .= -1
        compare[2:3] .= [3, 2]
        exclude = vec(sum(all_combos .== compare, dims = 1) .== 2)
        cover2 = UnitTestDesign.test_coverage(r2, arity, k)
        @test cover2.start == combo_cnt
        @test cover2.finish == sum(exclude)
        @test length(design.excluded) == sum(exclude)
        @test !any(sum(r2 .== compare, dims = 1) .== 2)
    end
end


@testitem "test coverage specific: a stronger group" setup=[IPOGSetup] begin
    imw_arity = [2, 3, 2, 3]
    imw_k = 2
    imw_ind = [1, 3, 4]
    request = positional_request(imw_arity; stronger = [imw_ind => 3])
    imw1 = generate(IPOG(), request).matrix
    imw_cover1 = UnitTestDesign.test_coverage(imw1, imw_arity, imw_k)
    @test imw_cover1.finish == 0
    imw_cover2 = UnitTestDesign.test_coverage(imw1[imw_ind, :], imw_arity[imw_ind], 3)
    @test imw_cover2.finish == 0
    oind1 = [1, 2, 3]
    imw_cover3 = UnitTestDesign.test_coverage(imw1[oind1, :], imw_arity[oind1], 3)
    oind2 = [2, 3, 4]
    imw_cover4 = UnitTestDesign.test_coverage(imw1[oind2, :], imw_arity[oind2], 3)
    @test imw_cover3.finish + imw_cover4.finish > 0

    # What if we do the whole set at 3-way?
    im11 = generate(IPOG(), positional_request(imw_arity; strength = 3)).matrix
    im11_cover = UnitTestDesign.test_coverage(im11, imw_arity, 3)
    @test im11_cover.finish == 0

    # Groups by range and tuple; the positional wayness of 0.4, twenty binary parameters.
    stronger5 = [1:5 => 3, (4, 5, 6) => 3, collect(11:18) => 4]
    trials5 = generate(IPOG(), positional_request(fill(2, 20); stronger = stronger5)).matrix
    arity5 = fill(2, 20)
    @test UnitTestDesign.test_coverage(trials5, arity5, 2).finish == 0
    @test UnitTestDesign.test_coverage(trials5[1:5, :], arity5[1:5], 3).finish == 0
    @test UnitTestDesign.test_coverage(trials5[4:6, :], arity5[4:6], 3).finish == 0
    @test UnitTestDesign.test_coverage(trials5[11:18, :], arity5[11:18], 4).finish == 0
end


@testitem "IPOG: Astra's chained equalities (§1.2)" setup=[IPOGSetup, Checker] begin
    request, design, cases, check = ipog_fixture(astra_chain)
    @test complete(check)
    @test Set(cases) == Set([(A = 1, B = 1, C = 1), (A = 2, B = 2, C = 2)])
    @test design.required == design.covered == 6
    @test count(e -> e.status == :implied, design.excluded) == 2
    @test count(e -> e.status == :forbidden, design.excluded) == 4
end


@testitem "IPOG: Fable's solver example (§1.4)" setup=[IPOGSetup, Checker] begin
    request, design, cases, check = ipog_fixture(fable_solver)
    @test complete(check)
    @test check.ordinary.counts.covered == 11
    @test design.required == design.covered == 11
    @test length(cases) == 5
    @test sort([e.status for e in design.excluded]) == [:forbidden, :forbidden, :forbidden, :implied, :implied]
end


@testitem "IPOG: Opus's GPU example closes issue #51 (§1.3)" setup=[IPOGSetup, Checker] begin
    # The 0.4 IPOG threw a BoundsError here.
    request, design, cases, check = ipog_fixture(opus_gpu)
    @test complete(check)
    @test check.ordinary.counts.covered == 13
    @test !any(c -> c.os == :windows && c.gpu, cases)
end


@testitem "IPOG: greedy dead ends are completed (§1.3, §3.1)" setup=[IPOGSetup, Checker] begin
    for f in (dead_end_pairwise_1, dead_end_pairwise_2, dead_end_threeway_1, dead_end_threeway_2)
        request, design, cases, check = ipog_fixture(f)
        @test complete(check)
        @test design.covered == check.ordinary.counts.feasible
        @test isempty(check.ordinary.rejected)
    end
end


@testitem "IPOG: bench12 at strengths 2 and 3 (§1.2–§1.4)" setup=[IPOGSetup, Checker] begin
    # Case counts at this revision: 22 pairwise, 93 three-way. They may change
    # with the engine (contract §8.1); coverage may not.
    for (strength, feasible, excluded, rows) in ((2, 586, 4, 22), (3, 5702, 118, 93))
        request, design, cases, check = ipog_fixture(bench12; strength = strength)
        @test complete(check)
        @test design.required == design.covered == feasible
        @test length(design.excluded) == excluded
        @test length(cases) == rows
        @test !any(c -> c.p1 == 2 && c.p2 == 2, cases)
    end
end


@testitem "IPOG: a proven empty space gives an empty design (§1.24)" setup=[IPOGSetup, Checker] begin
    request, design, cases, check = ipog_fixture(disconnected_unsat)
    @test isempty(cases)
    @test size(design.matrix) == (3, 0)
    @test design.required == design.covered == 0
    @test length(design.excluded) == length(targets(request)) == 16
    @test complete(check)
end


@testitem "IPOG: disconnected components and a whole-case rule (§3.4, §12.21)" setup=[IPOGSetup, Checker] begin
    request, design, cases, check = ipog_fixture(disconnected_witness)
    @test complete(check)
    @test all(c -> c.a == c.b == 3 && c.c == c.d == :y, cases)
    request, design, cases, check = ipog_fixture(whole_case_connects)
    @test complete(check)
    @test unique(cases) == [(a = 3, b = 3, c = :y, d = :y, e = 2)]
end


@testitem "IPOG: an exhausted search throws, a larger limit succeeds (§3.6–§3.8)" setup=[IPOGSetup, Checker] begin
    f = limit_exhaustion
    space = test_space(f)
    @test_throws ResourceLimitError generate(IPOG(), Request(space; feasibility_limit = f.request.small_limit))
    design = generate(IPOG(), Request(space; feasibility_limit = f.request.default_limit))
    @test design.matrix == fill(4, 8, 1)
    @test design.required == design.covered == 28
    # Raising the limit never changes a resolved answer (§3.8).
    @test generate(IPOG(), Request(space; feasibility_limit = 10 * f.request.default_limit)).matrix == design.matrix
end


@testitem "IPOG: overlapping stronger groups (§1.8, §11.8)" setup=[IPOGSetup, Checker] begin
    f = overlapping_groups
    request, design, cases, check = ipog_fixture(f; stronger = f.request.stronger)
    @test complete(check)
    @test design.required == 35
    @test length(design.excluded) == 5
    _, twice, _, _ = ipog_fixture(f; stronger = f.request.stronger_twice)
    @test twice.matrix == design.matrix

    # A rule across the two groups: a value set for (a, b, c) constrains d.
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2);
                      constraints = [forbid((b = 2, c = 2)), forbid((a = 1, d = 1))])
    stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3]
    request = Request(space; stronger = stronger)
    design = generate(IPOG(), request)
    cases = to_cases(request, design.matrix)
    oracle = CheckSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2),
                        [((:b, :c), (b, c) -> b == 2 && c == 2), ((:a, :d), (a, d) -> a == 1 && d == 1)])
    @test complete(check_design(cases, oracle; stronger = stronger))
end


@testitem "IPOG: must-include rows first, partial ones completed in place (§10.5, §7.10)" setup=[IPOGSetup, Checker] begin
    f = fable_solver
    seeds = [(solver = :lu,), (mode = :fast, solver = :none, tol = 1e-3), (solver = :lu,), (mode = :exact,)]
    request, design, cases, check = ipog_fixture(f; must_include = seeds)
    @test complete(check)
    @test design.n_must_include == 4
    @test cases[1] == cases[3] == (mode = :exact, solver = :lu, tol = 1e-6)   # the only completion
    @test cases[2] == seeds[2]
    @test cases[4].mode == :exact
    @test length(cases) >= 5

    # Without rules, a partial row keeps its value and the rest still covers.
    request = positional_request([2, 3, 2]; must_include = [(p2 = 3,), (1, 1, 1)])
    design = generate(IPOG(), request)
    @test design.matrix[2, 1] == 3 && design.matrix[:, 2] == [1, 1, 1]
    @test UnitTestDesign.test_coverage(design.matrix, [2, 3, 2], 2).finish == 0
end


@testitem "IPOG: strength equal to the parameter count is a full factorial (§7.8, §11.2)" setup=[IPOGSetup, Checker] begin
    request, design, cases, check = ipog_fixture(fable_solver; strength = 3)
    @test complete(check)
    @test cases == valid_rows(fable_solver.space)
    @test design.required == 5 && length(design.excluded) == 7
    # With a must-include row, it comes first and is not repeated.
    request, design, cases, check = ipog_fixture(fable_solver; strength = 3, must_include = [(solver = :lu,)])
    @test cases[1] == (mode = :exact, solver = :lu, tol = 1e-6)
    @test Set(cases) == Set(valid_rows(fable_solver.space)) && length(cases) == 5
    # Without rules: every row, in lexicographic order.
    free = generate(IPOG(), positional_request([2, 3]; strength = 2)).matrix
    @test free == [1 1 1 2 2 2; 1 2 3 1 2 3]
    @test all_tuples([1, 2], [:a, :b]; n_way = 2) == [[1, :a], [1, :b], [2, :a], [2, :b]]
    @test length(all_triples([1, 2], [3, 4], [5, 6])) == 8
    @test_throws ArgumentError all_triples([1, 2], [3, 4])   # strength above n (§11.2)
end


@testitem "IPOG: single-valued parameters (plan Phase 3 step 7)" setup=[IPOGSetup] begin
    rows = all_pairs([1], [1, 2], [:a, :b])
    @test length(rows) == 4
    @test all(r -> r[1] == 1, rows)
    @test Set(r[2:3] for r in rows) == Set([[1, :a], [1, :b], [2, :a], [2, :b]])
    @test all_values([:only]) == [[:only]]
    space = TestSpace((a = [1], b = 1:3, c = [:x, :y]); constraints = [forbid((b = 3, c = :y))])
    request = Request(space)
    design = generate(IPOG(), request)
    @test design.required == design.covered == 2 + 3 + 5
    @test all(==(1), design.matrix[1, :])
end


@testitem "IPOG is deterministic (§9.1, §9.4)" setup=[IPOGSetup, Checker] begin
    space = test_space(bench12)
    once = generate(IPOG(), Request(space; strength = 3))
    again = generate(IPOG(), Request(test_space(bench12); strength = 3))
    @test once.matrix == again.matrix
    @test [e.target for e in once.excluded] == [e.target for e in again.excluded]
    # The same request twice: its caches do not change the answer (§3.5).
    request = Request(space; stronger = [(:p1, :p2, :p9) => 3], must_include = [(p3 = 2,)])
    @test generate(IPOG(), request).matrix == generate(IPOG(), request).matrix
end
