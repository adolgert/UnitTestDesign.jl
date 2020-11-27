module UnitTestDesign

export n_way_coverage
export n_way_coverage_init
export n_way_coverage_filter
export n_way_coverage_multi

include("combinations.jl")
include("coverage_set.jl")
include("greedy_tuples.jl")
include("parameter_order.jl")

end
