using Test
using TestItemRunner

# The 0.4 positional entry points, now routed through a TestSpace, a Request
# and an engine (plan Phase 3 step 7). They return the 0.4 shape, a vector of
# Vector{Any}, until Phase 4 changes the return type (contract §13.4). Rules
# need a TestSpace; the tests that used `disallow` build one and call the
# engine directly.

@testsnippet InterfaceSetup begin
    using UnitTestDesign: Request, generate, to_cases, generate_excursion, generate_full_factorial,
        engine_rng, _stronger_from_wayness

    "Positional names p1, p2, ... and named rules, as a positional caller would write them."
    positional_space(domains...; constraints = []) =
        TestSpace((Symbol(:p, i) => d for (i, d) in enumerate(domains))...; constraints = constraints)

    "The named cases of a design."
    cases_of(request, design) = to_cases(request, design.matrix)
end


@testitem "IPOG init" begin
    ipog = IPOG()
    @test isa(ipog, IPOG)
end


@testitem "GND init (§9.5, §9.6)" setup=[InterfaceSetup] begin
    using Random
    gnd1 = GND()
    @test gnd1.candidates == 50 && gnd1.seed == 0 && gnd1.rng === nothing
    # Each call starts a fresh generator from the seed.
    @test randn(engine_rng(gnd1)) == randn(engine_rng(gnd1)) == randn(Xoshiro(0))
    gnd2 = GND(candidates = 100, seed = 7)
    @test gnd2.candidates == 100 && gnd2.seed == 7
    @test randn(engine_rng(gnd2)) != randn(engine_rng(gnd1))
    caller = Xoshiro(23423523)
    gnd3 = GND(rng = caller)
    @test gnd3.candidates == 50 && gnd3.seed === nothing
    sample3 = randn(engine_rng(gnd3))
    @test sample3 == randn(engine_rng(gnd3))       # a copy, so repeated calls agree
    @test randn(caller) == sample3                 # and the caller's generator is unadvanced
    @test_throws ArgumentError GND(candidates = 0)
    # The 0.4 keyword M is deprecated and means candidates.
    gnd5 = @test_deprecated GND(rng = Xoshiro(23423523), M = 70)
    @test gnd5.candidates == 70
end


@testitem "removed: disallow, Counter, generate_tuples (§12.10, §13.3)" begin
    @test_throws MethodError all_pairs([1, 2], [3, 4], [5, 6]; disallow = (a, b, c) -> false)
    @test_throws MethodError all_tuples([1, 2], [3, 4]; n_way = 1, disallow = (a, b) -> false)
    @test_throws MethodError full_factorial([1, 2], [3, 4]; disallow = (a, b) -> false)
    @test_throws MethodError pairs_excursion([1, 2], [3, 4], [5, 6]; disallow = (a, b, c) -> false)
    @test_throws MethodError all_pairs([1, 2], [3, 4], [5, 6]; Counter = Int8)
    @test !isdefined(UnitTestDesign, :generate_tuples)
    @test !isdefined(UnitTestDesign, :wrap_disallow)
    @test !isdefined(UnitTestDesign, :seeds_to_integers)
    @test !(:generate_tuples in names(UnitTestDesign))
end


@testitem "positional calls return the 0.4 shape and keep values (§2.9)" begin
    rows = all_pairs([1, 2], ["a", "b", "c"], [4, 7])
    @test rows isa Vector{Vector{Any}}
    @test length(rows) == 6
    @test all(r -> r[1] isa Int && r[2] isa String && r[3] isa Int, rows)
    # nothing and missing are values, and 1 and 1.0 are two values.
    rows = all_pairs(Any[1, 1.0], [nothing, :a], [missing, 2])
    @test any(r -> r[1] === 1.0, rows) && any(r -> r[1] === 1, rows)
    @test any(r -> r[2] === nothing, rows) && any(r -> r[3] === missing, rows)
    # Domains may be vectors, ranges or tuples.
    @test length(all_pairs((1, 2), 1:2, [:a, :b])) == 4
    @test_throws ArgumentError all_pairs()
    @test_throws ArgumentError all_pairs([1, 1, 2], [3, 4])   # a value listed twice (§2.5)
    @test_throws ArgumentError all_pairs([1, 2], [3, 4]; engine = :fast)
end


@testitem "IPOG generate tuples" setup=[InterfaceSetup] begin
    trials1 = all_tuples([1, 2], [true, false], ["a", "b", "c"])
    @test length(trials1) == 6
    @test trials1[1][3] in ["a", "b", "c"]

    # Rules live in a TestSpace.
    space2 = positional_space([1, 2], [true, false], ["a", "b", "c"];
                              constraints = [forbid((y, z) -> y == false && z in ("b", "c"), :p2, :p3)])
    request2 = Request(space2)
    trials2 = cases_of(request2, generate(IPOG(), request2))
    for trial2 in trials2
        @test !(!trial2.p2 && trial2.p3 in ["b", "c"])
    end

    space3 = positional_space([1, 2], [true, false], ["a", "b", "c"];
                              constraints = [forbid(case -> case.p1 == 2 && case.p3 in ("a", "b"))])
    request3 = Request(space3)
    trials3 = cases_of(request3, generate(IPOG(), request3))
    for trial3 in trials3
        @test !(trial3.p1 == 2 && trial3.p3 in ["a", "b"])
    end

    seeds = [[1, 2, 3, 4, 1, 2, 3, 4], fill(4, 8)]
    trials4 = all_tuples(fill(1:4, 8)...; seeds = seeds)
    @test trials4[1] == seeds[1]
    @test trials4[2] == seeds[2]
    cover4 = UnitTestDesign.test_coverage(hcat(trials4...), fill(4, 8), 2)
    @test cover4.finish == 0
    @test_throws ArgumentError all_tuples(fill(1:4, 8)...; seeds = [[1, 2, 3]])
    @test_throws ArgumentError all_tuples(fill(1:4, 8)...; seeds = [fill(5, 8)])

    params5 = fill(1:2, 20)
    wayness5 = Dict(3 => [[1, 2, 3, 4, 5], [4, 5, 6]], 4 => [collect(11:18)])
    trials5 = all_tuples(params5...; wayness = wayness5)
    trails5_arr = hcat(trials5...)
    arity5 = [length(x) for x in params5]
    @test UnitTestDesign.test_coverage(trails5_arr, arity5, 2).finish == 0
    @test UnitTestDesign.test_coverage(trails5_arr[1:5, :], arity5[1:5], 3).finish == 0
    @test UnitTestDesign.test_coverage(trails5_arr[4:6, :], arity5[4:6], 3).finish == 0
    @test UnitTestDesign.test_coverage(trails5_arr[11:18, :], arity5[11:18], 4).finish == 0
    # The caller's wayness is not mutated (§11.9).
    @test wayness5 == Dict(3 => [[1, 2, 3, 4, 5], [4, 5, 6]], 4 => [collect(11:18)])
end


@testitem "wayness is translated to stronger (§11.10)" setup=[InterfaceSetup] begin
    @test _stronger_from_wayness(nothing) == []
    @test _stronger_from_wayness(Dict(3 => [[3, 4, 5, 6]])) == [[3, 4, 5, 6] => 3]
    @test _stronger_from_wayness(Dict(4 => [11:18], 3 => [(1, 2, 3), [4, 5, 6]])) ==
          [[1, 2, 3] => 3, [4, 5, 6] => 3, collect(11:18) => 4]
    # A group at the base strength adds nothing (§11.7).
    @test length(all_pairs(fill(1:2, 4)...; wayness = Dict(2 => [[1, 2, 3]]))) ==
          length(all_pairs(fill(1:2, 4)...))
    @test_throws ArgumentError all_pairs(fill(1:2, 4)...; wayness = [[1, 2, 3]])
    @test_throws ArgumentError all_pairs(fill(1:2, 4)...; wayness = Dict(3 => [1, 2, 3]))
    @test_throws ArgumentError all_pairs(fill(1:2, 4)...; wayness = Dict(1 => [[1, 2, 3]]))  # below the base (§11.6)
    @test_throws ArgumentError all_pairs(fill(1:2, 4)...; wayness = Dict(3 => [[1, 2, 9]]))  # no parameter 9 (§11.4)
end


@testitem "GND generate tuples" setup=[InterfaceSetup] begin
    gndt1 = all_tuples([1, 2], [true, false], ["a", "b", "c"]; engine = GND())
    @test length(gndt1) > 3
    @test gndt1[1][2] in [true, false]
    @test gndt1[1][3] in ["a", "b", "c"]

    space2 = positional_space([1, 2], [true, false], ["a", "b", "c"];
                              constraints = [forbid((y, z) -> y == false && z in ("b", "c"), :p2, :p3)])
    request2 = Request(space2)
    trials2 = cases_of(request2, generate(GND(), request2))
    for trial2 in trials2
        @test !(!trial2.p2 && trial2.p3 in ["b", "c"])
    end

    space3 = positional_space([1, 2], [true, false], ["a", "b", "c"];
                              constraints = [forbid(case -> case.p1 == 2 && case.p3 in ("a", "b"))])
    request3 = Request(space3)
    trials3 = cases_of(request3, generate(GND(), request3))
    for trial3 in trials3
        @test !(trial3.p1 == 2 && trial3.p3 in ["a", "b"])
    end

    seeds = [[1, 2, 3, 4, 1, 2, 3, 4], fill(4, 8)]
    trials4 = all_tuples(fill(1:4, 8)...; seeds = seeds, engine = GND())
    @test trials4[1:2] == seeds
    cover4 = UnitTestDesign.test_coverage(hcat(trials4...), fill(4, 8), 2)
    @test cover4.finish == 0

    params5 = fill(1:2, 20)
    wayness5 = Dict(3 => [[1, 2, 3, 4, 5], [4, 5, 6]], 4 => [collect(11:18)])
    trials5 = all_tuples(params5...; wayness = wayness5, engine = GND(candidates = 20))
    trails5_arr = hcat(trials5...)
    arity5 = [length(x) for x in params5]
    @test UnitTestDesign.test_coverage(trails5_arr, arity5, 2).finish == 0
    @test UnitTestDesign.test_coverage(trails5_arr[1:5, :], arity5[1:5], 3).finish == 0
    @test UnitTestDesign.test_coverage(trails5_arr[4:6, :], arity5[4:6], 3).finish == 0
    @test UnitTestDesign.test_coverage(trails5_arr[11:18, :], arity5[11:18], 4).finish == 0

    # A fixed default seed: two calls agree (§9.5).
    @test all_pairs(fill(1:3, 6)...; engine = GND()) == all_pairs(fill(1:3, 6)...; engine = GND())
end


@testitem "IPOG generate all values" begin
    av1 = all_values([1, 2], ["a", "b", "c"], [4, 7])
    @test length(av1) == 3
    @test av1[1][3] in [4, 7]
end


@testitem "IPOG generate all pairs" begin
    pairs1 = all_pairs([1, 2], ["a", "b", "c"], [4, 7])
    @test length(pairs1) > 3
    @test pairs1[1][3] in [4, 7]
end


@testitem "IPOG generate all triples" begin
    at1 = all_triples([1, 2], ["a", "b", "c"], [4, 7], [true, false])
    @test length(at1) > 9
    @test at1[1][3] in [4, 7]
    @test length(at1[1]) == 4
end


@testitem "values excursion" begin
    ve1_params = [1:3, 1:2, 1:4, 1:2, 1:2]
    ve1 = values_excursion(ve1_params...)
    ve1_arity = maximum.(ve1_params)
    @test length(ve1) == sum(ve1_arity .- 1) + 1
    # n_way is the excursion's distance, not a covering strength (§7.5), so a
    # single parameter is fine, and a distance above the parameter count is
    # the parameter count.
    @test values_excursion([1, 2, 3]) == [[1], [2], [3]]
    @test pairs_excursion([1, 2, 3]) == [[1], [2], [3]]
    @test triples_excursion([1, 2], [:a, :b]) == [[1, :a], [2, :a], [1, :b], [2, :b]]
    @test all_tuples([1, 2], [3, 4]; n_way = 0, engine = Excursion()) == [[1, 3]]
    @test_throws ArgumentError all_tuples([1, 2], [3, 4]; n_way = -1, engine = Excursion())
end


@testitem "pairs excursion" setup=[InterfaceSetup] begin
    pe1_arity = [1:4, 1:4, 1:4, 1:4, 1:3, 1:3, 1:3, 1:4]
    pe1 = pairs_excursion(pe1_arity...)
    @test length(pe1) == 214
    @test length(pe1[1]) == length(pe1_arity)

    space2 = positional_space([1, 2], [true, false], ["a", "b", "c"];
                              constraints = [forbid((y, z) -> y == false && z in ("b", "c"), :p2, :p3)])
    request2 = Request(space2)
    trials2 = cases_of(request2, generate_excursion(request2; distance = 2))
    @test !isempty(trials2)
    for trial2 in trials2
        @test !(!trial2.p2 && trial2.p3 in ["b", "c"])
    end

    seeds = [[1, 2, 3, 4, 1, 2, 3, 4], fill(4, 8)]
    trials4 = pairs_excursion(fill(1:4, 8)...; seeds = seeds)
    @test seeds[1] in trials4
    @test seeds[2] in trials4
    origin = 1
    double_walk = UnitTestDesign.total_combinations(fill(3, 8), 2)
    single_walk = UnitTestDesign.total_combinations(fill(3, 8), 1)
    seed_cnt = length(seeds)
    @test length(trials4) == origin + double_walk + single_walk + seed_cnt

    # An excursion has one distance: `wayness` groups are refused (§7.5).
    params5 = fill(1:2, 20)
    wayness5 = Dict(3 => [[1, 2, 3, 4, 5], [4, 5, 6]], 4 => [collect(11:18)])
    err = try pairs_excursion(params5...; wayness = wayness5); nothing catch e; e end
    @test err isa ArgumentError && occursin("excursions take a single distance", err.msg)
    # Every row is within distance 2 of the base.
    trials6 = pairs_excursion(params5...)
    @test length(trials6) == 1 + 20 + 190
    @test all(t -> count(t .!= trials6[1]) <= 2, trials6)

    @test length(pairs_excursion([1, 2], [true, false], ["a", "b", "c"])) == 10
end


@testitem "triples excursion" begin
    te1 = triples_excursion([1:4, 1:4, 1:4, 1:4, 1:3, 1:3, 1:3, 1:4]...)
    @test length(te1) > 214
end


@testitem "full factorial" setup=[InterfaceSetup] begin
    ff1 = full_factorial([1:2, 1:2, 1:3, 1:2]...)
    @test length(ff1) == 24
    @test length(unique(ff1)) == 24
    @test length(full_factorial([1])) == 1

    space2 = positional_space([1, 2, 3], [7, 8], [true, false];
                              constraints = [forbid((b, c) -> b == 7 && c == false, :p2, :p3)])
    request2 = Request(space2; strength = 1)
    ff2 = cases_of(request2, generate_full_factorial(request2))
    @test length(ff2) == 9
    for ffs in ff2
        @test !(ffs.p2 == 7 && !ffs.p3)
    end
end
