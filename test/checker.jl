# The independent oracle for UnitTestDesign 0.5.
#
# Phase 1, step 3 of design/20260926_implementation_plan.md. It answers by
# brute force over the full product of a small space the questions the
# engines must answer: which complete rows are valid, which combinations are
# feasible, and whether a design covers them. It shares no code with src/
# and does not load UnitTestDesign. It aims to be obviously right, not fast.
#
# Use it with `include("checker.jl")`, or in a test item with
# `setup=[Checker]` (the `@testmodule` is in test_checker.jl).
#
# INPUT FORMAT
#
#   CheckSpace(names, domains, rules = [])
#   CheckSpace((a = [1, 2], b = [:x, :y]), rules = [])
#
#   names    Parameter names, distinct Symbols, at least one.
#   domains  One collection of values per name. Values are copied into a
#            Vector{Any} exactly as given: no promotion, so Any[1, 1.0] is
#            two choices.
#   rules    Each rule is `(scope, predicate)` or `scope => predicate`.
#            `scope` is a tuple of distinct parameter names (a lone Symbol
#            means a one-name scope). `predicate(values...)` receives the
#            scoped values positionally, in scope order, and returns a Bool
#            that is `true` when the combination is FORBIDDEN. A scope that
#            names every parameter is a whole-case rule. Rules are numbered
#            by position; that number is the attribution reported.
#
#   CheckInvalid(x)      An invalid value in a domain (a negative-test input).
#   CheckPartition(name) A named partition. Rules and targets see `name`;
#                        cases and rows carry the wrapper itself.
#
# Construction rejects (ArgumentError): repeated names; empty domains; a
# value listed twice (by identity); a raw Symbol equal to a partition name
# in the same domain; nested wrappers; a domain with only invalid values;
# a rule scope that is empty, repeats a name, or names an unknown parameter.
#
# SEMANTICS (the Phase 1 contract)
#
# Identity. Two values are the same choice when they have the same concrete
# type and are `isequal` (`same_value`). `CheckInvalid(x)` compares the
# wrapped values by the same rule and is never the same choice as `x`.
# `CheckPartition` compares by name. `nothing` is an ordinary value.
#
# Rows (complete cases).
#   ordinary row: no invalid value, and no rule forbids it.
#   negative row: exactly one invalid value, at parameter p, and no rule
#                 whose scope omits p forbids it. Rules whose scope includes
#                 p, whole-case rules among them, are not evaluated.
#   A row with two or more invalid values is never valid.
#
# Targets (partial assignments). The requested groups are the base group
# (every parameter, at `strength`) and each `stronger` entry `group => s`.
#   ordinary targets: for each group (G, s), each s-subset of G, each
#     assignment of ordinary values. The union over groups. A target is
#     feasible (required) when some valid ordinary row contains it.
#   negative targets: for each group (G, s), each p in G, each invalid
#     value v of p, each (s-1)-subset S of G without p, each assignment of
#     ordinary values to S: the target {p = v} plus S. The union over groups.
#     Feasible when some valid negative row contains it. At s = 1 the target
#     is {p = v} alone.
#   An infeasible target is :forbidden when a single applicable rule whose
#   scope lies within the target's parameters forbids the target's values
#   (for a negative target, applicable means the scope omits p); every such
#   rule is named, in rule order. Otherwise it is :implied: infeasible with
#   no direct rule match, that is, infeasible although no rule within the
#   target's parameters forbids it (contract §1.4). One rule with a wider
#   scope can be the whole cause: a rule over (a, b, c) that forbids every c
#   when a = 1 and b = 1 makes the target (a = 1, b = 1) :implied, so an
#   explanation of an :implied target may contain a single rule. The checker
#   names no rules for :implied targets.
#   A stronger group listed twice acts as its highest strength (§11.8).
#
# Cases. A case is a NamedTuple naming every parameter once, in any order,
# or a Tuple or AbstractVector in the order of `names`. Values are matched
# to the domain by identity, never by `==`. A partition may be written as
# its wrapper or as its name (contract §2.11). A rejected case contributes
# no coverage. Reasons:
#   :not_a_case         neither a NamedTuple, Tuple, nor AbstractVector
#   :unknown_parameter  a NamedTuple field that is not a parameter
#   :missing_parameter  a parameter the NamedTuple omits (partial case)
#   :wrong_length       a positional case of the wrong length
#   :unknown_value      a value not in that parameter's domain
#   :multiple_invalid   more than one invalid value
#   :violates_rule      applicable rules forbid the row (`rules` lists them)
# A rejected case belongs to the negative part if any of its values is a
# CheckInvalid, and to the ordinary part otherwise. The checker lists every
# rejected case; production `coverage` throws for the first four reasons and
# :unknown_value (contract §1.13) and lists the last two (§1.14).
#
# Duplicate valid rows count once. Ordinary rows cover only ordinary
# targets; negative rows cover only negative targets.
#
# OUTPUT
#
# Targets are NamedTuples with fields in parameter order. A partition
# appears as its name; an invalid value appears as its CheckInvalid. Rows
# are NamedTuples of domain values, wrappers kept. Lists are in a fixed
# order: rows sorted by value position; targets by size, then parameters,
# then value positions.
#
# The checker refuses any space whose full product exceeds CHECK_MAX_PRODUCT.

export CheckSpace, CheckInvalid, CheckPartition, CheckPart, CheckResult,
    CHECK_MAX_PRODUCT, same_value, same_target, check_design, complete,
    valid_rows, negative_rows, feasible_targets, negative_targets,
    classify_target

"Largest full product the checker will enumerate."
const CHECK_MAX_PRODUCT = 10^6

"An invalid value in a domain, for negative tests."
struct CheckInvalid{T}
    value::T
end

"A named partition of a domain. Rules and targets see its name."
struct CheckPartition
    name::Symbol
end

"""
    same_value(a, b)

The identity of domain values: the same concrete type and `isequal`.
"""
same_value(a::CheckInvalid, b::CheckInvalid) = same_value(a.value, b.value)
same_value(a::CheckPartition, b::CheckPartition) = a.name === b.name
same_value(a, b) = typeof(a) === typeof(b) && isequal(a, b)

"""
    same_target(a::NamedTuple, b::NamedTuple)

The same fields in the same order with `same_value` values. Use it to
compare targets or rows where `==` would equate `1` and `1.0`.
"""
same_target(a::NamedTuple, b::NamedTuple) =
    keys(a) == keys(b) && all(same_value(a[k], b[k]) for k in keys(a))

isinvalid(x) = x isa CheckInvalid

"What a rule or a target sees for a domain value."
seen_as(x::CheckPartition) = x.name
seen_as(x) = x


struct CheckSpace
    names::Vector{Symbol}
    domains::Vector{Vector{Any}}
    rules::Vector{Tuple{Tuple{Vararg{Symbol}},Any}}
    scopes::Vector{Vector{Int}}  # each rule's scope as parameter positions, in scope order

    function CheckSpace(names, domains, rules = [])
        all(n -> n isa Symbol, names) ||
            throw(ArgumentError("parameter names must be Symbols; got $(repr(names))"))
        names = Symbol[n for n in names]
        isempty(names) && throw(ArgumentError("a space needs at least one parameter"))
        allunique(names) || throw(ArgumentError("parameter names repeat: $(names)"))
        length(domains) == length(names) ||
            throw(ArgumentError("$(length(names)) names but $(length(domains)) domains"))

        doms = Vector{Any}[]
        for (name, domain) in zip(names, domains)
            values = collect(Any, domain)
            isempty(values) && throw(ArgumentError("parameter `$name` has an empty domain"))
            for (i, x) in enumerate(values)
                if x isa CheckInvalid && (x.value isa CheckInvalid || x.value isa CheckPartition)
                    throw(ArgumentError("parameter `$name`: nested wrappers are unsupported: $(repr(x))"))
                end
                for j in 1:(i - 1)
                    same_value(values[j], x) &&
                        throw(ArgumentError("parameter `$name` lists $(repr(x)) twice"))
                end
            end
            for x in values
                if x isa Symbol && any(y -> y isa CheckPartition && y.name === x, values)
                    throw(ArgumentError(
                        "parameter `$name` has both $(repr(x)) and CheckPartition($(repr(x)))"))
                end
            end
            all(isinvalid, values) && throw(ArgumentError(
                "parameter `$name` has only invalid values; it needs an ordinary value"))
            push!(doms, values)
        end

        rs = Tuple{Tuple{Vararg{Symbol}},Any}[]
        scopes = Vector{Int}[]
        for (i, rule) in enumerate(rules)
            if rule isa Pair
                scope, predicate = rule.first, rule.second
            elseif rule isa Tuple && length(rule) == 2
                scope, predicate = rule
            else
                throw(ArgumentError("rule $i must be (scope, predicate) or scope => predicate"))
            end
            scope isa Symbol && (scope = (scope,))
            scope isa AbstractVector && (scope = Tuple(scope))
            (scope isa Tuple && all(s -> s isa Symbol, scope)) ||
                throw(ArgumentError("rule $i: the scope must be a tuple of Symbols"))
            isempty(scope) && throw(ArgumentError("rule $i has an empty scope"))
            allunique(scope) || throw(ArgumentError("rule $i names a parameter twice: $scope"))
            positions = Int[]
            for s in scope
                p = findfirst(==(s), names)
                p === nothing && throw(ArgumentError(
                    "rule $i names `$s`, which is not a parameter; parameters are $(join(names, ", "))"))
                push!(positions, p)
            end
            push!(rs, (scope, predicate))
            push!(scopes, positions)
        end
        return new(names, doms, rs, scopes)
    end
end

CheckSpace(domains::NamedTuple, rules = []) =
    CheckSpace(collect(keys(domains)), collect(values(domains)), rules)

nparams(space::CheckSpace) = length(space.names)
ordinary_positions(space, p) = [i for (i, x) in enumerate(space.domains[p]) if !isinvalid(x)]
invalid_positions(space, p) = [i for (i, x) in enumerate(space.domains[p]) if isinvalid(x)]

# Internally a row or a target is a Vector{Int} holding, for each parameter,
# the position of its value in the domain, or 0 when unassigned.

assigned(t) = [p for p in eachindex(t) if t[p] != 0]
invalid_params(space, t) = [p for p in assigned(t) if isinvalid(space.domains[p][t[p]])]

"Rule `i` applies unless its scope includes a parameter holding an invalid value."
applies(space, i, invalid_ps) = !any(p -> p in invalid_ps, space.scopes[i])

"Whether rule `i` forbids the values `t` assigns to its scope."
function forbids(space, i, t)
    args = [seen_as(space.domains[p][t[p]]) for p in space.scopes[i]]
    verdict = space.rules[i][2](args...)
    verdict isa Bool || throw(ArgumentError(
        "rule $i returned $(repr(verdict)), not a Bool, for $(space.rules[i][1]) = $(Tuple(args))"))
    return verdict
end

"The applicable rules that forbid a complete row with at most one invalid value."
function violated_rules(space, row)
    bad = invalid_params(space, row)
    return [i for i in eachindex(space.rules) if applies(space, i, bad) && forbids(space, i, row)]
end

"Every valid ordinary row and every valid negative row, by brute force."
function enumerate_rows(space::CheckSpace)
    total = prod(big(length(d)) for d in space.domains)
    total <= CHECK_MAX_PRODUCT || throw(ArgumentError(
        "the checker enumerates the full product; this space has $total rows, " *
        "above CHECK_MAX_PRODUCT = $(CHECK_MAX_PRODUCT)"))
    ordinary = Vector{Int}[]
    negative = Vector{Int}[]
    for positions in Iterators.product((eachindex(d) for d in space.domains)...)
        row = collect(Int, positions)
        nbad = length(invalid_params(space, row))
        nbad > 1 && continue
        isempty(violated_rules(space, row)) || continue
        push!(nbad == 0 ? ordinary : negative, row)
    end
    return (ordinary = sort!(ordinary), negative = sort!(negative))
end

"For each target, whether some row in `pool` agrees with it on every assigned parameter."
function contained_in(targets, pool)
    projections = Dict{Vector{Int},Set{Vector{Int}}}()
    return map(targets) do t
        P = assigned(t)
        seen = get!(() -> Set(r[P] for r in pool), projections, P)
        t[P] in seen
    end
end


## Groups and targets

function param_position(space, x)
    if x isa Symbol
        p = findfirst(==(x), space.names)
        p === nothing && throw(ArgumentError(
            "`$x` is not a parameter; parameters are $(join(space.names, ", "))"))
        return p
    elseif x isa Integer
        1 <= x <= nparams(space) || throw(ArgumentError("no parameter at position $x"))
        return Int(x)
    end
    throw(ArgumentError("a group lists parameter names or positions; got $(repr(x))"))
end

function group_positions(space, group)
    group isa Union{Symbol,Integer} && (group = (group,))
    ps = [param_position(space, x) for x in group]
    isempty(ps) && throw(ArgumentError("a group needs at least one parameter"))
    allunique(ps) || throw(ArgumentError("group $(repr(group)) names a parameter twice"))
    return sort!(ps)
end

"The base group and the stronger groups as (positions, strength), validated."
function requested_groups(space, strength, stronger)
    n = nparams(space)
    (strength isa Integer && 1 <= strength <= n) || throw(ArgumentError(
        "strength must be an integer from 1 to the number of parameters, $n; got $(repr(strength))"))
    groups = Tuple{Vector{Int},Int}[(collect(1:n), Int(strength))]
    for entry in stronger
        entry isa Pair || throw(ArgumentError(
            "each `stronger` entry must be group => strength; got $(repr(entry))"))
        ps = group_positions(space, entry.first)
        s = entry.second
        (s isa Integer && strength <= s <= length(ps)) || throw(ArgumentError(
            "stronger group $(repr(entry.first)) => $(repr(s)): its strength must be at least " *
            "the base strength $strength and at most the group size $(length(ps))"))
        same = findfirst(g -> g[1] == ps, groups[2:end])
        if same === nothing
            push!(groups, (ps, Int(s)))
        else  # A group listed twice acts as its highest strength (contract §11.8).
            groups[same + 1] = (ps, max(groups[same + 1][2], Int(s)))
        end
    end
    return groups
end

"The `k`-element subsets of `v`, in lexicographic order."
function subsets(v, k)
    k == 0 && return [Int[]]
    return [[v[i]; rest] for i in eachindex(v) for rest in subsets(v[(i + 1):end], k - 1)]
end

"Every partial row assigning an ordinary value to each parameter in `params`."
function ordinary_assignments(space, params)
    out = Vector{Int}[]
    for values in Iterators.product((ordinary_positions(space, p) for p in params)...)
        t = zeros(Int, nparams(space))
        for (p, v) in zip(params, values)
            t[p] = v
        end
        push!(out, t)
    end
    return out
end

function ordinary_candidates(space, (ps, s))
    return [t for P in subsets(ps, s) for t in ordinary_assignments(space, P)]
end

function negative_candidates(space, (ps, s))
    out = Vector{Int}[]
    for p in ps, v in invalid_positions(space, p), S in subsets(filter(!=(p), ps), s - 1)
        for t in ordinary_assignments(space, S)
            t[p] = v
            push!(out, t)
        end
    end
    return out
end

target_order(t) = (count(!=(0), t), assigned(t), t[assigned(t)])

"The union of the candidate targets from every group, in a fixed order."
function union_of(candidates, space, groups)
    all = unique(reduce(vcat, [candidates(space, g) for g in groups]; init = Vector{Int}[]))
    return sort!(all; by = target_order)
end

"Rules that forbid target `t` by themselves: applicable and scoped within `t`."
function direct_rules(space, t)
    bad = invalid_params(space, t)
    return [i for i in eachindex(space.rules)
            if applies(space, i, bad) && all(p -> t[p] != 0, space.scopes[i]) && forbids(space, i, t)]
end

"Classify each target as :required, :forbidden (with rules), or :implied."
function classify_all(space, targets, rows)
    for t in targets
        length(invalid_params(space, t)) <= 1 ||
            throw(ArgumentError("a target holds at most one invalid value"))
    end
    ordinary = filter(t -> isempty(invalid_params(space, t)), targets)
    negative = filter(t -> !isempty(invalid_params(space, t)), targets)
    feasible = Dict{Vector{Int},Bool}()
    for (t, ok) in zip(ordinary, contained_in(ordinary, rows.ordinary))
        feasible[t] = ok
    end
    for (t, ok) in zip(negative, contained_in(negative, rows.negative))
        feasible[t] = ok
    end
    return map(targets) do t
        feasible[t] && return (status = :required, rule = nothing, rules = Int[])
        direct = direct_rules(space, t)
        isempty(direct) && return (status = :implied, rule = nothing, rules = Int[])
        return (status = :forbidden, rule = first(direct), rules = direct)
    end
end

row_value(space, row) =
    NamedTuple{Tuple(space.names)}(Tuple(space.domains[p][row[p]] for p in eachindex(row)))

target_value(space, t) =
    NamedTuple{Tuple(space.names[assigned(t)])}(Tuple(seen_as(space.domains[p][t[p]]) for p in assigned(t)))

"""
The position of `x` in `domain` by identity, or of the partition named `x`
(contract §2.11), or `nothing`.
"""
function value_position(domain, x)
    i = findfirst(y -> same_value(y, x), domain)
    if i === nothing && x isa Symbol
        i = findfirst(y -> y isa CheckPartition && y.name === x, domain)
    end
    return i
end

"Parse a target NamedTuple. A partition may be given by its name or its wrapper."
function read_target(space, target::NamedTuple)
    t = zeros(Int, nparams(space))
    for (name, x) in pairs(target)
        p = param_position(space, name)
        i = value_position(space.domains[p], x)
        i === nothing && throw(ArgumentError("parameter `$name` has no value $(repr(x))"))
        t[p] = i
    end
    return t
end


## Building blocks

"""
    valid_rows(space) -> Vector{NamedTuple}

Every complete ordinary row that no rule forbids.
"""
valid_rows(space::CheckSpace) = [row_value(space, r) for r in enumerate_rows(space).ordinary]

"""
    negative_rows(space) -> Vector{NamedTuple}

Every complete row with exactly one invalid value, at `p`, that no rule
whose scope omits `p` forbids.
"""
negative_rows(space::CheckSpace) = [row_value(space, r) for r in enumerate_rows(space).negative]

"""
    feasible_targets(space, group, strength) -> Vector{NamedTuple}
    feasible_targets(space; strength = 2, stronger = [])

The feasible ordinary targets of one group (a tuple of parameter names or
positions), or the union over the base group and the stronger groups.
"""
function feasible_targets(space::CheckSpace, group, strength::Integer)
    ps = group_positions(space, group)
    1 <= strength <= length(ps) ||
        throw(ArgumentError("strength $strength must be from 1 to the group size $(length(ps))"))
    return _feasible(space, ordinary_candidates, [(ps, Int(strength))])
end

feasible_targets(space::CheckSpace; strength = 2, stronger = []) =
    _feasible(space, ordinary_candidates, requested_groups(space, strength, stronger))

"""
    negative_targets(space, group, strength) -> Vector{NamedTuple}
    negative_targets(space; strength = 2, stronger = [])

The feasible negative targets of one group, or the union over the base
group and the stronger groups.
"""
function negative_targets(space::CheckSpace, group, strength::Integer)
    ps = group_positions(space, group)
    1 <= strength <= length(ps) ||
        throw(ArgumentError("strength $strength must be from 1 to the group size $(length(ps))"))
    return _feasible(space, negative_candidates, [(ps, Int(strength))])
end

negative_targets(space::CheckSpace; strength = 2, stronger = []) =
    _feasible(space, negative_candidates, requested_groups(space, strength, stronger))

function _feasible(space, candidates, groups)
    targets = union_of(candidates, space, groups)
    status = classify_all(space, targets, enumerate_rows(space))
    return [target_value(space, t) for (t, c) in zip(targets, status) if c.status == :required]
end

"""
    classify_target(space, target::NamedTuple) -> (; status, rule, rules)

`status` is `:required` when some valid row contains the target,
`:forbidden` when a single applicable rule within the target's parameters
forbids it (`rule` is the first such rule, `rules` all of them), and
`:implied` when it is infeasible with no direct rule match: infeasible
although no rule within the target's parameters forbids it. A single rule
with a wider scope can cause an `:implied` target, so an explanation may
contain one rule. A target with one `CheckInvalid` is judged against
negative rows. A partition may be given by name.
"""
function classify_target(space::CheckSpace, target::NamedTuple)
    return only(classify_all(space, [read_target(space, target)], enumerate_rows(space)))
end


## Checking a design

"""
One part of a check: the ordinary rows or the negative rows.

- `rows`: distinct valid rows of the design, in first-seen order.
- `duplicates`: valid rows repeating an earlier row (they count once).
- `rejected`: `(; index, case, reason, parameter, rules)` for each rejected case;
  `rules` lists the violated rules for `:violates_rule` and is empty otherwise.
- `feasible`, `covered`, `missing`: required targets, and which the design has.
- `forbidden`: directly forbidden targets, as `target => rules`, every rule
  that forbids the target by itself, in rule order.
- `implied`: targets infeasible with no direct rule match: no rule within
  the target's parameters forbids them. The cause may be one rule with a
  wider scope.
- `counts`: the lengths of the above.
"""
struct CheckPart
    rows::Vector{NamedTuple}
    duplicates::Int
    rejected::Vector{NamedTuple}
    feasible::Vector{NamedTuple}
    covered::Vector{NamedTuple}
    missing::Vector{NamedTuple}
    forbidden::Vector{Pair{NamedTuple,Vector{Int}}}
    implied::Vector{NamedTuple}
    counts::NamedTuple
end

struct CheckResult
    ordinary::CheckPart
    negative::CheckPart
    strength::Int
    groups::Vector{Pair{Vector{Symbol},Int}}
end

"""
    complete(result)

Every feasible target, ordinary and negative, is covered, and no case was
rejected.
"""
complete(part::CheckPart) = isempty(part.missing) && isempty(part.rejected)
complete(result::CheckResult) = complete(result.ordinary) && complete(result.negative)

"Read a case into value positions, or return why it is rejected."
function read_case(space, case)
    n = nparams(space)
    if case isa NamedTuple
        for k in keys(case)
            k in space.names || return (reason = :unknown_parameter, parameter = k)
        end
        for name in space.names
            haskey(case, name) || return (reason = :missing_parameter, parameter = name)
        end
        vals = Any[case[name] for name in space.names]
    elseif case isa Union{Tuple,AbstractVector}
        length(case) == n || return (reason = :wrong_length, parameter = nothing)
        vals = collect(Any, case)
    else
        return (reason = :not_a_case, parameter = nothing)
    end
    row = zeros(Int, n)
    for p in 1:n
        i = value_position(space.domains[p], vals[p])
        i === nothing && return (reason = :unknown_value, parameter = space.names[p])
        row[p] = i
    end
    return row
end

mentions_invalid(case) =
    case isa Union{NamedTuple,Tuple,AbstractVector} && any(isinvalid, values(case))

"""
    check_design(cases, space; strength = 2, stronger = []) -> CheckResult

Check a design against `space` by brute force. `cases` is an iterable of
NamedTuples, or of tuples in the order of `space.names`. `stronger` is a
vector of `group => strength` pairs, where a group is a tuple of names.
"""
function check_design(cases, space::CheckSpace; strength = 2, stronger = [])
    cases isa NamedTuple &&
        throw(ArgumentError("pass a collection of cases, not a single case"))
    groups = requested_groups(space, strength, stronger)
    rows = enumerate_rows(space)
    valid = (ordinary = Set(rows.ordinary), negative = Set(rows.negative))
    found = (ordinary = Vector{Int}[], negative = Vector{Int}[])
    duplicates = Dict(:ordinary => 0, :negative => 0)
    rejected = (ordinary = NamedTuple[], negative = NamedTuple[])

    for (k, case) in enumerate(cases)
        row = read_case(space, case)
        if !(row isa Vector{Int})
            part = mentions_invalid(case) ? :negative : :ordinary
            push!(rejected[part], (index = k, case = case, reason = row.reason,
                                   parameter = row.parameter, rules = Int[]))
            continue
        end
        bad = invalid_params(space, row)
        part = isempty(bad) ? :ordinary : :negative
        if length(bad) > 1
            push!(rejected[part], (index = k, case = case, reason = :multiple_invalid,
                                   parameter = nothing, rules = Int[]))
            continue
        end
        violated = violated_rules(space, row)
        if !isempty(violated)
            push!(rejected[part], (index = k, case = case, reason = :violates_rule,
                                   parameter = nothing, rules = violated))
            continue
        end
        # The same test that built the enumeration; a mismatch means a rule
        # answered differently on a second call.
        row in valid[part] || error("checker: rules are not deterministic on row $k")
        if row in found[part]
            duplicates[part] += 1
        else
            push!(found[part], row)
        end
    end

    parts = map((:ordinary, :negative)) do part
        candidates = part == :ordinary ? ordinary_candidates : negative_candidates
        targets = union_of(candidates, space, groups)
        status = classify_all(space, targets, rows)
        feasible = [t for (t, c) in zip(targets, status) if c.status == :required]
        hit = contained_in(feasible, found[part])
        CheckPart(
            [row_value(space, r) for r in found[part]],
            duplicates[part],
            rejected[part],
            [target_value(space, t) for t in feasible],
            [target_value(space, t) for (t, h) in zip(feasible, hit) if h],
            [target_value(space, t) for (t, h) in zip(feasible, hit) if !h],
            Pair{NamedTuple,Vector{Int}}[target_value(space, t) => c.rules
                                 for (t, c) in zip(targets, status) if c.status == :forbidden],
            NamedTuple[target_value(space, t)
                       for (t, c) in zip(targets, status) if c.status == :implied],
            (rows = length(found[part]), duplicates = duplicates[part],
             rejected = length(rejected[part]), feasible = length(feasible),
             covered = count(hit), missing = count(!, hit),
             forbidden = count(c -> c.status == :forbidden, status),
             implied = count(c -> c.status == :implied, status)),
        )
    end
    named_groups = [space.names[ps] => s for (ps, s) in groups]
    return CheckResult(parts[1], parts[2], Int(strength), named_groups)
end

function Base.show(io::IO, part::CheckPart)
    c = part.counts
    print(io, "covers $(c.covered) of $(c.feasible) feasible targets ",
          "($(c.forbidden) forbidden, $(c.implied) implied); ",
          "$(c.rows) rows, $(c.duplicates) duplicates, $(c.rejected) rejected")
end

function Base.show(io::IO, ::MIME"text/plain", result::CheckResult)
    println(io, "CheckResult, strength $(result.strength): ",
            complete(result) ? "complete" : "incomplete")
    for (label, part) in (("ordinary", result.ordinary), ("negative", result.negative))
        println(io, "  $label: ", part)
        for t in part.missing
            println(io, "    missing ", t)
        end
        for r in part.rejected
            println(io, "    rejected case $(r.index): $(r.reason)",
                    r.parameter === nothing ? "" : " `$(r.parameter)`",
                    isempty(r.rules) ? "" : " rules $(r.rules)")
        end
    end
end
