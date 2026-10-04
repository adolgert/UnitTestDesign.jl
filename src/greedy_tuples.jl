# GND, the greedy non-deterministic engine (plan Phase 3 step 3).
#
# Each round draws `candidates` candidate rows and keeps the one that covers
# the most uncovered required targets. A candidate is built one parameter at
# a time: the first parameter is the one with the most uncovered targets, the
# rest follow in a random order, and each takes the value that matches the
# most uncovered targets among the values that keep the row completable
# (`dead(request, row)` is false). By induction every candidate is a
# complete valid row: the empty row is completable (the space has a valid
# row whenever a target is required), and a completable partial row always
# has at least one value that keeps it completable.
#
# Progress guarantee. If the best candidate of a round covers nothing new,
# the round builds its row from the first uncovered target instead: the
# target is feasible (it is required), so it is a completable partial row,
# and the same fill completes it into a valid row that covers it. Every round
# therefore covers at least one target, and the loop ends after at most as
# many rounds as there are required targets. There is no attempt cap and no
# "could not construct" error. A feasibility search that reaches its limit
# throws `ResourceLimitError` from `dead`; no target is ever dropped
# (contract §3.6).

using Random

"""
    argmin_rand(rng, v)

Given a vector, find the index of the smallest value. If more than
one value is the smallest, then randomly choose among the smallest
values.
"""
function argmin_rand(rng, v)
    small = typemax(v[1])
    small_extra_cnt = 0
    small_idx = -1
    for i in eachindex(v)
        if v[i] < small
            small = v[i]
            small_extra_cnt = 0
            small_idx = i
        elseif v[i] == small
            small_extra_cnt += 1
        # else not the smallest.
        end
    end
    if small_extra_cnt == 0
        return small_idx
    else
        which = rand(rng, 1:(small_extra_cnt + 1))
        which_cnt = 1
        for s_idx in small_idx:length(v)
            if v[s_idx] == small
                if which_cnt == which
                    return s_idx
                end
                which_cnt += 1
            end
        end
    end
    return 0
end


"""
    allowed_argmax(rng, entry, param_idx, scores, isdead)

Choose the highest-scoring value for `param_idx`, breaking ties at random,
among the values that keep `entry` completable: `isdead(entry)` is false
with the value set. `isdead === nothing` means every value is allowed (an
unconstrained parameter). `entry` must be completable on entry, so some
value is allowed; finding none is an internal error. `entry[param_idx]` is
left unset (`0`).
"""
function allowed_argmax(rng, entry, param_idx, scores, isdead)
    masked = -scores
    if isdead !== nothing
        blocked = typemax(eltype(masked))
        for value in eachindex(scores)
            entry[param_idx] = value
            if isdead(entry)
                masked[value] = blocked
            end
        end
        entry[param_idx] = 0
        any(<(blocked), masked) || error(
            "internal error: no value of parameter $param_idx keeps the row $entry completable")
    end
    return argmin_rand(rng, masked)
end


"""
    _Greedy

The state one GND call shares: the coverage matrix of uncovered required
targets, the `dead` predicate (`nothing` when unconstrained), and which
parameters need it (those in some rule's scope; a parameter no rule reads
cannot make a completable row dead).
"""
struct _Greedy{F}
    mc::MatrixCoverage{Int}
    isdead::F
    checked::Vector{Bool}
end

function _Greedy(request::Request, required)
    n = length(request.arity)
    allc = isempty(required) ? zeros(Int, n, 0) : reduce(hcat, required)
    mc = MatrixCoverage(allc, size(allc, 2), copy(request.arity))
    if isconstrained(request)
        checked = [!isempty(request.feasibility.param_tables[i]) for i in 1:n]
        return _Greedy(mc, partial -> dead(request, partial), checked)
    else
        return _Greedy(mc, nothing, fill(false, n))
    end
end

_check(g::_Greedy, p) = g.checked[p] ? g.isdead : nothing

"Assign each unset parameter of `entry`, in `order`, its best allowed value."
function _fill!(rng, g::_Greedy, entry, order)
    for p in order
        entry[p] == 0 || continue
        scores = most_matches_existing(g.mc, entry, p)
        entry[p] = allowed_argmax(rng, entry, p, scores, _check(g, p))
    end
    return entry
end

"One candidate row: `order[1]` by its most common uncovered value, the rest greedily."
function _candidate!(rng, g::_Greedy, entry, order)
    fill!(entry, 0)
    first = order[1]
    entry[first] = allowed_argmax(rng, entry, first, coverage_by_value(g.mc, first), _check(g, first))
    return _fill!(rng, g, entry, @view order[2:end])
end

"Complete a partial row in place, greedily, with its unset parameters in random order."
function _complete!(rng, g::_Greedy, entry)
    order = shuffle!(rng, findall(==(0), entry))
    return _fill!(rng, g, entry, order)
end

"""
    _greedy_rounds!(rows, rng, g, candidates) -> Int

Add rows until every target in `g.mc` is covered. Returns the number of
rounds whose row came from the progress guarantee (the first uncovered
target, completed) because no candidate covered anything.
"""
function _greedy_rounds!(rows, rng, g::_Greedy, candidates::Int)
    mc = g.mc
    n = length(mc.arity)
    trials = zeros(Int, n, candidates)
    scores = zeros(Int, candidates)
    order = collect(1:n)
    entry = zeros(Int, n)
    progress = 0
    while remaining_uncovered(mc) > 0
        order .= 1:n
        first = argmin_rand(rng, -coverage_by_parameter(mc))
        order[1], order[first] = first, 1
        for trial in 1:candidates
            shuffle!(rng, @view order[2:end])
            _candidate!(rng, g, entry, order)
            scores[trial] = match_score(mc, entry)
            trials[:, trial] .= entry
        end
        best = argmin_rand(rng, -scores)
        if scores[best] > 0
            row = trials[:, best]
        else
            row = _complete!(rng, g, mc.allc[:, 1])
            progress += 1
        end
        before = remaining_uncovered(mc)
        add_coverage!(mc, row)
        remaining_uncovered(mc) < before || error(
            "internal error: GND row $row covers no required target")
        push!(rows, row)
    end
    return progress
end


"""
    gnd_cover(engine::GND, request, required) -> (matrix, progress)

The GND design for `required` targets (engine positions), must-include rows
first, and the number of rows built by the progress guarantee. Partial
must-include rows are completed greedily, in place, keeping their assigned
values (contract §7.10, §10.5). At strength equal to the parameter count
every required target is a complete row, so the rows are the required
targets the must-include rows leave uncovered, in target order (§7.8).
"""
function gnd_cover(engine::GND, request::Request, required)
    rng = engine_rng(engine)
    n = length(request.arity)
    g = _Greedy(request, required)
    rows = Vector{Int}[]
    for s in axes(request.must_include, 2)
        row = request.must_include[:, s]
        any(==(0), row) && _complete!(rng, g, row)
        push!(rows, row)
        add_coverage!(g.mc, row)
    end
    progress = 0
    if request.strength == n
        seen = Set(rows)
        for t in required
            t in seen || push!(rows, copy(t))
        end
    else
        progress = _greedy_rounds!(rows, rng, g, engine.candidates)
    end
    matrix = isempty(rows) ? zeros(Int, n, 0) : reduce(hcat, rows)
    return matrix, progress
end


"""
    cover_ordinary(engine::GND, request::Request, targets::RequiredTargets) -> Matrix{Int}

GND's rows for `request` (contract §1.3): the must-include rows first and
unchanged (§10.5), then rows until every required target (`targets`, whose
list of classified required targets in engine positions GND reads) is
covered (`gnd_cover`). `generate` classifies the targets, calls this, and
validates the result (§1.21). The request's must-include rows are ordinary.
"""
cover_ordinary(engine::GND, request::Request, targets::RequiredTargets) =
    first(gnd_cover(engine, request, _target_list(targets)))

"The record: randomized; the seed is `engine.seed`, or `nothing` when the engine was given an `rng` (§9.5, §9.6)."
engine_record(engine::GND) = EngineRecord(:GND, engine.seed, Pair{Symbol, Any}[:candidates => engine.candidates];
                                          randomized = true)

fit(::GND, ::Profile) = Fit(:native, "GND covers any request")

# A result keeps the engine's name and seed, not its settings, so a GND that
# draws other than the default 50 candidates a row records how many: repeating
# its cases needs them (`_repeat_call`). The default records nothing.
function _cover_with_notes(engine::GND, request::Request, targets::RequiredTargets)
    rows = cover_ordinary(engine, request, targets)
    return rows, engine.candidates == 50 ? (;) : (gnd = (candidates = engine.candidates,),)
end

_repeat_call(::Val{:GND}, seed, notes::NamedTuple) =
    haskey(notes, :gnd) ? "GND(seed = $seed, candidates = $(notes.gnd.candidates))" : "GND(seed = $seed)"
