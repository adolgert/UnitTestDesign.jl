# A reference sweep of UnitTestDesign.jl, for a person to read at a review.
#
#     julia benchmark/reference_sweep.jl           # the names nothing public reaches
#     julia benchmark/reference_sweep.jl TABLE     # one table, tab-separated
#
# It parses every .jl file under src/, test/, benchmark/ (except this one),
# docs/, paper/ and design/, and finds each function, macro and type that
# src/ defines at top level and each reference to it. From the public entry
# points (exported names, names in a docs/src @docs block, methods added to
# other modules' functions, and module-level code) it follows references
# within src/, and it prints each name they never reach, with its
# definitions and its reference counts by directory. It writes no files.
#
# The list is for a person to judge, not a gate. Julia reaches methods
# through dispatch, iteration protocols, callbacks and operators with no
# textual reference to the definition; a count per name cannot tell a used
# method from an unused method of the same function; and a name bound
# locally is told from the global one by a heuristic.
#
# TABLE is one of
#     names      every top-level name in src/: kinds, definitions, whether it is
#                exported, documented and reachable, and references by directory
#     refs       every reference to such a name: file, line, kind, enclosing definition
#     shadowed   the references left out because a local binding shadows the name
#     locals     the functions src/ defines inside other definitions
#     callgraph  for each top-level definition in src/, the src/ names it references
#
# First written as probe 05a for design/components_review_verification.md
# (section 5), which wrote these tables to files beside the script.

const ROOT = dirname(@__DIR__)

jlfiles(dir) = sort([joinpath(r, f) for (r, _, fs) in walkdir(joinpath(ROOT, dir)) for f in fs
                     if endswith(f, ".jl") && !occursin("/docs/build", r) && joinpath(r, f) != @__FILE__])

const AREAS = ["src", "test", "benchmark", "docs", "paper", "design"]
const FILES = Dict(a => jlfiles(a) for a in AREAS)

rel(f) = replace(f, ROOT * "/" => "")

# ---------------------------------------------------------------- definitions

mutable struct Def
    name::String          # "foo", "Base.show", "@forbid"
    kind::Symbol          # :function, :macro, :type, :extension
    file::String
    line::Int
    local_to::String      # enclosing function name, "" for top level
end

# One reference: name, file, line, kind (:call, :value, :qualified, :macro, :import, :broadcast), context def
struct Ref
    name::String
    file::String
    line::Int
    kind::Symbol
    context::String       # enclosing top-level definition name, or "toplevel"
end

defs = Def[]
refs = Ref[]

"The function name and whether it is qualified, from a signature expression."
function signame(sig)
    while sig isa Expr && sig.head in (:where, :(::)) && !(sig.head == :(::) && length(sig.args) == 1)
        sig = sig.args[1]
    end
    sig isa Expr && sig.head == :call || return nothing
    f = sig.args[1]
    if f isa Symbol
        return (string(f), false, sig)
    elseif f isa Expr && f.head == :curly && f.args[1] isa Symbol
        return (string(f.args[1]), false, sig)
    elseif f isa Expr && f.head == :. && length(f.args) == 2 && f.args[2] isa QuoteNode
        return (string(f.args[1], ".", f.args[2].value), true, sig)
    elseif f isa Expr && f.head == :(::)   # callable object (x::T)(...)
        return ("(callable)" * string(f.args[end]), true, sig)
    end
    return nothing
end

structname(x) = x isa Symbol ? string(x) :
                x isa Expr && x.head == :curly ? structname(x.args[1]) :
                x isa Expr && x.head == :<: ? structname(x.args[1]) : string(x)

const IMPORTED = Set{String}()   # names from `import Base: x` in src

# Walk the binding side of a signature/assignment: skip bound names, walk types and defaults.
function walk_binding(x, st)
    if x isa Symbol
        return
    elseif x isa Expr
        if x.head == :(::)
            length(x.args) == 2 ? walk(x.args[2], st) : walk(x.args[1], st)
        elseif x.head == :kw || x.head == :(=)
            walk_binding(x.args[1], st); walk(x.args[2], st)
        elseif x.head in (:tuple, :parameters)
            foreach(a -> walk_binding(a, st), x.args)
        elseif x.head == :...
            walk_binding(x.args[1], st)
        elseif x.head == :ref || x.head == :.
            walk(x, st)       # a[i] = ..., x.f = ... : these read a and x
        else
            walk(x, st)
        end
    end
end

mutable struct State
    file::String
    line::Int
    context::String     # top-level def name or "toplevel"
    depth::Int          # function nesting depth
    bound::Vector{Set{Symbol}}   # names bound locally in enclosing scopes
end
State(file, line, context, depth) = State(file, line, context, depth, Set{Symbol}[])

"Names bound by a binding form (argument list, assignment target, loop variable)."
function binding_syms!(acc, x)
    if x isa Symbol
        push!(acc, x)
    elseif x isa Expr
        if x.head == :(::)
            length(x.args) == 2 && binding_syms!(acc, x.args[1])
        elseif x.head in (:kw, :(=))
            binding_syms!(acc, x.args[1])
        elseif x.head in (:tuple, :parameters, :..., :block)
            foreach(a -> binding_syms!(acc, a), x.args)
        elseif x.head == :call   # local function definition f(x) = ...: binds f
            f = x.args[1]
            f isa Symbol && push!(acc, f)
        elseif x.head == :where
            binding_syms!(acc, x.args[1])
        end
    end
    return acc
end

"Every name assigned, looped over, caught, or taken as a closure argument anywhere in `x`."
function bound_in!(acc, x)
    x isa Expr || return acc
    h = x.head
    if h in (:tuple, :parameters)
        # named tuple fields and keyword arguments are not bindings: (a = f(x),)
        for a in x.args
            if a isa Expr && a.head in (:(=), :kw)
                bound_in!(acc, a.args[2])
            else
                bound_in!(acc, a)
            end
        end
        return acc
    elseif h == :call || h == :macrocall
        # keyword arguments in calls: f(x; k = v) or f(x, k = v)
        for a in x.args
            if a isa Expr && a.head == :kw
                bound_in!(acc, a.args[2])
            else
                bound_in!(acc, a)
            end
        end
        return acc
    elseif h == :(=) || h == :local
        binding_syms!(acc, x.args[1])
    elseif h == :-> 
        binding_syms!(acc, x.args[1])
    elseif h == :try && length(x.args) >= 2 && x.args[2] isa Symbol
        push!(acc, x.args[2])
    elseif h == :function && length(x.args) >= 1
        s = x.args[1]
        while s isa Expr && s.head in (:where, :(::)) && length(s.args) >= 1
            s = s.args[1]
        end
        s isa Expr && s.head == :call && s.args[1] isa Symbol && push!(acc, s.args[1])
        s isa Expr && s.head == :call && foreach(a -> binding_syms!(acc, a), s.args[2:end])
    elseif h in (:quote,)
        return acc
    end
    foreach(a -> bound_in!(acc, a), x.args)
    return acc
end

const SHADOWED = Ref[]
function addref!(st, name, kind)
    r = Ref(string(name), st.file, st.line, kind, st.context)
    if name isa Symbol && kind in (:value, :call, :broadcast) && any(b -> name in b, st.bound)
        push!(SHADOWED, r)
    else
        push!(refs, r)
    end
end

function define!(st, name, kind)
    push!(defs, Def(name, kind, st.file, st.line, st.depth > 0 ? st.context : ""))
end

function walk_def(sig, body, st; kind = :function)
    s = signame(sig)
    if s === nothing
        # `function foo end` or odd forms
        if sig isa Symbol
            define!(st, string(sig), kind)
        end
        walk(body, st); return
    end
    name, qualified, call = s
    k = qualified ? :extension : (name in IMPORTED ? :extension : kind)
    define!(st, name, k)
    saved = st.context
    st.depth == 0 && (st.context = name)
    st.depth += 1
    b = Set{Symbol}()
    foreach(a -> binding_syms!(b, a), call.args[2:end])
    bound_in!(b, body)
    push!(st.bound, b)
    # arguments: bindings; where-clause params: skip
    for a in call.args[2:end]
        walk_binding(a, st)
    end
    # return type annotation
    s2 = sig
    while s2 isa Expr && s2.head in (:where, :(::))
        if s2.head == :(::) && length(s2.args) == 2
            walk(s2.args[2], st)
        end
        s2 = s2.args[1]
    end
    walk(body, st)
    pop!(st.bound)
    st.depth -= 1
    st.context = saved
end

function walk(x, st::State)
    if x isa LineNumberNode
        st.line = x.line
    elseif x isa Symbol
        addref!(st, x, :value)
    elseif x isa QuoteNode
        # :sym values and field names are not references
    elseif x isa Expr
        h = x.head
        if h == :function && length(x.args) >= 1
            walk_def(x.args[1], length(x.args) >= 2 ? x.args[2] : nothing, st)
        elseif h == :function
            nothing
        elseif h == :macro
            name = "@" * string(x.args[1].args[1])
            define!(st, name, :macro)
            saved = st.context; st.depth == 0 && (st.context = name); st.depth += 1
            walk(x.args[2], st)
            st.depth -= 1; st.context = saved
        elseif h == :(=) && signame(x.args[1]) !== nothing && !(x.args[1] isa Expr && x.args[1].head == :call &&
                                                                x.args[1].args[1] isa Expr && x.args[1].args[1].head == :.
                                                                && !(x.args[1].args[1].args[2] isa QuoteNode))
            walk_def(x.args[1], x.args[2], st)
        elseif h == :(=) || h == :const || h == :local || h == :global
            if h == :(=)
                walk_binding(x.args[1], st); walk(x.args[2], st)
            else
                foreach(a -> walk(a, st), x.args)
            end
        elseif h == :struct
            name = structname(x.args[2])
            define!(st, name, :type)
            saved = st.context; st.depth == 0 && (st.context = name)
            # supertype
            x.args[2] isa Expr && x.args[2].head == :<: && walk(x.args[2].args[2], st)
            for a in x.args[3].args
                if a isa Expr && a.head == :(::)
                    walk(a.args[end], st)       # field type
                elseif a isa Symbol
                    # untyped field
                else
                    walk(a, st)                 # inner constructors, line nodes
                end
            end
            st.context = saved
        elseif h == :abstract || h == :primitive
            define!(st, structname(x.args[1]), :type)
        elseif h == :call
            f = x.args[1]
            if f isa Symbol
                addref!(st, f, :call)
            elseif f isa Expr && f.head == :curly && f.args[1] isa Symbol
                addref!(st, f.args[1], :call)
                foreach(a -> walk(a, st), f.args[2:end])
            else
                walk(f, st)
            end
            for a in x.args[2:end]
                if a isa Expr && a.head == :kw
                    walk(a.args[2], st)
                elseif a isa Expr && a.head == :parameters
                    for p in a.args
                        p isa Expr && p.head == :kw ? walk(p.args[2], st) : walk(p, st)
                    end
                else
                    walk(a, st)
                end
            end
        elseif h == :. && length(x.args) == 2 && x.args[2] isa QuoteNode
            # qualified name or field access
            if x.args[1] === :UnitTestDesign
                addref!(st, x.args[2].value, :qualified)
            else
                walk(x.args[1], st)
            end
        elseif h == :. && length(x.args) == 2 && x.args[2] isa Expr && x.args[2].head == :tuple
            # broadcast f.(args)
            f = x.args[1]
            f isa Symbol ? addref!(st, f, :broadcast) : walk(f, st)
            walk(x.args[2], st)
        elseif h == :macrocall
            m = x.args[1]
            if m in (Symbol("@testitem"), Symbol("@testsnippet"), Symbol("@testmodule"), Symbol("@testset"))
                b = Set{Symbol}()
                foreach(a -> bound_in!(b, a), x.args[2:end])
                push!(st.bound, b)
                addref!(st, m, :macro)
                foreach(a -> walk(a, st), x.args[2:end])
                pop!(st.bound)
                return
            end
            if m isa Symbol
                addref!(st, m, :macro)
            elseif m isa Expr && m.head == :. && m.args[1] === :UnitTestDesign
                addref!(st, m.args[2].value, :macro)
            else
                m isa GlobalRef || walk(m, st)
            end
            foreach(a -> walk(a, st), x.args[2:end])
        elseif h == :->
            walk_binding(x.args[1], st); walk(x.args[2], st)
        elseif h == :using || h == :import
            for a in x.args
                if a isa Expr && a.head == :(:)
                    mod = a.args[1]
                    frommod = mod isa Expr ? join(string.(mod.args), ".") : string(mod)
                    for b in a.args[2:end]
                        nm = string(b.args[end])
                        if frommod == "UnitTestDesign"
                            addref!(st, nm, :import)
                        elseif frommod == "Base" && occursin("/src/", st.file) && h == :import
                            push!(IMPORTED, nm)
                        end
                    end
                end
            end
        elseif h == :kw
            walk(x.args[2], st)
        elseif h == :where
            walk(x.args[1], st)
        elseif h == :module
            walk(x.args[3], st)
        else
            foreach(a -> walk(a, st), x.args)
        end
    end
end

# src first so IMPORTED is set; then the others
for area in AREAS, file in FILES[area]
    text = read(file, String)
    ex = try
        Meta.parseall(text; filename = file)
    catch err
        println(stderr, "PARSE FAIL: $(rel(file)): $err"); continue
    end
    walk(ex, State(file, 1, "toplevel", 0))
end

# --------------------------------------------------------------- aggregation

srcdefs = filter(d -> startswith(rel(d.file), "src/"), defs)
exports = Set{String}()
for line in eachline(joinpath(ROOT, "src/UnitTestDesign.jl"))
    m = match(r"^\s*export\s+(.*)$", line)
    m === nothing && continue
    for n in split(m.captures[1], ",")
        push!(exports, strip(n))
    end
end
documented = Set{String}()
for (r, _, fs) in walkdir(joinpath(ROOT, "docs/src")), f in fs
    endswith(f, ".md") || continue
    inblock = false
    for line in eachline(joinpath(r, f))
        if startswith(line, "```@docs")
            inblock = true
        elseif inblock && startswith(line, "```")
            inblock = false
        elseif inblock
            push!(documented, strip(line))
        end
    end
end

area(f) = split(rel(f), "/")[1]
names = sort(unique(d.name for d in srcdefs if d.local_to == ""))
kinds = Dict{String, Set{Symbol}}()
for d in srcdefs
    d.local_to == "" && push!(get!(kinds, d.name, Set{Symbol}()), d.kind)
end
localdefs = filter(d -> d.local_to != "", srcdefs)

# Reference counts by area; "self" = inside a definition of the same name
function counts(name)
    c = Dict{String, Int}()
    self = 0
    for r in refs
        r.name == name || continue
        a = area(r.file)
        if a == "src" && r.context == name
            self += 1
        else
            c[a] = get(c, a, 0) + 1
        end
    end
    return c, self
end

# Call graph over src top-level names: context -> referenced defined names
defset = Set(names)
graph = Dict{String, Set{String}}()
for r in refs
    area(r.file) == "src" || continue
    r.name in defset || continue
    r.context == r.name && continue
    push!(get!(graph, r.context, Set{String}()), r.name)
end

# Seeds: exported names, extension methods (Base./Tables./...), module-level code, docs @docs names
seeds = Set{String}(["toplevel"])
union!(seeds, [n for n in names if n in exports])
union!(seeds, [n for n in names if :extension in kinds[n]])
union!(seeds, [n for n in names if n in documented])
reach = Set{String}()
stack = collect(seeds)
while !isempty(stack)
    n = pop!(stack)
    n in reach && continue
    push!(reach, n)
    for m in get(graph, n, Set{String}())
        m in reach || push!(stack, m)
    end
end

deffiles(name) = join(sort(unique("$(rel(d.file)):$(d.line)" for d in srcdefs if d.name == name && d.local_to == "")), " ")

# ------------------------------------------------------------------- output

function names_table(io)
    println(io, join(["name", "kinds", "defs", "exported", "documented", "reachable_from_public",
                      "src_refs", "src_self", "test_refs", "benchmark_refs", "docs_refs", "paper_refs", "design_refs"], '\t'))
    for n in names
        c, self = counts(n)
        println(io, join([n, join(sort(string.(collect(kinds[n]))), ","), deffiles(n),
                          n in exports, n in documented, n in reach,
                          get(c, "src", 0), self, get(c, "test", 0), get(c, "benchmark", 0),
                          get(c, "docs", 0), get(c, "paper", 0), get(c, "design", 0)], '\t'))
    end
end

function refs_table(io)
    println(io, join(["name", "file", "line", "kind", "context"], '\t'))
    for r in refs
        r.name in defset || continue
        println(io, join([r.name, rel(r.file), r.line, r.kind, r.context], '\t'))
    end
end

function shadowed_table(io)
    println(io, join(["name", "file", "line", "kind", "context"], '\t'))
    for r in SHADOWED
        r.name in defset || continue
        println(io, join([r.name, rel(r.file), r.line, r.kind, r.context], '\t'))
    end
end

function locals_table(io)
    println(io, join(["name", "kind", "file", "line", "enclosing"], '\t'))
    for d in localdefs
        println(io, join([d.name, d.kind, rel(d.file), d.line, d.local_to], '\t'))
    end
end

function callgraph_table(io)
    println(io, "definition\treferences")
    for (k, v) in sort(collect(graph); by = first)
        println(io, k, '\t', join(sort(collect(v)), ","))
    end
end

function unreachable_list(io)
    println(io, "src top-level names: ", length(names), "; exported: ", count(in(exports), names),
            "; reachable: ", length(intersect(reach, defset)))
    println(io, "unreachable from public entry points (by call graph):")
    for n in names
        n in reach && continue
        c, self = counts(n)
        println(io, "  ", rpad(n, 42), rpad(deffiles(n), 60), " src=", get(c, "src", 0), " test=", get(c, "test", 0),
                " bench=", get(c, "benchmark", 0), " docs=", get(c, "docs", 0), " kinds=", join(string.(collect(kinds[n])), ","))
    end
end

const TABLES = Dict("names" => names_table, "refs" => refs_table, "shadowed" => shadowed_table,
                    "locals" => locals_table, "callgraph" => callgraph_table)

if isempty(ARGS)
    unreachable_list(stdout)
elseif length(ARGS) == 1 && haskey(TABLES, ARGS[1])
    TABLES[ARGS[1]](stdout)
else
    println(stderr, "usage: julia benchmark/reference_sweep.jl [", join(sort(collect(keys(TABLES))), " | "), "]")
    exit(2)
end
