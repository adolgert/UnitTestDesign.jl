using ArgParse
using TestEnv
using TestItemRunner

using UnitTestDesign

# For running tests from a Bash prompt.
# julia --project=test test/cli.jl --longer 100
# You need to ensure the test/Project.toml is set to Plg.develop(UnitTestDesign)
# so that it can load that in the activate() below.

function parse_testcli(env_args)
    settings = ArgParseSettings()
    @add_arg_table settings begin
        "--file"
            help = "File to test"
            arg_type = String
            required = false
        "--name"
            help = "Name of the test to run"
            arg_type = String
            required = false
    end
    return parse_args(env_args, settings)
end


TestEnv.activate("UnitTestDesign") do
    args = parse_testcli(ARGS)
    matches = Function[ti -> true]
    if args["file"] !== nothing
        push!(matches, ti -> endswith(join(splitext(ti.filename)[1:end-1]), args["file"]))
    end
    if args["name"] !== nothing
        push!(matches, ti -> occursin(args["name"], ti.name))
    end
    @run_package_tests filter=ti -> all(map(f -> f(ti), matches))
end
