# Spaces from a spec's `arity`, `forbid`, `space`, `model`, `stronger` and
# `adapt` fields (plan §7.2). Included by worker.jl, whose `model(s)` calls
# `base_model` and `adapt!`. A spec without these fields builds the n × v
# space it always did.
#
#   arity    one value count per parameter p1, p2, …; values 1:a
#   forbid   scoped rules as forbidden tuples:
#            [{"scope": [1, 3], "tuples": [[1, 2], [2, 2]], "text": "…"}],
#            scope as parameter positions, tuples as values, one rule per entry
#   space    a named space from spaces.jl
#   model    an imported model, a JSON file written by datasets.py, relative to
#            the repository root: {"arity": […], "forbid": […], "names": […]};
#            its rules are read and compiled before timing (`load_model`)
#   stronger [[group, strength], …], a group as parameter names or positions
#   adapt    one change for the `adapted` family; see `adapt!`
# `n` (and `v`) stay in every spec, as labels the runner and summaries use;
# the worker checks `n` against the space it builds.

const REPOSITORY = normpath(joinpath(@__DIR__, "..", ".."))

"A predicate that is true for the listed value tuples."
tuple_predicate(tuples) = (forbidden = Set(Tuple(Int.(t)) for t in tuples); (xs...) -> xs in forbidden)

"Scoped rules, one per entry, from forbidden value tuples over the entry's scope."
function table_rules(names, entries)
    rules = Constraint[]
    for e in entries
        scope = Tuple(names[Int(p)] for p in e["scope"])
        push!(rules, forbid(tuple_predicate(e["tuples"]), scope...; reason = get(e, "text", nothing)))
    end
    return rules
end

# An ACTS expression, from datasets.py's `tree_json`, as Julia code over the
# value positions `args` of the parameters in `position` (name => argument).
# Each parameter reads its typed value from `labels`, so comparisons are the
# model's own: `Par3 = "PAR3_2"`, `Par12 < 54`, `Par8 = false`.
const TREE_OPS = Dict("||" => :||, "&&" => :&&, "=" => :(==), "!=" => :(!=), "<" => :<, "<=" => :<=,
                      ">" => :>, ">=" => :>=, "+" => :+, "-" => :-, "*" => :*, "/" => :fld, "%" => :mod)
function tree_code(node, position, args, labels)
    op = node[1]
    op == "param" && return :($(labels[position[node[2]]])[$(args[position[node[2]]])])
    op == "lit" && return node[2]
    op == "!" && return :(!$(tree_code(node[2], position, args, labels)))
    op == "neg" && return :(-$(tree_code(node[2], position, args, labels)))
    a, b = (tree_code(c, position, args, labels) for c in node[2:3])
    op == "=>" && return :(!$a || $b)
    f = TREE_OPS[op]
    return f in (:||, :&&) ? Expr(f, a, b) : :($f($a, $b))
end

"A compiled predicate, true where the expression is false: the rule forbids those tuples."
function expression_predicate(tree, scope, names, values)
    args = [Symbol(:x, i) for i in eachindex(scope)]
    position = Dict(String(names[p]) => i for (i, p) in enumerate(scope))
    labels = [identity.(values[p]) for p in scope]          # concrete Vector{Bool}, {Int} or {String}
    return Core.eval(Main, :(($(args...),) -> !$(tree_code(tree, position, args, labels))))
end

"An imported model's parameters and compiled rules, `(; arity, names, rules)`, rules as `(scope, predicate, text)`."
function load_model(path)
    file = JSON.parsefile(path)
    arity = Int.(file["arity"])
    names = file["names"] === nothing ? [Symbol(:p, i) for i in eachindex(arity)] : Symbol.(file["names"])
    rules = Any[]
    for e in file["forbid"]
        scope = [Int(p) for p in e["scope"]]
        predicate = haskey(e, "tuples") ? tuple_predicate(e["tuples"]) :
                                          expression_predicate(e["expr"], scope, names, file["values"])
        push!(rules, (Tuple(names[scope]), predicate, get(e, "text", nothing)))
    end
    return (; arity, names, rules)
end

# Read the spec's model, and compile its expressions, before the benchmark's
# world age and outside every timer: the timed construction builds the
# `forbid` rules and the TestSpace, as for any other spec.
const LOADED_MODEL = let spec = isempty(ARGS) ? nothing : JSON.parsefile(ARGS[1])
    spec !== nothing && haskey(spec, "model") ? load_model(joinpath(REPOSITORY, spec["model"])) : nothing
end

"`(names, domains, rules)` for the spec, before its family's own values and rules."
function base_model(s)
    n = s["n"]
    if haskey(s, "space")
        names, domains, rules = named_space(s["space"])
    elseif haskey(s, "model")
        loaded = LOADED_MODEL === nothing ? load_model(joinpath(REPOSITORY, s["model"])) : LOADED_MODEL
        names = copy(loaded.names)
        domains = [Any[1:a...] for a in loaded.arity]
        rules = Constraint[forbid(predicate, scope...; reason) for (scope, predicate, reason) in loaded.rules]
    else
        arity = haskey(s, "arity") ? Int.(s["arity"]) : fill(s["v"], n)
        names = [Symbol(:p, i) for i in 1:n]
        domains = [Any[1:a...] for a in arity]
        rules = Constraint[]
    end
    length(names) == n || throw(ArgumentError("spec says n = $n; its space has $(length(names)) parameters"))
    if any(haskey(s, f) for f in ("arity", "space", "model"))
        s["family"] == "none" || throw(ArgumentError("a spec with arity, space or model takes family \"none\" and `adapt`"))
        ordinary = [count(x -> !(x isa Invalid), d) for d in domains]
        haskey(s, "arity") && ordinary != s["arity"] &&
            throw(ArgumentError("spec arity $(s["arity"]) differs from the space's $ordinary"))
    end
    append!(rules, table_rules(names, get(s, "forbid", Any[])))
    return names, domains, rules
end

"The spec's explicit `stronger` groups, by name or position."
spec_stronger(s, names) =
    Pair[Tuple(g isa Integer ? names[g] : Symbol(g) for g in group) => Int(t) for (group, t) in get(s, "stronger", Any[])]

ordinary_values(d) = [x for x in d if !(x isa Invalid)]

"""
The `adapted` family's change (plan §7.2), from `s["adapt"]`:

- `seed`: one partial must-include row, the first parameter with two or more
  values set to its second value (the existing `seed` usage's `(p1 = 2,)`);
- `stronger`: the first min(6, n) parameters at strength + 1;
- `noop_scoped`: a rule over the first two parameters that excludes nothing;
- `forbid3`: three forbidden pairs, on parameters (1, 2), (3, 4) and (n − 1, n)
  where those differ, of first and last values;
- `invalid`: `Invalid(:adapted)` added to the first two parameters.

Changes `domains` and `rules` in place and returns `(must_include, stronger)`
to add to the request.
"""
function adapt!(s, names, domains, rules)
    adaptation = get(s, "adapt", nothing)
    must, stronger = Any[], Pair[]
    adaptation === nothing && return must, stronger
    n, t = length(names), s["strength"]
    if adaptation == "seed"
        p = findfirst(d -> length(ordinary_values(d)) >= 2, domains)
        push!(must, NamedTuple{(names[p],)}((ordinary_values(domains[p])[2],)))
    elseif adaptation == "stronger"
        g = min(6, n)
        t + 1 <= g || throw(ArgumentError("adapt = stronger needs at least $(t + 1) parameters"))
        push!(stronger, Tuple(names[1:g]) => t + 1)
    elseif adaptation == "noop_scoped"
        push!(rules, forbid((a, b) -> false, names[1], names[2]))
    elseif adaptation == "forbid3"
        pairs = filter(((i, j),) -> i < j <= n, unique([(1, 2), (3, 4), (n - 1, n), (1, 3), (2, 4), (1, 4)]))
        length(pairs) >= 3 || throw(ArgumentError("adapt = forbid3 needs at least 3 parameters"))
        for (k, (i, j)) in enumerate(pairs[1:3])
            a, b = ordinary_values(domains[i]), ordinary_values(domains[j])
            x = k == 1 ? (first(a), first(b)) : k == 2 ? (last(a), first(b)) : (last(a), last(b))
            push!(rules, forbid(NamedTuple{(names[i], names[j])}(x)))
        end
    elseif adaptation == "invalid"
        foreach(p -> push!(domains[p], Invalid(:adapted)), 1:min(2, n))
    else
        throw(ArgumentError("unknown adaptation: $adaptation"))
    end
    return must, stronger
end
