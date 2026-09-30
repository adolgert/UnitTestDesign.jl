using Test
using TestItemRunner

# The model's value layer and TestSpace (src/space.jl): plan Phase 2 steps 1,
# 2 and 8. Test names cite the contract clauses (docs/src/dev/contract.md).

@testitem "space: the target screen (plan; §2.10, §12.1, §12.4, §12.18)" begin
    space = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])
    @test space.names == [:mode, :solver, :tol]
    @test parameters(space) == [:mode, :solver, :tol]
    @test parameters(space) !== space.names
    @test space.values == [[:fast, :exact], [:none, :lu, :qr], [1e-3, 1e-6]]
    @test space.values[3] isa Vector{Float64}
    @test UnitTestDesign.arity(space) == [2, 3, 2]
    @test length(space) === 12
    @test length(space.constraints) == 2
    @test space.tabulation_limit == 10^5

    # Rule 1 forbids fast mode with a solver; rule 2 exact mode at 1e-3.
    t1, t2 = space.tables
    @test t1.scope == [1, 2] && t1.lazy === nothing
    @test t1.forbidden == Set([(1, 2), (1, 3)])
    @test t2.scope == [1, 3]
    @test t2.forbidden == Set([(2, 1)])
    @test space.constraints[1].polarity == :require
    @test space.constraints[2].polarity == :forbid
    @test UnitTestDesign.rule_label(space, 1) == "@require(mode == :exact || solver == :none)"
    @test UnitTestDesign.rule_label(space, 2) == "exact mode needs a tight tolerance"

    # The pairs form builds the same space.
    pairs_space = TestSpace(:mode => [:fast, :exact], :solver => [:none, :lu, :qr],
        :tol => [1e-3, 1e-6]; constraints = space.constraints)
    @test pairs_space.names == space.names
    @test [t.forbidden for t in pairs_space.tables] == [t.forbidden for t in space.tables]
    # The caller's constraint vector is copied.
    rules = [@forbid(mode == :fast)]
    s = TestSpace((mode = [:fast, :exact],); constraints = rules)
    push!(rules, @forbid(mode == :exact))
    @test length(s.constraints) == 1
end


@testitem "space: domains keep values and element types (§2.1–§2.4, §2.6–§2.9)" begin
    space = TestSpace((x = Any[1, 1.0], y = [1, 2, 3], r = 1:3, t = (1, :a, "s"),
                       f = Any[Float32(1), 1.0], z = Any[0.0, -0.0], one = [:only]))
    # Any[1, 1.0] is two choices and stays a Vector{Any} (§2.2, §2.3).
    @test space.values[1] isa Vector{Any}
    @test length(space.values[1]) == 2
    @test space.values[1][1] isa Int && space.values[1][2] isa Float64
    # A homogeneous vector keeps its concrete element type; a range becomes a vector.
    @test space.values[2] isa Vector{Int}
    @test space.values[3] isa Vector{Int} && space.values[3] == [1, 2, 3]
    # A tuple becomes a vector without converting its values.
    @test space.values[4] isa Vector
    @test map(typeof, space.values[4]) == [Int, Symbol, String]
    # Float32(1) and 1.0 differ; 0.0 and -0.0 differ (§2.2). A single value is allowed (§2.7).
    @test length(space.values[5]) == 2 && space.values[5][1] isa Float32
    @test length(space.values[6]) == 2
    @test UnitTestDesign.arity(space) == [2, 3, 3, 3, 2, 2, 1]

    # Domains are copied (§2.8).
    domain = [1, 2, 3]
    s = TestSpace((a = domain,))
    push!(domain, 4)
    @test s.values[1] == [1, 2, 3]
    @test s.values[1] !== domain

    # nothing and missing are ordinary values (§2.9).
    s = TestSpace((a = [nothing, 1], b = [missing, :m]))
    @test s.values[1] isa Vector{Union{Nothing,Int}}
    @test UnitTestDesign.value_index(s, 1, nothing) == 1
    @test UnitTestDesign.value_index(s, 2, missing) == 1
    @test UnitTestDesign.ordinary_indices(s, 1) == [1, 2]
    @test isequal(UnitTestDesign.from_indices(s, [1, 1]), (a = nothing, b = missing))
    @test UnitTestDesign.case_indices(s, (b = missing,)) == [0, 1]
end


@testitem "space: rejected parameters and domains (§0.1, §2.5, §2.6, §2.10, §12.7)" begin
    function message(f)
        err = try
            f()
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        return err isa ArgumentError ? err.msg : ""
    end
    # At least one parameter; distinct Symbol names (§2.10).
    @test occursin("at least one parameter", message(() -> TestSpace()))
    @test occursin("at least one parameter", message(() -> TestSpace(NamedTuple())))
    @test occursin("parameter `a` appears twice", message(() -> TestSpace(:a => [1], :a => [2])))
    @test occursin("\"a\"", message(() -> TestSpace("a" => [1])))
    # nothing and missing are values, not names (§12.7).
    @test occursin("`nothing`", message(() -> TestSpace(:nothing => [1])))
    @test occursin("`missing`", message(() -> TestSpace((missing = [1], b = [2]))))
    # Nonempty, ordered, finite collections (§2.6).
    @test occursin("parameter `a` has no values", message(() -> TestSpace((a = [],))))
    @test occursin("parameter `a` has no values", message(() -> TestSpace((a = (),))))
    @test occursin("unordered", message(() -> TestSpace((tol = Set([1.0, 2.0]),))))
    @test occursin("unordered", message(() -> TestSpace((d = Dict(1 => 2),))))
    @test occursin("parameter `g`", message(() -> TestSpace((g = (x for x in 1:3),))))
    @test occursin("[x] for a single value", message(() -> TestSpace((mode = :fast,))))
    @test occursin("parameter `s`", message(() -> TestSpace((s = "abc",))))
    # A value listed twice, by identity (§2.5, §2.2: NaN is NaN).
    @test occursin("parameter `tol` lists `1.0` twice",
                   message(() -> TestSpace((tol = [1.0, 1e-3, 1.0],))))
    @test occursin("lists `NaN` twice", message(() -> TestSpace((x = [NaN, 1.0, NaN],))))
    @test occursin("lists `:a` twice", message(() -> TestSpace((x = (:a, :b, :a),))))
    @test occursin("lists `[1, 2]` twice", message(() -> TestSpace((x = [[1, 2], [1, 2]],))))
    # The same value in two domains is allowed (§2.5).
    @test TestSpace((a = [1, 2], b = [1, 2])) isa TestSpace
    # Keywords and the constraints list.
    @test occursin("tabulation_limit", message(() -> TestSpace((a = [1],); tabulation_limit = 0)))
    @test occursin("tabulation_limit", message(() -> TestSpace((a = [1],); tabulation_limit = 1.5)))
    @test occursin("constraints[2]", message(() ->
        TestSpace((a = [1, 2],); constraints = [@forbid(a == 1), (:a,) => (a -> a == 2)])))
    @test occursin("vector of rules", message(() -> TestSpace((a = [1],); constraints = :a)))
    # A single rule is accepted as a one-rule list.
    @test length(TestSpace((a = [1, 2],); constraints = @forbid(a == 1)).tables) == 1
end


@testitem "space: same_value is value identity (§2.1, §2.2, §2.12, §2.13)" begin
    using UnitTestDesign: same_value
    @test same_value(1, 1)
    @test !same_value(1, 1.0)
    @test !same_value(Float32(1), 1.0)
    @test !same_value(0.0, -0.0)
    @test same_value(NaN, NaN)
    @test same_value(nothing, nothing)
    @test same_value(missing, missing)
    @test !same_value(:x, "x")
    @test same_value([1, 2], [1, 2])
    # Invalid compares its wrapped value by the same rule and never equals a bare value.
    @test same_value(Invalid(1), Invalid(1))
    @test !same_value(Invalid(1), Invalid(1.0))
    @test !same_value(Invalid(1), 1)
    @test !same_value(1, Invalid(1))
    @test same_value(Invalid(NaN), Invalid(NaN))
    @test same_value(Invalid{Any}(1), Invalid(1))
    # A partition's identity is its name (§2.13), and it is not the same value as that name.
    tiny = Partition(:tiny, Returns(1e-9))
    @test same_value(tiny, Partition(:tiny, rng -> rand(rng)))
    @test !same_value(tiny, Partition(:huge, Returns(1e9)))
    @test !same_value(tiny, :tiny)
    @test !same_value(:tiny, tiny)
    # The duplicate check's hashable key agrees with same_value.
    vals = Any[1, 1.0, Float32(1), 0.0, -0.0, NaN, NaN, :x, "x", nothing, missing,
                 Invalid(1), Invalid(1.0), Invalid{Any}(1), tiny, Partition(:tiny, identity),
                 Partition(:huge, identity), [1, 2], [1, 2]]
    key = UnitTestDesign._identity_key
    @test all(isequal(key(a), key(b)) == same_value(a, b) for a in vals, b in vals)
end


@testitem "space: Invalid and Partition wrappers (§4.1, §4.12, §5.1, §5.2)" begin
    f = Returns(1e-9)
    # Nested wrappers are rejected when built (§4.12).
    @test_throws ArgumentError Invalid(Invalid(0))
    @test_throws ArgumentError Invalid(Partition(:tiny, f))
    @test_throws ArgumentError Partition(:tiny, Invalid(1))
    @test_throws ArgumentError Partition(:tiny, Partition(:small, f))
    # A partition's name is a Symbol (§4.1), and its draw is callable.
    @test_throws ArgumentError Partition("tiny", f)
    err = try Partition(:tiny, 1e-9) catch e; e end
    @test err isa ArgumentError && occursin("Returns(1.0e-9)", err.msg)
    # Display uses the name, and the wrapped value.
    @test repr(Partition(:tiny, f)) == "Partition(:tiny)"
    @test repr(Invalid(-1)) == "Invalid(-1)"
    @test repr(Invalid("s")) == "Invalid(\"s\")"
    @test Invalid(1) == Invalid(1) && isequal(Invalid([1]), Invalid([1]))
    @test hash(Invalid([1])) == hash(Invalid([1]))
    @test Partition(:a, f) == Partition(:a, identity)
    @test hash(Partition(:a, f)) == hash(Partition(:a, identity))
    # hasinvalid (§5.1).
    @test hasinvalid((n = Invalid(-1), m = :a))
    @test !hasinvalid((n = 1, m = :a))
    @test hasinvalid((1, Invalid(0)))
    @test !hasinvalid((1, Partition(:tiny, f)))
    @test hasinvalid(Any[1, Invalid(0)])
    @test !hasinvalid(NamedTuple())
end


@testitem "space: wrapper domains and collisions (§2.12, §4.2–§4.4, §5.2)" begin
    f = Returns(1e-9)
    message(g) = try g(); "" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError" end
    # Invalid(1) beside 1: two choices (§2.12).
    s = TestSpace((n = [1, 2, Invalid(1)], m = [:a, :b]))
    @test UnitTestDesign.arity(s) == [3, 2]
    @test UnitTestDesign.ordinary_indices(s, 1) == [1, 2]
    @test UnitTestDesign.invalid_indices(s, 1) == [3]
    @test UnitTestDesign.invalid_indices(s, 2) == Int[]
    @test UnitTestDesign.value_index(s, 1, 1) == 1
    @test UnitTestDesign.value_index(s, 1, Invalid(1)) == 3
    @test UnitTestDesign.value_index(s, 1, Invalid{Any}(1)) == 3
    @test_throws ArgumentError UnitTestDesign.value_index(s, 1, Invalid(2))
    @test occursin("lists `Invalid(1)` twice", message(() -> TestSpace((n = [1, Invalid(1), Invalid(1)],))))
    # A domain of only Invalid values is rejected (§5.2); a partition counts as ordinary (§4.2).
    @test occursin("only Invalid values", message(() -> TestSpace((n = [Invalid(0), Invalid(-1)], m = [:a]))))
    @test TestSpace((n = [Partition(:tiny, f), Invalid(0)],)) isa TestSpace
    # Partition names are unique within a parameter (§4.3).
    @test occursin("two partitions named :tiny",
                   message(() -> TestSpace((size = [Partition(:tiny, f), Partition(:tiny, identity)],))))
    # A raw Symbol equal to a partition name in the same domain (§4.4), in either order.
    @test occursin("both the Symbol :tiny and the partition Partition(:tiny)",
                   message(() -> TestSpace((size = [Partition(:tiny, f), :tiny],))))
    @test occursin("Partition(:tiny)", message(() -> TestSpace((size = [:tiny, Partition(:tiny, f)],))))
    # ... but the same Symbol in another parameter is allowed (§4.4).
    s = TestSpace((size = [Partition(:tiny, f), Partition(:huge, f), 100], mode = [:a, :b, :tiny]))
    @test UnitTestDesign.ordinary_indices(s, 1) == [1, 2, 3]
    @test s.values[1][1] isa Partition
end


@testitem "space: value lookup and index round trips (§2.11, §4.5)" begin
    using UnitTestDesign: value_index, case_indices, from_indices, parameter_index, rule_value
    tiny = Partition(:tiny, Returns(1e-9))
    space = TestSpace((size = [tiny, Partition(:huge, Returns(1e9)), 100],
                       n = Any[1, 1.0, Invalid(-1)], mode = [:a, :b, :tiny]))
    # A partition by its wrapper or by its name (§2.11).
    @test value_index(space, 1, tiny) == 1
    @test value_index(space, 1, Partition(:tiny, identity)) == 1
    @test value_index(space, 1, :tiny) == 1
    @test value_index(space, :size, :huge) == 2
    @test value_index(space, 1, 100) == 3
    # A raw Symbol in another parameter is itself, not a partition.
    @test value_index(space, 3, :tiny) == 3
    @test_throws ArgumentError value_index(space, 3, tiny)
    # Identity: 1 and 1.0 are different entries.
    @test value_index(space, 2, 1) == 1
    @test value_index(space, 2, 1.0) == 2
    @test value_index(space, 2, Invalid(-1)) == 3
    # Unmatched values name the parameter, the value, and the domain.
    err = try value_index(space, 1, 100.0) catch e; e end
    @test err isa ArgumentError
    @test occursin("100.0", err.msg) && occursin("`size`", err.msg) && occursin("[Partition(:tiny)", err.msg)
    @test occursin("Int64", err.msg)  # the hint: same isequal, different type
    err = try value_index(space, 2, -1) catch e; e end
    @test err isa ArgumentError && occursin("`n`", err.msg)
    # Parameter names.
    @test parameter_index(space, :mode) == 3
    err = try parameter_index(space, :colour) catch e; e end
    @test err isa ArgumentError && occursin("`colour`", err.msg) && occursin("size, n, mode", err.msg)

    # case_indices and from_indices, wrappers kept.
    @test case_indices(space, (n = Invalid(-1), size = :tiny)) == [1, 3, 0]
    @test case_indices(space, NamedTuple()) == [0, 0, 0]
    @test case_indices(space, (tiny, 1.0, :b)) == [1, 2, 2]
    @test_throws ArgumentError case_indices(space, (tiny, 1.0))
    err = try case_indices(space, (colour = :red,)) catch e; e end
    @test err isa ArgumentError && occursin("size, n, mode", err.msg)
    row = from_indices(space, [1, 3, 2])
    @test row.size === tiny
    @test row.n === Invalid(-1)
    @test keys(row) == (:size, :n, :mode)
    @test from_indices(space, [0, 2, 0]) === (n = 1.0,)
    @test from_indices(space, [0, 0, 0]) === NamedTuple()
    @test_throws ArgumentError from_indices(space, [1, 1])
    for key in Iterators.product(1:3, 1:3, 1:3)
        idx = collect(key)
        @test case_indices(space, from_indices(space, idx)) == idx
        @test case_indices(space, Tuple(from_indices(space, idx))) == idx
    end
    partial = (mode = :tiny, size = Partition(:huge, identity))
    @test from_indices(space, case_indices(space, partial)).size.name == :huge
    @test keys(from_indices(space, case_indices(space, partial))) == (:size, :mode)

    # What rules see (§4.5, §5.8).
    @test rule_value(space, 1, 1) === :tiny
    @test rule_value(space, 1, 3) === 100
    @test rule_value(space, 2, 2) === 1.0
    @test_throws ArgumentError rule_value(space, 2, 3)
end


@testitem "space: the row reader and its four input errors (§2.11)" begin
    using UnitTestDesign: _row_indices, _row_list
    message(f) = try f(); "no error" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError: $e" end
    tiny = Partition(:tiny, Returns(1e-9))
    space = TestSpace((size = [tiny, 100], n = Any[1, 1.0, Invalid(-1)], mode = [:a, :b]))
    row_of(row; complete = false, section = nothing, hint = nothing) =
        _row_indices(space, row; what = "row 7", section, complete, hint)
    # A NamedTuple, in any order and partial unless `complete`; a tuple or a
    # vector in parameter order; a partition by its name.
    @test row_of((mode = :b, size = :tiny)) == [1, 0, 2]
    @test row_of((:tiny, 1.0, :b)) == row_of(Any[:tiny, 1.0, :b]) == row_of([tiny, 1.0, :b]) == [1, 2, 2]
    @test row_of((size = 100, n = Invalid(-1), mode = :a); complete = true) == [2, 3, 1]
    # The four errors, with and without a contract section.
    @test message(() -> row_of(5)) ==
          "row 7 is a Int64; a row is a NamedTuple, or a tuple or vector with one value per parameter"
    @test message(() -> row_of(Set([1]); section = "§1.13")) ==
          "row 7 is a Set{Int64}; a row is a NamedTuple, or a tuple or vector with one value per " *
          "parameter (contract §1.13)"
    @test message(() -> row_of([tiny, 1])) == "row 7 has 2 values; the space has 3 parameters (size, n, mode)"
    @test message(() -> row_of((tiny, 1); section = "§1.13")) ==
          "row 7 has 2 values; the space has 3 parameters (size, n, mode) (contract §1.13)"
    @test message(() -> row_of((colour = :red,); section = "§1.13")) ==
          "row 7: `colour` is not a parameter of this space; the parameters are size, n, mode"
    @test startswith(message(() -> row_of((tiny, 2, :a))), "row 7: 2 is not a value of `n`")
    @test message(() -> row_of((n = 1,); complete = true)) ==
          "row 7, (n = 1,), has no value for `size` and `mode`; it must name every parameter"
    @test message(() -> row_of((n = 1, mode = :a); complete = true, section = "§1.13")) ==
          "row 7, (n = 1, mode = :a), has no value for `size`; it must name every parameter (contract §1.13)"
    # A caller's hint follows the missing-value error only, before the section.
    hinted(row) = message(() -> row_of(row; complete = true, section = "§1.13", hint = "use g instead"))
    @test hinted((n = 1,)) ==
          "row 7, (n = 1,), has no value for `size` and `mode`; it must name every parameter; use g instead " *
          "(contract §1.13)"
    @test message(() -> row_of((n = 1,); complete = true, hint = "use g instead")) ==
          "row 7, (n = 1,), has no value for `size` and `mode`; it must name every parameter; use g instead"
    @test hinted(5) == message(() -> row_of(5; section = "§1.13"))
    @test hinted((tiny, 1)) == message(() -> row_of((tiny, 1); section = "§1.13"))
    @test hinted((colour = :red,)) == message(() -> row_of((colour = :red,)))

    # The collection reader reads an iterator once and refuses a single row.
    rows_of(input) = _row_list(input; what = "f takes rows", fix = row -> "f([$(repr(row))])", section = "§0")
    once = Iterators.Stateful([(1, 2), (3, 4)])
    @test rows_of(once) == [(1, 2), (3, 4)] && isempty(once)
    @test rows_of(((a = 1,), (a = 2,))) == [(a = 1,), (a = 2,)]
    @test rows_of([]) == []
    @test message(() -> rows_of((a = 1,))) == "f takes rows; wrap a single row in a vector: f([(a = 1,)])"
    @test message(() -> rows_of((1, :x))) == "f takes rows; wrap a single row in a vector: f([(1, :x)])"
    @test message(() -> rows_of([1, :x])) == "f takes rows; wrap a single row in a vector: f([Any[1, :x]])"
    # The input itself, or, with `as_tuple`, the tuple of the elements of one
    # that is neither a tuple nor a vector.
    @test message(() -> rows_of(Dict(:a => 1))) == "f takes rows; wrap a single row in a vector: f([Dict(:a => 1)])"
    @test message(() -> rows_of("ab")) == "f takes rows; wrap a single row in a vector: f([\"ab\"])"
    tuple_of(input) = _row_list(input; what = "f takes rows", fix = row -> "f([$(repr(row))])", as_tuple = true)
    @test message(() -> tuple_of(x for x in (1, :x))) == "f takes rows; wrap a single row in a vector: f([(1, :x)])"
    @test message(() -> tuple_of(Dict(:a => 1))) == "f takes rows; wrap a single row in a vector: f([(:a => 1,)])"
    @test message(() -> tuple_of("ab")) == "f takes rows; wrap a single row in a vector: f([('a', 'b')])"
    @test message(() -> tuple_of([1, :x])) == message(() -> rows_of([1, :x]))
    @test message(() -> tuple_of((a = 1,))) == message(() -> rows_of((a = 1,)))
    @test message(() -> rows_of(5)) == "f takes rows, such as a vector of NamedTuples or tuples; got 5 (contract §0)"
    # The caller may call a row something else.
    cases_of(input) = _row_list(input; what = "g takes cases", noun = "case", fix = row -> "g([$(repr(row))])")
    @test message(() -> cases_of((a = 1,))) == "g takes cases; wrap a single case in a vector: g([(a = 1,)])"
    @test message(() -> cases_of([1, :x])) == "g takes cases; wrap a single case in a vector: g([Any[1, :x]])"
end


@testitem "space: active tables for negative rows (§5.4–§5.6, §12.22)" begin
    using UnitTestDesign: active_tables, active_rules
    space = TestSpace((n = [1, 2, Invalid(0)], m = [:a, :b], k = [:x, :y]);
        constraints = [
            @forbid(n == 2 && m == :b),
            @forbid(m == :a && k == :y),
            forbid(case -> case.k == :x && case.n == 1),
            @forbid(k == :x && n == 2),
        ])
    t = space.tables
    @test active_rules(space, 0) == [1, 2, 3, 4]
    @test active_tables(space, 0) == t
    # A negative row at n skips rules 1 and 4 (they read n) and the whole-case rule 3.
    @test active_rules(space, 1) == [2]
    @test active_tables(space, 1) == [t[2]]
    @test active_rules(space, 2) == [4]
    @test active_rules(space, 3) == [1]
    @test all(tab -> !(1 in tab.scope), active_tables(space, 1))
    @test_throws ArgumentError active_rules(space, 4)
    @test_throws ArgumentError active_rules(space, -1)
    # No rule: every p gives an empty set.
    free = TestSpace((a = [1, Invalid(2)],))
    @test isempty(active_tables(free, 0)) && isempty(active_tables(free, 1))
end


@testitem "space: the candidates of each kind of row (§5.4, §5.5)" begin
    using UnitTestDesign: _candidates
    space = TestSpace((n = [1, Invalid(0), 2, Invalid(9)], m = [:a, :b], k = [Invalid(:z), :x, :y]))
    # An ordinary row: every parameter's ordinary values.
    @test _candidates(space, 0, 0) == [[1, 3], [1, 2], [2, 3]] == space.ordinary
    # A negative row: its invalid value at its parameter, ordinary values elsewhere.
    @test _candidates(space, 1, 4) == [[4], [1, 2], [2, 3]]
    @test _candidates(space, 3, 1) == [[1, 3], [1, 2], [1]]
end


@testitem "space: the mixed-radix code of target order and its inverse (§9.7)" begin
    using UnitTestDesign: _code, _decode!
    radix = [3, 1, 4, 2]
    for support in ([1, 3, 4], [4, 1], [3], [1, 2, 3, 4])
        n = prod(radix[support])
        rows = [_decode!(fill(-1, 4), c, support, radix) for c in 0:(n - 1)]
        # Each code gives one assignment, only at the support, within the radix.
        @test allunique(rows) && all(r -> all(q -> (q in support) == (r[q] != -1), 1:4), rows)
        @test all(r -> all(q -> 1 <= r[q] <= radix[q], support), rows)
        @test [_code(r, support, radix) for r in rows] == 0:(n - 1)
        # The first parameter of the support varies fastest.
        @test rows[1][support] == ones(Int, length(support))
        n > 1 && @test rows[2][support] == [2; ones(Int, length(support) - 1)]
    end
    @test _decode!(zeros(Int, 4), 13, [1, 3, 4], radix) == [2, 0, 1, 2]   # 13 = 1 + 3 * (0 + 4 * 1)
    @test _code([2, 7, 1, 2], [1, 3, 4], radix) == 13
end


@testitem "space: a space from parts takes every field by name, in order" begin
    message(f) = try
        f()
        "no error"
    catch e
        sprint(showerror, e)
    end
    space = TestSpace((n = [1, 2, Invalid(0)], m = [:a, :b]); constraints = [@forbid(n == 2 && m == :b)])
    parts = NamedTuple{fieldnames(TestSpace)}(Tuple(getfield(space, f) for f in fieldnames(TestSpace)))
    rebuilt = TestSpace(Val(:parts), parts)
    @test all(getfield(rebuilt, f) === getfield(space, f) for f in fieldnames(TestSpace))
    # A missing, extra or misplaced part is refused, so a field added to
    # TestSpace fails at the first negative generation (src/invalid.jl).
    for wrong in (Base.structdiff(parts, NamedTuple{(:invalid,)}), merge(parts, (extra = 1,)),
                  NamedTuple{reverse(keys(parts))}(reverse(values(parts))))
        @test startswith(message(() -> TestSpace(Val(:parts), wrong)),
                         "internal error: a TestSpace from parts needs the parts (:names, :values, ")
    end
end


@testitem "space: length is the full product, BigInt-safe" begin
    @test length(TestSpace((a = [1],))) === 1
    @test length(TestSpace((a = [1, 2, Invalid(3)], b = 1:4))) === 12
    big_space = TestSpace((Symbol(:p, i) => [1, 2, 3] for i in 1:40)...)
    @test length(big_space) == big(3)^40
    @test length(big_space) isa BigInt
    fits = TestSpace((Symbol(:p, i) => [1, 2] for i in 1:62)...)
    @test length(fits) === 2^62
end


@testitem "space: show" begin
    space = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [@require(mode == :exact || solver == :none),
                       forbid((mode = :exact, tol = 1e-3))])
    @test sprint(show, space) == "TestSpace with 3 parameters, 12 combinations, 2 constraints"
    @test repr(MIME"text/plain"(), space) == """
        TestSpace with 3 parameters, 12 combinations, 2 constraints
          mode:   :fast, :exact
          solver: :none, :lu, :qr
          tol:    0.001, 1.0e-6"""
    one = TestSpace((size = [Partition(:tiny, Returns(1)), Invalid(0)],); constraints = [])
    @test repr(MIME"text/plain"(), one) == """
        TestSpace with 1 parameter, 2 combinations, 0 constraints
          size: Partition(:tiny), Invalid(0)"""
    @test repr(TestSpace((a = [1],); constraints = [@forbid(a == 2)])) ==
          "TestSpace with 1 parameter, 1 combination, 1 constraint"
    long = TestSpace((n = 1:20,))
    @test occursin("… (20 values)", repr(MIME"text/plain"(), long))
    # A space inside a container prints on one line.
    @test !occursin('\n', repr([space]))
end


@testitem "space: fixtures agree with the checker (Phase 2 adapter)" setup=[Checker] begin
    # test_space, model_rows and checker_row: test/fixture_model.jl, through the Checker module.
    # The five inputs construction must reject.
    for f in (invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
              partition_symbol_collision, duplicate_partition_name)
        @test f.space === nothing
        @test_throws ArgumentError test_space(f)
    end
    # Every other small fixture: the tables give the checker's valid ordinary
    # and negative rows (§1.1, §5.4, §5.5).
    checked = Symbol[]
    for f in FIXTURES
        f.space === nothing && continue
        space = test_space(f)
        @test space.names == f.space.names
        @test UnitTestDesign.arity(space) == length.(f.space.domains)
        length(space) <= 10^4 || continue
        rows = model_rows(space)
        ordinary, negative = valid_rows(f.space), negative_rows(f.space)
        @test length(rows.ordinary) == length(ordinary)
        @test all(same_target(checker_row(f.space, r), o) for (r, o) in zip(rows.ordinary, ordinary))
        @test length(rows.negative) == length(negative)
        @test all(same_target(checker_row(f.space, r), o) for (r, o) in zip(rows.negative, negative))
        push!(checked, f.name)
    end
    @test length(checked) >= 15
    # The named facts: 5 valid rows for Fable's solver, 3 of 8 heterogeneous
    # rows, and the rule sees the partition name in partition_names.
    @test length(model_rows(test_space(fable_solver)).ordinary) == 5
    @test length(model_rows(test_space(heterogeneous_values)).ordinary) == 3
    # Its one rule names both parameters, so the adapter makes it a whole-case
    # rule (lazy); it forbids only (size = :tiny, mode = :b).
    s = test_space(partition_names)
    @test [k for k in Iterators.product(1:3, 1:3) if UnitTestDesign.forbids(s.tables[1], collect(k))] ==
          [(1, 2)]
    @test length(model_rows(s).ordinary) == 8
    # Invalid(1) beside 1: 4 ordinary rows and 3 negative rows.
    rows = model_rows(test_space(invalid_beside_ordinary))
    @test (length(rows.ordinary), length(rows.negative)) == (4, 3)
    # No valid ordinary row, one valid negative row (§1.24).
    rows = model_rows(test_space(empty_ordinary_negative_seed))
    @test isempty(rows.ordinary) && rows.negative == [[2, 1]]
end
