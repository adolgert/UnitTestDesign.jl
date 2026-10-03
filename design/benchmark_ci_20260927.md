# UnitTestDesign benchmark

- Date: 2026-09-27 17:57
- Package: /home/runner/work/UnitTestDesign.jl/UnitTestDesign.jl, commit `6df2fa25343f1d48056295d43aa4760f37b87c06`
- Julia 1.13.1, x86_64-linux-gnu, Linux x86_64
- CPU: AMD EPYC 7763 64-Core Processor, 4 logical cores, 15.6 GiB memory
- Julia threads: 1; optimization level -O2; bounds checks default
- Machine: CI runner
- Engine seed: GND `seed = 0` (a fresh `Xoshiro(0)` per call); IPOG is deterministic
- Compilation: the first call of each measurement is reported separately; timings are the median of 5 warm calls, each after `GC.gc()`

<details><summary>versioninfo()</summary>

```
Julia Version 1.13.1
Commit 96ca370cf0e (2026-09-25 19:34 UTC)
Build Info:
  Official https://julialang.org release
Platform Info:
  OS: Linux (x86_64-linux-gnu)
  CPU: 4 × AMD EPYC 7763 64-Core Processor
  WORD_SIZE: 64
  LLVM: libLLVM-20.1.8 (ORCJIT, znver3)
  GC: Built with stock GC
Threads: 1 default, 1 interactive, 1 GC (on 4 virtual cores)
Environment:
  JULIA_PKG_SERVER_REGISTRY_PREFERENCE = eager
```
</details>

## Fixture 1: 15 parameters × 4 values, strength 4, no rules

`all_tuples(fill(1:4, 15)...; n_way = 4, engine)`, the same call on both revisions. The design fingerprint is `hash` of the returned rows; equal fingerprints mean equal designs.

| Engine | Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) | Fingerprint |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| IPOG | 958 | 8.11 | 6.84 | 6.77–7.14 | 18025.5 | 199,402,311 | 1.42 | `f0c75cba9fa65154` |

GND left out (`--skip-slow`).

## Fixture 2: `bench12` (test/fixtures.jl)

12 parameters, 331776 rows, 207360 valid, four rules. `generate(engine, Request(space; strength))` through the internal request; the public `covering` arrives in Phase 4. Queries, nodes and rule checks are the request's `feasibility.stats` for one call. Full factorial is `generate_full_factorial(Request(space; strength = 1))`.

| Strategy | Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) | Queries | Nodes | Rule checks |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| IPOG, strength 2 | 22 | 0.434 | 0.0019 | 0.0019–0.0021 | 3.9 | 67,953 | 0.0000 | 817 | 68 | 805 |
| GND, strength 2 | 25 | 0.029 | 0.029 | 0.029–0.030 | 42.2 | 829,552 | 0.0000 | 26,837 | 68 | 35,649 |
| IPOG, strength 3 | 93 | 0.059 | 0.024 | 0.024–0.025 | 64.0 | 944,809 | 0.0000 | 6,616 | 68 | 3,697 |
| GND, strength 3 | 96 | 0.431 | 0.429 | 0.427–0.432 | 190.5 | 3,398,443 | 0.0000 | 106,528 | 68 | 134,636 |
| full factorial | 207360 | 0.120 | 0.112 | 0.111–0.113 | 191.6 | 2,644,088 | 0.0000 | 0 | 0 | 1,980,288 |

## Fixture 3: the repaired greedy dead ends

The four dead ends frozen in test/fixtures.jl, on which the 0.4 IPOG threw a `BoundsError`. No "before" number exists; these record the "after".

| Fixture | Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) | Queries | Nodes | Rule checks |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| `dead_end_pairwise_1`, IPOG, strength 2 | 12 | 0.0004 | 0.0003 | 0.0002–0.0003 | 0.2 | 5,144 | 0.0000 | 71 | 96 | 559 |
| `dead_end_pairwise_1`, GND, strength 2 | 12 | 0.0016 | 0.0015 | 0.0014–0.0016 | 2.3 | 55,229 | 0.0000 | 6,642 | 165 | 1,043 |
| `dead_end_pairwise_2`, IPOG, strength 2 | 16 | 0.0005 | 0.0003 | 0.0003–0.0004 | 0.3 | 7,443 | 0.0000 | 96 | 134 | 949 |
| `dead_end_pairwise_2`, GND, strength 2 | 15 | 0.0022 | 0.0022 | 0.0021–0.0022 | 3.3 | 78,627 | 0.0000 | 9,809 | 242 | 2,035 |
| `dead_end_threeway_1`, IPOG, strength 3 | 30 | 0.0010 | 0.0008 | 0.0008–0.0008 | 1.0 | 22,876 | 0.0000 | 240 | 364 | 2,099 |
| `dead_end_threeway_1`, GND, strength 3 | 30 | 0.0067 | 0.0068 | 0.0068–0.0070 | 7.3 | 175,098 | 0.0000 | 19,667 | 752 | 4,317 |
| `dead_end_threeway_2`, IPOG, strength 3 | 60 | 0.0064 | 0.0063 | 0.0063–0.0064 | 11.8 | 218,854 | 0.0000 | 1,605 | 7,012 | 17,857 |
| `dead_end_threeway_2`, GND, strength 3 | 64 | 0.098 | 0.100 | 0.099–0.101 | 69.6 | 1,403,553 | 0.0000 | 74,884 | 48,364 | 176,720 |

## Memory of a lazy rule's memo

Each space gets one added whole-case rule, `forbid(case -> false)`, which is always lazy (contract §12.19), so every complete row the searches reach is memoized. The memo belongs to the request (§3.5): `memo_size(request)` counts its entries and `Base.summarysize(request.feasibility)` is the request's search state, memo included, while `Base.summarysize(space)` should not change. One space per table; the calls run in order on the same space, each with a fresh request. Times are single first calls, not medians.

| Space | When | Cases | Time (s) | `Base.summarysize(space)` (bytes) | `memo_size(request)` (entries) | `Base.summarysize(request.feasibility)` (bytes) | Nodes |
|:--|:--|--:|--:|--:|--:|--:|--:|
| bench12 + whole-case rule | before generation | – | – | 5,440 | – | – | – |
| bench12 + whole-case rule | after IPOG, strength 2 | 22 | 0.207 | 5,440 | 982 | 978,768 | 6,800 |
| bench12 + whole-case rule | after IPOG, strength 3 | 93 | 0.054 | 5,440 | 4,870 | 5,710,288 | 54,583 |
| bench12 + whole-case rule | after GND, strength 2 | 25 | 0.180 | 5,440 | 36,558 | 25,997,320 | 146,828 |
| bench12 + whole-case rule | after GND, strength 3 | 96 | 1.07 | 5,440 | 85,380 | 96,593,480 | 497,731 |
| fixture 1 + whole-case rule | before generation | – | – | 3,864 | – | – | – |
| fixture 1 + whole-case rule | after IPOG, strength 2 | 33 | 0.250 | 3,864 | 4,451 | 3,453,768 | 23,968 |
| fixture 1 + whole-case rule | after IPOG, strength 3 | 177 | 0.618 | 3,864 | 47,666 | 54,020,808 | 359,151 |
| fixture 1 + whole-case rule | after IPOG, strength 4 | 958 | 17.7 | 3,864 | 389,417 | 392,836,232 | 3,886,299 |

GND is not run on fixture 1 with the whole-case rule: without rules it already takes about four minutes per call at strength 4, and the rule adds a feasibility search to every value it scores.

## Where the time goes

Parts of the calls above, timed alone (median of 5 after one discarded call). Recorded as Phase 4/5 candidates; only the final validation changed in Phase 3 (review round 1 moved it to index space).

| Call | Part | Time (s) | Allocated (MiB) | Note |
|:--|:--|--:|--:|:--|
| bench12 full factorial | whole call | 0.116 | 191.6 | 207360 rows of 331776 |
| bench12 full factorial | enumeration, `violates` per candidate | 0.074 | 166.2 | 64% of the call; 1,150,848 rule checks |
| bench12 full factorial | `validate_design`, `violates` per row | 0.033 | 25.3 | 29% of the call; 829,440 rule checks |
| `forbids` on a tabulated rule | one call | 26.1 ns | 32 bytes | the runtime-length `ntuple` key allocates on every check |
| bench12 full factorial | `forbids` in enumeration, estimated | 0.030 | 35.1 | 26% of the call |
| bench12 full factorial | `forbids` in validation, estimated | 0.022 | 25.3 | 19% of the call |
| bench12 full factorial | not in the call: each row to a case, `from_indices` (`to_cases`) | 0.648 | 357.5 | 560% of the call |
| bench12 full factorial | not in the call: `isallowed` on each case (the old validation) | 0.352 | 217.1 | 304% of the call |
| bench12 full factorial | ... of which `case_indices`, the value lookup | 0.285 | 109.5 | 246% of the call |
| fixture 1, IPOG | whole `generate` call | 6.88 | 18022.9 | |
| fixture 1, IPOG | classic `ipog`, the 0.4 core | 6.31 | 17278.7 | 92% |
| fixture 1, IPOG | `classify_targets`: the list of 349,440 targets | 0.772 | 504.2 | 11%; unconstrained, so nothing is excluded |
| fixture 1, IPOG | `validate_design` | 0.165 | 240.0 | 2% |

