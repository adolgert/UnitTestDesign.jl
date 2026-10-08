using Test
using TestItemRunner

# Partitions (src/partition.jl; plan Phase 6 steps 2 and 5): generation and
# coverage see a Partition by its name, returned rows hold the wrapper, and
# `realize` draws each partition's value from a caller's rng. Contract
# §4.1–§4.13, §2.4, §2.11, §2.13.

@testsnippet PartitionSetup begin
    using Random
    using Random: Xoshiro

    "A production value or row in the checker's terms: a partition by its name, `CheckInvalid` for `Invalid`."
    as_check(x::Invalid) = CheckInvalid(as_check(x.value))
    as_check(x::Partition) = x.name
    as_check(x) = x
    as_check(row::Union{NamedTuple, Tuple}) = map(as_check, row)

    "The message of the exception `f()` throws, or \"no error\"."
    message(f) = try
        f()
        "no error"
    catch e
        sprint(showerror, e)
    end
end


@testitem "partition: generation keeps the wrappers, and coverage is over names (§4.5, §4.6, §2.4)" setup=[Checker, PartitionSetup] begin
    f = partition_names
    space = test_space(f)
    for engine in (IPOG(), GND()), strength in (1, 2)
        cases = covering(space; strength, engine)
        @test all(r -> r.size isa Union{Partition, Int} && r.mode isa Symbol, cases)
        @test any(r -> r.size isa Partition, cases)
        @test fieldtype(eltype(cases), :size) === Union{Int, Partition}
        check = check_design(as_check.(collect(cases)), f.space; strength)
        @test complete(check)
        @test iscomplete(coverage(cases))
        # The rule sees the name: (size = :tiny, mode = :b) never appears (§4.5).
        @test !any(r -> r.size isa Partition && r.size.name === :tiny && r.mode === :b, cases)
        # The raw Symbol :tiny of `mode` is a different value from the partition (§4.4).
        @test any(r -> r.mode === :tiny, cases)
    end
    # A partition may be written by its name in a must-include row (§2.11).
    cases = all_pairs(space; must_include = [(size = :huge, mode = :b)])
    @test cases[1].size isa Partition && cases[1].size.name === :huge
    # Full factorial and excursions keep the wrappers too.
    @test count(r -> r.size isa Partition, full_factorial(space)) == 5
    @test excursions(space)[1].size isa Partition
end


@testitem "partition: iterating, indexing and showing never draw (§4.6, §1.22)" setup=[Checker, PartitionSetup] begin
    boom = Partition(:boom, rng -> error("drawn"))
    space = TestSpace((x = [boom, 1.0], y = [:a, :b]))
    cases = all_pairs(space)
    @test cases[1].x === boom
    @test length(collect(cases)) == 4
    @test occursin("Partition(:boom)", sprint(show, MIME"text/plain"(), cases))
    @test iscomplete(coverage(cases))
    @test occursin("drawn", message(() -> realize(cases; rng = Xoshiro(1))))
end


@testitem "partition: realize is deterministic for an rng state and draws once per partition, in order (§4.7, §4.10)" setup=[Checker, PartitionSetup] begin
    calls = Symbol[]
    p = Partition(:p, rng -> (push!(calls, :p); rand(rng)))
    q = Partition(:q, rng -> (push!(calls, :q); rand(rng, 1:1000)))
    space = TestSpace((x = [p, 0.5], y = [q, 7], z = [:a, :b]))
    cases = all_pairs(space)
    # Two realizations from equal rng states are equal.
    rng = Xoshiro(2026)
    twin = copy(rng)
    first_draw = realize(cases; rng)
    @test first_draw == realize(cases; rng = twin)
    @test rng == twin                                  # both advanced by the same draws
    @test realize(cases; rng = Xoshiro(1)) == realize(cases; rng = Xoshiro(1))
    # One call per partition, in parameter order, rows in order (§4.7, §4.9).
    empty!(calls)
    realize(cases; rng = Xoshiro(5))
    expected = Symbol[]
    for row in cases
        row.x isa Partition && push!(expected, :p)
        row.y isa Partition && push!(expected, :q)
    end
    @test calls == expected && !isempty(calls)
    # The draws are the rng's, in parameter order: x's first, then y's.
    empty!(calls)
    row = realize((x = p, y = q, z = :a); rng = Xoshiro(9))
    reference = Xoshiro(9)
    @test calls == [:p, :q]
    @test row === (x = rand(reference), y = rand(reference, 1:1000), z = :a)
    # No draw touches the global generator.
    state = copy(Random.default_rng())
    realize(cases; rng = Xoshiro(3))
    @test Random.default_rng() == state
    # The labeled cases are unchanged; coverage stays measured on them (§4.11).
    @test all(r -> r.x isa Union{Partition, Float64}, cases)
    @test iscomplete(coverage(cases))
end


@testitem "partition: realize keeps the shape and passes other values through (§4.8, §4.9, §4.13)" setup=[Checker, PartitionSetup] begin
    tiny = Partition(:tiny, Returns(1e-9))     # the fixed-value form (§4.1)
    # Positional rows stay tuples of the same length.
    cases = all_pairs([tiny, 1.0], [:a, :b], [sin, cos])
    realized = realize(cases; rng = Xoshiro(1))
    @test realized isa Vector && !(realized isa TestCases)
    @test length(realized) == length(cases)
    @test all(r -> r isa Tuple && length(r) == 3, realized)
    @test all(((a, b),) -> (a[1] === tiny ? b[1] === 1e-9 : b[1] === a[1]) && b[2] === a[2] && b[3] === a[3],
              zip(cases, realized))
    # A function in a domain is an ordinary value, never drawn (§4.13).
    @test any(r -> r[3] === sin, realized)
    # A NamedTuple keeps its names and their order.
    row = realize((n = Invalid(-1), size = tiny, mode = nothing); rng = Xoshiro(1))
    @test row === (n = Invalid(-1), size = 1e-9, mode = nothing)
    @test keys(realize((b = tiny, a = 1); rng = Xoshiro(1))) == (:b, :a)
    # Invalid markers and ordinary values pass through (§4.8).
    space = TestSpace((n = [1, Invalid(-1)], size = [tiny, 2.0]))
    for r in realize(all_pairs(space); rng = Xoshiro(4))
        @test r.n === 1 || r.n === Invalid(-1)
        @test r.size === 1e-9 || r.size === 2.0
    end
    @test hasinvalid(realize((n = Invalid(-1), size = tiny); rng = Xoshiro(1)))
    @test realize((); rng = Xoshiro(1)) === ()
    @test realize(NamedTuple[]; rng = Xoshiro(1)) == []
end


@testitem "partition: realize's errors (§4.7, §4.12)" setup=[Checker, PartitionSetup] begin
    # A draw that returns a wrapper.
    for wrapped in (Invalid(1), Partition(:inner, Returns(1)))
        bad = Partition(:bad, Returns(wrapped))
        msg = message(() -> realize((x = bad,); rng = Xoshiro(1)))
        @test occursin("Partition(:bad)", msg) && occursin("§4.12", msg)
    end
    # rng is required and is an AbstractRNG; the global generator is never used.
    row = (x = Partition(:t, Returns(1)),)
    @test occursin("needs the keyword rng", message(() -> realize(row)))
    @test occursin("§4.7", message(() -> realize(row)))
    @test occursin("AbstractRNG", message(() -> realize(row; rng = 1)))
    @test occursin("needs the keyword rng", message(() -> realize([row])))
    # Rows only.
    @test occursin("row 2 is a Int64", message(() -> realize([row, 3]; rng = Xoshiro(1))))
    @test occursin("got a Int64", message(() -> realize(3; rng = Xoshiro(1))))
    # Nested wrappers stay rejected when built (§4.12), and names are Symbols (§4.1).
    @test_throws ArgumentError Invalid(Partition(:t, Returns(1)))
    @test_throws ArgumentError Partition(:t, Partition(:u, Returns(1)))
    @test_throws ArgumentError Partition("t", Returns(1))
    for f in (partition_symbol_collision, duplicate_partition_name, nested_invalid_partition)
        @test_throws ArgumentError test_space(f)
    end
end
