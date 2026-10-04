# Construction() against IPOG on uniform shapes, for plan §5.4's gate "with
# keep-the-smallest, never more rows than IPOG on any benchmark point".
# Keep-the-smallest is Phase 3's (`Auto`); this lists every shape where the
# catalog's array has more rows than IPOG's design, which is where it
# matters, and the seeded path against IPOG under a few rules. Run from the
# repository root:
#
#     julia --project=. --startup-file=no benchmark/construction_vs_ipog.jl [SETS...] [--expensive]
#         [--expensive-cost=C] [--only-expensive]
#
# SETS (default: all four):
#
#   compare      the 202 shapes of compare_ipog.jl in the plan's constructions
#                directory: strength 2 with 2-12 values and 3-60 parameters,
#                and strength 3 with at most 1.5 million targets
#   uniform-pp   benchmark/scaling/families.py's family of that name
#   uniform-npp  the same
#   seeded       probe 11's uniform cases and a few more: rules, must-include
#                rows and a stronger group, where the catalog seeds IPOG
#
# A family's expensive points (families.py: over 2·10^6 targets, or targets
# times the bound over 4·10^8) get only the catalog's size, from sizes alone,
# unless --expensive is given, or --expensive-cost=C and their targets times
# the bound is at most C (families.py's estimate is 4·10^8 for ten seconds of
# IPOG). --only-expensive skips the other points, for a second run. Every
# other point runs both engines through
# `covering`, which certifies each design (contract §1.21), once to compile
# and once timed. The rows are exact; the times are one warm call each, and
# provisional on a busy machine. It prints one line per point and a summary
# per set; "larger" marks a point where the catalog has more rows than IPOG.
include(joinpath(@__DIR__, "best_known", "BestKnown.jl"))
using .BestKnown
using UnitTestDesign

const ROOT = normpath(joinpath(@__DIR__, ".."))
const C = UnitTestDesign.Construction()
const SETS = filter(a -> !startswith(a, "--"), ARGS)
const EXPENSIVE = "--expensive" in ARGS
const ONLY_EXPENSIVE = "--only-expensive" in ARGS

"The C of `--expensive-cost=C`, or 0."
function cost_cap()
    for a in ARGS
        startswith(a, "--expensive-cost=") && return parse(Float64, a[(length("--expensive-cost=") + 1):end])
    end
    return 0.0
end
const COST_CAP = cost_cap()
selected(name) = isempty(SETS) || name in SETS

compare_shapes() =
    [[(2, v, k) for v in 2:12 for k in (3, 4, 5, 6, 8, 10, 12, 15, 20, 30, 40, 60)];
     [(3, v, k) for v in (2, 3, 4, 5, 6, 7, 8, 10) for k in (4, 5, 6, 8, 10, 12, 16, 20, 30)
      if v^3 * binomial(k, 3) <= 1_500_000]]

"(t, v, k, expensive, cost) for each point of a uniform family, from families.py itself."
function family_shapes(name)
    code = "import sys; sys.path.insert(0, 'benchmark/scaling'); import families\n" *
           "for j in families.FAMILIES['$name'](['ipog'], 1): " *
           "print(j['strength'], j['v'], j['n'], int(bool(j.get('expensive'))), j['cost'])"
    lines = split(strip(read(Cmd(`python3 -c $code`; dir = ROOT), String)), '\n')
    return [(parse(Int, a), parse(Int, b), parse(Int, c), e == "1", parse(Float64, d)) for (a, b, c, e, d) in split.(lines)]
end

"Rows and warm seconds of `covering` with `engine`, after one call to compile and warm it."
function timed_rows(space, t, engine)
    covering(space; strength = t, engine)
    stats = @timed covering(space; strength = t, engine)
    return length(stats.value), stats.time
end

fmt(x) = x === nothing ? "-" : x isa AbstractFloat ? string(round(x; digits = 3)) : string(x)
percent(x) = string(x >= 0 ? "+" : "", round(Int, 100 * x), "%")
median(x) = (s = sort(x); isodd(length(s)) ? s[(end + 1) ÷ 2] : (s[end ÷ 2] + s[end ÷ 2 + 1]) / 2)

function run_set(name, shapes)
    println("\n== $name: $(length(shapes)) shapes")
    println(join(["t", "v", "k", "ipog", "construction", "best_known", "ipog_s", "construction_s", "mark", "entry"], '\t'))
    larger, equal, smaller, over = Tuple{Int, Int, Int}[], 0, 0, Float64[]
    for (t, v, k, expensive, cost) in shapes
        ONLY_EXPENSIVE && !expensive && continue
        entry = UnitTestDesign._catalog_entry(t, v, k)
        best = best_known(t, v, k)
        best = best === nothing ? nothing : best.N
        if entry === nothing
            println(join(fmt.((t, v, k, nothing, nothing, best, nothing, nothing)), '\t'), "\tno entry\t-")
            continue
        end
        ipog = ipog_s = ours = ours_s = nothing
        if !expensive || EXPENSIVE || cost <= COST_CAP
            space = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
            ipog, ipog_s = timed_rows(space, t, IPOG())
            ours, ours_s = timed_rows(space, t, C)
            ours == entry.rows || error("Construction gave $ours rows where the catalog says $(entry.rows)")
        end
        mark = ipog === nothing ? "expensive" : entry.rows > ipog ? "larger" : entry.rows == ipog ? "equal" : "smaller"
        if ipog !== nothing
            entry.rows > ipog ? push!(larger, (t, v, k)) : entry.rows == ipog ? (equal += 1) : (smaller += 1)
            push!(over, ipog / entry.rows - 1)
        end
        println(join(fmt.((t, v, k, ipog, entry.rows, best, ipog_s, ours_s)), '\t'), "\t$mark\t$(entry.name)")
        flush(stdout)
    end
    println("-- $name: IPOG ran on $(length(over)); the catalog is smaller at $smaller, equal at $equal, " *
            "larger at $(length(larger))" *
            (isempty(over) ? "" : "; IPOG over the catalog: median $(percent(median(over))), " *
                                  "range $(percent(minimum(over))) to $(percent(maximum(over)))"))
    isempty(larger) || println("-- $name: the catalog is larger than IPOG at ", join(larger, ", "))
    return larger
end

names_for(k) = Tuple(Symbol(:p, i) for i in 1:k)
domains(arity) = NamedTuple{names_for(length(arity))}(Tuple(collect(1:a) for a in arity))

"The seeded path (plan §5.4, 'Seed with a few rules'): rows of Construction() and IPOG() under each case."
function run_seeded()
    println("\n== seeded: the catalog's rows that no rule forbids, then IPOG's general path")
    println(join(["case", "t", "ipog", "construction", "ipog_s", "construction_s", "mark"], '\t'))
    chain(k) = [forbid((a, b) -> a == b, Symbol(:p, i), Symbol(:p, i + 1)) for i in 1:(k - 1)]
    cases = [
        ("8 x 7, no rules", fill(7, 8), 2, Constraint[], (;)),
        ("8 x 7, 3 forbidden pairs", fill(7, 8), 2,
         [forbid((p1 = 1, p2 = 1)), forbid((p3 = 2, p5 = 4)), forbid((p2 = 7, p8 = 1))], (;)),
        ("8 x 7, p1 != p2", fill(7, 8), 2, [@forbid(p1 == p2)], (;)),
        ("8 x 7, chain p_i != p_(i+1) (7 rules)", fill(7, 8), 2, chain(8), (;)),
        ("8 x 7, p1 < p2 required (28 of 49 pairs forbidden)", fill(7, 8), 2, [@require(p1 < p2)], (;)),
        ("8 x 7, three-way rule p1 + p2 + p3 <= 15", fill(7, 8), 2, [@forbid(p1 + p2 + p3 > 15)], (;)),
        ("12 x 3 at t = 3, p1 != p2", fill(3, 12), 3, [@forbid(p1 == p2)], (;)),
        ("12 x 3 at t = 3, 3 forbidden pairs", fill(3, 12), 3,
         [forbid((p1 = 1, p2 = 1)), forbid((p3 = 2, p5 = 3)), forbid((p2 = 3, p12 = 1))], (;)),
        ("20 x 2, 3 forbidden pairs", fill(2, 20), 2,
         [forbid((p1 = 1, p2 = 1)), forbid((p3 = 2, p5 = 2)), forbid((p2 = 2, p20 = 1))], (;)),
        ("10 x 5, p1 != p2", fill(5, 10), 2, [@forbid(p1 == p2)], (;)),
        ("8 x 5, a whole-case rule", fill(5, 8), 2, [forbid(row -> row.p1 == 1 && row.p8 == 5)], (;)),
        ("20 x 10, 3 forbidden pairs", fill(10, 20), 2,
         [forbid((p1 = 1, p2 = 1)), forbid((p3 = 2, p5 = 4)), forbid((p2 = 7, p20 = 1))], (;)),
        ("8 x 7, two must-include rows", fill(7, 8), 2, Constraint[],
         (; must_include = [(p1 = 1, p2 = 2), (p1 = 3, p3 = 3, p4 = 4)])),
        ("8 x 7, a stronger group of 3", fill(7, 8), 2, Constraint[], (; stronger = [(:p1, :p2, :p3) => 3])),
        ("16 x 4, a stronger group of 4", fill(4, 16), 2, Constraint[], (; stronger = [(:p1, :p2, :p3, :p4) => 3])),
    ]
    larger = String[]
    for (label, arity, t, rules, extra) in cases
        space = TestSpace(domains(arity); constraints = rules)
        covering(space; strength = t, extra...)
        covering(space; strength = t, engine = C, extra...)
        a = @timed covering(space; strength = t, extra...)
        b = @timed covering(space; strength = t, engine = C, extra...)
        iscomplete(coverage(b.value)) || error("the seeded design for $label is incomplete")
        mark = length(b.value) > length(a.value) ? "larger" : length(b.value) == length(a.value) ? "equal" : "smaller"
        mark == "larger" && push!(larger, label)
        println(join([label, string(t), string(length(a.value)), string(length(b.value)), fmt(a.time), fmt(b.time), mark], '\t'))
        flush(stdout)
    end
    println("-- seeded: the catalog-seeded design is larger than IPOG's at ", isempty(larger) ? "none" : join(larger, "; "))
end

function main()
    covering(TestSpace((a = 1:2, b = 1:2, c = 1:2)); engine = C)
    selected("compare") && run_set("compare", [(t, v, k, false, 0.0) for (t, v, k) in compare_shapes()])
    for family in ("uniform-pp", "uniform-npp")
        selected(family) && run_set(family, family_shapes(family))
    end
    selected("seeded") && run_seeded()
end
main()
