using Test
using Random
using UnitTestDesign

ip232 = ipog([2, 3, 2], 2)
@test size(ip232) == (3, 6)
ip2324 = ipog([2, 3, 2, 4, 7, 2], 2)
@test size(ip2324) == (6, 28)

im232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, missing)
@test size(im232) == (3, 6)
@test UnitTestDesign.test_coverage(im232, [2, 3, 2], 2) == (start = 16, finish = 0)

seed232 = [2 1; 3 3; 1 2]
is232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, x -> false, seed232)
# total cases doesn't change.
@test size(is232) == (3, 6)
# the test cases come first.
@test is232[:, 1:2] == seed232

not32 = (x -> (length(x) >= 3 && x[2] == 3 && x[3] == 2))
@test !not32([1, 1])
@test !not32([1,2,3])
@test not32([1,3,2])  # this is disallowed
@test not32([2,3,2])  # this is disallowed
forbid32 = UnitTestDesign.reorder_disallow(not32, [2, 1, 3])
@test !forbid32([1, 1])
@test !forbid32([1,2,3])
@test !forbid32([1,3,2])  # this is allowed
@test !forbid32([2,3,2])  # this is allowed
@test forbid32([3, 1, 2])
@test forbid32([3, 1, 2])

ex232 = UnitTestDesign.ipog_multi([2, 3, 2], 2, not32, missing)
# There are no tuples that are [x, 3, 2].
@test !any(sum(ex232 .== [0, 3, 2], dims = 1) .== 2)

CI = get(ENV, "CI", false) == "true"

rng = Random.MersenneTwister(90714134)
test_time = CI ? 5 : 30
max_n = CI ? 6 : 10
max_arity = CI ? 5 : 7
start_time = time()
while time() - start_time < test_time
    n = rand(rng, 3:max_n)
    arity = rand(rng, 2:max_arity, n)
    k = rand(rng, 2:minimum([4, n]))
    println("$(arity) $(k)")
    r1 = UnitTestDesign.ipog_multi(arity, k, x -> false, missing)
    println("$(size(r1))")
    cover1 = UnitTestDesign.test_coverage(r1, arity, k)
    @test cover1.finish == 0
end


rng = Random.MersenneTwister(2424324)
test_time = CI ? 2 : 30
max_n = CI ? 6 : 10
max_arity = CI ? 5 : 7
start_time = time()
not32 = (x -> (length(x) >= 3 && x[2] == 3 && x[3] == 2))
while time() - start_time < test_time
    n = rand(rng, 3:max_n)
    arity = rand(rng, 2:max_arity, n)
    arity[2] = maximum([3, arity[2]]) # make sure it's >=3.
    k = rand(rng, 2:minimum([4, n]))
    println("$(arity) $(k)")
    r2 = UnitTestDesign.ipog_multi(arity, k, not32, missing)
    println("$(size(r2))")
    all_combos = UnitTestDesign.all_combinations(arity, k)
    combo_cnt = size(all_combos, 2)
    compare = zeros(Int, n)
    compare .= -1
    compare[2:3] .= [3, 2]
    exclude = vec(sum(all_combos .== compare, dims = 1) .== 2)
    cover2 = UnitTestDesign.test_coverage(r2, arity, k)
    @test cover2.start == combo_cnt
    @test cover2.finish == sum(exclude)
    @test !any(sum(r2 .== compare, dims = 1) .== 2)
end
