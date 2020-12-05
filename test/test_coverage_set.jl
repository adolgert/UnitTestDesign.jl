
#### Set-based

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
cover = n_way_coverage_init(arity, n_way, seed, M, rng)
tuple_cnt = UnitTestDesign.coverage_by_tuple(cover, n_way)
# It is possible for this to fail randomly.
@test tuple_cnt < UnitTestDesign.total_combinations(arity, n_way)
