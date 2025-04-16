using TestEnv
using TestItemRunner

using UnitTestDesign

# For running tests from a Bash prompt.
# julia --project=test test/cli.jl --longer 100
# You need to ensure the test/Project.toml is set to Plg.develop(UnitTestDesign)
# so that it can load that in the activate() below.
TestEnv.activate("UnitTestDesign") do
    @run_package_tests
end
