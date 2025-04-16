using TestItemRunner

using Random
using UnitTestDesign


@testitem "ensure these little functions are mutually exclusive" begin
    micro_set = [
        [0, 0],
        [1, 0],
        [0, 1],
        [1, 1],
        [1, 2]
    ]
    function micro_test(micro_func)
        [micro_func(a, b) for (a, b) in micro_set]
    end
    @test micro_test(UnitTestDesign.ignores) == [1, 0, 0, 0, 0]
    @test micro_test(UnitTestDesign.skips) == [0, 1, 0, 0, 0]
    @test micro_test(UnitTestDesign.misses) == [0, 0, 1, 0, 0]
    @test micro_test(UnitTestDesign.matches) == [0, 0, 0, 1, 0]
    @test micro_test(UnitTestDesign.mismatch) == [0, 0, 0, 0, 1]
end


@testitem "core comparisons" begin
    # They will all use the same test suite but will give different answers.
    compare_suite = [
        # [case, tuple]
        [[1, 0, 0, 0], [2, 0, 0, 0]],  # mismatch
        [[3, 0, 4, 0], [3, 0, 4, 0]],  # exact match
        [[1, 1, 0, 2], [1, 0, 0, 2]],  # cover, partial case
        [[1, 0, 0, 3], [1, 1, 0, 3]],  # incomplete / partial cover
        [[0, 1, 0, 2], [1, 0, 3, 0]],  # crossed
        [[1, 3, 1, 2], [0, 3, 0, 2]]   # cover, complete case
    ]
    function cs_test(compare_func)
        cs_res = zeros(Bool, length(compare_suite))
        code = 0
        for cs_idx in 1:length(compare_suite)
            case = compare_suite[cs_idx][1]
            tuple = compare_suite[cs_idx][2]
            cs_res[cs_idx] = compare_func(case, tuple)
            code <<= 1
            code |= cs_res[cs_idx]
        end
        (cs_res, code)
    end
    # match everything
    @test cs_test(UnitTestDesign.case_compatible_with_tuple)[2] == 31
    cpc_res = cs_test(UnitTestDesign.case_partial_cover)
    @test cpc_res[2] == 29
    cpt_res = cs_test(UnitTestDesign.case_covers_tuple)
    @test cpt_res[2] == 25
end


@testitem "coverage_by_parameter" begin
    cbp_cases = [
        [[0 0 0; 0 0 0; 0 1 0]', 3, [0, 1, 0]],
        [[0 0 0; 0 0 0; 0 1 0]', 2, [0, 0, 0]],
        [[0 0 7; 0 0 4; 0 1 0]', 3, [0, 1, 2]]
    ]
    for cbp_case in cbp_cases
        mc = UnitTestDesign.MatrixCoverage(collect(cbp_case[1]), cbp_case[2], [2, 2, 7])
        res = UnitTestDesign.coverage_by_parameter(mc)
        @test res == cbp_case[3]
    end
end

@testitem "one parameter combinations matrix" begin
    mc_opcm = UnitTestDesign.one_parameter_combinations_matrix([2, 2, 3], 2)
    @test mc_opcm.remain == 4 * 3
end


@testitem "coverage_by_value" begin

    # (coverage matrix, remaining uncovered, arity,
    #  parameter, coverage of that parameter)
    cbv_cases = [
        [[0 0 0; 0 0 0; 0 0 0]', 3, [2,2,2], 1, [0, 0]],
        [[0 0 0; 0 0 0; 0 0 0]', 3, [2,2,2], 2, [0, 0]],
        [[0 0 0; 0 0 0; 0 0 0]', 3, [2,3,2], 2, [0, 0, 0]], # sees arity of choice
        [[0 1 0; 0 1 0; 0 0 0]', 3, [2,3,2], 2, [2, 0, 0]], # does multiple rows
        [[0 1 0; 0 1 0; 0 3 0]', 3, [2,3,2], 2, [2, 0, 1]], # does multiple columns
        [[0 1 0; 0 1 0; 0 3 0]', 2, [2,3,2], 2, [2, 0, 0]]  # excludes extra rows
    ]
    for cbv_case in cbv_cases
        mc = UnitTestDesign.MatrixCoverage(collect(cbv_case[1]), cbv_case[2], cbv_case[3])
        res = UnitTestDesign.coverage_by_value(mc, cbv_case[4])
        @test res == cbv_case[5]
    end
end


@testitem "most_matches_existing(allc, row_cnt, arity, existing, param_idx)" begin
    mmm_allc = [1 1 1 0 0; 1 2 1 0 0; 0 0 1 2 2]'
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
        mc = UnitTestDesign.MatrixCoverage(collect(mmm_allc), 3, mmm_arity)
        res = UnitTestDesign.most_matches_existing(mc, mmm_case[1], mmm_case[2])
        @test res == mmm_case[3]
    end
end


@testitem "most_matches_existing" begin
    # Let's understand this most_matches_existing function by assuming,
    # at this point, that it obeys the condition that the given parameter
    # index must be nonzero. Let's always put that last. And let's just make
    # one row to cover or not cover. Test for yes or no.
    mm2_arity = [2, 2, 2, 2]
    # test is a) a tuple to cover, b) an existing array. The param_idx is the last entry,
    # so that's always zero for the "existing" array.
    mm2_cases = [
        [[1; 1; 0; 1], [1, 1, 0, 0], 1],
        [[1; 1; 0; 1], [1, 0, 0, 0], 1],
        [[1; 1; 0; 1], [0, 0, 0, 0], 1],
        [[1; 1; 0; 1], [1, 0, 2, 0], 0],  # This could be a 1. This is subtle. Must match all existing.
        [[1; 1; 0; 1], [1, 1, 2, 0], 0]   # again, compatible but not exact.
    ]
    for mm2_case in mm2_cases
        mc = UnitTestDesign.MatrixCoverage(reshape(mm2_case[1], length(mm2_arity), 1), 1, mm2_arity)
        res = UnitTestDesign.most_matches_existing(mc, mm2_case[2], length(mm2_arity))
        @test res == [mm2_case[3], 0]
    end
end


@testitem "insert_tuple_into_tests" begin
    test_set = [
        1 1 1;
        1 0 3;
        1 3 2;
        1 2 2
    ]
    allc = UnitTestDesign.MatrixCoverage(
        [
            1 2 0
            1 0 1
            0 0 3
            0 0 0
        ],
        3,
        [2, 3, 3]
    )
    UnitTestDesign.insert_tuple_into_tests(test_set, allc)
end


@testitem "matches from missing" begin
    wider = [
        1 1 0; 1 2 0; 2 1 0;
        2 2 0; 3 1 0; 3 2 0
    ]
    arity4 = [3, 2, 2]
    allc4 = [
        1 0 1; 2 0 1; 3 0 1; 0 1 1; 0 2 1;
        1 0 2; 2 0 2; 3 0 2; 0 1 2; 0 2 2
    ]'
    mc4 = UnitTestDesign.MatrixCoverage(collect(allc4), size(allc4, 2), arity4)
    mm4 = UnitTestDesign.matches_from_missing(mc4, wider[1, :], 3)
    @test mm4 == [2, 2]
end



@testitem "first_match_for_parameter(mc, param_idx)" begin
    arity = [3, 2, 2, 2]
    mat = [0 1 2 0; 2 2 1 0]'
    mcfm = UnitTestDesign.MatrixCoverage(collect(mat), size(mat, 2), arity)
    fm1 = UnitTestDesign.first_match_for_parameter(mcfm, 3)
    @test fm1 == [0, 1, 2, 0]
    blank = UnitTestDesign.first_match_for_parameter(mcfm, 1)
    @test blank == [2, 2, 1, 0]
    lack = UnitTestDesign.first_match_for_parameter(mcfm, 4)
    @test lack == [0, 0, 0, 0]
end


@testitem "fill_consistent_matches" begin
    arity = [2, 4, 4]
    mat = [
        0 0 0;
        1 0 0;
        0 2 0;
        0 0 3;
        0 0 4
    ]'
    mc = UnitTestDesign.MatrixCoverage(collect(mat), size(mat, 2), arity)
    res1 = UnitTestDesign.fill_consistent_matches(mc, [0, 2, 0])
    @test res1 == [1, 2, 3]
end

@testitem "fill_consistent_matches incrmental change" begin
    arity = [2, 4, 4]
    mat2 = [
        0 0 0;
        1 2 0; # change here
        0 2 0;
        1 0 4;
        0 0 3
    ]'
    mc2 = UnitTestDesign.MatrixCoverage(collect(mat2), size(mat2, 2), arity)
    res2 = UnitTestDesign.fill_consistent_matches(mc2, [0, 2, 0])
    @test res2 == [1, 2, 4]
end

@testitem "fill_consistent_matches another increment" begin
    arity = [2, 4, 4]
    mat3 = [
        0 0 0;
        1 2 0;
        0 2 0;
        0 0 3;
        1 0 4
    ]'
    mc3 = UnitTestDesign.MatrixCoverage(collect(mat3), size(mat3, 2), arity)
    res3 = UnitTestDesign.fill_consistent_matches(mc3, [0, 2, 0])
    @test res3 == [1, 2, 3]
end

@testitem "add_coverage!(allc, row_cnt, entry)" begin
    # This checks that the rows of the matrix are reordered
    # when a new test covers values. It expects a particular
    # reordering due to swapping. Very much an implementation test.
    ac_cases = [
        [[1 1 0; 1 2 0; 1 0 1; 1 0 2]', 4, 2, [1, 1, 1], 2, [1 0 2; 1 2 0; 1 1 0; 1 0 1]'],
        [[1 1 0; 1 2 0; 1 0 1; 1 0 2]', 3, 2, [1, 1, 1], 1, [1 2 0; 1 1 0; 1 0 1; 1 0 2]'],
        [[1 0 2; 0 2 2; 0 1 2]', 1, 2, [1, 0, 2], 0, [1 0 2; 0 2 2; 0 1 2]'],
        [[1 0 2; 0 2 2; 0 1 2]', 1, 2, [1, 0, 1], 1, [1 0 2; 0 2 2; 0 1 2]']
    ]
    for ac_case in ac_cases
        mcac = UnitTestDesign.MatrixCoverage(collect(ac_case[1]), ac_case[2], [2, 3, 2])
        UnitTestDesign.add_coverage!(mcac, ac_case[4])
        @test mcac.remain == ac_case[5]
        @test mcac.allc == ac_case[6]
    end
end


@testitem "match_score" begin
    ms_cases = [
        [[1 1 0; 1 2 0; 0 1 3]', 3, 2, [4,4,4], 0],
        [[1 1 0; 1 2 0; 0 2 1; 0 1 3]', 4, 2, [1,1,1], 1],
        [[1 1 0; 1 2 0; 0 2 1; 0 1 3]', 4, 2, [1,2,1], 2],
        [[1 1 0; 1 2 0; 0 2 1; 0 1 3]', 4, 2, [1,1,3], 2],
        [[1 1 0; 1 2 0; 0 2 1; 0 1 3]', 3, 2, [1,1,3], 1]
    ]
    for ms_case in ms_cases
        mc_ms = UnitTestDesign.MatrixCoverage(collect(ms_case[1]), ms_case[2], [4, 4, 4])
        cnt = UnitTestDesign.match_score(mc_ms, ms_case[4])
        @test cnt == ms_case[5]
    end
end


@testitem "remove_combinations" begin
    rc_cases = [
        [[1 1 1; 1 1 2; 1 2 1; 1 2 2]', (x -> x[2] == 1 && x[3] == 1), [1 1 2; 1 2 1; 1 2 2]'],
        [[1 1 1; 1 1 2; 1 2 1; 1 2 2]', (x -> x[2] == 1), [1 2 1; 1 2 2]'],
        [[1 1 1; 1 1 2; 1 2 1; 1 2 2]', (x -> x[1] == 1 && x[3] == 1), [1 1 2; 1 2 2]'],
        [[1 1 1; 1 1 2; 1 2 1; 1 2 2]', (x -> x[2] < x[3]), [1 1 1; 1 2 1; 1 2 2]']
    ]
    for rc_case in rc_cases
        mc_rc = UnitTestDesign.MatrixCoverage(collect(rc_case[1]), 4, [2, 3, 2])
        UnitTestDesign.remove_combinations!(mc_rc, rc_case[2])
        @test mc_rc.allc == rc_case[3]
    end
end


@testitem "multi_way_coverage" begin
    mwc = UnitTestDesign.multi_way_coverage([2,3,4,2,2,3], Dict(3 => [[1,3,4,5]]), 2)
    @test maximum(sum(mwc .!= 0, dims = 1)) == 3
    @inferred UnitTestDesign.multi_way_coverage([2,3,4,2,2,3], Dict(3 => [[1,3,4,5]]), 2)
end
