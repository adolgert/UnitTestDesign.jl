using TestItemRunner

@testsnippet UTSetup begin
    using Random
    using ArgParse

    # Some arguments support randomized testing.
    # 1. Longer random tests catch more bugs.
    #    Use --longer 1.0, with a larger number, and it will run longer.
    #    In the test, use time() to decide when to quit the test, and multiply
    #    time duration by test_run_multiplier().
    #    Under CI (CI=true or --ci) the multiplier defaults to 0.2. Two things
    #    override that default. An explicit --longer on the command line wins
    #    over it, and the environment variable UNITTESTDESIGN_TEST_LONGER
    #    (a Float64, such as "1.0" or "5") wins over everything, because a
    #    GitHub Actions job sets env more easily than test arguments.
    #    Precedence: UNITTESTDESIGN_TEST_LONGER, then --longer, then CI's
    #    0.2, then 1.0.
    #
    # 2. It's sometimes good to try new random seeds.
    #    Usually pin test seeds so that unit tests don't fail randomly, but
    #    sometimes it's good to explore, so call testing with "--randseed"
    #    and in the test, initialize the random number generator with
    #    Xoshiro(928347293 ⊻ seed_mod()) so that the seed can be randomized.
    #
    # 3. If something failed reproduce it by rerunning the seed that failed.
    #    That's the --seed 293847 option. If you saw a randseed fail and want
    #    to try it again, this will get you there.
    #
    function parse_commandline()
        CI = get(ENV, "CI", "false") == "true"
        # "longer" is nothing unless --longer is given, so an explicit value
        # can win over the CI default in test_run_multiplier().
        default_args = Dict(
            "longer" => nothing, "ci" => CI, "randseed" => false, "seed" => zero(UInt64)
            )
        # VisualStudio Code calls package testing with its own set of arguments
        # that differ from those we want to use on the command line.
        # ArgParse doesn't have an option to allow spurious argument, so let's
        # look for a keyword and short-circuit the ArgParse in that case.
        if "v:UnitTestDesign" in ARGS
            return default_args
        end

        settings = ArgParseSettings()
        add_arg_table!(settings,
            "--longer",
            Dict(
                :help => "Multiply randomized test lengths by this factor (default 1.0, or 0.2 under CI)",
                :arg_type => Float64,
                :default => nothing
            ),
            "--ci",
            Dict(
                :help => "Whether this is running in continuous integration (CI).",
                :action => :store_true
            ),
            "--randseed",
            Dict(
                :help => "Set a random seed for tests to try new values.",
                :action => :store_true
            ),
            "--seed",
            Dict(
                :help => "Set a particular random seed for all tests.",
                :arg_type => UInt64,
                :default => zero(UInt64)
            ),
        )
        parsed = try
             parse_args(settings)
        catch err
            if isa(err, ArgParseError)
                default_args
            else
                rethrow(err)
            end
        end
        if CI
            parsed["ci"] = true
        end
        return parsed
    end


    function test_run_multiplier()
        env = strip(get(ENV, "UNITTESTDESIGN_TEST_LONGER", ""))
        if !isempty(env)
            longer = tryparse(Float64, env)
            isnothing(longer) && throw(ArgumentError(
                "UNITTESTDESIGN_TEST_LONGER must be a Float64, got \"$env\""))
            return longer
        end
        args = parse_commandline()
        if !isnothing(args["longer"])
            return args["longer"]
        elseif args["ci"]
            return 0.2
        else
            return 1.0
        end
    end


    function seed_mod()
        args = parse_commandline()
        if args["seed"] > zero(UInt64)
            return args["seed"]
        elseif args["randseed"]
            return rand(UInt64)
        else
            return zero(UInt64)
        end
    end

end

@testsnippet IndexCoverage begin
    # Index-space coverage counts for the engine tests, which check designs
    # as parameters × cases matrices or vectors of rows of value positions.
    # They replace src/coverage_set.jl, removed in Phase 5: measurement in
    # the package is `coverage` (src/measure.jl), in value space, and the
    # oracle is test/checker.jl.
    using Combinatorics: combinations

    """
    The distinct `n_way`-tuples of nonzero values in `rows` (each indexable by
    parameter), as a `Dict` from each parameter subset to its set of tuples.
    """
    function tuples_in_trials(rows, n_way)
        n = length(first(rows))
        seen = Dict(Tuple(s) => Set{NTuple{n_way, Int}}() for s in combinations(1:n, n_way))
        for row in rows, (s, set) in seen
            values = ntuple(k -> row[s[k]], n_way)
            all(!=(0), values) && push!(set, values)
        end
        return seen
    end

    "The number of distinct `n_way`-tuples of nonzero values in `rows`."
    coverage_by_tuple(rows, n_way) = sum(length, values(tuples_in_trials(rows, n_way)); init = 0)

    "The number of `n_way` combinations of values `1:arity[i]`: an unconstrained space's targets."
    combination_count(arity, n_way) = sum(s -> prod(arity[s]), combinations(1:length(arity), n_way); init = 0)

    """
    `(start, finish)` for a design `matrix` (parameters × cases): `start` is
    the number of `n_way` combinations of values `1:arity[i]`, and `finish`
    how many of them no column contains.
    """
    function test_coverage(matrix, arity, n_way)
        subsets = collect(combinations(1:length(arity), n_way))
        start = sum(s -> prod(arity[s]), subsets; init = 0)
        covered = 0
        for s in subsets
            seen = Set(matrix[s, j] for j in axes(matrix, 2)
                       if all(k -> 1 <= matrix[s[k], j] <= arity[s[k]], eachindex(s)))
            covered += length(seen)
        end
        return (start = start, finish = start - covered)
    end
end

# Under CI (CI=true, which GitHub Actions sets, or --ci) the run leaves out
# test items tagged :skipci. They are the slow ones whose lines and branches
# other test items already reach, such as larger random sweeps and
# acceptance runs. Locally, without --ci, every test item runs.
const RUNNING_CI = get(ENV, "CI", "false") == "true" || "--ci" in ARGS

@run_package_tests filter = ti -> !(RUNNING_CI && :skipci in ti.tags)
