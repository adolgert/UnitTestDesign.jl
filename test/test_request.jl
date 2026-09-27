using Test
using TestItemRunner

# The internal request (src/request.jl, plan Phase 3 step 1): validation of
# strength, `stronger` and must-include rows, the target list, target
# classification, final validation, and the round trip to named cases.

@testsnippet RequestSetup begin
    using UnitTestDesign: Request, Design, Excluded, targets, classify_targets, validate_design,
        to_cases, dead, witness, isconstrained, n_must_include, from_indices, case_indices,
        _positions, _space_indices

    "Fable's solver space: 5 valid rows of 12, 11 feasible pairs, 3 direct, 2 implied."
    solver_space() = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])

    "An engine-position row from a named partial assignment."
    positions(request, nt) = _positions(request, case_indices(request.space, nt))

    "The message of the exception `f()` throws, or `nothing`."
    message(f) = try f(); nothing catch e; sprint(showerror, e) end
end


@testitem "request: strength is from 1 to the parameter count (§11.1, §11.2)" setup=[RequestSetup] begin
    space = solver_space()
    @test_throws ArgumentError Request(space; strength = 0)
    @test_throws ArgumentError Request(space; strength = -1)
    @test occursin("§11.1", message(() -> Request(space; strength = 0)))
    @test_throws ArgumentError Request(space; strength = 4)
    @test occursin("larger than the number of parameters, 3", message(() -> Request(space; strength = 4)))
    @test occursin("§11.2", message(() -> Request(space; strength = 4)))
    @test Request(space; strength = 3).strength == 3
    @test Request(space; strength = 1).groups == [[1, 2, 3] => 1]
    @test Request(space).strength == 2
    # One parameter at strength 1, and a single-valued parameter, are fine.
    single = Request(TestSpace((a = [1],)); strength = 1)
    @test single.arity == [1]
    @test Request(TestSpace((a = [1], b = [:x, :y])); strength = 2).arity == [1, 2]
end


@testitem "request: stronger groups by name, index, range, or vector (§11.3, §11.4)" setup=[RequestSetup] begin
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2))
    base = [1, 2, 3, 4] => 2
    @test Request(space; stronger = [(:a, :b, :c) => 3]).groups == [base, [1, 2, 3] => 3]
    @test Request(space; stronger = [[:a, :b, :c] => 3]).groups == [base, [1, 2, 3] => 3]
    @test Request(space; stronger = [(1, 2, 3) => 3]).groups == [base, [1, 2, 3] => 3]
    @test Request(space; stronger = [[1, 2, 3] => 3]).groups == [base, [1, 2, 3] => 3]
    @test Request(space; stronger = [2:4 => 3]).groups == [base, [2, 3, 4] => 3]
    @test Request(space; stronger = [(:d, :c, :b) => 3]).groups == [base, [2, 3, 4] => 3]

    # §11.4: unknown names and indices outside 1:n are errors naming them.
    @test_throws ArgumentError Request(space; stronger = [(:a, :z) => 2])
    @test occursin("`z` is not a parameter", message(() -> Request(space; stronger = [(:a, :z) => 2])))
    @test_throws ArgumentError Request(space; stronger = [(1, 5) => 2])
    @test occursin("names parameter 5", message(() -> Request(space; stronger = [(1, 5) => 2])))
    @test_throws ArgumentError Request(space; stronger = [(0, 1) => 2])
    @test_throws ArgumentError Request(space; stronger = [("a", "b") => 2])
    # Each entry is a pair with an integer strength.
    @test_throws ArgumentError Request(space; stronger = [(:a, :b, :c)])
    @test_throws ArgumentError Request(space; stronger = [(:a, :b, :c) => 3.0])
end


@testitem "request: stronger groups are distinct and sized (§11.5, §11.6)" setup=[RequestSetup] begin
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2))
    @test_throws ArgumentError Request(space; stronger = [(:a, :a, :b) => 3])
    @test occursin("§11.5", message(() -> Request(space; stronger = [(:a, :a, :b) => 3])))
    @test_throws ArgumentError Request(space; stronger = [(1, 2, 1) => 3])
    # Below the base strength, or above the group's size.
    @test occursin("below the base strength 2", message(() -> Request(space; stronger = [(:a, :b) => 1])))
    @test occursin("above its size 2", message(() -> Request(space; stronger = [(:a, :b) => 3])))
    @test occursin("§11.6", message(() -> Request(space; stronger = [(:a, :b) => 3])))
end


@testitem "request: base-strength groups add nothing, overlaps are a union (§11.7, §11.8)" setup=[RequestSetup] begin
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2))
    plain = Request(space)
    @test Request(space; stronger = [(:a, :b, :c) => 2]).groups == plain.groups
    @test length(targets(Request(space; stronger = [(:a, :b) => 2]))) == length(targets(plain)) == 24

    overlap = Request(space; stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3])
    @test overlap.groups == [[1, 2, 3, 4] => 2, [1, 2, 3] => 3, [2, 3, 4] => 3]
    # 24 pairs, then 8 triples per group; the groups share no triple.
    @test length(targets(overlap)) == 24 + 8 + 8
    # A group listed twice, in another order, acts as its highest strength.
    twice = Request(space; stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3, (:c, :b, :a) => 3])
    @test twice.groups == overlap.groups
    @test targets(twice) == targets(overlap)
    highest = Request(space; stronger = [(:a, :b, :c) => 2, (:a, :b, :c) => 3])
    @test highest.groups == [[1, 2, 3, 4] => 2, [1, 2, 3] => 3]
    # A group at full strength: its targets are the whole product of its members.
    @test length(targets(Request(space; stronger = [(:a, :b, :c, :d) => 4]))) == 24 + 16
end


@testitem "request: stronger is copied, never mutated (§11.9)" setup=[RequestSetup] begin
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2))
    group = [1, 2, 3]
    stronger = [group => 3]
    request = Request(space; stronger = stronger)
    @test stronger == [[1, 2, 3] => 3] && group == [1, 2, 3]
    group[1] = 4
    @test request.groups == [[1, 2, 3, 4] => 2, [1, 2, 3] => 3]
end


@testitem "request: must-include rows are validated by name and value (§10.1, §10.2)" setup=[RequestSetup] begin
    space = solver_space()
    # Named and positional rows, complete or (named only) partial.
    request = Request(space; must_include = [(mode = :exact, solver = :lu, tol = 1e-6), (solver = :lu,),
                                             (:fast, :none, 1e-3), [:exact, :qr, 1e-6]])
    @test n_must_include(request) == 4
    @test request.must_include == [2 0 1 2; 2 2 1 3; 2 0 1 2]
    @test n_must_include(Request(space)) == 0

    # Unknown names, values outside a domain, wrong lengths, other types.
    @test occursin("must_include row 1: `speed` is not a parameter",
                   message(() -> Request(space; must_include = [(speed = 1,)])))
    @test occursin("must_include row 2: :cholesky is not a value of `solver`",
                   message(() -> Request(space; must_include = [(solver = :lu,), (solver = :cholesky,)])))
    @test occursin("must_include row 1: :cholesky is not a value of `solver`",
                   message(() -> Request(space; must_include = [(:fast, :cholesky, 1e-3)])))
    # Values match by identity: 1 is not the value 1.0 (§2.1).
    @test_throws ArgumentError Request(TestSpace((a = [1.0, 2.0], b = [1, 2])); must_include = [(a = 1,)])
    @test occursin("must_include row 2 has 2 values; the space has 3 parameters",
                   message(() -> Request(space; must_include = [(:fast, :none, 1e-3), (:fast, :none)])))
    @test occursin("must_include row 1 is a Int64",
                   message(() -> Request(space; must_include = [42])))
    for bad in ([(speed = 1,)], [(solver = :cholesky,)], [(:fast, :none)], [42])
        @test_throws ArgumentError Request(space; must_include = bad)
    end
    # The caller's rows are not mutated (§10.7).
    rows = [(solver = :lu,)]
    Request(space; must_include = rows)
    @test rows == [(solver = :lu,)]
end


@testitem "request: a complete must-include row obeys the rules (§10.3)" setup=[RequestSetup] begin
    space = solver_space()
    msg = message(() -> Request(space; must_include = [(mode = :fast, solver = :lu, tol = 1e-6)]))
    @test occursin("must_include row 1", msg)
    @test occursin("breaks rule 1", msg)
    @test occursin("§10.3", msg)
    msg2 = message(() -> Request(space; must_include = [(:fast, :none, 1e-3), (:exact, :lu, 1e-3)]))
    @test occursin("must_include row 2", msg2) && occursin("rule 2", msg2)
    @test occursin("exact mode needs a tight tolerance", msg2)
    # A partial row that a rule forbids directly is an error the same way.
    @test occursin("breaks rule 1", message(() -> Request(space; must_include = [(mode = :fast, solver = :qr)])))
end


@testitem "request: a partial must-include row needs a proven completion (§10.4)" setup=[RequestSetup, Checker] begin
    space = solver_space()
    # (solver = :lu, tol = 1e-3) has no valid completion, though no rule forbids it directly.
    msg = message(() -> Request(space; must_include = [(solver = :lu, tol = 1e-3)]))
    @test occursin("has no valid completion", msg)
    @test occursin("§10.4", msg)
    @test_throws ArgumentError Request(space; must_include = [(solver = :lu, tol = 1e-3)])

    # An exhausted search is a ResourceLimitError, distinct from infeasible.
    f = limit_exhaustion
    lspace = test_space(f)
    @test_throws ResourceLimitError Request(lspace; must_include = [(x1 = 4,)],
                                            feasibility_limit = f.request.small_limit)
    @test n_must_include(Request(lspace; must_include = [(x1 = 4,)],
                                 feasibility_limit = f.request.default_limit)) == 1
    # Under the default limit (x1 = 1,) is proven infeasible: an ArgumentError.
    @test_throws ArgumentError Request(lspace; must_include = [(x1 = 1,)])
    @test_throws ResourceLimitError Request(lspace; must_include = [(x1 = 1,)], feasibility_limit = 1)
end


@testitem "request: limits are positive, wrappers wait for Phase 6 (§3.3, §0.2)" setup=[RequestSetup] begin
    space = solver_space()
    @test_throws ArgumentError Request(space; feasibility_limit = 0)
    @test_throws ArgumentError Request(space; explanation_limit = -1)
    @test Request(space; feasibility_limit = 5).feasibility_limit == 5
    msg = message(() -> Request(TestSpace((a = [1, Invalid(0)], b = [1, 2]))))
    @test occursin("parameter `a` has an Invalid value", msg) && occursin("§0.2", msg)
    msg = message(() -> Request(TestSpace((a = [Partition(:tiny, Returns(1)), 2], b = [1, 2]))))
    @test occursin("parameter `a` has a Partition value", msg)
end


@testitem "request: targets, their count and order (§1.8, §9.7)" setup=[RequestSetup] begin
    request = Request(solver_space())
    t = targets(request)
    # (mode, solver) 6, (mode, tol) 4, (solver, tol) 6.
    @test length(t) == 16
    # Base group first, subsets in combinations order, first parameter fastest.
    @test t[1:6] == [[1, 1, 0], [2, 1, 0], [1, 2, 0], [2, 2, 0], [1, 3, 0], [2, 3, 0]]
    @test t[7:10] == [[1, 0, 1], [2, 0, 1], [1, 0, 2], [2, 0, 2]]
    @test t[11:16] == [[0, 1, 1], [0, 2, 1], [0, 3, 1], [0, 1, 2], [0, 2, 2], [0, 3, 2]]
    @test targets(request) == t   # fixed, not hash order
    @test length(targets(Request(solver_space(); strength = 1))) == 7
    @test length(targets(Request(solver_space(); strength = 3))) == 12
    # A stronger group adds its own targets once.
    @test length(targets(Request(solver_space(); stronger = [(:mode, :solver, :tol) => 3]))) == 16 + 12
end


@testitem "request: dead and witness on Fable's space (plan Phase 3 step 1)" setup=[RequestSetup] begin
    request = Request(solver_space())
    @test isconstrained(request)
    @test !isconstrained(Request(TestSpace((a = 1:2, b = 1:2))))
    @test dead(request, positions(request, (solver = :lu, tol = 1e-3)))       # implied
    @test dead(request, positions(request, (mode = :fast, solver = :lu)))     # direct
    @test !dead(request, positions(request, (solver = :lu,)))
    @test !dead(request, [0, 0, 0])
    w = witness(request, positions(request, (solver = :lu,)))
    @test from_indices(request.space, _space_indices(request, w)) == (mode = :exact, solver = :lu, tol = 1e-6)
    @test_throws ErrorException witness(request, positions(request, (solver = :lu, tol = 1e-3)))
end


@testitem "request: dead and witness throw on an exhausted search (§3.6, §3.7)" setup=[RequestSetup, Checker] begin
    request = Request(test_space(limit_exhaustion); feasibility_limit = 1)
    row = positions(request, (x1 = 4,))
    @test_throws ResourceLimitError dead(request, row)
    @test_throws ResourceLimitError witness(request, row)
    msg = message(() -> dead(request, row))
    @test occursin("(x1 = 4,)", msg) && occursin("feasibility_limit", msg)
    @test occursin("(x1 = 4,)", message(() -> witness(request, row)))
    roomy = Request(test_space(limit_exhaustion))
    @test !dead(roomy, row)
    @test witness(roomy, row) == fill(4, 8)
end


@testitem "request: classify_targets on Fable's space (§1.2, §1.4)" setup=[RequestSetup] begin
    request = Request(solver_space())
    required, excluded = classify_targets(request)
    @test length(required) == 11
    @test length(excluded) == 5
    named(t) = from_indices(request.space, _space_indices(request, t))
    forbidden = [named(e.target) => e.rules for e in excluded if e.status == :forbidden]
    @test forbidden == [(mode = :fast, solver = :lu) => [1], (mode = :fast, solver = :qr) => [1],
                        (mode = :exact, tol = 1e-3) => [2]]
    @test all(e -> e.minimal == :not_applicable, filter(e -> e.status == :forbidden, excluded))
    implied = [e for e in excluded if e.status == :implied]
    @test [named(e.target) for e in implied] == [(solver = :lu, tol = 1e-3), (solver = :qr, tol = 1e-3)]
    @test all(e -> e.rules == [1, 2] && e.minimal == :verified, implied)
    # Required targets keep the order of `targets`.
    @test required == filter(t -> t in required, targets(request))

    # An unconstrained request requires every target and classifies nothing.
    free = Request(TestSpace((a = 1:2, b = 1:3, c = 1:2)))
    r, e = classify_targets(free)
    @test r == targets(free) && isempty(e)
end


@testitem "request: classify_targets never returns an unknown (§3.6)" setup=[RequestSetup, Checker] begin
    f = limit_exhaustion
    space = test_space(f)
    @test_throws ResourceLimitError classify_targets(Request(space; feasibility_limit = f.request.small_limit))
    required, excluded = classify_targets(Request(space))
    @test length(required) == 28   # the pairs of the one valid row
    @test length(excluded) == 28 * 16 - 28
    @test all(e -> e.status == :implied, excluded)
end


@testitem "request: validate_design names each internal error (§1.21)" setup=[RequestSetup] begin
    request = Request(solver_space(); must_include = [(solver = :lu,)])
    required, _ = classify_targets(request)
    # A design that works: the must-include row completed, then four more.
    good = [2 1 1 2 2; 2 1 1 1 3; 2 1 2 2 2]
    @test validate_design(request, good, required) == 11
    @test validate_design(request, good, required; strategy = :excursion) == 0
    msg(m) = message(() -> validate_design(request, m, required))
    @test startswith(msg(good[1:2, :]), "internal error: design has 2 rows for 3 parameters")
    incomplete = copy(good); incomplete[3, 4] = 0
    @test occursin("internal error: case 4 has value position 0 for parameter tol", msg(incomplete))
    outside = copy(good); outside[2, 2] = 4
    @test occursin("internal error: case 2 has value position 4 for parameter solver", msg(outside))
    broken = copy(good); broken[1, 5] = 1          # (fast, qr, 1e-6) breaks rule 1
    @test occursin("internal error: case 5", msg(broken)) && occursin("breaks a rule", msg(broken))
    changed = copy(good); changed[2, 1] = 3        # the must-include row asked for :lu
    @test occursin("internal error: must_include row 1 was changed at parameter solver", msg(changed))
    @test occursin("internal error: must_include row 1 is missing", msg(zeros(Int, 3, 0)))
    short = good[:, 1:4]                           # (exact, qr) is never covered
    @test occursin("internal error: required target (mode = :exact, solver = :qr) is not covered", msg(short))
    @test_throws ErrorException validate_design(request, short, required)
    # Only required targets are checked: excluded ones may stay uncovered.
    @test validate_design(Request(solver_space()), good, required) == 11
end


@testitem "request: to_cases round trip keeps values and types (§2.1, §2.9)" setup=[RequestSetup] begin
    space = TestSpace((x = Any[1, 1.0], y = [nothing, :a], z = Any[:s, "s", missing]))
    request = Request(space)
    matrix = [1 2 1 2; 1 2 2 1; 1 2 3 3]
    cases = to_cases(request, matrix)
    @test cases[1] === (x = 1, y = nothing, z = :s)
    @test cases[2] === (x = 1.0, y = :a, z = "s")
    @test cases[3].z === missing
    @test reduce(hcat, [positions(request, c) for c in cases]) == matrix
    @test isempty(to_cases(request, zeros(Int, 3, 0)))
end
