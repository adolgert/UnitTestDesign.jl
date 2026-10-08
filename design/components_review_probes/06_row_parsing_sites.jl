using UnitTestDesign
const U = UnitTestDesign
x = 3
println("== 1. expansion ==")
ex = @macroexpand @forbid(a == 1 && b > $x; reason = "why")
println(Base.remove_linenums!(ex))

println("\n== 2. macro from a module that only imports the package ==")
module Bare
import UnitTestDesign
helper(v) = v > 1
r = UnitTestDesign.@forbid(helper(a) && b == 2)
println("scope=", r.scope, " label=", r.label, " source=", r.source)
s = UnitTestDesign.TestSpace((a = [1, 2], b = [1, 2]); constraints = [r])
println("forbidden=", only(s.tables).forbidden)
end

println("\n== 3. macro vs listed-names Constraint fields ==")
m = @forbid(a == 1)
f = forbid(a -> a == 1, :a)
for fld in fieldnames(Constraint)
    println(rpad(fld, 10), " macro=", repr(getfield(m, fld)), "   names=", repr(getfield(f, fld)))
end

println("\n== 4. row shapes across entry points ==")
space = TestSpace((a = [1, 2], b = [:x, :y]); constraints = [forbid((a = 2, b = :y))])
function show_try(label, g)
    r = try
        v = g(); "ok: " * repr(v)[1:min(end, 110)]
    catch e
        string(typeof(e), ": ", sprint(showerror, e))[1:min(end, 200)]
    end
    println(rpad(label, 44), r)
end
show_try("coverage vector row", () -> coverage([[1, :x]], space).ordinary.covered)
show_try("coverage rule-breaking row (rejected?)", () -> length(coverage([(a = 2, b = :y)], space).rejected))
show_try("diagnose vector row", () -> diagnose([[1, :x], [2, :y]], [true, false]; space).status)
show_try("diagnose rule-breaking failing row", () -> [s.combination for s in diagnose([(a = 1, b = :x), (a = 2, b = :y)], [true, false]; space).suspects])
show_try("isallowed vector row", () -> isallowed(space, [1, :x]))
show_try("isallowed tuple row", () -> isallowed(space, (1, :x)))
show_try("explain vector row", () -> explain(space, [1, :x]))
show_try("all_pairs must_include vector", () -> collect(all_pairs(space; must_include = [[1, :x]]))[1])
show_try("all_pairs must_include partial NT", () -> collect(all_pairs(space; must_include = [(a = 1,)]))[1])
show_try("coverage partial NT", () -> coverage([(a = 1,)], space))
show_try("diagnose partial NT", () -> diagnose([(a = 1,)], [false]; space))
show_try("excursions from partial NT", () -> excursions(space; from = (a = 1,)))
show_try("excursions from vector (values)", () -> collect(excursions(space; from = [1, :x]))[1])
show_try("coverage short tuple", () -> coverage([(1,)], space))
show_try("diagnose short tuple", () -> diagnose([(1,)], [false]; space))
show_try("must_include short tuple", () -> all_pairs(space; must_include = [(1,)]))
show_try("excursions short tuple from", () -> excursions(space; from = (1,)))
show_try("isallowed short tuple", () -> isallowed(space, (1,)))
show_try("coverage unknown name", () -> coverage([(a = 1, b = :x, c = 0)], space))
show_try("must_include unknown name", () -> all_pairs(space; must_include = [(c = 0,)]))

println("\n== 5. internal generate_excursion: Vector{Int} means engine positions ==")
req = U.Request(TestSpace((a = [10, 20], b = [1, 2])); strength = 1)
d = U.generate_excursion(req; from = [2, 1], distance = 0)
println("from=[2,1] -> base column ", d.matrix[:, 1], " = ", U.from_indices(req.space, U._space_indices(req, d.matrix[:, 1])))
