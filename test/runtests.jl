using TestItemRunner

@testsnippet UTSetup begin
    using Random
    using ArgParse

    # Some arguments support randomized testing.
    # 1. Longer random tests catch more bugs.
    #    Use --longer 1.0, with a larger number, and it will run longer.
    #    In the test, use time() to decide when to quit the test, and multiply
    #    time duration by test_run_multiplier().
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
        settings = ArgParseSettings()
        add_arg_table!(settings,
            "--longer",
            Dict(
                :help => "Multiply randomized test lengths by this factor",
                :arg_type => Float64,
                :default => 1.0
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
        parsed = parse_args(settings)
        if get(ENV, "CI", "false") == "true"
            parsed["ci"] = true
        end
        return parsed
    end


    function test_run_multiplier()
        args = parse_commandline()
        if args["ci"]
            return 0.2
        elseif !isnothing(args["longer"])
            longer = args["longer"]
            return longer
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

@run_package_tests
