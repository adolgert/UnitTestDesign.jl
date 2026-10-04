using Test
using TestItemRunner

# `Compact`, the row reducer (src/compact.jl; plan §5.3), and `_compact`, its
# core, which reduces any start design. The registry's oracle loops
# (test_random_problems.jl) check `Compact(IPOG())` on random constrained
# problems at strengths 2 and 3 and with Invalid values; the items here add
# must-include rows, `stronger` groups, every rule kind, the reducer's own
# promises (never more rows, valid rows at every step, no feasibility search,
# the same rows for a seed and for any `feasibility_limit`), its stops, and
# its record. The inference and allocation guards are in test_stability.jl.

@testsnippet CompactSetup begin
    using Random: Xoshiro
    using Base.CoreLogging: with_logger, NullLogger
    using UnitTestDesign: Compact, CoveringEngine, EngineRecord, Fit, Profile, Request, RequiredTargets,
                          NegativeProjection, classify_targets, cover_ordinary, engine_record, fit, generate,
                          validate_design, _compact, _negative_request, _fallback, _randomized, _engine_phrase,
                          _seed_text, _engine_registry, _COMPACT_MAX_COMBINATIONS

    "A request's required targets, through the targets interface, and IPOG's rows for it."
    function start_of(request; engine = IPOG())
        required, _ = classify_targets(request)
        targets = RequiredTargets(request, required)
        return required, targets, cover_ordinary(engine, request, targets)
    end

    """
    A random space of 3 to 7 parameters with 1 to 5 values: sometimes an
    Invalid value, and rules of every kind: tabulated (scoped, small), lazy
    (scoped, past `tabulation_limit`) and whole-case.
    """
    function random_space(rng)
        n = rand(rng, 3:7)
        domains = [Any[1:rand(rng, 1:5)...] for _ in 1:n]
        rand(rng) < 0.25 && push!(domains[rand(rng, 1:n)], Invalid(0))
        names = [Symbol(:p, i) for i in 1:n]
        rules = Constraint[]
        rand(rng) < 0.6 && push!(rules, forbid((a, b) -> a == 1 && b == 1, names[1], names[2]))
        rand(rng) < 0.4 && push!(rules, forbid((a, b, c) -> a + b == c, names[1], names[2], names[3]))
        rand(rng) < 0.3 && push!(rules, forbid(row -> row[end] == 2 && row[1] == 2))
        limit = rand(rng, (8, 100_000))   # at 8 most scoped rules are lazy, and warn so
        return with_logger(NullLogger()) do
            TestSpace(NamedTuple{Tuple(names)}(Tuple(domains)); constraints = rules, tabulation_limit = limit)
        end
    end

    "Up to two random valid must-include rows of `request`, some partial: IPOG's rows with entries cleared."
    function random_must_include(rng, space, strength)
        rows = collect(covering(space; strength))
        isempty(rows) && return []
        picked = [rows[rand(rng, eachindex(rows))] for _ in 1:rand(rng, 0:2)]
        return [rand(rng) < 0.5 ? row : NamedTuple{keys(row)[1:end - 1]}(Tuple(row)[1:end - 1])
                for row in picked]
    end
end


@testitem "compact: a wrapper engine with a record, a fit, a fallback and a seed (§4.2, §5.3)" setup=[CompactSetup] begin
    engine = Compact(IPOG())
    @test engine isa CoveringEngine && engine.seed == 0 && engine.effort == 1
    @test repr(Compact(GND(seed = 3); seed = 2, effort = 5)) == "Compact($(repr(GND(seed = 3))); seed = 2, effort = 5)"
    @test repr(engine) == "Compact($(repr(IPOG())); seed = 0, effort = 1)"
    # Arguments are checked as GND's are (§9.5).
    @test_throws ArgumentError Compact(IPOG(); seed = -1)
    @test_throws ArgumentError Compact(IPOG(); effort = 0)
    @test_throws ArgumentError Compact(IPOG(); effort = 1.5)
    @test_throws ArgumentError Compact(IPOG(); seed = true)
    @test_throws MethodError Compact(:IPOG)
    # The record names the reducer, its seed and its settings, the inner engine's record among them.
    record = engine_record(Compact(GND(seed = 4); seed = 9, effort = 2))
    @test record.name === :Compact && record.seed == 9
    @test first.(record.parameters) == [:inner, :effort]
    inner = record.parameters[1].second
    @test inner isa EngineRecord && inner.name === :GND && inner.seed == 4
    @test record.parameters[2].second == 2
    @test _randomized(record)
    @test _engine_phrase(EngineRecord(:Compact, 9)) == "Compact seed 9"
    @test _seed_text(EngineRecord(:Compact, 9)) ==
          "seed: 9 (Compact(inner; seed = 9) with the same inner engine and effort repeats these cases)"
    @test _seed_text(EngineRecord(:GND, 3)) == "seed: 3 (GND(seed = 3) repeats these cases)"   # unchanged
    # Results show it through the public entry points.
    space = TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:2, e = 1:2))
    cases = all_pairs(space; engine)
    @test cases.engine === :Compact && cases.seed == 0
    @test occursin("Compact seed 0", sprint(show, MIME"text/plain"(), cases))
    @test occursin("Compact(inner; seed = 0) with the same inner engine and effort repeats these cases",
                   sprint(show, MIME"text/plain"(), report(cases)))
    @test length(cases) <= length(all_pairs(space))
    @test design_sizes(space; engine) isa DesignSizes
    # The notes say what the reducer did; the harness records them (benchmark/scaling/metrics.jl).
    @test cases.notes.reducer_start == length(all_pairs(space)) && cases.notes.reducer_rows == length(cases)
    @test cases.notes.reducer_stop in (:bound, :budget, :work)
    @test isempty(all_pairs(space).notes)
    # Its fit is the inner engine's, reduced; past the index's cap, unreduced.
    profile = Profile(Request(space))
    f = fit(engine, profile)
    @test f.kind === :native && occursin("reduced", f.reason)
    # 17 four-valued parameters at strength 6: 12,376 supports of 4,096 combinations.
    wide = Profile(Request(TestSpace([Symbol(:x, i) for i in 1:17], [1:4 for _ in 1:17], Constraint[], 10^5);
                           strength = 6))
    @test wide.targets > _COMPACT_MAX_COMBINATIONS
    @test fit(engine, wide).kind === :native && occursin("unreduced", fit(engine, wide).reason)
    # What its inner engine refuses goes to the inner engine's fallback, reduced the same way.
    @test _fallback(Compact(GND(); seed = 3, effort = 2)) === Compact(IPOG(); seed = 3, effort = 2)
    # The registry runs it, with the problem's seed.
    registry = Dict(_engine_registry(5))
    @test registry["Compact(IPOG())"] === Compact(IPOG(); seed = 5)
end


@testitem "compact: fewer rows, must-include rows first, every step valid, and no feasibility search (§5.3)" setup=[CompactSetup] begin
    # On random requests with every rule kind, stronger groups and
    # must-include rows: the reduced design never has more rows than the
    # start, keeps the start's must-include rows first and unchanged, and is
    # certified. In the test mode (`check = true`) every changed row is checked
    # against every rule and every complete design is recounted. The request's
    # feasibility search answers no question for the reducer (its query and
    # node counts don't move), while its rule checks are counted.
    rng = Xoshiro(0x2026_1004_02)
    reduced = Ref(0)
    for _ in 1:40
        space = random_space(rng)
        n = length(space.names)
        strength = rand(rng, 1:min(3, n))
        stronger = strength < n && rand(rng) < 0.3 ? [Tuple(space.names[2:end]) => strength + 1] : []
        must_include = random_must_include(rng, space, strength)
        request = try
            Request(space; strength, stronger, must_include)
        catch err
            err isa ArgumentError || rethrow()   # a partial row that the rules can't complete
            continue
        end
        # Ordinary rows only, as `generate` hands an engine (the negative rows are below).
        any(row -> any(i -> row[i] > request.arity[i], eachindex(row)), eachcol(request.must_include)) && continue
        required, targets, start = start_of(request)
        stats = request.feasibility.stats
        queries, nodes, checks = stats.queries, stats.total_nodes, stats.evaluations
        matrix, notes = _compact(request, targets, start; seed = rand(rng, 0:9), check = true, budget = 3_000)
        @test stats.queries == queries && stats.total_nodes == nodes
        @test isempty(space.tables) || stats.evaluations >= checks
        @test size(matrix, 2) <= size(start, 2)
        @test notes.reducer_start == size(start, 2) && notes.reducer_rows == size(matrix, 2)
        m = size(request.must_include, 2)
        @test matrix[:, 1:m] == start[:, 1:m]
        @test validate_design(request, matrix, required) == length(required)
        reduced[] += size(matrix, 2) < size(start, 2)
    end
    @test reduced[] > 6
end


@testitem "compact: a negative sub-request is reduced without a feasibility search (§5.3, §4.1)" setup=[CompactSetup] begin
    # cover_negative hands Compact one sub-request per invalid value, at one
    # strength less (invalid.jl). The reducer reduces it like any request.
    rng = Xoshiro(0x2026_1004_03)
    for _ in 1:60
        n = rand(rng, 4:6)
        domains = [Any[1:rand(rng, 2:4)...] for _ in 1:n]
        push!(domains[1], Invalid(:bad))
        names = Tuple(Symbol(:p, i) for i in 1:n)
        rules = Constraint[forbid((a, b) -> a == b, :p2, :p3), forbid(row -> row.p4 == 1 && row.p2 == 2)]
        space = TestSpace(NamedTuple{names}(Tuple(domains)); constraints = rules)
        request = Request(space; strength = 3, stronger = rand(rng) < 0.5 ? [(:p1, :p2, :p3, :p4) => 4] : [])
        sub = _negative_request(request, NegativeProjection(space, 1), zeros(Int, n - 1, 0))
        @test sub.strength == 2
        required, targets, start = start_of(sub)
        stats = sub.feasibility.stats
        queries = stats.queries
        matrix, _ = _compact(sub, targets, start; seed = 1, check = true, budget = 2_000)
        @test stats.queries == queries
        @test size(matrix, 2) <= size(start, 2)
        @test validate_design(sub, matrix, required) == length(required)
    end
end


@testitem "compact: the same rows for the same seed and for any feasibility_limit (§9.5, §3.8)" setup=[CompactSetup] begin
    include(joinpath(pkgdir(UnitTestDesign), "benchmark", "fixtures.jl"))
    bench12 = BenchFixtures.test_space(BenchFixtures.bench12)
    for strength in (2, 3)
        a = covering(bench12; strength, engine = Compact(IPOG()))
        b = covering(bench12; strength, engine = Compact(IPOG()))
        @test collect(a) == collect(b)
        ipog = covering(bench12; strength)
        @test length(a) < length(ipog)
        # Another seed is allowed to give other rows; it is certified either way.
        c = covering(bench12; strength, engine = Compact(IPOG(); seed = 1))
        @test iscomplete(coverage(c)) && length(c) <= length(ipog)
        # The smallest limits that still succeed search differently, and give the same rows (§3.8).
        for limit in (20, 1_000, 10^8)
            d = try
                covering(bench12; strength, engine = Compact(IPOG()), feasibility_limit = limit)
            catch err
                err isa ResourceLimitError || rethrow()
                continue
            end
            @test collect(d) == collect(a)
            @test d.required == a.required && d.covered == a.covered && length(d.excluded) == length(a.excluded)
        end
    end
    # The same request and seed give the same rows from a fresh request, call after call.
    space = TestSpace((a = 1:4, b = 1:4, c = 1:3, d = 1:3, e = 1:2, f = 1:2))
    first_rows = generate(Compact(IPOG(); seed = 3), Request(space)).matrix
    @test all(_ -> generate(Compact(IPOG(); seed = 3), Request(space)).matrix == first_rows, 1:3)
end


@testitem "compact: must-include rows, stronger groups and Invalid values pass the oracle (§5.3, §7.4)" setup=[CompactSetup, Checker, UTSetup] begin
    # The registry's oracle loops have no must-include rows or stronger
    # groups, so this loop adds them, with an Invalid value in a third of the
    # problems, and with IPOG or GND as the inner engine: each design must
    # satisfy the independent oracle, keep the must-include rows first and
    # unchanged where they were set, and have no more ordinary rows than its
    # inner engine's.
    as_check(x::Invalid) = CheckInvalid(x.value)
    as_check(x) = x
    rng = Xoshiro(0x2026_1004_04 ⊻ seed_mod())
    inner(index) = isodd(index) ? IPOG() : GND(seed = index)   # Compact(GND()) is not in the registry
    checked = Ref(0)
    n_problems = max(10, round(Int, 16 * test_run_multiplier()))
    for index in 1:n_problems
        strength = rand(rng, 2:3)
        problem = random_problem(rng; strength)
        domains = [collect(Any, d) for d in problem.space.domains]
        invalid = rand(rng) < 0.35
        invalid && push!(domains[rand(rng, eachindex(domains))], CheckInvalid(-1))
        cs = CheckSpace(problem.space.names, domains, problem.space.rules)
        space = test_space(cs)
        n = length(problem.names)
        stronger = strength < n && rand(rng) < 0.6 ?
                   [Tuple(problem.names[sort(unique(rand(rng, 1:n, strength + 2)))]) => strength + 1] : []
        stronger = [g for g in stronger if length(g.first) > strength]
        valid = valid_rows(problem.space)
        must = isempty(valid) ? [] : [valid[rand(rng, eachindex(valid))] for _ in 1:rand(rng, 0:2)]
        must = [rand(rng) < 0.5 ? row : NamedTuple{keys(row)[1:2]}(Tuple(row)[1:2]) for row in must]
        cases = try
            covering(space; strength, stronger, must_include = must, engine = Compact(inner(index); seed = index))
        catch err
            err isa InterruptException && rethrow()
            @error("Compact threw on problem $index", problem, stronger, must, exception = (err, catch_backtrace()))
            @test false
            continue
        end
        rows = collect(cases)
        check = check_design([map(as_check, row) for row in rows], cs; strength, stronger)
        ok = complete(check.ordinary) && (!invalid || complete(check.negative)) &&
             cases.required == check.ordinary.counts.feasible &&
             all(k -> all(name -> rows[k][name] == must[k][name], keys(must[k])), eachindex(must))
        start = covering(space; strength, stronger, must_include = must, engine = inner(index))
        ok &= count(!hasinvalid, rows) <= count(!hasinvalid, collect(start))
        ok || @error("Compact's design fails the oracle", index, problem, stronger, must, check)
        @test ok
        checked[] += ok
    end
    @test checked[] == n_problems
end


@testitem "compact: it stops at the bound, at the must-include rows, at a budget, and past its caps (§5.3)" setup=[CompactSetup] begin
    # At the bound: the most required combinations on one support. 3 × 3 at
    # strength 2 has a bound of 9, which the reducer reaches from IPOG's 9 + k rows.
    space = TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:2, e = 1:2))
    request = Request(space)
    required, targets, start = start_of(request)
    matrix, notes = _compact(request, targets, start)
    @test size(start, 2) > 9 && size(matrix, 2) == 9
    @test notes.reducer_stop === :bound && notes.reducer_bound == 9 && notes.reducer_steps < notes.reducer_budget
    # A start at the bound is returned as it is.
    again, notes = _compact(request, targets, matrix)
    @test again === matrix && notes.reducer_stop === :bound && notes.reducer_steps == 0
    # No budget: the start's rows.
    same, notes = _compact(request, targets, start; budget = 0)
    @test same == start && notes.reducer_stop === :budget
    same, notes = _compact(request, targets, start; work_budget = 0)
    @test same == start && notes.reducer_stop === :work
    # Every row a must-include row: nothing can go.
    named(j) = NamedTuple{Tuple(space.names)}(Tuple(start[:, j]))
    frozen = Request(space; must_include = [named(j) for j in axes(start, 2)])
    required, targets, all_must = start_of(frozen)
    @test size(all_must, 2) == size(start, 2)
    kept, notes = _compact(frozen, targets, all_must)
    @test kept == all_must && notes.reducer_stop === :frozen
    # Must-include rows that cover nearly everything: only the rest can go.
    partly = Request(space; must_include = [named(j) for j in 1:(size(start, 2) - 2)])
    required, targets, mostly = start_of(partly)
    kept, notes = _compact(partly, targets, mostly)
    @test kept[:, 1:(size(start, 2) - 2)] == mostly[:, 1:(size(start, 2) - 2)]
    @test validate_design(partly, kept, required) == length(required)
    # Past the index's cap, or past the rows a count holds, the start comes back unreduced.
    wide = Request(TestSpace([Symbol(:x, i) for i in 1:17], [1:4 for _ in 1:17], Constraint[], 10^5); strength = 6)
    wide_targets = RequiredTargets(wide, first(classify_targets(wide)))
    fake = ones(Int, 17, 3)
    kept, notes = _compact(wide, wide_targets, fake)
    @test kept === fake && notes.reducer_stop === :index_cap && notes.reducer_steps == 0
    many = ones(Int, 5, Int(typemax(UInt16)) + 1)
    kept, notes = _compact(request, RequiredTargets(request, first(classify_targets(request))), many)
    @test kept === many && notes.reducer_stop === :rows_cap
    # A start that leaves a required combination uncovered is an internal error.
    required, targets, start = start_of(request)
    @test_throws ErrorException _compact(request, targets, repeat(start[:, 1:1], 1, 20))
end


@testitem "compact: the core reduces any engine's start, and more effort never ends higher here (§4.1)" setup=[CompactSetup] begin
    # Phase 3's Auto reduces the start that keep-the-smallest chose; `_compact`
    # takes any engine's rows.
    include(joinpath(pkgdir(UnitTestDesign), "benchmark", "fixtures.jl"))
    bench12 = BenchFixtures.test_space(BenchFixtures.bench12)
    request = Request(bench12; strength = 2)
    required, targets, gnd = start_of(request; engine = GND(seed = 2))
    matrix, notes = _compact(request, targets, gnd)
    @test size(matrix, 2) < size(gnd, 2)
    @test validate_design(request, matrix, required) == length(required)
    # bench12 pairwise: 22 IPOG rows to 18 (plan §5.3's gate), at effort 1 and 3.
    _, _, ipog = start_of(request)
    @test size(ipog, 2) == 22
    one = size(first(_compact(request, targets, ipog)), 2)
    three = size(first(_compact(request, targets, ipog; effort = 3)), 2)
    @test one <= 18 && three <= one
end
