using Test
using TestItemRunner

# The fixture inventory (fixtures.jl), checked against the independent oracle.
# Each item asserts the hand-known facts now. Each `@test_skip` line is an
# engine or production test waiting for a later phase; its comment says
# which. The skipped expressions sketch the future call and are never
# evaluated; `test_space(fixture)` stands for the Phase 2 adapter from a
# fixture to a production `TestSpace`, and `throws(T, f)` for `@test_throws`.

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


@testitem "fixtures: named examples" setup=[Checker] begin
    s = astra_chain.space
    @test valid_rows(s) == [(A = 1, B = 1, C = 1), (A = 2, B = 2, C = 2)]
    @test classify_target(s, (A = 1, C = 2)).status == :implied
    @test classify_target(s, (A = 1, B = 2)).rules == [1]
    @test check_design([], s).ordinary.counts.feasible == 6
    # pending: Phase 2 — explain((A = 1, C = 2)) is infeasible, implied by rules 1 and 2
    @test_skip explain(test_space(astra_chain), (A = 1, C = 2)).rules == [1, 2]
    # pending: Phase 3 — IPOG and GND cover all 6 feasible pairs
    @test_skip complete(check_design(all_pairs(test_space(astra_chain)), astra_chain.space))

    s = fable_solver.space
    @test length(valid_rows(s)) == 5
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (11, 3, 2)
    @test Set(r.ordinary.forbidden) == Set([
        (mode = :fast, solver = :lu) => [1], (mode = :fast, solver = :qr) => [1],
        (mode = :exact, tol = 1e-3) => [2]])
    @test Set(r.ordinary.implied) == Set([(solver = :lu, tol = 1e-3), (solver = :qr, tol = 1e-3)])
    # pending: Phase 2 — classify: 3 direct naming their rules, 2 implied with rules [1, 2]
    @test_skip explain(test_space(fable_solver), (solver = :lu, tol = 1e-3)).rules == [1, 2]
    # pending: Phase 3 — IPOG and GND cover all 11 feasible pairs; IPOG in 5 rows
    @test_skip length(all_pairs(test_space(fable_solver))) == 5
    # pending: Phase 5 — coverage and report agree with the checker
    @test_skip coverage(valid_rows(fable_solver.space), test_space(fable_solver)).covered == 11

    s = opus_gpu.space
    @test length(valid_rows(s)) == 7
    @test classify_target(s, (os = :windows, gpu = true)).status == :implied
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (13, 2, 1)
    # pending: Phase 2 — explain((os = :windows, gpu = true)) is infeasible with rules [1, 2]
    @test_skip explain(test_space(opus_gpu), (os = :windows, gpu = true)).rules == [1, 2]
    # pending: Phase 3 — both engines cover all 13 feasible pairs (issue #51)
    @test_skip complete(check_design(all_pairs(test_space(opus_gpu); engine = GND()), opus_gpu.space))
end


@testitem "fixtures: disconnected components" setup=[Checker] begin
    s = disconnected_unsat.space
    @test isempty(valid_rows(s))
    @test classify_target(s, (free = 1,)).status == :implied
    @test classify_target(s, (x = 1, y = 1)).rules == [1]
    @test classify_target(s, (x = 1, y = 2)).rules == [2]
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (0, 4, 12)
    @test complete(r)  # nothing is required, so the empty design is complete (§1.24)
    # pending: Phase 2 — completable((free = 1,)) is proven infeasible by the {x, y} component
    @test_skip explain(test_space(disconnected_unsat), (free = 1,)).outcome == :infeasible
    # pending: Phase 3 — all_pairs returns no rows and reports every target excluded
    @test_skip isempty(all_pairs(test_space(disconnected_unsat)))

    s = disconnected_witness.space
    rows = valid_rows(s)
    @test rows == [(a = 3, b = 3, c = :y, d = :y, e = 1), (a = 3, b = 3, c = :y, d = :y, e = 2)]
    # The witness needs the last value of a, b, c and d, never the first.
    @test all(r -> r.a != first(s.domains[1]) && r.c != first(s.domains[3]), rows)
    @test classify_target(s, (e = 1,)).status == :required
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (14, 11, 32)
    # pending: Phase 2 — the witness for (e = 1,) combines both components
    @test_skip explain(test_space(disconnected_witness), (e = 1,)).witness == rows[1]
    # pending: Phase 3 — IPOG and GND return only rows with a = b = 3 and c = d = :y
    @test_skip complete(check_design(all_pairs(test_space(disconnected_witness)), disconnected_witness.space))

    s = whole_case_connects.space
    @test valid_rows(s) == [(a = 3, b = 3, c = :y, d = :y, e = 2)]
    @test classify_target(s, (e = 1,)).status == :implied
    @test classify_target(s, (e = 2,)).status == :required
    @test classify_target(s, (c = :y, e = 1)).status == :implied
    @test classify_target(s, (a = 3, b = 3, c = :y, d = :y, e = 1)).rules == [3]
    # pending: Phase 2 — explain((e = 1,)) is infeasible with rules [2, 3]
    @test_skip explain(test_space(whole_case_connects), (e = 1,)).rules == [2, 3]
    # pending: Phase 3 — generation returns the single valid row
    @test_skip collect(all_pairs(test_space(whole_case_connects))) == valid_rows(whole_case_connects.space)
end


@testitem "fixtures: limit exhaustion" setup=[Checker] begin
    s = limit_exhaustion.space
    @test valid_rows(s) == [NamedTuple{Tuple(s.names)}(ntuple(_ -> 4, 8))]
    r = check_design([], s)
    @test (r.ordinary.counts.feasible, r.ordinary.counts.forbidden, r.ordinary.counts.implied) == (28, 0, 420)
    @test limit_exhaustion.request.small_limit == 1
    # pending: Phase 2 — explain with feasibility_limit = 1 is unknown; the default finds the witness
    @test_skip explain(test_space(limit_exhaustion), (x1 = 4,); feasibility_limit = 1).outcome == :unknown
    # pending: Phase 3 — generation with limit 1 throws ResourceLimitError; the retry succeeds
    @test_skip throws(ResourceLimitError, () -> all_pairs(test_space(limit_exhaustion); feasibility_limit = 1))
    # pending: Phase 5 — coverage with limit 1 lists unknown targets and claims no percentage
    @test_skip !complete(coverage([], test_space(limit_exhaustion); feasibility_limit = 1))
end


@testitem "fixtures: greedy dead ends" setup=[Checker] begin
    using Combinatorics: combinations
    using Random
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

        generate = k == 2 ? all_pairs : all_triples
        # The legacy defect (issue #51): the 0.4 IPOG throws on a greedy dead
        # end. Phase 3 replaces this with a @test that its design is complete.
        @test_throws BoundsError generate(f.legacy.domains...; disallow = f.legacy.disallow, engine = IPOG())
        # The 0.4 GND completes these problems, under a watchdog.
        watched = budgeted(f.legacy.disallow, 20_000_000, f)
        design = generate(f.legacy.domains...; disallow = watched, engine = GND(rng = Xoshiro(0)))
        @test complete(check_design(design, s; strength = k))
        # pending: Phase 3 — IPOG covers every feasible target without throwing
        @test_skip complete(check_design(generate(test_space(f); engine = IPOG()), s; strength = k))
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
    # pending: Phase 2 — TestSpace keeps 1 and 1.0 as two choices and nothing as a value
    @test_skip length(test_space(heterogeneous_values).values[1]) == 2
    # pending: Phase 4 — generated rows keep Int, Float64, Nothing, Symbol and String values
    @test_skip Set(typeof(r.x) for r in all_pairs(test_space(heterogeneous_values))) == Set([Int, Float64])
    # pending: Phase 5 — coverage of the 3 valid rows is 7 of 7, keyed by identity
    @test_skip coverage(valid_rows(heterogeneous_values.space), test_space(heterogeneous_values)).covered == 7
end


@testitem "fixtures: partial seeds" setup=[Checker] begin
    s = partial_seeds.space
    completions(seed) = filter(r -> all(same_value(r[k], v) for (k, v) in pairs(seed)), valid_rows(s))
    @test completions(only(partial_seeds.request.completable)) == [(mode = :exact, solver = :lu, tol = 1e-6)]
    @test isempty(completions(only(partial_seeds.request.infeasible)))
    @test classify_target(s, only(partial_seeds.request.infeasible)).status == :implied
    r = check_design(partial_seeds.request.violating, s)
    @test only(r.ordinary.rejected).rules == [1]
    # pending: Phase 4 — (solver = :lu,) is completed in place and comes first
    @test_skip first(all_pairs(test_space(partial_seeds); must_include = [(solver = :lu,)])) ==
               (mode = :exact, solver = :lu, tol = 1e-6)
    # pending: Phase 4 — an infeasible partial row is an error carrying its explanation
    @test_skip throws(ArgumentError, () -> all_pairs(test_space(partial_seeds); must_include = [(solver = :lu, tol = 1e-3)]))
    # pending: Phase 4 — a complete row violating rule 1 is an error naming it
    @test_skip throws(ArgumentError, () -> all_pairs(test_space(partial_seeds);
                                                     must_include = [(mode = :fast, solver = :lu, tol = 1e-6)]))
end


@testitem "fixtures: overlapping stronger groups" setup=[Checker] begin
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
    # pending: Phase 3 — ipog_multi_way and GND cover all 35 targets and leave wayness unmutated
    @test_skip complete(check_design(all_pairs(f.legacy.domains...; disallow = f.legacy.disallow,
                                               wayness = f.legacy.wayness()), f.space; stronger = f.request.stronger))
    # pending: Phase 4 — covering(space; stronger) covers the union; the caller's vector is unchanged
    @test_skip complete(check_design(covering(test_space(f); stronger = f.request.stronger), f.space;
                                     stronger = f.request.stronger))
end


@testitem "fixtures: wrappers" setup=[Checker] begin
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
    # pending: Phase 2 — TestSpace accepts 1 and Invalid(1) in one domain
    @test_skip length(test_space(invalid_beside_ordinary).values[1]) == 3
    # pending: Phase 6 — all_pairs covers 9 ordinary pairs and 4 negative targets, reported separately
    @test_skip coverage(all_pairs(test_space(invalid_beside_ordinary))).negative.covered == 4
    # pending: Phase 6 — must_include = [(n = Invalid(1),)] completes as a negative row
    @test_skip hasinvalid(first(all_pairs(test_space(invalid_beside_ordinary); must_include = f.request.negative_seed)))

    f = partition_names
    s = f.space
    @test length(valid_rows(s)) == 8
    @test valid_rows(s)[1].size isa CheckPartition
    r = check_design([], s)
    @test r.ordinary.forbidden == [(size = :tiny, mode = :b) => [1]]
    @test classify_target(s, (size = :tiny, mode = :tiny)).status == :required
    # pending: Phase 2 — TestSpace accepts the space and the rule receives :tiny
    @test_skip explain(test_space(partition_names), (size = :tiny, mode = :b)).outcome == :forbidden
    # pending: Phase 6 — generated rows hold the Partition wrappers; realize draws each once
    @test_skip all(r -> !(r.size isa Symbol), all_pairs(test_space(partition_names)))
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
    # pending: Phase 6 — the negative must-include row is accepted: it is the whole result
    @test_skip collect(all_pairs(test_space(f); must_include = [(a = Invalid(0), b = 1)])) == [(a = Invalid(0), b = 1)]
    # pending: Phase 6 — the ordinary must-include row is an error naming rule 1
    @test_skip throws(ArgumentError, () -> all_pairs(test_space(f); must_include = f.request.ordinary_seed))
end


@testitem "fixtures: bench12 constrained benchmark" setup=[Checker] begin
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

    # Legacy baseline: the 0.4 IPOG throws on the implied pair (issue #51).
    # Phase 3 replaces these with @test that each design is complete. The 0.4
    # GND never returns here, so it is not run.
    @test_throws BoundsError all_pairs(f.legacy.domains...; disallow = f.legacy.disallow, engine = IPOG())
    @test_throws BoundsError all_triples(f.legacy.domains...; disallow = f.legacy.disallow, engine = IPOG())
    # pending: Phase 2 — explain((p1 = 2, p2 = 2)) is infeasible with rules [1, 2]
    @test_skip explain(test_space(bench12), (p1 = 2, p2 = 2)).rules == [1, 2]
    # pending: Phase 3 — IPOG and GND cover all 586 feasible pairs and 5702 feasible triples
    @test_skip complete(check_design(all_pairs(test_space(bench12)), bench12.space))
    @test_skip complete(check_design(all_triples(test_space(bench12); engine = GND()), bench12.space; strength = 3))
end


@testitem "fixtures: rejected inputs" setup=[Checker] begin
    for f in (invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
              partition_symbol_collision, duplicate_partition_name)
        @test f.space === nothing
        @test f.legacy === nothing
        @test_throws ArgumentError CheckSpace(f.input...)
    end
    # pending: Phase 2 — TestSpace rejects each of these five inputs with an ArgumentError naming the parameter
    @test_skip all(f -> throws(ArgumentError, () -> test_space(f)),
                   (invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
                    partition_symbol_collision, duplicate_partition_name))
end
