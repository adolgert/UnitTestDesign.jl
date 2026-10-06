# Engine types and the internal engine protocol (plan §4.2 of
# design/20261003_solver_plan.md). The engines themselves live in
# ipog_core.jl (IPOG) and greedy_tuples.jl (GND); this file defines the
# public structs, the protocol every engine implements (`CoveringEngine`),
# what an engine's `fit` reads of a request (`Profile`), the plan an engine
# prepares from it and generation executes (`_prepare`, `_execute`), the
# fallback for a part of a request an engine can't cover, the configuration
# and stages a result records, the registry of engines the tests and the
# benchmark harness run, and `generate`, the one entry point. The protocol is
# internal: nothing here but `IPOG` and `GND` is exported or documented for
# users (decision D7).

using Random: AbstractRNG, Xoshiro

"""
    CoveringEngine

The internal engine protocol (plan §4.2; not public, decision D7). A covering
engine is a struct that subtypes `CoveringEngine`. Generation prepares the
engine's plan for a request once, from the request's `Profile` alone
(`_prepare`), and executes that plan (`_execute`); `fit` is the plan's fit,
and `recommend`, `design_sizes` and the negative sub-requests read the same
plans. An engine defines, in its own file, `engine_record` and one of two
forms.

- `engine_record(engine) -> EngineRecord`: its name, seed and settings, a
  wrapped engine among them as the engine itself. A result records them as
  its configuration, `record.engine` (`_engine_config`), and names the
  engine by its constructor call (`_engine_label`, its `show`), which must
  repeat its rows, since `report`'s seed line offers that call.
- **An engine that decides nothing ahead**, as GND, defines
  - `fit(engine, profile::Profile) -> Fit`: whether it covers a request of
    this shape, read from the request alone, never by running; and
  - `cover_ordinary(engine, request::Request, targets::RequiredTargets) ->
    Matrix{Int}`: its rows (below).

  Its plan is the default, `_DefaultPlan`, which holds the engine and its
  fit; executing it calls `cover_ordinary` and reports nothing.
- **An engine with a recipe**, such as the catalog entry it builds
  (`Construction`), its inner engine's plan (`Compact`), its candidates'
  plans (`Auto`), or the order it adds parameters in and the members it runs
  (IPOG, `_IPOGPlan`), defines
  - its plan type, a `_Plan` with fields `engine` and `fit` beside the
    recipe;
  - `_prepare(engine, profile) -> plan`, from the profile alone;
  - `_execute(plan, request, targets) -> (matrix, notes)`: the rows, and
    `notes`, a `NamedTuple` of plain data on what it found (the catalog's
    array, the reducer's run, what it chose, the member that made the
    rows). It runs an inner plan with `_run`, and puts the stage `_run`
    returns into its notes, so that the record keeps every stage;
  - `fit(engine, p) = _prepare(engine, p).fit` (or a `fit` that its
    `_prepare` reads, as IPOG's), and `cover_ordinary` as the rows of
    `_execute(_prepare(engine, Profile(request)), …)`, for the callers that
    ask for rows alone (`_cover`);
  - where `Auto` or `recommend` may read the plan, `_known_rows`,
    `_at_bound` and `_plan_line`, when the plan knows more than the
    defaults say (the fit's rows, `false`, the fit's reason).

The rows are parameters × cases, in engine positions `1:request.arity[i]`.
Every row is complete and valid under the request's rules (ask
`dead(request, partial)`, or complete a partial row with `witness`). The
request's must-include rows come first, in order, unchanged where they are
set and completed in place where they are not (contract §10.5, §7.10); then
rows until every required target is in some row. The targets are read
through `supports`, `ncombinations`, `isrequired` and `nrequired`
(`RequiredTargets`), which list no target; they are shared with every engine
that covers the same request (`Auto`'s starts, `design_sizes`' engines) and
with the certifier, which recounts the rows against them, so an engine never
changes them and keeps its search state, a coverage index's counts for one,
in what it builds for its run. `generate` certifies the result
(`validate_design`, §1.21), so a wrong design is an internal error, never a
wrong answer.

What an engine reports stays in its own stage of the result's record (its
`ordinary` stage, or a negative sub-request's in `negative`), beside the
`engine` and `rows` that `_run` writes there and an engine may not. The
record's own fields, the lower bound, whether the design is minimal, the
proof, whether the engine is randomized, and the configuration, are the
pipeline's, and no engine sets them (`_covering_record`).

An engine may also define `_fallback(engine)`, the engine that covers what
its `fit` refuses (IPOG by default); a randomized engine says so in its
record (`EngineRecord`'s `randomized`), so that results show its seed. Add
the engine to `_engine_registry`, so that the oracle loops of
test/test_random_problems.jl check it against the independent oracle
(test/checker.jl), the seed-line test of test/test_engines.jl runs the call
its results name, and the benchmark harness can name it; and give its plan
and inner loops `@inferred` and `@allocated` tests in
test/test_stability.jl (no JET).

Every engine keeps these rules.

- **Ordinary values only.** An engine never sees an `Invalid` value. For each
  invalid value, `cover_negative` (invalid.jl) hands the engine a sub-request
  over the other parameters, whose base strength is one less and may be 0,
  in which case only its `stronger` groups carry targets. The engine's plan
  is prepared from that sub-request's profile, and an `:unsupported` fit
  sends it to `_fallback` (`_prepare_for`).
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
required target in `targets` (`CoveringEngine`). For an engine with a plan
of its own, the rows its plan's execution gives (`_cover`).
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
(`CoveringEngine`, `Fit`): the fit of the plan `_prepare` makes.
"""
function fit end

"""
Use when you want IPOG's design itself, which `Auto(goal = :fast)` also runs:
deterministic and free of randomness, so the same inputs always give the
same cases, and covering any request.

    IPOG()

In-parameter-order General (IPOG): deterministic, no randomness (contract
§9.4). It builds the design one parameter at a time, as four members of the
IPOG family, and keeps the smallest (the manual's IPOG page). The default
engine, [`Auto`](@ref)`()`, gives IPOG's design except where the catalog's
array ([`Construction`](@ref)) is smaller.

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
    EngineRecord(name, seed, parameters = Pair{Symbol, Any}[]; randomized = false)

What an engine says of itself (plan §4.2), from `engine_record(engine)`:
`name`, the `Symbol` that a `Design` and a [`TestCases`](@ref) keep as
`engine`; `seed`, the seed a randomized engine draws from, or `nothing` when
it draws from a caller's `rng` (contract §9.6) or uses no randomness;
`parameters`, its other settings as `keyword => value` pairs, each value
plain data (a number, `Symbol`, `String`, `Bool` or `nothing`) or a covering
engine, as a wrapper's `inner` is, or a vector of them, as `Auto`'s
candidates are; and `randomized`, whether the engine draws random numbers,
so that results show its seed (§9.5). `Auto` is randomized only with `goal =
:compact`, which is why this is a field and not a fact about the name.

`generate` reads it once per call, as the result's configuration,
`record.engine` (`_engine_config`), which the display reads (`_engine_phrase`,
`_seed_note`, `_seed_text`).
"""
struct EngineRecord
    name::Symbol
    seed::Union{Nothing, Int}
    parameters::Vector{Pair{Symbol, Any}}
    randomized::Bool
end

EngineRecord(name::Symbol, seed, parameters::Vector{Pair{Symbol, Any}} = Pair{Symbol, Any}[];
             randomized::Bool = false) = EngineRecord(name, seed, parameters, randomized)

"Whether an engine draws random numbers, so that its seed is shown (contract §9.5)."
_randomized(record::EngineRecord) = record.randomized

"""
    _engine_label(engine) -> String

An engine as its constructor call, for the record, tables and messages:
"IPOG()", "GND(seed = 3)", "Construction()", "Compact(IPOG(); seed = 0,
effort = 1)", "Auto(goal = :compact)": its `show`, which for GND names the
seed and any other number of candidates than 50. Run in a module that uses
the package, the call gives an engine that makes the same rows, unless it
draws from a caller's generator, shown as "GND(rng = Xoshiro(…))".
"""
_engine_label(engine::CoveringEngine) = sprint(show, engine)
_engine_label(::IPOG) = "IPOG()"   # `show` would name the module where the package isn't loaded in `Main`
function _engine_label(e::GND)
    settings = e.rng === nothing ? ["seed = $(e.seed)"] : ["rng = $(nameof(typeof(e.rng)))(…)"]
    e.candidates == 50 || push!(settings, "candidates = $(e.candidates)")
    return "GND(" * join(settings, ", ") * ")"
end

"""
    _engine_config(engine) -> NamedTuple

The configuration a covering result records of its engine, `record.engine`,
as plain data (plan §4.2): `name`; `call`, the constructor call
(`_engine_label`); `seed`; `randomized`; and `settings`, the record's other
`parameters` as a `NamedTuple`, in which a covering engine, such as
`Compact`'s `inner` or each of `Auto`'s `candidates`, is its own
configuration, nested the same way. So `Compact(GND(seed = 17); seed = 3,
effort = 2)` records `(name = :Compact, call = "Compact(GND(seed = 17); seed
= 3, effort = 2)", seed = 3, randomized = true, settings = (inner = (name =
:GND, call = "GND(seed = 17)", seed = 17, randomized = true, settings =
(candidates = 50,)), effort = 2))`.
"""
function _engine_config(engine::CoveringEngine)
    r = engine_record(engine)
    keys = Tuple(first(p) for p in r.parameters)
    # Collected as `Any` from the start: a generator of settings of different
    # types (Auto's goal, effort and candidates) widens its vector as it goes,
    # and that widening is compiled in each fresh session, outside the package
    # image, about 14 ms of the default engine's first call.
    settings = NamedTuple{keys}(Tuple(Any[_config_value(last(p)) for p in r.parameters]))
    return (name = r.name, call = _engine_label(engine), seed = r.seed, randomized = r.randomized,
            settings = settings)
end

_config_value(v::CoveringEngine) = _engine_config(v)
_config_value(v::AbstractVector{<:CoveringEngine}) = NamedTuple[_engine_config(e) for e in v]
_config_value(v) = v

"The configurations nested in one: a wrapper's `inner` and `Auto`'s `candidates`, in order."
function _nested_configs(config::NamedTuple)
    nested = NamedTuple[]
    for v in values(config.settings)
        v isa NamedTuple && haskey(v, :call) && push!(nested, v)
        v isa AbstractVector && append!(nested, (c for c in v if c isa NamedTuple && haskey(c, :call)))
    end
    return nested
end

"""
    _drew_from_rng(config) -> Union{Nothing, NamedTuple}

The first configuration in `config`'s tree, itself included, of an engine
that drew from a caller's generator (randomized, with no seed), whose rows
no seed repeats (contract §9.6); `nothing` when there is none.
"""
function _drew_from_rng(config::NamedTuple)
    config.randomized && config.seed === nothing && return config
    for nested in _nested_configs(config)
        found = _drew_from_rng(nested)
        found === nothing || return found
    end
    return nothing
end

# The engine's name, a wrapped engine shown as its call: "IPOG", "Compact(GND(seed = 17))".
function _engine_name(config::NamedTuple)
    inner = get(config.settings, :inner, nothing)
    return inner isa NamedTuple ? "$(config.name)($(inner.call))" : string(config.name)
end

"""
    _engine_phrase(config, chose = nothing) -> String

How the summary line names the engine that made a result, from the
configuration it recorded (`record.engine`, §1.22): "IPOG", "GND seed 3",
"GND, caller's rng", "Compact(GND(seed = 17)) seed 3", and with what `Auto`
chose (its stage's `chose`), "Auto: Construction()" or "Auto:
Compact(Construction()) seed 0".
"""
function _engine_phrase(config::NamedTuple, chose::Union{Nothing, AbstractString} = nothing)
    phrase = chose === nothing ? _engine_name(config) : "$(_engine_name(config)): $chose"
    config.randomized || return phrase
    return config.seed === nothing ? "$phrase, caller's rng" : "$phrase seed $(config.seed)"
end

"A randomized engine's seed in `report`'s guarantee line, from its configuration, or `nothing` for an engine without one."
function _seed_note(config::NamedTuple)
    config.randomized || return nothing
    name = _engine_name(config)
    return config.seed === nothing ? "$name with the caller's rng" : "$name seed $(config.seed)"
end

"""
    _seed_text(config) -> String

`report`'s seed line for a covering design (§9.5), from its configuration
(`record.engine`): the seed and the call that repeats the cases, the
configuration's `call`, "seed: 3 (Compact(GND(seed = 17); seed = 3, effort =
2) repeats these cases)"; or why no seed repeats them: the engine uses no
randomness, or an engine in it drew from the caller's generator.
"""
function _seed_text(config::NamedTuple)
    config.randomized || return "seed: none ($(config.name) uses no randomness)"
    config.seed === nothing && return "seed: none ($(config.name) drew from the caller's rng)"
    drew = _drew_from_rng(config)
    drew === nothing || return "seed: $(config.seed) ($(drew.name) inside $(config.name) drew from the caller's " *
                               "rng, so no seed repeats these cases)"
    return "seed: $(config.seed) ($(config.call) repeats these cases)"
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
- `:seeded`: the engine builds a start that IPOG's core extends
  (`_lookup_cover`; §4.1, stage 2), such as a catalog array with the rows a
  rule forbids dropped;
- `:unsupported`: the engine can't cover it. Where generation hands an engine
  part of a request, that part goes to the engine's fallback instead
  (`_prepare_for`).
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

What an engine's plan (`_prepare`) and so its `fit` read of a request (plan
§4.2), and what Phase 3's `recommend` and `Auto` read. It is computed from
the request alone, without classifying or listing a target, so it costs
time in the parameters, groups and rules, never in the targets.

- `arity`: the ordinary values of each parameter, engine positions
  `1:arity[i]`; the parameter count is its length (`nparameters`).
- `prime_power`: whether each `arity[i]` is a prime power, as the field
  constructions of Phase 2 need.
- `strength` and `groups`: as the request has them, the base group first,
  then each `stronger` group with its strength. A negative sub-request's base
  strength may be 0.
- `n_must_include`: the ordinary must-include rows, those that hold no
  [`Invalid`](@ref) value. They are the must-include rows of the ordinary
  design, which `generate` builds from the ordinary request (the request with
  the negative must-include rows set apart), so the whole request's profile
  and the ordinary request's are the same, and a fit reads what the engine
  will cover. A negative must-include row is a must-include row of the
  negative sub-request of its invalid value (`cover_negative`), over the
  other parameters, where it holds no invalid value, so that sub-request's
  profile counts it.
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
    must = request.must_include
    ordinary = count(j -> !_holds_invalid(request, view(must, :, j)), axes(must, 2))
    return Profile(arity, BitVector(_is_prime_power.(arity)), request.strength, groups,
                   ordinary, n_invalid, rules, _target_count(arity, groups))
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
groups. A state that only choices of `s` parameters reach makes no new
state, so the states are the distinct sets of groups that hold some choice of
at most `s` parameters, whatever the number of groups: twenty groups of
twenty of 21 parameters at strength 3 make 1,351 states (1 + 20 + 190 +
1,140), where without that rule each of the 2^20 − 1 intersections of groups
is one.
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
            # A state that only choices of `s` parameters reach is complete: it
            # makes no new state, else the states could number 2^G for G groups.
            any(!iszero, view(e, 1:s)) || continue
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
    _Plan

What an engine will build for a request, decided from its `Profile` alone
(`_prepare`, plan §4.2), and executed by generation (`_execute`). Every plan
has two fields: `engine`, the engine whose plan it is, and `fit`, its `Fit`
for the request, which `fit(engine, profile)` returns. Beside them it holds
the engine's recipe: nothing for an engine that decides nothing ahead
(`_DefaultPlan`), IPOG's order and members (`_IPOGPlan`), the catalog's entry
(`_ConstructionPlan`), the inner engine's plan (`_CompactPlan`), the
candidates' plans (`_AutoPlan`). A plan
is made once per request and read by every caller that needs the decision:
`generate` and `design_sizes` execute it, a negative sub-request takes it or
its fallback's (`_prepare_for`), and `recommend` shows `Auto`'s.
"""
abstract type _Plan end

"""
    _DefaultPlan(engine, fit)

The plan of an engine that defines `fit` and `cover_ordinary` and decides
nothing ahead, as GND: the engine and its fit. Executing it calls
`cover_ordinary`, and the engine reports nothing beyond its rows.
"""
struct _DefaultPlan{E <: CoveringEngine} <: _Plan
    engine::E
    fit::Fit
end

"""
    _prepare(engine, profile::Profile) -> plan

`engine`'s plan for a request with this profile (`_Plan`), from the profile
alone: no target is listed and nothing is built. The default is
`_DefaultPlan(engine, fit(engine, profile))`; an engine with a recipe defines
its own, and its `fit` is the plan's.
"""
_prepare(engine::CoveringEngine, p::Profile) = _DefaultPlan(engine, fit(engine, p))

"""
    _execute(plan, request, targets::RequiredTargets) -> (matrix, notes::NamedTuple)

The rows `plan` builds for `request` (`cover_ordinary`'s promise,
`CoveringEngine`), with `notes`, plain data on what the engine found, which
the stage of `_run` keeps. `request`'s profile is the one the plan was
prepared from. For `_DefaultPlan`, `cover_ordinary`'s rows and no notes.
"""
_execute(plan::_DefaultPlan, request::Request, targets::RequiredTargets) =
    (cover_ordinary(plan.engine, request, targets), (;))

"""
    _run(plan, request, targets) -> (matrix, stage::NamedTuple)

`_execute(plan, …)`, with its notes as a stage of the result's record: the
plan's `engine`, as its call (`_engine_label`), and the `rows` it made, then
the engine's notes. A wrapper or a chooser runs its inner plans this way, so
that the record keeps each stage under its own. An engine's notes may not
set `engine` or `rows`, which are the stage's: that is an internal error.
The return type is asserted, since `Auto` runs its candidates' plans without
knowing their types.
"""
function _run(plan::_Plan, request::Request, targets::RequiredTargets)
    matrix, notes = _execute(plan, request, targets)
    for key in (:engine, :rows)
        haskey(notes, key) && error("internal error: $(_engine_label(plan.engine))'s notes set its stage's `$key`")
    end
    return (matrix, merge((engine = _engine_label(plan.engine), rows = size(matrix, 2)), notes))::
           Tuple{Matrix{Int}, NamedTuple}
end

"""
    _known_rows(plan) -> Union{Nothing, Int}

The ordinary rows `plan` builds, when they are known without running it:
the fit's `rows` by default; the catalog's array for an exact shape, also
with `Invalid` values, whose negative rows follow (`_ConstructionPlan`).
"""
_known_rows(plan::_Plan) = plan.fit.rows

"""
    _at_bound(plan) -> Bool

Whether `plan`'s ordinary rows are known to equal a lower bound on every
design for the request, so that no engine builds fewer (an orthogonal or
zero-sum array). `false` by default.
"""
_at_bound(::_Plan) = false

"""
    _plan_line(plan) -> String

One line on what `plan` builds, for `recommend`'s table: the fit's reason by
default; for an exact catalog shape, its size and construction.
"""
_plan_line(plan::_Plan) = plan.fit.reason

"The rows of an engine with a plan of its own: its plan's, prepared from the request (`cover_ordinary`)."
_cover(engine::CoveringEngine, request::Request, targets::RequiredTargets) =
    first(_execute(_prepare(engine, Profile(request)), request, targets))

"""
    _fallback(engine) -> CoveringEngine

The engine that covers what `engine`'s `fit` refuses (plan §4.2): IPOG, which
covers any request. An engine may name another that covers any request, such
as a wrapper that wraps its inner engine's fallback.
"""
_fallback(::CoveringEngine) = IPOG()

"""
    _prepare_for(engine, profile) -> plan

The plan that covers a part of a request that generation hands `engine`
(plan §4.2): `engine`'s own, or its `_fallback`'s when `engine`'s plan's fit
is `:unsupported`, each prepared once. The negative sub-requests of
`cover_negative` (invalid.jl) go through it. IPOG and GND fit every request,
so for them it is the engine's own.
"""
function _prepare_for(engine::CoveringEngine, p::Profile)
    plan = _prepare(engine, p)
    plan.fit.kind === :unsupported || return plan
    return _prepare(_fallback(engine), p)
end

"The engine that covers `request` when generation hands it to `engine`: the engine of `_prepare_for`'s plan."
_engine_for(engine::CoveringEngine, request::Request) = _prepare_for(engine, Profile(request)).engine

"""
    _engine_registry(seed = 0) -> Vector{Pair{String, CoveringEngine}}

Every engine the package checks, by name, with `seed` for each randomized one
(plan §4.2, §7.4). The oracle loops of test/test_random_problems.jl run every
engine here on every random problem and check each design with the
independent oracle (test/checker.jl), so an engine added here is checked with
no other change to the tests. The benchmark harness (benchmark/scaling/
worker.jl) resolves a job's `solver` by these names. A name is the engine's
constructor call without its seed, such as `"IPOG()"` or `"Compact(IPOG())"`.
`Auto`'s two pipelines are here, `"Auto()"` and `"Auto(goal = :compact)"`, so
that every pipeline it can choose (IPOG, the catalog, and either reduced) is
checked as `Auto` runs it.

The list is in the package, not in test/, so that the harness, which loads
only the package, reads the same list the tests run. Nothing in `src/` calls
it.
"""
_engine_registry(seed::Integer = 0) =
    Pair{String, CoveringEngine}["IPOG()" => IPOG(), "GND()" => GND(; seed),
                                 "Compact(IPOG())" => Compact(IPOG(); seed),
                                 "Construction()" => Construction(),
                                 "Auto()" => Auto(),
                                 "Auto(goal = :compact)" => Auto(; goal = :compact, seed)]

"""
    _check_fit(engine, request) -> plan

The engine's plan for the whole request (`_prepare`, plan §4.2), or an
`ArgumentError` with its fit's reason when that is `:unsupported`, which
names the engine as it was called and suggests `IPOG()` or `Auto()`, which
cover any request. The plan reads the request's `Profile`, which describes
the ordinary design (its must-include rows are the ordinary ones), so it is
the plan for the ordinary request too, and `generate` executes it. A
directly named engine covers the ordinary design or says why not; it never
hands it to another engine, so a result's ordinary rows are always the named
engine's, the `engine` it records (option (c) of p0-protocol's judgment call
1). The parts of a request that generation hands an engine, the negative
sub-requests of a space with `Invalid` values, still go to its fallback
where it refuses them (`_prepare_for`), so those negative rows may be the
fallback's, as the record's `negative` stages say: IPOG's for
`Construction()`, which has no array for a sub-request's strength 1, and
`Compact(IPOG())`'s for `Compact(Construction())`. IPOG and GND fit every
request, so for them this never throws.
"""
function _check_fit(engine::CoveringEngine, request::Request)
    plan = _prepare(engine, Profile(request))
    f = plan.fit
    f.kind === :unsupported || return plan
    throw(ArgumentError("$(_engine_label(engine)) does not cover this request: $(f.reason); " *
                        "IPOG() or Auto() covers any request"))
end

"""
    generate(engine::CoveringEngine, request::Request) -> Design

The one engine entry point (plan Phase 3 step 1): a covering design for
`request` in index space, certified by `validate_design` before it returns
(contract §1.21). Every [`CoveringEngine`](@ref) builds covering designs
(§1.3): `generate` prepares the engine's plan once (`_check_fit`, which
refuses with an `ArgumentError`, before anything is classified, a request the
plan's fit refuses) and executes it (`_generate`). Every target
classification, must-include completion and placement decision is resolved
or the call throws `ResourceLimitError` (§3.6); a design is never returned
with a target unresolved or dropped.
"""
generate(engine::CoveringEngine, request::Request) = _generate(_check_fit(engine, request), request)

"""
    _Classified(request)

A request's targets, classified once (contract §1.4, §6): `targets`, the
ordinary targets as engines and the certifier read them, a `RequiredTargets`
on the request's `TargetList`, which classification walks
(`_classify_targets`) and which is built once; `excluded`, the ordinary
`Excluded` records; and, for a space with `Invalid` values, `negative`, the
negative targets' `(required, excluded)` (`classify_negative_targets`),
classified the first time negative generation asks (`_negative_targets!`),
after the ordinary design, as before, so that a request whose ordinary
design stops at a resource limit stops there. Classification is a function
of the request's space, strength, groups and limits, never of its
must-include rows (the ordinary request of a space with `Invalid` values has
the same targets) or of the engine, so every generation of such a request
reads the same, and `design_sizes` hands one to each engine at a strength.

No ordinary target is listed: `targets` holds the layout, a count per
support and the ids of the excluded targets, and the required targets are
the rest of the layout (`RequiredTargets`); an unconstrained request's
`targets` is its `TargetList` whole.

What engines may share is immutable: the targets' layout, counts and ids,
and the parts made on first use, each written once (the required bits, the
negative targets) and then only read. An engine's search state, a coverage
index's counts or the reducer's, is made for each run and never kept here.
The package runs nothing concurrently inside a call, and design_sizes runs
its engines one after another, so the parts made on first use need no lock.
"""
mutable struct _Classified{L <: Union{Nothing, TargetList}}
    const targets::RequiredTargets{L}
    const excluded::Vector{Excluded}
    negative::Union{Nothing, Tuple{Vector{Vector{Int}}, Vector{Excluded}}}
end

function _Classified(request::Request)
    targets, excluded = _classify_targets(request, TargetList(request))
    return _Classified(targets, excluded, nothing)
end

"The negative targets of `classified`'s request, classified on first use (`_Classified`)."
function _negative_targets!(classified::_Classified, request::Request)
    negative = classified.negative
    negative === nothing || return negative
    negative = classify_negative_targets(request)
    classified.negative = negative
    return negative
end

"""
    _generate(plan, request[, classified]) -> Design

`generate` for a plan of `request`'s profile that covers it, which
`design_sizes` also calls with the plan whose fit it read. The ordinary
design is built first, over ordinary values only, from the classified
ordinary targets (`_classify_targets`, read through `RequiredTargets`) and
the ordinary must-include rows (`_run`), and certified against the same
targets (`validate_design`). When the space has
[`Invalid`](@ref) values, negative generation (`cover_negative`, invalid.jl)
then covers the negative targets of §6 with the same engine, or its fallback
where its fit refuses a sub-request (`_prepare_for`). The rows are the
must-include rows in the order given, each completed under its own row
policy (§7.9), then the generated ordinary rows, then the generated negative
rows (§5.12). The two kinds' bookkeeping is kept apart (§1.19).

The result's record (`_covering_record`) holds the lower bound on its rows
(`_ordinary_bound`, and the negative rows' from `cover_negative`), the
engine's configuration (`_engine_config`), and the stages that ran: the
ordinary design's, and each negative sub-request's.

`classified` is the request's targets (`_Classified`), classified here
unless a caller that generates several designs for one request passes them
(`design_sizes`).
"""
_generate(plan::_Plan, request::Request) = _generate(plan, request, _Classified(request))

function _generate(plan::_Plan, request::Request, classified::_Classified)
    engine = plan.engine
    targets, excluded = classified.targets, classified.excluded
    record = engine_record(engine)
    name, seed = record.name, record.seed
    config = _engine_config(engine)
    names = request.space.names
    if !_has_invalid(request.space)
        matrix, stage = _run(plan, request, targets)
        covered = validate_design(request, matrix, targets)
        bound = _bound_record(size(matrix, 2), _ordinary_bound(request, targets), 0, names, request.arity,
                              supports(targets))
        return Design(matrix, :covering, name, seed, nrequired(targets), covered, excluded,
                      n_must_include(request), (;), 0, 0, Excluded[],
                      _covering_record(config, bound, stage, NamedTuple[]))
    end
    must = request.must_include
    negative_columns = [j for j in axes(must, 2) if _holds_invalid(request, view(must, :, j))]
    ordinary_columns = [j for j in axes(must, 2) if !(j in negative_columns)]
    ordinary_request = _with_must_include(request, must[:, ordinary_columns])   # the same targets
    ordinary, stage = _run(plan, ordinary_request, targets)
    negative = cover_negative(engine, request, negative_columns, _negative_targets!(classified, request))
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
    covered = validate_design(request, matrix, targets; negative = negative.required)
    bound = _bound_record(size(matrix, 2), _ordinary_bound(ordinary_request, targets), negative.bound, names,
                          request.arity, supports(targets))
    return Design(matrix, :covering, name, seed, nrequired(targets), covered, excluded,
                  n_must_include(request), (;), length(negative.required), length(negative.required),
                  negative.excluded, _covering_record(config, bound, stage, negative.stages))
end

"""
    _covering_record(config, bound, ordinary, negative) -> NamedTuple

A covering result's record (`TestCases`'s `record`; contract §1.19, §8.7).
The pipeline's fields come first, and only `generate` sets them:
`randomized`, from the engine's record; `lower_bound`, `minimal` and
`proof`, from the bound the pipeline proved and checked against the
certified rows (`_bound_record`); and `engine`, the configuration
(`_engine_config`). Then the stages: `ordinary`, the ordinary design's
(`_run`), and `negative`, one per invalid value (`cover_negative`). What an
engine reports is only ever inside a stage, so it can't claim the bound,
minimality, a proof or randomness for the result.
"""
_covering_record(config::NamedTuple, bound::NamedTuple, ordinary::NamedTuple, negative::Vector{NamedTuple}) =
    (randomized = config.randomized, lower_bound = bound.lower_bound, minimal = bound.minimal, proof = bound.proof,
     engine = config, ordinary = ordinary, negative = negative)
