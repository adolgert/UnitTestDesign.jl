using Test
using Random
using UnitTestDesign

### wrap_disallow, an internal function.

function filter_bc(a, b, c)
    !b && c == "two"
end
@assert !filter_bc(1, false, "one")
@assert !filter_bc(1, true, "two")
@assert filter_bc(1, false, "two")  # So we disallow this one.
@assert !filter_bc(1, true, "two")
function parameter_filter(choices, filter, parameter_map)
    filter((p[c] for (p, c) in zip(parameter_map, choices))...)
end

params = ([1,2,3], [true, false], ["one", "two"])
pf1 = UnitTestDesign.wrap_disallow(filter_bc, params)
# These should mirror the ones above.
@assert !pf1([1, 2, 1])
@assert !pf1([1, 1, 2])
@assert pf1([1, 2, 2])
@assert !pf1([1, 1, 2])


## seeds_to_integers, an internal function

params = (["a", "b", "c"], [1, 2], [4, 7])
seeds = [["a", 2, 4], ["b", 1, 7]]
sti_res = UnitTestDesign.seeds_to_integers(seeds, params)
@test sti_res == collect([1 2 1; 2 1 2]')


## IPOG

ipog = IPOG()


## GND

gnd1 = GND()
@test gnd1.M == 50
sample1 = randn(gnd1.rng)
gnd2 = GND(M = 100)
@test gnd2.M == 100
sample2 = randn(gnd2.rng)
@test sample1 != sample2
gnd3 = GND(rng = MersenneTwister(23423523))
@test gnd3.M == 50
sample3 = randn(gnd3.rng)
@test sample3 != sample2
gnd4 = GND(rng = MersenneTwister(23423523))
sample4 = randn(gnd4.rng)
@test sample3 == sample4
gnd5 = GND(rng = MersenneTwister(23423523), M = 70)
@test gnd5.M == 70
@test randn(gnd5.rng) == sample3


## generate_tuples(IPOG())

trials1 = generate_tuples(IPOG(), 2, ([1, 2], [true, false], ["a", "b", "c"]))
@test length(trials1) == 6
@test trials1[1][3] in ["a", "b", "c"]

gndt1 = generate_tuples(GND(), 2, ([1, 2], [true, false], ["a", "b", "c"]))
@test length(gndt1) > 3
@test gndt1[1][2] in [true, false]
@test gndt1[1][3] in ["a", "b", "c"]


## all_values

av1 = all_values([1, 2], ["a", "b", "c"], [4, 7])
@test length(av1) == 3
@test av1[1][3] in [4, 7]

## all_pairs

pairs1 = all_pairs([1, 2], ["a", "b", "c"], [4, 7])
@test length(pairs1) > 3
@test pairs1[1][3] in [4, 7]


## all_triples

at1 = all_triples([1, 2], ["a", "b", "c"], [4, 7], [true, false])
@test length(at1) > 8
@test at1[1][3] in [4, 7]
@test length(at1[1]) == 4
