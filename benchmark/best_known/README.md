# Best-known covering-array sizes

The reference data of the solver plan's benchmarks (design/20261003_solver_plan.md
§7.1): for a strength t, v values and k parameters, the fewest rows anyone has
published, with the source of that number, and the elementary lower bound.
Only numbers and source attributions are stored, never arrays (D6).

| File | What |
|:--|:--|
| `colbourn_tables.csv` | The snapshot: `t,v,k,N,source,status,retrieved`. A line says that N rows are known to suffice for up to k parameters. |
| `refresh.py` | Fetches the tables and writes or checks `colbourn_tables.csv`. Python standard library. |
| `BestKnown.jl` | `best_known(t, v, k)`, `lower_bound(t, values)`, `catalog_rows(t, v, k)`. Julia standard library and the package; runs in the package's or the benchmark's environment. |
| `write_table.jl` | Writes `uniform_shapes.csv` for every uniform shape the benchmark grid uses. |
| `uniform_shapes.csv` | `t,v,k,best_known,source,status,retrieved,lower_bound,catalog`, one line per shape. summarize.py joins benchmark results on it. |
| `check.jl` | Spot checks against the plan's tables; exits nonzero on a difference. |

## Where the numbers come from

Charles Colbourn's covering array tables, in the November 2024 state indexed at
github.com/ugroempi/CAs/blob/main/ColbournTables.md, which links one page per
(t, v) at `https://www.data2intelligence.de/ColbournTables/t{t}v{v}.html`.
Each page lists (t, v, k, N, source). The snapshot holds strengths 2 and 3
with 2–25 values, strength 4 with 2–9, and strengths 5 and 6 with 2–5:
6,775 lines, all retrieved on 2026-10-04 (`retrieved`; `status` is the
tables' own November 2024).

The plan's first version, design/20261003_solver_plan_constructions/best_known.csv
(served October 3 and 4, 2026), held the same pages without strength 3 at
15–25 values. All 6,207 of its lines agree with what the pages served on
2026-10-04 (`refresh.py --check` against it); strength 3 at 15–25 values was
added for the `uniform-pp` and `uniform-npp` families.

**The lookup.** The best-known N for k parameters is the smallest N among the
lines of its (t, v) page whose k is at least the given k (plan, appendix).
`best_known` returns `nothing` past the last line. Where the tables have no
page for (t, v), it gives one size that needs no table, marked
`status = "derived"`: vᵗ, the lower bound, which the zero-sum array meets for
k ≤ t + 1 and Bush's orthogonal array meets for a prime power v ≥ t and
k ≤ v + 1. That is how the plan's §2.1 has 1,024 and 4,096 rows for 8 × 32
and 8 × 64. The lower bound is the product of the t largest value counts:
each of those t parameters' combinations needs its own row.

**What to watch for when parsing.** The pages wrap the table in an outer
`<tr><td>`, so a parser that matches `<tr>…</tr>` loses each table's first
row. `refresh.py` keeps only rows of exactly five innermost cells and checks
that k ascends on each page. The source strings are kept as the pages print
them, internal double spaces included.

## Refreshing

```sh
python3 benchmark/best_known/refresh.py --check benchmark/best_known/colbourn_tables.csv  # what changed
python3 benchmark/best_known/refresh.py --out benchmark/best_known/colbourn_tables.csv    # rewrite
julia --project=. --startup-file=no benchmark/best_known/write_table.jl                  # the shapes
julia --project=. --startup-file=no benchmark/best_known/check.jl                        # spot checks
```

Fetching the 64 pages takes about two minutes, one second apart. `--cache DIR`
keeps the pages. To add pages, extend `PAGES` in `refresh.py`. A refresh that
changes numbers moves the plan's comparisons: say so in the change, and expect
`check.jl` to fail where the plan's tables quote the old number.

After adding a benchmark family or shape, rerun `write_table.jl`;
`benchmark/scaling/test_families.py` fails while a uniform shape of the grid
is missing from `uniform_shapes.csv`.

## The catalog column

`catalog` is the size of the array the `Construction` engine builds for the
shape, which the package's catalog says without building it (plan §5.4,
Phase 2): `BestKnown.catalog_rows` calls `UnitTestDesign._catalog_rows(t, v,
k)`, which returns the rows or `nothing` where no entry applies. Every
strength-2 and strength-3 shape has one. At strengths 4 to 6 the catalog has
only the zero-sum array (k ≤ t + 1) and the Bush array, fused (k ≤ q + 1 for
a prime power q ≥ t), so 36 of the 473 shapes are empty, and the two filled
strength-6 shapes, 531,427 and 531,429 rows for 10 parameters of 2 and 3
values, are far above the best known. Rerun `write_table.jl` after the
catalog changes.
