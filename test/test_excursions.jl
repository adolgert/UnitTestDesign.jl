using Test
using TestItemRunner

# Excursions through the internal Request (plan Phase 3 step 4; contract
# §7.5–§7.7, §7.11).


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
    # 0.4 levels Dict(3 => [[1, 2, 3], [2, 3, 4]]): three-way changes within each group.
    ex = build_excursion(arity, 2, base, row -> false; groups = [[1, 2, 3] => 3, [2, 3, 4] => 3])
    @test size(ex.matrix) == (4, 25 + 2 * 1 + 3 * 2)
    @test all(count(ex.matrix[:, j] .!= base) <= 2 || ex.matrix[1, j] == 1 || ex.matrix[4, j] == 1
              for j in axes(ex.matrix, 2))
    # Distance 0 is the base alone; a distance beyond the parameter count is the full product.
    @test build_excursion(arity, 0, base, row -> false).matrix == reshape(base, 4, 1)
    @test size(build_excursion(arity, 9, base, row -> false).matrix, 2) == prod(arity)
    # Another base: each changed parameter takes every other value.
    ex = build_excursion(arity, 1, [2, 3, 1, 4], row -> false)
    @test ex.matrix == [2 1 2 2 2 2 2 2; 3 3 1 2 3 3 3 3; 1 1 1 1 2 1 1 1; 4 4 4 4 4 1 2 3]
end


@testitem "excursions: default and explicit base, distance 1 and 2" setup=[Checker] begin
    using UnitTestDesign: Request, generate_excursion, to_cases
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    checker = CheckSpace(names, domains)
    space = TestSpace(Pair.(names, domains)...)
    within(case, base, d) = count(k -> case[k] != base[k], keys(base)) <= d

    request = Request(space; strength = 1)
    design = generate_excursion(request)
    cases = to_cases(request, design.matrix)
    @test cases == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                    (a = 1, b = :y, c = true), (a = 1, b = :x, c = false)]
    @test (design.strategy, design.engine, design.seed) == (:excursion, :Excursion, nothing)
    @test (design.required, design.covered, isempty(design.excluded)) == (0, 0, true)
    @test design.notes.dropped == 0
    @test isempty(design.notes.never_appear)
    @test design.notes.base == [1, 1, 1]

    base = (a = 3, b = :y, c = false)
    for from in (base, (3, :y, false), [3, 2, 2]), d in (1, 2)
        rows = to_cases(request, generate_excursion(Request(space; strength = d); distance = d, from).matrix)
        @test rows[1] == base
        @test allunique(rows)
        @test all(c -> within(c, base, d), rows)
        # Every valid row within distance d, and nothing else.
        @test Set(rows) == Set(filter(c -> within(c, base, d), valid_rows(checker)))
        @test length(rows) == (d == 1 ? 1 + 2 + 1 + 1 : 1 + 4 + 2 * 1 + 2 * 1 + 1 * 1)
    end
end


@testitem "excursions: dropped rows and values that never appear (§7.7)" setup=[Checker] begin
    using UnitTestDesign: Request, generate_excursion, to_cases
    # (b = :y, c = true) is forbidden. From the base (1, :x, true):
    #   distance 1: (2,x,T) (3,x,T) (1,y,T)✗ (1,x,F)          dropped 1, b = :y never appears
    #   distance 2: adds (2,y,T)✗ (3,y,T)✗ (2,x,F) (3,x,F) (1,y,F)   dropped 3
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    checker = CheckSpace(names, domains, [((:b, :c), (b, c) -> b == :y && c == true)])
    space = TestSpace(Pair.(names, domains)...;
        constraints = [forbid((b = :y, c = true); reason = "y needs c off")])

    request = Request(space; strength = 1)
    design = generate_excursion(request; distance = 1)
    cases = to_cases(request, design.matrix)
    @test cases == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                    (a = 1, b = :x, c = false)]
    @test design.notes.dropped == 1
    @test design.notes.never_appear == [(2, 2)]
    # No covering claim: b = :y is feasible but absent. No row is rejected.
    result = check_design(cases, checker; strength = 1)
    @test result.ordinary.missing == [(b = :y,)]
    @test isempty(result.ordinary.rejected)

    request = Request(space; strength = 2)
    design = generate_excursion(request; distance = 2)
    cases = to_cases(request, design.matrix)
    @test cases == [(a = 1, b = :x, c = true), (a = 2, b = :x, c = true), (a = 3, b = :x, c = true),
                    (a = 1, b = :x, c = false), (a = 2, b = :x, c = false), (a = 3, b = :x, c = false),
                    (a = 1, b = :y, c = false)]
    @test design.notes.dropped == 3
    @test isempty(design.notes.never_appear)
    @test all(c -> c in valid_rows(checker), cases)

    # A base with c = false: the forbidden pair is one change away only through b.
    design = generate_excursion(request; distance = 1, from = (a = 2, b = :y, c = false))
    cases = to_cases(request, design.matrix)
    @test design.notes.dropped == 1  # (2, :y, true)
    @test design.notes.never_appear == [(3, 1)]  # c = true
    @test Set(cases) == Set(filter(c -> count(k -> c[k] != (a = 2, b = :y, c = false)[k], names) <= 1,
                                   valid_rows(checker)))
end


@testitem "excursions: a forbidden or invalid base is an error naming the cause (§7.6)" setup=[Checker] begin
    using UnitTestDesign: Request, generate_excursion
    space = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [true, false]);
        constraints = [forbid((b = :y, c = true); reason = "y needs c off"),
                       forbid(:a, :b) do a, b; a == 3 && b == :y end])
    request = Request(space; strength = 1)
    message(f) = try f(); "no error" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError: $e" end
    msg = message(() -> generate_excursion(request; from = (a = 3, b = :y, c = true)))
    @test occursin("breaks", msg)
    @test occursin("rule 1 (y needs c off)", msg)
    @test occursin("rule 2 on (a, b)", msg)
    @test occursin("§7.6", msg)
    msg = message(() -> generate_excursion(request; from = (a = 1, b = :y, c = true)))
    @test occursin("y needs c off", msg) && !occursin("rule 2", msg)
    # A partial base, a value outside the domain, a wrong length, a bad position.
    @test occursin("complete row", message(() -> generate_excursion(request; from = (a = 1,))))
    @test occursin("`b`", message(() -> generate_excursion(request; from = (a = 1, b = :z, c = true))))
    @test occursin("3 parameters", message(() -> generate_excursion(request; from = (1, :x))))
    @test occursin("outside 1:2", message(() -> generate_excursion(request; from = [1, 3, 1])))
    @test occursin("at least 0", message(() -> generate_excursion(request; distance = -1)))
end


@testitem "excursions: must-include rows first, not repeated (§7.11, §10.5)" setup=[Checker] begin
    using UnitTestDesign: Request, generate_excursion, to_cases
    names = [:a, :b, :c]
    domains = [[1, 2, 3], [:x, :y], [true, false]]
    space = TestSpace(Pair.(names, domains)...; constraints = [forbid((b = :y, c = true))])
    plain = to_cases(Request(space; strength = 1), generate_excursion(Request(space; strength = 1)).matrix)
    @test length(plain) == 4

    seeds = [(a = 3, b = :y, c = false), (a = 2, b = :x, c = true), (c = false,), (a = 3, b = :y, c = false)]
    request = Request(space; strength = 1, must_include = seeds)
    design = generate_excursion(request)
    cases = to_cases(request, design.matrix)
    @test design.n_must_include == 4
    # The partial row is completed toward the base, (1, :x, true).
    @test cases[1:4] == [seeds[1], seeds[2], (a = 1, b = :x, c = false), seeds[4]]
    # (2, x, T) and (1, x, F) are excursion rows already present: not repeated.
    @test cases[5:end] == [(a = 1, b = :x, c = true), (a = 3, b = :x, c = true)]
    @test design.notes.dropped == 1
    @test isempty(design.notes.never_appear)
end


@testitem "excursions: stronger groups widen the distance within the group" setup=[Checker] begin
    using UnitTestDesign: Request, generate_excursion, to_cases
    # 0.4's pairs_excursion(fill(1:2, 20)...; wayness): 3-way coverage within groups.
    names = [Symbol(:p, i) for i in 1:8]
    space = TestSpace((n => [1, 2] for n in names)...)
    stronger = [(:p1, :p2, :p3, :p4) => 3, (:p6, :p7, :p8) => 3]
    request = Request(space; strength = 2, stronger)
    design = generate_excursion(request; distance = 2)
    # 1 base, 8 singles, 28 pairs, and the triples inside each group: 4 + 1.
    @test size(design.matrix, 2) == 1 + 8 + 28 + 4 + 1
    checker = CheckSpace(names, [[1, 2] for _ in names])
    cases = to_cases(request, design.matrix)
    @test complete(check_design(cases, checker; strength = 2, stronger))
    changed = [count(design.matrix[:, j] .!= 1) for j in axes(design.matrix, 2)]
    @test maximum(changed) == 3
    # p5 is in no group, so it never changes in a three-parameter excursion.
    @test all(j -> changed[j] <= 2 || design.matrix[5, j] == 1, axes(design.matrix, 2))
end


@testitem "excursions: fixtures, every row valid and within distance" setup=[Checker] begin
    using UnitTestDesign: Request, generate_excursion, to_cases
    for f in (fable_solver, opus_gpu, dead_end_pairwise_1, dead_end_threeway_1, disconnected_witness)
        space = test_space(f)
        n = length(f.input.names)
        valid = valid_rows(f.space)
        # The first valid row as the base, and distances 1 to 3.
        base = first(valid)
        for d in 1:3
            request = Request(space; strength = min(d, n))
            design = generate_excursion(request; distance = d, from = base)
            cases = to_cases(request, design.matrix)
            near = filter(c -> count(k -> c[k] != base[k], keys(base)) <= d, valid)
            @test Set(cases) == Set(near)
            @test length(cases) == length(near)
            @test cases[1] == base
            # Values that never appear, recomputed from the rows.
            missing_values = [(i, v) for i in 1:n for v in 1:length(f.input.domains[i])
                              if !any(c -> isequal(c[i], f.input.domains[i][v]), cases)]
            @test design.notes.never_appear == missing_values
        end
    end
    # The default base, the first value of each parameter, breaks both rules here.
    msg = try generate_excursion(Request(test_space(disconnected_witness); strength = 1)); "" catch e; e.msg end
    @test occursin("breaks rule 1", msg) && occursin("rule 2", msg)
end
