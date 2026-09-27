# Measurement: `coverage` and `missing_interactions` (plan Phase 5 steps 1,
# 2 and 5; contract §1.8–§1.17, §3.10, §3.11, §5.9–§5.11, §6).
#
# Coverage works in space value indices (space.jl) and reads nothing a
# generator recorded (§1.12). A row becomes one value index per parameter; a
# target is a partial index vector over one support (`_supports`, request.jl).
# A target that a valid row contains is feasible, with that row as its
# witness, and is never searched (§1.10): each support gets the set of the
# valid rows' projections onto it, and only the targets missing from that set
# are classified, through the Phase 2 machinery (`explain_partial` on the
# `Feasibility` of the target's row kind, from one `FeasibilityContext` per
# call, §3.5). Ordinary and negative targets are measured separately, each
# against its own kind of row (§5.9–§5.11).


## The result

"One `stronger` group's (or the base group's) share of a coverage part."
const _GroupCounts = NamedTuple{
    (:names, :strength, :covered, :feasible, :missing_count, :excluded_count, :unknown_count),
    Tuple{Tuple{Vararg{Symbol}}, Int, Int, Int, Int, Int, Int}}

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
    Coverage

What [`coverage`](@ref) measured: which of the requested combinations the
supplied rows contain (contract §1.12–§1.17). Fields:

- `ordinary`, `negative`: a `CoveragePart` each (see its docstring), measured
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
    iscomplete(c::Coverage) -> Bool

`true` when every feasible target, ordinary and negative, is covered and no
target is unresolved (contract §1.16). An unknown target makes it `false`:
coverage is never claimed complete under an exhausted limit (§1.7, §3.10).
Rejected rows do not change it; they are listed in the result (§1.14).
"""
iscomplete(c::Coverage) = all(p -> isempty(p.missing) && isempty(p.unknown), (c.ordinary, c.negative))


## Reading the rows (contract §1.13, §1.14)

"""
    _coverage_rows(cases) -> Vector

The caller's cases as a `Vector`, read once with `collect`, so an iterator
that can be read only once gives all its rows. A single row, or the space in
the rows' place, is an `ArgumentError` saying how to write the call.
"""
function _coverage_rows(cases)
    cases isa TestSpace && throw(ArgumentError(
        "coverage takes the rows first and the space second: coverage(cases, space)"))
    cases isa NamedTuple && throw(ArgumentError(
        "coverage takes a collection of rows; wrap a single row in a vector: " *
        "coverage([$(repr(cases))], space)"))
    rows = applicable(iterate, cases) ? collect(cases) : nothing
    rows isa AbstractVector || throw(ArgumentError(
        "coverage takes a collection of rows, such as a vector of NamedTuples or tuples; " *
        "got $(repr(cases)) (contract §1.12)"))
    if !isempty(rows) && !any(_is_row, rows)
        throw(ArgumentError(
            "coverage takes a collection of rows; wrap a single row in a vector: " *
            "coverage([$(repr(cases))], space)"))
    end
    return rows
end

"""
    _coverage_row(space, row, k) -> Vector{Int}

Row `k` as one value index per parameter (contract §1.13, §2.11). A
`NamedTuple` names every parameter, in any order; a `Tuple` or vector lists
one value per parameter in parameter order. Values match by identity, and a
[`Partition`](@ref) may be written by its name. Anything else is an
`ArgumentError` naming the row and the parameter.
"""
function _coverage_row(space::TestSpace, row, k::Integer)
    n = length(space.names)
    if row isa Union{Tuple, AbstractVector}
        length(row) == n || throw(ArgumentError(
            "coverage row $k has $(length(row)) values; the space has $n parameters " *
            "($(join(space.names, ", "))), and a row given to coverage is complete (contract §1.13)"))
        row = Tuple(row)
    elseif !(row isa NamedTuple)
        throw(ArgumentError(
            "coverage row $k is a $(typeof(row)); a row is a NamedTuple, or a tuple or vector " *
            "with one value per parameter (contract §1.13)"))
    end
    idx = try
        case_indices(space, row)
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError("coverage row $k: " * err.msg))   # §1.13 names the row
    end
    unset = space.names[idx .== 0]
    isempty(unset) || throw(ArgumentError(
        "coverage row $k, $(repr(row)), has no value for " *
        "$(join(("`$u`" for u in unset), ", ", " and ")); a row given to coverage names every " *
        "parameter (contract §1.13)"))
    return idx
end

"""
    _read_rows(context, rows) -> (kept, duplicates, rejected, slots)

Sort the rows by kind and validity (contract §1.11, §1.14, §5.3–§5.7): `kept`
holds the distinct valid ordinary rows and the distinct valid negative rows,
in first-seen order; `duplicates` counts repeats of each kind; `rejected`
lists, per kind, the rows that break an applicable rule (judged under
`active_rules`, so a negative row at `p` skips every rule that reads `p`) and
the rows with more than one `Invalid` value (negative kind). `slots[k]` is
the position in `kept[1]` of row `k` when it is the first appearance of a
valid ordinary row, else 0: the prefix curve of `report` reads it. Rules are
checked through the call's `FeasibilityContext`, so a lazy rule's verdicts
are memoized for the call and no longer (§3.5, §12.19).
"""
function _read_rows(context::FeasibilityContext, rows::AbstractVector)
    space = context.space
    kept = (Vector{Int}[], Vector{Int}[])
    duplicates = [0, 0]
    rejected = (_Rejected[], _Rejected[])
    slots = zeros(Int, length(rows))
    seen = Set{Vector{Int}}()
    for (k, row) in enumerate(rows)
        idx = _coverage_row(space, row, k)
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
            part == 1 && (slots[k] = length(kept[1]))
        end
    end
    return kept, duplicates, rejected, slots
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
adds to the rows before it, which is the prefix curve of `report`.
"""
function _projections(table::Matrix{Int}, support::Vector{Int}, radix::Vector{Int},
                      codes::Vector{Int}, firsts::Union{Nothing, Vector{Int}} = nothing)
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
            firsts === nothing || (firsts[j] += 1)
        end
        return marks
    end
    set = Set{Vector{Int}}()
    for j in axes(table, 1)
        key = table[j, support]
        key in set && continue
        push!(set, key)
        firsts === nothing || (firsts[j] += 1)
    end
    return set
end

_contains(marks::BitVector, t, support, radix) = marks[_code(t, support, radix) + 1]
_contains(set::Set{Vector{Int}}, t, support, radix) = t[support] in set

"""
    _Lists

The targets one part lists, in the order they are met (target order, §9.7).
"""
struct _Lists
    missing::Vector{NamedTuple}
    excluded::Vector{Exclusion}
    unknown::Vector{NamedTuple}
end

_Lists() = _Lists(NamedTuple[], Exclusion[], NamedTuple[])

"""
    _classify!(lists, context, t, explanation_limit) -> Symbol

Decide one target that no valid row contains, `t` a full-width index vector,
with `explain_partial` on the `Feasibility` of its row kind (§5.5, §6.2), and
record it: allowed or completable is `:missing`; forbidden or infeasible is
`:excluded`, with its rules in the space's numbering and their labels, the
deletion search bounded by `explanation_limit` (§1.4, §3.13–§3.16); a search
at its limit is `:unknown` (§1.7). `t` is not retained.
"""
function _classify!(lists::_Lists, context::FeasibilityContext, t::Vector{Int}, explanation_limit::Int)
    space = context.space
    f, active = feasibility_for(context, t)
    e = explain_partial(f, t; explanation_limit)
    if e.outcome === :allowed || e.outcome === :completable
        push!(lists.missing, from_indices(space, t))
        return :missing
    elseif e.outcome === :unknown
        push!(lists.unknown, from_indices(space, t))
        return :unknown
    end
    rules = active[e.rules]
    push!(lists.excluded, Exclusion(from_indices(space, t),
        e.outcome === :forbidden ? :forbidden : :implied, rules, [rule_label(space, k) for k in rules],
        e.minimal, _limit_pair(e.limit, context.feasibility_limit, explanation_limit)))
    return :excluded
end

"""
    _measure_block!(lists, context, support, rest, t, seen, radix, explanation_limit)
        -> (covered, missing, excluded, unknown)

Measure the targets that assign `t`'s fixed entries (an invalid value, for a
negative block, or none) and every combination of ordinary values of the
parameters `rest`, the first varying fastest (§1.8, §6.1). A target found in
`seen`, the rows' projections onto `support`, is covered without a search
(§1.10); any other is classified. `t` is a reused buffer: `rest` is cleared
again on return.
"""
function _measure_block!(lists::_Lists, context::FeasibilityContext, support::Vector{Int},
                         rest::Vector{Int}, t::Vector{Int}, seen, radix::Vector{Int},
                         explanation_limit::Int)
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
            status = _classify!(lists, context, t, explanation_limit)
            status === :missing ? (m += 1) : status === :excluded ? (x += 1) : (u += 1)
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
    _measure_support!(lists, context, support, kind, table, codes, radix, explanation_limit, firsts)
        -> (covered, missing, excluded, unknown)

The targets of `kind` on one support, in a fixed order (contract §9.7):

- `:ordinary` (§1.8): every assignment of ordinary values, the first
  parameter varying fastest, as `TargetList` orders engine positions.
- `:negative` (§6.1, §6.4, §6.5): for each parameter `p` of the support, in
  order, each invalid value `v` of `p`, in domain order, every assignment of
  ordinary values to the rest of the support, the first parameter fastest.
  At strength 1 the rest is empty and the target is `(p = v)` alone.
"""
function _measure_support!(lists::_Lists, context::FeasibilityContext, support::Vector{Int},
                           kind::Symbol, table::Matrix{Int}, codes::Vector{Int}, radix::Vector{Int},
                           explanation_limit::Int, firsts)
    space = context.space
    t = zeros(Int, length(space.names))
    kind === :negative && all(p -> isempty(space.invalid[p]), support) && return (0, 0, 0, 0)
    # Only ordinary rows have firsts: a negative row's projection onto a
    # support without its invalid parameter is no negative target.
    seen = _projections(table, support, radix, codes, kind === :ordinary ? firsts : nothing)
    kind === :ordinary &&
        return _measure_block!(lists, context, support, support, t, seen, radix, explanation_limit)
    total = (0, 0, 0, 0)
    for p in support, v in space.invalid[p]
        t[p] = v
        block = _measure_block!(lists, context, support, filter(!=(p), support), t, seen, radix,
                                explanation_limit)
        total = total .+ block
        t[p] = 0
    end
    return total
end

"""
    _measure_part(context, groups, supports, rows, kind; explanation_limit, duplicates, rejected,
                  firsts = nothing) -> CoveragePart

Measure the targets of `kind` (`:ordinary` or `:negative`) against `rows`,
the distinct valid rows of that kind, support by support, and sum each
group's supports for its breakdown (§1.15). For the ordinary part, `firsts`,
a vector of zeros aligned with `rows`, receives the number of targets each
row is the first to cover (see `_projections`).
"""
function _measure_part(context::FeasibilityContext, groups, supports::Vector{Vector{Int}},
                       rows::Vector{Vector{Int}}, kind::Symbol; explanation_limit::Int,
                       duplicates::Int, rejected::Vector{_Rejected}, firsts = nothing)
    space = context.space
    radix = [length(v) for v in space.values]
    lists = _Lists()
    table = Int[r[p] for r in rows, p in eachindex(space.names)]   # cases × parameters
    codes = zeros(Int, length(rows))
    counts = Dict{Vector{Int}, NTuple{4, Int}}()   # support => (covered, missing, excluded, unknown)
    for support in supports
        counts[support] = _measure_support!(lists, context, support, kind, table, codes, radix,
                                            explanation_limit, firsts)
    end
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

"""
    _measure(rows, space; strength, stronger, feasibility_limit, explanation_limit)
        -> (coverage, prefix)

The measurement behind every `coverage` method and `report`. Checks the
request (§11), reads and sorts the rows (§1.13, §1.14), then measures the
ordinary targets (§1.8) and, when the space has `Invalid` values, the
negative targets (§6). The targets are those of `Request(space; strength,
stronger)`, in the same order: `_supports(groups)`, each over its ordinary
values.

`prefix[k]` is the number of ordinary targets the first `k` rows cover, from
the same pass (each row adds the targets it is the first to hold), so
`prefix[end] == coverage.ordinary.covered`.
"""
function _measure(rows::AbstractVector, space::TestSpace; strength, stronger,
                  feasibility_limit, explanation_limit)
    strength = _check_strength(strength, length(space.names))
    groups = _groups(space, strength, stronger)
    context = FeasibilityContext(space; feasibility_limit)
    explanation_limit = _check_limit(:explanation_limit, explanation_limit)
    kept, duplicates, rejected, slots = _read_rows(context, rows)
    supports = _supports(groups)
    firsts = zeros(Int, length(kept[1]))
    ordinary = _measure_part(context, groups, supports, kept[1], :ordinary; explanation_limit,
                             duplicates = duplicates[1], rejected = rejected[1], firsts)
    negative = _measure_part(context, groups, supports, kept[2], :negative; explanation_limit,
                             duplicates = duplicates[2], rejected = rejected[2])
    named = Pair{Tuple{Vararg{Symbol}}, Int}[Tuple(space.names[g]) => s for (g, s) in groups[2:end]]
    c = Coverage(ordinary, negative, space, strength, named,
                 (feasibility_limit = context.feasibility_limit, explanation_limit = explanation_limit))
    return c, cumsum(Int[slot == 0 ? 0 : firsts[slot] for slot in slots])
end

_coverage(rows::AbstractVector, space::TestSpace; kwargs...) = first(_measure(rows, space; kwargs...))


## The public functions

"""
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
    rows = _coverage_rows(cases)
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

_has_invalid(space::TestSpace) = any(!isempty, space.invalid)

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
