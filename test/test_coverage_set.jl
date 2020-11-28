using Test
using Random
using UnitTestDesign

### coverage_by_parameter
cbp_cases = [
    [[0 0 0; 0 0 0; 0 1 0], 3, [0, 1, 0]],
    [[0 0 0; 0 0 0; 0 1 0], 2, [0, 0, 0]],
    [[0 0 7; 0 0 4; 0 1 0], 3, [0, 1, 2]]
]
for cbp_case in cbp_cases
    mc = UnitTestDesign.MatrixCoverage(cbp_case[1], cbp_case[2], [2, 2, 7])
    res = UnitTestDesign.coverage_by_parameter(mc)
    @test res == cbp_case[3]
end


### coverage_by_value

# (coverage matrix, remaining uncovered, arity,
#  parameter, coverage of that parameter)
cbv_cases = [
    [[0 0 0; 0 0 0; 0 0 0], 3, [2,2,2], 1, [0, 0]],
    [[0 0 0; 0 0 0; 0 0 0], 3, [2,2,2], 2, [0, 0]],
    [[0 0 0; 0 0 0; 0 0 0], 3, [2,3,2], 2, [0, 0, 0]], # sees arity of choice
    [[0 1 0; 0 1 0; 0 0 0], 3, [2,3,2], 2, [2, 0, 0]], # does multiple rows
    [[0 1 0; 0 1 0; 0 3 0], 3, [2,3,2], 2, [2, 0, 1]], # does multiple columns
    [[0 1 0; 0 1 0; 0 3 0], 2, [2,3,2], 2, [2, 0, 0]]  # excludes extra rows
]
for cbv_case in cbv_cases
    mc = UnitTestDesign.MatrixCoverage(cbv_case[1], cbv_case[2], cbv_case[3])
    res = UnitTestDesign.coverage_by_value(mc, cbv_case[4])
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
    mc = UnitTestDesign.MatrixCoverage(mmm_allc, 3, mmm_arity)
    res = UnitTestDesign.most_matches_existing(mc, mmm_case[1], mmm_case[2])
    @test res == mmm_case[3]
end


### add_coverage!(allc, row_cnt, entry)
# This checks that the rows of the matrix are reordered
# when a new test covers values. It expects a particular
# reordering due to swapping. Very much an implementation test.
ac_cases = [
    [[1 1 0; 1 2 0; 1 0 1; 1 0 2], 4, 2, [1, 1, 1], 2, [1 0 2; 1 2 0; 1 1 0; 1 0 1]],
    [[1 1 0; 1 2 0; 1 0 1; 1 0 2], 3, 2, [1, 1, 1], 1, [1 2 0; 1 1 0; 1 0 1; 1 0 2]]
]
for ac_case in ac_cases
    mc = UnitTestDesign.MatrixCoverage(ac_case[1], ac_case[2], [2, 3, 2])
    UnitTestDesign.add_coverage!(mc, ac_case[4])
    @test mc.remain == ac_case[5]
    @test mc.allc == ac_case[6]
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
    mc = UnitTestDesign.MatrixCoverage(ms_case[1], ms_case[2], [4, 4, 4])
    cnt = UnitTestDesign.match_score(mc, ms_case[4])
    @test cnt == ms_case[5]
end


## remove_combinations
rc_cases = [
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[2] == 1 && x[3] == 1), [1 1 2; 1 2 1; 1 2 2]],
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[2] == 1), [1 2 1; 1 2 2]],
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[1] == 1 && x[3] == 1), [1 1 2; 1 2 2]],
    [[1 1 1; 1 1 2; 1 2 1; 1 2 2], (x -> x[2] < x[3]), [1 1 1; 1 2 1; 1 2 2]]
]
for rc_case in rc_cases
    mc = UnitTestDesign.MatrixCoverage(rc_case[1], 4, [2, 3, 2])
    UnitTestDesign.remove_combinations!(mc, rc_case[2])
    @test mc.allc == rc_case[3]
end








## multi_way_coverage
mwc = UnitTestDesign.multi_way_coverage([2,3,4,2,2,3], Dict(3 => [[1,4,4,5]]), 2)
@test maximum(sum(mwc .!= 0, dims = 2)) == 3
