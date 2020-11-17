using UnitTestDesign
using Documenter

makedocs(;
    modules=[UnitTestDesign],
    authors="Andrew Dolgert <adolgert@uw.edu>",
    repo="https://github.com/adolgert/UnitTestDesign.jl/blob/{commit}{path}#L{line}",
    sitename="UnitTestDesign.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://adolgert.github.io/UnitTestDesign.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/adolgert/UnitTestDesign.jl",
)
