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
    # The error carries its explanation, in the words of explain (§10.4, §1.26).
    msg = message(() -> Request(space; must_include = [(solver = :lu, tol = 1e-3)]))
    @test msg == "ArgumentError: must_include row 1, (solver = :lu, tol = 0.001), has no valid completion: " *
                 "rules 1 and 2 together exclude it (rule 1: @require(mode == :exact || solver == :none); " *
                 "rule 2: exact mode needs a tight tolerance) (contract §10.4)"
    @test occursin(split(sprint(show, explain(space, (solver = :lu, tol = 1e-3))), "; ", limit = 2)[2], msg)
    @test_throws ArgumentError Request(space; must_include = [(solver = :lu, tol = 1e-3)])
    # The deletion search runs under the request's explanation_limit; a cut-short
    # search still names a sufficient set and says which limit it reached.
    msg = message(() -> Request(space; must_include = [(mode = :fast,), (solver = :qr, tol = 1e-3)],
                                explanation_limit = 1))
    @test occursin("must_include row 2, (solver = :qr, tol = 0.001), has no valid completion: rules 1 and 2", msg)
    @test occursin("; whether each rule is needed is unresolved: explanation_limit = 1 reached (contract §10.4)", msg)
    # One rule alone: "rule k (label) excludes it".
    one = TestSpace((a = 1:2, b = 1:2); constraints = [forbid(case -> case.a == 1; reason = "a is never 1")])
    msg = message(() -> Request(one; must_include = [(a = 1,)]))
    @test occursin("(a = 1,), has no valid completion: rule 1 (a is never 1) excludes it (contract §10.4)", msg)

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


@testitem "request: limits are positive, and wrappers are values (§3.3, §4.2, §5)" setup=[RequestSetup] begin
    space = solver_space()
    @test_throws ArgumentError Request(space; feasibility_limit = 0)
    @test_throws ArgumentError Request(space; explanation_limit = -1)
    @test Request(space; feasibility_limit = 5).feasibility_limit == 5
    # Invalid values follow the ordinary ones in engine positions; an engine
    # sees only the ordinary positions, 1:arity (Phase 6).
    r = Request(TestSpace((a = [1, Invalid(0), 2], b = [1, 2])))
    @test r.candidates == [[1, 3, 2], [1, 2]] && r.arity == [2, 2]
    @test r.feasibility.candidates == [[1, 3], [1, 2]]
    @test length(targets(r)) == 4
    # A Partition is an ordinary value.
    r = Request(TestSpace((a = [Partition(:tiny, Returns(1)), 2], b = [1, 2])))
    @test r.candidates == [[1, 2], [1, 2]] && r.arity == [2, 2]
    # A negative must-include row is validated under the negative policy and
    # holds its invalid position (§7.9).
    s = TestSpace((a = [1, Invalid(0)], b = [1, 2]); constraints = [@forbid(a == 1 && b == 2)])
    r = Request(s; must_include = [(a = Invalid(0), b = 2), (a = Invalid(0),)])
    @test r.must_include == [2 2; 2 0]
    @test occursin("breaks rule 1", message(() -> Request(s; must_include = [(a = 1, b = 2)])))
    # Strength 0 is refused at the keyword constructor, the public floor (§11.1).
    @test_throws ArgumentError Request(s; strength = 0)
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


@testitem "request: the supports, each listed once, and each group's share of them (§1.8, §1.15)" setup=[RequestSetup] begin
    using UnitTestDesign: _group_supports, _supports
    # A subset two groups share is one support, where it first appears; each
    # group's share lists it all the same.
    groups = [[1, 2, 3, 4] => 2, [1, 2, 3] => 3, [1, 2, 3, 4] => 3]
    supports, shares = _group_supports(groups)
    @test supports == [[1, 2], [1, 3], [1, 4], [2, 3], [2, 4], [3, 4], [1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]]
    @test shares == [1:6, [7], 7:10]
    @test _supports(groups) == supports
    # A base group at strength 0, as a negative sub-request's, has no share.
    @test _group_supports([[1, 2, 3] => 0, [1, 2] => 1, [2, 3] => 2]) == ([[1], [2], [2, 3]], [Int[], [1, 2], [3]])
    # The base group's supports are computed, not listed: only the other groups' are.
    @test supports.nbase == 6 && supports.listed == [1, 2, 3, 1, 2, 4, 1, 3, 4, 2, 3, 4]
    # A group at the base strength adds no support (`_groups` drops one, §11.7): its subsets are base subsets.
    @test _group_supports([[1, 2, 3, 4] => 2, [2, 3, 4] => 2]) == (supports[1:6], [1:6, [4, 5, 6]])
    # Groups whose base group is not every parameter in order are an internal error.
    @test_throws ErrorException _group_supports([[2, 1] => 1])
end


@testitem "request: the base group's supports are unranked and ranked in `combinations` order (plan §5.6)" setup=[RequestSetup] begin
    using Combinatorics: combinations
    using Random: Xoshiro
    using UnitTestDesign: _supports, _support!, _support_rank, _each_support
    # Support `s` of the base group, every parameter at strength `t`, is the
    # subset of rank `s - 1` among the `t`-subsets of 1:n in lexicographic
    # order, as `combinations` lists them: unranked (`_support!`), ranked
    # back (`_support_rank`), stepped through in order (`_each_support`), and
    # read whole (`getindex`, `collect`), on every (n, t) up to n = 12 and
    # at strength 0, which has none.
    buffer = Int[]
    for n in 1:12, t in 0:n
        supports = _supports([collect(1:n) => t])
        listed = t == 0 ? Vector{Int}[] : collect(combinations(1:n, t))
        @test length(supports) == supports.nbase == length(listed)
        @test collect(supports) == listed
        @test all(s -> _support!(buffer, supports, s) == listed[s], eachindex(listed))
        @test all(s -> _support_rank(supports, listed[s]) == s, eachindex(listed))
        @test [copy(support) for (_, support) in _each_support(supports)] == listed
        @test [s for (s, _) in _each_support(supports)] == eachindex(listed)
    end
    # Wide cases, against the definition of the rank with BigInt binomials:
    # the subsets before c are, for each place, those that agree before it
    # and hold a smaller value there.
    function brute_rank(c, n)
        t = length(c)
        r = big(0)
        for i in 1:t, v in ((i == 1 ? 0 : c[i - 1]) + 1):(c[i] - 1)
            r += binomial(big(n - v), t - i)
        end
        return r
    end
    rng = Xoshiro(0x2026_1006_5099)
    for (n, t) in ((100, 3), (1_000, 2), (1_000, 4), (4_096, 2), (4_096, 3), (250, 6), (60, 30), (64, 63), (30, 1))
        supports = _supports([collect(1:n) => t])
        @test length(supports) == binomial(big(n), t)
        for s in vcat([1, 2, length(supports) - 1, length(supports)], rand(rng, 1:length(supports), 100))
            c = supports[s]
            @test length(c) == t && issorted(c; lt = <=) && 1 <= first(c) && last(c) <= n
            @test brute_rank(c, n) == s - 1
            @test _support_rank(supports, c) == s
            # The step to the next subset, in place, is the next position's.
            if s < length(supports)
                walk = _each_support(supports, copy(c))
                @test last(iterate(walk, s)[1]) == supports[s + 1]
            end
        end
    end
    # Past Int, the number of base supports is an OverflowError, as the offsets' was.
    @test_throws OverflowError _supports([collect(1:200) => 100])
end


@testitem "request: the layout's walk of the base supports that hold a parameter and others from a set, in order (plan §5.6)" setup=[RequestSetup] begin
    using Combinatorics: combinations
    using Random: Xoshiro, randperm
    using UnitTestDesign: TargetList, _Classified, _request, _supports, _support!, _support_rank,
                          _each_base_support, _BaseWalkBuffers, _lookup_steps, ipog_order
    # `_each_base_support(supports, p, earlier)` gives each base support that
    # holds p and t - 1 of the parameters `earlier`, with its position, in
    # increasing position, as IPOG's step at p reads them (`_begin_step!`).
    # Against the definition: each (t - 1)-subset of `earlier` with p,
    # positioned by ranking (`_support_rank`) and read back by unranking
    # (`_support!`). On every step of random parameter orders, IPOG's among
    # them, on random layouts with `stronger` groups at base strengths 1 to
    # 4, and a negative sub-request's at base strength 0, which has none; at
    # IPOG's order the walk gives exactly the step's base supports
    # (`_lookup_steps`). Then on wide base groups with random sets. One pair
    # of buffers serves every walk.
    buffers = _BaseWalkBuffers()
    buffer = Int[]
    "The walk at `p` against the definition; returns its positions."
    function check(sups, p, earlier)
        got = [(s, copy(support)) for (s, support) in _each_base_support(sups, p, earlier, buffers)]
        t = sups.t
        expected = t == 0 || length(earlier) < t - 1 ? Tuple{Int, Vector{Int}}[] :
                   sort!([(_support_rank(sups, c), c) for c in (sort!([p; subset]) for subset in combinations(earlier, t - 1))])
        @test got == expected
        @test issorted(first.(got); lt = <=)
        @test all(((s, c),) -> _support!(buffer, sups, s) == c, got)
        @test length(got) == (t == 0 ? 0 : binomial(length(earlier), t - 1))
        return first.(got)
    end
    rng = Xoshiro(0x2026_1007_1a70)
    tally = Dict(:t0 => 0, :t1 => 0, :t2 => 0, :t3 => 0, :t4 => 0, :listed => 0, :steps => 0)
    for _ in 1:80
        n = rand(rng, 2:9)
        strength = rand(rng, 1:min(4, n))
        stronger = Pair{Vector{Int}, Int}[]
        for _ in 1:(strength < n ? rand(rng, 0:3) : 0)
            k = rand(rng, (strength + 1):n)
            push!(stronger, sort!(randperm(rng, n)[1:k]) => rand(rng, (strength + 1):k))
        end
        space = TestSpace([Symbol(:p, i) for i in 1:n], [1:rand(rng, 1:3) for _ in 1:n], Constraint[], 10^5)
        requests = [Request(space; strength, stronger)]
        if strength == 1 && !isempty(stronger)
            # A negative sub-request's shape: base strength 0, so every support is listed.
            r = requests[1]
            push!(requests, _request(space, 0, [collect(1:n) => 0; r.groups[2:end]], zeros(Int, n, 0), r.feasibility,
                                     10^6, 10^6))
        end
        for request in requests
            sups = TargetList(request).supports
            order = ipog_order(request.arity, request.groups)
            steps = _lookup_steps(_Classified(request).targets, request.arity, order)
            for (k, p) in enumerate(order)
                ids = check(sups, p, sort(order[1:(k - 1)]))
                @test ids == filter(<=(sups.nbase), steps.supports[steps.first[p]:(steps.first[p + 1] - 1)])
                tally[:steps] += 1
            end
            for _ in 1:2
                shuffled = randperm(rng, n)
                for (k, p) in enumerate(shuffled)
                    check(sups, p, sort(shuffled[1:(k - 1)]))
                end
            end
            tally[Symbol(:t, request.strength)] += 1
            tally[:listed] += length(sups) > sups.nbase
        end
    end
    @test all(>(0), values(tally))
    # Wide base groups, random parameters and sets, the first and last
    # parameters among them; and every other parameter as the set.
    for (n, t, size) in ((1_000, 2, 999), (1_000, 2, 40), (200, 3, 60), (60, 4, 30), (4_096, 3, 25), (30, 1, 29))
        sups = _supports([collect(1:n) => t])
        for _ in 1:20
            p = rand(rng, (1, n, rand(rng, 1:n)))
            others = setdiff(1:n, p)
            earlier = sort!(size >= n - 1 ? others : others[randperm(rng, n - 1)[1:size]])
            check(sups, p, earlier)
        end
    end
    # A set that isn't ascending within 1:n, or that holds p, is an internal
    # error, but not at t = 1, which doesn't read it; p must be a parameter.
    sups = _supports([collect(1:6) => 3])
    for bad in ([2, 1], [1, 1], [0, 2], [1, 7], [1, 4])
        @test_throws ErrorException collect(_each_base_support(sups, 4, bad))
    end
    @test_throws ErrorException collect(_each_base_support(sups, 7, [1, 2]))
    @test [s for (s, _) in _each_base_support(_supports([collect(1:6) => 1]), 4, [2, 1])] == [4]
end


@testitem "request: the layout's supports and offsets are the listed layout's, in order (plan §5.6, §9.7)" setup=[RequestSetup] begin
    using Combinatorics: combinations
    using Random: Xoshiro, randperm
    using UnitTestDesign: TargetList, NegativeProjection, _negative_request, _group_supports, _supports,
                          _support!, _each_support
    # The supports as 31bef0f listed them, written out: each group's subsets
    # in `combinations` order, the base group first, each subset once, where
    # it first appears, with each group's share of positions; and the offsets
    # from them. The layout must give every support in the same order, every
    # offset and every share, on random requests with overlapping `stronger`
    # groups (several at one strength, one inside another, one listed twice),
    # their negative sub-requests (base strength 0, and 1), and full strength.
    function listed_supports(groups)
        supports, position, shares = Vector{Int}[], Dict{Vector{Int}, Int}(), Vector{Int}[]
        for (members, s) in groups
            share = Int[]
            s > 0 && for subset in combinations(members, s)
                push!(share, get!(() -> (push!(supports, subset); length(supports)), position, subset))
            end
            push!(shares, share)
        end
        return supports, shares
    end
    function listed_offsets(arity, supports)
        offsets = [0]
        for support in supports
            push!(offsets, last(offsets) + prod(arity[support]; init = 1))
        end
        return offsets
    end
    "The layout of `request` against the listed one; returns the number of supports listed after the base group's."
    function check(request)
        layout = TargetList(request)
        supports, shares = listed_supports(request.groups)
        @test collect(layout.supports) == supports
        @test [copy(support) for (_, support) in _each_support(layout.supports)] == supports
        buffer = Int[]
        @test all(s -> _support!(buffer, layout.supports, s) == supports[s], eachindex(supports))
        @test layout.offsets == listed_offsets(request.arity, supports)
        @test last(_group_supports(request.groups)) == shares
        return length(layout.supports) - layout.supports.nbase
    end
    rng = Xoshiro(0x2026_1006_1157)
    tally = Dict(:listed => 0, :shared => 0, :zero => 0, :one => 0, :sub => 0, :full => 0)
    for _ in 1:150
        n = rand(rng, 3:9)
        space = TestSpace([Symbol(:p, i) for i in 1:n], [Any[1:rand(rng, 1:3)...; rand(rng) < 0.3 ? [Invalid(0)] : []]
                                                         for _ in 1:n], Constraint[], 10^5)
        strength = rand(rng, 1:n)
        stronger = Pair{Vector{Int}, Int}[]
        if strength < n
            # Groups at one strength overlap often; one may hold another, or repeat.
            s = rand(rng, (strength + 1):n)
            for _ in 1:rand(rng, 0:5)
                k = rand(rng, s:n)
                push!(stronger, sort!(randperm(rng, n)[1:k]) => rand(rng) < 0.7 ? s : rand(rng, (strength + 1):k))
            end
            rand(rng) < 0.3 && !isempty(stronger) && push!(stronger, first(stronger))
        end
        request = Request(space; strength, stronger)
        listed = check(request)
        tally[:listed] += listed > 0
        tally[:shared] += sum(binomial(length(g), s) for (g, s) in request.groups[2:end]; init = 0) > listed
        tally[:full] += strength == n
        for q in 1:n
            isempty(space.invalid[q]) && continue
            strength > 1 || any(g -> q in g.first, request.groups[2:end]) || continue
            sub = _negative_request(request, NegativeProjection(space, q), zeros(Int, n - 1, 0))
            tally[sub.strength == 0 ? :zero : sub.strength == 1 ? :one : :sub] += 1
            check(sub)
        end
    end
    @test all(>(0), values(tally))
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
    @test all(e -> e.limit === nothing, excluded)
    # Required targets keep the order of `targets`.
    @test required == filter(t -> t in required, targets(request))

    # An explanation that a limit left unresolved records which limit, so a
    # report can say so without searching again.
    _, cut = classify_targets(Request(solver_space(); explanation_limit = 1))
    @test [e.target for e in cut] == [e.target for e in excluded]
    @test all(e -> e.limit === nothing, filter(e -> e.status == :forbidden, cut))
    cut_implied = filter(e -> e.status == :implied, cut)
    @test all(e -> e.rules == [1, 2] && e.minimal == :unresolved, cut_implied)
    @test all(e -> e.limit == (:explanation_limit => 1), cut_implied)

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


@testitem "request: a placement search at its limit throws; no design is incomplete (§3.6–§3.8)" setup=[RequestSetup, Checker] begin
    # The acceptance gate of plan Phase 3: a limited search raises an error
    # rather than returning an incomplete design. Here the limit runs out while
    # an engine places a value, after every target was classified.
    #
    # Ten two-valued parameters, then a, b and c with three values, and one
    # whole-case rule forbidding a = b = c = 1. A whole-case rule is checked
    # only when at most one parameter is left, so proving that (a = 1, b = 1,
    # c = 1) has no completion visits every assignment of the x's, about 2^10
    # nodes. Every other question has a witness about a dozen nodes deep: each
    # pair (the search fills the x's with 1 and then gives whichever of a, b,
    # c is left a value the rule allows), the empty row, and the partial
    # must-include row (a = 1, b = 1). Both engines, completing that row, try
    # c = 1 beside it and ask the expensive question.
    using UnitTestDesign: generate
    xs = [Symbol(:x, i) for i in 1:10]
    names = [xs; :a; :b; :c]
    domains = [fill(1:2, 10); fill(1:3, 3)]
    space = TestSpace(Pair.(names, domains)...;
                      constraints = [forbid(case -> case.a == 1 && case.b == 1 && case.c == 1)])
    oracle = CheckSpace(names, collect.(domains), [(Tuple(names), (v...) -> v[11] == 1 && v[12] == 1 && v[13] == 1)])
    seeds = [(a = 1, b = 1)]
    for engine in (IPOG(), GND())
        request = Request(space; must_include = seeds, feasibility_limit = 100)
        required, excluded = classify_targets(request)   # resolved within the limit
        @test length(required) == length(targets(request)) && isempty(excluded)
        err = try generate(engine, request); nothing catch e; e end
        @test err isa ResourceLimitError
        @test (err.limit, err.keyword) == (100, :feasibility_limit)
        @test startswith(err.what, "placing a value")
        @test occursin("a = 1, b = 1", err.what) && occursin("c = 1", err.what)

        # Every limit either throws ResourceLimitError or returns a design the
        # oracle accepts; a larger limit never changes a returned design.
        designs = Matrix{Int}[]
        for limit in (1, 10, 100, 1_000, 3_000, 10_000, 1_000_000)
            outcome = try
                limited = Request(space; must_include = seeds, feasibility_limit = limit)
                (limited, generate(engine, limited))
            catch e
                e
            end
            if outcome isa Exception
                @test outcome isa ResourceLimitError
                continue
            end
            limited, design = outcome
            cases = to_cases(limited, design.matrix)
            @test complete(check_design(cases, oracle))
            @test cases[1].a == 1 && cases[1].b == 1 && cases[1].c != 1
            push!(designs, design.matrix)
        end
        @test length(designs) >= 2
        @test all(==(first(designs)), designs)
    end
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
    @test occursin("internal error: case 5, (mode = :fast, solver = :qr, tol = 1.0e-6), breaks rule 1 " *
                   "(@require(mode == :exact || solver == :none))", msg(broken))
    changed = copy(good); changed[2, 1] = 3        # the must-include row asked for :lu
    @test occursin("internal error: must_include row 1 was changed at parameter solver", msg(changed))
    @test occursin("internal error: must_include row 1 is missing", msg(zeros(Int, 3, 0)))
    short = good[:, 1:4]                           # (exact, qr) is never covered
    @test occursin("internal error: required target (mode = :exact, solver = :qr) is not covered", msg(short))
    @test_throws ErrorException validate_design(request, short, required)
    # Only required targets are checked: excluded ones may stay uncovered.
    @test validate_design(Request(solver_space()), good, required) == 11
end


@testsnippet RecountVerdict begin
    using UnitTestDesign: from_indices, _space_indices

    """
    The layout recount's verdict on the rows `m` (columns, engine positions),
    written out from lists: the message for the first target of `walked`,
    every target in target order, that is excluded (in `gone`) and held by a
    row, or required and held by none, or `nothing`. The recount checks the
    exclusions against the rows as well as their coverage (contract §1.4,
    §1.21); the list recount, from the required targets alone, can't.
    """
    function layout_verdict(request, m, walked, gone)
        named(t) = from_indices(request.space, _space_indices(request, t))
        holds(t, j) = all(i -> t[i] == 0 || t[i] == m[i, j], eachindex(t))
        for t in walked
            j = findfirst(j -> holds(t, j), axes(m, 2))
            if t in gone
                j === nothing || return "internal error: excluded target $(named(t)) is held by the row " *
                                        "$(named(m[:, j])); classification found no valid row that holds it " *
                                        "(contract §1.4)"
            elseif j === nothing
                return "internal error: required target $(named(t)) is not covered"
            end
        end
        return nothing
    end
end


@testitem "request: the recount counts on the layout, names the first uncovered target, and rejects a held excluded one (§1.21)" setup=[RequestSetup, RecountVerdict] begin
    using UnitTestDesign: TargetList, _Classified, _recount, nrequired
    # Phase 5 (plan §5.6): `generate` certifies a design by recounting it on
    # the request's layout against the ids of the targets classification
    # excluded (`_recount`), with no list of required targets. It counts what
    # the list recount counts, 31bef0f's certification of the classified
    # list, which stays for tests and scripts, and a failure names the first
    # target in target order that is required and held by no row or, since
    # review p5-core 5, excluded and held by one: every row has been checked
    # valid by then, and no valid row holds an excluded target (§1.4), so
    # that means classification was wrong. Where no row holds an excluded
    # target, the failure is the list recount's. Rows of every kind are given
    # to `_recount` itself, which `validate_design` calls after it has
    # checked each row, so a changed value can break a rule here.
    request = Request(solver_space(); must_include = [(solver = :lu,)])
    layout_targets = _Classified(request).targets
    required, excluded = classify_targets(request)
    walked, gone = collect(TargetList(request)), Set(e.target for e in excluded)
    good = [2 1 1 2 2; 2 1 1 1 3; 2 1 2 2 2]
    @test validate_design(request, good, layout_targets) == validate_design(request, good, required) ==
          nrequired(layout_targets) == 11
    msg(m, t) = message(() -> _recount(request, m, t))
    designs = [good[:, setdiff(axes(good, 2), j)] for j in axes(good, 2)]                 # a row dropped
    for j in axes(good, 2), i in axes(good, 1), v in 1:request.arity[i]                   # a value changed
        v == good[i, j] && continue
        changed = copy(good)
        changed[i, j] = v
        push!(designs, changed)
    end
    uncovered, held = Ref(0), Ref(0)
    for m in designs
        ours, listed = msg(m, layout_targets), msg(m, required)
        @test ours == layout_verdict(request, m, walked, gone)
        if ours === nothing
            @test _recount(request, m, layout_targets) == _recount(request, m, required) == 11
        elseif startswith(ours, "internal error: excluded target")
            held[] += 1
        else
            @test ours == listed
            uncovered[] += 1
        end
    end
    @test uncovered[] >= 5 && held[] >= 5
    @test msg(good[:, 1:4], layout_targets) == "internal error: required target (mode = :exact, solver = :qr) is not covered"
    # Each excluded target, held by a row added to the design or alone, is
    # named, unless a required target before it in target order is uncovered.
    @test length(gone) == 5
    for t in gone
        row = [x == 0 ? 1 : x for x in t]
        for m in (hcat(good, row), reshape(row, :, 1), hcat(good[:, 1:4], row))
            @test msg(m, layout_targets) == layout_verdict(request, m, walked, gone) !== nothing
        end
        @test startswith(msg(hcat(good, row), layout_targets), "internal error: excluded target")
    end
end


@testitem "request: an unconstrained request's targets stay lazy, and the recount streams (§1.8, §1.21, §9.7)" setup=[RequestSetup] begin
    using UnitTestDesign: TargetList, generate
    # Phase 3 review, round 1, item 4: with no rule every target is required,
    # so classify_targets returns the TargetList, which computes each target
    # on demand, and validate_design certifies it one support at a time.
    free = Request(TestSpace((a = 1:2, b = 1:3, c = 1:2, d = [:x, :y]));
                   stronger = [(:a, :b, :c) => 3, (:c, :b, :a) => 3, (:a, :b, :c, :d) => 3])
    required, excluded = classify_targets(free)
    @test required isa TargetList && isempty(excluded)
    @test collect(required) == targets(free)     # the same targets, in the same order
    # 30 pairs; the triples of (a, b, c, d), of which (a, b, c)'s 12 are counted once.
    @test length(required) == 30 + (12 + 12 + 8 + 12)
    @test required[1] == [1, 1, 0, 0] && required[end] == [0, 3, 2, 2]
    @test_throws BoundsError required[length(required) + 1]
    # A constrained request lists its required targets.
    @test first(classify_targets(Request(solver_space()))) isa Vector{Vector{Int}}
    for engine in (IPOG(), GND())
        design = generate(engine, free)
        @test design.required == design.covered == length(required)
    end
    # The streamed recount agrees with the listed one, and names the same
    # first uncovered target.
    matrix = generate(IPOG(), free).matrix
    listed = collect(required)
    @test validate_design(free, matrix, required) == validate_design(free, matrix, listed) == length(required)
    for drop in (1, size(matrix, 2))
        short = matrix[:, setdiff(axes(matrix, 2), drop)]
        streamed, list = message(() -> validate_design(free, short, required)),
                         message(() -> validate_design(free, short, listed))
        @test streamed !== nothing && streamed == list
        @test occursin("internal error: required target", streamed)
    end
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


@testitem "request: the lazy-rule memo belongs to the request, not the space (§3.5, §12.19)" setup=[RequestSetup] begin
    using UnitTestDesign: generate, memo_size, validate_design, generate_full_factorial
    # Ten parameters and a whole-case rule, which is always lazy.
    names = [Symbol(:p, i) for i in 1:10]
    space = TestSpace((n => 1:3 for n in names)...;
                      constraints = [forbid(case -> case.p1 == case.p2 == case.p3 == 2; reason = "no three 2s"),
                                     @forbid(p4 == 1 && p5 == 3)])
    before = Base.summarysize(space)
    request = Request(space)
    @test memo_size(request) == 0
    design = generate(IPOG(), request)
    grown = memo_size(request)
    @test grown > 0                                   # generation memoized verdicts ...
    @test Base.summarysize(space) == before           # ... on the request, not the space
    @test Base.summarysize(request.feasibility) > Base.summarysize(Request(space).feasibility)
    # Validation shares the memo: every row was checked during generation.
    validate_design(request, design.matrix, Vector{Int}[]; strategy = :excursion)
    @test memo_size(request) == grown
    # A second request on the same space starts empty.
    second = Request(space)
    @test memo_size(second) == 0
    generate(GND(), second)
    @test memo_size(second) > 0 && memo_size(request) == grown
    # A long-lived space retains nothing, however often it is used.
    sizes = Int[]
    for k in 1:10
        r = Request(space; strength = isodd(k) ? 2 : 3)
        generate(isodd(k) ? IPOG() : GND(seed = k), r)
        push!(sizes, Base.summarysize(space))
    end
    @test all(==(before), sizes)
    # Full factorial memoizes one verdict per row it checks: every row once.
    full = Request(space; strength = 1)
    generate_full_factorial(full; limit = 3^10)
    @test memo_size(full) == 3^10
    @test Base.summarysize(space) == before
    # explain and classify keep their memo for the one call.
    explain(space, (p1 = 2, p2 = 2))
    UnitTestDesign.classify(space, [(p1 = 2, p2 = 2), (p3 = 1,)])
    @test Base.summarysize(space) == before
    context = UnitTestDesign.FeasibilityContext(space)
    idx = case_indices(space, (p1 = 2, p2 = 2))
    f, _ = UnitTestDesign.feasibility_for(context, idx)
    @test memo_size(f) == memo_size(context) == 0
    UnitTestDesign.explain_partial(f, idx)
    @test memo_size(f) == memo_size(context) > 0
    @test memo_size(UnitTestDesign.FeasibilityContext(space)) == 0
end
