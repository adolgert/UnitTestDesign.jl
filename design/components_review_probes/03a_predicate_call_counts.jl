# Probe for review section 3: how often does a whole-case predicate run?
#
# Run from anywhere:
#   julia --project=/Users/adolgert/dev/UnitTestDesign.jl probe_predicate_calls.jl
#
# Space: three binary parameters a, b, c (8 complete assignments) and ONE
# whole-case rule, forbid(case -> ...), whose predicate logs every complete
# assignment it is called on. Public API only, except the "decomposition"
# lines, which call the two internal functions report() calls
# (UnitTestDesign._measure and UnitTestDesign._coverage) to attribute calls.
using UnitTestDesign
const U = UnitTestDesign

const LOG = Tuple{Int,Int,Int}[]

probe_space(body) = TestSpace((a = [0, 1], b = [0, 1], c = [0, 1]);
    constraints = [forbid(case -> (push!(LOG, (case.a, case.b, case.c)); body(case)); reason = "probe")])

function counted(f)
    empty!(LOG)
    result = f()
    return result, copy(LOG)
end

function repeats(log)
    counts = Dict{Tuple{Int,Int,Int},Int}()
    for x in log
        counts[x] = get(counts, x, 0) + 1
    end
    return sort([k => v for (k, v) in counts if v > 1])
end

describe(log) = "calls = $(length(log)), distinct assignments = $(length(unique(log)))" *
                (isempty(repeats(log)) ? "" : ", evaluated more than once: $(repeats(log))")

const KW = (feasibility_limit = 1_000_000, explanation_limit = 1_000_000)

function scenario(title, body, make_design)
    println("\n", "="^78, "\n", title, "\n", "="^78)
    space = probe_space(body)
    design, genlog = counted(() -> make_design(space))
    println("design ($(design.strategy), $(length(design)) rows): ",
            join((string((r.a, r.b, r.c)) for r in design), " "))
    println("  constructing the design:            ", describe(genlog))
    r, replog = counted(() -> report(design))
    println("  report(design):                     ", describe(replog))
    println("      guarantee: ", r.guarantee)
    println("      bonus: ", (r.bonus.covered, r.bonus.feasible, r.bonus.unknown))
    s = r.strength
    _, c2 = counted(() -> coverage(design; strength = s))
    println("  coverage(design; strength = $s):     ", describe(c2))
    if s + 1 <= 3
        _, c3 = counted(() -> coverage(design; strength = s + 1))
        println("  coverage(design; strength = $(s + 1)):     ", describe(c3))
    end
    # Attribution: exactly the two measurements report() makes (report.jl:191, :232).
    rows = collect(design)
    _, m1 = counted(() -> U._measure(rows, space; strength = s, stronger = Pair[], KW...))
    _, m2 = counted(() -> U._coverage(rows, space; strength = s + 1, stronger = Pair[], KW...))
    println("  decomposition: _measure(strength $s) = $(length(m1)) $(m1)")
    println("                 _coverage(strength $(s + 1)) = $(length(m2)) $(m2)")
    println("                 sum = $(length(m1) + length(m2)) (report: $(length(replog)))")
    # What one shared FeasibilityContext would cost (a simulation of the
    # review's recommendation, built from measure.jl's own internals).
    _, shared = counted() do
        context = U.FeasibilityContext(space; feasibility_limit = KW.feasibility_limit)
        for strength in (s, s + 1)
            groups = U._groups(space, strength, Pair[])
            kept, dups, rej, _ = U._read_rows(context, rows)
            supports = U._supports(groups)
            U._measure_part(context, groups, supports, kept[1], :ordinary;
                            explanation_limit = KW.explanation_limit, duplicates = dups[1], rejected = rej[1])
            U._measure_part(context, groups, supports, kept[2], :negative;
                            explanation_limit = KW.explanation_limit, duplicates = dups[2], rejected = rej[2])
        end
    end
    println("  simulated shared context (both strengths): ", describe(shared))
    return space
end

function design_sizes_breakdown(space)
    _, total = counted(() -> design_sizes(space))
    println("  design_sizes(space):                ", describe(total))
    parts = Pair{String,Int}[]
    designs = Pair{String,Any}[]
    d, l = counted(() -> full_factorial(space)); push!(parts, "generate full_factorial" => length(l)); push!(designs, "full_factorial" => d)
    for s in 1:3
        d, l = counted(() -> covering(space; strength = s)); push!(parts, "generate covering($s)" => length(l)); push!(designs, "covering($s)" => d)
    end
    for dist in 1:2
        _, l = counted(() -> isallowed(space, U._default_base(space))); push!(parts, "isallowed(default base) before excursions($dist)" => length(l))
        d, l = counted(() -> excursions(space; distance = dist)); push!(parts, "generate excursions($dist)" => length(l)); push!(designs, "excursions($dist)" => d)
    end
    for (name, d) in designs, s in 2:3
        _, l = counted(() -> coverage(d; strength = s)); push!(parts, "measure $name at strength $s ($(length(d)) rows)" => length(l))
    end
    for (k, v) in parts
        println("      ", rpad(k, 58), v)
    end
    gen = sum(v for (k, v) in parts if !startswith(k, "measure"))
    meas = sum(v for (k, v) in parts if startswith(k, "measure"))
    println("      replayed sum = $(gen + meas)  (generation + isallowed = $gen, measurement = $meas)")
end

println("Julia ", VERSION)

# S1: the predicate forbids nothing; all_pairs gives a 4-row covering array,
# so every pair is covered and the base measurement searches nothing.
s1 = scenario("S1: forbid(case -> false); all_pairs(space) (every pair covered)",
              case -> false, space -> all_pairs(space))
design_sizes_breakdown(s1)

# S2: same space; a 4-row excursion around (0,0,0) leaves three pairs
# uncovered, so the base measurement runs feasibility searches.
s2 = scenario("S2: forbid(case -> false); excursions(space; distance = 1) (3 pairs uncovered)",
              case -> false, space -> excursions(space; distance = 1))

# S3: the whole-case rule makes the pair (a = 1, b = 1) infeasible, so a
# pair is excluded (implied: the rule's scope is every parameter).
s3 = scenario("S3: forbid(case -> case.a == 1 && case.b == 1); all_pairs(space)",
              case -> case.a == 1 && case.b == 1, space -> all_pairs(space))
design_sizes_breakdown(s3)

# S4: that rule, and the 4-row excursion: one pair excluded, two missing.
s4 = scenario("S4: forbid(case -> case.a == 1 && case.b == 1); excursions(space; distance = 1)",
              case -> case.a == 1 && case.b == 1, space -> excursions(space; distance = 1))
