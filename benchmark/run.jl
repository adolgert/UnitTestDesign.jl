# The performance baseline of design/benchmark_procedure.md (plan Phase 3
# step 9). Dependency-free: `@timed` and `Base.summarysize` only.
#
#     julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'   # once
#     julia --project=benchmark benchmark/run.jl [options]
#
# or, with the package's own environment, `julia --project benchmark/run.jl`.
#
# Options:
#     --runs N       warm runs per measurement (default 5; the median is reported)
#     --out PATH     also write the Markdown report to PATH
#     --tsv PATH     also write one tab-separated line per timed measurement
#     --skip-slow    leave out GND on fixture 1 (about four minutes per call)
#
# Every measurement makes one discarded first call, reported separately as the
# cold start (it includes compilation only for the first measurement that
# reaches a method), then `--runs` warm calls after a `GC.gc()`, and reports
# their median time and median allocation. Case counts are reported so that a
# speedup is never bought with a larger design unnoticed. Tests assert
# completion and coverage, never seconds; this script is for people.
#
# The same script runs on the prior revision (0.4, commit d46122d), which has
# no TestSpace: there it measures fixture 1 only, through the 0.4 API. Point
# its environment at a checkout of that revision, for example
#
#     git worktree add ../v04 d46122d
#     julia --project=../v04 benchmark/run.jl

using UnitTestDesign
using InteractiveUtils: versioninfo
using Printf: @sprintf
using Random: Xoshiro

"True on the 0.4 code, which has no TestSpace and still takes `disallow`."
const LEGACY = !isdefined(UnitTestDesign, :TestSpace)

LEGACY || include(joinpath(@__DIR__, "fixtures.jl"))


## Options

function options(args)
    opts = Dict{String, Any}("runs" => 5, "out" => nothing, "tsv" => nothing, "skip-slow" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--skip-slow"
            opts["skip-slow"] = true
        elseif a in ("--runs", "--out", "--tsv") && i < length(args)
            opts[a[3:end]] = a == "--runs" ? parse(Int, args[i + 1]) : args[i + 1]
            i += 1
        else
            error("unknown option $a; see the header of benchmark/run.jl")
        end
        i += 1
    end
    opts["runs"] >= 1 || error("--runs must be at least 1")
    return opts
end


## Measuring

median_of(xs) = (s = sort(collect(xs)); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)

"""
One measurement: `f()` returns `(cases, stats)`, where `cases` is the design's
case count and `stats` the request's `SearchStats` or `nothing`. The first
call is the cold start; then `runs` warm calls.
"""
function measure(f, runs)
    GC.gc()
    cold = @timed f()
    warm = map(1:runs) do _
        GC.gc()
        @timed f()
    end
    cases, stats = last(warm).value
    all(w -> first(w.value) == cases, warm) && first(cold.value) == cases ||
        error("the case count changed between runs of a deterministic call")
    return (cases = cases, stats = stats, cold = cold.time,
            median = median_of(w.time for w in warm), low = minimum(w.time for w in warm),
            high = maximum(w.time for w in warm), bytes = median_of(w.bytes for w in warm),
            allocs = median_of(Base.gc_alloc_count(w.gcstats) for w in warm),
            gc = median_of(w.gctime for w in warm))
end

seconds(t) = t >= 10 ? @sprintf("%.1f", t) : t >= 1 ? @sprintf("%.2f", t) : t >= 0.01 ? @sprintf("%.3f", t) :
             @sprintf("%.4f", t)
mib(b) = @sprintf("%.1f", b / 2^20)
count_str(n) = n === nothing ? "–" : replace(string(round(Int, n)), r"(?<=\d)(?=(\d{3})+$)" => ",")

const TIMING_HEADER = "| Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) |"
const TIMING_ALIGN = "--:|--:|--:|--:|--:|--:|--:|"

"The header of a table of measurements, with `extra` columns after the timings."
header(first, extra...) = "| $first $TIMING_HEADER" * join(" $x |" for x in extra) * "\n|:--|" * TIMING_ALIGN *
                          join("--:|" for _ in extra)

"A table row: the label, the timings, then `extra` cells."
function row(label, m, extra...)
    return "| $label | $(m.cases) | $(seconds(m.cold)) | $(seconds(m.median)) | " *
           "$(seconds(m.low))–$(seconds(m.high)) | $(mib(m.bytes)) | $(count_str(m.allocs)) | " *
           "$(seconds(m.gc)) |" * join(" $x |" for x in extra)
end

"Queries, nodes and rule checks of a request's feasibility searches."
search_cells(m) = (count_str(m.stats.queries), count_str(m.stats.total_nodes), count_str(m.stats.evaluations))
const SEARCH_COLUMNS = ("Queries", "Nodes", "Rule checks")


## Environment

function environment(opts)
    pkgdir = dirname(dirname(pathof(UnitTestDesign)))
    commit = strip(read(Cmd(`git -C $pkgdir rev-parse HEAD`; ignorestatus = true), String))
    dirty = !isempty(strip(read(Cmd(`git -C $pkgdir status --porcelain -- src`; ignorestatus = true), String)))
    ci = get(ENV, "CI", "false") == "true"
    jl = Base.JLOptions()
    lines = [
        "- Date: $(Libc.strftime("%Y-%m-%d %H:%M", time()))",
        "- Package: $(pkgdir), commit `$(commit)`$(dirty ? " with uncommitted changes in src/" : "")" *
            (LEGACY ? " (0.4 API)" : ""),
        "- Julia $(VERSION), $(Sys.MACHINE), $(Sys.KERNEL) $(Sys.ARCH)",
        "- CPU: $(Sys.cpu_info()[1].model), $(Sys.CPU_THREADS) logical cores, " *
            "$(round(Sys.total_memory() / 2^30, digits = 1)) GiB memory",
        "- Julia threads: $(Threads.nthreads()); optimization level -O$(jl.opt_level); bounds checks " *
            (jl.check_bounds == 0 ? "default" : jl.check_bounds == 1 ? "on" : "off"),
        "- Machine: " * (ci ? "CI runner" : "a workstation or laptop, not a CI runner"),
        "- Engine seed: GND `seed = 0` (a fresh `Xoshiro(0)` per call" * (LEGACY ? ", passed as `rng`" : "") * "); IPOG is deterministic",
        "- Compilation: the first call of each measurement is reported separately; timings are the median " *
            "of $(opts["runs"]) warm calls, each after `GC.gc()`",
    ]
    return join(lines, "\n")
end


## Fixture 1: 15 parameters of 4 values, strength 4, no rules

fixture1_engine(name) = name == :IPOG ? IPOG() : LEGACY ? GND(rng = Xoshiro(0)) : GND(seed = 0)

function fixture1(opts, out, tsv)
    println(out, "## Fixture 1: 15 parameters × 4 values, strength 4, no rules\n")
    println(out, "`all_tuples(fill(1:4, 15)...; n_way = 4, engine)`, the same call on both revisions. " *
                 "The design fingerprint is `hash` of the returned rows; equal fingerprints mean equal designs.\n")
    println(out, header("Engine", "Fingerprint"))
    engines = opts["skip-slow"] ? (:IPOG,) : (:IPOG, :GND)
    for name in engines
        fingerprint = Ref(UInt(0))
        m = measure(opts["runs"]) do
            rows = all_tuples(fill(1:4, 15)...; n_way = 4, engine = fixture1_engine(name))
            fingerprint[] = hash(rows)
            (length(rows), nothing)
        end
        println(out, row("$name", m, "`$(string(fingerprint[], base = 16))`"))
        println(tsv, join(("fixture1", name, 4, m.cases, m.cold, m.median, m.low, m.high, m.bytes, m.allocs), '\t'))
    end
    opts["skip-slow"] && println(out, "\nGND left out (`--skip-slow`).")
    println(out)
end


## Fixture 2: bench12, and fixture 3: the repaired greedy dead ends

function covering(engine, space, strength)
    request = UnitTestDesign.Request(space; strength)
    design = UnitTestDesign.generate(engine, request)
    return size(design.matrix, 2), request.feasibility.stats
end

function full_factorial_design(space)
    request = UnitTestDesign.Request(space; strength = 1)
    design = UnitTestDesign.generate_full_factorial(request)
    return size(design.matrix, 2), request.feasibility.stats
end

function fixture2(opts, out, tsv)
    space = BenchFixtures.test_space(BenchFixtures.bench12)
    println(out, "## Fixture 2: `bench12` (test/fixtures.jl)\n")
    println(out, "12 parameters, 331776 rows, 207360 valid, four rules. `generate(engine, Request(space; strength))` " *
                 "through the internal request; the public `covering` arrives in Phase 4. Queries, nodes and rule " *
                 "checks are the request's `feasibility.stats` for one call. Full factorial is " *
                 "`generate_full_factorial(Request(space; strength = 1))`.\n")
    println(out, header("Strategy", SEARCH_COLUMNS...))
    for strength in (2, 3), (name, engine) in ((:IPOG, IPOG()), (:GND, GND(seed = 0)))
        m = measure(() -> covering(engine, space, strength), opts["runs"])
        println(out, row("$name, strength $strength", m, search_cells(m)...))
        println(tsv, join(("bench12", name, strength, m.cases, m.cold, m.median, m.low, m.high, m.bytes, m.allocs), '\t'))
    end
    m = measure(() -> full_factorial_design(space), opts["runs"])
    println(out, row("full factorial", m, search_cells(m)...))
    println(tsv, join(("bench12", :FullFactorial, 0, m.cases, m.cold, m.median, m.low, m.high, m.bytes, m.allocs), '\t'))
    println(out)
end

function fixture3(opts, out, tsv)
    println(out, "## Fixture 3: the repaired greedy dead ends\n")
    println(out, "The four dead ends frozen in test/fixtures.jl, on which the 0.4 IPOG threw a `BoundsError`. " *
                 "No \"before\" number exists; these record the \"after\".\n")
    println(out, header("Fixture", SEARCH_COLUMNS...))
    for f in (BenchFixtures.dead_end_pairwise_1, BenchFixtures.dead_end_pairwise_2,
              BenchFixtures.dead_end_threeway_1, BenchFixtures.dead_end_threeway_2)
        space = BenchFixtures.test_space(f)
        strength = f.request.strength
        for (name, engine) in ((:IPOG, IPOG()), (:GND, GND(seed = 0)))
            m = measure(() -> covering(engine, space, strength), opts["runs"])
            println(out, row("`$(f.name)`, $name, strength $strength", m, search_cells(m)...))
            println(tsv, join((f.name, name, strength, m.cases, m.cold, m.median, m.low, m.high, m.bytes, m.allocs), '\t'))
        end
    end
    println(out)
end


## The memo of a lazy rule (contract §3.5, §12.19)

"A copy of `space` with one more rule, a whole-case rule that forbids nothing, so it is lazy."
function with_whole_case_rule(space)
    return TestSpace((n => v for (n, v) in zip(space.names, space.values))...;
                     constraints = [space.constraints; forbid(case -> false)])
end

function memo_steps(out, label, space, steps)
    size0 = Base.summarysize(space)
    println(out, "| $label | before generation | – | – | $(count_str(size0)) | – | – | – |")
    for (name, engine, strength) in steps
        request = UnitTestDesign.Request(space; strength)
        t = @timed UnitTestDesign.generate(engine, request)
        println(out, "| $label | after $name, strength $strength | $(size(t.value.matrix, 2)) | " *
                     "$(seconds(t.time)) | $(count_str(Base.summarysize(space))) | " *
                     "$(count_str(UnitTestDesign.memo_size(request))) | " *
                     "$(count_str(Base.summarysize(request.feasibility))) | " *
                     "$(count_str(request.feasibility.stats.total_nodes)) |")
    end
end

function memo(opts, out)
    println(out, "## Memory of a lazy rule's memo\n")
    println(out, "Each space gets one added whole-case rule, `forbid(case -> false)`, which is always lazy " *
                 "(contract §12.19), so every complete row the searches reach is memoized. The memo belongs " *
                 "to the request (§3.5): `memo_size(request)` counts its entries and " *
                 "`Base.summarysize(request.feasibility)` is the request's search state, memo included, while " *
                 "`Base.summarysize(space)` should not change. One space per table; the calls run in order on " *
                 "the same space, each with a fresh request. Times are single first calls, not medians.\n")
    println(out, "| Space | When | Cases | Time (s) | `Base.summarysize(space)` (bytes) | " *
                 "`memo_size(request)` (entries) | `Base.summarysize(request.feasibility)` (bytes) | Nodes |")
    println(out, "|:--|:--|--:|--:|--:|--:|--:|--:|")
    bench = with_whole_case_rule(BenchFixtures.test_space(BenchFixtures.bench12))
    memo_steps(out, "bench12 + whole-case rule", bench,
               [(:IPOG, IPOG(), 2), (:IPOG, IPOG(), 3), (:GND, GND(seed = 0), 2), (:GND, GND(seed = 0), 3)])
    wide = with_whole_case_rule(TestSpace((Symbol(:p, i) => 1:4 for i in 1:15)...))
    memo_steps(out, "fixture 1 + whole-case rule", wide, [(:IPOG, IPOG(), 2), (:IPOG, IPOG(), 3), (:IPOG, IPOG(), 4)])
    println(out, "\nGND is not run on fixture 1 with the whole-case rule: without rules it already takes about " *
                 "four minutes per call at strength 4, and the rule adds a feasibility search to every value it scores.\n")
end


## Where the time goes (Phase 4/5 candidates; measured, not optimized)

"Median seconds and bytes of `f()` over `n` calls, after one discarded call."
function quick(f, n = 5)
    f()
    ts = [(GC.gc(); @timed f()) for _ in 1:n]
    return median_of(t.time for t in ts), median_of(t.bytes for t in ts)
end

function breakdown(opts, out)
    println(out, "## Where the time goes\n")
    println(out, "Parts of the calls above, timed alone (median of 5 after one discarded call). " *
                 "Recorded as Phase 4/5 candidates; only the final validation changed in Phase 3 (review " *
                 "round 1 moved it to index space).\n")
    println(out, "| Call | Part | Time (s) | Allocated (MiB) | Note |")
    println(out, "|:--|:--|--:|--:|:--|")

    # Full factorial on bench12: enumeration (each candidate row through
    # `violates`) versus the final validation (each accepted row through
    # `violates` in index space, since Phase 3 review round 1).
    space = BenchFixtures.test_space(BenchFixtures.bench12)
    total, total_b = quick(() -> full_factorial_design(space))
    request = UnitTestDesign.Request(space; strength = 1)
    design = UnitTestDesign.generate_full_factorial(request)
    enumerate_t, enumerate_b = quick() do
        r = UnitTestDesign.Request(space; strength = 1)
        UnitTestDesign._accept_rows!(Int[], r, Set{Vector{Int}}())
    end
    validate_t, validate_b = quick(() -> UnitTestDesign.validate_design(request, design.matrix, Vector{Int}[];
                                                                          strategy = :full_factorial))
    # One `forbids` call on a tabulated two-parameter rule, the kind every check here makes.
    table = space.tables[1]
    key = ones(Int, 12)
    calls = 10^6
    forbids_t, forbids_b = quick() do
        hits = 0
        for _ in 1:calls
            hits += UnitTestDesign.forbids(table, key)
        end
        hits
    end
    per_call, per_call_b = forbids_t / calls, forbids_b / calls
    r = UnitTestDesign.Request(space; strength = 1)
    UnitTestDesign._accept_rows!(Int[], r, Set{Vector{Int}}())
    checks = r.feasibility.stats.evaluations
    rows = size(design.matrix, 2)
    validate_checks = rows * length(space.tables)
    share(t) = @sprintf("%.0f%%", 100 * t / total)
    println(out, "| bench12 full factorial | whole call | $(seconds(total)) | $(mib(total_b)) | $(rows) rows of 331776 |")
    println(out, "| bench12 full factorial | enumeration, `violates` per candidate | $(seconds(enumerate_t)) | " *
                 "$(mib(enumerate_b)) | $(share(enumerate_t)) of the call; $(count_str(checks)) rule checks |")
    println(out, "| bench12 full factorial | `validate_design`, `violates` per row | $(seconds(validate_t)) | " *
                 "$(mib(validate_b)) | $(share(validate_t)) of the call; $(count_str(validate_checks)) rule checks |")
    println(out, "| `forbids` on a tabulated rule | one call | $(@sprintf("%.1f", 1e9 * per_call)) ns | " *
                 "$(@sprintf("%.0f", per_call_b)) bytes | the runtime-length `ntuple` key allocates on every check |")
    println(out, "| bench12 full factorial | `forbids` in enumeration, estimated | " *
                 "$(seconds(checks * per_call)) | $(mib(checks * per_call_b)) | $(share(checks * per_call)) of the call |")
    println(out, "| bench12 full factorial | `forbids` in validation, estimated | " *
                 "$(seconds(validate_checks * per_call)) | $(mib(validate_checks * per_call_b)) | " *
                 "$(share(validate_checks * per_call)) of the call |")
    # The round trip through values that validation made before Phase 3
    # review round 1, for comparison: each row becomes a case (`from_indices`,
    # which `to_cases` still does), and `isallowed` reads it back
    # (`case_indices`, a lookup of each value by identity) before its rule
    # checks. Neither is part of the call any more.
    as_case(j) = UnitTestDesign.from_indices(space, UnitTestDesign._space_indices(request, design.matrix[:, j]))
    cases_t, cases_b = quick(() -> [as_case(j) for j in axes(design.matrix, 2)])
    cases = [as_case(j) for j in axes(design.matrix, 2)]
    allowed_t, allowed_b = quick(() -> count(c -> isallowed(space, c), cases))
    lookup_t, lookup_b = quick(() -> sum(c -> sum(UnitTestDesign.case_indices(space, c)), cases))
    println(out, "| bench12 full factorial | not in the call: each row to a case, `from_indices` (`to_cases`) | " *
                 "$(seconds(cases_t)) | $(mib(cases_b)) | $(share(cases_t)) of the call |")
    println(out, "| bench12 full factorial | not in the call: `isallowed` on each case (the old validation) | " *
                 "$(seconds(allowed_t)) | $(mib(allowed_b)) | $(share(allowed_t)) of the call |")
    println(out, "| bench12 full factorial | ... of which `case_indices`, the value lookup | " *
                 "$(seconds(lookup_t)) | $(mib(lookup_b)) | $(share(lookup_t)) of the call |")

    # Fixture 1 through IPOG: the classic unconstrained `ipog` is the 0.4
    # core; the request adds the target list and the final validation.
    wide = TestSpace((Symbol(:p, i) => 1:4 for i in 1:15)...)
    whole, whole_b = quick(() -> covering(IPOG(), wide, 4))
    targets_t, targets_b = quick(() -> UnitTestDesign.classify_targets(UnitTestDesign.Request(wide; strength = 4)))
    core_t, core_b = quick(() -> UnitTestDesign.ipog(fill(4, 15), 4))
    wide_request = UnitTestDesign.Request(wide; strength = 4)
    required, _ = UnitTestDesign.classify_targets(wide_request)
    matrix = UnitTestDesign.ipog(fill(4, 15), 4)
    check_t, check_b = quick(() -> UnitTestDesign.validate_design(wide_request, matrix, required))
    wshare(t) = @sprintf("%.0f%%", 100 * t / whole)
    println(out, "| fixture 1, IPOG | whole `generate` call | $(seconds(whole)) | $(mib(whole_b)) | |")
    println(out, "| fixture 1, IPOG | classic `ipog`, the 0.4 core | $(seconds(core_t)) | $(mib(core_b)) | $(wshare(core_t)) |")
    println(out, "| fixture 1, IPOG | `classify_targets`: the list of $(count_str(length(required))) targets | " *
                 "$(seconds(targets_t)) | $(mib(targets_b)) | $(wshare(targets_t)); unconstrained, so nothing is excluded |")
    println(out, "| fixture 1, IPOG | `validate_design` | $(seconds(check_t)) | $(mib(check_b)) | $(wshare(check_t)) |")
    println(out)
end


## Main

function main(args)
    opts = options(args)
    tsv = opts["tsv"] === nothing ? devnull : open(opts["tsv"], "w")
    report = IOBuffer()
    # Each section goes to stdout as soon as it is done, and to the report.
    function emit(section)
        io = IOBuffer()
        section(io)
        text = String(take!(io))
        print(stdout, text)
        flush(stdout)
        print(report, text)
    end
    emit() do io
        println(io, "# UnitTestDesign benchmark\n")
        println(io, environment(opts), "\n")
        println(io, "<details><summary>versioninfo()</summary>\n\n```\n", sprint(versioninfo), "```\n</details>\n")
    end
    emit(io -> fixture1(opts, io, tsv))
    if LEGACY
        emit() do io
            println(io, "Fixtures 2 and 3 are not run on the 0.4 code: its IPOG throws a `BoundsError` on them " *
                        "and its GND does not return on `bench12` (design/benchmark_procedure.md), so they " *
                        "have no baseline.\n")
        end
    else
        emit(io -> fixture2(opts, io, tsv))
        emit(io -> fixture3(opts, io, tsv))
        emit(io -> memo(opts, io))
        emit(io -> breakdown(opts, io))
    end
    opts["out"] === nothing || write(opts["out"], String(take!(report)))
    tsv === devnull || close(tsv)
    return nothing
end

main(ARGS)
