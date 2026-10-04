# The best-known covering-array sizes and the elementary lower bound, for the
# benchmark's uniform shapes (plan §7.1). Standard library only, plus the
# package for the catalog hook; runs in the package's or the benchmark's
# environment:
#
#     include("benchmark/best_known/BestKnown.jl")
#     BestKnown.best_known(2, 2, 1024)    # (N = 14, source = "Kleitman and Spencer, or Katona", ...)
#     BestKnown.lower_bound(3, [7, 5, 4]) # 140
#
# colbourn_tables.csv is the data; README.md says where it comes from.
module BestKnown

using UnitTestDesign: UnitTestDesign

export best_known, lower_bound, catalog_rows

const TABLES = joinpath(@__DIR__, "colbourn_tables.csv")

"One table line: N rows are known to suffice for up to k columns."
const Line = @NamedTuple{k::Int, N::Int, source::String, status::String, retrieved::String}

"The fields of one CSV line, with RFC 4180 quoting (a quoted field may hold commas and doubled quotes)."
function csv_fields(line::AbstractString)
    fields = String[]
    field = IOBuffer()
    quoted = false
    i = firstindex(line)
    while i <= lastindex(line)
        c = line[i]
        if quoted
            if c == '"'
                j = nextind(line, i)
                if j <= lastindex(line) && line[j] == '"'
                    write(field, '"'); i = j
                else
                    quoted = false
                end
            else
                write(field, c)
            end
        elseif c == '"'
            quoted = true
        elseif c == ','
            push!(fields, String(take!(field)))
        else
            write(field, c)
        end
        i = nextind(line, i)
    end
    push!(fields, String(take!(field)))
    return fields
end

"`(t, v) => lines` with k ascending, from `path`."
function load(path::AbstractString = TABLES)
    tables = Dict{Tuple{Int, Int}, Vector{Line}}()
    lines = eachline(path)
    header = csv_fields(first(lines))
    header == ["t", "v", "k", "N", "source", "status", "retrieved"] || error("unexpected header in $path: $header")
    for line in lines
        isempty(line) && continue
        t, v, k, N, source, status, retrieved = csv_fields(line)
        push!(get!(tables, (parse(Int, t), parse(Int, v)), Line[]),
              (k = parse(Int, k), N = parse(Int, N), source, status, retrieved))
    end
    foreach(lines -> sort!(lines; by = l -> l.k), values(tables))
    return tables
end

const TABLE = Ref{Dict{Tuple{Int, Int}, Vector{Line}}}()
tables() = isassigned(TABLE) ? TABLE[] : (TABLE[] = load())

function isprimepower(q::Int)
    q >= 2 || return false
    p = first(d for d in 2:q if q % d == 0)
    while q % p == 0
        q ÷= p
    end
    return q == 1
end

"""
    best_known(t, v, k) -> NamedTuple or nothing

The fewest rows known for `k` parameters of `v` values at strength `t`, as
`(; N, source, status, retrieved)`. The rule (plan, appendix): the smallest N
among the table's lines whose k is at least the given k. `nothing` when the
tables have a page for (t, v) but no line reaches k.

Where the tables have no page for (t, v), the one size that needs no table is
given: `v^t`, the lower bound, which an orthogonal array meets for k ≤ t + 1
(the zero-sum array; Chateauneuf & Kreher 2002, Theorem 2.1) and, when v is a
prime power with t ≤ v, for k ≤ v + 1 (Bush). Its `status` is `"derived"`.
This is how the plan's §2.1 gives 1,024 and 4,096 for 8 × 32 and 8 × 64.
"""
function best_known(t::Integer, v::Integer, k::Integer)
    lines = get(tables(), (Int(t), Int(v)), nothing)
    if lines === nothing
        bound = Int(v)^t
        if k <= t + 1
            return (N = bound, source = "zero-sum orthogonal array, equal to the lower bound", status = "derived", retrieved = "")
        elseif isprimepower(Int(v)) && t <= v && k <= v + 1
            return (N = bound, source = "orthogonal array (Bush), equal to the lower bound", status = "derived", retrieved = "")
        end
        return nothing
    end
    reaching = [l for l in lines if l.k >= k]
    isempty(reaching) && return nothing
    best = reaching[argmin([l.N for l in reaching])]
    return (N = best.N, source = best.source, status = best.status, retrieved = best.retrieved)
end

"""
    lower_bound(t, values) -> Int

The elementary lower bound for strength `t` on parameters with these value
counts: the product of the `t` largest. Every row covers one combination of
those `t` parameters, and each of their combinations needs a row. For a
uniform space it is `v^t`.
"""
lower_bound(t::Integer, values::AbstractVector{<:Integer}) = prod(Int, sort(values; rev = true)[1:min(t, length(values))]; init = 1)
lower_bound(t::Integer, v::Integer, k::Integer) = lower_bound(t, fill(v, k))

# The hook for the catalog's size (Phase 2, plan §5.4: "each entry says, for a
# strength, a number of parameters and a number of values, what size it
# would give, without building anything"). When the package defines
# `UnitTestDesign._catalog_rows(t, v, k)`, returning an Int or `nothing`, the
# `catalog` column fills; Phase 2 either uses that name or edits this one line.
const CATALOG_LOOKUP = :_catalog_rows

"""
    catalog_rows(t, v, k) -> Union{Int, Nothing, Missing}

The `Construction` engine's size for the shape: `missing` while the package
has no catalog lookup (today), `nothing` when it has one and no entry applies.
"""
function catalog_rows(t::Integer, v::Integer, k::Integer)
    isdefined(UnitTestDesign, CATALOG_LOOKUP) || return missing
    return Base.invokelatest(getfield(UnitTestDesign, CATALOG_LOOKUP), Int(t), Int(v), Int(k))
end

end # module
