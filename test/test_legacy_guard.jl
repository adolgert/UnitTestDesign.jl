using Test
using TestItemRunner

# The guard on generation over wrapper values (plan Phase 2 step 2, contract
# §0.2): generation over a domain with an Invalid or Partition value is an
# explicit unsupported-feature error until negative generation lands. Every
# generation call reaches it through the Request, which names the parameter:
# `p2` for a positional call, the parameter's name otherwise.
# Pending Phase 6: negative generation replaces this guard, and these tests,
# with real generation over wrapper values (the Phase 6 pending lines of
# test_fixtures.jl).

@testitem "legacy guard: generation rejects Invalid and Partition values (§0.2)" begin
    message(g) = try g(); "no error" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e))" end
    invalid = Any[1, Invalid(0)]
    tiny = Any[Partition(:tiny, Returns(1e-9)), 1.0]
    cases = [
        # Before the guard, this returned rows with two Invalid values.
        (() -> all_pairs(invalid, invalid), "parameter `p1` has an Invalid value"),
        (() -> all_pairs([1, 2], [3, 4], invalid; engine = GND()), "parameter `p3` has an Invalid value"),
        (() -> all_values([1, 2], tiny), "parameter `p2` has a Partition value"),
        (() -> all_triples([1, 2], invalid, [3, 4]), "parameter `p2` has an Invalid value"),
        (() -> covering([1, 2], invalid; strength = 1), "parameter `p2` has an Invalid value"),
        (() -> full_factorial([1, 2], [3, 4], invalid), "parameter `p3` has an Invalid value"),
        (() -> full_factorial(tiny, [3, 4]), "parameter `p1` has a Partition value"),
        (() -> excursions([1, 2], invalid, [:a, :b]; distance = 2), "parameter `p2` has an Invalid value"),
        (() -> excursions(tiny, [1, 2]), "parameter `p1` has a Partition value"),
        # Named spaces name the parameter.
        (() -> all_pairs((n = invalid, m = [1, 2])), "parameter `n` has an Invalid value"),
        (() -> all_pairs(TestSpace((size = tiny, m = [1, 2]))), "parameter `size` has a Partition value"),
    ]
    for (call, expected) in cases
        msg = message(call)
        @test occursin(expected, msg)
        @test occursin("generation with Invalid or Partition values is not supported yet", msg)
        @test occursin("(contract §0.2)", msg)
    end
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
