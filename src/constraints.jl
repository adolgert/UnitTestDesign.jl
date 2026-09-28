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
Use when a rule reads most clearly as a Julia expression over bare parameter
names that is `true` for the forbidden combinations, such as
`@forbid mode == :fast && solver != :none`.

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
  `"s"`, `r"re"`) are values, so no parameter may be named `nothing` or
  `missing`.
- `\$x` interpolates the caller's `x`, evaluated once when the rule is built:
  `@forbid n < \$threshold`. Write `\$Inf`, `\$Int` and the like for any
  other global that is not called.
- Names bound inside the expression are local, not parameters, with Julia's
  scoping: the arguments of `->` and of an anonymous `function` (including
  keyword arguments and `do`-block arguments), `let` bindings, and the
  variables of generators and comprehensions. So in
  `@forbid (n -> n)(m) > n` the scope is `(m, n)`: the lambda's `n` is local.
- Anything else that binds or assigns a name or runs statements (an
  assignment outside a `let` binding, `for`, `while`, `try`, `global`,
  `local`, a quoted expression, or a macro call) is an `ArgumentError` when
  the macro expands. Write such a rule with the function form,
  `forbid(f, names...)`.

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
Use when a rule reads most clearly as a Julia expression over bare parameter
names that must be `true` in every valid combination, such as
`@require mode == :exact || solver == :none`.

    @require expr
    @require(expr; reason = "...")

Allow only the combinations for which `expr` is `true`, written with bare
parameter names: `@require mode == :exact || solver == :none`. Identifiers are
read, and binding forms accepted or rejected, as in [`@forbid`](@ref). The
macro builds the same [`Constraint`](@ref) as [`require`](@ref) with listed
names.
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
    text = "@$polarity(" * _source_text(body) * ")"

    w = _RuleWalk(polarity, text)
    lowered = _walk(w, body, Set{Symbol}())

    lambda = Expr(:->, Expr(:tuple, (w.renamed[n] for n in w.names)...), lowered)
    call = Expr(:call, _macro_rule, QuoteNode(polarity), Expr(:tuple, map(QuoteNode, w.names)...),
                lambda, text, reason)
    bindings = [Expr(:(=), g, x) for (g, x) in w.interpolated]
    return esc(Expr(:let, Expr(:block, bindings...), call))
end

# The walk of one macro rule's expression. Parameter identifiers are replaced
# by the lambda arguments standing for them, so a parameter that shares a
# name with a function called in the same rule (`size(x) > size`) still calls
# the function. `$x` is replaced by a gensym bound to the caller's `x` when the
# rule is built. Names bound inside the expression (the `bound` set passed down
# the walk) are left alone. Subexpressions are walked in source order, so
# `names` lists the parameters in order of first appearance (§12.6).
struct _RuleWalk
    polarity::Symbol
    text::String                           # the label's source text, for errors
    names::Vector{Symbol}                  # parameter names, in order of first appearance
    renamed::Dict{Symbol,Symbol}           # parameter name => the lambda argument standing for it
    interpolated::Vector{Pair{Symbol,Any}} # gensym => the caller's expression
end

_RuleWalk(polarity::Symbol, text::String) =
    _RuleWalk(polarity, text, Symbol[], Dict{Symbol,Symbol}(), Pair{Symbol,Any}[])

# Identifiers that are values, never parameters (§12.7); `end` and `begin`
# appear inside indexing.
const _RULE_VALUE_NAMES = (:nothing, :missing, :true, :false, :end, :begin)

# Heads whose arguments are all ordinary subexpressions, walked in order.
const _RULE_PLAIN_HEADS = (:block, :if, :elseif, :&&, :||, :.&&, :.||, :vect, :vcat, :hcat,
    :row, :nrow, :ncat, :ref, :typed_vcat, :typed_hcat, :typed_ncat, :braces, :bracescat,
    :..., :string, Symbol("'"), :return, :comprehension)

function _walk(w::_RuleWalk, ex, bound::Set{Symbol})
    ex isa Symbol && return _walk_name(w, ex, bound)
    ex isa Expr || return ex  # literals, QuoteNode (:fast), LineNumberNode, GlobalRef
    head, args = ex.head, ex.args
    if head === :$
        return _interpolate(w, ex)
    elseif head === :call
        return _walk_call(w, ex, bound)
    elseif head === :. && length(args) == 2 && args[2] isa Expr && args[2].head === :tuple
        # A broadcast call, f.(x).
        return Expr(:., _walk_callee(w, args[1], bound), _walk(w, args[2], bound))
    elseif (head === :. && _is_dotted_name(ex)) || head === :curly
        # A dotted name (Base.isodd, M.x) or a type (Vector{Int}): the caller's.
        return _caller_expr(w, ex)
    elseif head === :.
        # A field of a computed value, f(x).re or (; a = n).a: walk the value.
        return Expr(:., _walk(w, args[1], bound), _caller_expr(w, args[2]))
    elseif head === :comparison
        # a < b <= c: operands at odd positions, operators at even ones.
        return Expr(:comparison, (isodd(k) ? _walk(w, a, bound) : a for (k, a) in enumerate(args))...)
    elseif head === :(::)
        # x::T asserts a type, which is the caller's.
        length(args) == 1 && return _caller_expr(w, ex)
        return Expr(:(::), _walk(w, args[1], bound), _caller_expr(w, args[2]))
    elseif head === :tuple || head === :parameters
        return _walk_fields(w, ex, bound)
    elseif head === :kw
        return Expr(:kw, args[1], _walk(w, args[2], bound))
    elseif head === :-> || head === :function
        return _walk_function(w, ex, bound)
    elseif head === :let
        return _walk_let(w, ex, bound)
    elseif head === :do
        # f(x) do y ... end: the call, then the block, an anonymous function of y.
        return Expr(:do, _walk(w, args[1], bound), _walk(w, args[2], bound))
    elseif head === :generator || head === :flatten
        return _walk_generator(w, ex, bound)
    elseif head === :typed_comprehension
        return Expr(head, _caller_expr(w, args[1]), _walk(w, args[2], bound))
    elseif head === :macrocall && _is_string_literal(ex)
        return ex  # r"...", v"...": a literal
    elseif head in _RULE_PLAIN_HEADS
        return Expr(head, (_walk(w, a, bound) for a in args)...)
    else
        _rule_unsupported(w, _describe_form(ex))
    end
end

function _walk_name(w::_RuleWalk, name::Symbol, bound::Set{Symbol})
    (name in bound || name in _RULE_VALUE_NAMES || Base.isoperator(name)) && return name
    if !haskey(w.renamed, name)
        push!(w.names, name)
        w.renamed[name] = gensym(name)
    end
    return w.renamed[name]
end

function _interpolate(w::_RuleWalk, ex::Expr)
    g = gensym(:interpolated)
    push!(w.interpolated, g => ex.args[1])
    return g
end

# A dotted name, `M.x` or `Base.Math.pi`: an identifier, or `$x`, followed by
# field names.
_is_dotted_name(ex) = ex isa Symbol || (ex isa Expr && ex.head === :$) ||
    (ex isa Expr && ex.head === :. && length(ex.args) == 2 && ex.args[2] isa QuoteNode &&
     _is_dotted_name(ex.args[1]))

# An expression in the caller's scope (a dotted name, a type): only `$x`
# inside it is rewritten.
function _caller_expr(w::_RuleWalk, ex)
    ex isa Expr || return ex
    ex.head === :$ && return _interpolate(w, ex)
    return Expr(ex.head, (_caller_expr(w, a) for a in ex.args)...)
end

# The function a call calls. An identifier is the caller's function, or a
# local one; a dotted name or a type is the caller's. Any other expression
# computes the function, `(x -> x > n)(1)` or `$f(x)`, and is walked.
function _walk_callee(w::_RuleWalk, f, bound::Set{Symbol})
    f isa Symbol && return f
    f isa Expr || return f
    ((f.head === :. && _is_dotted_name(f)) || f.head === :curly) && return _caller_expr(w, f)
    return _walk(w, f, bound)
end

# f(x, k = v; kw = u): the positional arguments come before the keywords in
# the source, although the parser stores `; kw = u` first.
function _walk_call(w::_RuleWalk, ex::Expr, bound::Set{Symbol})
    f = _walk_callee(w, ex.args[1], bound)
    rest = ex.args[2:end]
    lowered = Vector{Any}(undef, length(rest))
    for keywords in (false, true), (k, a) in enumerate(rest)
        (a isa Expr && a.head === :parameters) == keywords || continue
        lowered[k] = _walk(w, a, bound)
    end
    return Expr(:call, f, lowered...)
end

# A tuple, or the keyword part of a call or a named tuple. In `(a = v, b = u)`
# the names are field names, so only the values are walked. A bare name among
# keywords, `f(x; tol)` or `(; tol)`, means `tol = tol`, which stays true when
# `tol` is a parameter and is renamed.
function _walk_fields(w::_RuleWalk, ex::Expr, bound::Set{Symbol})
    lowered = map(ex.args) do a
        if ex.head === :tuple && a isa Expr && a.head === :(=) && a.args[1] isa Symbol
            return Expr(:(=), a.args[1], _walk(w, a.args[2], bound))
        elseif ex.head === :parameters && a isa Symbol
            value = _walk(w, a, bound)
            return value === a ? a : Expr(:kw, a, value)
        else
            return _walk(w, a, bound)
        end
    end
    return Expr(ex.head, lowered...)
end

# `args -> body`, `function (args) body end`, and a do block's function. The
# arguments are local to the body. A default value sees the arguments before
# it, keywords see every positional argument, and a type annotation is the
# caller's.
function _walk_function(w::_RuleWalk, ex::Expr, bound::Set{Symbol})
    arglist, body = ex.args[1], ex.args[2]
    ex.head === :function && !(arglist isa Expr && arglist.head === :tuple) &&
        _rule_unsupported(w, "the function definition `function $(_source_text(arglist)) ... end`")
    inner = copy(bound)
    if arglist isa Expr && arglist.head in (:tuple, :block)
        # (x, y = d; k = e) is a tuple with a :parameters part; (x; k) is a block
        # whose first entry is positional and the rest keywords.
        items = arglist.args
        first_positional = findfirst(a -> !(a isa LineNumberNode), items)
        is_keyword(k, a) = arglist.head === :tuple ? (a isa Expr && a.head === :parameters) :
                                                     k != first_positional
        lowered = Vector{Any}(undef, length(items))
        for keywords in (false, true), (k, a) in enumerate(items)
            is_keyword(k, a) == keywords || continue
            lowered[k] = a isa Expr && a.head === :parameters ?
                Expr(:parameters, (_bind_argument!(w, b, inner) for b in a.args)...) :
                _bind_argument!(w, a, inner)
        end
        arglist = Expr(arglist.head, lowered...)
    else
        arglist = _bind_argument!(w, arglist, inner)
    end
    return Expr(ex.head, arglist, _walk(w, body, inner))
end

# Bind the names of one argument, `let` left side, or generator variable in
# `inner`: a name, `x::T`, `xs...`, a destructuring tuple, or an argument with
# a default, `y = d`, whose default is walked before `y` is bound. Returns it
# with its types and defaults rewritten.
function _bind_argument!(w::_RuleWalk, a, inner::Set{Symbol})
    a isa LineNumberNode && return a
    if a isa Symbol
        push!(inner, a)
        return a
    elseif a isa Expr && a.head === :(::)
        length(a.args) == 1 && return _caller_expr(w, a)
        return Expr(:(::), _bind_argument!(w, a.args[1], inner), _caller_expr(w, a.args[2]))
    elseif a isa Expr && a.head === :...
        return Expr(:..., _bind_argument!(w, a.args[1], inner))
    elseif a isa Expr && a.head in (:tuple, :parameters)
        return Expr(a.head, (_bind_argument!(w, b, inner) for b in a.args)...)
    elseif a isa Expr && a.head in (:(=), :kw) && length(a.args) == 2
        default = _walk(w, a.args[2], inner)
        return Expr(a.head, _bind_argument!(w, a.args[1], inner), default)
    else
        _rule_unsupported(w, "the binding `$(_source_text(a))`")
    end
end

# let a = x, b = y; body end. Each right side sees the enclosing scope and the
# bindings before it (so `let x = x` reads the outer `x`), and the body sees
# them all. A `let` binding cannot define a function.
function _walk_let(w::_RuleWalk, ex::Expr, bound::Set{Symbol})
    bindings, body = ex.args
    inner = copy(bound)
    items = bindings isa Expr && bindings.head === :block ? bindings.args : Any[bindings]
    lowered = map(items) do b
        if b isa Expr && b.head === :(=)
            lhs = b.args[1]
            lhs isa Expr && lhs.head in (:call, :where) &&
                _rule_unsupported(w, "the function definition `$(_source_text(b))` in a `let`")
            rhs = _walk(w, b.args[2], inner)
            return Expr(:(=), _bind_argument!(w, lhs, inner), rhs)
        elseif b isa Symbol || b isa LineNumberNode
            return _bind_argument!(w, b, inner)
        else
            _rule_unsupported(w, "the `let` binding `$(_source_text(b))`")
        end
    end
    bindings = bindings isa Expr && bindings.head === :block ? Expr(:block, lowered...) : only(lowered)
    return Expr(:let, bindings, _walk(w, body, inner))
end

# (body for x in xs if p for y in ys if q). A generator has one or more `for`
# levels, outermost first; `:flatten` marks more than one. Each level's
# iterators see the enclosing scope and the variables of the levels before
# it; its filter, the later levels, and the body see its own variables too.
# A level `for x in xs, y in ys` binds x and y together, and neither is
# visible to the other's iterator. Walked in source order: the body, then
# each level's iterators and filter.
function _walk_generator(w::_RuleWalk, ex::Expr, bound::Set{Symbol})
    body, levels = _generator_parts(ex)
    conditions = Any[]
    ranges = Vector{Any}[]
    for specs in levels
        filtered = length(specs) == 1 && specs[1] isa Expr && specs[1].head === :filter
        push!(conditions, filtered ? specs[1].args[1] : nothing)
        push!(ranges, filtered ? specs[1].args[2:end] : specs)
    end
    inner = copy(bound)
    outer_scope = Set{Symbol}[]   # what level k's iterators see
    level_scope = Set{Symbol}[]   # what level k's filter sees
    variables = Vector{Any}[]
    for level_ranges in ranges
        push!(outer_scope, copy(inner))
        vars = map(level_ranges) do r
            (r isa Expr && r.head === :(=)) ||
                _rule_unsupported(w, "the generator clause `$(_source_text(r))`")
            _bind_argument!(w, r.args[1], inner)
        end
        push!(variables, vars)
        push!(level_scope, copy(inner))
    end
    lowered_body = _walk(w, body, inner)
    lowered_levels = Vector{Any}[]
    for (k, level_ranges) in enumerate(ranges)
        iterators = Any[Expr(:(=), variables[k][j], _walk(w, r.args[2], outer_scope[k]))
                        for (j, r) in enumerate(level_ranges)]
        condition = conditions[k]
        push!(lowered_levels, condition === nothing ? iterators :
              Any[Expr(:filter, _walk(w, condition, level_scope[k]), iterators...)])
    end
    return _generator_build(ex, lowered_body, lowered_levels, 1)
end

"The body of a generator and its levels' specifications, outermost first."
function _generator_parts(ex::Expr)
    if ex.head === :flatten
        g = ex.args[1]
        body, inner = _generator_parts(g.args[1])
        return body, Vector{Any}[g.args[2:end], inner...]
    end
    return ex.args[1], Vector{Any}[ex.args[2:end]]
end

"Reassemble `_generator_parts(ex)` with a new body and specifications."
function _generator_build(ex::Expr, body, levels, k::Int)
    if ex.head === :flatten
        g = ex.args[1]
        return Expr(:flatten, Expr(:generator, _generator_build(g.args[1], body, levels, k + 1), levels[k]...))
    end
    return Expr(:generator, body, levels[k]...)
end

# How an expression prints in labels and messages: Julia's printing, without
# `#= file:line =#` comments, including those a macro call carries.
_source_text(ex) = string(_strip_lines(ex))
_strip_lines(ex) = ex
function _strip_lines(ex::Expr)
    args = Any[a for a in ex.args if !(a isa LineNumberNode)]
    if ex.head === :macrocall
        args = Any[ex.args[1], nothing, (_strip_lines(a) for a in ex.args[3:end])...]
    else
        args = Any[_strip_lines(a) for a in args]
    end
    return Expr(ex.head, args...)
end

# A nonstandard string literal such as r"a+" or v"1.2": a macro call whose
# arguments are literal strings, so it reads no name.
_is_string_literal(ex::Expr) =
    ex.args[1] isa Symbol && endswith(string(ex.args[1]), "_str") &&
    all(a -> a isa Union{AbstractString, LineNumberNode, Nothing}, ex.args[2:end])

function _describe_form(ex::Expr)
    head = ex.head
    shown() = "`" * _source_text(ex) * "`"
    head in (:for, :while) && return "a `$head` loop"
    head === :try && return "a `try` block"
    head === :quote && return "the quoted expression $(shown())"
    head in (:global, :local, :const) && return "the `$head` declaration $(shown())"
    head === :macrocall && return "the macro call `$(ex.args[1])`"
    head === :where && return "a `where` clause"
    endswith(string(head), "=") && return "the assignment $(shown())"
    return "the `$head` expression $(shown())"
end

function _rule_unsupported(w::_RuleWalk, what::AbstractString)
    throw(ArgumentError(
        "$(w.text) contains $what, which a macro rule does not support. Inside " *
        "@$(w.polarity), only `->` and anonymous `function` arguments, `let` bindings, " *
        "generators, comprehensions and `do` blocks bind names (contract §12.6). For " *
        "anything else, use the function form $(w.polarity)(f, names...)."))
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
evaluated lazily, memoized per operation by the `Feasibility` that asks
(§12.19), and the package warns once for that rule. A whole-case rule is
always lazy, with no warning; its table's scope is every parameter.

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
value indices, in scope order, to `true` when forbidden. Each call evaluates
the predicate: a non-`Bool` result is an `ArgumentError` and an exception a
`ConstraintError` (§12.15, §12.16), as in tabulation.

It keeps no memo. The verdicts are memoized per operation by the
`Feasibility` that asks (feasibility.jl: a request, or one `explain` or
`classify` call), so the memo is released with the operation and a
`TestSpace` retains nothing from any call (§3.5, §12.19).
"""
struct _LazyRule{N} <: Function
    rule::Constraint
    ref::String
    names::NTuple{N,Symbol}
    domains::Vector{AbstractVector}
end

_LazyRule(c::Constraint, ref::String, names::NTuple{N,Symbol}, domains) where {N} =
    _LazyRule{N}(c, ref, names, collect(AbstractVector, domains))

function (r::_LazyRule{N})(key::NTuple{N,Int}) where {N}
    args = ntuple(Val(N)) do k
        value = r.domains[k][key[k]]
        value isa Invalid && throw(ArgumentError(
            "internal error: $(r.ref) was consulted with the invalid value " *
            "$(repr(value)) of `$(r.names[k])`; rules never see an Invalid (contract §5.8)"))
        rule_value(value)
    end
    return _evaluate_rule(r.rule, r.ref, r.names, args)
end
