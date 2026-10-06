# The random spaces of the `mainstream`, `exact` and `smallest` families (plan §7.2),
# written to random_spaces.json beside this file, which families.py reads. Run from
# the repository root:
#
#     julia --project=. --startup-file=no benchmark/scaling/families/generate.jl            # write
#     julia --project=. --startup-file=no benchmark/scaling/families/generate.jl --check    # compare
#     julia --project=. --startup-file=no benchmark/scaling/families/generate.jl --verify   # and IPOG
#
# The spaces are probes 12, 16 and 25's (design/20261003_solver_plan_review_probes/):
# `k = rand(rng, ks); arity = rand(rng, levels, k)` from `Xoshiro(seed)`, so a set
# here is the probes' set and their numbers are comparable. The draws depend on
# Julia's random streams, so the file is the reference and records the Julia that
# wrote it; `--check` says whether this Julia reproduces it. `--verify` runs IPOG on
# each probe set and compares with what probe 16 printed.
#
# Rules come from test/random_problems.jl's `random_rule` (1–4 scoped rules over
# 2–3 parameters, about half with `!=` or `<`), drawn from their own generators so
# the spaces stay the probes', and are written as the forbidden tuples they imply.
using UnitTestDesign, Random, JSON
include(joinpath(@__DIR__, "..", "..", "fixtures.jl"))     # BenchFixtures.random_rule
const OUT = joinpath(@__DIR__, "random_spaces.json")

# name, seed, count, levels, parameters, strength, and probe 16's printed IPOG
# figures for the set: mean rows over the bound, and spaces where IPOG meets it.
const SETS = [
    (name = "r1", seed = 1, count = 150, levels = 2:5, ks = 4:12, strength = 2, probe = (1.128, 52)),
    (name = "r2", seed = 2, count = 150, levels = 2:3, ks = 4:12, strength = 2, probe = (1.404, 6)),
    (name = "r3", seed = 3, count = 100, levels = 2:7, ks = 4:12, strength = 2, probe = (1.112, 17)),
    (name = "r4", seed = 4, count = 60, levels = 2:4, ks = 5:10, strength = 3, probe = (1.191, 6)),
]
# The same spaces with 1–4 scoped rules: base set and the seed of the rule generator.
const RULE_SETS = [(name = "r3-rules", base = "r3", seed = 1003), (name = "r4-rules", base = "r4", seed = 1004)]
# `smallest`: random value counts in 2:12 on t + 1 and t + 2 parameters.
const SMALLEST = [(name = "s$t-$k", seed = 2000 + 10t + k, count = 8, k, strength = t) for t in (2, 3) for k in (t + 1, t + 2)]

bound(arity, t) = prod(sort(arity; rev = true)[1:t])

function forbidden(rule, domains)
    scope = rule.scope
    tuples = [collect(xs) for xs in Iterators.product((domains[p] for p in scope)...) if rule.predicate(xs...)]
    return (scope = scope, tuples = tuples, text = rule.text)
end

function generate()
    spaces = []
    for set in SETS
        rng = Xoshiro(set.seed)
        for i in 1:set.count
            k = rand(rng, set.ks); arity = rand(rng, set.levels, k)
            push!(spaces, (id = "$(set.name)-$(lpad(i, 3, '0'))", set = set.name, strength = set.strength, arity))
        end
    end
    dropped = String[]
    for rs in RULE_SETS
        rng = Xoshiro(rs.seed)
        for base in filter(s -> s.set == rs.base, spaces)
            names = [Symbol(:p, i) for i in eachindex(base.arity)]
            domains = [collect(1:a) for a in base.arity]
            rules = [BenchFixtures.random_rule(rng, names, domains) for _ in 1:rand(rng, 1:4)]
            forbid = [forbidden(r, domains) for r in rules]
            id = replace(base.id, base.set => rs.name; count = 1)
            space = TestSpace((names[i] => domains[i] for i in eachindex(names))...;
                              constraints = [UnitTestDesign.forbid(r.predicate, names[r.scope]...) for r in rules])
            try
                covering(space; strength = base.strength, engine = IPOG())   # IPOG(), as when the file was written
            catch err
                push!(dropped, "$id: $(sprint(showerror, err))")
                continue
            end
            push!(spaces, (id, set = rs.name, strength = base.strength, arity = base.arity, forbid))
        end
    end
    for set in SMALLEST
        rng = Xoshiro(set.seed)
        for i in 1:set.count
            push!(spaces, (id = "$(set.name)-$(lpad(i, 3, '0'))", set = set.name, strength = set.strength,
                           arity = rand(rng, 2:12, set.k)))
        end
    end
    header = (generator = "benchmark/scaling/families/generate.jl", julia = string(VERSION),
              sets = [(; s.name, s.seed, s.count, levels = [first(s.levels), last(s.levels)],
                       parameters = [first(s.ks), last(s.ks)], s.strength,
                       probe16_ipog = (mean_over_bound = s.probe[1], at_bound = s.probe[2])) for s in SETS],
              rule_sets = RULE_SETS, smallest = [(; s.name, s.seed, s.count, s.k, s.strength) for s in SMALLEST],
              dropped)
    io = IOBuffer()
    println(io, "{\"header\": ", JSON.json(header), ",")
    println(io, " \"spaces\": [")
    println(io, join(("  " * JSON.json(s) for s in spaces), ",\n"))
    println(io, " ]}")
    return String(take!(io)), spaces, dropped
end

function verify(spaces)
    ok = true
    for set in SETS
        selected = filter(s -> s.set == set.name, spaces)
        ratios = Float64[]; at = 0
        for s in selected
            space = TestSpace((Symbol(:p, i) => collect(1:a) for (i, a) in enumerate(s.arity))...)
            rows = length(covering(space; strength = s.strength, engine = IPOG()))
            push!(ratios, rows / bound(s.arity, s.strength)); at += rows == bound(s.arity, s.strength)
        end
        mean = round(sum(ratios) / length(ratios); digits = 3)
        agree = (mean, at) == set.probe
        ok &= agree
        println("$(set.name): IPOG mean rows/bound $mean, at the bound on $at of $(length(selected)); probe 16 printed ",
                "$(set.probe[1]) and $(set.probe[2])", agree ? "" : "   DIFFERS")
    end
    return ok
end

text, spaces, dropped = generate()
foreach(d -> println("dropped (no design): ", d), dropped)
if "--check" in ARGS || "--verify" in ARGS
    # The header records the Julia that ran; compare everything after it.
    body(x) = split(x, '\n'; limit = 2)[2]
    same = isfile(OUT) && body(read(OUT, String)) == body(text)
    println(same ? "random_spaces.json's spaces are reproduced by Julia $VERSION" :
                   "random_spaces.json's spaces DIFFER under Julia $VERSION")
    good = !("--verify" in ARGS) || verify(spaces)
    exit(same && good ? 0 : 1)
else
    write(OUT, text)
    println(length(spaces), " spaces: ", OUT)
end
