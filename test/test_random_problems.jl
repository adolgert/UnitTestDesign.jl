using Test
using TestItemRunner

# The random-problem gate (plan Phase 1 step 4, mandatory from Phase 3).
# Random constrained problems go through the 0.4 engines, and every returned
# design must satisfy contract §1.3 according to the independent checker.
#
# Expected-failure policy, until Phase 3 repairs the engines (issue #51):
#
# - IPOG: only a BoundsError at index 0 is the known legacy defect. IPOG
#   commits a value without proving the row can still be completed, leaves a
#   0 in the row, and then indexes a domain at 0. It happens on every problem
#   with an implied target and on a few greedy dead ends without one. The
#   count is asserted with @test_broken, so it turns into an unexpected pass
#   when Phase 3 fixes IPOG. Any other exception, and any returned design the
#   checker rejects, is a real failure.
# - GND: it loops forever when an implied target remains, because no valid
#   row covers it and its attempt cap counts only rows it fails to build.
#   A hang cannot be an expected failure, so GND is skipped on exactly those
#   problems (pending: Phase 3). On the rest, only the attempt-cap
#   ErrorException is expected; it has not been observed there. A watchdog
#   on disallow calls turns an unexpected infinite loop into a real error.

@testsnippet RandomGate begin
    using Random

    "Run `n_problems` problems at `strength` through IPOG and GND; return the tallies."
    function random_gate(strength, seed, n_problems)
        rng = Xoshiro(seed)
        generate = strength == 2 ? all_pairs : all_triples
        tally = Dict(k => 0 for k in (
            :problems, :implied, :planted,
            :ipog_checked, :ipog_crash, :ipog_crash_implied, :ipog_crash_dead_end,
            :gnd_checked, :gnd_skipped, :gnd_cap))
        for _ in 1:n_problems
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
                tally[implied ? :ipog_crash_implied : :ipog_crash_dead_end] += 1
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
                tally[:gnd_cap] += 1
                nothing
            end
            if design !== nothing
                tally[:gnd_checked] += 1
                check_returned(design, problem, "GND")
            end
        end
        return tally
    end

    function check_returned(design, problem, engine)
        result = check_design(design, problem.space; strength = problem.strength)
        ok = complete(result)
        ok || @error "$engine returned a design that fails the checker" problem result
        @test ok
    end

    "Assert the tallies that do not depend on the draw, and record the expected failures."
    function gate_verdicts(tally, n_problems)
        @test tally[:problems] == n_problems
        @test tally[:ipog_checked] + tally[:ipog_crash] == n_problems
        @test tally[:gnd_checked] + tally[:gnd_cap] + tally[:gnd_skipped] == n_problems
        # Known legacy defect; flips to an unexpected pass when Phase 3 fixes IPOG.
        @test_broken tally[:ipog_crash] == 0
        # pending: Phase 3 — run GND on the problems with implied targets.
        @test_skip tally[:gnd_skipped] == 0
        if tally[:gnd_cap] > 0
            # Known legacy defect: the GND attempt cap. Not observed so far on
            # problems without implied targets.
            @test_broken tally[:gnd_cap] == 0
        end
    end

    "At least 50 problems, so the IPOG crash count cannot be zero by chance."
    gate_count() = max(50, round(Int, 500 * test_run_multiplier()))
end


@testitem "random problems: generator" setup=[UTSetup, Checker] begin
    using Random
    # Deterministic from the rng.
    a = [random_problem(Xoshiro(17); strength = 2) for _ in 1:3]
    b = [random_problem(Xoshiro(17); strength = 2) for _ in 1:3]
    @test all(repr(x) == repr(y) for (x, y) in zip(a, b))

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
    tally = random_gate(2, 0x2026_0926_0000_0002 ⊻ seed_mod(), n_problems)
    @info "Random pairwise problems" tally = (; sort(collect(tally))...)
    gate_verdicts(tally, n_problems)
end


@testitem "random problems: three-way through IPOG and GND" setup=[UTSetup, Checker, RandomGate] begin
    n_problems = gate_count()
    tally = random_gate(3, 0x2026_0926_0000_0003 ⊻ seed_mod(), n_problems)
    @info "Random three-way problems" tally = (; sort(collect(tally))...)
    gate_verdicts(tally, n_problems)
end
