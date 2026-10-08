# Probe for review section 4: does followups() report a union of per-kind proofs
# as `minimal = :verified` when a sub-union already suffices for every kind?
using UnitTestDesign
const U = UnitTestDesign

same(a, b) = typeof(a) === typeof(b) && isequal(a, b)
holds(row, c) = all(k -> haskey(row, k) && same(row[k], c[k]), keys(c))
all_rows(sp) = (names = Tuple(parameters(sp));
                [NamedTuple{names}(v) for v in Iterators.product(sp.values...)])

"Valid rows (under `constraints` only) holding `s` and none of `others`; independent brute force via isallowed."
function isolating_rows(domains, constraints, s, others)
    sp = TestSpace(domains; constraints)
    [r for r in all_rows(sp) if isallowed(sp, r) && holds(r, s) && !any(o -> holds(r, o), others)]
end

"The per-kind proofs that _followup unions (internal _isolate, called exactly as _followup calls it)."
function per_kind(d, j)
    space = d.space
    memos = U.rule_memos(space.tables)
    isolation = U.RuleTable[U._isolation_table(s.key) for s in d.suspects]
    s = d.suspects[j]
    others = [i for i in eachindex(d.suspects) if i != j]
    starts = unique(k -> d.rows[k], s.failing)[1:min(end, 5)]
    for (p, v) in U._row_kinds(space, s.key)
        r = U._isolate(d, s, (p, v), others, isolation, memos, (1_000_000, 1_000_000), starts)
        kind = U._kind_named(space, p, v)
        println("    kind ", isempty(kind) ? "ordinary" : repr(kind), ": active rules ",
                U.active_rules(space, p), " -> status=", r.status, " rules=", r.rules,
                " others=", [d.suspects[i].combination for i in r.others], " minimal=", r.minimal)
    end
end

function report(title, domains, constraints, rows, passed; strength = 1)
    println("\n==== ", title, " ====")
    space = TestSpace(domains; constraints)
    d = diagnose(rows, passed; space, strength)
    println("suspects: ", [s.combination for s in d.suspects])
    fs = followups(d)
    for f in fs
        println("  show: ", sprint(show, f))
        println("    status=", f.status, " rules=", f.rules, " others=", f.others,
                " minimal=", f.minimal, " limit=", f.limit, " searched=", f.searched)
    end
    return d, fs
end

"Global deletion check: for each part x of the combined proof, is there an isolating row of ANY kind without x?"
function global_deletion(domains, constraints, f)
    println("  global deletion check on the combined proof (rules=", f.rules, ", others=", f.others, "):")
    parts = [[(:rule, k) for k in f.rules]; [(:other, o) for o in f.others]]
    for x in parts
        rules = [constraints[k] for k in f.rules if (:rule, k) != x]
        others = [o for o in f.others if (:other, o) != x]
        iso = isolating_rows(domains, rules, f.suspect, others)
        verdict = isempty(iso) ? "NOT needed (still no isolating row of any kind)" : "needed; witness $(first(iso))"
        println("    drop ", x, ": ", verdict)
    end
end

## Example A: literal form of the review's claim. Rule 1 (a, b) alone keeps a = 2
## out of every valid row, ordinary or negative. Rule 2 reads n, so it does not
## apply to negative rows at n (§5.5), but it also keeps a = 2 out of ordinary rows.
domA = (a = [1, 2], b = [1, 2], n = [1, Invalid(0)])
consA = [forbid(:a, :b; reason = "a = 2 never, whatever b") do a, b; a == 2 end,
         forbid(:a, :n; reason = "a = 2 never with an ordinary n") do a, n; a == 2 end]
rowsA = [(a = 1, b = 1, n = 1), (a = 1, b = 2, n = Invalid(0)), (a = 2, b = 1, n = 1)]
passA = [true, true, false]
dA, fsA = report("A: no valid case holds the suspect", domA, consA, rowsA, passA)
println("  per-kind proofs that _followup unions:"); per_kind(dA, 1)
global_deletion(domA, consA, fsA[1])
println("  followups on the same rows with ONLY rule 1 in the space:")
dA1 = diagnose(rowsA, passA; space = TestSpace(domA; constraints = consA[1:1]), strength = 1)
f = only(followups(dA1)); println("    ", sprint(show, f), "  | rules=", f.rules, " minimal=", f.minimal)
println("  brute force, rule 1 only: isolating rows of any kind = ", isolating_rows(domA, consA[1:1], (a = 2,), NamedTuple[]))
println("  brute force, rule 2 only: isolating rows of any kind = ", isolating_rows(domA, consA[2:2], (a = 2,), NamedTuple[]))

## Example B: a natural shape. The failing case is valid; the proof needs another
## suspect. Rule 2 is a whole-case rule (never applies to negative rows, §5.6)
## that overlaps rule 1 on ordinary rows.
domB = (a = [1, 2], b = [1, 2], n = [1, Invalid(0)])
consB = [forbid((a = 2, b = 2); reason = "a = 2 needs b = 1"),
         forbid(; reason = "whole-case: no a = 2 with b = 2") do c; c.a == 2 && c.b == 2 end]
rowsB = [(a = 1, b = 2, n = 1), (a = 1, b = 2, n = Invalid(0)), (a = 2, b = 1, n = 1)]
passB = [true, true, false]
dB, fsB = report("B: valid failing case, proof with another suspect", domB, consB, rowsB, passB)
println("  per-kind proofs that _followup unions:"); per_kind(dB, 1)
global_deletion(domB, consB, fsB[1])
println("  followups on the same rows with ONLY rule 1 in the space:")
dB1 = diagnose(rowsB, passB; space = TestSpace(domB; constraints = consB[1:1]), strength = 1)
f = first(followups(dB1)); println("    ", sprint(show, f), "  | rules=", f.rules, " minimal=", f.minimal)
println("  brute force, rule 1 + other suspect only: isolating rows = ",
        isolating_rows(domB, consB[1:1], (a = 2,), [(b = 1,)]))

## Order dependence: swap the two rules of B; the union collapses to one rule.
consBr = [consB[2], consB[1]]
dBr, fsBr = report("B reversed: same rules, whole-case rule first", domB, consBr, rowsB, passB)
println("  per-kind proofs:"); per_kind(dBr, 1)

## Combination rule with a directly forbidden kind (test_diagnose.jl:394-402 setup).
domC = (n = [1, Invalid(0)], b = [1, 2])
consC = [forbid((n = 1, b = 2))]
rowsC = [(n = 1, b = 1), (n = Invalid(0), b = 1), (n = Invalid(0), b = 2)]
dC, fsC = report("C: test_diagnose.jl:394 setup at strength 2", domC, consC, rowsC, [true, true, false]; strength = 2)
println("  per-kind proofs:"); per_kind(dC, 1)

## Example D: the same union effect on `others`. One rule; at strength 2 the other
## suspect (a = 2, n = 1) blocks every ORDINARY row alone (n has one ordinary value),
## while negative rows need rule 1 and (a = 2, b = 1). The union keeps both suspects.
domD = (a = [1, 2], b = [1, 2], n = [1, Invalid(0)])
consD = [forbid((a = 2, b = 2); reason = "a = 2 needs b = 1")]
rowsD = [(a = 1, b = 2, n = 1), (a = 1, b = 2, n = Invalid(0)), (a = 2, b = 1, n = 1)]
dD, fsD = report("D: union of others", domD, consD, rowsD, [true, true, false]; strength = 2)
println("  per-kind proofs:"); per_kind(dD, 1)
global_deletion(domD, consD, fsD[1])
