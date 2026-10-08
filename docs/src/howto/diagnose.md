# Diagnose a failure

Some cases of a covering design failed, and you want to know which values,
or which combination of values, to suspect before reading any code. The
design and the outcomes already hold much of the answer: give both to
[`diagnose`](@ref), then run the cases [`followups`](@ref) proposes to tell
the suspects apart.

`diagnose` and `followups` are experimental; their interface may change in
a minor release.

## 1. Run the cases and collect the outcomes

Here a solver fails whenever `method = :newton` and `sparse = true`,
although nobody knows that yet:

```@example diagnose
using UnitTestDesign

solve(n, method, tol, sparse) =
    method == :newton && sparse ? error("Jacobian pattern not set") : true

space = TestSpace((n = [10, 100, 1000, 10000], method = [:newton, :bicg, :gmres],
                   tol = [1e-3, 1e-6], sparse = [false, true]))
cases = all_pairs(space)

runs(case) = try solve(case...) catch; false end   # a thrown error is a failure
passed = runs.(cases)
nothing # hide
```

`passed[k]` is the outcome of `cases[k]`. Collect it however you like: a
loop, a cluster job, a spreadsheet. `diagnose` runs nothing; it is a
function of the rows and the outcomes. Inside a `@testset`, record each
outcome as you test it, and diagnose before the test set ends, since a
failing test set throws when it closes:

```julia
passed = Bool[]
@testset "solver" begin
    for case in cases
        ok = runs(case)
        push!(passed, ok)
        @test ok
    end
    all(passed) || display(diagnose(cases, passed))
end
```

## 2. Diagnose

```@example diagnose
d = diagnose(cases, passed)
```

A suspect is a combination of values that appears in at least one failing
case and in no passing case. The list is ranked by how many failures hold
the suspect. The true cause ranks first, in all three failures. The other
pairs appear only in failing cases, so nothing yet says whether they work:
the failures mask them.

Each numbered line is a group. Suspects with the same failure pattern,
those that occur in exactly the same failing cases, share a group, and the
group's line lists the others as "same failures as" the first: these
outcomes cannot tell them apart, though new cases may. The last line here
is such a group, and so is the second example below.

## 3. Run the follow-ups

```@example diagnose
f = followups(d)
```

For each suspect, `followups` looks for a valid case that holds it and no
other suspect, so its outcome speaks to that suspect alone. It starts
from a failing case and changes few of its values, here one or two, a
heuristic with no minimum-distance guarantee. Run the cases it found, and
diagnose again with every row and outcome so far:

```@example diagnose
next = [x.case for x in f if x.status == :found]
diagnose([collect(cases); next], [passed; runs.(next)]; space)
```

One suspect remains, in all four failures. That is strong evidence, and it
is still a hypothesis: the next step is to read the code that handles a
sparse Newton step.

## Reading a follow-up's status

- `found`: `case` isolates the suspect. Run it.
- `indistinguishable`: the suspect contains another suspect, so every case
  that holds it holds the other too. No case can isolate it; run the
  smaller suspect's follow-up instead. This is stronger than a group's
  "same failures as" in the diagnosis, which is about the outcomes so far.
- `inseparable`: an exhausted search proved that, under the space's rules,
  every valid case holding the suspect holds another suspect too. The
  follow-up names the rules and the suspects in the proof.
- `unknown`: the search reached `feasibility_limit` before deciding. Retry
  with a larger limit.

A space with rules shows the middle two. Here only `solver = :qr` fails,
and a rule says `:qr` needs exact mode:

```@example diagnose
rules = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [
        @require(mode == :exact || solver == :none),
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
    ])
qr_cases = all_pairs(rules)
qr = diagnose(qr_cases, [c.solver != :qr for c in qr_cases])
```

The single value ranks first, since it is the simpler hypothesis, and its
two pairs share its group: they occur in the same failing case.

```@example diagnose
followups(qr)
```

Both pairs contain the single value, so no case can hold either without
it. The single value, in turn, cannot appear without `mode = :exact` under
rule 1, so no valid case separates it from that pair. These outcomes cannot
tell the three apart, and no follow-up can. Every valid case that runs
`:qr` runs it in exact mode, so that is the code to read.

## One proof per kind of case

A space with [`Invalid`](@ref) values has more than one kind of case:
ordinary cases, and negative cases that hold one invalid value, where the
rules that read its parameter do not apply. A suspect is `inseparable` only
when every kind that could hold it is proven, and each kind has its own
proof. Here both rules keep `a = 2` out of ordinary cases, but the second
reads `n`, so only the first applies to a negative case at `n`:

```@example diagnose
kinds = TestSpace((a = [1, 2], b = [1, 2], n = [1, Invalid(0)]);
    constraints = [
        forbid(:a, :b; reason = "a = 2 never, whatever b") do a, b; a == 2 end,
        forbid(:a, :n; reason = "a = 2 never with an ordinary n") do a, n; a == 2 end,
    ])
kind_cases = [(a = 1, b = 1, n = 1), (a = 1, b = 2, n = Invalid(0)), (a = 2, b = 1, n = 1)]
followup = only(followups(diagnose(kind_cases, [true, true, false]; space = kinds, strength = 1)))
```

No valid case holds `a = 2` at all; the failing case broke the rules. The
kinds' proofs differ, rule 2 in ordinary cases and rule 1 in negative ones,
so the line gives each. `proofs` holds them, one for each entry of
`searched`, with the kind of case, the rules and their labels, the other
suspects, `minimal` and `limit`:

```@example diagnose
followup.proofs
```

Each proof's `minimal` is judged within its kind. The union in `rules`,
`[1, 2]`, suffices for every kind but is not minimal: rule 1 alone would do
for both. The deletion search tries removing the rules in order, and in
ordinary cases rule 2 alone suffices, so it drops rule 1 there.

## The ranking is a set of hypotheses

- Several faults at once split the failures between their causes, and an
  innocent combination that shares failing cases with two faults can rank
  above both.
- An intermittent failure makes a passing case look innocent when it is
  not, so the true cause can be missing from the list.
- A fault that needs more values together than the strength of the
  diagnosis, by default the design's, leaves no suspect, or only
  combinations that happen to occur with it. Diagnose again with a larger
  `strength`.

## Pitfall: a thrown error and a wrong answer are both `false`

The outcome vector has one bit per case, so an exception and an inaccurate
result look the same to `diagnose`. If they may have different causes,
diagnose them separately: once with `passed` false only for the cases that
threw, and once with it false only for the wrong answers.
