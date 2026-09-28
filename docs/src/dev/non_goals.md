# Non-goals

UnitTestDesign chooses which configurations to test and measures which
combinations a set of cases covers. It stays small on purpose. The items
below are outside the 0.5 release ([Contract](contract.md) §14.1), and a
proposal for any of them needs a new design review. Each entry says why it
is out, what the package offers instead, and, where the design review said
so, what would change the decision.

## Running tests

**A test runner.** Test.jl, TestItemRunner, and cluster schedulers already
run tests well, and a runner would turn this package into a test framework.
Instead, cases are plain rows that you loop over in whatever framework you
use, and outcomes come back only through the pure function
`diagnose(cases, passed)` ([Diagnose a failure](../howto/diagnose.md)). The
design review expects this to stay out, possibly for good.

**Outcome files.** Recording which cases ran and passed is a runner's job.
Keep outcomes however suits you, in a Test.jl loop, a cluster job, or a
spreadsheet, and hand them to [`diagnose`](@ref); to measure coverage by the
cases that ran or passed, give [`coverage`](@ref) those rows (§1.17). This
would be reconsidered only if another feature, such as rolling coverage,
needed recorded outcomes anyway.

**Rolling coverage across CI runs.** The idea is to run a differently seeded
design on each CI run, so that higher-strength coverage accumulates across
runs. It needs a record of which cases ran on earlier runs, which is outcome
recording by another name. You can do it by hand: seed [`GND`](@ref) from
the run number, keep the rows each run used, and measure them together with
`coverage(rows, space; strength = 3)`. It comes back into scope if outcome
recording exists for some other reason.

**Shrinking.** Reducing a failing input to a simpler one is what
property-based testing tools such as Supposition.jl do well, and a design's
cases are already few and labeled. Instead, `diagnose` ranks the
combinations a failure points to, and `followups` proposes cases that
separate them. For exploring and shrinking within a class of values, use a
[`Partition`](@ref) with a property-based tool; see [Combine with
property-based testing](../howto/property_based.md). A joint design, where
the covering design picks the classes and a property-based tool shrinks
within one, would be a separate project.

## Describing the space

**Model inference.** The package does not build a space from method
signatures, types, or enum definitions. The user writes the space, because
the values are the model: choosing a representative for each class of
inputs takes judgement about the code under test ([Choosing values and
oracles](../explain/values_and_oracles.md)), and an inferred model would hide
the choice that most decides what a design is worth. Writing a domain is
short, as in `mode = instances(Mode)` for an enum.

**A fixture catalog.** There is no library of ready-made domains, such as
edge-case floats, numeric types, or awkward strings. Good values depend on
the code under test, and a large catalog would be costly to maintain and
would invite choosing values without thinking about them. Domains are
ordinary Julia vectors, so a project can keep its own in a shared module.

**A solver (Z3, SAT).** Feasibility is decided by a backtracking search over
tabulated rules, bounded by `feasibility_limit`, and that search is quick
for the spaces people bring. A solver would add a large binary dependency to
answer questions the search already answers. Rules are kept as data (a
scope, a predicate, a polarity, and a label), so a solver could be added
later as a package extension. That becomes worth doing only if real spaces
appear that backtracking cannot handle: many parameters with many
interacting rules, or spaces dominated by whole-case rules.

## Getting cases in and out

**A command-line interface.** A command-line tool needs a file format for
spaces, including their rules, and rules are Julia functions. A short Julia
script does the same job, and [`github_matrix`](@ref) writes the JSON a CI
workflow reads ([Plan a CI matrix](../howto/ci_matrix.md)). A command-line
tool could return as a recipe once rules can be written as strings; the
macros already keep their source text, and patterns are plain data.

**TOML specifications.** The reason is the same as for the command line:
until rules serialize, a TOML file cannot describe a space with rules. A
space written in Julia source is the specification, and it can be reviewed
like any other code.

**A serialization framework.** Every format needs a reader, a writer, and a
compatibility policy, and formats multiply. Instead, a named space's
results are vectors of `NamedTuple` rows, which Tables.jl and DataFrames
accept as they are;
`repr(collect(cases))` prints a Julia literal; and `github_matrix` is the
one exporter (§14.1).

**`as_code`.** A printer of cases as Julia source is unnecessary, because
`repr(collect(cases))` already prints a literal that Julia reads back.
[Commit a design as data](../howto/commit_design.md) shows the pattern: save
the literal, and add one test that checks its coverage.

## Choosing how many cases

**`max_cases`.** A cap on the number of cases would return a design that no
longer carries its guarantee. Instead, the prefix curve of [`report`](@ref)
says how much the first ``k`` cases cover, so a job with a fixed budget can
run a prefix knowing what it gives up, and [`design_sizes`](@ref) compares
strategies before you commit to one. A budget option would be worth
revisiting if measurements showed an engine that front-loads coverage
reliably. GND, which builds each case to cover as much as possible, is the
candidate, and that is a hypothesis to test, not a result.

## Evidence

**The evidence track.** The package does not yet have its own study of
whether designed suites find more faults than random or exhaustive suites
of the same size on real Julia code, measured with mutation analysis. That
case study is deferred until after 0.5, not rejected: it is research, and
this release is about correctness. [Interaction coverage and the
evidence](../explain/coverage_evidence.md) says what the published studies
show and what they do not, and [`report`](@ref) and [`coverage`](@ref)
measure your own suite.

## Other open questions

The design review also named problems that no proposal addressed. They are
not planned, and they are recorded here so that nobody mistakes their
absence for an oversight.

- **Weights and operational profiles.** A design treats every feasible
  combination alike; it does not favor the configurations users run most.
- **Sequences.** Parameters could stand for successive calls to an API, and
  sequence covering arrays exist for that, but the package covers
  combinations only.
- **Validating the model.** Measuring code coverage per case would show
  redundant values and missing classes, but it is hard to do in Julia today.
- **Stability by design.** Only `must_include` keeps a design stable across
  edits (§9.10). An engine that deliberately changes as little as possible
  from a previous design is an open problem.

Behavior not stated in the contract is not promised (§14.2).
