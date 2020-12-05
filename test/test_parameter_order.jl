using Test
using UnitTestDesign
ip232 = ipog([2, 3, 2], 2)
@test size(ip232) == (3, 6)
ip2324 = ipog([2, 3, 2, 4, 7, 2], 2)
@test size(ip2324) == (6, 28)

#res = ipog([2, 3, 2, 4, 4, 4, 4, 4, 4, 4, 4, 7, 2, 4, 5, 4, 4], 3)
im232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, missing)
@test size(im232) == (3, 6)

seed232 = [2 1; 3 3; 1 2]
is232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, seed232)
# total cases doesn't change.
@test size(is232) == (3, 6)
# the test cases come first.
@test is232[:, 1:2] == seed232

not32 = (x -> (x[2] == 3 && x[3] == 2))
@test !not32([1,2,3])
@test not32([1,3,2])  # this is disallowed
ex232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, not32, missing)
# There are no tuples that are [x, 3, 2].
@test !any(sum(ex232 .== [0, 3, 2], dims = 1) .== 2)
