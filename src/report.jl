# Reporting and planning: `report` and `design_sizes` (plan Phase 5 steps 3
# and 4; contract §1.12, §1.23, §3.10, §3.12, §7.7, §8.3, §8.4).
#
# `report` is where verification happens (§1.23): it measures a result's rows
# with `coverage` machinery (measure.jl), never trusting the bookkeeping, and
# adds bonus coverage at strength + 1 and the prefix curve. `design_sizes`
# runs each strategy and measures what it produced. Neither prints a
# percentage when a target is unresolved (§3.10, §3.12), and neither calls a
# case count minimal (§8.3, §8.4).


## report

const _BonusCounts = NamedTuple{(:strength, :covered, :feasible, :unknown, :applicable, :reason),
                                Tuple{Int, Int, Int, Int, Bool, String}}
const _PrefixPoint = NamedTuple{(:cases, :covered, :feasible, :unknown), NTuple{4, Int}}

"""
    Report

What [`report`](@ref) found about a [`TestCases`](@ref). Fields:

- `guarantee::String`: the claim the rows meet, checked by measuring them,
  such as "5 cases cover all 11 feasible pairs of a 12-combination space (3
  pairs forbidden, 2 impossible under the constraints)".
- `strategy::Symbol`, `n_cases::Int`, `engine::Symbol`, `seed`,
  `n_must_include::Int`: as the result recorded them.
- `strength::Int`: the strength measured: the result's, or `min(2, number of
  parameters)` for an excursion or a full factorial, which have none
  (contract §1.12).
- `coverage::`[`Coverage`](@ref): the verification, at `strength` and the
  result's `stronger` groups.
- `excluded::Vector{`[`Exclusion`](@ref)`}`: the targets no valid row can
  hold, with the rules that exclude them, as this report's measurement
  classified and explained them with its own `explanation_limit`:
  `coverage.ordinary.excluded`, then `coverage.negative.excluded`, whose
  targets hold an [`Invalid`](@ref) value (§1.23, §5.10).
- `recorded::Vector{Exclusion}`: exclusions generation recorded for targets
  this measurement left unresolved (a search reached `feasibility_limit`),
  ordinary then negative, shown as "(recorded at generation)". Empty when
  the measurement resolved every target, and always for an excursion or a
  full factorial, which record none.
- `bonus`: coverage of the same rows at `strength + 1`, as `(strength,
  covered, feasible, unknown, applicable, reason)`. `applicable` is `false`,
  with a `reason`, when there are no targets at `strength + 1`: the strength
  already equals the number of parameters (§3.12).
- `prefix`: the prefix curve, one `(cases, covered, feasible, unknown)` per
  prefix length `1:n_cases`: how many ordinary targets at `strength` the
  first `cases` rows cover.

With `unknown` targets (a search reached `feasibility_limit`), `feasible` in
`coverage`, `bonus` and `prefix` is a lower bound, and nothing prints a
percentage or claims completeness (§3.10, §3.12).

`Report` fields are plain data except `coverage.space`, the
[`TestSpace`](@ref), which holds the rules' predicates.
`UnitTestDesign.plain(report)` gives a representation with no executable
state: nested `NamedTuple`s and `Vector`s of `Int`, `Float64`, `String`,
`Symbol`, `Bool` and `nothing`, with the space reduced to its names, its
printed domains and its rule labels. `github_matrix` validates values itself and rejects wrappers rather than stringifying them.
"""
struct Report
    guarantee::String
    strategy::Symbol
    n_cases::Int
    strength::Int
    coverage::Coverage
    excluded::Vector{Exclusion}
    recorded::Vector{Exclusion}
    bonus::_BonusCounts
    prefix::Vector{_PrefixPoint}
    seed::Union{Nothing, Int}
    engine::Symbol
    n_must_include::Int
end

"""
    report(cases::TestCases; feasibility_limit = 1_000_000,
           explanation_limit = 1_000_000) -> Report

Check what a generated result promises and say it in one line, with the
evidence (contract §1.23): the guarantee, measured from the rows; the targets
excluded, each with the rules that exclude it; bonus coverage at the next
strength; the prefix curve, how much the first rows cover, for suites that
run only part of the cases; and the seed. `show` prints only what generation
recorded; `report` recounts.

```jldoctest; setup = :(using UnitTestDesign)
julia> space = TestSpace(
           (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
           constraints = [
               @require(mode == :exact || solver == :none),
               forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
           ]);

julia> report(all_pairs(space))
5 cases cover all 11 feasible pairs of a 12-combination space (3 pairs forbidden, 2 impossible under the constraints)
excluded:
  (mode = :fast, solver = :lu): forbidden by rule 1 (@require(mode == :exact || solver == :none))
  (mode = :fast, solver = :qr): forbidden by rule 1 (@require(mode == :exact || solver == :none))
  (mode = :exact, tol = 0.001): forbidden by rule 2 (exact mode needs a tight tolerance)
  (solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
  (solver = :qr, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)
bonus: 5 of 5 feasible triples covered
prefix curve:
  first 1 of 5 cover 27% (3 of 11)
  first 2 of 5 cover 45% (5 of 11)
  first 3 of 5 cover 63% (7 of 11)
  first 4 of 5 cover 90% (10 of 11)
  first 5 of 5 cover 100% (11 of 11)
seed: none (IPOG uses no randomness)
```

A covering result is measured at its strength and `stronger` groups. An
excursion or a full factorial has no strength, so it is measured at strength
`min(2, number of parameters)` and the guarantee says so; an excursion is not
a covering design, and the guarantee says that too (§1.12, §7.7). An
excursion's must-include rows are kept first and are not bound by its
distance, so the guarantee counts them apart, as in "1 must-include row
kept first, then 1 case within distance 0 of (…)" (§7.5, §7.9).

With [`Invalid`](@ref) values the rows make two guarantees, stated apart
(§5.10): the ordinary one, then, after "negative:", what the negative rows
cover of the negative targets (§6) and which of those are excluded, as in
"6 cases cover all 9 feasible pairs of a 12-combination space (2 pairs
forbidden, 1 impossible under the constraints); negative: covers 4 of 4
feasible pairs". The excluded list gives the negative exclusions after the
ordinary ones.

The measurement searches, within `feasibility_limit` nodes per target, for
the targets no row holds (§3.9). A search that runs out leaves its target
unresolved: the counts become bounds ("8 of at least 11"), no percentage is
printed, and nothing is called complete (§3.10, §3.12). `explanation_limit`
bounds the search for the rules behind an implied exclusion (§3.13).

The report is the verification (§1.23). The exclusions it lists, with their
rules and whether each explanation is verified minimal, are its own, found
with its own `feasibility_limit` and `explanation_limit`, not copied from
generation: a result generated with `explanation_limit = 1` and reported
with the default shows verified explanations, and one reported with
`explanation_limit = 1` shows the explanations that limit left unresolved,
whatever generation found. Exclusions recorded at generation are a
fallback, used only for targets this measurement left unknown, and each is
printed with "(recorded at generation)"; they are in the `recorded` field,
apart from `excluded`.
"""
function report(cases::TestCases; feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    _check_limits(feasibility_limit, explanation_limit)
    n = length(cases.space.names)
    covering = cases.strategy === :covering
    strength = covering ? cases.strength : min(2, n)
    stronger = covering ? cases.stronger : Pair[]
    rows = collect(cases)
    c, prefix = _measure(rows, cases.space; strength, stronger, feasibility_limit, explanation_limit)
    recorded = covering ? _recorded_exclusions(cases, c) : Exclusion[]
    unknown = length(c.ordinary.unknown)
    points = _PrefixPoint[(cases = k, covered = prefix[k], feasible = c.ordinary.feasible, unknown = unknown)
                          for k in eachindex(prefix)]
    bonus = _bonus(rows, cases.space, strength; feasibility_limit, explanation_limit)
    return Report(_guarantee(cases, c), cases.strategy, length(cases), strength, c,
                  [c.ordinary.excluded; c.negative.excluded], recorded, bonus, points, cases.seed,
                  cases.engine, cases.n_must_include)
end

"""
    _recorded_exclusions(cases, c) -> Vector{Exclusion}

The exclusions generation recorded for targets the measurement `c` left
unknown, in the recorded (target) order, ordinary then negative: the
fallback `report` shows as "(recorded at generation)" (§1.23, §3.15).
Targets match by value index, so by identity (§2.1).
"""
function _recorded_exclusions(cases::TestCases, c::Coverage)
    isempty(c.ordinary.unknown) && isempty(c.negative.unknown) && return Exclusion[]
    space = cases.space
    unresolved = Set(case_indices(space, t) for t in [c.ordinary.unknown; c.negative.unknown])
    return Exclusion[e for e in [cases.excluded; cases.negative_excluded]
                     if case_indices(space, e.target) in unresolved]
end

"Coverage of `rows` at `strength + 1`, or why there is none (§3.12)."
function _bonus(rows, space::TestSpace, strength::Int; feasibility_limit, explanation_limit)
    n = length(space.names)
    if strength + 1 > n
        return _BonusCounts((strength + 1, 0, 0, 0, false,
            "strength $(strength + 1) exceeds the number of parameters, $n"))
    end
    b = _coverage(rows, space; strength = strength + 1, stronger = Pair[], feasibility_limit,
                  explanation_limit)
    return _BonusCounts((strength + 1, b.ordinary.covered, b.ordinary.feasible,
                         length(b.ordinary.unknown), true, ""))
end

_text(x) = sprint(show, x; context = :typeinfo => Any)

# "strength 2, 3 within (mode, solver, tol)"
function _strength_text(c::Coverage)
    text = "strength $(c.strength)"
    for (names, s) in c.stronger
        text *= ", $s within ($(join(names, ", ")))"
    end
    return text
end

"""
    _covers_text(c, verb; with_strength) -> (claim, rest)

What the rows cover, from the measurement: the claim "cover all 11 feasible
pairs", or "cover 9 of 11 feasible pairs" with the rest "; 2 pairs missing",
or, with unresolved targets, "cover 28 of at least 28 feasible pairs" with
"; 420 pairs unresolved (feasibility_limit = 1); no exact percentage"
(§3.10). The noun is pairs, triples, or combinations, the last followed by
the strengths when `with_strength`. The claim is `nothing` when no target is
feasible and none is unresolved.
"""
function _covers_text(c::Coverage, verb::AbstractString; with_strength::Bool)
    part = c.ordinary
    noun = _coverage_noun(c)
    nouns = noun == "combination" && with_strength ? "combinations at " * _strength_text(c) : noun * "s"
    resolved = isempty(part.unknown)
    resolved && part.feasible == 0 && return nothing, ""
    claim = if resolved && isempty(part.missing)
        "$verb all $(part.feasible) feasible $nouns"
    else
        "$verb $(part.covered) of $(resolved ? "" : "at least ")$(part.feasible) feasible $nouns"
    end
    rest = isempty(part.missing) ? "" : "; " * _plural(length(part.missing), noun) * " missing"
    if !resolved
        rest *= "; " * _plural(length(part.unknown), noun) * " unresolved (feasibility_limit = " *
                _grouped(c.limits.feasibility_limit) * "); no exact percentage"
    end
    return claim, rest
end

_excluded_note(c::Coverage) =
    isempty(c.ordinary.excluded) ? "" : " (" * _excluded_counts(c.ordinary.excluded) * ")"

# The negative guarantee, stated apart from the ordinary one (§5.10): "; negative:
# covers 4 of 4 feasible pairs (1 pair impossible under the constraints)".
function _negative_note(c::Coverage)
    _has_invalid(c.space) || return ""
    noun, limit = _coverage_noun(c), c.limits.feasibility_limit
    note = "; negative: " * sprint(io -> _print_part(io, c.negative, noun, limit; lists = false))
    isempty(c.negative.excluded) || (note *= " (" * _excluded_counts(c.negative.excluded) * ")")
    return note
end

"""
    _guarantee(cases, c) -> String

The guarantee line of `report`, from the measurement `c` and what the result
recorded (§1.19): for a covering design, what the rows cover in a space of
how many combinations, what was excluded, the must-include rows kept first,
and GND's seed; for an excursion, the must-include rows kept first, which
the distance does not bind (§7.5, §7.9), then the rows within the distance
of the base, the dropped rows and missing values, that it is not a covering
design, and what it covers at the measured strength; for a full factorial,
that it is every valid row, and what it covers. With `Invalid` values, the
negative targets' coverage and exclusions follow, after "negative:", stated
apart from the ordinary guarantee (§5.10).
"""
function _guarantee(tc::TestCases, c::Coverage)
    lead = _plural(length(tc), "case")
    space = "a $(length(tc.space))-combination space"
    tail = String[]
    must = _plural(tc.n_must_include, "must-include row") * " kept first"
    tc.n_must_include > 0 && tc.strategy !== :excursion && push!(tail, must)
    noun = _coverage_noun(c)
    if tc.strategy === :covering
        claim, rest = _covers_text(c, length(tc) == 1 ? "covers" : "cover"; with_strength = true)
        head = claim === nothing ? "$lead: no $noun of $space is feasible" : "$lead $claim of $space"
        head *= _excluded_note(c) * rest
        if tc.engine === :GND
            push!(tail, tc.seed === nothing ? "GND with the caller's rng" : "GND seed $(tc.seed)")
        end
        return join([head * _negative_note(c); tail], "; ")
    end
    if tc.strategy === :excursion
        # Must-include rows are exempt from the distance (§7.5, §7.9), so the
        # claim is made of the rows after them only.
        notes = tc.notes
        within = "within distance $(notes.distance) of $(sprint(io -> print(io, _row_text(io, notes.base))))"
        head = tc.n_must_include == 0 ? "$lead $within" :
               "$must, then $(_plural(length(tc) - tc.n_must_include, "case")) $within"
        notes.dropped > 0 && push!(tail, _plural(notes.dropped, "row") * " dropped")
        if !isempty(notes.never_appear)
            push!(tail, (length(notes.never_appear) == 1 ? "never appears: " : "never appear: ") *
                        join(("$name = $(_text(v))" for (name, v) in notes.never_appear), ", "))
        end
        push!(tail, "not a covering design")
    else
        head = "$lead, every valid row of $(length(tc.space))"
    end
    claim, rest = _covers_text(c, length(tc) == 1 ? "covers" : "cover"; with_strength = false)
    measured = "measured at strength $(c.strength), " *
               (claim === nothing ? "no $noun is feasible" :
                (length(tc) == 1 ? "the case " : "the cases ") * claim)
    push!(tail, measured * _excluded_note(c) * rest * _negative_note(c))
    return join([head; tail], "; ")
end

const _SHOWN_EXCLUSIONS = 20

_percent(covered, feasible) = covered == feasible ? 100 : min(99, floor(Int, 100 * covered / feasible))

"The prefix lengths `show` prints: about every fifth of the rows, and where coverage first is whole."
function _prefix_cuts(prefix::Vector{_PrefixPoint})
    n = length(prefix)
    cuts = Set(cld(n * i, 5) for i in 1:5)
    point = prefix[end]
    if point.unknown == 0 && point.feasible > 0
        whole = findfirst(p -> p.covered == p.feasible, prefix)
        whole === nothing || push!(cuts, whole)
    end
    return sort!(collect(cuts))
end

function _print_prefix(io::IO, r::Report)
    noun = _coverage_noun(r.coverage)
    if isempty(r.prefix)
        print(io, "prefix curve: no cases")
        return nothing
    end
    last = r.prefix[end]
    if last.unknown == 0 && last.feasible == 0
        print(io, "prefix curve: no feasible $noun to cover")
        return nothing
    end
    print(io, "prefix curve:")
    n = length(r.prefix)
    for k in _prefix_cuts(r.prefix)
        p = r.prefix[k]
        if p.unknown == 0
            print(io, "\n  first $k of $n cover $(_percent(p.covered, p.feasible))% ($(p.covered) of $(p.feasible))")
        else
            print(io, "\n  first $k of $n cover $(p.covered) of at least $(p.feasible)")
        end
    end
    return nothing
end

function _print_bonus(io::IO, r::Report)
    b = r.bonus
    if !b.applicable
        print(io, "bonus coverage not applicable: ", b.reason)
        return nothing
    end
    noun = _target_noun([b.strength])
    nouns = noun == "combination" ? "combinations at strength $(b.strength)" : noun * "s"
    if b.unknown == 0
        print(io, "bonus: $(b.covered) of $(b.feasible) feasible $nouns covered")
    else
        print(io, "bonus: $(b.covered) of at least $(b.feasible) feasible $nouns covered; ",
              _plural(b.unknown, noun), " unresolved (feasibility_limit = ",
              _grouped(r.coverage.limits.feasibility_limit), "); no exact percentage")
    end
    return nothing
end

function _seed_text(r::Report)
    r.engine === :GND && return r.seed === nothing ? "seed: none (GND drew from the caller's rng)" :
                                                     "seed: $(r.seed) (GND(seed = $(r.seed)) repeats these cases)"
    r.strategy === :excursion && return "seed: none (an excursion uses no randomness)"
    r.strategy === :full_factorial && return "seed: none (a full factorial uses no randomness)"
    return "seed: none ($(r.engine) uses no randomness)"
end

Base.show(io::IO, r::Report) = print(io, r.guarantee)

function Base.show(io::IO, ::MIME"text/plain", r::Report)
    print(io, r.guarantee)
    # This report's own exclusions, then generation's for the targets it left
    # unresolved, marked as such (§1.23).
    shown = [[(e, false) for e in r.excluded]; [(e, true) for e in r.recorded]]
    if !isempty(shown)
        print(io, "\nexcluded:")
        for (e, recorded) in shown[1:min(end, _SHOWN_EXCLUSIONS)]
            print(io, "\n  ")
            show(io, e)
            recorded && print(io, " (recorded at generation)")
        end
        length(shown) > _SHOWN_EXCLUSIONS &&
            print(io, "\n  and ", length(shown) - _SHOWN_EXCLUSIONS, " more")
    end
    print(io, "\n")
    _print_bonus(io, r)
    print(io, "\n")
    _print_prefix(io, r)
    print(io, "\n", _seed_text(r))
    return nothing
end


## design_sizes

const _SizeCounts = NamedTuple{(:covered, :feasible, :unknown), NTuple{3, Int}}
const _SizeRow = NamedTuple{(:strategy, :kind, :level, :status, :message, :cases, :share, :pairs, :triples),
    Tuple{String, Symbol, Int, Symbol, String, Union{Nothing, Int}, Union{Nothing, Float64},
          Union{Nothing, _SizeCounts}, Union{Nothing, _SizeCounts}}}

"""
    DesignSizes

The table [`design_sizes`](@ref) returns. Fields: `parameters` (the names),
`total` (the full product), `valid` (the valid rows, or `nothing` when the
product is above `limit` and they were not counted), `engine`, `limit`, and
`rows`, one per strategy run, each a `NamedTuple`:

- `strategy`: `"full_factorial"`, `"covering(s)"` or `"excursions(d)"`;
  `kind` (`:full_factorial`, `:covering`, `:excursion`) and `level` (the
  strength or distance, 0 for the full factorial).
- `status`: `:ok`; `:resource_limit` when the strategy stopped at a limit,
  with `message` naming it, and no case count or share (§3.12); or
  `:invalid_base` for an excursion whose default base breaks a rule.
- `cases`: the rows the strategy produced, and `share`, `cases / valid`
  (`nothing` when `valid` is unknown).
- `pairs`, `triples`: the design's coverage at strength 2 and 3 as
  `(covered, feasible, unknown)`; `nothing` when the space has too few
  parameters or the strategy did not finish.

Case counts are what the engine produced, not lower bounds (§8.3).
"""
struct DesignSizes
    parameters::Vector{Symbol}
    total::Union{Int, BigInt}
    valid::Union{Nothing, Int}
    engine::Symbol
    limit::Int
    rows::Vector{_SizeRow}
end

"""
    design_sizes(space; strengths = 1:3, distances = 1:2, engine = IPOG(), limit = 10^6,
                 from = nothing, feasibility_limit = 1_000_000,
                 explanation_limit = 1_000_000) -> DesignSizes
    design_sizes(domains::NamedTuple; constraints = [], kwargs...)
    design_sizes(name => domain, ...; constraints = [], kwargs...)
    design_sizes(domain, domain, ...; kwargs...)

How many cases each strategy gives for `space`, before committing to one
(plan Phase 5 step 4). Runs the full factorial, [`covering`](@ref) at each
of `strengths` up to the number of parameters (larger ones are left out),
and [`excursions`](@ref) at each of `distances` from `from` (the first value
of each parameter when omitted), and measures each design's pairs and
triples with [`coverage`](@ref):

```jldoctest; setup = :(using UnitTestDesign)
julia> design_sizes(:n => [1, 2, 3], :level => ["low", "mid", "high"],
                    :tol => [1.0, 3.7, 4.9], :kind => [:greedy, :relax, :optim])
strategy        cases   share  pairs  triples
full_factorial     81  100.0%  54/54  108/108  valid 81 of 81
covering(1)         3    3.7%  18/54   12/108
covering(2)        10   12.3%  54/54   39/108
covering(3)        31   38.3%  54/54  108/108
excursions(1)       9   11.1%  30/54   28/108
excursions(2)      33   40.7%  54/54   76/108
case counts are the rows each strategy produced with IPOG, not lower bounds
```

`share` is the fraction of the valid rows, known when the full product is at
most `limit` and the full factorial counted them; above it the table gives
the product only and no shares (§7.3). A strategy that stops at a resource
limit is shown with its status in place of a count (§3.12); the others still
run. The counts are the rows each strategy produced with `engine`, not lower
bounds (§8.3). The space comes in the forms `covering` takes.
"""
function design_sizes(input...; strengths = 1:3, distances = 1:2, engine = IPOG(), limit = 10^6,
                      from = nothing, constraints = nothing, feasibility_limit = 1_000_000,
                      explanation_limit = 1_000_000)
    strengths = _check_levels(:strengths, strengths, 1, "§11.1")
    distances = _check_levels(:distances, distances, 0, "§7.5")
    _check_engine(engine)
    limit = _check_integer(:limit, limit, 1, "§7.3")
    _check_limits(feasibility_limit, explanation_limit)
    space, _ = _space(:design_sizes, input, constraints)
    n = length(space.names)
    limits = (; feasibility_limit, explanation_limit)
    rows = _SizeRow[]
    ff = _attempt(() -> full_factorial(space; limit, limits...))
    valid = ff isa TestCases ? length(ff) : nothing
    push!(rows, _size_row("full_factorial", :full_factorial, 0, ff, valid, n, limits))
    for s in strengths
        s <= n || continue
        design = _attempt(() -> covering(space; strength = s, engine, limits...))
        push!(rows, _size_row("covering($s)", :covering, s, design, valid, n, limits))
    end
    for d in distances
        base = from === nothing ? _default_base(space) : nothing
        if base !== nothing && !isallowed(space, base)
            push!(rows, _SizeRow(("excursions($d)", :excursion, d, :invalid_base,
                "the default base $(_text(base)) breaks a rule; pass `from`", nothing, nothing,
                nothing, nothing)))
            continue
        end
        design = _attempt(() -> excursions(space; distance = d, from, limits...))
        push!(rows, _size_row("excursions($d)", :excursion, d, design, valid, n, limits))
    end
    return DesignSizes(copy(space.names), length(space), valid, nameof(typeof(engine)), limit, rows)
end

"A list of strengths or distances: integers of at least `least`, read before anything runs."
function _check_levels(keyword::Symbol, levels, least::Integer, section)
    levels isa Union{AbstractVector, Tuple, AbstractRange} || throw(ArgumentError(
        "$keyword is a list of integers, such as 1:3; got $(repr(levels))"))
    return Int[_check_integer(keyword, x, least, section) for x in levels]
end

_default_base(space::TestSpace) =
    NamedTuple{Tuple(space.names)}(Tuple(space.values[i][space.ordinary[i][1]] for i in eachindex(space.names)))

"`f()`, or the `ResourceLimitError` it threw (§3.12)."
function _attempt(f)
    try
        return f()
    catch err
        err isa ResourceLimitError || rethrow()
        return err
    end
end

function _size_counts(cases::TestCases, s::Int, n::Int, limits)
    s <= n || return nothing
    c = coverage(cases; strength = s, limits...)
    return _SizeCounts((c.ordinary.covered, c.ordinary.feasible, length(c.ordinary.unknown)))
end

function _size_row(strategy, kind, level, design, valid, n, limits)
    if design isa ResourceLimitError
        message = "$(design.keyword) = $(_grouped(design.limit)) reached: $(design.what)"
        return _SizeRow((strategy, kind, level, :resource_limit, message, nothing, nothing, nothing, nothing))
    end
    share = valid === nothing ? nothing : (valid == 0 ? nothing : length(design) / valid)
    return _SizeRow((strategy, kind, level, :ok, "", length(design), share,
                     _size_counts(design, 2, n, limits), _size_counts(design, 3, n, limits)))
end

# A share as a percentage: one decimal, but never 0.0% for a nonzero share nor
# 100.0% for less than the whole; below 0.1%, two significant digits.
function _share_cell(x::Real)
    x == 1 && return "100.0%"
    percent = 100 * x
    percent >= 0.1 && return string(min(99.9, round(percent; digits = 1)), "%")
    return string(round(percent; sigdigits = 2), "%")
end

_count_cell(c::Nothing) = "—"
_count_cell(c::_SizeCounts) = c.unknown == 0 ? "$(c.covered)/$(c.feasible)" : "$(c.covered)/≥$(c.feasible)"

function _size_note(t::DesignSizes, row::_SizeRow)
    if row.kind === :full_factorial
        row.status === :ok && return "valid $(row.cases) of $(t.total)"
        return "total $(t.total) only; $(row.message)"
    end
    return row.status === :ok ? "" : row.message
end

Base.show(io::IO, t::DesignSizes) =
    print(io, "DesignSizes: ", _plural(length(t.rows), "strategy"), " for ", _plural(length(t.parameters), "parameter"))

function Base.show(io::IO, ::MIME"text/plain", t::DesignSizes)
    header = ["strategy", "cases", "share", "pairs", "triples"]
    table = [[row.strategy,
              row.cases === nothing ? "—" : string(row.cases),
              row.share === nothing ? "—" : _share_cell(row.share),
              _count_cell(row.pairs), _count_cell(row.triples)] for row in t.rows]
    widths = [maximum(textwidth, [header[j]; [r[j] for r in table]]) for j in eachindex(header)]
    cell(text, j) = j == 1 ? rpad(text, widths[j]) : lpad(text, widths[j])
    print(io, rstrip(join((cell(header[j], j) for j in eachindex(header)), "  ")))
    for (row, texts) in zip(t.rows, table)
        line = join((cell(texts[j], j) for j in eachindex(header)), "  ")
        note = _size_note(t, row)
        print(io, "\n", isempty(note) ? rstrip(line) : line * "  " * note)
    end
    print(io, "\ncase counts are the rows each strategy produced with $(t.engine), not lower bounds")
    return nothing
end


## Plain data (Phase 5 review round 1, item 4)
#
# `plain` turns a Report, Coverage or DesignSizes into nested NamedTuples and
# Vectors whose leaves are Int, Float64, String, Symbol, Bool or nothing: no
# TestSpace, Constraint, RuleTable or Function survives. A value from a
# domain stays itself when it is one of those types, and becomes its `repr`
# otherwise. `repr` of the result parses back to an equal value.

const _PlainLeaf = Union{Int, Float64, String, Symbol, Bool, Nothing}

"A domain value as plain data: itself when it is a plain leaf, a `String` for other text, else its `repr`."
_plain_value(x) = x isa _PlainLeaf ? x : x isa AbstractString ? String(x) : repr(x)

"A target or a named row, with its values plain."
_plain_target(t::NamedTuple) = map(_plain_value, t)

"A row as the caller gave it: a NamedTuple stays one; a tuple or vector is named by the space."
_plain_row(space::TestSpace, row::NamedTuple) = _plain_target(row)
_plain_row(space::TestSpace, row) = NamedTuple{Tuple(space.names)}(Tuple(_plain_value(x) for x in row))

_plain_exclusion(e::Exclusion) =
    (target = _plain_target(e.target), status = e.status, rules = copy(e.rules), labels = copy(e.labels),
     minimal = e.minimal, limit = e.limit === nothing ? nothing : (keyword = e.limit.first, value = e.limit.second))

"The space without executable state: names, each domain's values as `repr`, and the rule labels."
_plain_space(space::TestSpace) =
    (names = copy(space.names),
     domains = [String[repr(v) for v in domain] for domain in space.values],
     rules = String[rule_label(space, k) for k in eachindex(space.constraints)])

function _plain_part(space::TestSpace, part::CoveragePart)
    return (covered = part.covered, feasible = part.feasible,
            missing = NamedTuple[_plain_target(t) for t in part.missing],
            excluded = NamedTuple[_plain_exclusion(e) for e in part.excluded],
            unknown = NamedTuple[_plain_target(t) for t in part.unknown],
            groups = NamedTuple[(names = collect(g.names), strength = g.strength, covered = g.covered,
                                 feasible = g.feasible, missing_count = g.missing_count,
                                 excluded_count = g.excluded_count, unknown_count = g.unknown_count)
                                for g in part.groups],
            rows = part.rows, duplicates = part.duplicates,
            rejected = NamedTuple[(index = r.index, row = _plain_row(space, r.row), reason = r.reason,
                                   rules = copy(r.rules)) for r in part.rejected])
end

"""
    plain(r::Report)
    plain(c::Coverage)
    plain(t::DesignSizes)

The same information as nested `NamedTuple`s and `Vector`s whose values are
`Int`, `Float64`, `String`, `Symbol`, `Bool` or `nothing`, with no executable
state: the space becomes its parameter names, each domain as the `repr` of
its values, and its rule labels (`coverage.space`, the one field of a
`Report` that holds rule predicates). Targets and rows are `NamedTuple`s of
their values where a value is one of those types and of its `repr` where it
is not, such as `"Invalid(0)"` or `"Partition(:tiny)"`; a row given as a
tuple or vector is named by the space. `stronger` groups become `(names,
strength)`, an exclusion's `limit` becomes `(keyword, value)`, and a
`DesignSizes` total above `typemax(Int)` becomes a `String` of digits.
`repr` of the result parses back to an equal value. Not exported.
"""
function plain(c::Coverage)
    return (ordinary = _plain_part(c.space, c.ordinary), negative = _plain_part(c.space, c.negative),
            space = _plain_space(c.space), strength = c.strength,
            stronger = NamedTuple[(names = collect(names), strength = s) for (names, s) in c.stronger],
            limits = c.limits)
end

function plain(r::Report)
    return (guarantee = r.guarantee, strategy = r.strategy, n_cases = r.n_cases, strength = r.strength,
            coverage = plain(r.coverage), excluded = NamedTuple[_plain_exclusion(e) for e in r.excluded],
            recorded = NamedTuple[_plain_exclusion(e) for e in r.recorded], bonus = r.bonus,
            prefix = copy(r.prefix), seed = r.seed, engine = r.engine, n_must_include = r.n_must_include)
end

function plain(t::DesignSizes)
    total = t.total isa Int ? t.total : (typemin(Int) <= t.total <= typemax(Int) ? Int(t.total) : string(t.total))
    return (parameters = copy(t.parameters), total = total, valid = t.valid, engine = t.engine,
            limit = t.limit, rows = NamedTuple[NamedTuple{keys(row)}(values(row)) for row in t.rows])
end
