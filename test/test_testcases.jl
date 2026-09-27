using Test
using TestItemRunner

# TestCases, the public result (src/testcases.jl; plan Phase 4 steps 1, 6 and
# 7; contract §1.18–§1.24, §2.4, §9.5–§9.7, §13.4): a read-only vector of
# typed rows, its bookkeeping, its display, and Tables.jl interoperability.
# Results are built through the request layer: Request, then generate (or
# generate_excursion, generate_full_factorial), then TestCases.

@testsnippet CasesSetup begin
    using UnitTestDesign: Request, generate, generate_excursion, generate_full_factorial, row_type
    using Random: Xoshiro

    "Fable's solver space, typed and labeled: 5 valid rows of 12, 3 forbidden and 2 implied pairs."
    solver_space() = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            @require(mode == :exact || solver == :none),
            forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        ])

    "A covering result: `generate(engine, Request(space; kwargs...))` as a TestCases."
    function covering_cases(space; engine = IPOG(), positional = false, kwargs...)
        request = Request(space; kwargs...)
        return TestCases(request, generate(engine, request); positional)
    end

    function excursion_cases(space; distance = 1, from = nothing, positional = false, kwargs...)
        request = Request(space; strength = 1, kwargs...)
        return TestCases(request, generate_excursion(request; distance, from); positional)
    end

    function factorial_cases(space; limit = 10^6, positional = false, kwargs...)
        request = Request(space; strength = 1, kwargs...)
        return TestCases(request, generate_full_factorial(request; limit); positional)
    end

    "A TestCases with the given rows, for display tests that need no engine."
    function handmade(space, rows; strength = 1, excluded = Exclusion[], positional = false)
        T = row_type(space, positional)
        return TestCases{T}(T[r for r in rows], space, :covering, strength,
                            Pair{Tuple{Vararg{Symbol}}, Int}[], :IPOG, nothing, 0, 0, 0,
                            excluded, positional, NamedTuple())
    end

    "The text/plain display under an IOContext with `:limit` and `:displaysize`."
    plain(x; limit = false, size = (24, 80)) =
        sprint((io, x) -> show(IOContext(io, :limit => limit, :displaysize => size), MIME"text/plain"(), x), x)
    lines(x; kwargs...) = split(plain(x; kwargs...), '\n')

    "Each table line's cells: the row number, then one entry per shown column."
    cells(line) = split(strip(line))

    const SOLVER_SUMMARY = "5 cases · strength 2 · IPOG · 3 parameters · 12 combinations"
    const SOLVER_EXCLUDED = "excluded: 3 pairs forbidden, 2 impossible because constraints combine; see report(cases)"
end


@testitem "testcases: the solver example's display (§1.19, §1.22)" setup=[CasesSetup] begin
    cases = covering_cases(solver_space())
    @test length(cases) == 5
    text = lines(cases)
    @test text[1] == SOLVER_SUMMARY
    @test text[2] == SOLVER_EXCLUDED
    @test text[3] == "    mode    solver  tol"
    @test length(text) == 3 + 5
    # One line per row, in order, each value as `show` prints it, aligned
    # under its header.
    for (i, row) in enumerate(cases)
        @test cells(text[3 + i]) == [string(i), repr(row.mode), repr(row.solver), repr(row.tol)]
        @test findfirst(repr(row.solver), text[3 + i]).start == findfirst("solver", text[3]).start
        @test findfirst(repr(row.tol), text[3 + i]).start == findfirst("tol", text[3]).start
    end
    # The compact form, used inside containers, is the summary line alone.
    @test sprint(show, cases) == SOLVER_SUMMARY
    @test repr(cases) == SOLVER_SUMMARY
    @test occursin("\n " * SOLVER_SUMMARY, plain([cases, cases]))
    # Nothing trails a line.
    @test all(l -> l == rstrip(l), text)
end


@testitem "testcases: the solver fixture displays the same with unlabeled rules (§1.22)" setup=[CasesSetup, Checker] begin
    # The fixture's space holds the same values in Any-typed domains, and its
    # rules have no labels. The summary, the counts and the table are unchanged.
    cases = covering_cases(test_space(fable_solver))
    typed = covering_cases(solver_space())
    @test lines(cases)[1] == SOLVER_SUMMARY
    @test lines(cases)[2] == SOLVER_EXCLUDED
    @test collect(cases) == collect(typed)
    @test plain(cases) == plain(typed)
    @test repr(cases.excluded[1]) == "(mode = :fast, solver = :lu): forbidden by rule 1 on (mode, solver)"
    @test repr(cases.excluded[4]) ==
          "(solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine " *
          "(rule 1 on (mode, solver); rule 2 on (mode, tol))"
    @test (cases.required, cases.covered) == (11, 11)

    # GND covers the same 11 pairs; its display names the seed.
    gnd = covering_cases(test_space(fable_solver); engine = GND())
    @test lines(gnd)[1] == "$(length(gnd)) cases · strength 2 · GND seed 0 · 3 parameters · 12 combinations"
    @test lines(gnd)[2] == SOLVER_EXCLUDED
    @test (gnd.required, gnd.covered) == (11, 11)
end


@testitem "testcases: an Exclusion prints as one line (§1.4, §1.19, §3.15)" setup=[CasesSetup] begin
    cases = covering_cases(solver_space())
    @test [e.status for e in cases.excluded] == [:forbidden, :forbidden, :forbidden, :implied, :implied]
    @test repr(cases.excluded[3]) ==
          "(mode = :exact, tol = 0.001): forbidden by rule 2 (exact mode needs a tight tolerance)"
    @test repr(cases.excluded[4]) ==
          "(solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine " *
          "(rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance)"
    @test repr(MIME"text/plain"(), cases.excluded[3]) == repr(cases.excluded[3])
    @test !occursin('\n', plain(cases.excluded[5]))
    # In a vector, one line each.
    @test length(lines(cases.excluded)) == 1 + 5

    # A deletion search cut short by explanation_limit: the rules are still
    # sufficient, and both the Exclusion and the excluded line say so.
    limited = covering_cases(solver_space(); explanation_limit = 1)
    @test count(e -> e.minimal === :unresolved, limited.excluded) == 2
    @test repr(limited.excluded[4]) ==
          "(solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine " *
          "(rule 1: @require(mode == :exact || solver == :none); rule 2: exact mode needs a tight tolerance) " *
          "(explanation unresolved: explanation_limit = 1 reached)"
    @test lines(limited)[2] == "excluded: 3 pairs forbidden, 2 impossible because constraints combine, " *
                               "2 with an unresolved explanation; see report(cases)"

    # Other shapes: several direct rules, one rule behind an implied target.
    two = Exclusion((a = 1, b = 2), :forbidden, [1, 3], ["a is odd", "rule 3 on (a, b)"], :not_applicable, nothing)
    @test repr(two) == "(a = 1, b = 2): forbidden by rules 1 and 3 (rule 1: a is odd; rule 3 on (a, b))"
    wide = Exclusion((a = 1,), :implied, [2], ["no a without c"], :verified, nothing)
    @test repr(wide) == "(a = 1,): impossible because of rule 2 (no a without c)"
    big = Exclusion((a = 1,), :implied, [1, 2], ["x", "y"], :unresolved, :explanation_limit => 1_000_000)
    @test endswith(repr(big), "(explanation unresolved: explanation_limit = 1_000_000 reached)")
end


@testitem "testcases: show never searches, evaluates a rule, or reads the tables (§1.22)" setup=[CasesSetup] begin
    # A whole-case rule is always lazy (§12.20): generation evaluates it
    # through the request's memo, and each evaluation bumps the counter.
    evaluations = Ref(0)
    space = TestSpace(
        (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [
            forbid(case -> (evaluations[] += 1; case.mode == :exact && case.tol == 1e-3);
                   reason = "exact mode needs a tight tolerance"),
            forbid((mode = :fast, solver = :qr)),
        ])
    @test space.tables[1].lazy !== nothing
    for cases in (covering_cases(space), covering_cases(space; engine = GND()),
                  excursion_cases(space; from = (mode = :exact, solver = :lu, tol = 1e-6)),
                  factorial_cases(space), covering_cases(space; strength = 3))
        before = evaluations[]
        @test before > 0
        # Every table now throws if consulted, tabulated or lazy.
        saved = copy(space.tables)
        for (k, t) in enumerate(space.tables)
            space.tables[k] = UnitTestDesign.RuleTable(t.scope, key -> error("display consulted rule $k"))
        end
        try
            text = plain(cases) * plain(cases; limit = true, size = (8, 30)) * sprint(show, cases) *
                   repr(cases.excluded) * plain(cases.excluded)
            @test occursin("cases", text)
        finally
            copyto!(space.tables, saved)
        end
        @test evaluations[] == before
    end
end


@testitem "testcases: GND records its seed or the caller's rng (§9.5, §9.6)" setup=[CasesSetup] begin
    seeded = covering_cases(solver_space(); engine = GND(seed = 7))
    @test (seeded.engine, seeded.seed) == (:GND, 7)
    @test occursin(" · GND seed 7 · ", repr(seeded))
    @test covering_cases(solver_space(); engine = GND()).seed == 0

    rng = Xoshiro(3)
    state = copy(rng)
    own = covering_cases(solver_space(); engine = GND(rng = rng))
    @test (own.engine, own.seed) == (:GND, nothing)
    @test lines(own)[1] == "$(length(own)) cases · strength 2 · GND, caller's rng · 3 parameters · 12 combinations"
    @test rng == state

    ipog = covering_cases(solver_space())
    @test (ipog.engine, ipog.seed) == (:IPOG, nothing)
end


@testitem "testcases: excursions show distance, base and dropped rows (§7.5–§7.7)" setup=[CasesSetup] begin
    space = solver_space()
    # From the default base, three of the four one-change rows break a rule.
    cases = excursion_cases(space)
    @test (cases.strategy, cases.engine, cases.seed) == (:excursion, :Excursion, nothing)
    @test cases.strength == 0
    @test !occursin("strength", repr(cases))
    @test (cases.required, cases.covered, cases.n_must_include) == (0, 0, 0)
    @test isempty(cases.excluded)
    @test cases.notes.dropped == 3
    text = lines(cases)
    @test text[1] == "2 cases · excursion, distance 1 from (mode = :fast, solver = :none, tol = 0.001) · " *
                     "3 parameters · 12 combinations, 3 rows dropped"
    @test text[2] == "    mode   solver  tol"
    @test length(text) == 2 + 2

    # From a chosen base, at distance 1: (fast, lu, 1e-6) and (exact, lu, 1e-3) are dropped.
    base = (mode = :exact, solver = :lu, tol = 1e-6)
    cases = excursion_cases(space; from = base)
    @test cases[1] == base
    # The notes are in values: the base is a row, never_appear names values.
    @test cases.notes.base === base
    @test cases.notes.base isa eltype(cases)
    @test cases.notes.never_appear == [:mode => :fast, :tol => 1e-3]
    @test cases.notes.never_appear isa Vector{Pair{Symbol, Any}}
    @test repr(cases) == "3 cases · excursion, distance 1 from (mode = :exact, solver = :lu, tol = 1.0e-6) · " *
                         "3 parameters · 12 combinations, 2 rows dropped"
    # In a narrow REPL the base is shortened, keeping its first value.
    @test lines(cases; limit = true, size = (24, 80))[1] ==
          "3 cases · excursion, distance 1 from (mode = :exact, …) · 3 parameters · 12 combinations, 2 rows dropped"
    @test lines(cases; limit = true, size = (24, 20))[1] ==
          "3 cases · excursion, distance 1 from (mode = :exact, …) · 3 parameters · 12 combinations, 2 rows dropped"
    @test lines(cases; limit = true, size = (24, 200))[1] == repr(cases)
    # Nothing dropped: nothing said.
    free = excursion_cases(TestSpace((a = 1:2, b = [:x, :y])))
    @test repr(free) == "3 cases · excursion, distance 1 from (a = 1, b = :x) · 2 parameters · 4 combinations"
    # A positional excursion prints its base as a tuple.
    positional = excursion_cases(TestSpace(:p1 => 1:2, :p2 => [:x, :y]); positional = true, from = (2, :y))
    @test repr(positional) == "3 cases · excursion, distance 1 from (2, :y) · 2 parameters · 4 combinations"
    @test lines(positional)[2] == "    p1  p2"
    @test positional.notes.base === (2, :y)
    # Value identity survives the translation (§2.3): 1 and 1.0 stay apart.
    mixed = excursion_cases(TestSpace((a = Any[1, 1.0], b = [nothing, :x])); distance = 0)
    @test mixed.notes.base isa @NamedTuple{a::Any, b::Union{Nothing, Symbol}}
    @test mixed.notes.base.a === 1 && mixed.notes.base.b === nothing
    @test mixed.notes.never_appear == [:a => 1.0, :b => :x]
    @test last(mixed.notes.never_appear[1]) === 1.0
end


@testitem "testcases: the valid count, only when generation knows it (§1.22, §7.3, §11.2)" setup=[CasesSetup] begin
    space = solver_space()
    # A full factorial counted its valid rows.
    full = factorial_cases(space)
    @test (full.strategy, full.engine) == (:full_factorial, :FullFactorial)
    @test full.notes == (candidates = 12, accepted = 5)
    @test (full.required, full.covered) == (0, 0)
    @test full.strength == 0   # a full factorial has no strength
    @test repr(full) == "5 cases · full factorial · 3 parameters · 12 combinations, 5 valid"
    # Covering at strength equal to the parameter count: the required targets
    # are the valid rows.
    top = covering_cases(space; strength = 3)
    @test top.required == 5
    @test lines(top)[1:2] == ["5 cases · strength 3 · IPOG · 3 parameters · 12 combinations, 5 valid",
                              "excluded: 7 triples forbidden; see report(cases)"]
    @test Set(top) == Set(full)
    # Below full strength, and for excursions, the valid count is not known.
    @test !occursin("valid", repr(covering_cases(space)))
    @test !occursin("valid", repr(excursion_cases(space)))
    @test repr(covering_cases(space; strength = 1)) ==
          "$(length(covering_cases(space; strength = 1))) cases · strength 1 · IPOG · 3 parameters · 12 combinations"
end


@testitem "testcases: stronger groups and must-include rows are recorded (§1.19, §10.5, §11.7, §11.9)" setup=[CasesSetup] begin
    space = TestSpace((a = 1:2, b = 1:2, c = 1:2, d = 1:2))
    stronger = [(:c, :b, :a) => 3, (:b, :d) => 2]
    kept = deepcopy(stronger)
    cases = covering_cases(space; stronger)
    @test stronger == kept
    # names => strength, in space order; a group at the base strength adds nothing.
    @test cases.stronger == [(:a, :b, :c) => 3]
    @test cases.stronger isa Vector{Pair{Tuple{Vararg{Symbol}}, Int}}
    @test (cases.strength, cases.strategy) == (2, :covering)
    @test repr(cases) == "$(length(cases)) cases · strength 2, 3 within (a, b, c) · IPOG · 4 parameters · 16 combinations"
    @test isempty(covering_cases(space).stronger)
    # Positional groups by index are recorded by name.
    pspace = TestSpace(:p1 => 1:2, :p2 => 1:2, :p3 => 1:2, :p4 => 1:2)
    @test covering_cases(pspace; positional = true, stronger = [(4, 2, 3) => 3]).stronger == [(:p2, :p3, :p4) => 3]

    # Must-include rows come first, in order; the count is recorded and shown.
    rows = [(mode = :exact, solver = :qr, tol = 1e-6), (mode = :fast,)]
    must = covering_cases(solver_space(); must_include = rows)
    @test must.n_must_include == 2
    @test must[1] == rows[1]
    @test must[2].mode === :fast
    @test lines(must)[1] == "$(length(must)) cases (2 must-include) · strength 2 · IPOG · 3 parameters · 12 combinations"
    @test (must.required, must.covered) == (11, 11)
    @test covering_cases(solver_space()).n_must_include == 0
end


@testitem "testcases: Opus's space, with an implied target (§1.2, §1.4, §1.19)" setup=[CasesSetup, Checker] begin
    cases = covering_cases(test_space(opus_gpu))
    text = lines(cases)
    @test text[1] == "$(length(cases)) cases · strength 2 · IPOG · 3 parameters · 12 combinations"
    @test text[2] == "excluded: 2 pairs forbidden, 1 impossible because constraints combine; see report(cases)"
    @test text[3] == "    os        gpu    driver"
    @test length(text) == 3 + length(cases)
    @test cases.required == cases.covered == 13
    @test repr.(cases.excluded) == [
        "(os = :windows, gpu = true): impossible because rules 1 and 2 combine (rule 1 on (gpu, driver); rule 2 on (os, driver))",
        "(os = :windows, driver = :cuda): forbidden by rule 2 on (os, driver)",
        "(gpu = true, driver = :none): forbidden by rule 1 on (gpu, driver)"]
    # Values print as show prints them: Bools bare, Symbols with a colon.
    @test all(i -> cells(text[3 + i])[2:end] == [repr(v) for v in cases[i]], eachindex(cases))
    gnd = covering_cases(test_space(opus_gpu); engine = GND())
    @test lines(gnd)[2] == text[2]
end


@testitem "testcases: an empty design prints 0 cases and its exclusions (§1.24)" setup=[CasesSetup, Checker] begin
    for engine in (IPOG(), GND())
        cases = covering_cases(test_space(disconnected_unsat); engine)
        @test isempty(cases)
        @test length(cases) == 0
        @test collect(cases) == eltype(cases)[]
        @test (cases.required, cases.covered) == (0, 0)
        @test length(cases.excluded) == 16
        name = engine isa IPOG ? "IPOG" : "GND seed 0"
        @test lines(cases) == ["0 cases · strength 2 · $name · 3 parameters · 12 combinations",
                               "excluded: 4 pairs forbidden, 12 impossible because constraints combine; see report(cases)",
                               "    free  x  y"]
        @test plain(cases; limit = true, size = (5, 20)) == plain(cases)
        @test repr(cases) == "0 cases · strength 2 · $name · 3 parameters · 12 combinations"
    end
end


@testitem "testcases: a read-only vector of immutable rows (§1.18, §13.4)" setup=[CasesSetup] begin
    cases = covering_cases(solver_space())
    T = @NamedTuple{mode::Symbol, solver::Symbol, tol::Float64}
    @test cases isa AbstractVector{T}
    @test eltype(cases) === T
    @test (length(cases), size(cases), axes(cases)) == (5, (5,), (Base.OneTo(5),))
    @test cases[1] === cases.cases[1]
    @test cases[end] === last(cases) === cases.cases[5]
    @test first(cases) === cases[1]
    @test_throws BoundsError cases[6]
    @test [row for row in cases] == cases.cases
    @test collect(eachindex(cases)) == 1:5

    # collect, copy and slices are plain, mutable Vector{T}s.
    v = collect(cases)
    @test v isa Vector{T}
    @test v == cases && v !== cases.cases
    push!(v, cases[1])
    @test length(cases) == 5
    @test copy(cases) isa Vector{T}
    @test copy(cases) == cases
    @test cases[1:2] isa Vector{T}
    @test cases[1:2] == cases.cases[1:2]
    @test cases[[1, 3]] == [cases[1], cases[3]]
    @test first(cases, 2) == cases[1:2]
    @test Vector(cases) isa Vector{T}

    # == compares rows, as for any vector.
    @test cases == cases.cases
    @test cases == covering_cases(solver_space())
    @test cases != reverse(cases.cases)

    # Rows and the result are immutable.
    @test !ismutable(cases[1])
    @test_throws Base.CanonicalIndexError cases[1] = cases[2]
    @test_throws ErrorException (cases[1].mode = :exact)

    # Rows destructure.
    seen = Tuple{Symbol, Symbol, Float64}[]
    for (mode, solver, tol) in cases
        push!(seen, (mode, solver, tol))
    end
    @test seen == [Tuple(row) for row in cases]
    for (; mode, tol) in cases
        @test mode === :fast || tol === 1e-6
    end
end


@testitem "testcases: rows keep their values' types (§2.1, §2.4, §13.4)" setup=[CasesSetup] begin
    space = TestSpace((n = [1, 2, 3], x = Any[1, 1.0], z = [nothing, :x], s = ["fast", "slow"]))
    cases = covering_cases(space)
    T = eltype(cases)
    @test T === NamedTuple{(:n, :x, :z, :s), Tuple{Int, Any, Union{Nothing, Symbol}, String}}
    @test eltype(collect(cases)) === T
    @test all(row -> row.n isa Int && row.s isa String, cases)
    # 1 and 1.0 are two choices, kept apart through generation: each pairs with
    # both values of z.
    for x in (1, 1.0), z in (nothing, :x)
        @test any(row -> row.x === x && row.z === z, cases)
    end
    @test all(row -> row.x === 1 || row.x === 1.0, cases)
    @test count(row -> row.x === 1, cases) >= 2 && count(row -> row.x === 1.0, cases) >= 2
    @test any(row -> row.z === nothing, cases)

    # A positional result: Tuples with the same field types and the same rows.
    pspace = TestSpace(:p1 => [1, 2, 3], :p2 => Any[1, 1.0], :p3 => [nothing, :x], :p4 => ["fast", "slow"])
    positional = covering_cases(pspace; positional = true)
    @test positional.positional && !cases.positional
    @test eltype(positional) === Tuple{Int, Any, Union{Nothing, Symbol}, String}
    @test collect(positional) isa Vector{Tuple{Int, Any, Union{Nothing, Symbol}, String}}
    @test all(((a, b),) -> Tuple(a) === b, zip(cases, positional))
    for (n, x, z, s) in positional
        @test n isa Int && (x === 1 || x === 1.0) && s isa String
    end
    @test !ismutable(positional[1])
    @test lines(positional)[2] == "    p1  p2   p3       p4"
end


@testitem "testcases: the table prints wrappers, nothing, and strings distinctly (§2.3)" setup=[CasesSetup] begin
    tiny = Partition(:tiny, Returns(1e-9))
    space = TestSpace((n = [1, Invalid(-1)], size = [tiny, 1.0], mode = [:fast, "fast", nothing]))
    cases = handmade(space, [(n = 1, size = tiny, mode = :fast),
                             (n = Invalid(-1), size = 1.0, mode = "fast"),
                             (n = 1, size = 1.0, mode = nothing)])
    @test plain(cases) == """
        3 cases · strength 1 · IPOG · 3 parameters · 12 combinations
            n            size              mode
         1  1            Partition(:tiny)  :fast
         2  Invalid(-1)  1.0               "fast"
         3  1            1.0               nothing"""
    # A positional result has the same table under p1, p2, p3.
    pspace = TestSpace(:p1 => [1, Invalid(-1)], :p2 => [tiny, 1.0], :p3 => [:fast, "fast", nothing])
    positional = handmade(pspace, [(1, tiny, :fast), (Invalid(-1), 1.0, "fast"), (1, 1.0, nothing)];
                          positional = true)
    @test eltype(positional) <: Tuple
    @test lines(positional)[3:end] == lines(cases)[3:end]
    @test lines(positional)[2] == "    p1           p2                p3"
end


@testitem "testcases: long and wide results are cut to the display, like a DataFrame (§1.22)" setup=[CasesSetup] begin
    # 32 rows. Without :limit every row prints; with it, the first 10 and last 5.
    full = factorial_cases(TestSpace((a = 1:4, b = 1:4, c = [:x, "x"])))
    @test length(full) == 32
    @test length(lines(full)) == 2 + 32
    shown = lines(full; limit = true, size = (24, 80))
    @test shown[1] == "32 cases · full factorial · 3 parameters · 32 combinations, 32 valid"
    @test shown[2] == "     a  b  c"
    @test [cells(l)[1] for l in shown[3:end]] == [string.(1:10); "⋮"; string.(28:32)]
    @test cells(shown[13]) == fill("⋮", 4)
    @test cells(shown[end]) == ["32", "4", "4", "\"x\""]
    # A short display keeps fewer rows, within its height.
    short = lines(full; limit = true, size = (12, 80))
    @test length(short) <= 12
    @test [cells(l)[1] for l in short[3:end]] == ["1", "2", "3", "4", "⋮", "31", "32"]
    # Twenty rows fit a tall display; twenty-one do not.
    twenty = factorial_cases(TestSpace((a = 1:4, b = 1:5)))
    @test length(lines(twenty; limit = true, size = (50, 80))) == 2 + 20
    many = factorial_cases(TestSpace((a = 1:3, b = 1:7)))
    @test length(lines(many; limit = true, size = (50, 80))) == 2 + 10 + 1 + 5

    # A wide cell is cut with "…" under :limit and printed whole otherwise.
    long = "x"^50
    wide = covering_cases(TestSpace((a = [long, "y"], b = [:short, :s], c = [1, 2])))
    table = lines(wide; limit = true, size = (24, 40))[2:end]
    @test all(l -> textwidth(l) <= 40, table)
    @test any(l -> occursin("xxx…", l), table)
    @test !any(l -> occursin(repr(long), l), table)
    @test any(l -> occursin(repr(long), l), lines(wide))

    # Too many columns: the columns that fit, then "…".
    params = TestSpace((Symbol(:p, i) => [1, 2, 3] for i in 1:30)...)
    many_columns = covering_cases(params; positional = true)
    table = lines(many_columns; limit = true, size = (24, 60))[2:end]
    @test all(l -> textwidth(l) <= 60, table)
    @test all(l -> endswith(l, "…"), table)
    @test startswith(table[1], "     p1  p2  p3")
    @test !occursin("p30", table[1])
    @test endswith(lines(many_columns)[2], "p30")
    # The summary is never cut.
    @test lines(many_columns; limit = true, size = (24, 60))[1] == repr(many_columns)
end


@testitem "testcases: Tables.jl reads named results; positional results need names (plan Phase 4 step 7)" setup=[CasesSetup] begin
    using DataFrames, CSV
    Tables = DataFrames.Tables

    cases = covering_cases(solver_space())
    @test Tables.istable(cases)
    df = DataFrame(cases)
    @test names(df) == ["mode", "solver", "tol"]
    @test eltype.(eachcol(df)) == [Symbol, Symbol, Float64]
    @test Tables.rowtable(df) == collect(cases)
    @test size(df) == (5, 3)

    # CSV is text: Symbols go out as their names and come back as strings.
    io = IOBuffer()
    CSV.write(io, cases)
    text = String(take!(io))
    @test startswith(text, "mode,solver,tol\n")
    @test occursin("\nexact,qr,1.0e-6\n", text)
    back = DataFrame(CSV.File(IOBuffer(text); stringtype = String))
    @test names(back) == names(df)
    @test back.mode == string.(df.mode)
    @test Symbol.(back.solver) == [row.solver for row in cases]
    @test back.tol == [row.tol for row in cases]

    # Typed columns. CSV refuses a `nothing` cell; mapped to missing it goes
    # out as an empty field and comes back missing.
    typed = covering_cases(TestSpace((n = [1, 2, 3], z = [nothing, :x], s = ["fast", "slow"])))
    df = DataFrame(typed)
    @test eltype.(eachcol(df)) == [Int, Union{Nothing, Symbol}, String]
    @test Tables.rowtable(df) == collect(typed)
    @test_throws ArgumentError CSV.write(IOBuffer(), typed)
    io = IOBuffer()
    CSV.write(io, typed; transform = (column, value) -> something(value, missing))
    back = DataFrame(CSV.File(IOBuffer(String(take!(io))); stringtype = String))
    @test back.n == [row.n for row in typed]
    @test back.s == [row.s for row in typed]
    @test [ismissing(z) ? nothing : Symbol(z) for z in back.z] == [row.z for row in typed]

    # A positional result is a vector of Tuples. Tables.jl does not call it a
    # table and names Tuple columns by position; the recipe names them.
    pspace = TestSpace(:p1 => [1, 2, 3], :p2 => [nothing, :x], :p3 => ["fast", "slow"])
    positional = covering_cases(pspace; positional = true)
    @test !Tables.istable(positional)
    @test names(DataFrame(positional)) == ["1", "2", "3"]
    named = DataFrame(positional, parameters(positional.space))
    @test names(named) == ["p1", "p2", "p3"]
    @test eltype.(eachcol(named)) == [Int, Union{Nothing, Symbol}, String]
    @test Tuple.(Tables.rowtable(named)) == collect(positional)
    @test_throws Exception CSV.write(IOBuffer(), positional)
    io = IOBuffer()
    CSV.write(io, NamedTuple{Tuple(parameters(positional.space))}.(positional);
              transform = (column, value) -> something(value, missing))
    @test startswith(String(take!(io)), "p1,p2,p3\n")
end
