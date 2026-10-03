using UnitTestDesign
const U = UnitTestDesign

# b (p = 2) has an Invalid value. Rule 1 reads b (inactive for negative rows at b);
# rule 2 is an unlabeled function rule on (a, c), lazy because 9 > tabulation_limit = 4.

space = TestSpace((a = [1, 2, 3], b = [1, 2, Invalid(0)], c = [1, 2, 3], d = [1, 2]);
    constraints = [@forbid(b == 2 && d == 1), forbid((a, c) -> a == 3 && c == 3, :a, :c)],
    tabulation_limit = 4)
req = U.Request(space; strength = 2)
p = 2
println("active_rules(space, 2) = ", U.active_rules(space, p))
sub = U._negative_request(req, p, zeros(Int, 3, 0))
println("typeof(sub) = ", typeof(sub), "; sub.strength = ", sub.strength, "; sub.groups = ", sub.groups)
println("sub.space.names = ", sub.space.names)
println("parent scopes = ", [t.scope for t in space.tables], "; sub scopes = ", [t.scope for t in sub.space.tables])
println("parent rule_label(2) = ", U.rule_label(space, 2))
println("sub    rule_label(1) = ", U.rule_label(sub.space, 1))
println("lazy memo dict shared (sub.feasibility vs req.feasibility): ",
        sub.feasibility.rule_memo[1] === req.feasibility.rule_memo[2])
println("req.context.memos === req.feasibility.rule_memo: ", req.context.memos === req.feasibility.rule_memo)
println("sub.context.memos[1] === req.context.memos[2]: ", sub.context.memos[1] === req.context.memos[2])
println("sub-request context searches keys: ", collect(keys(sub.context.searches)))
println("sub.candidates == req.candidates[others]: ", sub.candidates == req.candidates[[1, 3, 4]])

# Generate and check the parent memo grows (sub-request engine searches write the shared dicts).
d = U.generate(IPOG(), req)
println("memo_size(req) after generate = ", U.memo_size(req),
        "; negative rows = ", count(j -> any(i -> d.matrix[i, j] > req.arity[i], 1:4), axes(d.matrix, 2)))
println("parent context searches after generate: ", sort(collect(keys(req.context.searches))))
