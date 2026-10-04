# Write uniform_shapes.csv: for every uniform shape the benchmark grid uses, the
# best-known size with its source and snapshot, the elementary lower bound, and
# the catalog's size (plan §7.1). Run from the repository root:
#
#     julia --project=. --startup-file=no benchmark/best_known/write_table.jl [OUT]
#
# The shapes come from the harness itself, `python3 benchmark/scaling/run.py
# --shapes`: every uniform, unconstrained covering spec of the default grid and
# of every generated family, expensive points included. summarize.py joins the
# results on (t, v, k) for rows over the best known and over the bound, and
# test_families.py checks that the file holds every shape the grid uses.
#
# `catalog` is the package's catalog size (BestKnown.catalog_rows, which calls
# UnitTestDesign._catalog_rows), empty where no entry applies; rerun this
# script when the catalog changes.
include(joinpath(@__DIR__, "BestKnown.jl"))
using .BestKnown

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const OUT = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "uniform_shapes.csv")

csv_field(x) = x === nothing || x === missing ? "" :
               (s = string(x); any(in(",\"\n"), s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s)

function shapes()
    text = read(Cmd(`python3 $(joinpath(ROOT, "benchmark", "scaling", "run.py")) --shapes`; dir = ROOT), String)
    return [Tuple(parse.(Int, split(line))) for line in split(strip(text), '\n')]
end

function main()
    rows = String["t,v,k,best_known,source,status,retrieved,lower_bound,catalog"]
    found = 0
    for (t, v, k) in shapes()
        b = best_known(t, v, k)
        found += b !== nothing
        fields = (t, v, k, b === nothing ? nothing : b.N, b === nothing ? nothing : b.source,
                  b === nothing ? nothing : b.status, b === nothing ? nothing : b.retrieved,
                  lower_bound(t, v, k), catalog_rows(t, v, k))
        push!(rows, join(map(csv_field, fields), ","))
    end
    write(OUT, join(rows, "\n") * "\n")
    println(length(rows) - 1, " shapes, ", found, " with a best-known size: ", OUT)
end
main()
