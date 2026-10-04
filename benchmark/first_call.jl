# The first call in a fresh process (solver plan §5.1): the example on the
# front page of the documentation (docs/src/index.md, README.md), timed from
# `using UnitTestDesign` to its first displayed result, each run in a new
# process so that no earlier call compiled what it needs. Every phase of the
# solver plan reports this number, so its precompile workload
# (src/precompile.jl) is checked against it. Dependency-free.
#
#     julia --project=. benchmark/first_call.jl [--runs N] [--precompile]
#
# Each run is a child process of the same Julia, in the same project, which
# prints one line of figures; the script prints every run and the median of
# each figure, in seconds:
#
#     load     `using UnitTestDesign`
#     space    the example's `TestSpace`, with its two rules
#     pairs    the first `all_pairs(space)`
#     show     the cases' display, as the REPL shows them, into a buffer
#     example  space + pairs + show: the gate, under 0.5 s (plan §5.1)
#     rest     the rest of the front page's example: `explain`, `coverage`
#              and `must_include`, each displayed
#     other    a second space with other names, value types and rule, its
#              pairs and their display: what a user's own first space costs,
#              which no workload can compile in advance
#
# With `--precompile` it first times `Base.compilecache` of the package in a
# child process: the one-time cost of precompiling, which the workload
# raises. That writes one more cache file to the depot, as `Pkg.precompile`
# would after an edit.
#
# Run it against another checkout through that checkout's environment, and
# on Julia 1.10 through an environment that develops the checkout:
#
#     julia --project=../base benchmark/first_call.jl
#     julia +lts --project=<environment> benchmark/first_call.jl
#
# Timings depend on the machine and on what else it is running; repeat them
# on a quiet machine before comparing two checkouts.

"The child process's code, evaluated statement by statement as a user's session would be."
const CHILD = raw"""
t0 = time_ns()
using UnitTestDesign
t1 = time_ns()
space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
t2 = time_ns()
cases = all_pairs(space)
t3 = time_ns()
io = IOContext(IOBuffer(), :limit => true, :displaysize => (24, 80))
show(io, MIME"text/plain"(), cases)
t4 = time_ns()
show(io, MIME"text/plain"(), explain(space, (solver = :lu, tol = 1e-3)))
handwritten = [(mode = :fast, solver = :none, tol = 1e-3),
               (mode = :exact, solver = :lu, tol = 1e-6)]
show(io, MIME"text/plain"(), coverage(handwritten, space))
show(io, MIME"text/plain"(), all_pairs(space; must_include = handwritten))
t5 = time_ns()
other = TestSpace((window = [1, 3, 5], boundary = [:clamp, :reflect, :periodic],
                   kernel = [:box, :triangle, :gaussian], n = [1.0, 4.0, 100.0]);
                  constraints = [@forbid(window == 1 && kernel != :box)])
show(io, MIME"text/plain"(), all_pairs(other))
t6 = time_ns()
seconds(a, b) = round((b - a) / 1e9; digits = 3)
println(join((seconds(t0, t1), seconds(t1, t2), seconds(t2, t3), seconds(t3, t4), seconds(t1, t4),
              seconds(t4, t5), seconds(t5, t6)), " "))
"""

"The child process that times `Base.compilecache` of the package."
const PRECOMPILE = raw"""
package = Base.identify_package("UnitTestDesign")
println(round(@elapsed(Base.compilecache(package)); digits = 2))
"""

const FIGURES = ("load", "space", "pairs", "show", "example", "rest", "other")

median(x) = (s = sort(x); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)

function main(args)
    i = findfirst(==("--runs"), args)
    runs = i === nothing ? 5 : parse(Int, args[i + 1])
    julia = `$(Base.julia_cmd()) --project=$(Base.active_project()) --startup-file=no`
    source = Base.locate_package(Base.identify_package("UnitTestDesign"))
    println("Julia ", VERSION, ", UnitTestDesign from ", source, ", ", runs, " fresh processes")
    if "--precompile" in args
        println("precompile: ", readchomp(`$julia -e $PRECOMPILE`), " s")
    end
    # Untimed: make sure the package image is current before the first run.
    run(pipeline(`$julia -e "using UnitTestDesign"`; stdout = devnull))
    println(rpad("run", 8), join((lpad(f, 8) for f in FIGURES)))
    results = Vector{Vector{Float64}}()
    for run in 1:runs
        figures = parse.(Float64, split(readchomp(`$julia -e $CHILD`)))
        push!(results, figures)
        println(rpad(run, 8), join((lpad(f, 8) for f in figures)))
    end
    medians = [median([r[k] for r in results]) for k in eachindex(FIGURES)]
    println(rpad("median", 8), join((lpad(round(m; digits = 3), 8) for m in medians)))
end

main(ARGS)
