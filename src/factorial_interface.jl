## all_values
## all_pairs
## all_triples
## all_n_tuples
## values_excursion
## pairs_excursion
## n_tuples_excursion
## full_factorial
## driven_factorial


"""
In-parameter-order General (IPOG).

This algorithm generates test cases quickly. It will generate
tuples of any order. It always generates the same set of test
cases for the same set of input values.

Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008. “IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing.” Software Testing, Verification & Reliability 18 (3): 125–48.
"""
struct IPOG
end


"""
Greedy Non-deterministic (GND).

This algorithm searches for test cases. It will generate tuples
of any order. It generates a different set every time it is invoked.

# Arguments

- `rng::Random.AbstractRNG`: This option is a random number
  generator. Set this if you want to generate the same test cases
  twice in a row.
- `M::Int`: The number of times it should create a candidate test case
  each time it creates a candidate. The default is 50. Raising this
  number could improve test cases and slow generation.

# Extended

This algorithm starts with the seeded test cases and then
adds test cases, one at a time. It chooses those parameters
that are least used, so far, and then chooses values of those
parameters that are least covered by previous tuples. At each
step, there is some probability of choosing among nearly-equal
next values.

It's not complicated, but it can be slow because every next choice
checks against all possible tuples. For large numbers of parameters
or large numbers of possible values of each parameter, this generator
can be slow, so test it for fewer values first and gradually increase
the number of parameters or parameter values.
"""
struct GND
    rng::Random.AbstractRNG
    M::Int

    function GND(; rng = nothing, M = 50)
        if rng === nothing
            new(Random.MersenneTwister(), M)
        else
            new(rng, M)
        end
    end
end


struct Excursion
end


function wrap_disallow(disallow, parameters)
    if disallow !== nothing
        inner_filter = let filter = disallow, params = parameters
            choices -> filter((p[c] for (p, c) in zip(params, choices))...)
        end
    else
        inner_filter = nothing
    end
end


function seeds_to_integers(seed, parameters, Counter = Int)
    param_cnt = length(parameters)
    if length(seed) > 0
        seed_array = zeros(Counter, param_cnt, length(seed))
        for seed_idx in 1:length(seed)
            seed_array[:, seed_idx] = [indexin([c], p)[1] for (p, c) in zip(parameters, seed[seed_idx])]
        end
    else
        seed_array = []
    end
    seed_array
end


function generate_tuples(engine::IPOG, n_way, parameters; Counter = Int, kwargs...)
    # We convert from parameters to integers here so that different generators
    # can use different internal representations.
    arity = Counter[length(p) for p in parameters]
    param_cnt = length(arity)
    if :disallow in keys(kwargs) && isa(kwargs[:disallow], Function)
        disallow = wrap_disallow(kwargs[:disallow], parameters)
    else
        disallow = x -> false
    end
    if :seeds in keys(kwargs) && length(kwargs[:seeds]) > 0
        seeds = seeds_to_integers(kwargs[:seeds], parameters, Counter)
    else
        seeds = zeros(Counter, param_cnt, 0)
    end
    if :wayness in keys(kwargs) && length(kwargs[:wayness]) > 0
        result = ipog_multi_way(arity, n_way, levels, kwargs[:wayness], disallow, seeds)
    elseif :disallow in keys(kwargs) || :seed in keys(kwargs)
        result = ipog_multi(arity, n_way, disallow, seeds)
    else
        result = ipog(arity, n_way)
    end
    [[p[c] for (p, c) in zip(parameters, result[:, i])] for i in 1:size(result, 2)]
end


function generate_tuples(engine::GND, n_way, parameters; Counter = Int, kwargs...)
    arity = Counter[length(p) for p in parameters]
    if :disallow in keys(kwargs)
        disallow = wrap_disallow(kwargs[:disallow], parameters)
    else
        disallow = x -> false
    end
    if :seeds in keys(kwargs)
        seeds = seeds_to_integers(kwargs[:seeds], parameters, Counter)
    else
        seeds = []
    end
    if :wayness in keys(kwargs) && length(kwargs[:wayness]) > 0
        mwc = multi_way_coverage(arity, kwargs[:wayness], n_way)
        mc = UnitTestDesign.MatrixCoverage(mwc, size(mwc, 1), arity)
        result = n_way_coverage_multi(mc, disallow, seeds, engine.M, engine.rng)
    else
        result = n_way_coverage_filter(arity, n_way, disallow, seeds, engine.M, engine.rng)
    end
    [[p[c] for (p, c) in zip(parameters, answer)] for answer in result]
end


function generate_tuples(engine::Excursion, n_way, parameters; Counter = Int, kwargs...)
    # We convert from parameters to integers here so that different generators
    # can use different internal representations.
    arity = Counter[length(p) for p in parameters]
    param_cnt = length(arity)
    if :disallow in keys(kwargs) && isa(kwargs[:disallow], Function)
        disallow = wrap_disallow(kwargs[:disallow], parameters)
    else
        disallow = x -> false
    end
    if :seeds in keys(kwargs) && length(kwargs[:seeds]) > 0
        seeds = seeds_to_integers(kwargs[:seeds], parameters, Counter)
    else
        seeds = zeros(Counter, param_cnt, 0)
    end
    if :wayness in keys(kwargs) && length(kwargs[:wayness]) > 0
        levels = kwargs[:wayness]
        result = build_excursion_multi(arity, n_way, levels, disallow, seeds_to_integers)
    else
        result = build_excursion(arity, n_way, disallow, seeds)
    end
    [[p[c] for (p, c) in zip(parameters, result[:, i])] for i in 1:size(result, 2)]
end


"""
    all_tuples(parameters...; n_way, engine, disallow, seeds, wayness, Counter)

Given a tuple of parameters, generate all test cases that cover all `n_way` combinations
of those parameters.

# Arguments

- `engine=IPOG()`: The `engine` is `IPOG()` or `GND()`.
- `disallow=nothing`: The disallow function is a function of the parameters that
  returns `true` when that combination should be forbidden.
- `seeds=[]`: is a list of test cases that must be included among those
generated.
- `wayness` is a dictionary that specifies subsets of parameters for
  which to increase the `n_way` combinations. For instance, if the combinations are
  two-way, and you want the third-sixth parameters to be three-way covered, use,
  `wayness = Dict(3 => [[3, 4, 5, 6]])`.
- `Counter=Int`The Counter is an integer type to use for
the computation. It must be large enough to hold the integer number of the parameters.

# Examples
```
all_tuples([1, 2, 3], ["a", "b", "c"], [true, false]; n_way = 2)
```
"""
function all_tuples(
    parameters...;
    n_way = 2, engine = IPOG(), disallow = nothing, seeds = [], wayness = Dict{Int,Array{Array{Int,1},1}}(), Counter = Int
    )

    generate_tuples(engine, n_way, parameters; disallow = disallow, seeds = seeds, wayness = wayness, Counter = Counter)
end


"""
    all_values(parameters...; kwargs...)

Ensure that the test cases include every value of every parameter
at least once.

See also: [`all_tuples`](@ref)
"""
function all_values(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 1, kwargs...)
end


"""
    all_pairs(parameters...; kwargs...)

Ensure that the returned test cases include every pair of
parameters at least once.

# Examples
```
all_pairs([1, 2, 3], ["a", "b", "c"], [true, false])
```
"""
function all_pairs(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 2, kwargs...)
end


"""
    all_triples(parameters...; kwargs...)

Ensure that the returned test cases include every combination
of three parameters at least once.
"""
function all_triples(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 3, kwargs...)
end


function values_excursion(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 1, engine = Excursion(), kwargs...)
end


function pairs_excursion(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 2, engine = Excursion(), kwargs...)
end


function triples_excursion(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 3, engine = Excursion(), kwargs...)
end


function full_factorial(parameters...; disallow = nothing)
    arity = [length(p) for p in parameters]
    param_cnt = length(arity)
    if disallow !== nothing
        disallow = wrap_disallow(disallow, parameters)
    else
        disallow = x -> false
    end
    result = full_factorial(arity, disallow)
    [[p[c] for (p, c) in zip(parameters, result[:, i])] for i in 1:size(result, 2)]
end
