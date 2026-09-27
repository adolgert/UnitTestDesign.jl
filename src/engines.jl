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
`M` is accepted with a deprecation warning and means `candidates`; passing
both is an error (§13.2).

`candidates` is a positive integer and `seed` an integer of at least 0
(Julia 1.10's `Xoshiro` refuses a negative seed), each within `Int`; `rng`
is an `AbstractRNG`. Any other value is an `ArgumentError` naming the
keyword, such as "candidates must be a positive integer, got 1.5".
"""
struct GND
    seed::Union{Nothing, Int}
    candidates::Int
    rng::Union{Nothing, AbstractRNG}

    # `candidates = nothing` marks it omitted (50), so an explicit value beside
    # `M` is refused rather than overridden. Every value is checked before it
    # is converted to the field's type.
    function GND(; seed = 0, candidates = nothing, rng = nothing, M = nothing)
        if M !== nothing
            candidates === nothing || throw(ArgumentError(
                "pass candidates only; M is its deprecated alias (contract §13.1)"))
            _check_integer(:M, M, 1, "§9.5")
            Base.depwarn("GND(M = n) is deprecated; use GND(candidates = n)", :GND)
            candidates = M
        end
        candidates = _check_integer(:candidates, something(candidates, 50), 1, "§9.5")
        if rng === nothing
            return new(_check_integer(:seed, seed, 0, "§9.5"), candidates, nothing)
        end
        rng isa AbstractRNG || throw(ArgumentError(
            "rng must be a random number generator, an AbstractRNG such as Xoshiro(1), " *
            "got $(repr(rng)) (contract §9.6)"))
        # The caller's generator replaces the seed, which may then be omitted.
        seed === nothing || _check_integer(:seed, seed, 0, "§9.5")
        return new(nothing, candidates, rng)
    end
end

"A fresh generator for one call: the seed's, or a copy of the caller's (§9.6)."
engine_rng(engine::GND) = engine.rng === nothing ? Xoshiro(engine.seed) : copy(engine.rng)

"""
    generate(engine, request::Request) -> Design

The one engine entry point (plan Phase 3 step 1): a design for `request` in
index space, certified by `validate_design` before it returns (contract
§1.21). `IPOG()` and `GND()` build covering designs (§1.3). Every target
classification, must-include completion and placement decision is resolved or
the call throws `ResourceLimitError` (§3.6); a design is never returned with a
target unresolved or dropped.
"""
function generate end
