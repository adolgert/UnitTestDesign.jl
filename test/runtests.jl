using UnitTestDesign
using Test
using SafeTestsets


@testset "UnitTestDesign.jl" begin
    include("test_combinations.jl")
    include("test_coverage_matrix.jl")
    include("test_coverage_set.jl")
    include("test_excursions.jl")
    include("test_factorial_interface.jl")
    include("test_full_factorial.jl")
    include("test_greedy_tuples.jl")
    include("test_parameter_order.jl")
end
