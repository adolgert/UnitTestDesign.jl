module UnitTestDesign

export n_way_coverage
export n_way_coverage_init
export n_way_coverage_filter
export n_way_coverage_multi
export ipog
export IPOG
export GND
export generate_tuples
export all_tuples
export all_values
export all_pairs
export all_triples

include("combinations.jl")
include("coverage_set.jl")
include("greedy_tuples.jl")
include("parameter_order.jl")
include("factorial_interface.jl")

end
