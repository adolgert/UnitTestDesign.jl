using Test
using TestItemRunner

# The 0.5 public interface (plan Phase 4 steps 2–5, 8, 9): `covering` and its
# fixed strengths, `excursions`, `full_factorial`, the four input forms, the
# keywords, the deprecated 0.4 spellings and the removed ones. Completeness is
# judged by the independent checker (checker.jl), never by the engines' own
# bookkeeping.

@testsnippet InterfaceSetup begin
    using UnitTestDesign: engine_rng, _stronger_from_wayness

    "The ArgumentError message of `f()`, or what happened instead."
    message(f) = try
        f()
        "no error"
    catch e
        e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e)): $(sprint(showerror, e))"
    end

    "A checker space for positional domains, named p1, p2, ... as a positional call names them."
    positional_checker(domains...; rules = []) =
        CheckSpace([Symbol(:p, i) for i in eachindex(domains)], collect(domains), rules)

    "Fable's solver example with concrete domain types (the fixtures' domains are `Any`)."
    fable_domains() = (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6])
    fable_rules() = [forbid((m, s) -> m == :fast && s != :none, :mode, :solver),
                     forbid((m, t) -> m == :exact && t == 1e-3, :mode, :tol)]
    fable_row = NamedTuple{(:mode, :solver, :tol), Tuple{Symbol, Symbol, Float64}}
end


@testitem "IPOG init" begin
    ipog = IPOG()
    @test isa(ipog, IPOG)
end


@testitem "GND init (§9.5, §9.6)" setup=[InterfaceSetup] begin
    using Random
    gnd1 = GND()
    @test gnd1.candidates == 50 && gnd1.seed == 0 && gnd1.rng === nothing
    # Each call starts a fresh generator from the seed.
    @test randn(engine_rng(gnd1)) == randn(engine_rng(gnd1)) == randn(Xoshiro(0))
    gnd2 = GND(candidates = 100, seed = 7)
    @test gnd2.candidates == 100 && gnd2.seed == 7
    @test randn(engine_rng(gnd2)) != randn(engine_rng(gnd1))
    caller = Xoshiro(23423523)
    gnd3 = GND(rng = caller)
    @test gnd3.candidates == 50 && gnd3.seed === nothing
    sample3 = randn(engine_rng(gnd3))
    @test sample3 == randn(engine_rng(gnd3))       # a copy, so repeated calls agree
    @test randn(caller) == sample3                 # and the caller's generator is unadvanced
    @test_throws ArgumentError GND(candidates = 0)
    # The 0.4 keyword M is deprecated and means candidates.
    gnd5 = @test_deprecated GND(rng = Xoshiro(23423523), M = 70)
    @test gnd5.candidates == 70
    # candidates and its alias M together is an error, whatever the values (§13.2).
    @test message(() -> GND(candidates = 50, M = 70)) ==
          "pass candidates only; M is its deprecated alias (contract §13.1)"
    @test occursin("pass candidates only", message(() -> GND(candidates = 20, M = 20)))
end


@testitem "covering: every input form gives a complete design of the right type (§1.3, §1.18)" setup=[Checker, InterfaceSetup] begin
    s = fable_solver.space
    space = TestSpace(fable_domains(); constraints = fable_rules())
    forms = [
        () -> (space,),                                                  # a TestSpace
        () -> (fable_domains(),),                                        # a NamedTuple of domains
        () -> Tuple(pairs(fable_domains())),                             # name => domain pairs
    ]
    for engine in (IPOG(), GND())
        designs = []
        for form in forms
            input = form()
            kw = input[1] isa TestSpace ? (;) : (constraints = fable_rules(),)
            for cases in (covering(input...; engine, kw...), covering(input...; strength = 2, engine, kw...),
                          all_pairs(input...; engine, kw...))
                @test cases isa TestCases{fable_row}
                @test eltype(cases) == fable_row
                @test collect(cases) isa Vector{fable_row}
                @test complete(check_design(collect(cases), s; strength = 2))
                @test (cases.strategy, cases.strength, cases.positional) == (:covering, 2, false)
                @test cases.engine == nameof(typeof(engine))
                @test parameters(cases.space) == [:mode, :solver, :tol]
                push!(designs, collect(cases))
            end
            one = all_values(input...; engine, kw...)
            @test complete(check_design(collect(one), s; strength = 1))
            @test one.strength == 1
            three = all_triples(input...; engine, kw...)
            @test complete(check_design(collect(three), s; strength = 3))
            @test Set(three) == Set(valid_rows(s))
        end
        # The same space in every form gives the same rows (§9.1).
        @test allequal(designs)
    end

    # Positional: a space named p1, p2, ... and tuples.
    domains = ([1, 2, 3], ["a", "b"], [true, false], 1:2)
    checker = positional_checker(domains...)
    for engine in (IPOG(), GND()), (f, strength) in ((all_values, 1), (all_pairs, 2), (all_triples, 3))
        cases = f(domains...; engine)
        @test cases isa TestCases{Tuple{Int, String, Bool, Int}}
        @test collect(cases) isa Vector{Tuple{Int, String, Bool, Int}}
        @test cases.positional && cases.strength == strength
        @test parameters(cases.space) == [:p1, :p2, :p3, :p4]
        @test complete(check_design(collect(cases), checker; strength))
        @test collect(covering(domains...; strength, engine)) == collect(cases)
    end
    # Vectors, ranges and tuples are all domains; the 0.4 sizes.
    @test length(all_pairs((1, 2), 1:2, [:a, :b])) == 4
    @test length(all_values([1, 2], ["a", "b", "c"], [4, 7])) == 3
    @test length(all_pairs([1, 2], ["a", "b", "c"], [4, 7])) == 6
    at = all_triples([1, 2], ["a", "b", "c"], [4, 7], [true, false])
    @test length(at) >= 12 && length(at[1]) == 4
end


@testitem "covering: rules, must_include and stronger on the 0.4 problems, both engines" setup=[IndexCoverage, InterfaceSetup] begin
    matrix(cases) = reduce(hcat, [collect(c) for c in cases])
    domains = (p1 = [1, 2], p2 = [true, false], p3 = ["a", "b", "c"])
    for engine in (IPOG(), GND())
        cases = covering(domains; engine, constraints = [forbid((y, z) -> y == false && z in ("b", "c"), :p2, :p3)])
        @test !isempty(cases) && all(c -> !(!c.p2 && c.p3 in ("b", "c")), cases)
        cases = covering(domains; engine, constraints = [forbid(case -> case.p1 == 2 && case.p3 in ("a", "b"))])
        @test !isempty(cases) && all(c -> !(c.p1 == 2 && c.p3 in ("a", "b")), cases)

        seeds = [[1, 2, 3, 4, 1, 2, 3, 4], fill(4, 8)]
        cases = covering(fill(1:4, 8)...; must_include = seeds, engine)
        @test cases[1] == Tuple(seeds[1]) && cases[2] == Tuple(seeds[2])
        @test cases.n_must_include == 2
        @test test_coverage(matrix(cases), fill(4, 8), 2).finish == 0

        stronger = [(1, 2, 3, 4, 5) => 3, [4, 5, 6] => 3, 11:18 => 4]
        cases = covering(fill(1:2, 20)...; stronger, engine = engine isa GND ? GND(candidates = 20) : engine)
        m = matrix(cases)
        arity = fill(2, 20)
        @test test_coverage(m, arity, 2).finish == 0
        @test test_coverage(m[1:5, :], arity[1:5], 3).finish == 0
        @test test_coverage(m[4:6, :], arity[4:6], 3).finish == 0
        @test test_coverage(m[11:18, :], arity[11:18], 4).finish == 0
        @test cases.stronger == [(:p1, :p2, :p3, :p4, :p5) => 3, (:p4, :p5, :p6) => 3,
                                 Tuple(Symbol(:p, i) for i in 11:18) => 4]
    end
    # A fixed default seed: two calls agree (§9.5).
    @test collect(all_pairs(fill(1:3, 6)...; engine = GND())) == collect(all_pairs(fill(1:3, 6)...; engine = GND()))
    @test all_pairs(fill(1:3, 6)...; engine = GND()).seed == 0
end


@testitem "constraints = builds a named space and is an error elsewhere (§12.11, §12.12)" setup=[Checker, InterfaceSetup] begin
    rule = forbid((a = 1, b = :x); reason = "one is never x")
    checker = CheckSpace((a = [1, 2, 3], b = [:x, :y]), [((:a, :b), (a, b) -> a == 1 && b == :x)])
    for cases in (covering((a = [1, 2, 3], b = [:x, :y]); constraints = [rule]),
                  covering(:a => [1, 2, 3], :b => [:x, :y]; constraints = [rule]),
                  all_pairs((a = [1, 2, 3], b = [:x, :y]); constraints = rule))
        @test length(cases.space.constraints) == 1
        @test !((a = 1, b = :x) in cases)
        @test Set(cases) == Set(valid_rows(checker))
        @test complete(check_design(collect(cases), checker))
        @test only(cases.excluded).target == (a = 1, b = :x)
        @test only(cases.excluded).labels == [UnitTestDesign.rule_label(cases.space, 1)]
    end
    # From (2, :x): (1, :x) is dropped; (3, :x) and (2, :y) remain.
    @test length(excursions((a = [1, 2, 3], b = [:x, :y]); from = (a = 2, b = :x), constraints = [rule])) == 3
    @test length(full_factorial((a = [1, 2, 3], b = [:x, :y]); constraints = [rule])) == 5

    space = TestSpace((a = [1, 2, 3], b = [:x, :y]))
    for f in (covering, all_values, all_pairs, excursions, full_factorial), constraints in ([rule], [])
        @test occursin("constraints belong to the space: build TestSpace(...; constraints) instead",
                       message(() -> f(space; constraints)))
        @test occursin("positional calls take no constraints; use a named space",
                       message(() -> f([1, 2, 3], [:x, :y]; constraints)))
    end
end


@testitem "fixed strengths take no strength (§13.1)" setup=[InterfaceSetup] begin
    for (f, s) in ((all_values, 1), (all_pairs, 2), (all_triples, 3))
        msg = message(() -> f([1, 2], [3, 4], [5, 6]; strength = s))
        @test occursin("$(nameof(f)) has strength $s and takes no `strength`", msg)
        @test occursin("covering(...; strength = $s)", msg)
        @test occursin("takes no `n_way`", message(() -> f([1, 2], [3, 4], [5, 6]; n_way = 2)))
        @test occursin("takes no `strength`", message(() -> f((a = [1, 2], b = [3, 4], c = [5, 6]); strength = 2)))
    end
    # A strength above the parameter count (§11.2), and below 1 (§11.1).
    @test occursin("larger than the number of parameters, 2", message(() -> all_triples([1, 2], [3, 4])))
    @test message(() -> covering([1, 2], [3, 4]; strength = 0)) ==
          "strength must be a positive integer, got 0 (contract §11.1)"
    @test message(() -> covering([1, 2], [3, 4]; strength = 1.5)) ==
          "strength must be a positive integer, got 1.5 (contract §11.1)"
end


@testitem "heterogeneous domains keep their values and types (§2.1–§2.4, §2.9)" setup=[Checker, InterfaceSetup] begin
    # Positional: 1 and 1.0 are two values, nothing and missing are values.
    domains = (Any[1, 1.0], [nothing, :x], [missing, 2])
    cases = covering(domains...)
    @test cases isa TestCases{Tuple{Union{Int, Float64}, Union{Nothing, Symbol}, Union{Missing, Int}}}
    @test any(r -> r[1] === 1, cases) && any(r -> r[1] === 1.0, cases)
    @test any(r -> r[2] === nothing, cases) && any(r -> r[3] === missing, cases)
    @test complete(check_design(collect(cases), positional_checker(domains...)))
    for x in (1, 1.0), y in (nothing, :x)
        @test any(r -> r[1] === x && r[2] === y, cases)   # each pair by identity
    end

    # Named: field types come from the values, a Union when they differ in type
    # and one concrete type when they share it, whatever the domain's element
    # type (§2.4). Rules see the values.
    nt = (x = Any[1, 1.0], y = [nothing, :a], z = Any[:s, :t])
    cases = all_pairs(nt; constraints = [@forbid(x === 1.0 && y === nothing)])
    @test cases isa TestCases{NamedTuple{(:x, :y, :z), Tuple{Union{Int, Float64}, Union{Nothing, Symbol}, Symbol}}}
    @test !any(r -> r.x === 1.0 && r.y === nothing, cases)
    @test any(r -> r.x === 1 && r.y === nothing, cases)
    @test Set(typeof(r.x) for r in cases) == Set([Int, Float64])

    # The fixture: rule 2 uses ==, which matches both 1 and 1.0 (§12.23).
    f = heterogeneous_values
    cases = all_pairs(test_space(f))
    @test complete(check_design(collect(cases), f.space))
    @test Set(typeof(r.x) for r in cases) == Set([Int, Float64])
    @test Set(typeof(r.y) for r in cases) == Set([Nothing, Symbol])
    @test all(r -> r.z === :s, cases)                      # "s" is infeasible
    @test Set(e.target for e in cases.excluded if e.status == :implied) ==
          Set([(y = nothing, z = "s"), (y = :a, z = "s")])
end


@testitem "must_include: partial and duplicate rows come first, in order (§10.1–§10.5, §10.7)" setup=[Checker, InterfaceSetup] begin
    completion = (mode = :exact, solver = :lu, tol = 1e-6)
    full = (mode = :exact, solver = :qr, tol = 1e-6)
    seeds = [(solver = :lu,), full, (solver = :lu,), full, (mode = :fast,)]
    given = deepcopy(seeds)
    for engine in (IPOG(), GND()), input in ((TestSpace(fable_domains(); constraints = fable_rules()),),
                                             (fable_domains(),))
        kw = input[1] isa TestSpace ? (;) : (constraints = fable_rules(),)
        cases = all_pairs(input...; must_include = seeds, engine, kw...)
        @test cases[1:4] == [completion, full, completion, full]   # duplicates kept
        @test cases[5].mode == :fast
        @test cases.n_must_include == 5
        @test complete(check_design(collect(cases), fable_solver.space))
        @test seeds == given                                     # §10.7
    end

    # Positional rows are tuples or vectors, complete.
    rows = [[1, "b", true], (2, "a", false), [1, "b", true]]
    cases = all_pairs([1, 2, 3], ["a", "b"], [true, false]; must_include = rows)
    @test cases[1:3] == [(1, "b", true), (2, "a", false), (1, "b", true)]
    @test complete(check_design(collect(cases), positional_checker([1, 2, 3], ["a", "b"], [true, false])))
    @test rows == [[1, "b", true], (2, "a", false), [1, "b", true]]

    # Errors name the row, the parameter and the value (§10.2–§10.4).
    positional = ([1, 2, 3], ["a", "b"], [true, false])
    @test occursin("must_include row 2: \"c\" is not a value of `p2`",
                   message(() -> all_pairs(positional...; must_include = [(1, "a", true), (1, "c", true)])))
    @test occursin("must_include row 1 has 2 values; the space has 3 parameters",
                   message(() -> all_pairs(positional...; must_include = [(1, "a")])))
    @test occursin("must_include row 1 is a NamedTuple; a positional call takes each row as a tuple or vector",
                   message(() -> all_pairs(positional...; must_include = [(p1 = 1,)])))
    @test occursin("wrap a single row in a vector: must_include = [(1, \"a\", true)]",
                   message(() -> all_pairs(positional...; must_include = (1, "a", true))))
    @test occursin("wrap a single row", message(() -> all_pairs(fable_domains(); must_include = (solver = :lu,))))
    msg = message(() -> all_pairs(test_space(partial_seeds); must_include = partial_seeds.request.infeasible))
    @test occursin("must_include row 1", msg) && occursin("no valid completion", msg) &&
          occursin("rules 1 and 2", msg)
    msg = message(() -> all_pairs(test_space(partial_seeds); must_include = [full, partial_seeds.request.violating[1]]))
    @test occursin("must_include row 2", msg) && occursin("breaks rule 1", msg)
    @test occursin("`speed` is not a parameter of this space; the parameters are mode, solver, tol",
                   message(() -> all_pairs(fable_domains(); must_include = [(speed = 1,)])))
    @test occursin("must_include row 1: 1 is not a value of `tol`",
                   message(() -> all_pairs(fable_domains(); must_include = [(tol = 1,)])))
    @test occursin("must_include is a list of rows", message(() -> all_pairs(positional...; must_include = 5)))
    @test occursin("must_include is a list of rows", message(() -> all_pairs(fable_domains(); must_include = :a)))
end


@testitem "must_include: an iterator is read once, so a Stateful or a generator keeps its rows (§10.5)" setup=[Checker, InterfaceSetup] begin
    # The rows are collected once, and that collection is validated and handed
    # on: a Stateful that validation had already consumed would give no rows.
    domains = fill(1:2, 3)
    checker = positional_checker(domains...)
    for rows in (() -> Iterators.Stateful([(2, 2, 2)]), () -> (Tuple(r) for r in [[2, 2, 2]]))
        for engine in (IPOG(), GND())
            cases = all_pairs(domains...; must_include = rows(), engine)
            @test cases[1] == (2, 2, 2) && cases.n_must_include == 1
            @test complete(check_design(collect(cases), checker))
        end
        for f in (excursions, full_factorial)
            cases = f(domains...; must_include = rows())
            @test cases[1] == (2, 2, 2) && cases.n_must_include == 1
        end
    end
    nt = (a = 1:2, b = 1:2, c = 1:2)
    for rows in (() -> Iterators.Stateful([(a = 2, b = 2, c = 2)]), () -> ((a = v, b = v, c = v) for v in [2]))
        cases = all_pairs(nt; must_include = rows())
        @test cases[1] == (a = 2, b = 2, c = 2) && cases.n_must_include == 1
        @test complete(check_design(collect(cases), CheckSpace(nt, [])))
    end
    # A partial named row from a Stateful is completed in place, first.
    cases = all_pairs(fable_domains(); constraints = fable_rules(), must_include = Iterators.Stateful([(solver = :lu,)]))
    @test cases[1] == (mode = :exact, solver = :lu, tol = 1e-6) && cases.n_must_include == 1
end


@testitem "must_include: a TestCases is kept and topped up (§9.10, §10.1)" setup=[Checker, InterfaceSetup] begin
    space = TestSpace(fable_domains(); constraints = fable_rules())
    existing = all_values(space)
    for engine in (IPOG(), GND())
        topped = all_pairs(space; must_include = existing, engine)
        n = length(existing)
        @test collect(topped[1:n]) == collect(existing)
        @test topped.n_must_include == n
        @test complete(check_design(collect(topped), fable_solver.space))
    end
    # A complete design as must_include adds nothing.
    cases = all_pairs(space)
    @test collect(all_pairs(space; must_include = cases)) == collect(cases)
    # A TestCases over some of the parameters gives partial rows, completed in place.
    small = all_pairs((mode = [:fast, :exact], solver = [:none, :lu, :qr]); constraints = fable_rules()[1:1])
    topped = all_pairs(space; must_include = small)
    @test [(r.mode, r.solver) for r in topped[1:length(small)]] == [(r.mode, r.solver) for r in small]
    @test complete(check_design(collect(topped), fable_solver.space))
    # A TestCases with a parameter the space lacks is an error naming it.
    other = all_pairs((mode = [:fast, :exact], speed = [1, 2]))
    msg = message(() -> all_pairs(space; must_include = other))
    @test occursin("must_include is a TestCases over mode, speed", msg) && occursin("`speed` is not a parameter", msg)
    # Positional: a positional TestCases over the same parameters.
    domains = ([1, 2, 3], [:a, :b], [true, false])
    before = all_values(domains...)
    after = all_pairs(domains...; must_include = before)
    @test collect(after[1:length(before)]) == collect(before)
    @test complete(check_design(collect(after), positional_checker(domains...)))
    @test occursin("a positional call takes complete rows",
                   message(() -> all_pairs(domains..., [0, 1]; must_include = before)))
end


@testitem "stronger: overlapping groups, positional groups, the caller's vector untouched (§11.3–§11.9)" setup=[Checker, InterfaceSetup] begin
    f = overlapping_groups
    for engine in (IPOG(), GND()), stronger in (f.request.stronger, f.request.stronger_twice)
        given = deepcopy(stronger)
        groups = [first(g) for g in given]
        cases = covering(test_space(f); stronger = given, engine)
        @test complete(check_design(collect(cases), f.space; stronger = f.request.stronger))
        @test given == stronger && all(first(g) === k for (g, k) in zip(given, groups))
        @test cases.stronger == [(:a, :b, :c) => 3, (:b, :c, :d) => 3]
        @test cases.stronger !== given
    end
    # Positional groups: tuples, vectors, ranges of positions.
    domains = fill(1:2, 6)
    given = [(1, 3, 4) => 3, [4, 5, 6] => 3, 2:4 => 3]
    snapshot = deepcopy(given)
    cases = covering(domains...; stronger = given)
    @test given == snapshot
    @test complete(check_design(collect(cases), positional_checker(domains...);
                                stronger = [(:p1, :p3, :p4) => 3, (:p4, :p5, :p6) => 3, (:p2, :p3, :p4) => 3]))
    # A group at the base strength adds nothing (§11.7).
    @test collect(covering(fill(1:3, 5)...; stronger = [(1, 2, 3) => 2])) == collect(covering(fill(1:3, 5)...))
    @test isempty(covering(fill(1:3, 5)...; stronger = [(1, 2, 3) => 2]).stronger)
    # Errors name the group (§11.4–§11.6).
    nt = (a = [1, 2], b = [1, 2], c = [1, 2], d = [1, 2])
    @test occursin("`z` is not a parameter", message(() -> covering(nt; stronger = [(:a, :z) => 2])))
    @test occursin("lists a parameter twice", message(() -> covering(nt; stronger = [(:a, :b, :a) => 3])))
    @test occursin("below the base strength 2", message(() -> covering(nt; stronger = [(:a, :b, :c) => 1])))
    @test occursin("above its size 2", message(() -> covering(nt; stronger = [(:a, :b) => 3])))
    @test occursin("names parameter 9, but the space has 6 parameters",
                   message(() -> covering(domains...; stronger = [(1, 2, 9) => 3])))
end


@testitem "excursions: distance 0, 1 and 2 from a base; dropped rows in notes (§7.5–§7.7)" setup=[Checker, InterfaceSetup] begin
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    checker = CheckSpace(names, domains, [((:b, :c), (b, c) -> b == :y && c == true)])
    nt = (a = [1, 2, 3], b = [:x, :y], c = [true, false])
    rules = [forbid((b = :y, c = true); reason = "y needs c off")]
    within(case, base, d) = count(k -> case[k] != base[k], keys(base)) <= d

    # The default base: the first value of each parameter.
    cases = excursions(nt; constraints = rules)
    @test cases isa TestCases{NamedTuple{(:a, :b, :c), Tuple{Int, Symbol, Bool}}}
    @test collect(cases) == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                             (a = 1, b = :x, c = false)]
    @test (cases.strategy, cases.positional) == (:excursion, false)
    @test cases.notes.dropped == 1 && cases.notes.distance == 1
    @test cases.notes.never_appear == [:b => :y]              # b = :y never appears
    @test cases.notes.base === cases[1] && cases.strength == 0
    # No covering claim: a feasible value is missing (§7.7).
    @test check_design(collect(cases), checker; strength = 1).ordinary.missing == [(b = :y,)]

    base = (a = 2, b = :y, c = false)
    for d in (0, 1, 2)
        near = excursions(nt; from = base, distance = d, constraints = rules)
        @test near[1] == base
        @test allunique(near)
        @test all(c -> within(c, base, d), near)
        @test Set(near) == Set(filter(c -> within(c, base, d), valid_rows(checker)))
        @test near.notes.distance == d
    end
    @test collect(excursions(nt; from = base, distance = 0, constraints = rules)) == [base]
    @test excursions(nt; from = base, distance = 1, constraints = rules).notes.dropped == 1  # (2, :y, true)

    # Positional: `from` is a tuple, or a vector of values.
    pos = excursions([1, 2, 3], [:x, :y], [true, false]; from = (3, :y, false), distance = 2)
    @test pos isa TestCases{Tuple{Int, Symbol, Bool}}
    @test pos[1] == (3, :y, false) && pos.positional
    @test all(c -> count(i -> c[i] != pos[1][i], 1:3) <= 2, pos)
    @test length(pos) == 1 + 4 + 2 * 1 + 2 * 1 + 1 * 1
    @test collect(excursions([1, 2, 3], [:x, :y], [true, false]; from = [3, :y, false], distance = 2)) == collect(pos)
    # A distance above the parameter count is the parameter count (§7.5).
    @test length(excursions([1, 2], [:a, :b]; distance = 5)) == 4
    @test collect(excursions([1, 2, 3])) == [(1,), (2,), (3,)]   # one parameter is fine

    # Must-include rows first, and not repeated (§7.11).
    seeds = [(a = 3, b = :y, c = false), (a = 2, b = :x, c = true), (c = false,)]
    cases = excursions(nt; must_include = seeds, constraints = rules)
    @test cases[1:3] == [seeds[1], seeds[2], (a = 1, b = :x, c = false)]  # completed toward the base
    @test collect(cases[4:end]) == [(a = 1, b = :x, c = true), (a = 3, b = :x, c = true)]
    @test cases.n_must_include == 3
    # A duplicated must-include row keeps both copies, first (§10.5); the base
    # and the other excursion rows follow once each, without a third copy (§7.11).
    twice = [(a = 2, b = :x, c = true), (a = 2, b = :x, c = true)]
    cases = excursions(nt; must_include = twice, constraints = rules)
    @test collect(cases) == [twice; (a = 1, b = :x, c = true); (a = 3, b = :x, c = true); (a = 1, b = :x, c = false)]
    @test cases.n_must_include == 2 && allunique(cases[2:end])

    # Errors: a base that breaks a rule, a partial base, a negative distance, stronger (§7.5, §7.6).
    msg = message(() -> excursions(nt; from = (a = 1, b = :y, c = true), constraints = rules))
    @test occursin("breaks rule 1 (y needs c off)", msg) && occursin("§7.6", msg)
    @test occursin("it must name every parameter", message(() -> excursions(nt; from = (a = 1,))))
    @test message(() -> excursions(nt; distance = -1)) == "distance must be an integer of at least 0, got -1 (contract §7.5)"
    @test message(() -> excursions(nt; distance = 1.5)) == "distance must be an integer of at least 0, got 1.5 (contract §7.5)"
    @test occursin("the excursion base `from` is a Symbol", message(() -> excursions(nt; from = :a)))
    @test message(() -> excursions(nt; stronger = [(:a, :b, :c) => 3])) ==
          "excursions take a single distance; stronger groups apply to covering designs"
    @test_throws MethodError excursions(nt; strength = 2)
end


@testitem "full_factorial: every valid row; the limit error names the count (§7.2–§7.4)" setup=[Checker, InterfaceSetup] begin
    for f in (astra_chain, fable_solver, opus_gpu, disconnected_witness, whole_case_connects, overlapping_groups)
        cases = full_factorial(test_space(f))
        valid = valid_rows(f.space)
        @test Set(cases) == Set(valid) && length(cases) == length(valid)
        @test cases.strategy == :full_factorial
        @test cases.notes == (candidates = prod(length.(f.input.domains)), accepted = length(valid))
    end
    @test isempty(full_factorial(test_space(disconnected_unsat)))

    cases = full_factorial([1:2, 1:2, 1:3, 1:2]...)
    @test cases isa TestCases{Tuple{Int, Int, Int, Int}}
    @test length(cases) == 24 && allunique(cases)
    @test cases[1:3] == [(1, 1, 1, 1), (1, 1, 1, 2), (1, 1, 2, 1)]   # the last parameter fastest
    @test collect(full_factorial([1])) == [(1,)]
    cases = full_factorial((a = [1, 2, 3], b = [7, 8], c = [true, false]); constraints = [forbid((b = 7, c = false))])
    @test length(cases) == 9 && !any(r -> r.b == 7 && !r.c, cases)
    @test cases.notes == (candidates = 12, accepted = 9)

    # Must-include rows first, not repeated.
    seeds = [(mode = :exact, solver = :qr, tol = 1e-6), (solver = :lu,)]
    cases = full_factorial(fable_domains(); constraints = fable_rules(), must_include = seeds)
    @test cases[1:2] == [seeds[1], (mode = :exact, solver = :lu, tol = 1e-6)]
    @test length(cases) == 5 && Set(cases) == Set(valid_rows(fable_solver.space))

    # A duplicated must-include row keeps both copies, first (§10.5); then each
    # remaining valid row once, and never a third copy (§7.2).
    twice = [(mode = :fast, solver = :none, tol = 1e-6), (mode = :fast, solver = :none, tol = 1e-6), (solver = :qr,)]
    cases = full_factorial(fable_domains(); constraints = fable_rules(), must_include = twice)
    @test cases[1:3] == [twice[1], twice[1], (mode = :exact, solver = :qr, tol = 1e-6)]
    @test cases.n_must_include == 3 && length(cases) == 3 + 3
    rest = collect(cases[4:end])
    @test allunique(rest) && isempty(intersect(rest, cases[1:3]))
    @test Set(cases) == Set(valid_rows(fable_solver.space))
    @test collect(full_factorial([1, 2], [:a, :b]; must_include = [(2, :b), (2, :b)])) ==
          [(2, :b), (2, :b), (1, :a), (1, :b), (2, :a)]

    # The limit refuses before enumerating (§7.3).
    err = try full_factorial(fill(1:2, 21)...) catch e; e end
    @test err isa ResourceLimitError && err.keyword == :limit && err.limit == 10^6
    @test occursin("2_097_152 candidate rows", sprint(showerror, err))
    @test occursin("`limit = 1_000_000`", sprint(showerror, err))
    err = try full_factorial([1, 2], [3, 4], [5, 6]; limit = 7) catch e; e end
    @test err isa ResourceLimitError && occursin("8 candidate rows", sprint(showerror, err))
    @test length(full_factorial([1, 2], [3, 4], [5, 6]; limit = 8)) == 8
    # The count comes before any must-include search: with eight candidates and
    # limit = 1, a partial row under a lazy rule gives the limit error, not a
    # feasibility_limit error for a search that would have been wasted.
    seen = Ref(0)
    lazy = TestSpace((a = [1, 2], b = [3, 4], c = [5, 6]); tabulation_limit = 1,
                     constraints = [forbid(case -> (seen[] += 1; case.a == 1 && case.c == 6); reason = "lazy")])
    partial = [(a = 1,)]
    seen[] = 0
    err = try full_factorial(lazy; must_include = partial, limit = 1, feasibility_limit = 1) catch e; e end
    @test err isa ResourceLimitError && err.keyword == :limit && err.limit == 1
    @test occursin("8 candidate rows", sprint(showerror, err))
    @test seen[] == 0
    # Within the limit, the same call searches, and its budget is what runs out.
    err = try full_factorial(lazy; must_include = partial, limit = 8, feasibility_limit = 1) catch e; e end
    @test err isa ResourceLimitError && err.keyword == :feasibility_limit
    @test seen[] > 0
    @test occursin("full_factorial returns every valid row",
                   message(() -> full_factorial([1, 2], [3, 4]; stronger = [(1, 2) => 2])))
end


@testitem "explanation_limit: running out leaves a complete design with an unresolved attribution (§3.13–§3.16)" setup=[Checker, InterfaceSetup] begin
    space = TestSpace(fable_domains(); constraints = fable_rules())
    for engine in (IPOG(), GND())
        cases = all_pairs(space; explanation_limit = 1, engine)
        full = all_pairs(space; engine)
        # Certified and complete, and the same rows: only the attribution changes.
        @test complete(check_design(collect(cases), fable_solver.space))
        @test collect(cases) == collect(full)
        implied = [e for e in cases.excluded if e.status === :implied]
        @test [e.target for e in implied] == [(solver = :lu, tol = 1e-3), (solver = :qr, tol = 1e-3)]
        @test all(e -> e.minimal === :unresolved && e.limit == (:explanation_limit => 1), implied)
        @test all(e -> e.minimal === :verified && e.limit === nothing,
                  [e for e in full.excluded if e.status === :implied])
        text = split(sprint(show, MIME"text/plain"(), cases), '\n')
        @test text[2] == "excluded: 3 pairs forbidden, 2 impossible under the constraints, " *
                         "2 with an unresolved explanation; see report(cases)"
        @test !occursin("unresolved", sprint(show, MIME"text/plain"(), full))
    end
    # A must-include row with no completion is still an error; the budget only
    # leaves its explanation unresolved. feasibility_limit is what throws.
    row = [(solver = :lu, tol = 1e-3)]
    for f in (all_pairs, excursions, full_factorial)
        msg = message(() -> f(space; must_include = row, explanation_limit = 1))
        @test occursin("has no valid completion: rules 1 and 2 together exclude it", msg)
        @test occursin("unresolved: explanation_limit = 1 reached", msg)
    end
end


@testitem "feasibility_limit: rows, counts and exclusion statuses do not depend on it; explanations may (§3.8, §3.14)" begin
    # (w = 1, v = 1) is excluded twice over: by rule 1, which forward checking
    # sees at once, and by rules 2 to 7, which, when w = 1 and v = 1, make
    # x, y, z and u all different, four parameters with three values each.
    # Proving that takes more nodes than the small limits below allow.
    names4 = (:x, :y, :z, :u)
    pigeons = [forbid((w, v, p, q) -> w == 1 && v == 1 && p == q, :w, :v, a, b)
               for (i, a) in enumerate(names4) for b in names4[(i + 1):end]]
    domains = (w = [1, 2], v = [1, 2], a = [1, 2], x = 1:3, y = 1:3, z = 1:3, u = 1:3)
    space = TestSpace(domains; constraints = [forbid((w, v, a) -> w == 1 && v == 1, :w, :v, :a); pigeons])
    counts(c) = (c.required, c.covered, c.negative_required, c.negative_covered)
    statuses(c) = [(e.target, e.status) for e in [c.excluded; c.negative_excluded]]
    "Brute force: every row of the product that holds the target breaks one of these rules."
    function sufficient(e)
        rules_only = TestSpace(domains; constraints = space.constraints[e.rules])
        rows = (NamedTuple{keys(domains)}(v) for v in Iterators.product(domains...))
        return all(r -> !isallowed(rules_only, r),
                   Iterators.filter(r -> all(k -> r[k] == e.target[k], keys(e.target)), rows))
    end

    reference = all_pairs(space)
    @test statuses(reference) == [((w = 1, v = 1), :implied)]
    for limit in (6, 10, 14)
        cases = all_pairs(space; feasibility_limit = limit)
        @test collect(cases) == collect(reference)
        @test counts(cases) == counts(reference)
        @test statuses(cases) == statuses(reference)
        # The explanation names a sufficient set, whichever set it is. Here a
        # deletion trial stops at feasibility_limit, keeps its rule, and the
        # explanation names that limit (§3.14).
        e = only(cases.excluded)
        @test sufficient(e)
        @test (e.minimal, e.limit) == (:unresolved, :feasibility_limit => limit)
    end
    @test sufficient(only(reference.excluded))
end


@testitem "strength equal to the parameter count is the full factorial, as a set (§7.8, §11.2)" setup=[Checker, InterfaceSetup] begin
    space = TestSpace(fable_domains(); constraints = fable_rules())
    for engine in (IPOG(), GND())
        @test Set(covering(space; strength = 3, engine)) == Set(full_factorial(space))
        @test Set(covering([1, 2], [3, 4, 5], [:a, :b]; strength = 3, engine)) ==
              Set(full_factorial([1, 2], [3, 4, 5], [:a, :b]))
    end
    @test occursin("larger than the number of parameters", message(() -> covering(space; strength = 4)))
end


@testitem "single-valued parameters (§2.7)" setup=[InterfaceSetup] begin
    rows = all_pairs([1], [1, 2], [:a, :b])
    @test length(rows) == 4
    @test all(r -> r[1] == 1, rows)
    @test Set(r[2:3] for r in rows) == Set([(1, :a), (1, :b), (2, :a), (2, :b)])
    @test collect(all_values([:only])) == [(:only,)]
    @test collect(covering((a = [1], b = [2]))) == [(a = 1, b = 2)]
    @test collect(excursions([1], [2, 3])) == [(1, 2), (1, 3)]
    @test collect(full_factorial([1], [2])) == [(1, 2)]
end


@testitem "input errors use the caller's vocabulary (§0.1)" setup=[InterfaceSetup] begin
    @test occursin("all_pairs needs the parameters", message(() -> all_pairs()))
    @test occursin("parameter `p1` lists `1` twice", message(() -> all_pairs([1, 1, 2], [3, 4])))
    @test occursin("parameter `p2` lists its values in a Set", message(() -> all_pairs([1, 2], Set([3, 4]))))
    @test occursin("argument 1 of all_pairs is a TestSpace among other arguments",
                   message(() -> all_pairs(TestSpace((a = [1, 2],)), [1, 2])))
    @test occursin("parameter names are Symbols", message(() -> covering("a" => [1, 2], "b" => [3, 4])))
    @test occursin("`engine` is a covering engine such as IPOG(), Construction(), Compact(IPOG()) or Auto(); got :ipog",
                   message(() -> covering([1, 2], [3, 4]; engine = :ipog)))
    @test occursin("`engine` is a covering engine such as", message(() -> all_pairs((a = [1, 2], b = [3, 4]); engine = "GND")))
end


@testitem "keyword values are checked before they are sorted or converted (§3.3, §7.3, §7.5, §7.6, §9.5, §11.1, §11.3, §11.10)" setup=[InterfaceSetup] begin
    using Random: Xoshiro
    d = ([1, 2], [3, 4], [5, 6])
    nt = (a = [1, 2], b = [3, 4], c = [5, 6])

    # wayness: every key is checked before the keys are sorted, so an Int beside
    # a Symbol is not a MethodError from isless.
    mixed = Dict{Any, Any}(3 => [[1, 2, 3]], :a => [[1, 2]])
    form = "`wayness` is a Dict{Int, Vector{Vector{Int}}} from a strength to parameter index groups, " *
           "such as Dict(3 => [[3, 4, 5, 6]])"
    @test message(() -> covering(fill(1:2, 4)...; wayness = mixed)) ==
          form * "; got the key :a, which is not an integer strength (contract §11.10)"
    @test message(() -> _stronger_from_wayness(mixed)) ==
          form * "; got the key :a, which is not an integer strength (contract §11.10)"
    @test occursin("got the key 3.0", message(() -> _stronger_from_wayness(Dict(3.0 => [[1, 2, 3]]))))
    @test message(() -> _stronger_from_wayness([[1, 2, 3]])) == form * "; got [[1, 2, 3]] (contract §11.10)"
    @test _stronger_from_wayness(Dict{Integer, Any}(Int32(3) => [[1, 2, 3]], 4 => [1:4])) ==
          [[1, 2, 3] => 3, [1, 2, 3, 4] => 4]

    # GND: candidates, M and seed are integers, checked before Int(...).
    @test message(() -> GND(candidates = 1.5)) == "candidates must be a positive integer, got 1.5 (contract §9.5)"
    @test message(() -> GND(candidates = 2.0)) == "candidates must be a positive integer, got 2.0 (contract §9.5)"
    @test message(() -> GND(candidates = :a)) == "candidates must be a positive integer, got :a (contract §9.5)"
    @test message(() -> GND(candidates = true)) == "candidates must be a positive integer, got true (contract §9.5)"
    @test message(() -> GND(candidates = 0)) == "candidates must be a positive integer, got 0 (contract §9.5)"
    @test message(() -> GND(candidates = big(2)^70)) ==
          "candidates must be a positive integer that fits in an Int, got 1180591620717411303424 (contract §9.5)"
    @test message(() -> GND(M = 1.5)) == "M must be a positive integer, got 1.5 (contract §9.5)"
    @test message(() -> GND(seed = 1.5)) == "seed must be an integer of at least 0, got 1.5 (contract §9.5)"
    @test message(() -> GND(seed = :a)) == "seed must be an integer of at least 0, got :a (contract §9.5)"
    @test message(() -> GND(seed = nothing)) == "seed must be an integer of at least 0, got nothing (contract §9.5)"
    # Julia 1.10's Xoshiro refuses a negative seed, so GND does on every version.
    @test message(() -> GND(seed = -1)) == "seed must be an integer of at least 0, got -1 (contract §9.5)"
    @test message(() -> GND(seed = typemax(UInt64))) ==
          "seed must be an integer of at least 0 that fits in an Int, got 0xffffffffffffffff (contract §9.5)"
    @test message(() -> GND(seed = 1.5, rng = Xoshiro(1))) == "seed must be an integer of at least 0, got 1.5 (contract §9.5)"
    @test GND(seed = nothing, rng = Xoshiro(1)).seed === nothing
    @test message(() -> GND(rng = :a)) ==
          "rng must be a random number generator, an AbstractRNG such as Xoshiro(1), got :a (contract §9.6)"
    gnd = GND(seed = UInt8(3), candidates = Int32(7))       # any integer type is read as an Int
    @test (gnd.seed, gnd.candidates) === (3, 7)

    # strength and its alias n_way.
    @test message(() -> covering(d...; strength = 2.0)) == "strength must be a positive integer, got 2.0 (contract §11.1)"
    @test message(() -> covering(d...; strength = :a)) == "strength must be a positive integer, got :a (contract §11.1)"
    @test message(() -> covering(d...; strength = true)) == "strength must be a positive integer, got true (contract §11.1)"
    @test message(() -> covering(d...; n_way = 1.5)) == "n_way must be a positive integer, got 1.5 (contract §11.1)"
    @test message(() -> covering(d...; n_way = 0)) == "n_way must be a positive integer, got 0 (contract §11.1)"
    @test covering(d...; strength = Int32(3)).strength == 3

    # distance, and n_way as an excursion's distance. A distance beyond Int is
    # above the parameter count, so it is the parameter count (§7.5).
    @test message(() -> excursions(d...; distance = :a)) == "distance must be an integer of at least 0, got :a (contract §7.5)"
    @test message(() -> excursions(d...; distance = true)) == "distance must be an integer of at least 0, got true (contract §7.5)"
    @test @test_deprecated(message(() -> values_excursion(d...; n_way = 1.5))) ==
          "n_way, an excursion's distance, must be an integer of at least 0, got 1.5 (contract §7.5)"
    @test excursions(d...; distance = big(10)^30).notes.distance == 3
    @test length(excursions(d...; distance = UInt8(1))) == 4

    # full_factorial's limit.
    @test message(() -> full_factorial(d...; limit = 1.5)) == "limit must be a positive integer, got 1.5 (contract §7.3)"
    @test message(() -> full_factorial(d...; limit = true)) == "limit must be a positive integer, got true (contract §7.3)"
    @test message(() -> full_factorial(d...; limit = big(10)^30)) ==
          "limit must be a positive integer that fits in an Int, got 1000000000000000000000000000000 (contract §7.3)"
    @test length(full_factorial(d...; limit = Int32(8))) == 8

    # The search budgets, on every entry point: an ArgumentError naming the
    # keyword, never a TypeError from a keyword's type or an InexactError.
    for f in (covering, all_values, all_pairs, all_triples, excursions, full_factorial),
            keyword in (:feasibility_limit, :explanation_limit)
        @test message(() -> f(d...; (keyword => 1.5,)...)) ==
              "$keyword must be a positive integer, got 1.5 (contract §3.3, §3.13)"
        @test message(() -> f(d...; (keyword => true,)...)) ==
              "$keyword must be a positive integer, got true (contract §3.3, §3.13)"
        @test message(() -> f(d...; (keyword => big(10)^30,)...)) ==
              "$keyword must be a positive integer that fits in an Int, got 1000000000000000000000000000000 " *
              "(contract §3.3, §3.13)"
    end

    # from: its shape, then its names and values, each error naming `from`.
    @test message(() -> excursions(d...; from = (1, 3))) ==
          "the excursion base `from` has 2 values; the space has 3 parameters (p1, p2, p3) (contract §7.6)"
    @test message(() -> excursions(d...; from = [1, 3, 5, 7])) ==
          "the excursion base `from` has 4 values; the space has 3 parameters (p1, p2, p3) (contract §7.6)"
    @test message(() -> excursions(d...; from = (p1 = 1, p2 = 3, p3 = 5))) ==
          "`from` is a NamedTuple; a positional call takes the base as a tuple or vector of values in " *
          "argument order, one for each of p1, p2, p3 (contract §7.6)"
    @test message(() -> excursions(nt; from = (a = 1, b = 3, c = 5, d = 1))) ==
          "the excursion base `from`: `d` is not a parameter of this space; the parameters are a, b, c"
    @test startswith(message(() -> excursions(nt; from = (a = 9, b = 3, c = 5))),
                     "the excursion base `from`: 9 is not a value of `a`")
    @test message(() -> excursions(nt; from = Dict(:a => 1))) ==
          "the excursion base `from` is a Dict{Symbol, Int64}; a row is a NamedTuple, or a tuple or " *
          "vector with one value per parameter (contract §7.6)"
    @test excursions(nt; from = (1, 4, 6), distance = 0)[1] == (a = 1, b = 4, c = 6)   # values in parameter order

    # stronger: a vector of group => strength pairs, each group a tuple or vector.
    @test message(() -> covering(d...; stronger = :a)) ==
          "stronger is a vector of `group => strength` pairs, such as [(:a, :b, :c) => 3]; got :a (contract §11.3)"
    @test message(() -> covering(d...; stronger = 5)) ==
          "stronger is a vector of `group => strength` pairs, such as [(:a, :b, :c) => 3]; got 5 (contract §11.3)"
    @test message(() -> covering(d...; stronger = (1, 2, 3) => 3)) ==
          "stronger is a vector of `group => strength` pairs; wrap a single group in a vector: " *
          "stronger = [(1, 2, 3) => 3] (contract §11.3)"
    @test message(() -> covering(nt; stronger = [:a => 3])) ==
          "each `stronger` group is a tuple or vector of parameter names or indices, such as " *
          "(:a, :b, :c) => 3; got :a => 3 (contract §11.3)"
    @test message(() -> covering(d...; stronger = [(1, 2, 3) => 2.5])) ==
          "`stronger` strength for (1, 2, 3) must be an integer, got 2.5 (contract §11.6)"
    @test message(() -> covering(d...; stronger = [(1, true) => 2])) ==
          "`stronger` group members are names or indices; got true"
end


@testitem "every row a caller writes is read by one reader, whose errors read alike (§1.13, §1.25, §1.26, §2.11, §7.6, §10.1)" setup=[InterfaceSetup] begin
    space = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [true, false]))
    valid = (1, :x, true)
    # What each caller calls the row, the section its errors cite, whether the
    # row must be complete, the hint a partial row's error adds, and a call
    # that reads the row `r`.
    readers = [
        ("coverage row 2", " (contract §1.13)", true, "", r -> coverage([valid, r], space)),
        ("diagnose case 2", "", true, "", r -> diagnose([valid, r], [true, false]; space)),
        ("must_include row 2", " (contract §10.1)", false, "", r -> all_pairs(space; must_include = [valid, r])),
        ("the excursion base `from`", " (contract §7.6)", true, "", r -> excursions(space; from = r)),
        ("the case", " (contract §1.25)", true, "; use explain for a partial assignment", r -> isallowed(space, r)),
        ("the assignment", " (contract §1.26)", false, "", r -> explain(space, r)),
    ]
    for (what, cited, complete, hint, call) in readers
        @test message(() -> call(:a)) ==
              "$what is a Symbol; a row is a NamedTuple, or a tuple or vector with one value per parameter$cited"
        @test message(() -> call((1, :x))) == "$what has 2 values; the space has 3 parameters (a, b, c)$cited"
        @test message(() -> call([1, :x, true, 4])) ==
              "$what has 4 values; the space has 3 parameters (a, b, c)$cited"
        @test message(() -> call((a = 1, d = 2))) ==
              "$what: `d` is not a parameter of this space; the parameters are a, b, c"
        @test startswith(message(() -> call([1, :z, true])), "$what: :z is not a value of `b`")
        partial = message(() -> call((c = false, a = 2)))
        @test partial == (complete ? "$what, (c = false, a = 2), has no value for `b`; it must name every " *
                                     "parameter$hint$cited" : "no error")
    end
    # classify takes NamedTuple targets only; their names and values read alike.
    @test message(() -> UnitTestDesign.classify(space, [(a = 1, d = 2)])) ==
          "the target: `d` is not a parameter of this space; the parameters are a, b, c"
end


@testitem "a collection of values, not rows, is a single row: coverage and diagnose show it wrapped, must_include the tuple of its values (§1.12, §10.1)" setup=[InterfaceSetup] begin
    space = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [true, false]))
    @test message(() -> coverage(Dict(:a => 1), space)) ==
          "coverage takes a collection of rows; wrap a single row in a vector: coverage([Dict(:a => 1)], space)"
    @test message(() -> coverage("abc", space)) ==
          "coverage takes a collection of rows; wrap a single row in a vector: coverage([\"abc\"], space)"
    @test message(() -> diagnose(Dict(:a => 1), [true]; space)) ==
          "diagnose takes a collection of cases; wrap a single case in a vector: " *
          "diagnose([Dict(:a => 1)], passed; space)"
    @test message(() -> diagnose("abc", [true]; space)) ==
          "diagnose takes a collection of cases; wrap a single case in a vector: diagnose([\"abc\"], passed; space)"
    @test message(() -> all_pairs(space; must_include = Dict(:a => 1))) ==
          "must_include is a list of rows; wrap a single row in a vector: must_include = [(:a => 1,)]"
    @test message(() -> all_pairs(space; must_include = "abc")) ==
          "must_include is a list of rows; wrap a single row in a vector: must_include = [('a', 'b', 'c')]"
    @test message(() -> all_pairs(space; must_include = (v for v in (1, :x, true)))) ==
          "must_include is a list of rows; wrap a single row in a vector: must_include = [(1, :x, true)]"
end


@testitem "removed: Excursion, generate_tuples, disallow, Counter (§12.10, §13.3)" begin
    using Base.CoreLogging: with_logger, NullLogger   # Logging is not a test dependency
    @test !isdefined(UnitTestDesign, :Excursion)
    @test !(:Excursion in names(UnitTestDesign))
    @test !isdefined(UnitTestDesign, :generate_tuples)
    @test !isdefined(UnitTestDesign, :wrap_disallow)
    @test !isdefined(UnitTestDesign, :seeds_to_integers)
    for f in (covering, all_values, all_pairs, all_triples, excursions, full_factorial)
        @test_throws MethodError f([1, 2], [3, 4], [5, 6]; disallow = (a, b, c) -> false)
        @test_throws MethodError f((a = [1, 2], b = [3, 4], c = [5, 6]); disallow = (a, b, c) -> false)
    end
    @test_throws MethodError all_pairs([1, 2], [3, 4], [5, 6]; Counter = Int8)
    with_logger(NullLogger()) do   # the aliases warn before the keyword error
        @test_throws MethodError all_tuples([1, 2], [3, 4]; n_way = 1, disallow = (a, b) -> false)
        @test_throws MethodError pairs_excursion([1, 2], [3, 4], [5, 6]; disallow = (a, b, c) -> false)
    end
    # The new names are exported, and the deprecated aliases still are.
    for name in (:covering, :excursions, :TestCases, :Exclusion, :all_values, :all_pairs, :all_triples,
                 :full_factorial, :all_tuples, :values_excursion, :pairs_excursion, :triples_excursion)
        @test name in names(UnitTestDesign)
    end
end


@testitem "deprecated spellings warn and mean the new ones (§10.8, §11.10, §13.1)" setup=[InterfaceSetup] begin
    d = ([1, 2], [3, 4, 5], [:a, :b])
    @test collect(@test_deprecated(all_tuples(d...; n_way = 2))) == collect(all_pairs(d...))
    @test collect(@test_deprecated(all_tuples(d...))) == collect(covering(d...))
    @test collect(@test_deprecated(all_tuples((a = [1, 2], b = [3, 4]); n_way = 1))) ==
          collect(all_values((a = [1, 2], b = [3, 4])))
    @test collect(@test_deprecated(covering(d...; n_way = 3))) == collect(covering(d...; strength = 3))
    @test collect(@test_deprecated(covering(d...; seeds = [[2, 5, :b]]))) ==
          collect(covering(d...; must_include = [[2, 5, :b]]))
    @test collect(@test_deprecated(all_pairs(d...; seeds = [(2, 5, :b)])))[1] == (2, 5, :b)
    wayness = Dict(3 => [[1, 2, 3]])
    @test collect(@test_deprecated(covering(fill(1:2, 5)...; wayness))) ==
          collect(covering(fill(1:2, 5)...; stronger = [(1, 2, 3) => 3]))
    @test wayness == Dict(3 => [[1, 2, 3]])   # translated from a copy (§11.9)
    @test collect(@test_deprecated(values_excursion(d...))) == collect(excursions(d...; distance = 1))
    @test collect(@test_deprecated(pairs_excursion(d...))) == collect(excursions(d...; distance = 2))
    @test collect(@test_deprecated(triples_excursion(d...))) == collect(excursions(d...; distance = 3))
    @test @test_deprecated(excursions(d...; seeds = [(2, 5, :b)]))[1] == (2, 5, :b)
    @test @test_deprecated(full_factorial(d...; seeds = [(2, 5, :b)]))[1] == (2, 5, :b)
    @test @test_deprecated(values_excursion(d...; seeds = [(2, 5, :b)])).n_must_include == 1
    # An excursion's 0.4 n_way is its distance (§7.5); excursions itself takes no n_way.
    @test collect(@test_deprecated(values_excursion(d...; n_way = 2))) == collect(excursions(d...; distance = 2))
    @test_throws MethodError excursions(d...; n_way = 2)

    # The 0.4 excursion sizes.
    pe = @test_deprecated pairs_excursion([1:4, 1:4, 1:4, 1:4, 1:3, 1:3, 1:3, 1:4]...)
    @test length(pe) == 214 && length(pe[1]) == 8
    @test length(@test_deprecated(values_excursion([1:3, 1:2, 1:4, 1:2, 1:2]...))) == 1 + 2 + 1 + 3 + 1 + 1
    @test length(excursions(fill(1:2, 20)...; distance = 2)) == 1 + 20 + 190

    # A keyword and its deprecated alias together is an error, whatever their
    # values (§13.2): an explicit default is not taken for an omitted keyword,
    # so `strength = 2, n_way = 1` cannot quietly give strength 1.
    @test message(() -> covering(d...; strength = 2, n_way = 1)) ==
          "pass strength only; n_way is its deprecated alias (contract §11.10)"
    for (s, n) in ((3, 1), (2, 2), (1, 3))
        @test occursin("pass strength only", message(() -> covering(d...; strength = s, n_way = n)))
    end
    @test occursin("pass strength only", @test_deprecated(message(() -> all_tuples(d...; strength = 2, n_way = 3))))
    @test message(() -> all_pairs(d...; seeds = [(2, 5, :b)], must_include = [(1, 3, :a)])) ==
          "pass must_include only; seeds is its deprecated alias (contract §10.8)"
    @test occursin("pass must_include only", message(() -> covering(d...; must_include = [(1, 3, :a)], seeds = [(1, 3, :a)])))
    for f in (covering, all_values, all_pairs, excursions, full_factorial)   # even when one is empty
        @test occursin("pass must_include only", message(() -> f(d...; seeds = [(2, 5, :b)], must_include = [])))
        @test occursin("pass must_include only", message(() -> f(d...; seeds = [], must_include = [(2, 5, :b)])))
    end
    @test message(() -> covering(fill(1:2, 4)...; stronger = [], wayness)) ==
          "pass stronger only; wayness is its deprecated form (contract §11.10)"
    @test occursin("pass stronger only", message(() -> covering(fill(1:2, 4)...; stronger = [(1, 2, 3) => 3], wayness)))
    @test @test_deprecated(message(() -> values_excursion(d...; distance = 1, n_way = 2))) ==
          "pass distance only; n_way is its deprecated alias for an excursion (contract §7.5)"
    @test occursin("pass distance only", @test_deprecated(message(() -> pairs_excursion(d...; distance = 2, n_way = 2))))
    # Each alias alone still means the new keyword; omitted, the defaults hold.
    @test @test_deprecated(covering(d...; n_way = 1)).strength == 1
    @test covering(d...).strength == 2 && covering(d...; strength = nothing).strength == 2
    @test @test_deprecated(all_tuples(d...)).strength == 2
    @test excursions(d...).notes.distance == 1
    @test @test_deprecated(values_excursion(d...; distance = 2)).notes.distance == 2
    # wayness excursions: one distance only (§7.5).
    @test @test_deprecated(message(() -> pairs_excursion(fill(1:2, 6)...; wayness))) ==
          "excursions take a single distance; stronger groups apply to covering designs"

    # The translation of wayness (§11.10).
    @test _stronger_from_wayness(nothing) == []
    @test _stronger_from_wayness(Dict(3 => [[3, 4, 5, 6]])) == [[3, 4, 5, 6] => 3]
    @test _stronger_from_wayness(Dict(4 => [11:18], 3 => [(1, 2, 3), [4, 5, 6]])) ==
          [[1, 2, 3] => 3, [4, 5, 6] => 3, collect(11:18) => 4]
    ws(w) = message(() -> covering(fill(1:2, 4)...; wayness = w))
    @test occursin("`wayness` is a Dict", ws([[1, 2, 3]]))
    @test occursin("list of parameter index groups", ws(Dict(3 => [1, 2, 3])))
    @test occursin("below the base strength", @test_deprecated(ws(Dict(1 => [[1, 2, 3]]))))   # §11.6
    @test occursin("names parameter 9", @test_deprecated(ws(Dict(3 => [[1, 2, 9]]))))         # §11.4
end


@testitem "deprecations warn once per call site under --depwarn=yes (§13.2)" begin
    # A fresh process, since this one may run with deprecation warnings off.
    calls = [
        # One deprecated spelling per line: two on one line warn once on 1.13 but twice on 1.10.
        "all_tuples([1, 2], [3, 4])" => "all_tuples is deprecated; use covering",
        "covering([1, 2], [3, 4]; n_way = 1)" => "the keyword `n_way` is deprecated; use `strength = 1`",
        "all_pairs([1, 2], [3, 4]; seeds = [[1, 3]])" => "the keyword `seeds` is deprecated; use `must_include`",
        "covering(fill(1:2, 4)...; wayness = Dict(3 => [[1, 2, 3]]))" =>
            "the keyword `wayness` is deprecated; use `stronger = [(1, 2, 3) => 3]`",
        "values_excursion([1, 2], [3, 4])" => "values_excursion is deprecated; use excursions(...; distance = 1)",
        "pairs_excursion([1, 2], [3, 4])" => "pairs_excursion is deprecated; use excursions(...; distance = 2)",
        "triples_excursion([1, 2], [3, 4])" => "triples_excursion is deprecated; use excursions(...; distance = 3)",
        "excursions([1, 2], [3, 4]; seeds = [(2, 4)])" => "the keyword `seeds` is deprecated",
        "full_factorial([1, 2], [3, 4]; seeds = [(2, 4)])" => "the keyword `seeds` is deprecated",
        "GND(M = 3)" => "GND(M = n) is deprecated; use GND(candidates = n)",
    ]
    # Each call site runs three times. Calling one compiled function thrice keeps
    # one call site per line; a loop could be unrolled into several.
    header = ["using UnitTestDesign", "function run_all()"]
    script = tempname() * ".jl"
    write(script, join([header; ["    " * c for (c, _) in calls]; "end"; fill("run_all()", 3)], "\n"))
    cmd = `$(Base.julia_cmd()) --startup-file=no --color=no --depwarn=yes --project=$(Base.active_project()) $script`
    log = IOBuffer()
    run(pipeline(cmd; stdout = devnull, stderr = log))
    records = [(message = m[1], file = m[2], line = parse(Int, m[3]))
               for m in eachmatch(r"Warning: (.*)\n(?:│.*\n)*└ @ \S+ (\S+):(\d+)", String(take!(log)))]
    # Once each, though every call runs three times, and at the caller's line.
    @test length(records) == length(calls)
    for (k, (r, (_, expected))) in enumerate(zip(records, calls))
        @test startswith(r.message, expected)
        @test basename(r.file) == basename(script) && r.line == length(header) + k
    end
    rm(script; force = true)
end
