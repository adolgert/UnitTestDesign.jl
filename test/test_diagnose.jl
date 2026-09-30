using Test
using TestItemRunner

# Diagnosis after a run (src/diagnose.jl; plan Phase 6 steps 3 and 5):
# `diagnose`, `followups`. Contract §1.17, §3.9, §3.17, §5.5, §5.7, §8.6,
# §13.1, §14.1. Suspects are checked against a brute-force oracle written
# here in value space, and every follow-up claim against an enumeration of
# the space's valid rows: a found case must hold its suspect and no other,
# and an inseparable one must have no such case.

@testsnippet DiagnoseSetup begin
    using Combinatorics: combinations
    using UnitTestDesign: Diagnosis, Followup, Suspect

    "Opus's solver space: fails only when method = :newton and sparse = true."
    newton_space() = TestSpace((n = [10, 100, 1000], method = [:newton, :bicg, :gmres],
                                tol = [1e-3, 1e-6], sparse = [false, true]))
    newton_bug(c) = c.method == :newton && c.sparse

    shown(x) = sprint(show, MIME"text/plain"(), x)

    "The ArgumentError message of `f()`, or what happened instead."
    message(f) = try
        f()
        "no error"
    catch e
        e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e)): $(sprint(showerror, e))"
    end

    "The same value by the package's identity rule: same type and isequal (§2.1)."
    same(a, b) = typeof(a) === typeof(b) && isequal(a, b)

    "Whether the named row or combination `outer` holds every value of `inner`."
    holds(outer::NamedTuple, inner::NamedTuple) =
        all(k -> haskey(outer, k) && same(outer[k], inner[k]), keys(inner))

    """
    The oracle: every combination of 1 to `strength` values that a failing
    row holds and no passing row does, as `combination => failing rows`.
    Written over NamedTuples, with no index space and no package code.
    """
    function oracle_suspects(rows, passed, strength)
        found = Dict{Any, Vector{Int}}()
        subsets(row) = (NamedTuple{Tuple(names)}(Tuple(row[k] for k in names))
                        for s in 1:strength for names in combinations(collect(keys(row)), s))
        for (k, row) in enumerate(rows)
            passed[k] && continue
            for c in subsets(row)
                push!(get!(() -> Int[], found, c), k)
            end
        end
        for (k, row) in enumerate(rows)
            passed[k] || continue
            for c in subsets(row)
                delete!(found, c)
            end
        end
        return found
    end

    """
    Every valid row of a small space, by enumeration and isallowed, split by
    kind: `ordinary` rows hold no `Invalid` value; `negative` rows hold one
    and are valid when the rules that omit its parameter allow them (§5.5).
    Rows with two `Invalid` values are never valid (§5.7).
    """
    function valid_rows(space)
        names = Tuple(parameters(space))
        rows = [NamedTuple{names}(values) for values in Iterators.product(space.values...)]
        valid = filter(row -> isallowed(space, row), rows)
        @test !any(row -> count(x -> x isa Invalid, values(row)) > 1, valid)
        return (ordinary = filter(!hasinvalid, valid), negative = filter(hasinvalid, valid))
    end

    "The kinds of case that could hold `suspect`, in the order `followups` searches them."
    function row_kinds(space, suspect)
        bad = [k for k in keys(suspect) if suspect[k] isa Invalid]
        length(bad) > 1 && return NamedTuple[]
        length(bad) == 1 && return NamedTuple[NamedTuple{(only(bad),)}((suspect[only(bad)],))]
        names = parameters(space)
        return NamedTuple[NamedTuple();
                          [NamedTuple{(names[p],)}((v,)) for p in eachindex(names)
                           if !haskey(suspect, names[p]) for v in space.values[p] if v isa Invalid]]
    end

    """
    Check every follow-up of `d` against the space's valid rows, ordinary and
    negative, by brute force: a found case is a valid row of the kind it
    names, holds its suspect and no other, and its distance is right; an
    indistinguishable suspect holds the others it names; an inseparable
    suspect has no valid row of either kind that isolates it, and every kind
    of case that could hold it was searched. Returns the statuses.
    """
    function check_followups(d, fs)
        space = d.space
        rows = valid_rows(space)
        every = [rows.ordinary; rows.negative]
        suspects = [s.combination for s in d.suspects]
        @test [f.suspect for f in fs] == suspects
        for (j, f) in enumerate(fs)
            others = suspects[[i for i in eachindex(suspects) if i != j]]
            isolates(row) = holds(row, f.suspect) && !any(o -> holds(row, o), others)
            if f.status === :found
                @test isallowed(space, f.case)
                @test f.kind === (hasinvalid(f.case) ? :negative : :ordinary)
                @test any(row -> holds(row, f.case), f.kind === :negative ? rows.negative : rows.ordinary)
                @test isolates(f.case)
                @test f.from in d.suspects[j].failing
                failing_row = NamedTuple{Tuple(parameters(space))}(
                    Tuple(space.values[p][d.rows[f.from][p]] for p in eachindex(space.values)))
                @test f.changes == count(k -> !same(f.case[k], failing_row[k]), keys(f.case))
                @test isempty(f.others) && isempty(f.rules) && f.limit === nothing
                # The kinds searched are a prefix of the kinds that could hold it.
                kinds = row_kinds(space, f.suspect)
                @test isequal(f.searched, kinds[1:length(f.searched)])
            elseif f.status === :indistinguishable
                @test !isempty(f.others)
                @test all(o -> o in others && holds(f.suspect, o), f.others)
                @test f.case === nothing && f.kind === :none
            elseif f.status === :inseparable
                @test !any(isolates, every)   # proven: no valid row of any kind isolates it
                @test all(o -> o in others, f.others)
                @test f.case === nothing && f.kind === :none
                @test isequal(f.searched, row_kinds(space, f.suspect))
            else
                @test f.status === :unknown && f.kind === :none
            end
        end
        return [f.status for f in fs]
    end
end


@testitem "diagnose: Opus's newton/sparse example ranks the true cause first (§8.6)" setup=[DiagnoseSetup] begin
    space = newton_space()
    cases = all_pairs(space)
    @test length(cases) == 10
    passed = [!newton_bug(c) for c in cases]
    failing = findall(!, passed)
    @test length(failing) == 2

    d = diagnose(cases, passed)
    @test d isa Diagnosis
    @test d.status === :ranked
    @test d.strength == 2 && d.n_cases == 10 && d.n_failed == 2
    @test d.failing == failing && d.passing == findall(passed)
    @test isempty(d.conflicting)
    @test length(d.groups) == 3 && length(d.suspects) == 3
    @test all(g -> length(g) == 1, d.groups)

    top = d.suspects[1]
    @test top isa Suspect
    @test top.combination == (method = :newton, sparse = true)
    @test top.failures == 2 && top.passes == 0 && top.failing == failing
    # Opus's other two pairs, one failure each, parameter order breaking the tie.
    @test [s.combination for s in d.suspects[2:3]] == [(n = 1000, method = :newton), (n = 100, sparse = true)]
    @test [s.failures for s in d.suspects] == [2, 1, 1]
    @test all(s -> s.passes == 0, d.suspects)
    for s in d.suspects, k in s.failing
        @test !passed[k] && holds(cases[k], s.combination)
    end

    # The oracle agrees on the suspects and their failing rows.
    oracle = oracle_suspects(cases, passed, 2)
    @test Dict(s.combination => s.failing for s in d.suspects) == oracle

    @test shown(d) == """
        2 failures of 10 cases; 3 suspects in 3 groups (hypotheses, not proof)
        1. (method = :newton, sparse = true) — in 2 of 2 failures
        2. (n = 1000, method = :newton) — in 1 of 2 failures
        3. (n = 100, sparse = true) — in 1 of 2 failures"""
    @test sprint(show, d) == "2 failures of 10 cases; 3 suspects in 3 groups (hypotheses, not proof)"
end


@testitem "followups: every newton/sparse suspect is isolated near a failing case (§3.17, §8.6)" setup=[DiagnoseSetup] begin
    space = newton_space()
    cases = all_pairs(space)
    passed = [!newton_bug(c) for c in cases]
    d = diagnose(cases, passed)
    fs = followups(d)
    @test fs isa Vector{Followup}
    @test check_followups(d, fs) == [:found, :found, :found]

    # Opus's follow-ups keep one suspect and change the value that separates it.
    @test fs[1].case.method == :newton && fs[1].case.sparse && fs[1].case.n == 10
    @test fs[2].case == (n = 1000, method = :newton, tol = 1e-3, sparse = false)
    @test fs[3].case.n == 100 && fs[3].case.sparse && fs[3].case.method != :newton
    # Each is one change from a failing case: the heuristic, not a guarantee (§8.6).
    @test [f.changes for f in fs] == [1, 1, 1]
    @test all(f -> !passed[f.from], fs)

    lines = split(sprint(show, MIME"text/plain"(), fs), "\n")
    @test length(lines) == 4
    @test lines[2] == " (method = :newton, sparse = true): found " *
        "(n = 10, method = :newton, tol = 0.001, sparse = true), 1 change from case $(fs[1].from)"
    @test sprint(show, fs[2]) == "(n = 1000, method = :newton): found " *
        "(n = 1000, method = :newton, tol = 0.001, sparse = false), 1 change from case $(fs[2].from)"

    # Domain order finds valid isolating cases too; `from` is still the nearest failing case.
    fd = followups(d; prefer = :domain)
    @test check_followups(d, fd) == [:found, :found, :found]
    @test occursin("prefer is :nearest", message(() -> followups(d; prefer = :closest)))
    @test occursin("prefer is :nearest", message(() -> followups(d; prefer = "nearest")))
    @test occursin("feasibility_limit must be a positive integer", message(() -> followups(d; feasibility_limit = 0)))
    @test occursin("explanation_limit must be a positive integer", message(() -> followups(d; explanation_limit = 0)))
end


@testitem "diagnose agrees with the brute-force oracle at strengths 1 to 3" setup=[DiagnoseSetup] begin
    space = newton_space()
    cases = all_pairs(space)
    bugs = [c -> c.method == :newton && c.sparse,
            c -> c.tol == 1e-6,
            c -> (c.method == :gmres && c.tol == 1e-3) || newton_bug(c),
            c -> c.n == 1000 && c.method == :bicg && !c.sparse]
    for bug in bugs, strength in 1:3
        passed = [!bug(c) for c in cases]
        d = diagnose(cases, passed; strength)
        @test d.strength == strength
        @test Dict(s.combination => s.failing for s in d.suspects) == oracle_suspects(cases, passed, strength)
        # Ranked by failures, then size, and groups share one failing set.
        @test issorted([(-g[1].failures, length(g[1].combination)) for g in d.groups])
        for g in d.groups
            @test allequal(s.failing for s in g)
            @test issorted([length(s.combination) for s in g])
        end
        @test length(unique(g[1].failing for g in d.groups)) == length(d.groups)
        @test all(s -> s.failures == length(s.failing) && s.passes == 0, d.suspects)
    end
end


@testitem "diagnose: two independent faults are both ranked, and an innocent pair can lead (§8.6)" setup=[DiagnoseSetup] begin
    space = newton_space()
    cases = all_pairs(space)
    gmres_bug(c) = c.method == :gmres && c.tol == 1e-3
    passed = [!(newton_bug(c) || gmres_bug(c)) for c in cases]
    d = diagnose(cases, passed)
    faults = [(method = :newton, sparse = true), (method = :gmres, tol = 1e-3)]
    combos = [s.combination for s in d.suspects]
    @test all(f -> f in combos, faults)            # both true causes are suspects
    ranks = [findfirst(==(f), combos) for f in faults]
    # Neither cause is in every failure: the faults split them.
    @test all(f -> d.suspects[f].failures < length(d.failing), ranks)
    # And a pair that shares failing cases with both faults ranks above both,
    # as the docstring warns.
    lead = d.suspects[1]
    @test !(lead.combination in faults)
    @test lead.failures > maximum(d.suspects[r].failures for r in ranks)
    @test lead.combination == (tol = 1e-3, sparse = true)
    @test check_followups(d, followups(d)) isa Vector{Symbol}
end


@testitem "followups: a pair containing a suspect value is indistinguishable; group-mates separate" setup=[DiagnoseSetup] begin
    space = TestSpace((a = [1, 2], b = [1, 2], c = [1, 2]))
    rows = [(a = 1, b = 1, c = 1), (a = 1, b = 2, c = 2), (a = 2, b = 1, c = 2), (a = 1, b = 1, c = 2)]
    d = diagnose(rows, [true, true, false, true]; space)
    @test d.status === :ranked
    # One group: the value a = 2 and the two pairs holding it fail in the same case.
    @test length(d.groups) == 1
    @test [s.combination for s in d.groups[1]] == [(a = 2,), (a = 2, b = 1), (a = 2, c = 2)]
    @test shown(d) == """
        1 failure of 4 cases; 3 suspects in 1 group (hypotheses, not proof)
        1. (a = 2,) — in 1 of 1 failure — same failures as (a = 2, b = 1) and (a = 2, c = 2)"""

    fs = followups(d)
    @test check_followups(d, fs) == [:found, :indistinguishable, :indistinguishable]
    @test fs[1].case == (a = 2, b = 2, c = 1)
    @test fs[2].others == [(a = 2,)] && fs[3].others == [(a = 2,)]
    @test sprint(show, fs[2]) == "(a = 2, b = 1): indistinguishable; every case holding it holds (a = 2,)"

    # Two pairs in one group that do not contain each other can be separated.
    rows = [(a = 1, b = 1, c = 1), (a = 2, b = 2, c = 2), (a = 1, b = 2, c = 1)]
    d = diagnose(rows, [true, true, false]; space)
    @test [[s.combination for s in g] for g in d.groups] == [[(a = 1, b = 2), (b = 2, c = 1)]]
    fs = followups(d)
    @test check_followups(d, fs) == [:found, :found]
    @test [f.case for f in fs] == [(a = 1, b = 2, c = 2), (a = 2, b = 2, c = 1)]
end


@testitem "followups: rules make a suspect inseparable, and the proof names them (§3.13–§3.16)" setup=[DiagnoseSetup] begin
    reason = "a = 2 needs c = 2"
    space = TestSpace((a = [1, 2], b = [1, 2], c = [1, 2]); constraints = [forbid((a = 2, c = 1); reason)])
    rows = [(a = 2, b = 2, c = 2), (a = 1, b = 1, c = 1), (a = 2, b = 1, c = 2)]
    d = diagnose(rows, [true, true, false]; space)
    @test [s.combination for s in d.suspects] == [(a = 2, b = 1), (b = 1, c = 2)]
    fs = followups(d)
    @test check_followups(d, fs) == [:inseparable, :found]
    # The only valid case with a = 2, b = 1 has c = 2, so it holds the other suspect.
    f = fs[1]
    @test f.others == [(b = 1, c = 2)] && f.rules == [1] && f.labels == [reason]
    @test f.minimal === :verified && f.limit === nothing
    @test sprint(show, f) == "(a = 2, b = 1): inseparable; every valid case holding it also holds " *
                             "(b = 1, c = 2), under rule 1 ($reason)"
    @test fs[2].case == (a = 1, b = 1, c = 2)

    # A failing case that broke the rules is ranked like any other, and leaves a
    # suspect no valid case holds (§8.6).
    rows = [(a = 2, b = 2, c = 2), (a = 1, b = 1, c = 1), (a = 2, b = 1, c = 1), (a = 1, b = 2, c = 1)]
    d = diagnose(rows, [true, true, false, true]; space)
    fs = followups(d)
    @test [f.suspect for f in fs] == [(a = 2, b = 1), (a = 2, c = 1)]
    @test check_followups(d, fs) == [:found, :inseparable]
    @test fs[2].others == [] && fs[2].rules == [1]
    @test sprint(show, fs[2]) == "(a = 2, c = 1): inseparable; no valid case holds it: rule 1 ($reason) excludes it"

    # With no rule at all, the other suspects can cover every value of a parameter.
    space = newton_space()
    cases = all_pairs(space)
    passed = [!(newton_bug(c) || (c.method == :gmres && c.tol == 1e-3)) for c in cases]
    d = diagnose(cases, passed)
    fs = followups(d)
    statuses = check_followups(d, fs)
    k = findfirst(==(:inseparable), statuses)
    @test k !== nothing && isempty(fs[k].rules) && length(fs[k].others) >= 2
end


@testitem "followups: feasibility_limit = 1 gives unknown, and a retry resolves it (§3.17)" setup=[DiagnoseSetup] begin
    space = TestSpace((a = [1, 2], b = [1, 2], c = [1, 2], d = [1, 2]); constraints = [forbid((c = 1, d = 2))])
    rows = [(a = 1, b = 1, c = 1, d = 1), (a = 2, b = 2, c = 2, d = 2), (a = 1, b = 2, c = 1, d = 1)]
    d = diagnose(rows, [true, true, false]; space)
    @test [s.combination for s in d.suspects] == [(a = 1, b = 2), (b = 2, c = 1), (b = 2, d = 1)]

    limited = followups(d; feasibility_limit = 1)
    @test limited[1].status === :unknown
    @test limited[1].case === nothing && limited[1].limit == (:feasibility_limit => 1)
    @test sprint(show, limited[1]) ==
        "(a = 1, b = 2): unknown; feasibility_limit = 1 reached; retry with a larger limit"
    # A proof that needs no node stands under any limit; only its minimality waits (§3.15).
    @test limited[2].status === :inseparable && limited[2].minimal === :unresolved
    @test limited[2].limit == (:feasibility_limit => 1)
    @test endswith(sprint(show, limited[2]), "(whether each is needed is unresolved: feasibility_limit = 1 reached)")

    retried = followups(d)
    @test check_followups(d, retried) == [:found, :inseparable, :found]
    @test retried[2].minimal === :verified
    @test retried[2].others == [(b = 2, d = 1)] && retried[2].rules == [1]
end


@testitem "followups: invalid suspects use negative rows; isolation conditions still apply (§5.5, §5.7)" setup=[DiagnoseSetup] begin
    # For an ordinary n, k must be :y; a negative row at n skips that rule.
    space = TestSpace((n = [1, 2, Invalid(-1)], m = [:a, :b, Invalid(:z)], k = [:x, :y]);
                      constraints = [forbid(:n, :k) do n, k; k == :x end])
    rows = [(n = 1, m = :a, k = :y), (n = 2, m = :b, k = :y), (n = Invalid(-1), m = :a, k = :x),
            (n = 1, m = Invalid(:z), k = :y),
            (n = Invalid(-1), m = :b, k = :y), (n = Invalid(-1), m = Invalid(:z), k = :y)]
    passed = [true, true, true, true, false, false]
    # The last row holds two Invalid values and is ranked like any other (§8.6).
    d = diagnose(rows, passed; space)
    @test Dict(s.combination => s.failing for s in d.suspects) == oracle_suspects(rows, passed, 2)
    @test [s.combination for s in d.suspects] ==
        [(n = Invalid(-1), k = :y), (n = Invalid(-1), m = :b), (n = Invalid(-1), m = Invalid(:z))]

    fs = followups(d)
    @test check_followups(d, fs) == [:found, :found, :inseparable]
    # (n = Invalid(-1), m = :b) must avoid (n = Invalid(-1), k = :y), a condition that
    # names the invalid parameter, so k = :x, which only the negative-row policy allows.
    @test fs[2].case == (n = Invalid(-1), m = :b, k = :x)
    @test hasinvalid(fs[2].case) && isallowed(space, fs[2].case)
    @test !holds(fs[2].case, d.suspects[1].combination)
    @test fs[1].case == (n = Invalid(-1), m = :a, k = :y)
    # Two Invalid values: no valid case holds them (§5.7).
    @test fs[3].others == [] && fs[3].rules == []
    @test sprint(show, fs[3]) == "(n = Invalid(-1), m = Invalid(:z)): inseparable; it has more than " *
                                 "one Invalid value, and a case holds at most one"
end


@testitem "followups: a suspect kept out of ordinary cases is isolated by a negative case (§5.5, review round 1)" setup=[DiagnoseSetup] begin
    # The reviewer's example: the rule forbids b = 2 beside the ordinary n = 1,
    # but it reads n, so it does not apply to a negative case at n (§5.5).
    space = TestSpace((n = [1, Invalid(0)], b = [1, 2]); constraints = [forbid((n = 1, b = 2))])
    @test length(valid_rows(space).negative) == 2 && length(valid_rows(space).ordinary) == 1
    rows = [(n = 1, b = 1), (n = Invalid(0), b = 1), (n = Invalid(0), b = 2)]
    passed = [true, true, false]
    d = diagnose(rows, passed; space, strength = 1)
    @test [s.combination for s in d.suspects] == [(b = 2,)]
    for prefer in (:nearest, :domain)
        fs = followups(d; prefer)
        @test check_followups(d, fs) == [:found]
        f = only(fs)
        @test f.case == (n = Invalid(0), b = 2) && f.kind === :negative
        @test (f.from, f.changes) == (3, 0)
        @test isequal(f.searched, NamedTuple[NamedTuple(), (n = Invalid(0),)])
        @test sprint(show, f) == "(b = 2,): found negative case (n = Invalid(0), b = 2), failing case 3 itself"
    end

    # At strength 2 the pair (n = Invalid(0), b = 2) is a suspect too. Ordinary
    # cases cannot hold b = 2 and the negative one holds the pair, so the value
    # is inseparable, and the explanation names both kinds of case.
    d = diagnose(rows, passed; space)
    fs = followups(d)
    @test check_followups(d, fs) == [:inseparable, :indistinguishable]
    f = fs[1]
    @test f.others == [(n = Invalid(0), b = 2)] && f.rules == [1]
    @test isequal(f.searched, NamedTuple[NamedTuple(), (n = Invalid(0),)])
    @test sprint(show, f) == "(b = 2,): inseparable; every valid case holding it also holds " *
        "(n = Invalid(0), b = 2), under rule 1 on (n, b); searched ordinary cases and negative cases " *
        "with n = Invalid(0)"

    # An ordinary case wins a tie in changes, and needs no rule to be skipped.
    free = TestSpace((n = [1, 2, Invalid(0)], b = [1, 2], c = [:x, :y]))
    rows = [(n = 1, b = 1, c = :x), (n = 2, b = 1, c = :y), (n = Invalid(0), b = 1, c = :x),
            (n = 1, b = 2, c = :y)]
    d = diagnose(rows, [true, true, true, false]; space = free, strength = 1)
    fs = followups(d)
    @test check_followups(d, fs) == [:found]
    @test fs[1].kind === :ordinary && fs[1].changes == 0
    @test isequal(fs[1].searched, NamedTuple[NamedTuple()])   # a failing case itself stops the search
end


@testitem "followups: every claim holds by brute force over both kinds of case, for many outcomes (review round 1)" setup=[DiagnoseSetup] begin
    using Random: Xoshiro
    rng = Xoshiro(0x2026_0927_0601)
    spaces = [
        TestSpace((n = [1, Invalid(0)], b = [1, 2]); constraints = [forbid((n = 1, b = 2))]),
        TestSpace((n = [1, 2, Invalid(-1)], m = [:a, :b, Invalid(:z)], k = [:x, :y]);
                  constraints = [forbid(:n, :k) do n, k; k == :x end, forbid((m = :b, k = :y))]),
        TestSpace((a = [1, 2, Invalid(0)], b = [1, 2], c = [1, 2, Invalid(9)]);
                  constraints = [forbid((a = 1, b = 2)), forbid((a = 2, c = 1)), forbid((b = 1, c = 2))]),
    ]
    seen = Set{Symbol}()
    for space in spaces
        rows = let v = valid_rows(space); [v.ordinary; v.negative] end
        n = length(rows)
        outcomes = n <= 8 ? [digits(Bool, x; base = 2, pad = n) for x in 0:(2^n - 1)] :
                            [rand(rng, Bool, n) for _ in 1:40]
        for passed in outcomes, strength in 1:2, prefer in (:nearest, :domain)
            d = diagnose(rows, passed; space, strength)
            d.status === :ranked || continue
            fs = followups(d; prefer)
            union!(seen, check_followups(d, fs))
            for f in fs
                f.status === :found && push!(seen, f.kind)
            end
        end
    end
    # The sweep reaches every status the brute force can check, and both kinds of found case.
    @test issubset([:found, :inseparable, :indistinguishable, :ordinary, :negative], seen)
end


@testitem "diagnose: no failures, all failures, and repeated cases with conflicting outcomes" setup=[DiagnoseSetup] begin
    space = newton_space()
    cases = all_pairs(space)
    passed = [!newton_bug(c) for c in cases]

    d = diagnose(cases, fill(true, 10))
    @test d.status === :no_failures && isempty(d.groups) && isempty(d.suspects)
    @test shown(d) == "0 failures of 10 cases; nothing to diagnose"
    @test followups(d) == Followup[]

    d = diagnose(cases, fill(false, 10))
    @test d.status === :all_failed && isempty(d.groups)
    @test shown(d) == "10 failures of 10 cases; every case failed; no combination is implicated " *
                      "over another; check the setup"

    d = diagnose(NamedTuple[], Bool[]; space)
    @test d.status === :no_failures && d.n_cases == 0

    # Case 1 ran twice, passing once and failing once: both rows are left out.
    rows = [collect(cases); cases[1]]
    d = diagnose(rows, [passed; false]; space)
    @test d.status === :conflicting
    @test d.conflicting == [[1, 11]]
    @test d.n_failed == 3 && d.failing == findall(!, passed)
    kept = [k for k in 1:11 if !(k in (1, 11))]
    expected = oracle_suspects(rows[kept], [passed; false][kept], 2)
    @test Dict(s.combination => s.failing for s in d.suspects) ==
          Dict(c => kept[f] for (c, f) in expected)
    lines = split(shown(d), "\n")
    @test lines[1] == "3 failures of 11 cases; 4 suspects in 3 groups (hypotheses, not proof)"
    @test lines[2] == "cases 1 and 11 hold the same case with different outcomes; left out of the analysis"
    @test startswith(lines[3], "1. (method = :newton, sparse = true) — in 2 of 2 failures")

    # When the only other failure is the repeated case, nothing is left to rank.
    rows = [collect(cases); cases[7]]
    only_seven = copy(passed)
    only_seven[findall(!, passed)[2]] = true
    d = diagnose(rows, [only_seven; true]; space)
    @test d.status === :conflicting && d.conflicting == [[7, 11]] && isempty(d.suspects)
    @test startswith(shown(d), "1 failure of 11 cases; no failure outside the conflicting cases; nothing else to diagnose")

    # Repeats that agree are counted once per row.
    rows = [collect(cases); cases[7]]
    d = diagnose(rows, [passed; false]; space)
    @test d.status === :ranked
    @test d.suspects[1].combination == (method = :newton, sparse = true) && d.suspects[1].failures == 3
end


@testitem "diagnose: input errors name the problem" setup=[DiagnoseSetup] begin
    space = newton_space()
    cases = all_pairs(space)
    passed = [!newton_bug(c) for c in cases]
    @test message(() -> diagnose(cases, [true])) ==
        "diagnose got 1 outcome for 10 cases; passed needs one outcome per case, in case order"
    @test message(() -> diagnose(cases, [passed; true])) ==
        "diagnose got 11 outcomes for 10 cases; passed needs one outcome per case, in case order"
    @test message(() -> diagnose(cases, Any[passed[1:9]; missing])) ==
        "outcome 10 is missing; each outcome is true (passed) or false (failed)"
    @test occursin("diagnose needs the space the cases belong to", message(() -> diagnose(collect(cases), passed)))
    @test occursin("space must be a TestSpace", message(() -> diagnose(collect(cases), passed; space = 1)))
    @test message(() -> diagnose(cases, passed; strength = 5)) ==
        "strength 5 is larger than the number of parameters, 4 (contract §11.2)"
    @test occursin("strength must be a positive integer", message(() -> diagnose(cases, passed; strength = 0)))
    @test occursin("wrap a single case in a vector", message(() -> diagnose(cases[1], [true]; space)))
    @test occursin("cases first and their outcomes second", message(() -> diagnose(space, passed)))
    rows = Any[c for c in cases]
    rows[3] = (n = 10, method = :newton, tol = 1e-3)
    @test occursin("diagnose case 3", message(() -> diagnose(rows, passed; space)))
    @test occursin("no value for `sparse`", message(() -> diagnose(rows, passed; space)))
    rows[3] = (n = 10, method = :newton, tol = 1e-3, sparse = 1)
    @test startswith(message(() -> diagnose(rows, passed; space)), "diagnose case 3: 1 is not a value of `sparse`")
end


@testitem "diagnose: strength defaults, rows as vectors, and positional results" setup=[DiagnoseSetup] begin
    space = newton_space()
    # A full factorial has strength 0; diagnosis uses min(2, parameters).
    ff = full_factorial(space)
    @test ff.strength == 0
    d = diagnose(ff, [!newton_bug(c) for c in ff])
    @test d.strength == 2
    @test [s.combination for s in d.suspects] == [(method = :newton, sparse = true)]
    @test d.suspects[1].failures == 6
    ex = excursions(space)
    @test ex.strength == 0 && diagnose(ex, fill(true, length(ex))).strength == 2
    single = full_factorial((a = [1, 2, 3],))
    d = diagnose(single, [true, false, true])
    @test d.strength == 1 && [s.combination for s in d.suspects] == [(a = 2,)]

    # An explicit strength replaces the result's; strength 1 can leave no suspect.
    cases = all_pairs(space)
    passed = [!newton_bug(c) for c in cases]
    @test diagnose(cases, passed; strength = 3).strength == 3
    d = diagnose(cases, passed; strength = 1)
    @test d.status === :ranked && isempty(d.suspects)
    @test shown(d) == "2 failures of 10 cases; no suspects: every value in a failing case also appears " *
        "in a passing case; the fault may need more values together (diagnose at a higher strength) " *
        "or fail intermittently"

    # Rows as plain NamedTuples, tuples or vectors, with the space given; a BitVector of outcomes.
    named = diagnose(collect(cases), BitVector(passed); space)
    tuples = diagnose([Tuple(c) for c in cases], passed; space)
    vectors = diagnose([collect(Any, c) for c in cases], passed; space)
    @test [s.combination for s in named.suspects] == [s.combination for s in diagnose(cases, passed).suspects]
    @test [s.combination for s in tuples.suspects] == [s.combination for s in named.suspects]
    @test [s.combination for s in vectors.suspects] == [s.combination for s in named.suspects]

    # A positional result names its parameters p1, p2, ….
    pc = all_pairs([10, 100, 1000], [:newton, :bicg, :gmres], [1e-3, 1e-6], [false, true])
    ppassed = [!(c[2] == :newton && c[4]) for c in pc]
    d = diagnose(pc, ppassed)
    @test [s.combination for s in d.suspects] == [(p2 = :newton, p4 = true), (p1 = 1000, p2 = :newton), (p1 = 100, p4 = true)]
    @test startswith(split(shown(d), "\n")[2], "1. (p2 = :newton, p4 = true) — in 2 of 2 failures")
    fs = followups(d)
    @test check_followups(d, fs) == [:found, :found, :found]
    @test keys(fs[1].case) == (:p1, :p2, :p3, :p4)
    @test Tuple(fs[1].case) == (10, :newton, 1e-3, true)
end


@testitem "diagnose and followups on a generated result with negative rows (§5.5, §5.12)" setup=[DiagnoseSetup] begin
    # The error path for an invalid n mishandles m = :b.
    space = TestSpace((n = [1, 2, Invalid(-1)], m = [:a, :b], k = [:x, :y]);
                      constraints = [forbid((m = :b, k = :x); reason = "b needs y")])
    cases = all_pairs(space)
    @test any(hasinvalid, cases)
    passed = [!(hasinvalid(c) && c.m == :b) for c in cases]
    d = diagnose(cases, passed)
    @test Dict(s.combination => s.failing for s in d.suspects) == oracle_suspects(cases, passed, 2)
    @test d.suspects[1].combination == (n = Invalid(-1), m = :b)
    fs = followups(d)
    statuses = check_followups(d, fs)
    @test statuses[1] in (:found, :inseparable)
    # Rule 1 omits n, so it applies to negative rows at n (§5.5): with m = :b
    # the case needs k = :y, which is what can make the top suspect inseparable.
    statuses[1] === :inseparable && @test fs[1].rules == [1] && fs[1].labels == ["b needs y"]
    for f in fs
        f.status === :found && hasinvalid(f.suspect) && @test hasinvalid(f.case)
    end
end
