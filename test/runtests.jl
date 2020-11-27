using UnitTestDesign
using SafeTestsets
using Test

@safetestset "UnitTestDesign.jl" begin
    include("test_greedy_tuples.jl")
end
