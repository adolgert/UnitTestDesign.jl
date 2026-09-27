using Test
using TestItemRunner

# Excursions (plan Phase 3 step 4, Phase 4 step 5; contract §7.5–§7.7,
# §7.11): `excursions(input...; from, distance, must_include)`, which returns
# a TestCases. An excursion has one distance and no groups. `build_excursion`
# and the index-space `notes` of the Design are checked below the public
# call; a TestCases carries the notes in values (`base`, `never_appear`).


@testitem "build_excursion: the 0.4 sizes and order" begin
    using UnitTestDesign: build_excursion
    arity = [2, 3, 2, 4]
    base = ones(Int, 4)
    # 1 base + 7 single changes + 17 double changes.
    ex = build_excursion(arity, 2, base, row -> false)
    @test size(ex.matrix) == (4, 25)
    @test ex.dropped == 0
    @test ex.matrix[:, 1] == base
    # Single changes first, by parameter, then pairs, the last parameter fastest.
    @test ex.matrix[:, 2:8] == [2 1 1 1 1 1 1; 1 2 3 1 1 1 1; 1 1 1 2 1 1 1; 1 1 1 1 2 3 4]
    @test ex.matrix[:, 9:11] == [2 2 2; 2 3 1; 1 1 2; 1 1 1]
    @test allunique(eachcol(ex.matrix))
    @test all(count(ex.matrix[:, j] .!= base) <= 2 for j in 1:25)
    # Two rows break the rule; they are dropped and counted.
    ex = build_excursion(arity, 2, base, row -> row[3] == 2 && row[4] > 2)
    @test size(ex.matrix) == (4, 23)
    @test ex.dropped == 2
    # There are no groups: the only widening keyword is gone.
    @test_throws MethodError build_excursion(arity, 2, base, row -> false; groups = [[1, 2, 3] => 3])
    # Distance 0 is the base alone; a distance beyond the parameter count is the full product.
    @test build_excursion(arity, 0, base, row -> false).matrix == reshape(base, 4, 1)
    @test size(build_excursion(arity, 9, base, row -> false).matrix, 2) == prod(arity)
    @test_throws ArgumentError build_excursion(arity, -1, base, row -> false)
    # Another base: each changed parameter takes every other value.
    ex = build_excursion(arity, 1, [2, 3, 1, 4], row -> false)
    @test ex.matrix == [2 1 2 2 2 2 2 2; 3 3 1 2 3 3 3 3; 1 1 1 1 2 1 1 1; 4 4 4 4 4 1 2 3]
end


@testitem "excursions: default and explicit base, distance 1 and 2" setup=[Checker] begin
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    checker = CheckSpace(names, domains)
    space = TestSpace(Pair.(names, domains)...)
    within(case, base, d) = count(k -> case[k] != base[k], keys(base)) <= d

    cases = excursions(space)
    @test collect(cases) == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                             (a = 1, b = :y, c = true), (a = 1, b = :x, c = false)]
    @test (cases.strategy, cases.engine, cases.seed) == (:excursion, :Excursion, nothing)
    @test cases.strength == 0   # an excursion has a distance, not a strength
    @test (cases.required, cases.covered, isempty(cases.excluded), cases.n_must_include) == (0, 0, true, 0)
    @test cases.notes.dropped == 0 && cases.notes.distance == 1
    @test isempty(cases.notes.never_appear)
    # The base is a row of the result's type, the first row.
    @test cases.notes.base === (a = 1, b = :x, c = true) === cases[1]
    @test cases.notes.base isa eltype(cases)
    @test excursions(domains...).notes.base === (1, :x, true)
    @test excursions(domains...; from = [3, :y, false]).notes.base isa Tuple{Int, Symbol, Bool}
    # The same space as a NamedTuple, as pairs, and positionally.
    @test collect(excursions((a = [1, 2, 3], b = [:x, :y], c = [true, false]))) == collect(cases)
    @test collect(excursions(Pair.(names, domains)...)) == collect(cases)
    @test collect(excursions(domains...)) == [Tuple(c) for c in cases]

    base = (a = 3, b = :y, c = false)
    for from in (base, (3, :y, false), [3, :y, false]), d in (1, 2)
        rows = excursions(space; distance = d, from)
        @test rows[1] == base
        @test allunique(rows)
        @test all(c -> within(c, base, d), rows)
        # Every valid row within distance d, and nothing else.
        @test Set(rows) == Set(filter(c -> within(c, base, d), valid_rows(checker)))
        @test length(rows) == (d == 1 ? 1 + 2 + 1 + 1 : 1 + 4 + 2 * 1 + 2 * 1 + 1 * 1)
    end
end


@testitem "excursions: dropped rows and values that never appear (§7.7)" setup=[Checker] begin
    # (b = :y, c = true) is forbidden. From the base (1, :x, true):
    #   distance 1: (2,x,T) (3,x,T) (1,y,T)✗ (1,x,F)          dropped 1, b = :y never appears
    #   distance 2: adds (2,y,T)✗ (3,y,T)✗ (2,x,F) (3,x,F) (1,y,F)   dropped 3
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    checker = CheckSpace(names, domains, [((:b, :c), (b, c) -> b == :y && c == true)])
    space = TestSpace(Pair.(names, domains)...;
        constraints = [forbid((b = :y, c = true); reason = "y needs c off")])

    cases = excursions(space; distance = 1)
    @test collect(cases) == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                             (a = 1, b = :x, c = false)]
    @test cases.notes.dropped == 1
    # never_appear names each missing value: `name => value`.
    @test cases.notes.never_appear == [:b => :y]
    @test cases.notes.never_appear isa Vector{Pair{Symbol, Any}}
    @test cases.notes.base == (a = 1, b = :x, c = true)
    # No covering claim: b = :y is feasible but absent. No row is rejected.
    result = check_design(collect(cases), checker; strength = 1)
    @test result.ordinary.missing == [(b = :y,)]
    @test isempty(result.ordinary.rejected)

    cases = excursions(space; distance = 2)
    @test collect(cases) == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                             (a = 1, b = :x, c = false), (a = 2, b = :x, c = false), (a = 3, b = :x, c = false),
                             (a = 1, b = :y, c = false)]
    @test cases.notes.dropped == 3
    @test isempty(cases.notes.never_appear)
    @test all(c -> c in valid_rows(checker), cases)

    # A base with c = false: the forbidden pair is one change away only through c.
    base = (a = 2, b = :y, c = false)
    cases = excursions(space; distance = 1, from = base)
    @test cases.notes.dropped == 1  # (2, :y, true)
    @test cases.notes.never_appear == [:c => true]
    @test cases.notes.base === base
    @test Set(cases) == Set(filter(c -> count(k -> c[k] != base[k], names) <= 1, valid_rows(checker)))
end


@testitem "excursions (index space): never_appear lists (parameter, position) pairs (§7.7)" begin
    using UnitTestDesign: Request, generate_excursion
    space = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [true, false]);
        constraints = [forbid((b = :y, c = true))])
    request = Request(space)
    @test generate_excursion(request; distance = 1).notes.never_appear == [(2, 2)]
    @test isempty(generate_excursion(request; distance = 2).notes.never_appear)
    @test generate_excursion(request; distance = 1, from = (a = 2, b = :y, c = false)).notes.never_appear == [(3, 1)]
    design = generate_excursion(request; distance = 0)
    @test (design.notes.dropped, design.notes.distance, design.notes.base) == (0, 0, [1, 1, 1])
    @test design.notes.never_appear == [(1, 2), (1, 3), (2, 2), (3, 2)]
    # The public call never passes engine positions; the index form checks them.
    @test_throws ArgumentError generate_excursion(request; from = [1, 3, 1])
    # An excursion has no groups: a request with stronger groups is refused.
    grouped = Request(TestSpace((Symbol(:p, i) => [1, 2] for i in 1:4)...); stronger = [(:p1, :p2, :p3) => 3])
    @test_throws ArgumentError generate_excursion(grouped; distance = 0)
end


@testitem "excursions: a forbidden or partial base is an error naming the cause (§7.6)" begin
    space = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [true, false]);
        constraints = [forbid((b = :y, c = true); reason = "y needs c off"),
                       forbid(:a, :b) do a, b; a == 3 && b == :y end])
    message(f) = try f(); "no error" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError: $e" end
    msg = message(() -> excursions(space; from = (a = 3, b = :y, c = true)))
    @test occursin("breaks", msg)
    @test occursin("rule 1 (y needs c off)", msg)
    @test occursin("rule 2 on (a, b)", msg)
    @test occursin("§7.6", msg)
    msg = message(() -> excursions(space; from = (a = 1, b = :y, c = true)))
    @test occursin("y needs c off", msg) && !occursin("rule 2", msg)
    # A partial base, a value outside the domain, a wrong length.
    @test occursin("complete row", message(() -> excursions(space; from = (a = 1,))))
    @test occursin("`b`", message(() -> excursions(space; from = (a = 1, b = :z, c = true))))
    @test occursin("3 parameters", message(() -> excursions(space; from = (1, :x))))
    @test occursin("`b`", message(() -> excursions(space; from = [1, 3, true])))   # values, not positions
    @test occursin("at least 0", message(() -> excursions(space; distance = -1)))
    # A forbidden base is an error at distance 0 as well.
    @test_throws ArgumentError excursions(space; distance = 0, from = (a = 1, b = :y, c = true))
    # Positional: the base is a tuple of values.
    msg = message(() -> excursions([1, 2], [3, 4]; from = (1, 5)))
    @test occursin("5 is not a value of `p2`", msg)
end


@testitem "excursions: must-include rows first, not repeated (§7.11, §10.5)" begin
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    space = TestSpace(Pair.(names, domains)...; constraints = [forbid((b = :y, c = true))])
    @test length(excursions(space)) == 4

    seeds = [(a = 3, b = :y, c = false), (a = 2, b = :x, c = true), (c = false,), (a = 3, b = :y, c = false)]
    cases = excursions(space; must_include = seeds)
    @test cases.n_must_include == 4
    # The partial row is completed toward the base, (1, :x, true).
    @test cases[1:4] == [seeds[1], seeds[2], (a = 1, b = :x, c = false), seeds[4]]
    # (2, x, T) and (1, x, F) are excursion rows already present: not repeated.
    @test cases[5:end] == [(a = 1, b = :x, c = true), (a = 3, b = :x, c = true)]
    @test cases.notes.dropped == 1
    @test isempty(cases.notes.never_appear)
    @test cases.notes.base == cases[5]   # the base follows the must-include rows

    # Distance 0: the must-include rows and the base, nothing else.
    cases = excursions(space; must_include = seeds, distance = 0)
    @test collect(cases) == [seeds[1], seeds[2], (a = 1, b = :x, c = false), seeds[4], (a = 1, b = :x, c = true)]
    @test (cases.notes.dropped, cases.notes.distance) == (0, 0)
    @test isempty(cases.notes.never_appear)

    # Positional must-include rows are complete tuples or vectors.
    cases = excursions([1, 2, 3], [:x, :y]; must_include = [[3, :y], (2, :y)])
    @test cases[1:2] == [(3, :y), (2, :y)]
    @test collect(cases[3:end]) == [(1, :x), (2, :x), (3, :x), (1, :y)]
end


@testitem "excursions: distance 0 is the base alone (§7.5)" begin
    space = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [true, false]);
        constraints = [forbid((b = :y, c = true))])
    cases = excursions(space; distance = 0)
    @test collect(cases) == [(a = 1, b = :x, c = true)]
    @test (cases.notes.dropped, cases.notes.distance) == (0, 0)
    # In parameter order, then domain order.
    @test cases.notes.never_appear == [:a => 2, :a => 3, :b => :y, :c => false]
    # Positional results name the parameters p1, p2, ...
    @test excursions([1, 2, 3], [:x, :y]; distance = 0).notes.never_appear == [:p1 => 2, :p1 => 3, :p2 => :y]
    from = (a = 2, b = :y, c = false)
    @test collect(excursions(space; distance = 0, from)) == [from]
end


@testitem "excursions: stronger groups are refused; one distance only (§7.5)" begin
    names = [Symbol(:p, i) for i in 1:8]
    space = TestSpace((n => [1, 2] for n in names)...)
    err = try excursions(space; distance = 2, stronger = [(:p1, :p2, :p3, :p4) => 3, (:p6, :p7, :p8) => 3])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test err.msg == "excursions take a single distance; stronger groups apply to covering designs"
    # Even at distance 0 or 1, and whatever the base; positional groups too.
    @test_throws ArgumentError excursions(space; distance = 0, stronger = [(:p1, :p2, :p3) => 3])
    @test_throws ArgumentError excursions(fill([1, 2], 8)...; distance = 1, from = Tuple(fill(2, 8)),
                                          stronger = [(1, 2, 3) => 3])
    # An empty stronger is no group.
    @test length(excursions(space; distance = 2, stronger = [])) == 1 + 8 + 28
    # Excursion distance is not covering strength: strength is not a keyword.
    @test_throws MethodError excursions(space; strength = 2)
end


@testitem "excursions: no row beyond the distance, distance 1, 2 and n (§7.5)" setup=[Checker] begin
    # Five parameters and three rules, one of them a whole-case rule.
    names = [:a, :b, :c, :d, :e]
    domains = [[1, 2, 3], [:x, :y], [true, false], [1, 2], [:p, :q, :r]]
    checker = CheckSpace(names, domains, [
        ((:b, :c), (b, c) -> b == :y && c == true),
        ((:a, :e), (a, e) -> a == 3 && e == :r),
        (Tuple(names), (a, b, c, d, e) -> a + d == 5 && e == :q)])
    space = TestSpace(Pair.(names, domains)...; constraints = [
        forbid((b = :y, c = true)),
        @forbid(a == 3 && e == :r),
        forbid(case -> case.a + case.d == 5 && case.e == :q)])
    valid = valid_rows(checker)
    n = length(names)
    for from in (nothing, (a = 3, b = :y, c = false, d = 2, e = :p)), d in (1, 2, n, n + 2)
        cases = excursions(space; distance = d, from)
        base = cases[1]
        hamming(c) = count(k -> !isequal(c[k], base[k]), names)
        @test maximum(hamming, cases) <= min(d, n)
        # Exactly the valid rows within the distance, each once.
        near = filter(c -> hamming(c) <= d, valid)
        @test Set(cases) == Set(near) && length(cases) == length(near)
        @test cases.notes.distance == min(d, n)
        # Every candidate within the distance is kept or dropped.
        product_near = count(r -> hamming(NamedTuple{Tuple(names)}(r)) <= d, Iterators.product(domains...))
        @test length(cases) + cases.notes.dropped == product_near
    end
    # A distance beyond the parameter count is the parameter count.
    @test collect(excursions(space; distance = n + 2)) == collect(excursions(space; distance = n))
end


@testitem "excursions: fixtures, every row valid and within distance" setup=[Checker] begin
    for f in (fable_solver, opus_gpu, dead_end_pairwise_1, dead_end_threeway_1, disconnected_witness)
        valid = valid_rows(f.space)
        # The first valid row as the base, and distances 1 to 3.
        base = first(valid)
        for d in 1:3
            cases = excursions(test_space(f); distance = d, from = base)
            near = filter(c -> count(k -> c[k] != base[k], keys(base)) <= d, valid)
            @test Set(cases) == Set(near)
            @test length(cases) == length(near)
            @test cases[1] == base
            @test isempty(check_design(collect(cases), f.space).ordinary.rejected)
        end
    end
    # The default base, the first value of each parameter, breaks both rules here.
    msg = try excursions(test_space(disconnected_witness)); "" catch e; e.msg end
    @test occursin("breaks rule 1", msg) && occursin("rule 2", msg)
end
