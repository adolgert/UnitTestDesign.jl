using Test
using TestItemRunner

# Negative generation (src/invalid.jl; plan Phase 6 steps 1 and 5): the
# covering design over ordinary values, then negative rows that cover the
# negative targets of contract §6, and the same row policy for must-include
# rows, full factorials and excursions (§5, §7.2–§7.9, §10). Every design is
# judged by the independent oracle (checker.jl) on both parts, ordinary and
# negative, and by `coverage(cases)`, which measures both from the rows.

@testsnippet InvalidSetup begin
    using Random: Xoshiro

    "A production value or row in the checker's terms: `CheckInvalid` for `Invalid`, a partition by its name."
    as_check(x::Invalid) = CheckInvalid(as_check(x.value))
    as_check(x::Partition) = x.name
    as_check(x) = x
    as_check(row::Union{NamedTuple, Tuple}) = map(as_check, row)

    const ENGINES = (IPOG(), GND())

    plain(x) = sprint(show, MIME"text/plain"(), x)

    "The message of the exception `f()` throws, or \"no error\"."
    message(f) = try
        f()
        "no error"
    catch e
        sprint(showerror, e)
    end

    "Two lists of exclusions agree field by field, targets by identity."
    same_exclusions(a, b) = length(a) == length(b) && all(zip(a, b)) do (x, y)
        same_target(x.target, y.target) && x.status == y.status && x.rules == y.rules &&
            x.labels == y.labels && x.minimal == y.minimal && x.limit == y.limit
    end

    "The number of `Invalid` values in a row."
    invalids(row) = count(x -> x isa Invalid, values(row))

    "The same row by identity (§2.1): the same names, each value `===`, whatever the field types."
    same_row(a, b) = keys(a) == keys(b) && all(a[k] === b[k] for k in keys(a))

    """
    Generate a covering design and check it: both parts complete by the oracle
    (§1.3, §6.7), the bookkeeping equal to the oracle's counts and
    attributions (§1.19), must-include rows, then ordinary rows, then negative
    rows (§5.12), no multiple-invalid row (§5.7), and `coverage(cases)`
    complete on both parts and equal to the bookkeeping (§1.12, §5.10).
    """
    function checked_design(space, cs; engine, strength, stronger = [], must_include = [])
        cases = covering(space; strength, stronger, engine, must_include)
        check = check_design(as_check.(collect(cases)), cs; strength, stronger)
        @test complete(check.ordinary)
        @test complete(check.negative)
        @test cases.required == cases.covered == check.ordinary.counts.feasible
        @test cases.negative_required == cases.negative_covered == check.negative.counts.feasible
        @test length(cases.negative_excluded) ==
              check.negative.counts.forbidden + check.negative.counts.implied
        for e in cases.negative_excluded
            t = as_check(e.target)
            if e.status == :forbidden
                k = findfirst(x -> same_target(x.first, t), check.negative.forbidden)
                @test k !== nothing && check.negative.forbidden[k].second == e.rules
            else
                @test e.status == :implied && any(x -> same_target(x, t), check.negative.implied)
            end
        end
        generated = collect(cases)[(cases.n_must_include + 1):end]
        @test issorted(hasinvalid.(generated))
        @test all(row -> invalids(row) <= 1, cases)
        c = coverage(cases)
        @test iscomplete(c)
        @test c.negative.covered == c.negative.feasible == cases.negative_required
        @test c.ordinary.covered == cases.covered
        @test same_exclusions(c.ordinary.excluded, cases.excluded)
        @test same_exclusions(c.negative.excluded, cases.negative_excluded)
        return cases
    end

    "Two parameters with Invalid values, rules on each, and a whole-case rule (§5.6)."
    two_invalid() = CheckSpace((a = [1, 2, CheckInvalid(0)], b = [CheckInvalid(:z), 1, 2], c = [1, 2]),
        [((:a, :c), (a, c) -> a == 1 && c == 2),
         ((:b, :c), (b, c) -> b == 2 && c == 1),
         ((:a, :b, :c), (a, b, c) -> a == 2 && b == 1 && c == 2)])

    "An Invalid value on a parameter inside a stronger group."
    grouped() = CheckSpace((a = [1, 2, CheckInvalid(0)], b = [1, 2], c = [1, 2, 3], d = [:x, :y]),
        [((:b, :c), (b, c) -> b == 2 && c == 3),
         ((:a, :d), (a, d) -> a == 1 && d == :y)])

    """
    Negative targets that rules not mentioning `n` exclude (§6.2): `m = 1` has
    no valid completion, so `(n = Invalid(-1), m = 1)` is implied by rules 1,
    2 and 4, and `(n = Invalid(-1), k = :z)` is forbidden by rule 4. Rule 3
    reads `n` and does not apply to negative rows (§5.5).
    """
    excluding() = TestSpace((n = [1, 2, Invalid(-1)], m = [1, 2], k = [:x, :y, :z]);
        constraints = [@forbid(m == 1 && k == :x), @forbid(m == 1 && k == :y),
                       @forbid(n == 1 && m == 2), @forbid(k == :z)])

    "A space built without the warning a lazily evaluated rule gives."
    quietly(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())

    """
    Invalid values at `a` and `c`, and every rule's scope written out of
    parameter order. Rules 1 and 4 are lazy (above `tabulation_limit = 6`) and
    read neither `a` nor `c`; rule 2 reads `c` and rule 3 reads `a`, both
    tabulated; rule 5 reads every parameter. As `benchmark/snapshot.jl`'s
    space "negative sub-requests, scopes out of order", with rule 5 added.
    """
    out_of_order() = quietly() do
        TestSpace((a = [1, 2, 3, Invalid(0)], b = [:x, :y, :z], c = [1, 2, Invalid(-1)], d = [true, false],
                   e = [1, 2, 3]);
            constraints = [forbid(:e, :b) do e, b; e == 3 && b != :x end,
                           forbid(:d, :c) do d, c; d && c == 2 end,
                           forbid(:d, :a) do d, a; !d && a == 2 end,
                           forbid(:e, :d, :b) do e, d, b; e == 3 && d && b == :x end,
                           forbid(; reason = "whole-case") do r; r.a == 1 && r.b == :y && r.e == 2 end],
            tabulation_limit = 6)
    end
end


@testitem "invalid: both guarantees against the oracle, strengths 1 to 3, both engines (§1.3, §5, §6)" setup=[Checker, InvalidSetup] begin
    spaces = [(invalid_beside_ordinary.space, 1:3), (empty_ordinary_negative_seed.space, 1:2),
              (two_invalid(), 1:3), (grouped(), 1:3)]
    for (cs, strengths) in spaces, strength in strengths, engine in ENGINES
        @testset "$(cs.names) strength $strength $engine" begin
            checked_design(test_space(cs), cs; engine, strength)
        end
    end
    # Stronger groups that contain the invalid parameter, from base strength 1
    # (a sub-request at strength 0), 2 and 3, and a group without it.
    cs = grouped()
    space = test_space(cs)
    for engine in ENGINES
        for (strength, stronger) in ((1, [(:a, :b, :c) => 3]), (1, [(:a, :b) => 2, (:c, :d) => 2]),
                                     (2, [(:a, :b, :c) => 3]), (2, [(:a, :b, :c, :d) => 4]),
                                     (3, [(:a, :b, :c, :d) => 4]), (2, [(:b, :c, :d) => 3]))
            @testset "stronger $stronger at $strength, $engine" begin
                checked_design(space, cs; engine, strength, stronger)
            end
        end
        # A group without the invalid parameter adds no negative target (§6.5).
        plain_design = covering(space; strength = 2, engine)
        with_group = covering(space; strength = 2, stronger = [(:b, :c, :d) => 3], engine)
        @test with_group.negative_required == plain_design.negative_required
        @test covering(space; strength = 2, stronger = [(:a, :b, :c) => 3], engine).negative_required >
              plain_design.negative_required
    end
    # At strength 2, each invalid value appears beside every feasible value of
    # every other parameter (§6.6), and at strength 1 once (§6.4).
    space = test_space(invalid_beside_ordinary)
    @test covering(space; strength = 1).negative_required == 1
    @test all_pairs(space).negative_required == 4
    @test count(hasinvalid, all_values(space)) == 1
end


@testitem "invalid: an infeasible negative target is an Exclusion (§1.4, §6.2, §6.7)" setup=[Checker, InvalidSetup] begin
    space = excluding()
    for engine in ENGINES
        cases = all_pairs(space; engine)
        bad = Invalid(-1)
        @test [e.target for e in cases.negative_excluded] == [(n = bad, m = 1), (n = bad, k = :z)]
        implied, forbidden = cases.negative_excluded
        @test implied.status == :implied && implied.rules == [1, 2, 4] && implied.minimal == :verified
        @test forbidden.status == :forbidden && forbidden.rules == [4]
        # Rule 3 reads n, so it names no negative exclusion.
        @test !any(e -> 3 in e.rules, cases.negative_excluded)
        @test cases.negative_required == cases.negative_covered == 3
        @test sort([r for r in cases if hasinvalid(r)]; by = r -> r.k) ==
              [(n = bad, m = 2, k = :x), (n = bad, m = 2, k = :y)]
        c = coverage(cases)
        @test iscomplete(c) && same_exclusions(c.negative.excluded, cases.negative_excluded)
    end
    # The show and report lines count the negative exclusions apart.
    cases = all_pairs(space)
    # Ordinary: (2, 2, :x) and (2, 2, :y) are the valid rows, so 5 pairs are
    # feasible; 7 are forbidden directly and 4 implied.
    @test split(plain(cases), '\n')[2] ==
          "excluded: 7 pairs forbidden, 4 impossible under the constraints; negative: " *
          "1 pair forbidden, 1 impossible under the constraints; see report(cases)"
    @test report(cases).guarantee ==
          "$(length(cases)) cases cover all 5 feasible pairs of an 18-combination space (7 pairs " *
          "forbidden, 4 impossible under the constraints); negative: covers 3 of 3 feasible pairs " *
          "(1 pair forbidden, 1 impossible under the constraints)"
    shown = plain(report(cases))
    @test occursin("\n  (n = Invalid(-1), m = 1): impossible because rules 1, 2 and 4 combine", shown)
    @test occursin("\n  (n = Invalid(-1), k = :z): forbidden by rule 4 (@forbid(k == :z))", shown)
    @test same_exclusions(report(cases).excluded[(end - 1):end], cases.negative_excluded)
end


@testitem "invalid: must-include rows under their own row policy (§5.7, §7.9, §10.3–§10.6)" setup=[Checker, InvalidSetup] begin
    f = invalid_beside_ordinary
    space = test_space(f)
    bad = Invalid(1)
    for engine in ENGINES
        # A complete negative row first: kept in place, and it counts toward
        # the negative targets it holds (§10.6).
        row = (n = bad, m = :b, k = :y)
        cases = checked_design(space, f.space; engine, strength = 2, must_include = [row])
        @test same_row(cases[1], row) && cases.n_must_include == 1
        @test count(hasinvalid, cases) <= 1 + count(hasinvalid, all_pairs(space; engine))
        # A partial row with an Invalid is completed as a negative row (§7.9).
        cases = checked_design(space, f.space; engine, strength = 2, must_include = [(n = bad,)])
        @test cases[1].n === bad && isallowed(space, cases[1])
        # A partial row without one is completed as an ordinary row (§7.9).
        cases = checked_design(space, f.space; engine, strength = 2, must_include = [(m = :b,), (k = :y, n = bad)])
        @test !hasinvalid(cases[1]) && cases[1].m === :b && isallowed(space, cases[1])
        @test cases[2].n === bad && cases[2].k === :y && isallowed(space, cases[2])
        # Must-include rows at strength 1 and 3, where negative generation
        # uses a witness or the full-strength path.
        for strength in (1, 3)
            cases = checked_design(space, f.space; engine, strength, must_include = [(n = bad,), (n = 1,)])
            @test cases[1].n === bad && cases[2].n === 1
        end
    end
    # No valid ordinary row, one valid negative row (§1.24).
    e = empty_ordinary_negative_seed
    espace = test_space(e)
    for engine in ENGINES
        cases = checked_design(espace, e.space; engine, strength = 2,
                               must_include = [(a = Invalid(0), b = 1)])
        @test collect(cases) == [(a = Invalid(0), b = 1)]
        @test cases.required == 0 && cases.negative_required == 1
        @test collect(checked_design(espace, e.space; engine, strength = 1)) == [(a = Invalid(0), b = 1)]
    end
    @test occursin("breaks rule 1", message(() -> all_pairs(espace; must_include = [(a = 1, b = 1)])))
    @test occursin("has no valid completion", message(() -> all_pairs(espace; must_include = [(a = 1,)])))

    # A negative row that breaks a rule not reading its invalid parameter is an error (§10.3).
    msg = message(() -> all_pairs(space; must_include = [(n = bad, m = :a, k = :y)]))
    @test occursin("must_include row 1, (n = Invalid(1), m = :a, k = :y), breaks rule 2", msg)
    @test occursin("§10.3", msg)
    # Rules reading the invalid parameter do not apply to it (§5.5): rule 1
    # forbids n = 2 with m = :b, which says nothing of n = Invalid(1).
    @test same_row(all_pairs(space; must_include = [(n = bad, m = :b, k = :x)])[1], (n = bad, m = :b, k = :x))

    # Two Invalid values in one row are an error, complete or partial (§5.7).
    two = test_space(two_invalid())
    for rows in ([(a = Invalid(0), b = Invalid(:z), c = 1)], [(a = Invalid(0), b = Invalid(:z))])
        for call in (() -> all_pairs(two; must_include = rows), () -> full_factorial(two; must_include = rows),
                     () -> excursions(two; must_include = rows))
            text = message(call)
            @test occursin("must_include row 1", text) && occursin("has Invalid values for a and b", text)
            @test occursin("§5.7", text)
        end
    end
    # Positional rows too.
    @test occursin("§5.7", message(() -> all_pairs([1, Invalid(0)], [Invalid(1), 2];
                                                   must_include = [(Invalid(0), Invalid(1))])))
    @test all_pairs([1, Invalid(0)], [Invalid(1), 2]; must_include = [(Invalid(0), 2)])[1] === (Invalid(0), 2)
end


@testitem "invalid: full_factorial is the oracle's ordinary rows, then its negative rows (§7.2, §7.3)" setup=[Checker, InvalidSetup] begin
    for cs in (invalid_beside_ordinary.space, two_invalid(), grouped(), empty_ordinary_negative_seed.space)
        space = test_space(cs)
        cases = full_factorial(space)
        # The oracle sorts rows by value position: the last parameter fastest,
        # as full_factorial enumerates. Negative rows come by invalid
        # parameter, then invalid value, as full_factorial lists them.
        negative = negative_rows(cs)
        by_value = [r for p in eachindex(cs.names)
                    for v in cs.domains[p] if v isa CheckInvalid
                    for r in negative if same_value(r[p], v)]
        expected = [valid_rows(cs); by_value]
        @test length(cases) == length(expected)
        @test all(same_target(as_check(a), b) for (a, b) in zip(cases, expected))
        @test cases.notes.accepted == length(expected)
        # The candidates (§7.3): the ordinary product, plus each parameter's
        # invalid values times the other parameters' ordinary products.
        ordinary = [count(x -> !(x isa CheckInvalid), d) for d in cs.domains]
        invalid = [count(x -> x isa CheckInvalid, d) for d in cs.domains]
        candidates = prod(ordinary) + sum(invalid[p] * prod(ordinary[setdiff(eachindex(ordinary), p)])
                                          for p in eachindex(ordinary))
        @test cases.notes.candidates == candidates
        @test !any(r -> invalids(r) > 1, cases)
        # The limit error names the count and the keyword.
        err = try
            full_factorial(space; limit = candidates - 1)
        catch e
            e
        end
        @test err isa ResourceLimitError && err.keyword == :limit && err.limit == candidates - 1
        @test occursin("full factorial of $candidates candidate rows ($(prod(ordinary)) ordinary and " *
                       "$(candidates - prod(ordinary)) with one Invalid value)", sprint(showerror, err))
        @test length(full_factorial(space; limit = candidates)) == length(expected)
        # Coverage of a full factorial is complete on both parts at every strength.
        for strength in 1:length(cs.names)
            @test iscomplete(coverage(cases; strength))
        end
    end
    # Must-include rows come first, a partial negative one completed as negative.
    space = test_space(invalid_beside_ordinary)
    cases = full_factorial(space; must_include = [(n = Invalid(1), k = :y), (n = 2,)])
    @test cases[1].n === Invalid(1) && cases[1].k === :y && isallowed(space, cases[1])
    @test cases[2].n === 2 && isallowed(space, cases[2])
    @test length(cases) == 2 + 7 - 2   # the two rows are not repeated
    # The covering design at full strength is, as a set, the full factorial (§7.8).
    for engine in ENGINES
        @test issetequal(covering(space; strength = 3, engine), full_factorial(space))
    end
end


@testitem "invalid: excursions change a parameter to an Invalid value (§7.5, §7.6)" setup=[Checker, InvalidSetup] begin
    cs = two_invalid()
    space = test_space(cs)
    base = (a = 2, b = 1, c = 1)
    known = [valid_rows(cs); negative_rows(cs)]
    distance_of(r) = count(k -> !same_value(as_check(r[k]), as_check(base[k])), keys(base))
    for distance in 0:3
        cases = excursions(space; from = base, distance)
        @test same_row(cases[1], base)
        # Every valid ordinary or negative row within the distance, each once.
        expected = [r for r in known if count(k -> !same_value(r[k], as_check(base[k])), keys(base)) <= distance]
        @test length(cases) == length(expected)
        @test all(r -> any(x -> same_target(as_check(r), x), expected), cases)
        @test all(r -> invalids(r) <= 1 && isallowed(space, r), cases)
        @test all(r -> distance_of(r) <= distance, cases)
        # Dropped rows break their rules; multiple-invalid rows are no candidates.
        within = [r for r in Iterators.product(cs.domains...) if
                  count(x -> x isa CheckInvalid, r) <= 1 &&
                  count(k -> !same_value(r[k], as_check(base[k])), 1:3) <= distance]
        @test cases.notes.dropped == length(within) - length(expected)
    end
    cases = excursions(space; from = base, distance = 1)
    @test count(hasinvalid, cases) == 2   # a = Invalid(0) and b = Invalid(:z); c has none
    @test (a = Invalid(0), b = 1, c = 1) in cases && (a = 2, b = Invalid(:z), c = 1) in cases
    # The whole-case rule forbids (2, 1, 2), an ordinary row one change away.
    @test !((a = 2, b = 1, c = 2) in cases)
    @test coverage(cases; strength = 1).negative.covered == 2
    # A changed parameter takes its other values in domain order, Invalid
    # values included, and the never_appear list names Invalid values too.
    @test [r.a for r in excursions(TestSpace((a = [1, Invalid(0), 2], b = [:x, :y])))] == [1, Invalid(0), 2, 1]
    @test excursions(space; from = base, distance = 0).notes.never_appear ==
          [:a => 1, :a => Invalid(0), :b => Invalid(:z), :b => 2, :c => 2]
    # The base is an ordinary row (§7.6).
    msg = message(() -> excursions(space; from = (a = Invalid(0), b = 1, c = 1)))
    @test occursin("the base must be an ordinary row", msg) && occursin("§7.6", msg)
    # The default base is the first ordinary value of each parameter.
    @test same_row(excursions(space)[1], (a = 1, b = 1, c = 1))
    # A partial negative must-include row is completed toward the base, as a negative row.
    cases = excursions(space; from = base, must_include = [(b = Invalid(:z),)])
    @test same_row(cases[1], (a = 2, b = Invalid(:z), c = 1)) && same_row(cases[2], base)
    # The rows: that one, the base, (1, 1, 1) and (Invalid(0), 1, 1); (2, 2, 1)
    # and (2, 1, 2) are dropped. The valid ordinary rows are (1, 1, 1),
    # (2, 1, 1) and (2, 2, 2), so 8 pairs are feasible; all 8 negative pairs are.
    @test report(cases).guarantee == "1 must-include row kept first, then 3 cases within distance 1 of " *
          "(a = 2, b = 1, c = 1); 2 rows dropped; never appear: b = 2, c = 2; not a covering design; " *
          "measured at strength 2, the cases cover 5 of 8 feasible pairs (2 pairs forbidden, 2 impossible " *
          "under the constraints); 3 pairs missing; negative: covers 4 of 8 feasible pairs, 4 missing"
end


@testitem "invalid: show and report state the two guarantees (§1.22, §1.23, §5.10)" setup=[Checker, InvalidSetup] begin
    space = test_space(invalid_beside_ordinary)
    cases = all_pairs(space)
    @test plain(cases) == """
        6 cases (lower bound 5) · strength 2 · Auto: IPOG() · 3 parameters · 12 combinations · 4 negative targets
        excluded: 2 pairs forbidden, 1 impossible under the constraints; see report(cases)
             n           m   k
         1   1           :a  :x
         2   1           :b  :y
         3   2           :a  :x
         4   1           :b  :x
         5!  Invalid(1)  :a  :x
         6!  Invalid(1)  :b  :y"""
    r = report(cases)
    @test r.guarantee == "6 cases cover all 9 feasible pairs of a 12-combination space (2 pairs forbidden, " *
                         "1 impossible under the constraints); negative: covers 4 of 4 feasible pairs"
    @test sprint(show, r) == r.guarantee
    @test r.coverage.negative.covered == 4 && isempty(r.recorded)
    # The one-line summary, in a container.
    @test sprint(show, cases) == "6 cases (lower bound 5) · strength 2 · Auto: IPOG() · 3 parameters · 12 combinations · 4 negative targets"
    # At full strength the valid rows are known: 4 ordinary and 3 negative.
    @test startswith(plain(covering(space; strength = 3)),
                     "7 cases (minimal) · strength 3 · Auto: IPOG() · 3 parameters · 12 combinations, 7 valid · 3 negative targets")
    # Excursions and full factorials have no negative targets to count.
    @test sprint(show, full_factorial(space)) == "7 cases · full factorial · 3 parameters · 12 combinations, 7 valid"
    @test startswith(sprint(show, excursions(space)), "4 cases · excursion, distance 1 from (n = 1, m = :a, k = :x)")
    # The marker column survives when columns are cut, and appears only with a negative row.
    limited = sprint((io, x) -> show(IOContext(io, :limit => true, :displaysize => (24, 20)), MIME"text/plain"(), x), cases)
    @test any(line -> startswith(line, " 5!"), split(limited, '\n'))
    @test !occursin("!", plain(all_pairs(test_space(fable_solver))))
end


@testitem "invalid: coverage rejects a negative row that breaks an applicable rule (§1.14, §5.5, §5.11)" setup=[Checker, InvalidSetup] begin
    space = test_space(invalid_beside_ordinary)
    bad = Invalid(1)
    c = coverage([(n = bad, m = :a, k = :y), (n = bad, m = :b, k = :x)], space)
    @test [(r.index, r.reason, r.rules) for r in c.negative.rejected] == [(1, :violates_rule, [2])]
    @test c.negative.rows == 1 && isempty(c.ordinary.rejected)
    @test c.negative.covered == 2   # (n = bad, m = :b) and (n = bad, k = :x)
    # A generated design never holds such a row.
    for engine in ENGINES
        @test !((n = bad, m = :a, k = :y) in all_pairs(space; engine))
    end
    # Inputs the space still rejects (§4.12, §5.2).
    @test_throws ArgumentError test_space(invalid_only_domain)
    @test_throws ArgumentError Invalid(Partition(:tiny, Returns(1)))
    @test_throws ArgumentError Invalid(Invalid(0))
    @test_throws ArgumentError all_pairs([Invalid(0), Invalid(1)], [1, 2])
end


@testitem "invalid: generation is deterministic and positional calls keep their shape (§1.18, §9.1)" setup=[Checker, InvalidSetup] begin
    space = test_space(two_invalid())
    for engine in (IPOG(), GND(seed = 3)), strength in 1:3
        a = covering(space; strength, engine)
        b = covering(space; strength, engine)
        @test collect(a) == collect(b)
        @test same_exclusions(a.negative_excluded, b.negative_excluded)
    end
    cases = all_pairs([1, 2, Invalid(0)], [:x, :y], [true, false]; engine = GND())
    @test eltype(cases) <: Tuple && length(first(cases)) == 3
    # Invalid(0) beside :x, :y, true and false: two rows can hold the four pairs.
    @test count(hasinvalid, cases) >= 2
    @test iscomplete(coverage(cases))
    @test cases.negative_required == 4
    # A previous result as must_include keeps every row, negative ones
    # included, and adds none when nothing is left to cover (§9.10).
    for engine in (IPOG(), GND(seed = 5), GND(rng = Xoshiro(8))), strength in 1:3
        previous = covering(space; strength, engine)
        again = covering(space; strength, engine, must_include = previous)
        @test collect(again) == collect(previous) && again.n_must_include == length(previous)
        @test again.negative_required == previous.negative_required
    end
    # One parameter: its Invalid values each take one row (§6.4).
    one = all_values([1, 2, Invalid(0), Invalid(-1)])
    @test collect(one) == [(1,), (2,), (Invalid(0),), (Invalid(-1),)]
    @test one.negative_required == 2 && iscomplete(coverage(one))
    @test collect(full_factorial([1, Invalid(0)])) == [(1,), (Invalid(0),)]
    @test collect(excursions([1, Invalid(0)])) == [(1,), (Invalid(0),)]
    # design_sizes runs every strategy; the full factorial counts negative rows as valid.
    sizes = design_sizes(space)
    @test sizes.valid == length(full_factorial(space))
    @test all(row -> row.status === :ok, sizes.rows)
end


@testitem "invalid: an unresolved negative target stops generation (§3.6, §6.7)" setup=[Checker, InvalidSetup] begin
    # No ordinary row: n's one ordinary value is forbidden, which the search
    # proves without a node. A negative row skips that rule (§5.5), and its
    # other rule allows only x1 = x2 = x3 = x4 = 4, which takes nodes to find.
    space = TestSpace((n = [1, Invalid(0)], x1 = 1:4, x2 = 1:4, x3 = 1:4, x4 = 1:4);
        constraints = [forbid(n -> n == 1, :n),
                       forbid((a, b, c, d) -> !(a == b == c == d == 4), :x1, :x2, :x3, :x4)])
    err = try
        all_pairs(space; feasibility_limit = 1)
    catch e
        e
    end
    @test err isa ResourceLimitError && err.keyword == :feasibility_limit && err.limit == 1
    @test occursin("classifying the negative target (n = Invalid(0), x1 = 1)", sprint(showerror, err))
    # The default limit resolves every target: one negative row, and no ordinary row (§1.24).
    for engine in ENGINES
        cases = all_pairs(space; engine)
        @test collect(cases) == [(n = Invalid(0), x1 = 4, x2 = 4, x3 = 4, x4 = 4)]
        @test cases.required == 0 && cases.negative_required == 4
        @test length(cases.negative_excluded) == 12 && all(e -> e.status == :implied, cases.negative_excluded)
        @test iscomplete(coverage(cases))
    end
end


@testitem "invalid: every negative target is classified before a negative row is generated (§3.6, §6.7)" setup=[Checker, InvalidSetup] begin
    # As benchmark/snapshot.jl's space "negative rows' engine at the limit".
    # Both engines place a = 5 beside b = 5 in a negative row at n, and
    # proving that (a = 5, b = 5) leaves no valid row, five pigeons in four
    # holes, takes 66 nodes. Classifying (m = Invalid(0), e = 2) takes 26, and
    # every other pair is classified at feasibility_limit = 12. n = 1 keeps a
    # from 5, and m = 1 keeps e from 2, wherever they apply.
    five = (:x, :y, :z, :u, :w)
    crowded = [forbid((a, b, p, q) -> a == 5 && b == 5 && p == q, :a, :b, h, k)
               for (i, h) in enumerate(five) for k in five[(i + 1):end]]
    space = TestSpace((n = [1, Invalid(0)], m = [1, Invalid(0)], a = 1:5, b = 1:5, x = 1:4, y = 1:4, z = 1:4,
                       u = 1:4, w = 1:4, e = 1:2);
        constraints = [crowded; forbid((n, a) -> n == 1 && a == 5, :n, :a); forbid((m, e) -> m == 1 && e == 2, :m, :e);
                       forbid((e, x, y, z) -> e == 2 && !(x == y == z == 4), :e, :x, :y, :z)])
    for engine in ENGINES
        # Every classification resolves, and n's engine run reaches the limit.
        @test occursin("generating the negative rows with n = Invalid(0): placing a value",
                       message(() -> all_pairs(space; engine, feasibility_limit = 40)))
        # m's classification reaches it first, though m's invalid value comes after n's.
        @test occursin("classifying the negative target (m = Invalid(0), e = 2) reached `feasibility_limit = 12`",
                       message(() -> all_pairs(space; engine, feasibility_limit = 12)))
        @test iscomplete(coverage(all_pairs(space; engine)))
    end
end


@testitem "invalid: a negative row's projection is the space without its invalid parameter, field by field" setup=[Checker, InvalidSetup] begin
    using UnitTestDesign: Request, NegativeProjection, parent_row, _negative_request
    space = out_of_order()
    n = length(space.names)
    for p in 1:n
        pr = NegativeProjection(space, p)
        kept = [q for q in 1:n if q != p]
        rules = [k for k in eachindex(space.tables) if !(p in space.tables[k].scope)]
        @test pr.space === space && pr.p == p && pr.kept == kept && pr.rules == rules
        @test pr.renumber[kept] == 1:(n - 1) && pr.renumber[p] == 0
        @test !(5 in pr.rules)   # the whole-case rule reads p
        # Every field of the sub-space: the space's own parts, over the kept
        # parameters and the rules that omit p. A field added to TestSpace
        # fails the first test.
        expected = (names = space.names[kept], values = space.values[kept],
                    constraints = space.constraints[rules], tables = space.tables[rules],
                    tabulation_limit = space.tabulation_limit, ordinary = space.ordinary[kept],
                    invalid = space.invalid[kept], lookup = space.lookup[kept])
        @test keys(expected) == fieldnames(TestSpace)
        for field in fieldnames(TestSpace)
            got, want = getfield(pr.subspace, field), expected[field]
            if field == :tables
                # A table keeps its forbidden bits or predicate; its scope is
                # renumbered one parameter at a time, in the rule's order.
                @test length(got) == length(want) && all(zip(got, want)) do (t, u)
                    kept[t.scope] == u.scope &&
                        all(f -> getfield(t, f) === getfield(u, f), (:low, :radix, :forbidden, :lazy))
                end
            elseif want isa Vector
                @test length(got) == length(want) && all(splat(===), zip(got, want))
            else
                @test got === want
            end
        end
    end
    # Scopes are not sorted: at a, rule 1 on (e, b) reads sub-space parameters 4 and 1, in that order.
    @test [t.scope for t in NegativeProjection(space, 1).subspace.tables] == [[4, 1], [3, 2], [4, 3, 1]]
    @test [t.scope for t in NegativeProjection(space, 3).subspace.tables] == [[4, 2], [3, 1], [4, 3, 2]]
    # A sub-request's row goes back with its invalid position at p.
    @test parent_row(NegativeProjection(space, 1), [2, 3, 1, 2], 4) == [4, 2, 3, 1, 2]
    @test parent_row(NegativeProjection(space, 3), [2, 3, 1, 2], 3) == [2, 3, 3, 1, 2]
    # A request shares its memos only with a projection of its own space.
    request = Request(space; strength = 2)
    twin = NegativeProjection(out_of_order(), 1)   # the same rules, other tables
    @test occursin("internal error: the request's rule tables are not the projected space's",
                   message(() -> _negative_request(request, twin, zeros(Int, 4, 0))))
end


@testitem "invalid: a negative sub-request's rule numbers map back to the space's (§1.4, §5.5)" setup=[Checker, InvalidSetup] begin
    using UnitTestDesign: Request, NegativeProjection, parent_rule, _negative_request, violates, rule_label
    space = out_of_order()
    request = Request(space; strength = 2)
    for p in eachindex(space.names)
        pr = NegativeProjection(space, p)
        sub = _negative_request(request, pr, zeros(Int, length(space.names) - 1, 0))
        # The sub-space holds the space's own rules, numbered again from 1.
        @test length(sub.space.constraints) == length(sub.space.tables) == length(pr.rules)
        @test all(i -> request.space.constraints[parent_rule(pr, i)] === sub.space.constraints[i],
                  eachindex(sub.space.constraints))
    end
    # So a sub-space number is not the space's: at a, the sub-space's rule 3 is rule 4.
    pr = NegativeProjection(space, 1)
    @test parent_rule(pr, 3) == 4
    @test rule_label(pr.subspace, 3) == "rule 3 on (e, d, b)" && rule_label(space, 4) == "rule 4 on (e, d, b)"
    # An error from a lazy rule's predicate, the one way a rule leaves a
    # sub-request today, names the rule as the space tabulated it.
    boom = quietly() do
        TestSpace((a = [1, Invalid(0)], b = [1, 2, 3], c = [1, 2, 3]);
            constraints = [forbid((a = 1, b = 3)), forbid((c, b) -> c == b == 2 ? error("boom") : false, :c, :b)],
            tabulation_limit = 8)
    end
    pr = NegativeProjection(boom, 1)
    sub = _negative_request(Request(boom), pr, zeros(Int, 2, 0))
    err = try
        violates(sub.feasibility, [2, 2])
    catch e
        e
    end
    @test err isa ConstraintError && err.rule == rule_label(boom, parent_rule(pr, 1)) == "rule 2 on (c, b)"
    @test rule_label(pr.subspace, 1) == "rule 1 on (c, b)"
    @test occursin("rule 2 on (c, b) threw", message(() -> all_pairs(boom)))
end


@testitem "invalid: a negative sub-request shares its request's lazy-rule memos (§3.5, §12.19)" setup=[Checker, InvalidSetup] begin
    using UnitTestDesign: Request, NegativeProjection, _negative_request, violates
    calls = Tuple{Int, Symbol}[]
    # Rule 2 reads c and b, 9 combinations above tabulation_limit = 8, so it
    # is lazy; its scope omits a, so it applies to the negative rows at a.
    space = quietly() do
        TestSpace((a = [1, 2, Invalid(0)], b = [:x, :y, :z], c = [1, 2, 3], d = [true, false]);
            constraints = [forbid((a = 2, d = false)),
                           forbid(:c, :b) do c, b; push!(calls, (c, b)); c == 3 && b == :z end],
            tabulation_limit = 8)
    end
    @test space.tables[2].lazy !== nothing
    request = Request(space; strength = 2)
    pr = NegativeProjection(space, 1)
    sub = _negative_request(request, pr, zeros(Int, 3, 0))
    @test pr.rules == [2]
    # The memo dictionaries are the request's own.
    @test sub.feasibility.rule_memo[1] === request.feasibility.rule_memo[2]
    @test sub.context.memos[1] === request.context.memos[2]
    # A combination the request evaluated is not evaluated again: b = :x beside each c.
    @test !any(c -> violates(request.feasibility, [1, 1, c, 1]), 1:3)
    @test calls == [(1, :x), (2, :x), (3, :x)]
    @test !any(c -> violates(sub.feasibility, [1, c, 1]), 1:3)   # (b, c, d)
    @test length(calls) == 3
    # A combination new to the sub-request is evaluated once, however often
    # it is asked, and the request then knows the verdict too.
    for _ in 1:2, b in 2:3, c in 1:3
        @test violates(sub.feasibility, [b, c, 1]) == (b == 3 && c == 3)
    end
    @test length(calls) == 9 && allunique(calls)
    @test violates(request.feasibility, [1, 3, 3, 1]) && length(calls) == 9
    # So one generation evaluates each combination at most once: target
    # classification, the ordinary rows, each sub-request and validation
    # share one memo, with and without a group holding a, and with a
    # negative must-include row that the sub-request completes.
    for strength in 1:3, engine in (IPOG(), GND(seed = 2)), stronger in ([], [(:a, :b, :c) => 3])
        strength == 3 && !isempty(stronger) && continue
        empty!(calls)
        cases = covering(space; strength, engine, stronger, must_include = [(a = Invalid(0), c = 3)])
        @test cases[1].a === Invalid(0) && cases[1].c == 3
        @test !isempty(calls) && allunique(calls)
    end
end


@testitem "invalid: a negative sub-request's targets are the negative targets at its value (§6.1, §6.3, §9.7)" setup=[Checker, InvalidSetup] begin
    using UnitTestDesign: Request, NegativeProjection, TargetList, parent_row, _negative_request, _space_indices,
                          from_indices
    # The negative targets at (p, v), in the order coverage lists them, are
    # (p = v) at strength 1, then (p = v) beside each target of the
    # sub-request at (p, v). On these requests they come in the order of the
    # sub-request's own TargetList. Not always: where one group without p
    # becomes a prefix of another, the sub-request sorts the two the other
    # way (the item on groups that change order, below), so negative
    # generation finds the excluded ones on the sub-request's layout from
    # their targets, not from their order (`_sub_excluded`).
    interleaved = TestSpace((a = [1, 2], b = [1, Invalid(0), 2, Invalid(9)], c = [1, 2, 3], d = [Invalid(:x), 1, 2],
                             e = [1, 2]);
        constraints = [forbid((b = 2, c = 3)), forbid((a = 1, e = 2)), forbid((c = 1, d = 2))])
    spaces = [
        out_of_order() => ([(1, [(:c, :a, :e) => 3, (:b, :d) => 2]), (1, [(:a, :b) => 2]), (2, []),
                            (2, [(:c, :a, :e) => 3, (:b, :d) => 2]), (2, [(:a, :b, :c, :d) => 4]), (3, []),
                            (3, [(:a, :b, :c, :d) => 4])],
                           [(a = Invalid(0), e = 3), (c = Invalid(-1), a = 3, b = :y, d = false, e = 1),
                            (c = Invalid(-1),), (a = 1, b = :x)]),
        interleaved => ([(1, [(:a, :b, :c) => 2]), (1, [(:b, :c) => 2, (:a, :b, :d, :e) => 3]), (2, []),
                         (2, [(:a, :b, :c) => 3, (:b, :d, :e) => 3, (:c, :d, :e) => 3]), (3, []),
                         (3, [(:a, :b, :c, :d) => 4])],
                        [(b = Invalid(9), c = 2), (d = Invalid(:x),)]),
        test_space(grouped()) => ([(1, [(:a, :b, :c) => 3]), (2, [(:a, :b, :c) => 3]), (3, [])],
                                  [(a = Invalid(0), d = :x)]),
        test_space(two_invalid()) => ([(1, [(:a, :b) => 2]), (2, []), (3, [])], []),
        excluding() => ([(2, []), (3, [])], [(n = Invalid(-1), k = :y)]),
    ]
    for (space, (requests, must_include)) in spaces, (strength, stronger) in requests
        free = TestSpace(NamedTuple{Tuple(space.names)}(Tuple(space.values)))   # the same targets, all feasible
        every = coverage(NamedTuple[], free; strength, stronger).negative.missing
        measured = coverage(NamedTuple[], space; strength, stronger).negative
        @test isempty(measured.unknown)
        request = Request(space; strength, stronger, must_include)
        must = request.must_include
        for p in eachindex(space.names), position in (request.arity[p] + 1):length(request.candidates[p])
            v = space.values[p][request.candidates[p][position]]
            at(t) = haskey(t, space.names[p]) && t[space.names[p]] === v
            # Every negative target at (p, v), in target order; (p = v) alone first at strength 1.
            here = filter(at, every)
            @test (length(first(here)) == 1) == (strength == 1)
            if strength == 1 && !any(g -> p in g.first, request.groups[2:end])
                @test length(here) == 1   # no sub-request
                continue
            end
            pr = NegativeProjection(space, p)
            sub = _negative_request(request, pr, must[pr.kept, [j for j in axes(must, 2) if must[p, j] == position]])
            listed = [from_indices(space, _space_indices(request, parent_row(pr, t, position))) for t in TargetList(sub)]
            @test listed == filter(t -> length(t) > 1, here)
            # So too for the required and the excluded ones.
            required = filter(at, measured.missing)
            excluded = filter(at, [e.target for e in measured.excluded])
            @test filter(in(required), listed) == filter(t -> length(t) > 1, required)
            @test filter(in(excluded), listed) == filter(t -> length(t) > 1, excluded)
        end
    end
end


@testitem "invalid: a negative sub-request whose groups change order without its invalid parameter (§6.3, §6.7)" setup=[Checker, InvalidSetup] begin
    using UnitTestDesign: Request, NegativeProjection, TargetList, RequiredTargets, _Classified, _negative_targets!,
                          _negative_request, _ordinary_bound, _required_bits, _slot, _sub_excluded,
                          classify_negative_targets, from_indices, parent_row, _space_indices
    # A negative sub-request's groups are sorted again without the invalid
    # parameter p (`_groups`), so where one group without p becomes a prefix
    # of another, their supports come in the other order: (p1, p2, p3, p4)
    # sorts before (p1, p2, p4), but without p4 (p1, p2) sorts before
    # (p1, p2, p3). Negative generation finds the excluded targets on the
    # sub-request's layout from the targets themselves (`_sub_excluded`). At
    # f249ffc it read their numbers in the parent's walk as ids on that
    # layout, and all three requests below ended in internal errors (review
    # p5-core 1); 31bef0f handled the first two, with these rows and bounds,
    # and stopped on the third ("excluded target … out of target order").
    # Every design is judged by the oracle (`checked_design`).
    space_with(rule) = CheckSpace((p1 = [1, 2], p2 = [1, 2], p3 = [1, 2], p4 = [1, 2, CheckInvalid(:x)],
                                   p5 = [1, 2]), [rule])
    rule13 = ((:p1, :p3), (a, c) -> a == 1 && c == 1)
    rule12 = ((:p1, :p2), (a, b) -> a == 1 && b == 1)
    requests = [(space_with(rule13), 2, [(:p1, :p2, :p3, :p4) => 4, (:p1, :p2, :p4) => 3], 18, 18),
                (space_with(rule12), 1, [(:p1, :p2, :p4, :p5) => 3, (:p1, :p4) => 2], 15, 12),
                (space_with(rule12), 2, [(:p1, :p2, :p3, :p4, :p5) => 4, (:p1, :p2, :p4) => 3], 30, 24)]
    for (cs, strength, stronger, rows, bound) in requests
        space = test_space(cs)
        for engine in (IPOG(), GND(), Auto(), Compact(IPOG()))
            @testset "$stronger at $strength, $engine" begin
                cases = checked_design(space, cs; engine, strength, stronger)
                @test length(cases) == rows && cases.record.lower_bound == bound
            end
        end
        # The sub-request at p4 = Invalid(:x) lists the targets at that value
        # in another order than coverage does, and the ids found from the
        # excluded targets give it the list path's targets, counts and bound.
        request = Request(space; strength, stronger)
        p, position = 4, request.arity[4] + 1
        pr = NegativeProjection(space, p)
        sub = _negative_request(request, pr, zeros(Int, 4, 0))
        layout = TargetList(sub)
        free = TestSpace(NamedTuple{Tuple(space.names)}(Tuple(space.values)))   # the same targets, all feasible
        here = filter(t -> haskey(t, :p4) && t.p4 isa Invalid && length(t) > 1,
                      coverage(NamedTuple[], free; strength, stronger).negative.missing)
        listed = [from_indices(space, _space_indices(request, parent_row(pr, t, position))) for t in layout]
        @test issetequal(listed, here) && length(listed) == length(here) && listed != here
        negative = _negative_targets!(_Classified(request), request)
        slot = _slot(negative, request, p, position)
        required, excluded = classify_negative_targets(request)
        gone = [e.target[pr.kept] for e in excluded if e.target[p] == position && count(!=(0), e.target) > 1]
        ids = _sub_excluded(negative, slot, pr, layout)
        @test !isempty(gone) && ids == sort([findfirst(==(t), collect(layout)) for t in gone])
        st = RequiredTargets(layout, ids)
        sl = RequiredTargets(sub, [r[pr.kept] for r in required if r[p] == position && count(!=(0), r) > 1])
        @test st.counts == sl.counts && st.excluded == sl.excluded && _required_bits(st) == _required_bits(sl)
        @test _ordinary_bound(sub, st).rows == _ordinary_bound(sub, sl).rows
    end
end


@testitem "invalid: random negative sub-requests whose groups change order, against the oracle (§6.3, §6.7)" setup=[Checker, InvalidSetup] begin
    using Random: randperm
    using UnitTestDesign: Request, NegativeProjection, TargetList, RequiredTargets, _Classified, _negative_targets!,
                          _negative_request, _ordinary_bound, _required_bits, _slot, _sub_excluded,
                          classify_negative_targets
    # The shape of the item above, drawn at random (review p5-core 2: the
    # random groups of test_engines.jl rarely draw it). Around a parameter p
    # with an Invalid value, two groups G2 = A ∪ {p} and G1 = A ∪ B ∪ {p},
    # where B holds a parameter between A's last and p: G1 sorts before G2,
    # but without p G2's members are a prefix of G1's and sort first. Pair
    # rules, mostly on other parameters, exclude some negative targets, and
    # sometimes another parameter has an Invalid value or another group
    # joins. Each design, from IPOG and GND, is judged by the oracle, and
    # each sub-request's targets, from the excluded ids, are the list path's,
    # with the same counts and bound.
    rng = Xoshiro(0x2026_1006_c1)
    drawn, reordered, with_excluded = Ref(0), Ref(0), Ref(0)
    while drawn[] < 60
        n = rand(rng, 4:6)
        p = rand(rng, 3:n)
        before = collect(1:(p - 1))
        cut = rand(rng, 1:(p - 2))
        A = sort(before[1:cut][randperm(rng, cut)[1:rand(rng, 1:cut)]])
        pool = [q for q in 1:n if q != p && q > last(A)]
        B = sort(unique([rand(rng, filter(<(p), pool)); filter(_ -> rand(rng) < 0.4, pool)]))
        strength = rand(rng, 1:2)
        G2, G1 = sort([A; p]), sort([A; B; p])
        length(G2) > strength || continue
        groups = [G1 => rand(rng, (strength + 1):length(G1)), G2 => rand(rng, (strength + 1):length(G2))]
        if rand(rng) < 0.3
            k = rand(rng, (strength + 1):n)
            push!(groups, sort(randperm(rng, n)[1:k]) => rand(rng, (strength + 1):k))
        end
        names = [Symbol(:p, i) for i in 1:n]
        domains = [Any[1:rand(rng, 2:3)...] for _ in 1:n]
        push!(domains[p], CheckInvalid(:x))
        rand(rng) < 0.3 && (q = rand(rng, filter(!=(p), 1:n)); push!(domains[q], CheckInvalid(:y)))
        rules = []
        for _ in 1:rand(rng, 1:3)
            a, b = sort(randperm(rng, n)[1:2])
            (a == p || b == p) && rand(rng) < 0.7 && continue
            va, vb = rand(rng, 1:2), rand(rng, 1:2)
            push!(rules, ((names[a], names[b]), (x, y) -> x == va && y == vb))
        end
        cs = CheckSpace(names, domains, rules)
        space = test_space(cs)
        stronger = [Tuple(names[g]) => s for (g, s) in groups]
        drawn[] += 1
        for engine in (IPOG(), GND())
            @testset "request $(drawn[]), $engine" begin
                checked_design(space, cs; engine, strength, stronger)
            end
        end
        request = Request(space; strength, stronger)
        negative = _negative_targets!(_Classified(request), request)
        required, _ = classify_negative_targets(request)
        for q in 1:n, position in (request.arity[q] + 1):length(request.candidates[q])
            strength > 1 || any(g -> q in g.first, request.groups[2:end]) || continue
            slot = _slot(negative, request, q, position)
            pr = NegativeProjection(space, q)
            sub = _negative_request(request, pr, zeros(Int, n - 1, 0))
            layout = TargetList(sub)
            st = RequiredTargets(layout, _sub_excluded(negative, slot, pr, layout))
            sl = RequiredTargets(sub, [r[pr.kept] for r in required if r[q] == position && count(!=(0), r) > 1])
            @test st.counts == sl.counts && st.excluded == sl.excluded && _required_bits(st) == _required_bits(sl)
            @test _ordinary_bound(sub, st).rows == _ordinary_bound(sub, sl).rows
            # Whether the sub-request's groups come in another order than the parent's.
            kept = [pr.renumber[filter(!=(q), g)] => s - 1 for (g, s) in request.groups[2:end] if q in g]
            if [g for (g, _) in kept] != [g for (g, _) in sub.groups[2:end]]
                reordered[] += 1
                with_excluded[] += !isempty(st.excluded)
            end
        end
    end
    @info "Negative sub-requests whose groups change order" drawn = drawn[] reordered = reordered[] with_excluded = with_excluded[]
    @test reordered[] >= 40 && with_excluded[] >= 15
end


@testitem "invalid: the certifier's negative recount agrees with the list's on failing designs (§1.21, §6.7)" setup=[Checker, InvalidSetup, RecountVerdict] begin
    using UnitTestDesign: Request, TargetList, _Classified, _check_fit, _decode!, _generate, _recount,
                          classify_negative_targets
    # `generate` certifies the negative rows by recounting them on the
    # layout against the numbers of the excluded negative targets
    # (`_recount(request, rows, ::_NegativeTargets)`). Review p5-evidence 1:
    # no test gave it a design that fails, so a recount that checked nothing
    # passed every test. Here, on random spaces with Invalid values, rules,
    # strengths 1 to 3 and sometimes a group, each IPOG design's negative
    # rows, with each row dropped and with ordinary values changed, get the
    # verdict written out from lists (`layout_verdict`, over the negative
    # targets in the order of §9.7): the first negative target that is
    # required and held by no negative row, or excluded and held by one; and,
    # wherever no row holds an excluded target, the message of the list
    # recount of `classify_negative_targets` (31bef0f's certification). Enough
    # of them must fail that a vacuous recount fails this item.
    rng = Xoshiro(0x2026_1006_e1)
    compared, failed, held = Ref(0), Ref(0), Ref(0)
    for trial in 1:150
        n = rand(rng, 3:6)
        domains = [Any[1:rand(rng, 1:4)...] for _ in 1:n]
        for _ in 1:rand(rng, 1:3)
            p = rand(rng, 1:n)
            push!(domains[p], Invalid(100 + length(domains[p])))
        end
        names = [Symbol(:p, i) for i in 1:n]
        rules = Constraint[]
        rand(rng) < 0.6 && push!(rules, forbid((a, b) -> a == 1 && b == 1, names[1], names[2]))
        rand(rng) < 0.3 && push!(rules, forbid((a, b) -> a == 2 && b == 1, names[2], names[3]))
        space = TestSpace(NamedTuple{Tuple(names)}(Tuple(domains)); constraints = rules)
        strength = rand(rng, 1:min(3, n))
        stronger = rand(rng) < 0.3 && n >= 4 ? [Tuple(names[1:4]) => min(strength + 1, 4)] : []
        request = Request(space; strength, stronger)
        classified = _Classified(request)
        design = _generate(_check_fit(IPOG(), request), request, classified)
        negative = classified.negative
        # A request with no negative target required is recounted too, as
        # `validate_design` recounts it (the maintainer's review, R3): here
        # that is a space with no valid row (one of the 150), whose design is
        # empty, and the recount accepts it with every target excluded.
        negative === nothing && continue
        list, excluded = classify_negative_targets(request)
        gone = Set(e.target for e in excluded)
        walked = Vector{Int}[]   # every negative target, in the order of §9.7
        for support in TargetList(request).supports, q in support, v in (request.arity[q] + 1):length(request.candidates[q])
            rest = filter(!=(q), support)
            for code in 0:(prod(request.arity[rest]; init = 1) - 1)
                target = _decode!(zeros(Int, n), code, rest, request.arity)
                target[q] = v
                push!(walked, target)
            end
        end
        m = design.matrix
        rows = m[:, [any(i -> m[i, j] > request.arity[i], axes(m, 1)) for j in axes(m, 2)]]
        variants = Matrix{Int}[rows]
        for j in axes(rows, 2)
            push!(variants, rows[:, setdiff(axes(rows, 2), j)])
        end
        for _ in 1:4
            isempty(rows) && break   # no negative row to change
            changed = copy(rows)
            i, j = rand(rng, axes(changed, 1)), rand(rng, axes(changed, 2))
            changed[i, j] > request.arity[i] && continue   # the invalid value stays
            request.arity[i] > 1 || continue
            changed[i, j] = mod1(changed[i, j] + rand(rng, 1:(request.arity[i] - 1)), request.arity[i])
            push!(variants, changed)
        end
        for v in variants
            ours, listed = message(() -> _recount(request, v, negative)), message(() -> _recount(request, v, list))
            ours == "no error" && (ours = nothing)
            listed == "no error" && (listed = nothing)
            @test ours == layout_verdict(request, v, walked, gone)
            if ours !== nothing && startswith(ours, "internal error: excluded target")
                held[] += 1
            else
                @test ours == listed
            end
            ours === nothing && @test _recount(request, v, negative) == _recount(request, v, list) == negative.required
            compared[] += 1
            failed[] += ours !== nothing
        end
    end
    @info "Negative recounts compared" compared = compared[] failed = failed[] held = held[]
    @test compared[] > 1000 && failed[] > 800 && held[] > 5
end


@testitem "invalid: the negative recount runs with no negative target required, and names a held excluded one (§1.4, §1.21)" setup=[Checker, InvalidSetup, RecountVerdict] begin
    using UnitTestDesign: Request, TargetList, _Classified, _NegativeTargets, _check_fit, _decode!, _generate,
                          nrequired, validate_design
    # The maintainer's review, R3: `validate_design` skipped the negative
    # recount when classification required no negative target, but the
    # recount also checks that no negative row holds a target classification
    # excluded (§1.4), so a classification that wrongly excluded every
    # negative target let a negative row holding one pass. With a right
    # classification a valid negative row holds at least one required
    # negative target, so "none required, beside a negative row" is exactly
    # the wrong classification the check is for. Here it is made by hand:
    # the request's own negative targets with every one excluded, beside the
    # design's negative rows. At 81f8056 `validate_design` passes it.
    space = TestSpace((a = [1, 2, Invalid(0)], b = [:x, :y, Invalid(:bad)], c = [true, false]);
                      constraints = [forbid((b = :y, c = false))])
    request = Request(space; strength = 2)
    classified = _Classified(request)
    design = _generate(_check_fit(IPOG(), request), request, classified)
    m, targets, right = design.matrix, classified.targets, classified.negative
    holds = [any(i -> m[i, j] > request.arity[i], axes(m, 1)) for j in axes(m, 2)]
    @test count(holds) >= 2 && right.required > 0
    @test validate_design(request, m, targets; negative = right) == nrequired(targets)
    # Every negative target excluded: the recount reads the layout, the
    # excluded numbers and the required count.
    total = right.required + length(right.ids)
    none = _NegativeTargets(right.layout, 0, empty(right.excluded), collect(1:total), right.first, right.count,
                            right.excluded_at, right.alone)
    walked = Vector{Int}[]   # every negative target, in the order of §9.7
    for support in TargetList(request).supports, q in support, v in (request.arity[q] + 1):length(request.candidates[q])
        rest = filter(!=(q), support)
        for code in 0:(prod(request.arity[rest]; init = 1) - 1)
            push!(walked, setindex!(_decode!(zeros(Int, 3), code, rest, request.arity), v, q))
        end
    end
    @test length(walked) == total
    # The first negative target in target order that a negative row holds is named, by `_held`.
    msg = message(() -> validate_design(request, m, targets; negative = none))
    @test startswith(msg, "internal error: excluded target") &&
          endswith(msg, "classification found no valid row that holds it (contract §1.4)")
    @test msg == layout_verdict(request, m[:, holds], walked, Set(walked))
    @test_throws ErrorException validate_design(request, m, targets; negative = none)
    # Each negative row alone beside the ordinary rows: still named.
    for j in findall(holds)
        keep = [!holds[k] || k == j for k in axes(m, 2)]
        @test message(() -> validate_design(request, m[:, keep], targets; negative = none)) ==
              layout_verdict(request, m[:, [j]], walked, Set(walked))
    end
    # With no negative row, nothing is held and none is required: it passes,
    # its count and numbers being the layout's.
    @test validate_design(request, m[:, .!holds], targets; negative = none) == nrequired(targets)
    # The recount runs with no negative row too, so it still checks that the
    # numbers and the count are the layout's (review p5f-evidence 2): one
    # negative target neither required nor excluded, or a required count
    # that isn't the number left, is named. A recount only "whenever the
    # design has negative rows" passes both.
    unnumbered = _NegativeTargets(right.layout, 0, empty(right.excluded), collect(1:(total - 1)), right.first,
                                  right.count, right.excluded_at, right.alone)
    @test_throws ErrorException validate_design(request, m[:, .!holds], targets; negative = unnumbered)
    @test startswith(message(() -> validate_design(request, m[:, .!holds], targets; negative = unnumbered)),
                     "internal error: required target")
    miscounted = _NegativeTargets(right.layout, 3, empty(right.excluded), collect(1:total), right.first,
                                  right.count, right.excluded_at, right.alone)
    @test message(() -> validate_design(request, m[:, .!holds], targets; negative = miscounted)) ==
          "internal error: the negative targets' excluded numbers and count are not the request's"
end
