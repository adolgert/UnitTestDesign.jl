# Phase 5's gate points (solver plan §5.6 "Gate", §2.8, §2.9, §12.7 item 3;
# the orchestrator's p5/decision_rule.md §1, items 2–4): the memory the
# request's feasibility caches and the classified targets retain, peak memory,
# and the time of the study's ladders, each point measured in a fresh process
# per engine and mode, with the package of whatever checkout `--project`
# names, as benchmark/ipog_compare.jl measures. Run from a checkout's root:
#
#     julia --project=. --startup-file=no benchmark/phase5_gate.jl list [POINTS]
#     julia --project=. --startup-file=no benchmark/phase5_gate.jl fresh [POINTS] [ENGINES] [MODES] [LIMITS] --out OUT.tsv
#     julia --project=. --startup-file=no benchmark/phase5_gate.jl summary --base FILE... [--branch FILE...] [--recheck-base FILE... --recheck-branch FILE...]
#     julia --project=. --startup-file=no benchmark/phase5_gate.jl outside --base FILE... --branch FILE...
#
# It includes ipog_compare.jl for its functions (the row hash, the engines as
# expressions, the fresh process and its watchdog, the harness's warm and
# first calls, the line files), so the two tools agree on how a call is timed
# and stopped. Nothing here reads how the package stores its memo or its
# targets: classification is `_Classified(request)` and generation on it
# `_generate(_check_fit(engine, request), request, classified)`, as
# `design_sizes` calls them, and the bytes are counted from outside.
#
# POINTS: `--group gate` or `--group ladder` (repeatable; default both),
# `--point ID` (repeatable) and `--filter TEXT` (repeatable; the ids that hold
# one of them). The points (`POINTS` below):
#
# - `gcc200`, `gcc400`: probe 21's model (design/20261003_solver_plan_review_
#   probes/21_many_options_today.jl, `model(n, "gcc")`), shaped like the GCC
#   optimizer model of Cohen, Dwyer & Shi 2007: n options, 95% of them
#   `[:off, :on]` and the rest `[:low, :mid, :high]`, and rules over 17.6% of
#   the on/off options, chains of "a on needs b on" and sometimes "not all
#   three off", from `Xoshiro(1)`; strength 2 and the request's default
#   limits. 24 rules and 83,625 targets at 200; 46 rules and 335,350 at 400
#   (on Julia 1.13; the random stream differs on 1.10). Probe 21 at 2798ecf:
#   83,581 required, 266 MiB of memo and 132 MiB of list at 200; 2.0 GiB and
#   1.0 GiB at 400. Modes `index`, `peak` and `covering` (plan §2.8,
#   "Through `covering`": 3.0 s and 1.4 GiB at 200, 19 s and 6.2 GiB at
#   400).
# - `t6-20x2-rule`, `t5-20x3-rule`: probe 24's `rule` argument
#   (24_high_strength_20_parameters.jl): k parameters with values `1:v`, one
#   rule `forbid((p1 = 1, p2 = 1))`, the request's default limits. Probe 24:
#   996 + 483 MiB, and 1.5 + 0.7 GiB. Modes `index` and `peak`.
# - `bin1024-noop`: 1,024 binary parameters with a scoped rule that excludes
#   nothing, built as the ladders are (worker.jl's `noop_scoped`), strength
#   2. Modes `index` and `peak`.
# - The ladders, built exactly as benchmark/scaling/worker.jl's `model`
#   builds a spec of usage "reuse" (`family_space`): values `Any[1, 2]`,
#   `tabulation_limit = 100_000`, `feasibility_limit = 100_000`,
#   `explanation_limit = 1_000_000`, strength 2; ids `FAMILY-nN`.
#   `equality`, `whole` and `noop_whole` are the gate's (decision rule §1
#   item 4), `chain` and `noop_scoped` are reported beside them;
#   `noop_scoped` holds probe 06's shapes (n = 8, 32, … 512). n = 8, 16, 32,
#   64 and 128, and 256 and 512 for `noop_scoped`; `equality` stops at 64,
#   since at 128 the base takes 47 s a call. A ladder stops at the first
#   size a tree doesn't complete within the study's limits (below).
#   Modes `index` and `covering`. The 2798ecf baseline of the same ladders
#   is in UTD-wt/phase0/benchmark/scaling/results/2798ecf-baseline-20261004/.
#
# ENGINES: `--engine EXPR` or `--engine LABEL=EXPR`, as in ipog_compare.jl
# (default `IPOG()` and `Auto()`). MODES: `--mode index`, `--mode peak` or
# `--mode covering` (repeatable; default every mode the point has).
#
# `fresh` runs each point, engine and mode in its own Julia process
# (ipog_compare.jl's `child_command` and `watch`: `/usr/bin/time -l`, the
# process group's RSS sampled every half second, stopped past `--rss-mib`
# (default 8192) or `--seconds` (default 3600)). The child first runs the
# whole measurement once on a small point built the same way (gcc at 20
# options, k = t + 2 for the rule, n = 8 for the ladders), so that the
# measured calls don't compile it. Then, in mode `index` (the gate's "in
# index space"):
#
#  1. two full collections, and `live0 = Base.gc_live_bytes()`, the space
#     alive;
#  2. `request = Request(space; kw...)`; `req0_b`, its bytes;
#  3. classification, `classified = _Classified(request)`: `classify_s`,
#     `classify_bytes`, and `hwm_c_mib`, the process's high-water mark
#     (`Sys.maxrss`) after it;
#  4. the bytes retained after classification (`…_c_…`, below): first the
#     live heap and the memo's entries, then a `PARTIAL` line, then the
#     summarysize walks and a second `PARTIAL` line; the last one stands if
#     the process is stopped later;
#  5. `_generate` on that classification, the first call of the engine on
#     this point (certification included): `gen_s`, `gen_bytes`, the rows,
#     their hash, the required and excluded counts, the bound, and
#     `hwm_g_mib`;
#  6. the design dropped, the bytes retained after generation (`…_g_…`),
#     and a third `PARTIAL` line;
#  7. the request and classification dropped, then the harness's own calls
#     (ipog_compare.jl's `measure`): a first and then warm calls of a whole
#     `generate(engine, Request(space; kw...))`, each with its own request,
#     classification and certification: `first_s`, `warm_s` (the minimum of
#     the warm calls), `calls`, `bytes` (the fewest any warm call
#     allocated), `gc_s`. Their rows must equal step 5's.
#
# In mode `peak`, one whole `generate(engine, Request(space; kw...))`
# (classification and certification included) and nothing else, so that the
# process's peak RSS is one call's after the warm-up, as gate 3 asks:
# `gen_s`, `gen_bytes`, the rows, and `hwm_g_mib`. Mode `index`'s peak also
# holds its summarysize walks and warm calls.
#
# In mode `covering`, the public call `covering(space; engine, kw...)`:
# `first_s`, `warm_s`, `calls`, `bytes`, `gc_s`, and the rows and hash of the
# returned cases (their value indices). `--calls N` and `--budget S` (default
# 3 and 30) set the warm calls of the gate points; a ladder point makes at
# least `--ladder-calls` (default 5) within `--ladder-budget` (default 300 s),
# so that decision rule §1 gate 4 compares minima of at least five warm calls.
#
# Retained bytes, measured two ways that don't depend on how the memo or the
# targets are stored. `…_c_…` after classification, `…_g_…` after generation:
#
# - `Base.summarysize`, with the space excluded (it retains nothing from an
#   operation, contract §3.5; `exclude` is Base's default plus `TestSpace`):
#   `feas_*_b`, the request's `feasibility` (every cache it keeps, whatever
#   its fields: the memo, the component caches, the lazy-rule verdicts, the
#   tables and candidates); `req_*_b`, the whole request (its feasibility,
#   its negative-row context, candidates, groups); `cls_*_b`, the
#   classification (its targets, layout, counts, bits once built, excluded
#   records); `tgt_c_b` and `exc_c_b`, its `targets` and `excluded` fields
#   where it has them; and `ret_*_b`, the request and the classification
#   together, shared parts counted once: **the gate's figure**.
# - `live_*_b`: `Base.gc_live_bytes()` after two full collections, less
#   `live0`, with the request and the classification kept alive
#   (`GC.@preserve`) and the design dropped. It counts what summarysize does
#   plus the allocator's rounding of each object to its size class, and
#   anything else the call left alive.
# - `memo_c`, `memo_g`: the entry count of every dictionary in
#   `request.feasibility`, found by walking its fields (`memo_entries`), and
#   of every package function named like `memo_size` that takes the search
#   or the request: `memo=83601 witness_cache[]=224 memo_size()=0` at
#   `gcc200` on 31bef0f, with `rule_memo[].verdicts=…` where a rule is lazy
#   (a whole-case rule).
#
# `--no-retained` leaves out steps 1, 4 and 6 (summarysize keeps a
# dictionary of every object it visits, which raises the process's peak).
#
# A ladder is skipped from the first size whose line, for the same label and
# mode, in OUT or in this run, did not complete or whose warm call took
# `--ladder-seconds` (default 30, run.py's stage limit) or more, as run.py
# stops a ladder (`--continue-ladders` runs every size). `--resume` keeps
# OUT's lines and runs only the (point, label, mode) it lacks, so a driver
# can alternate trees point by point, each into its own file. `--work DIR`
# keeps each job's spec, stdout and stderr (default: beside OUT).
#
# Each line of OUT.tsv (`COLUMNS`): the point (`group`, `point`, `ladder`,
# `t`, `k`, value counts as in ipog_compare.jl, `rules`, `targets`); `label`,
# `expr`, `mode`; `status` (`ok`, `resource_limit`, `error:…`,
# `nondeterministic`, `skipped:…`, and from the watchdog `rss_limit(STAGE)`,
# `timeout(STAGE)`, `crash(STAGE, exit N)`); `rows`, `hash` (ipog_compare.jl's
# `rows_hash`), `required`, `excluded`, `bound`; the times and bytes above;
# `peak_rss_mib` (the OS's high-water mark, or the sampled one where stopped)
# and `wall_s`; the package's source (`commit`: the last commit that changed
# its src/, `+` when src/ differs), the Julia version, the 1-minute load when
# the job started, and `entry`, the classification and generation entries
# used. Bytes, rows and hashes are exact; times are provisional on a busy
# machine, and peak RSS depends on memory pressure on macOS (plan §12.4).
#
# `summary` reads the base's lines (`--base`, the reference) and the
# branch's (`--branch`), each option taking the files after it, and prints a
# table of every point, the jobs the watchdog stopped, then each gate of
# decision rule §1 items 2–4 with its verdict:
#
# - gate 2: at `gcc200` the branch's retained bytes (`ret`, the larger of
#   after classification and after generation, summarysize) under 20 MiB,
#   and at `t6-20x2-rule` under 50 MiB, for each engine in mode `index`,
#   with the base's figures and the gc_live cross-check beside them;
# - gate 3: `bin1024-noop` completed by `IPOG()` in mode `peak` with the
#   process's peak RSS under 2 GiB (2,048 MiB);
# - gate 4: at every ladder point of `equality`, `whole` and `noop_whole` the
#   base completed within the study's limits (its warm minimum under
#   `--ladder-seconds`, 30 s, run.py's stage limit), for each engine and
#   mode, the branch's warm minimum at most `--tolerance` (default 0.10)
#   above the base's or within `--floor` (default 0.001 s) of it, every point
#   outside listed; with `--recheck-base` and `--recheck-branch` (a second,
#   alternating run of the points outside, from `outside`), a point fails
#   only if it is outside in both runs. `chain`, `noop_scoped` and points
#   past the study's limits are judged the same way and reported, not gated;
# - completed: every (point, engine, mode) the base completed and the
#   branch ran, gated or not, completes on the branch (an error,
#   `nondeterministic` or a stop there fails), and a branch line that is an
#   error or `nondeterministic` fails wherever the base stood;
# - rows: at every (point, engine, mode) both completed, the same rows,
#   hash, `required`, `excluded` and `bound` (Phase 5 changes no row or
#   count); any difference fails.
#
# One line is kept per (point, label, mode): a completed one over a failed,
# stopped or skipped one, the later among equals, but a `nondeterministic`
# one over every other, so that a resumed file can't hide it.
#
# Without `--branch` it prints the base's table and the thresholds only.
# `outside` prints the ids of the ladder points outside the time rule, one per
# line, for a recheck (`fresh --point ID`). Both take `--tolerance`,
# `--floor` and `--ladder-seconds`.

using UnitTestDesign, JSON, Printf, Random
using UnitTestDesign: Request, generate

"benchmark/ipog_compare.jl's functions, without its main (it runs only as a script)."
module IC
include(joinpath(@__DIR__, "ipog_compare.jl"))
end

const U = UnitTestDesign

# ---------------------------------------------------------------- points

# equality stops at 64: at 128 the base classifies for 47 s a call (p5-bench's notes), past run.py's
# 30 s stage limit, so the study's limits leave it out.
const LADDER_SIZES = Dict("equality" => [8, 16, 32, 64], "whole" => [8, 16, 32, 64, 128],
                          "noop_whole" => [8, 16, 32, 64, 128], "chain" => [8, 16, 32, 64, 128],
                          "noop_scoped" => [8, 16, 32, 64, 128, 256, 512])
const LADDER_ORDER = ["equality", "whole", "noop_whole", "chain", "noop_scoped"]
"The ladders decision rule §1 gate 4 names; the others are reported beside them."
const GATED_LADDERS = ("equality", "whole", "noop_whole")

"Every point, as the Dicts a child reads from JSON: gate points first, then the ladders, smallest first."
function all_points()
    pts = Dict{String, Any}[]
    gate(id, builder, n, v, t, modes; family = "") =
        push!(pts, Dict{String, Any}("id" => id, "group" => "gate", "ladder" => "", "builder" => builder,
                                     "family" => family, "n" => n, "v" => v, "t" => t, "modes" => modes))
    gate("gcc200", "gcc", 200, 0, 2, ["index", "peak", "covering"])
    gate("gcc400", "gcc", 400, 0, 2, ["index", "peak", "covering"])
    gate("t6-20x2-rule", "rule", 20, 2, 6, ["index", "peak"])
    gate("t5-20x3-rule", "rule", 20, 3, 5, ["index", "peak"])
    gate("bin1024-noop", "family", 1024, 2, 2, ["index", "peak"]; family = "noop_scoped")
    for family in LADDER_ORDER, n in LADDER_SIZES[family]
        push!(pts, Dict{String, Any}("id" => "$family-n$n", "group" => "ladder", "ladder" => family,
                                     "builder" => "family", "family" => family, "n" => n, "v" => 2, "t" => 2,
                                     "modes" => ["index", "covering"]))
    end
    return pts
end

"The selected points: `--group`, `--point`, `--filter`, in `all_points`' order."
function select_points(args)
    groups = IC.options(args, "--group")
    ids = IC.options(args, "--point")
    filters = IC.options(args, "--filter")
    pts = all_points()
    isempty(groups) || filter!(p -> p["group"] in groups, pts)
    isempty(ids) || filter!(p -> p["id"] in ids, pts)
    isempty(filters) || filter!(p -> any(f -> occursin(f, p["id"]), filters), pts)
    unknown = setdiff(ids, [p["id"] for p in all_points()])
    isempty(unknown) || error("no point named $(join(unknown, ", ")); `list` names them")
    return pts
end

"""
Probe 21's model (21_many_options_today.jl, `model(n, "gcc")`), line for line:
`n` options, 95% on/off and 5% of three values, and rules over 17.6% of the
on/off options in small groups, each a chain of "a on needs b on", with "not
all three off" on a quarter of the groups of three or more.
"""
function gcc_space(n::Int)
    names = [Symbol(:o, i) for i in 1:n]
    binary = round(Int, 0.95n)
    domains = [names[i] => (i <= binary ? [:off, :on] : [:low, :mid, :high]) for i in 1:n]
    constraints = Any[]
    rng = Xoshiro(1)
    constrained = shuffle(rng, 1:binary)[1:round(Int, 0.176n)]
    start = 1
    while start < length(constrained)
        group = constrained[start:min(start + rand(rng, 1:3), length(constrained))]
        for (a, b) in zip(group[1:(end - 1)], group[2:end])          # a on needs b on
            push!(constraints, forbid(NamedTuple{(names[a], names[b])}((:on, :off))))
        end
        if length(group) >= 3 && rand(rng) < 0.25                      # not all three off
            push!(constraints, forbid(NamedTuple{Tuple(names[group[1:3]])}((:off, :off, :off))))
        end
        start += length(group)
    end
    return TestSpace(domains...; constraints)
end

"Probe 24's space with its `rule` argument (24_high_strength_20_parameters.jl): `k` parameters of values `1:v`, one rule."
rule_space(k::Int, v::Int) =
    TestSpace((Symbol(:p, i) => collect(1:s) for (i, s) in enumerate(fill(v, k)))...;
              constraints = Any[forbid((p1 = 1, p2 = 1))])

"""
The space and keywords of benchmark/scaling/worker.jl's `model` for a spec
of `family` with usage "reuse", n binary-or-v-valued parameters: the same
values, rules, tabulation limit and request limits (worker.jl's `model`,
`base_model` of an n × v spec, no adaptation).
"""
function family_space(family::AbstractString, n::Int, v::Int, t::Int)
    names = [Symbol(:p, i) for i in 1:n]
    domains = [Any[1:v...] for _ in 1:n]
    rules = Constraint[]
    if family == "whole"
        push!(rules, forbid(c -> c.p1 == 1 && c.p2 == 1))
    elseif family == "noop_scoped"
        push!(rules, forbid((a, b) -> false, :p1, :p2))
    elseif family == "noop_whole"
        push!(rules, forbid(c -> false))
    elseif family in ("chain", "equality")
        for i in 1:(n - 1)
            pred = family == "equality" ? ((a, b) -> a != b) : ((a, b) -> a == 1 && b == 1)
            push!(rules, forbid(pred, names[i], names[i + 1]))
        end
    else
        throw(ArgumentError("no ladder family $family"))
    end
    space = TestSpace((names[i] => domains[i] for i in 1:n)...; constraints = rules, tabulation_limit = 100_000)
    kw = (; strength = t, stronger = Pair[], must_include = Any[], feasibility_limit = 100_000,
          explanation_limit = 1_000_000)
    return space, kw
end

"The space and the keywords of `Request` and `covering` for a point."
function build_point(p)
    b, n, v, t = p["builder"], p["n"], p["v"], p["t"]
    b == "gcc" && return gcc_space(n), (; strength = t)
    b == "rule" && return rule_space(n, v), (; strength = t)
    b == "family" && return family_space(p["family"], n, v, t)
    throw(ArgumentError("no builder $b"))
end

"A point of the same kind, small enough to compile the measurement on: gcc at 20 options, k = t + 2, n = 8."
function small_point(p)
    q = copy(p)
    q["id"] = p["id"] * "-warmup"
    q["n"] = p["builder"] == "gcc" ? 20 : p["builder"] == "rule" ? p["t"] + 2 : 8
    return q
end

"The value counts of a point, without building it."
function point_arity(p)
    n = p["n"]
    p["builder"] == "gcc" && return [fill(2, round(Int, 0.95n)); fill(3, n - round(Int, 0.95n))]
    return fill(p["v"], n)
end

# ---------------------------------------------------------------- measuring

const COLUMNS = ["group", "point", "ladder", "t", "k", "arity", "rules", "targets", "label", "expr", "mode", "status",
                 "rows", "hash", "required", "excluded", "bound", "classify_s", "classify_bytes", "gen_s", "gen_bytes",
                 "first_s", "warm_s", "calls", "bytes", "gc_s", "spent_s",
                 "req0_b", "feas_c_b", "req_c_b", "cls_c_b", "tgt_c_b", "exc_c_b", "ret_c_b", "live_c_b", "memo_c",
                 "hwm_c_mib", "feas_g_b", "req_g_b", "cls_g_b", "ret_g_b", "live_g_b", "memo_g", "hwm_g_mib",
                 "peak_rss_mib", "wall_s", "commit", "julia", "load", "entry"]

const ENTRY = "_Classified+_generate"

"Classification as `design_sizes` does it: the request's targets, classified once."
classify(request) = U._Classified(request)

"Generation on a classification, as `design_sizes` calls it: the engine's plan, checked, then executed."
generate_on(engine, request, classified) = U._generate(U._check_fit(engine, request), request, classified)

"The live heap after two full collections."
live_bytes() = (GC.gc(true); GC.gc(true); Base.gc_live_bytes())

"`Base.summarysize` without the space, which retains nothing from an operation (contract §3.5)."
bytes_of(x) = Base.summarysize(x; exclude = Union{TestSpace, DataType, Core.TypeName, Core.MethodInstance})

"""
The entry counts of the dictionaries `x` holds, by field path, walking its
fields, vectors and their elements to `depth` levels: a vector's elements
count together under `name[]`.
"""
function dict_counts!(found::Dict{String, Int}, x, path::String, depth::Int)
    if x isa AbstractDict
        found[path] = get(found, path, 0) + length(x)
    elseif depth <= 0 || x isa Union{Number, Symbol, AbstractString, Function, Module, Type, Nothing}
        return found
    elseif x isa AbstractArray
        isbitstype(eltype(x)) && return found
        for y in x
            dict_counts!(found, y, path * "[]", depth - 1)
        end
    elseif isstructtype(typeof(x))
        for name in fieldnames(typeof(x))
            isdefined(x, name) || continue
            dict_counts!(found, getfield(x, name), isempty(path) ? string(name) : "$path.$name", depth - 1)
        end
    end
    return found
end

"""
The memo's entry counts, found reflectively, so that they read any
storage: every dictionary in `request.feasibility` (`dict_counts!`), and the
value of every function of the package named like `memo_size`
(`memo`, then `size`, `entries`, `count` or `length`) that takes the search
or the request.
"""
function memo_entries(request)
    f = request.feasibility
    found = dict_counts!(Dict{String, Int}(), f, "", 3)
    parts = ["$k=$v" for (k, v) in sort!(collect(found))]
    for name in names(U; all = true)
        s = lowercase(string(name))
        occursin("memo", s) && any(w -> occursin(w, s), ("size", "entries", "count", "length")) || continue
        g = getfield(U, name)
        g isa Function || continue
        for x in (f, request)
            if hasmethod(g, Tuple{typeof(x)})
                push!(parts, "$name()=$(g(x))")
                break
            end
        end
    end
    return join(parts, " ")
end

"The retained bytes of `request` and `classified` into `r`, `k` being \"c\" or \"g\"."
function retained!(r, k, request, classified)
    r["feas_$(k)_b"] = bytes_of(request.feasibility)
    r["req_$(k)_b"] = bytes_of(request)
    r["cls_$(k)_b"] = bytes_of(classified)
    r["ret_$(k)_b"] = bytes_of((request, classified))
    if k == "c"
        r["tgt_c_b"] = hasproperty(classified, :targets) ? bytes_of(classified.targets) : ""
        r["exc_c_b"] = hasproperty(classified, :excluded) ? bytes_of(classified.excluded) : ""
    end
    return r
end

"The value indices of public cases, one column per case, for the row hash."
function case_matrix(space, cases)
    isempty(cases) && return zeros(Int, length(space.names), 0)
    return reduce(hcat, [collect(Int, U.case_indices(space, row)) for row in cases])
end

stage(name, quiet) = quiet || (println("STAGE ", name); flush(stdout))
mib(x) = @sprintf("%.1f", x / 2^20)

"""
Mode `index` on one built point (the header's steps 1–7), into `r`. With
`emit`, prints a `PARTIAL` line after classification (twice: before and
after the summarysize walks) and after generation.
"""
function measure_index!(r, engine, space, kw, opts; emit = identity, quiet = false)
    retained = opts.retained
    live0 = retained ? live_bytes() : 0
    request = Request(space; kw...)
    classified = nothing
    GC.@preserve request begin
        retained && (r["req0_b"] = bytes_of(request))
        stage("classify", quiet)
        c = @timed classify(request)
        classified = c.value
        r["classify_s"], r["classify_bytes"] = @sprintf("%.6f", c.time), c.bytes
        r["hwm_c_mib"] = mib(Sys.maxrss())
        c = nothing
        GC.@preserve classified begin
            if retained
                stage("retained-classify", quiet)
                r["live_c_b"] = live_bytes() - live0
                r["memo_c"] = memo_entries(request)
                emit(r)                   # before summarysize, whose walk can be what stops a large point
                retained!(r, "c", request, classified)
            end
            emit(r)
            stage("generate", quiet)
            g = @timed generate_on(engine, request, classified)
            d = g.value
            r["gen_s"], r["gen_bytes"] = @sprintf("%.6f", g.time), g.bytes
            r["rows"], r["hash"], r["required"] = size(d.matrix, 2), IC.rows_hash(d.matrix), d.required
            r["excluded"], r["bound"] = length(d.excluded), something(d.record.lower_bound, "")
            r["hwm_g_mib"] = mib(Sys.maxrss())
            g = d = nothing
            if retained
                stage("retained-generate", quiet)
                r["live_g_b"] = live_bytes() - live0
                r["memo_g"] = memo_entries(request)
                retained!(r, "g", request, classified)
            end
            emit(r)                       # a stop in the warm calls keeps the rows and bytes
        end
    end
    request = classified = nothing
    stage("calls", quiet)
    m = IC.measure(engine, space, kw; opts.calls, opts.budget)
    timing!(r, m)
    r["status"] = m.same && size(m.design.matrix, 2) == r["rows"] && IC.rows_hash(m.design.matrix) == r["hash"] ?
                  "ok" : "nondeterministic"
    return r
end

"""
Mode `peak`: one whole `generate(engine, Request(space; kw...))`, its
classification and certification included, and nothing else, so that the
process's peak RSS is that of one call (after the warm-up): `gen_s`,
`gen_bytes`, the rows, and `hwm_g_mib`.
"""
function measure_peak!(r, engine, space, kw; quiet = false)
    stage("generate", quiet)
    g = @timed generate(engine, Request(space; kw...))
    d = g.value
    r["gen_s"], r["gen_bytes"] = @sprintf("%.6f", g.time), g.bytes
    r["rows"], r["hash"], r["required"] = size(d.matrix, 2), IC.rows_hash(d.matrix), d.required
    r["excluded"], r["bound"] = length(d.excluded), something(d.record.lower_bound, "")
    r["hwm_g_mib"] = mib(Sys.maxrss())
    r["status"] = "ok"
    return r
end

"Mode `covering`: the public call, first and warm calls as ipog_compare.jl's `measure` makes them, into `r`."
function measure_covering!(r, engine, space, kw, opts; quiet = false)
    stage("covering", quiet)
    call() = covering(space; engine, kw...)
    start = time()
    GC.gc(false)
    first = @timed call()
    cases = first.value
    warm, bytes, gc, n, same, spent = first.time, first.bytes, first.gctime, 0, true, 0.0
    if first.time < opts.budget && opts.calls > 0
        warm, bytes = Inf, typemax(Int)
        while n < opts.calls && spent < opts.budget
            w = @timed call()
            n += 1
            spent += w.time
            same &= w.value.cases == cases.cases
            w.time < warm && ((warm, gc) = (w.time, w.gctime))
            bytes = min(bytes, w.bytes)
        end
    end
    matrix = case_matrix(space, cases)
    r["rows"], r["hash"], r["required"] = size(matrix, 2), IC.rows_hash(matrix), cases.required
    r["excluded"], r["bound"] = length(cases.excluded), something(get(cases.record, :lower_bound, nothing), "")
    timing!(r, (; first = first.time, warm, bytes, gc, calls = n, spent = time() - start))
    r["status"] = same ? "ok" : "nondeterministic"
    return r
end

function timing!(r, m)
    r["first_s"], r["warm_s"], r["calls"] = @sprintf("%.6f", m.first), @sprintf("%.6f", m.warm), m.calls
    r["bytes"], r["gc_s"], r["spent_s"] = m.bytes, @sprintf("%.6f", m.gc), @sprintf("%.3f", m.spent)
    return r
end

"The point's own columns, from the spec and, where it was built, its space."
function point_fields!(r, p, space = nothing)
    arity = space === nothing ? point_arity(p) : [count(x -> !(x isa Invalid), d) for d in space.values]
    r["group"], r["point"], r["ladder"], r["t"], r["k"] = p["group"], p["id"], p["ladder"], p["t"], length(arity)
    r["arity"], r["targets"] = IC.arity_text(arity), Int(IC.count_targets(arity, p["t"]))
    space === nothing || (r["rules"] = length(space.constraints))
    return r
end

line_text(r) = join((string(get(r, c, "")) for c in COLUMNS), '\t')

"""
One point, engine and mode, measured into a line's fields. A call that throws
gives `resource_limit` or `error:TYPE`, with the fields measured before it.
"""
function measure_point(p, label, expr, engine, mode, opts; emit = identity, quiet = false)
    r = Dict{String, Any}("label" => label, "expr" => expr, "mode" => mode, "commit" => IC.COMMIT,
                          "julia" => string(VERSION), "load" => IC.load1(), "entry" => ENTRY)
    point_fields!(r, p)
    stage("build", quiet)
    space, kw = build_point(p)
    point_fields!(r, p, space)
    started = time()
    try
        mode == "index" ? measure_index!(r, engine, space, kw, opts; emit, quiet) :
        mode == "peak" ? measure_peak!(r, engine, space, kw; quiet) :
        mode == "covering" ? measure_covering!(r, engine, space, kw, opts; quiet) :
        throw(ArgumentError("no mode $mode"))
    catch e
        e isa InterruptException && rethrow()
        quiet || @warn "$(p["id"]) $label $mode" exception = e
        r["status"] = e isa U.ResourceLimitError ? "resource_limit" : "error:$(nameof(typeof(e)))"
        r["spent_s"] = @sprintf("%.3f", time() - started)       # the seconds the call took to fail
    end
    return r
end

"The child of `fresh`: one point, engine and mode, after compiling them on a small point; prints its stages, a PARTIAL and a RESULT line."
function child(args)
    p = JSON.parsefile(args[2])
    label, expr, mode = args[3], args[4], args[5]
    opts = (calls = parse(Int, IC.option(args, "--calls", "3")), budget = parse(Float64, IC.option(args, "--budget", "30")),
            retained = !IC.flag(args, "--no-retained"))
    stage("warm-up", false)
    engine = IC.make_engine(expr)
    warm = Base.invokelatest(measure_point, small_point(p), label, expr, engine, mode,
                             (calls = 1, budget = Inf, retained = opts.retained); quiet = true)
    warm["status"] == "ok" || error("the warm-up failed: $(warm["status"])")
    emit(r) = (println("PARTIAL\t", line_text(r)); flush(stdout))
    r = Base.invokelatest(measure_point, p, label, expr, engine, mode, opts; emit)
    println("RESULT\t", line_text(r))
end

# ---------------------------------------------------------------- fresh processes

"""
One point, engine and mode in a fresh process (ipog_compare.jl's `watch`):
the child's RESULT line, or, where it was stopped or crashed, its PARTIAL
line (or the point's own fields) with the status and the stage it reached.
"""
function fresh_job(p, label, expr, mode, opts, work)
    name = replace("$(p["id"])--$label--$mode", r"[^A-Za-z0-9_.\-]" => "_")
    specpath, outpath, errpath = (joinpath(work, name * x) for x in (".json", ".out", ".err"))
    write(specpath, JSON.json(p))
    extra = opts.retained ? String[] : ["--no-retained"]
    cmd = IC.child_command(@__FILE__, `$specpath $label $expr $mode --calls $(opts.calls) --budget $(opts.budget) $extra`)
    load = IC.load1()
    w = IC.watch(cmd, outpath, errpath; opts.rss_mib, opts.seconds)
    result = findlast(l -> startswith(l, "RESULT\t"), w.output)
    partial = findlast(l -> startswith(l, "PARTIAL\t"), w.output)
    take(k) = Dict{String, Any}(zip(COLUMNS, split(w.output[k], '\t')[2:end]))
    r = if result !== nothing && w.stopped === nothing
        take(result)
    else
        r = partial === nothing ? point_fields!(Dict{String, Any}("label" => label, "expr" => expr, "mode" => mode,
                                                                   "commit" => IC.COMMIT, "julia" => string(VERSION),
                                                                   "entry" => ENTRY), p) :
                                  take(partial)
        r["status"] = w.stopped !== nothing ? "$(w.stopped)($(w.where))" : "crash($(w.where), exit $(w.p.exitcode))"
        r
    end
    r["peak_rss_mib"], r["wall_s"], r["load"] = @sprintf("%.0f", w.rss / 2^20), @sprintf("%.1f", w.wall), load
    return line_text(r)
end

"The lines of the files, as Dicts of column => text (ipog_compare.jl's `read_lines`)."
read_lines(paths) = IC.read_lines(filter(isfile, paths))

"""
Why a ladder point is skipped for `label` and `mode`, or `nothing`: a smaller
size of its ladder, in `done`, did not complete, or took `seconds` or more
(warm minimum), as run.py stops a ladder.
"""
function ladder_stop(p, label, mode, done, seconds)
    p["group"] == "ladder" || return nothing
    for q in all_points()
        q["ladder"] == p["ladder"] && q["n"] < p["n"] || continue
        r = get(done, (q["id"], label, mode), nothing)
        r === nothing && continue
        r["status"] == "ok" || return "skipped:ladder after $(q["id"])"
        tryparse(Float64, r["warm_s"]) !== nothing && parse(Float64, r["warm_s"]) >= seconds &&
            return "skipped:ladder after $(q["id"])"
    end
    return nothing
end

function fresh_sweep(args)
    out = IC.option(args, "--out", nothing)
    out === nothing && error("fresh needs --out OUT.tsv")
    opts = (calls = parse(Int, IC.option(args, "--calls", "3")), budget = parse(Float64, IC.option(args, "--budget", "30")),
            ladder_calls = parse(Int, IC.option(args, "--ladder-calls", "5")),
            ladder_budget = parse(Float64, IC.option(args, "--ladder-budget", "300")),
            ladder_seconds = parse(Float64, IC.option(args, "--ladder-seconds", "30")),
            rss_mib = parse(Float64, IC.option(args, "--rss-mib", "8192")),
            seconds = parse(Float64, IC.option(args, "--seconds", "3600")), retained = !IC.flag(args, "--no-retained"),
            continue_ladders = IC.flag(args, "--continue-ladders"))
    work = IC.option(args, "--work", splitext(out)[1] * "_jobs")
    mkpath(work)
    pts = select_points(args)
    columns = IC.options(args, "--engine")
    columns = isempty(columns) ? [("IPOG()", "IPOG()"), ("Auto()", "Auto()")] : IC.engine_columns(args)
    foreach(c -> IC.make_engine(c[2]), columns)          # an expression that doesn't evaluate stops here
    modes = IC.options(args, "--mode")
    resume = IC.flag(args, "--resume") && isfile(out)
    done = Dict{Tuple{String, String, String}, Dict{String, String}}()
    if resume
        for r in read_lines([out])
            done[(r["point"], r["label"], r["mode"])] = r
        end
    end
    started = time()
    open(out, resume ? "a" : "w") do io
        resume || println(io, join(COLUMNS, '\t'))
        for (i, p) in enumerate(pts), (label, expr) in columns, mode in p["modes"]
            isempty(modes) || mode in modes || continue
            haskey(done, (p["id"], label, mode)) && continue
            why = opts.continue_ladders ? nothing : ladder_stop(p, label, mode, done, opts.ladder_seconds)
            l = if why !== nothing
                r = point_fields!(Dict{String, Any}("label" => label, "expr" => expr, "mode" => mode, "status" => why,
                                                    "commit" => IC.COMMIT, "julia" => string(VERSION),
                                                    "load" => IC.load1(), "entry" => ENTRY), p)
                line_text(r)
            else
                ladder = p["group"] == "ladder"
                o = merge(opts, (calls = ladder ? max(opts.calls, opts.ladder_calls) : opts.calls,
                                 budget = ladder ? opts.ladder_budget : opts.budget))
                fresh_job(p, label, expr, mode, o, work)
            end
            println(io, l)
            flush(io)
            f = Dict{String, String}(c => String(x) for (c, x) in zip(COLUMNS, split(l, '\t')))
            done[(p["id"], label, mode)] = f
            @printf("%3d/%d %-16s %-8s %-8s %-24s rows %-6s warm %-10s ret %s/%s MiB, peak %s MiB, wall %s s\n", i,
                    length(pts), p["id"], label, mode, f["status"], f["rows"], f["warm_s"],
                    isempty(f["ret_c_b"]) ? "-" : mib(parse(Int, f["ret_c_b"])),
                    isempty(f["ret_g_b"]) ? "-" : mib(parse(Int, f["ret_g_b"])), f["peak_rss_mib"], f["wall_s"])
            flush(stdout)
        end
    end
    @printf("fresh: %d points, %d engines, %.1f s\n", length(pts), length(columns), time() - started)
end

function list_points(args)
    @printf("%-16s %-6s %-12s %-8s %5s %3s %3s %12s  %s\n", "point", "group", "ladder", "builder", "n", "v", "t",
            "targets", "modes")
    for p in select_points(args)
        @printf("%-16s %-6s %-12s %-8s %5d %3d %3d %12d  %s\n", p["id"], p["group"], p["ladder"], p["builder"], p["n"],
                p["v"], p["t"], IC.count_targets(point_arity(p), p["t"]), join(p["modes"], ","))
    end
end

# ---------------------------------------------------------------- summary

"The files after each `name` in `args`, up to the next option: `--base A.tsv B.tsv --base C.tsv`."
function files_after(args, name)
    files, on = String[], false
    for a in args
        startswith(a, "--") ? (on = a == name) : on && push!(files, a)
    end
    return files
end

"""
The lines of `paths`, one per (point, label, mode): a completed line over a
failed, stopped or skipped one (ipog_compare.jl's `rank`), the later among
equals; but a `nondeterministic` line over every other, so that a resumed
file's later `ok` line can't hide it (review p5-evidence 2).
"""
function by_key(paths)
    by = Dict{Tuple{String, String, String}, Dict{String, String}}()
    rank(r) = r["status"] == "nondeterministic" ? 4 : IC.rank(r)
    for r in read_lines(paths)
        key = (r["point"], r["label"], r["mode"])
        old = get(by, key, nothing)
        (old === nothing || rank(r) >= rank(old)) && (by[key] = r)
    end
    return by
end

ok(r) = r !== nothing && r["status"] == "ok"
"A line whose status is a finding against the code wherever the base stood: an error or `nondeterministic`."
broken(r) = r["status"] == "nondeterministic" || startswith(r["status"], "error:")
"The columns that must be equal wherever base and branch both completed: Phase 5 changes no row or count."
const SAME_COLUMNS = ("rows", "hash", "required", "excluded", "bound")
num(r, c) = (x = tryparse(Float64, get(r, c, "")); x === nothing ? NaN : x)
"The larger of two byte counts that may be missing (NaN), as a number."
larger(a, b) = isnan(a) ? b : isnan(b) ? a : max(a, b)

"Decision rule §1 gate 4's rule at one point: :within when `cand` is at most (1 + tol) × `ref` or within `floor` of it."
within(ref, cand, tol, floor) = cand <= (1 + tol) * ref || cand - ref <= floor ? :within : :outside

"""
The gates of decision rule §1 items 2–4 and the rows check, from the base's
and the branch's lines (`by_key`), and a recheck of the ladder points outside
(`rb`, `rr`; empty for none): a NamedTuple of verdicts and the evidence
`print_summary` prints.
"""
function judge_gates(base, branch, rb = Dict(), rr = Dict(); tol = 0.10, floor = 0.001, ladder_seconds = 30.0)
    keys_both = sort!([k for k in keys(base) if ok(base[k]) && ok(get(branch, k, nothing))])
    # Gate 2: retained bytes (summarysize, the larger of after classification and after generation).
    gate2 = NamedTuple[]
    for (point, limit, against) in (("gcc200", 20, "398 MiB"), ("t6-20x2-rule", 50, "1.4 GiB"))
        for k in sort!([k for k in union(keys(base), keys(branch)) if k[1] == point && k[3] == "index"])
            b, c = get(base, k, nothing), get(branch, k, nothing)
            ret(r) = r === nothing ? NaN : larger(num(r, "ret_c_b"), num(r, "ret_g_b"))
            live(r) = r === nothing ? NaN : larger(num(r, "live_c_b"), num(r, "live_g_b"))
            measured = c !== nothing && !isnan(ret(c))
            pass = measured && ok(c) && ret(c) < limit * 2^20
            push!(gate2, (; point, label = k[2], limit, against, base = ret(b), base_live = live(b),
                          base_status = b === nothing ? "not run" : b["status"], branch = ret(c), branch_live = live(c),
                          branch_status = c === nothing ? "not run" : c["status"],
                          verdict = c === nothing ? :missing : pass ? :pass : :fail))
        end
    end
    # Gate 3: bin1024-noop, IPOG(), one call in index space (mode `peak`), peak RSS under 2 GiB.
    gate3 = NamedTuple[]
    for k in sort!([k for k in union(keys(base), keys(branch)) if k[1] == "bin1024-noop" && k[3] == "peak"])
        b, c = get(base, k, nothing), get(branch, k, nothing)
        peak(r) = r === nothing ? NaN : num(r, "peak_rss_mib")
        pass = ok(c) && peak(c) < 2048
        push!(gate3, (; label = k[2], gated = k[2] == "IPOG()", base = peak(b),
                      base_status = b === nothing ? "not run" : b["status"], branch = peak(c),
                      branch_status = c === nothing ? "not run" : c["status"],
                      verdict = c === nothing ? :missing : pass ? :pass : :fail))
    end
    # Gate 4: the ladders, at every point the base completed within the study's limits (a warm call
    # under run.py's 30 s stage limit); a point past them is judged the same way and reported.
    gate4 = NamedTuple[]
    for k in sort!([k for k in keys(base) if ok(base[k]) && base[k]["group"] == "ladder"])
        b, c = base[k], get(branch, k, nothing)
        ladder = b["ladder"]
        gated = ladder in GATED_LADDERS && num(b, "warm_s") < ladder_seconds
        if !ok(c)
            push!(gate4, (; key = k, ladder, gated, base = num(b, "warm_s"), branch = NaN,
                          ratio = NaN, first = :not_completed, recheck = :none, verdict = :fail,
                          status = c === nothing ? "not run" : c["status"]))
            continue
        end
        first = within(num(b, "warm_s"), num(c, "warm_s"), tol, floor)
        recheck = :none
        if first == :outside && ok(get(rb, k, nothing)) && ok(get(rr, k, nothing))
            recheck = within(num(rb[k], "warm_s"), num(rr[k], "warm_s"), tol, floor)
        end
        verdict = first == :within || recheck == :within ? :pass : :fail
        push!(gate4, (; key = k, ladder, gated, base = num(b, "warm_s"), branch = num(c, "warm_s"),
                      ratio = num(c, "warm_s") / num(b, "warm_s"), first, recheck, verdict,
                      status = "ok"))
    end
    # Completion (review p5-evidence 2): every (point, engine, mode) the base completed and the branch
    # ran must complete on the branch, at every point and mode, gated or not; and a branch line that
    # is an error or `nondeterministic` fails wherever the base stood.
    failed = [(; key = k, base_status = haskey(base, k) ? base[k]["status"] : "not run", branch_status = c["status"])
              for (k, c) in sort!(collect(branch); by = first) if !ok(c) && (ok(get(base, k, nothing)) || broken(c))]
    # Rows: the same rows, hash and counts (required, excluded, bound) wherever both completed.
    rows = [(; key = k, base_rows = base[k]["rows"], branch_rows = branch[k]["rows"], base_hash = base[k]["hash"],
             branch_hash = branch[k]["hash"], differ = [c for c in SAME_COLUMNS if get(base[k], c, "") != get(branch[k], c, "")])
            for k in keys_both]
    filter!(x -> !isempty(x.differ), rows)
    verdict(xs) = isempty(xs) ? :missing : all(x -> x.verdict == :pass, xs) ? :pass : :fail
    return (; gate2, gate2_verdict = verdict(gate2), gate3,
            gate3_verdict = verdict([x for x in gate3 if x.gated]), gate4,
            gate4_verdict = verdict([x for x in gate4 if x.gated]),
            reported4_verdict = verdict([x for x in gate4 if !x.gated]), failed,
            completed_verdict = isempty(branch) ? :missing : isempty(failed) ? :pass : :fail, rows,
            compared = length(keys_both), rows_verdict = isempty(keys_both) ? :missing : isempty(rows) ? :pass : :fail,
            tol, floor)
end

word(v) = v == :pass ? "PASS" : v == :fail ? "FAIL" : "NOT MEASURED"
mibs(x) = isnan(x) ? "-" : @sprintf("%.1f", x / 2^20)
secs(x) = isnan(x) ? "-" : @sprintf("%.4g", x)

"Every line of one side, as a table: status, rows, times, retained bytes, memo, peak RSS."
function print_table(name, by)
    println("\n== $name: $(length(by)) lines")
    @printf("  %-16s %-8s %-8s %-22s %6s %16s %9s %9s %9s %9s %9s %9s %9s %9s %7s  %s\n", "point", "label", "mode",
            "status", "rows", "hash", "classify", "gen", "warm", "ret c", "ret g", "live c", "live g", "feas g",
            "peak", "memo after generation")
    order = Dict(p["id"] => i for (i, p) in enumerate(all_points()))
    for k in sort!(collect(keys(by)); by = k -> (get(order, k[1], 0), k[2], k[3]))
        r = by[k]
        @printf("  %-16s %-8s %-8s %-22s %6s %16s %9s %9s %9s %9s %9s %9s %9s %9s %7s  %s\n", k[1], first(k[2], 8), k[3],
                first(r["status"], 22), r["rows"], r["hash"], secs(num(r, "classify_s")), secs(num(r, "gen_s")),
                secs(num(r, "warm_s")), mibs(num(r, "ret_c_b")), mibs(num(r, "ret_g_b")), mibs(num(r, "live_c_b")),
                mibs(num(r, "live_g_b")), mibs(num(r, "feas_g_b")), r["peak_rss_mib"], r["memo_g"])
    end
    println("  (seconds; MiB: ret = request and classification by summarysize, live = gc_live_bytes, feas = the request's feasibility; peak RSS of the process)")
end

"Whether the two measures of retained bytes agree: within 10% or 1 MiB of each other."
agree(ss, live) = isnan(ss) || isnan(live) ? "-" : abs(live - ss) <= max(0.10ss, 2^20) ? "agree" :
                  @sprintf("differ (live/ss %.2f)", live / ss)

function print_summary(args)
    base_files, branch_files = files_after(args, "--base"), files_after(args, "--branch")
    isempty(base_files) && error("summary needs --base FILE")
    base, branch = by_key(base_files), by_key(branch_files)
    rb, rr = by_key(files_after(args, "--recheck-base")), by_key(files_after(args, "--recheck-branch"))
    tol = parse(Float64, IC.option(args, "--tolerance", "0.10"))
    floor = parse(Float64, IC.option(args, "--floor", "0.001"))
    ladder_seconds = parse(Float64, IC.option(args, "--ladder-seconds", "30"))
    println("phase5_gate summary: base ", join(base_files, " "), "; branch ", join(branch_files, " "))
    for (name, by) in (("base", base), ("branch", branch), ("recheck base", rb), ("recheck branch", rr))
        isempty(by) && continue
        xs = collect(values(by))
        loads = [num(r, "load") for r in xs if !isnan(num(r, "load"))]
        @printf("  %-15s %4d lines (%d ok), commit %s, Julia %s, load %s\n", name, length(xs), count(ok, xs),
                join(unique(r["commit"] for r in xs), "/"), join(unique(r["julia"] for r in xs), "/"),
                isempty(loads) ? "-" : @sprintf("%.1f–%.1f", minimum(loads), maximum(loads)))
    end
    print_table("base", base)
    isempty(branch) || print_table("branch", branch)
    stops = [(n, k, r) for (n, by) in (("base", base), ("branch", branch)) for (k, r) in by
             if any(s -> startswith(r["status"], s), ("rss_limit", "timeout", "crash"))]
    if !isempty(stops)
        println("\n== stopped by the watchdog or crashed")
        for (n, k, r) in sort!(stops)
            @printf("  %-7s %-16s %-8s %-8s %-28s peak %s MiB after %s s; retained after classification %s / %s MiB (summarysize / gc_live)\n",
                    n, k[1], k[2], k[3], r["status"], r["peak_rss_mib"], r["wall_s"], mibs(num(r, "ret_c_b")),
                    mibs(num(r, "live_c_b")))
        end
    end
    if isempty(branch)
        println("\nno --branch files: the gates need the branch's lines. Thresholds: gate 2, retained under 20 MiB at ",
                "gcc200 and under 50 MiB at t6-20x2-rule; gate 3, bin1024-noop with IPOG() under 2,048 MiB peak; ",
                "gate 4, every ladder point at most $(round(Int, 100tol))% or $(1000floor) ms above the base")
        return nothing
    end
    v = judge_gates(base, branch, rb, rr; tol, floor, ladder_seconds)
    println("\n== gate 2 (decision rule §1 item 2): retained bytes, summarysize of the request and its classification, the larger of after classification and after generation")
    for x in v.gate2
        @printf("  %-13s %-8s base %9s MiB (%s), branch %9s MiB (%s): %s, under %d MiB (plan: against %s); gc_live: base %s, branch %s MiB, %s\n",
                x.point, x.label, mibs(x.base), x.base_status, mibs(x.branch), x.branch_status, word(x.verdict),
                x.limit, x.against, mibs(x.base_live), mibs(x.branch_live), agree(x.branch, x.branch_live))
    end
    println("  gate 2: ", word(v.gate2_verdict))
    println("\n== gate 3 (item 3): bin1024-noop in index space, one whole generate (mode peak), IPOG(), the process's peak RSS under 2 GiB")
    for x in v.gate3
        @printf("  %-8s base %s MiB (%s), branch %s MiB (%s): %s%s\n", x.label, isnan(x.base) ? "-" : string(round(Int, x.base)),
                x.base_status, isnan(x.branch) ? "-" : string(round(Int, x.branch)), x.branch_status, word(x.verdict),
                x.gated ? "" : " (reported)")
    end
    println("  gate 3: ", word(v.gate3_verdict))
    @printf("\n== gate 4 (item 4): the ladders no slower, the branch's warm minimum at most %.0f%% above the base's or within %.1f ms, at every point the base completed\n",
            100tol, 1000floor)
    for gated in (true, false)
        xs = [x for x in v.gate4 if x.gated == gated]
        isempty(xs) && continue
        outside = [x for x in xs if x.first != :within]
        @printf("  %s: %d points (point, engine, mode); outside the rule in the first run: %d; failing: %d\n",
                gated ? "gated (equality, whole, noop_whole)" :
                        "reported (chain, noop_scoped, and points past the study's limits)", length(xs),
                length(outside), count(x -> x.verdict == :fail, xs))
        for x in outside
            @printf("    %-16s %-8s %-8s base %s s, branch %s s, ×%.2f; %s%s\n", x.key[1], x.key[2], x.key[3],
                    secs(x.base), secs(x.branch),
                    x.ratio, x.first == :not_completed ? "not completed: $(x.status)" : "outside",
                    x.recheck == :none ? (x.first == :outside ? ", not rechecked" : "") : ", recheck: $(x.recheck)")
        end
    end
    println("  gate 4: ", word(v.gate4_verdict), " (provisional unless measured quiet); reported ladders: ",
            word(v.reported4_verdict))
    println("\n== completed: every (point, engine, mode) the base completed and the branch ran completes on the branch; ",
            "no branch line is an error or nondeterministic")
    for x in v.failed
        @printf("  %-16s %-8s %-8s base %s, branch %s\n", x.key[1], x.key[2], x.key[3], x.base_status, x.branch_status)
    end
    @printf("  %d failing: %s\n", length(v.failed), word(v.completed_verdict))
    println("\n== rows: the same rows, hash, required, excluded and bound at every (point, engine, mode) both completed")
    for x in v.rows
        @printf("  %-16s %-8s %-8s rows %s → %s, hash %s → %s; differ: %s\n", x.key[1], x.key[2], x.key[3], x.base_rows,
                x.branch_rows, x.base_hash, x.branch_hash, join(x.differ, ", "))
    end
    @printf("  %d compared, %d differ: %s\n", v.compared, length(v.rows), word(v.rows_verdict))
    return v
end

"The ids of the ladder points outside gate 4's rule, for a recheck."
function outside_points(args)
    base, branch = by_key(files_after(args, "--base")), by_key(files_after(args, "--branch"))
    tol = parse(Float64, IC.option(args, "--tolerance", "0.10"))
    floor = parse(Float64, IC.option(args, "--floor", "0.001"))
    ladder_seconds = parse(Float64, IC.option(args, "--ladder-seconds", "30"))
    v = judge_gates(base, branch; tol, floor, ladder_seconds)
    foreach(println, unique(x.key[1] for x in v.gate4 if x.first != :within))     # gated or reported
end

# ---------------------------------------------------------------- main

const USAGE = "usage: phase5_gate.jl list|fresh [--group G]... [--point ID]... [--filter S]... [--engine [LABEL=]EXPR]... " *
              "[--mode M]... --out OUT.tsv | summary --base FILE... [--branch FILE...] | outside --base FILE... --branch FILE..."
if abspath(PROGRAM_FILE) == @__FILE__
    if isempty(ARGS)
        error(USAGE)
    elseif ARGS[1] == "child"
        child(ARGS)
    else
        # `outside` prints only its ids, for a driver to read.
        ARGS[1] == "outside" || println("phase5_gate ", ARGS[1], " at ", IC.COMMIT, " (", pkgdir(U), "), Julia ", VERSION,
                                        ", load ", round.(Sys.loadavg(); digits = 1))
        ARGS[1] == "fresh" ? fresh_sweep(ARGS) :
        ARGS[1] == "summary" ? print_summary(ARGS) :
        ARGS[1] == "outside" ? outside_points(ARGS) :
        ARGS[1] == "list" ? list_points(ARGS) : error(USAGE)
    end
end
