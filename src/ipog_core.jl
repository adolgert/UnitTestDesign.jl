# IPOG, the engine behind `IPOG()`: in-parameter-order generation that scores
# by lookup (plan §5.5, Phase 4; Kleine & Simos 2018, "FIPOG"). One algorithm
# for every request: unconstrained and constrained, one strength or several
# (`stronger` groups, a negative sub-request at base strength 0), with and
# without must-include rows, complete and partial. It replaced IPOG's two
# paths, the classic `ipog` and the general `ipog_multi_way` (decision D2).
# `Construction`'s seeded path calls its operations (`_lookup_steps`,
# `_lookup_complete`, `_lookup_cover`), and `_IPOGLookup`, an internal engine
# outside the registry, runs any of its members, for benchmark studies.
#
# Parameters are added in `ipog_order`. A support (a set of parameters that
# carries targets, `supports(targets)`) belongs to the step of its parameter
# that comes last in the order (`_lookup_steps`). At step p the run keeps a
# map of the step's supports only (CAgen drops finished columns): one entry
# per combination, `true` while it is required and uncovered, laid out as
# FIPOG lays out its coverage map (PDF p.5, p.8, p.10). A support's
# combinations are a block; within it the code is lexicographic in the
# support's other parameters, in support order, with p as the least
# significant digit, so the candidate values of p for one row on one support
# are adjacent entries, `base + 1 … base + arity[p]`. The required
# combinations come through the targets interface (`supports`, `nrequired`,
# `isrequired`; plan §4.2), whose layout code (`_code`) has a support's first
# parameter least significant; the map is built from it once per step, never
# per lookup (`_mark_required!`).
#
# - Horizontal growth (`_horizontal!`): each row without a value for p
#   scores every value by lookups over the step's supports (FIPOG's
#   Algorithm 5, with its skip of supports already covered, §5.2) and takes
#   the best, ties broken by the engine's rule (`_tiekey`). A support on
#   which the row has an unset entry scores nothing (Forbes et al. 2008,
#   p.291: the potential of don't-care entries is ignored here, and vertical
#   growth fills them). A row that no value improves keeps p unset.
# - Vertical growth (`_vertical!`): each combination still uncovered goes to
#   the first row, in row order, that agrees with it and stays completable,
#   or else starts a new row. Rows are partitioned by p's value (FIPOG §5.3,
#   PDF pp.8–9, measured on p.12), rows without one being candidates for
#   every value, and only rows with an unset entry among the parameters
#   added so far are candidates (FIPOG §4.3). The combinations are taken
#   support by support (FIPOG's order) or value by value (about the old
#   classic order), and before a support's combinations are placed, the rows
#   changed so far mark what they now cover on it (Forbes et al., p.291: "it
#   is important to capture the unintended coverage"), so no combination is
#   placed twice.
# - The final fill (`_fill!`) gives every unset entry its parameter's least
#   used value that keeps the row completable, as the old general path did.
# - Two rules, a tie-break and a vertical order, choose a member of the IPOG
#   family (plan §2.5). `IPOG()` runs several (`_IPOG_MEMBERS`) on the same
#   steps and keeps the fewest rows, stopping at a member whose rows no
#   design can go below (`_execute`).
#
# The completability invariant (contract §1.3): a value is committed only when
# the row stays completable, `dead(row)` false. Must-include rows are
# completable when the request accepts them (§10.4), and every required target
# is completable (§1.2), so every row starts completable; each of the three
# placement sites keeps it so (horizontal growth, vertical growth, the final
# fill); by induction every row is completable after every step, and the fill
# ends each at a complete completable row, which is a valid row. `dead`
# answers `true` or `false` or throws `ResourceLimitError`, which propagates
# (§3.6, §3.8); the core decides only from its answers. An unconstrained
# request passes `Returns(false)`, which the core never calls with a row; that
# is the only place where the rules' absence shows, so with `dead` always
# false a constrained request gives the rows of the unconstrained one.
#
# Deterministic (contract §9.3, §9.4): no randomness, no hashing order; every
# loop runs in row, support, code or value order.

## IPOG()

"""
The members of the IPOG family that `IPOG()` runs (plan §2.5, §5.5): each
tie-break rule of `tiebreak` with each vertical order of `vertical`
(`_IPOGLookup`), tie-break rules first, on the same steps, keeping the design
with the fewest rows, the first of equals.

A provisional trade-off of rows against time and memory, open for the
maintainer (p4-switch's notes, judgment call 1). In the Phase 4 study of
1,826 benchmark grid points no single member has no more rows than the old
paths at 90% of the points; these four do at 96.7%, with 2.0% fewer rows in
total and 10 points more than 3% above. By rows alone the study's decision
rule picks eight members (four tie-breaks by both orders: 97.9%, 4 points
above 3%). But each member asks the feasibility search, so on constrained
models more members cost more: in single first calls under load, eight were
slower than the old paths at 179 of 912 judged points, these four at 72 of
871, two tie-breaks at 3 of 866 (91.3%, 54 points above 3%); and four
members make 3.5 to 4 times the old paths' `dead` calls and double one
strength-3 model's peak memory. Changing the set changes `IPOG()`'s rows: the
tests that pin them say how to regenerate their values.
"""
const _IPOG_MEMBERS = (tiebreak = (:lowest, :rotate), vertical = (:support, :value))

engine_record(::IPOG) = EngineRecord(:IPOG, nothing)

# The core takes any request, a negative sub-request at base strength 0 included.
fit(::IPOG, ::Profile) = Fit(:native, "IPOG covers any request")

"The members `IPOG()` runs, in order (`_IPOG_MEMBERS`, `_members`)."
_ipog_members() = _members(_IPOG_MEMBERS.tiebreak, _IPOG_MEMBERS.vertical)

_prepare(engine::IPOG, p::Profile) = _ipog_plan(engine, p, _ipog_members())

"""
    cover_ordinary(::IPOG, request::Request, targets::RequiredTargets) -> Matrix{Int}

IPOG's rows for `request` (contract §1.3), its plan's (`_IPOGPlan`,
`_execute`): the must-include rows first, then rows until every required
target (`targets`) is in some row, each row valid under the request's rules.
`generate` classifies the targets, prepares the plan, executes it and
validates the result (§1.21). No required target and no must-include row
gives no rows (§1.24); strength equal to the parameter count gives every
valid row (`full_strength_rows`, §7.8); anything else is the lookup core's
design for each member of `_IPOG_MEMBERS`, the one with the fewest rows kept,
with `dead(request, row)` deciding each placement when the request has
rules. IPOG uses no randomness (§9.4).
"""
cover_ordinary(engine::IPOG, request::Request, targets::RequiredTargets) = _cover(engine, request, targets)

"""
    ipog_order(arity, groups) -> Vector{Int}

The order in which IPOG adds parameters: members of stronger groups first
(highest strength first), then larger domains first, then parameter index.
With one group this is the classic IPOG order, `sortperm(arity, rev = true)`.
"""
function ipog_order(arity::AbstractVector{<:Integer}, groups)
    n = length(arity)
    top = zeros(Int, n)
    for (members, s) in groups, i in members
        top[i] = max(top[i], s)
    end
    return sortperm(collect(1:n); by = i -> (-top[i], -arity[i], i))
end

"""
    full_strength_rows(request, required) -> Matrix{Int}

Strength equal to the parameter count: every required target is a complete
valid row, so the design is the must-include rows (partial ones completed)
followed by every valid row they do not already hold, in lexicographic order.
Without must-include rows this is the set `full_factorial` returns (contract
§7.8, §11.2).
"""
function full_strength_rows(request::Request, required)
    n = length(request.arity)
    rows = Vector{Int}[]
    for j in axes(request.must_include, 2)
        row = request.must_include[:, j]
        push!(rows, any(==(0), row) ? witness(request, row) : row)
    end
    held = Set(rows)
    for t in sort(required)
        t in held || push!(rows, t)
    end
    return isempty(rows) ? zeros(Int, n, 0) : stack(rows)
end


## The lookup core as an engine

"The tie-break rules of `_IPOGLookup` (`_tiekey`) and its orders of vertical growth (`_vertical!`)."
const _TIEBREAKS = (:lowest, :highest, :rotate, :leastused, :mostleft)
const _VERTICALS = (:support, :value)

"""
    _IPOGLookup(; tiebreak = :lowest, vertical = :support)

IPOG's core that scores by lookup (plan §5.5, Phase 4) with the members
given, as an internal engine for studies of the members (benchmark/
ipog_compare.jl names it). `IPOG()` is the same core with the members
`_IPOG_MEMBERS`; this engine runs the ones it is given, so it is not in the
registry, whose oracle loops check `IPOG()`, and test/test_ipog_core.jl checks
each member. It covers any request, deterministically. Its rows are one
member of the IPOG family (plan §2.5), chosen by two rules.

`tiebreak` chooses among the values of equal score in horizontal growth
(probe 08):

- `:lowest`, the lowest value, as IPOG's old paths chose;
- `:highest`, the highest;
- `:rotate`, the first at or after a start that moves with the row (row `r`
  starts at value `mod1(r, arity)`);
- `:leastused`, the value this step has given to the fewest rows so far;
- `:mostleft`, the value that the most uncovered combinations of the step
  still hold, so that fewer are left for vertical growth (a density rule,
  after the deterministic density algorithm IPOG is compared with in Forbes
  et al. 2008, p.294).

Ties between values the rule ranks equal go to the lowest.

`vertical` is the order in which vertical growth places what horizontal
growth left uncovered:

- `:support`, support by support, each support's combinations in the map's
  order, as FIPOG and Forbes et al. place them;
- `:value`, by the value of the parameter being added, the highest first,
  then support by support and combination by combination, the last first:
  about the order the old classic path placed them in.

Either may be a tuple of rules: the engine then runs every combination, a
tie-break rule with a vertical order, tie-break rules first, and keeps the
design with the fewest rows, the first of equals (plan §4.1's "keep the
smallest"). The stage's notes say which member made the rows (`member`).
"""
struct _IPOGLookup <: CoveringEngine
    tiebreak::Tuple{Vararg{Symbol}}
    vertical::Tuple{Vararg{Symbol}}

    function _IPOGLookup(; tiebreak = :lowest, vertical = :support)
        return new(_rules(:tiebreak, tiebreak, _TIEBREAKS), _rules(:vertical, vertical, _VERTICALS))
    end
end

"A rule, or a tuple of distinct rules, from `allowed`, as a tuple; anything else is an `ArgumentError` naming `name`."
function _rules(name::Symbol, x, allowed::Tuple)
    xs = x isa Symbol ? (x,) : x
    xs isa Tuple && !isempty(xs) && all(y -> y isa Symbol && y in allowed, xs) && allunique(xs) ||
        throw(ArgumentError("$name is one of $(join(repr.(allowed), ", ", " or ")), or a tuple of them; " *
                            "got $(repr(x))"))
    return xs
end

# A rule as the caller writes it: `:lowest`, or `(:lowest, :rotate)`.
_rules_text(xs::Tuple) = length(xs) == 1 ? repr(only(xs)) : "(" * join(repr.(xs), ", ") * ")"
_rules_value(xs::Tuple) = length(xs) == 1 ? only(xs) : xs

# A call that makes the same engine in any module that loads the package (the
# name is internal): "UnitTestDesign._IPOGLookup(tiebreak = :lowest, vertical = :support)".
Base.show(io::IO, e::_IPOGLookup) = print(io, "UnitTestDesign._IPOGLookup(tiebreak = ", _rules_text(e.tiebreak),
                                          ", vertical = ", _rules_text(e.vertical), ")")

engine_record(e::_IPOGLookup) = EngineRecord(:IPOGLookup, nothing,
    Pair{Symbol, Any}[:tiebreak => _rules_value(e.tiebreak), :vertical => _rules_value(e.vertical)])

fit(::_IPOGLookup, ::Profile) = Fit(:native, "IPOG by lookup covers any request")

# It covers any request, a negative sub-request at base strength 0 included.
_fallback(e::_IPOGLookup) = e

"""
    _IPOGPlan

The lookup core's plan for a request (`_prepare`, plan §4.2), from its
`Profile` alone: `engine`; `fit`; `path`, `:full_strength` when the strength
is the number of parameters (every valid row, `full_strength_rows`, §7.8),
otherwise `:lookup`; `order`, the order in which parameters are added
(`ipog_order`); `rules`, whether the request has rules, so that `dead` is
asked; and `members`, each `(tiebreak, vertical)` the engine runs, tie-break
rules first (`_IPOGLookup`). The engine is a type parameter, so that one plan
serves `_IPOGLookup` and `IPOG()` (`_ipog_plan`).
"""
struct _IPOGPlan{E <: CoveringEngine} <: _Plan
    engine::E
    fit::Fit
    path::Symbol
    order::Vector{Int}
    rules::Bool
    members::Vector{Tuple{Symbol, Symbol}}
end

"Each tie-break rule of `tiebreak` with each vertical order of `vertical`, tie-break rules first: the members a plan runs."
_members(tiebreak::Tuple{Vararg{Symbol}}, vertical::Tuple{Vararg{Symbol}}) =
    Tuple{Symbol, Symbol}[(t, v) for t in tiebreak for v in vertical]

"The plan of `engine` for a request with profile `p` that runs `members` (`_IPOGPlan`)."
function _ipog_plan(engine::CoveringEngine, p::Profile, members::Vector{Tuple{Symbol, Symbol}})
    path = p.strength == nparameters(p) ? :full_strength : :lookup
    return _IPOGPlan(engine, fit(engine, p), path, ipog_order(p.arity, p.groups), !isempty(p.rules), members)
end

_prepare(engine::_IPOGLookup, p::Profile) = _ipog_plan(engine, p, _members(engine.tiebreak, engine.vertical))

"The member a full-strength design records, where no member runs (`_execute`)."
const _NO_MEMBER = (tiebreak = :none, vertical = :none)

"""
    _execute(plan::_IPOGPlan, request, targets) -> (matrix, (member = (; tiebreak, vertical),))

The lookup core's rows (`CoveringEngine`): the must-include rows first, in
order, unchanged where set (contract §10.5, §7.10), then rows until every
required target is covered, each valid under the request's rules. At full
strength, every valid row (`full_strength_rows`), which no member changes, so
the notes' `member` is `(tiebreak = :none, vertical = :none)`; otherwise
`_lookup_cover`, which with no required target and no must-include row gives
no rows (§1.24), for each member of the plan on the same steps, keeping the
fewest rows, the first of equals (`_fewest_rows`), and the notes' `member` is
the one kept. A member whose rows meet `_rows_floor` ends the loop: no later
member can have fewer, so the rows and the member are those of running every
member. The notes have one type for every plan, so that `_run`'s stage
infers concretely.
"""
function _execute(plan::_IPOGPlan, request::Request, targets::RequiredTargets)
    plan.path === :full_strength &&
        return (full_strength_rows(request, _target_list(targets)), (member = _NO_MEMBER,))
    steps = _lookup_steps(targets, request.arity, plan.order)
    isdead = plan.rules ? (row -> dead(request, row)) : Returns(false)
    rows, kept = _fewest_rows(plan.members, _rows_floor(request, targets)) do tiebreak, vertical
        _lookup_cover(steps, targets, isdead, request.must_include; tiebreak, vertical)
    end
    tiebreak, vertical = plan.members[kept]
    return (rows, (member = (; tiebreak, vertical),))
end

"""
    _fewest_rows(f, members, floor = 0) -> (rows, k)

`f(tiebreak, vertical)` for each member of `members` in order, and of its
results the one with the fewest rows, the first of equals, with the index of
the member that made it: plan §4.1's "keep the smallest", decided from the
rows alone, so deterministic. `floor` is a number of rows that no result has
fewer of; once the result kept has that many, the members after it are not
run, since none of them could replace it.
"""
function _fewest_rows(f, members::Vector{Tuple{Symbol, Symbol}}, floor::Int = 0)
    isempty(members) && error("internal error: an IPOG plan with no member")
    best, kept = f(members[1]...)::Matrix{Int}, 1
    for k in 2:length(members)
        size(best, 2) <= floor && break
        rows = f(members[k]...)::Matrix{Int}
        size(rows, 2) < size(best, 2) && ((best, kept) = (rows, k))
    end
    return best, kept
end

"""
    _rows_floor(request, targets) -> Int

A number of rows that no covering design for `request` has fewer of, from
counts alone: its must-include rows, which are rows of every design (contract
§10.5), or the most required combinations on one support, since a row holds
one combination of each support, whichever is more. Without must-include
rows it is the lower bound the result records (`_ordinary_bound`); with them
that bound can be larger, as it also reads which combinations the
must-include rows hold, which this leaves to the pipeline.
"""
function _rows_floor(request::Request, targets::RequiredTargets)
    floor = size(request.must_include, 2)
    for s in eachindex(supports(targets))
        floor = max(floor, nrequired(targets, s))
    end
    return floor
end

cover_ordinary(engine::_IPOGLookup, request::Request, targets::RequiredTargets) = _cover(engine, request, targets)


## The targets by step

"""
    _LookupSteps

The targets by step, shared by every run on one request (`_lookup_steps`):
`order`, the parameters in the order they are added; `arity`; and, for each
parameter `p`, the positions in `supports(targets)` of the supports whose
parameter last in `order` is `p`, `supports[first[p]:(first[p + 1] - 1)]`,
ascending. Only read, so `_lookup_complete` and the run after it share one
(`Construction`'s seeded path).
"""
struct _LookupSteps
    order::Vector{Int}
    arity::Vector{Int}
    first::Vector{Int}
    supports::Vector{Int}
end

"""
    _lookup_steps(targets, arity, order) -> _LookupSteps

The supports of `targets` by the step that covers them: a support goes to
its parameter last in `order`. `arity` must be the targets' layout's
(`targets.layout.arity`), the radix of the layout's codes: `isrequired`
decodes a code with it and `_mark_required!` walks the same codes with
`arity`, so a support's combinations are its values' product under both
(`TargetList`). Anything else is an internal error.
"""
function _lookup_steps(targets::RequiredTargets, arity::Vector{Int}, order::Vector{Int})
    n = length(arity)
    arity == targets.layout.arity ||
        error("internal error: the arity $arity is not the targets' layout's, $(targets.layout.arity)")
    length(order) == n && isperm(order) || error("internal error: $order is not an order of $n parameters")
    rank = invperm(order)
    sups = supports(targets)
    last = Vector{Int}(undef, length(sups))
    first = zeros(Int, n + 1)
    for (s, support) in enumerate(sups)
        isempty(support) && error("internal error: support $s is empty")
        l = support[1]
        for q in support
            1 <= q <= n || error("internal error: support $s names parameter $q of $n")
            rank[q] > rank[l] && (l = q)
        end
        last[s] = l
        first[l + 1] += 1
    end
    first[1] = 1
    for p in 1:n
        first[p + 1] += first[p]
    end
    by_step = Vector{Int}(undef, length(sups))
    next = first[1:n]
    for s in eachindex(sups)
        by_step[next[last[s]]] = s
        next[last[s]] += 1
    end
    return _LookupSteps(copy(order), copy(arity), first, by_step)
end


## A run

"""
    _LookupRun

One run of the core: the rows and the current step's map. Rows are kept in
`cells`, `n` entries each, row `r` at `(r - 1) * n .+ (1:n)`, in the space's
parameter order, `0` for unset, so `dead` sees every value a row holds. The
step's map (`_begin_step!`) is, for the step's support `j`, its position `s`
in `supports(targets)` (`sidx`), its other parameters and their strides in
the map's code (`params`, `strides`, `pfirst[j]:(pfirst[j + 1] - 1)`), the
start of its block (`offset`), how many of its combinations are uncovered
(`left`), and per combination whether it is required and uncovered
(`uncovered`). Per value of the step's parameter: `gains`, a row's score;
`used`, rows given that value in this step's horizontal growth; `leftv`,
uncovered combinations holding it; `tried`. `tiebreak` and `vertical` are
the run's member (`_IPOGLookup`). `pass` numbers the passes of vertical
growth, so that `stamp[r] == pass` marks row `r` as changed in the current
one. The other buffers are scratch, sized once per step or once per run.
"""
mutable struct _LookupRun{D}
    const n::Int
    const arity::Vector{Int}
    const order::Vector{Int}
    const rank::Vector{Int}
    const dead::D
    const tiebreak::Symbol
    const vertical::Symbol
    cells::Vector{Int}
    nrows::Int
    p::Int
    ap::Int
    m::Int
    pass::Int
    const sidx::Vector{Int}
    const pfirst::Vector{Int}
    const params::Vector{Int}
    const strides::Vector{Int}
    const offset::Vector{Int}
    const left::Vector{Int}
    const uncovered::Vector{Bool}
    const base::Vector{Int}
    const gains::Vector{Int}
    const used::Vector{Int}
    const leftv::Vector{Int}
    const tried::Vector{Bool}
    const putative::Vector{Int}      # one row, for `dead`
    const combo::Vector{Int}         # a combination's values on a support's other parameters
    const digits::Vector{Int}        # an odometer over one support, for `_mark_required!`
    const fstride::Vector{Int}
    const lists::Vector{Vector{Int}} # vertical growth's candidate rows, by p's value, `lists[1]` without one
    const modified::Vector{Int}      # rows changed in this pass of vertical growth
    const stamp::Vector{Int}         # per row, the last pass of vertical growth that changed it
    const hist::Vector{Int}          # the final fill's value counts, parameter q's at hoff[q] .+ (1:arity[q])
    const hoff::Vector{Int}
end

function _LookupRun(steps::_LookupSteps, dead::D, seeds::AbstractMatrix{<:Integer}, tiebreak::Symbol,
                    vertical::Symbol) where {D}
    arity = steps.arity
    n = length(arity)
    size(seeds, 1) == n || throw(ArgumentError("seeds have $(size(seeds, 1)) rows for $n parameters"))
    _rules(:tiebreak, tiebreak, _TIEBREAKS)
    _rules(:vertical, vertical, _VERTICALS)
    cells = Vector{Int}(vec(seeds))   # column j of `seeds` is row j
    nrows = size(seeds, 2)
    vmax = isempty(arity) ? 0 : maximum(arity)
    hoff = zeros(Int, n)
    for q in 2:n
        hoff[q] = hoff[q - 1] + arity[q - 1]
    end
    return _LookupRun{D}(n, arity, steps.order, invperm(steps.order), dead, tiebreak, vertical, cells, nrows,
                         0, 0, 0, 0,
                         Int[], Int[], Int[], Int[], Int[], Int[], Bool[], Int[],
                         zeros(Int, vmax), zeros(Int, vmax), zeros(Int, vmax), zeros(Bool, vmax),
                         zeros(Int, n), Int[], Int[], Int[], [Int[] for _ in 1:(vmax + 1)], Int[],
                         zeros(Int, nrows), zeros(Int, isempty(arity) ? 0 : sum(arity)), hoff)
end

"The rows of `run` as a parameters × rows matrix."
_lookup_matrix(run::_LookupRun) = reshape(run.cells[1:(run.n * run.nrows)], run.n, run.nrows)

"""
    _lookup_cover(steps, targets, dead, seeds; tiebreak = :lowest, vertical = :support) -> Matrix{Int}

IPOG's rows by lookup for the required targets of `targets` (`RequiredTargets`)
on the steps `steps` (`_lookup_steps`): the must-include rows `seeds`
(parameters × rows, `0` for unset, each completable) first, in order, their
set values unchanged and their unset entries filled like any other (§10.5,
§7.10); then rows until every required target is covered; every row complete
and, with `dead(row)` the request's completability question (`dead`), valid.
`dead` may throw `ResourceLimitError`, which propagates. An unconstrained
request passes `Returns(false)`. `tiebreak` and `vertical` are one member's
rules (`_IPOGLookup`). Deterministic (§9.3, §9.4).
"""
function _lookup_cover(steps::_LookupSteps, targets::RequiredTargets, dead, seeds::AbstractMatrix{<:Integer};
                       tiebreak::Symbol = :lowest, vertical::Symbol = :support)
    run = _LookupRun(steps, dead, seeds, tiebreak, vertical)
    _lookup_grow!(run, steps, targets, true)
    _fill!(run)
    return _lookup_matrix(run)
end

"""
    _lookup_complete(steps, targets, dead, seeds; tiebreak = :lowest, vertical = :support) -> Matrix{Int}

The must-include rows `seeds` with their unset entries chosen as
`_lookup_cover` chooses them before any other row exists: its steps on these
rows alone, adding no row. At each parameter, in order, each row without a
value takes the one horizontal growth gives it (`_horizontal!`): the value
whose combinations on the supports the row sets in full are the most still
uncovered, ties broken by the member's rule, among the values that keep the
row completable (`dead`), and none when the best scores nothing. Then the
targets still uncovered go to the first row that agrees with them and stays
completable, and the others stay uncovered. An entry that no uncovered
target asks for stays unset, for the rows that follow to use. A set value
never changes (contract §7.10), and the rows stay in order (§10.5).
`Construction` calls it before it filters the catalog's rows
(`_construction_rows`), on the steps the run after it reads again.
"""
function _lookup_complete(steps::_LookupSteps, targets::RequiredTargets, dead, seeds::AbstractMatrix{<:Integer};
                          tiebreak::Symbol = :lowest, vertical::Symbol = :support)
    run = _LookupRun(steps, dead, seeds, tiebreak, vertical)
    _lookup_grow!(run, steps, targets, false)
    return _lookup_matrix(run)
end

"The core's steps on `run`: for each parameter in order that ends some support, horizontal then vertical growth, the latter starting rows where `add` is true."
function _lookup_grow!(run::_LookupRun, steps::_LookupSteps, targets::RequiredTargets, add::Bool)
    for p in steps.order
        steps.first[p] == steps.first[p + 1] && continue
        _begin_step!(run, steps, targets, p)
        _horizontal!(run)
        _vertical!(run, add)
    end
    return run
end


## The step's map

"""
    _begin_step!(run, steps, targets, p)

Make the map of step `p`: its supports, their strides and blocks, each
combination marked when it is required (`_mark_required!`), then unmarked
where a row that already holds `p`, a must-include row, covers it.
"""
function _begin_step!(run::_LookupRun, steps::_LookupSteps, targets::RequiredTargets, p::Int)
    arity = run.arity
    ap = arity[p]
    lo = steps.first[p]
    m = steps.first[p + 1] - lo
    run.p, run.ap, run.m = p, ap, m
    resize!(run.sidx, m)
    resize!(run.left, m)
    resize!(run.base, m)
    resize!(run.pfirst, m + 1)
    resize!(run.offset, m + 1)
    empty!(run.params)
    empty!(run.strides)
    sups = supports(targets)
    total = 0
    for j in 1:m
        s = steps.supports[lo + j - 1]
        support = sups[s]
        run.sidx[j] = s
        start = length(run.params)
        run.pfirst[j] = start + 1
        for q in support
            q == p && continue
            push!(run.params, q)
            push!(run.strides, 0)
        end
        # p is the least significant digit, then the other parameters from
        # the last to the first: lexicographic, as FIPOG's `pack`.
        stride = ap
        for k in length(run.params):-1:(start + 1)
            run.strides[k] = stride
            stride *= arity[run.params[k]]
        end
        run.offset[j] = total
        total += stride
    end
    run.pfirst[m + 1] = length(run.params) + 1
    run.offset[m + 1] = total
    resize!(run.uncovered, total)
    fill!(view(run.used, 1:ap), 0)
    fill!(view(run.leftv, 1:ap), 0)
    for j in 1:m
        _mark_required!(run, targets, j)
    end
    n = run.n
    for r in 1:run.nrows
        off = (r - 1) * n
        run.cells[off + p] == 0 && continue
        for j in 1:m
            _cover_on!(run, off, j)
        end
    end
    return run
end

"""
    _mark_required!(run, targets, j)

Mark the required combinations of the step's support `j` in the map. When
every combination of the support is required (a `TargetList`, or a support
no rule touches), or none is, the counts say so (`nrequired`) and no
combination is asked about; otherwise each is asked (`isrequired`) by its
layout code, which an odometer over the support walks in order, first
parameter fastest, carrying the map's index along: the two layouts are
mapped without a division per combination.
"""
function _mark_required!(run::_LookupRun, targets::RequiredTargets, j::Int)
    s, p, ap = run.sidx[j], run.p, run.ap
    lo, hi = run.offset[j] + 1, run.offset[j + 1]
    uncovered, leftv = run.uncovered, run.leftv
    required = nrequired(targets, s)
    run.left[j] = required
    if required == hi - lo + 1
        fill!(view(uncovered, lo:hi), true)
        each = (hi - lo + 1) ÷ ap
        for v in 1:ap
            leftv[v] += each
        end
        return
    end
    fill!(view(uncovered, lo:hi), false)
    required == 0 && return
    support = supports(targets)[s]
    t = length(support)
    digits, fstride = run.digits, run.fstride
    resize!(digits, t)
    resize!(fstride, t)
    k = run.pfirst[j]
    for (i, q) in enumerate(support)
        digits[i] = 0
        if q == p
            fstride[i] = 1
        else
            fstride[i] = run.strides[k]   # `params` holds the support's other parameters in support order
            k += 1
        end
    end
    arity = run.arity
    idx = lo
    for code in 0:(hi - lo)
        if isrequired(targets, s, code)
            uncovered[idx] = true
            leftv[(idx - lo) % ap + 1] += 1
        end
        i = 1
        while i <= t
            digits[i] += 1
            idx += fstride[i]
            digits[i] < arity[support[i]] && break
            idx -= digits[i] * fstride[i]
            digits[i] = 0
            i += 1
        end
    end
    return
end

"""
    _base(run, off, j) -> Int

The index before the block of the row at `off` on the step's support `j`:
its combination with the step's parameter at value `v` is entry `_base + v`
of the map. `-1` when the row has an unset entry on the support's other
parameters, which then scores nothing (see the file header).
"""
@inline function _base(run::_LookupRun, off::Int, j::Int)
    cells, params, strides = run.cells, run.params, run.strides
    b = run.offset[j]
    @inbounds for k in run.pfirst[j]:(run.pfirst[j + 1] - 1)
        x = cells[off + params[k]]
        x == 0 && return -1
        b += (x - 1) * strides[k]
    end
    return b
end

"Unmark, on the step's support `j`, the combination the row at `off` holds, if it holds one there."
@inline function _cover_on!(run::_LookupRun, off::Int, j::Int)
    @inbounds x = run.cells[off + run.p]
    x == 0 && return
    @inbounds run.left[j] == 0 && return
    b = _base(run, off, j)
    b < 0 && return
    i = b + x
    @inbounds if run.uncovered[i]
        run.uncovered[i] = false
        run.left[j] -= 1
        run.leftv[x] -= 1
    end
    return
end


## Horizontal growth

"""
    _horizontal!(run)

Give the step's parameter a value in each row that has none: the value
whose combinations, looked up on each of the step's supports the row sets in
full, are the most still uncovered, ties broken by the run's rule
(`_choose`), and only a value that keeps the row completable. A row whose
best score is 0 keeps the entry unset.
"""
function _horizontal!(run::_LookupRun)
    n, p, ap, m = run.n, run.p, run.ap, run.m
    cells, gains, base, left, uncovered, leftv = run.cells, run.gains, run.base, run.left, run.uncovered, run.leftv
    for r in 1:run.nrows
        off = (r - 1) * n
        @inbounds cells[off + p] == 0 || continue   # a must-include row's value
        fill!(view(gains, 1:ap), 0)
        for j in 1:m
            @inbounds b = left[j] == 0 ? -1 : _base(run, off, j)   # FIPOG §5.2: a covered support is skipped
            @inbounds base[j] = b
            b < 0 && continue
            @inbounds for v in 1:ap
                gains[v] += uncovered[b + v]
            end
        end
        v = _choose(run, r, off)
        v == 0 && continue
        # Invariant: the row was completable, and `_choose` keeps it so.
        @inbounds cells[off + p] = v
        @inbounds run.used[v] += 1
        @inbounds for j in 1:m
            b = base[j]
            (b >= 0 && uncovered[b + v]) || continue
            uncovered[b + v] = false
            left[j] -= 1
            leftv[v] -= 1
        end
    end
    return run
end

"""
    _tiekey(run, r, v) -> Int

Row `r`'s rank of value `v` among values of equal score, lower first, by the
run's tie-break rule (`_IPOGLookup`); the lowest value wins a tie in rank.
"""
@inline function _tiekey(run::_LookupRun, r::Int, v::Int)
    tb, ap = run.tiebreak, run.ap
    tb === :lowest && return v
    tb === :highest && return -v
    tb === :rotate && return mod(v - r, ap)
    tb === :leastused && return @inbounds run.used[v] * (ap + 1) + v
    return @inbounds -run.leftv[v] * (ap + 1) + v   # :mostleft
end

"""
    _choose(run, r, off) -> Int

The value row `r` takes: among values of positive score, the best score,
then the best rank (`_tiekey`), whose row stays completable; `0` when there
is none. `dead` is asked once per value tried, best first, so a decision is
built only on its answers.
"""
function _choose(run::_LookupRun, r::Int, off::Int)
    gains, tried = run.gains, run.tried
    fill!(view(tried, 1:run.ap), false)
    while true
        best, score, key = 0, 0, 0
        @inbounds for v in 1:run.ap
            g = gains[v]
            (g > 0 && !tried[v]) || continue
            k = _tiekey(run, r, v)
            if best == 0 || g > score || (g == score && k < key)
                best, score, key = v, g, k
            end
        end
        best == 0 && return 0
        _dead_with(run, run.dead, off, best) || return best
        @inbounds tried[best] = true
    end
end

# Whether the row at `off` with the step's parameter set to `v` has no valid
# completion. `Returns(false)`, an unconstrained request's, is never shown a row.
_dead_with(::_LookupRun, d::Returns, ::Int, ::Int) = d.value
function _dead_with(run::_LookupRun, dead, off::Int, v::Int)
    putative = run.putative
    copyto!(putative, 1, run.cells, off + 1, run.n)
    putative[run.p] = v
    return dead(putative)::Bool
end


## Vertical growth

"""
    _vertical!(run, add)

Place every combination of the step still uncovered: in the first row, in
row order, that agrees with it (each of its entries unset or equal) and stays
completable; otherwise in a new row, when `add` is true (a new row holds one
required target, which is completable, §1.2), or nowhere, when it is false
(`_lookup_complete`). The run's `vertical` rule orders the combinations
(`_IPOGLookup`): `:support`, support by support in one pass; `:value`, a
pass per value of the step's parameter, the highest first, its supports and
combinations last first. Before a support's combinations are placed, the
rows changed so far in the pass unmark what they now cover on it
(`_rescan!`), so the map is exact for the support and a combination a row
already holds is never placed again. A pass of `:value` places only
combinations with its value, which only rows changed in that pass can have
come to hold, since a placement sets the step's parameter to the pass's
value.
"""
function _vertical!(run::_LookupRun, add::Bool)
    n, p, ap, m = run.n, run.p, run.ap, run.m
    left, uncovered, offset = run.left, run.uncovered, run.offset
    lists = run.lists
    for v in 1:(ap + 1)
        empty!(lists[v])
    end
    # Candidates (FIPOG §4.3, §5.3): rows with an unset entry among the
    # parameters added so far, by the step's parameter's value.
    k = run.rank[p]
    for r in 1:run.nrows
        off = (r - 1) * n
        @inbounds x = run.cells[off + p]
        if x == 0
            push!(lists[1], r)
        elseif _has_unset(run, off, k)
            push!(lists[x + 1], r)
        end
    end
    if run.vertical === :support
        _new_pass!(run)
        for j in 1:m
            @inbounds left[j] == 0 && continue
            _rescan!(run, j)
            for i in (offset[j] + 1):offset[j + 1]
                @inbounds uncovered[i] && _place!(run, j, i, add)
            end
        end
    else   # :value
        for v in ap:-1:1
            _new_pass!(run)
            for j in m:-1:1
                @inbounds left[j] == 0 && continue
                _rescan!(run, j)
                for i in (offset[j + 1] - ap + v):(-ap):(offset[j] + v)
                    @inbounds uncovered[i] && _place!(run, j, i, add)
                end
            end
        end
    end
    return run
end

"Begin a pass of vertical growth: no row has changed in it yet."
function _new_pass!(run::_LookupRun)
    run.pass += 1
    empty!(run.modified)
    return run
end

"Unmark, on the step's support `j`, what the rows changed in this pass now cover there."
function _rescan!(run::_LookupRun, j::Int)
    n = run.n
    for r in run.modified
        _cover_on!(run, (r - 1) * n, j)
    end
    return
end

"""
    _place!(run, j, i, add)

Place the uncovered combination at entry `i` of the map, on the step's
support `j`, in the first row that takes it (`_find_row`) or, when `add` is
true, a new row; mark it covered and the row changed in this pass.
"""
function _place!(run::_LookupRun, j::Int, i::Int, add::Bool)
    v = _decode_combo!(run, j, i - run.offset[j] - 1)
    r = _find_row(run, j, v)
    if r == 0
        add || return
        r = _new_row!(run)
        push!(run.lists[v + 1], r)
    end
    _write_combo!(run, r, j, v)
    @inbounds if run.stamp[r] != run.pass
        run.stamp[r] = run.pass
        push!(run.modified, r)
    end
    @inbounds run.uncovered[i] = false
    @inbounds run.left[j] -= 1
    @inbounds run.leftv[v] -= 1
    return
end

"Whether the row at `off` has an unset entry among the first `k - 1` parameters of the order."
@inline function _has_unset(run::_LookupRun, off::Int, k::Int)
    cells, order = run.cells, run.order
    @inbounds for i in 1:(k - 1)
        cells[off + order[i]] == 0 && return true
    end
    return false
end

"Write the values of combination `c` (its code in support `j`'s block) on the other parameters to `run.combo`; return its value of the step's parameter."
@inline function _decode_combo!(run::_LookupRun, j::Int, c::Int)
    combo, params, strides, arity = run.combo, run.params, run.strides, run.arity
    lo, hi = run.pfirst[j], run.pfirst[j + 1] - 1
    length(combo) < hi - lo + 1 && resize!(combo, hi - lo + 1)
    @inbounds for k in lo:hi
        combo[k - lo + 1] = (c ÷ strides[k]) % arity[params[k]] + 1
    end
    return c % run.ap + 1
end

"""
    _find_row(run, j, v) -> Int

The first row, in row order, among the candidates for value `v` (rows with
the step's parameter at `v` or unset), that agrees with the decoded
combination on support `j` and stays completable with it; `0` for none.
"""
function _find_row(run::_LookupRun, j::Int, v::Int)
    a, b = run.lists[1], run.lists[v + 1]
    na, nb = length(a), length(b)
    ia, ib = 1, 1
    n, p, cells = run.n, run.p, run.cells
    while ia <= na || ib <= nb
        if ib > nb || (ia <= na && @inbounds(a[ia] < b[ib]))
            @inbounds r = a[ia]
            ia += 1
        else
            @inbounds r = b[ib]
            ib += 1
        end
        off = (r - 1) * n
        @inbounds x = cells[off + p]
        (x == 0 || x == v) || continue   # a row of `a` given another value in this growth
        _agrees(run, off, j) || continue
        # Invariant: a row changes only if the merged row is completable.
        _combo_dead(run, run.dead, off, j, v) && continue
        return r
    end
    return 0
end

"Whether the row at `off` agrees with the decoded combination on support `j`'s other parameters."
@inline function _agrees(run::_LookupRun, off::Int, j::Int)
    cells, params, combo = run.cells, run.params, run.combo
    lo = run.pfirst[j]
    @inbounds for k in lo:(run.pfirst[j + 1] - 1)
        x = cells[off + params[k]]
        (x == 0 || x == combo[k - lo + 1]) || return false
    end
    return true
end

# Whether the row at `off` with the decoded combination written in has no valid completion.
_combo_dead(::_LookupRun, d::Returns, ::Int, ::Int, ::Int) = d.value
function _combo_dead(run::_LookupRun, dead, off::Int, j::Int, v::Int)
    putative, params, combo = run.putative, run.params, run.combo
    copyto!(putative, 1, run.cells, off + 1, run.n)
    lo = run.pfirst[j]
    for k in lo:(run.pfirst[j + 1] - 1)
        putative[params[k]] = combo[k - lo + 1]
    end
    putative[run.p] = v
    return dead(putative)::Bool
end

"Write the decoded combination on support `j`, with value `v` of the step's parameter, into row `r`."
@inline function _write_combo!(run::_LookupRun, r::Int, j::Int, v::Int)
    cells, params, combo = run.cells, run.params, run.combo
    off = (r - 1) * run.n
    lo = run.pfirst[j]
    @inbounds for k in lo:(run.pfirst[j + 1] - 1)
        cells[off + params[k]] = combo[k - lo + 1]
    end
    @inbounds cells[off + run.p] = v
    return
end

"A new row, every entry unset; its index."
function _new_row!(run::_LookupRun)
    n = run.n
    start = run.nrows * n
    resize!(run.cells, start + n)
    fill!(view(run.cells, (start + 1):(start + n)), 0)
    run.nrows += 1
    push!(run.stamp, 0)
    return run.nrows
end


## The final fill

"""
    _fill!(run)

Give every unset entry a value, row by row and parameter by parameter: the
value of that parameter used least so far in the design (the lowest of
equals) that keeps the row completable, so that rows end complete and valid.
"""
function _fill!(run::_LookupRun)
    n, cells, hist, hoff, arity = run.n, run.cells, run.hist, run.hoff, run.arity
    fill!(hist, 0)
    for r in 1:run.nrows, q in 1:n
        @inbounds x = cells[(r - 1) * n + q]
        x == 0 || @inbounds(hist[hoff[q] + x] += 1)
    end
    for r in 1:run.nrows
        off = (r - 1) * n
        for q in 1:n
            @inbounds cells[off + q] == 0 || continue
            v = _least_used(run, off, q)
            # Invariant: the row is completable, so some value keeps it so (a witness's).
            v == 0 && error("internal error: no value of parameter $q keeps case $r completable, " *
                            "though the case was completable")
            @inbounds cells[off + q] = v
            @inbounds hist[hoff[q] + v] += 1
        end
    end
    return run
end

"The least used value of parameter `q` that keeps the row at `off` completable, the lowest of equals; `0` for none."
function _least_used(run::_LookupRun, off::Int, q::Int)
    hist, h, aq, tried = run.hist, run.hoff[q], run.arity[q], run.tried
    length(tried) < aq && resize!(tried, aq)
    fill!(view(tried, 1:aq), false)
    while true
        best = 0
        @inbounds for v in 1:aq
            tried[v] && continue
            (best == 0 || hist[h + v] < hist[h + best]) && (best = v)
        end
        best == 0 && return 0
        _fill_dead(run, run.dead, off, q, best) || return best
        @inbounds tried[best] = true
    end
end

_fill_dead(::_LookupRun, d::Returns, ::Int, ::Int, ::Int) = d.value
function _fill_dead(run::_LookupRun, dead, off::Int, q::Int, v::Int)
    putative = run.putative
    copyto!(putative, 1, run.cells, off + 1, run.n)
    putative[q] = v
    return dead(putative)::Bool
end
