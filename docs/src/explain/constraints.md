# Constraints

Not every combination of values is a valid input. A GPU needs a driver, an
exact solver ignores a loose tolerance, and a sparse kernel may not exist on
some device. You describe these facts as *rules* in a [`TestSpace`](@ref),
and the package works out their consequences. This page says what a rule
means, how the package reports what the rules leave out, what it does when
a question is too hard to answer within its budget, and what each way of
writing a rule costs. The clauses cited, such as §1.2, are those of the
[Contract](../dev/contract.md).

## Valid cases and feasible combinations

Three definitions carry everything else.

- A case is **valid** when it satisfies every rule (§1.1).
- A combination, such as the pair `(os = :windows, gpu = true)`, is
  **feasible** when at least one valid case contains it (§1.2).
- A combination is **required** exactly when it is feasible. Every case a
  design returns is valid, and every required combination appears in at
  least one of them; no other combination is asked for (§1.3).

The third point means you never write a rule that follows from other rules.
Here a GPU needs the CUDA driver, and Windows has no CUDA. Neither rule
mentions Windows together with a GPU, yet no valid case can hold both.

```@example rules
using UnitTestDesign
space = TestSpace(
    (os = [:linux, :mac, :windows], gpu = [false, true], driver = [:cuda, :none]);
    constraints = [
        @forbid(gpu && driver == :none),
        forbid((os = :windows, driver = :cuda); reason = "no CUDA on Windows"),
    ])
cases = all_pairs(space)
```

```@example rules
report(cases)
```

The design covers the thirteen feasible pairs and does not try to cover the
pair that the two rules exclude together. In the 0.4 releases this example
crashed IPOG and left GND running forever.

## Direct and implied exclusions

Every combination that is not required is reported with the reason (§1.4).

- **Directly forbidden**: a rule that reads only the combination's
  parameters forbids it, and every such rule is named.
  `(os = :windows, driver = :cuda)` is forbidden by the second rule.
- **Implied**: no single rule forbids it on its face, but no valid case
  contains it. `(os = :windows, gpu = true)` is implied by the two rules
  together.
- **Unknown**: a search budget ran out before the answer was known (see
  below).

For an implied exclusion the package finds which rules are responsible with
a *deletion search* (§3.14). It starts from all the rules, which together
are proven to exclude the combination, and tries removing them one at a
time, in the order you wrote them. A rule is dropped only when the
combination is proven to stay infeasible without it. What remains is a set
of rules that is *sufficient*: those rules alone exclude the combination.
The set is called *minimal* only when removing each of its rules was
verified to make the combination feasible, with a witness case to show it
(§3.16). The package never names a rule that does not take part in a proven
exclusion (§1.5).

[`explain`](@ref) asks the same questions about any assignment, complete or
partial. It answers `allowed`, `forbidden`, `completable` (with a valid case
that contains it), `infeasible` (with the rules and whether the set was
verified minimal), or `unknown`:

```@example rules
explain(space, (os = :windows, gpu = true))
```

```@example rules
explain(space, (os = :windows, gpu = false))
```

The list of implied exclusions is a check on your own rules. Rules that each
read sensibly can combine into consequences you did not intend, and the
report is where you find out that some combination you meant to test can
never run.

## Three answers and two budgets

Deciding whether a combination is feasible is a search, and a search can be
expensive. Every feasibility question therefore has one of three answers
(§3.1): *feasible*, with a valid case as the witness; *infeasible*, proven
by a search that tried everything; or *unknown*, because the search reached
its budget. An unknown answer is never treated as either of the others
(§3.2).

The budget is the keyword `feasibility_limit`, which counts search nodes (one
tentative value for one parameter) per question and defaults to one million
(§3.3). What happens at the limit depends on the operation.

- **Generation must answer every question.** If any answer is unknown, the
  call throws a [`ResourceLimitError`](@ref) naming the limit and suggesting
  a larger one. It never returns a design with a combination left
  unresolved or silently dropped (§3.6, §3.7). Raising the limit never
  changes an answer already known; it only resolves unknown ones (§3.8).
- **Measurement and explanation may say unknown.** [`coverage`](@ref) and
  [`report`](@ref) then give bounds and list the unresolved combinations,
  and never print an exact percentage or claim completeness (§3.10).
  [`explain`](@ref) answers `unknown`.

A second keyword, `explanation_limit`, bounds the deletion search that
attributes an implied exclusion (§3.13). Running out of it never undoes a
proof: the combination stays infeasible, the explanation keeps the last set
of rules proven sufficient, and its minimality is marked unresolved (§3.15).

The rule below reads all five parameters at once, so its questions are
harder than those of the solver example. With a budget of three nodes the
answer is unknown, and generation refuses to guess:

```@example budget
using UnitTestDesign
space = TestSpace((a = 1:4, b = 1:4, c = 1:4, d = 1:4, e = 1:4);
    constraints = [require(case -> sum(case) <= 8; reason = "the budget")])
explain(space, (a = 4, b = 4); feasibility_limit = 3)
```

```@example budget
try
    all_pairs(space; feasibility_limit = 3)
catch err
    showerror(stdout, err)
end
```

With the default budget the same question is settled. One rule excludes the
pair, though its scope reaches beyond the two parameters the pair assigns,
so the exclusion is implied rather than direct:

```@example budget
explain(space, (a = 4, b = 4))
```

And a starved explanation budget leaves the rules sufficient but their
minimality unresolved:

```@example rules
explain(space, (os = :windows, gpu = true); explanation_limit = 1)
```

## Five ways to write a rule

Every rule becomes one internal form: a scope (the parameter names it
reads), a predicate, a polarity (forbid or require), and a label (§12.1).
Nothing after construction knows which surface form you used. The forms are:

- **The macros**, `@forbid mode == :exact && tol == 1e-3` and
  `@require mode == :fast || tol == 1e-6`. The scope is the names the
  expression mentions, and the label is the source text.
- **A pattern**, `forbid((mode = :exact, tol = 1e-3))`, which forbids one
  exact combination. The scope is the pattern's names.
- **A function with listed names**,
  `forbid(:mode, :tol) do m, t; m == :exact && t == 1e-3 end`. The function
  receives the listed parameters' values in the order listed.
- **A whole-case function**,
  `forbid(case -> case.mode == :exact && case.tol == 1e-3)`, which receives
  the complete case as a `NamedTuple`. The scope is every parameter.

[`require`](@ref) has the listed-names and whole-case forms too. It allows
only what its predicate accepts, so you can state each rule the way you
would say it ("exact mode requires a tight tolerance", "no CUDA on
Windows"). There is no pattern form of `require`. Any form takes
`reason = "..."`, which labels the rule in reports.

Here is the same rule written all five ways. Each space excludes the same
rows and gets the same design:

```@example forms
using UnitTestDesign
domains = (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6])
rules = [
    @forbid(mode == :exact && tol == 1e-3),
    @require(mode == :fast || tol == 1e-6),
    forbid((mode = :exact, tol = 1e-3)),
    forbid(:mode, :tol) do mode, tol
        mode == :exact && tol == 1e-3
    end,
    forbid(case -> case.mode == :exact && case.tol == 1e-3),
]
for rule in rules
    println(rpad(repr(rule.scope), 16), rule)
end
```

```@example forms
spaces = [TestSpace(domains; constraints = [rule]) for rule in rules]
(same_valid_rows = allequal(collect(full_factorial(s)) for s in spaces),
 same_design = allequal(collect(all_pairs(s)) for s in spaces))
```

One difference among the forms is how they compare values. A pattern
matches by identity, the same type and `isequal` value, so the pattern
value `1` does not match a domain value `1.0` (§12.4). Predicates compare
however you write them, so `n == 1` is true for both (§12.23).

## What the macros treat as a name

[`@forbid`](@ref) and [`@require`](@ref) read bare identifiers as parameter
names (§12.6):

- Every identifier that is not being called names a parameter, and the
  rule's scope lists them in order of first appearance.
- A called name is a function: `isodd(n)`, `n < 3`, `Base.isodd(n)`.
- Literals, `true`, `false`, `nothing`, and `missing` are values.
- Names bound inside the expression, by `->`, `let`, or a comprehension,
  are local.
- `$x` inserts the value of your variable `x` when the rule is built. That
  applies to any global that is not called, so a comparison with infinity is
  written `tol < $Inf`.

A name the space lacks is an error when the space is built, and the message
suggests `$` if you meant a variable (§12.8):

```@example forms
threshold = 1e-4
@forbid(mode == :exact && tol > $threshold)
```

```@example forms
try
    TestSpace(domains; constraints = [@forbid(mode == :exact && tol < Inf)])
catch err
    showerror(stdout, err)
end
```

The macros reject any other form that binds or assigns a name or runs
statements: an assignment outside a `let` binding, `for`, `while`, `try`,
`global`, `local`, a quoted expression, or a macro call. They also reject a
subtype test written with `<:` or `>:`, which are syntax, not calls; the
call form, `(<:)(T, $AbstractFloat)`, is read like any other call. Each is
an `ArgumentError` when the macro expands, and the message points to the
function form. For a rule the macros cannot express, write
[`forbid(f, names...)`](@ref forbid) or `require(f, names...)`, whose
function is ordinary Julia code that receives the listed parameters' values
(§12.6).

## What rules cost

A scoped rule, written in any form but the whole-case one, is *tabulated*
when the space is built: its predicate runs exactly once for each
combination of its scope's values, and the forbidden combinations are
stored (§12.18). A rule over `(mode, solver)`
runs six times, whatever the searches do later. The number of calls is
known in advance, a predicate that throws fails when the space is built
rather than deep inside generation, and the searches only look up tables.
A rule whose scope has more than `tabulation_limit` combinations (a
`TestSpace` keyword, default ``10^5``) is evaluated lazily instead, and the
package warns and suggests a narrower scope (§12.19). A lazy rule,
including every whole-case rule (below), runs its predicate only when a
search or a row check reaches it, so a predicate that throws fails in
whichever call reached it: a generation, `isallowed`, `explain`,
`coverage`, `report` or `followups` (§12.16).

A whole-case rule is always lazy (§12.20). Its predicate runs on complete
cases as the searches reach them, and each answer is remembered until that
one call returns: a generation, an `explain`, a `coverage` or a `followups`
call. `report` and `design_sizes` run several of these, each with its own
memo. The space keeps nothing (§12.19). The cost is in the searches: a
whole-case rule reads every parameter, so it joins them all into one
search, and deciding whether a combination is feasible may
explore up to the product of the unassigned domains, bounded by
`feasibility_limit` (§12.21). In the package's benchmark, adding one
whole-case rule that forbids nothing roughly doubled the time of a
strength-4 design over fifteen four-valued parameters (from about 5 s to
about 9 s on a laptop, first calls). Use a whole-case rule when a rule
really is global, such as a memory budget over every parameter, and list the
names otherwise.

Every predicate must return a `Bool`, and should be deterministic and free
of side effects, since it may run more than once (§12.15, §12.17). An
exception from a predicate is rethrown as a `ConstraintError` naming the
rule and the values it received. It never means "forbidden" or "allowed"
(§12.16).

## Rules and invalid values

A space can hold [`Invalid`](@ref) values, inputs the code should reject,
for negative testing (see [Test invalid inputs](../howto/invalid_inputs.md)).
A case with one invalid value, at parameter `p`, is a *negative* case. It
must satisfy every rule whose scope leaves out `p`, and the rules whose
scope includes `p` are skipped for it (§5.5). A rule describes how valid
values combine; it was not written for a value outside the domain, and
predicates never receive an `Invalid` (§5.8). Whole-case rules read every
parameter, so they never apply to negative cases (§5.6). A case with two
invalid values is never valid (§5.7).

```@example negative
using UnitTestDesign
space = TestSpace(
    (rows = [1, 100, Invalid(-1)], layout = [:dense, :sparse], device = [:cpu, :gpu]);
    constraints = [
        @forbid(rows == 1 && layout == :sparse),
        forbid((layout = :sparse, device = :gpu); reason = "no sparse kernels on the GPU"),
    ])
# The first rule reads `rows`, so it is skipped for a case with an invalid `rows`.
isallowed(space, (rows = Invalid(-1), layout = :sparse, device = :cpu))
```

```@example negative
# The second rule does not read `rows`, so it still applies.
explain(space, (rows = Invalid(-1), layout = :sparse, device = :gpu))
```

## Why it changed

In 0.4, a rule was a single function passed as `disallow`. The engines
called it on partial cases, with `nothing` standing for every parameter not
yet chosen, and asked only whether the partial case was forbidden *yet*.
Three problems followed.

- A rule written the natural way could forbid too much, silently. With
  `disallow = (m, s, t) -> m == :fast && s != :none`, a partial case with
  `mode = :fast` and no solver yet looked forbidden, because
  `nothing != :none`. The feasible pair `(mode = :fast, tol = 1e-6)` never
  appeared in the design, with no error and no warning.
- `nothing` could not be a real value, and a rule that compared with `<`
  threw a `MethodError` on the sentinel.
- The engines never asked whether a partial case could still be completed,
  so an implied exclusion like the Windows and GPU pair above crashed IPOG
  and left GND running forever.

Now a rule sees values only when its whole scope is assigned, and never a
partial case (§1.6, §12.14); `nothing` is an ordinary value (§2.9); and
every placement is checked for a valid completion. The
[Migration](../reference/migration.md) page shows how to rewrite a
`disallow` function as rules.
