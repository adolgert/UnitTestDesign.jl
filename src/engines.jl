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

The one engine entry point (plan Phase 3 step 1): a covering design for
`request` in index space, certified by `validate_design` before it returns
(contract §1.21). `IPOG()` and `GND()` build covering designs (§1.3). Every
target classification, must-include completion and placement decision is
resolved or the call throws `ResourceLimitError` (§3.6); a design is never
returned with a target unresolved or dropped.

The ordinary design is built first, over ordinary values only, from the
classified ordinary targets (`classify_targets`) and the ordinary
must-include rows (`cover_ordinary`). When the space has
[`Invalid`](@ref) values, negative generation (`cover_negative`,
invalid.jl) then covers the negative targets of §6 with the same engine.
The rows are the must-include rows in the order given, each completed under
its own row policy (§7.9), then the generated ordinary rows, then the
generated negative rows (§5.12). The two kinds' bookkeeping is kept apart
(§1.19).
"""
function generate(engine::Union{IPOG, GND}, request::Request)
    required, excluded = classify_targets(request)
    name, seed = _engine_name(engine), _engine_seed(engine)
    if !_has_invalid(request.space)
        matrix = cover_ordinary(engine, request, required)
        covered = validate_design(request, matrix, required)
        return Design(matrix, :covering, name, seed, length(required), covered, excluded,
                      n_must_include(request), (;))
    end
    must = request.must_include
    negative_columns = [j for j in axes(must, 2) if _holds_invalid(request, view(must, :, j))]
    ordinary_columns = [j for j in axes(must, 2) if !(j in negative_columns)]
    ordinary = cover_ordinary(engine, _with_must_include(request, must[:, ordinary_columns]), required)
    negative = cover_negative(engine, request, negative_columns)
    # Must-include rows in the order given, each completed by its kind's step.
    rows = Vector{Vector{Int}}(undef, size(must, 2))
    for (k, j) in enumerate(ordinary_columns)
        rows[j] = ordinary[:, k]
    end
    for j in negative_columns
        rows[j] = negative.seeds[j]
    end
    append!(rows, (ordinary[:, k] for k in (length(ordinary_columns) + 1):size(ordinary, 2)))
    append!(rows, negative.rows)
    matrix = isempty(rows) ? zeros(Int, length(request.arity), 0) : reduce(hcat, rows)
    covered = validate_design(request, matrix, required; negative = negative.required)
    return Design(matrix, :covering, name, seed, length(required), covered, excluded,
                  n_must_include(request), (;), length(negative.required), length(negative.required),
                  negative.excluded)
end
