using Test
using TestItemRunner


@testitem "arity excursion with an exclusion" begin
    be1_arity = [2, 3, 2, 4]
    be1_res = UnitTestDesign.build_excursion(be1_arity, 2, x -> false)
    @test size(be1_res) == (4, 25)
end


@testitem "arity excursion with two exclusions" begin
    be2_arity = [2, 3, 2, 4]
    be2_res = UnitTestDesign.build_excursion(be2_arity, 2, x -> x[3] == 2 && x[4] > 2)
    @test size(be2_res) == (4, 23)
end


@testitem "arity exclusion with a seed" begin
    be3_arity = [2, 3, 2, 4]
    # one new and one already in the set.
    be3_seed = [2 1; 3 1; 2 1; 4 2]
    be3_res = UnitTestDesign.build_excursion(be3_arity, 2, x -> false, be3_seed)
    @test be3_res[:, 1] == be3_seed[:, 1]
    @test size(be3_res) == (4, 26)  # adds one to total length.
    be4_arity = [2, 3, 2, 4]
    be4_seed = [2 1; 3 1; 2 1; 4 2]
    levels = Dict{Int,Array{Array{Int,1},1}}()
    be4_res = UnitTestDesign.build_excursion_multi(be4_arity, 2, levels, x -> false, be4_seed)
    @test be4_res[:, 1] == be4_seed[:, 1]
    @test size(be4_res) == (4, 26)
    @test be4_res == be3_res
end

@testitem "arity exclusion levels dictionary" begin
    be5_arity = [2, 3, 2, 4]
    be5_seed = [2 1; 3 1; 2 1; 4 2]
    levels = Dict(3 => [[1, 2, 3], [2, 3, 4]])
    be5_res = UnitTestDesign.build_excursion_multi(be5_arity, 2, levels, x -> false, be5_seed)
    @test be5_res[:, 1] == be5_seed[:, 1]
    @test size(be5_res) == (4, 1 +25 + 2*1 + 3*2)
    @inferred UnitTestDesign.build_excursion_multi(be5_arity, 2, levels, x -> false, be5_seed)
end
