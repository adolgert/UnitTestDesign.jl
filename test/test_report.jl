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

    plain(x) = sprint(show, MIME"text/plain"(), x)

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


@testitem "report: agrees with the checker on 50 random problems (§1.3, §1.23, §3.12)" setup=[Checker, ReportSetup] begin
    rng = Xoshiro(0x2026_0927_0052)
    for index in 1:50
        problem = random_problem(rng; strength = 2)
        cs = problem.space
        n = length(cs.names)
        for engine in (IPOG(), GND(seed = index))
            cases = all_pairs(test_space(cs); engine)
            r = report(cases)
            check = check_design(cases, cs)
            ok = iscomplete(r.coverage) && r.coverage.ordinary.covered == check.ordinary.counts.feasible &&
                 r.excluded == cases.excluded && r.strength == 2 && r.n_cases == length(cases)
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
    @test plain(r) == join([r.guarantee; "excluded:"; SOLVER_EXCLUDED;
        "bonus: 5 of 5 feasible triples covered";
        "prefix curve:";
        "  first 1 of 5 cover 27% (3 of 11)";
        "  first 2 of 5 cover 45% (5 of 11)";
        "  first 3 of 5 cover 63% (7 of 11)";
        "  first 4 of 5 cover 90% (10 of 11)";
        "  first 5 of 5 cover 100% (11 of 11)";
        "seed: none (IPOG uses no randomness)"], "\n")
    @test sprint(show, r) == r.guarantee
    @test (r.strategy, r.engine, r.seed, r.n_must_include, r.strength) == (:covering, :IPOG, nothing, 0, 2)
    @test r.excluded == cases.excluded
    @test [x.covered for x in r.prefix] == [3, 5, 7, 10, 11]

    # GND names its seed; must-include rows are counted; stronger groups are named.
    g = report(all_pairs(space; engine = GND(seed = 3)))
    @test endswith(g.guarantee, "; GND seed 3") && g.seed == 3
    @test occursin("seed: 3 (GND(seed = 3) repeats these cases)", plain(g))
    @test occursin("GND with the caller's rng", report(all_pairs(space; engine = GND(rng = Xoshiro(1)))).guarantee)
    kept = report(all_pairs(space; must_include = [(mode = :fast, solver = :none, tol = 1e-3), (solver = :lu,)]))
    @test endswith(kept.guarantee, "; 2 must-include rows kept first") && kept.n_must_include == 2
    grouped = report(covering(space; stronger = [(:mode, :solver, :tol) => 3]))
    @test startswith(grouped.guarantee, "5 cases cover all 16 feasible combinations at strength 2, " *
                                        "3 within (mode, solver, tol) of a 12-combination space")
    @test startswith(report(all_values(space)).guarantee,
                     "3 cases cover all 7 feasible combinations at strength 1 of a 12-combination space")
    # No percentage above 100 or rounded up to it: 2 of 3 is 66%.
    @test occursin("first 2 of 3 cover 66% (2 of 3)", plain(report(excursions((a = [1, 2, 3],)))))
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
    @test occursin("seed: none (an excursion uses no randomness)", plain(ex))
    ff = report(full_factorial(space))
    @test ff.guarantee == "5 cases, every valid row of 12; measured at strength 2, the cases cover all " *
                          "11 feasible pairs (3 pairs forbidden, 2 impossible under the constraints)"
    @test ff.strength == 2 && iscomplete(ff.coverage) && ff.bonus.applicable && ff.bonus.covered == 5
    @test occursin("seed: none (a full factorial uses no randomness)", plain(ff))
    # One parameter: strength 1, the only strength (§1.12, §11.2), and no bonus.
    one = report(excursions((a = [1, 2, 3],)))
    @test one.strength == 1
    @test one.guarantee == "3 cases within distance 1 of (a = 1,); not a covering design; measured at " *
                           "strength 1, the cases cover all 3 feasible combinations"
    @test !one.bonus.applicable
    @test occursin("bonus coverage not applicable: strength 2 exceeds the number of parameters, 1", plain(one))
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
    @test occursin("\nbonus coverage not applicable: strength 4 exceeds the number of parameters, 3\n", plain(full))
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
    @test isempty(r.prefix) && occursin("\nprefix curve: no cases\n", plain(r))
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
    text = plain(r)
    @test !occursin('%', text) && !occursin("complete", text) && !occursin(" all ", r.guarantee)
    @test r.guarantee == "1 case covers 28 of at least 28 feasible pairs of a 65536-combination space; " *
                         "420 pairs unresolved (feasibility_limit = 1); no exact percentage"
    @test !iscomplete(r.coverage) && length(r.coverage.ordinary.unknown) == 420
    @test r.bonus.applicable && r.bonus.unknown > 0 && r.bonus.covered == 56
    @test occursin("\nbonus: 56 of at least 56 feasible triples covered; $(r.bonus.unknown) triples " *
                   "unresolved (feasibility_limit = 1); no exact percentage\n", text)
    @test only(r.prefix) == (cases = 1, covered = 28, feasible = 28, unknown = 420)
    @test occursin("\nprefix curve:\n  first 1 of 1 cover 28 of at least 28\n", text)
    # The recorded exclusions stay as generation proved them (§3.15).
    @test r.excluded == cases.excluded && length(r.excluded) == 420
    @test occursin("\n  and 400 more\n", text)
    # The default limit resolves everything.
    whole = report(cases)
    @test iscomplete(whole.coverage) && whole.guarantee ==
          "1 case covers all 28 feasible pairs of a 65536-combination space (420 pairs impossible under the constraints)"
    @test whole.bonus.unknown == 0 && whole.bonus.covered == whole.bonus.feasible == 56
    @test occursin("first 1 of 1 cover 100% (28 of 28)", plain(whole))
end


@testitem "Report: its fields are plain data (§1.19)" setup=[ReportSetup] begin
    allowed = Union{Int, String, Symbol, Vector, NamedTuple, Nothing, Coverage}
    @test all(T -> T <: allowed, fieldtypes(Report))
    @test !any(T -> T <: Function, fieldtypes(Coverage))
    @test !any(T -> T <: Function, fieldtypes(UnitTestDesign.CoveragePart))
    r = report(all_pairs(solver_space()))
    @test all(x -> x isa allowed, (getfield(r, k) for k in fieldnames(Report)))
    @test r.bonus isa NamedTuple && r.prefix[1] isa NamedTuple
    @test all(T -> T <: Union{Int, String, Symbol, Vector, NamedTuple, Nothing, BigInt}, fieldtypes(DesignSizes))
    @test endswith(sprint(show, [r]), "[5 cases cover all 11 feasible pairs of a 12-combination space " *
                                      "(3 pairs forbidden, 2 impossible under the constraints)]")
    @test occursin("feasibility_limit", message(() -> report(all_pairs(solver_space()); feasibility_limit = 0)))
end


@testitem "design_sizes: Fable's example, and the solver space's valid share (§8.3, plan Phase 5 step 4)" setup=[Checker, ReportSetup] begin
    t = design_sizes(fable_domains()...)
    @test [r.strategy for r in t.rows] ==
          ["full_factorial", "covering(1)", "covering(2)", "covering(3)", "excursions(1)", "excursions(2)"]
    @test [r.cases for r in t.rows] == [81, 3, 10, 31, 9, 33]
    @test (t.total, t.valid, t.engine) == (81, 81, :IPOG)
    @test all(r -> r.status == :ok, t.rows)
    @test [r.pairs.covered for r in t.rows] == [54, 18, 54, 54, 30, 54]
    @test [r.triples.covered for r in t.rows] == [108, 12, 39, 108, 28, 76]
    @test all(r -> (r.pairs.feasible, r.triples.feasible) == (54, 108), t.rows)
    @test plain(t) == join([
        "strategy        cases   share  pairs  triples",
        "full_factorial     81  100.0%  54/54  108/108  valid 81 of 81",
        "covering(1)         3    3.7%  18/54   12/108",
        "covering(2)        10   12.3%  54/54   39/108",
        "covering(3)        31   38.3%  54/54  108/108",
        "excursions(1)       9   11.1%  30/54   28/108",
        "excursions(2)      33   40.7%  54/54   76/108",
        "case counts are the rows each strategy produced with IPOG, not lower bounds"], "\n")
    # The same through a NamedTuple and a TestSpace; the counts come from running the strategies.
    @test [r.cases for r in design_sizes(TestSpace(fable_domains()...)).rows] == [81, 3, 10, 31, 9, 33]
    @test design_sizes(fable_domains()...).rows[3].cases == length(all_pairs(fable_domains()...))

    s = design_sizes(solver_space())
    @test (s.total, s.valid) == (12, 5)
    @test [r.cases for r in s.rows] == [5, 3, 5, 5, 2, 3]
    @test [r.share for r in s.rows] == [1.0, 0.6, 1.0, 1.0, 0.4, 0.6]
    @test [r.pairs.covered for r in s.rows] == [11, 8, 11, 11, 5, 7]
    @test all(r -> r.pairs.feasible == 11 && r.triples.feasible == 5, s.rows)
    @test plain(s) == join([
        "strategy        cases   share  pairs  triples",
        "full_factorial      5  100.0%  11/11      5/5  valid 5 of 12",
        "covering(1)         3   60.0%   8/11      3/5",
        "covering(2)         5  100.0%  11/11      5/5",
        "covering(3)         5  100.0%  11/11      5/5",
        "excursions(1)       2   40.0%   5/11      2/5",
        "excursions(2)       3   60.0%   7/11      3/5",
        "case counts are the rows each strategy produced with IPOG, not lower bounds"], "\n")
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
    @test occursin("\nfull_factorial      —      —      —        —  total 12 only; limit = 10 reached", plain(t))
    # A strategy that stops at feasibility_limit = 1 records its status; the others still report.
    lim = design_sizes(space; feasibility_limit = 1)
    stopped = lim.rows[2]
    @test stopped.strategy == "covering(1)" && stopped.status == :resource_limit && stopped.cases === nothing
    @test startswith(stopped.message, "feasibility_limit = 1 reached")
    @test [r.status for r in lim.rows] == [:ok, :resource_limit, :ok, :ok, :ok, :ok]
    @test [r.cases for r in lim.rows] == [5, nothing, 5, 5, 2, 3]
    @test occursin("\ncovering(1)         —       —      —        —  feasibility_limit = 1 reached", plain(lim))
    # Unresolved measurements print as bounds, never as a share of an unknown.
    f = limit_exhaustion
    u = design_sizes(test_space(f); strengths = [2], distances = [], feasibility_limit = 1)
    @test u.rows[1].status == :ok && u.rows[1].pairs.unknown > 0
    @test u.rows[2].status == :resource_limit
    @test occursin("28/≥28", plain(u)) && !occursin("28/28", plain(u))
    # Strengths above the parameter count are left out, not errors.
    wide = design_sizes([1, 2], [:a, :b]; strengths = 1:4)
    @test [r.strategy for r in wide.rows] == ["full_factorial", "covering(1)", "covering(2)", "excursions(1)", "excursions(2)"]
    @test all(r -> r.triples === nothing, wide.rows) && all(r -> r.pairs !== nothing, wide.rows)
    @test occursin("—", plain(wide))
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
