# Does the test-only wrapper n_way_coverage produce what generate(GND) produces?
using UnitTestDesign, Random
const U = UnitTestDesign
for (arity, t) in (([2, 3, 2, 3], 2), (fill(4, 10), 2), ([3, 3, 2, 2, 4], 3))
    space = TestSpace((Symbol(:p, i) => 1:arity[i] for i in eachindex(arity))...)
    for seed in 1:3
        w = reduce(hcat, U.n_way_coverage(arity, t, 50, Xoshiro(seed)))
        g = U.generate(GND(; seed), U.Request(space; strength = t)).matrix
        println("arity=$arity t=$t seed=$seed: wrapper $(size(w, 2)) rows, generate(GND) $(size(g, 2)) rows, same matrix: $(w == g)")
    end
end
