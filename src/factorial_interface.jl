## full_factorial
## all_values
## all_pairs
## all_triples
## all_n_tuples
## all_values_excursion
## all_pairs_excursion
## all_n_tuples_excursion


"""
In-parameter-order General (IPOG).
"""
struct IPOG
end


"""
Greedy Non-deterministic (GND).
"""
struct GND
    rng::Random.AbstractRNG
    M::Int

    function GND(;rng=nothing, M = 50)
        if rng === nothing
            new(Random.MersenneTwister(), M)
        else
            new(rng, M)
        end
    end
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
    result = ipog(arity, n_way)
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
    result = n_way_coverage_filter(arity, n_way, disallow, seeds, engine.M, engine.rng)
    [[p[c] for (p, c) in zip(parameters, answer)] for answer in result]
end


function all_tuples(
    parameters...;
    n_way = 2, engine = IPOG(), disallow = nothing, seeds = [], wayness = Dict{Int,Array{Array{Int,1},1}}(), Counter = Int
    )

    generate_tuples(engine, n_way, parameters; disallow = disallow, seeds = seeds, wayness = wayness, Counter = Counter)
end


function all_values(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 1, kwargs...)
end


function all_pairs(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 2, kwargs...)
end


function all_triples(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 3, kwargs...)
end
