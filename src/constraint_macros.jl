# The rule macros, `@forbid` and `@require` (contract §12.6–§12.8). A macro
# walks its expression to find the parameter names it reads, in order of first
# appearance, and expands to a call of `_macro_rule` with a lambda over them.
# `_macro_rule` builds the rule with `_function_rule` (constraints.jl), so a
# macro rule is the rule `forbid(f, names...)` or `require(f, names...)` would
# build, except for its label, which ends with the source text, and its
# source, `:macro`, which `_check_rule` reads to suggest `$name` for a name
# the space lacks (§12.8).
#
# Included after constraints.jl. Of the package, this file uses only
# `_function_rule`. The expansion holds `_macro_rule` itself, not its name, so
# a module that only imports UnitTestDesign can use the macros.


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
- A subtype test written with the operator, `T <: \$AbstractFloat` or
  `T >: \$Int`, is an `ArgumentError` too: `<:` and `>:` are syntax, not
  calls. Write the call, `(<:)(T, \$AbstractFloat)`, or use the function form.

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
    elseif head === :<: || head === :>:
        _rule_unsupported_operator(w, ex, bound)
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

# `a <: b` and `a >: b` parse as their own expression heads, not as calls, so
# a macro rule rejects them; they bind nothing, so the message says what to
# write instead: the call form, which the macro reads, or the function form.
# When the subtype test is the whole rule, one operand a parameter's name and
# the other `$x`, as in `@forbid(T <: $AbstractFloat)`, the message spells out
# the function form for it. With two bare names it cannot tell a parameter
# from a type the caller forgot to interpolate, so it gives the general form.
function _rule_unsupported_operator(w::_RuleWalk, ex::Expr, bound::Set{Symbol})
    op = ex.head
    call = "($op)(" * join(map(_source_text, ex.args), ", ") * ")"
    example = ""
    is_name(a) = a isa Symbol && !(a in bound || a in _RULE_VALUE_NAMES)
    is_interpolated(a) = a isa Expr && a.head === :$ && length(a.args) == 1
    if w.text == "@$(w.polarity)(" * _source_text(ex) * ")" && length(ex.args) == 2 &&
       count(is_name, ex.args) == 1 && count(is_interpolated, ex.args) == 1
        name = only(filter(is_name, ex.args))
        plain = Expr(op, (is_interpolated(a) ? a.args[1] : a for a in ex.args)...)
        example = ", here $(w.polarity)(($name,) -> $(_source_text(plain)), $(repr(name)))"
    end
    throw(ArgumentError(
        "$(w.text) contains `$(_source_text(ex))`, and `$op` is not supported inside " *
        "@forbid/@require: Julia parses it as syntax, not as a function call (contract " *
        "§12.6). Write it as the call `$call`, which the macro reads, or use the " *
        "function form $(w.polarity)(f, names...)$example."))
end

# What the macros expand to: the Constraint of the listed-names form, built by
# the same function, with the source text in its label.
function _macro_rule(polarity::Symbol, scope::Tuple{Vararg{Symbol}}, f, text::String, reason)
    isempty(scope) && throw(ArgumentError(
        "$text reads no parameter. A rule names at least one parameter; for a rule on " *
        "the whole case, use $polarity(f), which receives the row as a NamedTuple."))
    return _function_rule(polarity, f, scope, reason; text)
end
