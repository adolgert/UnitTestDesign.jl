using Test

using TestItemRunner

using UnitTestDesign

@testitem "full factorial with exclusion" begin
    res1 = UnitTestDesign.full_factorial([2, 3, 4, 2, 2], x -> false)
    @test size(res1, 2) == prod([2, 3, 4, 2, 2])
    @test UnitTestDesign.test_coverage(res1, [2, 3, 4, 2, 2], 5).finish == 0
end


@testitem "full factorial with two exclusions" begin
    omit = x -> x[3] == 4 && x[5] == 1
    res2 = UnitTestDesign.full_factorial([2, 3, 4, 2, 2], omit)
    @test size(res2, 2) == prod([2, 3, 4, 2, 2]) - prod([2, 3, 2])
    @test UnitTestDesign.test_coverage(res2, [2, 3, 4, 2, 2], 5).finish == 12
end
