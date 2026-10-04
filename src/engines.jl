# Engine types and the internal engine protocol (plan §4.2 of
# design/20261003_solver_plan.md). The engines themselves live in
# parameter_order.jl (IPOG) and greedy_tuples.jl (GND); this file defines the
# public structs, the protocol every engine implements (`CoveringEngine`),
# what an engine's `fit` reads of a request (`Profile`), the fallback for a
# part of a request an engine can't cover, and `generate`, the one entry
# point. The protocol is internal: nothing here but `IPOG` and `GND` is
# exported or documented for users (decision D7).

using Random: AbstractRNG, Xoshiro

"""
    CoveringEngine

The internal engine protocol (plan §4.2; not public, decision D7). A covering
engine is a struct that subtypes `CoveringEngine` and defines three methods,
in its own file:

- `cover_ordinary(engine, request::Request, targets::RequiredTargets) ->
  Matrix{Int}`: parameters × cases, in engine positions `1:request.arity[i]`.
  Every row is complete and valid under the request's rules (ask
  `dead(request, partial)`, or complete a partial row with `witness`). The
  request's must-include rows come first, in order, unchanged where they are
  set and completed in place where they are not (contract §10.5, §7.10);
  then rows until every required target is in some row. The targets are read
  through `supports`, `ncombinations`, `isrequired` and `nrequired`
  (`RequiredTargets`). `generate` certifies the result (`validate_design`,
  §1.21), so a wrong design is an internal error, never a wrong answer.
- `engine_record(engine) -> EngineRecord`: the name, seed and settings that a
  result records and shows.
- `fit(engine, profile::Profile) -> Fit`: whether the engine covers a request
  of this shape, read from the request alone (`Profile`), never by running.

An engine may also define `_fallback(engine)`, the engine that covers what
its `fit` refuses (IPOG by default); a randomized engine defines
`_randomized(::Val{name}) = true` for its record's name, so that results show
its seed. Give its inner loops `@inferred` and `@allocated` tests in
test/test_stability.jl (no JET).

Every engine keeps these rules.

- **Ordinary values only.** An engine never sees an `Invalid` value. For each
  invalid value, `cover_negative` (invalid.jl) hands the engine a sub-request
  over the other parameters, whose base strength is one less and may be 0,
  in which case only its `stronger` groups carry targets. `fit` sees that
  sub-request's profile, and an `:unsupported` fit sends it to `_fallback`
  (`_engine_for`).
- **Determinism** (contract §9). The rows depend only on the request and the
  engine's settings: never the clock, hash iteration order, object addresses,
  threads or the global random number generator (§9.3). A randomized engine
  takes a `seed` (default 0) or an `rng`, starts every call from a fresh
  generator, a copy of the `rng` when one is given, so the caller's is never
  advanced (`engine_rng`, §9.5, §9.6), and records the seed, or `nothing`
  for an `rng`. A budget counts steps, never seconds.
- **Independence from `feasibility_limit`** (contract §3.8). Two successful
  calls that differ only in the limit return the same rows. An engine
  decides only from resolved answers: `dead` returns `true` or `false` or
  throws `ResourceLimitError`, so a decision built on it doesn't depend on
  the limit. An engine must not branch on a search's node count, treat an
  unknown answer as either answer, or catch a `ResourceLimitError` and carry
  on; it lets the error propagate (§3.6).
"""
abstract type CoveringEngine end

"""
    cover_ordinary(engine, request::Request, targets::RequiredTargets) -> Matrix{Int}

An engine's rows for `request`, must-include rows first, covering every
required target in `targets` (`CoveringEngine`).
"""
function cover_ordinary end

"""
    engine_record(engine) -> EngineRecord

What a result records of `engine` (`CoveringEngine`, `EngineRecord`).
"""
function engine_record end

"""
    fit(engine, profile::Profile) -> Fit

Whether `engine` covers a request with this `Profile`, and how
(`CoveringEngine`, `Fit`).
"""
function fit end

"""
Use when you want the default engine: deterministic and free of randomness, so
the same inputs always give the same cases.

    IPOG()

In-parameter-order General (IPOG): deterministic, no randomness (contract
§9.4).

Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008.
"IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing."
Software Testing, Verification & Reliability 18 (3): 125-48.
"""
struct IPOG <: CoveringEngine
end

"""
Use when you want a seeded, randomized alternative to [`IPOG`](@ref), for
instance to compare design sizes at a high strength, where it sometimes finds
fewer cases; the same `seed` gives the same cases, and neither engine promises
the smaller design.

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
struct GND <: CoveringEngine
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
    EngineRecord(name, seed, parameters = Pair{Symbol, Any}[])

What a result records of the engine that made it (plan §4.2), from
`engine_record(engine)`: `name`, the `Symbol` that a `Design` and a
[`TestCases`](@ref) keep as `engine`; `seed`, the seed a randomized engine
drew from, or `nothing` when it drew from a caller's `rng` (contract §9.6)
or uses no randomness; and `parameters`, the engine's other settings as
`keyword => value` pairs, for display. Whether the engine is randomized is a
fact about its name (`_randomized`), so a result that keeps only `engine` and
`seed` shows its seed as the record does (`_engine_phrase`, `_seed_note`,
`_seed_text`).

`generate` reads the record once per call. Phase 3's `Auto` records what it
chose here, beside its own name, and `TestCases` gains a field for it then.
"""
struct EngineRecord
    name::Symbol
    seed::Union{Nothing, Int}
    parameters::Vector{Pair{Symbol, Any}}
end

EngineRecord(name::Symbol, seed) = EngineRecord(name, seed, Pair{Symbol, Any}[])

"""
    _randomized(::Val{name}) -> Bool

Whether the engine whose record is named `name` draws random numbers, so that
its results show the seed (contract §9.5). A randomized engine adds its method
in its own file; `:Excursion` and `:FullFactorial`, the records of the other
strategies, use no randomness.
"""
_randomized(::Val) = false
_randomized(record::EngineRecord) = _randomized(Val(record.name))

"How a summary line names the engine: \"IPOG\", \"GND seed 3\", or \"GND, caller's rng\" (§1.22)."
function _engine_phrase(record::EngineRecord)
    _randomized(record) || return string(record.name)
    return record.seed === nothing ? "$(record.name), caller's rng" : "$(record.name) seed $(record.seed)"
end

"A randomized engine's seed in `report`'s guarantee line, or `nothing` for an engine without one."
function _seed_note(record::EngineRecord)
    _randomized(record) || return nothing
    return record.seed === nothing ? "$(record.name) with the caller's rng" : "$(record.name) seed $(record.seed)"
end

"`report`'s seed line for a covering design (§9.5): the seed and how to repeat it, or why there is none."
function _seed_text(record::EngineRecord)
    _randomized(record) || return "seed: none ($(record.name) uses no randomness)"
    record.seed === nothing && return "seed: none ($(record.name) drew from the caller's rng)"
    return "seed: $(record.seed) ($(record.name)(seed = $(record.seed)) repeats these cases)"
end

"""
    Fit(kind, reason; rows = nothing)

An engine's answer to whether it covers a request of some shape (`fit`, plan
§4.2), with `reason`, one line that `recommend` and messages can show
(Phase 3). `kind` is

- `:exact`: the engine builds the design directly, as a catalog array does
  for an exact shape (Phase 2), and `rows` is its size when the engine knows
  it without building anything;
- `:native`: the engine covers the request with its own search, as IPOG and
  GND cover any request;
- `:seeded`: the engine builds a start that IPOG's general path extends
  (§4.1, stage 2), such as a catalog array with the rows a rule forbids
  dropped;
- `:unsupported`: the engine can't cover it. Where generation hands an engine
  part of a request, that part goes to the engine's fallback instead
  (`_engine_for`).
"""
struct Fit
    kind::Symbol
    reason::String
    rows::Union{Nothing, Int}

    function Fit(kind::Symbol, reason::AbstractString; rows::Union{Nothing, Integer} = nothing)
        kind in (:exact, :native, :seeded, :unsupported) || throw(ArgumentError(
            "a fit is :exact, :native, :seeded or :unsupported; got $(repr(kind))"))
        return new(kind, String(reason), rows === nothing ? nothing : Int(rows))
    end
end

"""
    Profile(request) -> Profile

What an engine's `fit` reads of a request (plan §4.2), and what Phase 3's
`recommend` and `Auto` read. It is computed from the request alone, without
classifying or listing a target, so it costs time in the parameters, groups
and rules, never in the targets.

- `arity`: the ordinary values of each parameter, engine positions
  `1:arity[i]`; the parameter count is its length (`nparameters`).
- `prime_power`: whether each `arity[i]` is a prime power, as the field
  constructions of Phase 2 need.
- `strength` and `groups`: as the request has them, the base group first,
  then each `stronger` group with its strength. A negative sub-request's base
  strength may be 0.
- `n_must_include`: the must-include rows, ordinary and negative.
- `n_invalid`: the [`Invalid`](@ref) values, over every parameter.
- `rules`: for each rule, in order, its scope size and kind: `:tabulated`,
  `:lazy` (a scoped rule evaluated on demand, §12.19), or `:whole_case`
  (§12.9; always lazy, and checked only on complete rows).
- `targets`: the targets before classification, as `TargetList` counts them,
  saturating at `typemax(Int)` (`_target_count`).
"""
struct Profile
    arity::Vector{Int}
    prime_power::BitVector
    strength::Int
    groups::Vector{Pair{Vector{Int}, Int}}
    n_must_include::Int
    n_invalid::Int
    rules::Vector{@NamedTuple{scope::Int, kind::Symbol}}
    targets::Int
end

function Profile(request::Request)
    space = request.space
    arity = copy(request.arity)
    n_invalid = 0
    for i in eachindex(arity)
        n_invalid += length(request.candidates[i]) - arity[i]
    end
    rules = @NamedTuple{scope::Int, kind::Symbol}[
        (scope = length(t.scope), kind = isempty(c.scope) ? :whole_case : t.lazy === nothing ? :tabulated : :lazy)
        for (t, c) in zip(space.tables, space.constraints)]
    groups = Pair{Vector{Int}, Int}[copy(members) => s for (members, s) in request.groups]
    return Profile(arity, BitVector(_is_prime_power.(arity)), request.strength, groups,
                   n_must_include(request), n_invalid, rules, _target_count(arity, groups))
end

nparameters(p::Profile) = length(p.arity)

"Whether `q` is a power of a prime: 2, 3, 4, 5, 7, 8, 9, …"
function _is_prime_power(q::Integer)
    q < 2 && return false
    p = 2
    while p * p <= q && q % p != 0
        p += 1
    end
    q % p == 0 || return true   # no factor up to its square root: q is prime
    while q % p == 0
        q ÷= p
    end
    return q == 1
end

# Counts of targets grow past `Int` long before a request is too large to
# describe, so a profile's count stops at `typemax(Int)` rather than throw.
function _saturating_add(a::Int, b::Int)
    c, over = Base.Checked.add_with_overflow(a, b)
    return over ? typemax(Int) : c
end

function _saturating_mul(a::Int, b::Int)
    c, over = Base.Checked.mul_with_overflow(a, b)
    return over ? typemax(Int) : c
end

"""
    _target_count(arity, groups) -> Int

The number of targets `TargetList` lists for these groups, without listing
supports, saturating at `typemax(Int)`. For one group `(G, s)` it is the
elementary symmetric polynomial `e_s` of the value counts of `G`: the sum,
over the `s`-subsets of `G`, of the product of their value counts, by the
recurrence `e_k += e_(k-1) * a` over the members (`_elementary`). Supports of
different sizes are different, and every `stronger` group's strength is above
the base strength (contract §11.6; §11.7 drops a group at the base strength),
so only `stronger` groups of one strength can share a support, such as two
groups at strength 3 with three parameters in common. `TargetList` lists a
shared support once, so the groups of one strength are counted together
(`_union_count`). A group at strength 0, a negative sub-request's base group,
has no targets.
"""
function _target_count(arity::Vector{Int}, groups::Vector{Pair{Vector{Int}, Int}})
    total = 0
    for s in sort!(unique!([s for (_, s) in groups if s > 0]))
        level = Vector{Int}[members for (members, t) in groups if t == s]
        total = _saturating_add(total, length(level) == 1 ? _elementary(arity, only(level), s) :
                                                           _union_count(arity, level, s))
    end
    return total
end

"`e_s` of the value counts of `members`, saturating (`_target_count`)."
function _elementary(arity::Vector{Int}, members::Vector{Int}, s::Int)
    e = zeros(Int, s + 1)   # e[k + 1] is e_k of the members so far
    e[1] = 1
    for p in members
        for k in s:-1:1
            e[k + 1] = _saturating_add(e[k + 1], _saturating_mul(e[k], arity[p]))
        end
    end
    return e[s + 1]
end

"""
    _union_count(arity, groups, s) -> Int

The targets on the `s`-subsets of any of `groups`, each subset once
(`_target_count`). A recurrence over the parameters in order: a state is the
set of groups that hold every parameter chosen so far, with `e_k` of the
choices of `k` parameters that lead to it. Choosing a parameter intersects
the state with the groups that hold it, and a choice that no group holds
whole is dropped. So each `s`-subset held by some group is counted once,
under the set of groups that hold it, with no inclusion–exclusion over the
groups. The states are the distinct sets of groups that share some
parameters, which for listed groups are few.
"""
function _union_count(arity::Vector{Int}, groups::Vector{Vector{Int}}, s::Int)
    holds = [falses(length(groups)) for _ in arity]   # holds[p][j]: group j holds parameter p
    for (j, members) in enumerate(groups), p in members
        holds[p][j] = true
    end
    states = Dict{BitVector, Vector{Int}}(trues(length(groups)) => [1; zeros(Int, s)])
    for p in eachindex(arity)
        any(holds[p]) || continue
        next = Dict{BitVector, Vector{Int}}(mask => copy(e) for (mask, e) in states)
        for (mask, e) in states
            both = mask .& holds[p]
            any(both) || continue
            f = get!(() -> zeros(Int, s + 1), next, both)
            for k in 1:s
                f[k + 1] = _saturating_add(f[k + 1], _saturating_mul(e[k], arity[p]))
            end
        end
        states = next
    end
    # A saturating sum of counts is the same in any order.
    total = 0
    for e in values(states)
        total = _saturating_add(total, e[s + 1])
    end
    return total
end

"""
    _fallback(engine) -> CoveringEngine

The engine that covers what `engine`'s `fit` refuses (plan §4.2): IPOG, which
covers any request. An engine may name another that covers any request, such
as a wrapper that wraps its inner engine's fallback.
"""
_fallback(::CoveringEngine) = IPOG()

"""
    _engine_for(engine, request) -> CoveringEngine

The engine that covers `request`, a part of a request that generation hands
`engine` (plan §4.2): `engine` itself, or its `_fallback` when its `fit` for
the request's `Profile` is `:unsupported`. The negative sub-requests of
`cover_negative` (invalid.jl) go through it. IPOG and GND fit every request,
so for them it is the engine itself.
"""
function _engine_for(engine::CoveringEngine, request::Request)
    fit(engine, Profile(request)).kind === :unsupported || return engine
    return _fallback(engine)
end

"""
    generate(engine::CoveringEngine, request::Request) -> Design

The one engine entry point (plan Phase 3 step 1): a covering design for
`request` in index space, certified by `validate_design` before it returns
(contract §1.21). Every [`CoveringEngine`](@ref) builds covering designs
(§1.3) through `cover_ordinary`, and the result records it by
`engine_record`. Every target classification, must-include completion and
placement decision is resolved or the call throws `ResourceLimitError`
(§3.6); a design is never returned with a target unresolved or dropped.

The ordinary design is built first, over ordinary values only, from the
classified ordinary targets (`classify_targets`, read through
`RequiredTargets`) and the ordinary must-include rows (`cover_ordinary`).
When the space has [`Invalid`](@ref) values, negative generation
(`cover_negative`, invalid.jl) then covers the negative targets of §6 with
the same engine, or its fallback where its `fit` refuses a sub-request
(`_engine_for`). The rows are the must-include rows in the order given, each
completed under its own row policy (§7.9), then the generated ordinary rows,
then the generated negative rows (§5.12). The two kinds' bookkeeping is kept
apart (§1.19).
"""
function generate(engine::CoveringEngine, request::Request)
    required, excluded = classify_targets(request)
    record = engine_record(engine)
    name, seed = record.name, record.seed
    if !_has_invalid(request.space)
        matrix = cover_ordinary(engine, request, RequiredTargets(request, required))
        covered = validate_design(request, matrix, required)
        return Design(matrix, :covering, name, seed, length(required), covered, excluded,
                      n_must_include(request), (;))
    end
    must = request.must_include
    negative_columns = [j for j in axes(must, 2) if _holds_invalid(request, view(must, :, j))]
    ordinary_columns = [j for j in axes(must, 2) if !(j in negative_columns)]
    ordinary_request = _with_must_include(request, must[:, ordinary_columns])
    ordinary = cover_ordinary(engine, ordinary_request, RequiredTargets(ordinary_request, required))
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
