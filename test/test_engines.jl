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
                          _engine_registry, _negative_request, _decode!, _randomized, _required_list

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
    Base.show(io::IO, e::Refusing) = print(io, "Refusing($(e.least))")
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
    using UnitTestDesign: _engine_phrase, _seed_note, _seed_text, _fallback, _engine_config
    @test IPOG <: CoveringEngine && GND <: CoveringEngine
    # The record keeps what 0.5 recorded: the engine's name and its seed.
    ipog = engine_record(IPOG())
    @test ipog.name === :IPOG && ipog.seed === nothing && ipog.parameters == []
    gnd = engine_record(GND(seed = 7, candidates = 20))
    @test gnd.name === :GND && gnd.seed == 7 && gnd.parameters == [:candidates => 20]
    @test engine_record(GND(rng = Xoshiro(1))).seed === nothing
    @test !_randomized(ipog) && _randomized(gnd) && _randomized(engine_record(GND(rng = Xoshiro(1))))
    @test !_randomized(EngineRecord(:Excursion, nothing)) && !_randomized(EngineRecord(:FullFactorial, nothing))
    # A result records the engine's configuration (`record.engine`), and shows
    # it as 0.5 showed GND's seed (§1.22, §9.5): a randomized engine shows its
    # seed, or the caller's rng.
    config(e) = _engine_config(e)
    @test config(IPOG()) == (name = :IPOG, call = "IPOG()", seed = nothing, randomized = false, settings = (;))
    @test config(GND(seed = 7, candidates = 20)) ==
          (name = :GND, call = "GND(seed = 7, candidates = 20)", seed = 7, randomized = true, settings = (candidates = 20,))
    @test _engine_phrase(config(IPOG())) == "IPOG"
    @test _engine_phrase(config(GND(seed = 3))) == "GND seed 3"
    @test _engine_phrase(config(GND(rng = Xoshiro(1)))) == "GND, caller's rng"
    @test _seed_note(config(IPOG())) === nothing
    @test _seed_note(config(GND(seed = 3))) == "GND seed 3"
    @test _seed_note(config(GND(rng = Xoshiro(1)))) == "GND with the caller's rng"
    @test _seed_text(config(IPOG())) == "seed: none (IPOG uses no randomness)"
    @test _seed_text(config(GND(seed = 3))) == "seed: 3 (GND(seed = 3) repeats these cases)"
    @test _seed_text(config(GND(rng = Xoshiro(1)))) == "seed: none (GND drew from the caller's rng)"
    # GND's rows depend on `candidates` too, so the configuration keeps them
    # and the seed line names the call that repeats its cases; the default's
    # line is as before.
    @test _seed_text(config(GND(seed = 3, candidates = 20))) ==
          "seed: 3 (GND(seed = 3, candidates = 20) repeats these cases)"
    twenty = covering(fill(1:4, 6)...; engine = GND(seed = 3, candidates = 20))
    @test twenty.record.engine.settings == (candidates = 20,)
    @test "seed: 3 (GND(seed = 3, candidates = 20) repeats these cases)" in
          split(sprint(show, MIME"text/plain"(), report(twenty)), '\n')
    @test covering(fill(1:4, 6)...; engine = GND(seed = 3, candidates = 20)) == twenty
    @test covering(fill(1:4, 6)...; engine = GND(seed = 3)) != twenty   # why the line names candidates
    fifty = covering(fill(1:4, 6)...; engine = GND(seed = 3))
    @test fifty.record.engine.settings == (candidates = 50,) && "seed: 3 (GND(seed = 3) repeats these cases)" in
          split(sprint(show, MIME"text/plain"(), report(fifty)), '\n')
    # A result keeps whether its engine is randomized in its record, beside engine and seed.
    @test all_pairs(1:2, 1:3; engine = GND(seed = 3)).record.randomized
    @test !all_pairs(1:2, 1:3).record.randomized
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
    @test "Compact(IPOG())" in first.(registry)
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
    # The ordinary must-include rows only: the negative one is a must-include
    # row of its value's negative sub-request, whose profile counts it.
    @test p.n_must_include == 1 && p.n_invalid == 3
    sub = UnitTestDesign._negative_request(request, UnitTestDesign.NegativeProjection(space, 5),
                                           request.must_include[[1, 2, 3, 4, 6, 7, 8, 9], [2]])
    @test Profile(sub).n_must_include == 1
    # So the whole request's profile is the ordinary request's, which `generate` builds the ordinary rows from.
    ordinary = Profile(UnitTestDesign._with_must_include(request, request.must_include[:, [1]]))
    @test all(name -> getfield(p, name) == getfield(ordinary, name), fieldnames(Profile))
    @test p.groups == [collect(1:9) => 2, [1, 2, 3] => 3]
    @test p.targets == length(TargetList(request))
    @test [UnitTestDesign._is_prime_power(q) for q in 1:32] ==
          [q in (2, 3, 4, 5, 7, 8, 9, 11, 13, 16, 17, 19, 23, 25, 27, 29, 31, 32) for q in 1:32]
end


@testitem "engines: RequiredTargets answers for the list it is built from (§4.2)" setup=[EngineSetup] begin
    rng = Xoshiro(0x2026_1005)
    for _ in 1:100
        space = random_space(rng)
        n = length(space.names)
        strength = rand(rng, 1:min(3, n))
        request = Request(space; strength, stronger = random_groups(rng, n, strength))
        required, _ = classify_targets(request)
        t = RequiredTargets(request, required)
        @test _required_list(t) == required   # read back through the interface, in target order
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


@testitem "engines: classification keeps the excluded ids, and its targets are the list's bit for bit (§4.2, §1.4)" tags=[:skipci] setup=[EngineSetup] begin
    using UnitTestDesign: CoverageIndex, Excluded, _Classified, _classify_target, _negative_targets!, _required_bits,
                          _ordinary_bound, _prepare, _run, _space_indices, _slot, _sub_excluded, cache_entries,
                          classify_negative_targets, isconstrained, n_must_include
    # Phase 5 (plan §5.6, "Target storage"): classification walks the
    # request's layout and keeps a count per support, the excluded targets'
    # ids and their `Excluded` records; no required target is listed. Its
    # targets must be the list path's, 31bef0f's loop written out below
    # (every target of the TargetList as a fresh vector, classified in target
    # order, then counted and marked by the list-alone constructor), bit for
    # bit, with the same records, after the same feasibility questions in the
    # same order: on a fresh request of its own, the list path leaves the
    # search with the same statistics. `classify_targets`, which tests and
    # scripts read, returns the same lists. The two paths share
    # `_classify_target`, the `TargetList` they walk and
    # `RequiredTargets(request, required)`, so this compares the walk's order
    # and its storage, not those: the supports are compared with 31bef0f's
    # listing in test_request.jl ("the layout's supports and offsets are the
    # listed layout's"), and `_classify_target`'s question without the
    # witness with the full one in test_feasibility.jl ("explain_partial
    # without the witness asks and answers the same").
    #
    # The follow-ups' laziness stays: the bits are built the first time
    # something asks, never by the bound without must-include rows, and then
    # shared. IPOG's lookup core asks `isrequired` on a support where a rule
    # excludes some of its combinations, which builds them, and on no other
    # (p4-core's notes, §1.8). GND reads every required target through
    # `isrequired` to build its coverage matrix, which builds them.
    function listed(request)
        isconstrained(request) || return TargetList(request), Excluded[]
        f = request.feasibility
        active = collect(eachindex(f.tables))
        required, excluded = Vector{Int}[], Excluded[]
        for t in TargetList(request)
            e = _classify_target(request, f, active, t, _space_indices(request, t), "classifying target")
            e === nothing ? push!(required, t) : push!(excluded, e)
        end
        return required, excluded
    end
    fields(e::Excluded) = (e.target, e.status, e.rules, e.minimal, e.limit)
    effort(f) = (s = f.stats; (s.queries, s.memo_hits, s.total_nodes, s.evaluations, cache_entries(f)))
    stats(r) = effort(r.feasibility)
    negative_stats(r) = sort!([k => effort(first(v)) for (k, v) in r.context.searches if k != (0, 0)])
    rng = Xoshiro(0x2026_1006)
    must_rng = Xoshiro(0x2026_1008)   # apart, so the spaces are the follow-ups' 100
    with_must = Ref(0)
    for _ in 1:100
        space = random_space(rng)
        n = length(space.names)
        strength = rand(rng, 1:min(3, n))
        stronger = random_groups(rng, n, strength)
        # Sometimes a must-include row, whose check asks the search before classification does.
        must = rand(must_rng) < 0.3 ? [NamedTuple{(space.names[1],)}((first(space.values[1]),))] : []
        function make()
            isempty(must) && return Request(space; strength, stronger)
            try
                return Request(space; strength, stronger, must_include = must)
            catch err
                err isa ArgumentError || rethrow()
                return Request(space; strength, stronger)
            end
        end
        request = make()
        with_must[] += n_must_include(request) > 0
        classified = _Classified(request)
        t = classified.targets
        mirror = make()
        required, excluded = listed(mirror)
        @test stats(request) == stats(mirror)
        @test fields.(classified.excluded) == fields.(excluded)
        listed_t = RequiredTargets(mirror, collect(required))
        @test t.layout.supports == listed_t.layout.supports && t.layout.offsets == listed_t.layout.offsets &&
              t.layout.arity == request.arity
        @test all(s -> nrequired(t, s) == nrequired(listed_t, s), eachindex(supports(t))) &&
              nrequired(t) == nrequired(listed_t) == length(required)
        @test t.excluded == listed_t.excluded   # the ids of the combinations not required, ascending
        @test (t isa RequiredTargets{TargetList}) == (required isa TargetList)
        required isa TargetList && @test t.list === t.layout   # unconstrained: the layout itself, whole
        test_required, test_excluded = classify_targets(make())
        @test test_required == required && fields.(test_excluded) == fields.(excluded)
        # The bits, built when first asked.
        @test t.bits === nothing
        n_must_include(request) == 0 && (_ordinary_bound(request, t); @test t.bits === nothing)
        fresh = _Classified(request).targets
        _run(_prepare(IPOG(), Profile(request)), request, fresh)
        @test (fresh.bits === nothing) ==
              !any(s -> 0 < nrequired(fresh, s) < ncombinations(fresh, s), eachindex(supports(fresh)))
        _run(_prepare(GND(), Profile(request)), request, t)
        @test (t.bits === nothing) == (required isa TargetList)   # a TargetList's answer is always true
        @test all(isrequired(t, s, code) == isrequired(listed_t, s, code)
                  for s in eachindex(supports(t)) for code in 0:(ncombinations(t, s) - 1))
        bits = _required_bits(t)
        @test bits == _required_bits(listed_t)
        @test t.bits === bits && CoverageIndex(request, t).required === bits
        # The negative targets: counted, each exclusion kept with its number
        # in target order and its record's position under its invalid value,
        # after the same questions as the list path
        # (`classify_negative_targets`, 31bef0f's record renamed), whose lists
        # they must reproduce. The two share `_classify_target` and the walk
        # (`_walk_support!`), so this compares the numbering and the storage;
        # the order is stated a third time below.
        any(!isempty, space.invalid) || continue
        negative = _negative_targets!(classified, request)
        @test _negative_targets!(classified, request) === classified.negative   # classified once
        @test negative.layout === t.layout
        negative_required, negative_excluded = classify_negative_targets(mirror)
        @test negative_stats(request) == negative_stats(mirror)
        @test negative.required == length(negative_required)
        @test fields.(negative.excluded) == fields.(negative_excluded)
        # Their numbers, in the order of §9.7 written out once more.
        walked = Vector{Int}[]
        for support in TargetList(request).supports, q in support, v in (request.arity[q] + 1):length(request.candidates[q])
            rest = filter(!=(q), support)
            for code in 0:(prod(request.arity[rest]; init = 1) - 1)
                target = _decode!(zeros(Int, n), code, rest, request.arity)
                target[q] = v
                push!(walked, target)
            end
        end
        gone = Set(e.target for e in negative_excluded)
        @test negative.ids == findall(in(gone), walked)
        @test walked[setdiff(eachindex(walked), negative.ids)] == negative_required
        # Each invalid value's sub-request: its targets are the ones at that
        # value without p, required or excluded as here (not always in the
        # same order: test_invalid.jl's items on groups that change order).
        for q in 1:n, position in (request.arity[q] + 1):length(request.candidates[q])
            slot = _slot(negative, request, q, position)
            here = [r for r in negative_required if r[q] == position]
            @test (negative.alone[slot] === :required) == any(r -> count(!=(0), r) == 1, here)
            @test negative.excluded_at[slot] ==
                  findall(e -> e.target[q] == position && count(!=(0), e.target) > 1, negative.excluded)
            if !(strength > 1 || any(g -> q in g.first, request.groups[2:end]))
                @test negative.count[slot] == 0 && isempty(negative.excluded_at[slot])
                continue
            end
            pr = NegativeProjection(space, q)
            sub = _negative_request(request, pr, zeros(Int, n - 1, 0))
            sub_required = [r[pr.kept] for r in here if count(!=(0), r) > 1]
            st = RequiredTargets(TargetList(sub), _sub_excluded(negative, slot, pr, TargetList(sub)))
            sl = RequiredTargets(sub, sub_required)
            @test negative.count[slot] == length(TargetList(sub))
            @test all(s -> nrequired(st, s) == nrequired(sl, s), eachindex(supports(st)))
            @test _required_bits(st) == _required_bits(sl) && st.excluded == sl.excluded
        end
    end
    @test with_must[] > 10
    # Unconstrained: the TargetList, no counts, and bits only for the index, all set.
    request = Request(TestSpace((a = 1:3, b = 1:2, c = 1:4)); strength = 2)
    t = _Classified(request).targets
    @test t isa RequiredTargets{TargetList} && t.bits === nothing && [nrequired(t, s) for s in 1:3] == [6, 12, 8]
    @test CoverageIndex(request, t).required === t.bits && all(t.bits) && length(t.bits) == 26
    # The ids are the rest of the layout's targets, in target order, each once.
    ruled = Request(TestSpace((a = 1:3, b = 1:2, c = 1:4); constraints = [forbid((a = 1, b = 1))]); strength = 2)
    list = TargetList(ruled)
    t = _Classified(ruled).targets
    @test t.excluded == [1] && t.counts == [5, 12, 8] && nrequired(t) == 25
    @test RequiredTargets(list, [1]).counts == [5, 12, 8]
    @test_throws ErrorException RequiredTargets(list, [2, 1])     # out of target order
    @test_throws ErrorException RequiredTargets(list, [1, 1])     # twice
    @test_throws ErrorException RequiredTargets(list, [27])       # not on the layout
end


@testitem "engines: no engine changes the targets the certifier reads (§4.2, §1.21)" tags=[:skipci] setup=[EngineSetup] begin
    using UnitTestDesign: Design, _Classified, _IPOGLookup, _check_fit, _generate, _required_bits
    # The certifier recounts each design on the targets the engines read
    # (`validate_design`): their layout and the ids of the excluded targets.
    # Engines read the bits too, through `isrequired`, and the coverage index
    # holds them by reference. So each engine of the registry, and the lookup
    # core named directly, must leave all of it as classification made it:
    # generating from one classification, with the bits built first so that an
    # engine holding them could change them, the layout, counts, ids and bits
    # are equal after the run.
    engines = CoveringEngine[last.(_engine_registry(3)); _IPOGLookup();
                             _IPOGLookup(tiebreak = (:rotate,), vertical = (:value,))]
    rng = Xoshiro(0x2026_1007)
    runs = Ref(0)
    for _ in 1:40
        space = random_space(rng)
        n = length(space.names)
        strength = rand(rng, 1:min(3, n))
        request = Request(space; strength, stronger = random_groups(rng, n, strength))
        for engine in engines
            plan = try
                _check_fit(engine, request)
            catch err
                err isa ArgumentError || rethrow()
                continue
            end
            classified = _Classified(request)
            t = classified.targets
            bits = copy(_required_bits(t))
            before = deepcopy((t.layout.arity, t.layout.supports, t.layout.offsets, t.counts, t.excluded))
            @test _generate(plan, request, classified) isa Design
            @test (t.layout.arity, t.layout.supports, t.layout.offsets, t.counts, t.excluded) == before
            @test t.bits == bits
            runs[] += 1
        end
    end
    @test runs[] > 200
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
    @test message == "ArgumentError: Refusing(3) does not cover this request: strength below 3; IPOG() or Auto() covers any request"
    @test length(covering(space; strength = 3, engine)) == 12 && engine.covered == [3]
    # IPOG and GND fit every request, so nothing changes for them.
    for e in (IPOG(), GND())
        @test _check_fit(e, request).fit.kind === :native
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
    @test occursin("`engine` is a covering engine such as IPOG(), Construction(), Compact(IPOG()) or Auto(); got :ipog",
                   message)
    # design_sizes names the engine by its record.
    t = design_sizes((a = [1, 2], b = [:x, :y], c = [true, false]); engine, distances = 1:1)
    @test t.engine === :Refusing
    @test occursin("produced with Refusing", sprint(show, MIME"text/plain"(), t))
    @test design_sizes((a = [1, 2], b = [:x, :y]); engine = GND(seed = 2), distances = 1:1).engine === :GND
end


@testitem "engines: an engine's notes stay in its stage; the bound, minimal and proof are the pipeline's (§8.7)" setup=[EngineSetup] begin
    using UnitTestDesign: _Plan
    # A probe engine whose notes claim what only the pipeline may say: IPOG's
    # rows, reported as minimal, with a lower bound of their own count, a
    # proof and randomness. Generation proves and checks the bound itself
    # (`_covering_record`), so the result says what the pipeline found, and
    # the claims stay in the engine's own stage.
    struct Boasting <: CoveringEngine end
    struct BoastingPlan <: _Plan
        engine::Boasting
        fit::Fit
    end
    UnitTestDesign.engine_record(::Boasting) = EngineRecord(:Boasting, nothing)
    Base.show(io::IO, ::Boasting) = print(io, "Boasting()")
    UnitTestDesign._prepare(e::Boasting, ::Profile) = BoastingPlan(e, Fit(:native, "IPOG's rows"))
    UnitTestDesign.fit(e::Boasting, p::Profile) = UnitTestDesign._prepare(e, p).fit
    function UnitTestDesign._execute(plan::BoastingPlan, request::Request, targets::RequiredTargets)
        rows = cover_ordinary(IPOG(), request, targets)
        return rows, (minimal = true, lower_bound = size(rows, 2), proof = "no design has fewer", randomized = true)
    end
    # Eight flags: IPOG's design is above the bound of 4, and the catalog's
    # Kleitman-Spencer array has fewer cases, so the claim is false.
    flags = TestSpace(NamedTuple{Tuple(Symbol(:f, i) for i in 1:8)}(Tuple([false, true] for _ in 1:8)))
    cases = all_pairs(flags; engine = Boasting())
    @test collect(cases) == collect(all_pairs(flags; engine = IPOG()))
    @test length(all_pairs(flags; engine = Construction())) < length(cases)
    @test !cases.record.minimal && cases.record.lower_bound == 4 && !cases.record.randomized
    @test cases.record.proof == all_pairs(flags; engine = IPOG()).record.proof == "the 2 × 2 = 4 combinations of f1 and f2 need a case each"
    @test startswith(repr(cases), "$(length(cases)) cases (lower bound 4) · strength 2 · Boasting · ")
    text = sprint(show, MIME"text/plain"(), report(cases))
    @test occursin("\nsize: $(length(cases)) cases; lower bound 4: the 2 × 2 = 4 combinations", text)
    @test !occursin("minimal", text) && endswith(text, "seed: none (Boasting uses no randomness)")
    # What the engine said is kept, in its namespace: its stage of the record.
    stage = cases.record.ordinary
    @test stage.engine == "Boasting()" && stage.rows == length(cases)
    @test stage.minimal && stage.lower_bound == length(cases) && stage.proof == "no design has fewer"
    # The same for each negative sub-request's stage.
    invalid = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3))
    cases = covering(invalid; strength = 3, engine = Boasting())
    @test collect(cases) == collect(covering(invalid; strength = 3, engine = IPOG()))
    @test cases.record.minimal == (length(cases) == cases.record.lower_bound)
    @test cases.record.lower_bound == covering(invalid; strength = 3, engine = IPOG()).record.lower_bound
    @test only(cases.record.negative).stage.minimal && only(cases.record.negative).stage.engine == "Boasting()"
    # A stage's `engine` and `rows` are the pipeline's too: an engine that sets
    # them is an internal error, never a record that misstates its rows.
    struct Miscounting <: CoveringEngine end
    struct MiscountingPlan <: _Plan
        engine::Miscounting
        fit::Fit
    end
    UnitTestDesign.engine_record(::Miscounting) = EngineRecord(:Miscounting, nothing)
    Base.show(io::IO, ::Miscounting) = print(io, "Miscounting()")
    UnitTestDesign._prepare(e::Miscounting, ::Profile) = MiscountingPlan(e, Fit(:native, "IPOG's rows"))
    UnitTestDesign.fit(e::Miscounting, p::Profile) = UnitTestDesign._prepare(e, p).fit
    UnitTestDesign._execute(::MiscountingPlan, request::Request, targets::RequiredTargets) =
        (cover_ordinary(IPOG(), request, targets), (rows = 1,))
    @test_throws "internal error: Miscounting()'s notes set its stage's `rows`" all_pairs(flags; engine = Miscounting())
end


@testitem "engines: generation prepares a plan once, and so do negative sub-requests and design_sizes (§4.2)" setup=[EngineSetup] begin
    using UnitTestDesign: _Plan, generate
    # A probe engine that counts the plans it prepares, by the strength of the
    # request, and refuses a request below strength 2. Its rows are IPOG's.
    struct Counting <: CoveringEngine
        prepared::Vector{Int}
    end
    Counting() = Counting(Int[])
    struct CountingPlan <: _Plan
        engine::Counting
        fit::Fit
    end
    UnitTestDesign.engine_record(::Counting) = EngineRecord(:Counting, nothing)
    Base.show(io::IO, ::Counting) = print(io, "Counting()")
    function UnitTestDesign._prepare(e::Counting, p::Profile)
        push!(e.prepared, p.strength)
        return CountingPlan(e, p.strength >= 2 ? Fit(:native, "IPOG's rows") : Fit(:unsupported, "strength below 2"))
    end
    UnitTestDesign.fit(e::Counting, p::Profile) = UnitTestDesign._prepare(e, p).fit
    UnitTestDesign._execute(::CountingPlan, request::Request, targets::RequiredTargets) =
        (cover_ordinary(IPOG(), request, targets), (;))
    space = TestSpace((a = 1:3, b = 1:3, c = 1:2, d = 1:2))
    # `generate` prepares the plan once and executes it: its check of the fit is the plan's.
    e = Counting()
    @test collect(covering(space; strength = 2, engine = e)) == collect(covering(space; strength = 2, engine = IPOG()))
    @test e.prepared == [2]
    # A negative sub-request prepares once too; one the engine refuses (strength
    # 1) takes the fallback's plan, IPOG's, and its stage says so.
    invalid = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:2, d = 1:2))
    e = Counting()
    cases = covering(invalid; strength = 3, engine = e)
    @test e.prepared == [3, 2] && only(cases.record.negative).stage.engine == "Counting()"
    e = Counting()
    cases = covering(invalid; strength = 2, engine = e)
    @test e.prepared == [2, 1] && only(cases.record.negative).stage.engine == "IPOG()"
    @test collect(cases) == collect(covering(invalid; strength = 2, engine = IPOG()))
    # A refusal is an ArgumentError after one plan; design_sizes reads the
    # plan's fit for each strength and generates from that same plan.
    e = Counting()
    @test_throws "Counting() does not cover this request: strength below 2" generate(e, Request(space; strength = 1))
    @test e.prepared == [1]
    e = Counting()
    t = design_sizes(space; engine = e, distances = 1:1)
    @test e.prepared == [1, 2, 3]
    @test [r.status for r in t.rows if r.kind === :covering] == [:unsupported, :ok, :ok]
    @test all(r -> r.engine == "Counting()", (r for r in t.rows if r.kind === :covering))
end


@testitem "engines: design_sizes classifies each strength once for all its engines (§4.2, §3.5)" setup=[EngineSetup] begin
    using UnitTestDesign: _Plan
    # The maintainer's follow-up 3. A probe engine that keeps the targets each
    # run reads, and IPOG's rows. With several engines, every engine at a
    # strength reads the same targets, classified once, and keeps its own
    # search state; the rows, counts and statuses are what each engine gives
    # alone.
    struct Keeping <: CoveringEngine
        seen::Vector{Any}
    end
    Keeping() = Keeping(Any[])
    UnitTestDesign.engine_record(::Keeping) = EngineRecord(:Keeping, nothing)
    Base.show(io::IO, ::Keeping) = print(io, "Keeping()")
    UnitTestDesign.fit(::Keeping, ::Profile) = Fit(:native, "IPOG's rows")
    function UnitTestDesign.cover_ordinary(e::Keeping, request::Request, targets::RequiredTargets)
        push!(e.seen, targets)
        return cover_ordinary(IPOG(), request, targets)
    end
    space = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:2, d = 1:3); constraints = [forbid((a = 1, b = 1))])
    first_engine, second_engine = Keeping(), Keeping()
    engines = [first_engine, Compact(IPOG()), second_engine, Construction(), Auto(goal = :compact)]
    both = design_sizes(space; engine = engines, strengths = 2:3, distances = 1:1)
    # Each strength's ordinary targets, then its negative sub-requests'. The
    # ordinary targets are one object for every engine at a strength; a
    # sub-request's are made for each run from the negative targets classified
    # once, on the sub-request's own layout, and read the same.
    @test length(first_engine.seen) == length(second_engine.seen) == 4   # two strengths, one Invalid value
    ordinary = [length(t.layout.arity) == 4 for t in first_engine.seen]
    @test count(ordinary) == 2
    @test all(first_engine.seen[ordinary] .=== second_engine.seen[ordinary])
    @test all(zip(first_engine.seen[.!ordinary], second_engine.seen[.!ordinary])) do (x, y)
        x !== y && _required_list(x) == _required_list(y) && x.counts == y.counts && x.layout.supports == y.layout.supports
    end
    # Rows, counts and messages as each engine gives them alone; the probes give IPOG's.
    fields(r) = (r.strategy, r.status, r.message, r.cases, r.pairs, r.triples, r.negative_cases)
    for (e, label) in ((IPOG(), "Keeping()"), (Compact(IPOG()), nothing), (Construction(), nothing),
                       (Auto(goal = :compact), nothing))
        alone = design_sizes(space; engine = e, strengths = 2:3, distances = 1:1)
        label = something(label, alone.rows[2].engine)
        mine = [r for r in both.rows if r.engine == label || r.kind !== :covering]
        twice = label == "Keeping()"   # the two probes' rows at each strength, each IPOG's
        @test fields.(mine) == fields.(twice ? alone.rows[[1, 2, 2, 3, 3, 4]] : alone.rows)
    end
    for s in 2:3
        @test collect(covering(space; strength = s, engine = Keeping())) == collect(covering(space; strength = s, engine = IPOG()))
    end
end


@testitem "engines: a result records its engine's configuration and every stage, and its seed line names a call that repeats its cases (§9.5)" tags=[:skipci] setup=[EngineSetup] begin
    using UnitTestDesign: _engine_config, _engine_phrase
    # Every registry engine and nested ones, on spaces of one value count
    # (the catalog's), with Invalid values, and with mixed counts and a rule.
    # A result's configuration names its engine's call, which run again is the
    # same engine; a randomized engine's seed line names a call, and running
    # that call gives the same cases.
    spaces = [TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:3)),
              TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = [1, 2, 3, Invalid(:x)])),
              TestSpace((a = 1:2, b = 1:3, c = 1:4, d = 1:2); constraints = [forbid((a = 1, b = 1))])]
    nested = CoveringEngine[Compact(GND(seed = 17); seed = 3, effort = 2), Compact(Compact(GND(seed = 2)); seed = 5),
                            Compact(Auto(goal = :compact, seed = 4)), Auto(goal = :compact, seed = 7, effort = 2),
                            GND(seed = 3, candidates = 20), Compact(Construction(); seed = 1), Auto(goal = :fast)]
    engines = vcat(last.(_engine_registry(0)), last.(_engine_registry(7)), nested)
    run(call) = Core.eval(@__MODULE__, Meta.parse(call))
    checked = Ref(0)
    for space in spaces, strength in (2, 3), engine in engines
        fit(engine, Profile(Request(space; strength))).kind === :unsupported && continue
        cases = covering(space; strength, engine)
        config = cases.record.engine
        @test config == _engine_config(engine) && run(config.call) === engine
        line = last(split(sprint(show, MIME"text/plain"(), report(cases)), '\n'))
        if config.randomized
            m = match(r"^seed: (\d+) \((.*) repeats these cases\)$", line)
            @test m !== nothing && parse(Int, m[1]) == cases.seed
            @test collect(covering(space; strength, engine = run(m[2]))) == collect(cases)
        else
            @test line == "seed: none ($(config.name) uses no randomness)"
            @test collect(covering(space; strength, engine = run(config.call))) == collect(cases)
        end
        # The stages: the ordinary design's names the engine and its rows, and
        # one per invalid value names the engine that covered its sub-request.
        @test cases.record.ordinary.engine == config.call
        @test cases.record.ordinary.rows == length(cases) - count(hasinvalid, cases)
        @test [(n.parameter, n.value) for n in cases.record.negative] ==
              (UnitTestDesign._has_invalid(space) ? [(:a, "Invalid(0)"), (:d, "Invalid(:x)")] : [])
        @test sum(n -> n.rows, cases.record.negative; init = 0) == count(hasinvalid, cases)
        checked[] += 1
    end
    @test checked[] > 3 * length(engines)
    # The maintainer's example: a wrapper's inner engine keeps its seed, and the
    # wrapper its effort, in the configuration and in the call that repeats the cases.
    space = first(spaces)
    engine = Compact(GND(seed = 17); seed = 3, effort = 2)
    cases = all_pairs(space; engine)
    @test cases.record.engine ==
          (name = :Compact, call = "Compact(GND(seed = 17); seed = 3, effort = 2)", seed = 3, randomized = true,
           settings = (inner = (name = :GND, call = "GND(seed = 17)", seed = 17, randomized = true,
                                settings = (candidates = 50,)),
                       effort = 2))
    stage = cases.record.ordinary
    @test stage.start.engine == "GND(seed = 17)" && stage.reducer.start == stage.start.rows
    @test stage.reducer.rows == stage.rows == length(cases)
    @test occursin(" · Compact(GND(seed = 17)) seed 3 · ", repr(cases))
    text = sprint(show, MIME"text/plain"(), report(cases))
    @test endswith(text, "seed: 3 (Compact(GND(seed = 17); seed = 3, effort = 2) repeats these cases)")
    @test occursin("; Compact(GND(seed = 17)) seed 3", report(cases).guarantee)
    t = design_sizes(space; engine, distances = 1:1)
    @test t.engines == ["Compact(GND(seed = 17); seed = 3, effort = 2)"] &&
          all(r -> r.engine == t.engines[1], (r for r in t.rows if r.kind === :covering))
    # Auto's candidates are part of its configuration; its negative rows' choice
    # is in each invalid value's stage; the catalog's refusal at strength 1
    # sends those rows to IPOG, and its stage names IPOG.
    invalid = spaces[2]
    auto = all_pairs(invalid; engine = Auto())
    @test [c.call for c in auto.record.engine.settings.candidates] == ["IPOG()", "Construction()"]
    @test all(n -> n.stage.engine == "Auto()" && haskey(n.stage, :chose), auto.record.negative)
    @test all(n -> n.stage.engine == "IPOG()", all_pairs(invalid; engine = Construction()).record.negative)
    @test all(n -> startswith(n.stage.engine, "Compact(IPOG()"),
              all_pairs(invalid; engine = Compact(Construction())).record.negative)
    # An engine inside another that drew from the caller's generator: no seed
    # repeats the cases, and the line says which engine drew.
    drew = all_pairs(space; engine = Compact(GND(rng = Xoshiro(1)); seed = 3))
    @test endswith(sprint(show, MIME"text/plain"(), report(drew)),
                   "seed: 3 (GND inside Compact drew from the caller's rng, so no seed repeats these cases)")
    @test _engine_phrase(drew.record.engine) == "Compact(GND(rng = Xoshiro(…))) seed 3"
    # An excursion and a full factorial have no engine.
    for other in (excursions(space; distance = 1), full_factorial(space))
        @test other.record.engine === nothing && other.record.ordinary === nothing && other.record.negative === nothing
    end
end
