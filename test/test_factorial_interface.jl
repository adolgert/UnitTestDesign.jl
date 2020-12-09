using Test

### wrap_disallow, an internal function.

@safetestset wrap_disallow_tests = "wrap_disallow" begin
    using UnitTestDesign

    function filter_bc(a, b, c)
        !b && c == "two"
    end
    @assert !filter_bc(1, false, "one")
    @assert !filter_bc(1, true, "two")
    @assert filter_bc(1, false, "two")  # So we disallow this one.
    @assert !filter_bc(1, true, "two")
    function parameter_filter(choices, filter, parameter_map)
        filter((p[c] for (p, c) in zip(parameter_map, choices))...)
    end

    params = ([1,2,3], [true, false], ["one", "two"])
    pf1 = UnitTestDesign.wrap_disallow(filter_bc, params)
    # These should mirror the ones above.
    @assert !pf1([1, 2, 1])
    @assert !pf1([1, 1, 2])
    @assert pf1([1, 2, 2])
    @assert !pf1([1, 1, 2])

end

## seeds_to_integers, an internal function

@safetestset seeds_to_integers_tests = "seeds_to_integers" begin
    using UnitTestDesign

    params = (["a", "b", "c"], [1, 2], [4, 7])
    seeds = [["a", 2, 4], ["b", 1, 7]]
    sti_res = UnitTestDesign.seeds_to_integers(seeds, params)
    @test sti_res == collect([1 2 1; 2 1 2]')

end

## IPOG

@safetestset IPOG_init_test = "IPOG init" begin
    using UnitTestDesign
    ipog = IPOG()
    @test isa(ipog, IPOG)
end

## GND

@safetestset GND_init_tests = "GND init" begin
    using Random
    using UnitTestDesign
    gnd1 = GND()
    @test gnd1.M == 50
    sample1 = randn(gnd1.rng)
    gnd2 = GND(M = 100)
    @test gnd2.M == 100
    sample2 = randn(gnd2.rng)
    @test sample1 != sample2
    gnd3 = GND(rng = MersenneTwister(23423523))
    @test gnd3.M == 50
    sample3 = randn(gnd3.rng)
    @test sample3 != sample2
    gnd4 = GND(rng = MersenneTwister(23423523))
    sample4 = randn(gnd4.rng)
    @test sample3 == sample4
    gnd5 = GND(rng = MersenneTwister(23423523), M = 70)
    @test gnd5.M == 70
    @test randn(gnd5.rng) == sample3
end

## generate_tuples(IPOG())

@safetestset IPOG_gen_tuples_test = "IPOG generate tuples" begin
    using UnitTestDesign
    trials1 = generate_tuples(IPOG(), 2, ([1, 2], [true, false], ["a", "b", "c"]))
    @test length(trials1) == 6
    @test trials1[1][3] in ["a", "b", "c"]
end

@safetestset GND_gen_tuples_test = "GND generate tupels" begin
    using UnitTestDesign
    gndt1 = generate_tuples(GND(), 2, ([1, 2], [true, false], ["a", "b", "c"]))
    @test length(gndt1) > 3
    @test gndt1[1][2] in [true, false]
    @test gndt1[1][3] in ["a", "b", "c"]
end

## all_values
@safetestset IPOG_all_values_test = "IPOG generate tuples" begin
    using UnitTestDesign

    av1 = all_values([1, 2], ["a", "b", "c"], [4, 7])
    @test length(av1) == 3
    @test av1[1][3] in [4, 7]

end

## all_pairs
@safetestset IPOG_gen_pairs_test = "IPOG generate tuples" begin
    using UnitTestDesign

    pairs1 = all_pairs([1, 2], ["a", "b", "c"], [4, 7])
    @test length(pairs1) > 3
    @test pairs1[1][3] in [4, 7]

end

## all_triples
@safetestset IPOG_gen_triples_test = "IPOG generate tuples" begin
    using UnitTestDesign
    at1 = all_triples([1, 2], ["a", "b", "c"], [4, 7], [true, false])
    @test length(at1) > 8
    @test at1[1][3] in [4, 7]
    @test length(at1[1]) == 4
end


@safetestset values_excursion_test = "values excursion" begin
    using UnitTestDesign
    ve1_params = [1:3, 1:2, 1:4, 1:2, 1:2]
    ve1 = values_excursion(ve1_params...)
    ve1_arity = maximum.(ve1_params)
    @test length(ve1) == sum(ve1_arity .- 1)
end


@safetestset pairs_excursion_test = "pairs excursion" begin
    using UnitTestDesign
    pe1_arity = [1:4, 1:4, 1:4, 1:4, 1:3, 1:3, 1:3, 1:4]
    pe1 = pairs_excursion(pe1_arity...)
    @test length(pe1) == 213
    @test length(pe1[1]) == length(pe1_arity)
end


@safetestset triples_excursion_test = "triples excursion" begin
    using UnitTestDesign
    te1 = triples_excursion([1:4, 1:4, 1:4, 1:4, 1:3, 1:3, 1:3, 1:4]...)
end


@safetestset full_factorial_test = "full factorial" begin
    using UnitTestDesign
    ff1 = full_factorial([1:2, 1:2, 1:3, 1:2]...)
end
