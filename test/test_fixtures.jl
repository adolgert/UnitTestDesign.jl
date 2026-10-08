using Test
using TestItemRunner

# The fixture inventory (fixtures.jl), checked against the independent oracle.
# Each item asserts the hand-known facts now. `test_space(fixture)` is the
# adapter from a fixture to a production `TestSpace` (fixture_model.jl), and
# the "Phase 2" lines ask the production model the fixture's question. The
# "Phase 3" lines generate with both engines through the internal request,
# `gen(engine, space; kwargs...)` below, until Phase 4 brings `all_pairs` and
# `covering` over a `TestSpace`. The "Phase 6" lines, pending until
# negative generation and partitions landed, now run.

@testsnippet FixtureGen begin
    using UnitTestDesign: Request, generate, to_cases
    "The named cases `engine` generates for `space` (Phase 4 spells this `covering`)."
    gen(engine, space; kwargs...) = (r = Request(space; kwargs...); to_cases(r, generate(engine, r).matrix))
    "Both engines, each with its default seed."
    ENGINES = (IPOG(), GND())
end

@testitem "fixtures: inventory" setup=[Checker] begin
    @test allunique(f.name for f in FIXTURES)
    @test all(f -> !isempty(f.clauses) && !isempty(f.pending), FIXTURES)
    @test all(f -> all(p -> 2 <= p.first <= 6, f.pending), FIXTURES)

    # Every cited clause exists in the contract.
    contract = read(joinpath(@__DIR__, "..", "docs", "src", "dev", "contract.md"), String)
    for f in FIXTURES, clause in f.clauses
        @test occursin("**$clause**", contract)
    end

    # Where a fixture has 0.4 inputs, its disallow agrees with the checker on
    # every complete row.
    for f in FIXTURES
        f.legacy === nothing && continue
        valid = Set(Tuple(r) for r in valid_rows(f.space))
        @test all(f.legacy.disallow(row...) == !(row in valid)
                  for row in Iterators.product(f.legacy.domains...))
    end
end


@testitem "fixtures: named examples" setup=[Checker, FixtureGen] begin
    s = astra_chain.space
    @test valid_rows(s) == [(A = 1, B = 1, C = 1), (A = 2, B = 2, C = 2)]
    @test classify_target(s, (A = 1, C = 2)).status == :implied
    @test classify_target(s, (A = 1, B = 2)).rules == [1]
    @test check_design([], s).ordinary.counts.feasible == 6
    # Phase 2 — explain((A = 1, C = 2)) is infeasible, implied by rules 1 and 2
    @test explain(test_space(astra_chain), (A = 1, C = 2)).rules == [1, 2]
    # Phase 3 — IPOG and GND cover all 6 feasible pairs
    for engine in ENGINES
        @test complete(check_design(gen(engine, test_space(astra_chain)), astra_chain.space))
    end

    s = fable_solver.space
    @test length(valid_rows(s)) == 5
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (11, 3, 2)
    @test Set(r.ordinary.forbidden) == Set([
        (mode = :fast, solver = :lu) => [1], (mode = :fast, solver = :qr) => [1],
        (mode = :exact, tol = 1e-3) => [2]])
    @test Set(r.ordinary.implied) == Set([(solver = :lu, tol = 1e-3), (solver = :qr, tol = 1e-3)])
    # Phase 2 — classify: 3 direct naming their rules, 2 implied with rules [1, 2]
    @test explain(test_space(fable_solver), (solver = :lu, tol = 1e-3)).rules == [1, 2]
    excluded = vcat(first.(r.ordinary.forbidden), r.ordinary.implied)
    @test [(c.status, c.rules) for c in UnitTestDesign.classify(test_space(fable_solver), excluded)] ==
          [(:forbidden, [1]), (:forbidden, [1]), (:forbidden, [2]), (:implied, [1, 2]), (:implied, [1, 2])]
    # Phase 3 — IPOG and GND cover all 11 feasible pairs; IPOG in 5 rows
    for engine in ENGINES
        check = check_design(gen(engine, test_space(fable_solver)), fable_solver.space)
        @test complete(check) && check.ordinary.counts.covered == 11
    end
    @test length(gen(IPOG(), test_space(fable_solver))) == 5
    # Phase 5 — coverage agrees with the checker: 11 of 11, 3 forbidden, 2 implied
    c = coverage(valid_rows(fable_solver.space), test_space(fable_solver))
    @test iscomplete(c) && c.ordinary.covered == c.ordinary.feasible == 11
    @test [(e.status, e.rules) for e in c.ordinary.excluded] ==
          [(:forbidden, [1]), (:forbidden, [1]), (:forbidden, [2]), (:implied, [1, 2]), (:implied, [1, 2])]

    s = opus_gpu.space
    @test length(valid_rows(s)) == 7
    @test classify_target(s, (os = :windows, gpu = true)).status == :implied
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (13, 2, 1)
    # Phase 2 — explain((os = :windows, gpu = true)) is infeasible with rules [1, 2]
    @test explain(test_space(opus_gpu), (os = :windows, gpu = true)).rules == [1, 2]
    # Phase 3 — both engines cover all 13 feasible pairs (issue #51)
    for engine in ENGINES
        check = check_design(gen(engine, test_space(opus_gpu)), opus_gpu.space)
        @test complete(check) && check.ordinary.counts.covered == 13
    end
end


@testitem "fixtures: disconnected components" setup=[Checker, FixtureGen] begin
    s = disconnected_unsat.space
    @test isempty(valid_rows(s))
    @test classify_target(s, (free = 1,)).status == :implied
    @test classify_target(s, (x = 1, y = 1)).rules == [1]
    @test classify_target(s, (x = 1, y = 2)).rules == [2]
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (0, 4, 12)
    @test complete(r)  # nothing is required, so the empty design is complete (§1.24)
    # Phase 2 — completable((free = 1,)) is proven infeasible by the {x, y} component
    @test explain(test_space(disconnected_unsat), (free = 1,)).outcome == :infeasible
    # Phase 3 — generation returns no rows and reports every target excluded
    for engine in ENGINES
        request = Request(test_space(disconnected_unsat))
        design = generate(engine, request)
        @test isempty(to_cases(request, design.matrix))
        @test design.required == design.covered == 0
        @test length(design.excluded) == length(UnitTestDesign.targets(request)) == 16
        @test count(e -> e.status == :forbidden, design.excluded) == 4
        @test count(e -> e.status == :implied, design.excluded) == 12
    end

    s = disconnected_witness.space
    rows = valid_rows(s)
    @test rows == [(a = 3, b = 3, c = :y, d = :y, e = 1), (a = 3, b = 3, c = :y, d = :y, e = 2)]
    # The witness needs the last value of a, b, c and d, never the first.
    @test all(r -> r.a != first(s.domains[1]) && r.c != first(s.domains[3]), rows)
    @test classify_target(s, (e = 1,)).status == :required
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (14, 11, 32)
    # Phase 2 — the witness for (e = 1,) combines both components
    @test explain(test_space(disconnected_witness), (e = 1,)).witness == rows[1]
    # Phase 3 — IPOG and GND return only rows with a = b = 3 and c = d = :y
    for engine in ENGINES
        cases = gen(engine, test_space(disconnected_witness))
        @test complete(check_design(cases, disconnected_witness.space))
        @test all(c -> c.a == c.b == 3 && c.c == c.d == :y, cases)
    end

    s = whole_case_connects.space
    @test valid_rows(s) == [(a = 3, b = 3, c = :y, d = :y, e = 2)]
    @test classify_target(s, (e = 1,)).status == :implied
    @test classify_target(s, (e = 2,)).status == :required
    @test classify_target(s, (c = :y, e = 1)).status == :implied
    @test classify_target(s, (a = 3, b = 3, c = :y, d = :y, e = 1)).rules == [3]
    # Phase 2 — explain((e = 1,)) is infeasible with rules [2, 3]
    @test explain(test_space(whole_case_connects), (e = 1,)).rules == [2, 3]
    # Phase 3 — generation returns the single valid row
    for engine in ENGINES
        @test gen(engine, test_space(whole_case_connects)) == valid_rows(whole_case_connects.space)
    end
end


@testitem "fixtures: limit exhaustion" setup=[Checker, FixtureGen] begin
    s = limit_exhaustion.space
    @test valid_rows(s) == [NamedTuple{Tuple(s.names)}(ntuple(_ -> 4, 8))]
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (28, 0, 420)
    @test limit_exhaustion.request.small_limit == 1
    # Phase 2 — explain with feasibility_limit = 1 is unknown; the default finds the witness
    @test explain(test_space(limit_exhaustion), (x1 = 4,); feasibility_limit = 1).outcome == :unknown
    @test explain(test_space(limit_exhaustion), (x1 = 4,)).witness == only(valid_rows(s))
    # Phase 3 — generation with limit 1 throws ResourceLimitError; the retry succeeds
    for engine in ENGINES
        @test_throws ResourceLimitError gen(engine, test_space(limit_exhaustion); feasibility_limit = 1)
        @test gen(engine, test_space(limit_exhaustion)) == valid_rows(s)
    end
    # Phase 5 — coverage with limit 1 lists unknown targets and claims no percentage
    c = coverage([], test_space(limit_exhaustion); feasibility_limit = limit_exhaustion.request.small_limit)
    @test !iscomplete(c) && length(c.ordinary.unknown) == 448
    @test !occursin('%', sprint(show, MIME"text/plain"(), c)) && !occursin("complete", sprint(show, MIME"text/plain"(), c))
    @test iscomplete(coverage(valid_rows(s), test_space(limit_exhaustion)))
end


@testitem "fixtures: greedy dead ends" setup=[Checker, FixtureGen] begin
    using Combinatorics: combinations
    "The `k`-way sub-combinations of a partial row."
    subrows(t, k) = [NamedTuple{Tuple(ks)}(Tuple(t[x] for x in ks)) for ks in combinations(collect(keys(t)), k)]

    counts = Dict(
        :dead_end_pairwise_1 => (29, 42, 2), :dead_end_pairwise_2 => (63, 59, 3),
        :dead_end_threeway_1 => (81, 167, 4), :dead_end_threeway_2 => (2672, 1284, 5))
    for f in (dead_end_pairwise_1, dead_end_pairwise_2, dead_end_threeway_1, dead_end_threeway_2)
        s, k = f.space, f.request.strength
        r = check_design([], s; strength = k)
        # No target is implied: each is feasible or directly forbidden.
        @test r.ordinary.counts.implied == 0
        @test (length(valid_rows(s)), r.ordinary.counts.feasible, r.ordinary.counts.forbidden) == counts[f.name]
        # The partial row the 0.4 IPOG cannot complete is infeasible, although
        # each of its k-way sub-combinations is feasible.
        dead = f.request.dead_end
        @test classify_target(s, dead).status == :implied
        @test all(t -> classify_target(s, t).status == :required, subrows(dead, k))

        # Phase 3 — the 0.4 IPOG threw a BoundsError on each of these (issue
        # #51), and the 0.4 GND completed them. Both engines now cover every
        # feasible target.
        for engine in ENGINES
            @test complete(check_design(gen(engine, test_space(f); strength = k), s; strength = k))
        end
    end
end


@testitem "fixtures: heterogeneous values" setup=[Checker] begin
    same_list(a, b) = length(a) == length(b) && all(same_target(x, y) for (x, y) in zip(a, b))
    s = heterogeneous_values.space
    @test heterogeneous_values.legacy === nothing  # nothing is the 0.4 sentinel
    @test same_list(valid_rows(s), [
        (x = 1, y = nothing, z = :s), (x = 1, y = :a, z = :s), (x = 1.0, y = :a, z = :s)])
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (7, 3, 2)
    @test same_list(first.(r.ordinary.forbidden),
        [(x = 1.0, y = nothing), (x = 1, z = "s"), (x = 1.0, z = "s")])
    @test last.(r.ordinary.forbidden) == [[1], [2], [2]]
    @test same_list(r.ordinary.implied, [(y = nothing, z = "s"), (y = :a, z = "s")])
    @test complete(check_design(valid_rows(s), s))
    # Phase 2 — TestSpace keeps 1 and 1.0 as two choices and nothing as a value
    @test length(test_space(heterogeneous_values).values[1]) == 2
    @test test_space(heterogeneous_values).values[2][1] === nothing
    # Phase 4 — generated rows keep Int, Float64, Nothing, Symbol and String values
    @test Set(typeof(r.x) for r in all_pairs(test_space(heterogeneous_values))) == Set([Int, Float64])
    # Phase 5 — coverage of the 3 valid rows is 7 of 7, keyed by identity: 1 and 1.0 are two values
    c = coverage(valid_rows(heterogeneous_values.space), test_space(heterogeneous_values))
    @test iscomplete(c) && c.ordinary.covered == c.ordinary.feasible == 7
    @test (count(t -> t.x === 1, [e.target for e in c.ordinary.excluded if haskey(e.target, :x)]),
           count(t -> t.x === 1.0, [e.target for e in c.ordinary.excluded if haskey(e.target, :x)])) == (1, 2)
end


@testitem "fixtures: partial seeds" setup=[Checker] begin
    s = partial_seeds.space
    completions(seed) = filter(r -> all(same_value(r[k], v) for (k, v) in pairs(seed)), valid_rows(s))
    @test completions(only(partial_seeds.request.completable)) == [(mode = :exact, solver = :lu, tol = 1e-6)]
    @test isempty(completions(only(partial_seeds.request.infeasible)))
    @test classify_target(s, only(partial_seeds.request.infeasible)).status == :implied
    r = check_design(partial_seeds.request.violating, s)
    @test only(r.ordinary.rejected).rules == [1]
    # Phase 4 — (solver = :lu,) is completed in place and comes first
    @test first(all_pairs(test_space(partial_seeds); must_include = [(solver = :lu,)])) ==
          (mode = :exact, solver = :lu, tol = 1e-6)
    # Phase 4 — an infeasible partial row is an error carrying its explanation
    @test_throws ArgumentError all_pairs(test_space(partial_seeds); must_include = [(solver = :lu, tol = 1e-3)])
    # Phase 4 — a complete row violating rule 1 is an error naming it
    @test_throws ArgumentError all_pairs(test_space(partial_seeds);
                                         must_include = [(mode = :fast, solver = :lu, tol = 1e-6)])
end


@testitem "fixtures: overlapping stronger groups" setup=[Checker, FixtureGen] begin
    f = overlapping_groups
    r = check_design([], f.space; stronger = f.request.stronger)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (35, 5, 0)
    @test Set(r.ordinary.forbidden) == Set([
        (b = 2, c = 2) => [1],
        (a = 1, b = 2, c = 2) => [1], (a = 2, b = 2, c = 2) => [1],
        (b = 2, c = 2, d = 1) => [1], (b = 2, c = 2, d = 2) => [1]])
    twice = check_design([], f.space; stronger = f.request.stronger_twice)
    @test twice.ordinary.feasible == r.ordinary.feasible
    @test f.legacy.wayness() == Dict(3 => [[1, 2, 3], [2, 3, 4]])
    @test f.legacy.wayness() !== f.legacy.wayness()
    # Phase 3 — IPOG and GND cover all 35 targets and leave the
    # caller's groups unmutated
    for engine in ENGINES, stronger in (f.request.stronger, f.request.stronger_twice)
        given = deepcopy(stronger)
        cases = gen(engine, test_space(f); stronger = given)
        @test complete(check_design(cases, f.space; stronger = f.request.stronger))
        @test given == stronger
    end
    wayness = f.legacy.wayness()
    @test length(all_pairs(f.legacy.domains...; wayness)) >= 8
    @test wayness == f.legacy.wayness()
    # Phase 4 — covering(space; stronger) covers the union; the caller's vector is unchanged
    @test complete(check_design(covering(test_space(f); stronger = f.request.stronger), f.space;
                                stronger = f.request.stronger))
end


@testitem "fixtures: wrappers" setup=[Checker] begin
    using Random: Xoshiro
    f = invalid_beside_ordinary
    s = f.space
    bad = CheckInvalid(1)
    @test length(s.domains[1]) == 3  # 1 and Invalid(1) are two choices
    @test length(valid_rows(s)) == 4
    @test negative_rows(s) == [(n = bad, m = :a, k = :x), (n = bad, m = :b, k = :x), (n = bad, m = :b, k = :y)]
    @test negative_targets(s) == [(n = bad, m = :a), (n = bad, m = :b), (n = bad, k = :x), (n = bad, k = :y)]
    @test negative_targets(s; strength = 1) == [(n = bad,)]
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (9, 2, 1)
    seed = only(f.request.negative_seed)
    @test length(filter(row -> same_value(row.n, seed.n), negative_rows(s))) == 3
    # Phase 2 — TestSpace accepts 1 and Invalid(1) in one domain
    @test length(test_space(invalid_beside_ordinary).values[1]) == 3
    # Phase 6 — all_pairs covers 9 ordinary pairs and 4 negative targets, reported separately
    c = coverage(all_pairs(test_space(invalid_beside_ordinary)))
    @test (c.ordinary.covered, c.ordinary.feasible, c.negative.covered, c.negative.feasible) == (9, 9, 4, 4)
    # Phase 6 — must_include = [(n = Invalid(1),)] completes as a negative row
    negative_seed = [(n = Invalid(1),)]   # f.request.negative_seed in production values
    @test hasinvalid(first(all_pairs(test_space(invalid_beside_ordinary); must_include = negative_seed)))

    f = partition_names
    s = f.space
    @test length(valid_rows(s)) == 8
    @test valid_rows(s)[1].size isa CheckPartition
    r = check_design([], s)
    @test r.ordinary.forbidden == [(size = :tiny, mode = :b) => [1]]
    @test classify_target(s, (size = :tiny, mode = :tiny)).status == :required
    # Phase 2 — TestSpace accepts the space and the rule receives :tiny
    @test explain(test_space(partition_names), (size = :tiny, mode = :b)).outcome == :forbidden
    # Phase 6 — generated rows hold the Partition wrappers; realize draws each once
    cases = all_pairs(test_space(partition_names))
    @test all(r -> !(r.size isa Symbol), cases) && any(r -> r.size isa Partition, cases)
    @test all(((c, r),) -> c.size isa Partition ? r.size === c.size.name : r.size === c.size,
              zip(cases, realize(cases; rng = Xoshiro(1))))   # the model draws Returns(name)
end


@testitem "fixtures: no ordinary row, one negative row" setup=[Checker] begin
    f = empty_ordinary_negative_seed
    s = f.space
    bad = CheckInvalid(0)
    @test isempty(valid_rows(s))
    @test negative_rows(s) == [(a = bad, b = 1)]
    @test negative_targets(s; strength = 1) == [(a = bad,)]
    @test negative_targets(s) == [(a = bad, b = 1)]
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (0, 1, 0)
    @test r.ordinary.forbidden == [(a = 1, b = 1) => [1]]
    @test complete(r.ordinary) && !complete(r.negative)
    # The negative row is valid and covers the negative targets at strengths 1 and 2.
    @test complete(check_design(f.request.negative_seed, s; strength = 1))
    @test complete(check_design(f.request.negative_seed, s))
    # The ordinary row violates rule 1.
    r = check_design(f.request.ordinary_seed, s)
    @test only(r.ordinary.rejected).reason == :violates_rule
    @test only(r.ordinary.rejected).rules == [1]
    # Phase 6 — the negative must-include row is accepted: it is the whole result
    @test collect(all_pairs(test_space(f); must_include = [(a = Invalid(0), b = 1)])) == [(a = Invalid(0), b = 1)]
    # Phase 6 — the ordinary must-include row is an error naming rule 1
    @test_throws ArgumentError all_pairs(test_space(f); must_include = f.request.ordinary_seed)
    err = try all_pairs(test_space(f); must_include = f.request.ordinary_seed) catch e; e end
    @test occursin("breaks rule 1", err.msg)
end


@testitem "fixtures: bench12 constrained benchmark" setup=[Checker, FixtureGen] begin
    f = bench12
    s = f.space
    recorded = f.request.recorded
    # The replacement matches the statistics recorded for Fable's example.
    @test length(s.names) == 12
    @test count(r -> length(r[1]) == 3, s.rules) == 1 && length(s.rules) == 4
    @test prod(length, s.domains) == recorded.product
    @test length(valid_rows(s)) == recorded.valid
    r = check_design([], s; strength = 2)
    c = r.ordinary.counts
    @test c.feasible + c.forbidden + c.implied == recorded.pairs
    @test (c.feasible, c.forbidden, c.implied) == (586, recorded.forbidden, recorded.implied)
    @test r.ordinary.implied == [recorded.implied_pair]
    @test r.ordinary.forbidden == [(p1 = 2, p9 = 2) => [1], (p5 = 1, p6 = 1) => [3], (p7 = 1, p10 = 1) => [4]]
    r = check_design([], s; strength = 3)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (5702, 92, 26)
    @test all(t -> t.p1 == 2 && t.p2 == 2, r.ordinary.implied)

    # Phase 2 — explain((p1 = 2, p2 = 2)) is infeasible with rules [1, 2]
    @test explain(test_space(bench12), (p1 = 2, p2 = 2)).rules == [1, 2]
    # Phase 3 — IPOG and GND cover all 586 feasible pairs and 5702 feasible
    # triples. The 0.4 IPOG threw a BoundsError on the implied pair at both
    # strengths, and the 0.4 GND never returned (design/benchmark_procedure.md).
    for (k, feasible) in ((2, 586), (3, 5702)), engine in ENGINES
        cases = gen(engine, test_space(bench12); strength = k)
        check = check_design(cases, bench12.space; strength = k)
        @test complete(check) && check.ordinary.counts.covered == feasible
        @test !any(c -> c.p1 == 2 && c.p2 == 2, cases)
    end
end


@testitem "fixtures: rejected inputs" setup=[Checker] begin
    for f in (invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
              partition_symbol_collision, duplicate_partition_name)
        @test f.space === nothing
        @test f.legacy === nothing
        @test_throws ArgumentError CheckSpace(f.input...)
    end
    # Phase 2 — TestSpace rejects each of these five inputs with an ArgumentError
    for f in (invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
              partition_symbol_collision, duplicate_partition_name)
        @test_throws ArgumentError test_space(f)
    end
    # The space's errors name the parameter. A nested wrapper is rejected when
    # the wrapper is built, before it belongs to a parameter (§4.12).
    for (f, name) in ((invalid_only_domain, "`n`"), (partition_symbol_collision, "`size`"),
                      (duplicate_partition_name, "`size`"))
        err = try
            test_space(f)
        catch e
            e
        end
        @test err isa ArgumentError && occursin(name, err.msg)
    end
end
