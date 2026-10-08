using Test
using TestItemRunner

# Reporting and planning (src/report.jl; plan Phase 5 steps 3, 4 and 6):
# `report`, `Report`, `design_sizes`, `DesignSizes`. Contract §1.12, §1.23,
# §3.10, §3.12, §7.7, §8.3, §8.4. The numbers are checked against the
# independent checker (checker.jl), never against the engines' bookkeeping.

@testsnippet ReportSetup begin
    using Random: Xoshiro

    "Fable's solver space, typed and labeled: 5 valid rows of 12, 11 feasible pairs."
    solver_space() = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])

    shown(x) = sprint(show, MIME"text/plain"(), x)

    "Two lists of exclusions agree field by field, targets by identity (isequal and type)."
    same_exclusions(a, b) = length(a) == length(b) && all(zip(a, b)) do (x, y)
        isequal(x.target, y.target) && typeof(x.target) == typeof(y.target) && x.status == y.status &&
            x.rules == y.rules && x.labels == y.labels && x.minimal == y.minimal && x.limit == y.limit
    end

    "The ArgumentError message of `f()`, or what happened instead."
    message(f) = try
        f()
        "no error"
    catch e
        e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e)): $(sprint(showerror, e))"
    end

    const RULE1 = "@require(mode == :exact || solver == :none)"
    const SOLVER_EXCLUDED = [
        "  (mode = :fast, solver = :lu): forbidden by rule 1 ($RULE1)",
        "  (mode = :fast, solver = :qr): forbidden by rule 1 ($RULE1)",
        "  (mode = :exact, tol = 0.001): forbidden by rule 2 (exact mode needs a tight tolerance)",
        "  (solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: $RULE1; " *
            "rule 2: exact mode needs a tight tolerance)",
        "  (solver = :qr, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: $RULE1; " *
            "rule 2: exact mode needs a tight tolerance)"]

    "Fable's planning example (design/interface_fable.md, level 4)."
    fable_domains() = (:n => [1, 2, 3], :level => ["low", "mid", "high"], :tol => [1.0, 3.7, 4.9],
                       :kind => [:greedy, :relax, :optim])
end


@testitem "report: agrees with the checker on 50 random problems (§1.3, §1.23, §3.12)" tags=[:skipci] setup=[Checker, ReportSetup] begin
    rng = Xoshiro(0x2026_0927_0052)
    for index in 1:50
        problem = random_problem(rng; strength = 2)
        cs = problem.space
        n = length(cs.names)
        for engine in (IPOG(), GND(seed = index))
            cases = all_pairs(test_space(cs); engine)
            r = report(cases)
            check = check_design(cases, cs)
            # With the same budgets, the report's own exclusions are the ones generation recorded.
            ok = iscomplete(r.coverage) && r.coverage.ordinary.covered == check.ordinary.counts.feasible &&
                 same_exclusions(r.excluded, cases.excluded) && isempty(r.recorded) &&
                 r.strength == 2 && r.n_cases == length(cases)
            # Bonus coverage at strength 3 is the checker's triple coverage of the same rows.
            triples = check_design(cases, cs; strength = 3).ordinary.counts
            ok &= r.bonus.applicable && r.bonus.strength == 3 && r.bonus.unknown == 0 &&
                  (r.bonus.covered, r.bonus.feasible) == (triples.covered, triples.feasible)
            # The prefix curve: nondecreasing, one point per row, the last the whole
            # coverage, and each point the checker's coverage of that prefix.
            p = r.prefix
            ok &= length(p) == length(cases) && issorted([x.covered for x in p]) &&
                  p[end].covered == r.coverage.ordinary.covered &&
                  all(x -> x.feasible == check.ordinary.counts.feasible && x.unknown == 0, p)
            for k in unique([1, cld(length(cases), 2), length(cases)])
                isempty(cases) && break
                ok &= p[k].covered == check_design(cases[1:k], cs).ordinary.counts.covered
            end
            ok || @error "report disagrees on random problem $index" engine problem
            @test ok
        end
    end
end


@testitem "report: the solver example, exactly (§1.23, §1.4, §9.7)" setup=[ReportSetup] begin
    space = solver_space()
    cases = all_pairs(space)
    r = report(cases)
    @test r.guarantee == "5 cases cover all 11 feasible pairs of a 12-combination space " *
                         "(3 pairs forbidden, 2 impossible under the constraints)"
    @test shown(r) == join([r.guarantee; "excluded:"; SOLVER_EXCLUDED;
        "size: 5 cases; lower bound 4: the 4 feasible combinations of mode and solver need a case each";
        "bonus: 5 of 5 feasible triples covered";
        "prefix curve:";
        "  first 1 of 5 cover 27% (3 of 11)";
        "  first 2 of 5 cover 54% (6 of 11)";
        "  first 3 of 5 cover 72% (8 of 11)";
        "  first 4 of 5 cover 90% (10 of 11)";
        "  first 5 of 5 cover 100% (11 of 11)";
        "seed: none (Auto uses no randomness)"], "\n")
    @test sprint(show, r) == r.guarantee
    @test (r.strategy, r.engine, r.seed, r.n_must_include, r.strength) == (:covering, :Auto, nothing, 0, 2)
    @test same_exclusions(r.excluded, cases.excluded) && isempty(r.recorded)
    @test r.excluded == r.coverage.ordinary.excluded
    @test [x.covered for x in r.prefix] == [3, 6, 8, 10, 11]

    # GND names its seed; must-include rows are counted; stronger groups are named.
    g = report(all_pairs(space; engine = GND(seed = 3)))
    @test endswith(g.guarantee, "; GND seed 3") && g.seed == 3
    @test occursin("seed: 3 (GND(seed = 3) repeats these cases)", shown(g))
    @test occursin("GND with the caller's rng", report(all_pairs(space; engine = GND(rng = Xoshiro(1)))).guarantee)
    kept = report(all_pairs(space; must_include = [(mode = :fast, solver = :none, tol = 1e-3), (solver = :lu,)]))
    @test endswith(kept.guarantee, "; 2 must-include rows kept first") && kept.n_must_include == 2
    grouped = report(covering(space; stronger = [(:mode, :solver, :tol) => 3]))
    @test startswith(grouped.guarantee, "5 cases cover all 16 feasible combinations at strength 2, " *
                                        "3 within (mode, solver, tol) of a 12-combination space")
    @test startswith(report(all_values(space)).guarantee,
                     "3 cases cover all 7 feasible combinations at strength 1 of a 12-combination space")
    # No percentage above 100 or rounded up to it: 2 of 3 is 66%.
    @test occursin("first 2 of 3 cover 66% (2 of 3)", shown(report(excursions((a = [1, 2, 3],)))))
end


@testitem "report: excursions and full factorials measure at min(2, n) and say so (§1.12, §7.7)" setup=[ReportSetup] begin
    space = solver_space()
    ex = report(excursions(space; from = (mode = :exact, solver = :lu, tol = 1e-6), distance = 2))
    @test ex.strength == 2 && ex.strategy == :excursion
    @test ex.guarantee == "4 cases within distance 2 of (mode = :exact, solver = :lu, tol = 1.0e-6); " *
        "6 rows dropped; never appears: tol = 0.001; not a covering design; measured at strength 2, " *
        "the cases cover 9 of 11 feasible pairs (3 pairs forbidden, 2 impossible under the constraints); " *
        "2 pairs missing"
    @test !iscomplete(ex.coverage) && length(ex.coverage.ordinary.missing) == 2
    @test [e.target for e in ex.excluded] == [e.target for e in report(all_pairs(space)).excluded]   # measured
    @test occursin("seed: none (an excursion uses no randomness)", shown(ex))
    ff = report(full_factorial(space))
    @test ff.guarantee == "5 cases, every valid row of 12; measured at strength 2, the cases cover all " *
                          "11 feasible pairs (3 pairs forbidden, 2 impossible under the constraints)"
    @test ff.strength == 2 && iscomplete(ff.coverage) && ff.bonus.applicable && ff.bonus.covered == 5
    @test occursin("seed: none (a full factorial uses no randomness)", shown(ff))
    # One parameter: strength 1, the only strength (§1.12, §11.2), and no bonus.
    one = report(excursions((a = [1, 2, 3],)))
    @test one.strength == 1
    @test one.guarantee == "3 cases within distance 1 of (a = 1,); not a covering design; measured at " *
                           "strength 1, the cases cover all 3 feasible combinations"
    @test !one.bonus.applicable
    @test occursin("bonus coverage not applicable: strength 2 exceeds the number of parameters, 1", shown(one))
    @test report(full_factorial((a = [1, 2],))).strength == 1
    # Two parameters: strength 2 is the parameter count, so no bonus either.
    two = report(full_factorial([1, 2], [:a, :b]))
    @test two.strength == 2 && !two.bonus.applicable && two.bonus.reason ==
          "strength 3 exceeds the number of parameters, 2"
end


@testitem "report: bonus coverage is not applicable at strength n (§3.12)" setup=[Checker, ReportSetup] begin
    space = solver_space()
    full = report(covering(space; strength = 3))
    @test !full.bonus.applicable && full.bonus.strength == 4
    @test (full.bonus.covered, full.bonus.feasible, full.bonus.unknown) == (0, 0, 0)
    @test occursin("\nbonus coverage not applicable: strength 4 exceeds the number of parameters, 3\n", shown(full))
    # At strength n - 1 the bonus is the whole row: the checker's valid rows.
    pairs = all_pairs(space)
    b = report(pairs).bonus
    @test b.applicable && (b.covered, b.feasible) ==
          (check_design(pairs, fable_solver.space; strength = 3).ordinary.counts.covered, 5)
end


@testitem "report: empty and positional results (§1.18, §1.24)" setup=[Checker, ReportSetup] begin
    empty = all_pairs(test_space(disconnected_unsat))
    @test isempty(empty)
    r = report(empty)
    @test r.guarantee == "0 cases: no pair of a 12-combination space is feasible " *
                         "(4 pairs forbidden, 12 impossible under the constraints)"
    @test isempty(r.prefix) && occursin("\nprefix curve: no cases\n", shown(r))
    @test r.bonus.applicable && (r.bonus.covered, r.bonus.feasible) == (0, 0)
    @test length(r.excluded) == 16
    positional = all_pairs([1, 2, 3], [:a, :b], [true, false])
    p = report(positional)
    @test p.guarantee == "$(length(positional)) cases cover all 16 feasible pairs of a 12-combination space"
    @test p.prefix[end].covered == 16 && p.bonus.applicable
    ex = report(excursions([1, 2, 3], [:a, :b]; distance = 1))
    @test startswith(ex.guarantee, "4 cases within distance 1 of (1, :a); not a covering design")
end


@testitem "report under limits: bounds, no percentage, nothing complete (§1.7, §3.10, §3.12)" setup=[Checker, ReportSetup] begin
    f = limit_exhaustion
    cases = all_pairs(test_space(f))
    r = report(cases; feasibility_limit = f.request.small_limit)
    text = shown(r)
    @test !occursin('%', text) && !occursin("complete", text) && !occursin(" all ", r.guarantee)
    @test r.guarantee == "1 case covers 28 of at least 28 feasible pairs of a 65536-combination space; " *
                         "420 pairs unresolved (feasibility_limit = 1); no exact percentage"
    @test !iscomplete(r.coverage) && length(r.coverage.ordinary.unknown) == 420
    @test r.bonus.applicable && r.bonus.unknown > 0 && r.bonus.covered == 56
    @test occursin("\nbonus: 56 of at least 56 feasible triples covered; $(r.bonus.unknown) triples " *
                   "unresolved (feasibility_limit = 1); no exact percentage\n", text)
    @test only(r.prefix) == (cases = 1, covered = 28, feasible = 28, unknown = 420)
    @test occursin("\nprefix curve:\n  first 1 of 1 cover 28 of at least 28\n", text)
    # This measurement resolved none of the 420 exclusions, so generation's
    # proofs are shown in their place, marked as recorded (§1.23, §3.15).
    @test isempty(r.excluded) && r.recorded == cases.excluded && length(r.recorded) == 420
    @test occursin("\nexcluded:\n  (x1 = 1, x2 = 1): impossible because", text)
    @test count("(recorded at generation)", text) == 20
    @test occursin("\n  and 400 more\n", text)
    # The default limit resolves everything.
    whole = report(cases)
    @test iscomplete(whole.coverage) && whole.guarantee ==
          "1 case covers all 28 feasible pairs of a 65536-combination space (420 pairs impossible under the constraints)"
    @test whole.bonus.unknown == 0 && whole.bonus.covered == whole.bonus.feasible == 56
    @test same_exclusions(whole.excluded, cases.excluded) && isempty(whole.recorded)
    @test !occursin("recorded at generation", shown(whole))
    @test occursin("first 1 of 1 cover 100% (28 of 28)", shown(whole))
end


@testitem "report: must-include rows are exempt from an excursion's distance (§7.5, §7.9, review round 1)" setup=[Checker, ReportSetup] begin
    space = solver_space()
    far = (mode = :exact, solver = :lu, tol = 1e-6)   # three parameters from the default base
    ex = excursions(space; distance = 0, must_include = [far])
    @test collect(ex) == [far, (mode = :fast, solver = :none, tol = 1e-3)]
    r = report(ex)
    @test r.guarantee == "1 must-include row kept first, then 1 case within distance 0 of " *
        "(mode = :fast, solver = :none, tol = 0.001); never appears: solver = :qr; not a covering design; " *
        "measured at strength 2, the cases cover 6 of 11 feasible pairs (3 pairs forbidden, " *
        "2 impossible under the constraints); 5 pairs missing"
    @test !occursin("2 cases within distance 0", r.guarantee)
    # The counts are those of every row, the must-include row included.
    c = coverage(ex; strength = 2)
    @test (r.n_cases, r.n_must_include) == (2, 1)
    @test r.coverage.ordinary.covered == c.ordinary.covered == 6
    @test r.coverage.ordinary.missing == c.ordinary.missing
    @test r.coverage.ordinary.covered == check_design(ex, fable_solver.space).ordinary.counts.covered
    @test r.prefix[end].covered == 6 && r.prefix[1].covered == 3
    # A must-include row equal to the base is not repeated (§7.11).
    same = report(excursions(space; distance = 0, must_include = [(mode = :fast, solver = :none, tol = 1e-3)]))
    @test startswith(same.guarantee, "1 must-include row kept first, then 0 cases within distance 0 of ")
    @test same.n_cases == 1
    # Rows within the distance keep the plain wording when nothing is kept first.
    @test startswith(report(excursions(space; distance = 0)).guarantee, "1 case within distance 0 of ")
    two = report(excursions(space; distance = 1, must_include = [far, far]))
    @test startswith(two.guarantee, "2 must-include rows kept first, then 2 cases within distance 1 of ")
    @test two.n_cases == 4 && !occursin("; 2 must-include rows kept first", two.guarantee)
    # Covering and full factorial results still name the must-include rows in the tail.
    @test startswith(report(full_factorial(space; must_include = [far])).guarantee,
                     "5 cases, every valid row of 12; 1 must-include row kept first; measured at strength 2")
end


@testitem "report: its exclusions are its own measurement; recorded ones only for unresolved targets (§1.23, §3.13, §3.15)" setup=[Checker, ReportSetup] begin
    space = solver_space()
    implied(list) = filter(e -> e.status == :implied, list)
    # Generated with explanation_limit = 1, reported with the default: the
    # report's search verifies both implied exclusions.
    cut = all_pairs(space; explanation_limit = 1)
    @test all(e -> e.minimal == :unresolved, implied(cut.excluded))
    r = report(cut)
    @test length(implied(r.excluded)) == 2
    @test all(e -> e.minimal == :verified && e.limit === nothing && e.rules == [1, 2], implied(r.excluded))
    @test isempty(r.recorded)
    @test shown(r) == shown(report(all_pairs(space)))
    @test !occursin("unresolved", shown(r)) && !occursin("recorded at generation", shown(r))
    # Generated with the default, reported with explanation_limit = 1: the
    # report shows what it verified, the unresolved explanations, with the
    # limit that cut them short; generation's proofs are not substituted.
    full = all_pairs(space)
    q = report(full; explanation_limit = 1)
    @test all(e -> e.minimal == :verified, implied(full.excluded))
    @test all(e -> e.minimal == :unresolved && e.limit == (:explanation_limit => 1), implied(q.excluded))
    @test isempty(q.recorded)
    @test q.guarantee == "5 cases cover all 11 feasible pairs of a 12-combination space (3 pairs forbidden, " *
                         "2 impossible under the constraints, 2 with an unresolved explanation)"
    @test count("(explanation unresolved: explanation_limit = 1 reached)", shown(q)) == 2
    @test !occursin("recorded at generation", shown(q))
    @test q.excluded == q.coverage.ordinary.excluded
    # An excursion records no exclusions, so it has none to fall back on.
    ex = report(excursions(space; distance = 1); feasibility_limit = 1)
    @test isempty(ex.recorded)
end


@testitem "Report: plain(report) has no executable state and round-trips through repr (§1.23, review round 1)" setup=[Checker, ReportSetup] begin
    using UnitTestDesign: plain
    leaf(x) = x isa Union{Int, Float64, String, Symbol, Bool, Nothing}
    "Every value in `x`, recursively, is a NamedTuple, a Vector, or a plain leaf."
    function plain_tree(x)
        x isa Union{Function, TestSpace, Constraint, UnitTestDesign.RuleTable} && return false
        x isa NamedTuple && return all(plain_tree, values(x))
        x isa Vector && return all(plain_tree, x)
        return leaf(x)
    end
    roundtrip(x) = eval(Meta.parse(repr(x)))

    space = solver_space()
    rows = [(mode = :fast, solver = :none, tol = 1e-3), (mode = :fast, solver = :qr, tol = 1e-3),
            (:exact, :lu, 1e-6)]
    reports = [report(all_pairs(space)),
               report(excursions(space; distance = 0, must_include = [(mode = :exact, solver = :lu, tol = 1e-6)])),
               report(covering(space; stronger = [(:mode, :solver, :tol) => 3]); explanation_limit = 1),
               report(all_pairs(test_space(limit_exhaustion)); feasibility_limit = 1),
               report(all_pairs([1, 2, 3], [:a, :b], [true, false])),
               report(all_pairs(test_space(invalid_beside_ordinary)))]
    for r in reports
        x = plain(r)
        @test plain_tree(x)
        y = roundtrip(x)
        @test x == y && plain_tree(y)
        @test x.guarantee == r.guarantee && x.n_cases == r.n_cases
        @test x.coverage.ordinary.covered == r.coverage.ordinary.covered
        @test length(x.excluded) == length(r.excluded) && length(x.recorded) == length(r.recorded)
    end
    x = plain(reports[1])
    @test x.coverage.space == (names = [:mode, :solver, :tol],
                               domains = [[":fast", ":exact"], [":none", ":lu", ":qr"], ["0.001", "1.0e-6"]],
                               rules = ["@require(mode == :exact || solver == :none)",
                                        "exact mode needs a tight tolerance"])
    @test x.excluded[4] == (target = (solver = :lu, tol = 0.001), status = :implied, rules = [1, 2],
        labels = ["@require(mode == :exact || solver == :none)", "exact mode needs a tight tolerance"],
        minimal = :verified, limit = nothing)
    @test x.bonus == (strength = 3, covered = 5, feasible = 5, unknown = 0,
                      negative = (covered = 0, feasible = 0, unknown = 0), applicable = true, reason = "")
    @test x.prefix[end] == (cases = 5, covered = 11, feasible = 11, unknown = 0)
    @test x.prefix_negative[end] == (cases = 5, covered = 0, feasible = 0, unknown = 0)
    @test (x.strategy, x.engine, x.seed, x.n_must_include) == (:covering, :Auto, nothing, 0)
    @test plain(reports[3]).coverage.stronger == [(names = [:mode, :solver, :tol], strength = 3)]
    # With Invalid values the negative prefix curve and bonus are plain data too.
    xi = plain(reports[6])
    @test xi.prefix_negative[end] == (cases = 6, covered = 4, feasible = 4, unknown = 0)
    @test xi.bonus.negative == (covered = 2, feasible = 3, unknown = 0)
    @test plain(design_sizes(test_space(invalid_beside_ordinary))).has_invalid
    @test plain(reports[3]).excluded[4].limit == (keyword = :explanation_limit, value = 1)
    # Coverage of hand-written rows: rejected rows, tuples named by the space.
    c = coverage(rows, space)
    xc = plain(c)
    @test plain_tree(xc) && roundtrip(xc) == xc
    @test [r.row for r in xc.ordinary.rejected] == [(mode = :fast, solver = :qr, tol = 0.001)]
    @test xc.ordinary.rejected[1].reason == :violates_rule && xc.ordinary.rejected[1].rules == [1]
    @test xc.ordinary.groups[1].names == [:mode, :solver, :tol]
    # Values that are not plain become their repr: Invalid, Partition, a Char, an Int32.
    wrapped = TestSpace((a = [1, Invalid(0)], b = [Partition(:tiny, rng -> 1e-9), 'x'], c = Int32[3, 4]))
    w = plain(coverage([(a = 1, b = 'x', c = Int32(3)), (a = Invalid(0), b = 'x', c = Int32(4))], wrapped))
    @test plain_tree(w) && roundtrip(w) == w
    @test w.space.domains == [["1", "Invalid(0)"], ["Partition(:tiny)", "'x'"], ["3", "4"]]
    @test w.ordinary.missing[1] == (a = 1, b = "Partition(:tiny)")
    @test !isempty(w.negative.missing) && all(t -> get(t, :a, nothing) == "Invalid(0)", w.negative.missing)
    # DesignSizes.
    d = plain(design_sizes(space))
    @test plain_tree(d) && roundtrip(d) == d
    none = (covered = 0, feasible = 0, unknown = 0)
    @test d.total == 12 && d.valid == 5 && !d.has_invalid && d.rows[2] == (strategy = "covering(1)",
        kind = :covering, level = 1, status = :ok, message = "", cases = 3, share = 0.6,
        pairs = (covered = 8, feasible = 11, unknown = 0), triples = (covered = 3, feasible = 5, unknown = 0),
        negative_cases = 0, negative_pairs = none, negative_triples = none, engine = "Auto()")
    @test d.engines == ["Auto()"]
    # Above `limit` the valid count is unknown; above typemax(Int) the total is a string of digits.
    wide = plain(design_sizes(fill(1:10, 5)...; strengths = Int[], distances = Int[], limit = 10))
    @test wide.total === 100_000 && wide.valid === nothing && plain_tree(wide)
    @test wide.rows[1].status == :resource_limit && wide.rows[1].cases === nothing
    huge = plain(design_sizes(fill(1:100, 12)...; strengths = Int[], distances = Int[], limit = 10))
    @test huge.total == string(big(100)^12) && plain_tree(huge) && roundtrip(huge) == huge
    # The Report itself still prints as its guarantee, and limits are checked first.
    r = reports[1]
    @test endswith(sprint(show, [r]), "[5 cases cover all 11 feasible pairs of a 12-combination space " *
                                      "(3 pairs forbidden, 2 impossible under the constraints)]")
    @test occursin("feasibility_limit", message(() -> report(all_pairs(solver_space()); feasibility_limit = 0)))
end


@testitem "design_sizes: Fable's example, and the solver space's valid share (§8.3, plan Phase 5 step 4)" setup=[Checker, ReportSetup] begin
    t = design_sizes(fable_domains()...)
    @test [r.strategy for r in t.rows] ==
          ["full_factorial", "covering(1)", "covering(2)", "covering(3)", "excursions(1)", "excursions(2)"]
    @test [r.cases for r in t.rows] == [81, 3, 9, 27, 9, 33]
    @test (t.total, t.valid, t.engine) == (81, 81, :Auto)
    @test all(r -> r.status == :ok, t.rows)
    @test [r.pairs.covered for r in t.rows] == [54, 18, 54, 54, 30, 54]
    @test [r.triples.covered for r in t.rows] == [108, 12, 36, 108, 28, 76]
    @test all(r -> (r.pairs.feasible, r.triples.feasible) == (54, 108), t.rows)
    @test shown(t) == join([
        "strategy        cases   share  pairs  triples",
        "full_factorial     81  100.0%  54/54  108/108  valid 81 of 81",
        "covering(1)         3    3.7%  18/54   12/108",
        "covering(2)         9   11.1%  54/54   36/108",
        "covering(3)        27   33.3%  54/54  108/108",
        "excursions(1)       9   11.1%  30/54   28/108",
        "excursions(2)      33   40.7%  54/54   76/108",
        "case counts are the rows each strategy produced with Auto, not lower bounds"], "\n")
    # The same through a NamedTuple and a TestSpace; the counts come from running the strategies.
    @test [r.cases for r in design_sizes(TestSpace(fable_domains()...)).rows] == [81, 3, 9, 27, 9, 33]
    @test design_sizes(fable_domains()...).rows[3].cases == length(all_pairs(fable_domains()...))

    s = design_sizes(solver_space())
    @test (s.total, s.valid) == (12, 5)
    @test [r.cases for r in s.rows] == [5, 3, 5, 5, 2, 3]
    @test [r.share for r in s.rows] == [1.0, 0.6, 1.0, 1.0, 0.4, 0.6]
    @test [r.pairs.covered for r in s.rows] == [11, 8, 11, 11, 5, 7]
    @test all(r -> r.pairs.feasible == 11 && r.triples.feasible == 5, s.rows)
    @test shown(s) == join([
        "strategy        cases   share  pairs  triples",
        "full_factorial      5  100.0%  11/11      5/5  valid 5 of 12",
        "covering(1)         3   60.0%   8/11      3/5",
        "covering(2)         5  100.0%  11/11      5/5",
        "covering(3)         5  100.0%  11/11      5/5",
        "excursions(1)       2   40.0%   5/11      2/5",
        "excursions(2)       3   60.0%   7/11      3/5",
        "case counts are the rows each strategy produced with Auto, not lower bounds"], "\n")
    # The checker agrees on each design's pairs.
    for (row, cases) in zip(s.rows[2:4], (all_values(solver_space()), all_pairs(solver_space()),
                                          all_triples(solver_space())))
        @test row.pairs.covered == check_design(cases, fable_solver.space).ordinary.counts.covered
    end
    # A GND table names its engine.
    @test design_sizes(solver_space(); engine = GND()).engine == :GND
end


@testitem "design_sizes: unknown valid count, resource limits, skipped strengths (§3.12, §7.3)" setup=[Checker, ReportSetup] begin
    space = solver_space()
    # Above `limit` the valid rows are not counted, so there are no shares.
    t = design_sizes(space; limit = 10)
    @test t.valid === nothing && t.total == 12
    ff = t.rows[1]
    @test ff.status == :resource_limit && ff.cases === nothing && ff.share === nothing && ff.pairs === nothing
    @test occursin("limit = 10 reached", ff.message)
    @test all(r -> r.share === nothing, t.rows)
    @test [r.cases for r in t.rows[2:end]] == [3, 5, 5, 2, 3]
    @test occursin("\nfull_factorial      —      —      —        —  total 12 only; limit = 10 reached", shown(t))
    # A strategy that stops at feasibility_limit = 1 records its status; the others still report.
    lim = design_sizes(space; feasibility_limit = 1)
    stopped = lim.rows[2]
    @test stopped.strategy == "covering(1)" && stopped.status == :resource_limit && stopped.cases === nothing
    @test startswith(stopped.message, "feasibility_limit = 1 reached")
    @test [r.status for r in lim.rows] == [:ok, :resource_limit, :ok, :ok, :ok, :ok]
    @test [r.cases for r in lim.rows] == [5, nothing, 5, 5, 2, 3]
    @test occursin("\ncovering(1)         —       —      —        —  feasibility_limit = 1 reached", shown(lim))
    # Unresolved measurements print as bounds, never as a share of an unknown.
    f = limit_exhaustion
    u = design_sizes(test_space(f); strengths = [2], distances = [], feasibility_limit = 1)
    @test u.rows[1].status == :ok && u.rows[1].pairs.unknown > 0
    @test u.rows[2].status == :resource_limit
    @test occursin("28/≥28", shown(u)) && !occursin("28/28", shown(u))
    # Strengths above the parameter count are left out, not errors.
    wide = design_sizes([1, 2], [:a, :b]; strengths = 1:4)
    @test [r.strategy for r in wide.rows] == ["full_factorial", "covering(1)", "covering(2)", "excursions(1)", "excursions(2)"]
    @test all(r -> r.triples === nothing, wide.rows) && all(r -> r.pairs !== nothing, wide.rows)
    @test occursin("—", shown(wide))
    # An excursion whose default base breaks a rule is recorded, not thrown; `from` fixes it.
    bad = TestSpace((a = [1, 2], b = [1, 2]); constraints = [forbid((a = 1, b = 1))])
    b = design_sizes(bad; strengths = [2])
    @test [r.status for r in b.rows] == [:ok, :ok, :invalid_base, :invalid_base]
    @test occursin("pass `from`", b.rows[3].message)
    @test all(r -> r.status == :ok, design_sizes(bad; strengths = [2], from = (a = 2, b = 2)).rows)
    # Keywords are checked first, in the caller's words.
    @test occursin("strengths", message(() -> design_sizes(space; strengths = [0])))
    @test occursin("distances", message(() -> design_sizes(space; distances = [-1])))
    @test occursin("strengths is a list", message(() -> design_sizes(space; strengths = 2)))
    @test occursin("limit", message(() -> design_sizes(space; limit = 0)))
    @test occursin("engine", message(() -> design_sizes(space; engine = :ipog)))
    @test occursin("constraints belong to the space", message(() -> design_sizes(space; constraints = [])))
end


@testitem "report: the prefix curve and bonus give ordinary and negative figures apart (§5.9, §5.10, review round 1)" setup=[Checker, ReportSetup] begin
    as_check(x::Invalid) = CheckInvalid(as_check(x.value))
    as_check(x) = x
    as_check(row::Union{NamedTuple, Tuple}) = map(as_check, row)

    # The reviewer's two-domain example: the first row covers the one ordinary
    # pair while both negative targets are missing, and the curve says so.
    space = TestSpace((a = [1, Invalid(0)], b = [1, Invalid(0)]))
    cases = all_pairs(space)
    r = report(cases)
    @test split(shown(r), "\n")[2:end] == [
        "size: 3 cases, minimal: the 1 combination of a and b needs a case; and 2 negative cases, bounded in " *
        "the same way for each Invalid value",
        "bonus coverage not applicable: strength 3 exceeds the number of parameters, 2",
        "prefix curve:",
        "  first 1 of 3 cover 100% of ordinary pairs (1 of 1); negative 0 of 2",
        "  first 2 of 3 cover 100% of ordinary pairs (1 of 1); negative 1 of 2",
        "  first 3 of 3 cover 100% of ordinary pairs (1 of 1); negative 2 of 2",
        "seed: none (Auto uses no randomness)"]
    @test [p.covered for p in r.prefix] == [1, 1, 1]
    @test [p.covered for p in r.prefix_negative] == [0, 1, 2]
    @test all(p -> p.feasible == 2 && p.unknown == 0, r.prefix_negative)
    @test r.prefix_negative[end].covered == r.coverage.negative.covered
    @test r.bonus.negative == (covered = 0, feasible = 0, unknown = 0) && !r.bonus.applicable

    # invalid_beside_ordinary: the bonus measures negative triples too.
    cs = invalid_beside_ordinary.space
    r = report(all_pairs(test_space(cs)))
    @test split(shown(r), "\n")[(end - 7):end] == [
        "bonus: 4 of 4 feasible triples covered; negative: 2 of 3",
        "prefix curve:",
        "  first 2 of 6 cover 66% of ordinary pairs (6 of 9); negative 0 of 4",
        "  first 3 of 6 cover 88% of ordinary pairs (8 of 9); negative 0 of 4",
        "  first 4 of 6 cover 100% of ordinary pairs (9 of 9); negative 0 of 4",
        "  first 5 of 6 cover 100% of ordinary pairs (9 of 9); negative 2 of 4",
        "  first 6 of 6 cover 100% of ordinary pairs (9 of 9); negative 4 of 4",
        "seed: none (Auto uses no randomness)"]
    @test r.bonus.negative == (covered = 2, feasible = 3, unknown = 0)

    # Every figure against the oracle, prefix by prefix, on spaces with one and
    # two invalid parameters, no ordinary row, and a whole-case rule.
    two = CheckSpace((a = [1, 2, CheckInvalid(0)], b = [CheckInvalid(:z), 1, 2], c = [1, 2]),
        [((:a, :c), (a, c) -> a == 1 && c == 2),
         ((:b, :c), (b, c) -> b == 2 && c == 1),
         ((:a, :b, :c), (a, b, c) -> a == 2 && b == 1 && c == 2)])
    for (cs, strengths) in ((invalid_beside_ordinary.space, 1:2), (empty_ordinary_negative_seed.space, 1:1),
                            (two, 1:2)),
        strength in strengths, engine in (IPOG(), GND(seed = 7))
        cases = covering(test_space(cs); strength, engine)
        r = report(cases)
        rows = as_check.(collect(cases))
        ok = length(r.prefix_negative) == length(cases)
        for k in eachindex(rows)
            check = check_design(rows[1:k], cs; strength)
            ok &= r.prefix[k].covered == check.ordinary.counts.covered &&
                  r.prefix_negative[k].covered == check.negative.counts.covered &&
                  r.prefix_negative[k].feasible == check.negative.counts.feasible &&
                  r.prefix_negative[k].unknown == 0
        end
        if strength < length(cs.names)
            above = check_design(rows, cs; strength = strength + 1)
            ok &= r.bonus.negative == (covered = above.negative.counts.covered,
                                       feasible = above.negative.counts.feasible, unknown = 0)
            ok &= (r.bonus.covered, r.bonus.feasible) == (above.ordinary.counts.covered, above.ordinary.counts.feasible)
        end
        ok || @error "report's negative figures disagree with the oracle" cs.names strength engine
        @test ok
    end

    # With no feasible ordinary target the lines say so, and a search at its
    # limit leaves the negative figures as bounds (§3.10).
    space = TestSpace((n = [1, Invalid(0)], x1 = 1:4, x2 = 1:4, x3 = 1:4, x4 = 1:4);
        constraints = [forbid(n -> n == 1, :n),
                       forbid((a, b, c, d) -> !(a == b == c == d == 4), :x1, :x2, :x3, :x4)])
    cases = all_pairs(space)
    lines = split(shown(report(cases; feasibility_limit = 1)), "\n")
    @test lines[(end - 3):end] == [
        "bonus: 0 of 0 feasible triples covered; negative: 6 of at least 6, 90 unresolved",
        "prefix curve:",
        "  first 1 of 1: no ordinary pair is feasible; negative 4 of at least 4",
        "seed: none (Auto uses no randomness)"]
    @test occursin("\n  first 1 of 1: no ordinary pair is feasible; negative 4 of 4\n", shown(report(cases)))
end


@testitem "design_sizes: negative rows and targets are counted apart (§5.10, review round 1)" setup=[Checker, ReportSetup] begin
    as_check(x::Invalid) = CheckInvalid(as_check(x.value))
    as_check(x) = x
    as_check(row::Union{NamedTuple, Tuple}) = map(as_check, row)

    cs = invalid_beside_ordinary.space
    space = test_space(cs)
    t = design_sizes(space)
    @test t.has_invalid && (t.total, t.valid) == (12, 7)
    @test shown(t) == join([
        "strategy        cases   share      pairs    triples",
        "full_factorial  4 + 3  100.0%  9/9 + 4/4  4/4 + 3/3  valid 7 of 12",
        "covering(1)     2 + 1   42.9%  6/9 + 2/4  2/4 + 1/3",
        "covering(2)     4 + 2   85.7%  9/9 + 4/4  4/4 + 2/3",
        "covering(3)     4 + 3  100.0%  9/9 + 4/4  4/4 + 3/3",
        "excursions(1)   3 + 1   57.1%  7/9 + 2/4  3/4 + 1/3",
        "excursions(2)   4 + 2   85.7%  9/9 + 3/4  4/4 + 2/3",
        "cells with + read ordinary + negative: rows without and with an Invalid value, and the targets " *
            "each kind covers",
        "case counts are the rows each strategy produced with Auto, not lower bounds"], "\n")
    # Each figure is the oracle's measure of the design the strategy produces.
    designs = [full_factorial(space), all_values(space), all_pairs(space), all_triples(space),
               excursions(space; distance = 1), excursions(space; distance = 2)]
    @test [r.cases for r in t.rows] == length.(designs)
    for (row, design) in zip(t.rows, designs)
        rows = as_check.(collect(design))
        @test row.negative_cases == count(hasinvalid, design)
        for (s, ordinary, negative) in ((2, row.pairs, row.negative_pairs), (3, row.triples, row.negative_triples))
            check = check_design(rows, cs; strength = s)
            @test ordinary == (covered = check.ordinary.counts.covered, feasible = check.ordinary.counts.feasible,
                               unknown = 0)
            @test negative == (covered = check.negative.counts.covered, feasible = check.negative.counts.feasible,
                               unknown = 0)
        end
    end
    # The full factorial's negative rows are exactly the oracle's valid negative rows.
    @test (t.rows[1].cases - t.rows[1].negative_cases, t.rows[1].negative_cases) ==
          (length(valid_rows(cs)), length(negative_rows(cs)))

    # A strategy stopped at a limit has no negative figures either.
    stopped = TestSpace((n = [1, Invalid(0)], x1 = 1:4, x2 = 1:4, x3 = 1:4, x4 = 1:4);
        constraints = [forbid(n -> n == 1, :n),
                       forbid((a, b, c, d) -> !(a == b == c == d == 4), :x1, :x2, :x3, :x4)])
    u = design_sizes(stopped; strengths = [2], distances = [], feasibility_limit = 1)
    @test u.rows[2].status == :resource_limit
    @test (u.rows[2].negative_cases, u.rows[2].negative_pairs, u.rows[2].negative_triples) == (nothing, nothing, nothing)
    @test occursin("\ncovering(2)         —       —           —           —  feasibility_limit = 1 reached", shown(u))
    @test occursin("\nfull_factorial  0 + 1  100.0%  0/0 + 4/≥4  0/0 + 6/≥6  valid 1 of 512", shown(u))

    # A space without Invalid values has zero negative figures and prints as before.
    s = design_sizes(solver_space())
    none = (covered = 0, feasible = 0, unknown = 0)
    @test !s.has_invalid
    @test all(r -> r.negative_cases == 0 && r.negative_pairs == none && r.negative_triples == none, s.rows)
    @test !occursin("+", shown(s))
end


@testitem "report and design_sizes: a count of one is singular, and 8 and 18 take \"an\" (Phase 6 review)" setup=[ReportSetup] begin
    # One feasible pair: the rules forbid three of the four.
    one_pair = TestSpace((a = [1, 2], b = [:x, :y]);
                         constraints = [forbid((a = 1, b = :x)), forbid((a = 2, b = :y)), forbid((a = 2, b = :x))])
    r = report(all_pairs(one_pair))
    @test r.guarantee == "1 case covers the 1 feasible pair of a 4-combination space (3 pairs forbidden)"
    @test occursin("\n  first 1 of 1 cover 100% (1 of 1)\n", shown(r))
    # One valid row: 3 feasible pairs, and the bonus is 1 feasible triple.
    one_row = TestSpace((a = [1, 2], b = [:x, :y], c = [true, false]);
                        constraints = [@require(a == 1 && b == :x && c)])
    r = report(all_pairs(one_row))
    @test startswith(r.guarantee, "1 case covers all 3 feasible pairs of an 8-combination space (")
    @test occursin("\nbonus: 1 of 1 feasible triple covered\n", shown(r))
    # With Invalid values the ordinary prefix figure is labeled, and agrees too.
    negative = report(all_pairs(TestSpace((a = [1, Invalid(0)], b = [:x]))))
    @test occursin("cover 100% of ordinary pairs (1 of 1); negative", shown(negative))
    @test sprint(show, design_sizes((a = [1, 2], b = [:x]); strengths = 1:0, distances = 1:0)) ==
          "DesignSizes: 1 strategy for 2 parameters"
    @test sprint(show, design_sizes((a = [1, 2], b = [:x]); strengths = 1:1, distances = 1:0)) ==
          "DesignSizes: 2 strategies for 2 parameters"
    @test sprint(show, report(all_pairs(1:3, 1:6))) == "18 cases cover all 18 feasible pairs of an 18-combination space"
end


@testitem "report and design_sizes: one memo, one answer cache per measurement; each figure is a separate measurement's (§3.5, plan Stage C decision 7)" setup=[Checker, ReportSetup] begin
    using Base.CoreLogging: with_logger, NullLogger   # a lazily evaluated rule warns
    # A report measures the rows twice, at its strength and for the bonus one
    # above, with one lazy-rule memo and a fresh answer cache for each. So every
    # figure is that of a `coverage` call, which has a memo of its own, under
    # any limit (probe 03b). Its answer caches must stay apart: in the space of
    # two components below, a bonus that shared the first measurement's answer
    # caches would find other component witnesses cached, and at
    # feasibility_limit = 4 would leave 14 triples unresolved, not 10.
    same_part(a, b) = (a.covered, a.feasible, a.rows, a.duplicates) == (b.covered, b.feasible, b.rows, b.duplicates) &&
        isequal(a.missing, b.missing) && isequal(a.unknown, b.unknown) && same_exclusions(a.excluded, b.excluded) &&
        a.groups == b.groups && isequal(a.rejected, b.rejected)
    counts(part) = (covered = part.covered, feasible = part.feasible, unknown = length(part.unknown))
    function agrees(cases, limits)
        r = report(cases; limits...)
        base = coverage(cases; limits...)
        ok = same_part(r.coverage.ordinary, base.ordinary) && same_part(r.coverage.negative, base.negative) &&
             r.coverage.limits == base.limits && same_exclusions(r.excluded, [base.ordinary.excluded; base.negative.excluded])
        if r.bonus.applicable
            above = coverage(collect(cases), cases.space; strength = r.strength + 1, limits...)
            ok &= (r.bonus.covered, r.bonus.feasible, r.bonus.unknown) == values(counts(above.ordinary)) &&
                  r.bonus.negative == counts(above.negative)
        end
        return ok
    end
    tight = [(feasibility_limit = 1, explanation_limit = 1), (feasibility_limit = 2,), (feasibility_limit = 3,),
             (feasibility_limit = 4,), (feasibility_limit = 5,), (explanation_limit = 1,), NamedTuple()]
    two = NamedTuple{Tuple(Symbol(c, i) for c in (:a, :b) for i in 1:4)}(Tuple(1:2 for _ in 1:8))
    two_rules = [forbid((a1 = 1, a2 = 1)), forbid((a3 = 1, a4 = 1)), forbid((a2 = 2, a3 = 2)),
                 forbid((b1 = 1, b2 = 1)), forbid((b3 = 1, b4 = 1)), forbid((b2 = 2, b3 = 2))]
    negative = (n = [1, Invalid(0)], x1 = 1:4, x2 = 1:4, x3 = 1:4, x4 = 1:4)
    negative_rules = [forbid(n -> n == 1, :n), forbid((a, b, c, d) -> !(a == b == c == d == 4), :x1, :x2, :x3, :x4)]
    rng = Xoshiro(0x2026_0930_0003)
    problems = [random_problem(rng; strength = 2).space for _ in 1:12]
    # Each space with its rules tabulated, then with every rule lazy.
    both(make) = [with_logger(() -> make(limit), NullLogger()) for limit in (10^5, 1)]
    randoms = reduce(vcat, [both(t -> test_space(cs; tabulation_limit = t)) for cs in problems])
    special = [both(t -> TestSpace(two; constraints = two_rules, tabulation_limit = t));
               both(t -> TestSpace(negative; constraints = negative_rules, tabulation_limit = t))]
    # limit_exhaustion (test "report under limits") only at feasibility_limit
    # 1 to 5: at the default it takes seconds.
    exhaustion = both(t -> test_space(limit_exhaustion; tabulation_limit = t))
    corpus = [[space => tight for space in [randoms; special]]; [space => tight[1:5] for space in exhaustion]]
    for (space, limit_list) in corpus, strength in 1:min(2, length(space.names))
        cases = try
            covering(space; strength)
        catch err
            err isa ResourceLimitError || rethrow()
            continue
        end
        for limits in limit_list
            ok = agrees(cases, limits)
            ok || @error "report's figures differ from separate measurements" space strength limits
            @test ok
        end
    end
    # The space of two components is the one where a shared answer cache
    # shows (14 unresolved triples with one), on the ten cases IPOG gave there
    # until its lookup core (plan §5.5, Phase 4), kept as data: passed back as
    # must-include rows, which cover every pair, they are the whole design.
    ten = [(2, 2, 1, 2, 1, 2, 1, 2), (1, 2, 1, 2, 2, 1, 2, 1), (2, 1, 2, 1, 2, 1, 1, 2), (2, 1, 1, 2, 1, 2, 1, 2),
           (2, 1, 2, 2, 1, 2, 1, 2), (2, 1, 2, 1, 1, 2, 1, 2), (1, 2, 1, 2, 1, 2, 1, 2), (1, 2, 1, 2, 2, 2, 1, 2),
           (2, 1, 2, 1, 2, 1, 2, 1), (1, 2, 1, 2, 2, 1, 2, 2)]
    pinned = covering(TestSpace(two; constraints = two_rules); strength = 2, must_include = ten)
    @test length(pinned) == 10
    r = report(pinned; feasibility_limit = 4)
    @test r.bonus.unknown == 10

    # design_sizes keeps one memo for the call; each figure is that of
    # `coverage(design; strength = s)` with its own.
    for space in special, limits in tight
        t = design_sizes(space; limits...)
        designs = Any[() -> full_factorial(space; limits...);
                      [() -> covering(space; strength = s, limits...) for s in 1:min(3, length(space.names))];
                      [() -> excursions(space; distance = d, limits...) for d in 1:2]]
        for (row, make) in zip(t.rows, designs)
            row.status === :ok || continue
            design = make()
            for (s, ordinary, negative) in ((2, row.pairs, row.negative_pairs), (3, row.triples, row.negative_triples))
                s <= length(space.names) || continue
                c = coverage(design; strength = s, limits...)
                @test (ordinary, negative) == (counts(c.ordinary), counts(c.negative))
            end
        end
    end
end


@testitem "report and design_sizes: a lazy predicate runs at most once per assignment for all the call's measurements (§3.5, §12.19)" begin
    # One whole-case rule over three binary parameters: eight complete
    # assignments. Probe 03a saw report evaluate it 12 to 16 times, and
    # design_sizes 91 times more than its generations do alone.
    seen = NTuple{3, Int}[]
    probe(forbidden) = TestSpace((a = [0, 1], b = [0, 1], c = [0, 1]);
        constraints = [forbid(case -> (push!(seen, Tuple(case)); forbidden(case)); reason = "counted")])
    calls(f) = (empty!(seen); f(); copy(seen))
    for forbidden in (case -> false, case -> case.a == 1 && case.b == 1)
        space = probe(forbidden)
        for design in (all_pairs(space), excursions(space; distance = 1))
            logged = calls(() -> report(design))
            @test !isempty(logged) && allunique(logged)
        end
        # design_sizes' generations are requests, each with its own memo; its
        # measurements share one.
        alone = length(calls(() -> full_factorial(space)))
        for s in 1:3
            alone += length(calls(() -> covering(space; strength = s)))
        end
        for d in 1:2
            alone += length(calls(() -> isallowed(space, (a = 0, b = 0, c = 0))))
            alone += length(calls(() -> excursions(space; distance = d)))
        end
        @test length(calls(() -> design_sizes(space))) - alone <= 8
    end
end


@testitem "report: the bonus counts without listing its targets (plan Stage C step 4)" begin
    using UnitTestDesign: rule_memos, _prepare_rows, _bonus
    # 30 parameters of 5 values, no rules: the bonus has 291,894 missing
    # triples (287,305 on the rows of IPOG's old paths, before Phase 4's
    # lookup core, which the figures below were measured on). Before Stage C
    # it listed them, and allocated about 1.0 GB here (Julia 1.13); counting
    # allocates about 0.22 GB, and a count that listed every target again
    # would allocate about 0.5 GB.
    space = TestSpace(NamedTuple{Tuple(Symbol("x$i") for i in 1:30)}(Tuple(1:5 for _ in 1:30)))
    cases = all_pairs(space; engine = IPOG())
    memos = rule_memos(space.tables)
    prepared = _prepare_rows(space, memos, collect(cases))
    bonus() = _bonus(prepared, space, 2; memos, feasibility_limit = 1_000_000)
    b = bonus()
    @test (b.covered, b.feasible, b.unknown) == (215_606, 507_500, 0)
    @test b.feasible - b.covered == 291_894
    @test @allocated(bonus()) < 400_000_000
end
