using Test
using TestItemRunner

# Tests of src/feasibility.jl, the index-space feasibility search (plan
# Phase 2 steps 6 and 8; contract §1.4–§1.7, §3, §5.5, §9.3, §9.7). Every
# test is in index space: hand-built RuleTables, candidate lists, and
# partial assignments with 0 for unset. The fixtures of test/fixtures.jl are
# translated by hand: value k of a parameter is the k-th value of its
# domain, and a rule becomes the table of value-index tuples it forbids.

@testsnippet FeasibilitySetup begin
    using UnitTestDesign: RuleTable, Feasibility, IndexExplanation, IndexClassification,
        completable, violates, violated_rules, dead, classify, explain_partial,
        components, forbids, assigned
    using UnitTestDesign: ResourceLimitError

    "A tabulated RuleTable from a scope and the value tuples it forbids."
    table(scope, forbidden...) =
        RuleTable(collect(Int, scope), Set{NTuple{length(scope), Int}}(forbidden))

    "A tabulated RuleTable forbidding the tuples of `1:arity` where `pred` holds."
    function tabulate(scope, arities, pred)
        tuples = Iterators.product((1:arities[p] for p in scope)...)
        return RuleTable(collect(Int, scope),
            Set{NTuple{length(scope), Int}}(t for t in tuples if pred(t...)))
    end

    "A complete row that no table forbids."
    valid(tables, row) = all(!=(0), row) && !any(t -> forbids(t, row), tables)

    "Whether `row` agrees with every assigned entry of `partial`."
    extends(row, partial) = all(i -> partial[i] == 0 || partial[i] == row[i], eachindex(partial))

    "A witness is a valid row extending the target, drawn from the candidates."
    good_witness(tables, cands, target, w) =
        w isa Vector{Int} && length(w) == length(target) && valid(tables, w) &&
        extends(w, target) && all(i -> w[i] in cands[i], eachindex(w))

    "Brute force: some row over the candidates extends `target` and satisfies `tables`."
    brute_feasible(tables, cands, target) =
        any(r -> extends(r, target) && valid(tables, r), (collect(r) for r in Iterators.product(cands...)))

    "Every target of size 1 and 2 over the candidates, in parameter then value order."
    function small_targets(cands)
        n = length(cands)
        targets = Vector{Int}[]
        for i in 1:n, v in cands[i]
            t = zeros(Int, n); t[i] = v
            push!(targets, t)
        end
        for i in 1:n, j in (i + 1):n, vi in cands[i], vj in cands[j]
            t = zeros(Int, n); t[i] = vi; t[j] = vj
            push!(targets, t)
        end
        return targets
    end

    "Every result field, so two results compare by value."
    fields(x) = ntuple(k -> getfield(x, k), fieldcount(typeof(x)))

    "Every field but the cost (`nodes`, `evaluations`), which depends on what was cached before."
    verdict(x) = Tuple(getfield(x, k) for k in fieldnames(typeof(x)) if !(k in (:nodes, :evaluations)))
end


@testitem "feasibility: Astra's chain, §1.2 §1.4 §3.16" setup=[FeasibilitySetup] begin
    # A == B and B == C over (1, 2): rules forbid A != B and B != C.
    cands = [[1, 2], [1, 2], [1, 2]]
    tables = [table([1, 2], (1, 2), (2, 1)), table([2, 3], (1, 2), (2, 1))]
    f = Feasibility(cands, tables)
    @test components(f) == [[1, 2, 3]]

    # (A = 1, C = 2) is implied by both rules, and both were verified necessary.
    e = explain_partial(f, [1, 0, 2])
    @test e.outcome == :infeasible
    @test e.rules == [1, 2]
    @test e.minimal == :verified
    @test e.witness === nothing
    c = only(classify(f, [[1, 0, 2]]))
    @test (c.status, c.rules, c.minimal) == (:implied, [1, 2], :verified)

    # (A = 1, B = 2) is forbidden directly by rule 1.
    @test violates(f, [1, 2, 0])
    @test violated_rules(f, [1, 2, 0]) == [1]
    e = explain_partial(f, [1, 2, 0])
    @test (e.outcome, e.rules, e.minimal) == (:forbidden, [1], :not_applicable)
    @test only(classify(f, [[1, 2, 0]])).status == :forbidden

    # (A = 1,) is completable, and the only witness is (1, 1, 1).
    @test completable(f, [1, 0, 0]) == (:feasible, [1, 1, 1])
    e = explain_partial(f, [1, 0, 0])
    @test (e.outcome, e.witness) == (:completable, [1, 1, 1])
    @test !dead(f, [1, 0, 0])
    @test dead(f, [1, 0, 2])

    # Complete rows: allowed or forbidden with every violated rule (§1.26).
    @test explain_partial(f, [2, 2, 2]).outcome == :allowed
    @test explain_partial(f, [2, 2, 2]).witness == [2, 2, 2]
    @test explain_partial(f, [1, 2, 1]).rules == [1, 2]
    c = only(classify(f, [[2, 2, 2]]))
    @test (c.status, c.witness) == (:required, [2, 2, 2])
end


@testitem "feasibility: Fable's solver, 11 required, 3 direct, 2 implied, §1.4 §1.5 §9.7" setup=[FeasibilitySetup] begin
    # mode (fast, exact), solver (none, lu, qr), tol (1e-3, 1e-6).
    # Rule 1: mode = fast forbids solver != none. Rule 2: exact forbids 1e-3.
    cands = [[1, 2], [1, 2, 3], [1, 2]]
    tables = [table([1, 2], (1, 2), (1, 3)), table([1, 3], (2, 1))]
    f = Feasibility(cands, tables)
    targets = filter(t -> count(!=(0), t) == 2, small_targets(cands))
    @test length(targets) == 16
    results = classify(f, targets)
    @test length(results) == 16

    status = Dict(targets[k] => results[k] for k in eachindex(targets))
    @test count(r -> r.status == :required, results) == 11
    @test count(r -> r.status == :forbidden, results) == 3
    @test count(r -> r.status == :implied, results) == 2
    @test status[[1, 2, 0]].rules == [1]   # fast + lu
    @test status[[1, 3, 0]].rules == [1]   # fast + qr
    @test status[[2, 0, 1]].rules == [2]   # exact + 1e-3
    for t in ([0, 2, 1], [0, 3, 1])        # lu + 1e-3, qr + 1e-3
        @test status[t].status == :implied
        @test status[t].rules == [1, 2]
        @test status[t].minimal == :verified
    end
    for (t, r) in zip(targets, results)
        if r.status == :required
            @test good_witness(tables, cands, t, r.witness)
            @test isempty(r.rules) && r.minimal == :not_applicable
        else
            @test r.witness === nothing
        end
    end
    # Results follow the input order (§9.7).
    reversed = classify(Feasibility(cands, tables), reverse(targets))
    @test map(fields, reversed) == map(fields, reverse(results))
end


@testitem "feasibility: Opus os/gpu/driver, §1.2 §1.4" setup=[FeasibilitySetup] begin
    # os (linux, mac, windows), gpu (false, true), driver (cuda, none).
    # Rule 1: a GPU forbids driver none. Rule 2: Windows forbids cuda.
    cands = [[1, 2, 3], [1, 2], [1, 2]]
    tables = [table([2, 3], (2, 2)), table([1, 3], (3, 1))]
    f = Feasibility(cands, tables)
    c = only(classify(f, [[3, 2, 0]]))
    @test (c.status, c.rules, c.minimal) == (:implied, [1, 2], :verified)
    results = classify(f, filter(t -> count(!=(0), t) == 2, small_targets(cands)))
    @test count(r -> r.status == :required, results) == 13
    @test count(r -> r.status == :forbidden, results) == 2
    @test count(r -> r.status == :implied, results) == 1
end


@testitem "feasibility: an unsatisfiable component beside a free parameter, §3.4 §1.24" setup=[FeasibilitySetup] begin
    # Fixture disconnected_unsat: `free` is in no rule; x and y may neither
    # match (rule 1) nor differ (rule 2).
    cands = [[1, 2, 3], [1, 2], [1, 2]]
    tables = [table([2, 3], (1, 1), (2, 2)), table([2, 3], (1, 2), (2, 1))]
    f = Feasibility(cands, tables)
    @test components(f) == [[1], [2, 3]]

    # The assigned parameter is unconstrained, yet the {x, y} component with
    # no assigned parameter makes the completion infeasible.
    @test !violates(f, [1, 0, 0])
    @test completable(f, [1, 0, 0]) == (:infeasible, nothing)
    @test f.stats.last_nodes == 2
    @test completable(f, zeros(Int, 3)) == (:infeasible, nothing)
    # The component's answer was cached for its empty sub-assignment.
    @test f.witness_cache[2][[0, 0]] === nothing
    @test completable(f, [3, 0, 0]) == (:infeasible, nothing)
    @test f.stats.last_nodes == 0

    # The deletion search names the rules of that component, and both are needed.
    e = explain_partial(f, [1, 0, 0])
    @test (e.outcome, e.rules, e.minimal) == (:infeasible, [1, 2], :verified)
    @test only(classify(f, [[0, 1, 1]])).rules == [1]
    @test only(classify(f, [[0, 1, 2]])).rules == [2]
end


@testitem "feasibility: two components need non-default witness values, §3.1 §3.4 §3.5" setup=[FeasibilitySetup] begin
    # Fixture disconnected_witness: a + b < 6 is forbidden over 1:3, so only
    # (3, 3); (c, d) over (x, y) must be (y, y); e is free.
    cands = [collect(1:3), collect(1:3), [1, 2], [1, 2], [1, 2]]
    arities = length.(cands)
    tables = [tabulate([1, 2], arities, (a, b) -> a + b < 6),
              tabulate([3, 4], arities, (c, d) -> !(c == 2 && d == 2))]
    f = Feasibility(cands, tables)
    @test components(f) == [[1, 2], [3, 4], [5]]

    status, w = completable(f, [0, 0, 0, 0, 1])
    @test status == :feasible
    @test w == [3, 3, 2, 2, 1]
    @test all(t -> !forbids(t, w), tables)
    # Each component's witness was cached and combined into the row.
    @test f.witness_cache[1][[0, 0]] == [3, 3]
    @test f.witness_cache[2][[0, 0]] == [2, 2]
    @test isempty(f.witness_cache[3])  # the free parameter is filled, not searched
    nodes = f.stats.last_nodes
    @test nodes > 0

    # Another question sharing both sub-assignments costs no nodes (§3.4).
    @test completable(f, [0, 0, 0, 0, 2]) == (:feasible, [3, 3, 2, 2, 2])
    @test f.stats.last_nodes == 0
    # A repeated question is a memo hit.
    hits = f.stats.memo_hits
    @test completable(f, [0, 0, 0, 0, 1]) == (:feasible, [3, 3, 2, 2, 1])
    @test f.stats.memo_hits == hits + 1

    # The returned witness is a copy: mutating it leaves the cache intact.
    _, w = completable(f, [0, 0, 0, 0, 1])
    w[1] = 1
    @test completable(f, [0, 0, 0, 0, 1])[2] == [3, 3, 2, 2, 1]

    # Assigned values are kept, and an assigned bad value is caught directly.
    @test completable(f, [3, 0, 0, 2, 0]) == (:feasible, [3, 3, 2, 2, 1])
    @test explain_partial(f, [1, 0, 0, 0, 0]).outcome == :infeasible
    @test explain_partial(f, [1, 0, 0, 0, 0]).rules == [1]
end


@testitem "feasibility: a whole-case table connects everything, §12.20 §12.21 §1.6" setup=[FeasibilitySetup] begin
    # Fixture whole_case_connects: disconnected_witness plus a whole-case rule
    # forbidding e == 1 whenever c == y.
    cands = [collect(1:3), collect(1:3), [1, 2], [1, 2], [1, 2]]
    arities = length.(cands)
    calls = Ref(0)
    whole = function (key)
        calls[] += 1
        # §1.6: a lazy rule is never called with an unset parameter.
        all(>(0), key) || error("whole-case rule called on a partial case $key")
        return key[5] == 1 && key[3] == 2
    end
    tables = [tabulate([1, 2], arities, (a, b) -> a + b < 6),
              tabulate([3, 4], arities, (c, d) -> !(c == 2 && d == 2)),
              RuleTable(1:5, whole)]
    f = Feasibility(cands, tables)
    @test components(f) == [[1, 2, 3, 4, 5]]

    @test completable(f, [0, 0, 0, 0, 2]) == (:feasible, [3, 3, 2, 2, 2])
    @test calls[] > 0
    @test completable(f, [0, 0, 0, 0, 1]) == (:infeasible, nothing)

    # Proven answers are memoized: asking again calls no rule and costs nothing.
    before = calls[]
    @test completable(f, [0, 0, 0, 0, 2]) == (:feasible, [3, 3, 2, 2, 2])
    @test completable(f, [0, 0, 0, 0, 1]) == (:infeasible, nothing)
    @test calls[] == before
    @test f.stats.last_nodes == 0
    @test haskey(f.memo, [0, 0, 0, 0, 1]) && f.memo[[0, 0, 0, 0, 1]] === nothing

    # (e = 1,) is implied by rules 2 and 3; rule 1 is not needed.
    e = explain_partial(f, [0, 0, 0, 0, 1])
    @test (e.outcome, e.rules, e.minimal) == (:infeasible, [2, 3], :verified)
    # The complete row with e = 1 is forbidden directly by the whole-case rule.
    @test explain_partial(f, [3, 3, 2, 2, 1]).rules == [3]
    @test explain_partial(f, [3, 3, 2, 2, 2]).outcome == :allowed
end


@testitem "feasibility: limits give unknown, never infeasible, §1.7 §3.1–§3.8" setup=[FeasibilitySetup] begin
    # Fixture limit_exhaustion: eight parameters over 1:4 and one whole-case
    # rule that allows only the row of all 4s.
    cands = [collect(1:4) for _ in 1:8]
    tables = [RuleTable(1:8, key -> !all(==(4), key))]
    target = [4, 0, 0, 0, 0, 0, 0, 0]

    f = Feasibility(cands, tables; limit = 1)
    @test completable(f, target) == (:unknown, nothing)
    @test f.stats.last_nodes == 1
    # §3.2, §3.5: the exhausted search is stored nowhere.
    @test !haskey(f.memo, target)
    @test all(isempty, f.witness_cache)
    @test completable(f, target) == (:unknown, nothing)
    @test_throws ResourceLimitError dead(f, target)
    err = try
        dead(f, target)
    catch e
        e
    end
    @test err.limit == 1 && err.keyword == :feasibility_limit
    @test occursin("[4, 0, 0, 0, 0, 0, 0, 0]", err.what)
    e = explain_partial(f, target)
    @test (e.outcome, e.limit, e.witness) == (:unknown, :feasibility_limit, nothing)
    c = only(classify(f, [target]))
    @test (c.status, c.rules, c.limit) == (:unknown, Int[], :feasibility_limit)

    # §3.8: a retry with a larger limit resolves it, on the same object or a
    # fresh one, because nothing was recorded as infeasible.
    @test completable(f, target; limit = 1_000_000) == (:feasible, fill(4, 8))
    @test !dead(f, target)  # now a memo hit, within the small limit
    g = Feasibility(cands, tables)
    @test g.limit == 1_000_000  # the default of §3.3
    @test completable(g, target) == (:feasible, fill(4, 8))
    @test !dead(g, target)
    @test dead(g, [1, 0, 0, 0, 0, 0, 0, 0])
    @test explain_partial(g, target).outcome == :completable

    # Two different sufficient limits give the same witness.
    @test completable(Feasibility(cands, tables; limit = 5461), target) ==
          completable(Feasibility(cands, tables; limit = 10^7), target)
end


@testitem "feasibility: node accounting and monotone limits, §3.3 §3.4 §3.8" setup=[FeasibilitySetup] begin
    # Astra by hand. From nothing: A = 1 (FC leaves B = {1}), B = 1 (FC leaves
    # C = {1}), C = 1: three nodes. From A = 1: two. From (A = 1, C = 2): the
    # initial prune empties B before any assignment, so zero.
    astra = () -> Feasibility([[1, 2], [1, 2], [1, 2]],
        [table([1, 2], (1, 2), (2, 1)), table([2, 3], (1, 2), (2, 1))])
    for (target, nodes, answer) in (([0, 0, 0], 3, :feasible), ([1, 0, 0], 2, :feasible),
                                    ([1, 0, 2], 0, :infeasible))
        h = astra()
        @test first(completable(h, target)) == answer
        @test h.stats.last_nodes == nodes
    end
    # disconnected_unsat: x = 1 and x = 2 each empty y, two nodes.
    f = Feasibility([[1, 2, 3], [1, 2], [1, 2]],
        [table([2, 3], (1, 1), (2, 2)), table([2, 3], (1, 2), (2, 1))])
    @test completable(f, [1, 0, 0]) == (:infeasible, nothing)
    @test f.stats.last_nodes == 2

    # limit_exhaustion from x1 = 4: every assignment of x2..x7 is tried
    # (4 + 16 + ... + 4^6 = 5460 nodes); forward checking empties x8 except
    # under all 4s, then x8 = 4 is node 5461. From nothing, 21845 nodes.
    cands = [collect(1:4) for _ in 1:8]
    tables = [RuleTable(1:8, key -> !all(==(4), key))]
    target = [4, 0, 0, 0, 0, 0, 0, 0]
    f = Feasibility(cands, tables)
    @test first(completable(f, target)) == :feasible
    @test f.stats.last_nodes == 5461
    f = Feasibility(cands, tables)
    @test first(completable(f, zeros(Int, 8))) == :feasible
    @test f.stats.last_nodes == 21845

    # A search that needs N nodes succeeds exactly when the limit is at least N.
    for limit in (1, 2, 100, 5459, 5460, 5461, 5462, 10_000, 10^6)
        h = Feasibility(cands, tables; limit)
        status, w = completable(h, target)
        @test status == (limit >= 5461 ? :feasible : :unknown)
        @test h.stats.last_nodes == min(limit, 5461)
        status == :feasible && @test w == fill(4, 8)
    end

    # On Fable's space, every question succeeds at exactly its own node count,
    # with the same answer and witness as at the default limit.
    cands = [[1, 2], [1, 2, 3], [1, 2]]
    tables = [table([1, 2], (1, 2), (1, 3)), table([1, 3], (2, 1))]
    for target in small_targets(cands)
        h = Feasibility(cands, tables)
        answer = completable(h, target)
        needed = h.stats.last_nodes
        needed == 0 && continue
        @test completable(Feasibility(cands, tables; limit = needed), target) == answer
        @test first(completable(Feasibility(cands, tables; limit = max(1, needed - 1)), target)) ==
              (needed == 1 ? answer[1] : :unknown)
    end
end


@testitem "feasibility: deletion search, §1.4 §3.13–§3.16" setup=[FeasibilitySetup] begin
    # A single rule wider than the target can be the whole explanation.
    # Rule 1 over (a, b, c) forbids every c when a = 1 and b = 1; rule 2 is
    # irrelevant. (a = 1, b = 1) is implied by rule 1 alone.
    cands = [[1, 2], [1, 2], [1, 2]]
    tables = [table([1, 2, 3], (1, 1, 1), (1, 1, 2)), table([2, 3], (2, 2))]
    f = Feasibility(cands, tables)
    @test !violates(f, [1, 1, 0])
    c = only(classify(f, [[1, 1, 0]]))
    @test (c.status, c.rules, c.minimal) == (:implied, [1], :verified)

    # The explanation limit on Astra's implied pair: the first trial (without
    # rule 1) spends the single node, so rule 2 is never tried. The target is
    # still proven infeasible and the full set is kept as sufficient (§3.15).
    astra = Feasibility([[1, 2], [1, 2], [1, 2]],
        [table([1, 2], (1, 2), (2, 1)), table([2, 3], (1, 2), (2, 1))])
    c = only(classify(astra, [[1, 0, 2]]; explanation_limit = 1))
    @test c.status == :implied
    @test c.rules == [1, 2]
    @test c.minimal == :unresolved
    @test c.limit == :explanation_limit
    # Two nodes are enough to verify both rules.
    c = only(classify(astra, [[1, 0, 2]]; explanation_limit = 2))
    @test (c.rules, c.minimal, c.limit) == ([1, 2], :verified, nothing)

    # A trial that ends unknown keeps its rule (§3.14). Rule 1 empties x1, so
    # the full set is infeasible at once. Without rule 1, the whole-case rule
    # 2 needs 5461 nodes to find its witness; without rule 2, rule 1 still
    # proves it. So rule 2 is dropped and rule 1 kept.
    cands = [collect(1:4) for _ in 1:8]
    tables = [table([1], (1,), (2,), (3,), (4,)), RuleTable(1:8, key -> !all(==(4), key))]
    target = [0, 4, 0, 0, 0, 0, 0, 0]
    e = explain_partial(Feasibility(cands, tables), target)
    @test (e.outcome, e.rules, e.minimal, e.limit) == (:infeasible, [1], :verified, nothing)
    # The trial's own feasibility limit stops it: rule 1 kept, unverified.
    e = explain_partial(Feasibility(cands, tables; limit = 100), target)
    @test (e.outcome, e.rules, e.minimal, e.limit) == (:infeasible, [1], :unresolved, :feasibility_limit)
    # The explanation budget stops it: nothing dropped, the full set kept.
    e = explain_partial(Feasibility(cands, tables), target; explanation_limit = 50)
    @test (e.outcome, e.rules, e.minimal, e.limit) == (:infeasible, [1, 2], :unresolved, :explanation_limit)
    # Proven infeasibility never depends on the explanation budget (§3.15).
    @test dead(Feasibility(cands, tables; limit = 1), target)
end


@testitem "feasibility: negative rows use restricted candidates and tables, §5.5 §12.22 §1.24" setup=[FeasibilitySetup] begin
    # Fixture invalid_beside_ordinary: n in (1, 2, Invalid(1)) as indices
    # 1, 2, 3; m in (a, b); k in (x, y). Rule 1 over (n, m) forbids (2, b);
    # rule 2 over (m, k) forbids (a, y).
    rule1 = table([1, 2], (2, 2))
    rule2 = table([2, 3], (1, 2))
    ordinary = Feasibility([[1, 2], [1, 2], [1, 2]], [rule1, rule2])
    @test completable(ordinary, [2, 2, 0]) == (:infeasible, nothing)

    # Negative rows at n: the one invalid index, and only the rules whose
    # scope omits n.
    negative = Feasibility([[3], [1, 2], [1, 2]], [rule2])
    @test components(negative) == [[1], [2, 3]]
    @test completable(negative, [3, 0, 0]) == (:feasible, [3, 1, 1])
    @test completable(negative, [0, 0, 2]) == (:feasible, [3, 2, 2])
    @test completable(negative, [3, 2, 0]) == (:feasible, [3, 2, 1])  # rule 1 not applied
    @test completable(negative, [3, 1, 2]) == (:infeasible, nothing)
    @test violated_rules(negative, [3, 1, 2]) == [1]  # position in the negative table list
    valid_negative = [r for r in ([3, m, k] for m in 1:2, k in 1:2) if valid([rule2], r)]
    @test length(valid_negative) == 3
    targets = [[3, 1, 0], [3, 2, 0], [3, 0, 1], [3, 0, 2]]
    @test all(c -> c.status == :required, classify(negative, targets))
    # An ordinary index at n is not among the negative candidates.
    @test_throws ArgumentError completable(negative, [1, 0, 0])

    # Fixture empty_ordinary_negative_seed: no ordinary row, one negative row.
    ordinary = Feasibility([[1], [1]], [table([1, 2], (1, 1))])
    @test completable(ordinary, [0, 0]) == (:infeasible, nothing)
    negative = Feasibility([[2], [1]], RuleTable[])
    @test completable(negative, [0, 0]) == (:feasible, [2, 1])
    @test completable(negative, [2, 1]) == (:feasible, [2, 1])
end


@testitem "feasibility: determinism, §9.1 §9.3 §9.7" setup=[FeasibilitySetup] begin
    using Random
    cands = [[1, 2], [1, 2, 3], [1, 2]]
    tables = [table([1, 2], (1, 2), (1, 3)), table([1, 3], (2, 1))]
    targets = small_targets(cands)
    a = classify(Feasibility(cands, tables), targets)
    b = classify(Feasibility(cands, tables), targets)
    @test map(fields, a) == map(fields, b)

    # A witness depends only on the question, never on which questions came
    # first (cache state) or on the order of the targets. The cost does: a
    # cached answer costs nothing, so it is left out of the comparison.
    shuffled = shuffle(Xoshiro(20260926), targets)
    c = classify(Feasibility(cands, tables), shuffled)
    for (t, r) in zip(shuffled, c)
        k = findfirst(==(t), targets)
        @test verdict(r) == verdict(a[k])
    end

    # The same random problem built twice gives identical answers.
    function build(seed)
        rng = Xoshiro(seed)
        n = 6
        cands = [collect(1:3) for _ in 1:n]
        tables = [table(randperm(rng, n)[1:3], ((rand(rng, 1:3), rand(rng, 1:3), rand(rng, 1:3)) for _ in 1:8)...)
                  for _ in 1:4]
        return Feasibility(cands, tables), small_targets(cands)
    end
    f1, t1 = build(7)
    f2, t2 = build(7)
    @test map(fields, classify(f1, t1)) == map(fields, classify(f2, t2))
end


@testitem "feasibility: random problems against brute force, §1.2 §1.4 §3.1 §3.16" setup=[FeasibilitySetup, UTSetup] begin
    using Random
    rng = Xoshiro(0x2026_0926_fea5 ⊻ seed_mod())
    tally = Dict(:required => 0, :forbidden => 0, :implied => 0, :unknown => 0,
                 :negative => 0, :lazy => 0, :whole => 0, :empty => 0)
    for problem in 1:200
        n = rand(rng, 3:6)
        arity = rand(rng, 2:3, n)
        cands = [collect(1:a) for a in arity]
        tables = RuleTable[]
        for _ in 1:rand(rng, 1:4)
            whole = rand(rng) < 0.1
            scope = whole ? collect(1:n) : randperm(rng, n)[1:rand(rng, 1:min(3, n))]
            share = whole ? rand(rng, (0.3, 0.6, 0.9)) : rand(rng, (0.2, 0.4, 0.6))
            tuples = Iterators.product((1:arity[p] for p in scope)...)
            forbidden = Set{NTuple{length(scope), Int}}(t for t in tuples if rand(rng) < share)
            if whole || rand(rng) < 0.3
                tally[whole ? :whole : :lazy] += 1
                lazy = function (key)
                    all(>(0), key) || error("rule called with an unset parameter")  # §1.6
                    return Tuple(key) in forbidden
                end
                push!(tables, RuleTable(scope, lazy))
            else
                push!(tables, RuleTable(scope, forbidden))
            end
        end
        if rand(rng) < 0.2
            # A negative row at p (§5.5): its one invalid index, and only the
            # tables whose scope omits p.
            p = rand(rng, 1:n)
            cands[p] = [arity[p] + 1]
            tables = filter(t -> !(p in t.scope), tables)
            tally[:negative] += 1
        end

        rows = [collect(r) for r in Iterators.product(cands...) if valid(tables, collect(r))]
        isempty(rows) && (tally[:empty] += 1)

        f = Feasibility(cands, tables)
        small = Feasibility(cands, tables; limit = rand(rng, 1:4))
        @test first(completable(f, zeros(Int, n))) == (isempty(rows) ? :infeasible : :feasible)
        targets = small_targets(cands)
        results = classify(f, targets)
        for (target, result) in zip(targets, results)
            truth = any(r -> extends(r, target), rows)
            direct = [k for (k, t) in enumerate(tables) if assigned(t, target) && forbids(t, target)]
            status, w = completable(f, target)
            @test status == (truth ? :feasible : :infeasible)
            @test dead(f, target) == !truth
            if truth
                @test result.status == :required
                @test good_witness(tables, cands, target, result.witness)
                @test w == result.witness
            elseif !isempty(direct)
                @test result.status == :forbidden
                @test result.rules == direct
            else
                @test result.status == :implied
                @test result.minimal == :verified
                # Sufficient: those rules alone exclude the target.
                @test !brute_feasible(tables[result.rules], cands, target)
                # Verified minimal: without any one of them it is feasible.
                for r in result.rules
                    @test brute_feasible(tables[filter(!=(r), result.rules)], cands, target)
                end
            end
            tally[result.status] += 1

            # A small limit may be unknown, but a resolved answer is right,
            # and nothing unknown is remembered (§3.2, §3.5).
            s, sw = completable(small, target)
            tally[:unknown] += s == :unknown
            if s == :unknown
                @test !haskey(small.memo, target)
                @test first(completable(small, target; limit = 10^6)) == (truth ? :feasible : :infeasible)
            else
                @test s == (truth ? :feasible : :infeasible)
                truth && @test sw == w
            end
        end
    end
    # The problems exercised every branch.
    @test all(>(0), values(tally))
end


@testitem "feasibility: rule checks are counted, not budgeted, §3.3" setup=[FeasibilitySetup] begin
    # Astra by hand; a check is one `forbids` call.
    astra = () -> Feasibility([[1, 2], [1, 2], [1, 2]],
        [table([1, 2], (1, 2), (2, 1)), table([2, 3], (1, 2), (2, 1))])
    # From nothing: no table is assigned, so the direct check and the initial
    # prune check nothing. Node 1, A = 1, prunes B through rule 1 (2 checks);
    # node 2, B = 1, completes rule 1 (no check) and prunes C through rule 2
    # (2 checks); node 3, C = 1, completes rule 2 (no check).
    f = astra()
    @test first(completable(f, [0, 0, 0])) == :feasible
    @test (f.stats.last_nodes, f.stats.evaluations) == (3, 4)
    # A memo hit costs neither.
    @test first(completable(f, [0, 0, 0])) == :feasible
    @test (f.stats.last_nodes, f.stats.total_nodes, f.stats.evaluations) == (0, 3, 4)
    # `violates` checks each fully assigned table once.
    f = astra()
    @test violates(f, [1, 2, 0])
    @test f.stats.evaluations == 1
    @test !violates(f, [1, 1, 1])
    @test f.stats.evaluations == 3

    # The explanation carries its own cost.
    e = explain_partial(astra(), [0, 0, 0])
    @test (e.outcome, e.nodes, e.evaluations) == (:completable, 3, 4)
    e = explain_partial(astra(), [1, 2, 0])  # the direct check, one table
    @test (e.outcome, e.nodes, e.evaluations) == (:forbidden, 0, 1)
    e = explain_partial(astra(), [1, 1, 1])  # both tables, both allow it
    @test (e.outcome, e.nodes, e.evaluations) == (:allowed, 0, 2)
    # (A = 1, C = 2): the initial prune checks B through rule 1 (2 checks, B = 2
    # removed) and rule 2 (1 check, B = 1 removed): infeasible with 0 nodes.
    # Each deletion trial keeps one rule, prunes B (2 checks) and assigns it
    # (1 node): 2 nodes and 4 checks in all.
    f = astra()
    e = explain_partial(f, [1, 0, 2])
    @test (e.outcome, e.rules, e.minimal) == (:infeasible, [1, 2], :verified)
    @test (e.nodes, e.evaluations) == (2, 7)
    @test (f.stats.total_nodes, f.stats.evaluations) == (0, 3)  # the trials have their own
    c = only(classify(astra(), [[1, 0, 2]]))
    @test (c.status, c.nodes, c.evaluations) == (:implied, 2, 7)

    # The budget counts nodes only: a unary lazy rule over 2,000 values is
    # checked 2,000 times by the initial prune, before the first node, so one
    # node suffices at limit 1 (§3.3).
    calls = Ref(0)
    last_only = key -> (calls[] += 1; key[1] < 2000)
    f = Feasibility([collect(1:2000)], [RuleTable([1], last_only)]; limit = 1)
    @test completable(f, [0]) == (:feasible, [2000])
    @test (f.stats.last_nodes, f.stats.evaluations, calls[]) == (1, 2000, 2000)
    # With a two-parameter scope the checks follow a node: a = 1 is node 1 and
    # prunes x (2,000 checks); x is node 2, beyond limit 1. Each node's checks
    # are at most the candidates of the parameters it prunes.
    pair = RuleTable([1, 2], key -> key[2] < 2000)
    f = Feasibility([[1, 2], collect(1:2000)], [pair]; limit = 1)
    @test completable(f, [0, 0]) == (:unknown, nothing)
    @test (f.stats.last_nodes, f.stats.evaluations) == (1, 2000)
    @test completable(f, [0, 0]; limit = 2) == (:feasible, [1, 2000])
    @test (f.stats.last_nodes, f.stats.evaluations) == (2, 4000)
end


@testitem "feasibility: ResourceLimitError names the limit and the retry, §3.7 §3.8" setup=[FeasibilitySetup] begin
    err = ResourceLimitError("the feasibility search for the partial assignment [1, 0]",
        1_000_000, :feasibility_limit)
    @test err isa Exception
    msg = sprint(showerror, err)
    @test occursin("the feasibility search for the partial assignment [1, 0]", msg)
    @test occursin("feasibility_limit = 1_000_000", msg)
    @test occursin("feasibility_limit = 10_000_000", msg)
    @test occursin("larger limit", msg)
    @test occursin("explanation_limit = 50", sprint(showerror, ResourceLimitError("x", 5, :explanation_limit)))
end


@testitem "feasibility: input validation, §0.1 §3.3" setup=[FeasibilitySetup] begin
    t = table([1, 2], (1, 1))
    @test_throws ArgumentError Feasibility([[1, 2], Int[]], [t])
    @test_throws ArgumentError Feasibility([[1, 2], [1, 1]], [t])
    @test_throws ArgumentError Feasibility([[1, 2], [0, 1]], [t])
    @test_throws ArgumentError Feasibility([[1, 2]], [t])  # scope outside the parameters
    @test_throws ArgumentError Feasibility([[1, 2], [1, 2]], [t]; limit = 0)
    f = Feasibility([1:2, 1:2], [t])
    @test f.candidates == [[1, 2], [1, 2]]
    @test_throws ArgumentError completable(f, [1, 0, 0])
    @test_throws ArgumentError completable(f, [3, 0])
    @test_throws ArgumentError completable(f, [1, 0]; limit = 0)
    @test_throws ArgumentError violates(f, [1])
    @test_throws ArgumentError explain_partial(f, [1, 0]; explanation_limit = 0)
    # No tables: everything is feasible, and every parameter is free.
    g = Feasibility([[2, 1], [1]], RuleTable[])
    @test components(g) == [[1], [2]]
    @test completable(g, [0, 0]) == (:feasible, [2, 1])
    @test g.stats.last_nodes == 0
end


@testitem "feasibility: the lazy-rule memo is the operation's, shared by its trials (§3.5, §12.19)" setup=[FeasibilitySetup] begin
    using UnitTestDesign: memo_size, rule_memos, RuleMemo
    # A lazy three-parameter rule and a tabulated one, as in Fable's solver:
    # (y = 2, z = 1) is implied, so its explanation runs deletion trials.
    calls = Ref(0)
    lazy = RuleTable([1, 2, 3], function (key)
        calls[] += 1
        key[1] == 1 && key[2] != 1          # require x == 2 || y == 1
    end)
    tables = [lazy, table([1, 3], (2, 1))]
    cands = [[1, 2], [1, 2, 3], [1, 2]]
    f = Feasibility(cands, tables)
    @test f.rule_memo[1] isa RuleMemo && length(f.rule_memo[1].key) == 3 && f.rule_memo[2] === nothing
    @test memo_size(f) == 0
    e = explain_partial(f, [0, 2, 1])
    @test (e.outcome, e.rules, e.minimal) == (:infeasible, [1, 2], :verified)
    # The trials share f's memo: each tuple is evaluated at most once.
    @test calls[] == memo_size(f) <= 12
    before = calls[]
    explain_partial(f, [0, 3, 1])
    classify(f, [[0, 2, 1], [0, 3, 1], [1, 0, 0]])
    @test calls[] == memo_size(f) <= 12
    # Memos may be handed to another Feasibility of the same operation ...
    g = Feasibility(cands, tables[[1]]; memos = f.rule_memo[[1]])
    @test g.rule_memo[1] === f.rule_memo[1]
    n = calls[]
    forbids(g, 1, [1, 2, 1])
    @test calls[] == n
    # ... but they must fit the tables.
    @test_throws ArgumentError Feasibility(cands, tables; memos = [nothing, nothing])
    @test_throws ArgumentError Feasibility(cands, tables; memos = rule_memos(tables[[1]]))
    @test_throws ArgumentError Feasibility(cands, tables; memos = [RuleMemo(2), nothing])
    # A fresh object starts empty, and the table itself keeps nothing.
    @test memo_size(Feasibility(cands, tables)) == 0
    @test !hasfield(UnitTestDesign._LazyRule{3}, :memo)
    # An evaluation that throws stores nothing.
    bad = RuleTable([1], key -> key[1] == 2 ? error("no") : false)
    h = Feasibility([[1, 2]], [bad])
    @test_throws ErrorException forbids(h, 1, [2])
    @test memo_size(h) == 0
    @test !forbids(h, 1, [1]) && memo_size(h) == 1
end
