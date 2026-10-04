# What each size of space costs, for the table of docs/src/man/engines.md
# ("What a call costs, and where it stops"; solver plan §6.2, decision D4).
# Each point runs in a fresh process under /usr/bin/time -l (macOS; `-v` on
# Linux prints the same peak as "Maximum resident set size" in KiB), which
# reports the process's peak resident memory. `seconds` is a second, warm
# `covering` call on the same space, so compilation is left out; `first` is
# the first call, which also compiles for the space's row type (plan §2.6).
# Run from the repository root:
#
#     julia --project=. --startup-file=no benchmark/engine_costs.jl [POINT...]
#
# POINT names one of the points below; with none, all run (about ten
# minutes on an Apple M2). Times are provisional on a busy machine; rows and
# peak memory are not.

const POINTS = [
    # name, k, v, strength, engine, rules
    ("10x3-t2", 10, 3, 2, "IPOG()", false),
    ("10x3-t2-auto", 10, 3, 2, "Auto()", false),
    ("10x3-t2-compact", 10, 3, 2, "Auto(goal = :compact)", false),
    ("50x4-t2", 50, 4, 2, "IPOG()", false),
    ("50x4-t2-auto", 50, 4, 2, "Auto()", false),
    ("50x4-t2-compact", 50, 4, 2, "Auto(goal = :compact)", false),
    ("250x2-t2", 250, 2, 2, "IPOG()", false),
    ("250x2-t2-rule", 250, 2, 2, "IPOG()", true),
    ("250x4-t2", 250, 4, 2, "IPOG()", false),
    ("250x4-t2-auto", 250, 4, 2, "Auto()", false),
    ("8x64-t2", 8, 64, 2, "IPOG()", false),
    ("8x64-t2-auto", 8, 64, 2, "Auto()", false),
    ("30x4-t3", 30, 4, 3, "IPOG()", false),
    ("30x4-t3-rule", 30, 4, 3, "IPOG()", true),
    ("30x4-t3-compact", 30, 4, 3, "Auto(goal = :compact)", false),
    ("15x4-t4", 15, 4, 4, "IPOG()", false),
    ("15x4-t4-compact", 15, 4, 4, "Auto(goal = :compact)", false),
    ("20x2-t6", 20, 2, 6, "IPOG()", false),
    ("20x2-t6-rule", 20, 2, 6, "IPOG()", true),
]

const CHILD = raw"""
using UnitTestDesign
k, v, t, engine, rule = parse(Int, ARGS[1]), parse(Int, ARGS[2]), parse(Int, ARGS[3]), eval(Meta.parse(ARGS[4])), ARGS[5] == "true"
names = [Symbol(:p, i) for i in 1:k]
# One scoped rule over two parameters that forbids one pair: the bookkeeping of
# any rule (plan §2.6) without changing much of the space.
rules = rule ? Constraint[forbid((a, b) -> a == 1 && b == 2, :p1, :p2)] : Constraint[]
space = TestSpace(names, [1:v for _ in 1:k], rules, 10^5)
first = @timed covering(space; strength = t, engine)            # compiles, the space's row type too
stats = @timed covering(space; strength = t, engine)
println(length(stats.value), " ", round(stats.time; digits = 3), " ", round(first.time; digits = 3), " ",
        stats.value.record.lower_bound, " ", get(stats.value.record, :chose, "-"))
"""

function main(names)
    julia = `$(Base.julia_cmd()) --project=$(Base.active_project()) --startup-file=no`
    println("engine_costs at Julia ", VERSION, ", ", Sys.cpu_info()[1].model, ", load ", round.(Sys.loadavg(); digits = 1))
    println(rpad("point", 18), rpad("engine", 24), lpad("rows", 7), lpad("bound", 7), lpad("seconds", 9),
            lpad("first", 9), lpad("peak MiB", 10), "  chose")
    for (name, k, v, t, engine, rule) in POINTS
        isempty(names) || name in names || continue
        out = IOBuffer()
        err = IOBuffer()
        cmd = `/usr/bin/time -l $julia -e $CHILD $k $v $t $engine $rule`
        ok = success(pipeline(cmd; stdout = out, stderr = err))
        text = String(take!(err))
        m = match(r"(\d+)\s+maximum resident set size", text)
        peak = m === nothing ? NaN : parse(Int, m[1]) / 2^20
        line = ok ? split(strip(String(take!(out)))) : ["failed", "", "", "", ""]
        rows, seconds, firstcall, bound = line[1], line[2], line[3], line[4]
        chose = length(line) >= 5 ? join(line[5:end], " ") : ""
        println(rpad(name, 18), rpad(engine, 24), lpad(rows, 7), lpad(bound, 7), lpad(seconds, 9),
                lpad(firstcall, 9), lpad(round(Int, peak), 10), "  ", chose)
        flush(stdout)
    end
end

main(ARGS)
