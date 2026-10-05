# The regret table for `Auto` (solver plan §7.5, decision D1): every default
# point of the benchmark families `mainstream`, `smallest`, `uniform-pp` and
# `uniform-npp` (benchmark/scaling/families.py), with every applicable
# candidate, and the gates on it. Run from the repository root:
#
#     julia --project=. --startup-file=no benchmark/auto_regret.jl run FAMILY OUT.tsv
#     julia --project=. --startup-file=no benchmark/auto_regret.jl summary OUT.tsv...
#     julia --project=. --startup-file=no benchmark/auto_regret.jl catalog-gate [--seeds N]
#
# `run` writes one line per point: its rows, warm generation time and lower
# bound under IPOG(), Construction() where its fit is exact or seeded,
# Auto() and Auto(goal = :compact), what each Auto chose, and every start's
# rows. A family's spaces are built as the scaling harness's worker builds
# them (spaces.jl, model_specs.jl), with its feasibility_limit of 100,000;
# expensive points (families.py) are left out, as the families' default runs
# leave them. Each engine's time is that of `generate(engine, Request(...))`,
# classification and certification included: the minimum of three calls when
# one takes under 0.1 s, else one call, after the engine has been compiled on
# a small space. Rows, bounds and choices are exact; times are provisional on
# a busy machine. The four families run as four processes in about an hour.
#
# `summary` reads the tables and prints the gates of §7.5 for
# Auto(goal = :balanced): rows never above IPOG's; time at most twice IPOG's
# wherever Auto picks something other than IPOG, unless the rows fall by 20%
# or more. It prints the D1 bar (fewer rows on a quarter or more of the
# uniform and t + 1 spaces of mainstream and smallest, never more rows on any
# space, warm time within twice IPOG's or 10 ms), and, for the
# keep-the-smallest threshold, what Auto would return at other thresholds:
# where the catalog's array is larger than IPOG's design, and at how many
# targets, since above the threshold an exact shape takes the catalog
# without running IPOG.
#
# `catalog-gate` re-checks Phase 1's catalog-start gate through the public
# engines (plan §5.3): 8 × 6 at strength 3 at most 303 rows and 30 × 6 at
# strength 2 at most 75, through Compact(Construction()) and
# Auto(goal = :compact), at seed 0 and as the median over seeds 0 to N - 1
# (default 10).

using UnitTestDesign, JSON, Printf
using UnitTestDesign: Request, generate, Profile, fit

const U = UnitTestDesign
const ROOT = normpath(joinpath(@__DIR__, ".."))
# spaces.jl and model_specs.jl read a job's spec from ARGS[1] when they are
# included by the worker; here there is none, so they see no arguments.
const COMMAND = copy(ARGS)
empty!(ARGS)
include(joinpath(ROOT, "benchmark", "scaling", "spaces.jl"))
include(joinpath(ROOT, "benchmark", "scaling", "model_specs.jl"))
append!(ARGS, COMMAND)
# bench12's rules, loaded here at top level so that the calls below run in a
# world that has them (spaces.jl loads them only for a worker's bench12 spec).
include(joinpath(ROOT, "benchmark", "fixtures.jl"))

"The default (not expensive) specs of a family, from families.py itself, as Dicts."
function family_specs(name)
    code = "import sys, json; sys.path.insert(0, 'benchmark/scaling'); import families\n" *
           "print(json.dumps([j for j in families.FAMILIES['$name'](['ipog'], 1) if not j.get('expensive')]))"
    return JSON.parse(read(Cmd(`python3 -c $code`; dir = ROOT), String))
end

"The space and keywords of a spec, as the scaling harness's worker builds them for family \"none\"."
function build(s)
    names, domains, rules = base_model(s)
    n = length(names)
    space = TestSpace((names[i] => domains[i] for i in 1:n)...; constraints = rules, tabulation_limit = 100_000)
    kw = (; strength = s["strength"], stronger = spec_stronger(s, names),
          feasibility_limit = get(s, "nodes", 100_000), explanation_limit = get(s, "explanations", 1_000_000))
    return space, kw
end

"Rows, warm seconds and record of `generate(engine, Request(space; kw...))`."
function measure(engine, space, kw)
    d = generate(engine, Request(space; kw...))
    seconds = @elapsed generate(engine, Request(space; kw...))
    if seconds < 0.1
        seconds = min(seconds, minimum(@elapsed(generate(engine, Request(space; kw...))) for _ in 1:2))
    end
    return (rows = size(d.matrix, 2), seconds, record = d.record)
end

const COLUMNS = ["family", "id", "t", "k", "arity", "uniform", "t1", "rules", "stronger", "targets", "bound",
                 "ipog", "ipog_s", "fit", "construction", "construction_s", "balanced", "balanced_s",
                 "balanced_chose", "balanced_starts", "compact", "compact_s", "compact_chose", "minimal_balanced"]

function run_family(family, out)
    # Compile every engine once on a small space, so no point pays for it.
    for e in (IPOG(), Construction(), Auto(), Auto(goal = :compact))
        generate(e, Request(TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:3)); strength = 2))
    end
    specs = family_specs(family)
    open(out, "w") do io
        println(io, join(COLUMNS, '\t'))
        for (i, s) in enumerate(specs)
            space, kw = build(s)
            arity = [count(x -> !(x isa Invalid), d) for d in space.values]
            p = Profile(Request(space; kw...))
            f = fit(Construction(), p)
            ipog = measure(IPOG(), space, kw)
            cons = f.kind in (:exact, :seeded) ? measure(Construction(), space, kw) : nothing
            balanced = measure(Auto(), space, kw)
            compact = measure(Auto(goal = :compact), space, kw)
            starts = join(("$(c.engine)=$(c.rows)" for c in balanced.record.ordinary.starts), ",")
            row = Any[family, s["id"], s["strength"], length(arity), join(arity, " "), allequal(arity),
                      length(arity) == s["strength"] + 1, length(space.constraints), length(kw.stronger), p.targets,
                      ipog.record.lower_bound, ipog.rows, ipog.seconds, f.kind,
                      cons === nothing ? "" : cons.rows, cons === nothing ? "" : cons.seconds,
                      balanced.rows, balanced.seconds, balanced.record.ordinary.chose, starts,
                      compact.rows, compact.seconds, compact.record.ordinary.chose, balanced.record.minimal]
            println(io, join(row, '\t'))
            flush(io)
            @printf("%4d/%d %-40s ipog %5d  auto %5d (%s)  compact %5d\n", i, length(specs), s["id"], ipog.rows,
                    balanced.rows, balanced.record.ordinary.chose, compact.rows)
            flush(stdout)
        end
    end
end

"The rows of the tables, as Dicts of column => text."
function read_tables(paths)
    rows = Dict{String, String}[]
    for path in paths
        lines = readlines(path)
        header = split(lines[1], '\t')
        for line in lines[2:end]
            push!(rows, Dict(String(h) => String(v) for (h, v) in zip(header, split(line, '\t'))))
        end
    end
    return rows
end

num(x) = parse(Float64, x)
int(x) = parse(Int, x)
median(x) = (s = sort(x); isempty(s) ? NaN : isodd(length(s)) ? s[(end + 1) ÷ 2] : (s[end ÷ 2] + s[end ÷ 2 + 1]) / 2)

function summary(paths)
    rows = read_tables(paths)
    println("Auto regret table: $(length(rows)) points from ", join(unique(r["family"] for r in rows), ", "))
    # §7.5's gates for :balanced.
    above = [r for r in rows if int(r["balanced"]) > int(r["ipog"])]
    other = [r for r in rows if r["balanced_chose"] != "IPOG()"]
    slow = [r for r in other if num(r["balanced_s"]) > 2num(r["ipog_s"]) &&
                                 int(r["balanced"]) > 0.8int(r["ipog"])]
    fewer = [r for r in rows if int(r["balanced"]) < int(r["ipog"])]
    println("\n== §7.5 gates for Auto(goal = :balanced)")
    @printf("  rows never above IPOG's: %s (%d points above)\n", isempty(above) ? "PASS" : "FAIL", length(above))
    for r in above
        println("    above: ", r["id"], " ipog ", r["ipog"], " balanced ", r["balanced"], " (", r["balanced_chose"], ")")
    end
    @printf("  Auto picks something other than IPOG on %d points; fewer rows on %d\n", length(other), length(fewer))
    @printf("  time at most twice IPOG's there, unless rows fall 20%% or more: %s (%d points over, provisional)\n",
            isempty(slow) ? "PASS" : "FAIL", length(slow))
    for r in slow
        @printf("    slow: %s ipog %s rows %.4f s, balanced %s rows %.4f s (%s)\n", r["id"], r["ipog"],
                num(r["ipog_s"]), r["balanced"], num(r["balanced_s"]), r["balanced_chose"])
    end
    ratio = [num(r["balanced_s"]) / num(r["ipog_s"]) for r in rows]
    @printf("  time balanced / IPOG over all points: median %.2f, max %.2f\n", median(ratio), maximum(ratio))
    # The D1 bar (§7.5).
    println("\n== D1: the bar for making Auto(goal = :balanced) the default")
    pool = [r for r in rows if r["family"] in ("mainstream", "smallest") && (r["uniform"] == "true" || r["t1"] == "true")]
    better = count(r -> int(r["balanced"]) < int(r["ipog"]), pool)
    @printf("  uniform and t + 1 spaces of mainstream and smallest: %d; fewer rows on %d (%.0f%%): %s (bar: a quarter)\n",
            length(pool), better, 100better / max(1, length(pool)), better >= length(pool) / 4 ? "PASS" : "FAIL")
    @printf("  never more rows on any space: %s\n", isempty(above) ? "PASS" : "FAIL")
    late = [r for r in rows if num(r["balanced_s"]) > max(2num(r["ipog_s"]), 0.010)]
    @printf("  warm time within twice IPOG's or 10 ms: %s (%d points over, provisional)\n",
            isempty(late) ? "PASS" : "FAIL", length(late))
    for r in late
        @printf("    over: %s ipog %.4f s, balanced %.4f s (%s)\n", r["id"], num(r["ipog_s"]), num(r["balanced_s"]),
                r["balanced_chose"])
    end
    for fam in unique(r["family"] for r in rows)
        xs = [r for r in rows if r["family"] == fam]
        saved = [1 - int(r["balanced"]) / int(r["ipog"]) for r in xs if int(r["ipog"]) > 0]
        csaved = [1 - int(r["compact"]) / int(r["ipog"]) for r in xs if int(r["ipog"]) > 0]
        @printf("  %-12s %3d points: balanced fewer on %3d, equal %3d; mean saving %.1f%% (compact %.1f%%); at the bound %d (IPOG %d)\n",
                fam, length(xs), count(r -> int(r["balanced"]) < int(r["ipog"]), xs),
                count(r -> int(r["balanced"]) == int(r["ipog"]), xs), 100sum(saved) / length(saved),
                100sum(csaved) / length(csaved), count(r -> r["minimal_balanced"] == "true", xs),
                count(r -> int(r["ipog"]) == int(r["bound"]), xs))
    end
    # The keep-the-smallest threshold: where the catalog's array is larger than IPOG's.
    println("\n== keep-the-smallest threshold (Profile.targets)")
    larger = [r for r in rows if r["fit"] == "exact" && !isempty(r["construction"]) &&
                                  int(r["construction"]) > int(r["ipog"])]
    println("  exact shapes where the catalog's array is larger than IPOG's design: ", length(larger))
    for r in sort(larger; by = r -> int(r["targets"]))
        println("    ", r["id"], " targets ", r["targets"], ": catalog ", r["construction"], ", IPOG ", r["ipog"])
    end
    seededlarger = [r for r in rows if r["fit"] == "seeded" && int(r["construction"]) > int(r["ipog"])]
    println("  seeded requests where the catalog's start is larger than IPOG's: ", length(seededlarger))
    for r in seededlarger
        println("    ", r["id"], " targets ", r["targets"], ": seeded ", r["construction"], ", IPOG ", r["ipog"])
    end
    exact = [r for r in rows if r["fit"] == "exact"]
    big = [int(r["targets"]) for r in exact]
    @printf("  exact shapes: %d, targets from %d to %d; above 10^4: %d, 10^5: %d, 10^6: %d\n", length(exact),
            minimum(big; init = 0), maximum(big; init = 0), count(>(10^4), big), count(>(10^5), big),
            count(>(10^6), big))
    for T in (0, 10^3, 10^4, 10^5, 10^6, 10^7)
        worse = count(r -> int(r["targets"]) > T && int(r["construction"]) > int(r["ipog"]), exact)
        skipped = [r for r in exact if int(r["targets"]) > T && int(r["construction"]) != int(r["bound"])]
        saved = sum(r -> num(r["ipog_s"]), skipped; init = 0.0)
        @printf("  threshold %8d: exact shapes above it with the catalog larger than IPOG %d; IPOG time not spent %.1f s on %d\n",
                T, worse, saved, length(skipped))
    end
end

"Phase 1's catalog-start gate through the public engines, at seed 0 and over seeds."
function catalog_gate(seeds)
    println("== catalog-start gate (plan §5.3) through Compact(Construction()) and Auto(goal = :compact)")
    for (k, v, t, gate) in ((8, 6, 3, 303), (30, 6, 2, 75))
        space = TestSpace([Symbol(:x, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
        start = U._catalog_entry(t, v, k)
        for (label, make) in (("Compact(Construction())", seed -> Compact(Construction(); seed)),
                              ("Auto(goal = :compact)", seed -> Auto(; goal = :compact, seed)))
            rows = Int[]
            chose = ""
            for seed in 0:(seeds - 1)
                d = generate(make(seed), Request(space; strength = t))
                push!(rows, size(d.matrix, 2))
                seed == 0 && (chose = get(d.record.ordinary, :chose, label))
            end
            med = median(Float64.(rows))
            @printf("  %d × %d, t = %d, start %s (%d rows): %-24s seed 0 %d (%s), median of %d seeds %.1f: %s %s\n",
                    k, v, t, start.name, start.rows, label, rows[1], rows[1] <= gate ? "PASS" : "FAIL", seeds, med,
                    med <= gate ? "PASS" : "FAIL", chose)
            println("      seeds 0:$(seeds - 1): ", join(rows, " "))
        end
    end
end

println("auto_regret at ", try readchomp(`git -C $ROOT rev-parse --short HEAD`) catch; "?" end, ", Julia ", VERSION,
        ", load ", round.(Sys.loadavg(); digits = 1), ", Auto's threshold ", U._AUTO_SMALL)
if ARGS[1] == "run"
    run_family(ARGS[2], ARGS[3])
elseif ARGS[1] == "summary"
    summary(ARGS[2:end])
elseif ARGS[1] == "catalog-gate"
    k = findfirst(==("--seeds"), ARGS)
    catalog_gate(k === nothing ? 10 : parse(Int, ARGS[k + 1]))
else
    error("usage: auto_regret.jl run FAMILY OUT.tsv | summary OUT.tsv... | catalog-gate [--seeds N]")
end
