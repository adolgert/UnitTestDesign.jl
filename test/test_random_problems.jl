using Test
using TestItemRunner

# The random-problem gate (plan Phase 1 step 4, mandatory from Phase 3).
# Random constrained problems go through the 0.4 engines, and every returned
# design must satisfy contract §1.3 according to the independent checker.
#
# Expected-failure policy, until Phase 3 repairs the engines (issue #51):
#
# - IPOG: only a BoundsError at index 0 is the known legacy defect, and it is
#   the only expected failure in the gate. IPOG commits a value without
#   proving the row can still be completed, leaves a 0 in the row, and then
#   indexes a domain at 0. It happens on every problem with an implied target
#   and on a few greedy dead ends without one (a partly built row that no
#   value completes, although every target is feasible or directly
#   forbidden). The count is asserted with @test_broken, so it turns into an
#   unexpected pass when Phase 3 fixes IPOG, and under a ceiling, so a
#   regression that crashes IPOG on many more problems fails. The dead ends
#   are logged by stream seed and index (see `gate_problem`); fixtures.jl
#   freezes four of them. Any other exception, and any returned design the
#   checker rejects, is a real failure.
# - GND: it loops forever when an implied target remains, because no valid
#   row covers it and its attempt cap counts only rows it fails to build.
#   A hang cannot be an expected failure, so GND is skipped on exactly those
#   problems (pending: Phase 3). On the rest it must return a design the
#   checker accepts. Its attempt-cap ErrorException is not an expected
#   failure: it is caught so the run continues, logged with the problem, and
#   counted, and the count must be 0. A watchdog on disallow calls turns an
#   unexpected infinite loop into a real error.

@testsnippet RandomGate begin
    using Random

    """
    Run `n_problems` problems at `strength` through IPOG and GND. Return the
    tallies, the stream `seed`, and `dead_ends`, a `(; index, problem)` for
    each problem without an implied target on which IPOG crashed. Problem
    `index` is the `index`-th draw of the stream; `gate_problem` redraws it.
    """
    function random_gate(strength, seed, n_problems)
        rng = Xoshiro(seed)
        generate = strength == 2 ? all_pairs : all_triples
        tally = Dict(k => 0 for k in (
            :problems, :implied, :planted,
            :ipog_checked, :ipog_crash, :ipog_crash_implied, :ipog_crash_dead_end,
            :gnd_checked, :gnd_skipped, :gnd_cap))
        dead_ends = NamedTuple[]
        for index in 1:n_problems
            problem = random_problem(rng; strength)
            gnd_seed = rand(rng, UInt64)  # drawn for every problem, so skips don't shift the stream
            implied = problem.implied > 0
            tally[:problems] += 1
            tally[:implied] += implied
            tally[:planted] += problem.planted

            design = try
                generate(problem.domains...; disallow = problem.disallow, engine = IPOG())
            catch err
                # The known legacy defect, and nothing else.
                (err isa BoundsError && isdefined(err, :i) && err.i == (0,)) || rethrow()
                tally[:ipog_crash] += 1
                if implied
                    tally[:ipog_crash_implied] += 1
                else
                    # A greedy dead end: no target is implied.
                    tally[:ipog_crash_dead_end] += 1
                    push!(dead_ends, (; index, problem))
                end
                nothing
            end
            if design !== nothing
                tally[:ipog_checked] += 1
                check_returned(design, problem, "IPOG")
            end

            if implied  # pending: Phase 3 (GND never returns on an implied target)
                tally[:gnd_skipped] += 1
                continue
            end
            watched = budgeted(problem.disallow, 20_000_000, problem)
            design = try
                generate(problem.domains...; disallow = watched, engine = GND(rng = Xoshiro(gnd_seed)))
            catch err
                (err isa ErrorException &&
                 startswith(err.msg, "Could not construct a test case")) || rethrow()
                # Not an expected failure: gate_verdicts asserts the count is 0.
                @error "GND hit its attempt cap on a problem without implied targets" seed index problem
                tally[:gnd_cap] += 1
                nothing
            end
            if design !== nothing
                tally[:gnd_checked] += 1
                check_returned(design, problem, "GND")
            end
        end
        return (; tally, seed, dead_ends)
    end

    "Problem `index` of the stream that `random_gate(strength, seed, n)` draws."
    function gate_problem(strength, seed, index)
        rng = Xoshiro(seed)
        for _ in 1:(index - 1)
            random_problem(rng; strength)
            rand(rng, UInt64)  # the GND seed random_gate draws after each problem
        end
        return random_problem(rng; strength)
    end

    function check_returned(design, problem, engine)
        result = check_design(design, problem.space; strength = problem.strength)
        ok = complete(result)
        ok || @error "$engine returned a design that fails the checker" problem result
        @test ok
    end

    "Assert the tallies that do not depend on the draw, and record the expected failure."
    function gate_verdicts(gate, n_problems)
        tally = gate.tally
        @test tally[:problems] == n_problems
        @test tally[:ipog_checked] + tally[:ipog_crash] == n_problems
        @test tally[:ipog_crash_implied] + tally[:ipog_crash_dead_end] == tally[:ipog_crash]
        @test tally[:gnd_checked] + tally[:gnd_cap] + tally[:gnd_skipped] == n_problems
        # Every crash without an implied target is a greedy dead end: the space
        # has required targets, and every other target is directly forbidden.
        @test length(gate.dead_ends) == tally[:ipog_crash_dead_end]
        @test all(d -> d.problem.implied == 0 && d.problem.feasible > 0, gate.dead_ends)
        # Known legacy defect, the only expected failure; flips to an
        # unexpected pass when Phase 3 fixes IPOG.
        @test_broken tally[:ipog_crash] == 0
        # A ceiling on the same defect, so a regression that makes IPOG crash
        # on many more problems fails. Observed at multiplier 1.0 with the
        # fixed seeds: 201 of 500 pairwise and 194 of 500 three-way, about
        # 40%. The ceiling is 50% to leave headroom for --randseed draws: with
        # 500 problems the crash count has a standard deviation of
        # sqrt(0.24 * 500) ≈ 11, so 250 is more than four deviations above
        # 200. Small runs vary more: the fixed seeds give 48 of the first 100
        # pairwise problems (CI's multiplier 0.2) and 26 of the first 50 (the
        # minimum), which a flat 50% would fail. So the ceiling is also at
        # least 3.5 deviations above 40%: 58 of 100 and 33 of 50.
        ceiling = max(ceil(Int, 0.5 * n_problems),
                      ceil(Int, 0.4 * n_problems + 3.5 * sqrt(0.24 * n_problems)))
        @test tally[:ipog_crash] <= ceiling
        # The GND attempt cap is not an expected failure; each hit was logged
        # with its problem.
        @test tally[:gnd_cap] == 0
        # pending: Phase 3 — run GND on the problems with implied targets.
        @test_skip tally[:gnd_skipped] == 0
    end

    "Log the IPOG dead ends: their indices, then (index, product size, rule count, problem)."
    function report_dead_ends(gate, strength)
        isempty(gate.dead_ends) && return nothing
        @info("IPOG greedy dead ends (no implied target), strength $strength; " *
              "redraw one with gate_problem($strength, $(repr(gate.seed)), index)",
              indices = [d.index for d in gate.dead_ends],
              dead_ends = [(d.index, prod(length, d.problem.domains), length(d.problem.rules), d.problem)
                           for d in gate.dead_ends])
        return nothing
    end

    "At least 50 problems, so the IPOG crash count cannot be zero by chance."
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
        # The legacy disallow agrees with the checker on every complete row.
        valid = Set(Tuple(r) for r in valid_rows(problem.space))
        @test all(problem.disallow(row...) == !(row in valid)
                  for row in Iterators.product(problem.domains...))
    end

    # The legacy disallow never shows a rule a partial case.
    space = CheckSpace([:a, :b, :c], [[1, 2], [1, 2], [1, 2]],
        [((:a, :b), (a, b) -> (a === nothing || b === nothing) ? error("saw nothing") : a < b),
         ((:c, :a, :b), (c, a, b) -> any(isnothing, (a, b, c)) ? error("saw nothing") : c == a + b)])
    disallow = legacy_disallow(space)
    @test all(disallow(row...) isa Bool for row in Iterators.product(([nothing, 1, 2] for _ in 1:3)...))
    @test disallow(1, 2, nothing) == true    # rule 1 has its whole scope
    @test disallow(2, 1, nothing) == false   # rule 2 is not applied yet
    @test disallow(1, 1, 2) == true
    @test_throws ArgumentError legacy_disallow(CheckSpace((a = [nothing, 1], b = [1, 2])))

    # The watchdog.
    stuck = budgeted((xs...) -> false, 3, :example)
    @test !stuck(1) && !stuck(1) && !stuck(1)
    @test_throws DisallowBudgetExceeded stuck(1)

    # A share of problems have implied targets, some of them planted.
    rng = Xoshiro(0x77)
    problems = [random_problem(rng; strength = 2) for _ in 1:200]
    @test 0 < count(p -> p.implied > 0, problems) < 200
    @test any(p -> p.planted, problems)
end


@testitem "random problems: pairwise through IPOG and GND" setup=[UTSetup, Checker, RandomGate] begin
    n_problems = gate_count()
    gate = random_gate(2, 0x2026_0926_0000_0002 ⊻ seed_mod(), n_problems)
    @info "Random pairwise problems" seed = gate.seed tally = (; sort(collect(gate.tally))...)
    report_dead_ends(gate, 2)
    gate_verdicts(gate, n_problems)
end


@testitem "random problems: three-way through IPOG and GND" setup=[UTSetup, Checker, RandomGate] begin
    n_problems = gate_count()
    gate = random_gate(3, 0x2026_0926_0000_0003 ⊻ seed_mod(), n_problems)
    @info "Random three-way problems" seed = gate.seed tally = (; sort(collect(gate.tally))...)
    report_dead_ends(gate, 3)
    gate_verdicts(gate, n_problems)
end
