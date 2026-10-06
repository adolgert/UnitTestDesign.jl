# Fixed requests whose rows from IPOG's lookup core (`_IPOGLookup`, plan §5.5)
# test_ipog_core.jl compares with ipog_core_rows.txt, as text, so that the same
# rows are checked in another process and on each Julia version (contract §9.1,
# §9.4). No random stream: Julia 1.10's differ from 1.13's. To write the file
# again after a change to the core's rows, on Julia 1.13, from the repository root:
#
#     julia --project=. -e 'include("test/ipog_core_requests.jl");
#                           write("test/ipog_core_rows.txt", join(lookup_rows_text(), "\n"), "\n")'

using UnitTestDesign
using UnitTestDesign: Request, generate, _IPOGLookup, _TIEBREAKS

"Each request's rows from the lookup core, as lines: a header naming the request, then one line per row."
function lookup_rows_text()
    grid(arity; kwargs...) = TestSpace((Symbol(:p, i) => collect(1:a) for (i, a) in enumerate(arity))...; kwargs...)
    mixed = grid([5, 4, 3, 3, 2, 2, 2]; constraints = [forbid((p1 = 1, p2 = 2)), forbid((p3 = 3, p4 = 3))])
    requests = Pair{String, Request}[
        "3^10, strength 2" => Request(grid(fill(3, 10))),
        "3^10, strength 3" => Request(grid(fill(3, 10)); strength = 3),
        "2^20, strength 4" => Request(grid(fill(2, 20)); strength = 4),
        "mixed with two rules" => Request(mixed),
        "mixed, a partial must-include row and a stronger group" =>
            Request(mixed; must_include = [(p2 = 3, p5 = 1)], stronger = [(:p1, :p3, :p4, :p6) => 3]),
        "mixed at strength 3" => Request(mixed; strength = 3)]
    lines = String[]
    for (label, request) in requests
        engines = label == "3^10, strength 2" ? [_IPOGLookup(; tiebreak) for tiebreak in _TIEBREAKS] :
                  [_IPOGLookup(), _IPOGLookup(vertical = :value)]
        label == "mixed with two rules" && push!(engines, _IPOGLookup(tiebreak = (:lowest, :rotate), vertical = (:support, :value)))
        for engine in engines
            matrix = generate(engine, request).matrix
            push!(lines, "# $label, $engine: $(size(matrix, 2)) rows")
            append!(lines, (join(c, " ") for c in eachcol(matrix)))
        end
    end
    # Negative rows, through the public call.
    space = TestSpace((a = [1, 2, Invalid(0)], b = [:x, :y, :z], c = 1:3, d = [true, false]))
    cases = all_pairs(space; engine = _IPOGLookup())
    push!(lines, "# a space with an Invalid value: $(length(cases)) cases")
    append!(lines, (join((repr(x) for x in values(c)), " ") for c in cases))
    return lines
end
