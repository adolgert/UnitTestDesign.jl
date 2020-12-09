using Test
using Random
using UnitTestDesign


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


n_way = 2
M = 50
rng = MersenneTwister(97072343)
arity = [5, 4, 3, 2, 2]
cover = UnitTestDesign.n_way_coverage_filter(arity, n_way, x -> x[3] == 1 && x[4] != 1, [], M, rng)
nn = UnitTestDesign.n_way_coverage([4,4,4,4,4,4,4,4,4], 2, M, rng)
@test length(nn) > 20
@test length(nn) < 100

### n_way_coverage_multi
rng = MersenneTwister(789607)
M = 50
arity = [2,3,4,2,2,3]
n_way = 2
high_indices = [1,3,4,5]
mwc = UnitTestDesign.multi_way_coverage(arity, Dict(3 => [high_indices]), n_way)
@test maximum(sum(mwc .!= 0, dims = 1)) == 3
mc = UnitTestDesign.MatrixCoverage(mwc, size(mwc, 1), arity)
cov = UnitTestDesign.n_way_coverage_multi(mc, x->false, [], M, rng)
cov_mat = vcat([cv' for cv in cov]...)
cov_high = cov_mat[:, high_indices]
singles = unique(sort(cov_mat[:, high_indices], dims = 1), dims = 1)

cov_high_list = [cov_high[idx, :] for idx in 1:size(cov_high, 1)]
accumulated = UnitTestDesign.tuples_in_trials(cov_high_list, 3)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cov_high_list, 3)
# This is it. The total number of 3-way tuples should match straight
# count of combinations of the four items for 3-way.
@test tuple_cnt == UnitTestDesign.total_combinations(arity[high_indices], 3)


### n_way_coverage
rng = Random.MersenneTwister(9234724)
arity = [2,3,2,3]
n_way = 2

M = 50
cover = UnitTestDesign.n_way_coverage(arity, n_way, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
@test tuple_cnt == UnitTestDesign.total_combinations(arity, n_way)

n_way = 3
cover = UnitTestDesign.n_way_coverage(arity, n_way, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
@test tuple_cnt == UnitTestDesign.total_combinations(arity, n_way)

cover = UnitTestDesign.n_way_coverage_init(arity, n_way, [], M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
@test tuple_cnt == UnitTestDesign.total_combinations(arity, n_way)

rng = Random.MersenneTwister(9234724)
arity = [2,3,2,3]
n_way = 3

M = 50
seed = [
    1 1 1 1;
    1 3 1 1;
    2 2 2 2;
    2 1 2 1
]
cover = UnitTestDesign.n_way_coverage_init(arity, n_way, seed, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
# It is possible for this to fail randomly.
@test tuple_cnt < UnitTestDesign.total_combinations(arity, n_way)
