using Test
using TestItemRunner

# The coverage index (src/coverage_index.jl; plan §4.3): per combination of
# every support, a required bit and a count of the rows that hold it. Every
# answer is checked here against a count made from scratch over the rows and
# the request's own target list. The inference and allocation guards are in
# test_stability.jl.

@testsnippet IndexSetup begin
    using Random: Xoshiro
    using UnitTestDesign: CoverageIndex, Request, RequiredTargets, TargetList, classify_targets, supports,
                          combination, add_row!, remove_row!, move_entry!, entry_score, singly_covered,
                          nuncovered, nrows, ncombinations, cover_count, random_uncovered, decode!,
                          support_of, members_of, max_support, _forget_covered!, _decode!

    "A random request of 3 to 7 parameters with 1 to 5 values, sometimes with rules and `stronger` groups."
    function random_request(rng)
        n = rand(rng, 3:7)
        domains = [collect(1:rand(rng, 1:5)) for _ in 1:n]
        names = [Symbol(:p, i) for i in 1:n]
        rules = Constraint[]
        rand(rng) < 0.5 && push!(rules, forbid((a, b) -> a == 1 && b == 1, names[1], names[2]))
        rand(rng) < 0.3 && push!(rules, forbid((a, b, c) -> a + b == c, names[1], names[2], names[3]))
        space = TestSpace(NamedTuple{Tuple(names)}(Tuple(domains)); constraints = rules)
        strength = rand(rng, 1:min(3, n))
        stronger = strength < n && rand(rng) < 0.4 ? [Tuple(names[1:rand(rng, (strength + 1):n)]) => strength + 1] : []
        return Request(space; strength, stronger)
    end

    "Every combination as (support, its members' positions, required), in id order."
    function every_combination(request, targets)
        list = TargetList(request)
        required = Set(first(classify_targets(request)))
        return [(s, list[list.offsets[s] + code + 1], list[list.offsets[s] + code + 1] in required)
                for s in eachindex(list.supports) for code in 0:(list.offsets[s + 1] - list.offsets[s] - 1)]
    end

    "Whether `row` holds the combination `target` (a partial row, 0 for unset)."
    holds(row, target) = all(p -> target[p] == 0 || target[p] == row[p], eachindex(row))

    "The counts, the uncovered required count and each row's singly covered count, from scratch."
    function brute(combinations, rows)
        counts = [count(row -> holds(row, target), rows) for (_, target, _) in combinations]
        uncovered = count(k -> counts[k] == 0 && combinations[k][3], eachindex(counts))
        alone = [count(k -> counts[k] == 1 && combinations[k][3] && holds(row, combinations[k][2]),
                       eachindex(counts)) for row in rows]
        return counts, uncovered, alone
    end

    random_row(rng, request) = [rand(rng, 1:a) for a in request.arity]
end


@testitem "coverage index: the counts, the uncovered and the singly covered agree with a recount (§4.3)" setup=[IndexSetup] begin
    rng = Xoshiro(0x2026_1004_01)
    for _ in 1:60
        request = random_request(rng)
        required, _ = classify_targets(request)
        targets = RequiredTargets(request, required)
        index = CoverageIndex(request, targets)
        combinations = every_combination(request, targets)
        @test ncombinations(index) == length(combinations) == length(TargetList(request))
        @test nuncovered(index) == count(c -> c[3], combinations) == length(required)
        @test nrows(index) == 0
        # Each id is its combination's: the support, and the code read back.
        values = zeros(Int, max_support(index))
        for (id, (s, target, req)) in enumerate(combinations)
            @test support_of(index, id) == s
            @test decode!(values, index, id) == s
            @test values[1:length(members_of(index, s))] == target[supports(targets)[s]]
            @test index.required[id] == req
            @test combination(index, s, max.(target, 1)) == id
        end
        rows = [random_row(rng, request) for _ in 1:rand(rng, 0:12)]
        foreach(row -> add_row!(index, row), rows)
        counts, uncovered, alone = brute(combinations, rows)
        @test Int.(index.count) == counts
        @test nuncovered(index) == uncovered && nrows(index) == length(rows)
        @test [singly_covered(index, row) for row in rows] == alone
        # Entry moves, scored first: the score is the change in covered required combinations.
        for _ in 1:20
            isempty(rows) && break
            j = rand(rng, eachindex(rows))
            p = rand(rng, eachindex(request.arity))
            w = rand(rng, 1:request.arity[p])
            before = nuncovered(index)
            score = entry_score(index, rows[j], p, w)
            move_entry!(index, rows[j], p, w)
            @test rows[j][p] == w
            @test before - nuncovered(index) == score
        end
        counts, uncovered, alone = brute(combinations, rows)
        @test Int.(index.count) == counts && nuncovered(index) == uncovered
        @test [singly_covered(index, row) for row in rows] == alone
        # A drawn uncovered combination is uncovered and required, and removing
        # rows uncovers what they alone held.
        if nuncovered(index) > 0
            for _ in 1:10
                id = random_uncovered(index, rng)
                @test counts[id] == 0 && combinations[id][3]
            end
        end
        while !isempty(rows)
            row = popat!(rows, rand(rng, eachindex(rows)))
            before = nuncovered(index)
            lost = singly_covered(index, row)
            remove_row!(index, row)
            @test nuncovered(index) == before + lost
        end
        @test all(iszero, index.count) && nuncovered(index) == length(required)
        # Every uncovered required combination is on the list, once, after a draw.
        isempty(required) || random_uncovered(index, rng)
        live = [id for id in index.uncovered if index.count[id] == 0]
        @test sort(live) == [id for (id, c) in enumerate(combinations) if c[3]]
        @test allunique(index.uncovered)
    end
end


@testitem "coverage index: a draw is uniform over the uncovered, and the list forgets what was covered (§4.3)" setup=[IndexSetup] begin
    request = Request(TestSpace((a = 1:3, b = 1:3, c = 1:2)); strength = 2)
    targets = RequiredTargets(request, first(classify_targets(request)))
    index = CoverageIndex(request, targets)
    rows = [[1, 1, 1], [2, 2, 2], [3, 3, 1], [1, 2, 2]]
    foreach(row -> add_row!(index, row), rows)
    uncovered = [id for id in 1:ncombinations(index) if index.count[id] == 0]
    @test nuncovered(index) == length(uncovered)
    # A draw lists them. Cover some of them again, so that the list holds stale ids.
    @test isempty(index.uncovered) && !index.listing
    random_uncovered(index, Xoshiro(1))
    @test sort(index.uncovered) == uncovered && index.listing
    move_entry!(index, rows[4], 1, 2)
    move_entry!(index, rows[3], 2, 1)
    live = [id for id in 1:ncombinations(index) if index.count[id] == 0]
    @test length(index.uncovered) > length(live) == nuncovered(index)
    rng = Xoshiro(5)
    draws = [random_uncovered(index, rng) for _ in 1:6000]
    @test sort(unique(draws)) == live
    # Each of the live ids is drawn about equally often.
    expected = 6000 / length(live)
    @test all(id -> abs(count(==(id), draws) - expected) < 0.25 * expected, live)
    # With nothing uncovered the list empties.
    for row in ([1, 3, 2], [2, 1, 1], [2, 3, 2], [3, 1, 2], [3, 2, 1], [1, 3, 1], [2, 1, 2])
        add_row!(index, row)
    end
    full = [id for id in 1:ncombinations(index) if index.count[id] == 0]
    for id in full   # cover the rest directly, as a complete design would
        s = support_of(index, id)
        values = zeros(Int, 2)
        decode!(values, index, id)
        row = ones(Int, 3)
        row[supports(targets)[s]] = values
        add_row!(index, row)
    end
    @test nuncovered(index) == 0
    _forget_covered!(index)
    @test isempty(index.uncovered) && !any(index.listed)
    @test_throws ErrorException random_uncovered(index, rng)
end


@testitem "coverage index: a count holds every row the index can hold, and no more rows (§4.3)" setup=[IndexSetup] begin
    # A count is a UInt16: one row adds one to one combination per support, so
    # a count is at most the rows held, and the index holds at most 65,535.
    request = Request(TestSpace((a = 1:2, b = 1:2)); strength = 2)
    targets = RequiredTargets(request, first(classify_targets(request)))
    index = CoverageIndex(request, targets)
    for _ in 1:typemax(UInt16)
        add_row!(index, [1, 1])
    end
    @test cover_count(index, 1) == 65_535 && nrows(index) == 65_535
    @test_throws ErrorException add_row!(index, [2, 2])
    @test cover_count(index, 4) == 0
    remove_row!(index, [1, 1])
    add_row!(index, [2, 2])
    @test cover_count(index, 1) == 65_534 && cover_count(index, 4) == 1
    # Rows that are not complete rows of engine positions are internal errors.
    @test_throws ErrorException add_row!(index, [1, 0])
    @test_throws ErrorException add_row!(index, [1, 3])
    @test_throws ErrorException add_row!(index, [1, 1, 1])
    @test_throws ErrorException move_entry!(index, [1, 1], 1, 3)
end
