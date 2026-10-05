# The gate of `Compact`, the row reducer (src/compact.jl; solver plan §5.3),
# outside the CASA set, which runs through the scaling harness (the command
# is printed at the end). Each section prints its rows, and the last lines
# say which gate items pass:
#
#     julia --project=. benchmark/compact_gate.jl [--seeds N] [--high] [--constructions DIR]
#
# - mainstream: the r3 spaces of benchmark/scaling/families/random_spaces.json
#   (100 unconstrained spaces of 4–12 parameters with 2–7 values, strength 2),
#   where the default effort must reach the bound on at least 92 (probe 16's
#   spike), each `generate` under 50 ms warm; and, for the record, r4
#   (strength 3) and both with rules (r3-rules, r4-rules).
# - bench12 at strengths 2 and 3: at most 18 and 72 rows, seed 0. `--seeds N`
#   also prints the rows for seeds 0 to N - 1 (default 20).
# - catalog starts: the reducer's core (`_compact`) from the catalog's array
#   for 8 × 6 at strength 3 (at most 303 rows) and 30 × 6 at strength 2 (at
#   most 75), built by the reference constructions in
#   design/20261003_solver_plan_constructions/ (`--constructions DIR` or the
#   UTD_CONSTRUCTIONS environment variable names the directory when the
#   checkout has no design/ directory; the section is skipped without one).
# - uniform: the shapes of plan §2.1's table, for the record.
# - `--high`: strengths 4 to 6 on 20 parameters (plan §2.9), which take
#   minutes.
# - `--casa RESULTS.json` (repeatable): the CASA set, from the scaling
#   harness's results of `Compact(IPOG())` jobs, whose engine extras hold IPOG's
#   rows (the reducer's start) beside the reduced rows. At strength 3, rows
#   must fall 10% or more below IPOG's on most of the models that complete.
#   The jobs run one at a time with an 8 GiB guard:
#
#       python3 benchmark/scaling/run.py --family casa --solver "Compact(IPOG())" --runs 1 \
#           --rss-mib 8192 --cold-seconds 900 --stage-seconds 900 --job-seconds 900 --out <dir>
#
#   Every other section is skipped when `--casa` is given.
#
# Every result is certified (`generate` validates; the core's results are
# recounted here by `validate_design`), and no section may end with more rows
# than its start. Warm times are the minimum of three calls after a first
# one; they depend on the machine and its load, so the timing items are
# provisional on a busy machine. Row counts and steps don't depend on either.

using UnitTestDesign, JSON, Printf
using UnitTestDesign: Request, RequiredTargets, Compact, classify_targets, cover_ordinary, generate,
                      validate_design, _compact

const ROOT = pkgdir(UnitTestDesign)
option(name, default) = (k = findfirst(==(name), ARGS); k === nothing ? default : ARGS[k + 1])
const SEEDS = parse(Int, option("--seeds", "20"))
const HIGH = "--high" in ARGS
const CONSTRUCTIONS = option("--constructions",
    get(ENV, "UTD_CONSTRUCTIONS", joinpath(ROOT, "design", "20261003_solver_plan_constructions")))

const VERDICTS = Pair{String, Bool}[]
verdict(what, ok) = (push!(VERDICTS, what => ok); println(ok ? "  PASS " : "  FAIL ", what))
const NEVER_MORE = Ref(true)
const RESULTS_HASH = Ref(UInt(0))

"A space of `1:a` values per parameter, with forbidden tuples as scoped rules (random_spaces.json)."
function json_space(x)
    arity = Int.(x["arity"])
    names = Tuple(Symbol(:p, i) for i in eachindex(arity))
    rules = Constraint[]
    for f in get(x, "forbid", [])
        scope = Symbol.(:p, Int.(f["scope"]))
        tuples = Set(Tuple(Int.(t)) for t in f["tuples"])
        push!(rules, forbid((v...) -> v in tuples, scope...))
    end
    return TestSpace(NamedTuple{names}(Tuple(collect(1:a) for a in arity)); constraints = rules)
end

uniform(k, v) = TestSpace([Symbol(:x, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)

"The minimum of three warm calls of `f`, after a first one."
warm(f) = (f(); minimum(@elapsed(f()) for _ in 1:3))

"Generate with IPOG and with Compact(IPOG()); return rows, bound, stop, steps and Compact's warm time."
function compare(space, strength; timed = false)
    ipog = generate(IPOG(), Request(space; strength))
    compact = generate(Compact(IPOG()), Request(space; strength))
    n = compact.record.ordinary.reducer
    n.start == size(ipog.matrix, 2) || error("Compact's start is not IPOG's rows")
    size(compact.matrix, 2) <= size(ipog.matrix, 2) || (NEVER_MORE[] = false)
    RESULTS_HASH[] = hash(compact.matrix, RESULTS_HASH[])
    seconds = timed ? warm(() -> generate(Compact(IPOG()), Request(space; strength))) : NaN
    return (ipog = size(ipog.matrix, 2), rows = size(compact.matrix, 2), bound = n.bound,
            stop = n.stop, steps = n.steps, seconds)
end

function mainstream()
    println("\n== mainstream (random_spaces.json)")
    spaces = JSON.parsefile(joinpath(ROOT, "benchmark", "scaling", "families", "random_spaces.json"))["spaces"]
    for set in ("r3", "r4", "r3-rules", "r4-rules")
        xs = [x for x in spaces if x["set"] == set]
        results = [compare(json_space(x), x["strength"]; timed = set == "r3") for x in xs]
        at = count(r -> r.rows == r.bound, results)
        ipog_at = count(r -> r.ipog == r.bound, results)
        saved = sum(r -> 1 - r.rows / r.ipog, results) / length(results)
        @printf("  %-9s t=%d  %3d spaces: at the bound %3d (IPOG %3d); rows %5d (IPOG %5d), mean saving %.1f%%; stops %s\n",
                set, xs[1]["strength"], length(xs), at, ipog_at, sum(r -> r.rows, results),
                sum(r -> r.ipog, results), 100saved, join(sort(unique(string.(getfield.(results, :stop)))), "/"))
        if set == "r3"
            times = sort([r.seconds for r in results])
            @printf("            warm generate(Compact(IPOG())): median %.1f ms, slowest %.1f ms\n",
                    1000times[end ÷ 2], 1000times[end])
            verdict("mainstream r3: at the bound on at least 92 of 100 (got $at)", at >= 92)
            verdict("mainstream r3: each under 50 ms warm (slowest $(round(1000times[end]; digits = 1)) ms; provisional)",
                    times[end] < 0.050)
        end
    end
end

function bench12()
    println("\n== bench12")
    include(joinpath(ROOT, "benchmark", "fixtures.jl"))
    space = Base.invokelatest(() -> BenchFixtures.test_space(BenchFixtures.bench12))
    for (strength, gate) in ((2, 18), (3, 72))
        r = compare(space, strength; timed = true)
        @printf("  t=%d: IPOG %d, Compact %d (bound %d, %s after %d steps), warm %.1f ms\n",
                strength, r.ipog, r.rows, r.bound, r.stop, r.steps, 1000r.seconds)
        verdict("bench12 t=$strength: at most $gate rows at seed 0 (got $(r.rows))", r.rows <= gate)
        SEEDS > 0 || continue
        rows = [size(generate(Compact(IPOG(); seed), Request(space; strength)).matrix, 2) for seed in 0:(SEEDS - 1)]
        println("        seeds 0:$(SEEDS - 1): ", join(rows, " "), "; at most $gate on $(count(<=(gate), rows))")
    end
end

"The reducer's core from a start matrix (parameters × rows, positions from 1) for k parameters of v values."
function reduce_start(k, v, t, start; kw...)
    request = Request(uniform(k, v); strength = t)
    required, _ = classify_targets(request)
    targets = RequiredTargets(request, required)
    stats = @timed _compact(request, targets, start; kw...)
    matrix, notes = stats.value
    validate_design(request, matrix, required) == length(required) || error("not certified")
    size(matrix, 2) <= size(start, 2) || (NEVER_MORE[] = false)
    RESULTS_HASH[] = hash(matrix, RESULTS_HASH[])
    return (; rows = size(matrix, 2), notes, seconds = stats.time)
end

function catalog()
    println("\n== catalog starts (the core, `_compact`, seed 0, effort 1)")
    file = joinpath(CONSTRUCTIONS, "catalog.jl")
    if !isfile(file)
        println("  skipped: no $file (pass --constructions DIR)")
        push!(VERDICTS, "catalog starts: skipped" => false)
        return
    end
    Main.include(file)
    for (t, k, v, gate) in ((3, 8, 6, 303), (2, 30, 6, 75))
        choice = Base.invokelatest(t == 2 ? Main.pairwise : Main.strength3, k, v)
        A = Base.invokelatest(Main.array, choice, k)       # rows × columns, symbols from 0
        start = permutedims(A) .+ 1
        r = reduce_start(k, v, t, start)
        request = Request(uniform(k, v); strength = t)
        required, _ = classify_targets(request)
        ipog = cover_ordinary(IPOG(), request, RequiredTargets(request, required))
        q = reduce_start(k, v, t, ipog)
        @printf("  %d × %d, t=%d: catalog (%s) %d → %d (%s, %d steps, %.2f s); IPOG %d → %d\n",
                k, v, t, choice.how, size(start, 2), r.rows, r.notes.reducer_stop, r.notes.reducer_steps,
                r.seconds, size(ipog, 2), q.rows)
        verdict("catalog start $k × $v at t=$t: at most $gate rows (got $(r.rows))", r.rows <= gate)
    end
end

function uniform_table()
    println("\n== uniform shapes of plan §2.1 (IPOG, then Compact(IPOG()) at the default effort)")
    for (k, v, t) in ((8, 2, 2), (32, 2, 2), (64, 2, 2), (128, 2, 2), (256, 2, 2), (8, 4, 2), (8, 8, 2),
                      (10, 8, 2), (12, 3, 2), (16, 4, 2), (32, 4, 2), (64, 4, 2), (128, 4, 2), (12, 3, 3))
        stats = @timed compare(uniform(k, v), t)
        r = stats.value
        @printf("  %3d × %d, t=%d: IPOG %4d → %4d (bound %d, %s after %d steps; IPOG and Compact %.2f s)\n",
                k, v, t, r.ipog, r.rows, r.bound, r.stop, r.steps, stats.time)
    end
end

"""
The CASA jobs of the scaling harness's `results.json` files: per model and strength, IPOG's rows
(`reducer_start` in the engine extras), the reduced rows, the bound and the stop, or the job's
status where it didn't complete.
"""
function casa(paths)
    println("\n== CASA (Compact(IPOG()) jobs of the scaling harness)")
    @printf("  %-14s %2s %6s %8s %7s %6s %7s %8s %9s %8s  %s\n", "model", "t", "IPOG", "Compact", "saved",
            "bound", "stop", "steps", "warm s", "RSS MiB", "status")
    tally = Dict(t => [0, 0] for t in (2, 3))   # completed, saved 10% or more
    for path in paths, r in JSON.parsefile(path)["results"]
        spec = r["spec"]
        t = spec["strength"]
        name = split(spec["id"], "-")[2]
        rss = something(get(r, "os_peak_rss_bytes", nothing), get(r, "sampled_peak_rss_bytes", 0), 0) / 2^20
        done = [m for m in r["measurements"] if get(m, "stage", "") in ("cold", "warm") && haskey(m, "result")]
        if isempty(done)
            errors = join((first(string(get(e, "message", "")), 70) for e in get(r, "errors", [])), "; ")
            @printf("  %-14s %2d %6s %8s %7s %6s %7s %8s %9s %8.0f  %s at %s %s\n", name, t, "", "", "", "", "", "",
                    "", rss, r["status"], something(r["stopped_stage"], "?"), errors)
            continue
        end
        m = last(done)
        x = m["result"]["engine_extras"]
        ipog, rows = x["reducer_start"], m["result"]["cases"]
        saved = 1 - rows / ipog
        tally[t][1] += 1
        tally[t][2] += saved >= 0.10
        rows <= ipog || (NEVER_MORE[] = false)
        @printf("  %-14s %2d %6d %8d %6.1f%% %6d %7s %8d %9.2f %8.0f  %s\n", name, t, ipog, rows, 100saved,
                x["reducer_bound"], x["reducer_stop"], x["reducer_steps"], m["seconds"], rss, r["status"])
    end
    for t in (2, 3)
        n, ten = tally[t]
        n == 0 && continue
        println("  strength $t: $n models complete; rows 10% or more below IPOG on $ten")
    end
    n, ten = tally[3]
    n > 0 && verdict("CASA t=3: rows 10% or more below IPOG on most completed models ($ten of $n)", ten > n / 2)
end

function high()
    println("\n== strengths 4 to 6 on 20 parameters (plan §2.9; IPOG's rows, then the core at effort 1)")
    for (v, t) in ((2, 4), (2, 5), (2, 6), (3, 4), (3, 5))
        request = Request(uniform(20, v); strength = t)
        required, _ = classify_targets(request)
        ipog = @timed cover_ordinary(IPOG(), request, RequiredTargets(request, required))
        r = reduce_start(20, v, t, ipog.value)
        @printf("  20 × %d, t=%d: IPOG %d (%.1f s) → %d (%s after %d steps, %.2g reads, %.1f s)\n",
                v, t, size(ipog.value, 2), ipog.time, r.rows, r.notes.reducer_stop, r.notes.reducer_steps,
                r.notes.reducer_work, r.seconds)
    end
end

commit = try
    readchomp(`git -C $ROOT rev-parse --short HEAD`)
catch
    "an unknown commit"
end
println("Compact gate (plan §5.3) at ", commit, ", Julia ", VERSION, ", ", Sys.cpu_info()[1].model,
        ", load ", round.(Sys.loadavg(); digits = 1))
casa_paths = [ARGS[k + 1] for k in eachindex(ARGS) if ARGS[k] == "--casa"]
if isempty(casa_paths)
    mainstream()
    bench12()
    catalog()
    uniform_table()
    HIGH && high()
else
    casa(casa_paths)
end
println()
verdict("never more rows than the start, on every point above", NEVER_MORE[])
isempty(casa_paths) &&
    println("\nrows hash (the same seed gives the same rows in another process): ", string(RESULTS_HASH[]; base = 16))
isempty(casa_paths) && println("\nThe CASA set: run the harness (see the header), then `--casa <dir>/results.json`.")
println("\n", count(last, VERDICTS), " of ", length(VERDICTS), " gate items pass")
