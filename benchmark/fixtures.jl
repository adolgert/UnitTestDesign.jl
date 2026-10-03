# The benchmark's fixtures, loaded from the checked-in test definitions so
# that `bench12` has one source of truth (test/fixtures.jl). The fixture
# module needs the checker's input types and the adapter to a TestSpace, as
# the `Checker` test module in test/test_checker.jl does. Nothing here times
# or checks anything.
module BenchFixtures
    const TEST = joinpath(dirname(@__DIR__), "test")
    include(joinpath(TEST, "checker.jl"))
    include(joinpath(TEST, "random_problems.jl"))
    include(joinpath(TEST, "fixtures.jl"))
    include(joinpath(TEST, "fixture_model.jl"))
end
