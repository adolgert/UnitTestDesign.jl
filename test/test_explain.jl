using Test
using TestItemRunner

# The public questions about assignments (src/explain.jl): isallowed,
# explain and classify over a TestSpace. Plan Phase 2 steps 7 and 8; contract
# §1.2, §1.4, §1.25–§1.27, §3, §5.5. The fixture cross-checks use the adapter
# `test_space` (fixture_model.jl) through `setup=[Checker]`.

@testsnippet ExplainSetup begin
    using UnitTestDesign: classify, Classification, Explanation, FeasibilityContext,
        feasibility_for, from_indices, case_indices

    "The Fable solver space of the plan's target screen, with rule labels."
    solver_space() = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])

    "Every pair target of a space's ordinary values, as NamedTuples in parameter order."
    function ordinary_pairs(space)
        names = parameters(space)
        targets = NamedTuple[]
        for i in eachindex(names), j in (i + 1):length(names)
            for vi in UnitTestDesign.ordinary_indices(space, i), vj in UnitTestDesign.ordinary_indices(space, j)
                push!(targets, NamedTuple{(names[i], names[j])}((space.values[i][vi], space.values[j][vj])))
            end
        end
        return targets
    end
end


@testitem "explain: Fable's solver, 3 direct and 2 implied exclusions by name (§1.4, §1.5, §1.26)" setup=[ExplainSetup] begin
    space = solver_space()
    label1 = "@require(mode == :exact || solver == :none)"
    label2 = "exact mode needs a tight tolerance"
    targets = ordinary_pairs(space)
    @test length(targets) == 16
    results = classify(space, targets)
    @test [c.target for c in results] == targets  # input order (§9.7)
    @test count(c -> c.status == :required, results) == 11

    forbidden = [(c.target, c.rules, c.labels) for c in results if c.status == :forbidden]
    @test forbidden == [((mode = :fast, solver = :lu), [1], [label1]),
                        ((mode = :fast, solver = :qr), [1], [label1]),
                        ((mode = :exact, tol = 1e-3), [2], [label2])]
    implied = [(c.target, c.rules, c.labels, c.minimal) for c in results if c.status == :implied]
    @test implied == [((solver = :lu, tol = 1e-3), [1, 2], [label1, label2], :verified),
                      ((solver = :qr, tol = 1e-3), [1, 2], [label1, label2], :verified)]
    for c in results
        if c.status == :required
            @test c.witness isa NamedTuple && isallowed(space, c.witness)
            @test all(c.witness[k] === v for (k, v) in pairs(c.target))
        else
            @test c.witness === nothing
        end
    end

    e = explain(space, (solver = :lu, tol = 1e-3))
    @test e.outcome == :infeasible
    @test (e.rules, e.labels, e.minimal) == ([1, 2], [label1, label2], :verified)
    @test e.assignment == (solver = :lu, tol = 1e-3)
    @test e.witness === nothing && e.limit === nothing
    e = explain(space, (solver = :lu,))
    @test e.outcome == :completable
    @test e.witness == (mode = :exact, solver = :lu, tol = 1e-6)
    e = explain(space, (mode = :exact, tol = 1e-3))
    @test (e.outcome, e.rules, e.labels) == (:forbidden, [2], [label2])
    # A complete row: allowed, or forbidden by every rule it violates.
    @test explain(space, (:exact, :lu, 1e-6)).outcome == :allowed
    @test explain(space, (mode = :fast, solver = :lu, tol = 1e-6)).rules == [1]
end


@testitem "explain: Opus's os/gpu/driver prints the two rules (§1.2, §1.26)" setup=[ExplainSetup] begin
    space = TestSpace((os = [:linux, :mac, :windows], gpu = [false, true], driver = [:cuda, :none]);
        constraints = [
            @forbid(gpu && driver == :none; reason = "a GPU needs CUDA"),
            @forbid(os == :windows && driver == :cuda; reason = "Windows has no CUDA"),
        ])
    e = explain(space, (os = :windows, gpu = true))
    @test e.outcome == :infeasible
    @test e.rules == [1, 2] && e.minimal == :verified
    @test sprint(show, e) ==
          "infeasible: no valid case contains (os = :windows, gpu = true); rules 1 and 2 together " *
          "exclude it (rule 1: a GPU needs CUDA: @forbid(gpu && driver == :none); " *
          "rule 2: Windows has no CUDA: @forbid(os == :windows && driver == :cuda))"
    @test repr(MIME"text/plain"(), e) == sprint(show, e)
    @test sprint(show, explain(space, (os = :windows,))) ==
          "completable, e.g. (os = :windows, gpu = false, driver = :none)"
    @test sprint(show, explain(space, (gpu = true, driver = :none))) ==
          "forbidden by rule 1 (a GPU needs CUDA: @forbid(gpu && driver == :none))"
    @test count(c -> c.status == :implied, classify(space, ordinary_pairs(space))) == 1
end


@testitem "explain: nothing is a real value (§2.9, §12.23)" setup=[ExplainSetup] begin
    # Fixture heterogeneous_values: 1 and 1.0 are two choices; y holds nothing.
    space = TestSpace((x = Any[1, 1.0], y = [nothing, :a], z = Any[:s, "s"]);
        constraints = [
            forbid((x, y) -> x === 1.0 && y === nothing, :x, :y),
            forbid((x, z) -> x == 1 && z == "s", :x, :z),
        ])
    e = explain(space, (y = nothing,))
    @test e.outcome == :completable
    @test e.witness.y === nothing && e.witness.x === 1
    @test explain(space, (x = 1.0, y = nothing)).rules == [1]
    @test explain(space, (x = 1, y = nothing)).outcome == :completable
    @test explain(space, (y = nothing, z = "s")).outcome == :infeasible
    @test explain(space, (y = nothing, z = "s")).rules == [2]
    @test explain(space, (x = 1, y = nothing, z = :s)).outcome == :allowed
    @test isallowed(space, (1, nothing, :s))
    @test !isallowed(space, (1.0, nothing, :s))
    # Values match by identity: missing is not a value of y, and 1.0 is not 1.
    @test_throws ArgumentError explain(space, (y = missing,))
    @test explain(space, (x = 1.0, z = :s)).witness.x === 1.0
end


@testitem "explain: the != rule forbids exactly two pairs (plan step 8, §12.23)" setup=[ExplainSetup] begin
    # 0.4 evaluated `a != b` on partial rows, where `nothing != 1`, and so
    # over-forbade. A rule now sees only complete scopes (§1.6, §12.14).
    space = TestSpace((a = [1, 2], b = [1, 2], c = [1, 2]); constraints = [@forbid(a != b)])
    results = classify(space, ordinary_pairs(space))
    @test length(results) == 12
    @test [c.target for c in results if c.status != :required] == [(a = 1, b = 2), (a = 2, b = 1)]
    @test all(c -> c.status == :forbidden && c.rules == [1], filter(c -> c.status != :required, results))
    @test explain(space, (a = 1, c = 2)).witness == (a = 1, b = 1, c = 2)
end


@testitem "explain: unknown at feasibility_limit = 1, then a retry (§1.7, §3.3, §3.8, §3.15)" setup=[ExplainSetup] begin
    # Fixture limit_exhaustion: only the row of all 4s is valid.
    space = TestSpace((Symbol(:x, i) => 1:4 for i in 1:8)...;
        constraints = [forbid(case -> !all(==(4), values(case)); reason = "only all 4s")])
    e = explain(space, (x1 = 4,); feasibility_limit = 1)
    @test e.outcome == :unknown
    @test e.limit == (:feasibility_limit => 1)
    @test e.witness === nothing && isempty(e.rules)
    @test sprint(show, e) == "unknown: feasibility_limit = 1 reached; retry with a larger limit"
    # The retry with the default limit resolves it; nothing was cached as infeasible.
    e = explain(space, (x1 = 4,))
    @test e.outcome == :completable
    @test e.witness == NamedTuple{Tuple(parameters(space))}(ntuple(_ -> 4, 8))
    @test explain(space, (x1 = 1,)).outcome == :infeasible
    @test explain(space, (x1 = 1,)).rules == [1]

    targets = [(x1 = 4, x2 = 4), (x1 = 1, x2 = 4)]
    @test [c.status for c in classify(space, targets; feasibility_limit = 1)] == [:unknown, :unknown]
    @test all(c -> c.limit == (:feasibility_limit => 1), classify(space, targets; feasibility_limit = 1))
    @test [c.status for c in classify(space, targets)] == [:required, :implied]

    # The explanation budget can run out, but the exclusion stays proven (§3.15).
    solver = solver_space()
    e = explain(solver, (solver = :lu, tol = 1e-3); explanation_limit = 1)
    @test (e.outcome, e.rules, e.minimal) == (:infeasible, [1, 2], :unresolved)
    @test e.limit == (:explanation_limit => 1)
    @test endswith(sprint(show, e), "; whether each rule is needed is unresolved: explanation_limit = 1 reached")

    # Limits are positive Ints.
    @test_throws ArgumentError explain(space, (x1 = 4,); feasibility_limit = 0)
    @test_throws ArgumentError explain(space, (x1 = 4,); explanation_limit = 0)
    @test_throws ArgumentError classify(space, targets; feasibility_limit = 1.5)
end


@testitem "isallowed: ordinary, negative and multiple-invalid rows (§1.25, §5.5–§5.7)" setup=[ExplainSetup] begin
    space = TestSpace((n = [1, 2, Invalid(1)], m = [:a, :b, Invalid(:z)], k = [:x, :y]);
        constraints = [
            @forbid(n == 2 && m == :b),
            @forbid(m == :a && k == :y),
            forbid(case -> case.n == 1 && case.k == :x; reason = "whole case"),
        ])
    # Ordinary rows satisfy every rule (§5.4).
    @test isallowed(space, (n = 2, m = :a, k = :x))
    @test !isallowed(space, (n = 2, m = :b, k = :y))
    @test !isallowed(space, (n = 1, m = :b, k = :x))  # the whole-case rule
    @test isallowed(space, (k = :y, m = :b, n = 1))    # any name order
    @test isallowed(space, (2, :a, :x))                # positional
    # A negative row at n skips rules 1 and 3, which read n (§5.5, §5.6) ...
    @test isallowed(space, (n = Invalid(1), m = :b, k = :x))
    # ... but not rule 2, which omits n.
    @test !isallowed(space, (n = Invalid(1), m = :a, k = :y))
    # A negative row at m skips rules 1 and 2, which read m, and the whole-case rule 3.
    @test isallowed(space, (n = 1, m = Invalid(:z), k = :x))
    # Two invalid values: never valid (§5.7).
    @test !isallowed(space, (n = Invalid(1), m = Invalid(:z), k = :x))

    # Inputs are complete and in the space's vocabulary.
    err = try isallowed(space, (n = 1, m = :a)) catch e; e end
    @test err isa ArgumentError && occursin("complete case", err.msg) && occursin("no value for k", err.msg)
    err = try isallowed(space, (n = 3, m = :a, k = :x)) catch e; e end
    @test err isa ArgumentError && occursin("`n`", err.msg) && occursin("3", err.msg)
    @test_throws ArgumentError isallowed(space, (n = 1, m = :a, k = :x, j = 1))
    @test_throws ArgumentError isallowed(space, (1, :a))

    # explain applies the same policy (§1.27).
    e = explain(space, (n = Invalid(1), m = :b))
    @test e.outcome == :completable && e.witness.n === Invalid(1) && e.witness.m === :b
    @test explain(space, (n = Invalid(1), m = :a, k = :y)).rules == [2]
    e = explain(space, (n = Invalid(1), m = Invalid(:z)))
    @test e.outcome == :forbidden && isempty(e.rules) && isempty(e.labels)
    @test sprint(show, e) == "forbidden: (n = Invalid(1), m = Invalid(:z)) has more than one " *
                             "Invalid value, and a case holds at most one"
    @test explain(space, (n = Invalid(1), m = :b, k = :x)).outcome == :allowed
    # classify rejects a target with two invalid values.
    @test_throws ArgumentError classify(space, [(n = Invalid(1), m = Invalid(:z))])
    c = only(classify(space, [(n = Invalid(1), k = :y)]))
    @test c.status == :required && c.witness == (n = Invalid(1), m = :b, k = :y)
end


@testitem "explain: the sentences (§1.26)" setup=[ExplainSetup] begin
    space = solver_space()
    sentence(a; kw...) = sprint(show, explain(space, a; kw...))
    @test sentence((mode = :exact, solver = :lu, tol = 1e-6)) ==
          "allowed: (mode = :exact, solver = :lu, tol = 1.0e-6) is a valid case"
    @test sentence((mode = :exact, tol = 1e-3)) == "forbidden by rule 2 (exact mode needs a tight tolerance)"
    @test sentence((mode = :fast, solver = :lu, tol = 1e-3)) ==
          "forbidden by rule 1 (@require(mode == :exact || solver == :none))"
    @test sentence((solver = :lu,)) == "completable, e.g. (mode = :exact, solver = :lu, tol = 1.0e-6)"
    @test sentence((solver = :lu, tol = 1e-3)) ==
          "infeasible: no valid case contains (solver = :lu, tol = 0.001); rules 1 and 2 together " *
          "exclude it (rule 1: @require(mode == :exact || solver == :none); " *
          "rule 2: exact mode needs a tight tolerance)"

    # Two direct rules, and rules with no label, which are named by scope (§12.3).
    bare = TestSpace((a = [1, 2], b = [1, 2], c = [1, 2]);
        constraints = [forbid((a, b) -> a == 1 && b == 1, :a, :b),
                       forbid((a, b) -> a == b, :a, :b),
                       forbid((b, c) -> b == 1 && c == 1, :b, :c),
                       forbid((a, c) -> a == 2, :a, :c)])
    @test sprint(show, explain(bare, (a = 1, b = 1))) ==
          "forbidden by rules 1 and 2 (rule 1 on (a, b); rule 2 on (a, b))"
    # (b = 1,): a = 1 is forbidden with it by rules 1 and 2, and a = 2 by rule 4.
    e = explain(bare, (b = 1,))
    @test (e.outcome, e.rules, e.labels) == (:infeasible, [2, 4], ["rule 2 on (a, b)", "rule 4 on (a, c)"])
    @test sprint(show, e) == "infeasible: no valid case contains (b = 1,); rules 2 and 4 together " *
                             "exclude it (rule 2 on (a, b); rule 4 on (a, c))"
    # One rule wider than the target is the whole explanation (§1.4).
    wide = TestSpace((a = [1, 2], b = [1, 2], c = [1, 2]);
        constraints = [forbid((a, b, c) -> a == 1 && b == 1, :a, :b, :c; reason = "no a = b = 1")])
    @test sprint(show, explain(wide, (a = 1, b = 1))) ==
          "infeasible: no valid case contains (a = 1, b = 1); rule 1 (no a = b = 1) excludes it"
    # An empty space: the empty assignment is infeasible.
    empty = TestSpace((x = [1, 2], y = [1, 2]);
        constraints = [forbid((x, y) -> x == y, :x, :y; reason = "differ"),
                       forbid((x, y) -> x != y, :x, :y; reason = "match")])
    @test sprint(show, explain(empty, NamedTuple())) ==
          "infeasible: the space has no valid case; rules 1 and 2 together exclude it " *
          "(rule 1: differ; rule 2: match)"
end


@testitem "explain: feasibility_for picks candidates and rules per row kind (§3.5, §5.5)" setup=[ExplainSetup] begin
    space = TestSpace((n = [1, 2, Invalid(0), Invalid(-1)], m = [:a, :b]);
        constraints = [@forbid(n == 2 && m == :b), @forbid(m == :a)])
    context = FeasibilityContext(space)
    f, rules = feasibility_for(context, [0, 1])
    @test f.candidates == [[1, 2], [1, 2]] && rules == [1, 2]
    g, rules = feasibility_for(context, [3, 0])
    @test g.candidates == [[3], [1, 2]] && rules == [2]
    h, _ = feasibility_for(context, [4, 2])
    @test h.candidates == [[4], [1, 2]]
    # One search per row kind within a call; a fresh one otherwise.
    @test feasibility_for(context, [2, 0])[1] === f
    @test feasibility_for(context, [3, 2])[1] === g
    @test h !== g
    @test first(feasibility_for(space, [0, 1])) !== f
    @test_throws ArgumentError feasibility_for(context, [3, 0, 0])
    @test_throws ArgumentError FeasibilityContext(space; feasibility_limit = 0)
    # Rule numbers from a negative row map back to the space's positions.
    @test explain(space, (n = Invalid(0), m = :a)).rules == [2]
end


@testitem "classify: agrees with the checker on every fixture (§1.2, §1.4, §5.5, §6.2)" setup=[Checker] begin
    using UnitTestDesign: classify
    seen(x) = x isa CheckPartition ? x.name : x
    function checker_status(part, t)
        any(x -> same_target(x, t), part.feasible) && return (:required, Int[])
        k = findfirst(p -> same_target(first(p), t), part.forbidden)
        k === nothing || return (:forbidden, last(part.forbidden[k]))
        any(x -> same_target(x, t), part.implied) && return (:implied, Int[])
        return (:missing, Int[])
    end
    compared = Symbol[]
    for f in FIXTURES
        f.space === nothing && continue
        cs, space = f.space, test_space(f)
        r = check_design([], cs)
        names = cs.names
        targets, expected = NamedTuple[], NamedTuple[]
        negative = Bool[]
        for i in eachindex(names), j in (i + 1):length(names)
            for ki in eachindex(cs.domains[i]), kj in eachindex(cs.domains[j])
                a, b = cs.domains[i][ki], cs.domains[j][kj]
                a isa CheckInvalid && b isa CheckInvalid && continue
                idx = zeros(Int, length(names)); idx[i] = ki; idx[j] = kj
                push!(targets, UnitTestDesign.from_indices(space, idx))
                push!(expected, NamedTuple{(names[i], names[j])}((seen(a), seen(b))))
                push!(negative, a isa CheckInvalid || b isa CheckInvalid)
            end
        end
        results = classify(space, targets)
        rechecked = 0
        for (c, t, neg) in zip(results, expected, negative)
            status, rules = checker_status(neg ? r.negative : r.ordinary, t)
            @test c.status == status
            status == :forbidden && @test c.rules == rules
            if status == :required
                @test isallowed(space, c.witness)
            elseif status == :implied
                @test c.minimal == :verified && !isempty(c.rules)
                # For a few targets per fixture (each checker call enumerates the
                # product), the rule set is sufficient by the checker too, and
                # each rule is needed.
                (rechecked += 1) > 3 && continue
                sub(rs) = CheckSpace(cs.names, cs.domains, cs.rules[rs])
                @test classify_target(sub(c.rules), t).status != :required
                for k in c.rules
                    @test classify_target(sub(filter(!=(k), c.rules)), t).status == :required
                end
            end
        end
        push!(compared, f.name)
    end
    @test length(compared) == length(FIXTURES) - 5

    # isallowed agrees with the checker's valid rows on every small fixture.
    for f in FIXTURES
        (f.space === nothing || prod(length, f.space.domains) > 4096) && continue
        space = test_space(f)
        valid = [valid_rows(f.space); negative_rows(f.space)]
        for key in Iterators.product((eachindex(d) for d in f.space.domains)...)
            row = UnitTestDesign.from_indices(space, collect(key))
            checker = NamedTuple{Tuple(f.space.names)}(Tuple(f.space.domains[p][key[p]] for p in eachindex(key)))
            @test isallowed(space, row) == any(v -> same_target(v, checker), valid)
        end
    end
end


@testitem "classify: agrees with the checker on 100 random problems (§1.2, §1.4)" setup=[Checker, UTSetup] begin
    using UnitTestDesign: classify
    using Random
    rng = Xoshiro(0x2026_0926_e8a1 ⊻ seed_mod())
    tally = Dict(:required => 0, :forbidden => 0, :implied => 0)
    for _ in 1:100
        problem = random_problem(rng)
        cs, space = problem.space, test_space(problem.space)
        r = check_design([], cs).ordinary
        targets = NamedTuple[]
        for i in eachindex(cs.names), j in (i + 1):length(cs.names), a in cs.domains[i], b in cs.domains[j]
            push!(targets, NamedTuple{(cs.names[i], cs.names[j])}((a, b)))
        end
        results = classify(space, targets)
        feasible = Set(r.feasible)  # integer values only, so hashing is identity here
        forbidden = Dict(r.forbidden)
        implied = Set(r.implied)
        for (t, c) in zip(targets, results)
            tally[c.status] += 1
            if t in feasible
                @test c.status == :required
            elseif haskey(forbidden, t)
                @test c.status == :forbidden
                @test c.rules == forbidden[t]
            else
                @test t in implied
                @test c.status == :implied
                @test !isempty(c.rules) && c.minimal == :verified
            end
        end
        @test count(c -> c.status == :implied, results) == problem.implied
    end
    @test all(>(0), values(tally))
end


@testitem "classify: input order, normalized targets and bad targets (§9.7, §2.11)" setup=[ExplainSetup] begin
    tiny = Partition(:tiny, Returns(1e-9))
    space = TestSpace((size = [tiny, 100], mode = [:a, :b]);
        constraints = [forbid((size = :tiny, mode = :b); reason = "tiny b")])
    results = classify(space, [(mode = :b, size = :tiny), (size = 100,), (mode = :a,)])
    @test [c.status for c in results] == [:forbidden, :required, :required]
    # Targets come back in parameter order with the stored values (a partition's wrapper).
    @test keys(results[1].target) == (:size, :mode)
    @test results[1].target.size === tiny
    @test results[1].labels == ["tiny b"]
    @test isempty(classify(space, NamedTuple[]))
    @test classify(space, NamedTuple[]) isa Vector{Classification}
    @test_throws ArgumentError classify(space, [(1, :a)])
    @test_throws ArgumentError classify(space, [(size = 3,)])
    @test_throws ArgumentError classify(space, [(colour = :red,)])
end


@testitem "explain: results report nodes and rule checks, which no limit bounds (§3.3)" setup=[ExplainSetup] begin
    # The probe of the Phase 2 review: a fresh unary rule over 2,000 values,
    # evaluated lazily. The initial prune checks every value before the first
    # node, so feasibility_limit = 1 suffices and the answer is exact.
    calls = Ref(0)
    last_only() = forbid(:x; reason = "only the last value") do x
        calls[] += 1
        x < 2000
    end
    space = @test_logs (:warn,) TestSpace((x = 1:2000,); constraints = [last_only()],
                                          tabulation_limit = 1000)
    e = explain(space, NamedTuple(); feasibility_limit = 1)
    @test e.outcome == :completable && e.witness == (x = 2000,)
    @test (e.nodes, e.evaluations, calls[]) == (1, 2000, 2000)
    # The same question again: the same checks. The memo was the first call's,
    # so the predicate runs again (§3.5, §12.19).
    e = explain(space, NamedTuple(); feasibility_limit = 1)
    @test (e.nodes, e.evaluations, calls[]) == (1, 2000, 4000)
    # A direct check is one rule check and no node.
    e = explain(space, (x = 3,))
    @test (e.outcome, e.nodes, e.evaluations) == (:forbidden, 0, 1)

    # Classification reports each target's own cost.
    solver = solver_space()
    results = classify(solver, [(solver = :lu, tol = 1e-3), (mode = :fast, solver = :lu), (solver = :lu,)])
    @test [c.status for c in results] == [:implied, :forbidden, :required]
    @test all(c -> c.evaluations > 0, results)
    @test results[1].nodes > 0          # the deletion trials search
    @test results[2].nodes == 0         # a direct exclusion needs no search
    @test explain(solver, (solver = :lu, tol = 1e-3)).nodes == results[1].nodes
    # An assignment with two Invalid values is decided without a check.
    neg = TestSpace((a = [1, Invalid(0)], b = [1, Invalid(0)]))
    e = explain(neg, (a = Invalid(0), b = Invalid(0)))
    @test (e.outcome, e.nodes, e.evaluations) == (:forbidden, 0, 0)
end


@testitem "explain: a lazy rule's memo lasts one call, and the space keeps nothing (§12.19, §3.5)" setup=[ExplainSetup] begin
    using UnitTestDesign: memo_size, explain_partial
    # A whole-case rule is lazy. Its verdicts are memoized in the call's
    # context, shared by that call's searches and row kinds, and dropped with it.
    calls = Ref(0)
    space = TestSpace((a = 1:3, b = 1:3, c = 1:2);
        constraints = [forbid(case -> (calls[] += 1; case.a + case.b + case.c > 6); reason = "small sums")])
    before = Base.summarysize(space)
    explain(space, (a = 3,))
    first_call = calls[]
    @test first_call > 0
    @test Base.summarysize(space) == before
    # The same question again evaluates the rule again: no memo survived.
    explain(space, (a = 3,))
    @test calls[] == 2 * first_call
    classify(space, ordinary_pairs(space))
    @test Base.summarysize(space) == before

    # Within one call, each verdict is evaluated once: a context's memo is
    # bounded by the product of the ordinary domains, 18 rows, and a second
    # question in the same context reuses it.
    context = FeasibilityContext(space)
    @test memo_size(context) == 0
    calls[] = 0
    for t in ordinary_pairs(space)
        idx = case_indices(space, t)
        f, _ = feasibility_for(context, idx)
        explain_partial(f, idx)
    end
    @test 0 < memo_size(context) <= 18
    @test calls[] == memo_size(context)
    # A fresh context starts empty.
    @test memo_size(FeasibilityContext(space)) == 0

    # A fully tabulated space memoizes nothing, however it is queried.
    tabulated = solver_space()
    context = FeasibilityContext(tabulated)
    for t in ordinary_pairs(tabulated)
        idx = case_indices(tabulated, t)
        explain_partial(first(feasibility_for(context, idx)), idx)
    end
    @test memo_size(context) == 0
    # A scoped rule above tabulation_limit is lazy too, and counted.
    lazy = @test_logs (:warn,) TestSpace((a = 1:3, b = 1:3); constraints = [@forbid(a == b)],
                                         tabulation_limit = 4)
    context = FeasibilityContext(lazy)
    idx = case_indices(lazy, (a = 1,))
    explain_partial(first(feasibility_for(context, idx)), idx)
    @test 0 < memo_size(context) <= 9
end
