# Reporting and planning: `report` and `design_sizes` (plan Phase 5 steps 3
# and 4; contract §1.12, §1.23, §3.10, §3.12, §7.7, §8.3, §8.4).
#
# `report` is where verification happens (§1.23): it measures a result's rows
# with `coverage` machinery (measure.jl) instead of reading the recorded
# counts, and adds bonus coverage at strength + 1, counted only, and the
# prefix curve. The guarantee line's other parts (must-include rows, an
# excursion's notes, a randomized engine's seed) are copied from the result (`_guarantee`),
# and recorded exclusions are a fallback for targets the measurement leaves
# unknown (`_recorded_exclusions`). `design_sizes` runs each strategy and
# counts what its rows cover. Each call reads a set of rows once and keeps one
# lazy-rule memo for all its measurements (§3.5). Neither prints a percentage
# when a target is unresolved (§3.10, §3.12). `report` calls a case count
# minimal only as the result recorded it, when the count equals its proven
# lower bound, and names the proof (§8.4, §8.7); `design_sizes` never does
# (§8.3). With `Invalid` values every figure comes in two parts, ordinary
# and negative, measured and printed apart (§5.9, §5.10).


## report

const _BonusCounts = NamedTuple{(:strength, :covered, :feasible, :unknown, :negative, :applicable, :reason),
                                Tuple{Int, Int, Int, Int, _PartCounts, Bool, String}}
const _PrefixPoint = NamedTuple{(:cases, :covered, :feasible, :unknown), NTuple{4, Int}}

"""
Use when you read the fields of what [`report`](@ref) found: the guarantee, the
coverage, the exclusions, bonus coverage, and the prefix curve.

    Report

What [`report`](@ref) found about a [`TestCases`](@ref). Fields:

- `guarantee::String`: the claim the rows meet, its coverage figures
  measured from the rows, such as "5 cases cover all 11 feasible pairs of a
  12-combination space (3 pairs forbidden, 2 impossible under the
  constraints)". The rest of the line is what the result recorded at
  generation (§1.19): the must-include rows kept first, an excursion's
  distance, base, dropped rows and values that never appear, a full
  factorial's "every valid row", and a randomized engine's seed, as its
  record's configuration names the engine.
- `strategy::Symbol`, `n_cases::Int`, `engine::Symbol`, `seed`,
  `n_must_include::Int`, `record::NamedTuple`: as the result recorded them
  ([`TestCases`](@ref)); `record` holds a covering design's lower bound,
  with its proof and whether the rows meet it, which `show` prints on its
  "size:" line, the engine's configuration, from which the guarantee and
  the seed line name the engine and the call that repeats the cases, and
  the stages that ran.
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
  covered, feasible, unknown, negative, applicable, reason)`. `covered`,
  `feasible` and `unknown` count the ordinary targets; `negative` is
  `(covered, feasible, unknown)` for the negative targets at `strength + 1`
  (§6), all 0 when the space has no [`Invalid`](@ref) values. `applicable`
  is `false`, with a `reason`, when there are no targets at `strength + 1`:
  the strength already equals the number of parameters (§3.12).
- `prefix`: the prefix curve, one `(cases, covered, feasible, unknown)` per
  prefix length `1:n_cases`: how many ordinary targets at `strength` the
  first `cases` rows cover.
- `prefix_negative`: the same for the negative targets, from the same pass
  over the rows: how many of them the first `cases` rows cover. Its
  `feasible` is 0 throughout when the space has no `Invalid` values.

Every progress figure keeps the two parts apart (§5.9, §5.10): ordinary
rows cover only ordinary targets and negative rows only negative ones, so
the ordinary prefix curve can reach 100% while the negative targets are not
yet covered. With `Invalid` values, `show` labels the ordinary figures as
ordinary and prints the negative ones beside them, as in "first 1 of 3
cover 100% of ordinary pairs (1 of 1); negative 0 of 2" and "bonus: 5 of 6
feasible triples covered; negative: 3 of 4".

With `unknown` targets (a search reached `feasibility_limit`), `feasible` in
`coverage`, `bonus` and the prefix curves is a lower bound, and nothing
prints a percentage or claims completeness (§3.10, §3.12).

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
    prefix_negative::Vector{_PrefixPoint}
    seed::Union{Nothing, Int}
    engine::Symbol
    n_must_include::Int
    record::NamedTuple
end

"""
Use when you want to check what a generated result promises and see the
evidence: the guarantee, with its coverage figures measured from the rows, what
the rules excluded and why, bonus coverage at the next strength, and how
coverage grows over the first cases.

    report(cases::TestCases; feasibility_limit = 1_000_000,
           explanation_limit = 1_000_000) -> Report

Check what a generated result promises and say it in one line, with the
evidence (contract §1.23): the guarantee, its coverage figures measured from
the rows; the targets excluded, each with the rules that exclude it; bonus
coverage at the next strength; the prefix curve, how much the first rows
cover, for suites that run only part of the cases; and the seed. `show`
prints only what generation recorded; `report` recounts.

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
size: 5 cases; lower bound 4: the 4 feasible combinations of mode and solver need a case each
bonus: 5 of 5 feasible triples covered
prefix curve:
  first 1 of 5 cover 27% (3 of 11)
  first 2 of 5 cover 54% (6 of 11)
  first 3 of 5 cover 72% (8 of 11)
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
ordinary ones. The bonus line and each prefix-curve line give the negative
figure beside the ordinary one, which is labeled ordinary, so a prefix
that covers every ordinary pair does not look complete while negative
targets remain:

```
prefix curve:
  first 1 of 3 cover 100% of ordinary pairs (1 of 1); negative 0 of 2
  first 2 of 3 cover 100% of ordinary pairs (1 of 1); negative 1 of 2
  first 3 of 3 cover 100% of ordinary pairs (1 of 1); negative 2 of 2
```

The measurement searches, within `feasibility_limit` nodes per target, for
the targets no row holds (§3.9). A search that runs out leaves its target
unresolved: the counts become bounds ("8 of at least 11"), no percentage is
printed, and nothing is called complete (§3.10, §3.12). `explanation_limit`
bounds the search for the rules behind an implied exclusion (§3.13); running
out marks that explanation unresolved and changes no count (§3.15).

The report is the verification (§1.23). The exclusions it lists, with their
rules and whether each explanation is verified inclusion-minimal, are its
own, found with its own `feasibility_limit` and `explanation_limit`, not
copied from generation: a result generated with `explanation_limit = 1`
and reported with the default shows verified explanations, and one reported
with `explanation_limit = 1` shows the explanations that limit left
unresolved, whatever generation found. Exclusions recorded at generation are a
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
    # One call: the rows are read once, and the base and bonus measurements
    # share one lazy-rule memo, each with its own answer caches (§3.5).
    memos = rule_memos(cases.space.tables)
    prepared = _prepare_rows(cases.space, memos, collect(cases))
    c, prefix, negative = _measure(prepared, cases.space; strength, stronger, memos, feasibility_limit,
                                   explanation_limit, curves = true)
    recorded = covering ? _recorded_exclusions(cases, c) : Exclusion[]
    bonus = _bonus(prepared, cases.space, strength; memos, feasibility_limit)
    return Report(_guarantee(cases, c), cases.strategy, length(cases), strength, c,
                  [c.ordinary.excluded; c.negative.excluded], recorded, bonus,
                  _prefix_points(prefix, c.ordinary), _prefix_points(negative, c.negative), cases.seed,
                  cases.engine, cases.n_must_include, cases.record)
end

"One prefix point per row: the part's targets the first `k` rows cover, out of its feasible and unknown."
_prefix_points(curve::Vector{Int}, part::CoveragePart) =
    _PrefixPoint[(cases = k, covered = curve[k], feasible = part.feasible, unknown = length(part.unknown))
                 for k in eachindex(curve)]

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

"Coverage counts of the prepared rows at `strength + 1`, ordinary and negative, or why there are none (§3.12)."
function _bonus(prepared::PreparedRows, space::TestSpace, strength::Int; memos, feasibility_limit)
    n = length(space.names)
    if strength + 1 > n
        return _BonusCounts((strength + 1, 0, 0, 0, _PartCounts((0, 0, 0)), false,
            "strength $(strength + 1) exceeds the number of parameters, $n"))
    end
    b = _measure_counts(prepared, space; strength = strength + 1, stronger = Pair[], memos, feasibility_limit)
    return _BonusCounts((strength + 1, b.ordinary.covered, b.ordinary.feasible, b.ordinary.unknown,
                         b.negative, true, ""))
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
pairs" ("cover the 1 feasible pair" for one), or "cover 9 of 11 feasible
pairs" with the rest "; 2 pairs missing", or, with unresolved targets,
"cover 28 of at least 28 feasible pairs" with
"; 420 pairs unresolved (feasibility_limit = 1); no exact percentage"
(§3.10). The noun is pairs, triples, or combinations, the last followed by
the strengths when `with_strength`. The claim is `nothing` when no target is
feasible and none is unresolved.
"""
function _covers_text(c::Coverage, verb::AbstractString; with_strength::Bool)
    part = c.ordinary
    noun = _coverage_noun(c)
    # The noun agrees with the feasible count: "the 1 feasible pair", "9 of 11 feasible pairs".
    nouns = _noun(part.feasible, noun) * (noun == "combination" && with_strength ? " at " * _strength_text(c) : "")
    resolved = isempty(part.unknown)
    resolved && part.feasible == 0 && return nothing, ""
    claim = if resolved && isempty(part.missing)
        "$verb $(part.feasible == 1 ? "the" : "all") $(part.feasible) feasible $nouns"
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
and a randomized engine's seed (`_seed_note`); for an excursion, the
must-include rows kept first, which the distance does not bind (§7.5, §7.9),
then the rows within the distance of the base, the dropped rows and missing
values, that it is not a covering design, and what it covers at the measured
strength; for a full factorial, that it is every valid row, and what it
covers. With `Invalid` values, the
negative targets' coverage and exclusions follow, after "negative:", stated
apart from the ordinary guarantee (§5.10).
"""
function _guarantee(tc::TestCases, c::Coverage)
    lead = _plural(length(tc), "case")
    space = "$(_indefinite(length(tc.space))) $(length(tc.space))-combination space"
    tail = String[]
    must = _plural(tc.n_must_include, "must-include row") * " kept first"
    tc.n_must_include > 0 && tc.strategy !== :excursion && push!(tail, must)
    noun = _coverage_noun(c)
    if tc.strategy === :covering
        claim, rest = _covers_text(c, length(tc) == 1 ? "covers" : "cover"; with_strength = true)
        head = claim === nothing ? "$lead: no $noun of $space is feasible" : "$lead $claim of $space"
        head *= _excluded_note(c) * rest
        config = get(tc.record, :engine, nothing)
        seed = config isa NamedTuple ? _seed_note(config) : nothing
        seed === nothing || push!(tail, seed)
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

"""
    _prefix_cuts(curves...) -> Vector{Int}

The prefix lengths `show` prints: about every fifth of the rows, and, for
each curve, where its coverage first is whole.
"""
function _prefix_cuts(curves::Vector{_PrefixPoint}...)
    n = length(first(curves))
    cuts = Set(cld(n * i, 5) for i in 1:5)
    for prefix in curves
        point = prefix[end]
        if point.unknown == 0 && point.feasible > 0
            whole = findfirst(p -> p.covered == p.feasible, prefix)
            whole === nothing || push!(cuts, whole)
        end
    end
    return sort!(collect(cuts))
end

"`covered of feasible`, or `covered of at least feasible` when some target is unresolved (§3.10)."
_of(p) = p.unknown == 0 ? "$(p.covered) of $(p.feasible)" : "$(p.covered) of at least $(p.feasible)"

_nothing_to_cover(p::_PrefixPoint) = p.unknown == 0 && p.feasible == 0

function _print_prefix(io::IO, r::Report)
    noun = _coverage_noun(r.coverage)
    if isempty(r.prefix)
        print(io, "prefix curve: no cases")
        return nothing
    end
    # With Invalid values the ordinary figure is labeled and the negative one
    # follows it on the same line (§5.10); without, the line is as it always was.
    negative = _has_invalid(r.coverage.space)
    if _nothing_to_cover(r.prefix[end]) && (!negative || _nothing_to_cover(r.prefix_negative[end]))
        print(io, "prefix curve: no feasible $noun to cover")
        return nothing
    end
    print(io, "prefix curve:")
    n = length(r.prefix)
    for k in _prefix_cuts(r.prefix, r.prefix_negative)
        p = r.prefix[k]
        print(io, "\n  first $k of $n")
        if negative && _nothing_to_cover(p)
            print(io, ": no ordinary $noun is feasible")
        elseif p.unknown == 0
            print(io, " cover $(_percent(p.covered, p.feasible))% ", negative ? "of ordinary $(noun)s " : "",
                  "($(p.covered) of $(p.feasible))")
        else
            print(io, " cover ", _of(p), negative ? " ordinary " * _noun(p.feasible, noun) : "")
        end
        negative && print(io, "; negative ", _of(r.prefix_negative[k]))
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
    nouns = _noun(b.feasible, noun) * (noun == "combination" ? " at strength $(b.strength)" : "")
    if b.unknown == 0
        print(io, "bonus: $(b.covered) of $(b.feasible) feasible $nouns covered")
    else
        print(io, "bonus: $(b.covered) of at least $(b.feasible) feasible $nouns covered; ",
              _plural(b.unknown, noun), " unresolved (feasibility_limit = ",
              _grouped(r.coverage.limits.feasibility_limit), "); no exact percentage")
    end
    if _has_invalid(r.coverage.space)
        print(io, "; negative: ", _of(b.negative))
        b.negative.unknown > 0 && print(io, ", ", b.negative.unknown, " unresolved")
    end
    return nothing
end

# The seed line reads the engine's configuration, `record.engine`, which a
# covering result records (`_seed_text` of a configuration). A result made
# without a record, which no engine of the package returns, shows the name it
# keeps.
function _seed_text(r::Report)
    config = get(r.record, :engine, nothing)
    config isa NamedTuple && return _seed_text(config)
    r.strategy === :excursion && return "seed: none (an excursion uses no randomness)"
    r.strategy === :full_factorial && return "seed: none (a full factorial uses no randomness)"
    return "seed: none ($(r.engine) uses no randomness)"
end

"""
    _size_line(r) -> Union{Nothing, String}

`report`'s line on a covering design's size (plan §6.1, D5): "size: 9 cases,
minimal: the 3 × 3 = 9 combinations of a and b need a case each" when the
rows equal the recorded lower bound, which is the one case in which a count
is called minimal and the line names its proof (contract §8.4); otherwise
"size: 13 cases; lower bound 9: …". A catalog design that is an orthogonal
array adds that each combination is in exactly one case. The bound was
proven at generation, from its classification, and is shown as recorded;
`nothing` for a result without one.
"""
function _size_line(r::Report)
    bound = get(r.record, :lower_bound, nothing)
    bound === nothing && return nothing
    size = _plural(r.n_cases, "case")
    line = r.record.minimal ? "size: $size, minimal: $(r.record.proof)" :
                              "size: $size; lower bound $bound: $(r.record.proof)"
    # A catalog design that is an orthogonal array says so (plan §5.4, "Balance").
    stage = get(r.record, :ordinary, nothing)
    maker = stage isa NamedTuple ? _made_by(stage) : (;)
    haskey(maker, :catalog) && maker.catalog.orthogonal &&
        (line *= "; an orthogonal array: each combination of $(r.strength) parameters' values is in exactly one case")
    return line
end

"""
    _made_by(stage) -> NamedTuple

The stage whose rows are the result's ordinary rows, from the stages a
result recorded (`record.ordinary`): a chooser's start that it kept
(`starts[kept]`), and a reducer's start when the reducer returned it as it
was (`reducer.rows == reducer.start`: it saves a smaller design only), else
the stage itself.
"""
function _made_by(stage::NamedTuple)
    haskey(stage, :reducer) && stage.reducer.rows < stage.reducer.start && return stage
    haskey(stage, :kept) && return _made_by(stage.starts[stage.kept])
    haskey(stage, :start) && return _made_by(stage.start)
    return stage
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
    size = _size_line(r)
    size === nothing || print(io, "\n", size)
    print(io, "\n")
    _print_bonus(io, r)
    print(io, "\n")
    _print_prefix(io, r)
    print(io, "\n", _seed_text(r))
    return nothing
end


## design_sizes

const _SizeCounts = _PartCounts
const _SizeRow = NamedTuple{(:strategy, :kind, :level, :status, :message, :cases, :share, :pairs, :triples,
                             :negative_cases, :negative_pairs, :negative_triples, :engine),
    Tuple{String, Symbol, Int, Symbol, String, Union{Nothing, Int}, Union{Nothing, Float64},
          Union{Nothing, _SizeCounts}, Union{Nothing, _SizeCounts},
          Union{Nothing, Int}, Union{Nothing, _SizeCounts}, Union{Nothing, _SizeCounts}, Union{Nothing, String}}}

"""
Use when you read the table [`design_sizes`](@ref) returns: one row per
strategy, with its case count, its share of the valid cases, and its coverage.

    DesignSizes

The table [`design_sizes`](@ref) returns. Fields: `parameters` (the names),
`total` (the full product), `valid` (the valid rows, ordinary and negative,
or `nothing` when the product is above `limit` and they were not counted),
`engine` (the name the results record of the first engine, such as `:IPOG`),
`limit`, `has_invalid` (whether the space has [`Invalid`](@ref) values, so
that each figure has a negative part), `rows`, one per strategy run, and
`engines`, every engine compared, as its constructor call (`"IPOG()"`,
`"Auto(goal = :compact)"`). Each row is a `NamedTuple`:

- `strategy`: `"full_factorial"`, `"covering(s)"` or `"excursions(d)"`;
  `kind` (`:full_factorial`, `:covering`, `:excursion`) and `level` (the
  strength or distance, 0 for the full factorial).
- `status`: `:ok`; `:resource_limit` when the strategy stopped at a limit,
  with `message` naming it, and no case count or share (§3.12);
  `:unsupported` when the engine does not cover the request, with `message`
  giving its reason, as `Construction()` refuses mixed value counts; or
  `:invalid_base` for an excursion whose default base breaks a rule.
- `cases`: the rows the strategy produced, ordinary and negative, and
  `share`, `cases / valid` (`nothing` when `valid` is unknown).
- `pairs`, `triples`: the design's coverage of the ordinary targets at
  strength 2 and 3 as `(covered, feasible, unknown)`; `nothing` when the
  space has too few parameters or the strategy did not finish.
- `negative_cases`: how many of `cases` are negative rows, with one
  `Invalid` value; `negative_pairs`, `negative_triples`: the coverage of the
  negative targets (§6) at strength 2 and 3, in the same form. 0 and zero
  counts when the space has no `Invalid` values; `nothing` where `cases` or
  `pairs` and `triples` are.
- `engine`: for a covering row, the engine that made it, as in `engines`,
  the call the result records (`record.engine.call` of its
  [`TestCases`](@ref)); `nothing` for the full factorial and the excursions,
  which use none.

Every figure keeps the ordinary and negative parts apart (§5.9, §5.10).
Case counts are what the engine produced, not lower bounds (§8.3).
"""
struct DesignSizes
    parameters::Vector{Symbol}
    total::Union{Int, BigInt}
    valid::Union{Nothing, Int}
    engine::Symbol
    limit::Int
    has_invalid::Bool
    rows::Vector{_SizeRow}
    engines::Vector{String}
end

"""
Use when choosing a strategy before committing to one: it shows how many cases
each strategy produces for your space, and what each covers.

    design_sizes(space; strengths = 1:3, distances = 1:2, engine = IPOG(), limit = 10^6,
                 from = nothing, feasibility_limit = 1_000_000,
                 explanation_limit = 1_000_000) -> DesignSizes
    design_sizes(space; engine = [IPOG(), Auto(goal = :compact)], kwargs...)
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
covering(2)         9   11.1%  54/54   36/108
covering(3)        30   37.0%  54/54  108/108
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

`engine` may be a vector of engines, to compare them: each covering strength
then has one row per engine, in the order given, under an `engine` column.
An engine that does not cover a request, such as [`Construction`](@ref) on
parameters with different numbers of values, shows its reason in place of a
count, as a resource limit does.

With [`Invalid`](@ref) values each count is two figures, ordinary + negative
(§5.10): `cases` as "4 + 3", the ordinary rows and the negative rows, and
`pairs` and `triples` as "9/9 + 4/4", the ordinary targets covered of the
feasible ones and then the negative targets (§6). A line under the table
says so. The share is of all valid rows, ordinary and negative.
"""
function design_sizes(input...; strengths = 1:3, distances = 1:2, engine = IPOG(), limit = 10^6,
                      from = nothing, constraints = nothing, feasibility_limit = 1_000_000,
                      explanation_limit = 1_000_000)
    strengths = _check_levels(:strengths, strengths, 1, "§11.1")
    distances = _check_levels(:distances, distances, 0, "§7.5")
    engines = _check_engines(engine)
    limit = _check_integer(:limit, limit, 1, "§7.3")
    _check_limits(feasibility_limit, explanation_limit)
    space, _ = _space(:design_sizes, input, constraints)
    n = length(space.names)
    limits = (; feasibility_limit, explanation_limit)
    # Every measurement of the call shares one lazy-rule memo, each with its
    # own answer caches; each generation is a request with its own (§3.5).
    memos = rule_memos(space.tables)
    rows = _SizeRow[]
    none = (nothing, nothing, nothing)   # the negative figures of a row with no case count
    ff = _attempt(() -> full_factorial(space; limit, limits...))
    valid = ff isa TestCases ? length(ff) : nothing
    push!(rows, _size_row("full_factorial", :full_factorial, 0, ff, valid, space; memos, feasibility_limit))
    labels = [_engine_config(e).call for e in engines]   # what each result records as its engine's call
    for s in strengths
        s <= n || continue
        # The targets at strength `s` are classified once, by the first engine
        # that runs, and read by every engine after it (`_Classified`):
        # classification is a function of the request, the same for each.
        classified = nothing
        for (e, label) in zip(engines, labels)
            # `covering(space; strength = s, engine = e, limits...)`, from the
            # plan whose fit is asked first, so that a refusal is a row's status
            # rather than an error, and the plan is prepared once. Each design
            # is a request of its own (§3.5).
            request = Request(space; strength = s, limits...)
            plan = _prepare(e, Profile(request))
            if plan.fit.kind === :unsupported
                push!(rows, _SizeRow(("covering($s)", :covering, s, :unsupported, plan.fit.reason, nothing, nothing,
                                      nothing, nothing, none..., label)))
                continue
            end
            classified === nothing && (classified = _attempt(() -> _Classified(request)))
            design = let c = classified
                c isa ResourceLimitError ? c : _attempt(() -> TestCases(request, _generate(plan, request, c)))
            end
            push!(rows, _size_row("covering($s)", :covering, s, design, valid, space; memos, feasibility_limit,
                                  engine = label))
        end
    end
    for d in distances
        base = from === nothing ? _default_base(space) : nothing
        if base !== nothing && !isallowed(space, base)
            push!(rows, _SizeRow(("excursions($d)", :excursion, d, :invalid_base,
                "the default base $(_text(base)) breaks a rule; pass `from`", nothing, nothing,
                nothing, nothing, none..., nothing)))
            continue
        end
        design = _attempt(() -> excursions(space; distance = d, from, limits...))
        push!(rows, _size_row("excursions($d)", :excursion, d, design, valid, space; memos, feasibility_limit))
    end
    return DesignSizes(copy(space.names), length(space), valid, engine_record(first(engines)).name, limit,
                       _has_invalid(space), rows, labels)
end

"`design_sizes`'s `engine`: one covering engine or a nonempty vector of them, each checked (`_check_engine`)."
function _check_engines(engine)
    engine isa AbstractVector || return CoveringEngine[_check_engine(engine)]
    isempty(engine) && throw(ArgumentError("`engine` is a covering engine or a vector of them; got an empty vector"))
    return CoveringEngine[_check_engine(e) for e in engine]
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

"""
    _size_counts(design, space, prepared, s; memos, feasibility_limit) -> (ordinary, negative)

The coverage counts at strength `s` of the design's rows, `prepared` in
`space`, at the strength and groups `coverage(design; strength = s)`
measures (`_measured_request`), or `(nothing, nothing)` above the number of
parameters. `memos` are the lazy-rule memos of `space`'s rules.
"""
function _size_counts(design::TestCases, space::TestSpace, prepared, s::Int; memos, feasibility_limit)
    s <= length(space.names) || return nothing, nothing
    strength, stronger = _measured_request(design, s, nothing)
    return _measure_counts(prepared, space; strength, stronger, memos, feasibility_limit)
end

"""
    _size_row(strategy, kind, level, design, valid, space; memos, feasibility_limit) -> _SizeRow

One line of `design_sizes`: `design`, generated from `space`, or the
`ResourceLimitError` that stopped it. The design's rows are measured in
`space`, not in `design.space`, because `memos` memoize `space`'s rules.
"""
function _size_row(strategy, kind, level, design, valid, space::TestSpace; memos, feasibility_limit,
                   engine::Union{Nothing, String} = nothing)
    if design isa ResourceLimitError
        message = "$(design.keyword) = $(_grouped(design.limit)) reached: $(design.what)"
        return _SizeRow((strategy, kind, level, :resource_limit, message, nothing, nothing, nothing, nothing,
                         nothing, nothing, nothing, engine))
    end
    # A covering row names the engine as its result recorded it.
    config = get(design.record, :engine, nothing)
    engine = config isa NamedTuple ? config.call : engine
    share = valid === nothing ? nothing : (valid == 0 ? nothing : length(design) / valid)
    # The rows are read once for both strengths, and only when one is measured.
    prepared = length(space.names) < 2 ? nothing : _prepare_rows(space, memos, collect(design))
    pairs, negative_pairs = _size_counts(design, space, prepared, 2; memos, feasibility_limit)
    triples, negative_triples = _size_counts(design, space, prepared, 3; memos, feasibility_limit)
    return _SizeRow((strategy, kind, level, :ok, "", length(design), share, pairs, triples,
                     count(hasinvalid, design), negative_pairs, negative_triples, engine))
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
# With Invalid values: "ordinary + negative" (§5.10).
_count_cell(c::Nothing, negative::Nothing) = "—"
_count_cell(c::_SizeCounts, negative::_SizeCounts) = _count_cell(c) * " + " * _count_cell(negative)

function _cases_cell(t::DesignSizes, row::_SizeRow)
    row.cases === nothing && return "—"
    t.has_invalid || return string(row.cases)
    return string(row.cases - row.negative_cases, " + ", row.negative_cases)
end

function _size_note(t::DesignSizes, row::_SizeRow)
    if row.kind === :full_factorial
        row.status === :ok && return "valid $(row.cases) of $(t.total)"
        return "total $(t.total) only; $(row.message)"
    end
    return row.status === :ok ? "" : row.message
end

Base.show(io::IO, t::DesignSizes) =
    print(io, "DesignSizes: ", _plural(length(t.rows), "strategy", "strategies"), " for ", _plural(length(t.parameters), "parameter"))

function Base.show(io::IO, ::MIME"text/plain", t::DesignSizes)
    # With several engines, an engine column follows the strategy (left-aligned, as it is).
    several = length(t.engines) > 1
    header = several ? ["strategy", "engine", "cases", "share", "pairs", "triples"] :
                       ["strategy", "cases", "share", "pairs", "triples"]
    counts(row, part) = t.has_invalid ? _count_cell(row[part], row[Symbol(:negative_, part)]) :
                                        _count_cell(row[part])
    table = [[row.strategy; several ? [something(row.engine, "")] : String[]; _cases_cell(t, row);
              row.share === nothing ? "—" : _share_cell(row.share);
              counts(row, :pairs); counts(row, :triples)] for row in t.rows]
    widths = [maximum(textwidth, [header[j]; [r[j] for r in table]]) for j in eachindex(header)]
    left = several ? 2 : 1
    cell(text, j) = j <= left ? rpad(text, widths[j]) : lpad(text, widths[j])
    print(io, rstrip(join((cell(header[j], j) for j in eachindex(header)), "  ")))
    for (row, texts) in zip(t.rows, table)
        line = join((cell(texts[j], j) for j in eachindex(header)), "  ")
        note = _size_note(t, row)
        print(io, "\n", isempty(note) ? rstrip(line) : line * "  " * note)
    end
    t.has_invalid && print(io, "\ncells with + read ordinary + negative: rows without and with an Invalid ",
                           "value, and the targets each kind covers")
    print(io, "\ncase counts are the rows each strategy produced with ",
          several ? "each engine" : string(t.engine), ", not lower bounds")
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

# Not called in src/: `plain` is for users, who call it qualified, as the `Report` docstring says.
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
            prefix = copy(r.prefix), prefix_negative = copy(r.prefix_negative), seed = r.seed,
            engine = r.engine, n_must_include = r.n_must_include, record = r.record)
end

function plain(t::DesignSizes)
    total = t.total isa Int ? t.total : (typemin(Int) <= t.total <= typemax(Int) ? Int(t.total) : string(t.total))
    return (parameters = copy(t.parameters), total = total, valid = t.valid, engine = t.engine,
            limit = t.limit, has_invalid = t.has_invalid,
            rows = NamedTuple[NamedTuple{keys(row)}(values(row)) for row in t.rows], engines = copy(t.engines))
end
