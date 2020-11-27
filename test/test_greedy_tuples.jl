using Test
using Random
using UnitTestDesign


### total_combinations
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

### next_multiplicative
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


### all_combinations
rng = MersenneTwister(9237425)
for ac_trial_idx in 1:5
    n_way = [2, 3, 4][rand(rng, 1:3)]
    param_cnt = rand(rng, (n_way + 1):(n_way + 3))
    arity = rand(rng, 2:4, param_cnt)
    coverage = UnitTestDesign.all_combinations(arity, n_way)
    # It has the right column dimnsion.
    @test size(coverage, 2) == length(arity)
    # Every combination is nonzero.
    @test sum(sum(coverage, dims = 2) == 0) == 0
    # The total number of combinations agrees with expectations.
    @test UnitTestDesign.total_combinations(arity, n_way) == size(coverage, 1)
    # Generate some random combinations and check that they are in there.
    for comb_idx in 1:100
        comb = [rand(rng, 1:arity[cj]) for cj in 1:param_cnt]
        comb[randperm(rng, param_cnt)[1:(param_cnt - n_way)]] .= 0
        @test sum(comb .!= 0) == n_way
        found = false
        for sidx in 1:size(coverage, 1)
            if coverage[sidx, :] == comb
                found = true
            end
        end
        @test found
    end
end

## multi_way_coverage
mwc = UnitTestDesign.multi_way_coverage([2,3,4,2,2,3], Dict(3 => [[1,4,4,5]]), 2)
@test maximum(sum(mwc .!= 0, dims = 2)) == 3

### coverage_by_paramter
cbp_cases = [
    [[0 0 0; 0 0 0; 0 1 0], 3, [0, 1, 0]],
    [[0 0 0; 0 0 0; 0 1 0], 2, [0, 0, 0]],
    [[0 0 7; 0 0 4; 0 1 0], 3, [0, 1, 2]]
]
for cbp_case in cbp_cases
    res = UnitTestDesign.coverage_by_parameter(cbp_case[1], cbp_case[2])
    @test res == cbp_case[3]
end

### coverage_by_value

cbv_cases = [
    [[0 0 0; 0 0 0; 0 0 0], 3, [2,2,2], 1, [0, 0]],
    [[0 0 0; 0 0 0; 0 0 0], 3, [2,2,2], 2, [0, 0]],
    [[0 0 0; 0 0 0; 0 0 0], 3, [2,3,2], 2, [0, 0, 0]], # sees arity of choice
    [[0 1 0; 0 1 0; 0 0 0], 3, [2,3,2], 2, [2, 0, 0]], # does multiple rows
    [[0 1 0; 0 1 0; 0 3 0], 3, [2,3,2], 2, [2, 0, 1]], # does multiple columns
    [[0 1 0; 0 1 0; 0 3 0], 2, [2,3,2], 2, [2, 0, 0]]  # excludes extra rows
]
for cbv_case in cbv_cases
    res = UnitTestDesign.coverage_by_value(cbv_case[1], cbv_case[2], cbv_case[3], cbv_case[4])
    @test res == cbv_case[5]
end

### most_matches_existing(allc, row_cnt, arity, existing, param_idx)
mmm_allc = [1 1 1 0 0; 1 2 1 0 0; 0 0 1 2 2]
mmm_arity = [2, 2, 2, 2, 2]
mmm_cases = [
    [[1, 0, 0, 0, 0], 2, [1, 1]],
    [[1, 0, 0, 0, 0], 4, [0, 0]],
    [[0, 0, 0, 0, 1], 2, [0, 0]],
    [[0, 0, 0, 0, 1], 3, [0, 0]],
    [[0, 0, 0, 0, 2], 3, [1, 0]],
    [[1, 0, 0, 0, 0], 3, [2, 0]],
    [[0, 0, 1, 0, 0], 1, [2, 0]],
    [[1, 0, 1, 0, 0], 2, [1, 1]],
    [[1, 1, 0, 0, 0], 3, [1, 0]],
    [[1, 2, 0, 0, 0], 3, [1, 0]],
    [[0, 0, 1, 0, 2], 4, [0, 1]]
]
for mmm_case in mmm_cases
    res = UnitTestDesign.most_matches_existing(mmm_allc, 3, mmm_arity, mmm_case[1], mmm_case[2])
    @test res == mmm_case[3]
end

### combination_number

for cn_a in 1:6
    for cn_b in 1:cn_a
        @test UnitTestDesign.combination_number(cn_a, cn_b) == factorial(cn_a) ÷ (factorial(cn_a - cn_b) * factorial(cn_b))
    end
end


### add_coverage!(allc, row_cnt, entry)
ac_cases = [
    [[1 1 0; 1 2 0; 1 0 1; 1 0 2], 4, 2, [1, 1, 1], 2, [1 0 2; 1 2 0; 1 1 0; 1 0 1]],
    [[1 1 0; 1 2 0; 1 0 1; 1 0 2], 3, 2, [1, 1, 1], 1, [1 2 0; 1 1 0; 1 0 1; 1 0 2]]
]
for ac_case in ac_cases
    cover0 = copy(ac_case[1])
    res = UnitTestDesign.add_coverage!(cover0, ac_case[2], ac_case[4])
    @test res == ac_case[5]
    println(cover0)
    println(ac_case[6])
    @test cover0 == ac_case[6]
end


### match_score
ms_cases = [
    [[1 1 0; 1 2 0; 0 1 3], 3, 2, [4,4,4], 0],
    [[1 1 0; 1 2 0; 0 2 1; 0 1 3], 4, 2, [1,1,1], 1],
    [[1 1 0; 1 2 0; 0 2 1; 0 1 3], 4, 2, [1,2,1], 2],
    [[1 1 0; 1 2 0; 0 2 1; 0 1 3], 4, 2, [1,1,3], 2],
    [[1 1 0; 1 2 0; 0 2 1; 0 1 3], 3, 2, [1,1,3], 1]
]
for ms_case in ms_cases
    cnt = UnitTestDesign.match_score(ms_case[1], ms_case[2], ms_case[4])
    @test cnt == ms_case[5]
end


### argmin_rand
ar_cases = [
    [[1,2,3,1,4], [1,4]],
    [[-5, -7, -6, -3], [2]],
    [[0, -1, -2, -2], [3, 4]],
    [[1,1,1,1], [1,2,3,4]]
]
ar_rng = MersenneTwister(342234)
for ar_case in ar_cases
    values = Set{Int}()
    for i in 1:10
        idx = UnitTestDesign.argmin_rand(ar_rng, ar_case[1])
        push!(values, idx)
    end
    res = sort([x for x in values])
    @test res == ar_case[2]
end


## remove_combinations
rc_cases = [
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[2] == 1 && x[3] == 1), [1 1 2; 1 2 1; 1 2 2]],
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[2] == 1), [1 2 1; 1 2 2]],
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[1] == 1 && x[3] == 1), [1 1 2; 1 2 2]],
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[2] < x[3]), [1 1 1; 1 2 1; 1 2 2]]
]
for rc_case in rc_cases
    res = UnitTestDesign.remove_combinations(rc_case[1], rc_case[2])
    @test res == rc_case[3]
end


### tuples_in_trials
tt_cases = [
    [[[1,2,3], [1,2,1], [2,3,4]], 2, 8],
    [[[1,1,1], [1,1,1], [1,1,1]], 2, 3],
    [[[1,1,1], [1,1,1], [1,1,1]], 3, 1],
]
for tt_case in tt_cases
    res = UnitTestDesign.tuples_in_trials(tt_case[1], tt_case[2])
    total_covered = sum([length(aset) for aset in values(res)])
    @test total_covered == tt_case[3]
end


### n_way_coverage
rng = Random.MersenneTwister(9234724)
arity = [2,3,2,3]
n_way = 2

M = 50
cover = n_way_coverage(arity, n_way, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
@test tuple_cnt == UnitTestDesign.total_combinations(arity, n_way)

n_way = 3
cover = n_way_coverage(arity, n_way, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
@test tuple_cnt == UnitTestDesign.total_combinations(arity, n_way)

cover = n_way_coverage_init(arity, n_way, [], M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
@test tuple_cnt == UnitTestDesign.total_combinations(arity, n_way)

seed = [
    1 1 1 1;
    1 3 1 1;
    2 2 2 2;
    2 1 2 1
]
cover = n_way_coverage_init(arity, n_way, seed, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
# It is possible for this to fail randomly.
@test tuple_cnt < UnitTestDesign.total_combinations(arity, n_way)

cover = n_way_coverage_filter(arity, n_way, x -> x[3] == 1 && x[4] != 1, [], M, rng)
n_way_coverage([4,4,4,4,4,4,4,4,4], 2, M, rng)


### n_way_coverage_multi
rng = MersenneTwister(789607)
M = 50
arity = [2,3,4,2,2,3]
n_way = 2
high_indices = [1,3,4,5]
mwc = UnitTestDesign.multi_way_coverage(arity, Dict(3 => [high_indices]), n_way)
@test maximum(sum(mwc .!= 0, dims = 2)) == 3
cov = n_way_coverage_multi(arity, mwc, x->false, [], M, rng)
cov_mat = vcat([cv' for cv in cov]...)
cov_high = cov_mat[:, high_indices]
singles = unique(sort(cov_mat[:, high_indices], dims = 1), dims = 1)

cov_high_list = [cov_high[idx, :] for idx in 1:size(cov_high, 1)]
accumulated = UnitTestDesign.tuples_in_trials(cov_high_list, 3)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cov_high_list, 3)
# This is it. The total number of 3-way tuples should match straight
# count of combinations of the four items for 3-way.
@test tuple_cnt == UnitTestDesign.total_combinations(arity[high_indices], 3)
