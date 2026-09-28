# The model: the Partition and Invalid wrappers, value identity, and the
# TestSpace, which holds parameters, domains and rules, and the rules'
# tabulated RuleTables (contract §2, §4, §5, §12). This layer is pure: it
# generates nothing. It translates between the caller's vocabulary (names and
# values) and index space (rule_table.jl), where parameter `i` is the i-th
# name and value `k` of parameter `i` is `space.values[i][k]`.


## Wrappers (contract §2.12, §2.13, §4, §5)

"""
Use when one value stands for a class of inputs, such as tiny tolerances, and
each run should draw a concrete member of the class while rules and coverage
count the class by its name.

    Partition(name::Symbol, draw)

A named choice that stands for a class of values (contract §4.1). Rules,
patterns and coverage see `name` (§4.5); returned rows keep the wrapper, and
`realize(case; rng)` replaces it by `draw(rng)`, a concrete value drawn at run
time (§4.7). A fixed value is `Partition(:tiny, Returns(1e-9))`.

A partition's identity is its name; `draw` is not part of it (§2.13). Names are
unique within a parameter, and a domain may not also hold the raw `Symbol` of a
partition's name (§4.3, §4.4). A partition is an ordinary value (§4.2).
`Invalid(Partition(...))` is an error (§4.12).

A partition prints as `Partition(:tiny)`, which does not read back as code. In
cases committed to a test file as a literal, such as the output of
`repr(collect(cases))`, write its name, `:tiny`, which `coverage` and
`must_include` accept in its place (§2.11).
"""
struct Partition
    name::Symbol
    draw::Any

    function Partition(name::Symbol, draw)
        (draw isa Partition || draw isa Invalid) && throw(ArgumentError(
            "Partition($(repr(name)), $(repr(draw))): nested wrappers are unsupported " *
            "(contract §4.12); the draw is a function of an rng"))
        isempty(methods(draw)) && throw(ArgumentError(
            "Partition($(repr(name)), $(repr(draw))): the draw must be a function of an rng, " *
            "such as Returns($(repr(draw)))"))
        return new(name, draw)
    end
end

Partition(name, draw) = throw(ArgumentError(
    "a Partition's name must be a Symbol, such as :tiny; got $(repr(name)) (contract §4.1)"))

Base.show(io::IO, p::Partition) = print(io, "Partition(", repr(p.name), ")")
Base.:(==)(a::Partition, b::Partition) = a.name === b.name
Base.isequal(a::Partition, b::Partition) = a.name === b.name
Base.hash(p::Partition, h::UInt) = hash(p.name, h ⊻ 0x5f0c8e2b4a1d7c39)


"""
Use when a parameter has values the code must reject, and you want negative
cases that try each invalid value beside otherwise valid values, one invalid
value per case.

    Invalid(x)

Marks `x` as an invalid value of the parameter whose domain lists it, for
negative tests (contract §5.1). A row with one invalid value is a *negative*
row: it must satisfy only the rules whose scope omits that parameter (§5.5).
Rules never receive an `Invalid` (§5.8), and every parameter needs at least one
ordinary value (§5.2).

`Invalid(x)` and `Invalid(y)` are the same choice exactly when `x` and `y` are;
`Invalid(x)` and `x` are different choices, so a domain may hold both (§2.12).
`Invalid(Invalid(x))` and `Invalid(Partition(...))` are errors (§4.12).

Generation builds the covering design over ordinary values, then adds
negative rows: each holds one invalid value beside ordinary values, and
together they cover that value's negative targets (§6), such as, at strength
2, the invalid value beside every feasible value of every other parameter.
Rows keep the wrapper, so a test body can branch on [`hasinvalid`](@ref).

The wrapped value is `x.value`, the supported way to read it. A test body
unwraps a row's values before the call with
`unwrap(x) = x isa Invalid ? x.value : x`.
"""
struct Invalid{T}
    value::T

    function Invalid{T}(value) where {T}
        (value isa Invalid || value isa Partition) && throw(ArgumentError(
            "Invalid($(repr(value))): nested wrappers are unsupported (contract §4.12)"))
        return new{T}(value)
    end
end

Invalid(value::T) where {T} = Invalid{T}(value)

Base.show(io::IO, x::Invalid) = (print(io, "Invalid("); show(io, x.value); print(io, ")"))
Base.:(==)(a::Invalid, b::Invalid) = a.value == b.value
Base.isequal(a::Invalid, b::Invalid) = isequal(a.value, b.value)
Base.hash(x::Invalid, h::UInt) = hash(x.value, h ⊻ 0x2d7a91c4e8b3f056)


"""
Use when a test body must tell a negative case, one that holds an
[`Invalid`](@ref) value, from an ordinary one.

    hasinvalid(case) -> Bool

True when the row (a `NamedTuple`, `Tuple`, or vector) holds an
[`Invalid`](@ref) value, so a test body can branch on negative rows
(contract §5.1).
"""
hasinvalid(case::NamedTuple) = any(x -> x isa Invalid, values(case))
hasinvalid(case::Union{Tuple,AbstractVector}) = any(x -> x isa Invalid, case)


## Value identity (contract §2.1, §2.12, §2.13)

"""
    same_value(a, b) -> Bool

Whether `a` and `b` are the same choice: the same concrete type and `isequal`
(contract §2.1). So `1` and `1.0` differ, `0.0` and `-0.0` differ, and `NaN`
equals `NaN` (§2.2). `Invalid(x)` and `Invalid(y)` compare `x` and `y` by the
same rule, and an `Invalid` never equals a bare value (§2.12). Partitions
compare by name (§2.13). A partition is not the same value as its name,
`same_value(Partition(:t, f), :t) == false`; a caller who writes a partition by
its name is served by `value_index` (§2.11).
"""
same_value(a::Invalid, b::Invalid) = same_value(a.value, b.value)
same_value(a::Partition, b::Partition) = a.name === b.name
same_value(a, b) = typeof(a) === typeof(b) && isequal(a, b)

"""
A hashable key with `isequal(_identity_key(a), _identity_key(b)) ==
same_value(a, b)`, for finding repeated values without comparing every pair.
"""
_identity_key(x::Invalid) = (Invalid, _identity_key(x.value))
_identity_key(x::Partition) = (Partition, x.name)
_identity_key(x) = (typeof(x), x)

"""
    rule_value(x)

What a rule sees for the domain value `x`: a partition's name, or `x` itself
(contract §4.5, §12.14). Predicates never receive an `Invalid` (§5.8), so this
throws for one.
"""
rule_value(x::Partition) = x.name
rule_value(x::Invalid) = throw(ArgumentError(
    "internal error: rules never see the invalid value $(repr(x)) (contract §5.8)"))
rule_value(x) = x

"The index of `v` in `domain` by identity, or of the partition named `v`; `nothing` if absent (§2.11)."
function _find_value(domain::AbstractVector, v)
    k = findfirst(x -> same_value(x, v), domain)
    if k === nothing && v isa Symbol
        k = findfirst(x -> x isa Partition && x.name === v, domain)
    end
    return k
end

function _domain_text(domain::AbstractVector; limit::Integer = 10)
    shown = [repr(x) for x in Iterators.take(domain, limit)]
    length(domain) > limit && push!(shown, "… ($(length(domain)) values)")
    return "[" * join(shown, ", ") * "]"
end

# The second half of an "is not a value" message: the domain, and a hint when
# the value differs from a domain value only by type.
function _not_in_domain(name::Symbol, domain::AbstractVector, v)
    msg = "$(repr(v)) is not a value of `$name`, whose domain is $(_domain_text(domain))."
    near = findfirst(x -> !(x isa Invalid) && isequal(x, v), domain)
    if near !== nothing
        x = domain[near]
        msg *= " The domain has $(repr(x)) ($(typeof(x))); values match by type as well as " *
               "isequal, so $(repr(v)) ($(typeof(v))) is a different value (contract §2.1)."
    end
    return msg
end


## The space

"""
Use when you want to describe a test's parameters, their values, and the rules
that exclude combinations once, and share that description among generation,
measurement and diagnosis.

    TestSpace(domains::NamedTuple; constraints = [], tabulation_limit = 10^5)
    TestSpace(name => domain, ...; constraints = [], tabulation_limit = 10^5)

The parameters of a test, their values, and the rules that exclude
combinations (contract §2, §12.11). Build one when a function or a
configuration has several options and not every combination is valid:

```julia
space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
```

Parameter names are distinct `Symbol`s, at least one, and none is `nothing` or
`missing` (§2.10, §12.7). Each domain is a nonempty vector, range, or tuple, in
the order its values should be tried (§2.6); a single value is allowed (§2.7).
Values keep their identity: the same concrete type and `isequal`, so
`Any[1, 1.0]` is two choices and no value is converted (§2.1–§2.3). A domain
listing the same choice twice is an error (§2.5). `nothing` and `missing` are
ordinary values (§2.9). Domains may hold [`Partition`](@ref) and
[`Invalid`](@ref) values (§4, §5); each parameter needs an ordinary value.

`constraints` are rules built with [`forbid`](@ref), [`require`](@ref),
[`@forbid`](@ref) and [`@require`](@ref). The space checks each rule's names
and pattern values, then tabulates it: a rule is evaluated once per
combination of its parameters' values, when the space is built, unless there
are more than `tabulation_limit` combinations, in which case it is evaluated
lazily and the package warns (§12.18–§12.20).

Domains are copied, preserving their element types; tuples become vectors.
Values themselves are not copied (§2.8).

`parameters(space)` gives the names and `length(space)` the size of the full
product, including rows the rules exclude.
"""
struct TestSpace
    names::Vector{Symbol}
    values::Vector{AbstractVector}
    constraints::Vector{Constraint}
    tables::Vector{RuleTable}
    tabulation_limit::Int
    ordinary::Vector{Vector{Int}}  # per parameter, the indices of ordinary values
    invalid::Vector{Vector{Int}}   # per parameter, the indices of Invalid values

    function TestSpace(names::Vector{Symbol}, domains::AbstractVector, constraints,
                       tabulation_limit)
        isempty(names) && throw(ArgumentError(
            "a TestSpace needs at least one parameter (contract §2.10)"))
        length(domains) == length(names) || throw(ArgumentError(
            "$(length(names)) parameter names but $(length(domains)) domains"))
        for (i, name) in enumerate(names)
            name in (:nothing, :missing) && throw(ArgumentError(
                "a parameter may not be named `$name`: inside @forbid and @require, " *
                "`$name` denotes the value (contract §12.7)"))
            name in names[1:(i - 1)] && throw(ArgumentError(
                "parameter `$name` appears twice; parameter names are distinct (contract §2.10)"))
        end
        (tabulation_limit isa Integer && tabulation_limit >= 1) || throw(ArgumentError(
            "tabulation_limit must be a positive integer; got $(repr(tabulation_limit))"))
        limit = Int(tabulation_limit)

        values = AbstractVector[_copy_domain(name, d) for (name, d) in zip(names, domains)]
        ordinary = [findall(x -> !(x isa Invalid), v) for v in values]
        invalid = [findall(x -> x isa Invalid, v) for v in values]

        rules = _collect_rules(constraints)
        for (k, c) in enumerate(rules)
            _check_rule(c, k, names, values)
        end
        tables = RuleTable[_tabulate(c, k, names, values, ordinary, limit)
                           for (k, c) in enumerate(rules)]
        return new(copy(names), values, rules, tables, limit, ordinary, invalid)
    end

    # Internal: a space from parts that are already validated and tabulated,
    # with nothing checked or evaluated again. Negative generation (invalid.jl)
    # builds one over the parameters other than a negative row's invalid
    # parameter, reusing that space's domains, rules and tables.
    function TestSpace(::Val{:parts}, names::Vector{Symbol}, values::Vector{AbstractVector},
                       constraints::Vector{Constraint}, tables::Vector{RuleTable}, tabulation_limit::Int,
                       ordinary::Vector{Vector{Int}}, invalid::Vector{Vector{Int}})
        return new(names, values, constraints, tables, tabulation_limit, ordinary, invalid)
    end
end

TestSpace(domains::NamedTuple; constraints = Constraint[], tabulation_limit = 10^5) =
    TestSpace(collect(Symbol, keys(domains)), collect(Any, values(domains)),
              constraints, tabulation_limit)

function TestSpace(pairs::Pair...; constraints = Constraint[], tabulation_limit = 10^5)
    for p in pairs
        p.first isa Symbol || throw(ArgumentError(
            "parameter names are Symbols, such as :mode; got $(repr(p.first)) (contract §2.10)"))
    end
    return TestSpace(Symbol[p.first for p in pairs], Any[p.second for p in pairs],
                     constraints, tabulation_limit)
end

# A validated copy of one domain, with the caller's element type (§2.3, §2.6, §2.8).
function _copy_domain(name::Symbol, domain)
    if domain isa AbstractSet || domain isa AbstractDict
        throw(ArgumentError(
            "parameter `$name` lists its values in a $(typeof(domain)), which is unordered. " *
            "Use a vector or tuple in the order the values should be tried (contract §2.6)."))
    elseif !(domain isa AbstractVector || domain isa Tuple)
        throw(ArgumentError(
            "parameter `$name` needs an ordered list of values, a vector, range, or tuple; " *
            "got $(repr(domain)). Write [x] for a single value (contract §2.6)."))
    end
    isempty(domain) && throw(ArgumentError(
        "parameter `$name` has no values; a domain needs at least one (contract §2.6)"))
    values = Vector{eltype(domain)}(undef, length(domain))
    for (k, x) in enumerate(domain)
        values[k] = x
    end
    _check_domain(name, values)
    return values
end

function _check_domain(name::Symbol, values::AbstractVector)
    partitions = Dict{Symbol,Int}()
    for x in values
        x isa Partition || continue
        haskey(partitions, x.name) && throw(ArgumentError(
            "parameter `$name` has two partitions named $(repr(x.name)); partition names " *
            "are unique within a parameter (contract §4.3)"))
        partitions[x.name] = 1
    end
    for x in values
        (x isa Symbol && haskey(partitions, x)) && throw(ArgumentError(
            "parameter `$name` has both the Symbol $(repr(x)) and the partition " *
            "Partition($(repr(x))). Rules see a partition by its name, so the two " *
            "could not be told apart (contract §4.4)."))
    end
    seen = Set{Any}()
    for x in values
        key = _identity_key(x)
        key in seen && throw(ArgumentError(
            "parameter `$name` lists `$(repr(x))` twice (contract §2.5)"))
        push!(seen, key)
    end
    all(x -> x isa Invalid, values) && throw(ArgumentError(
        "parameter `$name` has only Invalid values; it needs at least one ordinary value " *
        "(contract §5.2)"))
    return nothing
end


## Accessors

"""
Use when you need a space's parameter names in order, for example to name the
columns of a positional result: `DataFrame(cases, parameters(cases.space))`.

    parameters(space::TestSpace) -> Vector{Symbol}

The parameter names, in order.
"""
parameters(space::TestSpace) = copy(space.names)

"The number of values of each parameter, ordinary and invalid."
arity(space::TestSpace) = [length(v) for v in space.values]

"""
    length(space::TestSpace)

The size of the full product of the domains, counting rows the rules exclude
and rows with `Invalid` values. An `Int` when it fits, otherwise a `BigInt`.
"""
function Base.length(space::TestSpace)
    n = prod(BigInt, arity(space))
    return n <= typemax(Int) ? Int(n) : n
end

"""
    ordinary_indices(space, i) -> Vector{Int}

The value indices of parameter `i` that are not `Invalid`, in domain order. The
feasibility layer assigns only these, except for the fixed invalid value of a
negative row. The vector belongs to the space; do not mutate it.
"""
ordinary_indices(space::TestSpace, i::Integer) = space.ordinary[i]

"Whether some parameter of the space has an `Invalid` value (contract §5.1)."
_has_invalid(space::TestSpace) = any(!isempty, space.invalid)

"""
    invalid_indices(space, i) -> Vector{Int}

The value indices of parameter `i` that are `Invalid`, in domain order. The
vector belongs to the space; do not mutate it.
"""
invalid_indices(space::TestSpace, i::Integer) = space.invalid[i]

"""
    parameter_index(space, name::Symbol) -> Int

The position of a parameter. An unknown name is an `ArgumentError` that lists
the space's names (contract §12.13).
"""
function parameter_index(space::TestSpace, name::Symbol)
    i = findfirst(==(name), space.names)
    i === nothing && throw(ArgumentError(
        "`$name` is not a parameter of this space; the parameters are $(join(space.names, ", "))"))
    return i
end

"""
    value_index(space, i, v) -> Int

The index of value `v` in the domain of parameter `i` (an index or a name),
matched by identity (contract §2.1). A partition may be given as its wrapper or
as its name (§2.11). A value that is not in the domain is an `ArgumentError`
naming the parameter, the value, and the domain.
"""
function value_index(space::TestSpace, i::Integer, v)
    k = _find_value(space.values[i], v)
    k === nothing && throw(ArgumentError(_not_in_domain(space.names[i], space.values[i], v)))
    return k
end

value_index(space::TestSpace, name::Symbol, v) = value_index(space, parameter_index(space, name), v)

"""
    rule_value(space, i, k)

What a predicate sees for value `k` of parameter `i`: a partition's name, or
the value itself (contract §4.5, §12.14). Predicates never see an `Invalid`
(§5.8): this throws for an invalid index, and rules are tabulated only over
[`ordinary_indices`](@ref).
"""
rule_value(space::TestSpace, i::Integer, k::Integer) = rule_value(space.values[i][k])

"""
    case_indices(space, partial::NamedTuple) -> Vector{Int}
    case_indices(space, case::Tuple) -> Vector{Int}

Index-space form of an assignment written in the caller's vocabulary: for each
parameter, the index of its value, or `0` for a parameter the `NamedTuple`
omits. Values match by identity and a partition may be written by its name
(§2.11). A positional `Tuple` is a complete case in parameter order. Unknown
names, values outside a domain, and a tuple of the wrong length are
`ArgumentError`s.

The name avoids `Base.to_indices`, which `Base` exports.
"""
function case_indices end

function case_indices(space::TestSpace, partial::NamedTuple)
    idx = zeros(Int, length(space.names))
    for (name, v) in pairs(partial)
        i = parameter_index(space, name)
        idx[i] = value_index(space, i, v)
    end
    return idx
end

function case_indices(space::TestSpace, case::Tuple)
    n = length(space.names)
    length(case) == n || throw(ArgumentError(
        "a positional case lists $(length(case)) values, but the space has $n parameters " *
        "($(join(space.names, ", "))), and a positional case is complete"))
    return [value_index(space, i, case[i]) for i in 1:n]
end

"""
    from_indices(space, idx::AbstractVector{<:Integer}) -> NamedTuple

The assignment an index vector stands for, with values as stored (wrappers
kept) and parameters in space order. Entries of `0` are unassigned and left out,
so `from_indices(space, case_indices(space, partial))` returns `partial` with its
names in space order.
"""
function from_indices(space::TestSpace, idx::AbstractVector{<:Integer})
    n = length(space.names)
    length(idx) == n || throw(ArgumentError(
        "an index vector for this space has $n entries; got $(length(idx))"))
    set = [i for i in 1:n if idx[i] != 0]
    return NamedTuple{Tuple(space.names[set])}(Tuple(space.values[i][idx[i]] for i in set))
end

"""
    active_rules(space, p) -> Vector{Int}

Positions of the rules a row must satisfy. With `p == 0`, an ordinary row:
every rule (contract §5.4). With `p` a parameter index, a negative row whose
invalid value is at `p`: the rules whose scope omits `p` (§5.5, §12.22), so no
whole-case rule (§5.6).
"""
function active_rules(space::TestSpace, p::Integer)
    0 <= p <= length(space.names) || throw(ArgumentError(
        "p is 0 for an ordinary row or a parameter index from 1 to $(length(space.names)); got $p"))
    p == 0 && return collect(eachindex(space.tables))
    return [k for (k, t) in enumerate(space.tables) if !(p in t.scope)]
end

"""
    active_tables(space, p) -> Vector{RuleTable}

The tables of [`active_rules`](@ref)`(space, p)`: every table for an ordinary
row (`p == 0`), and for a negative row at `p` the tables whose scope omits `p`.
"""
active_tables(space::TestSpace, p::Integer) = space.tables[active_rules(space, p)]

"""
    rule_label(space, k) -> String

The label of the space's `k`-th rule: its reason and/or macro source text, or
its position and scope when it has neither (contract §12.3).
"""
rule_label(space::TestSpace, k::Integer) = rule_label(space.constraints[k], k)


## Display

"""
    _noun(n, word, plural = word * "s") -> String

The form of `word` that agrees with a count of `n`: `word` for exactly 1,
`plural` otherwise ("1 pair", "0 pairs", "2 strategies"). Every printed
count goes through it or through `_plural`, so none reads "1 pairs".
"""
_noun(n, word, plural = string(word, "s")) = n == 1 ? word : plural

"`n` followed by the form of `word` that agrees with it: \"1 case\", \"3 cases\"."
_plural(n, word, plural = string(word, "s")) = string(n, " ", _noun(n, word, plural))

"""
    _indefinite(n) -> String

The article before the number `n` read aloud: "an" when its name begins with
a vowel sound (8, 11, 18, 80–89, 800–899, 8000, 11000, 18000, …), else "a",
as in "an 18-combination space".
"""
function _indefinite(n::Integer)
    digits = string(abs(n))
    lead = digits[1:mod1(length(digits), 3)]   # the leading group of three digits
    return startswith(lead, "8") || lead == "11" || lead == "18" ? "an" : "a"
end

function Base.show(io::IO, space::TestSpace)
    print(io, "TestSpace with ", _plural(length(space.names), "parameter"), ", ",
          _plural(length(space), "combination"), ", ",
          _plural(length(space.constraints), "constraint"))
end

function Base.show(io::IO, ::MIME"text/plain", space::TestSpace)
    show(io, space)
    width = maximum(name -> textwidth(string(name)), space.names)
    for (name, domain) in zip(space.names, space.values)
        shown = [sprint(show, x; context = io) for x in Iterators.take(domain, 12)]
        length(domain) > 12 && push!(shown, "… ($(length(domain)) values)")
        print(io, "\n  ", rpad(string(name, ":"), width + 1), " ", join(shown, ", "))
    end
end
