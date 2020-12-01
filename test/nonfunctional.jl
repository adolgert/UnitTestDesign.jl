# Nonfunctional tests aren't testing whether it's correct but
# properties of the runs. It's a terrible, but amusing, name.
# Here we create combinatorial interaction test data using
# several algorithms and ask how long it takes to run and
# how many test cases it generates under different conditions.
using CSV
using Dates
using UnitTestDesign
using DataFrames
import Random: MersenneTwister
import StatsBase: trim, trimvar, winsor, mean

function ipog_extra(arity, n_way, M, rng)
    size(UnitTestDesign.ipog(arity, n_way), 2)
end


function greedy_extra(arity, n_way, M, rng)
    length(UnitTestDesign.n_way_coverage(arity, n_way, M, rng))
end


fut_map = Dict(:ipog => ipog_extra, :greedy => greedy_extra)


function single_test!(test_case, rng)
    arity = zeros(test_case.k, test_case.n)
    fill!(arity, test_case.r)
    callee = fut_map[test_case.fut]
    @timed callee(arity, wayness, test_case.M, rng)
end


function test_against_cases!(df, sample_cnt, rng)
    for idx in 1:size(df, 1)
        duration = zeros(sample_cnt)
        memory = zeros(sample_cnt)
        case_cnt = zeros(Int, sample_cnt)
        for sample_idx in 1:sample_cnt
            v = single_test!(df[idx, :], rng)
            duration[sample_idx] = v.time
            memory[sample_idx] = v.bytes / 1024.0^2
            case_cnt[sample_idx] = v.value
        end
        df[idx, :duration] = mean(trim(duration, prop = 0.2))
        df[idx, :duration_max] = maximum(duration)
        df[idx, :mbytes] = mean(trim(memory, prop = 0.2))
        df[idx, :mbytes_max] = maximum(memory)
        df[idx, :cases] = minimum(case_cnt)
        df[idx, :cases_max] = maximum(case_cnt)
    end
end

# n is the number of parameters
# r is the number of values for each parameter.
# wayness is 2-way or n-way coverage
# k is the data type to use to store the coverage
# fut is the function-under-test.
# M is a parameter for the greedy algorithm.
cases = DataFrame[]
N = 10
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int, N),
    duration = zeros(N),
    duration_max = zeros(N),
    mbytes = zeros(Float64, N),
    mbytes_max = zeros(Float64, N),
    cases = zeros(Int, N),
    cases_max = zeros(Int, N),
    fut = fill(:ipog, N),
    M = fill(0, N)
))
N = 3
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int, N),
    duration = zeros(N),
    duration_max = zeros(N),
    mbytes = zeros(Float64, N),
    mbytes_max = zeros(Float64, N),
    cases = zeros(Int, N),
    cases_max = zeros(Int, N),
    fut = fill(:greedy, N),
    M = fill(50, N)
))
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int, N),
    duration = zeros(N),
    duration_max = zeros(N),
    mbytes = zeros(Float64, N),
    mbytes_max = zeros(Float64, N),
    cases = zeros(Int, N),
    cases_max = zeros(Int, N),
    fut = fill(:greedy, N),
    M = fill(10, N)
))

df = vcat(cases...)
rng = MersenneTwister(947234)
test_against_cases!(df, 30, rng)
df

CSV.write("nonfunctional_cases_$(today()).csv", df)
