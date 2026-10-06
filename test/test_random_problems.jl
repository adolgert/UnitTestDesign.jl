using Test
using TestItemRunner

# The random-problem gate (plan Phase 1 step 4, mandatory from Phase 3 step 8).
# Random constrained problems go through `generate` with every engine of the
# registry (`_engine_registry`, src/engines.jl; plan §4.2), at strengths 2 and
# 3, and every design is checked by the independent oracle (checker.jl): every
# row valid and every feasible target covered (contract §1.3). The design's
# bookkeeping must agree with the oracle too: its required count is the
# oracle's feasible count, and each excluded target has the oracle's status,
# with the same rules when it is directly forbidden (§1.4). An engine added to
# the registry is checked here with no change to this file.
#
# There is no expected failure. Every problem must return a certified design
# from every engine whose fit accepts it; an exception from any engine is
# logged with its problem and fails the gate. An engine whose fit refuses a
# problem, as `Construction` refuses mixed value counts, must refuse it by
# name with an `ArgumentError` (`_check_fit`); the gate counts the refusals,
# and every engine must be checked on some problems. Before Phase 3 the 0.4 IPOG crashed on about 40% of
# these problems and the 0.4 GND never returned on those with an implied
# target (issue #51).

@testsnippet RandomGate begin
    using Random
    using UnitTestDesign: Request, generate, to_cases, _engine_registry, fit, Profile

    """
    The tally key for one engine's count: the registry name in lower case and
    without punctuation, so that `IPOG()`'s checked designs are `:ipog_checked`.
    """
    engine_key(name, what) = Symbol(strip(replace(lowercase(name), r"[^a-z0-9]+" => "_"), '_'), :_, what)

    """
    Run `n_problems` problems at `strength` through every registered engine and
    check each design with the oracle. Returns the tallies and the stream
    `seed`. Problem `index` is the `index`-th draw of the stream;
    `gate_problem` redraws it. A randomized engine takes the problem's seed.
    """
    function random_gate(strength, seed, n_problems)
        rng = Xoshiro(seed)
        tally = Dict(k => 0 for k in (:problems, :implied, :planted, :empty))
        for (name, _) in _engine_registry(), what in (:checked, :error, :rows, :refused)
            tally[engine_key(name, what)] = 0
        end
        for index in 1:n_problems
            problem = random_problem(rng; strength)
            engine_seed = Int(rand(rng, UInt64) >> 1)  # one draw per problem, as gate_problem expects
            tally[:problems] += 1
            tally[:implied] += problem.implied > 0
            tally[:planted] += problem.planted
            tally[:empty] += problem.feasible == 0
            space = test_space(problem.space)
            for (name, engine) in _engine_registry(engine_seed)
                request = Request(space; strength)
                if fit(engine, Profile(request)).kind === :unsupported
                    refused = try
                        generate(engine, request)
                        false
                    catch err
                        err isa ArgumentError
                    end
                    refused || @error("$engine's fit refuses random problem $index, and generate did not " *
                                      "refuse it with an ArgumentError", problem)
                    tally[engine_key(name, refused ? :refused : :error)] += 1
                    continue
                end
                design = try
                    generate(engine, request)
                catch err
                    err isa InterruptException && rethrow()
                    # Any exception fails the gate; gate_verdicts asserts the count is 0.
                    @error("$engine threw on random problem $index; redraw it with " *
                           "gate_problem($strength, $(repr(seed)), $index)",
                           problem, exception = (err, catch_backtrace()))
                    tally[engine_key(name, :error)] += 1
                    continue
                end
                tally[engine_key(name, :checked)] += 1
                tally[engine_key(name, :rows)] += size(design.matrix, 2)
                check_returned(design, request, problem, engine, (strength, seed, index))
            end
        end
        return (; tally, seed)
    end

    "Problem `index` of the stream that `random_gate(strength, seed, n)` draws."
    function gate_problem(strength, seed, index)
        rng = Xoshiro(seed)
        for _ in 1:(index - 1)
            random_problem(rng; strength)
            rand(rng, UInt64)  # the engines' seed random_gate draws after each problem
        end
        return random_problem(rng; strength)
    end

    "A target in engine positions as the oracle writes it: assigned names and their values."
    function checker_target(problem, t)
        assigned = findall(!=(0), t)
        return NamedTuple{Tuple(problem.names[assigned])}(Tuple(problem.domains[p][t[p]] for p in assigned))
    end

    """
    Assert that the design is complete by the oracle and that its bookkeeping
    agrees with the oracle's classification of every target.
    """
    function check_returned(design, request, problem, engine, where)
        cases = to_cases(request, design.matrix)
        result = check_design(cases, problem.space; strength = problem.strength)
        ok = complete(result)
        ok || @error "$engine returned a design that fails the checker" where problem result
        @test ok

        part = result.ordinary
        verdict = Dict{NamedTuple, Tuple{Symbol, Vector{Int}}}()
        for (t, rules) in part.forbidden
            verdict[t] = (:forbidden, rules)
        end
        for t in part.implied
            verdict[t] = (:implied, Int[])
        end
        counted = design.required == design.covered == part.counts.feasible &&
                  length(design.excluded) == part.counts.forbidden + part.counts.implied
        disagree = filter(design.excluded) do e
            v = get(verdict, checker_target(problem, e.target), nothing)
            v === nothing || v[1] != e.status || (e.status == :forbidden && v[2] != e.rules)
        end
        agree = counted && isempty(disagree)
        agree || @error("$engine's bookkeeping disagrees with the checker", where, problem,
                        required = design.required, covered = design.covered,
                        excluded = length(design.excluded), checker = part.counts,
                        disagree = [(checker_target(problem, e.target), e.status, e.rules) for e in disagree])
        @test agree
        return nothing
    end

    """
    Assert the tallies: every problem gave every registered engine a design the
    oracle accepts, or a refusal by name; IPOG and GND refuse none, and every
    engine was checked on some problems.
    """
    function gate_verdicts(gate, n_problems)
        tally = gate.tally
        @test tally[:problems] == n_problems
        for (name, _) in _engine_registry()
            @test tally[engine_key(name, :error)] == 0
            @test tally[engine_key(name, :checked)] + tally[engine_key(name, :refused)] == n_problems
            @test tally[engine_key(name, :checked)] > 0
        end
        @test tally[engine_key("IPOG()", :checked)] == tally[engine_key("GND()", :checked)] == n_problems
    end

    "500 problems at multiplier 1.0, and at least 50."
    gate_count() = max(50, round(Int, 500 * test_run_multiplier()))
end


@testitem "random problems: generator" setup=[UTSetup, Checker, RandomGate] begin
    using Random
    # Deterministic from the rng.
    a = [random_problem(Xoshiro(17); strength = 2) for _ in 1:3]
    b = [random_problem(Xoshiro(17); strength = 2) for _ in 1:3]
    @test all(repr(x) == repr(y) for (x, y) in zip(a, b))

    # gate_problem redraws a problem from the gate's stream.
    rng = Xoshiro(0x99)
    stream = [(random_problem(rng; strength = 3), rand(rng, UInt64))[1] for _ in 1:3]
    @test repr(gate_problem(3, 0x99, 3)) == repr(stream[3])

    rng = Xoshiro(0x51 ⊻ seed_mod())
    for _ in 1:100
        problem = random_problem(rng; strength = 2)
        @test 3 <= length(problem.names) <= 8
        @test all(d -> 2 <= length(d) <= 4 && allunique(d), problem.domains)
        @test 1 <= length(problem.rules) <= 4
        @test all(r -> 2 <= length(r.scope) <= 3 && allunique(r.scope), problem.rules)
        # The 0.4 form of the rules, kept as a record, agrees with the checker
        # on every complete row.
        valid = Set(Tuple(r) for r in valid_rows(problem.space))
        @test all(problem.disallow(row...) == !(row in valid)
                  for row in Iterators.product(problem.domains...))
    end

    # The 0.4 form never shows a rule a partial case.
    space = CheckSpace([:a, :b, :c], [[1, 2], [1, 2], [1, 2]],
        [((:a, :b), (a, b) -> (a === nothing || b === nothing) ? error("saw nothing") : a < b),
         ((:c, :a, :b), (c, a, b) -> any(isnothing, (a, b, c)) ? error("saw nothing") : c == a + b)])
    disallow = legacy_disallow(space)
    @test all(disallow(row...) isa Bool for row in Iterators.product(([nothing, 1, 2] for _ in 1:3)...))
    @test disallow(1, 2, nothing) == true    # rule 1 has its whole scope
    @test disallow(2, 1, nothing) == false   # rule 2 is not applied yet
    @test disallow(1, 1, 2) == true
    @test_throws ArgumentError legacy_disallow(CheckSpace((a = [nothing, 1], b = [1, 2])))

    # A share of problems have implied targets, some of them planted.
    rng = Xoshiro(0x77)
    problems = [random_problem(rng; strength = 2) for _ in 1:200]
    @test 0 < count(p -> p.implied > 0, problems) < 200
    @test any(p -> p.planted, problems)
end


@testitem "random problems: pairwise through every registered engine" setup=[UTSetup, Checker, RandomGate] begin
    n_problems = gate_count()
    gate = random_gate(2, 0x2026_0926_0000_0002 ⊻ seed_mod(), n_problems)
    @info "Random pairwise problems" seed = gate.seed tally = (; sort(collect(gate.tally))...)
    gate_verdicts(gate, n_problems)
end


@testitem "random problems: three-way through every registered engine" setup=[UTSetup, Checker, RandomGate] begin
    n_problems = gate_count()
    gate = random_gate(3, 0x2026_0926_0000_0003 ⊻ seed_mod(), n_problems)
    @info "Random three-way problems" seed = gate.seed tally = (; sort(collect(gate.tally))...)
    gate_verdicts(gate, n_problems)
end


@testitem "random problems: the certifier's recount on the layout agrees with the list's and the oracle's (§1.21)" setup=[UTSetup, Checker, RandomGate] begin
    using UnitTestDesign: _Classified, _recount, classify_targets, nrequired
    # Phase 5 (plan §5.6): `generate` certifies each design by recounting it
    # on the request's layout against the ids of the excluded targets
    # (`_recount`). On random problems, with every registered engine's design
    # and with designs broken by dropping a row or changing a value, it must
    # agree with the recount of the classified list (31bef0f's certification)
    # on the count and on the target a failure names, and, for designs of
    # valid rows, with the independent oracle on whether every feasible
    # target is covered.
    message(f) = try f(); nothing catch e; sprint(showerror, e) end
    rng = Xoshiro(0x2026_1009 ⊻ seed_mod())
    compared, failed, judged = Ref(0), Ref(0), Ref(0)
    for index in 1:15
        problem = random_problem(rng; strength = rand(rng, 2:3))
        space = test_space(problem.space)
        request = Request(space; strength = problem.strength)
        targets = _Classified(request).targets
        required, _ = classify_targets(request)
        for (name, engine) in _engine_registry(index)
            fit(engine, Profile(request)).kind === :unsupported && continue
            matrix = generate(engine, request).matrix
            designs = Matrix{Int}[matrix]
            for j in unique(rand(rng, axes(matrix, 2), 6))
                push!(designs, matrix[:, setdiff(axes(matrix, 2), j)])
            end
            for _ in 1:3
                changed = copy(matrix)
                i, j = rand(rng, axes(changed, 1)), rand(rng, axes(changed, 2))
                request.arity[i] > 1 || continue
                changed[i, j] = mod1(changed[i, j] + rand(rng, 1:(request.arity[i] - 1)), request.arity[i])
                push!(designs, changed)
            end
            for m in designs
                ours, listed = message(() -> _recount(request, m, targets)), message(() -> _recount(request, m, required))
                @test ours == listed
                ours === nothing && @test _recount(request, m, targets) == _recount(request, m, required) == nrequired(targets)
                check = check_design(to_cases(request, m), problem.space; strength = problem.strength)
                if isempty(check.ordinary.rejected)
                    @test (ours === nothing) == isempty(check.ordinary.missing)
                    judged[] += 1
                end
                compared[] += 1
                failed[] += ours !== nothing
            end
        end
    end
    @info "Recounts compared" compared = compared[] failed = failed[] judged = judged[]
    @test compared[] > 500 && failed[] > 200 && judged[] > 400
end


@testitem "random problems: one Invalid value, pairwise through every registered engine, both parts (§5, §6)" setup=[UTSetup, Checker] begin
    using Random
    using UnitTestDesign: _engine_registry, fit, Profile, Request
    # Plan Phase 6 step 5: each problem gives one random parameter the value
    # Invalid(-1) (domains hold 0:9, so it is a new choice). Every registered
    # engine generates at strength 2, a randomized one with the problem's
    # index as its seed, and the oracle judges the ordinary and the negative
    # part; the negative bookkeeping must match its counts. An engine whose
    # fit refuses a problem must refuse it with an ArgumentError.
    as_check(x::Invalid) = CheckInvalid(x.value)
    as_check(x) = x
    rng = Xoshiro(0x2026_0927_0006 ⊻ seed_mod())
    checked = Ref(0)
    refused = Ref(0)
    for index in 1:100
        problem = random_problem(rng; strength = 2)
        p = rand(rng, eachindex(problem.names))
        domains = [collect(Any, d) for d in problem.space.domains]
        push!(domains[p], CheckInvalid(-1))
        cs = CheckSpace(problem.space.names, domains, problem.space.rules)
        space = test_space(cs)
        for (_, engine) in _engine_registry(index)
            if fit(engine, Profile(Request(space; strength = 2))).kind === :unsupported
                @test_throws ArgumentError covering(space; strength = 2, engine)
                refused[] += 1
                continue
            end
            cases = try
                covering(space; strength = 2, engine)
            catch err
                err isa InterruptException && rethrow()
                @error("$engine threw on random problem $index with an Invalid value at $(problem.names[p])",
                       problem, exception = (err, catch_backtrace()))
                @test false
                continue
            end
            check = check_design([map(as_check, row) for row in cases], cs; strength = 2)
            ok = complete(check.ordinary) && complete(check.negative) &&
                 cases.required == check.ordinary.counts.feasible &&
                 cases.negative_required == cases.negative_covered == check.negative.counts.feasible &&
                 length(cases.negative_excluded) == check.negative.counts.forbidden + check.negative.counts.implied &&
                 issorted(hasinvalid.(collect(cases)))
            ok || @error("$engine's design with an Invalid value fails the checker", index, problem,
                         invalid_at = problem.names[p], check)
            @test ok
            checked[] += ok
        end
    end
    @test checked[] + refused[] == 100 * length(_engine_registry())
    @test checked[] > 100 * (length(_engine_registry()) - 1)
end
