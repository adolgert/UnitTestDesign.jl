using Test
using Random

using TestItemRunner

using UnitTestDesign

@testitem "ipog base" begin
    ip232 = UnitTestDesign.ipog([2, 3, 2], 2)
    @test size(ip232) == (3, 6)
    @inferred UnitTestDesign.ipog([2, 3, 2], 2)
    ip2324 = UnitTestDesign.ipog([2, 3, 2, 4, 7, 2], 2)
    @test size(ip2324) == (6, 28)
end

@testitem "ipog multi" begin
    im232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, nothing)
    @test size(im232) == (3, 6)
    @test UnitTestDesign.test_coverage(im232, [2, 3, 2], 2) == (start = 16, finish = 0)
end

@testitem "ipog multi with seed and exclusion" begin
    seed232 = [2 1; 3 3; 1 2]
    is232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, seed232)
    @inferred UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, seed232)
    # total cases doesn't change.
    @test size(is232) == (3, 6)
    # the test cases come first.
    @test is232[:, 1:2] == seed232
end


@testitem "reorder disallow forbid" begin
    not32 = (x -> (length(x) >= 3 && x[2] == 3 && x[3] == 2))
    @test !not32([1, 1])
    @test !not32([1,2,3])
    @test not32([1,3,2])  # this is disallowed
    @test not32([2,3,2])  # this is disallowed
    forbid32 = UnitTestDesign.reorder_disallow(not32, [2, 1, 3])
    @test !forbid32([1, 1])
    @test !forbid32([1,2,3])
    @test !forbid32([1,3,2])  # this is allowed
    @test !forbid32([2,3,2])  # this is allowed
    @test forbid32([3, 1, 2])
    @test forbid32([3, 1, 2])
end


@testitem "ipog multi ensure none of certain tuple" begin
    not32 = (x -> (length(x) >= 3 && x[2] == 3 && x[3] == 2))
    ex232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, not32, nothing)
    # There are no tuples that are [x, 3, 2].
    @test !any(sum(ex232 .== [0, 3, 2], dims = 1) .== 2)
end


@testitem "long random of ipog_multi" begin
    using Random
    CI = get(ENV, "CI", false) == "true"

    rng = Xoshiro(90714134)
    test_time = CI ? 5 : 30
    max_n = CI ? 6 : 10
    max_arity = CI ? 5 : 7
    start_time = time()
    while time() - start_time < test_time
        n = rand(rng, 3:max_n)
        local arity
        arity = rand(rng, 2:max_arity, n)
        k = rand(rng, 2:minimum([4, n]))
        # println("$(arity) $(k)")
        r1 = UnitTestDesign.ipog_multi(arity, k, x -> false, nothing)
        # println("$(size(r1))")
        cover1 = UnitTestDesign.test_coverage(r1, arity, k)
        @test cover1.finish == 0
    end
end

@testitem "all combinations long random" begin
    using Random
    CI = get(ENV, "CI", false) == "true"

    rng = Xoshiro(2424324)
    test_time = CI ? 2 : 30
    max_n = CI ? 6 : 10
    max_arity = CI ? 5 : 7
    start_time = time()
    not32 = (x -> (length(x) >= 3 && x[2] == 3 && x[3] == 2))
    while time() - start_time < test_time
        n = rand(rng, 3:max_n)
        local arity
        arity = rand(rng, 2:max_arity, n)
        arity[2] = maximum([3, arity[2]]) # make sure it's >=3.
        k = rand(rng, 2:minimum([4, n]))
        # println("$(arity) $(k)")
        r2 = UnitTestDesign.ipog_multi(arity, k, not32, nothing)
        # println("$(size(r2))")
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
        @test !any(sum(r2 .== compare, dims = 1) .== 2)
    end
end


@testitem "test coverage specific" begin
    imw_arity = [2, 3, 2, 3]
    imw_k = 2
    imw_ind = [1, 3, 4]
    imw1 = UnitTestDesign.ipog_multi_way(imw_arity, imw_k, Dict(3 => [imw_ind]), x -> false, nothing)
    @inferred UnitTestDesign.ipog_multi_way(imw_arity, imw_k, Dict(3 => [imw_ind]), x -> false, nothing)
    imw_cover1 = UnitTestDesign.test_coverage(imw1, imw_arity, imw_k)
    @test imw_cover1.finish == 0
    imw_cover2 = UnitTestDesign.test_coverage(imw1[imw_ind, :], imw_arity[imw_ind], 3)
    @test imw_cover2.finish == 0
    oind1 = [1, 2, 3]
    imw_cover3 = UnitTestDesign.test_coverage(imw1[oind1, :], imw_arity[oind1], 3)
    oind2 = [2, 3, 4]
    imw_cover4 = UnitTestDesign.test_coverage(imw1[oind2, :], imw_arity[oind2], 3)
    @test imw_cover3.finish + imw_cover4.finish > 0

    # What if we do the whole set at 3-way? It's the same number of tests,
    # so we didn't gain anything in this case by using multi-wayness.
    im11 = UnitTestDesign.ipog_multi(imw_arity, 3, x -> false, nothing)
    im11_cover = UnitTestDesign.test_coverage(im11, imw_arity, 3)
    @test im11_cover.finish == 0
end


@testitem "seeding of tests" begin
    @test UnitTestDesign.add_tests_to_seeds([0 0; 0 0], [0 0; 0 0]) == [0 0; 0 0]
    @test UnitTestDesign.add_tests_to_seeds([0 0; 0 0], [1 0; 0 0]) == [1 0; 0 0]
    @test UnitTestDesign.add_tests_to_seeds([0 0; 0 0], [1 0; 0 2]) == [1 0; 2 0]
    @test UnitTestDesign.add_tests_to_seeds([0 0; 0 0], [1 0; 3 2]) == [1 0; 3 2]
    @test UnitTestDesign.add_tests_to_seeds([0 0; 4 0], [1 0; 3 2]) == [0 1 0; 4 3 2]
    @test UnitTestDesign.add_tests_to_seeds([0 0; 4 0], [1 7; 3 2]) == [0 1 7; 4 3 2]
    @test UnitTestDesign.add_tests_to_seeds([0 0; 0 0], [1 7; 3 2]) == [1 7; 3 2]
end
