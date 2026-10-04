# Named spaces for the benchmark families (plan §7.2), included by worker.jl.
# A spec selects one with "space": "<name>". Each entry returns the space's
# pieces `(names, domains, rules)`, so the worker builds one TestSpace inside
# its timed construction, after any adaptation adds values or rules.
#
# The docs' examples are copied from the manual, with the file they came from,
# so that a docs edit doesn't move a benchmark point. Probe 25's fixtures are
# copied from design/20261003_solver_plan_review_probes/25_exact_minimum.jl.
# `bench12` comes from test/fixtures.jl through benchmark/fixtures.jl, which is
# loaded only when a spec asks for it.

"Positional pieces for a named tuple of domains and a list of rules."
pieces(domains::NamedTuple, rules = Constraint[]) =
    (collect(Symbol, keys(domains)), [Any[d...] for d in values(domains)], Constraint[rules...])
indexed(arity) = NamedTuple{Tuple(Symbol(:p, i) for i in eachindex(arity))}(Tuple(collect(1:a) for a in arity))

const SOLVER_RULES = () -> [@require(mode == :exact || solver == :none),
    forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance")]
needs_two(n, boundary) = n == 1 && boundary == :periodic
const BENCH_INTS = [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128]
const MIX1 = [7, 7, 7, 7, 5, 4, 3, 3, 2, 2, 2, 2]

const NAMED_SPACES = Dict{String, Function}(
    # docs/src/index.md:38 (also man/tutorial.md:163, man/agents.md:39, howto/commit_design.md:14,
    # howto/diagnose.md:106, explain/coverage_evidence.md:98)
    "docs-solver" => () -> pieces((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]), SOLVER_RULES()),
    # docs/src/man/tutorial.md:96
    "docs-solver-plain" => () -> pieces((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6])),
    # docs/src/man/tutorial.md:268; the manual asks for triples, and for pairs with (:n, :tol, :kind) => 3
    "docs-wide" => () -> pieces((n = [1, 2, 3], level = ["low", "mid", "high"], tol = [1.0, 3.7, 4.9],
                                 kind = [:greedy, :relax, :optim])),
    # docs/src/man/tutorial.md:357
    "docs-negative" => () -> pieces((mode = [:fast, :exact], solver = [:none, :lu, :qr],
                                     tol = [1e-3, 1e-6, Invalid(0.0), Invalid(-1.0)]), SOLVER_RULES()),
    # docs/src/man/tutorial.md:565
    "docs-hilbert" => () -> pieces((axis = BENCH_INTS, index = BENCH_INTS, offset = [0, 1], dims = [2, 3, 4],
                                    bits = [2, 3, 4, 5]),
                                   [@forbid(bits * dims > log2(typemax(index))), @forbid(bits * dims > log2(typemax(axis)))]),
    # docs/src/explain/constraints.md:29
    "docs-rules" => () -> pieces((os = [:linux, :mac, :windows], gpu = [false, true], driver = [:cuda, :none]),
                                 [@forbid(gpu && driver == :none),
                                  forbid((os = :windows, driver = :cuda); reason = "no CUDA on Windows")]),
    # docs/src/explain/values_and_oracles.md:56; pairs, pairs with 3:6 => 3, and triples
    "docs-spend" => () -> pieces(indexed(fill(4, 40))),
    # docs/src/howto/invalid_inputs.md:34
    "docs-periodic" => () -> pieces((n = [1, 2, 50], spacing = [0.1, 1.0], boundary = [:open, :periodic]),
                                    [forbid(needs_two, :n, :boundary; reason = "a periodic grid needs two points")]),
    # docs/src/howto/invalid_inputs.md:70
    "docs-periodic-invalid" => () -> pieces((n = [1, 2, 50, Invalid(0), Invalid(-3)],
                                             spacing = [0.1, 1.0, Invalid(0.0), Invalid(NaN)],
                                             boundary = [:open, :periodic, Invalid(:closed)]),
                                            [forbid(needs_two, :n, :boundary; reason = "a periodic grid needs two points")]),
    # docs/src/howto/diagnose.md:23 (also man/tutorial.md:417)
    "docs-diagnose" => () -> pieces((n = [10, 100, 1000], method = [:newton, :bicg, :gmres], tol = [1e-3, 1e-6],
                                     sparse = [false, true])),
    # docs/src/man/agents.md:76
    "docs-types" => () -> pieces((elt = [Int8, UInt8, Int32, Float32, Float64], acc = [Int64, Float64, BigInt],
                                  n = [0, 1, 100]),
                                 [forbid((elt, acc) -> elt <: AbstractFloat && acc <: Integer, :elt, :acc;
                                         reason = "an integer accumulator cannot hold a float sum")]),
    # docs/src/howto/many_options.md:35; also probe 25's "docs example (smooth)", minimum 11
    "docs-smooth" => () -> pieces((window = [1, 3, 5], boundary = [:clamp, :reflect, :periodic],
                                   kernel = [:box, :triangle, :gaussian], n = [1, 4, 100]),
                                  [@forbid(window == 1 && kernel != :box),
                                   @forbid(boundary == :reflect && n <= window ÷ 2;
                                           reason = "reflect needs more points than half the window")]),
    # docs/src/howto/simulation_campaign.md:13; the manual asks for (:R0, :contact, :vaccination) => 3
    "docs-campaign" => () -> pieces((R0 = [0.9, 1.5, 3.0], population = [1_000, 100_000, 10_000_000],
                                     contact = [:homogeneous, :household, :network], vaccination = [0.0, 0.3, 0.7],
                                     stepper = [:euler, :rk4, :adaptive], seasonal = [false, true]),
                                    [forbid((contact = :network, population = 10_000_000);
                                            reason = "the network model is too slow at this size")]),
    # docs/src/howto/ci_matrix.md:15
    "docs-ci" => () -> pieces((os = ["ubuntu-latest", "macos-latest", "windows-latest"],
                               julia = ["1.10", "1.12", "nightly"], threads = [1, 4], mkl = [false, true]),
                              [@forbid(os == "macos-latest" && mkl)]),
    # docs/src/howto/audit_existing.md:32
    "docs-interp" => () -> pieces((method = [:nearest, :linear, :cubic], boundary = [:error, :clamp, :extrapolate],
                                   grid = [:uniform, :irregular], T = [Float64, Float32]),
                                  [@forbid(method == :nearest && boundary == :extrapolate)]),
    # docs/src/howto/generic_types.md:18
    "docs-generic" => () -> pieces((T = [Float32, Float64, BigFloat], container = [:vector, :strided_view, :column_matrix],
                                    n = [0, 1, 10_000]),
                                   [forbid((T = BigFloat, n = 10_000); reason = "BigFloat is slow at this size")]),
    # Probe 25, part 1: spaces whose minimum the probe proved or bounded.
    "probe25-warmup" => () -> pieces(indexed([2, 2, 2, 2]), [forbid((p1 = 1, p2 = 1))]),
    "probe25-flags" => () -> pieces(indexed(fill(2, 12)),
                                    [@forbid(p1 == 2 && p2 == 1), @forbid(p3 == 2 && p4 == 1),
                                     @forbid(p5 == 2 && p1 == 1), @forbid(p6 == 2 && p7 == 2)]),
    "probe25-mix1" => () -> pieces(indexed(MIX1)),
    "probe25-mix1-forbid3" => () -> pieces(indexed(MIX1), [forbid((p1 = 1, p2 = 1)), forbid((p3 = 2, p5 = 4)),
                                                          forbid((p2 = 7, p9 = 1))]),
    "probe25-mix1-neq" => () -> pieces(indexed(MIX1), [@forbid(p1 == p2)]),
    "probe25-mix1-less" => () -> pieces(indexed(MIX1), [@require(p1 < p2)]),
    "probe25-neighbours" => () -> pieces(indexed(fill(4, 10)),
                                         [forbid((a, b) -> a == b, Symbol(:p, i), Symbol(:p, i + 1)) for i in 1:9]),
    # test/fixtures.jl's bench12, the heterogeneous fixture with four rules
    "bench12" => () -> bench12_pieces(),
)

function bench12_pieces()
    input = Main.BenchFixtures.bench12.input
    rules = Constraint[Main.BenchFixtures.model_rule(input.names, r) for r in input.rules]
    return (collect(Symbol, input.names), [Any[Main.BenchFixtures.model_value(x) for x in d] for d in input.domains], rules)
end

function named_space(name::AbstractString)
    haskey(NAMED_SPACES, name) || throw(ArgumentError("unknown benchmark space: $name"))
    return NAMED_SPACES[name]()
end

# Load the fixtures before the benchmark's world age when the spec needs them,
# as bench12_adapter.jl does by being included.
let spec = isempty(ARGS) ? nothing : JSON.parsefile(ARGS[1])
    if spec !== nothing && get(spec, "space", nothing) == "bench12" && !isdefined(Main, :BenchFixtures)
        include(joinpath(@__DIR__, "..", "fixtures.jl"))
    end
end
