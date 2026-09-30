# Rules. Every surface form (a pattern, listed names, a macro, a whole-case
# function) compiles to one `Constraint` (contract §12.1), and a TestSpace
# tabulates each Constraint into a `RuleTable` (rule_table.jl), the index-space
# form the feasibility search reads (§12.18–§12.22). The macros, `@forbid` and
# `@require`, are in constraint_macros.jl, which builds their rules with
# `_function_rule` here.
#
# This file is included before space.jl because a TestSpace stores
# Constraints. The functions a TestSpace calls here take the parts of the space
# (names, stored domains, ordinary value indices) rather than the space. They
# use the value helpers of space.jl (`Invalid`, `Partition`, `same_value`,
# `rule_value`, `_find_value`) only inside function bodies, which Julia resolves
# when they run.

"""
Use when you handle rules as values: [`forbid`](@ref), [`require`](@ref),
[`@forbid`](@ref) and [`@require`](@ref) all return a `Constraint`, and a
[`TestSpace`](@ref) takes a vector of them as `constraints`.

    Constraint

One rule of a [`TestSpace`](@ref): the single internal form that
[`forbid`](@ref), [`require`](@ref), [`@forbid`](@ref) and [`@require`](@ref)
all build (contract §12.1). Nothing downstream of construction distinguishes
the surface forms; a space tabulates every rule the same way.

Fields:

- `scope::Tuple{Vararg{Symbol}}`: the parameters the rule reads, in the order
  its predicate receives them. The empty tuple marks a whole-case rule, whose
  scope is every parameter (§12.9).
- `predicate`: returns `true` when the combination is *forbidden*. A scoped
  rule's predicate takes the scoped values positionally, in scope order
  (§12.5); a whole-case rule's takes the complete row as one `NamedTuple`.
  For a `require` rule it is the negation of the caller's function. A result
  that is not a `Bool` passes through unchanged so that evaluation can report
  it (§12.15).
- `polarity::Symbol`: `:forbid` or `:require`. Display only (§12.2).
- `label::String`: the `reason`, the macro's source text, or both. Empty when
  the rule has neither; the space then names the rule by its position and
  scope (§12.3, see `rule_label`).
- `source::Symbol`: `:pattern`, `:names`, `:macro`, or `:whole_case`. Used
  only to phrase construction errors (the `\$name` hint of §12.8).
- `pattern`: for a pattern rule, the pattern as given, so the space can check
  its values against the domains (§12.4); otherwise `nothing`.

`show` prints the label.
"""
struct Constraint
    scope::Tuple{Vararg{Symbol}}
    predicate::Any
    polarity::Symbol
    label::String
    source::Symbol
    pattern::Union{Nothing,NamedTuple}

    function Constraint(scope, predicate, polarity::Symbol, label::AbstractString,
                        source::Symbol, pattern)
        polarity in (:forbid, :require) || throw(ArgumentError(
            "a rule's polarity is :forbid or :require; got $(repr(polarity))"))
        source in (:pattern, :names, :macro, :whole_case) || throw(ArgumentError(
            "a rule's source is :pattern, :names, :macro or :whole_case; got $(repr(source))"))
        return new(Tuple(scope), predicate, polarity, String(label), source, pattern)
    end
end


"""
The predicate of a `require` rule: forbidden where the caller's function is
`false`. A non-`Bool` result passes through so evaluation can report it
(contract §12.15) instead of negating it (`!1` is `-2`).
"""
struct Negated{F}
    f::F
end
(n::Negated)(args...) = (verdict = n.f(args...); verdict isa Bool ? !verdict : verdict)


"""
The predicate of a pattern rule: forbidden when every scoped value is the same
choice (contract §2.1) as the pattern's value. `values` holds the pattern's
values as rules see them, a partition by its name (§4.5), so that they compare
with what the predicate receives.
"""
struct PatternMatch{T<:Tuple}
    values::T
end
(p::PatternMatch)(args...) = all(k -> same_value(args[k], p.values[k]), eachindex(args))::Bool


function _reason_label(reason)
    reason === nothing && return ""
    reason isa AbstractString && return String(reason)
    throw(ArgumentError("a rule's `reason` must be a string; got $(repr(reason))"))
end

_scope_text(c::Constraint) = isempty(c.scope) ? "the whole case" : "(" * join(c.scope, ", ") * ")"


"""
Use when some combinations of values are not valid and you can say which: an
exact pattern of values, or a predicate over named parameters that returns
`true` for the forbidden combinations.

    forbid(pattern::NamedTuple; reason = nothing)

Forbid one exact combination of values, such as
`forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance")`.
A row is excluded when its value at each named parameter is the same choice as
the pattern's value: the same type and `isequal`, so `1` does not match `1.0`
(contract §2.1, §12.4). A [`Partition`](@ref) may be written as its wrapper or
its name. Pattern values must be domain values; the space checks them when it
is built. A pattern cannot name an [`Invalid`](@ref) value (§5.8). There is no
`require` pattern form.

    forbid(f, names::Symbol...; reason = nothing)
    forbid(names::Symbol...; reason = nothing) do values... end

Forbid the combinations of the listed parameters for which `f` returns `true`.
`f` receives their values positionally, in the order listed (§12.5):
`forbid(:mode, :solver) do m, s; m == :fast && s != :none end`. The names are
distinct. A [`Partition`](@ref) is passed as its name; an `Invalid` value is
never passed (§5.8, §12.14).

    forbid(f; reason = nothing)
    forbid(; reason = nothing) do case; ... end

With no names, a whole-case rule: `f` receives the complete row as a
`NamedTuple` (§12.9). Use it as an escape hatch. A whole-case rule is evaluated
lazily, row by row (§12.20); it connects every parameter into one component,
so deciding feasibility may search up to the product of the unassigned
domains, bounded by `feasibility_limit` (§12.21). A whole-case rule does not
apply to a row with an `Invalid` value (§5.6).

Every predicate must return a `Bool` (§12.15) and should be deterministic and
free of side effects: it may be called more than once (§12.17). The rule's
`reason` labels it in errors and reports (§12.3).
"""
function forbid(pattern::NamedTuple; reason = nothing)
    isempty(pattern) && throw(ArgumentError(
        "forbid(pattern) needs at least one parameter in its pattern"))
    for (name, value) in pairs(pattern)
        value isa Invalid && throw(ArgumentError(
            "the pattern gives `$name` the invalid value $(repr(value)). Rules never apply " *
            "to a row at an invalid value, so this pattern could never match (contract §5.8)."))
    end
    seen = map(v -> v isa Partition ? v.name : v, Tuple(pattern))
    return Constraint(keys(pattern), PatternMatch(seen), :forbid, _reason_label(reason),
                      :pattern, pattern)
end

forbid(f, names::Symbol...; reason = nothing) = _function_rule(:forbid, f, names, reason)


"""
Use when it is easier to say which combinations are valid than which are not:
the rule excludes every combination for which the predicate returns `false`.

    require(f, names::Symbol...; reason = nothing)
    require(names::Symbol...; reason = nothing) do values... end
    require(f; reason = nothing)

Allow only the combinations for which `f` returns `true`; a row where it
returns `false` is excluded (contract §12.2). The forms and the arguments `f`
receives are those of [`forbid`](@ref): listed names receive their values
positionally, and no names means a whole-case rule that receives the complete
row as a `NamedTuple`. `require(:rows, :cols) do r, c; r == c end` allows only
square shapes. There is no `require` pattern form (§12.4).

A `require` rule is stored as the forbid rule "`f` is false", with its
polarity kept for display.
"""
require(f, names::Symbol...; reason = nothing) = _function_rule(:require, f, names, reason)

require(pattern::NamedTuple; reason = nothing) = throw(ArgumentError(
    "require has no pattern form (contract §12.4). To exclude the combination " *
    "$(pattern), write forbid($(pattern)); to allow only some combinations, write " *
    "require(:a, :b) do a, b ... end."))

# The rule of `forbid(f, names...)` and `require(f, names...)`, a whole-case
# rule when `names` is empty. The macros pass their source text as `text`: the
# label is then the reason, if any, followed by the text (§12.3), and the
# source is `:macro`.
function _function_rule(polarity::Symbol, f, names, reason; text = nothing)
    if isempty(methods(f))
        shown = join(map(repr, (f, names...)), ", ")
        throw(ArgumentError(
            "$polarity($shown) has no predicate function. Pass the function first, usually " *
            "with a do block: `$polarity(:a, :b) do a, b ... end`."))
    end
    for (k, name) in enumerate(names)
        name in names[1:(k - 1)] && throw(ArgumentError(
            "$polarity lists `$name` twice; a rule's names are distinct (contract §12.5)"))
    end
    predicate = polarity === :require ? Negated(f) : f
    label = _reason_label(reason)
    source = isempty(names) ? :whole_case : :names
    if text !== nothing
        label = isempty(label) ? text : string(label, ": ", text)
        source = :macro
    end
    return Constraint(names, predicate, polarity, label, source, nothing)
end


## Labels and errors

"""
    rule_label(rule::Constraint, position) -> String

The label a report prints for the rule at `position` in the space's
constraints: its `label` (reason and/or macro source text), or, for a rule with
neither, its position and scope, such as `"rule 2 on (mode, tol)"`
(contract §12.3).
"""
rule_label(c::Constraint, position::Integer) =
    isempty(c.label) ? "rule $position on $(_scope_text(c))" : c.label

"How errors refer to a rule: its position and its label."
_rule_ref(c::Constraint, position::Integer) =
    isempty(c.label) ? rule_label(c, position) : "rule $position ($(c.label))"

function Base.show(io::IO, c::Constraint)
    if isempty(c.label)
        print(io, c.polarity, " rule on ", _scope_text(c))
    else
        print(io, c.label)
    end
end


"""
Use when a rule's predicate may throw: the exception reaches you wrapped in a
`ConstraintError` that names the rule and the values it received.

    ConstraintError(rule, arguments, exception)

A rule's predicate threw an exception (contract §12.16). `rule` names the rule
by position and label, `arguments` is a `NamedTuple` of the values it received
(for a whole-case rule, the row), and `exception` is what it threw, which is
also the cause on the exception stack. An exception never means forbidden or
allowed: fix the predicate so that it returns `true` or `false` for every
combination of its parameters' values.
"""
struct ConstraintError <: Exception
    rule::String
    arguments::NamedTuple
    exception::Any
end

function Base.showerror(io::IO, e::ConstraintError)
    print(io, "ConstraintError: ", e.rule, " threw an exception for ", e.arguments, ": ")
    showerror(io, e.exception)
end


## Checking rules against a space and tabulating them

"The rules given as `constraints`, as a fresh `Vector{Constraint}`."
function _collect_rules(constraints)
    constraints isa Constraint && return Constraint[constraints]
    (constraints isa AbstractVector || constraints isa Tuple) || throw(ArgumentError(
        "constraints must be a vector of rules; got $(summary(constraints))"))
    rules = Constraint[]
    for (k, c) in enumerate(constraints)
        c isa Constraint || throw(ArgumentError(
            "constraints[$k] is $(repr(c)), not a rule. Build rules with forbid, require, " *
            "@forbid, or @require."))
        push!(rules, c)
    end
    return rules
end

"""
    _check_rule(rule, position, names, values)

Check a rule against the space being built: every name in its scope is a
parameter (§12.8, §12.13), and a pattern's values are domain values (§12.4,
§2.11).
"""
function _check_rule(c::Constraint, position::Int, names::Vector{Symbol}, values)
    for name in c.scope
        name in names && continue
        msg = "$(_rule_ref(c, position)) names `$name`, which is not a parameter of this " *
              "space. The parameters are $(join(names, ", "))."
        if c.source === :macro
            msg *= " If `$name` is a variable, write `\$$name` to use its value."
        end
        throw(ArgumentError(msg))
    end
    if c.pattern !== nothing
        for (name, value) in pairs(c.pattern)
            p = findfirst(==(name), names)
            _find_value(values[p], value) === nothing && throw(ArgumentError(
                "$(_rule_ref(c, position)) forbids `$name = $(repr(value))`, but " *
                "$(_not_in_domain(name, values[p], value))"))
        end
    end
    return nothing
end

"""
    _tabulate(rule, position, names, values, ordinary, tabulation_limit) -> RuleTable

The index-space form of the rule at `position` (contract §12.18–§12.20).

A scoped rule whose scope has at most `tabulation_limit` combinations of
ordinary values is evaluated once per combination, when the space is built,
and the table stores the forbidden value-index tuples (`RuleTable`). The
combinations follow `Iterators.product` over the scope's ordinary value
indices in scope order, so the first parameter of the scope varies fastest.
A larger scope is evaluated lazily, memoized per operation by the
`Feasibility` that asks (§12.19), and the package warns once for that rule.
A whole-case rule is always lazy, with no warning; its table's scope is
every parameter. Tabulation and a lazy table evaluate the rule the same way,
through its `_LazyRule`.

Only ordinary values are tabulated, and predicates receive them as
[`rule_value`](@ref)s (a partition by its name, never an `Invalid`: §5.8,
§12.14). A tabulated table does not contain an invalid index, and a lazy one
throws if asked about one. The feasibility layer never asks: it assigns only
ordinary indices, except for the fixed invalid value of a negative row at `p`,
and it consults only `active_tables(space, p)` for that row, none of which
reads `p` (§5.5, §12.22).
"""
function _tabulate(c::Constraint, position::Int, names::Vector{Symbol}, values::Vector{AbstractVector},
                   ordinary::Vector{Vector{Int}}, tabulation_limit::Int)
    ref = _rule_ref(c, position)
    if isempty(c.scope)
        return RuleTable(collect(1:length(names)), _LazyRule(c, ref, Tuple(names), values))
    end
    scope = [findfirst(==(name), names)::Int for name in c.scope]
    rule = _LazyRule(c, ref, c.scope, values[scope])
    count = prod(BigInt(length(ordinary[p])) for p in scope)
    if count > tabulation_limit
        @warn("$(ref) reads $(join(c.scope, ", ")), whose $(count) combinations of values " *
              "exceed tabulation_limit = $(tabulation_limit), so the rule is evaluated " *
              "lazily, as rows need it, which can be slow. A rule over fewer parameters is " *
              "cheaper: split it into narrower rules if you can, or raise tabulation_limit " *
              "(contract §12.19).")
        return RuleTable(scope, rule)
    end
    return RuleTable(scope, _forbidden_set(Val(length(scope)), rule, ordinary[scope]))
end

# The combinations of the `ordinary` value indices of a rule's scope that
# `rule`, its `_LazyRule`, forbids. Compiled once per scope length: each call
# of `rule` is one dynamic call, into code specialized for the rule.
function _forbidden_set(::Val{N}, @nospecialize(rule), ordinary::Vector{Vector{Int}}) where {N}
    forbidden = Set{NTuple{N, Int}}()
    key = zeros(Int, N)
    for combination in Iterators.product(ntuple(k -> ordinary[k], Val(N))...)
        key .= combination
        rule(key)::Bool && push!(forbidden, combination)
    end
    return forbidden
end


"""
    _LazyRule(rule, ref, names, domains)

A rule as a function of value indices (contract §12.19, §12.20): called with
the value indices of its scope, a `Vector{Int}` in scope order, it returns
`true` when the rule forbids the values they index. `names` are the names of
those `N` values and `domains` their parameters' domains; `ref` names the rule
in errors. Each call evaluates the predicate on the values as rules see them
(`rule_value`), positionally for a scoped rule and as one `NamedTuple` for a
whole-case rule. A non-`Bool` result is an `ArgumentError` (§12.15) and an
exception is rethrown as a [`ConstraintError`](@ref) (§12.16). An `Invalid`
value is an internal error: rules never see one (§5.8).

The names `Names`, whether the rule is a whole-case rule (`Whole`), the
predicate's type `F` and the domains' types `D` are type parameters, so the
one dynamic call that reaches a rule (`table.lazy(key)` on a memo miss, or
one per combination when tabulating) lands in code that is concrete as far as
the domains' element types are, and each rule compiles only the call it
makes. That compilation, a few milliseconds per rule, is the price of a fast
evaluation: under 10 ns for a predicate that allocates nothing.

It keeps no memo. The verdicts are memoized per operation by the
`Feasibility` that asks (feasibility.jl: one generation request, or one call
to `explain`, `classify`, `coverage`, `missing_interactions`, `report` or
`followups`; `design_sizes` keeps one memo for all its measurements, and
each design it generates is a separate generation request with its own), so
the memo is released with the operation and a `TestSpace` retains nothing
from any call (§3.5, §12.19).
"""
struct _LazyRule{N, Names, Whole, F, D <: Tuple} <: Function
    predicate::F
    ref::String
    domains::D
end

function _LazyRule(c::Constraint, ref::String, names::NTuple{N, Symbol}, domains) where {N}
    d = Tuple(domains)
    return _LazyRule{N, names, isempty(c.scope), typeof(c.predicate), typeof(d)}(c.predicate, ref, d)
end

function (r::_LazyRule{N, Names, Whole})(key::AbstractVector{<:Integer}) where {N, Names, Whole}
    args = _rule_arguments(r.ref, Val(Names), r.domains, key)
    verdict = try
        Whole ? r.predicate(NamedTuple{Names}(args)) : r.predicate(args...)
    catch err
        err isa InterruptException && rethrow()
        _threw(r.ref, NamedTuple{Names}(args), err)
    end
    verdict isa Bool || _not_a_bool(r.ref, NamedTuple{Names}(args), verdict)
    return verdict
end

# The errors of a rule's evaluation, apart so that the code compiled for each
# rule stays small.
@noinline _threw(ref::String, @nospecialize(arguments::NamedTuple), @nospecialize(err)) =
    throw(ConstraintError(ref, arguments, err))

@noinline _not_a_bool(ref::String, @nospecialize(arguments::NamedTuple), @nospecialize(verdict)) =
    throw(ArgumentError("$ref returned $(repr(verdict)), which is not a Bool, for $arguments. " *
                        "A rule must return true or false (contract §12.15)."))

# The values that `key` indexes, as rules see them. Apart from the rule's call,
# and not specialized on the predicate, so that rules over the same parameters
# share it.
@noinline function _rule_arguments(ref::String, ::Val{Names}, domains::Tuple,
                                   key::AbstractVector{<:Integer}) where {Names}
    return ntuple(j -> _seen_value(ref, Names[j], domains[j][key[j]]), Val(length(Names)))
end

"What the rule `ref` sees for `value` of parameter `name`: its `rule_value`, never an `Invalid` (§5.8)."
function _seen_value(ref::String, name::Symbol, value)
    value isa Invalid && throw(ArgumentError(
        "internal error: $(ref) was consulted with the invalid value " *
        "$(repr(value)) of `$name`; rules never see an Invalid (contract §5.8)"))
    return rule_value(value)
end
