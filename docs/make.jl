using UnitTestDesign
using Documenter

CI = get(ENV, "CI", nothing) == "true"

makedocs(;
    modules=[UnitTestDesign],
    authors="Andrew Dolgert <adolgert@andrew.cmu.edu>",
    sitename="UnitTestDesign.jl",
    # Phase 7 brings every exported docstring into the manual and fixes
    # cross references; until then these are warnings, not errors.
    warnonly=[:missing_docs, :cross_references, :docs_block],
    format=Documenter.HTML(;
        prettyurls=CI,
        canonical="https://adolgert.github.io/UnitTestDesign.jl",
        assets=String[],
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
