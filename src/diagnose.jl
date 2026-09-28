# After the run: `diagnose` and `followups` (plan Phase 6 step 3; contract
# §1.17, §3.9, §3.17, §8.6, §13.1, §14.1). Both are experimental.
#
# `diagnose` is a pure function of the rows and their outcomes. The package
# never runs a test (§14.1); outcomes enter here and nowhere else. It works
# in index space: each row becomes one value index per parameter
# (`case_indices`), so values compare by identity (§2.1), and a combination
# is a partial index vector with 0 for a parameter it leaves out.
#
# `followups` asks the Phase 2 feasibility search for a valid row that holds
# one suspect and no other, once per kind of row that could hold it (ordinary,
# and negative at each invalid value the suspect leaves room for, §5.5).
# Every other suspect becomes a temporary forbidden table, `RuleTable(scope,
# Set([values]))`, for those searches; the space's own tables and its
# lazy-rule memos are shared, never changed (§3.5).


## diagnose

"""
    Suspect

A combination [`diagnose`](@ref) implicates: it appears in at least one
failing case and in no passing case. A hypothesis, not a finding (§8.6).

- `combination::NamedTuple`: its values, in parameter order, as the domain
  stores them (wrappers kept).
- `failures::Int`: the number of failing cases that contain it.
- `passes::Int`: the number of passing cases that contain it. Always 0: a
  combination seen in a passing case is not a suspect. It is kept so that
  every count reads as what it is, "in 3 failures, 0 passes", and no reader
  mistakes a suspect for a combination known to fail.
- `failing::Vector{Int}`: the positions of those failing cases among the
  rows given, ascending.
- `key::Vector{Int}`: the combination in index space, one value index per
  parameter and 0 for a parameter it leaves out (internal).
"""
struct Suspect
    combination::NamedTuple
    failures::Int
    passes::Int
    failing::Vector{Int}
    key::Vector{Int}
end

"""
    Diagnosis

The result of [`diagnose`](@ref). Fields:

- `status::Symbol`: `:ranked` (failing and passing cases were compared; the
  list may be empty), `:no_failures` (nothing failed; no suspects),
  `:all_failed` (every case failed, so no combination is implicated over
  another; no suspects), or `:conflicting` (some case appears more than once
  with different outcomes; those rows are listed in `conflicting` and left
  out, and the rest are compared as for `:ranked`).
- `groups::Vector{Vector{Suspect}}`: the suspects, grouped by the failing
  cases that contain them. The members of a group occur in exactly the same
  cases, so these outcomes cannot tell them apart. Groups are ranked by the
  number of failing cases, most first, then by their representative, the
  group's first and smallest member: fewer values first, then parameter
  order, then domain order. Members follow the same order.
- `suspects::Vector{Suspect}`: every suspect, group by group, in rank order.
- `strength::Int`: the largest combination considered.
- `n_cases::Int`, `n_failed::Int`: the rows given, and how many failed,
  conflicting rows included.
- `failing::Vector{Int}`, `passing::Vector{Int}`: the positions of the
  failing and passing rows compared, conflicting rows left out.
- `conflicting::Vector{Vector{Int}}`: the positions of rows that hold the
  same case with different outcomes, one vector per case.
- `space::TestSpace`: the space the rows belong to, for [`followups`](@ref).
- `rows::Vector{Vector{Int}}`: every row in index space (internal).
"""
struct Diagnosis
    status::Symbol
    groups::Vector{Vector{Suspect}}
    suspects::Vector{Suspect}
    strength::Int
    n_cases::Int
    n_failed::Int
    failing::Vector{Int}
    passing::Vector{Int}
    conflicting::Vector{Vector{Int}}
    space::TestSpace
    rows::Vector{Vector{Int}}
end

"""
Use when some cases failed and you want ranked hypotheses about which values, or
combinations of values, the failures have in common. Experimental: the ranking
is a set of hypotheses, not proof.

    diagnose(cases, passed::AbstractVector{Bool}; strength = nothing, space = nothing) -> Diagnosis

!!! warning "Experimental"
    The ranking is a set of hypotheses, not proof (contract §8.6). Its
    interface may change in a minor release.

`passed[k]` is the outcome of `cases[k]`: `true` for a pass, `false` for a
failure. Collect outcomes however you like (a Test.jl loop, a cluster job, a
spreadsheet); diagnosis is a pure function of the cases and outcomes, and
runs nothing (§14.1).

A *suspect* is a combination of 1 to `strength` values that appears in at
least one failing case and in no passing case. Suspects are ranked by the
number of failing cases that contain them, most first; then smaller
combinations first, since a single value that explains the failures is a
simpler hypothesis than a pair; then by parameter order and domain order,
so the ranking is deterministic. Suspects that occur in exactly the same
failing cases are grouped: these outcomes cannot tell them apart, and only
new cases can. [`followups`](@ref) proposes those cases.

```jldoctest; setup = :(using UnitTestDesign)
julia> space = TestSpace((n = [10, 100, 1000], method = [:newton, :bicg, :gmres],
                          tol = [1e-3, 1e-6], sparse = [false, true]));

julia> cases = all_pairs(space);

julia> passed = [!(c.method == :newton && c.sparse) for c in cases];   # the bug

julia> diagnose(cases, passed)
2 failures of 10 cases; 3 suspects in 3 groups (hypotheses, not proof)
1. (method = :newton, sparse = true) — in 2 of 2 failures
2. (n = 1000, method = :newton) — in 1 of 2 failures
3. (n = 100, sparse = true) — in 1 of 2 failures
```

The true cause ranks first. The other two suspects appeared only in failing
cases, so nothing yet says whether they work; `followups` finds a case for
each that holds it and no other suspect.

Read the ranking as hypotheses (§8.6):

- Several faults at once split the failures between their causes, so each
  cause is in fewer failures than all of them, and a combination that
  happens to share failing cases with two faults can rank above both.
- An intermittent failure makes a passing case look innocent when it is
  not; the true cause may then be missing from the list, since a suspect
  must appear in no passing case.
- A fault that needs more values together than `strength` leaves no
  suspect, or only combinations that happen to occur with it. Diagnose
  again at a higher strength.
- A wrong answer and a thrown error are both `false`; diagnose them
  separately if they may have different causes.

Every suspect is unverified by passing cases by definition: each one's
`passes` is 0.

`cases` is a [`TestCases`](@ref) or a vector of rows. For a `TestCases`, the
space is the result's, and `strength` defaults to the result's strength, or
to `min(2, number of parameters)` for an excursion or a full factorial,
which have none. For a vector of rows, pass the space they belong to as
`space` (a [`TestSpace`](@ref)); `strength` then defaults to
`min(2, number of parameters)`. Rows are `NamedTuple`s naming every
parameter, or tuples or vectors in parameter order, and values match the
domain by identity (§2.1). Give the labeled rows, before
`realize`: a drawn value is not in the domain. A positional result's
parameters are named `p1`, `p2`, ….

`length(passed)` must equal the number of cases. Each row is counted once
per appearance, so a case that ran twice and failed twice is in two
failures. The result's `status` says how the comparison went:

- `:no_failures`: nothing failed, so there is nothing to diagnose.
- `:all_failed`: every case failed, so no combination is implicated over
  another; check the setup before suspecting the cases.
- `:conflicting`: some case appears more than once with different outcomes.
  Those rows are listed in `conflicting` and left out of the comparison,
  which proceeds on the rest.
- `:ranked`: failing and passing cases were compared.

Outcomes enter the package here and nowhere else: [`coverage`](@ref)
describes the rows it is given, whatever their outcomes, so to see what the
passing cases covered, pass those rows to it (§1.17).

See [`Diagnosis`](@ref UnitTestDesign.Diagnosis) and
[`Suspect`](@ref UnitTestDesign.Suspect) for the fields.
"""
function diagnose(cases, passed::AbstractVector; strength = nothing, space = nothing)
    rows, space, strength = _diagnosis_input(cases, strength, space)
    outcomes = _outcomes(passed, length(rows))
    idx = [_diagnosis_row(space, row, k) for (k, row) in enumerate(rows)]
    conflicting = _conflicts(idx, outcomes)
    left_out = Set{Int}(k for group in conflicting for k in group)
    failing = [k for k in eachindex(idx) if !outcomes[k] && !(k in left_out)]
    passing = [k for k in eachindex(idx) if outcomes[k] && !(k in left_out)]
    n_failed = count(!, outcomes)
    status = !isempty(conflicting) ? :conflicting :
             n_failed == 0 ? :no_failures :
             n_failed == length(rows) ? :all_failed : :ranked
    groups = isempty(failing) || isempty(passing) ? Vector{Suspect}[] :
             _suspect_groups(space, idx, failing, passing, strength)
    suspects = Suspect[s for g in groups for s in g]
    return Diagnosis(status, groups, suspects, strength, length(rows), n_failed, failing, passing,
                     conflicting, space, idx)
end

"""
    _diagnosis_input(cases, strength, space) -> (rows, space, strength)

The rows, the space, and the strength of a `diagnose` call. A `TestCases`
brings its space and strength (`min(2, n)` when it has none); an explicit
`space` replaces the result's. Other rows need `space`.
"""
function _diagnosis_input(cases, strength, space)
    if cases isa TestCases
        default = cases.strength == 0 ? min(2, length(cases.space.names)) : cases.strength
        rows = cases.cases
        space === nothing && (space = cases.space)
    else
        cases isa TestSpace && throw(ArgumentError(
            "diagnose takes the cases first and their outcomes second: diagnose(cases, passed)"))
        cases isa Union{NamedTuple, Tuple} && throw(ArgumentError(
            "diagnose takes a collection of cases; wrap a single case in a vector: " *
            "diagnose([$(_fit(repr(cases), 60))], passed; space)"))
        rows = applicable(iterate, cases) ? collect(cases) : nothing
        rows isa AbstractVector || throw(ArgumentError(
            "diagnose takes a TestCases or a vector of cases; got $(_fit(repr(cases), 60))"))
        space === nothing && throw(ArgumentError(
            "diagnose needs the space the cases belong to: diagnose(cases, passed; space, strength); " *
            "only a TestCases carries its own space"))
        default = nothing
    end
    space isa TestSpace || throw(ArgumentError(
        "space must be a TestSpace; got $(_fit(repr(space), 60))"))
    n = length(space.names)
    default === nothing && (default = min(2, n))
    strength = strength === nothing ? default : _check_integer(:strength, strength, 1, "§11.1")
    strength <= n || throw(ArgumentError(
        "strength $strength is larger than the number of parameters, $n (contract §11.2)"))
    return rows, space, strength
end

"The outcomes as a `Vector{Bool}`, after checking there is one `Bool` per case."
function _outcomes(passed::AbstractVector, n::Integer)
    length(passed) == n || throw(ArgumentError(
        "diagnose got $(_plural(length(passed), "outcome")) for $(_plural(n, "case")); passed " *
        "needs one outcome per case, in case order"))
    outcomes = Vector{Bool}(undef, n)
    for (k, x) in enumerate(passed)
        x isa Bool || throw(ArgumentError(
            "outcome $k is $(_fit(repr(x), 40)); each outcome is true (passed) or false (failed)"))
        outcomes[k] = x
    end
    return outcomes
end

"""
    _diagnosis_row(space, row, k) -> Vector{Int}

Case `k` as one value index per parameter. A `NamedTuple` names every
parameter; a `Tuple` or vector lists them in order. Values match by identity
and a [`Partition`](@ref) may be written by its name (§2.11). Anything else
is an `ArgumentError` naming the case.
"""
function _diagnosis_row(space::TestSpace, row, k::Integer)
    n = length(space.names)
    if row isa Union{Tuple, AbstractVector}
        length(row) == n || throw(ArgumentError(
            "diagnose case $k has $(length(row)) values; the space has $n parameters " *
            "($(join(space.names, ", "))), and a case is complete"))
        row = Tuple(row)
    elseif !(row isa NamedTuple)
        throw(ArgumentError(
            "diagnose case $k is a $(typeof(row)); a case is a NamedTuple, or a tuple or vector " *
            "with one value per parameter"))
    end
    idx = try
        case_indices(space, row)
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError("diagnose case $k: " * err.msg))
    end
    unset = space.names[idx .== 0]
    isempty(unset) || throw(ArgumentError(
        "diagnose case $k, $(_fit(repr(row), 60)), has no value for " *
        "$(join(("`$u`" for u in unset), ", ", " and ")); a case names every parameter"))
    return idx
end

"The rows that repeat one case with different outcomes, one ascending vector per case, by first row."
function _conflicts(idx::Vector{Vector{Int}}, outcomes::Vector{Bool})
    rows = Dict{Vector{Int}, Vector{Int}}()
    order = Vector{Int}[]
    for (k, r) in enumerate(idx)
        group = get!(rows, r) do
            push!(order, r)
            Int[]
        end
        push!(group, k)
    end
    return [rows[r] for r in order
            if any(k -> outcomes[k], rows[r]) && any(k -> !outcomes[k], rows[r])]
end

"""
    _suspect_groups(space, idx, failing, passing, strength) -> Vector{Vector{Suspect}}

Every combination of 1 to `strength` values that some row of `failing`
holds and no row of `passing` does, grouped by the failing rows that hold
it, and ranked (see [`Diagnosis`](@ref UnitTestDesign.Diagnosis)).
"""
function _suspect_groups(space::TestSpace, idx, failing, passing, strength::Int)
    n = length(space.names)
    found = Dict{Vector{Int}, Vector{Int}}()
    for k in failing, s in 1:strength, support in combinations(1:n, s)
        key = zeros(Int, n)
        key[support] = idx[k][support]
        push!(get!(() -> Int[], found, key), k)
    end
    probe = zeros(Int, n)
    for k in passing, s in 1:strength, support in combinations(1:n, s)
        fill!(probe, 0)
        probe[support] = idx[k][support]
        delete!(found, probe)
    end
    rank(key, failing) = (-length(failing), count(!=(0), key), findall(!=(0), key), filter(!=(0), key))
    keys_ranked = sort!(collect(keys(found)); by = key -> rank(key, found[key]))
    groups = Dict{Vector{Int}, Vector{Suspect}}()
    ranked = Vector{Suspect}[]
    for key in keys_ranked
        failing = found[key]
        s = Suspect(from_indices(space, key), length(failing), 0, failing, key)
        group = get!(groups, failing) do
            push!(ranked, Suspect[])
            last(ranked)
        end
        push!(group, s)
    end
    return ranked
end


## Display

"`x` printed in full, as the domain stores it: no `:compact`, no omitted type information."
_exact(io::IO, x) = sprint(show, x; context = IOContext(io, :typeinfo => Any, :compact => false))

"`items` joined as '(a), (b) and (c)', listing at most `limit` and counting the rest."
function _listed(items::AbstractVector{String}; limit::Integer = 3, conjunction = " and ")
    length(items) <= limit && return join(items, ", ", conjunction)
    return join(items[1:limit], ", ") * ", " * strip(conjunction) * " $(length(items) - limit) more"
end

_rows_phrase(rows) = (length(rows) == 1 ? "case " : "cases ") * join(rows, ", ", " and ")

# The clause after "N failures of M cases; ".
function _diagnosis_clause(d::Diagnosis)
    outside = d.status === :conflicting ? " outside the conflicting cases" : ""
    if isempty(d.failing)
        return d.status === :conflicting ? "no failure$outside; nothing else to diagnose" :
                                           "nothing to diagnose"
    elseif isempty(d.passing)
        return (isempty(outside) ? "every case failed" : "every case$outside failed") *
               "; no combination is implicated over another; check the setup"
    elseif isempty(d.groups)
        what = d.strength == 1 ? "every value" : "every combination of up to $(d.strength) values"
        return "no suspects: $what in a failing case also appears in a passing case; the fault " *
               "may need more values together (diagnose at a higher strength) or fail intermittently"
    end
    return string(_plural(length(d.suspects), "suspect"), " in ", _plural(length(d.groups), "group"),
                  " (hypotheses, not proof)")
end

function _print_diagnosis_summary(io::IO, d::Diagnosis)
    print(io, _plural(d.n_failed, "failure"), " of ", _plural(d.n_cases, "case"), "; ",
          _diagnosis_clause(d))
    return nothing
end

const _SHOWN_GROUPS = 10   # groups listed before "and N more groups"

Base.show(io::IO, d::Diagnosis) = _print_diagnosis_summary(io, d)

function Base.show(io::IO, ::MIME"text/plain", d::Diagnosis)
    _print_diagnosis_summary(io, d)
    for rows in d.conflicting
        print(io, "\n", _rows_phrase(rows), " hold the same case with different outcomes; ",
              "left out of the analysis")
    end
    total = length(d.failing)
    for (j, group) in enumerate(d.groups[1:min(end, _SHOWN_GROUPS)])
        representative = first(group)
        print(io, "\n", j, ". ", _exact(io, representative.combination), " — in ",
              representative.failures, " of ", total, " failure", total == 1 ? "" : "s")
        if length(group) > 1
            print(io, " — indistinguishable from ",
                  _listed([_exact(io, s.combination) for s in group[2:end]]))
        end
    end
    hidden = length(d.groups) - _SHOWN_GROUPS
    hidden > 0 && print(io, "\nand ", _plural(hidden, "more group"), "; see the groups field")
    return nothing
end


## followups

"""
    Followup

One suspect's follow-up from [`followups`](@ref). Fields:

- `suspect::NamedTuple`: the suspect's combination.
- `status::Symbol`: `:found`, `:indistinguishable`, `:inseparable`, or
  `:unknown` (see `followups`).
- `case`: for `:found`, a valid case holding the suspect and no other
  suspect, as a `NamedTuple` naming every parameter; otherwise `nothing`.
- `kind::Symbol`: for `:found`, the kind of `case`: `:ordinary`, or
  `:negative` when it holds one [`Invalid`](@ref) value and is valid under
  the negative-row policy (§5.3, §5.5). `:none` otherwise.
- `from::Int`, `changes::Int`: for `:found`, the failing case (its position
  among the rows diagnosed) that `case` is closest to, and how many
  parameters differ from it; 0 changes means that failing case already
  holds this suspect and no other. 0 and -1 otherwise.
- `others::Vector{NamedTuple}`: for `:indistinguishable`, the suspects this
  one contains; for `:inseparable`, the other suspects in the proof, of
  which every valid case holding this one holds at least one. Otherwise
  empty.
- `rules::Vector{Int}`, `labels::Vector{String}`: for `:inseparable`, the
  space's rules in the proof, as positions in its `constraints`, and their
  labels.
- `minimal::Symbol`: for `:inseparable`, `:verified` when each rule and
  suspect in the proof was shown to be needed for the kind of case whose
  search it is part of, `:unresolved` when a limit stopped that check (the
  proof still stands, §3.15), and `:not_applicable` otherwise.
- `limit`: `keyword => value` for the limit that made the status `:unknown`
  or left an explanation `:unresolved`; otherwise `nothing`.
- `searched::Vector{NamedTuple}`: the kinds of case searched, in the order
  searched: `NamedTuple()` for ordinary cases, and `(p = v,)` for negative
  cases with the invalid value `v` at `p`. For `:inseparable`, every kind
  that could hold the suspect, each proven to hold no isolating case. Empty
  for `:indistinguishable` and for a suspect with two `Invalid` values.
"""
struct Followup
    suspect::NamedTuple
    status::Symbol
    case::Union{Nothing, NamedTuple}
    kind::Symbol
    from::Int
    changes::Int
    others::Vector{NamedTuple}
    rules::Vector{Int}
    labels::Vector{String}
    minimal::Symbol
    limit::Union{Nothing, Pair{Symbol, Int}}
    searched::Vector{NamedTuple}
end

"A `Followup` with no case: every field but those given takes its empty value."
_no_case(suspect::NamedTuple, status::Symbol; others = NamedTuple[], rules = Int[], labels = String[],
         minimal = :not_applicable, limit = nothing, searched = NamedTuple[]) =
    Followup(suspect, status, nothing, :none, 0, -1, others, rules, labels, minimal, limit, searched)

"Failing cases each suspect's `:nearest` search starts from, at most."
const _FOLLOWUP_STARTS = 5

"""
Use when [`diagnose`](@ref) has ranked suspects and you want the next cases to
run: for each suspect it searches for a valid case that holds that suspect and
no other, and says when no such case exists or the search ran out. Experimental.

    followups(d::Diagnosis; feasibility_limit = 1_000_000, explanation_limit = 1_000_000,
              prefer = :nearest) -> Vector{Followup}

!!! warning "Experimental"
    Follow-up cases test hypotheses; they carry no minimum-distance
    guarantee (contract §8.6). The interface may change in a minor release.

For each suspect, `followups` searches for a valid case that holds it and no
other suspect, so that the case's outcome speaks to that suspect alone. Such
a case need not exist, and a search may reach its limit first, so isolation
is not guaranteed: the status says which. The result has one
[`Followup`](@ref UnitTestDesign.Followup) per suspect, in the diagnosis's
rank order, and each has a `status`:

- `:found`: `case` is such a case, a `NamedTuple` naming every parameter
  (for a positional result, `Tuple(f.case)` is the positional form), and
  `kind` says whether it is `:ordinary` or `:negative`. A negative case
  holds an [`Invalid`](@ref) value, so run it as the negative test it is.
- `:indistinguishable`: the suspect contains another suspect, listed in
  `others`, so every case that holds it holds that one too. No case can
  isolate it, whatever the rules; this is a matter of construction, not a
  search. When the two also fail in the same cases, as a value and a pair
  that contains it can, the outcomes so far cannot tell them apart either.
  The smaller suspect's follow-up is the case to run.
- `:inseparable`: proven by exhausted searches: under the space's rules, no
  valid case of any kind, ordinary or negative, holds the suspect without
  another suspect. `searched` lists the kinds of case proven. `others`
  lists the suspects in the proof and `rules` and `labels` the space's
  rules, found by the deletion search of `explain` (§3.13–§3.16), so the
  pair of them is a sufficient reason, and `minimal` says whether each part
  was verified necessary. With no `others`, no valid case holds the suspect
  at all: the failing cases broke the rules.
- `:unknown`: the search reached `feasibility_limit` before deciding
  (§3.17). Retry with a larger limit.

```jldoctest; setup = :(using UnitTestDesign)
julia> space = TestSpace((n = [10, 100, 1000], method = [:newton, :bicg, :gmres],
                          tol = [1e-3, 1e-6], sparse = [false, true]));

julia> cases = all_pairs(space);

julia> d = diagnose(cases, [!(c.method == :newton && c.sparse) for c in cases]);

julia> followups(d)
3-element Vector{UnitTestDesign.Followup}:
 (method = :newton, sparse = true): found (n = 10, method = :newton, tol = 0.001, sparse = true), 1 change from case 7
 (n = 1000, method = :newton): found (n = 1000, method = :newton, tol = 0.001, sparse = false), 1 change from case 7
 (n = 100, sparse = true): found (n = 100, method = :bicg, tol = 1.0e-6, sparse = true), 1 change from case 10
```

Each search is the witness search of `explain`, over the space's rules plus
one temporary forbidden combination per other suspect. Those isolation
conditions apply to every case, including one whose invalid value is at a
parameter they name (§3.17). A case is valid under its own kind's rules
(§5.3–§5.5), so every kind that could hold the suspect is searched:

- A suspect with no [`Invalid`](@ref) value: ordinary cases first, then,
  for each parameter the suspect leaves out and each invalid value of that
  parameter, in parameter and domain order, negative cases with that value,
  where the rules that read its parameter do not apply (§5.5). A rule that
  keeps the suspect out of every ordinary case does not make it
  inseparable when a negative case holds it alone.
- A suspect with one `Invalid` value: negative cases with that value.
- A suspect with two is `:inseparable`, since no valid case holds two
  (§5.7).

With `prefer = :nearest`, each search starts from a failing case that holds
the suspect: each parameter tries that case's value first, so the case
found tends to change few of its values. It starts in turn from each of the
first five such failing cases, for each kind of case, and keeps the case
with the fewest changes; on a tie, the kind searched first, so an ordinary
case before a negative one. This is a heuristic with no minimum-distance
guarantee (§8.6). With `prefer = :domain`, values are tried in domain order,
and the first kind with a case gives it, ordinary before negative. Either
way `from` is the failing case that the case found is closest to, and
`changes` the number of parameters that differ from it.

`feasibility_limit` bounds each search (§3.3); `explanation_limit` bounds
the deletion search that names an `:inseparable` suspect's reasons, and
running out leaves the reasons `:unresolved`, never the status (§3.15).
"""
function followups(d::Diagnosis; feasibility_limit = 1_000_000, explanation_limit = 1_000_000,
                   prefer = :nearest)
    _check_limit(:feasibility_limit, feasibility_limit)
    _check_limit(:explanation_limit, explanation_limit)
    prefer in (:nearest, :domain) || throw(ArgumentError(
        "prefer is :nearest (start from a failing case) or :domain (domain order); got $(repr(prefer))"))
    space = d.space
    memos = rule_memos(space.tables)
    isolation = RuleTable[_isolation_table(s.key) for s in d.suspects]
    limits = (Int(feasibility_limit), Int(explanation_limit))
    return Followup[_followup(d, j, isolation, memos, limits, prefer) for j in eachindex(d.suspects)]
end

"The temporary table that forbids exactly the combination `key` (0 = not in it)."
function _isolation_table(key::Vector{Int})
    scope = findall(!=(0), key)
    return RuleTable(scope, Set([Tuple(key[scope])]))
end

"Whether the combination `inner` is part of `outer`: every value `inner` sets, `outer` sets the same."
_contains(outer::Vector{Int}, inner::Vector{Int}) = all(p -> inner[p] == 0 || inner[p] == outer[p], eachindex(inner))

"The number of parameters at which two complete index rows differ."
_changes(a::Vector{Int}, b::Vector{Int}) = count(p -> a[p] != b[p], eachindex(a))

"""
    _row_kinds(space, key) -> Vector{Tuple{Int, Int}}

The kinds of valid case that can hold the combination `key`, each as
`(p, v)`: `(0, 0)` for ordinary cases, and `(p, v)` for negative cases with
the invalid value `v` at `p` (§5.3, §5.5), as `feasibility_for` keys them.
A combination with one `Invalid` value has that one kind. One with none
has the ordinary kind first, then each invalid value of each parameter it
leaves out, in parameter order and then domain order: a negative case may
hold every ordinary value of the combination.
"""
function _row_kinds(space::TestSpace, key::Vector{Int})
    bad = _invalid_parameters(space, key)
    isempty(bad) || return [(only(bad), key[only(bad)])]
    return [(0, 0); [(p, v) for p in eachindex(key) if key[p] == 0 for v in space.invalid[p]]]
end

"A kind of case as `Followup.searched` records it: `NamedTuple()` for ordinary, `(p = v,)` for negative."
_kind_named(space::TestSpace, p::Int, v::Int) =
    p == 0 ? NamedTuple() : from_indices(space, [q == p ? v : 0 for q in eachindex(space.names)])

"""
    _isolate(d, s, (p, v), others, isolation, memos, limits, starts) -> NamedTuple

One kind of case's isolation search for the suspect `s` (§3.17): ordinary
cases when `p == 0`, else negative cases with `v` at `p`, whose candidates
are `v` at `p` and ordinary values elsewhere and whose rules are the
space's rules that omit `p` (§5.5). The isolation tables of the `others`
apply to every kind, including those that name `p`. Each start, a failing
case, orders the candidates with its values first; with no starts, domain
order.

Returns `(status, witness, from, changes, rules, others, minimal, limit)`:
`:found` with the witness closest to a failing case of `s`; `:inseparable`
with the proof, `rules` in the space's numbering and `others` as positions
in `d.suspects`; or `:unknown`.
"""
function _isolate(d::Diagnosis, s::Suspect, (p, v)::Tuple{Int, Int}, others::Vector{Int},
                  isolation::Vector{RuleTable}, memos, limits, starts::Vector{Int})
    space = d.space
    feasibility_limit, explanation_limit = limits
    active = active_rules(space, p)
    tables = RuleTable[space.tables[active]; isolation[others]]
    table_memos = Union{Nothing, Dict}[memos[active]; fill(nothing, length(others))]
    base = [q == p ? [v] : space.ordinary[q] for q in eachindex(space.names)]
    key = copy(s.key)
    p == 0 || (key[p] = v)
    orders = isempty(starts) ? [base] :
             [[_value_first(base[q], d.rows[k][q]) for q in eachindex(base)] for k in starts]
    none = (status = :unknown, witness = nothing, from = 0, changes = -1, rules = Int[], others = Int[],
            minimal = :not_applicable, limit = nothing)
    best = none
    for candidates in orders
        f = Feasibility(candidates, tables; limit = feasibility_limit, memos = table_memos)
        e = explain_partial(f, key; explanation_limit)
        if e.outcome === :allowed || e.outcome === :completable
            k = argmin(k -> (_changes(e.witness, d.rows[k]), k), s.failing)
            changes = _changes(e.witness, d.rows[k])
            if best.status !== :found || changes < best.changes
                best = merge(none, (status = :found, witness = e.witness, from = k, changes = changes))
            end
            best.changes == 0 && break
        elseif e.outcome === :forbidden || e.outcome === :infeasible
            # Feasibility does not depend on the order values are tried in: one proof decides the kind.
            return merge(none, (status = :inseparable,
                rules = Int[active[r] for r in e.rules if r <= length(active)],
                others = Int[others[r - length(active)] for r in e.rules if r > length(active)],
                minimal = e.minimal, limit = _limit_pair(e.limit, feasibility_limit, explanation_limit)))
        end
    end
    return best
end

function _followup(d::Diagnosis, j::Int, isolation::Vector{RuleTable}, memos, limits, prefer::Symbol)
    space, suspects = d.space, d.suspects
    s = suspects[j]
    contained = [i for i in eachindex(suspects) if i != j && _contains(s.key, suspects[i].key)]
    if !isempty(contained)
        return _no_case(s.combination, :indistinguishable;
                        others = NamedTuple[suspects[i].combination for i in contained])
    end
    length(_invalid_parameters(space, s.key)) > 1 && return _no_case(s.combination, :inseparable)
    others = [i for i in eachindex(suspects) if i != j]
    starts = prefer === :nearest ? unique(k -> d.rows[k], s.failing) : Int[]
    starts = starts[1:min(end, _FOLLOWUP_STARTS)]
    # Every kind of case that could hold the suspect is searched, ordinary first
    # (§5.5). The fewest changes win; on a tie the kind searched first.
    kinds = _row_kinds(space, s.key)
    searched = NamedTuple[]
    best = nothing
    proofs = []
    for (p, v) in kinds
        push!(searched, _kind_named(space, p, v))
        r = _isolate(d, s, (p, v), others, isolation, memos, limits, starts)
        if r.status === :found
            if best === nothing || r.changes < best.changes
                best = merge(r, (kind = p == 0 ? :ordinary : :negative,))
            end
            (best.changes == 0 || prefer === :domain) && break
        elseif r.status === :inseparable
            push!(proofs, r)
        end
    end
    if best !== nothing
        return Followup(s.combination, :found, from_indices(space, best.witness), best.kind, best.from,
                        best.changes, NamedTuple[], Int[], String[], :not_applicable, nothing, searched)
    elseif length(proofs) < length(kinds)
        feasibility_limit = first(limits)
        return _no_case(s.combination, :unknown; limit = :feasibility_limit => feasibility_limit, searched)
    end
    # Every kind is proven to hold no isolating case: the proof is the union of theirs.
    rules = sort!(unique(Int[r for proof in proofs for r in proof.rules]))
    proof_others = sort!(unique(Int[i for proof in proofs for i in proof.others]))
    minimals = [proof.minimal for proof in proofs]
    minimal = any(==(:unresolved), minimals) ? :unresolved :
              all(==(:verified), minimals) ? :verified : :not_applicable
    unresolved = findfirst(proof -> proof.limit !== nothing, proofs)
    limit = unresolved === nothing ? nothing : proofs[unresolved].limit
    return _no_case(s.combination, :inseparable;
                    others = NamedTuple[suspects[i].combination for i in proof_others], rules,
                    labels = [rule_label(space, k) for k in rules], minimal, limit, searched)
end

"`values` with `v` moved to the front when it is one of them; otherwise unchanged."
function _value_first(values::Vector{Int}, v::Int)
    k = findfirst(==(v), values)
    k === nothing && return values
    return [v; values[1:(k - 1)]; values[(k + 1):end]]
end

"The kinds of case `searched` names: \"ordinary cases and negative cases with n = Invalid(0)\"."
function _kinds_phrase(io::IO, searched::Vector{NamedTuple})
    negative = [string(only(keys(k)), " = ", _exact(io, only(k))) for k in searched if !isempty(k)]
    parts = String[]
    any(isempty, searched) && push!(parts, "ordinary cases")
    isempty(negative) || push!(parts, "negative cases with " * _listed(negative; conjunction = " or "))
    return join(parts, " and ")
end

function Base.show(io::IO, f::Followup)
    print(io, _exact(io, f.suspect), ": ")
    if f.status === :found
        print(io, "found ", f.kind === :negative ? "negative case " : "", _exact(io, f.case), ", ")
        if f.changes == 0
            print(io, "failing case ", f.from, " itself")
        else
            print(io, _plural(f.changes, "change"), " from case ", f.from)
        end
    elseif f.status === :indistinguishable
        print(io, "indistinguishable; every case holding it holds ",
              _listed([_exact(io, o) for o in f.others]))
    elseif f.status === :inseparable
        print(io, "inseparable; ")
        if isempty(f.others) && isempty(f.rules)
            print(io, "it has more than one Invalid value, and a case holds at most one")
        elseif isempty(f.others)
            print(io, "no valid case holds it: ")
            _print_exclusion(io, f.rules, f.labels, f.minimal, f.limit)
        else
            print(io, "every valid case holding it also holds ",
                  _listed([_exact(io, o) for o in f.others]; conjunction = " or "))
            if !isempty(f.rules)
                print(io, ", under ", length(f.rules) == 1 ? _rule_phrase(only(f.rules), only(f.labels)) :
                          _rule_numbers(f.rules) * " " * _rule_details(f.rules, f.labels))
            end
            if f.minimal === :unresolved
                print(io, " (whether each is needed is unresolved: ", f.limit.first, " = ",
                      _grouped(f.limit.second), " reached)")
            end
        end
        # An ordinary suspect beside Invalid values: say which kinds of case the proof covers.
        length(f.searched) > 1 && print(io, "; searched ", _kinds_phrase(io, f.searched))
    else
        print(io, "unknown; ", f.limit.first, " = ", _grouped(f.limit.second),
              " reached; retry with a larger limit")
    end
    return nothing
end
