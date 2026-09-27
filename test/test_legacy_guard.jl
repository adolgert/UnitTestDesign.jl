using Test
using TestItemRunner

# The Phase 2 guard on the positional generators (plan Phase 2 step 2,
# contract §0.2): generation over a domain with an Invalid or Partition value
# is an explicit unsupported-feature error until negative generation lands.
# Pending Phase 6: negative generation replaces this guard, and these tests,
# with real generation over wrapper values (the Phase 6 pending lines of
# test_fixtures.jl).

@testitem "legacy guard: generation rejects Invalid and Partition values (§0.2)" begin
    message(g) = try g(); "no error" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e))" end
    invalid = Any[1, Invalid(0)]
    tiny = Any[Partition(:tiny, Returns(1e-9)), 1.0]
    cases = [
        # Before the guard, this returned rows with two Invalid values.
        (() -> all_pairs(invalid, invalid), "parameter 1 lists Invalid(0)"),
        (() -> all_pairs([1, 2], [3, 4], invalid; engine = GND()), "parameter 3 lists Invalid(0)"),
        (() -> all_values([1, 2], tiny), "parameter 2 lists Partition(:tiny)"),
        (() -> all_triples([1, 2], invalid, [3, 4]), "parameter 2 lists Invalid(0)"),
        (() -> full_factorial([1, 2], [3, 4], invalid), "parameter 3 lists Invalid(0)"),
        (() -> full_factorial(tiny, [3, 4]), "parameter 1 lists Partition(:tiny)"),
        (() -> full_factorial([1, 2], invalid; disallow = (a, b) -> false), "parameter 2 lists Invalid(0)"),
        (() -> pairs_excursion([1, 2], invalid, [:a, :b]), "parameter 2 lists Invalid(0)"),
        (() -> values_excursion(tiny, [1, 2]), "parameter 1 lists Partition(:tiny)"),
    ]
    for (call, position) in cases
        msg = message(call)
        @test occursin(position, msg)
        @test occursin("generation with Invalid or Partition values is not supported yet", msg)
        @test occursin("later release phase", msg)
    end
end


@testitem "legacy guard: ordinary values, including nothing and missing, still generate (§2.9)" begin
    rows = all_pairs([1, nothing], [:a, :b], [nothing, missing])
    @test length(rows) >= 4
    @test any(r -> r[1] === nothing, rows) && any(r -> r[3] === missing, rows)
    @test length(all_values(Any[nothing, :tiny], [1, 2])) == 2
    @test length(full_factorial([1, nothing], [:a, :b], [missing, 2.0])) == 8
    # Two domains reach the public full_factorial.
    @test full_factorial([nothing, 1], [:a, :b]) == [[nothing, :a], [nothing, :b], [1, :a], [1, :b]]
    @test length(pairs_excursion([nothing, 1], [2, 3], [:x, :y])) >= 4
end
