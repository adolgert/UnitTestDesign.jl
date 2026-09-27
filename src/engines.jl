# Engine types. The engines themselves live in parameter_order.jl (IPOG)
# and greedy_tuples.jl (GND); this file only defines the public structs so
# that the interface and the engines can be edited independently.

using Random: AbstractRNG, Xoshiro

"""
    IPOG()

In-parameter-order General (IPOG): deterministic, no randomness (contract
§9.4).

Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008.
"IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing."
Software Testing, Verification & Reliability 18 (3): 125-48.
"""
struct IPOG
end

"""
    GND(; seed = 0, candidates = 50, rng = nothing)

Greedy Non-deterministic (GND). Builds each case by drawing `candidates`
random candidate rows and keeping the one that covers the most uncovered
combinations. Deterministic for a given `seed` (contract §9.5): each call
seeds a fresh generator from `seed`. Pass `rng` to draw from a caller's
generator instead; it is copied at the start of each call and never
advanced (§9.6), and the recorded seed is then `nothing`. The 0.4 keyword
`M` is accepted with a deprecation warning and means `candidates`.
"""
struct GND
    seed::Union{Nothing, Int}
    candidates::Int
    rng::Union{Nothing, AbstractRNG}

    function GND(; seed = 0, candidates = 50, rng = nothing, M = nothing)
        if M !== nothing
            Base.depwarn("GND(M = n) is deprecated; use GND(candidates = n)", :GND)
            candidates = M
        end
        candidates >= 1 || throw(ArgumentError("GND needs at least one candidate per case, got $candidates"))
        if rng !== nothing
            new(nothing, Int(candidates), rng)
        else
            new(Int(seed), Int(candidates), nothing)
        end
    end
end

"A fresh generator for one call: the seed's, or a copy of the caller's (§9.6)."
engine_rng(engine::GND) = engine.rng === nothing ? Xoshiro(engine.seed) : copy(engine.rng)

"""
This class requests tests that are excursions from a base case.
"""
struct Excursion
end
