using UnitTestDesign
# (w = 1, v = 1) is excluded twice over: rule 1 (quick, forward checking) and a 4-pigeon/3-hole
# all-different on x, y, z, u that applies only when w = 1 and v = 1 (slow to prove).
names4 = (:x, :y, :z, :u)
pig = [forbid((w, v, p, q) -> w == 1 && v == 1 && p == q, :w, :v, a, b)
       for (i, a) in enumerate(names4) for b in names4[(i + 1):end]]
sp = TestSpace((w = [1, 2], v = [1, 2], a = [1, 2], x = 1:3, y = 1:3, z = 1:3, u = 1:3);
    constraints = [forbid((w, v, a) -> w == 1 && v == 1, :w, :v, :a); pig])
ref = all_pairs(sp)
show_ex(c) = [(e.rules, e.minimal, e.limit) for e in c.excluded if e.target == (w = 1, v = 1)]
println("default: ", length(ref), " cases; (w=1,v=1) excluded as ", show_ex(ref))
for fl in (14, 12, 10, 8, 6)
    try
        c = all_pairs(sp; feasibility_limit = fl)
        println("feasibility_limit=$fl: ", length(c), " cases, rows identical to default: ", collect(c) == collect(ref),
                "; (w=1,v=1) excluded as ", show_ex(c), "; excluded identical: ",
                [(e.target, e.rules, e.minimal) for e in c.excluded] == [(e.target, e.rules, e.minimal) for e in ref.excluded])
    catch err
        println("feasibility_limit=$fl: ", typeof(err))
    end
end
