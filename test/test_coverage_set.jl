using Test
using TestItemRunner


@testitem "tuples_in_trials set-based" begin
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
end


@testitem "coverage from a set" begin
    sc = UnitTestDesign.SetCoverage([2,3,2], 2)
    @test UnitTestDesign.remaining(sc) == 0
    @test eltype(sc) == Int64
    UnitTestDesign.build_all_combinations!(sc, 2)
    @test UnitTestDesign.remaining(sc) == 16
    @test UnitTestDesign.add_coverage!(sc, [1, 1, 1]) == 3
    @test UnitTestDesign.remaining(sc) == 13
    @test UnitTestDesign.add_coverage!(sc, [1, 2, 1]) == 2
    @test UnitTestDesign.remaining(sc) == 11
end


@testitem "all combinations from a set" begin
    sc = UnitTestDesign.SetCoverage([2,3,2], 2)
    UnitTestDesign.build_all_combinations!(sc, 2)
    multiple = [2 2; 2 3; 1 2]
    @test UnitTestDesign.add_coverage!(sc, multiple) == 6
    @test UnitTestDesign.remaining(sc) == 10
end


@testitem "Add two types of coverage" begin
    sc = UnitTestDesign.SetCoverage([2,3,2], 2)
    UnitTestDesign.build_all_combinations!(sc, 2)
    UnitTestDesign.build_all_combinations!(sc, 3)
    @test UnitTestDesign.remaining(sc) == 28
end
