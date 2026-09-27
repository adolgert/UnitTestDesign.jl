# Rules. Every surface form (a pattern, listed names, a macro, a whole-case
# function) compiles to one `Constraint` (contract §12.1), and a TestSpace
# tabulates each Constraint into a `RuleTable` (rule_table.jl), the index-space
# form the feasibility search reads (§12.18–§12.22).
#
# This file is included before space.jl because a TestSpace stores
# Constraints. The functions a TestSpace calls here take the parts of the space
# (names, stored domains, ordinary value indices) rather than the space. They
# use the value helpers of space.jl (`Invalid`, `Partition`, `same_value`,
# `rule_value`, `_find_value`) only inside function bodies, which Julia resolves
# when they run.

"""
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

function _function_rule(polarity::Symbol, f, names, reason)
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
    source = isempty(names) ? :whole_case : :names
    return Constraint(names, predicate, polarity, _reason_label(reason), source, nothing)
end


## The macros (contract §12.6–§12.8)

"""
    @forbid expr
    @forbid(expr; reason = "...")

Forbid the combinations for which `expr` is `true`, written with bare
parameter names: `@forbid mode == :fast && solver != :none`.

Which identifiers are parameters (contract §12.6, §12.7):

- Every free identifier that is not in call position names a parameter. The
  rule's scope lists them in order of first appearance.
- An identifier in call position is an ordinary function (`isodd(n)`,
  `n < 3`), as is a dotted name (`Base.isodd(n)`, `M.x`). To read a field of
  a parameter, write `getproperty(p, :field)`.
- `nothing`, `missing`, `true`, `false`, and literals (`:fast`, `1e-3`,
  `"s"`) are values, so no parameter may be named `nothing` or `missing`.
- `\$x` interpolates the caller's `x`, evaluated once when the rule is built:
  `@forbid n < \$threshold`. Write `\$Inf`, `\$Int` and the like for any
  other global that is not called.
- Identifiers bound inside the expression by `->` or a generator are not
  parameters.

The rule's label is its source text as Julia prints it, such as
`"@forbid(mode == :fast && solver != :none)"`, preceded by the reason if one
is given (§12.3). A name the space lacks is an error when the space is built,
suggesting `\$name` if a variable was meant (§12.8). The macro builds the same
[`Constraint`](@ref) as [`forbid`](@ref) with listed names.
"""
macro forbid(args...)
    return _rule_macro(:forbid, args)
end

"""
    @require expr
    @require(expr; reason = "...")

Allow only the combinations for which `expr` is `true`, written with bare
parameter names: `@require mode == :exact || solver == :none`. Identifiers are
read as in [`@forbid`](@ref). The macro builds the same [`Constraint`](@ref)
as [`require`](@ref) with listed names.
"""
macro require(args...)
    return _rule_macro(:require, args)
end

function _rule_macro(polarity::Symbol, args)
    usage = "@$polarity takes one expression and an optional `reason = \"...\"`"
    reason = nothing
    body = nothing
    for arg in args
        if arg isa Expr && arg.head === :parameters
            for kw in arg.args
                (kw isa Expr && kw.head === :kw && kw.args[1] === :reason) ||
                    throw(ArgumentError("$usage; got $(kw)"))
                reason = kw.args[2]
            end
        elseif arg isa Expr && arg.head === :(=) && arg.args[1] === :reason
            reason = arg.args[2]
        elseif arg isa Expr && arg.head === :(=)
            throw(ArgumentError("$usage; got the assignment `$(arg)`. Compare with `==`."))
        elseif body === nothing
            body = arg
        else
            throw(ArgumentError("$usage; got more than one expression"))
        end
    end
    body === nothing && throw(ArgumentError(usage))
    text = "@$polarity(" * string(Base.remove_linenums!(deepcopy(body))) * ")"

    names = Symbol[]                  # parameter names, in order of first appearance
    renamed = Dict{Symbol,Symbol}()   # parameter name => the lambda argument standing for it
    interpolated = Pair{Symbol,Any}[] # gensym => the caller's expression
    lowered = _rule_walk(body, names, renamed, interpolated, Set{Symbol}())

    lambda = Expr(:->, Expr(:tuple, (renamed[n] for n in names)...), lowered)
    call = Expr(:call, _macro_rule, QuoteNode(polarity), Expr(:tuple, map(QuoteNode, names)...),
                lambda, text, reason)
    bindings = [Expr(:(=), g, x) for (g, x) in interpolated]
    return esc(Expr(:let, Expr(:block, bindings...), call))
end

# Walk a macro rule's expression. Parameter identifiers are replaced by the
# lambda arguments standing for them, so a parameter that shares a name with a
# function called in the same rule (`size(x) > size`) still calls the function.
# `$x` is replaced by a gensym bound to the caller's `x` when the rule is built.
function _rule_walk(ex, names, renamed, interpolated, bound)
    if ex isa Symbol
        (ex in bound || ex in (:nothing, :missing, :true, :false, :end, :begin) ||
            Base.isoperator(ex)) && return ex
        if !haskey(renamed, ex)
            push!(names, ex)
            renamed[ex] = gensym(ex)
        end
        return renamed[ex]
    end
    ex isa Expr || return ex  # literals, QuoteNode (:fast), LineNumberNode, GlobalRef
    walk(x) = _rule_walk(x, names, renamed, interpolated, bound)
    head, args = ex.head, ex.args
    if head === :$
        g = gensym(:interpolated)
        push!(interpolated, g => args[1])
        return g
    elseif head === :call
        # The callee is an ordinary function in the caller's scope.
        return Expr(:call, _rule_callee(args[1], walk), map(walk, args[2:end])...)
    elseif head === :. && length(args) == 2 && args[2] isa Expr && args[2].head === :tuple
        # A broadcast call, f.(x).
        return Expr(:., _rule_callee(args[1], walk), walk(args[2]))
    elseif head === :.
        # A dotted name (Base.isodd, M.x) refers to the caller's scope.
        return _rule_callee(ex, walk)
    elseif head === :curly || head === :quote || head === :inert
        # A type (Vector{Int}) or a quotation.
        return ex
    elseif head === :comparison
        # a < b <= c: operands at odd positions, operators at even ones.
        return Expr(:comparison, (isodd(k) ? walk(a) : a for (k, a) in enumerate(args))...)
    elseif head === :kw
        return Expr(:kw, args[1], walk(args[2]))
    elseif head === :(::)
        return length(args) == 1 ? ex : Expr(:(::), walk(args[1]), args[2])
    elseif head === :->
        inner = union(bound, _bound_names(args[1]))
        return Expr(:->, args[1], _rule_walk(args[2], names, renamed, interpolated, inner))
    elseif head === :generator || head === :flatten
        return _rule_generator(ex, names, renamed, interpolated, bound)
    elseif head === :macrocall
        return Expr(:macrocall, args[1], args[2], map(walk, args[3:end])...)
    else
        return Expr(head, map(walk, args)...)
    end
end

# A callee or dotted name belongs to the caller's scope; only `$x` inside it
# is rewritten.
function _rule_callee(f, walk)
    f isa Expr || return f
    f.head === :$ && return walk(f)
    f.head === :. && return Expr(:., _rule_callee(f.args[1], walk), f.args[2:end]...)
    return f
end

# The names a lambda's argument list or a generator's iteration variable binds.
_bound_names(x::Symbol) = Set([x])
function _bound_names(x::Expr)
    x.head === :(::) && return length(x.args) == 2 ? _bound_names(x.args[1]) : Set{Symbol}()
    x.head === :kw && return _bound_names(x.args[1])
    return union(Set{Symbol}(), (_bound_names(a) for a in x.args)...)
end
_bound_names(x) = Set{Symbol}()

# (body for x in iter if cond): iterators see the outer scope, while the body
# and filters also see the iteration variables.
function _rule_generator(ex, names, renamed, interpolated, bound)
    ex.head === :flatten &&
        return Expr(:flatten, _rule_generator(ex.args[1], names, renamed, interpolated, bound))
    specs = ex.args[2:end]
    inner = copy(bound)
    lowered_specs = map(specs) do spec
        if spec isa Expr && spec.head === :filter
            ranges = map(spec.args[2:end]) do r
                union!(inner, _bound_names(r.args[1]))
                Expr(:(=), r.args[1], _rule_walk(r.args[2], names, renamed, interpolated, bound))
            end
            return (spec, ranges)
        else
            union!(inner, _bound_names(spec.args[1]))
            return (spec, Expr(:(=), spec.args[1],
                               _rule_walk(spec.args[2], names, renamed, interpolated, bound)))
        end
    end
    body = _rule_walk(ex.args[1], names, renamed, interpolated, inner)
    out = map(lowered_specs) do (spec, lowered)
        spec isa Expr && spec.head === :filter || return lowered
        Expr(:filter, _rule_walk(spec.args[1], names, renamed, interpolated, inner), lowered...)
    end
    return Expr(ex.head, body, out...)
end

# What the macros expand to: the same Constraint as the listed-names form.
function _macro_rule(polarity::Symbol, scope::Tuple{Vararg{Symbol}}, f, text::String, reason)
    isempty(scope) && throw(ArgumentError(
        "$text reads no parameter. A rule names at least one parameter; for a rule on " *
        "the whole case, use $polarity(f), which receives the row as a NamedTuple."))
    predicate = polarity === :require ? Negated(f) : f
    why = _reason_label(reason)
    label = isempty(why) ? text : string(why, ": ", text)
    return Constraint(scope, predicate, polarity, label, :macro, nothing)
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


"""
    _evaluate_rule(rule, ref, argnames, args) -> Bool

Evaluate one rule on the values it sees (`args`, in scope order, partitions
as names). `argnames` are the names of those values, used for the whole-case
`NamedTuple` and for error messages; `ref` names the rule. A non-`Bool` result
is an `ArgumentError` (§12.15); an exception is rethrown as a
[`ConstraintError`](@ref) (§12.16).
"""
function _evaluate_rule(c::Constraint, ref::String, argnames::Tuple{Vararg{Symbol}}, args::Tuple)
    verdict = try
        isempty(c.scope) ? c.predicate(NamedTuple{argnames}(args)) : c.predicate(args...)
    catch err
        err isa InterruptException && rethrow()
        throw(ConstraintError(ref, NamedTuple{argnames}(args), err))
    end
    verdict isa Bool || throw(ArgumentError(
        "$ref returned $(repr(verdict)), which is not a Bool, for $(NamedTuple{argnames}(args)). " *
        "A rule must return true or false (contract §12.15)."))
    return verdict
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
and the forbidden value-index tuples are stored in a `Set`. The combinations
follow `Iterators.product` over the scope's ordinary value indices in scope
order, so the first parameter of the scope varies fastest. A larger scope is
evaluated lazily with a memo, and the package warns once for that rule. A
whole-case rule is always lazy, with no warning; its table's scope is every
parameter.

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
    count = prod(BigInt(length(ordinary[p])) for p in scope)
    if count > tabulation_limit
        @warn("$(ref) reads $(join(c.scope, ", ")), whose $(count) combinations of values " *
              "exceed tabulation_limit = $(tabulation_limit), so the rule is evaluated " *
              "lazily, as rows need it, which can be slow. A rule over fewer parameters is " *
              "cheaper: split it into narrower rules if you can, or raise tabulation_limit " *
              "(contract §12.19).")
        return RuleTable(scope, _LazyRule(c, ref, c.scope, values[scope]))
    end
    return RuleTable(scope, _forbidden_set(Val(length(scope)), c, ref, scope, values, ordinary))
end

function _forbidden_set(::Val{N}, c::Constraint, ref::String, scope::Vector{Int},
                        values::Vector{AbstractVector}, ordinary::Vector{Vector{Int}}) where {N}
    forbidden = Set{NTuple{N,Int}}()
    domains = ntuple(k -> values[scope[k]], Val(N))
    for key in Iterators.product(ntuple(k -> ordinary[scope[k]], Val(N))...)
        args = ntuple(k -> rule_value(domains[k][key[k]]), Val(N))
        _evaluate_rule(c, ref, c.scope, args) && push!(forbidden, key)
    end
    return forbidden
end


"""
The lazy form of a rule (contract §12.19, §12.20): a function from a tuple of
value indices, in scope order, to `true` when forbidden, memoized per tuple.
An evaluation that throws stores nothing.
"""
struct _LazyRule{N} <: Function
    rule::Constraint
    ref::String
    names::NTuple{N,Symbol}
    domains::Vector{AbstractVector}
    memo::Dict{NTuple{N,Int},Bool}
end

_LazyRule(c::Constraint, ref::String, names::NTuple{N,Symbol}, domains) where {N} =
    _LazyRule{N}(c, ref, names, collect(AbstractVector, domains), Dict{NTuple{N,Int},Bool}())

function (r::_LazyRule{N})(key::NTuple{N,Int}) where {N}
    return get!(r.memo, key) do
        args = ntuple(Val(N)) do k
            value = r.domains[k][key[k]]
            value isa Invalid && throw(ArgumentError(
                "internal error: $(r.ref) was consulted with the invalid value " *
                "$(repr(value)) of `$(r.names[k])`; rules never see an Invalid (contract §5.8)"))
            rule_value(value)
        end
        _evaluate_rule(r.rule, r.ref, r.names, args)
    end
end
