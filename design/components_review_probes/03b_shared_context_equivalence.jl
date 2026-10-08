# Does sharing one FeasibilityContext between report's base and bonus
# measurements (the review's recommendation) change any reported figure when
# feasibility_limit binds? Fresh = what report() does today (report.jl:191,
# :232, each _measure builds its own context at measure.jl:521).
#   julia --project=/Users/adolgert/dev/UnitTestDesign.jl probe_shared_context.jl
using UnitTestDesign, Random
const U = UnitTestDesign

function parts_in(context, rows, space; strength, explanation_limit = 1_000_000)
    groups = U._groups(space, strength, Pair[])
    kept, dups, rej, _ = U._read_rows(context, rows)
    supports = U._supports(groups)
    o = U._measure_part(context, groups, supports, kept[1], :ordinary; explanation_limit,
                        duplicates = dups[1], rejected = rej[1])
    n = U._measure_part(context, groups, supports, kept[2], :negative; explanation_limit,
                        duplicates = dups[2], rejected = rej[2])
    return o, n
end

counts(p) = (p.covered, p.feasible, length(p.missing), length(p.excluded), length(p.unknown))

# (base, bonus) figures: fresh contexts (today) and one shared context (proposal).
function both(cases, limit)
    space, rows = cases.space, collect(cases)
    s = cases.strategy === :covering ? cases.strength : min(2, length(space.names))
    fresh_base = parts_in(U.FeasibilityContext(space; feasibility_limit = limit), rows, space; strength = s)
    fresh_bonus = parts_in(U.FeasibilityContext(space; feasibility_limit = limit), rows, space; strength = s + 1)
    ctx = U.FeasibilityContext(space; feasibility_limit = limit)
    shared_base = parts_in(ctx, rows, space; strength = s)
    shared_bonus = parts_in(ctx, rows, space; strength = s + 1)
    f(x) = (ordinary = counts(x[1]), negative = counts(x[2]))
    return (fresh = (f(fresh_base), f(fresh_bonus)), shared = (f(shared_base), f(shared_bonus)))
end

println("counts are (covered, feasible, missing, excluded, unknown)")

# test/fixtures.jl:175 (limit_exhaustion), used by test/test_report.jl:188-212
names = Tuple(Symbol(:x, i) for i in 1:8)
le = TestSpace(NamedTuple{names}(Tuple(1:4 for _ in 1:8));
               constraints = [forbid((xs...) -> !all(==(4), xs), names...)])
r = both(all_pairs(le), 1)
println("limit_exhaustion, feasibility_limit = 1")
println("  fresh  bonus: ", r.fresh[2])
println("  shared bonus: ", r.shared[2], r.fresh[2] == r.shared[2] ? "   (same)" : "   (DIFFERENT)")

# test/test_report.jl:532-535 (pins "negative: 6 of at least 6, 90 unresolved")
neg = TestSpace((n = [1, Invalid(0)], x1 = 1:4, x2 = 1:4, x3 = 1:4, x4 = 1:4);
    constraints = [forbid(n -> n == 1, :n),
                   forbid((a, b, c, d) -> !(a == b == c == d == 4), :x1, :x2, :x3, :x4)])
r = both(all_pairs(neg), 1)
println("test_report.jl:532 space, feasibility_limit = 1")
println("  fresh  bonus: ", r.fresh[2])
println("  shared bonus: ", r.shared[2], r.fresh[2] == r.shared[2] ? "   (same)" : "   (DIFFERENT)")

# Random small spaces with scoped rules over overlapping and separate scopes.
function random_space(rng)
    n = rand(rng, 4:7)
    names = Tuple(Symbol(:p, i) for i in 1:n)
    doms = Tuple(collect(1:rand(rng, 2:4)) for _ in 1:n)
    rules = Any[]
    for _ in 1:rand(rng, 1:4)
        k = rand(rng, 2:min(4, n))
        scope = Tuple(sort(randperm(rng, n)[1:k]))
        bad = Set(Tuple(rand(rng, 1:length(doms[p])) for p in scope) for _ in 1:rand(rng, 1:6))
        push!(rules, forbid((vs...) -> vs in bad, names[collect(scope)]...))
    end
    return TestSpace(NamedTuple{names}(doms); constraints = rules)
end

rng = Xoshiro(20260928)
tried = differ = 0
example = nothing
for trial in 1:400
    space = random_space(rng)
    cases = try
        all_pairs(space)
    catch
        continue
    end
    length(space.names) >= 3 || continue
    for limit in (1, 2, 3, 5)
        global tried += 1
        res = both(cases, limit)
        if res.fresh != res.shared
            global differ += 1
            example === nothing && (global example = (space, limit, res))
        end
    end
end
println("random spaces: $tried (space, limit) pairs; fresh != shared in $differ")
if example !== nothing
    space, limit, r = example
    println("  first difference: parameters $(space.names), domains $(length.(space.values)), ",
            "$(length(space.constraints)) rules, feasibility_limit = $limit")
    println("    fresh  (base, bonus): ", r.fresh)
    println("    shared (base, bonus): ", r.shared)
end
