# Scaling benchmark measurements

Each job is an isolated serial process. RSS includes Julia, compilation, setup, all runs and diagnostics; allocation is cumulative warm-call allocation, not peak memory. Cold calls include compilation. Censored jobs have no completed warm estimate.

| Job | Status | Cases | Warm median s | Warm allocated MiB | Peak RSS MiB |
|:--|:--|--:|--:|--:|--:|
| heap-hint-reuse-ipog-n512-v2-t2 | ok | 21 | 3.671 | 1.57e+04 | 1076 |
| heap-hint-reuse-ipog-n1024-v2-t2 | stage_timeout | 23 |  |  | 1634 |
| heap-hint-report-ipog-n64-v2-t2 | ok | 15 | 0.206 | 335.5 | 669.2 |
| heap-hint-report-ipog-n128-v2-t2 | rss_limit | 17 |  |  | 2050 |
