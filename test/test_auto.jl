using Test
using TestItemRunner

# `Auto`, `recommend`, and the lower bound every covering result records
# (src/auto.jl, src/lower_bound.jl; plan §4.1, §6.1, §7.5; decisions D1, D5,
# D8). The word "minimal" is a correctness claim the certifier can't recount
# (plan §3, §11), so the bound is checked against exhaustive minima on tiny
# random requests and against the known minima of probe 25. The inference and
# allocation guards are in test_stability.jl.

@testsnippet AutoSetup begin
    import Random
    using Random: Xoshiro
    using UnitTestDesign: CoveringEngine, Request, Profile, generate, fit, classify_targets,
                          classify_negative_targets, _auto_plan, _AUTO_SMALL, _engine_registry

    # What a result's record says Auto ran (`record.ordinary`): each start, as
    # (engine, rows), and the catalog's note of the stage that made the
    # ordinary rows, as `report` finds it (`_made_by`).
    starts_of(cases) = [(s.engine, s.rows) for s in cases.record.ordinary.starts]
    catalog_of(cases) = UnitTestDesign._made_by(cases.record.ordinary).catalog

    "Positions of every value of `space`'s parameter `i`: ordinary first, then invalid (`Request`)."
    value_at(space, request, i, k) = space.values[i][request.candidates[i][k]]
    named(space, request, row) = NamedTuple{Tuple(space.names)}(Tuple(value_at(space, request, i, row[i]) for i in eachindex(row)))

    """
    The fewest rows of `pool` that hold every target of `targets` (full-width
    position vectors, 0 unset), by branch and bound on the uncovered target
    held by the fewest rows; `nothing` when some target is in no row. It
    prunes with the counting the package's bound rests on, which is certain
    (a row has one value per parameter, so it holds one target of each set
    of parameters): the most uncovered targets on one set is a floor on the
    rows still needed. What the test checks is the package's arithmetic and
    bookkeeping (must-include rows, exclusions, groups, negative rows).
    """
    function min_cover(pool, targets)
        isempty(targets) && return 0
        holds(row, t) = all(i -> t[i] == 0 || row[i] == t[i], eachindex(t))
        options = [[j for j in eachindex(pool) if holds(pool[j], t)] for t in targets]
        any(isempty, options) && return nothing
        covers = [BitSet(i for i in eachindex(targets) if holds(pool[j], targets[i])) for j in eachindex(pool)]
        keys = unique(findall(!=(0), t) for t in targets)
        support = [findfirst(==(findall(!=(0), t)), keys) for t in targets]
        floor(uncovered) = maximum(s -> count(i -> support[i] == s, uncovered), eachindex(keys))
        best = Ref(length(targets))
        function search(uncovered::BitSet, depth::Int)
            isempty(uncovered) && return (best[] = min(best[], depth); nothing)
            depth + floor(uncovered) >= best[] && return nothing
            i = argmin(i -> length(options[i]), collect(uncovered))
            for j in options[i]
                search(setdiff(uncovered, covers[j]), depth + 1)
            end
            return nothing
        end
        search(BitSet(eachindex(targets)), 0)
        return best[]
    end

    "Every complete position row of the ordinary arity, as vectors."
    ordinary_rows(arity) = [collect(Tuple(c)) for c in vec(collect(CartesianIndices(Tuple(arity))))]

    """
    The fewest rows any covering design for `request` can have, by exhaustive
    search: its ordinary must-include rows (each partial one completed every
    valid way), then the fewest valid ordinary rows for the required ordinary
    targets they leave, plus, for each invalid value, the fewest valid
    negative rows that hold its required negative targets. Validity is the
    public `isallowed`. Negative must-include rows are not supported here.
    """
    function exhaustive_minimum(space, request)
        n = length(request.arity)
        pool = [r for r in ordinary_rows(request.arity) if isallowed(space, named(space, request, r))]
        required, _ = classify_targets(request)
        targets = [collect(t) for t in required]
        must = request.must_include
        any(j -> any(i -> must[i, j] > request.arity[i], 1:n), axes(must, 2)) &&
            error("exhaustive_minimum takes ordinary must-include rows only")
        completions = [[r for r in pool if all(i -> must[i, j] == 0 || r[i] == must[i, j], 1:n)] for j in axes(must, 2)]
        holds(row, t) = all(i -> t[i] == 0 || row[i] == t[i], eachindex(t))
        ordinary = typemax(Int)
        for chosen in Iterators.product(completions...)
            left = [t for t in targets if !any(r -> holds(r, t), chosen)]
            extra = min_cover(pool, left)
            extra === nothing && error("a required target is in no valid row")
            ordinary = min(ordinary, size(must, 2) + extra)
        end
        negative_required, _ = classify_negative_targets(request)
        negative = 0
        for p in 1:n, v in (request.arity[p] + 1):length(request.candidates[p])
            here = [t for t in negative_required if t[p] == v]
            isempty(here) && continue
            rows = Vector{Int}[]
            for r in ordinary_rows(request.arity[[q for q in 1:n if q != p]])
                row = [q < p ? r[q] : q == p ? v : r[q - 1] for q in 1:n]
                isallowed(space, named(space, request, row)) && push!(rows, row)
            end
            negative += min_cover(rows, here)
        end
        return ordinary + negative
    end

    "A tiny random request: 2–4 parameters, at most 36 ordinary rows, rules, must-include rows, a group, an Invalid value."
    function tiny_request(rng)
        while true
            k = rand(rng, 2:4)
            arity = rand(rng, 1:3, k)
            prod(arity) <= 36 || continue
            names = Tuple(Symbol(:p, i) for i in 1:k)
            domains = Any[Any[1:a...] for a in arity]
            invalid = rand(rng) < 0.3
            invalid && push!(domains[rand(rng, 1:k)], Invalid(0))
            rules = Constraint[]
            for _ in 1:rand(rng, 0:2)
                a, b = rand(rng, 1:k), rand(rng, 1:k)
                a == b && continue
                push!(rules, forbid(NamedTuple{(names[a], names[b])}((rand(rng, 1:arity[a]), rand(rng, 1:arity[b])))))
            end
            space = TestSpace(NamedTuple{names}(Tuple(domains)); constraints = rules)
            t = rand(rng, 1:min(3, k))
            stronger = k > t + 1 && rand(rng) < 0.3 ? [names[1:(t + 1)] => t + 1] : Pair[]
            valid = [r for r in ordinary_rows(arity) if isallowed(space, NamedTuple{names}(Tuple(r)))]
            isempty(valid) && continue
            must = NamedTuple[]
            for _ in 1:rand(rng, 0:2)
                r = rand(rng, valid)
                keep = [i for i in 1:k if rand(rng) < 0.7]
                isempty(keep) && (keep = [1])
                push!(must, NamedTuple{names[keep]}(Tuple(r[keep])))
            end
            return space, (; strength = t, stronger, must_include = must)
        end
    end
end


@testitem "Auto: settings, record, display and the goals (§6.1, D8)" setup=[AutoSetup] begin
    @test Auto() isa UnitTestDesign.CoveringEngine
    @test (Auto().goal, Auto().seed, Auto().effort) == (:balanced, 0, 1)
    @test repr(Auto()) == "Auto()"
    @test repr(Auto(goal = :compact, seed = 3, effort = 2)) == "Auto(goal = :compact, seed = 3, effort = 2)"
    @test_throws "goal is :fast, :balanced or :compact; got :quick" Auto(goal = :quick)
    @test_throws "seed must be an integer of at least 0, got -1" Auto(seed = -1)
    @test_throws "effort must be a positive integer, got 0" Auto(effort = 0)
    # Only :compact draws random numbers, so only it records a seed (contract §9.5).
    r = UnitTestDesign.engine_record(Auto())
    @test r.name === :Auto && r.seed === nothing && !r.randomized
    r = UnitTestDesign.engine_record(Auto(goal = :compact, seed = 4))
    @test r.name === :Auto && r.seed == 4 && r.randomized
    @test UnitTestDesign.engine_record(Auto(goal = :fast, seed = 4)).seed === nothing
    @test fit(Auto(), Profile(Request(TestSpace((a = 1:2, b = 1:3))))).kind === :native
    # The goals on a uniform space where the catalog is smaller than IPOG.
    space = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:8)}(Tuple(1:7 for _ in 1:8)))
    ipog, fast, balanced, compact = (all_pairs(space; engine) for engine in
                                     (IPOG(), Auto(goal = :fast), Auto(), Auto(goal = :compact)))
    @test fast == ipog && fast.record.ordinary.chose == "IPOG()"
    @test length(balanced) == 49 < length(ipog)
    @test balanced.record.ordinary.chose == "Construction()" && catalog_of(balanced).orthogonal
    @test starts_of(balanced) == [("Construction()", 49)]   # IPOG not run: at the bound
    @test balanced.record.minimal && balanced.record.lower_bound == 49
    @test length(compact) == 49 && compact.record.ordinary.chose == "Compact(Construction())"
    @test compact.record.ordinary.reducer.stop === :bound && compact.seed == 0
    @test (balanced.engine, balanced.seed, fast.seed) == (:Auto, nothing, nothing)
    @test startswith(repr(balanced), "49 cases (minimal) · strength 2 · Auto: Construction() · 8 parameters")
    @test occursin("· Auto: Compact(Construction()) seed 0 ·", repr(compact))
    text = sprint(show, MIME"text/plain"(), report(balanced))
    @test occursin("\nsize: 49 cases, minimal: the 7 × 7 = 49 combinations of p1 and p2 need a case each; " *
                   "an orthogonal array", text)
    @test endswith(text, "seed: none (Auto uses no randomness)")
    @test endswith(sprint(show, MIME"text/plain"(), report(compact)), "seed: 0 (Auto(goal = :compact) repeats these cases)")
end


@testitem "Auto: keep the smallest, the bound shortcut, and the threshold (§4.1)" setup=[AutoSetup] begin
    plan(space; kw...) = _auto_plan(Auto(), Profile(Request(space; kw...)))
    uniform(k, v) = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
    # At the bound (an orthogonal array, a zero-sum array): the catalog alone.
    for (k, v, t) in ((8, 7, 2), (3, 5, 2), (4, 3, 3))
        p = plan(uniform(k, v); strength = t)
        @test [(c.label, c.runs) for c in p.candidates] == [("IPOG()", false), ("Construction()", true)] && !p.smallest
    end
    # Small, above the bound: both, and the fewer rows kept (15 × 6: IPOG has 75, the catalog 76).
    p = plan(uniform(15, 6))
    @test p.smallest && all(c -> c.runs, p.candidates)
    cases = all_pairs(uniform(15, 6); engine = Auto())
    @test starts_of(cases) == [("IPOG()", 75), ("Construction()", 76)] && cases.record.ordinary.kept == 1
    @test cases.record.ordinary.chose == "IPOG()" && cases == all_pairs(uniform(15, 6))
    # A tie goes to IPOG, so Auto gives IPOG's cases unless the catalog's are fewer: the
    # front page's example, where the seeded zero-sum array also takes 5 cases.
    front = TestSpace((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
                      constraints = [@require(mode == :exact || solver == :none),
                                     forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance")])
    tie = all_pairs(front; engine = Auto())
    @test starts_of(tie) == [("IPOG()", 5), ("Construction()", 5)] && tie.record.ordinary.kept == 1
    @test tie.record.ordinary.chose == "IPOG()" && tie == all_pairs(front)
    # Smaller catalog: kept.
    seven = all_pairs(uniform(10, 7); engine = Auto())
    @test seven.record.ordinary.chose == "Construction()" && length(seven) < length(all_pairs(uniform(10, 7)))
    @test seven.record.ordinary.kept == 2 && haskey(seven.record.ordinary.starts[2], :catalog)
    # Above the threshold, an exact shape: the catalog alone, IPOG not run.
    big = uniform(40, 4)
    @test Profile(Request(big; strength = 3)).targets > _AUTO_SMALL
    p = plan(big; strength = 3)
    @test [(c.label, c.runs) for c in p.candidates] == [("IPOG()", false), ("Construction()", true)]
    # Above the threshold, seeded under a rule: IPOG alone.
    ruled = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:40)}(Tuple(1:4 for _ in 1:40));
                      constraints = [forbid((p1 = 1, p2 = 1))])
    p = plan(ruled; strength = 3)
    @test p.candidates[2].plan.fit.kind === :seeded && [(c.label, c.runs) for c in p.candidates] == [("IPOG()", true), ("Construction()", false)]
    # Not covered by the catalog (mixed counts): IPOG alone, and the same rows as IPOG.
    mixed = TestSpace((a = 1:2, b = 1:3, c = 1:4, d = 1:2))
    @test [(c.label, c.runs) for c in plan(mixed).candidates] == [("IPOG()", true), ("Construction()", false)]
    @test all_pairs(mixed; engine = Auto()) == all_pairs(mixed)
    # The plan is a pure function of the request: the same profile, the same plan.
    a, b = plan(uniform(15, 6)), plan(uniform(15, 6))
    @test [(c.label, c.runs, c.reason) for c in a.candidates] == [(c.label, c.runs, c.reason) for c in b.candidates]
end


@testitem "Auto: never more rows than IPOG, and :compact never more than :balanced (§7.5)" setup=[AutoSetup] begin
    rng = Xoshiro(20261004)
    for trial in 1:60
        k = rand(rng, 3:7)
        uniform = rand(rng) < 0.6
        arity = uniform ? fill(rand(rng, 2:6), k) : rand(rng, 2:5, k)
        names = Tuple(Symbol(:p, i) for i in 1:k)
        domains = Any[Any[1:a...] for a in arity]
        rand(rng) < 0.2 && push!(domains[1], Invalid(0))
        rules = rand(rng) < 0.3 ? [forbid(NamedTuple{(:p1, :p2)}((1, 1)))] : Constraint[]
        space = TestSpace(NamedTuple{names}(Tuple(domains)); constraints = rules)
        t = rand(rng, 1:min(3, k))
        ipog = covering(space; strength = t)
        fast = covering(space; strength = t, engine = Auto(goal = :fast))
        balanced = covering(space; strength = t, engine = Auto())
        compact = covering(space; strength = t, engine = Auto(goal = :compact))
        @test fast == ipog
        @test length(balanced) <= length(ipog)
        @test length(compact) <= length(balanced)
        @test iscomplete(coverage(balanced)) && iscomplete(coverage(compact))
        # Determinism (contract §9.1): another call, after reseeding the global generator, agrees.
        Random.seed!(trial)
        @test covering(space; strength = t, engine = Auto(goal = :compact)) == compact
    end
end


@testitem "Auto: a pure function of the request, whatever else is loaded or limited (§9.1, §3.8, §5.9)" setup=[AutoSetup] begin
    # An engine defined after the package loads, which fits everything exactly and would
    # win on size if Auto consulted it, changes nothing: Auto's candidates are a fixed list.
    struct Greedy <: UnitTestDesign.CoveringEngine end
    UnitTestDesign.engine_record(::Greedy) = UnitTestDesign.EngineRecord(:Greedy, nothing)
    UnitTestDesign.fit(::Greedy, ::UnitTestDesign.Profile) = UnitTestDesign.Fit(:exact, "everything"; rows = 1)
    UnitTestDesign.cover_ordinary(::Greedy, request, targets) = error("Auto must not call another engine")
    space = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:6)}(Tuple(1:5 for _ in 1:6));
                      constraints = [@forbid(p1 == p2)])
    before = all_pairs(space; engine = Auto())
    @test all_pairs(space; engine = Auto()) == before
    # The rows don't depend on feasibility_limit (contract §3.8), in the catalog's seeded path too.
    @test before.record.ordinary.chose in ("Construction()", "IPOG()")
    for limit in (1_000, 100_000, 10^8)
        @test all_pairs(space; engine = Auto(), feasibility_limit = limit) == before
        @test all_pairs(space; engine = Auto(goal = :compact), feasibility_limit = limit) ==
              all_pairs(space; engine = Auto(goal = :compact))
    end
    # A limit that stops classification stops the call before any start runs.
    @test_throws "classifying target" all_pairs(space; engine = Auto(), feasibility_limit = 1)
    # A limit that stops a start's own search ends Auto's call too (§9.12):
    # nothing catches the start's ResourceLimitError. In 1,500 small random
    # spaces with rules, no limit let classification finish and then stopped a
    # start, so the targets are classified under the default limit and the
    # starts run under a limit of 1, where IPOG's placement searches stop.
    ruled = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:7)}(Tuple(1:3 for _ in 1:7));
                      constraints = [forbid((p5 = 2, p1 = 2)), forbid((p2 = 3, p6 = 3)), forbid((p5 = 2, p1 = 1))])
    required, _ = classify_targets(Request(ruled))
    for engine in (Auto(), Auto(goal = :compact))
        @test _auto_plan(engine, Profile(Request(ruled))).candidates[1].runs   # IPOG's start runs first
        tight = Request(ruled; feasibility_limit = 1)
        @test_throws "placing a value: the feasibility search for" UnitTestDesign._execute(
            UnitTestDesign._prepare(engine, Profile(tight)), tight, UnitTestDesign.RequiredTargets(tight, required))
        @test iscomplete(coverage(all_pairs(ruled; engine)))
    end
end


@testitem "Auto: negative rows are chosen the same way for each invalid value (§4.1)" setup=[AutoSetup] begin
    space = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = [1, 2, 3, Invalid(:x)]))
    for t in (2, 3)
        ipog = covering(space; strength = t)
        auto = covering(space; strength = t, engine = Auto())
        compact = covering(space; strength = t, engine = Auto(goal = :compact))
        @test count(hasinvalid, auto) <= count(hasinvalid, ipog)
        @test length(auto) <= length(ipog) && length(compact) <= length(auto)
        @test iscomplete(coverage(auto)) && iscomplete(coverage(compact))
        @test auto.negative_covered == auto.negative_required
    end
end


@testitem "the lower bound: never above an exhaustive minimum, and minimal only when it is met (§4.1, D5)" setup=[AutoSetup] begin
    let rng = Xoshiro(1004), met = 0, claims = 0, checked = 0
        for trial in 1:150
            space, kw = tiny_request(rng)
            request = Request(space; kw...)
            exact = exhaustive_minimum(space, request)
            for engine in (IPOG(), Auto(), Auto(goal = :compact), GND())
                cases = covering(space; kw..., engine)
                b = cases.record.lower_bound
                checked += 1
                @test b <= exact <= length(cases)
                @test cases.record.minimal == (length(cases) == b)
                cases.record.minimal && (claims += 1; @test length(cases) == exact)
                met += b == exact
            end
        end
        @test checked == 600
        @test claims > 100 && met > 200   # the bound is usually tight on spaces this small, and is claimed
    end
end


@testitem "the lower bound: probe 25's known minima, zero-sum and orthogonal-array shapes (§4.1, D5)" setup=[AutoSetup] begin
    uniform(k, v) = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
    # (t, k, v, minimum): probe 25's settled uniform shapes (its .out lists the published minima).
    known = [(2, 10, 2, 6), (2, 15, 2, 7), (2, 4, 3, 9), (2, 5, 3, 11), (2, 6, 3, 12), (2, 7, 3, 12),
             (2, 8, 3, 13), (2, 5, 4, 16), (2, 6, 5, 25), (3, 5, 2, 10), (3, 6, 2, 12), (3, 8, 2, 12),
             (3, 11, 2, 12),
             # zero-sum (t + 1 parameters) and Bush orthogonal arrays, at the bound v^t
             (2, 3, 6, 36), (2, 3, 12, 144), (3, 4, 5, 125), (2, 8, 7, 49), (3, 5, 4, 64), (2, 9, 8, 64)]
    for (t, k, v, minimum) in known
        for engine in (IPOG(), Auto(), Auto(goal = :compact), Compact(IPOG()))
            cases = covering(uniform(k, v); strength = t, engine)
            @test cases.record.lower_bound <= minimum <= length(cases)
            cases.record.minimal && @test length(cases) == minimum
            cases.record.minimal || @test length(cases) > cases.record.lower_bound
        end
        # Where the minimum is the bound, Auto reaches it and says so.
        if minimum == v^t
            cases = covering(uniform(k, v); strength = t, engine = Auto())
            @test cases.record.minimal && length(cases) == minimum
        end
    end
    # Spaces with rules whose minimum probe 25 proved: the bound is below it, so no claim.
    smooth = TestSpace((window = [1, 3, 5], boundary = [:clamp, :reflect, :periodic],
                        kernel = [:box, :triangle, :gaussian], n = [1, 4, 100]);
                       constraints = [@forbid(window == 1 && kernel != :box),
                                      @forbid(boundary == :reflect && n <= window ÷ 2)])
    flags = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:12)}(Tuple(1:2 for _ in 1:12));
                      constraints = [@forbid(p1 == 2 && p2 == 1), @forbid(p3 == 2 && p4 == 1),
                                     @forbid(p5 == 2 && p1 == 1), @forbid(p6 == 2 && p7 == 2)])
    warmup = TestSpace((p1 = 1:2, p2 = 1:2, p3 = 1:2, p4 = 1:2); constraints = [forbid((p1 = 1, p2 = 1))])
    for (space, t, bound, minimum) in ((smooth, 2, 9, 11), (flags, 2, 4, 7), (flags, 3, 8, 18), (warmup, 2, 4, 5))
        for engine in (IPOG(), Auto(), Auto(goal = :compact))
            cases = covering(space; strength = t, engine)
            @test cases.record.lower_bound == bound
            @test !cases.record.minimal && length(cases) >= minimum
        end
    end
    # The Engines page says no design for `smooth` has fewer than 11 cases: an
    # exhaustive search over its 57 valid cases, here, shows it.
    @test exhaustive_minimum(smooth, Request(smooth)) == 11
    @test length(covering(smooth; engine = Auto(goal = :compact))) == 11
    # A must-include row is a row of the design, and those that hold combinations count once.
    must = all_pairs(uniform(3, 3); must_include = [(p1 = 1, p2 = 1, p3 = 1), (p1 = 1, p2 = 1, p3 = 1)])
    @test must.record.lower_bound == 10 && length(must) == 10 && must.record.minimal
    @test must.record.proof == "the 2 must-include rows hold at most 1 of the 3 × 3 = 9 combinations of p1 and p2, " *
                               "and the other 8 need a case each"
    one = all_pairs(uniform(3, 3); must_include = [(p1 = 1, p2 = 1, p3 = 1)])
    @test one.record.proof == "the 1 must-include row holds at most 1 of the 3 × 3 = 9 combinations of p1 and p2, " *
                              "and the other 8 need a case each"
    # Excluded combinations are not required.
    ruled = all_pairs(TestSpace((a = 1:3, b = 1:3, c = 1:2); constraints = [forbid((a = 1, b = 1))]))
    @test ruled.record.lower_bound == 8
    @test ruled.record.proof == "the 8 feasible combinations of a and b need a case each"
end


@testitem "the record calls a design an orthogonal array only when it is one (§5.4)" setup=[AutoSetup] begin
    # With an Invalid value the negative rows repeat combinations the array
    # holds once, so neither the record nor report says "orthogonal array",
    # at strength 2 or 3, and when the only must-include rows are negative.
    pairs_of(cases, x, y) = [(r[x], r[y]) for r in cases]
    for (space, t, must) in ((TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3)), 2, []),
                             (TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3)), 2, []),
                             (TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3)), 3, []),
                             (TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3)), 2,
                              [(a = Invalid(0), b = 1, c = 1, d = 1)]))
        for engine in (Construction(), Auto())
            cases = covering(space; strength = t, must_include = must, engine)
            @test !catalog_of(cases).orthogonal && !catalog_of(cases).seeded
            @test !allunique(pairs_of(cases, :b, :c))   # a negative row repeats a pair of the array
            @test !occursin("orthogonal array", sprint(show, MIME"text/plain"(), report(cases)))
        end
    end
    # Without one, the array is the design, and both say so.
    cases = all_pairs(TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:3)); engine = Construction())
    @test cases.record.ordinary.catalog.orthogonal && allunique(pairs_of(cases, :b, :c))
    @test occursin("an orthogonal array: each combination of 2 parameters' values is in exactly one case",
                   sprint(show, MIME"text/plain"(), report(cases)))
end


@testitem "recommend: what Auto would run, the bound, the goals and notes (§6.1)" setup=[AutoSetup] begin
    r = recommend(fill(1:7, 8)...)
    @test r isa Recommendation
    @test r.engine == "Construction()" && r.goal === :balanced
    @test [(c.engine, c.fit, c.runs, c.rows) for c in r.candidates] ==
          [("IPOG()", :native, false, nothing), ("Construction()", :exact, true, 49)]
    @test r.lower_bound == 49 && r.sizes == (fast = nothing, balanced = 49, compact = 49)
    @test (r.parameters, r.values, r.strength, r.n_rules, r.targets) == ([Symbol(:p, i) for i in 1:8], fill(7, 8), 2, 0, 1372)
    text = sprint(show, MIME"text/plain"(), r)
    @test startswith(text, "Recommendation: 8 parameters × 7 values, strength 2, no rules; 1372 combinations to cover")
    @test endswith(text, "covering(…; engine = Auto()) would use Construction().")
    @test repr(r) == "Recommendation: Construction() for 8 parameters"
    # What recommend says Auto runs is what Auto runs.
    for (space, t) in ((TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:15)}(Tuple(1:6 for _ in 1:15))), 2),
                       (TestSpace((a = 1:2, b = 1:3, c = 1:4)), 2), (TestSpace((a = 1:3, b = 1:3, c = 1:3)), 3))
        for goal in (:fast, :balanced, :compact)
            said = recommend(space; strength = t, goal)
            cases = covering(space; strength = t, engine = Auto(; goal))
            ran = [c.engine for c in said.candidates if c.runs]
            @test first.(starts_of(cases)) == ran
            length(ran) == 1 && @test cases.record.ordinary.chose == said.engine
            @test said.sizes.fast === nothing
            said.sizes.balanced === nothing ||
                @test length(covering(space; strength = t, engine = Auto())) <= said.sizes.balanced
        end
    end
    # The bound recommend states, without classifying, is the one generation records.
    rng = Xoshiro(61)
    for _ in 1:60
        k = rand(rng, 2:6)
        domains = Any[Any[1:rand(rng, 1:4)...] for _ in 1:k]
        rand(rng) < 0.4 && push!(domains[rand(rng, 1:k)], Invalid(1))
        rand(rng) < 0.2 && push!(domains[rand(rng, 1:k)], Invalid(2))
        names = Tuple(Symbol(:p, i) for i in 1:k)
        space = TestSpace(NamedTuple{names}(Tuple(domains)))
        t = rand(rng, 1:min(3, k))
        stronger = k > t + 1 && rand(rng) < 0.4 ? [names[2:(t + 2)] => t + 1] : Pair[]
        said = recommend(space; strength = t, stronger)
        cases = covering(space; strength = t, stronger)
        @test said.lower_bound == cases.record.lower_bound
        @test said.proof == cases.record.proof
    end
    # Negative must-include rows are the negative sub-requests' own (§10.6), so
    # recommend plans from the ordinary request, as Auto does, and counts them
    # among the must-include rows it shows. Every row Invalid in `a`: the
    # catalog's array meets the bound, so Auto runs it alone; and above the
    # threshold the catalog alone, not IPOG.
    invalid = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3))
    doms = Any[1:4 for _ in 1:40]
    doms[1] = [1, 2, 3, 4, Invalid(0)]
    wide = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:40)}(Tuple(doms)))
    for (space, t, must) in ((invalid, 2, [(a = Invalid(0), b = 1, c = 1, d = 1)]), (wide, 3, [(p1 = Invalid(0),)]))
        said = recommend(space; strength = t, must_include = must)
        cases = covering(space; strength = t, must_include = must, engine = Auto())
        @test first.(starts_of(cases)) == [c.engine for c in said.candidates if c.runs] == ["Construction()"]
        @test said.engine == cases.record.ordinary.chose == "Construction()" && said.n_must_include == 1
        @test fit(Construction(), Profile(Request(space; strength = t, must_include = must))).kind === :exact
        @test !catalog_of(cases).seeded && cases[1][first(keys(must[1]))] == Invalid(0)
    end
    # Past the reducer's caps, `:compact` returns the start as it is, and says so.
    seventeen = TestSpace([Symbol(:x, i) for i in 1:17], [1:3 for _ in 1:17], Constraint[], 10^5)
    said = recommend(seventeen; strength = 7, goal = :compact)   # 42,532,776 combinations, above 2^25
    @test said.engine == "IPOG()" &&
          "goal = :compact leaves the start it keeps unreduced: the coverage index would hold 42532776 " *
          "combinations, above Compact's 33554432" in said.notes
    six = Profile(Request(seventeen; strength = 6))   # 9,022,104 combinations, below 2^25
    @test UnitTestDesign._auto_label(_auto_plan(Auto(goal = :compact), six), six) == "Compact(IPOG())"
    square = TestSpace([:a, :b], [1:256, 1:256], Constraint[], 10^5)   # the catalog's 65,536 rows, above 65,535
    said = recommend(square; goal = :compact)
    cases = all_pairs(square; engine = Auto(goal = :compact))
    @test said.engine == cases.record.ordinary.chose == "Construction()" && cases.record.ordinary.reducer.stop === :rows_cap
    @test any(startswith("goal = :compact leaves the start it keeps unreduced: the catalog's array has 65536 rows"),
              said.notes)
    @test recommend(fill(1:3, 4)...; goal = :compact).engine == "Compact(Construction())"
    # Above the threshold :balanced may build the catalog's array alone, which :fast's note qualifies.
    @test any(startswith("goal = :fast is IPOG alone; goal = :balanced builds only the catalog's array here"),
              recommend(wide; strength = 3, goal = :fast).notes)
    # With rules or must-include rows the bound waits for generation.
    @test recommend((a = 1:3, b = 1:3); constraints = [forbid((a = 1, b = 1))]).lower_bound === nothing
    @test recommend((a = 1:3, b = 1:3); must_include = [(a = 1,)]).lower_bound === nothing
    # Notes: whole-case rules (STUDY.md), :fast leaning toward :balanced (D8).
    whole = recommend((a = 1:3, b = 1:3, c = 1:2); constraints = [forbid(row -> row.a == 1 && row.b == 2)])
    @test "1 whole-case rule: generation checks it only on complete rows; declare its scope if it reads fewer fields" in
          whole.notes
    @test any(startswith("goal = :fast is IPOG alone"), recommend(fill(1:2, 8)...; goal = :fast).notes)
    @test_throws "goal is :fast, :balanced or :compact" recommend(1:2, 1:3; goal = :fastest)
    @test_throws ArgumentError recommend(1:2, 1:3; strength = 3)
end


@testitem "design_sizes: a vector of engines, and a refusal as a row's status (§6.1)" setup=[AutoSetup] begin
    space = TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:3))
    t = design_sizes(space; engine = [IPOG(), Construction(), Auto(goal = :compact)])
    @test t.engines == ["IPOG()", "Construction()", "Auto(goal = :compact)"]
    covering_rows = [r for r in t.rows if r.kind === :covering]
    @test [(r.level, r.engine) for r in covering_rows] ==
          [(s, e) for s in 1:3 for e in t.engines]
    @test all(r -> r.engine === nothing, (r for r in t.rows if r.kind !== :covering))
    # Each engine's row is its own call's count (IPOG's 10 at 0ce33a4, the catalog's 9 and Auto's 9).
    @test [r.cases for r in covering_rows if r.level == 2] ==
          [length(covering(space; strength = 2, engine)) for engine in (IPOG(), Construction(), Auto(goal = :compact))]
    text = sprint(show, MIME"text/plain"(), t)
    @test startswith(text, "strategy        engine                 cases")
    @test endswith(text, "case counts are the rows each strategy produced with each engine, not lower bounds")
    mixed = design_sizes((a = 1:3, b = 1:2, c = 1:4, d = 1:2); engine = [IPOG(), Construction()])
    refused = [r for r in mixed.rows if r.engine == "Construction()" && r.level == 2]
    @test only(refused).status === :unsupported && only(refused).cases === nothing
    @test startswith(only(refused).message, "mixed value counts on 4 parameters")
    # One engine: the table as before.
    one = design_sizes(space)
    @test one.engines == ["IPOG()"] && one.engine === :IPOG
    @test startswith(sprint(show, MIME"text/plain"(), one), "strategy        cases   share  pairs  triples")
    @test_throws ArgumentError design_sizes(space; engine = CoveringEngine[])
    @test_throws "`engine` is a covering engine" design_sizes(space; engine = [IPOG(), :gnd])
end


@testitem "Construction above strength 3 offers only arrays at the lower bound (p2 judgment call 4)" setup=[AutoSetup] begin
    uniform(k, v) = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
    # A fused Bush array (619 rows for 6 binary parameters at strength 4) is refused, by name.
    f = fit(Construction(), Profile(Request(uniform(6, 2); strength = 4)))
    @test f.kind === :unsupported
    @test f.reason == "the catalog's array for 6 parameters of 2 values at strength 4 (Bush at 5, fused 3 times) " *
                      "has 619 rows, above the lower bound of 16; above strength 3 the catalog offers only arrays " *
                      "at the lower bound"
    @test_throws "Construction() does not cover this request: the catalog's array for 6 parameters" covering(
        uniform(6, 2); strength = 4, engine = Construction())
    @test occursin("IPOG() or Auto() covers any request",
                   sprint(showerror, try covering(uniform(6, 2); strength = 4, engine = Construction()) catch e; e end))
    # The unfused Bush array and the zero-sum array meet the bound and are offered.
    for (k, v, t) in ((6, 5, 4), (5, 3, 4), (6, 2, 5))
        cases = covering(uniform(k, v); strength = t, engine = Construction())
        @test length(cases) == v^t && cases.record.minimal && cases.record.ordinary.catalog.orthogonal
    end
    # Auto then takes IPOG where the catalog refuses.
    @test covering(uniform(6, 2); strength = 4, engine = Auto()) == covering(uniform(6, 2); strength = 4)
end


@testitem "engines named in messages: covering engines generally, and IPOG() or Auto() for a refusal" setup=[AutoSetup] begin
    message(f) = try f(); "" catch err; sprint(showerror, err) end
    @test occursin("`engine` is a covering engine such as IPOG(), Construction(), Compact(IPOG()) or Auto(); got :ipog",
                   message(() -> all_pairs(1:2, 1:3; engine = :ipog)))
    m = message(() -> all_pairs((a = 1:2, b = 1:3, c = 1:4, d = 1:2); engine = Compact(Construction())))
    @test startswith(m, "ArgumentError: Compact(Construction(); seed = 0, effort = 1) does not cover this request: mixed")
    @test endswith(m, "; IPOG() or Auto() covers any request")
end


@testitem "the registry holds Auto's pipelines, which the oracle loops check (§4.2)" setup=[AutoSetup] begin
    names = first.(_engine_registry())
    @test "Auto()" in names && "Auto(goal = :compact)" in names
    @test _engine_registry(5)[findfirst(==("Auto(goal = :compact)"), names)].second.seed == 5
end


@testitem "the lower bound: an independent brute force with negative must-include rows and several Invalid values (§4.1, §8.7)" begin
    # The exhaustive test above makes ordinary must-include rows and at most one
    # Invalid value. This one adds what it leaves out: negative must-include
    # rows, complete and partial; two Invalid values in a parameter; Invalid
    # values in two parameters; `stronger` groups that hold an invalid
    # parameter, at base strength 1 too; duplicated must-include rows; and rules
    # that read the invalid parameter. It computes rows, targets and validity
    # itself from the contract's definitions (§1, §5.5, §5.7, §5.9, §6.1–§6.4,
    # §10.5, §10.6, §11.8), with forbidden pairs as the only rules, and never
    # the package's classification. For each engine: the bound is at most the
    # exhaustive minimum, the minimum at most the rows, the required counts
    # agree, and "minimal" holds only at the minimum.
    using Random: Xoshiro
    subsets(xs, s) = s == 0 ? [Int[]] : s > length(xs) ? Vector{Int}[] :
                     [[x; rest] for (i, x) in enumerate(xs) for rest in subsets(xs[(i + 1):end], s - 1)]
    isinv(x) = x isa Invalid
    # A rule (scope, values) forbids the rows that hold `values` on `scope`; a
    # rule that reads a row's invalid parameter doesn't apply to it (§5.5).
    function valid(row, rules)
        count(isinv, row) > 1 && return false
        p = something(findfirst(isinv, row), 0)
        return !any(((scope, vals),) -> !(p in scope) && all(row[scope[i]] == vals[i] for i in eachindex(scope)), rules)
    end
    holds(row, t) = all(row[i] == v for (i, v) in t)   # a target or a must-include row: index => value pairs
    "The fewest rows of `pool` that hold every target, by branch and bound; `nothing` if one is in no row."
    function fewest(pool, targets)
        isempty(targets) && return 0
        options = [[j for j in eachindex(pool) if holds(pool[j], t)] for t in targets]
        any(isempty, options) && return nothing
        covers = [BitSet(i for i in eachindex(targets) if holds(pool[j], targets[i])) for j in eachindex(pool)]
        most = maximum(length, covers)
        best = Ref(length(targets))
        function search(uncovered::BitSet, depth::Int)
            isempty(uncovered) && return (best[] = min(best[], depth); nothing)
            depth + cld(length(uncovered), most) >= best[] && return nothing
            i = argmin(i -> length(options[i]), collect(uncovered))
            for j in options[i]
                search(setdiff(uncovered, covers[j]), depth + 1)
            end
            return nothing
        end
        search(BitSet(eachindex(targets)), 0)
        return best[]
    end
    "The fewest rows, given the must-include rows `must` that hold the targets' kind, each completed in `pool`."
    function fewest_with(pool, targets, must)
        best = typemax(Int)
        for chosen in Iterators.product(([r for r in pool if holds(r, m)] for m in must)...)
            extra = fewest(pool, [x for x in targets if !any(r -> holds(r, x), chosen)])
            extra === nothing && error("a required target is in no valid row")
            best = min(best, length(must) + extra)
        end
        return best
    end
    "(ordinary minimum, negative minimum, ordinary required, negative required)."
    function brute_minimum(domains, rules, t, stronger, must)
        k = length(domains)
        ordinary = [filter(!isinv, d) for d in domains]
        groups = [(collect(1:k), t); [(collect(g), s) for (g, s) in stronger]]
        pool = vec([collect(Any, r) for r in Iterators.product(ordinary...) if valid(collect(Any, r), rules)])
        targets = Set{Vector{Pair{Int, Any}}}()
        for (G, s) in groups, S in subsets(G, s), a in Iterators.product((ordinary[i] for i in S)...)
            push!(targets, [S[j] => a[j] for j in eachindex(S)])
        end
        required = [x for x in targets if any(r -> holds(r, x), pool)]
        o = fewest_with(pool, required, [m for m in must if !any(isinv, last.(m))])
        negative, n_negative = 0, 0
        for p in 1:k, v in filter(isinv, domains[p])
            others = [q for q in 1:k if q != p]
            rows = Vector{Any}[]
            for r in Iterators.product((ordinary[q] for q in others)...)
                row = Vector{Any}(undef, k)
                row[others] .= collect(r)
                row[p] = v
                valid(row, rules) && push!(rows, row)
            end
            here = Set{Vector{Pair{Int, Any}}}()
            for (G, s) in groups
                p in G || continue
                for A in subsets([q for q in G if q != p], s - 1), a in Iterators.product((ordinary[i] for i in A)...)
                    push!(here, sort([Pair{Int, Any}[A[j] => a[j] for j in eachindex(A)]; p => v]; by = first))
                end
            end
            need = [x for x in here if any(r -> holds(r, x), rows)]
            negative += fewest_with(rows, need, [m for m in must if any(((i, x),) -> i == p && x === v, m)])
            n_negative += length(need)
        end
        return o, negative, length(required), n_negative
    end
    function random_case(rng)
        while true
            k = rand(rng, 2:4)
            arity = rand(rng, 1:3, k)
            prod(arity) <= 27 || continue
            domains = Any[Any[1:a...] for a in arity]
            for _ in 1:rand(rng, 0:2)
                p = rand(rng, 1:k)
                for x in (Invalid(0), Invalid(1))[1:rand(rng, 1:2)]
                    x in domains[p] || push!(domains[p], x)
                end
            end
            rules = Tuple{Vector{Int}, Vector{Any}}[]
            for _ in 1:rand(rng, 0:2)
                a, b = rand(rng, 1:k), rand(rng, 1:k)
                a == b || push!(rules, ([a, b], Any[rand(rng, 1:arity[a]), rand(rng, 1:arity[b])]))
            end
            t = rand(rng, 1:min(3, k))
            stronger = Pair{Vector{Int}, Int}[]
            if k > t && rand(rng) < 0.4
                s = rand(rng, (t + 1):k)
                g = sort(sortperm(rand(rng, k))[1:rand(rng, s:k)])
                push!(stronger, g => s)
            end
            ordinary = [filter(!isinv, d) for d in domains]
            pool = [collect(Any, r) for r in Iterators.product(ordinary...) if valid(collect(Any, r), rules)]
            isempty(pool) && continue
            must = Vector{Vector{Pair{Int, Any}}}()
            for _ in 1:rand(rng, 0:3)
                if rand(rng) < 0.5 && any(d -> any(isinv, d), domains)
                    p = rand(rng, [i for i in 1:k if any(isinv, domains[i])])
                    v = rand(rng, filter(isinv, domains[p]))
                    others = [q for q in 1:k if q != p]
                    rows = Vector{Any}[]
                    for r in Iterators.product((ordinary[q] for q in others)...)
                        row = Vector{Any}(undef, k)
                        row[others] .= collect(r)
                        row[p] = v
                        valid(row, rules) && push!(rows, row)
                    end
                    isempty(rows) && continue
                    row = rand(rng, rows)
                    keep = sort(unique([p; [i for i in others if rand(rng) < 0.6]]))
                else
                    row = rand(rng, pool)
                    keep = [i for i in 1:k if rand(rng) < 0.7]
                    isempty(keep) && (keep = [1])
                end
                push!(must, Pair{Int, Any}[i => row[i] for i in keep])
                rand(rng) < 0.2 && push!(must, copy(must[end]))   # a duplicate
            end
            return domains, rules, t, stronger, must
        end
    end
    seen = Dict(k => 0 for k in (:negative_must, :partial_negative_must, :two_invalid_parameters, :two_invalid_values,
                                  :group_holds_invalid, :strength1_group_holds_invalid, :rule_reads_invalid,
                                  :duplicate_must))
    let rng = Xoshiro(20261004), checked = 0, claims = 0
        for trial in 1:100
            domains, rules, t, stronger, must = random_case(rng)
            names = Tuple(Symbol(:p, i) for i in eachindex(domains))
            space = TestSpace(NamedTuple{names}(Tuple(domains));
                              constraints = [forbid(NamedTuple{Tuple(names[s])}(Tuple(v))) for (s, v) in rules])
            must_include = [NamedTuple{Tuple(names[first.(m)])}(Tuple(last.(m))) for m in must]
            groups = [Tuple(names[g]) => s for (g, s) in stronger]
            o, n, n_required, n_negative = brute_minimum(domains, rules, t, stronger, must)
            holds_invalid(g) = any(i -> any(isinv, domains[i]), g)
            negative_must = [m for m in must if any(isinv, last.(m))]
            seen[:negative_must] += !isempty(negative_must)
            seen[:partial_negative_must] += any(m -> length(m) < length(domains), negative_must)
            seen[:two_invalid_parameters] += count(d -> any(isinv, d), domains) >= 2
            seen[:two_invalid_values] += any(d -> count(isinv, d) >= 2, domains)
            seen[:group_holds_invalid] += any(((g, s),) -> holds_invalid(g), stronger)
            seen[:strength1_group_holds_invalid] += t == 1 && any(((g, s),) -> holds_invalid(g), stronger)
            seen[:rule_reads_invalid] += any(((scope, v),) -> holds_invalid(scope), rules)
            seen[:duplicate_must] += !allunique(must)
            for engine in (IPOG(), Auto(), Auto(goal = :compact), GND(), Compact(IPOG()))
                cases = covering(space; strength = t, stronger = groups, must_include, engine)
                b = cases.record.lower_bound
                checked += 1
                @test b <= o + n <= length(cases)
                @test (cases.required, cases.negative_required) == (n_required, n_negative)
                cases.record.minimal && (claims += 1; @test length(cases) == o + n)
            end
        end
        @test checked == 500 && claims > 100
    end
    @test all(>(0), values(seen))   # every feature above came up
end
