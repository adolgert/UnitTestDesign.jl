using Test
using UnitTestDesign

res1 = UnitTestDesign.full_factorial([2, 3, 4, 2, 2], x -> false)
@test size(res1, 2) == prod([2, 3, 4, 2, 2])
@test UnitTestDesign.test_coverage(res1, [2, 3, 4, 2, 2], 5).finish == 0

omit = x -> x[3] == 4 && x[5] == 1
res2 = UnitTestDesign.full_factorial([2, 3, 4, 2, 2], omit)
@test size(res2, 2) == prod([2, 3, 4, 2, 2]) - prod([2, 3, 2])
@test UnitTestDesign.test_coverage(res2, [2, 3, 4, 2, 2], 5).finish == 22

df1 = UnitTestDesign.driven_factorial([3, 3, 2, 4, 2, 9], [1, 2, 3], x -> false)
@test maximum(df1, dims = 2)[1:3] == [3, 3, 2]
