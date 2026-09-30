using UnitTestDesign, Random
const U = UnitTestDesign
println("== 1. user predicate runs inside the feasibility search (lazy rule)")
calls = Ref(0)
sp = TestSpace((a = [1, 2, 3], b = [:x, :y], c = [0.5, 1.5]);
               constraints = [forbid(case -> (calls[] += 1; case.a == 3 && case.b == :y))])  # whole-case: always lazy
println("table lazy? ", sp.tables[1].lazy !== nothing, "  forbidden set: ", sp.tables[1].forbidden)
calls[] = 0; e = explain(sp, (a = 3,)); println("explain -> ", e.outcome, "; predicate calls during search: ", calls[])
bad = TestSpace((a = [1, 2, 3], b = [:x, :y]); constraints = [forbid(case -> case.a == 3 ? error("boom") : false)])
try explain(bad, (a = 3,)); catch err; println("throwing predicate surfaces from the search as: ", typeof(err)); end
tab = TestSpace((a = [1, 2, 3], b = [:x, :y]); constraints = [@forbid(a == 3 && b == :y)])
println("tabulated forbidden set (value-index tuples): ", tab.tables[1].forbidden, " scope ", tab.tables[1].scope)

println("\n== 3. feasibility_limit caps each deletion trial")
sp3 = TestSpace((a = [1, 2], x = [1, 2], y = [1, 2], z = [1, 2]);
    constraints = [forbid(a -> true, :a), forbid((x, y) -> x == y, :x, :y),
                   forbid((y, z) -> y == z, :y, :z), forbid((x, z) -> x == z, :x, :z)])
e1 = explain(sp3, NamedTuple(); feasibility_limit = 1, explanation_limit = 10^6)
println("feasibility_limit=1, explanation_limit=1e6: ", e1.outcome, " rules=", e1.rules, " minimal=", e1.minimal, " limit=", e1.limit)
e2 = explain(sp3, NamedTuple(); feasibility_limit = 10^6, explanation_limit = 10^6)
println("both 1e6: ", e2.outcome, " rules=", e2.rules, " minimal=", e2.minimal, " limit=", e2.limit)
e3 = explain(sp3, NamedTuple(); feasibility_limit = 10^6, explanation_limit = 1)
println("explanation_limit=1: ", e3.outcome, " rules=", e3.rules, " minimal=", e3.minimal, " limit=", e3.limit)

println("\n== 5. coverage of externally supplied rows")
s5 = TestSpace((m = [:fast, :exact], t = [1, 2]))
println("NamedTuples: ", coverage([(m = :fast, t = 1), (t = 2, m = :exact)], s5))
println("Tuples:      ", coverage([(:fast, 1), (:exact, 2)], s5))
println("Vectors:     ", coverage([Any[:fast, 1], Any[:exact, 2]], s5))
println("Generator:   ", coverage(((m = mm, t = 1) for mm in (:fast, :exact)), s5))
println("Positional domains: ", coverage([(:fast, 1)], [:fast, :exact], [1, 2]))
try coverage(permutedims(Any[:fast 1; :exact 2]), s5); println("Matrix accepted")
catch err; println("Matrix: ", typeof(err), ": ", first(sprint(showerror, err), 110)); end
try report([(m = :fast, t = 1)]); catch err; println("report(Vector): ", typeof(err)); end
try diagnose([(m = :fast, t = 1), (m = :exact, t = 2)], [true, false]; space = s5) |> x -> println("diagnose(external rows; space): ", x.status); catch err; println(err); end

println("\n== 7. github_matrix side effects")
cases = all_pairs(s5)
println("default io writes to stdout:"); r = github_matrix(cases); println("\nreturns: ", r)
buf = IOBuffer(); github_matrix(buf, cases); println("to IOBuffer: ", length(take!(buf)), " bytes")
big = [(k = i,) for i in 1:300]
github_matrix(IOBuffer(), big)   # expect a @warn
println("realize returns new rows, no mutation: ", realize((m = :fast, t = 1); rng = Xoshiro(1)))
