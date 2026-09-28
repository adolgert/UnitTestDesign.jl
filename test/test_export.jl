using Test
using TestItemRunner

# The GitHub Actions matrix exporter (src/export.jl; plan Phase 6 steps 4
# and 5; contract §13.1, §14.1). Every check parses the emitted text with
# JSON.parse and compares values, so no test relies only on a fixture
# string.

@testsnippet ExportSetup begin
    using JSON

    "The ArgumentError message of `f()`, or what happened instead."
    message(f) = try
        f()
        "no error"
    catch e
        e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e)): $(sprint(showerror, e))"
    end

    "The emitted text for `cases`, and its parsed `include` list."
    function emitted(cases)
        text = sprint(github_matrix, cases)
        return text, JSON.parse(text)["include"]
    end
end


@testitem "github_matrix: a named result round-trips through JSON.parse" setup=[ExportSetup] begin
    space = TestSpace((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
                      constraints = [@require(mode == :exact || solver == :none),
                                     forbid((mode = :exact, tol = 1e-3))])
    cases = all_pairs(space)
    text, entries = emitted(cases)
    @test !occursin('\n', text)                      # one line, for $GITHUB_OUTPUT
    @test collect(keys(JSON.parse(text))) == ["include"]
    @test length(entries) == length(cases)
    for (object, row) in zip(entries, cases)
        @test collect(keys(object)) == ["mode", "solver", "tol"]   # parameter order
        @test object["mode"] == String(row.mode)
        @test object["solver"] == String(row.solver)
        @test object["tol"] === row.tol                           # Float64 reads back exactly
    end

    # The keyword form writes the same text to io, and returns nothing.
    io = IOBuffer()
    @test github_matrix(cases; io) === nothing
    @test String(take!(io)) == text
    @test github_matrix(io, cases) === nothing
    @test String(take!(io)) == text
end


@testitem "github_matrix: strings, numbers, booleans, nothing and Symbols" setup=[ExportSetup] begin
    rows = [
        (s = "say \"hi\"", t = :fast, b = true, i = 3, x = 1.0e-6, z = nothing),
        (s = "back\\slash", t = :exact, b = false, i = -7, x = 0.5, z = nothing),
        (s = "line\nbreak\ttab\r\u0001\u007f", t = Symbol("with space"), b = true, i = 0, x = -2.0, z = nothing),
        (s = "héllo 🎉 日本", t = :ü, b = false, i = typemax(Int), x = 1.0e300, z = nothing),
    ]
    text, entries = emitted(rows)
    @test !occursin('\n', text) && !occursin('\t', text)          # control characters are escaped
    @test [o["s"] for o in entries] == [r.s for r in rows]
    @test [o["t"] for o in entries] == [String(r.t) for r in rows]
    @test all(o["b"] isa Bool for o in entries) && [o["b"] for o in entries] == [r.b for r in rows]
    @test [o["i"] for o in entries] == [r.i for r in rows]
    @test all(o["i"] isa Integer for o in entries)
    @test [o["x"] for o in entries] == [r.x for r in rows]
    @test all(o["x"] isa Float64 for o in entries)
    @test entries[1]["x"] === 1.0e-6
    @test all(o -> haskey(o, "z") && o["z"] === nothing, entries)
    @test occursin("\"z\":null", text)

    # Other integer and float types keep their values.
    rows = [(a = Int8(-3), b = UInt64(2)^63, c = big(2)^70, d = Float32(0.25), f = SubString("abc", 2))]
    _, entries = emitted(rows)
    @test entries[1]["a"] == -3 && entries[1]["b"] == UInt64(2)^63 && entries[1]["c"] == big(2)^70
    @test entries[1]["d"] == 0.25 && entries[1]["f"] == "bc"
end


@testitem "github_matrix: empty results, positional names, and tuple rows" setup=[ExportSetup] begin
    text, entries = emitted(NamedTuple[])
    @test text == "{\"include\":[]}"
    @test entries == []
    # A space with no valid row gives a result with no rows (§1.24).
    none = all_values(TestSpace((a = [1],); constraints = [forbid((a = 1,))]))
    @test length(none) == 0
    @test emitted(none) == ("{\"include\":[]}", [])

    positional = all_pairs([1, 2], ["a", "b"], [:x, :y])
    text, entries = emitted(positional)
    @test length(entries) == length(positional)
    for (object, row) in zip(entries, positional)
        @test collect(keys(object)) == ["p1", "p2", "p3"]
        @test (object["p1"], object["p2"], object["p3"]) == (row[1], row[2], String(row[3]))
    end
    _, entries = emitted([(1, "a"), (2, "b")])
    @test [collect(keys(o)) for o in entries] == [["p1", "p2"], ["p1", "p2"]]
    @test [(o["p1"], o["p2"]) for o in entries] == [(1, "a"), (2, "b")]

    # Rows may name different fields; each object keeps its own.
    _, entries = emitted([(os = "linux",), (os = "mac", arch = "arm64")])
    @test [collect(keys(o)) for o in entries] == [["os"], ["os", "arch"]]
end


@testitem "github_matrix: unsupported values are rejected before anything is written" setup=[ExportSetup] begin
    good = (n = 1, tol = 1e-3)
    suffix = ". Map it to a supported type first: a String, a Symbol, a Bool, a finite Integer or " *
             "AbstractFloat, or nothing."
    cases = [
        (NaN, "NaN is not a finite number, and JSON has no value for it"),
        (Inf, "Inf is not a finite number, and JSON has no value for it"),
        (-Inf32, "-Inf32 is not a finite number, and JSON has no value for it"),
        (missing, "missing has no JSON value; write nothing for null"),
        ([1, 2], "[1, 2] is a Vector{Int64}, a collection, but a matrix field holds one value"),
        ((1, 2), "(1, 2) is a Tuple{Int64, Int64}, a collection, but a matrix field holds one value"),
        (Invalid(1), "Invalid(1) is an Invalid wrapper, which marks a negative case, not data"),
        (Partition(:t, Returns(1)),
         "Partition(:t) is a Partition wrapper; realize the case, or write the partition's name"),
        ('c', "'c' is a Char, which github_matrix does not write"),
        (1 // 2, "1//2 is a Rational{Int64}, which github_matrix does not write"),
        ("bad \xff", "\"bad \\xff\" is not valid UTF-8, which JSON text must be"),
    ]
    for (value, reason) in cases
        rows = [good, good, (n = 1, tol = value)]
        io = IOBuffer()
        @test message(() -> github_matrix(io, rows)) ==
            "github_matrix: row 3, field `tol`: " * reason * suffix
        @test position(io) == 0 && isempty(take!(io))            # nothing written
    end
    # Positional rows name the field p1, p2, …; a TestCases row by its parameter.
    io = IOBuffer()
    @test startswith(message(() -> github_matrix(io, [(1, 2), (3, NaN)])), "github_matrix: row 2, field `p2`: NaN")
    @test isempty(take!(io))
    # Rows that are not rows, and a single row.
    @test startswith(message(() -> github_matrix(io, [good, 5])),
                     "github_matrix: row 2, 5 (Int64), is not a row; a row is a NamedTuple")
    @test occursin("wrap a single row in a vector", message(() -> github_matrix(io, good)))
    @test occursin("takes a TestCases or a vector of rows", message(() -> github_matrix(io, 5)))
    @test isempty(take!(io))
end


@testitem "github_matrix: field names are checked like values; JSON.jl escapes the rest (review round 1)" setup=[ExportSetup] begin
    # The bytes rejected as a value are rejected as a name, before anything is written.
    bad = Symbol(String(UInt8[0xff]))
    for (rows, k) in (([NamedTuple{(bad,)}((1,))], 1),
                      ([(n = 1,), NamedTuple{(:n, bad)}((2, 3))], 2))
        io = IOBuffer()
        @test message(() -> github_matrix(io, rows)) ==
            "github_matrix: row $k, field name Symbol(\"\\xff\"): not valid UTF-8, which JSON text must " *
            "be; rename the field"
        @test position(io) == 0 && isempty(take!(io))
    end
    # A bad name wins over a bad value in the same row: names are checked first.
    io = IOBuffer()
    @test startswith(message(() -> github_matrix(io, [NamedTuple{(bad,)}((NaN,))])), "github_matrix: row 1, field name")
    @test isempty(take!(io))
    # An empty name names nothing a workflow can read.
    @test message(() -> github_matrix(io, [NamedTuple{(Symbol(""),)}((1,))])) ==
        "github_matrix: row 1, field name Symbol(\"\"): empty; a job reads each value by its name, so " *
        "a name needs at least one character; rename the field"
    @test isempty(take!(io))
    # A TestSpace's names go through the same check.
    cases = all_pairs(TestSpace(NamedTuple{(:a, bad)}(([1, 2], [3, 4]))))
    @test startswith(message(() -> github_matrix(io, cases)), "github_matrix: row 1, field name Symbol(")
    @test isempty(take!(io))

    # Names GitHub reads only as matrix['<name>'] are written, escaped where JSON needs it.
    names = (Symbol("a\"b"), Symbol("c\\d"), Symbol("e\nf"), :π, Symbol("with space"), Symbol("1st"), Symbol("x.y"))
    text, entries = emitted([NamedTuple{names}((1, 2, 3, 4, 5, 6, 7))])
    @test isvalid(text)
    @test collect(keys(only(entries))) == [String(n) for n in names]
    @test [only(entries)[String(n)] for n in names] == 1:7
end


@testitem "github_matrix: warns once above GitHub's 256 jobs" setup=[ExportSetup] begin
    rows = [(k = k,) for k in 1:257]
    io = IOBuffer()
    @test_logs (:warn, r"257 jobs exceed GitHub Actions' limit of 256 jobs per matrix") github_matrix(io, rows)
    @test length(JSON.parse(String(take!(io)))["include"]) == 257   # still written in full
    @test_logs github_matrix(io, rows[1:256])                       # no warning at the limit
    @test length(JSON.parse(String(take!(io)))["include"]) == 256
end


@testitem "github_matrix: generated wrappers are rejected by row and field; realized rows are written" setup=[ExportSetup] begin
    using Random: Xoshiro
    space = TestSpace((n = [1, 2, Invalid(-1)], m = [:a, :b]))
    cases = all_pairs(space)
    k = findfirst(hasinvalid, cases)
    io = IOBuffer()
    @test startswith(message(() -> github_matrix(io, cases)),
                     "github_matrix: row $k, field `n`: Invalid(-1) is an Invalid wrapper")
    @test isempty(take!(io))
    # The caller maps the marker to data first.
    mapped = [merge(c, (n = c.n isa Invalid ? "invalid" : c.n,)) for c in cases]
    _, entries = emitted(mapped)
    @test [o["n"] for o in entries] == [c.n isa Invalid ? "invalid" : c.n for c in cases]

    space = TestSpace((n = [1, 2], size = [Partition(:tiny, Returns(1e-9)), Partition(:big, Returns(1e9))]))
    cases = all_pairs(space)
    @test startswith(message(() -> github_matrix(io, cases)),
                     "github_matrix: row 1, field `size`: Partition(:tiny) is a Partition wrapper")
    @test isempty(take!(io))
    realized = realize(cases; rng = Xoshiro(1))
    _, entries = emitted(realized)
    @test [o["size"] for o in entries] == [r.size for r in realized]
    @test sort(unique(o["size"] for o in entries)) == [1e-9, 1e9]
end
