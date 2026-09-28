using UnitTestDesign
using Documenter

CI = get(ENV, "CI", nothing) == "true"

# Every jldoctest block in a docstring runs after `using UnitTestDesign`, so
# none needs its own setup for it. A manual page's jldoctest blocks set up
# their own (a `@meta` block's `DocTestSetup`, or `setup =`).
# test/test_doctests.jl runs the same doctests with the same setup.
DocMeta.setdocmeta!(UnitTestDesign, :DocTestSetup, :(using UnitTestDesign); recursive = true)

makedocs(;
    modules=[UnitTestDesign],
    authors="Andrew Dolgert <adolgert@andrew.cmu.edu>",
    sitename="UnitTestDesign.jl",
    doctest=true,
    # Every exported name's docstring must appear in the manual (reference.md).
    checkdocs=:exports,
    warnonly=false,
    format=Documenter.HTML(;
        prettyurls=CI,
        canonical="https://adolgert.github.io/UnitTestDesign.jl",
        assets=String[],
        # reference.md holds every exported docstring on one page, about
        # 140 KiB of HTML, over the default 100 KiB warning. Warn above
        # 200 KiB and fail above 300 KiB instead.
        size_threshold_warn=200 * 2^10,
        size_threshold=300 * 2^10,
    ),
    pages=[
        "Home" => "index.md",
        "Tutorial" => "man/tutorial.md",
        "How-to guides" => [
            "Test a function with many options" => "howto/many_options.md",
            "Test generic code across types" => "howto/generic_types.md",
            "Plan a CI matrix" => "howto/ci_matrix.md",
            "Run a simulation campaign" => "howto/simulation_campaign.md",
            "Audit and extend an existing suite" => "howto/audit_existing.md",
            "Diagnose a failure" => "howto/diagnose.md",
            "Test invalid inputs" => "howto/invalid_inputs.md",
            "Combine with property-based testing" => "howto/property_based.md",
            "Commit a design as data" => "howto/commit_design.md",
            ],
        "Explanation" => [
            "Choosing values and oracles" => "explain/values_and_oracles.md",
            "Interaction coverage and the evidence" => "explain/coverage_evidence.md",
            "Constraints" => "explain/constraints.md",
            "Engines" => "man/engines.md",
            "IPOG" => "man/ipog.md",
            ],
        "Reference" => [
            "API" => "reference.md",
            "Migration from 0.4" => "reference/migration.md",
            ],
        "For AI agents" => "man/agents.md",
        "Developer" => [
            "Contract" => "dev/contract.md",
            "Non-goals" => "dev/non_goals.md",
            "Contributing" => "contributing.md",
            ],
    ]
)

if CI
    deploydocs(;
        devbranch = "main",
        repo="github.com/adolgert/UnitTestDesign.jl",
        deploy_config=Documenter.GitHubActions()
    )
end
