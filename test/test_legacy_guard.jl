using Test
using TestItemRunner

# The former guard on generation over wrapper values (plan Phase 2 step 2,
# contract §0.2): until Phase 6, generation over a domain with an Invalid or
# Partition value was an explicit unsupported-feature error. Negative
# generation and partitions replaced it (plan Phase 6 steps 1 and 2); the
# calls the guard refused now generate. Before the guard, the 0.4 engines
# returned rows with two Invalid values; none of these calls may (§5.7).

@testitem "legacy guard: generation over Invalid and Partition values now works (§4, §5, §6)" begin
    invalid = Any[1, Invalid(0)]
    tiny = Any[Partition(:tiny, Returns(1e-9)), 1.0]
    calls = [
        () -> all_pairs(invalid, invalid),
        () -> all_pairs([1, 2], [3, 4], invalid; engine = GND()),
        () -> all_values([1, 2], tiny),
        () -> all_triples([1, 2], invalid, [3, 4]),
        () -> covering([1, 2], invalid; strength = 1),
        () -> full_factorial([1, 2], [3, 4], invalid),
        () -> full_factorial(tiny, [3, 4]),
        () -> excursions([1, 2], invalid, [:a, :b]; distance = 2),
        () -> excursions(tiny, [1, 2]),
        () -> all_pairs((n = invalid, m = [1, 2])),
        () -> all_pairs(TestSpace((size = tiny, m = [1, 2]))),
    ]
    for call in calls
        cases = call()
        @test !isempty(cases)
        @test all(row -> count(x -> x isa Invalid, values(row)) <= 1, cases)
        @test all(row -> isallowed(cases.space, row), cases)
        # Covering results cover both parts; the others are measured at strength 1.
        c = cases.strategy === :covering ? coverage(cases) : coverage(cases; strength = 1)
        @test iscomplete(c) || cases.strategy === :excursion
    end
    # Two invalid parameters: every negative target at strength 2, never both at once.
    pairs = all_pairs(invalid, invalid)
    @test collect(pairs) == [(1, 1), (Invalid(0), 1), (1, Invalid(0))]
    @test pairs.negative_required == 2
    # Partition rows hold the wrapper; realize draws it.
    @test any(r -> r[2] isa Partition, all_values([1, 2], tiny))
    # Named spaces, a full factorial with its negative rows last (§7.2).
    @test collect(full_factorial((n = invalid, m = [1, 2]))) ==
          [(n = 1, m = 1), (n = 1, m = 2), (n = Invalid(0), m = 1), (n = Invalid(0), m = 2)]
end


@testitem "legacy guard: ordinary values, including nothing and missing, still generate (§2.9)" begin
    rows = all_pairs([1, nothing], [:a, :b], [nothing, missing])
    @test length(rows) >= 4
    @test any(r -> r[1] === nothing, rows) && any(r -> r[3] === missing, rows)
    @test length(all_values(Any[nothing, :tiny], [1, 2])) == 2
    @test length(full_factorial([1, nothing], [:a, :b], [missing, 2.0])) == 8
    # Two domains reach the public full_factorial.
    @test collect(full_factorial([nothing, 1], [:a, :b])) == [(nothing, :a), (nothing, :b), (1, :a), (1, :b)]
    @test length(excursions([nothing, 1], [2, 3], [:x, :y]; distance = 2)) == 7
end
