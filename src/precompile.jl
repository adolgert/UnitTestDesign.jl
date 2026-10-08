# The precompile workload (plan §5.1, decision D9). It runs once, while Julia
# precompiles the package, and the code it compiles is saved in the package
# image, so a fresh process's first space, design, display and measurement
# don't wait for compilation. It is plain code, with no dependency (D6).
#
# It runs only while Julia generates output (`jl_generating_output`): never
# when the package loads, so a session started with `--compiled-modules=no`
# doesn't pay for it. It prints nothing, writes no file and throws nothing,
# which test/test_precompile.jl checks by calling it.
#
# Each later phase adds its new engines and entry points here: first-call
# time is a gate for every phase (plan §5.1), measured by
# benchmark/first_call.jl.

"""
    _precompile_workload()

The calls a first session makes: the example on the front page of the
documentation, the tutorial's calls, each result's display, the default
engine `Auto()` (its plan, and its IPOG and catalog starts, which the front
page's example runs both of) and GND at strengths 2 and 3, `IPOG()` named,
spaces of other value types and rules, the row reducer `Compact`, the
catalog engine on an exact shape, `Auto(goal = :compact)` and `recommend`.
"""
function _precompile_workload()
    io = IOContext(IOBuffer(), :limit => true, :displaysize => (24, 80))
    text = MIME"text/plain"()
    # The front page's example (docs/src/index.md, README.md), with the default
    # engine, Auto(): its plan prepares IPOG's and the catalog's starts and,
    # on these three parameters, runs both and keeps IPOG's design.
    space = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])
    show(io, text, space)
    cases = all_pairs(space)
    show(io, text, cases)
    for (; mode, solver, tol) in cases
        show(io, (mode, solver, tol))
    end
    show(io, text, explain(space, (solver = :lu, tol = 1e-3)))
    handwritten = [(mode = :fast, solver = :none, tol = 1e-3), (mode = :exact, solver = :lu, tol = 1e-6)]
    show(io, text, coverage(handwritten, space))
    show(io, text, all_pairs(space; must_include = handwritten))
    # The tutorial's levels 3 and 4 (docs/src/man/tutorial.md).
    show(io, text, all_pairs(space; must_include = [(mode = :fast,), (solver = :qr,)]))
    show(io, text, all_triples(space))
    show(io, text, all_pairs(space; stronger = [(:mode, :solver, :tol) => 3]))
    show(io, text, all_pairs(space; engine = GND()))
    show(io, text, excursions(space; from = (mode = :exact, solver = :lu, tol = 1e-6), distance = 1))
    show(io, text, coverage(cases))
    show(io, text, report(cases))
    show(io, text, design_sizes(space))
    # Other value types, a scoped rule given as a function, and strength 3.
    other = TestSpace((n = 1:3, name = ["a", "b"], flag = [true, false], level = [1.0, 2.0]);
                      constraints = [@forbid(n == 1 && flag),
                                     forbid((n, name) -> n == 3 && name == "b", :n, :name)])
    show(io, text, covering(other; strength = 3))
    show(io, text, covering(other; strength = 3, engine = GND()))
    # Lists of values, positional and named (the tutorial's levels 0 and 1).
    show(io, text, all_pairs([1, 2, 3], ["a", "b"], [1.0, 2.0]))
    show(io, text, all_pairs(:mode => [:fast, :exact], :solver => [:none, :lu, :qr], :tol => [1e-3, 1e-6]))
    # The row reducer (plan §5.3), on the front page's space and at strength 3.
    show(io, text, all_pairs(space; engine = Compact(IPOG())))
    show(io, text, covering(other; strength = 3, engine = Compact(IPOG())))
    # The catalog engine (plan §5.4) on an exact shape: one call compiles the
    # lookup, every builder and the engine. A strength-3 call and a seeded
    # one, tried here too, made no first call faster and cost precompile time.
    uniform = TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:3, e = 1:3))
    show(io, text, all_pairs(uniform; engine = Construction()))
    # Auto(goal = :compact) and recommend (plan §6.1): on the uniform space Auto
    # runs both starts and reduces the smaller. IPOG() named, as a caller who
    # wants IPOG's design writes it, outside Auto's plan.
    show(io, text, all_pairs(uniform; engine = Auto(goal = :compact)))
    show(io, text, all_pairs(space; engine = IPOG()))
    show(io, text, recommend(uniform))
    show(io, text, recommend(space))
    return nothing
end

ccall(:jl_generating_output, Cint, ()) == 1 && _precompile_workload()
