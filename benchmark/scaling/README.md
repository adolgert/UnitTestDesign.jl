# Scaling and workflow benchmarks

This suite measures the current engines on one machine, including constraints,
public API costs, reporting, negative tests, and bounded feasibility searches.
Jobs run **serially**, each in a fresh Julia process, with external time and
resident-memory watchdogs. The older `benchmark/run.jl` preserves historical
fixtures; this suite explores scaling and practical workflows.

The completed MacBook study and practical interpretation are in
[STUDY.md](STUDY.md). Its raw measurements and protocol snapshots are
stored under `results/`; timings and RSS limits concern that machine
and those recorded budgets.

From the repository root, with the package environment already installed:

```sh
python3 benchmark/scaling/run.py --list
python3 benchmark/scaling/run.py --out benchmark/scaling/results/my-machine
python3 benchmark/scaling/run.py --filter arguments --runs 3
```

Python uses only its standard library. Julia uses the repository project.
The runner passes `--startup-file=no --threads=1` and sets
`OPENBLAS_NUM_THREADS=1`. IPOG is deterministic; GND uses seed 0, with 50
candidates normally and 10 in the tuning comparison. These are timings on a
specific machine, not portable performance guarantees or a claim that either
engine minimizes the number of test cases.

Use repeated `--julia-arg=FLAG` options for additional Julia settings, for
example `--julia-arg=--heap-size-hint=512M`. These flags precede the worker
script and enter the recorded command and resume fingerprint. A heap hint
influences garbage collection; the external RSS watchdog remains necessary.

## Workloads

The default grid varies one main dimension at a time:

| Family | What changes |
|:--|:--|
| `arguments` | 8–1,024 arguments, 2 options each, pairwise coverage |
| `options` | 8 arguments, 4–64 options each |
| `mixed` | 16 arguments; the first has 4–256 options, others have 2 |
| `strength3`–`strength5` | 12 arguments with 3 options, increasing interaction strength |
| `noop_scoped`, `noop_whole` | Rules excluding nothing, with narrow versus whole-case scope |
| `scoped`, `whole`, `pattern`, `macro`, `lazy_scoped` | The same forbidden `(p1=1, p2=1)` pair expressed differently; forced lazy tabulation is included |
| `matching`, `chain` | Forbid neighboring `(1,1)` pairs in disconnected or connected components |
| `equality` | Neighboring arguments must agree; nonadjacent unequal pairs have implied exclusions |
| `equality-cheap-explanations` | The equality family with attribution budget 1 instead of the default |
| `global_budget` | Whole-case rule: sum of argument values may not exceed `n + n÷2` |
| `tabulated_scope`, `lazy_scope` | Identical rules over six four-valued arguments, comparing construction-time tabulation with forced lazy evaluation |
| `alldifferent-sat`, `alldifferent-unsat` | Binary all-different rules with `q` colors and respectively `q` or `q+1` arguments |
| `invalid` | One invalid value added to every argument, requiring separate negative coverage |
| `partition`, `realize` | Named value classes and their subsequent realization |
| `gnd-candidates10` | A smaller GND candidate pool |

The all-different jobs measure a single feasibility question rather than a
covering design. The unsatisfiable family has more arguments than available
colors, so its expected answer is known independently. A node-budget result
of `unknown` is a bounded search outcome, not an incorrect SAT/UNSAT answer.

Workflow jobs compare reused spaces, inline named domains, positional domains,
partial `must_include` rows, complete-suite top-ups, pair-to-triple upgrades,
mixed interaction strength, coverage auditing,
rich reporting, collection, iteration, export, full factorial enumeration,
and distance-2 excursions. `seed` currently supplies one partial row
`(p1=2,)`; `stronger` raises the first up to six arguments to strength 3.
Full factorial and excursions have different guarantees from covering designs.
`topup` keeps the first half of a prepared pairwise suite and adds the cases
needed to restore coverage. `upgrade` keeps a prepared suite and requests
strength 3. `audit_half` and `audit_empty` measure respectively that first
half and no rows against the requested space. Preparation is recorded
separately and remains resident during these workflow measurements.

## What the measurements include

Each job records one first space construction, the requested number of warm
fresh-space constructions, one cold operation, and the requested number of
warm operations. `GC.gc()` runs before each construction and measured
operation. Jobs that analyze existing cases first generate a prepared design,
recording that preparation separately. The worker explicitly drops previous
results and request contexts before the next operation's collection.

| Metric or operation | Interpretation |
|:--|:--|
| `construct` | First model/space construction, including rule validation and tabulation; may include compilation |
| `construct_warm` | Fresh model/space construction after the initial compilation, measured separately from generation |
| `core` | `Request(space; ...)` plus `generate(engine, request)`: request normalization, target classification, solving, and built-in certification, without public `TestCases` conversion |
| `reuse` | Request, generation, and `TestCases` conversion using an existing space |
| `public` | Public `covering(space; ...)` pipeline using an existing space |
| `named`, `positional` | Public pipeline rebuilding a space from domains inside the timed operation |
| `coverage`, `report`, `collect`, `iterate`, `realize`, `export` | Only the named operation on prepared cases; preparation is a separate measurement |
| `cold` seconds | First operation in that process; includes compilation it triggers, but **excludes process startup and package loading** |
| Warm median/min/max | Completed warm-call durations; each call uses fresh request-local search state |
| `allocated_bytes` | Cumulative Julia heap allocation during the timed call, not live or peak memory |
| `gc_seconds` | Garbage collection time reported by Julia for that call |
| `retained_bytes` | `Base.summarysize` of the returned value; a design and a public result own different objects, so these sizes are not directly interchangeable |
| `search_retained_bytes` | Reachable size of the primary ordinary feasibility object; excludes other request contexts and some generation state |
| Sampled peak RSS | Maximum sampled resident memory of the process group, including the small `time` wrapper |
| OS peak RSS | Operating-system high-water mark from `/usr/bin/time -l` on macOS or `-v` on Linux, when available |
| OS peak memory footprint | Additional macOS footprint metric when `/usr/bin/time -l` provides it; preserved separately from RSS |
| `wall_seconds` | Whole job lifetime, including startup, setup, all runs, diagnostics, and oracle validation |

RSS includes Julia, package loading, compilation, model construction, prepared
cases, all calls, and diagnostics. It is a process-wide high-water mark, not a
stage-specific warm-memory measurement. Sampled stage peaks are recorded too,
but their attribution is approximate at the polling interval and they retain
the process's compilation/setup baseline. Sampling may miss brief peaks;
terminated jobs may lack an OS high-water mark. Neither allocated bytes nor
`summarysize` substitutes for resident-memory evidence on a memory-limited
machine. The runner measures summary sizes and emits JSON **outside** the
operation timer, but their cost and memory contribute to whole-job limits.

The current search counters describe the primary ordinary feasibility object:
queries, cache hits, tentative assignments, and rule checks. Rule checks include
memo hits and table lookups; they are not predicate-call counts. Negative-row
searches and deletion trials used to attribute implied exclusions are not
fully aggregated into these counters. `rule_memo` counts shared lazy-rule
verdicts in the request. Use total time and RSS when comparing workloads with
different attribution or negative-testing costs.

`report(cases)` checks the requested coverage, adds coverage at the next
strength, and computes prefix curves. It can cost more than generation or
`coverage(cases)`, particularly when the bonus strength has many interactions.
Partition realization is measured separately from labeled-case generation;
coverage claims concern the labels, not the realized values.

## Limits and interpretation

Default external limits are 2,048 MiB RSS, 30 seconds per warm stage, 60 seconds
for startup and first-call/setup stages, 30 seconds for diagnostics, 180 seconds
per whole job, and 0.2-second polling. These leave
headroom on a 24 GB laptop. Jobs are arranged from smaller to larger within
a ladder. An error, timeout, or memory stop blocks larger cases in that
ladder unless `--continue-ladders` is supplied. A preflight check can skip a
native workload when its proven raw dense-target integer payload alone
exceeds the RSS cap; this omits object overhead and applies only to known
storage paths with targets known feasible. Other workloads use the runtime
guards. Neither preflight nor sampled RSS is a guaranteed hard memory bound.

Generation and feasibility workloads default to 100,000 tentative assignments
per feasibility question. The explanation budget defaults to 1,000,000.
Budgets are per question, so they do not bound total operation time or memory;
external watchdogs remain necessary. An explanation budget of 1 can preserve
a proven exclusion while leaving its attribution minimality unresolved.

`ok` means the worker completed. `stage_timeout`, `job_timeout`, and
`rss_limit` are censored observations, not measurements of completed work.
`skipped_after_limit` means the larger job was not attempted. `resource_limit`
identifies an unknown bounded feasibility search or a thrown library `ResourceLimitError` (including the full-factorial row limit).
`skipped_payload_floor` means preflight proved the raw target payload already
exceeded the configured cap. `monitor_error` means the external memory monitor
failed and the job was stopped. `error` records the exception in `errors`,
other than the resource-limit exceptions classified above. Inspect the stage and raw events to
distinguish setup, generation, reporting, and diagnostic limits. Aggregate warm
estimates require all requested warm runs and an accepted completed status;
partial run measurements remain in the raw events.

`--resume --out EXISTING_DIRECTORY` reuses saved job results only when their
fingerprint matches the source files, worker/controller, package environment,
adapter contents, job specification, and configured guards. Mismatches rerun
the job. A fresh output directory remains useful for a new experiment or
changed machine conditions; fingerprints do not measure thermal load or
other applications' memory use.
The existing fixture dependencies are hashed too. For other trial adapters,
preserve transitive source dependencies outside the repository alongside
the results; their contents are not automatically discovered from `include`.

## Evidence and output files

Each job saves `spec.json`, `events.jsonl`, `stderr.txt`, and `result.json`.
The output root contains cumulative `results.json` and `summary.md`, updated
after every job. Metadata captures source revision, working-tree state,
source diff, source hashes, runner limits, platform, and initial memory state.
Julia events record version, CPU, thread count, and memory. Preserve these files together
when comparing engines or repeating the experiment on another machine.

Small ordinary integer covering jobs whose complete product is at most 4,096
rows receive an independent exhaustive check: enumerate valid rows using the
user-level predicates, check returned-row validity, and compare every required
interaction with the returned design. This check runs outside measured solver
time. Larger jobs rely on the built-in engine certification. The oracle
includes small mixed-domain jobs and checks must-include preservation. Small
partition and invalid-value jobs additionally receive public coverage checks
on their labeled cases, outside operation timing. The exhaustive oracle skips
these wrapped-value families and non-covering operations. Trial adapters
receive additional package certification within the timed operation:
classify required ordinary and
negative targets, validate every row, preserve must-include rows, and recount
coverage. Registration alone does not verify a solver's result bookkeeping
or prove that it implements a useful independent algorithm.

Create an analysis CSV and compact evidence archives after a study finishes:

```sh
python3 benchmark/scaling/summarize.py benchmark/scaling/results/my-machine/results.json \
  --out benchmark/scaling/results/my-machine/flat.csv --archive
```

`raw_jobs.zip` preserves per-job files. `protocol_snapshot.zip` preserves
the measured source, environment files and adapters. Archive before editing
measured files: a later archive retains matching existing snapshots, and
refuses to fabricate a snapshot if the measured source is no longer
available. Per-job directories are ignored in git; keep the archives and
aggregate JSON/CSV when sharing or checking in a study. Multiple result
files can be flattened into one CSV without `--archive`.

## Adding trial solvers and custom jobs

Pass one or more Julia extension files with `--adapter PATH`. Each is included
in the worker after the package loads and may call `register_solver(name,
adapter)`. The name becomes the job specification's `solver` value.

The simplest adapter is a function `(space, keywords) -> TestCases`:

```julia
# trial_adapter.jl: replace this baseline implementation with your trial solver.
register_solver("trial", (space, kw) ->
    covering(space; kw..., engine=GND(seed=0, candidates=20)))
```

Function adapters support `reuse`, `seed`, `stronger`, `topup`, `upgrade`, and
preparation for `coverage`, `audit_half`, `audit_empty`, `report`, `collect`,
`iterate`, `realize`, and `export`. They do
not currently support `core`, `public`, `named`, or `positional` jobs, which
call the engine interface directly. Their recorded request counters describe
the harness's certification, not search inside the function adapter.

An engine-object adapter can extend
`UnitTestDesign.generate(engine, request::UnitTestDesign.Request)` and return a
`UnitTestDesign.Design`, then register an instance. It supports `core` and
the internal-generation paths. The harness certifies its matrix with the
package's index-space validation before converting it into public cases.
The public API accepts only covering engines, so such an object cannot use
the direct public input jobs. A covering engine, a subtype of
`UnitTestDesign.CoveringEngine` with the methods its docstring lists (plan
§4.2), can: the package's own `generate` certifies it, as it does IPOG and
GND. An engine in the package's registry (`UnitTestDesign._engine_registry`)
needs no adapter: a job names it by its registry name, such as `"IPOG()"` or
`"GND()"`, beside the older names `ipog`, `gnd` and `gnd10`. These internal
types are tied to the checked-out package revision.

Certification is included in measured trial-adapter time. An adapter that
calls public `covering` already receives built-in certification and then the
harness's additional certification. Its timing therefore includes redundant
validation; distinguish that overhead when interpreting a future solver
comparison. Native engine timings include their own required certification.

Custom specifications are a JSON array, supplied with `--specs PATH`:

```json
[
  {
    "id": "trial-pairs-n8-v2",
    "ladder": "trial-arguments",
    "n": 8,
    "v": 2,
    "family": "none",
    "usage": "reuse",
    "solver": "trial",
    "strength": 2,
    "runs": 3,
    "nodes": 100000,
    "explanations": 1000000
  }
]
```

```sh
python3 benchmark/scaling/run.py --adapter trial_adapter.jl \
  --specs trial_jobs.json --out benchmark/scaling/results/trial
```

Give every job a unique `id`, use one `ladder` per comparable increasing
sequence, and order smaller cases first. Custom jobs should respect the
supported usage/adapter combinations; use `reuse` for trial adapters.
Built-in `named` jobs preserve the model's
constraints while rebuilding the space at the public input form's default
tabulation threshold. Forced-lazy named jobs are rejected; use `reuse` or `public`
to retain their configured threshold. `positional` rejects constrained
models because that public input form has no constraints. The default grid
uses simple integer values, one partial seed, and unconstrained audit/report
jobs. More heterogeneous values, large existing suites, large constrained reports,
and failed partial seeds are useful future extensions when the first
measurements justify them.

## Harness checks and focused studies

Run these checks serially, while no benchmark is measuring a solver:

```sh
python3 benchmark/scaling/test_watchdog.py
python3 benchmark/scaling/test_archives.py
python3 benchmark/scaling/test_adapters.py
python3 benchmark/scaling/run.py --adapter benchmark/scaling/example_adapter.jl \
  --specs benchmark/scaling/adapter_smoke.json --out benchmark/scaling/results/adapter-smoke
```

The watchdog tests use tiny fake workers to check successful recording,
external timer and RSS stops, truncated JSON, bounded-search status, resume
fingerprints and the dense-storage preflight. The real Julia adapter checks
verify ordinary and negative coverage and require the common validator to
reject incomplete trial outputs. The example adapters delegate to native
engines and demonstrate registration; they are not new solver algorithms.
Archive checks verify that source changes and raw-directory cleanup preserve
existing evidence and that external adapters sharing a filename stay distinct.

The supplied focused specifications extend the main grid:

```sh
python3 benchmark/scaling/run.py --adapter benchmark/scaling/bench12_adapter.jl \
  --specs benchmark/scaling/followup_specs.json --out benchmark/scaling/results/followup
python3 benchmark/scaling/run.py --adapter benchmark/scaling/bench12_adapter.jl \
  --adapter benchmark/scaling/phase_adapter.jl --specs benchmark/scaling/phase_specs.json \
  --out benchmark/scaling/results/phases
python3 benchmark/scaling/phases.py benchmark/scaling/results/phases/results.json \
  --out benchmark/scaling/results/phases/native_phases.csv
python3 benchmark/scaling/run.py --specs benchmark/scaling/heap_specs.json \
  --julia-arg=--heap-size-hint=512M --stage-seconds 60 --cold-seconds 120 \
  --job-seconds 300 --out benchmark/scaling/results/heap-hint
```

`bench12_adapter.jl` loads the existing heterogeneous fixture from the
repository instead of duplicating its rules. The phase adapter emits `phase`
events for native target classification, ordinary generation and final
validation. Its *overall* operation additionally includes the trial
wrapper's certification; use the phase events for attribution, not that
overall time as a native end-to-end baseline. Phase instrumentation adds
small logging overhead between the timed calls. Raw events preserve the
measurements. The adapter currently excludes `Invalid` models.

For a fresh run on different hardware or a different Julia executable, use
a new output directory. Resume fingerprints do not identify the host or
resolve changes behind a `julia` launcher; resume is intended for the same
machine/runtime and source configuration.

Generate standalone figures after measurements finish (requires matplotlib):

```sh
python3 benchmark/scaling/plot.py benchmark/scaling/results/my-machine/results.json \
  --out benchmark/scaling/results/my-machine/overview.png
```
