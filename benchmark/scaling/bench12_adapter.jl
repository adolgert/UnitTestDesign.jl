# Benchmark the package's existing heterogeneous fixture without duplicating it.
include(joinpath(@__DIR__, "..", "fixtures.jl"))
function model(s::AbstractDict)
    s["family"] == "bench12" || return invoke(model,Tuple{Any},s)
    space=BenchFixtures.test_space(BenchFixtures.bench12)
    kw=(;strength=s["strength"],stronger=Pair[],must_include=Any[],
        feasibility_limit=get(s,"nodes",100_000),explanation_limit=get(s,"explanations",1_000_000))
    return (;space,kw,names=space.names,domains=space.values)
end
