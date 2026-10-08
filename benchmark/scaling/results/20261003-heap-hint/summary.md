# Scaling benchmark measurements

Each job is an isolated serial process. RSS includes Julia, compilation, setup, all runs and diagnostics; allocation is cumulative warm-call allocation, not peak memory. Cold calls include compilation. Censored jobs have no completed warm estimate.

| Job | Status | Cases | Warm median s | Warm allocated MiB | Peak RSS MiB |
|:--|:--|--:|--:|--:|--:|
| heap-hint-reuse-ipog-n512-v2-t2 | rss_limit | 21 |  |  | 2055 |
| heap-hint-reuse-ipog-n1024-v2-t2 | skipped_after_limit |  |  |  |  |
| heap-hint-report-ipog-n64-v2-t2 | ok | 15 | 0.1756 | 335.5 | 821.7 |
| heap-hint-report-ipog-n128-v2-t2 | rss_limit | 17 |  |  | 2057 |
