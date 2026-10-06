using Test
using TestItemRunner

# IPOG's core that scores by lookup (plan §5.5, Phase 4; src/ipog_core.jl), the
# engine behind `IPOG()` since it replaced the classic `ipog` and the general
# `ipog_multi_way` (decision D2). `IPOG()` runs the members `_IPOG_MEMBERS` and
# keeps the smallest design; the internal engine `_IPOGLookup` runs any member,
# so that each is tested here. The oracle loops of test_random_problems.jl run
# `IPOG()` through the registry, test_ipog.jl has IPOG's fixtures,
# and test_stability.jl guards the core's loops. Every design is certified
# (`generate`, contract §1.21) and checked by the independent oracle
# (test/checker.jl).

@testsnippet LookupSetup begin
    using UnitTestDesign: Request, Design, generate, to_cases, classify_targets, RequiredTargets, Profile,
        _Classified, _IPOGLookup, _IPOGPlan, _prepare, _execute, _lookup_steps, _lookup_cover, _lookup_complete,
        ipog_order, validate_design, dead, nrequired, _with_must_include, isconstrained, full_strength_rows,
        _TIEBREAKS, _VERTICALS, _engine_config, _engine_label, engine_record, fit, _fallback, _ipog_members,
        _IPOG_MEMBERS, _engine_registry
    const LOOKUP = _IPOGLookup()

    "A space over parameters p1, p2, … with values 1:arity[i], so value positions are values."
    positional(arity; constraints = Constraint[]) =
        TestSpace((Symbol(:p, i) => collect(1:a) for (i, a) in enumerate(arity))...; constraints)

    "The rows of `engine` for `request`, as a matrix of value positions, certified by `generate`."
    rows_of(engine, request) = generate(engine, request).matrix

    "A rule over p1 and p2 that excludes nothing: the request is constrained, and `dead` is always false."
    noop() = forbid((a, b) -> false, :p1, :p2)

    "`IPOG()`, then each member it runs, alone (`_ipog_members`, in order)."
    ipog_and_members() = Any[IPOG(); [_IPOGLookup(; tiebreak, vertical) for (tiebreak, vertical) in _ipog_members()]]

    "The lookup core's run on `request`'s targets with the predicate `isdead`, from the steps up."
    function lookup_rows(request, isdead; tiebreak = :lowest, vertical = :support, seeds = request.must_include)
        targets = _Classified(request).targets
        steps = _lookup_steps(targets, request.arity, ipog_order(request.arity, request.groups))
        return _lookup_cover(steps, targets, isdead, seeds; tiebreak, vertical)
    end
end


@testitem "lookup core: IPOG()'s plan, and an engine for any member, with its configuration and fallback (§4.2)" setup=[LookupSetup] begin
    @test LOOKUP.tiebreak === (:lowest,) && LOOKUP.vertical === (:support,)
    @test [only(_IPOGLookup(; tiebreak).tiebreak) for tiebreak in _TIEBREAKS] == collect(_TIEBREAKS)
    @test [only(_IPOGLookup(; vertical).vertical) for vertical in _VERTICALS] == collect(_VERTICALS)
    for bad in (:random, "lowest", (), (:lowest, :lowest), [:lowest], (:lowest, 1))
        @test_throws ArgumentError _IPOGLookup(tiebreak = bad)
    end
    @test_throws ArgumentError _IPOGLookup(vertical = :row)
    # The call in the configuration makes the same engine in any module that loads the package.
    for tiebreak in (_TIEBREAKS..., (:lowest, :rotate)), vertical in (_VERTICALS..., _VERTICALS)
        engine = _IPOGLookup(; tiebreak, vertical)
        config = _engine_config(engine)
        text(x) = x isa Symbol ? repr(x) : "(" * join(repr.(x), ", ") * ")"
        @test config.call == "UnitTestDesign._IPOGLookup(tiebreak = $(text(tiebreak)), vertical = $(text(vertical)))"
        @test Core.eval(@__MODULE__, Meta.parse(config.call)) === engine
        @test config.name === :IPOGLookup && config.seed === nothing && !config.randomized
        @test config.settings == (; tiebreak, vertical)
    end
    @test _fallback(LOOKUP) === LOOKUP
    # The plan is read from the profile: the order IPOG uses, whether there are rules, and the path.
    request = Request(positional([2, 3, 4, 2]; constraints = [forbid((p1 = 1, p2 = 1))]); stronger = [(:p1, :p2, :p4) => 3])
    plan = _prepare(_IPOGLookup(tiebreak = :rotate), Profile(request))
    @test plan isa _IPOGPlan{_IPOGLookup} && plan.fit.kind === :native
    @test plan.order == ipog_order(request.arity, request.groups) && plan.rules && plan.path === :lookup
    @test plan.members == [(:rotate, :support)]
    several = _prepare(_IPOGLookup(tiebreak = (:lowest, :rotate), vertical = (:support, :value)), Profile(request))
    @test several.members == [(:lowest, :support), (:lowest, :value), (:rotate, :support), (:rotate, :value)]
    full = _prepare(LOOKUP, Profile(Request(positional([2, 3]))))
    @test full.path === :full_strength && !full.rules
    # IPOG() is the core with its members, in order; the registry lists IPOG(),
    # not a second engine with the same code.
    ipog = _prepare(IPOG(), Profile(request))
    @test ipog isa _IPOGPlan{IPOG} && ipog.members == _ipog_members() &&
          ipog.members == [(t, v) for t in _IPOG_MEMBERS.tiebreak for v in _IPOG_MEMBERS.vertical]
    @test (ipog.order, ipog.rules, ipog.path, ipog.fit) == (plan.order, plan.rules, plan.path, fit(IPOG(), Profile(request)))
    @test !any(e -> e isa _IPOGLookup, last.(_engine_registry()))
    # A design records the engine, its rows, and the member that made them.
    cases = all_pairs(positional([2, 3, 4, 2]); engine = LOOKUP)
    @test cases.engine === :IPOGLookup && iscomplete(coverage(cases))
    @test cases.record.ordinary ==
          (engine = "UnitTestDesign._IPOGLookup(tiebreak = :lowest, vertical = :support)", rows = length(cases),
           member = (tiebreak = :lowest, vertical = :support))
    # At full strength no member runs: every valid row, as `full_strength_rows` lists them.
    whole = all_pairs(positional([2, 3]); engine = _IPOGLookup(tiebreak = :rotate))
    @test whole.record.ordinary.member == (tiebreak = :none, vertical = :none) && length(whole) == 6
    # The steps take the arity of the targets' layout, whose codes the map
    # decodes, and no other: here a support of 2 × 3 values has 6
    # combinations under either order of the arity, but only one maps them.
    two = Request(positional([2, 3]))
    tt = _Classified(two).targets
    @test _lookup_steps(tt, [2, 3], [2, 1]).supports == [1]
    @test_throws ErrorException _lookup_steps(tt, [3, 2], [2, 1])
end


@testitem "lookup core: several rules keep the member with the fewest rows, the first of equals, as IPOG() does (§4.1)" setup=[LookupSetup] begin
    # Probe 08's 8 × 8 and 8 × 32 at strength 2, where the rules differ.
    for arity in (fill(8, 8), fill(32, 8), [5, 4, 4, 3, 3, 2, 2])
        request = Request(positional(arity))
        rows = Dict((t, v) => rows_of(_IPOGLookup(tiebreak = t, vertical = v), request)
                    for t in (:lowest, :rotate) for v in _VERTICALS)
        order = [(:lowest, :support), (:lowest, :value), (:rotate, :support), (:rotate, :value)]
        fewest = minimum(size(rows[m], 2) for m in order)
        first_fewest = order[findfirst(m -> size(rows[m], 2) == fewest, order)]
        engine = _IPOGLookup(tiebreak = (:lowest, :rotate), vertical = (:support, :value))
        design = generate(engine, request)
        @test design.matrix == rows[first_fewest]
        member = design.record.ordinary.member
        @test (member.tiebreak, member.vertical) == first_fewest
        # IPOG() is the same choice over its own members.
        own = Dict(m => rows_of(_IPOGLookup(tiebreak = m[1], vertical = m[2]), request) for m in _ipog_members())
        fewest_own = _ipog_members()[findfirst(m -> size(own[m], 2) == minimum(size.(values(own), 2)), _ipog_members())]
        ipog = generate(IPOG(), request)
        @test ipog.matrix == own[fewest_own]
        @test ipog.record.ordinary.member == (tiebreak = fewest_own[1], vertical = fewest_own[2])
    end
    # One member: it is the one recorded.
    @test generate(LOOKUP, Request(positional(fill(8, 8)))).record.ordinary.member ==
          (tiebreak = :lowest, vertical = :support)
end


@testitem "lookup core: fixtures, each checked by the oracle" setup=[LookupSetup, Checker] begin
    # The fixtures IPOG's tests use (test_ipog.jl): rules with
    # implied targets, greedy dead ends, an empty space, disconnected
    # components, a whole-case rule, overlapping groups, partial must-include
    # rows. Every design is complete by the oracle.
    function check(f; strength = get(f.request, :strength, 2), kwargs...)
        request = Request(test_space(f); strength, kwargs...)
        design = generate(LOOKUP, request)
        cases = to_cases(request, design.matrix)
        result = check_design(cases, f.space; strength, stronger = get(kwargs, :stronger, []))
        return design, cases, result
    end
    for f in (astra_chain, fable_solver, opus_gpu, dead_end_pairwise_1, dead_end_pairwise_2, dead_end_threeway_1,
              dead_end_threeway_2, disconnected_witness, whole_case_connects)
        local design, cases, result = check(f)
        @test complete(result)
        @test design.required == design.covered == result.ordinary.counts.feasible
    end
    design, cases, result = check(astra_chain)
    @test Set(cases) == Set([(A = 1, B = 1, C = 1), (A = 2, B = 2, C = 2)])
    design, cases, result = check(disconnected_unsat)
    @test isempty(cases) && complete(result)
    design, cases, result = check(whole_case_connects)
    @test unique(cases) == [(a = 3, b = 3, c = :y, d = :y, e = 2)]
    f = overlapping_groups
    design, cases, result = check(f; stronger = f.request.stronger)
    @test complete(result) && design.required == 35
    twice, _, _ = check(f; stronger = f.request.stronger_twice)
    @test twice.matrix == design.matrix
    # bench12 at strengths 2 and 3: IPOG's old paths gave 22 and 93 rows.
    for (strength, rows) in ((2, 22), (3, 93))
        local design, cases, result = check(bench12; strength)
        @test complete(result) && abs(length(cases) - rows) <= 3
    end
    # Partial must-include rows: first, set values kept, the only completion found.
    seeds = [(solver = :lu,), (mode = :fast, solver = :none, tol = 1e-3), (solver = :lu,), (mode = :exact,)]
    design, cases, result = check(fable_solver; must_include = seeds)
    @test complete(result) && design.n_must_include == 4
    @test cases[1] == cases[3] == (mode = :exact, solver = :lu, tol = 1e-6)
    @test cases[2] == seeds[2] && cases[4].mode == :exact
end


@testitem "lookup core: full strength is every valid row, and an empty space no row (§7.8, §1.24)" setup=[LookupSetup, Checker] begin
    # At full strength no member runs: every valid row in order, as the
    # old paths gave it (`full_strength_rows`).
    for f in (fable_solver, astra_chain)
        request = Request(test_space(f); strength = length(f.input.names))
        @test rows_of(LOOKUP, request) == rows_of(IPOG(), request) == sortslices(rows_of(IPOG(), request); dims = 2)
        @test to_cases(request, rows_of(IPOG(), request)) == valid_rows(f.space)
    end
    request = Request(test_space(fable_solver); strength = 3, must_include = [(solver = :lu,)])
    @test rows_of(LOOKUP, request) == rows_of(IPOG(), request)
    @test rows_of(LOOKUP, Request(positional([2, 3]))) == [1 1 1 2 2 2; 1 2 3 1 2 3]
    @test size(rows_of(LOOKUP, Request(test_space(disconnected_unsat)))) == (3, 0)
    # Single-valued parameters.
    @test all(==(1), rows_of(LOOKUP, Request(positional([1, 3, 2])))[1, :])
end


@testitem "lookup core: IPOG() on random problems is its members' smallest design, each certified (§5.5)" setup=[UTSetup, LookupSetup, Checker] begin
    using Random
    # The oracle loops' generator (test/random_problems.jl), at strengths 2
    # and 3, each drawn from the stream's start: every member's design is
    # complete by the oracle, and IPOG()'s is the first of its members' with
    # the fewest rows. Against IPOG's old paths on the first 1,000 problems
    # at each strength (Julia 1.13, seed_mod() = 0; p4-core's notes, §3.6, and
    # p4-switch's, §6.2) the default member alone gave totals 0.13% and 0.22%
    # below theirs, and IPOG() 3.29% and 3.22% below, with more rows at 2 and
    # 58 problems, by at most 1 and 4 rows. IPOG()'s total rows on the first
    # 40 problems at each strength are pinned (ipog_stream_rows.jl), so that
    # designs that stay valid but grow are seen.
    include(joinpath(@__DIR__, "ipog_stream_rows.jl"))
    members = _ipog_members()
    for strength in (2, 3)
        rng = Xoshiro(IPOG_STREAM_SEED ⊻ seed_mod())
        for _ in 1:max(IPOG_STREAM_COUNT, round(Int, 100 * test_run_multiplier()))
            problem = random_problem(rng; strength)
            request = Request(test_space(problem.space); strength)
            each = [rows_of(_IPOGLookup(tiebreak = t, vertical = v), request) for (t, v) in members]
            for rows in each
                @test complete(check_design(to_cases(request, rows), problem.space; strength))
            end
            k = argmin([size(rows, 2) for rows in each])   # the first of the fewest
            @test rows_of(IPOG(), request) == each[k]
        end
    end
    # The pin, on this Julia version's stream (seed_mod() = 0); a stream with
    # no entry, another version's or another seed's, is left unpinned.
    digest, totals = ipog_stream(random_problem, test_space; seed = IPOG_STREAM_SEED ⊻ seed_mod())
    pinned = get(IPOG_STREAM_ROWS, digest, nothing)
    if pinned === nothing
        @test_skip totals == pinned
    else
        @test totals == pinned
    end
end


@testitem "lookup core: with `dead` always false, a constrained request gives the unconstrained rows (§5.5)" setup=[UTSetup, LookupSetup] begin
    using Random
    # The gate of Phase 4: the core depends on the rules only through `dead`'s
    # answers. A scoped rule that excludes nothing makes the request
    # constrained, with every target required and `dead` always false: the
    # rows are the unconstrained request's, with must-include rows, partial
    # ones, `stronger` groups and each tie-break rule. IPOG's old paths took
    # the general path for the first and gave 2,131 rows on 8 × 32 where they
    # gave 1,991 without the rule (STUDY.md).
    for engine in (IPOG(), (_IPOGLookup(; tiebreak, vertical) for tiebreak in _TIEBREAKS, vertical in _VERTICALS)...)
        @test rows_of(engine, Request(positional(fill(32, 8)))) ==
              rows_of(engine, Request(positional(fill(32, 8); constraints = [noop()])))
    end
    rng = Xoshiro(0x2026_1005_0005 ⊻ seed_mod())
    for _ in 1:40
        k = rand(rng, 3:7)
        arity = rand(rng, 2:5, k)
        strength = rand(rng, 1:min(3, k - 1))
        extra = []
        rand(rng, Bool) && push!(extra, :stronger => [Tuple(Symbol(:p, i) for i in 1:min(k, strength + 2)) => strength + 1])
        rand(rng, Bool) && push!(extra, :must_include => [(p1 = 1,), Tuple(rand(rng, 1:a) for a in arity)])
        free = Request(positional(arity); strength, extra...)
        ruled = Request(positional(arity; constraints = [noop()]); strength, extra...)
        @test isconstrained(ruled) && !isconstrained(free)
        tiebreak, vertical = rand(rng, _TIEBREAKS), rand(rng, _VERTICALS)
        @test rows_of(_IPOGLookup(; tiebreak, vertical), ruled) == rows_of(_IPOGLookup(; tiebreak, vertical), free)
        # Directly: the same targets, a predicate that is asked and always says false.
        asked = Ref(0)
        @test lookup_rows(ruled, row -> (asked[] += 1; false); tiebreak, vertical) ==
              lookup_rows(ruled, Returns(false); tiebreak, vertical) == lookup_rows(free, Returns(false); tiebreak, vertical)
        @test asked[] > 0
    end
end


@testitem "lookup core: rules, must-include rows, stronger groups and Invalid values, alone and together" setup=[LookupSetup, Checker] begin
    # The `adapted` changes (plan §7.2) on one small space, each alone and in
    # every combination: a rule (with an implied target), a complete and a
    # partial must-include row, an overlapping `stronger` group, and an
    # Invalid value (negative rows). For `IPOG()` and for each member it runs,
    # alone, every design is complete by the oracle, its must-include rows
    # first and unchanged where set; and `IPOG()`'s ordinary rows are those of
    # its first member with the fewest.
    names = [:a, :b, :c, :d, :e]
    domains = [[1, 2, 3], [1, 2], [1, 2, 3], [1, 2], [1, 2, 3, 4]]
    rule = ((:a, :b), (a, b) -> a == 1 && b == 2)
    chain = [((:c, :d), (c, d) -> c == 3 && d == 1), ((:d, :e), (d, e) -> d == 2 && e == 4)]
    complete_row = (a = 2, b = 1, c = 2, d = 2, e = 3)
    partial_row = (c = 3, e = 2)
    as_check(x::Invalid) = CheckInvalid(x.value)
    as_check(x) = x
    checked = Ref(0)
    for with_rule in (false, true), with_complete in (false, true), with_partial in (false, true),
        with_group in (false, true), with_invalid in (false, true)
        doms = [collect(Any, d) for d in domains]
        with_invalid && push!(doms[2], CheckInvalid(0))
        cs = CheckSpace(names, doms, with_rule ? [rule; chain] : [])
        must = NamedTuple[]
        with_complete && push!(must, complete_row)
        with_partial && push!(must, partial_row)
        stronger = with_group ? [(:a, :c, :e) => 3, (:c, :d, :e) => 3] : []
        space = test_space(cs)
        each = [covering(space; strength = 2, stronger, must_include = must, engine) for engine in ipog_and_members()]
        for cases in each
            result = check_design([map(as_check, row) for row in cases], cs; strength = 2, stronger)
            @test complete(result.ordinary) && complete(result.negative)
            @test all(i -> all(k -> cases[i][k] == must[i][k], keys(must[i])), eachindex(must))
            @test cases.n_must_include == length(must)
        end
        # The ordinary rows come first (no must-include row holds the Invalid
        # value); each negative sub-request keeps its own fewest.
        ipog, members = each[1], each[2:end]
        ordinary = [c.record.ordinary.rows for c in members]
        k = argmin(ordinary)   # the first of the fewest
        @test ipog.record.ordinary.member == members[k].record.ordinary.member
        @test collect(ipog)[1:ordinary[k]] == collect(members[k])[1:ordinary[k]]
        checked[] += 1
    end
    @test checked[] == 32
    # At strength 1 with a group holding the Invalid value's parameter, a
    # negative sub-request has base strength 0: only its group carries
    # targets, and its stage names the engine itself (its own fallback).
    doms = [collect(Any, d) for d in domains]
    push!(doms[1], CheckInvalid(0))
    cs = CheckSpace(names, doms, [rule; chain])
    for stronger in ([(:a, :b, :c) => 2], [(:a, :b, :c) => 3, (:b, :d) => 2]),
        must in (NamedTuple[], [(a = CheckInvalid(0),), (b = 2,)]), engine in ipog_and_members()
        space = test_space(cs)
        cases = covering(space; strength = 1, stronger, engine,
                         must_include = [map(x -> x isa CheckInvalid ? Invalid(x.value) : x, m) for m in must])
        result = check_design([map(as_check, row) for row in cases], cs; strength = 1, stronger)
        @test complete(result.ordinary) && complete(result.negative)
        @test all(n -> n.stage.engine == _engine_label(engine), cases.record.negative)
    end
end


@testitem "lookup core: rows stay completable on the study's hard ladders (§1.3, STUDY.md)" setup=[LookupSetup] begin
    # benchmark/scaling's `equality` (neighbours agree), `chain` (no two
    # neighbours both 1), `global_budget` (a whole-case rule on the sum) and
    # all-different families: every placement asks `dead`, so no row is ever
    # left without a valid completion, and `generate` certifies the result;
    # for `IPOG()` and for each member it runs, alone. The budget of 14
    # parameters, where a whole-case rule makes each member's searches take
    # seconds, only through `IPOG()`, which runs all four on it and keeps one.
    ladder(n, v, rules) = positional(fill(v, n); constraints = rules)
    names(n) = [Symbol(:p, i) for i in 1:n]
    for engine in ipog_and_members()
        for n in (8, 16, 32)
            equality = ladder(n, 2, [forbid((a, b) -> a != b, names(n)[i], names(n)[i + 1]) for i in 1:(n - 1)])
            cases = all_pairs(equality; engine)
            @test length(cases) == 2 && iscomplete(coverage(cases))
            chain = ladder(n, 2, [forbid((a, b) -> a == 1 && b == 1, names(n)[i], names(n)[i + 1]) for i in 1:(n - 1)])
            @test iscomplete(coverage(all_pairs(chain; engine)))
            @test iscomplete(coverage(all_triples(chain; engine)))
        end
        for n in (engine isa IPOG ? (6, 10, 14) : (6, 10))
            budget = ladder(n, 3, [forbid(c -> sum(values(c)) > n + n ÷ 2)])
            @test iscomplete(coverage(all_pairs(budget; engine)))
        end
        for q in (4, 5)
            different = ladder(q, q, [forbid((a, b) -> a == b, names(q)[i], names(q)[j]) for i in 1:q for j in (i + 1):q])
            cases = all_pairs(different; engine)
            @test iscomplete(coverage(cases)) && all(c -> allunique(values(c)), cases)
        end
    end
end


@testitem "lookup core: the same rows at every feasibility_limit that succeeds; an exhausted search propagates (§3.8)" setup=[LookupSetup, Checker] begin
    using Random
    # For `IPOG()` and for each member it runs, alone.
    f = limit_exhaustion
    space = test_space(f)
    for engine in ipog_and_members()
        @test_throws ResourceLimitError generate(engine, Request(space; feasibility_limit = f.request.small_limit))
        design = generate(engine, Request(space; feasibility_limit = f.request.default_limit))
        @test design.matrix == fill(4, 8, 1)
        @test generate(engine, Request(space; feasibility_limit = 10 * f.request.default_limit)).matrix == design.matrix
    end
    # Random constrained problems: every limit at which the call succeeds
    # gives the same rows, and `IPOG()` the same member.
    rows_member(engine, request) = (d = generate(engine, request); (d.matrix, d.record.ordinary.member))
    rng = Xoshiro(0x2026_1005_0008)
    for _ in 1:30
        problem = random_problem(rng; strength = 2)
        drawn = test_space(problem.space)
        for engine in ipog_and_members()
            reference = rows_member(engine, Request(drawn; feasibility_limit = 10^8))
            for limit in (3, 30, 300, 10^5)
                got = try
                    rows_member(engine, Request(drawn; feasibility_limit = limit))
                catch err
                    err isa ResourceLimitError || rethrow()
                    nothing
                end
                got === nothing || @test got == reference
            end
        end
    end
    # An error from `dead` mid-run ends the run: nothing catches it.
    request = Request(positional([3, 3, 3, 3]; constraints = [forbid((p1 = 1, p2 = 1))]))
    calls = Ref(0)
    stop(row) = (calls[] += 1) > 5 ? throw(ResourceLimitError("a test's search", 1, :feasibility_limit)) : dead(request, row)
    @test_throws ResourceLimitError lookup_rows(request, stop)
    @test calls[] == 6
end


@testitem "lookup core: each tie-break rule and vertical order is deterministic and certified" setup=[LookupSetup, Checker] begin
    using Random
    rng = Xoshiro(0x2026_1005_0009)
    for _ in 1:20, strength in (2, 3)
        problem = random_problem(rng; strength)
        request = Request(test_space(problem.space); strength)
        for tiebreak in _TIEBREAKS, vertical in _VERTICALS
            engine = _IPOGLookup(; tiebreak, vertical)
            rows = rows_of(engine, request)
            @test complete(check_design(to_cases(request, rows), problem.space; strength))
            @test rows == rows_of(engine, Request(test_space(problem.space); strength))
        end
    end
    # The rules differ: probe 08's 8 × 8 at strength 2.
    sizes = [size(rows_of(_IPOGLookup(; tiebreak, vertical), Request(positional(fill(8, 8)))), 2)
             for tiebreak in _TIEBREAKS, vertical in _VERTICALS]
    @test length(unique(sizes)) > 1
end


@testitem "lookup core: completing must-include rows adds no row and changes no set value" setup=[LookupSetup] begin
    # The first of the two operations Construction's seeded path calls
    # (`_lookup_complete`, the old `_complete_seeds`).
    space = positional(fill(7, 8); constraints = [@forbid(p1 == p2)])
    must = [(p1 = 1, p2 = 2), (p3 = 3, p8 = 4), (p1 = 3, p3 = 3, p5 = 7)]
    request = Request(space; must_include = must)
    targets = _Classified(request).targets
    steps = _lookup_steps(targets, request.arity, ipog_order(request.arity, request.groups))
    isdead(row) = dead(request, row)
    completed = _lookup_complete(steps, targets, isdead, request.must_include)
    @test size(completed) == size(request.must_include)
    @test all(i -> request.must_include[i] == 0 || completed[i] == request.must_include[i], eachindex(completed))
    @test !any(j -> dead(request, completed[:, j]), axes(completed, 2))
    @test count(==(0), completed) < count(==(0), request.must_include)
    # Complete rows: nothing to choose.
    whole = Request(positional(fill(3, 4)); must_include = [(1, 2, 3, 1), (2, 2, 2, 2)])
    wt = _Classified(whole).targets
    @test _lookup_complete(_lookup_steps(wt, whole.arity, [1, 2, 3, 4]), wt, Returns(false), whole.must_include) ==
          whole.must_include
    # Then the run on the completed rows covers everything, the completed rows first.
    rows = _lookup_cover(steps, targets, isdead, completed)
    @test rows[:, 1:3] == completed
    @test validate_design(_with_must_include(request, completed), rows, targets) == nrequired(targets)
end


@testitem "lookup core: Construction's seeded path is IPOG's members' smallest on the core's two operations" setup=[LookupSetup] begin
    using UnitTestDesign: Construction, _ConstructionPlan, _engine_rows, _allowed_rows, _new_coverage_rows
    # src/construction.jl's `_construction_rows`, written out for one member
    # of IPOG: the steps once (`_lookup_steps`), the completion of partial
    # must-include rows (`_lookup_complete`), and the run that tops up
    # (`_lookup_cover`), both reading the targets from the same steps.
    # `Construction()` runs it for each member `IPOG()` runs and keeps the
    # first with the fewest rows; each member's design is certified.
    function lookup_construction(request; tiebreak, vertical)
        plan = _prepare(Construction(), Profile(request))
        targets = _Classified(request).targets
        f, entry, members = plan.fit, plan.entry, plan.members
        must = request.must_include
        size(must, 2) > 0 && request.strength == length(request.arity) &&
            return full_strength_rows(request, targets), targets
        if members === nothing
            rows = _engine_rows(entry, request.arity)
            f.kind === :exact && return rows, targets
        else
            rows = zeros(Int, length(request.arity), entry.rows)
            rows[members, :] .= _engine_rows(entry, request.arity[members])
        end
        kept = isconstrained(request) ? _allowed_rows(request, rows) : rows
        isdead = isconstrained(request) ? (row -> dead(request, row)) : Returns(false)
        steps = _lookup_steps(targets, request.arity, ipog_order(request.arity, request.groups))
        if size(must, 2) > 0
            partial = _new_coverage_rows(must, kept, targets)
            if any(==(0), must)
                completed = _lookup_complete(steps, targets, isdead, must; tiebreak, vertical)
                fewer = _new_coverage_rows(completed, kept, targets)
                size(fewer, 2) < size(partial, 2) && ((must, partial) = (completed, fewer))
            end
            kept = partial
        end
        return _lookup_cover(steps, targets, isdead, hcat(must, kept); tiebreak, vertical), targets
    end
    space_of(arity; constraints = Constraint[]) = positional(arity; constraints)
    partial(row, keep) = NamedTuple{Tuple(keys(row)[keep])}(Tuple(values(row)[keep]))
    s8 = space_of(fill(7, 8))
    oa = collect(all_pairs(s8; engine = Construction()))
    cut = [partial(r, 1:6) for r in oa]
    # The maintainer's cases (test_construction.jl), rules, a stronger group,
    # strength 3, and the dropped-parameters case.
    cases = [(s8, 2, (; must_include = cut)), (space_of(fill(7, 9)), 2, (; must_include = oa)),
             (space_of(fill(7, 8); constraints = [@forbid(p1 == p2)]), 2, (;)),
             (space_of(fill(4, 16)), 2, (; stronger = [(:p1, :p2, :p3, :p4) => 3])),
             (space_of(fill(3, 12)), 3, (; must_include = [(p1 = 1, p2 = 2), (p5 = 3,)])),
             (space_of(fill(7, 8); constraints = [@forbid(p1 == p2)]), 2,
              (; must_include = [(p1 = 1, p2 = 2, p5 = 3, p7 = 4), (p2 = 5, p4 = 1, p6 = 6, p8 = 2)])),
             (s8, 2, (; must_include = [partial(r, setdiff(1:8, [mod1(j, 8), mod1(j + 3, 8)])) for (j, r) in enumerate(oa)]))]
    for (space, strength, extra) in cases
        request = Request(space; strength, extra...)
        each = map(_ipog_members()) do (tiebreak, vertical)
            rows, targets = lookup_construction(request; tiebreak, vertical)
            @test validate_design(request, rows, targets) == nrequired(targets)
            rows
        end
        @test generate(Construction(), request).matrix == each[argmin(size.(each, 2))]
    end
    # The cut 8 × 7 array: the completed rows hold every pair, so no catalog row is kept.
    @test length(all_pairs(s8; engine = Construction(), must_include = cut)) == 49
end


@testitem "lookup core: the same rows in another process and on another Julia version (§9.1, §9.4)" setup=[LookupSetup] begin
    # ipog_core_rows.txt holds the rows of the fixed requests of
    # ipog_core_requests.jl, written by a separate process on Julia 1.13 (that
    # file says how). The rows here must be the same, line for line, on every
    # Julia version the package supports: the core uses no randomness, no
    # hashing order and no clock. Rows are compared as text, since a matrix's
    # `hash` differs between Julia 1.10 and 1.13.
    include(joinpath(@__DIR__, "ipog_core_requests.jl"))
    expected = readlines(joinpath(@__DIR__, "ipog_core_rows.txt"))
    @test lookup_rows_text() == expected
end
