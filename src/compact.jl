# `Compact`, the row reducer (plan §5.3 of design/20261003_solver_plan.md; the
# "Reduce" stage of §4.1). A wrapper engine after TCA (Lin et al. 2015) and
# FastCA (Lin et al. 2019): it takes its inner engine's design as the start,
# deletes the row whose removal uncovers the fewest required combinations,
# repairs the design at that row count by entry moves and row replacements,
# and repeats while each repair succeeds, under a budget of steps and of work.
# It returns the last complete design. The coverage index (coverage_index.jl)
# keeps the counts.
#
# Every row is complete and valid at every step, so the reducer never asks
# the feasibility search anything. An entry move is taken only if the rules
# whose scope holds the changed parameter allow the changed row; a replaced
# row is copied from the start, which is valid. Rule checks on a complete row
# are `forbids` (feasibility.jl): a bit test for a tabulated rule, a memo
# lookup or the predicate for a lazy or whole-case one. None of them searches,
# so none can reach `feasibility_limit`, and the rows don't depend on it
# (contract §3.8).
#
# `_compact` is the core: it reduces any start design for a request. `Compact`
# applies it to its inner engine's rows, from the inner engine's plan, which
# its own plan holds (`_CompactPlan`); Phase 3's `Auto` applies it to the
# start that keep-the-smallest chose (§4.1 step 3).

"""
Use when each case is expensive to run and you want fewer of them: it removes
rows from another engine's design, with the same guarantee, in a fraction of
a second for most spaces.

    Compact(inner; seed = 0, effort = 1)

The row reducer of plan §5.3, wrapped around the covering engine `inner`,
such as [`IPOG`](@ref)`()` or [`Construction`](@ref)`()`. It covers a
request with `inner`, then removes rows from that design: delete the row
whose removal leaves the fewest required combinations uncovered, repair the
design at that row count, and repeat while each repair succeeds, stopping
at the lower bound the result records (`_compact`). The result never has
more rows than `inner`'s and keeps its must-include rows, first and
unchanged (contract §10.5). Every row it writes is checked against the rules
on its own, so it never searches and its rows don't depend on
`feasibility_limit` (§3.8). A smaller design covers fewer combinations of
higher strength by accident: see the manual's Engines page.
[`Auto`](@ref)`(goal = :compact)` runs it on the start `Auto` keeps: the
smaller of IPOG's design and the catalog's array where it builds both, else
the one it builds.

`seed`, an integer of at least 0, seeds a fresh generator for every call,
so the same `inner`, `seed` and `effort` give the same rows (§9.11), and the
result records the seed. `effort`, a positive integer, multiplies the
reducer's two budgets, which count work, never seconds: at `effort = 1`,
30,000 repair steps or one per combination it indexes (every combination
of each set of parameters that has targets, before the rules exclude any),
whichever is more, and 2·10⁹ combinations read, about 10 to 20 seconds on a
laptop, which strength 3 on larger spaces (30 parameters of 4 values) and
strengths 4 to 6 reach. A request with more than 2^25 combinations to
cover, counted before the rules, or whose start has more than 65,535 rows,
gets `inner`'s rows unreduced. The result's record says what the reducer
did, `cases.record.ordinary.reducer`: the rows before and after, the steps,
and why it stopped; and what `inner` did, `cases.record.ordinary.start`.

The negative rows of a space with [`Invalid`](@ref) values are reduced too,
for each invalid value as for any request (plan §4.1). Where the inner
engine refuses one of them, IPOG's rows for it are reduced.
"""
struct Compact{E <: CoveringEngine} <: CoveringEngine
    inner::E
    seed::Int
    effort::Int

    function Compact(inner::E; seed = 0, effort = 1) where {E <: CoveringEngine}
        return new{E}(inner, _check_integer(:seed, seed, 0, "§9.11"), _check_integer(:effort, effort, 1, "§9.11"))
    end
end

# As the caller writes it, the inner engine as its constructor call (`_engine_label`): "Compact(GND(seed = 2); …)".
Base.show(io::IO, e::Compact) =
    print(io, "Compact(", _engine_label(e.inner), "; seed = ", e.seed, ", effort = ", e.effort, ")")

"""
    _COMPACT_MAX_COMBINATIONS

The largest coverage index `Compact` builds, in combinations: the request's
targets before classification, over every support, which `Profile.targets`
counts without listing them. Past it, `Compact` returns its inner engine's
rows unreduced. It is 2^25 = 33,554,432: 64 MiB of counts and 8 MiB of bits
(`CoverageIndex`), which holds every strength-6 index on 20 parameters of
three values (28,256,040) and every CASA model's at strength 3 (at most
14,534,798). A count, never a measurement of memory or time, so the choice
depends only on the request (contract §9.1).
"""
const _COMPACT_MAX_COMBINATIONS = 1 << 25

"""
    _compact_budget(combinations, effort) -> Int

The step budget of one reduction: `effort` times 30,000 or the number of
combinations in the index, whichever is larger, saturating at `typemax(Int)`.
A step is one repair move (`_reduce!`). The spike's budget was 20,000 (plan
§5.3, probes 13–19); 30,000 is the least round number at which seed 0
reaches the bound on 92 of the 100 `mainstream` spaces at strength 2, as
the spike did, and it stays under the 50 ms each of the gate.
"""
_compact_budget(combinations::Int, effort::Int) = _saturating_mul(effort, max(30_000, combinations))

"""
    _COMPACT_WORK

The work budget of one reduction at `effort = 1`, in combinations read: each
time the reducer computes one row's combination on one support, to build the
index, to score, make or undo a move, or to choose the row to delete, counts
one, and so does each row it scans for a move. A step's cost grows with the
rows and with the supports that hold a parameter, C(k − 1, t − 1) for k
parameters at strength t, so where steps are expensive (strength 3 on larger
spaces, such as 30 parameters of 4 values; strengths 4 to 6; or thousands of
rows) this budget ends the search before the step budget does.
2·10⁹ reads take about 10 to 20 seconds on an Apple M2 (5–9 ns a read).
"""
const _COMPACT_WORK = 2_000_000_000

"""
    _compact(request, targets, start; seed = 0, effort = 1, budget = nothing,
             work_budget = nothing, check = false) -> (matrix, notes)

The row reducer's core (plan §5.3), for any start design. `start` is
parameters × rows in engine positions: complete rows, each valid under
`request`'s rules, the request's must-include rows first (completed where
they were partial), and together covering every required target of
`targets` (`RequiredTargets(request, required)`). The result has the same
form and at most as many rows: the start's must-include rows first and
unchanged, then rows that cover what they leave. It never calls the
feasibility search (`dead`, `witness`), so it can't throw
`ResourceLimitError`, and its rows don't depend on `feasibility_limit`.

The search draws from `Xoshiro(seed)` and runs at most
`_compact_budget(combinations, effort)` steps and `effort` times
`_COMPACT_WORK` combinations read, or `budget` steps and `work_budget` reads
when they are given. It returns `start` itself, unreduced, when the index
would hold more than `_COMPACT_MAX_COMBINATIONS` combinations, when `start`
has more than `typemax(UInt16)` rows, or when no row can go: every row is a
must-include row, or the design is at the bound.

`notes` records the run: `reducer_start` and `reducer_rows`, the rows before
and after; `reducer_bound`, the lower bound below which no design for the
request goes (`_ordinary_bound`, which counts the must-include rows, so the
same bound the result records for its ordinary rows); `reducer_steps` and
`reducer_budget`; `reducer_work` and `reducer_work_budget`, the combinations
read; and `reducer_stop`, why it stopped: `:frozen` (only must-include rows
are left), `:bound` (at the bound), `:budget` (the steps), `:work`, or
`:index_cap` or `:rows_cap` (not reduced).

`check = true` is a test mode: every changed row is checked against every
rule, and every complete design is recounted from its rows. `tenure` and
`random_mode` are TCA's two settings (`_reduce!`), for experiments.
"""
function _compact(request::Request, targets::RequiredTargets, start::Matrix{Int};
                  seed::Int = 0, effort::Int = 1, budget::Union{Nothing, Int} = nothing,
                  work_budget::Union{Nothing, Int} = nothing, check::Bool = false,
                  tenure::Int = _TABU_TENURE, random_mode::Float64 = _RANDOM_MODE)
    m = n_must_include(request)
    rows = size(start, 2)
    combinations = _index_size(targets)
    # The result's own lower bound, which counts the must-include rows, so that
    # the reducer stops where the result can be called minimal (plan §4.1).
    bound = _ordinary_bound(request, targets).rows
    steps_budget = something(budget, _compact_budget(combinations, effort))
    reads_budget = something(work_budget, _saturating_mul(effort, _COMPACT_WORK))
    notes(stop, steps, work, kept) = (reducer_start = rows, reducer_rows = kept, reducer_bound = bound,
                                      reducer_steps = steps, reducer_budget = steps_budget, reducer_work = work,
                                      reducer_work_budget = reads_budget, reducer_stop = stop)
    combinations > _COMPACT_MAX_COMBINATIONS && return start, notes(:index_cap, 0, 0, rows)
    rows > typemax(UInt16) && return start, notes(:rows_cap, 0, 0, rows)
    rows <= m && return start, notes(:frozen, 0, 0, rows)
    rows <= bound && return start, notes(:bound, 0, 0, rows)
    index = CoverageIndex(request, targets)
    design = [start[:, j] for j in axes(start, 2)]
    for row in design
        add_row!(index, row)
    end
    nuncovered(index) == 0 || error("internal error: the start design leaves $(nuncovered(index)) " *
                                    "required combinations uncovered")
    _forget_covered!(index)
    values = [_space_indices(request, row) for row in design]
    best = copy(start)
    kept, steps, work, stop = _reduce!(index, design, values, [copy(row) for row in design], best,
                                       request.feasibility, request.candidates, m, bound, steps_budget,
                                       reads_budget, rows * length(supports(targets)), Xoshiro(seed), check,
                                       tenure, random_mode)
    return best[:, 1:kept], notes(stop, steps, work, kept)
end

"""
    _index_size(targets) -> Int

The combinations a coverage index for `targets` would count, over every
support, saturating at `typemax(Int)`.
"""
function _index_size(targets::RequiredTargets)
    combinations = 0
    for s in eachindex(supports(targets))
        combinations = _saturating_add(combinations, ncombinations(targets, s))
    end
    return combinations
end

# TCA's tabu tenure (Lin et al. 2015, p.5) and the probability of its random
# mode, a row write in place of an entry move (p.4–5; Algorithm 5).
const _TABU_TENURE = 4
const _RANDOM_MODE = 0.001

"""
    _reduce!(index, rows, values, start, best, f, candidates, m, bound, budget, work_budget,
             work, rng, check, tenure, random_mode) -> (kept, steps, work, stop)

The reducer's loop (plan §5.3; TCA, Lin et al. 2015, Algorithm 5), behind
`_compact`'s function barrier. `rows` are the design's rows in engine
positions, all held by `index`, the first `m` of them must-include rows,
which never change; `values` are the same rows as space value indices, for
the rule checks; `start` is the starting design, rows to copy; `best` has a
column for every starting row and receives the last complete design, whose
row count is `kept`.

While the design is complete, it is saved, and the row whose removal leaves
the fewest required combinations uncovered (`singly_covered`; the first such
row) is deleted, until the row count reaches `bound`, only must-include rows
are left, or a budget is spent: `budget` steps, or `work_budget`
combinations read (`_COMPACT_WORK`), of which `work` were read before the
loop. While it is not, each step takes an uncovered required combination at
random and covers it with one move:

- an **entry move**, which changes the one entry of a row that differs from
  the combination, in a row that differs from it in exactly one entry. Among
  the moves whose row stays valid (`_allows`) and whose entry is not tabu, it
  takes one of those with the best `entry_score`, at random. An entry that a
  move changes at step `S` is tabu through step `S + tenure − 1`: `tenure`
  steps, counting its own, as probe 13's spike counted them. Deleting a row
  clears every tabu;
- a **row write**, when there is no such move, and with probability
  `random_mode` in any step (TCA's random mode): a random row other than a
  must-include row takes the combination's values at its members, as TCA
  changes several entries of a row when no entry move covers a combination
  (p.4) and probe 13's spike did, if the rules whose scope holds one of them
  allow the changed row (`_allows_write`); the entries written are tabu as
  an entry move's are. Otherwise, a **row replacement**: that row becomes a
  copy of a random starting row that holds the combination. The start covers
  every required combination, so one always exists (CASA's connecting move,
  Garvin et al. 2011, p.18), and a copy is valid.
"""
function _reduce!(index::CoverageIndex, rows::Vector{Vector{Int}}, values::Vector{Vector{Int}},
                  start::Vector{Vector{Int}}, best::Matrix{Int}, f::Feasibility,
                  candidates::Vector{Vector{Int}}, m::Int, bound::Int, budget::Int, work_budget::Int,
                  work::Int, rng::Xoshiro, check::Bool, tenure::Int, random_mode::Float64)
    n = length(index.arity)
    N = length(rows)
    S = length(index.supports)
    changed = zeros(Int, n, N)   # the step at which an entry move last changed each entry; 0 for none
    moves = Tuple{Int, Int, Int}[]   # (row, parameter, position) of the best moves found
    combination_values = zeros(Int, max_support(index))
    saved = zeros(Int, max_support(index))   # a row's entries while a write is checked
    steps = 0
    kept = N
    while true
        if nuncovered(index) == 0
            for j in 1:N
                copyto!(view(best, :, j), rows[j])
            end
            kept = N
            check && _check_counts(index, rows, N)
            _forget_covered!(index)
            N <= m && return kept, steps, work, :frozen
            N <= bound && return kept, steps, work, :bound
            steps >= budget && return kept, steps, work, :budget
            work >= work_budget && return kept, steps, work, :work
            # Delete the row whose removal uncovers the fewest required
            # combinations, the first of them. A row's count stops once it
            # reaches the fewest so far, and the scan stops at a row of none.
            drop, fewest = 0, typemax(Int)
            for j in (m + 1):N
                alone, read = _singly_covered(index, rows[j], fewest)
                work += read
                if alone < fewest
                    drop, fewest = j, alone
                    fewest == 0 && break
                end
            end
            work += S
            remove_row!(index, rows[drop])
            rows[drop], rows[N] = rows[N], rows[drop]
            values[drop], values[N] = values[N], values[drop]
            N -= 1
            fill!(changed, 0)
            continue
        end
        steps >= budget && return kept, steps, work, :budget
        work >= work_budget && return kept, steps, work, :work
        N > m || return kept, steps, work, :frozen
        steps += 1
        s = decode!(combination_values, index, random_uncovered(index, rng))
        span = members_of(index, s)
        empty!(moves)
        score = typemin(Int)
        if rand(rng) >= random_mode
            work += N - m
            for j in (m + 1):N
                row = rows[j]
                missed, at = 0, 0
                # A row has every parameter, `span` is a support's members, and
                # `combination_values` has room for the largest support.
                @inbounds for (k, i) in enumerate(span)
                    row[index.members[i]] == combination_values[k] && continue
                    missed += 1
                    missed > 1 && break
                    at = k
                end
                missed == 1 || continue
                p = index.members[span[at]]
                w = combination_values[at]
                changed[p, j] > 0 && steps - changed[p, j] < tenure && continue
                work += _holders(index, p)
                g = _entry_score(index, row, p, w)
                g < score && continue
                _allows(f, values[j], p, candidates[p][w]) || continue
                g > score && (score = g; empty!(moves))
                push!(moves, (j, p, w))
            end
        end
        if isempty(moves)
            j = rand(rng, (m + 1):N)
            if _allows_write(f, values[j], saved, index, span, combination_values, candidates)
                for (k, i) in enumerate(span)
                    p = index.members[i]
                    work += _holders(index, p)
                    move_entry!(index, rows[j], p, combination_values[k])
                    values[j][p] = candidates[p][combination_values[k]]
                    changed[p, j] = steps
                end
            else
                work += length(start) + 2 * S
                _replace_row!(index, rows[j], values[j], _holder(start, index, span, combination_values, rng),
                              candidates)
            end
            check && _check_row_valid(f, values[j], rows[j], candidates)
        else
            j, p, w = moves[rand(rng, eachindex(moves))]
            work += _holders(index, p)
            move_entry!(index, rows[j], p, w)
            values[j][p] = candidates[p][w]
            changed[p, j] = steps
            check && _check_row_valid(f, values[j], rows[j], candidates)
        end
    end
end

"""
    _allows(f, row, p, value) -> Bool

Whether the complete, valid `row` (space value indices) stays valid with
`value` at `p`: the rules whose scope holds `p` (`f.param_tables[p]`, which
includes every whole-case rule, whose scope is every parameter) don't forbid
it. The others read the same values as before. Each check is a `forbids`,
counted in `f.stats.evaluations` (contract §3.3); none searches.
"""
function _allows(f::Feasibility, row::Vector{Int}, p::Int, value::Int)
    old = row[p]
    row[p] = value
    allowed = true
    for k in f.param_tables[p]
        f.stats.evaluations += 1
        if forbids(f, k, row)
            allowed = false
            break
        end
    end
    row[p] = old
    return allowed
end

"""
    _allows_write(f, row, saved, index, span, combination_values, candidates) -> Bool

Whether the complete, valid `row` (space value indices) stays valid with the
combination's values written in at the members `span` of its support: the
rules whose scope holds one of them allow it (`_allows` for several entries;
a rule that holds two is checked twice). `saved` holds the old values while
the row is changed.
"""
function _allows_write(f::Feasibility, row::Vector{Int}, saved::Vector{Int}, index::CoverageIndex,
                       span::UnitRange{Int}, combination_values::Vector{Int}, candidates::Vector{Vector{Int}})
    for (k, i) in enumerate(span)
        p = index.members[i]
        saved[k] = row[p]
        row[p] = candidates[p][combination_values[k]]
    end
    allowed = true
    for i in span
        for k in f.param_tables[index.members[i]]
            f.stats.evaluations += 1
            if forbids(f, k, row)
                allowed = false
                break
            end
        end
        allowed || break
    end
    for (k, i) in enumerate(span)
        row[index.members[i]] = saved[k]
    end
    return allowed
end

"A random starting row that holds the combination `combination_values` on the members `span`."
function _holder(start::Vector{Vector{Int}}, index::CoverageIndex, span::UnitRange{Int},
                 combination_values::Vector{Int}, rng::Xoshiro)
    holds(row) = all(k -> row[index.members[span[k]]] == combination_values[k], eachindex(span))
    n = count(holds, start)
    n > 0 || error("internal error: no starting row holds an uncovered required combination")
    k = rand(rng, 1:n)
    for row in start
        holds(row) && (k -= 1) == 0 && return row
    end
    error("internal error: unreachable")
end

"Make `row` (and its value indices `values`) a copy of the valid starting row `source`, updating the index."
function _replace_row!(index::CoverageIndex, row::Vector{Int}, values::Vector{Int}, source::Vector{Int},
                       candidates::Vector{Vector{Int}})
    remove_row!(index, row)
    copyto!(row, source)
    add_row!(index, row)
    for p in eachindex(row)
        values[p] = candidates[p][row[p]]
    end
    return row
end

# Test mode (`check = true`): a changed row breaks no rule, and its value
# indices are its positions'.
function _check_row_valid(f::Feasibility, values::Vector{Int}, row::Vector{Int}, candidates::Vector{Vector{Int}})
    all(p -> values[p] == candidates[p][row[p]], eachindex(row)) ||
        error("internal error: the reducer's value indices of row $row are out of date")
    _violates(f, values) && error("internal error: the reducer made the invalid row $row")
    return nothing
end

# Test mode: the index's counts are the first `N` rows' counts, recounted.
function _check_counts(index::CoverageIndex, rows::Vector{Vector{Int}}, N::Int)
    expected = zeros(Int, ncombinations(index))
    for j in 1:N, s in eachindex(index.supports)
        expected[combination(index, s, rows[j])] += 1
    end
    expected == index.count || error("internal error: the coverage index's counts are not its rows'")
    nrows(index) == N || error("internal error: the coverage index holds $(nrows(index)) rows, not $N")
    nuncovered(index) == count(id -> expected[id] == 0 && index.required[id], eachindex(expected)) ||
        error("internal error: the coverage index miscounts its uncovered combinations")
    return nothing
end

"""
    _CompactPlan

`Compact`'s plan for a request (`_prepare`): `engine`; `fit`, the inner
engine's, reduced (`fit(::Compact, …)`); and `inner`, the inner engine's
plan, which execution runs for the start.
"""
struct _CompactPlan{E <: CoveringEngine, P <: _Plan} <: _Plan
    engine::Compact{E}
    fit::Fit
    inner::P
end

"""
    _prepare(engine::Compact, profile) -> _CompactPlan

The inner engine's plan, and its fit, reduced: `:native` where the inner
engine covers the request and the index fits (`_COMPACT_MAX_COMBINATIONS`);
the inner engine's own fit where the index would be larger, since `Compact`
then returns its rows unreduced; and `:unsupported` where the inner engine
is.
"""
function _prepare(engine::Compact, profile::Profile)
    inner = _prepare(engine.inner, profile)
    f = inner.fit
    reduced = f.kind === :unsupported ? f :
              profile.targets > _COMPACT_MAX_COMBINATIONS ?
              Fit(f.kind, "$(f.reason), unreduced: the coverage index would hold $(profile.targets) combinations, " *
                          "above Compact's $(_COMPACT_MAX_COMBINATIONS)"; rows = f.rows) :
              Fit(:native, "$(f.reason), then reduced")
    return _CompactPlan(engine, reduced, inner)
end

fit(engine::Compact, profile::Profile) = _prepare(engine, profile).fit

"""
    cover_ordinary(engine::Compact, request::Request, targets::RequiredTargets) -> Matrix{Int}

The inner engine's rows for `request`, reduced by `_compact` (plan §5.3).
"""
cover_ordinary(engine::Compact, request::Request, targets::RequiredTargets) = _cover(engine, request, targets)

"""
    _execute(plan::_CompactPlan, request, targets) -> (matrix, (start = …, reducer = …))

The inner plan's rows (`_run`), reduced by `_compact` with the engine's seed
and effort. The notes are the inner engine's stage, `start`, and the
reducer's run, `reducer` (`_reducer_record`).
"""
function _execute(plan::_CompactPlan, request::Request, targets::RequiredTargets)
    start, stage = _run(plan.inner, request, targets)
    matrix, notes = _compact(request, targets, start; seed = plan.engine.seed, effort = plan.engine.effort)
    return matrix, (start = stage, reducer = _reducer_record(notes))
end

"""
    _reducer_record(notes) -> NamedTuple

`_compact`'s notes as a result's record keeps them, under `reducer`: `start`
and `rows`, the rows before and after; `bound`, `steps`, `budget`, `work`,
`work_budget` and `stop` (`_compact`). The benchmark harness writes them as
`reducer_start`, `reducer_rows`, … (benchmark/scaling/metrics.jl).
"""
_reducer_record(n::NamedTuple) =
    (start = n.reducer_start, rows = n.reducer_rows, bound = n.reducer_bound, steps = n.reducer_steps,
     budget = n.reducer_budget, work = n.reducer_work, work_budget = n.reducer_work_budget, stop = n.reducer_stop)

"The record: randomized, Compact's seed, and its inner engine's record and its effort as settings (plan §4.2)."
engine_record(engine::Compact) = EngineRecord(:Compact, engine.seed,
    Pair{Symbol, Any}[:inner => engine_record(engine.inner), :effort => engine.effort]; randomized = true)

# A result keeps only the engine's name and seed, so the phrase names what
# else must match to repeat the rows.
_repeat_call(::Val{:Compact}, seed) = "Compact(inner; seed = $seed) with the same inner engine and effort"

# What the inner engine refuses goes to its fallback, reduced the same way.
_fallback(engine::Compact) = Compact(_fallback(engine.inner); seed = engine.seed, effort = engine.effort)
