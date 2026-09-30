using Test
using TestItemRunner

# Measurement (src/measure.jl; plan Phase 5 steps 1, 2, 5 and 6): `coverage`,
# `missing_interactions`, `Coverage` and `iscomplete`, against the
# independent checker (checker.jl). Contract §1.8–§1.17, §3.10, §3.11,
# §5.9–§5.11, §6. `coverage` never reads a generator's bookkeeping, so the
# checker judges it on hand-written rows as well as on generated designs.

@testsnippet MeasureSetup begin
    using UnitTestDesign: Request, targets, _space_indices, from_indices
    using Random: Xoshiro

    "A production value, target or row in the checker's terms: a partition by its name."
    as_checker(x::Invalid) = CheckInvalid(as_checker(x.value))
    as_checker(x::Partition) = x.name
    as_checker(x) = x
    as_checker(t::NamedTuple) = map(as_checker, t)

    "A checker row (wrappers as CheckInvalid, CheckPartition) as production values."
    model_row(row::NamedTuple) = map(model_value, row)

    "Equal as sets of targets, by value identity (§2.1)."
    same_set(a, b) = length(a) == length(b) &&
        all(x -> any(y -> same_target(x, y), b), a) && all(y -> any(x -> same_target(x, y), a), b)

    "Two lists of exclusions agree field by field, targets by identity."
    same_exclusions(a, b) = length(a) == length(b) && all(zip(a, b)) do (x, y)
        same_target(x.target, y.target) && x.status == y.status && x.rules == y.rules &&
            x.labels == y.labels && x.minimal == y.minimal && x.limit == y.limit
    end

    "Fable's solver space, typed and labeled: 5 valid rows of 12, 11 feasible pairs."
    solver_space() = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])

    "Three valid rows written by hand, which leave three feasible pairs out."
    handwritten() = [(mode = :fast, solver = :none, tol = 1e-3),
                     (mode = :exact, solver = :lu, tol = 1e-6),
                     (mode = :exact, solver = :none, tol = 1e-6)]

    plain(x) = sprint(show, MIME"text/plain"(), x)

    "The request a fixture is about: its strength or `stronger` groups, if it names them."
    fixture_request(f) = f.name == :overlapping_groups ? (stronger = f.request.stronger,) :
        haskey(f.request, :strength) && f.request.strength isa Integer ? (strength = f.request.strength,) : (;)

    "Fixtures whose spaces hold Invalid or Partition values (generation takes them since Phase 6)."
    const WRAPPED = (:invalid_beside_ordinary, :partition_names, :empty_ordinary_negative_seed)

    "The ArgumentError message of `f()`, or what happened instead."
    message(f) = try
        f()
        "no error"
    catch e
        e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e)): $(sprint(showerror, e))"
    end

    """
    Rows written by hand for a checker space: about a fifth of the valid
    ordinary rows (at most 12), a duplicate of the first, the valid negative
    rows at odd positions, and the first row of the product, in domain order,
    that breaks an applicable rule. Checker values; `model_row` converts them.
    """
    function hand_rows(s)
        valid = valid_rows(s)
        picked = isempty(valid) ? NamedTuple[] :
                 collect(NamedTuple, valid[1:max(1, length(valid) ÷ 5):end][1:min(end, 12)])
        isempty(picked) || push!(picked, picked[1])
        negative = negative_rows(s)
        append!(picked, negative[1:2:end])
        known = [valid; negative]
        for values in Iterators.product(s.domains...)
            row = NamedTuple{Tuple(s.names)}(values)
            count(x -> x isa CheckInvalid, values) <= 1 || continue
            any(v -> same_target(v, row), known) && continue
            insert!(picked, min(3, length(picked) + 1), row)
            break
        end
        return picked
    end

    """
    Assert that one part of a production `Coverage` agrees with the checker's
    part: counts, the missing set, the forbidden targets with their rules,
    the implied targets, and the rejected rows with their reasons and rules.
    """
    function agrees(part, check)
        c = check.counts
        @test part.covered == c.covered
        @test part.feasible == c.feasible
        @test isempty(part.unknown)
        @test same_set(as_checker.(part.missing), check.missing)
        forbidden = [e for e in part.excluded if e.status == :forbidden]
        @test same_set(as_checker.([e.target for e in forbidden]), first.(check.forbidden))
        for e in forbidden
            k = findfirst(p -> same_target(p.first, as_checker(e.target)), check.forbidden)
            @test k !== nothing && check.forbidden[k].second == e.rules
        end
        @test same_set(as_checker.([e.target for e in part.excluded if e.status == :implied]), check.implied)
        @test part.rows == c.rows
        @test part.duplicates == c.duplicates
        @test [(r.index, r.reason, r.rules) for r in part.rejected] ==
              [(r.index, r.reason, r.rules) for r in check.rejected]
    end
end


@testitem "coverage: hand-written rows agree with the checker on every fixture (§1.9–§1.15, §5.9–§5.11, §6)" setup=[Checker, MeasureSetup] begin
    cases = [(f, fixture_request(f)) for f in FIXTURES if f.space !== nothing]
    # Strength 1 for the fixtures with wrappers: one negative target per invalid value (§6.4).
    append!(cases, [(f, (strength = 1,)) for f in FIXTURES if f.name in WRAPPED])
    with_rejected = Ref(0)
    for (f, request) in cases
        @testset "$(f.name) $request" begin
            s = f.space
            rows = hand_rows(s)
            check = check_design(rows, s; request...)
            c = coverage(model_row.(rows), test_space(f); request...)
            agrees(c.ordinary, check.ordinary)
            agrees(c.negative, check.negative)
            @test iscomplete(c) == (isempty(check.ordinary.missing) && isempty(check.negative.missing))
            with_rejected[] += !isempty(c.ordinary.rejected) || !isempty(c.negative.rejected)
        end
    end
    # Nearly every fixture has a rule, so its hand-written rows include one that breaks it.
    @test with_rejected[] >= length(cases) - 2
end


@testitem "coverage: every generated covering design is complete, and agrees with its bookkeeping (§1.3, §1.12)" setup=[Checker, MeasureSetup] begin
    for f in FIXTURES, engine in (IPOG(), GND())
        (f.space === nothing || f.name == :bench12) && continue   # bench12 below
        request = fixture_request(f)
        @testset "$(f.name) $engine" begin
            cases = covering(test_space(f); engine, request...)
            c = coverage(cases)
            @test iscomplete(c)
            @test c.ordinary.covered == cases.covered == cases.required
            @test c.ordinary.feasible == cases.required
            @test isempty(c.ordinary.missing) && isempty(c.ordinary.unknown)
            @test same_exclusions(c.ordinary.excluded, cases.excluded)
            # The negative part, for the fixtures with Invalid values (§5.10).
            @test c.negative.covered == c.negative.feasible == cases.negative_covered == cases.negative_required
            @test same_exclusions(c.negative.excluded, cases.negative_excluded)
            @test c.ordinary.rows + c.ordinary.duplicates + c.negative.rows + c.negative.duplicates == length(cases)
            @test isempty(c.ordinary.rejected) && isempty(c.negative.rejected)
            @test c.strength == cases.strength && c.stronger == cases.stronger
            # The checker agrees on the counts.
            check = check_design(as_checker.(collect(cases)), f.space; request...)
            @test c.ordinary.covered == check.ordinary.counts.covered
            @test c.negative.covered == check.negative.counts.covered
        end
    end
    # bench12 at strengths 2 and 3, both engines: 586 pairs and 5702 triples.
    for (k, feasible) in ((2, 586), (3, 5702)), engine in (IPOG(), GND())
        cases = covering(test_space(bench12); strength = k, engine)
        c = coverage(cases)
        @test iscomplete(c) && c.ordinary.covered == feasible == cases.covered
        @test same_exclusions(c.ordinary.excluded, cases.excluded)
    end
end


@testitem "coverage: random problems at strengths 2 and 3, both engines (§1.3, §1.4)" setup=[Checker, MeasureSetup] begin
    for strength in (2, 3)
        rng = Xoshiro(0x2026_0927_0005 + strength)
        for index in 1:100
            problem = random_problem(rng; strength)
            space = test_space(problem.space)
            for engine in (IPOG(), GND(seed = index))
                cases = covering(space; strength, engine)
                c = coverage(cases)
                ok = iscomplete(c) && c.ordinary.covered == cases.covered &&
                     c.ordinary.feasible == problem.feasible &&
                     count(e -> e.status == :forbidden, c.ordinary.excluded) == problem.forbidden &&
                     count(e -> e.status == :implied, c.ordinary.excluded) == problem.implied &&
                     same_exclusions(c.ordinary.excluded, cases.excluded)
                ok || @error "coverage disagrees on random problem $index" strength engine problem
                @test ok
            end
        end
    end
end


@testitem "coverage: the solver suite with gaps, then top-up and extend (plan Phase 5 step 5)" setup=[Checker, MeasureSetup] begin
    space = solver_space()
    rows = handwritten()
    c = coverage(rows, space)
    gaps = [(mode = :exact, solver = :qr), (mode = :fast, tol = 1e-6), (solver = :qr, tol = 1e-6)]
    @test c.ordinary.missing == gaps                        # in target order (§9.7)
    @test (c.ordinary.covered, c.ordinary.feasible) == (8, 11)
    @test same_set(c.ordinary.missing, check_design(rows, fable_solver.space).ordinary.missing)
    @test !iscomplete(c)
    @test missing_interactions(rows, space) == gaps
    @test plain(c) == "covers 8 of 11 feasible pairs, 3 missing: (mode = :exact, solver = :qr), " *
                      "(mode = :fast, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)\n" *
                      "excluded: 3 pairs forbidden, 2 impossible under the constraints"
    @test sprint(show, c) == "covers 8 of 11 feasible pairs, 3 missing"

    for engine in (IPOG(), GND())
        # Top-up: the rows are kept first, in order, and the result is complete.
        topped = all_pairs(space; must_include = rows, engine)
        @test collect(topped[1:3]) == rows
        full = coverage(topped)
        @test iscomplete(full) && full.ordinary.covered == 11
        @test complete(check_design(topped, fable_solver.space))
        @test isempty(missing_interactions(topped))
        @test plain(full) == "covers 11 of 11 feasible pairs\n" *
                             "excluded: 3 pairs forbidden, 2 impossible under the constraints"
        # Extend: a pairs design kept first and grown to triples.
        triples = all_triples(space; must_include = topped, engine)
        @test collect(triples[1:length(topped)]) == collect(topped)
        @test iscomplete(coverage(triples))
    end

    # Extend on a space where the pairs design misses triples.
    wide = TestSpace((a = 1:3, b = 1:3, c = 1:3, d = [:x, :y]); constraints = [forbid((a = 1, b = 2))])
    checker = CheckSpace((a = 1:3, b = 1:3, c = 1:3, d = [:x, :y]),
                         [((:a, :b), (a, b) -> a == 1 && b == 2)])
    for engine in (IPOG(), GND())
        pairs = all_pairs(wide; engine)
        @test iscomplete(coverage(pairs))
        @test !iscomplete(coverage(pairs; strength = 3))
        triples = all_triples(wide; must_include = pairs, engine)
        @test collect(triples[1:length(pairs)]) == collect(pairs)
        c3 = coverage(triples)
        @test iscomplete(c3)
        @test complete(check_design(triples, checker; strength = 3))
        @test c3.ordinary.covered == check_design(triples, checker; strength = 3).ordinary.counts.feasible
    end
end


@testitem "coverage: duplicates count once; a row that breaks a rule counts for nothing (§1.11, §1.14)" setup=[Checker, MeasureSetup] begin
    space = solver_space()
    rows = handwritten()
    # (fast, qr, 1e-6) breaks rule 1; alone it would cover two of the gaps.
    bad = (mode = :fast, solver = :qr, tol = 1e-6)
    given = [rows[1], rows[2], bad, rows[1], rows[3], rows[2]]
    c = coverage(given, space)
    @test c.ordinary.missing == coverage(rows, space).ordinary.missing
    @test (c.ordinary.covered, c.ordinary.rows, c.ordinary.duplicates) == (8, 3, 2)
    @test c.ordinary.rejected == [(index = 3, row = bad, reason = :violates_rule, rules = [1])]
    check = check_design(given, fable_solver.space)
    @test check.ordinary.counts.duplicates == 2 && only(check.ordinary.rejected).rules == [1]
    @test plain(c) == "covers 8 of 11 feasible pairs, 3 missing: (mode = :exact, solver = :qr), " *
                      "(mode = :fast, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)\n" *
                      "excluded: 3 pairs forbidden, 2 impossible under the constraints\n" *
                      "2 duplicate rows counted once\n" *
                      "1 row rejected: row 3 breaks rule 1 (@require(mode == :exact || solver == :none))"
    # A row breaking two rules names both, in rule order.
    both = (mode = :fast, solver = :lu, tol = 1e-3)
    two_rules = TestSpace((mode = [:fast, :exact], solver = [:none, :lu], tol = [1e-3, 1e-6]);
        constraints = [@forbid(mode == :fast && solver == :lu), @forbid(solver == :lu && tol == 1e-3)])
    r = only(coverage([both], two_rules).ordinary.rejected)
    @test r.rules == [1, 2]
    @test occursin("row 1 breaks rules 1 and 2 (rule 1: @forbid(mode == :fast && solver == :lu); " *
                   "rule 2: @forbid(solver == :lu && tol == 0.001))", plain(coverage([both], two_rules)))
    # No rows: nothing is covered, and nothing is claimed.
    empty = coverage([], space)
    @test (empty.ordinary.covered, empty.ordinary.feasible, length(empty.ordinary.missing)) == (0, 11, 11)
    @test empty.ordinary.rows == 0 && !iscomplete(empty)
    # An iterator is read once.
    @test coverage(Iterators.Stateful(rows), space).ordinary.covered == 8
    @test coverage((r for r in rows), space).ordinary.covered == 8
end


@testitem "coverage: value identity: Any[1, 1.0] is two values (§2.1, §2.2, §2.11)" setup=[Checker, MeasureSetup] begin
    f = heterogeneous_values
    space = test_space(f)
    rows = valid_rows(f.space)
    c = coverage(rows, space)
    @test iscomplete(c) && (c.ordinary.covered, c.ordinary.feasible) == (7, 7)
    # (x = 1.0, y = :a, z = :s) alone covers (x = 1.0, …), never (x = 1, …).
    one = coverage([rows[3]], space)
    @test any(t -> haskey(t, :x) && t.x === 1, one.ordinary.missing)
    @test !any(t -> haskey(t, :x) && t.x === 1.0, one.ordinary.missing)
    @test same_set(one.ordinary.missing, check_design([rows[3]], f.space).ordinary.missing)
    # A value equal to a domain value but of another type is an input error.
    msg = message(() -> coverage([(x = Float32(1), y = :a, z = :s)], space))
    @test occursin("coverage row 1", msg) && occursin("`x`", msg) && occursin("Float32", msg)
    # A partition may be written as its wrapper or by its name (§2.11, §4.5).
    p = partition_names
    pspace = test_space(p)
    by_name = [(size = :tiny, mode = :a), (size = :huge, mode = :b), (size = 100, mode = :tiny)]
    by_wrapper = [(size = pspace.values[1][1], mode = :a), (size = pspace.values[1][2], mode = :b),
                  (size = 100, mode = :tiny)]
    @test coverage(by_name, pspace).ordinary.covered == coverage(by_wrapper, pspace).ordinary.covered == 3
    @test only(coverage([(size = :tiny, mode = :b)], pspace).ordinary.rejected).rules == [1]
end


@testitem "coverage: positional spaces and rows (§1.13, §1.18, §13.4)" setup=[Checker, MeasureSetup] begin
    c = coverage([(1, :a), [2, :b]], [1, 2], [:a, :b])
    @test c.ordinary.missing == [(p1 = 2, p2 = :a), (p1 = 1, p2 = :b)]
    @test (c.ordinary.covered, c.ordinary.feasible) == (2, 4)
    # A positional result is measured as tuples, against its own space.
    for engine in (IPOG(), GND())
        cases = all_pairs([1, 2, 3], [:a, :b], [true, false]; engine)
        @test eltype(cases) <: Tuple
        full = coverage(cases)
        @test iscomplete(full) && full.ordinary.covered == 16 == cases.covered
        @test coverage(collect(cases), [1, 2, 3], [:a, :b], [true, false]).ordinary.covered == 16
        @test coverage(cases; strength = 3).ordinary.feasible == 12
    end
    # A named space accepts rows in parameter order, and a positional one named rows.
    space = solver_space()
    @test coverage([Tuple(r) for r in handwritten()], space).ordinary.missing ==
          coverage(handwritten(), space).ordinary.missing
    @test coverage([(p2 = :a, p1 = 1)], [1, 2], [:a, :b]).ordinary.covered == 1
    # Positional stronger groups use argument positions.
    g = coverage(all_pairs(fill(1:2, 4)...; stronger = [(1, 2, 3) => 3]))
    @test iscomplete(g) && g.stronger == [(:p1, :p2, :p3) => 3]
    @test [x.names for x in g.ordinary.groups] == [(:p1, :p2, :p3, :p4), (:p1, :p2, :p3)]
end


@testitem "coverage: input errors name the row and the parameter (§0.1, §1.13)" setup=[MeasureSetup] begin
    space = solver_space()
    ok = handwritten()
    msg = message(() -> coverage([ok[1], (mode = :fast, solver = :none)], space))
    @test occursin("coverage row 2", msg) && occursin("`tol`", msg) && occursin("§1.13", msg)
    msg = message(() -> coverage([ok[1], (mode = :fast, solver = :none, tol = 1e-3, speed = 1)], space))
    @test occursin("coverage row 2", msg) && occursin("`speed`", msg)
    msg = message(() -> coverage([ok[1], ok[2], (mode = :fast, solver = :svd, tol = 1e-3)], space))
    @test occursin("coverage row 3", msg) && occursin("`solver`", msg) && occursin(":svd", msg)
    msg = message(() -> coverage([(1, :a, 3)], [1, 2], [:a, :b]))
    @test occursin("coverage row 1 has 3 values", msg) && occursin("p1, p2", msg)
    msg = message(() -> coverage([ok[1], 7], space))
    @test occursin("coverage row 2 is a Int64", msg)
    # The shape of the call.
    @test occursin("wrap a single row", message(() -> coverage(ok[1], space)))
    @test occursin("wrap a single row", message(() -> coverage((1, :a), [1, 2], [:a, :b])))
    @test occursin("rows first", message(() -> coverage(space, ok)))
    @test occursin("needs the space", message(() -> coverage(ok)))
    @test occursin("collection of rows", message(() -> coverage(3, space)))
    # Keywords are checked before anything is read, in the caller's words.
    @test occursin("strength must be a positive integer", message(() -> coverage(ok, space; strength = 0)))
    @test occursin("strength 4 is larger than the number of parameters, 3",
                   message(() -> coverage(ok, space; strength = 4)))
    @test occursin("feasibility_limit", message(() -> coverage(ok, space; feasibility_limit = 0)))
    @test occursin("explanation_limit", message(() -> coverage(ok, space; explanation_limit = 1.5)))
    @test occursin("stronger", message(() -> coverage(ok, space; stronger = (:mode, :tol) => 3)))
    # constraints = builds a space from named domains, and is refused for a TestSpace (§12.12).
    domains = (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6])
    @test coverage(ok, domains; constraints = space.constraints).ordinary.missing ==
          coverage(ok, space).ordinary.missing
    @test coverage(ok, (k => v for (k, v) in pairs(domains))...;
                   constraints = space.constraints).ordinary.covered == 8
    @test occursin("constraints belong to the space",
                   message(() -> coverage(ok, space; constraints = space.constraints)))
end


@testitem "coverage(cases::TestCases): the result's request; excursions and full factorials need a strength (§1.12)" setup=[Checker, MeasureSetup] begin
    space = solver_space()
    pairs = all_pairs(space)
    c = coverage(pairs)
    @test c.strength == 2 && isempty(c.stronger) && c.space === space
    @test c.limits == (feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    # Explicit keywords override the result's.
    c3 = coverage(pairs; strength = 3)
    @test c3.strength == 3 && c3.ordinary.feasible == 5
    grouped = covering(space; stronger = [(:mode, :solver, :tol) => 3])
    @test coverage(grouped).stronger == [(:mode, :solver, :tol) => 3]
    @test iscomplete(coverage(grouped))
    @test coverage(pairs; stronger = [(:mode, :solver, :tol) => 3]).strength == 2
    # An explicit strength keeps the stored groups (review round 1, item 3):
    # the stored strength passed again measures the same 16 targets.
    whole = coverage(grouped)
    again = coverage(grouped; strength = 2)
    @test again.stronger == [(:mode, :solver, :tol) => 3]
    @test (again.ordinary.covered, again.ordinary.feasible, length(again.ordinary.excluded)) ==
          (whole.ordinary.covered, whole.ordinary.feasible, length(whole.ordinary.excluded)) == (16, 16, 12)
    @test again.ordinary.groups == whole.ordinary.groups
    @test missing_interactions(grouped; strength = 2) == missing_interactions(grouped) == []
    # A group at the requested strength adds nothing (§11.7); `stronger = []` drops the groups.
    @test isempty(coverage(grouped; strength = 3).stronger) && coverage(grouped; strength = 3).ordinary.feasible == 5
    dropped = coverage(grouped; strength = 2, stronger = [])
    @test isempty(dropped.stronger) && dropped.ordinary.feasible == 11
    @test coverage(grouped; stronger = []).ordinary.feasible == 11
    # An explicit `stronger` replaces the stored groups.
    @test coverage(grouped; stronger = [(:mode, :solver) => 2]).stronger == []
    # A stored group below the requested strength is an error naming it.
    low = covering(space; strength = 1, stronger = [(:mode, :solver) => 2])
    @test low.stronger == [(:mode, :solver) => 2]
    @test message(() -> coverage(low; strength = 3)) ==
          "stronger group (mode, solver) => 2 is below the requested strength 3; pass stronger = [] to drop it " *
          "(contract §1.12)"
    @test message(() -> missing_interactions(low; strength = 3)) == message(() -> coverage(low; strength = 3))
    @test iscomplete(coverage(low; strength = 3, stronger = [])) == false
    @test coverage(low; strength = 2).stronger == [] && coverage(low; strength = 1).stronger == [(:mode, :solver) => 2]
    four = covering(fill(1:2, 4)...; stronger = [(1, 2, 3) => 3])
    @test occursin("stronger group (p1, p2, p3) => 3 is below the requested strength 4",
                   message(() -> coverage(four; strength = 4)))
    @test isempty(coverage(four; strength = 3).stronger) && coverage(four; strength = 2).stronger == [(:p1, :p2, :p3) => 3]
    # Strength 0: an excursion and a full factorial have none.
    ex = excursions(space; from = (mode = :exact, solver = :lu, tol = 1e-6))
    ff = full_factorial(space)
    @test ex.strength == 0 && ff.strength == 0
    msg = message(() -> coverage(ex))
    @test occursin("an excursion has none", msg) && occursin("strength = 2", msg) && occursin("§1.12", msg)
    @test occursin("a full factorial has none", message(() -> coverage(ff)))
    @test occursin("full factorial", message(() -> coverage(ff; stronger = [(:mode, :solver, :tol) => 3])))
    @test iscomplete(coverage(ff; strength = 2)) && coverage(ff; strength = 3).ordinary.covered == 5
    @test coverage(ex; strength = 1).ordinary.feasible == 7
    @test occursin("strength must be", message(() -> coverage(ff; strength = 0)))
    # One parameter: strength 1 is the only strength (§1.12, §11.2).
    one = full_factorial((a = [1, 2, 3],))
    @test iscomplete(coverage(one; strength = 1))
    @test occursin("larger than the number of parameters", message(() -> coverage(one; strength = 2)))
    # A TestCases is also a collection of rows, for another space.
    @test coverage(pairs, solver_space()).ordinary.covered == 11
    @test missing_interactions(ex; strength = 2) == coverage(ex; strength = 2).ordinary.missing
end


@testitem "missing_interactions: the missing list only when every target is resolved (§3.11)" setup=[Checker, MeasureSetup] begin
    space = solver_space()
    @test missing_interactions(handwritten(), space) == coverage(handwritten(), space).ordinary.missing
    @test isempty(missing_interactions(all_pairs(space)))
    @test missing_interactions(all_pairs(space); strength = 3) == coverage(all_pairs(space); strength = 3).ordinary.missing
    @test missing_interactions(handwritten(), space; strength = 1) == [(solver = :qr,)]

    f = limit_exhaustion
    lspace = test_space(f)
    err = try
        missing_interactions([], lspace; feasibility_limit = f.request.small_limit)
    catch e
        e
    end
    @test err isa ResourceLimitError
    @test err.keyword == :feasibility_limit && err.limit == 1
    text = sprint(showerror, err)
    @test occursin("missing_interactions", text) && occursin("coverage", text)
    @test occursin("448 targets", text) && occursin("unresolved", text)
    @test occursin("feasibility_limit = 10", text)   # the retry hint
    # The default limit resolves every target, and the list is the 28 pairs of the one row.
    @test length(missing_interactions([], lspace)) == 28

    # Negative targets are listed after the ordinary ones.
    neg = test_space(invalid_beside_ordinary)
    rows = model_row.(valid_rows(invalid_beside_ordinary.space))
    listed = missing_interactions(rows, neg)
    c = coverage(rows, neg)
    @test isempty(c.ordinary.missing) && length(c.negative.missing) == 4
    @test listed == [c.ordinary.missing; c.negative.missing]
    @test all(hasinvalid, listed)
end


@testitem "coverage under limits: unknown targets, bounds, no percentage, no completeness (§1.7, §1.10, §3.10, §3.15)" setup=[Checker, MeasureSetup] begin
    f = limit_exhaustion
    space = test_space(f)
    c = coverage([], space; feasibility_limit = f.request.small_limit)
    @test length(c.ordinary.unknown) == 448 && c.ordinary.covered == 0 && c.ordinary.feasible == 0
    @test isempty(c.ordinary.missing) && isempty(c.ordinary.excluded)
    @test !iscomplete(c)
    @test c.limits.feasibility_limit == 1
    for text in (plain(c), sprint(show, c))
        @test !occursin('%', text)
        @test !occursin("complete", text)
        @test occursin("at least", text) && occursin("unresolved", text)
        @test occursin("feasibility_limit = 1", text) && occursin("no exact percentage", text)
    end
    @test plain(c) == "covers 0 of at least 0 feasible pairs; 448 pairs unresolved " *
        "(feasibility_limit = 1): (x1 = 1, x2 = 1), (x1 = 2, x2 = 1), (x1 = 3, x2 = 1), " *
        "(x1 = 4, x2 = 1), (x1 = 1, x2 = 2), (x1 = 2, x2 = 2), (x1 = 3, x2 = 2), (x1 = 4, x2 = 2), " *
        "(x1 = 1, x2 = 3), (x1 = 2, x2 = 3), and 438 more; no exact percentage"
    # A covered target needs no search (§1.10): the one valid row covers its
    # 28 pairs even though every search is cut off at the first node.
    row = only(valid_rows(f.space))
    part = coverage([row], space; feasibility_limit = 1)
    @test part.ordinary.covered == 28 && length(part.ordinary.unknown) == 420
    @test startswith(plain(part), "covers 28 of at least 28 feasible pairs; 420 pairs unresolved")
    @test !iscomplete(part)
    # The default limit resolves everything; raising a limit changes no resolved answer (§3.8).
    whole = coverage([row], space)
    @test iscomplete(whole) && whole.ordinary.covered == 28 && length(whole.ordinary.excluded) == 420
    @test plain(whole) == "covers 28 of 28 feasible pairs\nexcluded: 420 pairs impossible under the constraints"
    # The groups say the same.
    g = only(part.ordinary.groups)
    @test (g.covered, g.feasible, g.missing_count, g.excluded_count, g.unknown_count) == (28, 28, 0, 0, 420)

    # explanation_limit = 1 leaves the attribution unresolved, never the coverage (§3.15).
    solver = solver_space()
    cut = coverage(all_pairs(solver); explanation_limit = 1)
    @test iscomplete(cut)
    implied = filter(e -> e.status == :implied, cut.ordinary.excluded)
    @test length(implied) == 2
    @test all(e -> e.minimal == :unresolved && e.limit == (:explanation_limit => 1) && e.rules == [1, 2], implied)
    @test cut.limits.explanation_limit == 1
    @test plain(cut) == "covers 11 of 11 feasible pairs\nexcluded: 3 pairs forbidden, " *
                        "2 impossible under the constraints, 2 with an unresolved explanation"
    @test same_exclusions(cut.ordinary.excluded, all_pairs(solver; explanation_limit = 1).excluded)
end


@testitem "coverage: one call evaluates a lazy rule at most once per assignment (§3.5, §12.19)" begin
    # A whole-case rule is lazy. One coverage call is one operation, so its
    # row checks, target searches and deletion trials share one memo.
    seen = NTuple{4, Int}[]
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:3);
        constraints = [forbid(case -> (push!(seen, Tuple(case)); case.a == case.b == 2 && case.d == 3);
                              reason = "counted")])
    design = all_pairs(space)
    empty!(seen)
    c = coverage(design; strength = 3)
    # The call searched: some triples are missing, and one is excluded.
    @test !isempty(c.ordinary.missing) && !isempty(c.ordinary.excluded)
    @test !isempty(seen)
    @test allunique(seen)
end


@testitem "coverage: the per-group breakdown; overlapping stronger groups (§1.8, §11.7, §11.8)" setup=[Checker, MeasureSetup] begin
    f = overlapping_groups
    space = test_space(f)
    stronger = f.request.stronger
    rows = model_row.(valid_rows(f.space)[1:3])
    c = coverage(rows, space; stronger)
    check = check_design(valid_rows(f.space)[1:3], f.space; stronger)
    agrees(c.ordinary, check.ordinary)
    groups = c.ordinary.groups
    @test [g.names for g in groups] == [(:a, :b, :c, :d), (:a, :b, :c), (:b, :c, :d)]
    @test [g.strength for g in groups] == [2, 3, 3]
    # Each group accounts for each of its targets exactly once.
    @test [g.covered + g.missing_count + g.excluded_count + g.unknown_count for g in groups] == [24, 8, 8]
    @test all(g -> g.feasible == g.covered + g.missing_count, groups)
    # These groups share no support, so the groups sum to the totals.
    @test sum(g -> g.covered, groups) == c.ordinary.covered
    @test sum(g -> g.feasible, groups) == c.ordinary.feasible == 35
    @test sum(g -> g.excluded_count, groups) == length(c.ordinary.excluded) == 5
    # Listing a group twice changes nothing (§11.8).
    @test coverage(rows, space; stronger = f.request.stronger_twice).ordinary.groups == groups

    # Groups that share a support: (a, b, c) at 3 inside (a, b, c, d) at 3.
    # The shared triples count once in the totals and in each group.
    shared = [(:a, :b, :c) => 3, (:a, :b, :c, :d) => 3]
    s = coverage(rows, space; stronger = shared)
    base, abc, abcd = s.ordinary.groups
    @test (abc.covered + abc.missing_count + abc.excluded_count, abcd.covered + abcd.missing_count + abcd.excluded_count) == (8, 32)
    @test base.feasible + abcd.feasible == s.ordinary.feasible                 # abc ⊂ abcd
    @test base.feasible + abc.feasible + abcd.feasible == s.ordinary.feasible + abc.feasible
    @test s.ordinary.covered == check_design(valid_rows(f.space)[1:3], f.space; stronger = shared).ordinary.counts.covered
    # A group at the base strength adds nothing (§11.7).
    @test length(coverage(rows, space; stronger = [(:a, :b) => 2]).ordinary.groups) == 1
    # The negative part keeps the same groups, all zero without Invalid values.
    @test [g.names for g in c.negative.groups] == [g.names for g in groups]
    @test all(g -> g.covered == g.feasible == g.excluded_count == 0, c.negative.groups)
end


@testitem "coverage: the negative part (§5.5, §5.7, §5.9–§5.11, §6.1–§6.6)" setup=[Checker, MeasureSetup] begin
    f = invalid_beside_ordinary
    space = test_space(f)
    bad = Invalid(1)
    negative = model_row.(negative_rows(f.space))
    # Negative rows never increase ordinary coverage, even for their ordinary pairs (§5.9).
    c = coverage(negative, space)
    @test c.ordinary.covered == 0 && c.ordinary.rows == 0
    @test (c.negative.covered, c.negative.feasible, c.negative.rows) == (4, 4, 3)
    @test isempty(c.negative.missing)
    ordinary = model_row.(valid_rows(f.space))
    both = coverage([ordinary; negative], space)
    @test iscomplete(both)
    @test plain(both) == "covers 9 of 9 feasible pairs\nnegative: covers 4 of 4 feasible pairs\n" *
                         "excluded: 2 pairs forbidden, 1 impossible under the constraints"
    @test sprint(show, both) == "covers 9 of 9 feasible pairs; negative: covers 4 of 4 feasible pairs"
    # Ordinary rows alone leave every negative target missing, in target order.
    o = coverage(ordinary, space)
    @test o.negative.missing == [(n = bad, m = :a), (n = bad, m = :b), (n = bad, k = :x), (n = bad, k = :y)]
    @test !iscomplete(o)
    # Rule 1 reads n, so it is skipped for a row with n invalid (§5.5); rule 2
    # does not, and still applies (row 1 breaks it).
    skipped = (n = bad, m = :b, k = :x)
    broken = (n = bad, m = :a, k = :y)
    r = coverage([broken, skipped], space)
    @test r.negative.rejected == [(index = 1, row = broken, reason = :violates_rule, rules = [2])]
    @test r.negative.rows == 1 && isempty(r.ordinary.rejected)
    # Strength 1: one target per invalid value (§6.4).
    one = coverage(negative[1:1], space; strength = 1)
    @test (one.negative.covered, one.negative.feasible) == (1, 1)
    @test plain(one) == "covers 0 of 6 feasible combinations, 6 missing: (n = 1,), (n = 2,), (m = :a,), " *
                        "(m = :b,), (k = :x,), (k = :y,)\nnegative: covers 1 of 1 feasible combination"

    # Two invalid parameters and a stronger group: the checker's negative
    # targets (§6.1–§6.5), a multiple-invalid row (§5.7), and a negative
    # target excluded directly by a rule that omits its invalid parameter.
    domains = (a = [1, 2, CheckInvalid(0)], b = [:x, :y], c = [1, 2, CheckInvalid(9)], d = [true, false])
    rules = [((:b, :d), (b, d) -> b == :y && d == false),     # applies to every negative row
             ((:a, :c), (a, c) -> a == 2 && c == 2),           # skipped when a or c is invalid
             ((:b, :c), (b, c) -> b == :x && c == 1)]
    cs = CheckSpace(domains, rules)
    ms = test_space(cs)
    stronger = [(:a, :b, :c) => 3]
    rows = [valid_rows(cs)[1:2:end]; negative_rows(cs)[1:3:end];
            [(a = CheckInvalid(0), b = :x, c = CheckInvalid(9), d = true),   # two Invalid values
             (a = CheckInvalid(0), b = :y, c = 2, d = false)]]                # breaks rule 1
    for request in ((;), (strength = 1,), (stronger = stronger,), (strength = 3,))
        check = check_design(rows, cs; request...)
        m = coverage(model_row.(rows), ms; request...)
        agrees(m.ordinary, check.ordinary)
        agrees(m.negative, check.negative)
    end
    m = coverage(model_row.(rows), ms)
    @test [(r.reason, r.rules) for r in m.negative.rejected] == [(:multiple_invalid, Int[]), (:violates_rule, [1])]
    @test occursin("has more than one Invalid value", plain(m))
    # At strength 3, (a = Invalid(0), b = :y, d = false) is forbidden by rule 1,
    # which omits a; rule 2 reads a and c, the invalid parameters, so it never
    # applies to a negative target (§5.5).
    m3 = coverage(model_row.(rows), ms; strength = 3)
    @test any(e -> e.status == :forbidden && e.rules == [1] && e.target.a isa Invalid, m3.negative.excluded)
    @test !any(e -> 2 in e.rules, [m.negative.excluded; m3.negative.excluded])
    # A group without the invalid parameter adds no negative target for it (§6.5).
    g = coverage(model_row.(rows), ms; stronger = [(:b, :c, :d) => 3])
    counts(part) = part.covered + length(part.missing) + length(part.excluded) + length(part.unknown)
    @test counts(g.negative) == counts(m.negative) + 2 * 2   # (b, c = Invalid(9), d): 2 × 2 new triples
    triples = filter(t -> length(t) == 3, [g.negative.missing; [e.target for e in g.negative.excluded]])
    @test !isempty(triples) && all(t -> keys(t) == (:b, :c, :d) && t.c isa Invalid, triples)

    # No valid ordinary row, one valid negative row (§1.24, §5.5, §6.4).
    e = empty_ordinary_negative_seed
    only_negative = coverage([(a = Invalid(0), b = 1)], test_space(e))
    @test iscomplete(only_negative)
    @test (only_negative.ordinary.feasible, only_negative.negative.covered) == (0, 1)
    @test [x.rules for x in only_negative.ordinary.excluded] == [[1]]
end


@testitem "coverage: targets are the request's targets, in its order (§1.8, §9.7)" setup=[Checker, MeasureSetup] begin
    for f in FIXTURES
        (f.space === nothing || f.name == :bench12) && continue
        request = fixture_request(f)
        space = test_space(f)
        r = Request(space; request...)
        all = [from_indices(space, _space_indices(r, t)) for t in targets(r)]
        c = coverage([], space; request...)
        @test length(c.ordinary.missing) + length(c.ordinary.excluded) == length(all)
        position(t) = findfirst(x -> same_target(x, t), all)
        @test issorted(position.(c.ordinary.missing))
        @test issorted(position.([e.target for e in c.ordinary.excluded]))
    end
end


@testitem "coverage: a block's targets come in the order of their codes (§9.7)" begin
    using UnitTestDesign: FeasibilityContext, _Lists, _measure_block!, _decode!, from_indices
    # _measure_block! steps one buffer through a block's targets. They are the
    # codes 0, 1, 2, … of _decode! over the rest of the support, in radix the
    # ordinary arity, as positions among each parameter's ordinary values,
    # which Invalid values between them make differ from value indices.
    space = TestSpace((a = [Invalid(0), 1, 2], b = [:x, Invalid(:z), :y, :w], c = [true, false],
                       d = [1, 2, 3, Invalid(9)]))
    arity = length.(space.ordinary)
    for (support, p) in (([1, 2, 3, 4], 0), ([2, 4], 0), ([3], 0), ([1, 2, 4], 1), ([2, 4], 2), ([2, 4], 4),
                         ([4], 4))
        rest = filter(!=(p), support)
        t = zeros(Int, 4)
        p == 0 || (t[p] = only(space.invalid[p]))
        fixed = copy(t)
        lists = _Lists(1_000_000)   # no rule, so every target is missing, listed as met
        counts = _measure_block!(lists, FeasibilityContext(space), support, rest, t, nothing)
        n = prod(arity[rest]; init = 1)
        @test counts == (0, n, 0, 0)
        expected = map(0:(n - 1)) do code
            idx = copy(fixed)
            positions = _decode!(zeros(Int, 4), code, rest, arity)
            for q in rest
                idx[q] = space.ordinary[q][positions[q]]
            end
            from_indices(space, idx)
        end
        @test lists.missing == expected
        @test t == fixed   # the buffer is cleared again
    end
end


@testitem "coverage: the documented solver outputs (plan Phase 5 acceptance gate)" setup=[MeasureSetup] begin
    space = solver_space()
    # The handwritten suite, its top-up, and a limited search.
    @test plain(coverage(handwritten(), space)) ==
          "covers 8 of 11 feasible pairs, 3 missing: (mode = :exact, solver = :qr), " *
          "(mode = :fast, tol = 1.0e-6), (solver = :qr, tol = 1.0e-6)\n" *
          "excluded: 3 pairs forbidden, 2 impossible under the constraints"
    @test plain(coverage(all_pairs(space))) ==
          "covers 11 of 11 feasible pairs\nexcluded: 3 pairs forbidden, 2 impossible under the constraints"
    # More than ten missing targets: the first ten, then how many more.
    many = coverage([], TestSpace((a = 1:4, b = 1:4)))
    @test endswith(plain(many), "(a = 2, b = 3), and 6 more")
    # Triples and mixed strengths name their targets.
    @test startswith(plain(coverage(all_triples(space))), "covers 5 of 5 feasible triples")
    @test startswith(plain(coverage(covering(space; stronger = [(:mode, :solver, :tol) => 3]))),
                     "covers 16 of 16 feasible combinations")
    # A Coverage inside a container prints its one-line summary.
    @test endswith(sprint(show, [coverage(all_pairs(space))]), "Coverage[covers 11 of 11 feasible pairs]")
    @test sprint(show, coverage(all_pairs(space)).ordinary) == "covers 11 of 11 feasible targets"
end
