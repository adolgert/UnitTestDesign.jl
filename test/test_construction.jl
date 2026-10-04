using Test
using TestItemRunner

# The catalog engine, `Construction` (plan §5.4, Phase 2): its fit, its exact
# and seeded designs, its refusals, and determinism. It is internal until
# Phase 3 (decision D7). The catalog's own tests, and the brute-force
# checkers of `CatalogSetup`, are in test_catalog.jl.

@testsnippet ConstructionSetup begin
    using UnitTestDesign: Construction, Request, Profile, Fit, fit, engine_record, cover_ordinary, RequiredTargets,
        classify_targets, generate, NegativeProjection, _negative_request, _engine_for, _engine_rows, _catalog_rows

    names_for(k) = Tuple(Symbol(:p, i) for i in 1:k)
    space_of(arity; constraints = Constraint[]) =
        TestSpace(NamedTuple{names_for(length(arity))}(Tuple(collect(1:a) for a in arity)); constraints)
end


@testitem "construction: fit reads the profile" setup=[CatalogSetup, ConstructionSetup] begin
    C = Construction()
    profile(arity; strength = 2, kwargs...) = Profile(Request(space_of(arity); strength, kwargs...))
    f = fit(C, profile(fill(7, 8)))
    @test f.kind === :exact && f.rows == 49 && occursin("Bush", f.reason)
    @test fit(C, profile(fill(3, 12); strength = 3)).rows == 53
    @test fit(C, profile([5, 4, 3])).rows == 20 && fit(C, profile([6, 5, 4, 3]; strength = 3)).rows == 120
    @test fit(C, profile([5, 4]; strength = 2)).rows == 20
    # Seeded: rules, must-include rows, stronger groups; the size is known only after IPOG tops up.
    ruled = Profile(Request(space_of(fill(3, 5); constraints = [forbid((p1 = 1, p2 = 1))])))
    f = fit(C, ruled)
    @test f.kind === :seeded && f.rows === nothing && occursin("forbids", f.reason)
    f = fit(C, profile(fill(3, 5); must_include = [(p1 = 1,)]))
    @test f.kind === :seeded && occursin("must-include", f.reason)
    f = fit(C, profile(fill(3, 5); stronger = [(:p1, :p2, :p3) => 3]))
    @test f.kind === :seeded && occursin("stronger", f.reason)
    # Invalid values: exact for the ordinary rows; the negative rows come after.
    f = fit(C, Profile(Request(TestSpace((a = [1, 2, Invalid(0)], b = 1:2, c = 1:2)))))
    @test f.kind === :exact && f.rows === nothing && occursin("negative", f.reason)
    # Refused, with a reason a user can read.
    f = fit(C, profile([3, 3, 2, 2, 2]))
    @test f.kind === :unsupported && f.rows === nothing
    @test f.reason == "mixed value counts on 5 parameters; the catalog covers equal value counts, or t + 1 = 3 parameters"
    f = fit(C, profile(fill(3, 20); strength = 4))
    @test f.kind === :unsupported && f.reason == "no catalog entry for 20 parameters of 3 values at strength 4"
    request = Request(TestSpace((a = [1, 2, Invalid(0)], b = 1:2, c = 1:2)); strength = 1, stronger = [(:a, :b) => 2])
    sub = _negative_request(request, NegativeProjection(request.space, 1), zeros(Int, 2, 0))
    @test fit(C, Profile(sub)).kind === :unsupported && occursin("strength of 0", fit(C, Profile(sub)).reason)
    @test engine_record(C).name === :Construction && engine_record(C).seed === nothing
end


@testitem "construction: an exact shape's design is the catalog's array, certified" setup=[CatalogSetup, ConstructionSetup] begin
    C = Construction()
    for (arity, t) in ((fill(7, 8), 2), (fill(2, 20), 2), (fill(3, 12), 3), (fill(5, 6), 2), (fill(4, 9), 2),
                       ([5, 4, 3], 2), ([3, 6, 5, 4], 3), ([2, 3], 2), (fill(3, 4), 4), (fill(6, 7), 2))
        space = space_of(arity)
        request = Request(space; strength = t)
        e = _catalog_entry(t, arity)
        design = generate(C, request)                            # certified by validate_design (§1.21)
        @test design.matrix == _engine_rows(e, arity)
        @test size(design.matrix, 2) == e.rows == fit(C, Profile(request)).rows
        @test design.engine === :Construction && design.seed === nothing && design.n_must_include == 0
        cases = covering(space; strength = t, engine = C)
        @test length(cases) == e.rows && iscomplete(coverage(cases)) && cases.engine === :Construction
    end
    # Unequal value counts on t or t + 1 parameters: the zero-sum array, each
    # column back on its parameter, at the elementary bound, so minimal (§2.2).
    rng = Xoshiro(0x2026_1004_2)
    for _ in 1:40
        t = rand(rng, 1:3)
        arity = rand(rng, 1:6, t + rand(rng, 0:1))
        A = _engine_rows(_catalog_entry(t, arity), arity) .- 1   # parameters × cases
        @test size(A, 2) == prod(sort(arity; rev = true)[1:t])
        @test is_mixed_covering(permutedims(A), t, arity)
    end
    # Never more rows than the elementary bound allows at t + 1 parameters: the minimum (§2.2).
    cases = covering(space_of([6, 6, 6, 6]); strength = 3, engine = C)
    @test length(cases) == 216 && length(covering(space_of([6, 6, 6, 6]); strength = 3)) >= 216
    # The record's wording names it as an engine without randomness (§9.4).
    cases = all_pairs(space_of(fill(3, 4)); engine = C)
    @test occursin("Construction", sprint(show, MIME"text/plain"(), cases))
    @test occursin("seed: none (Construction uses no randomness)", sprint(show, MIME"text/plain"(), report(cases)))
end


@testitem "construction: seeded under rules, must-include rows and stronger groups" setup=[CatalogSetup, ConstructionSetup] begin
    C = Construction()
    # Probe 11's uniform cases: the catalog's rows that no rule forbids, then
    # IPOG's general path. Never more rows than IPOG here.
    uniform = fill(7, 8)
    for rules in ([forbid((p1 = 1, p2 = 1)), forbid((p3 = 2, p5 = 4)), forbid((p2 = 7, p8 = 1))],
                  [@forbid(p1 == p2)],
                  [forbid((a, b) -> a == b, Symbol(:p, i), Symbol(:p, i + 1)) for i in 1:7])
        space = space_of(uniform; constraints = rules)
        seeded, plain = all_pairs(space; engine = C), all_pairs(space)
        @test iscomplete(coverage(seeded)) && length(seeded) < length(plain)
        @test seeded.engine === :Construction
    end
    # More: a whole-case rule, a lazy rule, strength 3, two values.
    for (arity, t, rules) in ((fill(3, 12), 3, [@forbid(p1 == 1 && p2 == 1)]),
                              (fill(2, 20), 2, [forbid(row -> row.p1 == 1 && row.p20 == 2)]),
                              (fill(5, 6), 2, [forbid((a, b, c) -> a + b + c == 15, :p1, :p2, :p3)]),
                              (fill(4, 9), 2, [@forbid(p1 == p2), @forbid(p3 == p4 + 1)]))
        space = space_of(arity; constraints = rules)
        seeded, plain = covering(space; strength = t, engine = C), covering(space; strength = t)
        @test iscomplete(coverage(seeded)) && length(seeded) <= length(plain)
    end
    # Must-include rows come first and unchanged, partial ones completed in
    # place, and only they count as must-include rows (contract §10.5). Each
    # row of the orthogonal array holds a pair none of them holds, so all 49
    # follow them.
    space = space_of(uniform)
    must = [(p1 = 1, p2 = 2), (p1 = 3, p3 = 3, p4 = 4), (p1 = 7, p2 = 7, p3 = 7, p4 = 7, p5 = 7, p6 = 7, p7 = 7, p8 = 7)]
    cases = all_pairs(space; engine = C, must_include = must)
    @test cases.n_must_include == 3 && iscomplete(coverage(cases))
    @test cases[1].p1 == 1 && cases[1].p2 == 2 && cases[2].p1 == 3 && cases[2].p3 == 3 && cases[2].p4 == 4
    @test cases[3] == must[3]
    @test length(cases) == 3 + 49
    # A stronger group is seeded with its own array, on its parameters, when
    # that is at strength 2 or 3 and no smaller than the base array; IPOG
    # extends its rows to the other parameters and adds what they leave.
    cases = all_pairs(space; engine = C, stronger = [(:p1, :p2, :p3) => 3])
    @test iscomplete(coverage(cases)) && length(cases) == 343
    for (arity, group, rows) in ((fill(4, 16), (:p1, :p2, :p3, :p4), 64), (fill(3, 50), (:p1, :p2, :p3, :p4), 28),
                                 (fill(3, 12), Tuple(Symbol(:p, i) for i in 1:12), 53))
        seeded = all_pairs(space_of(arity); engine = C, stronger = [group => 3])
        plain = all_pairs(space_of(arity); stronger = [group => 3])
        @test iscomplete(coverage(seeded)) && length(seeded) <= length(plain)
        @test length(seeded) == rows && rows - _catalog_rows(3, arity[1], length(group)) <= 1   # its array, extended
        @test occursin("`stronger` group", fit(C, Profile(Request(space_of(arity); stronger = [group => 3]))).reason)
    end
    # A group at strength 4, where the catalog is weak, or one whose array is
    # smaller than the base array, is seeded with the base array.
    for (arity, group, s) in ((fill(2, 30), Tuple(Symbol(:p, i) for i in 1:8), 4), (fill(2, 100), (:p1, :p2, :p3), 3))
        f = fit(C, Profile(Request(space_of(arity); stronger = [group => s])))
        @test f.kind === :seeded && startswith(f.reason, "Kleitman-Spencer") && !occursin("`stronger` group", f.reason)
        @test iscomplete(coverage(all_pairs(space_of(arity); engine = C, stronger = [group => s])))
    end
    # With a rule, a partial row of the group's array that no valid row extends is dropped.
    ruled = space_of(fill(4, 16); constraints = [@forbid(p1 == p2)])
    seeded = all_pairs(ruled; engine = C, stronger = [(:p1, :p2, :p3, :p4) => 3])
    @test iscomplete(coverage(seeded)) && length(seeded) <= length(all_pairs(ruled; stronger = [(:p1, :p2, :p3, :p4) => 3]))
    # A rule with t + 1 parameters of mixed counts.
    space = space_of([4, 3, 2]; constraints = [forbid((p1 = 1, p2 = 1))])
    @test iscomplete(coverage(all_pairs(space; engine = C)))
end


@testitem "construction: with must-include rows, a catalog row is kept only for what they leave uncovered" setup=[CatalogSetup, ConstructionSetup] begin
    C = Construction()
    # Contract §9.10, §10.6: a result passed back as `must_include` keeps its
    # rows, in order, and gains rows only for targets they leave uncovered, so
    # a Construction() result passed back gains none, as with IPOG and Auto:
    # an exact array, one seeded under a rule, strength 3, a `stronger` group
    # (its rows partial), and the zero-sum array on mixed counts. Before the
    # review of Phase 2 the catalog's whole array came again after them.
    for (space, t, extra) in ((space_of(fill(7, 8)), 2, (;)),
                              (space_of(fill(7, 8); constraints = [@forbid(p1 == p2)]), 2, (;)),
                              (space_of(fill(3, 12)), 3, (;)),
                              (space_of(fill(4, 16)), 2, (; stronger = [(:p1, :p2, :p3, :p4) => 3])),
                              (space_of([5, 4, 3]), 2, (;)))
        rows = collect(covering(space; strength = t, engine = C, extra...))
        for engine in (C, IPOG(), Auto())
            again = covering(space; strength = t, engine, must_include = rows, extra...)
            @test collect(again) == rows && again.n_must_include == length(rows)
        end
        # Half of them: the catalog adds only what the other half held, never more than before.
        half = covering(space; strength = t, engine = C, must_include = rows[1:cld(length(rows), 2)], extra...)
        @test iscomplete(coverage(half)) && length(half) <= length(rows)
    end
    # One must-include row equal to a row of the orthogonal array: that row isn't repeated.
    oa = collect(all_pairs(space_of(fill(7, 8)); engine = C))
    cases = all_pairs(space_of(fill(7, 8)); engine = C, must_include = [oa[5]])
    @test length(cases) == 49 && allunique(collect(cases)) && cases[1] == oa[5] && Set(collect(cases)) == Set(oa)
    # At full strength every target is a whole row: the must-include rows,
    # completed, then every valid row they don't hold, IPOG's design exactly
    # (contract §7.8), whether they are complete, partial or repeated.
    for (space, t, must) in ((space_of([3, 4]), 2, [(p1 = 1, p2 = 1), (p1 = 2, p2 = 3)]),
                             (space_of([3, 4]), 2, [(p1 = 1,), (p1 = 2, p2 = 3)]),
                             (space_of([3, 4]), 2, [(p1 = 1, p2 = 1), (p1 = 1, p2 = 1)]),
                             (space_of([3, 3, 2]; constraints = [forbid((p1 = 1, p2 = 1))]), 3, [(p1 = 3,)]))
        full = covering(space; strength = t, engine = C, must_include = must)
        @test collect(full) == collect(covering(space; strength = t, must_include = must))
        @test full.n_must_include == length(must)
    end
end


@testitem "construction: a refusal is an ArgumentError, and a refused sub-request goes to IPOG" setup=[CatalogSetup, ConstructionSetup] begin
    C = Construction()
    space = space_of([3, 3, 2, 2, 2])
    message = try
        covering(space; engine = C)
        ""
    catch err
        err isa ArgumentError ? sprint(showerror, err) : "not an ArgumentError"
    end
    @test message == "ArgumentError: Construction() does not cover this request: mixed value counts on 5 " *
                     "parameters; the catalog covers equal value counts, or t + 1 = 3 parameters; IPOG() or Auto() covers any request"
    request = Request(space)
    @test_throws ArgumentError generate(C, request)
    @test_throws ArgumentError cover_ordinary(C, request, RequiredTargets(request, first(classify_targets(request))))
    # Invalid values: the ordinary rows are the catalog's. At strength 2 a
    # negative sub-request is at strength 1 on 3 parameters, which the catalog
    # refuses, so it goes to IPOG; at strength 3 it is at strength 2, which the
    # catalog covers.
    space = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3))
    request = Request(space; strength = 2)
    sub = _negative_request(request, NegativeProjection(space, 1), zeros(Int, 3, 0))
    @test _engine_for(C, sub) == IPOG() && _engine_for(C, request) === C
    cases = all_pairs(space; engine = C)
    @test iscomplete(coverage(cases)) && cases.negative_required == cases.negative_covered > 0
    @test count(!hasinvalid, collect(cases)) == 9                   # the orthogonal array OA(9; 2, 4, 3)
    request = Request(space; strength = 3)
    sub = _negative_request(request, NegativeProjection(space, 1), zeros(Int, 3, 0))
    @test _engine_for(C, sub) === C
    cases = all_triples(space; engine = C)
    @test iscomplete(coverage(cases)) && count(hasinvalid, collect(cases)) == 9
    # A negative must-include row goes with its sub-request (§10.6).
    cases = all_pairs(space; engine = C, must_include = [(a = Invalid(0), b = 2)])
    @test iscomplete(coverage(cases)) && cases.n_must_include == 1 && hasinvalid(cases[1])
end


@testitem "construction: no randomness" setup=[CatalogSetup, ConstructionSetup] begin
    using Random
    C = Construction()
    spaces = [(space_of(fill(5, 9)), 2), (space_of(fill(3, 14)), 3),
              (space_of(fill(4, 10); constraints = [forbid((p1 = 1, p2 = 2))]), 2)]
    for (space, t) in spaces
        Random.seed!(1)
        a = collect(covering(space; strength = t, engine = C))
        Random.seed!(2)
        rand(100)
        b = collect(covering(space; strength = t, engine = C))
        @test a == b
    end
    @test _build(_catalog_entry(3, 6, 30)) == _build(_catalog_entry(3, 6, 30))
end
