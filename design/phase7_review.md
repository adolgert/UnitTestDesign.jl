# Phase 7 review: documentation and first contact

Date: 2026-09-28. Branch `feature/phase7-docs`, stacked on
`feature/phase6-features` (PR #57). Plan: Phase 7.

## Artifacts

| Step | Artifact | Where |
|:--|:--|:--|
| 1 | README first screen: the promise sentence, install line, the decision table with three "use something else" rows, the solver example with its real output, the promises in contract terms, sections by situation, migration note | `README.md` |
| 2 | Tutorial, levels 0–4, every step an executed `@example`; ends with `coverage` and `report`; the Hilbert-index extended example rewritten with rules instead of `continue` skips | `docs/src/man/tutorial.md` |
| 3 | Nine how-to guides by job, each with the situation, runnable steps, what the output means, and one pitfall | `docs/src/howto/*.md` |
| 4 | Explanation: values and oracles (from the paper's "How to Use"), interaction coverage and the evidence (random-at-equal-budget formula computed live), constraints in plain words, engines corrected with measured numbers, IPOG kept | `docs/src/explain/*.md`, `docs/src/man/engines.md`, `ipog.md` |
| 5 | Reference organized by purpose with explicit `@docs` blocks; every exported docstring opens "Use when …" (deprecated ones "Deprecated alias of …"); migration table 0.4 → 0.5 with executed "after" code | `docs/src/reference.md`, `docs/src/reference/migration.md`, `src/*.jl` |
| 6 | Developer pages: contract, non-goals, contributing | `docs/src/dev/`, `docs/src/contributing.md` |
| 7 | One-pager for AI agents: the decision rule, three executed patterns, the one-line check | `docs/src/man/agents.md` |
| 8 | Doctests on: `DocMeta.setdocmeta!` and `doctest = true` in `make.jl`; a `@testitem` runs `Documenter.doctest(UnitTestDesign; manual = true)` in the suite (about 16 s); a second item checks every export has a docstring opening as required and free of minimum-count claims | `docs/make.jl`, `test/test_doctests.jl` |

Removed pages: `man/guide.md`, `man/examples.md`, `man/example_extended.md`,
`man/methods.md`, `man/greedy.md` (content absorbed).

`docs/make.jl`: `warnonly = false`, `checkdocs = :exports`, `doctest = true`.
The docs build (`julia --project=docs docs/make.jl`) exits 0 with no
warning from any page; the only message is Documenter's local
git-remote notice. Full suite: 310,435 pass, 0 failures, doctests
included. 23 manual pages.

## Acceptance gate

- Rendered docs built; doctests and the full suite pass.
- README, migration table, and examples reviewed for limits (the
  constraints page shows `unknown`, `ResourceLimitError`, and an unresolved
  explanation live), negative coverage (the invalid-inputs guide and the
  tutorial show `!` rows and the two guarantees), and unresolved diagnosis
  (the diagnose guide shows `inseparable`/`indistinguishable`/`unknown`).
- No example promises a minimum case count, a minimum explanation, or
  unconditional follow-up isolation; a test item enforces the docstring
  side, and the only "minimal" in the manual is "inclusion-minimal only
  when verified" for explanation rule sets (§8.5).

## Source changes made for the documentation

1. `Invalid`'s wrapped value is documented as `x.value`.
2. The `<:` operator inside `@forbid`/`@require` now gets a message that
   names it and suggests the call form or the function form (§12.6).
3. `diagnose`'s display says "same failures as …"; "indistinguishable" is
   reserved for the `followups` status.
4. Singular/plural and "a/an" agreement in printed counts ("the 1 feasible
   pair", "an 8-combination space", "2 strategies").
5. `iscomplete`'s docstring notes that a rejected row does not make a
   result incomplete; the lockfile pattern everywhere keeps two checks
   (`iscomplete(coverage(...))` and `all(isallowed(space, ·))`).
6. `covering`'s docstring no longer says "fewest cases"; explanation
   wording is "inclusion-minimal".

## Decisions for review

1. **Decision table rows**: Fable's rows plus three "use something else"
   rows (property-based testing or fuzzing for values you can generate but
   not list; design of experiments for effect estimation; space-filling
   samples for continuous sweeps). The full factorial is a row of its own.
2. **JuliaCon talk link** added to the README (it shows 0.4; the README
   says so). Remove if unwanted.
3. **Evidence page** cites Kuhn, Wallace & Gallo 2004, Kuhn, Kacker & Lei
   2010, and Arcuri & Briand 2012, and computes the random-at-equal-budget
   numbers live; the "GND shorter at eight values" claim is reproduced in
   an `@example` rather than cited from a benchmark file, since no
   benchmark file records it.
4. **Reference is one page** (about 141 KiB) with a raised size threshold;
   splitting it would change the page tree.
5. **`Partition` does not round-trip through `repr`**; the docstring and
   the lockfile guide say to write the name.
6. **`code_of_conduct.md`** stays out of the navigation, linked from
   Contributing.
7. **Manual-page doctests need their own `setup`** because the docs compat
   is `"1"` and `doctest(; meta)` arrived in 1.19; none currently do.
8. **Two uses of "combination"** (the full product in a summary line vs a
   t-way target in the prose) are noted on the evidence page rather than
   changing the display.

## What Phase 8 needs from this phase

- Registration makes the `pkg> add UnitTestDesign` line true; the README
  currently also gives the `#release/0.5` URL.
- The docs deploy to `stable` on the tag; the `devbranch = "main"` setting
  in `deploydocs` is unchanged.
