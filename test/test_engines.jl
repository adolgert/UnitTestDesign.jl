using Test
using TestItemRunner

# The internal engine protocol (src/engines.jl; plan §4.2): `CoveringEngine`
# with its three methods, the targets interface (`RequiredTargets`), the
# `Profile` that `fit` reads, the fallback for a negative sub-request an engine
# refuses, and the registry the oracle loops of test_random_problems.jl and the
# benchmark harness run. Nothing here is public (decision D7). The inference
# and allocation guards are in test_stability.jl.

@testsnippet EngineSetup begin
    using Random: Xoshiro
    using UnitTestDesign: CoveringEngine, EngineRecord, Fit, Profile, Request, RequiredTargets, TargetList,
                          NegativeProjection, classify_targets, engine_record, fit, cover_ordinary,
                          supports, ncombinations, isrequired, nrequired, nparameters, _engine_for,
                          _engine_registry, _negative_request, _decode!, _randomized, _target_list

    """
    An engine for the tests: IPOG's rows, but it refuses a request below
    strength `least`, and records the strength of each request it covers. It
    defines the three methods a covering engine defines (`CoveringEngine`).
    """
    struct Refusing <: CoveringEngine
        least::Int
        covered::Vector{Int}
    end
    Refusing(least::Int) = Refusing(least, Int[])

    UnitTestDesign.engine_record(::Refusing) = EngineRecord(:Refusing, nothing)
    UnitTestDesign.fit(e::Refusing, p::Profile) =
        p.strength >= e.least ? Fit(:native, "IPOG's rows") : Fit(:unsupported, "strength below $(e.least)")
    function UnitTestDesign.cover_ordinary(e::Refusing, request::Request, targets::RequiredTargets)
        request.strength >= e.least ||
            error("Refusing($(e.least)) was handed a request at strength $(request.strength)")
        push!(e.covered, request.strength)
        return cover_ordinary(IPOG(), request, targets)
    end

    "A random space of 3 to 7 parameters with 1 to 5 values, and sometimes an Invalid value or a rule."
    function random_space(rng)
        n = rand(rng, 3:7)
        domains = [Any[1:rand(rng, 1:5)...] for _ in 1:n]
        rand(rng) < 0.3 && push!(domains[rand(rng, 1:n)], Invalid(0))
        names = [Symbol(:p, i) for i in 1:n]
        rules = Constraint[]
        if rand(rng) < 0.4
            push!(rules, forbid((a, b) -> a == 1 && b == 1, names[1], names[2]))
        end
        return TestSpace(NamedTuple{Tuple(names)}(Tuple(domains)); constraints = rules)
    end

    "Random `stronger` groups for `n` parameters at base `strength`: some overlap, some repeat."
    function random_groups(rng, n, strength)
        groups = Pair{Vector{Int}, Int}[]
        strength < n || return groups
        for _ in 1:rand(rng, 0:4)
            k = rand(rng, (strength + 1):n)
            members = sort!(randperm_prefix(rng, n, k))
            push!(groups, members => rand(rng, (strength + 1):k))
        end
        rand(rng) < 0.3 && !isempty(groups) && push!(groups, first(groups))   # a group listed twice
        return groups
    end

    randperm_prefix(rng, n, k) = sort!(collect(1:n); by = _ -> rand(rng))[1:k]
end


@testitem "engines: IPOG and GND are covering engines, each with a record and a fit (§4.2)" setup=[EngineSetup] begin
    using UnitTestDesign: _engine_phrase, _seed_note, _seed_text, _fallback
    @test IPOG <: CoveringEngine && GND <: CoveringEngine
    # The record keeps what 0.5 recorded: the engine's name and its seed.
    ipog = engine_record(IPOG())
    @test ipog.name === :IPOG && ipog.seed === nothing && ipog.parameters == []
    gnd = engine_record(GND(seed = 7, candidates = 20))
    @test gnd.name === :GND && gnd.seed == 7 && gnd.parameters == [:candidates => 20]
    @test engine_record(GND(rng = Xoshiro(1))).seed === nothing
    @test !_randomized(ipog) && _randomized(gnd)
    @test !_randomized(EngineRecord(:Excursion, nothing)) && !_randomized(EngineRecord(:FullFactorial, nothing))
    # Results show the record as 0.5 showed GND's seed (§1.22, §9.5).
    @test _engine_phrase(EngineRecord(:IPOG, nothing)) == "IPOG"
    @test _engine_phrase(EngineRecord(:GND, 3)) == "GND seed 3"
    @test _engine_phrase(EngineRecord(:GND, nothing)) == "GND, caller's rng"
    @test _seed_note(EngineRecord(:IPOG, nothing)) === nothing
    @test _seed_note(EngineRecord(:GND, 3)) == "GND seed 3"
    @test _seed_note(EngineRecord(:GND, nothing)) == "GND with the caller's rng"
    @test _seed_text(EngineRecord(:IPOG, nothing)) == "seed: none (IPOG uses no randomness)"
    @test _seed_text(EngineRecord(:GND, 3)) == "seed: 3 (GND(seed = 3) repeats these cases)"
    @test _seed_text(EngineRecord(:GND, nothing)) == "seed: none (GND drew from the caller's rng)"
    # Both fit every request natively, and fall back on IPOG, which they never need.
    request = Request(TestSpace((a = [1, 2], b = [1, 2, 3], c = [:x, :y])); strength = 2)
    for engine in (IPOG(), GND())
        f = fit(engine, Profile(request))
        @test f.kind === :native && f.rows === nothing && !isempty(f.reason)
        @test _engine_for(engine, request) === engine
        @test _fallback(engine) == IPOG()
    end
    @test Fit(:exact, "a catalog array"; rows = 9).rows == 9
    @test_throws ArgumentError Fit(:sometimes, "no such kind")
end


@testitem "engines: the registry names every engine the oracle loops run (§4.2, §7.4)" setup=[EngineSetup] begin
    registry = _engine_registry()
    @test registry isa Vector{Pair{String, CoveringEngine}}
    @test first.(registry)[1:2] == ["IPOG()", "GND()"]
    @test "Construction()" in first.(registry)
    @test allunique(first.(registry))
    @test registry[1].second == IPOG()
    # A randomized engine takes the seed; the default is 0 (§9.5).
    @test registry[2].second.seed == 0 && registry[2].second.candidates == 50
    @test _engine_registry(17)[2].second.seed == 17
    @test _engine_registry(17)[1].second == IPOG()
    # Every engine there covers a small request through the public entry point.
    for (name, engine) in registry
        cases = all_pairs(TestSpace((a = [1, 2], b = [:x, :y], c = [true, false])); engine)
        @test iscomplete(coverage(cases))
        @test cases.engine === engine_record(engine).name
    end
end


@testitem "engines: a profile counts the targets as TargetList lists them, without listing them (§4.2)" setup=[EngineSetup] begin
    rng = Xoshiro(0x2026_1004)
    checked = Ref(0)
    for _ in 1:300
        space = random_space(rng)
        n = length(space.names)
        strength = rand(rng, 1:min(3, n))
        stronger = random_groups(rng, n, strength)
        request = Request(space; strength, stronger)
        p = Profile(request)
        @test p.targets == length(TargetList(request))
        @test nparameters(p) == n && p.arity == request.arity && p.strength == strength
        @test p.groups == request.groups && p.groups !== request.groups
        # Each negative sub-request too, whose base strength is one less and may be 0.
        for q in 1:n
            isempty(space.invalid[q]) && continue
            strength > 1 || any(g -> q in g.first, request.groups[2:end]) || continue
            sub = _negative_request(request, NegativeProjection(space, q), zeros(Int, n - 1, 0))
            @test Profile(sub).targets == length(TargetList(sub))
            @test Profile(sub).strength == strength - 1
            checked[] += 1
        end
    end
    @test checked[] > 20
    # Groups at one strength that share a support count it once (§11.8):
    # (1, 2, 3, 4) and (2, 3, 4, 5) at strength 3 share (2, 3, 4), and a group
    # inside another at the same strength shares all of its supports.
    space = TestSpace(NamedTuple{Tuple(Symbol(:p, i) for i in 1:6)}(Tuple(1:(i + 1) for i in 1:6)))
    for stronger in ([(1, 2, 3, 4) => 3, (2, 3, 4, 5) => 3], [(1, 2, 3, 4) => 3, (2, 3, 4, 5) => 3, (1, 2, 3, 5) => 3],
                     [(1, 2, 3) => 3, (1, 2, 3, 4) => 3, (1, 2, 3, 4, 5, 6) => 4])
        request = Request(space; strength = 2, stronger)
        @test Profile(request).targets == length(TargetList(request))
    end
    # A large space without listing a support: C(250, 4) supports of 64^4.
    wide = TestSpace([Symbol(:x, i) for i in 1:250], [1:64 for _ in 1:250], Constraint[], 10^5)
    @test Profile(Request(wide; strength = 4)).targets == binomial(big(250), 4) * big(64)^4
    # Past Int it saturates, where TargetList refuses.
    @test Profile(Request(wide; strength = 10)).targets == typemax(Int)
end


@testitem "engines: a profile's shape: prime powers, rules by kind, must-include rows, Invalid values (§4.2)" setup=[EngineSetup] begin
    using Base.CoreLogging: with_logger, NullLogger
    # Rule 1 (9 combinations) is tabulated, rule 2 (18) is lazy, and rule 3 is a
    # whole-case rule; tabulation_limit = 12, as in the stability tests.
    space = with_logger(NullLogger()) do
        TestSpace((a = [1, 2, 3], b = [:x, :y, :z], c = [true, false], d = 1:3, e = [:p, :q, Invalid(0)],
                   f = 1:6, g = 1:1, h = 1:8, i = [1, 2, Invalid(1), Invalid(2)]);
            constraints = [forbid((a = 1, b = :y)),
                           forbid((a, d, e) -> a == 2 && d == 1 && e == :q, :a, :d, :e),
                           forbid(row -> row.a == 3 && row.e == :p)],
            tabulation_limit = 12)
    end
    request = Request(space; strength = 2, stronger = [(:a, :b, :c) => 3],
                      must_include = [(a = 1, b = :x), (e = Invalid(0),)])
    p = Profile(request)
    @test p.arity == [3, 3, 2, 3, 2, 6, 1, 8, 2]
    @test p.prime_power == [true, true, true, true, true, false, false, true, true]
    @test p.rules == [(scope = 2, kind = :tabulated), (scope = 3, kind = :lazy), (scope = 9, kind = :whole_case)]
    @test p.n_must_include == 2 && p.n_invalid == 3
    @test p.groups == [collect(1:9) => 2, [1, 2, 3] => 3]
    @test p.targets == length(TargetList(request))
    @test [UnitTestDesign._is_prime_power(q) for q in 1:32] ==
          [q in (2, 3, 4, 5, 7, 8, 9, 11, 13, 16, 17, 19, 23, 25, 27, 29, 31, 32) for q in 1:32]
end


@testitem "engines: RequiredTargets answers for the list it wraps (§4.2)" setup=[EngineSetup] begin
    rng = Xoshiro(0x2026_1005)
    for _ in 1:100
        space = random_space(rng)
        n = length(space.names)
        strength = rand(rng, 1:min(3, n))
        request = Request(space; strength, stronger = random_groups(rng, n, strength))
        required, _ = classify_targets(request)
        t = RequiredTargets(request, required)
        @test _target_list(t) === required
        list = TargetList(request)
        @test supports(t) == list.supports
        listed = Set(required)
        @test nrequired(t) == length(required)
        @test sum(s -> nrequired(t, s), eachindex(supports(t)); init = 0) == length(required)
        row = zeros(Int, n)
        for (s, support) in enumerate(supports(t))
            @test ncombinations(t, s) == prod(request.arity[support])
            # The code is TargetList's order: code k is list[offsets[s] + k + 1].
            codes = 0:(ncombinations(t, s) - 1)
            @test all(code -> _decode!(fill!(row, 0), code, support, request.arity) ==
                              list[list.offsets[s] + code + 1], codes)
            @test all(code -> isrequired(t, s, code) == (list[list.offsets[s] + code + 1] in listed), codes)
            @test count(code -> isrequired(t, s, code), codes) == nrequired(t, s)
            @test_throws BoundsError isrequired(t, s, ncombinations(t, s))
            @test_throws BoundsError isrequired(t, s, -1)
        end
        # The same targets as a Vector answer the same.
        listed_t = RequiredTargets(request, collect(required))
        @test all(s -> nrequired(listed_t, s) == nrequired(t, s), eachindex(supports(t)))
        # So do a negative sub-request's.
        for q in 1:n
            isempty(space.invalid[q]) && continue
            strength > 1 || any(g -> q in g.first, request.groups[2:end]) || continue
            sub = _negative_request(request, NegativeProjection(space, q), zeros(Int, n - 1, 0))
            sub_targets = collect(TargetList(sub))[1:2:end]
            st = RequiredTargets(sub, sub_targets)
            @test nrequired(st) == length(sub_targets)
            @test sum(s -> nrequired(st, s), eachindex(supports(st)); init = 0) == length(sub_targets)
        end
    end
    # Unconstrained, the list is the TargetList and every target is required.
    request = Request(TestSpace((a = 1:3, b = 1:2, c = 1:4)); strength = 2)
    required, _ = classify_targets(request)
    @test required isa TargetList
    t = RequiredTargets(request, required)
    @test [nrequired(t, s) for s in 1:3] == [6, 12, 8]
    @test all(isrequired(t, s, c) for s in 1:3 for c in 0:(ncombinations(t, s) - 1))
    # A list that is not the request's targets is an internal error.
    @test_throws ErrorException RequiredTargets(request, [[1, 0, 0]])         # no such support
    @test_throws ErrorException RequiredTargets(request, [[1, 3, 0]])         # outside the arity
    @test_throws ErrorException RequiredTargets(request, [[1, 1, 0], [1, 1, 0]])
end


@testitem "engines: an engine that refuses a negative sub-request hands it to IPOG (§4.2)" setup=[EngineSetup] begin
    space = TestSpace((a = [1, 2, Invalid(0)], b = [:x, :y, :z], c = [true, false], d = 1:3);
                      constraints = [forbid((b = :y, c = true))])
    # At strength 2 the ordinary part is a request at strength 2, and the
    # negative sub-request for a = Invalid(0) is at strength 1, which Refusing(2)
    # refuses. Its fit sends that sub-request to IPOG, so the rows are IPOG's.
    engine = Refusing(2)
    cases = covering(space; strength = 2, engine)
    @test engine.covered == [2]
    @test collect(cases) == collect(covering(space; strength = 2, engine = IPOG()))
    @test cases.negative_required > 0 && iscomplete(coverage(cases))
    @test cases.engine === :Refusing && cases.seed === nothing
    @test occursin("Refusing", sprint(show, MIME"text/plain"(), cases))
    @test occursin("seed: none (Refusing uses no randomness)", sprint(show, MIME"text/plain"(), report(cases)))
    # The hook itself: the sub-request goes to IPOG, the request stays.
    request = Request(space; strength = 2)
    sub = _negative_request(request, NegativeProjection(space, 1), zeros(Int, 3, 0))
    @test _engine_for(engine, request) === engine
    @test _engine_for(engine, sub) == IPOG()
    @test_throws ErrorException cover_ordinary(engine, sub, RequiredTargets(sub, collect(TargetList(sub))))
    # At strength 3 the sub-request is at strength 2, which it covers itself.
    engine = Refusing(2)
    cases = covering(space; strength = 3, engine)
    @test engine.covered == [3, 2]
    @test collect(cases) == collect(covering(space; strength = 3, engine = IPOG()))
    # Must-include rows at the invalid value go with the sub-request.
    engine = Refusing(2)
    must_include = [(a = Invalid(0), b = :z), (a = 2, c = false)]
    cases = covering(space; strength = 2, engine, must_include)
    @test engine.covered == [2]
    @test collect(cases) == collect(covering(space; strength = 2, engine = IPOG(), must_include))
    # A base strength of 0, with a group holding the invalid parameter.
    engine = Refusing(1)
    cases = covering(space; strength = 1, stronger = [(:a, :b) => 2], engine)
    @test engine.covered == [1]
    @test collect(cases) == collect(covering(space; strength = 1, stronger = [(:a, :b) => 2], engine = IPOG()))
end


@testitem "engines: a directly named engine that refuses the request is an ArgumentError (§4.2)" setup=[EngineSetup] begin
    using UnitTestDesign: generate, _check_fit
    # Option (c) of p0-protocol's judgment call 1: `generate` refuses, with
    # the fit's reason, a request the named engine's fit refuses, before
    # anything is classified, and never hands it to another engine. Only the
    # negative sub-requests go to the fallback (the item above).
    space = TestSpace((a = [1, 2], b = [:x, :y, :z], c = [true, false]))
    engine = Refusing(3)
    request = Request(space; strength = 2)
    @test_throws ArgumentError generate(engine, request)
    @test isempty(engine.covered)
    message = try
        covering(space; strength = 2, engine)
        ""
    catch err
        sprint(showerror, err)
    end
    @test message == "ArgumentError: Refusing() does not cover this request: strength below 3; IPOG() covers any request"
    @test length(covering(space; strength = 3, engine)) == 12 && engine.covered == [3]
    # IPOG and GND fit every request, so nothing changes for them.
    for e in (IPOG(), GND())
        @test _check_fit(e, request).kind === :native
    end
end


@testitem "engines: any covering engine passes the engine check; anything else, as before (§4.2)" setup=[EngineSetup] begin
    using UnitTestDesign: _check_engine
    engine = Refusing(1)
    @test _check_engine(engine) === engine
    for other in (:ipog, IPOG, "GND", nothing)
        @test_throws ArgumentError _check_engine(other)
    end
    message = try
        _check_engine(:ipog)
    catch e
        sprint(showerror, e)
    end
    @test occursin("`engine` is IPOG() or GND(); got :ipog", message)
    # design_sizes names the engine by its record.
    t = design_sizes((a = [1, 2], b = [:x, :y], c = [true, false]); engine, distances = 1:1)
    @test t.engine === :Refusing
    @test occursin("produced with Refusing", sprint(show, MIME"text/plain"(), t))
    @test design_sizes((a = [1, 2], b = [:x, :y]); engine = GND(seed = 2), distances = 1:1).engine === :GND
end
