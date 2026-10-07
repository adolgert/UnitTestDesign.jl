# Tests of benchmark/phase5_gate.jl (and of what it uses of ipog_compare.jl):
# the points are built as the probes and the study build them, the summary
# judges hand-made lines as decision rule §1 items 2–4 say, the reflective
# memo count and the retained bytes read any storage, and the watchdog stops
# a child. Outside the package's test suite, as p4-bench's tests of
# ipog_compare.jl were. About a minute, most of it three fresh processes:
#
#     julia --project=. --startup-file=no benchmark/phase5_gate_test.jl

using Test
include(joinpath(@__DIR__, "phase5_gate.jl"))

"A line file in `dir` with the header and one line per Dict of fields."
function write_lines(path, lines)
    open(path, "w") do io
        println(io, join(COLUMNS, '\t'))
        for l in lines
            println(io, join((string(get(l, c, "")) for c in COLUMNS), '\t'))
        end
    end
    return path
end

"A completed line: the point's fields from `all_points`, then `kw`."
function made(point, label, mode; kw...)
    p = only(q for q in all_points() if q["id"] == point)
    r = point_fields!(Dict{String, Any}("label" => label, "expr" => label, "mode" => mode, "status" => "ok",
                                        "rows" => 10, "hash" => "00000000000000aa", "commit" => "base",
                                        "julia" => "1.13.1", "load" => "1.0"), p)
    for (k, v) in kw
        r[string(k)] = v
    end
    return r
end

# Two structs of the shape of a feasibility search's caches, for the reflective count.
struct Inner
    verdicts::Dict{Int, Bool}
    key::Vector{Int}
end
struct Outer
    memo::Dict{Vector{Int}, Int}
    caches::Vector{Dict{Int, Int}}
    inner::Vector{Union{Nothing, Inner}}
    n::Int
end

"worker.jl's `model`, taken from the file itself and evaluated beside the harness's spec files."
module Worker
using UnitTestDesign, JSON, Random
const U = UnitTestDesign
const SCALING = joinpath(@__DIR__, "scaling")
include(joinpath(SCALING, "spaces.jl"))
include(joinpath(SCALING, "model_specs.jl"))
let code = Meta.parseall(read(joinpath(SCALING, "worker.jl"), String))
    defs = [ex for ex in code.args if ex isa Expr && ex.head == :function && ex.args[1] == :(model(s))]
    length(defs) == 1 || error("worker.jl's `model` not found")
    Core.eval(@__MODULE__, defs[1])
end
end

@testset "phase5_gate.jl" begin
    @testset "points" begin
        pts = all_points()
        ids = [p["id"] for p in pts]
        @test allunique(ids)
        @test ["gcc200", "gcc400", "t6-20x2-rule", "t5-20x3-rule", "bin1024-noop"] ⊆ ids
        for f in ("equality", "whole", "noop_whole", "chain"), n in (8, 16, 32, 64)
            @test "$f-n$n" in ids
        end
        @test all("noop_scoped-n$n" in ids for n in (8, 32, 64, 128, 256, 512))   # probe 06's shapes
        @test [p["id"] for p in select_points(["fresh", "--group", "gate"])] == ids[1:5]
        @test [p["id"] for p in select_points(["fresh", "--filter", "whole-n1"])] == ["whole-n16", "whole-n128",
                                                                                       "noop_whole-n16", "noop_whole-n128"]
        @test_throws ErrorException select_points(["fresh", "--point", "nonesuch"])
    end

    @testset "probe 21's model" begin
        space, kw = build_point(only(p for p in all_points() if p["id"] == "gcc200"))
        @test kw == (; strength = 2)
        @test length(space.names) == 200 && length(space.constraints) == 24
        @test count(d -> d == [:off, :on], space.values) == 190 && count(d -> d == [:low, :mid, :high], space.values) == 10
        # Probe 21 at 2798ecf: 83,581 targets required and 44 excluded.
        d = generate(IPOG(), Request(space; kw...))
        @test d.required == 83_581 && length(d.excluded) == 44
        @test IC.count_targets(point_arity(Dict("builder" => "gcc", "n" => 200)), 2) == 83_625
        space400, _ = build_point(only(p for p in all_points() if p["id"] == "gcc400"))
        @test length(space400.constraints) == 46 && IC.count_targets(point_arity(Dict("builder" => "gcc", "n" => 400)), 2) == 335_350
    end

    @testset "probe 24's rule" begin
        space, kw = build_point(only(p for p in all_points() if p["id"] == "t6-20x2-rule"))
        @test kw == (; strength = 6) && length(space.constraints) == 1 && all(==(1:2), space.values)
        # The rule excludes the targets holding p1 = 1 and p2 = 1: C(18, t − 2) v^(t − 2) of them, so
        # 2,480,640 − 48,960 = 2,431,680 required at t = 6 (probe 24's figure); checked here at t = 3.
        d = generate(IPOG(), Request(space; strength = 3))
        @test length(d.excluded) == binomial(18, 1) * 2 && d.required == binomial(20, 3) * 8 - 36
        @test IC.count_targets(fill(2, 20), 6) - binomial(18, 4) * 2^4 == 2_431_680
        @test IC.count_targets(fill(3, 20), 5) - binomial(18, 3) * 3^3 == 3_745_440
    end

    @testset "the ladders are worker.jl's" begin
        for family in ("equality", "chain", "whole", "noop_whole", "noop_scoped"), n in (8, 16)
            spec = Dict{String, Any}("n" => n, "v" => 2, "family" => family, "usage" => "reuse", "strength" => 2)
            theirs = Base.invokelatest(Worker.model, spec)
            space, kw = family_space(family, n, 2, 2)
            @test space.names == theirs.space.names && space.values == theirs.space.values
            @test space.tabulation_limit == theirs.space.tabulation_limit
            @test length(space.tables) == length(theirs.space.tables)
            for (a, b) in zip(space.tables, theirs.space.tables)
                @test a.scope == b.scope && a.forbidden == b.forbidden && (a.lazy === nothing) == (b.lazy === nothing)
            end
            @test kw == (; theirs.kw.strength, theirs.kw.stronger, theirs.kw.must_include, theirs.kw.feasibility_limit,
                         theirs.kw.explanation_limit)
            mine, other = generate(IPOG(), Request(space; kw...)), generate(IPOG(), Request(theirs.space; theirs.kw...))
            @test mine.matrix == other.matrix && [e.target for e in mine.excluded] == [e.target for e in other.excluded]
        end
    end

    @testset "memo counts and retained bytes, whatever the storage" begin
        x = Outer(Dict([1] => 1, [2] => 2), [Dict(1 => 1), Dict(1 => 1, 2 => 2)],
                  [nothing, Inner(Dict(1 => true, 2 => false, 3 => true), [1])], 7)
        @test dict_counts!(Dict{String, Int}(), x, "", 3) == Dict("memo" => 2, "caches[]" => 3, "inner[].verdicts" => 3)
        space, kw = family_space("noop_scoped", 16, 2, 2)
        request = Request(space; kw...)
        classified = classify(request)
        text = memo_entries(request)
        @test !isempty(text) && all(part -> occursin(r"^[\w\[\].()]+=\d+$", part), split(text))
        # The space is left out, the request and classification together count shared parts once.
        @test bytes_of(request) < Base.summarysize(request)
        r = retained!(Dict{String, Any}(), "c", request, classified)
        @test r["ret_c_b"] <= r["req_c_b"] + r["cls_c_b"] && r["ret_c_b"] >= max(r["req_c_b"], r["cls_c_b"])
        @test r["feas_c_b"] < r["req_c_b"]
        @test agree(100 * 2^20, 105 * 2^20) == "agree" && startswith(agree(100 * 2^20, 120 * 2^20), "differ")
    end

    @testset "summary verdicts on hand-made lines" begin
        dir = mktempdir()
        MiB = 2^20
        base = [made("gcc200", "IPOG()", "index"; ret_c_b = 418 * MiB, ret_g_b = 463 * MiB, live_c_b = 425 * MiB),
                made("gcc200", "Auto()", "index"; ret_c_b = 418 * MiB, ret_g_b = 470 * MiB),
                made("t6-20x2-rule", "IPOG()", "index"; ret_c_b = 1500 * MiB),
                made("bin1024-noop", "IPOG()", "peak"; status = "rss_limit(classify)", peak_rss_mib = 3100),
                made("bin1024-noop", "Auto()", "peak"; status = "rss_limit(classify)", peak_rss_mib = 3100),
                made("equality-n8", "IPOG()", "index"; warm_s = 0.100),
                made("equality-n16", "IPOG()", "index"; warm_s = 0.100),
                made("equality-n32", "IPOG()", "index"; warm_s = 0.0005),
                made("equality-n64", "IPOG()", "index"; warm_s = 0.002),
                made("whole-n8", "IPOG()", "covering"; warm_s = 0.050),
                made("whole-n16", "IPOG()", "covering"; warm_s = 0.050),
                made("whole-n32", "IPOG()", "covering"; status = "resource_limit"),
                made("chain-n8", "IPOG()", "index"; warm_s = 0.010),
                made("noop_whole-n64", "IPOG()", "index"; warm_s = 40.0)]               # past run.py's 30 s
        branch = [made("gcc200", "IPOG()", "index"; ret_c_b = 2 * MiB, ret_g_b = 15 * MiB, live_c_b = 2 * MiB,
                       live_g_b = 16 * MiB),
                  made("gcc200", "Auto()", "index"; ret_c_b = 2 * MiB, ret_g_b = 25 * MiB),
                  made("t6-20x2-rule", "IPOG()", "index"; ret_c_b = 40 * MiB, ret_g_b = 45 * MiB),
                  made("bin1024-noop", "IPOG()", "peak"; peak_rss_mib = 1900),
                  made("bin1024-noop", "Auto()", "peak"; peak_rss_mib = 2100),
                  made("equality-n8", "IPOG()", "index"; warm_s = 0.109),          # within 10%
                  made("equality-n16", "IPOG()", "index"; warm_s = 0.111),         # outside, rechecked within
                  made("equality-n32", "IPOG()", "index"; warm_s = 0.0014),        # within the 1 ms floor
                  made("equality-n64", "IPOG()", "index"; warm_s = 0.0035),        # outside twice
                  made("whole-n8", "IPOG()", "covering"; warm_s = 0.04, hash = "00000000000000bb"),
                  made("whole-n16", "IPOG()", "covering"; status = "timeout(covering)"),
                  made("chain-n8", "IPOG()", "index"; warm_s = 0.020),           # reported only
                  made("noop_whole-n64", "IPOG()", "index"; warm_s = 50.0)]      # reported only
        rb = [made("equality-n16", "IPOG()", "index"; warm_s = 0.100), made("equality-n64", "IPOG()", "index"; warm_s = 0.002)]
        rr = [made("equality-n16", "IPOG()", "index"; warm_s = 0.105), made("equality-n64", "IPOG()", "index"; warm_s = 0.004)]
        files = [write_lines(joinpath(dir, "$name.tsv"), ls) for (name, ls) in (("base", base), ("branch", branch),
                                                                                 ("rb", rb), ("rr", rr))]
        v = judge_gates(by_key([files[1]]), by_key([files[2]]), by_key([files[3]]), by_key([files[4]]))
        g2 = Dict((x.point, x.label) => x for x in v.gate2)
        @test g2[("gcc200", "IPOG()")].verdict == :pass && g2[("gcc200", "IPOG()")].branch == 15 * MiB
        @test g2[("gcc200", "Auto()")].verdict == :fail                     # 25 MiB after generation
        @test g2[("t6-20x2-rule", "IPOG()")].verdict == :pass && g2[("t6-20x2-rule", "IPOG()")].base == 1500 * MiB
        @test v.gate2_verdict == :fail
        g3 = Dict(x.label => x for x in v.gate3)
        @test g3["IPOG()"].verdict == :pass && g3["IPOG()"].gated && !g3["Auto()"].gated && g3["Auto()"].verdict == :fail
        @test v.gate3_verdict == :pass                                      # judged on IPOG() alone
        g4 = Dict(x.key[1] => x for x in v.gate4)
        @test g4["equality-n8"].verdict == :pass && g4["equality-n8"].first == :within
        @test g4["equality-n16"].first == :outside && g4["equality-n16"].recheck == :within && g4["equality-n16"].verdict == :pass
        @test g4["equality-n32"].first == :within                           # 0.9 ms more, under the floor
        @test g4["equality-n64"].first == :outside && g4["equality-n64"].recheck == :outside && g4["equality-n64"].verdict == :fail
        @test g4["whole-n8"].verdict == :pass && g4["whole-n16"].first == :not_completed && g4["whole-n16"].verdict == :fail
        @test !haskey(g4, "whole-n32")                                      # the base didn't complete it
        @test !g4["chain-n8"].gated && g4["chain-n8"].verdict == :fail && v.reported4_verdict == :fail
        @test !g4["noop_whole-n64"].gated && g4["noop_whole-n64"].verdict == :fail
        @test v.gate4_verdict == :fail
        @test v.rows_verdict == :fail && [x.key for x in v.rows] == [("whole-n8", "IPOG()", "covering")]
        @test files_after(["summary", "--base", "a", "b", "--branch", "c", "--base", "d"], "--base") == ["a", "b", "d"]
        # Without the recheck, the point outside once fails.
        v1 = judge_gates(by_key([files[1]]), by_key([files[2]]))
        @test only(x for x in v1.gate4 if x.key[1] == "equality-n16").verdict == :fail
        # A branch that passes everything.
        good = [made("gcc200", "IPOG()", "index"; ret_c_b = MiB, ret_g_b = 2MiB), made("t6-20x2-rule", "IPOG()", "index"; ret_g_b = MiB),
                made("bin1024-noop", "IPOG()", "peak"; peak_rss_mib = 700), made("equality-n8", "IPOG()", "index"; warm_s = 0.1),
                made("whole-n8", "IPOG()", "covering"; warm_s = 0.05), made("whole-n16", "IPOG()", "covering"; warm_s = 0.05),
                made("equality-n16", "IPOG()", "index"; warm_s = 0.1), made("equality-n32", "IPOG()", "index"; warm_s = 0.0005),
                made("equality-n64", "IPOG()", "index"; warm_s = 0.002), made("gcc200", "Auto()", "index"; ret_g_b = MiB),
                made("bin1024-noop", "Auto()", "peak"; peak_rss_mib = 700), made("chain-n8", "IPOG()", "index"; warm_s = 0.01)]
        v2 = judge_gates(by_key([files[1]]), by_key([write_lines(joinpath(dir, "good.tsv"), good)]))
        @test v2.gate2_verdict == v2.gate3_verdict == v2.gate4_verdict == v2.rows_verdict == :pass
        # The printed summary and `outside` run on the files.
        text = mktemp() do path, io
            redirect_stdout(io) do
                print_summary(["summary", "--base", files[1], "--branch", files[2], "--recheck-base", files[3],
                               "--recheck-branch", files[4]])
            end
            close(io)
            read(path, String)
        end
        @test occursin("gate 2: FAIL", text) && occursin("gate 3: PASS", text) && occursin("gate 4: FAIL", text)
        @test occursin("1 differ: FAIL", text)
        ids = mktemp() do path, io
            redirect_stdout(() -> outside_points(["outside", "--base", files[1], "--branch", files[2]]), io)
            close(io)
            readlines(path)
        end
        @test sort(ids) == ["chain-n8", "equality-n16", "equality-n64", "noop_whole-n64", "whole-n16"]
    end

    @testset "a ladder stops where run.py stops one" begin
        p(id) = only(q for q in all_points() if q["id"] == id)
        done = Dict(("equality-n16", "IPOG()", "index") => Dict("status" => "ok", "warm_s" => "1.5"),
                    ("equality-n32", "IPOG()", "index") => Dict("status" => "ok", "warm_s" => "31.0"),
                    ("whole-n32", "IPOG()", "index") => Dict("status" => "resource_limit", "warm_s" => ""))
        @test ladder_stop(p("equality-n32"), "IPOG()", "index", done, 30) === nothing
        @test ladder_stop(p("equality-n64"), "IPOG()", "index", done, 30) == "skipped:ladder after equality-n32"
        @test ladder_stop(p("equality-n64"), "IPOG()", "covering", done, 30) === nothing
        @test ladder_stop(p("whole-n64"), "IPOG()", "index", done, 30) == "skipped:ladder after whole-n32"
        @test ladder_stop(p("gcc200"), "IPOG()", "index", done, 30) === nothing
    end

    @testset "fresh processes and the watchdog" begin
        dir = mktempdir()
        script = joinpath(@__DIR__, "phase5_gate.jl")
        julia = `$(Base.julia_cmd()) --project=$(Base.active_project()) --startup-file=no`
        out = joinpath(dir, "fresh.tsv")
        # One small point and its two modes; then the same with a watchdog that stops it.
        run(pipeline(`$julia $script fresh --point equality-n8 --engine 'IPOG()' --calls 1 --ladder-calls 1 --out $out`;
                     stdout = devnull))
        lines = read_lines([out])
        @test [(r["mode"], r["status"], r["rows"]) for r in lines] == [("index", "ok", "2"), ("covering", "ok", "2")]
        r = lines[1]
        @test r["required"] == "56" && r["excluded"] == "56" && parse(Int, r["ret_c_b"]) > 0 &&
              parse(Int, r["live_c_b"]) > 0 && r["hash"] == lines[2]["hash"]
        # The memo column's `name=count` pairs, whatever the tree's fields: at
        # 31bef0f `memo=… witness_cache[]=…`, since Phase 5 `witness_cache[]=…`.
        @test occursin(r"^\S+=\d+( \S+=\d+)*$", r["memo_c"]) && occursin("witness_cache[]=", r["memo_c"])
        @test parse(Int, r["calls"]) == 1 && parse(Float64, r["peak_rss_mib"]) > 100
        stopped = joinpath(dir, "stopped.tsv")
        run(pipeline(`$julia $script fresh --point equality-n8 --engine 'IPOG()' --mode index --rss-mib 100 --out $stopped`;
                     stdout = devnull))
        run(pipeline(`$julia $script fresh --point gcc200 --engine 'IPOG()' --mode peak --seconds 2 --resume --out $stopped`;
                     stdout = devnull))
        s = read_lines([stopped])
        @test startswith(s[1]["status"], "rss_limit(") && parse(Float64, s[1]["peak_rss_mib"]) > 100
        @test startswith(s[2]["status"], "timeout(") && parse(Float64, s[2]["wall_s"]) < 10
        @test isempty(readchomp(ignorestatus(`pgrep -f $(splitext(stopped)[1] * "_jobs")`)))   # no child left behind
        # ipog_compare.jl, whose watchdog this shares, still gives Phase 4's quiet rows (p4_quiet_scripts/m2).
        ic = joinpath(dir, "ic.tsv")
        run(pipeline(`$julia $(joinpath(@__DIR__, "ipog_compare.jl")) fresh --family large --filter 12x3 --engine 'IPOG()' --out $ic`;
                     stdout = devnull))
        l = only(read_lines([ic]))
        @test (l["status"], l["rows"], l["hash"]) == ("ok", "269", "90431c8b0ca4816f")
    end
end
