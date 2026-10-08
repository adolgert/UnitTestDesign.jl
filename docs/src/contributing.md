# Contributing

## Examples of contributions

- Reporting a space on which generation is slow, fails, or gives a
  surprising design.
- Adding or improving an engine for building covering designs.
- Pointing to a package that already does something this one should reuse.
- Improving the documentation or the tests.
- Suggesting a better interface.

The GitHub site has an [Issues page](https://github.com/adolgert/UnitTestDesign.jl/issues).
A small, complete space that shows the problem is the most useful thing an
issue can hold.

## The contract is the specification

The [Contract](dev/contract.md) states what the package promises, in
numbered clauses that code, tests, and reviews cite ("contract §3.4"). If
the code and the contract disagree, the contract stands until a review
changes it (§0.3). Don't edit a test to match code that departs from the
contract; raise the conflict in review instead. A change that adds a promise
or changes one updates the contract in the same pull request. The
[Non-goals](dev/non_goals.md) page lists what is out of scope and why.

## Layout

| Directory | Contents |
|:--|:--|
| `src/` | The package. `space.jl`, `constraints.jl` and `feasibility.jl` hold the model and the search; `ipog_core.jl` (IPOG) and `greedy_tuples.jl` (GND) are the engines; `measure.jl` and `report.jl` measure coverage. `precompile.jl` is the precompile workload, which runs while the package precompiles so that a first session's calls are already compiled; a new engine or entry point belongs in it too. |
| `test/` | `@testitem`s run by TestItemRunner, the independent checker, and the fixtures. |
| `benchmark/` | The performance baseline, `run.jl`, with its own environment; `first_call.jl`, which times the front page's example in fresh processes; and `reference_sweep.jl`, which lists for reviews the definitions in `src/` that nothing public reaches. |
| `docs/` | This manual, built with Documenter. |
| `design/` | Design documents, phase reviews, and benchmark results. |

## Running the tests

From the repository root:

```
julia --project -e 'using Pkg; Pkg.test()'
```

The tests are `@testitem`s in `test/`, run by TestItemRunner, and they
include an Aqua check. Some tests draw random problems, and three options
control them. Pass them through `test_args`:

```
julia --project -e 'using Pkg; Pkg.test(test_args = ["--longer", "5"])'
```

- `--longer x` multiplies the length of the randomized tests by `x`. The
  default is 1.0, or 0.2 under CI.
- `--randseed` draws fresh random seeds instead of the fixed ones, to explore.
- `--seed n` reruns with a particular seed, such as one a `--randseed` run
  reported as failing.

The environment variable `UNITTESTDESIGN_TEST_LONGER` (a number such as
`5`) overrides both `--longer` and the CI default, which is convenient in a
GitHub Actions job. `test/runtests.jl` documents the precedence.

## The correctness standard

Two pieces of the test suite decide whether an engine is correct.

- **The independent checker**, `test/checker.jl`, answers by brute force,
  over the full product of a small space, the questions the engines must
  answer: which cases are valid, which combinations are feasible, and
  whether a design covers them. It shares no code with `src/` and does not
  load the package. It aims to be obviously right, not fast.
- **The random gate**, in `test/test_random_problems.jl`, draws random
  constrained problems (500 at each of strengths 2 and 3 by default, fewer
  under CI), generates a design for each with both engines, and checks every design against the checker: every
  case valid, every feasible combination covered, and every excluded
  combination attributed as the checker attributes it. There is no expected
  failure; an exception from either engine fails the gate. Run it with
  `--randseed` or a larger `--longer` after changing an engine.

A change to an engine is ready when the gate passes, not only when the
examples do. When a random problem fails, the log gives its strength, stream
seed, and index, and `gate_problem(strength, seed, index)` redraws it, so it
can become a fixed regression test in `test/fixtures.jl`.

## Benchmarks

`benchmark/run.jl` times the engines on fixed spaces and reports case
counts beside the times, so that a speedup is never bought with a larger
design unnoticed. It needs nothing beyond the standard library.

```
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
julia --project=benchmark benchmark/run.jl --out results.md
```

The options are `--runs N` (warm runs per measurement, default 5),
`--out` and `--tsv` (write the report to a file), and `--skip-slow`, which
leaves out GND on the largest space, about four minutes per call. The CI
workflow has a benchmark job that runs the script with `--skip-slow` on
every push and keeps the report as a build artifact. Tests assert
completion and coverage, never seconds; the benchmark is for people. The
procedure is in `design/benchmark_procedure.md`.

## Building the documentation

The documentation has its own environment, and its manifest is not in the
repository. Once, from the repository root:

```
julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path = pwd())); Pkg.instantiate()'
```

Then build:

```
julia --project=docs docs/make.jl
```

The build runs every `@example` block and every `jldoctest` block, in the
pages and in the docstrings, so an example that no longer runs, or a doctest
whose printed output changed, fails the build. The
pages are in `docs/src`, and the page tree is in `docs/make.jl`. Write
examples that show output as `@example` or `jldoctest` blocks, and keep
plain `julia` blocks for fragments that are not meant to run.

## Branches and pull requests

The trunk is `main`. Work happens on branches and reaches `main` through
pull requests; CI runs the tests on several Julia versions and operating
systems, builds the documentation, and runs the benchmark job.

## Conduct

Contributors follow the [Contributor Covenant Code of
Conduct](man/code_of_conduct.md).
