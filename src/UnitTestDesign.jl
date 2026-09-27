"""
Generates test cases, which are sets of arguments to use for testing functions.
"""
module UnitTestDesign

export IPOG, GND
export covering, all_values, all_pairs, all_triples, excursions, full_factorial
export TestCases, Exclusion
# Deprecated aliases, kept for one release (contract §13.1, §13.2).
export all_tuples, values_excursion, pairs_excursion, triples_excursion
export TestSpace, parameters, Invalid, Partition, hasinvalid
export Constraint, forbid, require, @forbid, @require, ConstraintError
export ResourceLimitError
export isallowed, explain
export coverage, missing_interactions, Coverage, iscomplete
export report, Report, design_sizes, DesignSizes
export diagnose, followups
export github_matrix
export realize

include("rule_table.jl")
include("constraints.jl")
include("space.jl")
include("feasibility.jl")
include("explain.jl")
include("request.jl")
include("engines.jl")
include("testcases.jl")
include("measure.jl")
include("report.jl")
include("combinations.jl")
include("coverage_matrix.jl")
include("greedy_tuples.jl")
include("parameter_order.jl")
include("full_factorial.jl")
include("excursions.jl")
include("invalid.jl")
include("partition.jl")
include("interface.jl")
include("diagnose.jl")
include("export.jl")

end
