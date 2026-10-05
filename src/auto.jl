# `Auto`, the engine that chooses (plan §6.1, §4.1; decisions D1, D8), and
# `recommend`, which says what it would choose without generating (§6.1).
#
# `Auto` combines the pipeline of plan §4.1. Its starts are IPOG, which covers
# any request, and the catalog (`Construction`) where its `fit` is `:exact` or
# `:seeded`. With `goal = :balanced` it keeps the start with the fewest rows:
# where the space is small (`_AUTO_SMALL`, a count of targets, never a time),
# it runs both and compares; above that it runs one, chosen from the request
# alone (`_auto_plan`). `goal = :compact` then reduces the winner once with
# the row reducer (`_compact`, §4.1 step 3). `goal = :fast` is IPOG alone.
#
# The choice is a pure function of the request (contract §9.1): `_auto_plan`
# reads the `Profile` and nothing else, never a search result, a limit or
# the clock (§3.8, §9.3), and the candidates are a fixed list, so loading a
# package that defines another engine changes nothing (plan §5.9). Each
# candidate is prepared through the engine protocol (`_prepare`), and `Auto`
# reads its plan only through `_known_rows`, `_at_bound` and `_plan_line` and
# executes it with `_execute`, so it knows no candidate's recipe. A candidate that
# throws `ResourceLimitError` makes the call throw: nothing here catches it.
# Only the winner is certified, by `generate`.

"""
    _AUTO_SMALL

The keep-the-smallest threshold of `Auto(goal = :balanced)` (plan §4.1,
§7.5): at most this many targets, counted before the rules
(`Profile.targets`), and both starts are run and the smaller kept; above it,
one start is chosen from the request alone (`_auto_plan`). A count, never a
time, so the choice depends only on the request (contract §9.1, §9.3). Chosen
from the regret table of design/…/p3-auto.md (benchmark/auto_regret.jl).
"""
const _AUTO_SMALL = 100_000
const _AUTO_SMALL_TEXT = "100000"

"""
Use when you want the package to choose the engine for your space: the
smallest of the designs it can build quickly, or, with `goal = :compact`,
that design reduced further; `recommend` shows the choice before you run it.

    Auto(; goal = :balanced, seed = 0, effort = 1)

A covering engine that picks its method from the request (plan §6.1).
`goal` says what your tests cost, which the space can't tell:

| `goal` | Runs | For |
|:--|:--|:--|
| `:fast` | [`IPOG`](@ref) alone, the same rows as `engine = IPOG()` | cheap tests |
| `:balanced` | the smaller of IPOG's design and the catalog's array ([`Construction`](@ref)) where the catalog applies | the default for `Auto` |
| `:compact` | that, then the row reducer ([`Compact`](@ref)) with `effort` | expensive tests |

Where the catalog's array has as many rows as the lower bound, no design
has fewer, so IPOG isn't run. Otherwise, where the space is small (at most
$(replace(_AUTO_SMALL_TEXT, r"(?<=\d)(?=(\d{3})+$)" => ",")) combinations
to cover, counted before the rules) and the catalog applies, it builds both
and keeps the one with fewer rows, IPOG's on a tie, so that it gives the
cases `IPOG()` gives unless the catalog's are fewer. Above that size it
builds one: the catalog's array for a shape the catalog builds exactly
(parameters that all have the same number of values, or `strength + 1`
parameters, with no rules, no must-include rows other than negative ones,
and no `stronger` groups), and IPOG's design otherwise. So `:balanced`
never returns more cases than `:fast`, except that above that size the
catalog's array is not compared with IPOG's design: on the package's
benchmarks it was never larger, which is measured, not guaranteed.
`:compact` reduces the winner once, so it never has more rows than
`:balanced`. The negative rows of a space with [`Invalid`](@ref) values are
chosen the same way, for each invalid value.

`:fast` and `:balanced` use no randomness, and `seed` is not recorded. With
`:compact` the reducer draws from a fresh generator seeded with `seed` (an
integer of at least 0) on every call, so the same seed gives the same
cases, and the result records the seed (contract §9.11). `effort`, a
positive integer, multiplies the reducer's two budgets, of steps and of
combinations read, never seconds (see [`Compact`](@ref), which also says
when a design is too large to reduce).

What `Auto` chose for the ordinary cases is in the result's record,
`cases.record.chose`, with the rows of each start it ran in
`cases.record.candidates`; the summary line names it, as in "Auto:
Construction()". The negative rows' choices are not recorded. The choice
depends only on the request, never on the clock or a limit, but a later
version may choose differently (contract §9.8). To keep a design, save it
and pass it back as `must_include` (§9.10).
"""
struct Auto <: CoveringEngine
    goal::Symbol
    seed::Int
    effort::Int

    function Auto(; goal = :balanced, seed = 0, effort = 1)
        goal in (:fast, :balanced, :compact) || throw(ArgumentError(
            "goal is :fast, :balanced or :compact; got $(repr(goal)) (see `Auto`)"))
        return new(goal, _check_integer(:seed, seed, 0, "§9.11"), _check_integer(:effort, effort, 1, "§9.11"))
    end
end

function Base.show(io::IO, e::Auto)
    settings = String[]
    e.goal === :balanced || push!(settings, "goal = $(repr(e.goal))")
    e.seed == 0 || push!(settings, "seed = $(e.seed)")
    e.effort == 1 || push!(settings, "effort = $(e.effort)")
    print(io, "Auto(", join(settings, ", "), ")")
end

"""
    _AutoCandidate

One start `Auto` considers (`_auto_plan`): `label`, its engine's
constructor call; `plan`, its engine's plan for the request (`_prepare`),
whose `fit` says how it fits; `runs`, whether `Auto` runs it; `rows`, its
size when known without running it (`_known_rows`: the catalog's array for
an exact shape); and `reason`, one line on why it runs or not, which
`recommend` shows.
"""
struct _AutoCandidate
    label::String
    plan::_Plan
    runs::Bool
    rows::Union{Nothing, Int}
    reason::String
end

"""
    _AutoPlan

`Auto`'s plan for a request (`_prepare`, `_auto_plan`): `engine`; `fit`,
which covers any request; `candidates`, in the fixed order of a tie, IPOG
first, then the catalog; `smallest`, whether it runs more than one and keeps
the fewest rows; and `why`, one line on the rule.
"""
struct _AutoPlan <: _Plan
    engine::Auto
    fit::Fit
    candidates::Vector{_AutoCandidate}
    smallest::Bool
    why::String
end

# The starts, in the fixed order of a tie: IPOG, which covers any request, then the catalog.
_auto_engines() = (IPOG(), Construction())

"The candidates' plans for a request with this profile, in `_auto_engines`' order, each prepared once."
_auto_starts(p::Profile) = map(e -> _prepare(e, p), _auto_engines())

"""
    _auto_plan(engine::Auto, profile, starts = _auto_starts(profile)) -> _AutoPlan

The starts `engine` runs for a request with this `Profile`, from the profile
alone (plan §4.1), and from the candidates' plans `starts`, IPOG's and the
catalog's, which `recommend` prepares once for every goal it reports: no
target is classified and nothing is built, so the choice depends only on the
request (contract §9.1), and `recommend` shows it without generating.

- `:fast`: IPOG alone.
- Otherwise, when the catalog's fit is `:unsupported`: IPOG alone.
- When the catalog's array is known to have as many rows as the lower bound
  (`_at_bound`: an orthogonal array, a zero-sum array): the catalog alone.
  IPOG can't have fewer rows, and the array is balanced (an orthogonal array
  shows each combination once).
- When the request has at most `_AUTO_SMALL` targets: both, and the fewer rows
  are kept, IPOG's on a tie (keep the smallest), so that `Auto` gives IPOG's
  cases wherever the catalog is not smaller.
- Above it, `:exact`: the catalog alone. In the regret table no uniform
  shape above the threshold had a catalog array larger than IPOG's design.
- Above it, `:seeded`: IPOG alone, since a seeded design's size is known
  only after running it.
"""
function _auto_plan(engine::Auto, p::Profile, starts = _auto_starts(p))
    ipog, catalog = starts
    f = catalog.fit
    targets = "$(p.targets) combinations to cover"
    rows = _known_rows(catalog)
    line = _plan_line(catalog)
    plan(candidates, smallest, why) =
        _AutoPlan(engine, Fit(:native, "Auto covers any request: IPOG, or the catalog's array where it fits"),
                  candidates, smallest, why)
    array(runs, reason) = _AutoCandidate(_engine_label(catalog.engine), catalog, runs, rows, reason)
    start(runs, reason) = _AutoCandidate(_engine_label(ipog.engine), ipog, runs, _known_rows(ipog), reason)
    if engine.goal === :fast
        return plan([start(true, "IPOG alone, as goal = :fast asks"),
                     array(false, "not run: goal = :fast is IPOG alone")], false, "goal = :fast runs IPOG alone")
    elseif f.kind === :unsupported
        return plan([start(true, "covers any request"), array(false, "not run: $(f.reason)")], false,
                    "the catalog doesn't cover this request")
    elseif _at_bound(catalog)
        return plan([start(false, "not run: no design has fewer rows than the catalog's array, which meets the " *
                                  "lower bound"), array(true, line)], false,
                    "the catalog's array meets the lower bound")
    elseif p.targets <= _AUTO_SMALL
        return plan([start(true, "covers any request"), array(true, line)], true,
                    "$targets, at most $_AUTO_SMALL_TEXT: both run, and the fewer rows are kept, IPOG's on a tie")
    elseif f.kind === :exact
        return plan([start(false, "not run: above $_AUTO_SMALL_TEXT combinations Auto runs one start, and for an " *
                                  "exact shape that is the catalog's array"), array(true, line)], false,
                    "$targets, above $_AUTO_SMALL_TEXT: one start, the catalog's array")
    end
    return plan([start(true, "covers any request"),
                 array(false, "not run: above $_AUTO_SMALL_TEXT combinations Auto runs one start, and a " *
                            "seeded array's size is known only after running")],
                false, "$targets, above $_AUTO_SMALL_TEXT: one start, IPOG")
end

_prepare(engine::Auto, p::Profile) = _auto_plan(engine, p)

"""
    _auto_label(plan, profile) -> String

What `Auto` runs, as one engine call: "Construction()", "IPOG()", or, when it
keeps the smaller of two, "the smaller of IPOG() and Construction()";
wrapped in "Compact(…)" for `goal = :compact`, unless the reducer would
return the start unreduced (`_unreduced`).
"""
function _auto_label(plan::_AutoPlan, p::Profile)
    labels = [c.label for c in plan.candidates if c.runs]
    label = length(labels) == 1 ? only(labels) : "the smaller of " * _and_list(labels)
    return plan.engine.goal === :compact && _unreduced(plan, p) === nothing ? "Compact($label)" : label
end

"""
    _unreduced(plan, profile) -> Union{Nothing, String}

Why the row reducer would return `Auto`'s start unreduced (`_compact`), when
the profile shows it, or `nothing`: the coverage index would hold more than
`_COMPACT_MAX_COMBINATIONS` combinations, or the one start that runs is the
catalog's array, of more rows than an index counts (`typemax(UInt16)`). A
start of IPOG's past that many rows is known only after running it, when
`Auto`'s record says so (`_execute(::_AutoPlan, …)`).
"""
function _unreduced(plan::_AutoPlan, p::Profile)
    p.targets > _COMPACT_MAX_COMBINATIONS &&
        return "the coverage index would hold $(p.targets) combinations, above Compact's $(_COMPACT_MAX_COMBINATIONS)"
    known = [c.rows for c in plan.candidates if c.runs]
    if all(rows -> rows !== nothing, known)
        fewest = minimum(rows -> rows::Int, known)
        fewest > typemax(UInt16) &&
            return "the catalog's array has $fewest rows, above the $(Int(typemax(UInt16))) Compact reduces"
    end
    return nothing
end

"""
    _engine_label(engine) -> String

An engine as its constructor call, for tables and messages: "IPOG()",
"GND(seed = 3)", "Construction()", "Compact(IPOG(); seed = 0, effort = 1)",
"Auto(goal = :compact)".
"""
_engine_label(engine::CoveringEngine) = sprint(show, engine)
_engine_label(::IPOG) = "IPOG()"
_engine_label(::Construction) = "Construction()"
function _engine_label(e::GND)
    settings = e.rng === nothing ? ["seed = $(e.seed)"] : ["rng = $(typeof(e.rng))(…)"]
    e.candidates == 50 || push!(settings, "candidates = $(e.candidates)")
    return "GND(" * join(settings, ", ") * ")"
end

engine_record(e::Auto) = EngineRecord(:Auto, e.goal === :compact ? e.seed : nothing,
                                      Pair{Symbol, Any}[:goal => e.goal, :effort => e.effort];
                                      randomized = e.goal === :compact)

# Only `goal = :compact` is randomized, so the call that repeats the rows names it.
_repeat_call(::Val{:Auto}, seed) = "Auto(goal = :compact, seed = $seed) with the same effort"

fit(engine::Auto, p::Profile) = _prepare(engine, p).fit

cover_ordinary(engine::Auto, request::Request, targets::RequiredTargets) = _cover(engine, request, targets)

"""
    _execute(plan::_AutoPlan, request, targets) -> (matrix, notes)

The plan's starts, each through the engine protocol (`_execute` of its
plan), in the fixed order; the one with the fewest rows is kept, the first
on a tie; then, for `goal = :compact`, `_compact` on it, once (plan §4.1
step 3). A start that throws `ResourceLimitError` ends the call (plan §6.1).
`notes` record `chose`, the pipeline that made the rows, as
"Construction()" or "Compact(IPOG())", or the start alone when the reducer
returned it unreduced past its caps; `candidates`, each start that ran with
its rows, in order; then the winner's own notes (the catalog's array) and
the reducer's run. The starts' plans are of different types, so each
execution's result type is asserted, a function barrier.
"""
function _execute(plan::_AutoPlan, request::Request, targets::RequiredTargets)
    engine = plan.engine
    candidates = @NamedTuple{engine::String, rows::Int}[]
    best, notes, label = zeros(Int, length(request.arity), 0), (;), ""
    for c in plan.candidates
        c.runs || continue
        rows, found = _execute(c.plan, request, targets)::Tuple{Matrix{Int}, NamedTuple}
        push!(candidates, (engine = c.label, rows = size(rows, 2)))
        if isempty(label) || size(rows, 2) < size(best, 2)
            best, notes, label = rows, found, c.label
        end
    end
    engine.goal === :compact || return best, merge((chose = label, candidates), notes)
    matrix, reduced = _compact(request, targets, best; seed = engine.seed, effort = engine.effort)
    # Past the index's cap or the rows a count holds, the start comes back as it was.
    chose = reduced.reducer_stop in (:index_cap, :rows_cap) ? label : "Compact($label)"
    return matrix, merge((chose = chose, candidates), notes, (reducer = _reducer_record(reduced),))
end


## recommend

"""
Use when you want to know, before generating, what `Auto` would run for your
space and why, how many cases each `goal` can give where that is known
without running, and a lower bound on the cases of any design.

    Recommendation

What [`recommend`](@ref) returns. Fields:

- `goal::Symbol`: the goal asked about; `engine::String`: what
  `Auto(; goal)` would run, such as `"Construction()"`, `"IPOG()"`, `"the
  smaller of IPOG() and Construction()"`, or one of those inside
  `"Compact(…)"` for `:compact`, unless the reducer would return the start
  unreduced, as a note then says.
- `candidates`: the starts `Auto` considers, in the order a tie is broken
  (IPOG first), each a `NamedTuple` `(engine, fit, runs, rows, reason)`: its constructor
  call; how it fits the request (`:exact`, the catalog's array is the
  design; `:seeded`, the array seeds IPOG under the rules; `:native`, IPOG;
  `:unsupported`); whether `Auto` runs it; its number of cases when known
  without running (the catalog's array for an exact shape), else
  `nothing`; and one line on why.
- `rule::String`: how `Auto` chooses among them.
- `lower_bound`: a proven lower bound on the cases of any design for the
  request, and `proof`, why, as a result records it (`TestCases`'s `record`); `nothing`,
  with `proof` saying so, when the bound depends on the rules or the
  must-include rows, which only generation classifies.
- `sizes`: `(fast, balanced, compact)`, the most cases each goal can return,
  where that is known without running, else `nothing`. `:balanced` keeps the
  smaller of its starts, so it is at most the catalog's array whenever it
  runs it, and `:compact` is at most `:balanced`.
- `notes::Vector{String}`: things about the space worth knowing before
  generating, such as rules that read whole cases.
- `parameters`, `values` (the ordinary values of each parameter),
  `strength`, `stronger` (as `names => strength` pairs), `n_must_include`,
  `n_invalid`, `n_rules`, and `targets`, the combinations to cover before the
  rules exclude any.

`show` prints a short table:

```
Recommendation: 8 parameters × 32 values, strength 2, no rules; 28672 combinations to cover
  skip  IPOG()          not run: no design has fewer rows than the catalog's array, which meets the lower bound
  use   Construction()  1024 rows: Bush orthogonal array, every combination exactly once
lower bound: 1024 cases: the 32 × 32 = 1024 combinations of p1 and p2 need a case each
goals: :fast (IPOG alone) known only after running; :balanced 1024 cases, the minimum; :compact 1024 cases, the minimum
covering(…; engine = Auto()) would use Construction().
```
"""
struct Recommendation
    goal::Symbol
    engine::String
    candidates::Vector{@NamedTuple{engine::String, fit::Symbol, runs::Bool, rows::Union{Nothing, Int}, reason::String}}
    rule::String
    lower_bound::Union{Nothing, Int}
    proof::String
    sizes::@NamedTuple{fast::Union{Nothing, Int}, balanced::Union{Nothing, Int}, compact::Union{Nothing, Int}}
    notes::Vector{String}
    parameters::Vector{Symbol}
    values::Vector{Int}
    strength::Int
    stronger::Vector{Pair{Tuple{Vararg{Symbol}}, Int}}
    n_must_include::Int
    n_invalid::Int
    n_rules::Int
    targets::Int
end

"""
Use when you want to see which engine `Auto` would use for your space, and
why, before generating anything.

    recommend(space; strength = 2, stronger = [], must_include = [], goal = :balanced,
              feasibility_limit = 1_000_000, explanation_limit = 1_000_000) -> Recommendation
    recommend(domains::NamedTuple; constraints = [], kwargs...)
    recommend(name => domain, ...; constraints = [], kwargs...)
    recommend(domain, domain, ...; kwargs...)

What [`Auto`](@ref)`(; goal)` would run for this request, with one line of
reason for each start it considers, the number of cases each `goal` can give
where that is known without running, a lower bound on the cases of any
design, and notes (plan §6.1). It takes the inputs and keywords that
[`covering`](@ref) takes, builds the request, which checks them as
`covering` does, and generates nothing: no combination is classified and no
design is built, so it answers in about a millisecond. The limits bound the
search a partial must-include row's check makes.

```jldoctest; setup = :(using UnitTestDesign)
julia> recommend(fill(1:7, 8)...)
Recommendation: 8 parameters × 7 values, strength 2, no rules; 1372 combinations to cover
  skip  IPOG()          not run: no design has fewer rows than the catalog's array, which meets the lower bound
  use   Construction()  49 rows: Bush orthogonal array, every combination exactly once
lower bound: 49 cases: the 7 × 7 = 49 combinations of p1 and p2 need a case each
goals: :fast (IPOG alone) known only after running; :balanced 49 cases, the minimum; :compact 49 cases, the minimum
covering(…; engine = Auto()) would use Construction().

julia> recommend(fill(1:6, 15)...)
Recommendation: 15 parameters × 6 values, strength 2, no rules; 3780 combinations to cover
  run   IPOG()          covers any request
  run   Construction()  76 rows: Tripling (tripling from 5 columns)
rule: 3780 combinations to cover, at most 100000: both run, and the fewer rows are kept, IPOG's on a tie
lower bound: 36 cases: the 6 × 6 = 36 combinations of p1 and p2 need a case each
goals: :fast (IPOG alone) known only after running; :balanced at most 76 cases; :compact at most 76 cases
covering(…; engine = Auto()) would use the smaller of IPOG() and Construction().
```

The goals lean toward `:balanced` (decision D8): it returns no more cases
than `:fast`, which is IPOG alone, wherever it builds IPOG's design too or
the catalog's array meets the lower bound, and on a space whose parameters
share one number of values it is often a quarter smaller or more. Above
$(replace(_AUTO_SMALL_TEXT, r"(?<=\d)(?=(\d{3})+$)" => ",")) combinations
it may build the catalog's array alone, which on the package's benchmarks
was never larger than IPOG's design, though that is not guaranteed.
"""
function recommend(input...; strength = 2, stronger = [], must_include = nothing, goal = :balanced,
                   constraints = nothing, feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    strength = _check_integer(:strength, strength, 1, "§11.1")
    _check_limits(feasibility_limit, explanation_limit)
    engine = Auto(; goal)
    space, positional = _space(:recommend, input, constraints)
    request = Request(space; strength, stronger, feasibility_limit, explanation_limit,
                      must_include = _must_include_rows(must_include, space, positional))
    return _recommendation(engine, request)
end

"""
    _recommendation(engine::Auto, request) -> Recommendation

`recommend`'s answer for a request it built: `Auto`'s plan for the request's
`Profile` (`_auto_plan`), and `Auto()`'s for the sizes and the notes of
another goal, both from the candidates' plans prepared once
(`_auto_starts`); the bound `_request_bound` knows without classifying; the
sizes each goal can give; and the notes. A profile counts only the ordinary
must-include rows, so it is the profile of the ordinary request that
`generate` hands `Auto` (the negative must-include rows set apart), and the
plan is the one `Auto` makes.
"""
function _recommendation(engine::Auto, request::Request)
    p = Profile(request)
    starts = _auto_starts(p)
    plan = _auto_plan(engine, p, starts)
    balanced = engine.goal === :balanced ? plan : _auto_plan(Auto(), p, starts)
    candidates = [(engine = c.label, fit = c.plan.fit.kind, runs = c.runs, rows = c.plan.fit.rows, reason = c.reason)
                  for c in plan.candidates]
    bound, proof = _request_bound(request)
    # `:balanced` keeps the smaller of the starts it runs, so it has at most the
    # catalog's rows whenever it runs the catalog on an exact shape, and
    # `:compact` reduces that. IPOG's size is known only after running.
    catalog = last(balanced.candidates)   # in the fixed order: IPOG, then the catalog
    most = catalog.runs ? catalog.plan.fit.rows : nothing
    sizes = (fast = nothing, balanced = most, compact = most)
    space = request.space
    stronger = Pair{Tuple{Vararg{Symbol}}, Int}[Tuple(space.names[g]) => s for (g, s) in request.groups[2:end]]
    return Recommendation(engine.goal, _auto_label(plan, p), candidates, plan.why, bound, proof, sizes,
                          _recommend_notes(request, p, plan, balanced), copy(space.names), copy(p.arity),
                          p.strength, stronger, n_must_include(request), p.n_invalid, length(p.rules), p.targets)
end

"""
    _request_bound(request) -> (bound, proof)

The lower bound a covering result for `request` will record
(`_ordinary_bound`, `cover_negative`), when it is known without classifying:
for a request with no rules and no must-include rows, every combination is
required, so the ordinary bound is the largest product of `s` value counts
over each group at strength `s`, and each invalid value of a parameter adds
the largest product of `s - 1` value counts of the other parameters of a
group holding it, or 1. Otherwise `nothing`, with the reason.
"""
function _request_bound(request::Request)
    isconstrained(request) &&
        return nothing, "known after generating: the rules decide which combinations need a case"
    n_must_include(request) > 0 &&
        return nothing, "known after generating: it counts what the must-include rows hold"
    arity = request.arity
    best, members = 0, Int[]
    for (group, s) in request.groups
        s > 0 || continue
        top = sort(group; by = q -> (-arity[q], q))[1:s]   # the largest counts, the first of equal ones
        rows = prod(arity[top]; init = 1)
        rows > best && ((best, members) = (rows, sort!(top)))
    end
    negative = 0
    for q in eachindex(arity)
        invalid = length(request.candidates[q]) - arity[q]
        invalid > 0 || continue
        each = 1
        for (group, s) in request.groups
            q in group || continue
            others = sort([r for r in group if r != q]; by = r -> (-arity[r], r))
            each = max(each, prod(arity[others[1:(s - 1)]]; init = 1))
        end
        negative += invalid * each
    end
    support = isempty(members) ? 0 : 1
    b = _SupportBound(best, support, best, best, 0, 0, 0)
    record = _bound_record(best + negative, b, negative, request.space.names, arity, [members])
    return record.lower_bound, record.proof
end

"""
    _recommend_notes(request, profile, plan, balanced) -> Vector{String}

`recommend`'s notes: what about the space changes the choice or its cost.
Whole-case rules (STUDY.md, "Rules: writing the same condition differently
changes the problem"), the rules, must-include rows, `stronger` groups and
`Invalid` values as `Auto` treats them; for `goal = :fast`, how `:balanced`
(the plan `balanced`) compares (decision D8): never larger where it builds
IPOG's design too or the catalog's array meets the bound, else measured; and
for `:compact`, whether the reducer runs (`_unreduced`).
"""
function _recommend_notes(request::Request, p::Profile, plan::_AutoPlan, balanced::_AutoPlan)
    notes = String[]
    whole = count(r -> r.kind === :whole_case, p.rules)
    whole > 0 && push!(notes, "$(_plural(whole, "whole-case rule")): generation checks " *
                              "$(whole == 1 ? "it" : "them") only on complete rows; declare " *
                              "$(whole == 1 ? "its" : "their") scope if $(whole == 1 ? "it reads" : "they read") " *
                              "fewer fields")
    lazy = count(r -> r.kind === :lazy, p.rules)
    lazy > 0 && push!(notes, "$(_plural(lazy, "scoped rule")) over more combinations than `tabulation_limit` " *
                             "$(lazy == 1 ? "is" : "are") evaluated on demand, which makes generation slower")
    p.n_invalid > 0 && push!(notes, "$(_plural(p.n_invalid, "Invalid value")): the negative rows of each are " *
                                    "chosen the same way, on the other parameters")
    if plan.engine.goal === :fast
        ipog, catalog = balanced.candidates   # in the fixed order: IPOG, then the catalog
        push!(notes, ipog.runs || _at_bound(catalog.plan) ?
                     "goal = :fast is IPOG alone; goal = :balanced never gives more cases" :
                     "goal = :fast is IPOG alone; goal = :balanced builds only the catalog's array here, above " *
                     "$_AUTO_SMALL_TEXT combinations, which on the package's benchmarks was never larger than " *
                     "IPOG's design, though that is not guaranteed")
    elseif plan.engine.goal === :compact
        why = _unreduced(plan, p)
        push!(notes, why === nothing ?
                     "goal = :compact runs the row reducer once on the start it keeps, seeded with seed = 0" :
                     "goal = :compact leaves the start it keeps unreduced: $why")
    end
    return notes
end

# "8 parameters × 32 values" or "12 parameters of 2 to 4 values", then the strength and rules.
function _recommend_headline(r::Recommendation)
    k = length(r.parameters)
    shape = isempty(r.values) ? "no parameters" :
            allequal(r.values) ? "$(_plural(k, "parameter")) × $(_plural(first(r.values), "value"))" :
            "$(_plural(k, "parameter")) of $(minimum(r.values)) to $(maximum(r.values)) values"
    parts = [shape, "strength $(r.strength)" * join(", $s within ($(join(g, ", ")))" for (g, s) in r.stronger)]
    push!(parts, r.n_rules == 0 ? "no rules" : _plural(r.n_rules, "rule"))
    r.n_must_include > 0 && push!(parts, _plural(r.n_must_include, "must-include row"))
    r.n_invalid > 0 && push!(parts, _plural(r.n_invalid, "Invalid value"))
    return join(parts, ", ") * "; $(r.targets) combinations to cover"
end

# ":balanced 49 cases, the minimum", ":balanced at most 76 cases", ":balanced known only after running".
function _goal_size(r::Recommendation, goal::Symbol)
    rows = getfield(r.sizes, goal)
    label = goal === :fast ? ":fast (IPOG alone)" : repr(goal)
    rows === nothing && return "$label known only after running"
    rows == r.lower_bound && return "$label $(_plural(rows, "case")), the minimum"
    return "$label at most $(_plural(rows, "case"))"
end

Base.show(io::IO, r::Recommendation) =
    print(io, "Recommendation: ", r.engine, " for ", _plural(length(r.parameters), "parameter"))

function Base.show(io::IO, ::MIME"text/plain", r::Recommendation)
    print(io, "Recommendation: ", _recommend_headline(r))
    single = count(c -> c.runs, r.candidates) == 1
    width = maximum(c -> textwidth(c.engine), r.candidates)
    for c in r.candidates
        status = !c.runs ? "skip" : single ? "use" : "run"
        print(io, "\n  ", rpad(status, 5), " ", rpad(c.engine, width), "  ", c.reason)
    end
    single || print(io, "\nrule: ", r.rule)
    if r.lower_bound === nothing
        print(io, "\nlower bound: ", r.proof)
    else
        print(io, "\nlower bound: ", _plural(r.lower_bound, "case"), ": ", r.proof)
    end
    print(io, "\ngoals: ", join((_goal_size(r, g) for g in (:fast, :balanced, :compact)), "; "))
    for note in r.notes
        print(io, "\nnote: ", note)
    end
    call = r.goal === :balanced ? "Auto()" : "Auto(goal = $(repr(r.goal)))"
    print(io, "\ncovering(…; engine = $call) would use $(r.engine).")
    return nothing
end
