using TestItemRunner

@testsnippet UTSetup begin
    using ArgParse

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
            ))
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
            return args["longer"]
        else
            return 1.0
        end
    end

end

@run_package_tests
