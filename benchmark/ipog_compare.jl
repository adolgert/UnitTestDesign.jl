# Phase 4's comparison of IPOG cores (solver plan §5.5, "Tested against the
# paths it replaces" and "Gate for Phase 4"; §7): rows, warm time, bytes and
# peak memory of any engines on the points of the benchmark families, and the
# gates on them. Run from a checkout's root, with the package of whatever
# checkout `--project` names, so that two checkouts can be compared:
#
#     julia --project=. --startup-file=no benchmark/ipog_compare.jl run [POINTS] [ENGINES] [LIMITS] --out OUT.tsv
#     julia --project=. --startup-file=no benchmark/ipog_compare.jl fresh [POINTS] [ENGINES] [WATCHDOG] --out OUT.tsv
#     julia --project=. --startup-file=no benchmark/ipog_compare.jl summary FILE.tsv... [--ref COL] [--cand COL]...
#     julia --project=. --startup-file=no benchmark/ipog_compare.jl list [POINTS] [LIMITS]
#
# POINTS: `--family NAME` (repeatable) names a family of
# benchmark/scaling/families.py (`mainstream`, `mainstream-r1`, `smallest`,
# `uniform-pp`, `uniform-npp`, `strength`, `exact`, `adapted`, `casa`,
# `ct-comp`, `cart`; the last three need `python3
# benchmark/scaling/datasets.py fetch NAME`), or `large`, the points of the
# Phase 4 gate that the families don't hold (`LARGE` below: 8 × 64 and
# 8 × 32 at strength 2, the second also with a scoped rule that excludes
# nothing; 128, 512 and 1,024 binary parameters at strength 2; fixture 1,
# 15 × 4 at strength 4; 12 × 3 at strength 4; and D3's points of probe 24, 20
# parameters of 2, 3 and 4 values at strengths 4 to 6). `--points FILE.json`
# reads specs in the harness's format (run.py --specs). `--filter TEXT`
# (repeatable) keeps the points whose id (or spec id) holds one of them. A
# point is built as the harness's worker builds a spec of family "none" with
# usage "reuse" (worker.jl's `model`, model_specs.jl, spaces.jl): the same
# space, rules, `stronger` groups, must-include rows and limits, so both
# tools agree on what a point is. Its id is the spec's, without the solver
# ("uniform-pp-v3-k4-t2").
#
# ENGINES: `--engine EXPR` or `--engine LABEL=EXPR` (repeatable; default
# `IPOG()`). EXPR is Julia evaluated inside the module UnitTestDesign, so an
# internal engine such as `_IPOGLookup(tiebreak = :rotate)` works as well as
# `IPOG()` or `GND()`. LABEL (letters, digits, `_`, `-`, `.`) names the
# column; without it the column is EXPR.
#
# `run` builds each point once and runs every engine on it, in this process,
# one line per point and engine. Each engine is first compiled on small
# spaces at the sweep's strengths, built as the points are, plain and with
# each change of the `adapted` family (a rule, a partial must-include row, a
# `stronger` group, an `Invalid` value; `warm_up`), so that no point pays for
# compiling those paths; a point whose values have types the warm-up's
# don't still compiles for them. Then, at a point: a first call; then,
# unless the first took `--budget` seconds (default 2) or more, warm calls
# until `--calls` of them (default 3) or `--budget` seconds of them. The warm time is the minimum
# over the warm calls (a collection can triple a single call, plan §12.4), or
# the first call's when there were none; the bytes are the fewest any warm
# call allocated (`@timed`; on Julia 1.11.5 and later under macOS a large
# array counts at its malloc block's size, plan §12.4). Each call is
# `generate(engine, Request(space; kw...))`, so classification and
# certification are included, as in auto_regret.jl and the harness's `core`
# usage, and every result is certified. Every warm call must give the first
# call's rows, or the line says `nondeterministic`.
#
# One process can't stop a call, so `run` leaves out, in advance, the points
# whose cost it estimates too high (`over_limits`): those the family marks
# expensive (unless `--expensive`), those with more than `--max-targets`
# targets (default 2·10⁶) or more than `--max-cost` (default 4·10⁸) targets
# times the lower bound (families.py's proxy for IPOG's scan, about ten
# seconds at 2798ecf), and those with rules whose target bookkeeping, at the
# 24 bytes per parameter per target of plan §2.6, passes `--max-memory` GiB
# (default 1; that figure is a floor, and CASA's models at strength 3 peak at
# about twice it). `--max-seconds S` also leaves out the points whose
# `estimated_seconds` passes S (default: no such limit). These get a
# `skipped:` line; `fresh --over` runs exactly them. A first call that takes
# `--ladder-seconds` (default 120) or more also skips the larger points of
# its ladder for that engine, as run.py does.
# `--resume` keeps the lines OUT already holds and runs only the rest.
# `--classify-once` classifies each point's targets once and hands them to
# every engine (the package's internal `_Classified` and `_generate`, as
# `design_sizes` does), so the engines' times leave classification out and
# `classify_s` holds it: on constrained models the feasibility search can be
# nearly the whole call (ct-comp's MCAC_22: 35.6 of 36.1 s; CASA's benchmark
# 9 at strength 3: 37 s of 38), and a sweep of several candidates then pays
# for it once. What the targets build on first use (the required bits) is
# then built once too, by the first engine that asks, so the warm times leave
# it out: use the default mode for the time gates, and this one where only
# the rows matter, as in choosing the tie-break rule (with `--budget 0`, one
# call per point).
#
# `fresh` runs each point and engine in its own Julia process, with the
# same calls, under `/usr/bin/time -l` (macOS) for the process's peak RSS,
# and stops it at `--rss-mib` (default 8192) or `--seconds` (default 3600) of
# wall time, as benchmark/scaling/run.py's watchdog does: it samples the
# process group's RSS every half second and stops the group. Its defaults are
# `--calls 3 --budget 30`. It too leaves out the points a family marks
# expensive, unless `--expensive`; `--over` keeps only the points `run`'s
# limits leave out. `--work DIR` keeps each job's stdout and stderr (default:
# a directory beside OUT).
#
# Each line of OUT.tsv: the point (family, id, ladder, strength, parameters,
# the value counts in decreasing order as `v^count`, rules, `stronger` groups,
# must-include rows, Invalid values, the adaptation, targets, cost); the
# engine's column label and expression; `status` (`ok`, `skipped:…`,
# `resource_limit`, `error:…`, `nondeterministic`, and from `fresh`
# `timeout`, `rss_limit`, `crash`); the rows, their hash (`rows_hash`: the
# same on Julia 1.10 and 1.13), the required targets and the lower bound;
# `first_s`, `warm_s`, `calls` (warm calls), `bytes`, `gc_s` and `spent_s`
# (the point's whole time for the engine, or the time a failed call took);
# `peak_rss_mib` and `wall_s` (fresh only); the package's source (the last
# commit that changed its src/, `+` when src/ differs from it), the Julia
# version and the 1-minute load average when the point started; and
# `classify_s` (with `--classify-once`). Rows, hashes, bounds, bytes and peak
# RSS are exact; times are provisional on a busy machine.
#
# `summary` joins the lines of one or more files on the point and compares
# columns: `--ref COL` (default the first column read) against each `--cand
# COL` (repeatable; default every other column). A column is a label, so one
# run's files make one column; `LABEL@COMMIT` where the label was measured on
# two package sources; `…#FILE` where it still completes a point twice
# (`column_ids`); a completed line stands over a skipped or stopped one, so
# `fresh --over` fills in what `run` skipped. It prints Phase 4's gates (plan
# §5.5) for each candidate: the share of points with rows no more than
# the reference's (gate: 90%), the largest excess in percent and in rows,
# every point more than 3% above (gate: none), a point the reference
# completed and the candidate didn't counting against both; time ratios
# with the noise allowance below, every point slower beyond it (gate:
# none); and the named
# speed gates: strength 6 on 20 three-valued parameters in under 1,157 / 5 s
# (probe 24), on 20 two-valued parameters in no more than 8.6 s, and 8 × 64 at
# strength 2 in 1.61 / 5 s (Phase 0's quiet figure) and at least 5× faster
# than the reference's. Then a table of every candidate side by side (for
# choosing the tie-break rule), a breakdown by family, and the time each
# family took per column. `--wide OUT.tsv` also writes the joined table.
#
# Noise: a time differs only when the two warm minima differ by more than
# `--tolerance` (default 0.25) of the reference's and by more than `--floor`
# seconds (default 0.001); a point where both are under the floor is not
# judged. Why these: IPOG() against itself as two columns of one run, which
# alternate at every point, on 1,826 points of every family under load 2.6–7
# (an Apple M2 with another agent's Julia jobs): above a millisecond, 99% of
# the ratios lay within 0.81–1.19 and 6 of 873 beyond 25%; below it the
# second column was a median 9% faster at under 0.1 ms, from the order alone.
# Between two runs the machine moved: a rerun of three families beside
# heavier jobs was a median 19–34% slower at every size (up to 2×). So
# compare candidates as columns of one run; across runs, use a quiet machine
# or a larger `--tolerance`. `summary` says when two columns come from
# different files.

using UnitTestDesign, JSON, Printf
using UnitTestDesign: Request, generate

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
# A fresh process loads them only for bench12, so that they don't add to its
# peak memory.
if !(COMMAND[1:min(end, 1)] == ["child"] && get(JSON.parsefile(COMMAND[2]), "space", "") != "bench12")
    include(joinpath(ROOT, "benchmark", "fixtures.jl"))
end

# ---------------------------------------------------------------- options

"The value of every `--name VALUE` in `args`."
options(args, name) = [args[k + 1] for k in eachindex(args) if args[k] == name && k < length(args)]
option(args, name, default) = (xs = options(args, name); isempty(xs) ? default : last(xs))
flag(args, name) = name in args

"The engines as `(label, expression)`: `--engine LABEL=EXPR` or `--engine EXPR`."
function engine_columns(args)
    columns = Tuple{String, String}[]
    for text in options(args, "--engine")
        m = match(r"^([A-Za-z][A-Za-z0-9_.\-]*)=(?!=)(.*)$", text)
        push!(columns, m === nothing ? (strip(text), strip(text)) : (String(m[1]), strip(String(m[2]))))
    end
    isempty(columns) && push!(columns, ("IPOG()", "IPOG()"))
    length(unique(first.(columns))) == length(columns) || error("two engines have the same label")
    return columns
end

"An engine from its expression, evaluated inside the module UnitTestDesign."
make_engine(expr) = Core.eval(U, Meta.parse(expr))

# ---------------------------------------------------------------- points

# The Phase 4 gate's points the families don't hold (plan §5.5, §2.9; the
# quiet re-measurement's §2): (name, parameters, values, strength, adaptation).
const LARGE = [("8x64", 8, 64, 2, nothing), ("8x32", 8, 32, 2, nothing), ("8x32-noop", 8, 32, 2, "noop_scoped"),
               ("128x2", 128, 2, 2, nothing), ("512x2", 512, 2, 2, nothing), ("1024x2", 1024, 2, 2, nothing),
               ("15x4", 15, 4, 4, nothing), ("12x3", 12, 3, 4, nothing),
               ("20x2", 20, 2, 4, nothing), ("20x2", 20, 2, 5, nothing), ("20x2", 20, 2, 6, nothing),
               ("20x3", 20, 3, 4, nothing), ("20x3", 20, 3, 5, nothing), ("20x3", 20, 3, 6, nothing),
               ("20x4", 20, 4, 4, nothing), ("20x4", 20, 4, 5, nothing)]

"The targets of `t`-way coverage on value counts `arity`: the elementary symmetric polynomial (families.py's `targets`)."
function count_targets(arity, t)
    e = zeros(Int128, t + 1)
    e[1] = 1
    for a in arity, j in (t + 1):-1:2
        e[j] += e[j - 1] * a
    end
    return e[t + 1]
end

function large_specs()
    specs = Dict{String, Any}[]
    for (name, k, v, t, adapt) in LARGE
        targets = Int(count_targets(fill(v, k), t))
        s = Dict{String, Any}("id" => "large-$name-ipog-t$t", "ladder" => "large-$name-t$t", "grid" => "large",
                              "n" => k, "v" => v, "family" => "none", "usage" => "reuse", "solver" => "ipog",
                              "strength" => t, "runs" => 1, "targets" => targets, "cost" => targets * v^t)
        adapt === nothing || (s["adapt"] = adapt)
        push!(specs, s)
    end
    return specs
end

"Every spec of a family from families.py itself, expensive ones included and marked, as Dicts."
function family_specs(name)
    name == "large" && return large_specs()
    code = "import sys, json; sys.path.insert(0, 'benchmark/scaling'); import families\n" *
           "print(json.dumps(families.FAMILIES['$name'](['ipog'], 1)))"
    return JSON.parse(read(Cmd(`python3 -c $code`; dir = ROOT), String))
end

"The point's id: the spec's, without the solver the families put in it."
point_id(s) = replace(s["id"], r"-ipog-t(\d+)$" => s"-t\1")

"The selected specs: `--family`, `--points` and `--filter`, in order, each point once."
function select_specs(args)
    specs = Dict{String, Any}[]
    for name in options(args, "--family")
        append!(specs, family_specs(name))
    end
    for path in options(args, "--points")
        append!(specs, JSON.parsefile(path))
    end
    filters = options(args, "--filter")
    isempty(filters) || filter!(s -> any(f -> occursin(f, point_id(s)) || occursin(f, s["id"]), filters), specs)
    seen = Set{String}()
    return [s for s in specs if !(point_id(s) in seen) && (push!(seen, point_id(s)); true)]
end

"Whether a spec has rules, read from the spec (and an imported model's file) without building it."
function has_rules(s)
    !isempty(get(s, "forbid", [])) && return true
    get(s, "adapt", nothing) in ("noop_scoped", "forbid3") && return true
    haskey(s, "space") && return true
    haskey(s, "model") && return !isempty(JSON.parsefile(joinpath(ROOT, s["model"]))["forbid"])
    return false
end

const LIMITS = (expensive = false, max_targets = 2e6, max_cost = 4e8, max_memory = 1.0, max_seconds = Inf)

"""
A point's seconds for today's IPOG, estimated in advance: its targets times
its lower bound (families.py's `cost`) times its parameters, over 10⁹. On the
169 points without rules where today's IPOG (6b625c2's src/, Julia 1.13, an
Apple M2 under load 4–6) took over 0.1 s, that product ran at 0.8–3.9·10⁹
per second (median 2.3·10⁹), so this overstates by up to 4× and understates
by up to 1.25×; families.py's cost alone spread 222×, since a wide space's
rows are as long as it has parameters. With rules the feasibility search can
take far longer (ct-comp's MCAC_20 at strength 2: 105 s, against an estimate
of under a second).
"""
estimated_seconds(s) = s["cost"] * s["n"] / 1e9

function limits(args)
    return (expensive = flag(args, "--expensive"),
            max_seconds = parse(Float64, option(args, "--max-seconds", string(LIMITS.max_seconds))),
            max_targets = parse(Float64, option(args, "--max-targets", string(LIMITS.max_targets))),
            max_cost = parse(Float64, option(args, "--max-cost", string(LIMITS.max_cost))),
            max_memory = parse(Float64, option(args, "--max-memory", string(LIMITS.max_memory))))
end

"""
Why `run` leaves the point out, or `nothing`: its cost estimated in advance,
since one process can't stop a call (the header has the limits).
"""
function over_limits(s, lim)
    get(s, "expensive", false) && !lim.expensive && return "expensive"
    targets = s["targets"]
    targets > lim.max_targets && return "targets"
    s["cost"] > lim.max_cost && return "cost"
    has_rules(s) && 24 * s["n"] * targets > lim.max_memory * 2^30 && return "memory"
    estimated_seconds(s) > lim.max_seconds && return "seconds"
    return nothing
end

"""
The space and keywords of a spec, as worker.jl's `model` builds a spec of
family "none" with usage "reuse", from `base_model`'s parts. Called through
`invokelatest` after `base_model`, which compiles an imported model's
expressions, so that building the space can call them.
"""
function build(s, names, domains, rules)
    n = length(names)
    must, stronger = adapt!(s, names, domains, rules)
    space = TestSpace((names[i] => domains[i] for i in 1:n)...; constraints = rules, tabulation_limit = 100_000)
    kw = (; strength = s["strength"], stronger = Pair[spec_stronger(s, names); stronger], must_include = Any[must...],
          feasibility_limit = get(s, "nodes", 100_000), explanation_limit = get(s, "explanations", 1_000_000))
    return space, kw
end

"Value counts in decreasing order, as `v^count`: `4^3 3 2^5`."
function arity_text(arity)
    counts = sort!(collect(pairs(Dict(v => count(==(v), arity) for v in unique(arity)))); rev = true)
    return join((c == 1 ? string(v) : "$v^$c" for (v, c) in counts), " ")
end

# ---------------------------------------------------------------- measuring

"""
    rows_hash(matrix) -> String

FNV-1a, 64 bits, of the design's rows as text: one row (a column of
`matrix`) per line, its values, which are value positions from 1, separated by
single spaces, each line ending in a newline. The same rows give the same
hash on every Julia version, where `hash(matrix)` differs between 1.10 and
1.13. In Python: `h = 0xcbf29ce484222325; for b in text.encode(): h = ((h ^
b) * 0x100000001b3) % 2**64`.
"""
function rows_hash(m::AbstractMatrix{<:Integer})
    h = 0xcbf29ce484222325
    fnv(h, b) = (h ⊻ UInt64(b)) * 0x00000100000001b3
    for j in axes(m, 2), i in axes(m, 1)
        for b in codeunits(string(m[i, j]))
            h = fnv(h, b)
        end
        h = fnv(h, i == lastindex(m, 1) ? UInt8('\n') : UInt8(' '))
    end
    return string(h; base = 16, pad = 16)
end

"""
Compile `engine` on small spaces at each strength, built as the points are
(`build`, from a uniform spec of `t + 2` binary parameters): plain, and with
each change of the `adapted` family, a scoped rule that excludes nothing,
three forbidden pairs, a partial must-include row, a `stronger` group (where
the strength leaves room for one) and an `Invalid` value, whose negative
rows take another path. So no point pays for compiling them, except for the
value types of its own space.
"""
function warm_up(engine, strengths)
    for t in sort(unique(strengths))
        for adapt in (nothing, "noop_scoped", "forbid3", "seed", "stronger", "invalid")
            adapt == "stronger" && t + 1 > min(6, t + 2) && continue   # `adapt!`'s group needs t + 1 <= 6
            s = Dict{String, Any}("n" => t + 2, "v" => 2, "family" => "none", "usage" => "reuse", "strength" => t)
            adapt === nothing || (s["adapt"] = adapt)
            space, kw = build(s, base_model(s)...)
            generate(engine, Request(space; kw...))
        end
    end
end

"""
One engine on one point: a first call, then warm calls (the header says how
many), each `generate(engine, Request(space; kw...))`, or, given the point's
`classified` targets (`--classify-once`), the same generation from them
(`_generate`, as `design_sizes` hands one classification to every engine).
"""
function measure(engine, space, kw; calls, budget, classified = nothing)
    function call()
        request = Request(space; kw...)
        return classified === nothing ? generate(engine, request) :
                                        U._generate(U._check_fit(engine, request), request, classified)
    end
    start = time()
    GC.gc(false)
    first = @timed call()
    design = first.value
    warm, bytes, gc, n, same, spent = first.time, first.bytes, first.gctime, 0, true, 0.0
    if first.time < budget && calls > 0
        warm, bytes = Inf, typemax(Int)
        while n < calls && spent < budget
            w = @timed call()
            n += 1
            spent += w.time
            same &= w.value.matrix == design.matrix
            w.time < warm && ((warm, gc) = (w.time, w.gctime))
            bytes = min(bytes, w.bytes)
        end
    end
    return (; design, first = first.time, warm, bytes, gc, calls = n, same, spent = time() - start)
end

const COLUMNS = ["family", "point", "ladder", "t", "k", "arity", "rules", "stronger", "must", "invalid", "adapt",
                 "targets", "cost", "label", "expr", "status", "rows", "hash", "required", "bound", "first_s",
                 "warm_s", "calls", "bytes", "gc_s", "spent_s", "peak_rss_mib", "wall_s", "commit", "julia", "load",
                 "classify_s"]

# The package's source: the last commit that changed src/ in its checkout, `+`
# when src/ differs from it, `?` outside git.
const COMMIT = let dir = pkgdir(U)
    head = try readchomp(`git -C $dir log -1 --format=%h -- src`) catch; "?" end
    dirty = try !isempty(readchomp(`git -C $dir status --porcelain -- src`)) catch; false end
    (isempty(head) ? "?" : head) * (dirty ? "+" : "")
end

load1() = @sprintf("%.2f", Sys.loadavg()[1])

"The point's columns of a line, from the spec and, when it was built, its space and keywords."
function point_fields(s, space = nothing, kw = nothing)
    arity = space === nothing ? Int.(get(s, "arity", fill(s["v"], s["n"]))) :
            [count(x -> !(x isa Invalid), d) for d in space.values]
    invalid = space === nothing ? "" : sum(d -> count(x -> x isa Invalid, d), space.values)
    return Any[get(s, "grid", s["family"]), point_id(s), get(s, "ladder", ""), s["strength"], length(arity),
               arity_text(arity), space === nothing ? "" : length(space.constraints),
               kw === nothing ? "" : length(kw.stronger), kw === nothing ? "" : length(kw.must_include), invalid,
               get(s, "adapt", ""), s["targets"], s["cost"]]
end

"One line of OUT.tsv."
function line(point, label, expr, status; r = nothing, rss = "", wall = "", load = load1(), spent = "",
              classify = "")
    d = r === nothing ? nothing : r.design
    fields = Any[point; label; expr; status;
                 d === nothing ? ["", "", "", ""] :
                     [size(d.matrix, 2), rows_hash(d.matrix), d.required, something(d.record.lower_bound, "")];
                 r === nothing ? ["", "", "", "", "", spent] :
                     [@sprintf("%.6f", r.first), @sprintf("%.6f", r.warm), r.calls, r.bytes, @sprintf("%.6f", r.gc),
                      @sprintf("%.3f", r.spent)];
                 rss; wall; COMMIT; string(VERSION); load; classify]
    return join(fields, '\t')
end

"Each engine on one built point: one line per engine. `skip[label]` holds ladders an engine has stopped."
function run_point(s, parts, engines, opts, skip)
    load = load1()
    space, kw = build(s, parts...)
    point = point_fields(s, space, kw)
    out = String[]
    # --classify-once: the point's targets, classified once for every engine; a
    # classification that fails is every engine's failure.
    classified, classify, failed = nothing, "", nothing
    if opts.classify_once
        started = time()
        try
            classified = U._Classified(Request(space; kw...))
        catch e
            e isa InterruptException && rethrow()
            @warn "$(point_id(s)) classification" exception = e
            failed = e isa U.ResourceLimitError ? "resource_limit" : "error:$(nameof(typeof(e)))"
        end
        classify = @sprintf("%.3f", time() - started)
    end
    for (label, expr, engine) in engines
        if failed !== nothing
            push!(out, line(point, label, expr, failed; load, spent = classify, classify))
            continue
        end
        ladder = get(s, "ladder", "")
        if !isempty(ladder) && haskey(skip[label], ladder)
            push!(out, line(point, label, expr, "skipped:ladder after $(skip[label][ladder])"; load))
            continue
        end
        started = time()
        status, r = try
            r = measure(engine, space, kw; opts.calls, opts.budget, classified)
            (r.same ? "ok" : "nondeterministic"), r
        catch e
            e isa InterruptException && rethrow()
            @warn "$(point_id(s)) $label" exception = e
            (e isa U.ResourceLimitError ? "resource_limit" : "error:$(nameof(typeof(e)))"), nothing
        end
        # A call that failed records the seconds it took to fail as `spent_s`.
        took = r === nothing ? time() - started : r.first
        took >= opts.ladder_seconds && !isempty(ladder) && (skip[label][ladder] = point_id(s))
        push!(out, line(point, label, expr, status; r, load, spent = r === nothing ? @sprintf("%.3f", took) : "",
                        classify))
    end
    return out
end

"The (point, label) pairs an existing OUT already holds, for `--resume`."
done_pairs(path) = isfile(path) ? Set((r["point"], r["label"]) for r in read_lines([path])) : Set{Tuple{String, String}}()

function run_sweep(args)
    out = option(args, "--out", nothing)
    out === nothing && error("run needs --out OUT.tsv")
    lim = limits(args)
    opts = (calls = parse(Int, option(args, "--calls", "3")), budget = parse(Float64, option(args, "--budget", "2")),
            ladder_seconds = parse(Float64, option(args, "--ladder-seconds", "120")),
            classify_once = flag(args, "--classify-once"))
    columns = engine_columns(args)
    specs = select_specs(args)
    done = flag(args, "--resume") ? done_pairs(out) : Set{Tuple{String, String}}()
    engines = [(label, expr, make_engine(expr)) for (label, expr) in columns]
    started = time()
    for (label, _, engine) in engines
        Base.invokelatest(warm_up, engine, [s["strength"] for s in specs if over_limits(s, lim) === nothing])
    end
    @printf("compiled %d engines in %.1f s\n", length(engines), time() - started)
    skip = Dict(label => Dict{String, String}() for (label, _) in columns)
    fresh_file = !(flag(args, "--resume") && isfile(out))
    open(out, fresh_file ? "w" : "a") do io
        fresh_file && println(io, join(COLUMNS, '\t'))
        for (i, s) in enumerate(specs)
            todo = [e for e in engines if !((point_id(s), e[1]) in done)]
            isempty(todo) && continue
            reason = over_limits(s, lim)
            lines = if reason !== nothing
                [line(point_fields(s), label, expr, "skipped:$reason") for (label, expr, _) in todo]
            else
                parts = base_model(s)        # compiles an imported model's expressions: a new world
                Base.invokelatest(run_point, s, parts, todo, opts, skip)
            end
            foreach(l -> println(io, l), lines)
            flush(io)
            summary_line = join((let f = split(l, '\t'); "$(f[14]) $(f[16] == "ok" ? f[17] : f[16])" end
                                 for l in lines), "  ")
            @printf("%4d/%d %-44s %s\n", i, length(specs), point_id(s), summary_line)
            flush(stdout)
        end
    end
    @printf("run: %d points, %d engines, %.1f s, load %s at the end\n", length(specs), length(engines),
            time() - started, load1())
end

function list_points(args)
    lim = limits(args)
    @printf("%-48s %4s %4s %12s %14s %10s %6s  %s\n", "point", "t", "k", "targets", "cost", "estimate", "rules", "run")
    for s in select_specs(args)
        reason = over_limits(s, lim)
        @printf("%-48s %4d %4d %12d %14.4g %9.3gs %6s  %s\n", point_id(s), s["strength"], s["n"], s["targets"],
                s["cost"], estimated_seconds(s), has_rules(s), reason === nothing ? "in-process" : "skipped:$reason")
    end
end

# ---------------------------------------------------------------- fresh processes

"Sampled resident memory of a process group, in bytes (`ps`, as run.py samples it)."
function group_rss(pgid)
    total = 0
    for l in eachline(`ps -axo pgid=,rss=`)
        f = split(l)
        length(f) == 2 && parse(Int, f[1]) == pgid && (total += parse(Int, f[2]) * 1024)
    end
    return total
end

"Stop a process group: SIGTERM, then SIGKILL after two seconds (run.py's `stop_group`)."
function stop_group(p, pgid)
    run(ignorestatus(`kill -TERM -$pgid`))
    for _ in 1:20
        process_running(p) || return
        sleep(0.1)
    end
    run(ignorestatus(`kill -KILL -$pgid`))
    wait(p)
end

"""
One point and engine in a fresh Julia process under `/usr/bin/time -l`,
stopped at `rss_mib` of the group's resident memory or `seconds` of wall
time: the line, with its peak RSS (the OS's high-water mark, or the sampled
one where the process was stopped) and wall time.
"""
function fresh_job(s, label, expr, opts, work)
    name = replace("$(point_id(s))--$label", r"[^A-Za-z0-9_.\-]" => "_")
    specpath, outpath, errpath = (joinpath(work, name * x) for x in (".json", ".out", ".err"))
    write(specpath, JSON.json(s))
    julia = Base.julia_cmd()
    script = @__FILE__
    cmd = `/usr/bin/time -l $julia --project=$(Base.active_project()) --startup-file=no --threads=1 $script child`
    cmd = `$cmd $specpath $label $expr --calls $(opts.calls) --budget $(opts.budget)`
    cmd = Cmd(addenv(cmd, "JULIA_NUM_THREADS" => "1", "OPENBLAS_NUM_THREADS" => "1"); detach = true)
    load = load1()
    started = time()
    peak, stopped = 0, nothing
    p = open(outpath, "w") do o
        open(errpath, "w") do e
            run(pipeline(cmd; stdout = o, stderr = e); wait = false)
        end
    end
    pgid = getpid(p)        # a detached process leads its own group, as run.py's start_new_session
    while process_running(p)
        sleep(0.5)
        rss = try group_rss(pgid) catch; 0 end
        peak = max(peak, rss)
        if rss > opts.rss_mib * 2^20
            stopped = "rss_limit"
        elseif time() - started > opts.seconds
            stopped = "timeout"
        end
        stopped === nothing || (stop_group(p, pgid); break)
    end
    wait(p)
    wall = time() - started
    err = read(errpath, String)
    m = match(r"(\d+)\s+maximum resident set size", err)
    rss = m === nothing ? peak : parse(Int, m[1])
    output = readlines(outpath)
    result = findlast(l -> startswith(l, "RESULT\t"), output)
    stage = findlast(l -> startswith(l, "STAGE "), output)
    where = stage === nothing ? "startup" : output[stage][7:end]
    if result !== nothing && stopped === nothing
        fields = split(output[result], '\t')[2:end]
        fields[findfirst(==("peak_rss_mib"), COLUMNS)] = @sprintf("%.0f", rss / 2^20)
        fields[findfirst(==("wall_s"), COLUMNS)] = @sprintf("%.1f", wall)
        fields[findfirst(==("load"), COLUMNS)] = load
        return join(fields, '\t')
    end
    status = stopped !== nothing ? "$stopped($where)" : "crash($where, exit $(p.exitcode))"
    return line(point_fields(s), label, expr, status; rss = @sprintf("%.0f", rss / 2^20),
                wall = @sprintf("%.1f", wall), load)
end

function fresh_sweep(args)
    out = option(args, "--out", nothing)
    out === nothing && error("fresh needs --out OUT.tsv")
    lim = limits(args)
    opts = (calls = parse(Int, option(args, "--calls", "3")), budget = parse(Float64, option(args, "--budget", "30")),
            rss_mib = parse(Float64, option(args, "--rss-mib", "8192")),
            seconds = parse(Float64, option(args, "--seconds", "3600")))
    work = option(args, "--work", splitext(out)[1] * "_jobs")
    mkpath(work)
    specs = select_specs(args)
    lim.expensive || filter!(s -> !get(s, "expensive", false), specs)
    flag(args, "--over") && filter!(s -> over_limits(s, lim) !== nothing, specs)
    columns = engine_columns(args)
    foreach(c -> make_engine(c[2]), columns)          # an expression that doesn't evaluate stops here, not in every child
    done = flag(args, "--resume") ? done_pairs(out) : Set{Tuple{String, String}}()
    fresh_file = !(flag(args, "--resume") && isfile(out))
    started = time()
    open(out, fresh_file ? "w" : "a") do io
        fresh_file && println(io, join(COLUMNS, '\t'))
        for (i, s) in enumerate(specs), (label, expr) in columns
            (point_id(s), label) in done && continue
            l = fresh_job(s, label, expr, opts, work)
            println(io, l)
            flush(io)
            f = split(l, '\t')
            @printf("%4d/%d %-36s %-24s %-22s rows %-6s warm %-10s RSS %s MiB, wall %s s\n", i, length(specs),
                    point_id(s), label, f[16], f[17], f[22], f[27], f[28])
            flush(stdout)
        end
    end
    @printf("fresh: %d points, %d engines, %.1f s\n", length(specs), length(columns), time() - started)
end

"The child of `fresh`: one point and one engine, printing its stages and one RESULT line."
function child(args)
    s = JSON.parsefile(args[2])
    label, expr = args[3], args[4]
    opts = (calls = parse(Int, option(args, "--calls", "3")), budget = parse(Float64, option(args, "--budget", "30")))
    stage(name) = (println("STAGE ", name); flush(stdout))
    stage("warm-up")
    engine = make_engine(expr)
    Base.invokelatest(warm_up, engine, [s["strength"]])
    stage("build")
    parts = base_model(s)
    load = load1()
    Base.invokelatest() do
        space, kw = build(s, parts...)
        GC.gc()
        stage("calls")
        r = measure(engine, space, kw; opts.calls, opts.budget)
        println("RESULT\t", line(point_fields(s, space, kw), label, expr, r.same ? "ok" : "nondeterministic"; r, load))
    end
end

# ---------------------------------------------------------------- summary

"The lines of the files, as Dicts of column => text, each with the file it came from."
function read_lines(paths)
    rows = Dict{String, String}[]
    for path in paths
        lines = readlines(path)
        header = split(lines[1], '\t')
        for l in lines[2:end]
            isempty(l) && continue
            r = Dict(String(h) => String(v) for (h, v) in zip(header, split(l, '\t')))
            r["file"] = basename(path)
            push!(rows, r)
        end
    end
    return rows
end

num(x) = parse(Float64, x)
int(x) = parse(Int, x)
geomean(xs) = isempty(xs) ? NaN : exp(sum(log, xs) / length(xs))
median(x) = (s = sort(x); isempty(s) ? NaN : isodd(length(s)) ? s[(end + 1) ÷ 2] : (s[end ÷ 2] + s[end ÷ 2 + 1]) / 2)
"How much `a` exceeds `b`, in percent; an empty design (a space with no valid row) against another is 0%."
pct(a, b) = b == 0 ? (a == 0 ? 0.0 : Inf) : 100 * (a - b) / b

"A shape key for uniform points without rules or changes, so the named gates find them in any family: `20x3-t6`."
function shape(r)
    plain = all(r[c] in ("0", "") for c in ("rules", "stronger", "must", "invalid")) && isempty(r["adapt"])
    a = split(r["arity"])
    plain && length(a) == 1 && occursin('^', a[1]) || return ""
    v, k = split(a[1], '^')
    return "$(k)x$(v)-t$(r["t"])"
end

"""
The columns of the lines, in the order first read. A column is a label, so
that one run's files (one per family) make one column; `LABEL@COMMIT` where
the label was measured on more than one package source, as when today's
`IPOG()` meets the new branch's; and `…#FILE` where the label (and commit)
still completes a point twice, as two runs of the same source do. A line
that didn't complete doesn't count: a `fresh --over` run fills in the points
`run` skipped (`rank`).
"""
function column_ids(rows)
    commits = Dict{String, Set{String}}()
    for r in rows
        push!(get!(commits, r["label"], Set{String}()), r["commit"])
    end
    for r in rows
        r["column"] = length(commits[r["label"]]) > 1 ? "$(r["label"])@$(r["commit"])" : r["label"]
    end
    seen = Dict{String, Set{String}}()
    twice = Set{String}()
    for r in rows
        r["status"] == "ok" || continue
        points = get!(seen, r["column"], Set{String}())
        r["point"] in points && push!(twice, r["column"])
        push!(points, r["point"])
    end
    for r in rows
        r["column"] in twice && (r["column"] = "$(r["column"])#$(r["file"])")
    end
    return unique(r["column"] for r in rows)
end

function pick(columns, name)
    name in columns && return name
    hits = [c for c in columns if startswith(c, name * "@") || startswith(c, name * "#") || endswith(c, name)]
    length(hits) == 1 || error("no single column matches $name; columns: $(join(columns, ", "))")
    return hits[1]
end

"""
Which of two lines for one point and column stands: a completed call (3)
over a call that failed (2), over a fresh process that was stopped (1), over
a point that was skipped (0); the later line among equals.
"""
rank(r) = r["status"] == "ok" ? 3 : startswith(r["status"], "skipped") ? 0 :
          any(startswith(r["status"], x) for x in ("rss_limit", "timeout", "crash")) ? 1 : 2

"The time comparison of two warm minima: :fast (both under the floor), :slower, :faster or :same."
function judge(ref, cand, tol, floor)
    max(ref, cand) < floor && return :fast
    allowance = max(floor, tol * ref)
    cand - ref > allowance && return :slower
    ref - cand > max(floor, tol * cand) && return :faster
    return :same
end

"One candidate against the reference: Phase 4's gates (plan §5.5)."
function compare(ref, cand, by, opts)
    ok(r) = r !== nothing && r["status"] == "ok"
    points = sort!(collect(union(keys(by[ref]), keys(by[cand]))))
    both = [p for p in points if ok(get(by[ref], p, nothing)) && ok(get(by[cand], p, nothing))]
    lost = [p for p in points if ok(get(by[ref], p, nothing)) && !ok(get(by[cand], p, nothing))]
    gained = [p for p in points if !ok(get(by[ref], p, nothing)) && ok(get(by[cand], p, nothing))]
    println("\n== $cand against $ref: $(length(both)) points where both completed")
    if !isempty(lost)
        println("  the candidate did not complete $(length(lost)) points the reference did:")
        for p in first(lost, opts.show)
            c = get(by[cand], p, nothing)
            println("    ", p, ": ", c === nothing ? "not run" : c["status"])
        end
        length(lost) > opts.show && println("    … and $(length(lost) - opts.show) more")
    end
    isempty(gained) || println("  the candidate completed $(length(gained)) points the reference did not: ",
                               join(first(gained, 10), ", "), length(gained) > 10 ? ", …" : "")
    if isempty(both)
        isempty(lost) || println("  rows gate: FAIL (the candidate completed none of the points the reference did)")
        return nothing
    end
    R(p) = by[ref][p]
    C(p) = by[cand][p]
    rows(r) = int(r["rows"])
    fewer = count(p -> rows(C(p)) < rows(R(p)), both)
    equal = count(p -> rows(C(p)) == rows(R(p)), both)
    same_hash = count(p -> C(p)["hash"] == R(p)["hash"], both)
    excess = [(pct(rows(C(p)), rows(R(p))), rows(C(p)) - rows(R(p)), p) for p in both]
    worst_pct = maximum(excess)
    worst_rows = maximum(e -> (e[2], e[1], e[3]), excess)
    above = sort!([e for e in excess if e[1] > 3]; rev = true)
    # The rows gate is over every point the reference completed: one the
    # candidate didn't complete counts against both of its clauses.
    share = (fewer + equal) / (length(both) + length(lost))
    @printf("  rows: fewer at %d, equal at %d, more at %d; identical rows (hash) at %d\n", fewer, equal,
            length(both) - fewer - equal, same_hash)
    @printf("  rows no more than the reference's at %.1f%% of the %d points the reference completed%s: %s (gate: 90%% or more)\n",
            100share, length(both) + length(lost),
            isempty(lost) ? "" : " ($(length(lost)) not completed by the candidate count as more)",
            share >= 0.9 ? "PASS" : "FAIL")
    @printf("  largest excess: %+.1f%% (%s), %+d rows (%s)\n", worst_pct[1], worst_pct[3], worst_rows[1], worst_rows[3])
    @printf("  points more than 3%% above: %d%s: %s (gate: none)\n", length(above),
            isempty(lost) ? "" : ", and $(length(lost)) not completed", isempty(above) && isempty(lost) ? "PASS" : "FAIL")
    for (e, d, p) in above
        @printf("    %-48s %6d → %6d  %+5.1f%% (%+d rows)\n", p, rows(R(p)), rows(C(p)), e, d)
    end
    @printf("  total rows: reference %d, candidate %d (%+.2f%%)\n", sum(p -> rows(R(p)), both),
            sum(p -> rows(C(p)), both), pct(sum(p -> rows(C(p)), both), sum(p -> rows(R(p)), both)))
    # Time.
    w(r) = num(r["warm_s"])
    verdicts = Dict(p => judge(w(R(p)), w(C(p)), opts.tol, opts.floor) for p in both)
    judged = [p for p in both if verdicts[p] != :fast]
    ratios = [w(C(p)) / w(R(p)) for p in judged]
    slower = sort!([p for p in judged if verdicts[p] == :slower]; by = p -> -w(C(p)) / w(R(p)))
    @printf("  time (warm minima; differ when by more than %.0f%% and %.1f ms): %d points under %.1f ms not judged; of %d judged, faster %d, same %d, slower %d\n",
            100opts.tol, 1000opts.floor, length(both) - length(judged), 1000opts.floor, length(judged),
            count(p -> verdicts[p] == :faster, judged), count(p -> verdicts[p] == :same, judged), length(slower))
    isempty(ratios) || @printf("  time ratio candidate / reference over judged points: geometric mean %.3f, median %.3f, min %.3f, max %.3f\n",
                               geomean(ratios), median(ratios), minimum(ratios), maximum(ratios))
    @printf("  no slower anywhere on the grid: %s (%d points slower beyond the allowance; provisional)\n",
            isempty(slower) ? "PASS" : "FAIL", length(slower))
    for p in first(slower, opts.show)
        @printf("    %-48s %10.4g s → %10.4g s  ×%.2f\n", p, w(R(p)), w(C(p)), w(C(p)) / w(R(p)))
    end
    length(slower) > opts.show && println("    … and $(length(slower) - opts.show) more")
    # The named speed gates.
    println("  named speed gates (provisional):")
    # A point of that shape, the `large` family's (a fresh process) where there is one.
    function find(col, key)
        xs = sort!([r for r in values(by[col]) if ok(r) && shape(r) == key]; by = r -> r["family"] != "large")
        return isempty(xs) ? nothing : xs[1]
    end
    for (key, limit, source) in (("20x3-t6", 1157 / 5, "probe 24's 1,157 s / 5"), ("20x2-t6", 8.6, "probe 24's 8.6 s"),
                                 ("8x64-t2", 1.61 / 5, "Phase 0's quiet 1.61 s / 5"))
        c, r = find(cand, key), find(ref, key)
        if c === nothing
            @printf("    %-8s not measured by the candidate\n", key)
            continue
        end
        @printf("    %-8s %.3f s (first call %.3f s): %s against %s = %.4g s", key, w(c), num(c["first_s"]),
                w(c) <= limit ? "PASS" : "FAIL", source, limit)
        r === nothing || @printf("; reference %.3f s, ×%.2f", w(r), w(c) / w(r))
        key == "8x64-t2" && r !== nothing && @printf(", 5× faster than it: %s", w(c) <= w(r) / 5 ? "PASS" : "FAIL")
        println()
    end
    return (; both, lost, fewer, equal, share, worst_pct, worst_rows, above, slower, ratios, verdicts)
end

function summary(args)
    paths = [a for (k, a) in enumerate(args) if k > 1 && !startswith(a, "--") && !startswith(args[k - 1], "--")]
    rows = read_lines(paths)
    columns = column_ids(rows)
    ref = pick(columns, option(args, "--ref", columns[1]))
    cands = [pick(columns, c) for c in options(args, "--cand")]
    isempty(cands) && (cands = [c for c in columns if c != ref])
    opts = (tol = parse(Float64, option(args, "--tolerance", "0.25")),
            floor = parse(Float64, option(args, "--floor", "0.001")), show = parse(Int, option(args, "--show", "25")))
    by = Dict(c => Dict{String, Dict{String, String}}() for c in columns)
    for r in rows
        old = get(by[r["column"]], r["point"], nothing)
        old !== nothing && rank(old) == rank(r) == 3 &&
            @warn "$(r["column"]) completes $(r["point"]) twice; the later line wins"
        (old === nothing || rank(r) >= rank(old)) && (by[r["column"]][r["point"]] = r)
    end
    println("ipog_compare summary: ", length(paths), " files, ", length(rows), " lines")
    for c in columns
        xs = collect(values(by[c]))
        loads = [num(r["load"]) for r in xs]
        @printf("  %-40s %5d points (%d ok), commit %s, Julia %s, load %.1f–%.1f\n", c, length(xs),
                count(r -> r["status"] == "ok", xs), join(unique(r["commit"] for r in xs), "/"),
                join(unique(r["julia"] for r in xs), "/"), minimum(loads), maximum(loads))
    end
    println("reference: ", ref)
    files(c) = Set(r["file"] for r in values(by[c]))
    for c in cands
        isdisjoint(files(ref), files(c)) || continue
        load(c) = (xs = [num(r["load"]) for r in values(by[c])]; sum(xs) / length(xs))
        @printf("note: %s and %s come from different runs (mean load %.1f and %.1f); their times are comparable only on a quiet machine or with a larger --tolerance\n",
                ref, c, load(ref), load(c))
    end
    results = Dict(c => compare(ref, c, by, opts) for c in cands)
    # Every candidate side by side, on the points where all completed.
    if length(cands) > 1
        common = [p for p in keys(by[ref]) if all(c -> haskey(by[c], p) && by[c][p]["status"] == "ok", [ref; cands])]
        println("\n== candidates side by side, on the $(length(common)) points where every column completed")
        @printf("  %-36s %9s %7s %7s %8s %6s %9s %9s %8s %7s\n", "column", "rows", "vs ref", "≤ ref", "max exc",
                ">3%", "smallest", "time gm", "slower", "gates")
        best = Dict(p => minimum(int(by[c][p]["rows"]) for c in cands) for p in common)
        total_ref = sum(p -> int(by[ref][p]["rows"]), common; init = 0)
        for c in [ref; cands]
            total = sum(p -> int(by[c][p]["rows"]), common; init = 0)
            le = count(p -> int(by[c][p]["rows"]) <= int(by[ref][p]["rows"]), common)
            exc = maximum((pct(int(by[c][p]["rows"]), int(by[ref][p]["rows"])) for p in common); init = 0.0)
            gt3 = count(p -> pct(int(by[c][p]["rows"]), int(by[ref][p]["rows"])) > 3, common)
            small = count(p -> int(by[c][p]["rows"]) == best[p], common)
            ratios = [num(by[c][p]["warm_s"]) / num(by[ref][p]["warm_s"]) for p in common
                      if judge(num(by[ref][p]["warm_s"]), num(by[c][p]["warm_s"]), opts.tol, opts.floor) != :fast]
            slow = count(p -> judge(num(by[ref][p]["warm_s"]), num(by[c][p]["warm_s"]), opts.tol, opts.floor) == :slower,
                         common)
            # A point the reference completed and the candidate didn't fails the rows gate (`compare`).
            lost = c == ref || results[c] === nothing ? 0 : length(results[c].lost)
            gates = le >= 0.9 * length(common) && gt3 == 0 && lost == 0 ? "rows ok" : "rows FAIL"
            @printf("  %-36s %9d %+6.2f%% %6.1f%% %+7.1f%% %6d %9d %9.3f %8d %9s\n", first(c, 36), total,
                    pct(total, total_ref), 100le / max(1, length(common)), exc, gt3, small, geomean(ratios), slow,
                    c == ref ? "(ref)" : gates)
        end
        println("  (rows: total over these points; smallest: points where the column has the fewest rows among the candidates)")
    end
    # By family.
    for c in cands
        res = results[c]
        res === nothing && continue
        println("\n== by family: $c against $ref")
        @printf("  %-14s %6s %6s %6s %6s %5s %9s %9s %9s %9s %8s\n", "family", "points", "fewer", "equal", "more",
                ">3%", "max exc", "rows ref", "rows cand", "time gm", "slower")
        for fam in sort(unique(by[ref][p]["family"] for p in res.both))
            ps = [p for p in res.both if by[ref][p]["family"] == fam]
            rr = [int(by[ref][p]["rows"]) for p in ps]
            cr = [int(by[c][p]["rows"]) for p in ps]
            ratios = [num(by[c][p]["warm_s"]) / num(by[ref][p]["warm_s"]) for p in ps if res.verdicts[p] != :fast]
            @printf("  %-14s %6d %6d %6d %6d %5d %+8.1f%% %9d %9d %9.3f %8d\n", fam, length(ps), count(cr .< rr),
                    count(cr .== rr), count(cr .> rr), count(pct.(cr, rr) .> 3), maximum(pct.(cr, rr)), sum(rr),
                    sum(cr), geomean(ratios), count(p -> res.verdicts[p] == :slower, ps))
        end
    end
    # How long each family took, per column.
    println("\n== time per family and column (spent_s: first call, warm calls and collections; s)")
    fams = sort(unique(r["family"] for r in rows))
    @printf("  %-40s", "column")
    foreach(f -> @printf(" %13s", first(f, 13)), fams)
    println()
    for c in columns
        @printf("  %-40s", first(c, 40))
        for f in fams
            xs = [num(r["spent_s"]) for r in values(by[c]) if r["family"] == f && !isempty(r["spent_s"])]
            isempty(xs) ? @printf(" %13s", "-") : @printf(" %13.1f", sum(xs))
        end
        println()
    end
    wide = option(args, "--wide", nothing)
    wide === nothing || write_wide(wide, by, [ref; cands])
end

"The joined table: one line per point, rows and warm time per column."
function write_wide(path, by, cols)
    points = sort!(collect(union((keys(by[c]) for c in cols)...)))
    open(path, "w") do io
        println(io, join(["point", "family", "t", "k", "arity", "bound",
                          (x * "_" * c for c in cols for x in ("status", "rows", "warm_s"))...], '\t'))
        for p in points
            any0 = first(by[c][p] for c in cols if haskey(by[c], p))
            fields = Any[p, any0["family"], any0["t"], any0["k"], any0["arity"], any0["bound"]]
            for c in cols
                r = get(by[c], p, nothing)
                append!(fields, r === nothing ? ["", "", ""] : [r["status"], r["rows"], r["warm_s"]])
            end
            println(io, join(fields, '\t'))
        end
    end
end

# ---------------------------------------------------------------- main

const USAGE = "usage: ipog_compare.jl run|fresh|list [--family F]... [--points FILE]... [--filter S]... " *
              "[--engine [LABEL=]EXPR]... --out OUT.tsv | summary FILE... [--ref COL] [--cand COL]..."
if isempty(ARGS)
    error(USAGE)
elseif ARGS[1] == "child"
    child(ARGS)
else
    println("ipog_compare ", ARGS[1], " at ", COMMIT, " (", pkgdir(U), "), Julia ", VERSION, ", load ",
            round.(Sys.loadavg(); digits = 1))
    ARGS[1] == "run" ? run_sweep(ARGS) :
    ARGS[1] == "fresh" ? fresh_sweep(ARGS) :
    ARGS[1] == "summary" ? summary(ARGS) :
    ARGS[1] == "list" ? list_points(ARGS) : error(USAGE)
end
