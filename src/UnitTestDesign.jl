"""
Generates test cases, which are sets of arguments to use for testing functions.
"""
module UnitTestDesign

export IPOG
export GND
export Excursion
export generate_tuples
export all_tuples
export all_values
export all_pairs
export all_triples
export values_excursion
export pairs_excursion
export triples_excursion
export full_factorial
export TestSpace, parameters, Invalid, Partition, hasinvalid
export Constraint, forbid, require, @forbid, @require, ConstraintError
export ResourceLimitError

include("rule_table.jl")
include("constraints.jl")
include("space.jl")
include("feasibility.jl")
include("combinations.jl")
include("coverage_matrix.jl")
include("coverage_set.jl")
include("greedy_tuples.jl")
include("parameter_order.jl")
include("full_factorial.jl")
include("excursions.jl")
include("factorial_interface.jl")

end
