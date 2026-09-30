# Contrast: the same predicate as a scoped rule over (a, b, c) is tabulated
# when the space is built (8 combinations <= tabulation_limit), so report()
# never calls it again.
#   julia --project=/Users/adolgert/dev/UnitTestDesign.jl probe_tabulated_contrast.jl
using UnitTestDesign
calls = Ref(0)
space = TestSpace((a = [0, 1], b = [0, 1], c = [0, 1]);
                  constraints = [forbid((a, b, c) -> (calls[] += 1; false), :a, :b, :c)])
println("at construction: ", calls[]); calls[] = 0
d = all_pairs(space); println("all_pairs: ", calls[], " (", length(d), " rows)"); calls[] = 0
report(d); println("report: ", calls[]); calls[] = 0
design_sizes(space); println("design_sizes: ", calls[])
