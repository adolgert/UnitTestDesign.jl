# Phase 3 benchmark results

Measured 2026-09-27 with `benchmark/run.jl`, following
`design/benchmark_procedure.md` (plan Phase 3 step 9). This is the first
baseline for the repaired engines; it is a laptop measurement. **A
measurement on the CI runner used for the release is still pending**, and
the regression tolerance below must be re-derived from that runner's spread
before any job enforces it.

## How it was run

```
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
julia --project=benchmark benchmark/run.jl --out run_N.md --tsv run_N.tsv   # three times, N = 1, 2, 3

git worktree add <scratch>/v04 d46122d
julia --project=<scratch>/v04 benchmark/run.jl                              # the 0.4 code: fixture 1 only
```

The script needs no packages beyond the standard library: `@timed` for time,
bytes and allocation counts, `Base.summarysize` for retained memory. Each
measurement makes one first call, reported separately as the cold start, then
five warm calls, each after `GC.gc()`; the tables give the median of the warm
calls and their range. The three runs of the new revision ran back to back
in fresh processes (about 26 minutes each, most of it GND on fixture 1), then
the 0.4 run.

## Environment

| | |
|:--|:--|
| Package | commit `b955f50` (Phase 3 engines; `src/` unchanged by this round) |
| Prior revision | commit `d46122d` (0.4, `main` before `release/1.0`) |
| Julia | 1.13.1 (official release), `-O2`, default bounds checks, stock GC |
| OS | macOS, arm64-apple-darwin27.0.0 |
| CPU | Apple M2, 8 logical cores, 24 GiB memory |
| Threads | 1 Julia thread (1 interactive, 1 GC) |
| Machine | a laptop, not a CI runner |
| Engine seed | GND `seed = 0`: a fresh `Xoshiro(0)` per call (0.4: `GND(rng = Xoshiro(0))`, a fresh generator per call); IPOG is deterministic |
| Compilation | first call reported separately; median of 5 warm calls |

## Fixture 1: 15 parameters × 4 values, strength 4, no rules

The same public call on both revisions,
`all_tuples(fill(1:4, 15)...; n_way = 4, engine)`. The fingerprint is `hash`
of the returned rows.

| Revision | Engine | Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) | Fingerprint |
|:--|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| 0.4 (`d46122d`) | IPOG | 958 | 4.89 | 3.48 | 3.43–3.49 | 17305.4 | 181,659,415 | 0.528 | `f0c75cba9fa65154` |
| Phase 3, run 1 | IPOG | 958 | 4.76 | 4.09 | 4.05–4.09 | 18055.8 | 199,432,008 | 0.725 | `f0c75cba9fa65154` |
| Phase 3, run 2 | IPOG | 958 | 4.80 | 4.04 | 3.94–4.16 | 18055.8 | 199,432,008 | 0.696 | `f0c75cba9fa65154` |
| Phase 3, run 3 | IPOG | 958 | 4.78 | 3.95 | 3.93–4.04 | 18053.1 | 199,432,008 | 0.679 | `f0c75cba9fa65154` |
| 0.4 (`d46122d`) | GND | 936 | 254.0 | 239.3 | 235.9–242.6 | 19884.3 | 76,412,022 | 0.794 | `ed6adef052056416` |
| Phase 3, run 1 | GND | 936 | 236.2 | 236.4 | 235.5–240.2 | 20883.9 | 91,331,715 | 0.982 | `ed6adef052056416` |
| Phase 3, run 2 | GND | 936 | 240.5 | 236.5 | 236.1–238.9 | 20578.1 | 91,331,715 | 0.953 | `ed6adef052056416` |
| Phase 3, run 3 | GND | 936 | 236.0 | 251.6 | 235.7–254.1 | 20640.9 | 91,331,715 | 1.09 | `ed6adef052056416` |

Both engines return **the same design on both revisions** (equal
fingerprints and case counts: 958 rows for IPOG, 936 for GND), so the
comparison is of time for identical output.

- **IPOG: 3.95–4.09 s after, 3.48 s before, about 14–18% slower.** The
  classic unconstrained `ipog` core is unchanged; the difference is the
  request's bookkeeping, which 0.4 did not have: `classify_targets` lists all
  349,440 targets (about 0.47 s) and `validate_design` checks them (about
  0.1 s), see "Where the time goes". Allocations rose 10% (182 M to 199 M).
- **GND: 236–252 s after, 239 s before, no measurable change.** The 0.4
  median lies inside the spread of the three new runs. Allocations rose 20%
  (76 M to 91 M) while time did not move; the scoring over 349,440 targets
  dominates both.
- The 0.4 numbers are one run, so their own spread is unknown; the new
  revision's spread is in the last section. On this machine the IPOG
  difference is larger than the IPOG spread (3.3%) but within the proposed
  35% tolerance.

## Fixture 2: `bench12`

`generate(engine, Request(space; strength))` on `test_space(bench12)`
(test/fixtures.jl), through the internal request; the public `covering`
arrives in Phase 4. Queries, nodes and rule checks are the request's
`feasibility.stats` after one call. Full factorial is
`generate_full_factorial(Request(space; strength = 1))`. Run 1 of 3:

| Strategy | Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) | Queries | Nodes | Rule checks |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| IPOG, strength 2 | 22 | 0.248 | 0.0014 | 0.0014–0.0014 | 4.0 | 69,176 | 0.0000 | 817 | 68 | 717 |
| GND, strength 2 | 25 | 0.021 | 0.021 | 0.021–0.022 | 42.4 | 830,959 | 0.0000 | 26,837 | 68 | 35,549 |
| IPOG, strength 3 | 93 | 0.036 | 0.017 | 0.017–0.018 | 64.4 | 949,596 | 0.0000 | 6,616 | 68 | 3,325 |
| GND, strength 3 | 96 | 0.296 | 0.296 | 0.296–0.297 | 191.3 | 3,403,432 | 0.0000 | 106,528 | 68 | 134,252 |
| full factorial | 207360 | 0.820 | 0.831 | 0.826–0.834 | 742.1 | 14,589,171 | 0.056 | 0 | 0 | 1,150,848 |

The first IPOG call (0.25 s) carries the compilation of the request and
feasibility code; later first calls are nearly warm.

These agree with what the two engine agents reported during Phase 3: IPOG
22 rows in 1.4 ms pairwise and 93 rows in 22.6 ms three-way (here 16–18 ms);
GND 25 rows in 20 ms and 96 rows in 0.32 s (here 20–22 ms and 0.29–0.31 s);
full factorial 0.67 s, mostly validation (here 0.74–0.87 s across the three
runs, 92–93% of it in `validate_design`). Every design is checked complete by
`test/checker.jl` in the test suite (test_parameter_order.jl,
test_greedy_tuples.jl, test_fixtures.jl); the benchmark times only.

**Before:** no baseline. The 0.4 IPOG throws a `BoundsError` at both
strengths and the 0.4 GND does not return (the legacy baseline recorded in
`design/benchmark_procedure.md`, fixture 2).

## Fixture 3: the repaired greedy dead ends

The four dead ends frozen in test/fixtures.jl, on which the 0.4 IPOG threw a
`BoundsError`. There is no "before"; these are the "after" for later phases.
Run 1 of 3:

| Fixture | Cases | First call (s) | Warm median (s) | Warm min–max (s) | Allocated (MiB) | Allocations | GC (s) | Queries | Nodes | Rule checks |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| `dead_end_pairwise_1`, IPOG, strength 2 | 12 | 0.060 | 0.0002 | 0.0002–0.0002 | 0.2 | 5,611 | 0.0000 | 71 | 96 | 511 |
| `dead_end_pairwise_1`, GND, strength 2 | 12 | 0.0011 | 0.0011 | 0.0011–0.0011 | 2.3 | 55,696 | 0.0000 | 6,642 | 165 | 995 |
| `dead_end_pairwise_2`, IPOG, strength 2 | 16 | 0.0003 | 0.0002 | 0.0002–0.0002 | 0.3 | 8,085 | 0.0000 | 96 | 134 | 885 |
| `dead_end_pairwise_2`, GND, strength 2 | 15 | 0.0016 | 0.0016 | 0.0016–0.0016 | 3.4 | 79,228 | 0.0000 | 9,809 | 242 | 1,975 |
| `dead_end_threeway_1`, IPOG, strength 3 | 30 | 0.060 | 0.0006 | 0.0006–0.0006 | 1.1 | 24,101 | 0.0000 | 240 | 364 | 1,979 |
| `dead_end_threeway_1`, GND, strength 3 | 30 | 0.0051 | 0.0051 | 0.0050–0.0051 | 7.3 | 176,324 | 0.0000 | 19,667 | 752 | 4,197 |
| `dead_end_threeway_2`, IPOG, strength 3 | 60 | 0.063 | 0.0043 | 0.0042–0.0043 | 12.0 | 221,701 | 0.0000 | 1,605 | 7,012 | 17,617 |
| `dead_end_threeway_2`, GND, strength 3 | 64 | 0.068 | 0.068 | 0.068–0.068 | 69.9 | 1,406,590 | 0.0000 | 74,884 | 48,364 | 176,464 |

The random problems of the gate are the rest of fixture 3. At multiplier 1.0
(500 problems per strength, the fixed seeds), generation alone takes, summed
over the 500 problems: pairwise, IPOG 0.33 s and GND 1.8 s; three-way, IPOG
0.92 s and GND 11.5 s. The checker takes about 2.4–3.9 s per engine and
strength on top, and drawing the problems (which runs the checker once more)
about 3.7–4.0 s. The two gate test items take 54 s together in the test
runner.

## Retained memory of a lazy rule's memo

Contract §12.19 keeps a lazy rule's memo on the `TestSpace`, so it outlives
every call. Each space below gets one added whole-case rule,
`forbid(case -> false)`, which is always lazy; the calls run in order on the
same space, so the memo accumulates. Times are single first calls. Identical
in all three runs except the times.

| Space | When | Cases | Time (s) | `Base.summarysize(space)` (bytes) | `memo_size(space)` (entries) | Nodes |
|:--|:--|--:|--:|--:|--:|--:|
| bench12 + whole-case rule | before generation | – | – | 5,696 | 0 | – |
| bench12 + whole-case rule | after IPOG, strength 2 | 22 | 0.131 | 407,104 | 982 | 6,800 |
| bench12 + whole-case rule | after IPOG, strength 3 | 93 | 0.039 | 1,611,328 | 5,036 | 54,583 |
| bench12 + whole-case rule | after GND, strength 2 | 25 | 0.148 | 6,428,224 | 37,714 | 146,828 |
| bench12 + whole-case rule | after GND, strength 3 | 96 | 0.730 | 25,695,808 | 97,813 | 497,731 |
| fixture 1 + whole-case rule | before generation | – | – | 4,144 | 0 | – |
| fixture 1 + whole-case rule | after IPOG, strength 2 | 33 | 0.214 | 2,002,992 | 4,451 | 23,968 |
| fixture 1 + whole-case rule | after IPOG, strength 3 | 177 | 0.380 | 31,985,712 | 48,517 | 359,151 |
| fixture 1 + whole-case rule | after IPOG, strength 4 | 958 | 9.43 | 127,930,416 | 394,410 | 3,886,299 |

GND was not run on fixture 1 with the whole-case rule: unconstrained it
already takes four minutes per call at strength 4, and the rule adds a
feasibility search for every value it scores.

Reading: one memo entry costs about 260–330 bytes here (a 12- or 15-integer
tuple key and a `Bool` in a `Dict`). On `bench12` the memo reaches 98,000 of
its 331,776 possible entries (26 MB) after four calls. On fixture 1 one
strength-4 IPOG call leaves 394,000 entries and 128 MB on the space, against
a bound of 4^15 ≈ 1.07 × 10^9 entries (hundreds of GB). The memo therefore
grows with the work done, not with the product, and a long-lived space that
serves several high-strength calls can hold hundreds of MB. This is the
measurement the procedure asked for before deciding whether to keep the memo
on the space, bound it, or move it into the request; that decision is left to
the Phase 3 review.

## Where the time goes

Parts of the calls above, timed alone (median of 5 after one discarded call;
the parts are timed separately, so they need not sum to the whole). Run 1 of
3; runs 2 and 3 give the same shares within a few points.

| Call | Part | Time (s) | Allocated (MiB) | Note |
|:--|:--|--:|--:|:--|
| bench12 full factorial | whole call | 0.797 | 736.8 | 207360 rows of 331776 |
| bench12 full factorial | enumeration, `violates` per candidate | 0.053 | 168.5 | 7% of the call; 1,150,848 rule checks |
| bench12 full factorial | `validate_design`, `isallowed` per row | 0.740 | 568.3 | 93% of the call; 829,440 rule checks |
| `forbids` on a tabulated rule | one call | 19.9 ns | 32 bytes | the runtime-length `ntuple` key allocates on every check |
| bench12 full factorial | `forbids` in enumeration, estimated | 0.023 | 35.1 | 3% of the call |
| bench12 full factorial | `forbids` in validation, estimated | 0.017 | 25.3 | 2% of the call |
| bench12 full factorial | validation: each row to a case, `from_indices` | 0.413 | 357.5 | 52% of the call |
| bench12 full factorial | validation: `isallowed` on each case | 0.296 | 217.1 | 37% of the call |
| bench12 full factorial | ... of which `case_indices`, the value lookup | 0.257 | 109.5 | 32% of the call |
| fixture 1, IPOG | whole `generate` call | 4.21 | 18059.0 | |
| fixture 1, IPOG | classic `ipog`, the 0.4 core | 3.70 | 17310.6 | 88% |
| fixture 1, IPOG | `classify_targets`: the list of 349,440 targets | 0.476 | 506.7 | 11%; unconstrained, so nothing is excluded |
| fixture 1, IPOG | `validate_design` | 0.096 | 242.1 | 2% |

## Run-to-run spread and the proposed tolerance

Warm medians of the three runs of the new revision:

| Measurement | Cases | Run 1 (s) | Run 2 (s) | Run 3 (s) | Spread | Widest warm min–max within a run |
|:--|--:|--:|--:|--:|--:|--:|
| fixture 1, IPOG, strength 4 | 958 | 4.09 | 4.04 | 3.95 | 3.3% | 5.6% |
| fixture 1, GND, strength 4 | 936 | 236.4 | 236.5 | 251.6 | 6.4% | 7.8% |
| bench12, IPOG, strength 2 | 22 | 0.0014 | 0.0013 | 0.0014 | 10.4% | 60.7% |
| bench12, GND, strength 2 | 25 | 0.021 | 0.020 | 0.022 | 13.0% | 6.7% |
| bench12, IPOG, strength 3 | 93 | 0.017 | 0.016 | 0.018 | 8.6% | 7.4% |
| bench12, GND, strength 3 | 96 | 0.296 | 0.290 | 0.310 | 6.9% | 1.2% |
| bench12, full factorial | 207360 | 0.831 | 0.744 | 0.865 | 16.2% | 1.9% |
| dead_end_pairwise_1, IPOG, strength 2 | 12 | 0.0002 | 0.0002 | 0.0002 | 44.9% | 26.3% |
| dead_end_pairwise_1, GND, strength 2 | 12 | 0.0011 | 0.0010 | 0.0011 | 12.1% | 6.5% |
| dead_end_pairwise_2, IPOG, strength 2 | 16 | 0.0002 | 0.0002 | 0.0003 | 29.7% | 32.5% |
| dead_end_pairwise_2, GND, strength 2 | 15 | 0.0016 | 0.0014 | 0.0015 | 9.9% | 11.1% |
| dead_end_threeway_1, IPOG, strength 3 | 30 | 0.0006 | 0.0005 | 0.0006 | 11.6% | 21.1% |
| dead_end_threeway_1, GND, strength 3 | 30 | 0.0051 | 0.0047 | 0.0050 | 8.7% | 17.5% |
| dead_end_threeway_2, IPOG, strength 3 | 60 | 0.0043 | 0.0040 | 0.0045 | 11.8% | 19.7% |
| dead_end_threeway_2, GND, strength 3 | 64 | 0.068 | 0.064 | 0.071 | 9.9% | 2.1% |

Spread is (largest − smallest) / smallest of the three medians. Case counts,
allocation counts, rule checks, nodes and fingerprints were identical in all
three runs; allocated bytes varied by under 2%.

Proposed regression tolerance, **for this laptop only**:

- **Time, calls of 10 ms or more: 35%.** The largest spread among them is
  16.2% (bench12 full factorial; GND on fixture 1 is 6.4%), and twice that,
  rounded up to the next 5%, is 35%. A later run is a regression when its
  warm median exceeds the Phase 3 median by more than 35%.
- **Time, calls under 10 ms: not gated.** Their spread reaches 45% (the
  sub-millisecond IPOG dead ends), so a tolerance of twice that would catch
  nothing a reviewer would not see by eye.
- **Allocation counts: exact, per Julia version.** They were identical in
  every run, so any change is a code change and should be explained in the
  review rather than tolerated.

These numbers come from one laptop on one afternoon. The procedure sets the
tolerance from three runs on the stable CI runner used for the release; that
measurement has not been made, and until it is, the tolerance above is a
proposal, not a gate.

## Phase 4/5 candidates (measured, not optimized)

1. **`validate_design` round-trips every row through values.** On `bench12`
   full factorial it is 92–93% of the call (0.67–0.77 s of 0.73–0.83 s,
   timed alone). The engine agents attributed this to per-row `isallowed`; the breakdown
   shows the rule checks themselves are small: building a `NamedTuple` per
   row (`from_indices`) is about 52–57% of the call and reading it back
   (`case_indices`, a lookup of each value by identity) about 27–32%.
   Checking the index row against the tables directly (the enumeration's
   `violates` does the same work in 0.05 s) would remove most of it.
   Whether final validation should stay in the caller's vocabulary as an
   independent check is a design question for the review.
2. **`forbids` allocates a runtime-length `ntuple` key on every check**:
   about 17–20 ns and 32 bytes per call. It is only 2–3% of the full
   factorial each in enumeration and validation, so it matters less than
   item 1, but it is on every feasibility search's path (the rule checks
   column above: 1.15 million in one full factorial, 134,000 in GND
   three-way on `bench12`).
3. **Unconstrained requests still build the target list.** On fixture 1 the
   new IPOG is about 0.5–0.6 s slower than 0.4 in the same call; the
   `classify_targets` list of 349,440 targets (0.47 s, 506 MiB) and
   `validate_design` (0.1 s) account for it. The design itself is identical
   (same fingerprint). Counting targets instead of listing them when no rule
   excludes anything, or validating coverage with the engine's coverage
   matrix, would close most of the gap.
4. **GND on fixture 1 costs four minutes per call**, the same as 0.4: the
   candidate scoring over 349,440 targets dominates, as the procedure
   anticipated. Nothing in Phase 3 changed it.
