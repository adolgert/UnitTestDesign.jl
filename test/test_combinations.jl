using Test
using Random

using TestItemRunner



@testitem "total combinations from integers" begin
    tc_trials = [
        [[2, 2, 2], 2, 12],
        [[2, 3, 2], 2, 16],
        [[2, 3, 2, 2], 2, 6+4+4+6+6+4],
        [[2, 3, 2, 2], 3, 12+12+8+12]
    ]
    for trial in tc_trials
        res = UnitTestDesign.total_combinations(trial[1], trial[2])
        @test res == trial[3]
    end
end


@testitem "number of combinations" begin
    for cn_a in 1:6
        for cn_b in 1:cn_a
            oracle = factorial(cn_a) ÷ (factorial(cn_a - cn_b) * factorial(cn_b))
            @test UnitTestDesign.combination_number(cn_a, cn_b) == oracle
        end
    end
end


@testitem "next multiplicative value" begin
    arity0 = [3, 7, 9, 4]
    vv0 = copy(arity0)
    UnitTestDesign.next_multiplicative!(vv0, arity0)
    @test vv0 == [1, 1, 1, 1]
    vv = [1,1,1]
    nmarity = [2,3,2]
    for i in 1:prod(nmarity)
        UnitTestDesign.next_multiplicative!(vv, nmarity)
    end
    @test vv == [1, 1, 1]
end


@testitem "All combinations" setup=[UTSetup] begin
    using Random
    rng = Xoshiro(9237425 ⊻ seed_mod())
    test_time = 30 * test_run_multiplier()

    start_time = time()
    while time() - start_time < test_time
        n_way = [2, 3, 4][rand(rng, 1:3)]
        param_cnt = rand(rng, (n_way + 1):(n_way + 3))
        arity = rand(rng, 2:4, param_cnt)
        coverage = UnitTestDesign.all_combinations(arity, n_way)
        # It has the right column dimnsion.
        @test size(coverage, 1) == length(arity)
        # Every combination is nonzero.
        @test sum(sum(coverage, dims = 1) == 0) == 0
        # The total number of combinations agrees with expectations.
        @test UnitTestDesign.total_combinations(arity, n_way) == size(coverage, 2)
        # Generate some random combinations and check that they are in there.
        for comb_idx in 1:100
            comb = [rand(rng, 1:arity[cj]) for cj in 1:param_cnt]
            comb[randperm(rng, param_cnt)[1:(param_cnt - n_way)]] .= 0
            @test sum(comb .!= 0) == n_way
            found = false
            for sidx in 1:size(coverage, 2)
                if coverage[:, sidx] == comb
                    found = true
                end
            end
            @test found
        end
    end
end


@testitem "one_parameter_combinations(arity, n_way)" begin

    minimal = UnitTestDesign.one_parameter_combinations([2, 3], 1)
    @test minimal == [0 1; 0 2; 0 3]'

    paired = UnitTestDesign.one_parameter_combinations([2, 3], 2)
    @test paired == [1 1; 2 1; 1 2; 2 2; 1 3; 2 3]'

    singled = UnitTestDesign.one_parameter_combinations([2, 2, 3], 2)
    @test singled == [
        1 0 1; 2 0 1; 0 1 1; 0 2 1;
        1 0 2; 2 0 2; 0 1 2; 0 2 2;
        1 0 3; 2 0 3; 0 1 3; 0 2 3
        ]'

    again = UnitTestDesign.one_parameter_combinations([2, 2, 3], 3)
    @test again == [
        1 1 1; 1 2 1; 2 1 1; 2 2 1;
        1 1 2; 1 2 2; 2 1 2; 2 2 2;
        1 1 3; 1 2 3; 2 1 3; 2 2 3
        ]'
end
