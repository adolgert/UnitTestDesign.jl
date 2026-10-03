# Source evidence behind the scalability benchmarks

This review describes the current implementation, not measured timings. The formulas below are storage lower bounds derived from the source. The benchmark results should decide which effects matter on this machine.

## Target counts and representation

For uniform domains with `n` parameters, `v` ordinary options and strength `t`, the ordinary target count is `T = binomial(n,t) * v^t`. For mixed domains it is the sum of the products of domain sizes over the requested supports. `TargetList` uses checked arithmetic to calculate that count and synthesizes one full-width partial row per indexed target (`src/request.jl:388–415`). A target holds only `t` nonzero entries, but its representation has `n` integer entries.

On this 64-bit machine, one dense matrix of every target has an integer payload of `8*n*T` bytes. This excludes object headers, dictionaries, temporary copies, compilation and the result. For binary pairs, that is about 255 MiB at `n=256`, 2.00 GiB at `n=512`, and 14.9 GiB at `n=1000`. These are analytical estimates, not measurements or recommended job sizes.

The classic unconstrained IPOG path has a much smaller working coverage bucket: at parameter `k`, it represents only targets involving the new parameter, `binomial(k-1,t-1)*v^t` columns of height `k` (`src/parameter_order.jl:172–194`; `src/combinations.jl:80–96`). For binary pairs, the last bucket at 1000 parameters has about 30.5 MiB of integer payload. Parameter support lists and temporary allocations still exist, and a small live bucket does not imply low runtime.

GND materializes the complete target matrix (`src/greedy_tuples.jl:106–109`), including when its input was a lazy `TargetList`. Each candidate row scans uncovered targets to score every parameter; `most_matches_existing` also scans the full parameter width inside that target scan (`src/coverage_matrix.jl:170–198`). There are `candidates` candidates per output row (`src/greedy_tuples.jl:153–183`), default 50 (`src/engines.jl:53–61`). Target storage and repeated scans are distinct potential limits. A smaller candidate count trades search effort for design quality and should be measured, with case counts retained.

## Small API changes select substantially different algorithms

Classic IPOG is selected only when there are no constraints, no must-include rows and one effective strength group (`src/parameter_order.jl:468–480`). Even one seed or a scoped predicate that forbids nothing selects `ipog_multi_way`. That path makes a full-width copy of every required target into parameter buckets and then stacks each bucket into a dense matrix (`src/parameter_order.jl:393–420`). Mixed-strength groups have the same representation change even if the extra group adds few targets. A group at the base strength is removed as a no-op (`src/request.jl:172`).

Unconstrained classification returns a lazy target list, and final verification uses one bit vector per support (`src/request.jl:458–469,638–653`). Constrained classification retains every required target as a full-width vector, or an exclusion record for every excluded target (`src/request.jl:439–469`). Therefore a restrictive rule that reduces the final case count can still increase generation memory.

The general final verifier retains projection sets for all observed supports (`src/request.jl:621–630`). This differs from the specialized streaming verifier used for `TargetList`. Benchmarking only the legacy numeric `ipog` function hides classification, certification and conversion to the public result.

Public rows are converted from the index matrix to typed `NamedTuple`s or positional tuples. The positional route first constructs the named rows, then drops their names (`src/testcases.jl:214–243`; `src/request.jl:661–663`). Very wide row types may make compilation and conversion material; timings must separate fresh process costs from warmed calls, and compare numeric core generation to the public API.

## Constraint structure matters more than its spelling

Pattern, macro, scoped predicate and `require` rules all compile to the same `Constraint`/`RuleTable` forms (`src/constraints.jl:14–41`). Macro versus function syntax should not change downstream search for equivalent scopes and predicates. Construction and compiler costs can differ.

Scoped rules enumerate their domain product at space construction when it is at most `tabulation_limit` (default 100,000); only forbidden tuples are stored in a `Set`. Above the limit they become lazy, with operation-local verdict dictionaries (`src/constraints.jl:803–830`; `src/space.jl:189`). Patterns are also tabulated through the predicate route, rather than stored directly as one forbidden tuple. Measure construction separately from reuse of an already built `TestSpace`, and force both sides of the tabulation threshold for the same mathematical rule.

Whole-case predicates are always lazy and connect every parameter, even if their function body reads only two fields (`src/constraints.jl:123–131,803–807`; `src/rule_table.jl:21`). Unlike a narrow scoped rule, they cannot be checked until the whole scope is assigned, and forward checking starts only when one parameter remains unset (`src/feasibility.jl:494–541`). This can conceal a simple contradiction until deep in search. Whole-case tautologies isolate overhead; a whole-case equivalent of a two-parameter rule exposes lost locality.

The search partitions the rule graph into connected components, solves components separately, applies forward checking and picks the parameter with the fewest surviving candidates (`src/feasibility.jl:114–125,485–579`). Independent pairs should differ from a chain, and a dense connected graph from both. A hard unsatisfiable constraint system can cost more than a permissive system despite returning no cases.

Caches retain full-assignment keys and complete witnesses, plus per-component partial keys and component witnesses (`src/feasibility.jl:139–150,402–459`). They have no size cap. Component locality reduces search nodes, but whole-assignment cache keys still have the full parameter width. `memo_hits` counts only whole-assignment hits; it does not expose component hits. `SearchStats.evaluations` counts rule checks, not lazy predicate executions, and `memo_size` counts distinct lazy verdicts (`src/feasibility.jl:71–85,264–285`). Generation's main search stats do not aggregate deletion-trial work, although each `IndexExplanation` contains that trial cost (`src/feasibility.jl:636–695`).

An implied infeasible target also runs a deletion search over rules. Each trial constructs a fresh search context, sharing only lazy predicate verdict dictionaries, and attempts to remove one rule (`src/feasibility.jl:669–695`). Direct forbidden targets avoid this work. Compare direct exclusions with implications and redundant rules. `explanation_limit` can reduce attribution work without changing the underlying proved exclusion, but the budget counts search nodes, not all allocations or rule checks.

`feasibility_limit` is per query, not per generation; free fills, cache hits, checks and initial pruning consume no nodes (`src/feasibility.jl:14–30,378–398`). A million-node budget per target does not bound total runtime over millions of targets. Use an external wall timer and process memory guard even when the library's limits are set.

## User-facing operations can exceed generation costs

`coverage(cases)` checks rows, projects them support by support and avoids feasibility search for targets already observed in a valid row (`src/measure.jl:387–419,517–536`). This gives a complete design an advantage over a partial audit. Missing, excluded and unknown targets are retained in result lists (`src/measure.jl:340–373`), so auditing an empty or truncated suite has different memory behavior from certifying a complete suite.

For every uncovered target, measurement calls `explain_partial`, even when the space has no rules (`src/measure.jl:358–364`). The unconstrained search still stores a full-width key and witness in its operation-local memo (`src/feasibility.jl:402–459`). Thus an unconstrained audit of many missing interactions can accumulate roughly `16*n*missing_count` bytes of integer cache payload, despite the public missing record holding only the support's values.

`report(cases)` measures the requested strength, then always measures the next strength as its bonus (`src/report.jl:184–198,226–235`). A pair report thus creates a triple workload, often with many missing triples and their witnesses. This deserves its own guarded size ladder. It must not be attached automatically to large generation measurements. `design_sizes` similarly executes several generators and then measures pair and triple coverage for each result (`src/report.jl:559–591,616–630`).

`Invalid` options add separate negative-row subproblems, one per invalid value of every parameter; rules reading that parameter are omitted. Required negative targets are still retained at full width (`src/invalid.jl:123–182`). This is neither equivalent to adding an ordinary option nor proportional only to ordinary design size. `Partition` labels reduce concrete option count before the solver sees the problem, but measuring realization belongs to a separate workload.

Full factorial checks the candidate product before constructing its request through the public API, enumerates one row at a time, stores only accepted rows, and returns a materialized result (`src/interface.jl:647–662`; `src/full_factorial.jl:63–79,131–187`). Its size limit is a row-count guard, not a byte guard; narrow and wide million-row jobs have different memory demands. Restrictive constraints reduce retained rows but do not skip candidate enumeration.

## Suggested discriminating experiments

- Separate parameter count, option count and strength ladders. For heterogeneous domains, compare one wide domain with all domains wide, and shuffle parameter order while retaining identical semantics.
- For the same pairwise problem, compare classic IPOG, GND candidate counts/seeds, one complete seed, one partial seed, a small stronger group, a scoped tautology and a whole-case tautology.
- Compare equivalent pattern/function/macro rules, scoped versus whole-case representations, independent pairs versus chains versus dense graphs, and tabulated versus forced-lazy evaluation.
- Compare directly forbidden targets, implied exclusions, redundant rules and bounded unsatisfiable cases. Record limit failures as outcomes rather than speed measurements.
- Compare reuse of `TestSpace` with rebuilding it, numeric design versus public rows, complete coverage versus partial audits, report bonus, invalid-row generation, excursions and guarded full factorial.

Record generated case count and independently verified coverage as well as time, cumulative allocation, peak resident memory, retained result/search sizes and search counts. Allocated bytes are cumulative churn, not a capacity estimate. Peak resident memory includes runtime/compiler state; retained heap size excludes some process memory. Every larger ladder point should depend on smaller measured points and a conservative analytical payload check.

## Adding trial solvers

The useful internal boundary is `Request` in index space, required-target classification, `cover_ordinary(engine, request, required)`, and `Design` certification (`src/request.jl:14–70`; `src/engines.jl:77–125`). A trial solver can add `generate(::TrialEngine, ::Request)` without passing the public API gate. The benchmark should allow an adapter that returns the same index matrix/metadata and applies `validate_design`, so all solvers carry the same rules, seeds and coverage guarantee.

The public `_check_engine` currently accepts only `IPOG` or `GND` (`src/interface.jl:241–244`); common `generate` orchestration is also specialized on that union (`src/engines.jl:97`). Future public solver extensibility needs a deliberate protocol rather than only a new engine struct. A trial that improves coverage storage but still uses eager constrained classification will retain the common classification/cache limitation. Stage measurements should distinguish generation-core improvements from end-to-end gains.
