using Test
using UnitTestDesign

be1_arity = [2, 3, 2, 4]
be1_res = UnitTestDesign.build_excursion(be1_arity, 2, x -> false)
@test size(be1_res) == (4, 24)


be2_arity = [2, 3, 2, 4]
be2_res = UnitTestDesign.build_excursion(be2_arity, 2, x -> x[3] == 2 && x[4] > 2)
@test size(be2_res) == (4, 22)


be3_arity = [2, 3, 2, 4]
# one new and one already in the set.
be3_seed = [2 1; 3 1; 2 1; 4 2]
be3_res = UnitTestDesign.build_excursion(be3_arity, 2, x -> false, be3_seed)
@test be3_res[:, 1] == be3_seed[:, 1]
@test size(be3_res) == (4, 25)  # adds one to total length.
