using Test
using TestItemRunner

# Tests of the independent oracle in checker.jl against hand-enumerated
# fixtures. Any test item can use the oracle, the random problem generator,
# the fixture inventory, and the adapter from a fixture or checker space to a
# production TestSpace (`test_space`, `model_rows`, `checker_row`) with
# `setup=[Checker]`.

@testmodule Checker begin
    include("checker.jl")          # the oracle; no code shared with src/
    include("random_problems.jl")  # random constrained problems (test_random_problems.jl)
    include("fixtures.jl")         # the fixture inventory (test_fixtures.jl)
    include("fixture_model.jl")    # the adapter to a production TestSpace: test_space(fixture)
end


@testitem "checker: Astra's chained equalities" setup=[Checker] begin
    # A == B and B == C, written as rules that forbid A != B and B != C.
    space = CheckSpace((A = [1, 2], B = [1, 2], C = [1, 2]),
        [((:A, :B), (a, b) -> a != b),
         ((:B, :C), (b, c) -> b != c)])
    @test valid_rows(space) == [(A = 1, B = 1, C = 1), (A = 2, B = 2, C = 2)]
    @test isempty(negative_rows(space))

    @test classify_target(space, (A = 1, C = 2)) == (status = :implied, rule = nothing, rules = Int[])
    @test classify_target(space, (A = 1, B = 2)) == (status = :forbidden, rule = 1, rules = [1])
    @test classify_target(space, (B = 2, C = 1)) == (status = :forbidden, rule = 2, rules = [2])
    @test classify_target(space, (A = 2, C = 2)).status == :required

    # AB and BC: two feasible, two direct each. AC: two feasible, two implied.
    r = check_design(valid_rows(space), space)
    @test complete(r)
    @test Set(r.ordinary.feasible) == Set([
        (A = 1, B = 1), (A = 2, B = 2), (A = 1, C = 1),
        (A = 2, C = 2), (B = 1, C = 1), (B = 2, C = 2)])
    @test Set(r.ordinary.forbidden) == Set([
        (A = 1, B = 2) => [1], (A = 2, B = 1) => [1],
        (B = 1, C = 2) => [2], (B = 2, C = 1) => [2]])
    @test Set(r.ordinary.implied) == Set([(A = 1, C = 2), (A = 2, C = 1)])
    @test r.ordinary.counts == (rows = 2, duplicates = 0, rejected = 0,
        feasible = 6, covered = 6, missing = 0, forbidden = 4, implied = 2)
end


@testitem "checker: Fable's solver example" setup=[Checker] begin
    space = CheckSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]),
        [((:mode, :solver), (m, s) -> m == :fast && s != :none),
         ((:mode, :tol), (m, t) -> m == :exact && t == 1e-3)])

    # By hand: fast mode takes only :none, with either tolerance; exact mode
    # takes only 1e-6, with any solver. 2 + 3 = 5 of the 12 rows.
    @test valid_rows(space) == [
        (mode = :fast, solver = :none, tol = 1e-3),
        (mode = :fast, solver = :none, tol = 1e-6),
        (mode = :exact, solver = :none, tol = 1e-6),
        (mode = :exact, solver = :lu, tol = 1e-6),
        (mode = :exact, solver = :qr, tol = 1e-6)]

    # 16 candidate pairs: 6 mode-solver, 4 mode-tol, 6 solver-tol.
    feasible = [
        (mode = :fast, solver = :none), (mode = :exact, solver = :none),
        (mode = :exact, solver = :lu), (mode = :exact, solver = :qr),
        (mode = :fast, tol = 1e-3), (mode = :fast, tol = 1e-6),
        (mode = :exact, tol = 1e-6),
        (solver = :none, tol = 1e-3), (solver = :none, tol = 1e-6),
        (solver = :lu, tol = 1e-6), (solver = :qr, tol = 1e-6)]
    @test length(feasible) == 11
    @test Set(feasible_targets(space)) == Set(feasible)
    @test Set(feasible_targets(space, (:mode, :solver, :tol), 2)) == Set(feasible)

    # 3 direct: two by the fast-mode rule, one by the tolerance rule.
    # 2 implied: :lu and :qr need exact mode, which needs 1e-6.
    r = check_design(Any[], space)
    @test Set(r.ordinary.forbidden) == Set([
        (mode = :fast, solver = :lu) => [1],
        (mode = :fast, solver = :qr) => [1],
        (mode = :exact, tol = 1e-3) => [2]])
    @test Set(r.ordinary.implied) == Set([(solver = :lu, tol = 1e-3), (solver = :qr, tol = 1e-3)])
    @test r.ordinary.counts.feasible == 11
    @test r.ordinary.counts.forbidden == 3
    @test r.ordinary.counts.implied == 2

    for t in feasible
        @test classify_target(space, t).status == :required
    end
    @test classify_target(space, (mode = :fast, solver = :lu)).rule == 1
    @test classify_target(space, (mode = :fast, solver = :qr)).rule == 1
    @test classify_target(space, (mode = :exact, tol = 1e-3)).rule == 2
    @test classify_target(space, (solver = :lu, tol = 1e-3)).status == :implied
    @test classify_target(space, (solver = :qr, tol = 1e-3)).status == :implied
end


@testitem "checker: Opus's os/gpu/driver example" setup=[Checker] begin
    space = CheckSpace(
        (os = [:linux, :mac, :windows], gpu = [false, true], driver = [:cuda, :none]),
        [((:gpu, :driver), (g, d) -> g && d == :none),
         ((:os, :driver), (o, d) -> o == :windows && d == :cuda)])
    # A GPU needs CUDA, which Windows lacks; Windows runs only without a GPU.
    @test Set(valid_rows(space)) == Set([
        (os = :linux, gpu = false, driver = :cuda),
        (os = :linux, gpu = false, driver = :none),
        (os = :linux, gpu = true, driver = :cuda),
        (os = :mac, gpu = false, driver = :cuda),
        (os = :mac, gpu = false, driver = :none),
        (os = :mac, gpu = true, driver = :cuda),
        (os = :windows, gpu = false, driver = :none)])
    @test classify_target(space, (os = :windows, gpu = true)).status == :implied

    r = check_design(valid_rows(space), space)
    @test complete(r)
    @test Set(r.ordinary.forbidden) == Set([
        (gpu = true, driver = :none) => [1], (os = :windows, driver = :cuda) => [2]])
    @test r.ordinary.implied == [(os = :windows, gpu = true)]
    @test r.ordinary.counts.feasible == 13  # 5 os-gpu, 5 os-driver, 3 gpu-driver
end


@testitem "checker: value identity" setup=[Checker] begin
    @test same_value(1, 1)
    @test !same_value(1, 1.0)
    @test !same_value(1, true)
    @test same_value(nothing, nothing)
    @test !same_value(nothing, missing)
    @test same_value(NaN, NaN)
    @test !same_value(0.0, -0.0)
    @test same_value([1, 2], [1, 2])
    @test same_value(CheckInvalid(1), CheckInvalid(1))
    @test !same_value(CheckInvalid(1), CheckInvalid(1.0))
    @test !same_value(CheckInvalid(1), 1)
    @test same_value(CheckPartition(:a), CheckPartition(:a))
    @test !same_value(CheckPartition(:a), :a)

    # Any[1, 1.0] is two choices, kept apart through rows and targets.
    space = CheckSpace((x = Any[1, 1.0], y = [:a, :b]))
    rows = valid_rows(space)
    @test length(rows) == 4
    @test count(r -> r.x isa Int, rows) == 2
    @test count(r -> r.x isa Float64, rows) == 2
    singles = feasible_targets(space, (:x,), 1)
    @test length(singles) == 2
    @test same_target(singles[1], (x = 1,))
    @test same_target(singles[2], (x = 1.0,))
    r = check_design([(x = 1, y = :a), (x = 1, y = :b)], space; strength = 1)
    @test length(r.ordinary.missing) == 1
    @test same_target(only(r.ordinary.missing), (x = 1.0,))
    @test !same_target(only(r.ordinary.missing), (x = 1,))
    r2 = check_design([(x = 1, y = :a), (x = 1, y = :b)], space)
    @test r2.ordinary.counts.feasible == 4
    @test r2.ordinary.counts.covered == 2
    @test all(t -> t.x isa Float64, r2.ordinary.missing)

    # nothing is a value that rules see and coverage counts.
    space_n = CheckSpace((x = [nothing, 1], y = [:a, :b]),
        [((:x, :y), (x, y) -> x === nothing && y == :b)])
    @test Set(valid_rows(space_n)) == Set([
        (x = nothing, y = :a), (x = 1, y = :a), (x = 1, y = :b)])
    @test classify_target(space_n, (x = nothing, y = :b)) == (status = :forbidden, rule = 1, rules = [1])
    @test classify_target(space_n, (x = nothing, y = :a)).status == :required
    @test feasible_targets(space_n, (:x,), 1) == [(x = nothing,), (x = 1,)]
    rn = check_design([(x = nothing, y = :a), (x = 1, y = :b)], space_n)
    @test rn.ordinary.missing == [(x = 1, y = :a)]
    @test rn.ordinary.counts == (rows = 2, duplicates = 0, rejected = 0,
        feasible = 3, covered = 2, missing = 1, forbidden = 1, implied = 0)

    # A value not in the domain is rejected, with no promotion and no sentinel.
    space_i = CheckSpace((x = [1, 2], y = [:a, :b]))
    ri = check_design([(x = 1.0, y = :a), (x = 1, y = :a), (x = nothing, y = :b),
                       (x = Int32(2), y = :b)], space_i)
    @test [(j.index, j.reason, j.parameter) for j in ri.ordinary.rejected] == [
        (1, :unknown_value, :x), (3, :unknown_value, :x), (4, :unknown_value, :x)]
    @test ri.ordinary.rows == [(x = 1, y = :a)]
    @test ri.ordinary.counts.covered == 1
    @test !complete(ri)
end


@testitem "checker: construction and request validation" setup=[Checker] begin
    @test_throws ArgumentError CheckSpace((x = [1, 1],))
    @test_throws ArgumentError CheckSpace((x = Int[],))
    @test_throws ArgumentError CheckSpace([:x, :x], [[1], [2]])
    @test_throws ArgumentError CheckSpace([:x, :y], [[1]])
    @test_throws ArgumentError CheckSpace((x = [CheckPartition(:tiny), :tiny],))
    @test_throws ArgumentError CheckSpace((x = [CheckPartition(:tiny), CheckPartition(:tiny)],))
    @test_throws ArgumentError CheckSpace((x = [CheckInvalid(0), CheckInvalid(-1)],))
    @test_throws ArgumentError CheckSpace((x = [1, CheckInvalid(CheckPartition(:p))],))
    @test_throws ArgumentError CheckSpace((x = [1, CheckInvalid(CheckInvalid(0))],))
    @test_throws ArgumentError CheckSpace((x = [1, 2],), [((:y,), y -> true)])
    @test_throws ArgumentError CheckSpace((x = [1, 2], y = [1, 2]), [((:x, :x), (a, b) -> true)])
    @test_throws ArgumentError CheckSpace((x = [1, 2],), [((), () -> true)])
    @test_throws ArgumentError CheckSpace((x = [1, 2],), [x -> true])

    # Allowed: singleton domains, wrappers beside the values they wrap,
    # partitions beside unrelated Symbols, and both ways of writing a rule.
    @test CheckSpace((x = [1],)) isa CheckSpace
    @test CheckSpace((x = Any[1, 1.0, CheckInvalid(1), CheckInvalid(1.0)],)) isa CheckSpace
    @test CheckSpace((x = [CheckPartition(:tiny), :small],)) isa CheckSpace
    s2 = CheckSpace((x = [1, 2], y = [1, 2]), [(:x, :y) => ((a, b) -> a == b), :x => (a -> a == 2)])
    @test valid_rows(s2) == [(x = 1, y = 2)]

    # A rule must return a Bool.
    @test_throws ArgumentError valid_rows(CheckSpace((x = [1, 2],), [((:x,), x -> x)]))
    @test_throws ArgumentError valid_rows(CheckSpace((x = [1, 2],), [((:x,), x -> nothing)]))

    # Strength and stronger groups.
    s = CheckSpace((a = [1, 2], b = [1, 2], c = [1, 2]))
    @test_throws ArgumentError check_design([], s; strength = 0)
    @test_throws ArgumentError check_design([], s; strength = 4)
    @test_throws ArgumentError check_design([], s; stronger = [(:a, :b) => 3])
    @test_throws ArgumentError check_design([], s; strength = 2, stronger = [(:a, :b, :c) => 1])
    @test_throws ArgumentError check_design([], s; stronger = [(:a, :z) => 2])
    @test_throws ArgumentError check_design([], s; stronger = [(:a, :a) => 2])
    @test_throws ArgumentError check_design([], s; stronger = [(:a, :b, :c)])
    @test_throws ArgumentError check_design((a = 1, b = 1, c = 1), s)
    @test check_design([], s; strength = 3) isa CheckResult

    # The full product is refused above the documented limit, before enumerating.
    huge_space = CheckSpace([Symbol(:p, i) for i in 1:11], [1:4 for _ in 1:11])  # 4^11 > 10^6
    @test_throws ArgumentError valid_rows(huge_space)
    @test_throws ArgumentError check_design([], huge_space)
end


@testitem "checker: negative rows and targets" setup=[Checker] begin
    bad = CheckInvalid(-1)
    space = CheckSpace((n = [1, 2, bad], m = [:a, :b], k = [:x, :y]),
        [((:n, :m), (n, m) -> n == 2 && m == :b),
         ((:m, :k), (m, k) -> m == :a && k == :y),
         ((:n, :k), (n, k) -> k == :y && n != 2)])

    # Ordinary rows, by hand: k = :y needs n = 2 (rule 3), n = 2 needs m = :a
    # (rule 1), and m = :a forbids k = :y (rule 2). So k = :x always.
    @test valid_rows(space) == [
        (n = 1, m = :a, k = :x), (n = 1, m = :b, k = :x), (n = 2, m = :a, k = :x)]

    # Negative rows: n = bad. Rules 1 and 3 mention n and are skipped (rule 3
    # would forbid k = :y, since bad != 2). Rule 2 still applies.
    @test negative_rows(space) == [
        (n = bad, m = :a, k = :x), (n = bad, m = :b, k = :x), (n = bad, m = :b, k = :y)]

    # Strength 2: the invalid value with every ordinary value of each other parameter.
    neg2 = [(n = bad, m = :a), (n = bad, m = :b), (n = bad, k = :x), (n = bad, k = :y)]
    @test negative_targets(space) == neg2
    @test negative_targets(space, (:n, :m, :k), 2) == neg2
    # Strength 1: the invalid value by itself.
    @test negative_targets(space; strength = 1) == [(n = bad,)]
    # Strength 3: (m = :a, k = :y) is forbidden by rule 2, which omits n.
    r3 = check_design([], space; strength = 3)
    @test r3.negative.feasible == [
        (n = bad, m = :a, k = :x), (n = bad, m = :b, k = :x), (n = bad, m = :b, k = :y)]
    @test r3.negative.forbidden == [(n = bad, m = :a, k = :y) => [2]]
    @test isempty(r3.negative.implied)
    @test classify_target(space, (n = bad, m = :a, k = :y)) == (status = :forbidden, rule = 2, rules = [2])
    @test classify_target(space, (n = bad, k = :y)).status == :required
    @test_throws ArgumentError classify_target(space, (n = -1, k = :y))

    # Ordinary pairs, by hand: n-m 3 feasible, (2, :b) rule 1; n-k 2 feasible,
    # (1, :y) rule 3, (2, :y) implied; m-k 2 feasible, (:a, :y) rule 2,
    # (:b, :y) implied.
    r = check_design([], space)
    @test r.ordinary.counts.feasible == 7
    @test Set(r.ordinary.forbidden) == Set([
        (n = 2, m = :b) => [1], (m = :a, k = :y) => [2], (n = 1, k = :y) => [3]])
    @test Set(r.ordinary.implied) == Set([(n = 2, k = :y), (m = :b, k = :y)])
    @test r.negative.counts.feasible == 4
    @test r.negative.counts.missing == 4
    @test isempty(r.negative.forbidden) && isempty(r.negative.implied)
    r1 = check_design([], space; strength = 1)
    @test r1.ordinary.implied == [(k = :y,)]

    ordinary = valid_rows(space)
    # Ordinary rows cover nothing negative.
    ro = check_design(ordinary, space)
    @test complete(ro.ordinary)
    @test ro.negative.counts.covered == 0
    @test !complete(ro)
    # Negative rows cover nothing ordinary.
    rn = check_design(negative_rows(space), space)
    @test rn.ordinary.counts.covered == 0
    @test complete(rn.negative)
    # Both together are complete with two of the three negative rows.
    both = check_design([ordinary; (n = bad, m = :a, k = :x); (n = bad, m = :b, k = :y)], space)
    @test complete(both)
    # One negative row leaves the other two negative targets missing.
    one_neg = check_design([ordinary; (n = bad, m = :a, k = :x)], space)
    @test one_neg.negative.missing == [(n = bad, m = :b), (n = bad, k = :y)]
    @test complete(one_neg.ordinary) && !complete(one_neg)

    # A negative row that breaks a rule omitting n is rejected and covers nothing.
    broken = check_design([ordinary; (n = bad, m = :a, k = :y); (n = bad, m = :b, k = :x)], space)
    @test length(broken.negative.rejected) == 1
    j = only(broken.negative.rejected)
    @test (j.index, j.reason, j.rules) == (4, :violates_rule, [2])
    @test broken.negative.missing == [(n = bad, m = :a), (n = bad, k = :y)]
    @test isempty(broken.ordinary.rejected)

    # The raw -1 is not the invalid value.
    raw = check_design([(n = -1, m = :a, k = :x)], space)
    @test only(raw.ordinary.rejected).reason == :unknown_value
end


@testitem "checker: implied negative targets and groups" setup=[Checker] begin
    bad = CheckInvalid(:bad)
    space = CheckSpace((p = [0, bad], a = [1, 2], b = [1, 2], c = [1, 2]),
        [((:a, :b), (a, b) -> a != b),
         ((:b, :c), (b, c) -> b != c)])
    @test negative_rows(space) == [(p = bad, a = 1, b = 1, c = 1), (p = bad, a = 2, b = 2, c = 2)]
    base = [(p = bad, a = 1), (p = bad, a = 2), (p = bad, b = 1),
            (p = bad, b = 2), (p = bad, c = 1), (p = bad, c = 2)]
    @test negative_targets(space) == base

    # A stronger group containing p adds (s-1)-way combinations within the group.
    r = check_design([], space; stronger = [(:p, :a, :c) => 3])
    @test Set(r.negative.feasible) == Set([base; (p = bad, a = 1, c = 1); (p = bad, a = 2, c = 2)])
    @test Set(r.negative.implied) == Set([(p = bad, a = 1, c = 2), (p = bad, a = 2, c = 1)])
    @test isempty(r.negative.forbidden)
    rab = check_design([], space; stronger = [(:p, :a, :b) => 3])
    @test Set(rab.negative.forbidden) == Set([(p = bad, a = 1, b = 2) => [1], (p = bad, a = 2, b = 1) => [1]])
    # A group without p adds no negative targets.
    rabc = check_design([], space; stronger = [(:a, :b, :c) => 3])
    @test rabc.negative.feasible == base
    @test rabc.ordinary.counts.feasible == check_design([], space).ordinary.counts.feasible + 2

    # A negative target with no valid completion at strength 1 is reported, not required.
    dead_space = CheckSpace((q = [1, CheckInvalid(0)], x = [1, 2], y = [1, 2]),
        [((:x, :y), (x, y) -> x != y), ((:x, :y), (x, y) -> x == y)])
    @test isempty(valid_rows(dead_space)) && isempty(negative_rows(dead_space))
    re = check_design([], dead_space; strength = 1)
    @test re.negative.implied == [(q = CheckInvalid(0),)]
    @test re.ordinary.counts.feasible == 0 && re.negative.counts.feasible == 0
    @test complete(re)
end


@testitem "checker: two invalid values in a row" setup=[Checker] begin
    z = CheckInvalid(0)
    space = CheckSpace((x = [1, z], y = [1, z]))
    @test valid_rows(space) == [(x = 1, y = 1)]
    @test negative_rows(space) == [(x = 1, y = z), (x = z, y = 1)]
    @test negative_targets(space) == [(x = 1, y = z), (x = z, y = 1)]
    @test negative_targets(space; strength = 1) == [(x = z,), (y = z,)]
    @test_throws ArgumentError classify_target(space, (x = z, y = z))

    good = [(x = 1, y = 1), (x = z, y = 1), (x = 1, y = z)]
    @test complete(check_design(good, space))
    r = check_design([good; (x = z, y = z)], space)
    @test !complete(r)
    j = only(r.negative.rejected)
    @test (j.index, j.reason) == (4, :multiple_invalid)
    @test isempty(r.ordinary.rejected)
end


@testitem "checker: whole-case rules and scope order" setup=[Checker] begin
    bad = CheckInvalid(9)
    # The rule adds its arguments, so evaluating it on CheckInvalid would throw.
    space = CheckSpace((x = [1, 2, bad], y = [1, 2], z = [1, 2]),
        [((:x, :y, :z), (x, y, z) -> x + y + z == 4)])
    @test Set(valid_rows(space)) == Set([
        (x = 1, y = 1, z = 1), (x = 1, y = 2, z = 2), (x = 2, y = 1, z = 2),
        (x = 2, y = 2, z = 1), (x = 2, y = 2, z = 2)])
    # A whole-case rule mentions every parameter, so no negative row applies it.
    @test length(negative_rows(space)) == 4
    # It cannot forbid a pair directly; every pair is feasible here.
    r2 = check_design([], space)
    @test r2.ordinary.counts.feasible == 12
    @test isempty(r2.ordinary.forbidden) && isempty(r2.ordinary.implied)
    # At full strength it forbids its three rows directly.
    r3 = check_design([], space; strength = 3)
    @test Set(r3.ordinary.forbidden) == Set([
        (x = 1, y = 1, z = 2) => [1], (x = 1, y = 2, z = 1) => [1], (x = 2, y = 1, z = 1) => [1]])
    @test r3.ordinary.counts.feasible == 5

    # The predicate receives values in scope order, not parameter order.
    s = CheckSpace((a = [1, 2], b = [:p, :q]), [((:b, :a), (b, a) -> b == :q && a == 1)])
    @test Set(valid_rows(s)) == Set([(a = 1, b = :p), (a = 2, b = :p), (a = 2, b = :q)])
end


@testitem "checker: partitions" setup=[Checker] begin
    tiny = CheckPartition(:tiny)
    huge = CheckPartition(:huge)
    space = CheckSpace((size = [tiny, huge, 100], mode = [:a, :b]),
        [((:size, :mode), (s, m) -> s == :tiny && m == :b)])
    # Rules see the name; rows keep the wrapper.
    @test valid_rows(space) == [
        (size = tiny, mode = :a), (size = huge, mode = :a), (size = huge, mode = :b),
        (size = 100, mode = :a), (size = 100, mode = :b)]
    @test valid_rows(space)[1].size isa CheckPartition
    # Targets see the name.
    @test feasible_targets(space, (:size, :mode), 2) == [
        (size = :tiny, mode = :a), (size = :huge, mode = :a), (size = :huge, mode = :b),
        (size = 100, mode = :a), (size = 100, mode = :b)]
    @test feasible_targets(space, (:size,), 1) == [(size = :tiny,), (size = :huge,), (size = 100,)]
    r = check_design([], space)
    @test r.ordinary.forbidden == [(size = :tiny, mode = :b) => [1]]
    @test classify_target(space, (size = :tiny, mode = :b)).rule == 1
    @test classify_target(space, (size = tiny, mode = :b)).rule == 1
    @test classify_target(space, (size = :huge, mode = :b)).status == :required

    # A case may write a partition as its wrapper or its name (contract §2.11);
    # rows come back with the wrapper. A realized draw is not a domain value.
    rc = check_design([(size = tiny, mode = :a), (size = :huge, mode = :b), (size = 1e-9, mode = :a)], space)
    @test rc.ordinary.rows == [(size = tiny, mode = :a), (size = huge, mode = :b)]
    j = only(rc.ordinary.rejected)
    @test (j.index, j.reason, j.parameter) == (3, :unknown_value, :size)
    @test (size = :tiny, mode = :a) in rc.ordinary.covered
    @test (size = :huge, mode = :b) in rc.ordinary.covered
    @test same_target(only(check_design([(size = :tiny, mode = :a)], space).ordinary.rows),
                      (size = tiny, mode = :a))

    # A raw Symbol equal to a partition name is ambiguous and rejected.
    @test_throws ArgumentError CheckSpace((size = [tiny, :tiny],))
end


@testitem "checker: stronger groups" setup=[Checker] begin
    space = CheckSpace((a = [1, 2], b = [1, 2], c = [1, 2], d = [1, 2]))
    triples_abc = [(a = i, b = j, c = k) for i in 1:2 for j in 1:2 for k in 1:2]
    triples_bcd = [(b = i, c = j, d = k) for i in 1:2 for j in 1:2 for k in 1:2]

    @test length(feasible_targets(space)) == 24  # 6 parameter pairs, 4 value pairs each
    with_abc = feasible_targets(space; stronger = [(:a, :b, :c) => 3])
    @test length(with_abc) == 32
    @test issubset(Set(triples_abc), Set(with_abc))
    @test count(t -> length(t) == 3, with_abc) == 8
    @test Set(feasible_targets(space; stronger = [(1, 2, 3) => 3])) == Set(with_abc)

    # Overlapping groups combine by union.
    both = feasible_targets(space; stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3])
    @test length(both) == 40
    @test Set(both) == Set([feasible_targets(space); triples_abc; triples_bcd])
    @test length(feasible_targets(space; stronger = [(:a, :b, :c) => 3, (:c, :b, :a) => 3])) == 32
    @test length(feasible_targets(space; stronger = [(:a, :b, :c) => 3, (:a, :b, :c, :d) => 4])) == 48
    # A group at the base strength adds nothing.
    @test length(feasible_targets(space; stronger = [(:a, :b) => 2])) == 24
    # A group listed twice acts as its highest strength (contract §11.8):
    # 8 single values plus the 8 abc triples, not also the 12 abc pairs.
    @test length(feasible_targets(space; strength = 1,
        stronger = [(:a, :b, :c) => 2, (:a, :b, :c) => 3])) == 16
    @test length(feasible_targets(space; strength = 1, stronger = [(:a, :b, :c) => 2])) == 20

    # All abc triples, with d the parity: every pair appears twice.
    design = [(a = i, b = j, c = k, d = 1 + mod(i + j + k, 2)) for i in 1:2 for j in 1:2 for k in 1:2]
    r = check_design(design, space; stronger = [(:a, :b, :c) => 3])
    @test complete(r)
    @test r.groups == [[:a, :b, :c, :d] => 2, [:a, :b, :c] => 3]
    # Dropping one row loses exactly its abc triple.
    r7 = check_design(design[2:end], space; stronger = [(:a, :b, :c) => 3])
    @test r7.ordinary.missing == [(a = 1, b = 1, c = 1)]
    @test complete(check_design(design[2:end], space))
end


@testitem "checker: design coverage and rejected cases" setup=[Checker] begin
    space = CheckSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]),
        [((:mode, :solver), (m, s) -> m == :fast && s != :none),
         ((:mode, :tol), (m, t) -> m == :exact && t == 1e-3)])
    fn3 = (mode = :fast, solver = :none, tol = 1e-3)
    fn6 = (mode = :fast, solver = :none, tol = 1e-6)
    en6 = (mode = :exact, solver = :none, tol = 1e-6)
    el6 = (mode = :exact, solver = :lu, tol = 1e-6)
    eq6 = (mode = :exact, solver = :qr, tol = 1e-6)

    @test complete(check_design([fn3, fn6, en6, el6, eq6], space))

    # (exact, none) appears only in en6; its other two pairs appear elsewhere.
    r = check_design([fn3, fn6, el6, eq6], space)
    @test r.ordinary.missing == [(mode = :exact, solver = :none)]
    @test !complete(r)

    # A duplicate counts once.
    rd = check_design([fn3, fn6, en6, el6, eq6, fn3], space)
    @test complete(rd)
    @test rd.ordinary.duplicates == 1
    @test length(rd.ordinary.rows) == 5

    # A row that breaks a rule is listed and covers nothing: (fast, lu, 1e-6)
    # would otherwise cover (lu, 1e-6).
    rv = check_design([fn3, fn6, en6, eq6, (mode = :fast, solver = :lu, tol = 1e-6),
                       (mode = :exact, solver = :none, tol = 1e-3)], space)
    @test [(j.index, j.reason, j.rules) for j in rv.ordinary.rejected] == [
        (5, :violates_rule, [1]), (6, :violates_rule, [2])]
    @test rv.ordinary.missing == [(mode = :exact, solver = :lu), (solver = :lu, tol = 1e-6)]
    @test rv.ordinary.counts.covered == 9

    # Malformed cases.
    rbad = check_design(Any[
        (mode = :fast, solver = :none, tol = 1e-3, extra = 1),
        (mode = :fast, solver = :none),
        (:fast, :none),
        42,
        (mode = :fast, solver = nothing, tol = 1e-3),
        (mode = :fast, solver = :none, tol = 1f-3),
        ], space)
    @test [(j.index, j.reason, j.parameter) for j in rbad.ordinary.rejected] == [
        (1, :unknown_parameter, :extra), (2, :missing_parameter, :tol),
        (3, :wrong_length, nothing), (4, :not_a_case, nothing),
        (5, :unknown_value, :solver), (6, :unknown_value, :tol)]
    @test rbad.ordinary.counts.covered == 0
    @test isempty(rbad.negative.rejected)

    # Field order does not matter; rows come back in parameter order.
    ro = check_design([(tol = 1e-3, solver = :none, mode = :fast)], space)
    @test ro.ordinary.rows == [fn3]
    @test keys(only(ro.ordinary.rows)) == (:mode, :solver, :tol)

    # An empty design covers nothing.
    re = check_design([], space)
    @test re.ordinary.counts.missing == 11
    @test !complete(re)

    # Deterministic: the same inputs give the same lists.
    @test check_design([fn3, el6], space).ordinary.missing == check_design([fn3, el6], space).ordinary.missing
end


@testitem "checker: positional cases" setup=[Checker] begin
    space = CheckSpace([:mode, :solver, :tol],
        [[:fast, :exact], [:none, :lu, :qr], [1e-3, 1e-6]],
        [((:mode, :solver), (m, s) -> m == :fast && s != :none),
         ((:mode, :tol), (m, t) -> m == :exact && t == 1e-3)])
    named = [(mode = :fast, solver = :none, tol = 1e-3),
             (mode = :fast, solver = :none, tol = 1e-6),
             (mode = :exact, solver = :qr, tol = 1e-6),
             (mode = :fast, solver = :lu, tol = 1e-6)]
    tuples = [Tuple(c) for c in named]
    vectors = [collect(Any, c) for c in named]
    rn = check_design(named, space)
    for rp in (check_design(tuples, space), check_design(vectors, space))
        @test rp.ordinary.rows == rn.ordinary.rows
        @test rp.ordinary.missing == rn.ordinary.missing
        @test rp.ordinary.counts == rn.ordinary.counts
        @test [(j.index, j.reason, j.rules) for j in rp.ordinary.rejected] ==
              [(j.index, j.reason, j.rules) for j in rn.ordinary.rejected]
    end
    @test rn.ordinary.counts.rejected == 1
    @test rn.ordinary.missing == [(mode = :exact, solver = :none), (mode = :exact, solver = :lu),
                                  (solver = :lu, tol = 1e-6)]

    # Positional input with a partition and an invalid value.
    ps = CheckSpace([:n, :size], [[1, CheckInvalid(0)], [CheckPartition(:tiny), 5]])
    r = check_design([(1, CheckPartition(:tiny)), (1, 5), (CheckInvalid(0), 5),
                      (CheckInvalid(0), CheckPartition(:tiny))], ps)
    @test complete(r)
    @test r.negative.rows == [(n = CheckInvalid(0), size = 5), (n = CheckInvalid(0), size = CheckPartition(:tiny))]
end


@testitem "checker: direct attribution names every rule" setup=[Checker] begin
    # Contract §1.4: every applicable rule whose scope lies within the target
    # and forbids it is named, in rule order.
    space = CheckSpace((x = [1, 2], y = [1, 2], z = [1, 2]),
        [((:x, :y), (x, y) -> x == 1 && y == 1),
         ((:x,), x -> x == 1 && false),
         ((:y, :x), (y, x) -> x == 1),
         ((:x, :y, :z), (x, y, z) -> x == 1 && z == 2)])
    @test classify_target(space, (x = 1, y = 1)) == (status = :forbidden, rule = 1, rules = [1, 3])
    @test classify_target(space, (x = 1, y = 2)) == (status = :forbidden, rule = 3, rules = [3])
    @test classify_target(space, (x = 1, y = 1, z = 2)).rules == [1, 3, 4]
    r = check_design([(x = 1, y = 1, z = 2)], space)
    @test only(r.ordinary.rejected).rules == [1, 3, 4]
    @test Set(r.ordinary.forbidden) == Set([(x = 1, y = 1) => [1, 3], (x = 1, y = 2) => [3]])
    # (x = 1, z = 1) is forbidden by rule 3 only through y, so it is implied.
    @test (x = 1, z = 1) in r.ordinary.implied
end


@testitem "checker: one rule with a wider scope makes a target implied" setup=[Checker] begin
    # Contract §1.4: :implied means infeasible with no direct rule match. One
    # rule over (a, b, c) forbids every c when a = 1 and b = 1. That rule
    # alone excludes (a = 1, b = 1), but its scope is wider than the target's
    # parameters, so the target is :implied by definition, not :forbidden.
    space = CheckSpace((a = [1, 2], b = [1, 2], c = [1, 2]),
        [((:a, :b, :c), (a, b, c) -> a == 1 && b == 1)])
    @test classify_target(space, (a = 1, b = 1)) == (status = :implied, rule = nothing, rules = Int[])
    # The same rule is direct for a target that assigns its whole scope.
    @test classify_target(space, (a = 1, b = 1, c = 2)) == (status = :forbidden, rule = 1, rules = [1])
    @test classify_target(space, (a = 1, c = 1)).status == :required
    r = check_design(valid_rows(space), space)
    @test complete(r)
    @test r.ordinary.implied == [(a = 1, b = 1)]
    @test isempty(r.ordinary.forbidden)
end
