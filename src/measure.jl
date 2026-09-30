# Measurement: `coverage` and `missing_interactions` (plan Phase 5 steps 1,
# 2 and 5; contract §1.8–§1.17, §3.10, §3.11, §5.9–§5.11, §6).
#
# Coverage works in space value indices (space.jl) and reads nothing a
# generator recorded (§1.12). A row becomes one value index per parameter; a
# target is a partial index vector over one support (`_supports`, request.jl).
# A target that a valid row contains is feasible, with that row as its
# witness, and is never searched (§1.10): each support gets the set of the
# valid rows' projections onto it, and only the targets missing from that set
# are classified, through the Phase 2 machinery (`IndexClassification` of
# `explain_partial`, or `_status` when only counts are kept, on the
# `Feasibility` of the target's row kind). Ordinary and negative targets are
# measured separately, each against its own kind of row (§5.9–§5.11).
#
# A call reads its rows once (`PreparedRows`) and keeps one lazy-rule memo
# for all its measurements; each measurement searches in a
# `FeasibilityContext` of its own around that memo, so no answer cache
# crosses from one measurement to another (§3.5).


## The result

"One `stronger` group's (or the base group's) share of a coverage part."
const _GroupCounts = NamedTuple{
    (:names, :strength, :covered, :feasible, :missing_count, :excluded_count, :unknown_count),
    Tuple{Tuple{Vararg{Symbol}}, Int, Int, Int, Int, Int, Int}}

"Counts for one part, ordinary or negative: covered, feasible (a lower bound with unknowns), unknown."
const _PartCounts = NamedTuple{(:covered, :feasible, :unknown), NTuple{3, Int}}

"A row that contributes no coverage (§1.14): its position, the row as given, why, and the rules it breaks."
const _Rejected = NamedTuple{(:index, :row, :reason, :rules), Tuple{Int, Any, Symbol, Vector{Int}}}

"""
    CoveragePart

The ordinary or the negative half of a [`Coverage`](@ref) (contract §1.15,
§5.10). Ordinary targets are combinations of ordinary values, covered only by
valid ordinary rows; negative targets hold one [`Invalid`](@ref) value and
are covered only by valid negative rows (§1.9, §5.9, §6). Fields:

- `covered::Int`: targets some valid row of this kind contains (§1.9).
- `feasible::Int`: `covered` plus the missing targets. When `unknown` is
  empty this is the number of feasible targets; otherwise it is a lower
  bound, since an unresolved target may be feasible too (§3.10).
- `missing::Vector{NamedTuple}`: feasible targets no valid row contains, in
  target order (§9.7). Each is a partial row in parameter order.
- `excluded::Vector{`[`Exclusion`](@ref)`}`: targets no valid row can contain,
  `:forbidden` or `:implied`, with the rules that exclude them, in target
  order (§1.4).
- `unknown::Vector{NamedTuple}`: targets whose feasibility search reached
  `feasibility_limit`: neither missing nor excluded (§1.7, §3.10).
- `groups`: one entry per requested group, the base group first, then each
  `stronger` group in the order the request keeps them: `names`, `strength`,
  and the group's own `covered`, `feasible`, `missing_count`,
  `excluded_count` and `unknown_count`. A target that two groups share
  counts in each group's entry and once in the totals above (§1.8).
- `rows::Int`: distinct valid rows of this kind; `duplicates::Int`: valid
  rows that repeat an earlier one and count once (§1.11).
- `rejected`: rows accepted as input that contribute nothing (§1.14), as
  `(index, row, reason, rules)`: `index` is the row's position among the
  cases, `row` the row as given, `reason` `:violates_rule` (with `rules`,
  every applicable rule it breaks, in rule order) or `:multiple_invalid`
  (more than one `Invalid` value; `rules` empty). A row with an `Invalid`
  value is rejected in the negative part, any other in the ordinary part.
"""
struct CoveragePart
    covered::Int
    feasible::Int
    missing::Vector{NamedTuple}
    excluded::Vector{Exclusion}
    unknown::Vector{NamedTuple}
    groups::Vector{_GroupCounts}
    rows::Int
    duplicates::Int
    rejected::Vector{_Rejected}
end

"""
Use when you read what [`coverage`](@ref) measured: the covered, missing,
excluded and unresolved combinations, with ordinary and negative targets kept
apart.

    Coverage

What [`coverage`](@ref) measured: which of the requested combinations the
supplied rows contain (contract §1.12–§1.17). Fields:

- `ordinary`, `negative`: a
  [`CoveragePart`](@ref UnitTestDesign.CoveragePart) each, measured
  separately (§5.10). The negative part is empty unless the space has
  [`Invalid`](@ref) values.
- `space`: the [`TestSpace`](@ref) measured against.
- `strength`, `stronger`: the request, `stronger` as `names => strength`
  pairs without the base group, as in [`TestCases`](@ref).
- `limits`: `(feasibility_limit = …, explanation_limit = …)`, the budgets
  the classification used (§3.3, §3.13).

`iscomplete(c)` is `true` when no target of either part is missing or
unknown (§1.16). An unknown target makes it `false` without showing that
anything is missing: the counts are then bounds, and nothing prints a
percentage (§3.10).

It prints as a sentence per part (the negative part only when the space has
`Invalid` values), then the excluded counts, duplicates and rejected rows.
For the space and rows of [`coverage`](@ref)'s example, with the second row
given twice and a row that breaks a rule third:

```jldoctest; setup = :(using UnitTestDesign)
julia> space = TestSpace(
           (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
           constraints = [
               @require(mode == :exact || solver == :none),
               forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
           ]);

julia> handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
                      (mode = :exact, solver = :lu, tol = 1e-6),
                      (mode = :exact, solver = :none, tol = 1e-6)];

julia> rows = [handwritten[1], handwritten[2], (mode = :fast, solver = :lu, tol = 1e-3),
               handwritten[3], handwritten[2]];

julia> coverage(rows, space)
covers 8 of 11 feasible pairs, 3 missing: (mode = :exact, solver = :qr), (mode = :fast, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)
excluded: 3 pairs forbidden, 2 impossible under the constraints
1 duplicate row counted once
1 row rejected: row 3 breaks rule 1 (@require(mode == :exact || solver == :none))
```

and, when a search reached its limit, gives bounds and the unresolved
targets instead of an exact count:

```
covers 0 of at least 0 feasible pairs; 448 pairs unresolved (feasibility_limit = 1): (x1 = 1, x2 = 1), …, and 438 more; no exact percentage
```
"""
struct Coverage
    ordinary::CoveragePart
    negative::CoveragePart
    space::TestSpace
    strength::Int
    stronger::Vector{Pair{Tuple{Vararg{Symbol}}, Int}}
    limits::NamedTuple{(:feasibility_limit, :explanation_limit), Tuple{Int, Int}}
end

"""
Use when a test should assert that a set of cases covers every feasible
combination, as in `@test iscomplete(coverage(cases, space))`; it is `false`
when anything is missing or unresolved.

    iscomplete(c::Coverage) -> Bool

`true` when every feasible target, ordinary and negative, is covered and no
target is unresolved (contract §1.16). An unknown target makes it `false`:
coverage is never claimed complete under an exhausted limit (§1.7, §3.10).
Rejected rows do not change it; they are listed in the result (§1.14).

A rejected row does not make a result incomplete. To test that committed
cases are still valid, check the rows with [`isallowed`](@ref) as well,
`@test all(case -> isallowed(space, case), cases)`; otherwise a new rule
that forbids a committed row passes unnoticed.
"""
iscomplete(c::Coverage) = all(p -> isempty(p.missing) && isempty(p.unknown), (c.ordinary, c.negative))


## Preparing the rows (contract §1.11, §1.13, §1.14)

"""
    PreparedRows

A call's rows, read and sorted once for every measurement the call makes
(contract §1.11, §1.14, §5.3–§5.7), by `_prepare_rows`. Each field is a
pair, the ordinary kind first and the negative kind second:

- `kept`: the distinct valid rows of the kind, as value indices, in
  first-seen order.
- `duplicates`: how many valid rows of the kind repeat an earlier one.
- `rejected`: the rows of the kind that break an applicable rule (judged
  under `active_rules`, so a negative row at `p` skips every rule that reads
  `p`), and, for the negative kind, the rows with more than one `Invalid`
  value. Each record's `index` is the row's position among the caller's rows.
- `slots`: `slots[i][k]` is the position in `kept[i]` of the caller's row
  `k` when it is the first appearance of a valid row of kind `i`, else 0.
  The prefix curves of `report` read them.

Nothing here depends on the strength, the groups or a limit, so `report`'s
base and bonus measurements share one, and so do `design_sizes`'
measurements of one design at strengths 2 and 3.
"""
struct PreparedRows
    kept::Tuple{Vector{Vector{Int}}, Vector{Vector{Int}}}
    duplicates::Vector{Int}
    rejected::Tuple{Vector{_Rejected}, Vector{_Rejected}}
    slots::Tuple{Vector{Int}, Vector{Int}}
end

"""
    _prepare_rows(space, memos, rows) -> PreparedRows

Read each row with `_row_indices`, complete (§1.13), and sort it by kind and
validity (see `PreparedRows`). A row is checked with `violated_rules`, the
direct check alone, through the call's lazy-rule memo `memos` (§3.5,
§12.19). That check reads no answer cache and no limit bounds it, so the
result serves every measurement of the call.
"""
function _prepare_rows(space::TestSpace, memos, rows::AbstractVector)
    context = FeasibilityContext(space, memos)   # for each row kind's rule set; nothing is searched
    kept = (Vector{Int}[], Vector{Int}[])
    duplicates = [0, 0]
    rejected = (_Rejected[], _Rejected[])
    slots = (zeros(Int, length(rows)), zeros(Int, length(rows)))
    seen = Set{Vector{Int}}()
    for (k, row) in enumerate(rows)
        idx = _row_indices(space, row; what = "coverage row $k", section = "§1.13", complete = true)
        bad = _invalid_parameters(space, idx)
        part = isempty(bad) ? 1 : 2
        if length(bad) > 1
            push!(rejected[2], (index = k, row = row, reason = :multiple_invalid, rules = Int[]))
            continue
        end
        f, active = feasibility_for(context, idx)
        broken = violated_rules(f, idx)
        if !isempty(broken)
            push!(rejected[part], (index = k, row = row, reason = :violates_rule, rules = active[broken]))
        elseif idx in seen
            duplicates[part] += 1
        else
            push!(seen, idx)
            push!(kept[part], idx)
            slots[part][k] = length(kept[part])
        end
    end
    return PreparedRows(kept, duplicates, rejected, slots)
end


## Measuring one part

# Supports with at most this many value combinations mark projections in a
# BitVector, indexed by a mixed-radix code; larger ones use a Set of vectors.
const _MAX_MARKS = 1 << 26

"The 0-based code of `idx` over `support`, first parameter fastest, in radix `radix`."
function _code(idx::AbstractVector{<:Integer}, support::Vector{Int}, radix::Vector{Int})
    code, stride = 0, 1
    for p in support
        code += (idx[p] - 1) * stride
        stride *= radix[p]
    end
    return code
end

"""
    _projections(table, support, radix, codes, firsts)

The rows' projections onto `support`, the set that decides coverage without
a search (contract §1.10). `table` holds the rows parameter-major, one row
per case and one column per parameter, so a support reads only its own
columns, in order. A support with at most `_MAX_MARKS` value combinations
gets a `BitVector` over the codes of `_code`, accumulated column by column in
the buffer `codes`; a larger one gets a `Set` of value-index vectors.

`firsts`, when it is a vector, gains one at row `j` for each projection that
row `j` is the first to hold: summed over the supports, the targets each row
adds to the rows before it, which is the prefix curve of `report`. For
negative rows, `at[j]` is row `j`'s invalid parameter, and a projection
counts only when the support holds it: a negative row's projection onto
other parameters is ordinary values alone, no negative target (§5.9).
"""
function _projections(table::Matrix{Int}, support::Vector{Int}, radix::Vector{Int},
                      codes::Vector{Int}, firsts::Union{Nothing, Vector{Int}} = nothing,
                      at::Union{Nothing, Vector{Int}} = nothing)
    counts(j) = firsts !== nothing && (at === nothing || at[j] in support)
    if prod(BigInt, (radix[p] for p in support); init = big(1)) <= _MAX_MARKS
        fill!(codes, 0)
        stride = 1
        for p in support
            column = view(table, :, p)
            @inbounds for j in eachindex(codes, column)
                codes[j] += (column[j] - 1) * stride
            end
            stride *= radix[p]
        end
        marks = falses(stride)
        for (j, code) in enumerate(codes)
            marks[code + 1] && continue
            marks[code + 1] = true
            counts(j) && (firsts[j] += 1)
        end
        return marks
    end
    set = Set{Vector{Int}}()
    for j in axes(table, 1)
        key = table[j, support]
        key in set && continue
        push!(set, key)
        counts(j) && (firsts[j] += 1)
    end
    return set
end

_contains(marks::BitVector, t, support, radix) = marks[_code(t, support, radix) + 1]
_contains(set::Set{Vector{Int}}, t, support, radix) = t[support] in set

"""
    _Lists(explanation_limit)

What a measured part lists: its missing, excluded and unknown targets, in
the order they are met (target order, §9.7). Each excluded target carries
the rules the deletion search found within `explanation_limit` (§3.13).
"""
struct _Lists
    missing::Vector{NamedTuple}
    excluded::Vector{Exclusion}
    unknown::Vector{NamedTuple}
    explanation_limit::Int
end

_Lists(explanation_limit::Int) = _Lists(NamedTuple[], Exclusion[], NamedTuple[], explanation_limit)

"""
    _Counts()

The counting sibling of `_Lists`: a part measured with it lists no target
and explains no exclusion, so the counts `_measure_block!` returns are the
whole measurement. It holds nothing, because those counts are kept per
support anyway.
"""
struct _Counts end

"""
    _classify!(record, context, t) -> Symbol

Decide one target that no valid row contains, `t` a full-width index vector,
on the `Feasibility` of its row kind (§5.5, §6.2), and return its status as
`IndexClassification` gives it: `:required` (so missing, §1.9), `:forbidden`
or `:implied` (excluded, §1.4), or `:unknown` (the search reached its limit,
§1.7). `t` is not retained.

- With `_Lists`, record the target: missing or unknown as a `NamedTuple`,
  excluded as an `Exclusion` with its rules in the space's numbering and
  their labels, from `explain_partial` with the deletion search bounded by
  `lists.explanation_limit` (§3.13–§3.16).
- With `_Counts`, record nothing: `_status` finds the status without the
  deletion search.
"""
function _classify!(lists::_Lists, context::FeasibilityContext, t::Vector{Int})
    space = context.space
    f, active = feasibility_for(context, t)
    c = IndexClassification(explain_partial(f, t; explanation_limit = lists.explanation_limit))
    if c.status === :required
        push!(lists.missing, from_indices(space, t))
    elseif c.status === :unknown
        push!(lists.unknown, from_indices(space, t))
    else
        rules = active[c.rules]
        push!(lists.excluded, Exclusion(from_indices(space, t), c.status, rules,
            [rule_label(space, k) for k in rules], c.minimal,
            _limit_pair(c.limit, context.feasibility_limit, lists.explanation_limit)))
    end
    return c.status
end

_classify!(::_Counts, context::FeasibilityContext, t::Vector{Int}) =
    _status(first(feasibility_for(context, t)), t)

"""
    _measure_block!(record, context, support, rest, t, seen, radix)
        -> (covered, missing, excluded, unknown)

Measure the targets that assign `t`'s fixed entries (an invalid value, for a
negative block, or none) and every combination of ordinary values of the
parameters `rest`, the first varying fastest (§1.8, §6.1). A target found in
`seen`, the rows' projections onto `support`, is covered without a search
(§1.10); any other is classified into `record`, a `_Lists` or a `_Counts`.
`t` is a reused buffer: `rest` is cleared again on return.
"""
function _measure_block!(record::Union{_Lists, _Counts}, context::FeasibilityContext,
                         support::Vector{Int}, rest::Vector{Int}, t::Vector{Int}, seen, radix::Vector{Int})
    choices = [context.space.ordinary[q] for q in rest]
    k = length(rest)
    position = ones(Int, k)
    for i in 1:k
        t[rest[i]] = choices[i][1]
    end
    c = m = x = u = 0
    while true
        if _contains(seen, t, support, radix)
            c += 1
        else
            status = _classify!(record, context, t)
            status === :required ? (m += 1) : status === :unknown ? (u += 1) : (x += 1)
        end
        i = 1   # the next assignment, first parameter fastest
        while i <= k
            if position[i] < length(choices[i])
                position[i] += 1
                t[rest[i]] = choices[i][position[i]]
                break
            end
            position[i] = 1
            t[rest[i]] = choices[i][1]
            i += 1
        end
        i > k && break
    end
    for q in rest
        t[q] = 0
    end
    return (c, m, x, u)
end

"""
    _measure_support!(record, context, support, kind, table, codes, radix, firsts, at)
        -> (covered, missing, excluded, unknown)

The targets of `kind` on one support, in a fixed order (contract §9.7):

- `:ordinary` (§1.8): every assignment of ordinary values, the first
  parameter varying fastest, as `TargetList` orders engine positions.
- `:negative` (§6.1, §6.4, §6.5): for each parameter `p` of the support, in
  order, each invalid value `v` of `p`, in domain order, every assignment of
  ordinary values to the rest of the support, the first parameter fastest.
  At strength 1 the rest is empty and the target is `(p = v)` alone.

`firsts` and `at` are passed to `_projections` for the prefix curves.
"""
function _measure_support!(record::Union{_Lists, _Counts}, context::FeasibilityContext,
                           support::Vector{Int}, kind::Symbol, table::Matrix{Int}, codes::Vector{Int},
                           radix::Vector{Int}, firsts, at)
    space = context.space
    t = zeros(Int, length(space.names))
    kind === :negative && all(p -> isempty(space.invalid[p]), support) && return (0, 0, 0, 0)
    # A negative row's projection onto a support without its invalid
    # parameter is no negative target, so `at` keeps it out of `firsts`.
    seen = _projections(table, support, radix, codes, firsts, at)
    kind === :ordinary && return _measure_block!(record, context, support, support, t, seen, radix)
    total = (0, 0, 0, 0)
    for p in support, v in space.invalid[p]
        t[p] = v
        block = _measure_block!(record, context, support, filter(!=(p), support), t, seen, radix)
        total = total .+ block
        t[p] = 0
    end
    return total
end

"""
    _support_counts(record, context, supports, rows, kind; firsts = nothing)
        -> Dict{Vector{Int}, NTuple{4, Int}}

Measure the targets of `kind` (`:ordinary` or `:negative`) against `rows`,
the distinct valid rows of that kind, support by support, classifying into
`record`: each support's `(covered, missing, excluded, unknown)`. `firsts`,
a vector of zeros aligned with `rows`, receives the number of targets of
`kind` each row is the first to cover (see `_projections`), so
`sum(firsts)` is the part's `covered`.
"""
function _support_counts(record::Union{_Lists, _Counts}, context::FeasibilityContext,
                         supports::Vector{Vector{Int}}, rows::Vector{Vector{Int}}, kind::Symbol;
                         firsts = nothing)
    space = context.space
    at = kind === :negative ? Int[only(_invalid_parameters(space, r)) for r in rows] : nothing
    radix = [length(v) for v in space.values]
    table = Int[r[p] for r in rows, p in eachindex(space.names)]   # cases × parameters
    codes = zeros(Int, length(rows))
    counts = Dict{Vector{Int}, NTuple{4, Int}}()
    for support in supports
        counts[support] = _measure_support!(record, context, support, kind, table, codes, radix, firsts, at)
    end
    return counts
end

"""
    _measure_part(context, groups, supports, rows, kind; explanation_limit, duplicates, rejected,
                  firsts) -> CoveragePart

Measure the targets of `kind` against `rows` (see `_support_counts`),
listing them, and sum each group's supports for its breakdown (§1.15).
"""
function _measure_part(context::FeasibilityContext, groups, supports::Vector{Vector{Int}},
                       rows::Vector{Vector{Int}}, kind::Symbol; explanation_limit::Int,
                       duplicates::Int, rejected::Vector{_Rejected}, firsts)
    space = context.space
    lists = _Lists(explanation_limit)
    counts = _support_counts(lists, context, supports, rows, kind; firsts)
    breakdown = _GroupCounts[]
    for (members, s) in groups
        c = m = x = u = 0
        for support in combinations(members, s)
            sc, sm, sx, su = counts[support]
            c += sc; m += sm; x += sx; u += su
        end
        push!(breakdown, (names = Tuple(space.names[members]), strength = s, covered = c,
                          feasible = c + m, missing_count = m, excluded_count = x, unknown_count = u))
    end
    covered = sum(first, values(counts); init = 0)
    return CoveragePart(covered, covered + length(lists.missing), lists.missing, lists.excluded,
                        lists.unknown, breakdown, length(rows), duplicates, rejected)
end

"The counts of the targets of `kind` against `rows`, `(covered, feasible, unknown)`, with nothing listed."
function _count_part(context::FeasibilityContext, supports::Vector{Vector{Int}}, rows::Vector{Vector{Int}},
                     kind::Symbol)
    c = m = u = 0
    for (sc, sm, _, su) in values(_support_counts(_Counts(), context, supports, rows, kind))
        c += sc; m += sm; u += su
    end
    return _PartCounts((c, c + m, u))
end

"""
    _measure(prepared, space; strength, stronger, memos, feasibility_limit, explanation_limit, curves)
        -> (coverage, prefix, negative_prefix)

One measurement of prepared rows, behind every `coverage` method and
`report`. Checks the request (§11), then measures the ordinary targets
(§1.8) and, when the space has `Invalid` values, the negative targets (§6).
The targets are those of `Request(space; strength, stronger)`, in the same
order: `_supports(groups)`, each over its ordinary values. The searches run
in a `FeasibilityContext` of this measurement's own, around `memos`, the
call's lazy-rule memo (§3.5): a call's measurements may share the memo, never
the answer caches.

With `curves`, `prefix[k]` is the number of ordinary targets the first `k`
rows cover, from the same pass (each row adds the targets it is the first
to hold), so `prefix[end] == coverage.ordinary.covered`; `negative_prefix[k]`
is the same for the negative targets, from the negative part's marking, so
`negative_prefix[end] == coverage.negative.covered` (§5.9, §5.10). Without,
both are `nothing`: only `report`'s base measurement reads them.
"""
function _measure(prepared::PreparedRows, space::TestSpace; strength, stronger, memos,
                  feasibility_limit, explanation_limit, curves::Bool)
    strength = _check_strength(strength, length(space.names))
    groups = _groups(space, strength, stronger)
    context = FeasibilityContext(space, memos; feasibility_limit)
    explanation_limit = _check_limit(:explanation_limit, explanation_limit)
    supports = _supports(groups)
    kept, duplicates, rejected = prepared.kept, prepared.duplicates, prepared.rejected
    firsts = curves ? (zeros(Int, length(kept[1])), zeros(Int, length(kept[2]))) : (nothing, nothing)
    ordinary = _measure_part(context, groups, supports, kept[1], :ordinary; explanation_limit,
                             duplicates = duplicates[1], rejected = rejected[1], firsts = firsts[1])
    negative = _measure_part(context, groups, supports, kept[2], :negative; explanation_limit,
                             duplicates = duplicates[2], rejected = rejected[2], firsts = firsts[2])
    named = Pair{Tuple{Vararg{Symbol}}, Int}[Tuple(space.names[g]) => s for (g, s) in groups[2:end]]
    c = Coverage(ordinary, negative, space, strength, named,
                 (feasibility_limit = context.feasibility_limit, explanation_limit = explanation_limit))
    curves || return c, nothing, nothing
    curve(part) = cumsum(Int[slot == 0 ? 0 : firsts[part][slot] for slot in prepared.slots[part]])
    return c, curve(1), curve(2)
end

"""
    _measure_counts(prepared, space; strength, stronger, memos, feasibility_limit)
        -> (ordinary, negative)

The counts of the measurement `_measure` makes, `(covered, feasible,
unknown)` for each part, and nothing else: no target is listed and no
exclusion explained, so no deletion search runs and `explanation_limit`
plays no part (§3.13). The searches are `_measure`'s, in a context of this
measurement's own around `memos`, so each count is the one `_measure` gives.
For `report`'s bonus and `design_sizes`, which keep only counts.
"""
function _measure_counts(prepared::PreparedRows, space::TestSpace; strength, stronger, memos,
                         feasibility_limit)
    groups = _groups(space, _check_strength(strength, length(space.names)), stronger)
    context = FeasibilityContext(space, memos; feasibility_limit)
    supports = _supports(groups)
    return (ordinary = _count_part(context, supports, prepared.kept[1], :ordinary),
            negative = _count_part(context, supports, prepared.kept[2], :negative))
end

"The measurement behind `coverage`: one call, so the rows are prepared for this one measurement and memo."
function _coverage(rows::AbstractVector, space::TestSpace; strength, stronger, feasibility_limit,
                   explanation_limit)
    memos = rule_memos(space.tables)
    return first(_measure(_prepare_rows(space, memos, rows), space; strength, stronger, memos,
                          feasibility_limit, explanation_limit, curves = false))
end


## The public functions

"""
Use when you have test cases from anywhere (hand-written, generated, or an older
design) and want to know which combinations of values they cover and which they
miss.

    coverage(cases, space; strength = 2, stronger = [],
             feasibility_limit = 1_000_000, explanation_limit = 1_000_000) -> Coverage
    coverage(cases, domains::NamedTuple; constraints = [], kwargs...)
    coverage(cases, name => domain, ...; constraints = [], kwargs...)
    coverage(cases, domain, domain, ...; kwargs...)
    coverage(cases::TestCases; strength, stronger, feasibility_limit,
             explanation_limit) -> Coverage

Which of the combinations a set of test cases should hold it does hold
(contract §1.12–§1.17): every combination of values of every `strength`
parameters, and of every `stronger` group at its strength, that some valid
row contains. Use it to audit a hand-written suite, to check a design built
elsewhere, or to see what an edited space asks of an old result:

```jldoctest; setup = :(using UnitTestDesign)
julia> space = TestSpace(
           (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
           constraints = [
               @require(mode == :exact || solver == :none),
               forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
           ]);

julia> handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
                      (mode = :exact, solver = :lu, tol = 1e-6),
                      (mode = :exact, solver = :none, tol = 1e-6)];

julia> coverage(handwritten, space)
covers 8 of 11 feasible pairs, 3 missing: (mode = :exact, solver = :qr), (mode = :fast, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)
excluded: 3 pairs forbidden, 2 impossible under the constraints

julia> cases = all_pairs(space; must_include = handwritten);   # keep them, add rows for the gaps

julia> coverage(cases)
covers 11 of 11 feasible pairs
excluded: 3 pairs forbidden, 2 impossible under the constraints

julia> coverage(all_triples(space; must_include = cases))   # extend the same rows to triples
covers 5 of 5 feasible triples
excluded: 7 triples forbidden
```

`cases` is any collection of rows, read once: `NamedTuple`s naming every
parameter, or tuples or vectors with one value per parameter in parameter
order (as a positional call such as `coverage(cases, [1, 2], [:a, :b])`
writes them), or a [`TestCases`](@ref). Values match the domain by identity:
`1` and `1.0` are different values (§2.1, §2.11). A row that is partial,
names an unknown parameter, or holds a value outside its domain is an
`ArgumentError` naming the row and the parameter (§1.13). The space comes in
the forms [`covering`](@ref) takes; `constraints =` builds it from named
domains.

The measurement uses the rows alone, never how they were made (§1.12):

- A row that breaks a rule, or holds more than one [`Invalid`](@ref) value,
  is accepted, counts for nothing, and is listed in `rejected` with the rules
  it breaks (§1.14). Repeated rows count once (§1.11).
- A combination some valid row holds is covered; no search is needed for it
  (§1.10). Every other combination is classified as for generation: missing
  (some valid row could hold it), excluded (`:forbidden` directly by rules, or
  `:implied` by rules together, with the rules named, §1.4), or unknown when
  its feasibility search reaches `feasibility_limit` (§1.7).
- Ordinary and negative targets are measured separately: rows with one
  `Invalid` value cover only the negative targets of §6, whatever their other
  values, and ordinary rows only the ordinary ones (§5.9–§5.11).

The result is a [`Coverage`](@ref), whose `ordinary` and `negative` parts
hold the counts, the `missing`, `excluded` and `unknown` targets in target
order, a breakdown per group, and the rejected rows. It prints the covered
count and the missing targets. When a search ran out, it prints the known
counts as bounds and lists the unresolved targets, with no percentage and no
claim of completeness (§3.10); retry with a larger `feasibility_limit`.
`explanation_limit` only bounds the search for which rules cause an implied
exclusion (§3.13); running out leaves that attribution unresolved, never the
coverage. [`iscomplete`](@ref) says whether nothing is missing or unknown.

For a `TestCases`, `coverage(cases)` measures against the result's space at
its strength and `stronger` groups (§1.12). An excursion or a full factorial
has no strength: pass one, as in `coverage(cases; strength = 2)`. An
explicit `strength` replaces the result's and keeps its `stronger` groups; a
stored group whose strength is below the requested strength is an
`ArgumentError` naming the group, since a group never asks for less than the
base (§11.6). An explicit `stronger` replaces the stored groups, and
`stronger = []` drops them.

Coverage describes the rows given. To measure the cases that ran or passed,
pass those rows (§1.17).

See also [`missing_interactions`](@ref), [`iscomplete`](@ref).
"""
function coverage(cases, input...; strength = 2, stronger = [], constraints = nothing,
                  feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    # Keyword values are checked before the space is built or anything searched.
    strength = _check_integer(:strength, strength, 1, "§11.1")
    _check_limits(feasibility_limit, explanation_limit)
    isempty(input) && throw(ArgumentError(
        "coverage needs the space the rows belong to: coverage(cases, space), with $_INPUT_FORMS; " *
        "only a TestCases carries its own space"))
    space, _ = _space(:coverage, input, constraints)
    cases isa TestSpace && throw(ArgumentError(
        "coverage takes the rows first and the space second: coverage(cases, space)"))
    rows = _row_list(cases; what = "coverage takes a collection of rows", section = "§1.12",
                     fix = row -> "coverage([$(repr(row))], space)")
    return _coverage(rows, space; strength, stronger, feasibility_limit, explanation_limit)
end

function coverage(cases::TestCases; strength = nothing, stronger = nothing,
                  feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    _check_limits(feasibility_limit, explanation_limit)
    strength, stronger = _measured_request(cases, strength, stronger)
    return _coverage(collect(cases), cases.space; strength, stronger, feasibility_limit,
                     explanation_limit)
end

"""
    _measured_request(cases::TestCases, strength, stronger) -> (strength, stronger)

The strength and groups at which to measure a result (contract §1.12): the
result's own strength unless the caller passes `strength`, and the result's
`stronger` groups unless the caller passes `stronger` (`[]` drops them). A
stored group below a requested strength is an `ArgumentError` naming it. A
result with strength 0 (an excursion or a full factorial) needs an explicit
`strength`.
"""
function _measured_request(cases::TestCases, strength, stronger)
    if strength === nothing
        cases.strength == 0 && throw(ArgumentError(
            "coverage(cases) measures at the result's strength, but $(_strategy_phrase(cases)) has " *
            "none; pass the strength to measure, such as coverage(cases; strength = 2) (contract §1.12)"))
        strength = cases.strength
    else
        strength = _check_integer(:strength, strength, 1, "§11.1")
    end
    stronger === nothing || return strength, stronger
    for (names, s) in cases.stronger
        s >= strength || throw(ArgumentError(
            "stronger group ($(join(names, ", "))) => $s is below the requested strength $strength; " *
            "pass stronger = [] to drop it (contract §1.12)"))
    end
    return strength, cases.stronger
end

_strategy_phrase(cases::TestCases) =
    cases.strategy === :excursion ? "an excursion" :
    cases.strategy === :full_factorial ? "a full factorial" : "this $(cases.strategy) result"

"""
Use when you want the list of feasible combinations your cases miss, to add
cases for them; it throws rather than return a list that a search limit left
uncertain.

    missing_interactions(cases, space; strength = 2, stronger = [],
                         feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    missing_interactions(cases::TestCases; kwargs...)

The feasible combinations that no valid row of `cases` holds, in target
order: `coverage(cases, space; ...)`'s missing targets, ordinary then
negative (contract §3.11). It takes the arguments of [`coverage`](@ref).

An empty list means nothing is missing: it is returned only when every
target was resolved. If a feasibility search reached `feasibility_limit`,
some combination could be feasible and missing without anyone knowing, so
`missing_interactions` throws a [`ResourceLimitError`](@ref) instead; call
`coverage` with the same arguments for the missing targets known so far and
the unresolved ones, or raise the limit.

With the space and rows of [`coverage`](@ref)'s example:

```jldoctest; setup = :(using UnitTestDesign)
julia> space = TestSpace(
           (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
           constraints = [
               @require(mode == :exact || solver == :none),
               forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
           ]);

julia> handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
                      (mode = :exact, solver = :lu, tol = 1e-6),
                      (mode = :exact, solver = :none, tol = 1e-6)];

julia> missing_interactions(handwritten, space)
3-element Vector{NamedTuple}:
 (mode = :exact, solver = :qr)
 (mode = :fast, tol = 1.0e-6)
 (solver = :qr, tol = 1.0e-6)
```
"""
function missing_interactions(cases, input...; strength = 2, stronger = [], constraints = nothing,
                              feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    c = coverage(cases, input...; strength, stronger, constraints, feasibility_limit, explanation_limit)
    return _resolved_missing(c)
end

function missing_interactions(cases::TestCases; strength = nothing, stronger = nothing,
                              feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    return _resolved_missing(coverage(cases; strength, stronger, feasibility_limit, explanation_limit))
end

function _resolved_missing(c::Coverage)
    unresolved = length(c.ordinary.unknown) + length(c.negative.unknown)
    known = length(c.ordinary.missing) + length(c.negative.missing)
    unresolved == 0 || throw(ResourceLimitError(
        "resolving $(_plural(unresolved, "target")) for missing_interactions (coverage with the same " *
        "arguments lists the $known missing known so far and the $unresolved unresolved)",
        c.limits.feasibility_limit, :feasibility_limit))
    return NamedTuple[c.ordinary.missing; c.negative.missing]
end


## Display (contract §3.10, §5.10)

const _SHOWN_TARGETS = 10   # targets listed before "and N more"
const _SHOWN_ROWS = 10      # rejected rows listed before "and N more"

"The noun for the request's targets: pair, triple, or combination, as `TestCases` says."
_coverage_noun(c::Coverage) = _target_noun(unique([c.strength; [s for (_, s) in c.stronger]]))

function _print_targets(io::IO, targets::AbstractVector)
    k = min(length(targets), _SHOWN_TARGETS)
    print(io, join((_shown(io, t) for t in targets[1:k]), ", "))
    length(targets) > k && print(io, ", and ", length(targets) - k, " more")
    return nothing
end

# "covers 9 of 11 feasible pairs, 2 missing: …", or with unknown targets
# "covers 9 of at least 9 feasible pairs; 3 pairs unresolved (feasibility_limit
# = 1): …; no exact percentage". Never a percentage, and never "complete".
function _print_part(io::IO, part::CoveragePart, noun::AbstractString, limit; lists::Bool)
    resolved = isempty(part.unknown)
    print(io, "covers ", part.covered, " of ", resolved ? "" : "at least ",
          _plural(part.feasible, "feasible " * noun))
    if !isempty(part.missing)
        print(io, ", ", length(part.missing), " missing")
        lists && (print(io, ": "); _print_targets(io, part.missing))
    end
    if !resolved
        print(io, "; ", _plural(length(part.unknown), noun), " unresolved (feasibility_limit",
              limit === nothing ? " reached)" : " = " * _grouped(limit) * ")")
        lists && (print(io, ": "); _print_targets(io, part.unknown))
        print(io, "; no exact percentage")
    end
    return nothing
end

function _rejection_phrase(space::TestSpace, r::_Rejected)
    r.reason === :multiple_invalid && return "row $(r.index) has more than one Invalid value"
    labels = [rule_label(space, k) for k in r.rules]
    length(r.rules) == 1 && return "row $(r.index) breaks " * _rule_phrase(only(r.rules), only(labels))
    return "row $(r.index) breaks " * _rule_numbers(r.rules) * " " * _rule_details(r.rules, labels)
end

function Base.show(io::IO, c::Coverage)
    noun = _coverage_noun(c)
    _print_part(io, c.ordinary, noun, c.limits.feasibility_limit; lists = false)
    if _has_invalid(c.space)
        print(io, "; negative: ")
        _print_part(io, c.negative, noun, c.limits.feasibility_limit; lists = false)
    end
    return nothing
end

function Base.show(io::IO, ::MIME"text/plain", c::Coverage)
    noun = _coverage_noun(c)
    limit = c.limits.feasibility_limit
    _print_part(io, c.ordinary, noun, limit; lists = true)
    if _has_invalid(c.space)
        print(io, "\nnegative: ")
        _print_part(io, c.negative, noun, limit; lists = true)
    end
    excluded = String[]
    isempty(c.ordinary.excluded) || push!(excluded, _excluded_counts(c.ordinary.excluded))
    isempty(c.negative.excluded) || push!(excluded, "negative: " * _excluded_counts(c.negative.excluded))
    isempty(excluded) || print(io, "\nexcluded: ", join(excluded, "; "))
    duplicates = c.ordinary.duplicates + c.negative.duplicates
    duplicates > 0 && print(io, "\n", _plural(duplicates, "duplicate row"), " counted once")
    rejected = sort!([c.ordinary.rejected; c.negative.rejected]; by = r -> r.index)
    if !isempty(rejected)
        k = min(length(rejected), _SHOWN_ROWS)
        print(io, "\n", _plural(length(rejected), "row"), " rejected: ",
              join((_rejection_phrase(c.space, r) for r in rejected[1:k]), "; "))
        length(rejected) > k && print(io, "; and ", length(rejected) - k, " more")
    end
    return nothing
end

# A part alone does not know its request or limits, so it says "targets".
Base.show(io::IO, part::CoveragePart) = _print_part(io, part, "target", nothing; lists = false)
