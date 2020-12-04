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

function ipog_extra(arity, n_way, M = nothing, rng = nothing)
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
    @timed callee(arity, test_case.wayness, test_case.M, rng)
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

# These tests come from comparison with
# Calvagna, A., and A. Gargantini. 2009. “IPO-S: Incremental Generation of
# Combinatorial Interaction Test Data Based on Symmetries of Covering Arrays.”
# In 2009 International Conference on Software Testing, Verification, and
# Validation Workshops, 10–18.
N = 10
calvagna_table_3 = DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    cases = [31, 34, 41, 42, 48, 48, 51, 51, 51, 53]
)
N = 6
calvagna_table4 = DataFrame(
    n = fill(10, N),
    r = [5i for i in 1:N],
    wayness = fill(2, N),
    cases = [47, 169, 361, 618, 956, 1355]
)
N = 5
# calvagna_table4 = DataFrame(
#     n = fill(3, N),
#     r = [3, 4, 5, 6, 7],
#     wayness = fill(2, N),
#     cases = [9, 9, 9, 9, 10, 9]
# )


N = 10
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int, N),
    fut = fill(:ipog, N),
    M = fill(0, N)
))
N = 3
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int, N),
    fut = fill(:greedy, N),
    M = fill(50, N)
))
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int, N),
    fut = fill(:greedy, N),
    M = fill(10, N)
))
push!(cases, DataFrame(
    n = [10i for i in 1:N],
    r = fill(4, N),
    wayness = fill(2, N),
    k = fill(Int8, N),  # Using Int8 for reduced memory consumption.
    fut = fill(:greedy, N),
    M = fill(10, N)
))
# Add tests from Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun,
# and James Lawrence. 2008. “IPOG/IPOG-D: Efficient Test Generation
# for Multi-Way Combinatorial Testing.” Software Testing, Verification
# & Reliability 18 (3): 125–48.
N = 4
lei_table_1 = DataFrame(
    n = fill(15, N),
    r = fill(4, N),
    wayness = [3, 4, 5, 6],
    cases = [181, 924, 4519, 20384],
    time = [0.56, 16.57, 230, 2152]
)
N = 10
lei_table_2 = DataFrame(
    n = 11:20,
    r = fill(4, N),
    wayness = fill(5, N),
    cases = [3287, 3703, 4001, 4260, 4519, 4787, 5018, 5245, 5471, 5685],
    time = [23.3, 44, 80, 139, 230, 368, 565, 839, 1206, 1739]
)
N = 6
lei_table_3 = DataFrame(
    n = fill(15, N),
    r = 2:7,
    wayness = fill(5, N),
    cases = [134, 1123, 4531, 15095, 37748, 81814],
    time = [4.08, 48, 234, 997, 3273, 9040]
)


# Test 1: 15 4-value parameters
N = 2
push!(cases, DataFrame(
    n = fill(15, N),
    r = fill(4, N),
    wayness = 2:(2 + N - 1),
    k = fill(Int, N),
    fut = fill(:ipog, N),
    M = fill(0, N)
))


df = vcat(cases...)
# Add a place in the dataframe to store results.
df[:, :duration] = zeros(N),
df[:, :duration_max] = zeros(N),
df[:, :mbytes] = zeros(Float64, N),
df[:, :mbytes_max] = zeros(Float64, N),
df[:, :cases] = zeros(Int, N),
df[:, :cases_max] = zeros(Int, N),

rng = MersenneTwister(947234)
test_against_cases!(df, 10, rng)
df

CSV.write("nonfunctional_cases_$(today()).csv", df)

match_options = [
    UnitTestDesign.case_compatible_with_tuple,
    UnitTestDesign.case_partial_cover,
    UnitTestDesign.case_covers_tuple
]
opt_cnt = length(match_options)^3
opt_res = zeros(Int, 4, opt_cnt)
for opt_choice in 1:opt_cnt
    strat_idx = digits(opt_choice - 1, base = 3, pad = 3) .+ 1
    if strat_idx[1] != 3
        strategy = Dict((a, match_options[b]) for (a, b) in
            zip([:lastparam, :missingvals, :expand], strat_idx))

        ret = UnitTestDesign.ipog_instrumented(fill(4, 20), 2, strategy)
        opt_res[:, opt_choice] = vcat(size(ret[1], 2), strat_idx)
    end
end
opt_res


match_options = [
    UnitTestDesign.case_compatible_with_tuple,
    UnitTestDesign.case_partial_cover,
    UnitTestDesign.case_covers_tuple
]
strat_cnt = 2
opt_cnt = length(match_options)^strat_cnt
opt_res = zeros(Int, 1 + strat_cnt, opt_cnt)
for opt_choice in 1:opt_cnt
    strat_idx = digits(opt_choice - 1, base = 3, pad = strat_cnt) .+ 1
    if strat_idx[1] != 3
        strategy = Dict((a, match_options[b]) for (a, b) in
            zip([:lastparam, :expand], strat_idx))

        ret = UnitTestDesign.ipog_bytuple_instrumented(fill(4, 20), 2, strategy)
        opt_res[:, opt_choice] = vcat(size(ret[1], 2), strat_idx)
    end
end
opt_res

strat_idx = [2, 1]
strategy = Dict((a, match_options[b]) for (a, b) in
    zip([:lastparam, :expand], strat_idx))
ret = UnitTestDesign.ipog_bytuple_instrumented(fill(4, 30), 2, strategy)
