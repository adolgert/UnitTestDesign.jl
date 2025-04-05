using UnitTestDesign
using Documenter

CI = get(ENV, "CI", nothing) == "true"

makedocs(;
    modules=[UnitTestDesign],
    authors="Andrew Dolgert <adolgert@andrew.cmu.edu>",
    repo="https://github.com/adolgert/UnitTestDesign.jl/blob/{commit}{path}#L{line}",
    sitename="UnitTestDesign.jl",
    format=Documenter.HTML(;
        prettyurls=CI,
        canonical="https://adolgert.github.io/UnitTestDesign.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "Guide" => "man/guide.md",
            "Examples" => "man/examples.md",
            "Extended Example" => "man/example_extended.md",
            "Testing Methods" => "man/methods.md",
            "Engines" => "man/engines.md",
            "IPOG" => "man/ipog.md"
            ],
        "Reference" => "reference.md",
        "Contributing" => "contributing.md"
    ]
)

if CI
    deploydocs(;
        devbranch = "main",
        repo="github.com/adolgert/UnitTestDesign.jl",
        deploy_config=Documenter.GitHubActions()
    )
end
