# Scaling benchmark measurements

Each job is an isolated serial process. RSS includes Julia, compilation, setup, all runs and diagnostics; allocation is cumulative warm-call allocation, not peak memory. Cold calls include compilation. Censored jobs have no completed warm estimate.

| Job | Status | Cases | Warm median s | Warm allocated MiB | Peak RSS MiB |
|:--|:--|--:|--:|--:|--:|
| core-large-ipog-n128-v2-t2 | ok | 17 | 0.03383 | 254.6 | 829.8 |
| core-large-ipog-n256-v2-t2 | ok | 19 | 0.2977 | 1946 | 1017 |
| core-large-ipog-n512-v2-t2 | ok | 21 | 2.679 | 1.581e+04 | 1884 |
| core-large-ipog-n1024-v2-t2 | rss_limit |  |  |  | 2056 |
| seed-large-ipog-n128-v2-t2 | ok | 17 | 0.06221 | 409.2 | 905.3 |
| seed-large-ipog-n256-v2-t2 | ok | 19 | 0.7183 | 3123 | 1397 |
| seed-large-ipog-n512-v2-t2 | rss_limit |  |  |  | 2107 |
| scoped-large-ipog-n128-v2-t2 | ok | 17 | 0.2313 | 800.2 | 1042 |
| scoped-large-ipog-n256-v2-t2 | rss_limit | 19 |  |  | 2065 |
| scoped-large-ipog-n512-v2-t2 | skipped_after_limit |  |  |  |  |
| empty-audit-large-ipog-n128-v2-t2 | ok |  | 0.1215 | 357.1 | 839.2 |
| empty-audit-large-ipog-n256-v2-t2 | ok |  | 0.9859 | 2623 | 1580 |
| empty-audit-large-ipog-n512-v2-t2 | rss_limit |  |  |  | 2084 |
| bench12-ipog-n12-v0-t2 | ok | 22 | 0.001003 | 3.547 | 833.2 |
| bench12-gnd-n12-v0-t2 | ok | 25 | 0.02129 | 41.91 | 837.1 |
| bench12-ipog-n12-v0-t3 | ok | 93 | 0.01258 | 58.5 | 840.2 |
| bench12-gnd-n12-v0-t3 | ok | 96 | 0.3059 | 185.4 | 854.8 |
| bench12-coverage-ipog-n12-v0-t2 | ok |  | 0.0001443 | 0.1821 | 731.9 |
| bench12-report-ipog-n12-v0-t2 | ok | 22 | 0.00417 | 6.711 | 798.7 |
| bench12-audit_half-ipog-n12-v0-t2 | ok |  | 0.0003257 | 0.4418 | 813.7 |
| bench12-factorial-ipog-n12-v0-t2 | ok | 207360 | 0.5131 | 596.7 | 937.6 |
| strength2-ipog-n12-v3-t2 | ok | 20 | 0.0003542 | 1.299 | 833.8 |
| strength2-gnd-n12-v3-t2 | ok | 17 | 0.006185 | 3.936 | 758.8 |
| arguments4-ipog-n16-v4-t2 | ok | 32 | 0.001302 | 6.594 | 746.7 |
| arguments4-ipog-n32-v4-t2 | ok | 41 | 0.007083 | 45.26 | 838.1 |
| arguments4-ipog-n64-v4-t2 | ok | 49 | 0.05723 | 331.8 | 901.5 |
| arguments4-ipog-n128-v4-t2 | ok | 57 | 0.3675 | 2516 | 866.8 |
| arguments4-gnd-n16-v4-t2 | ok | 35 | 0.04684 | 15.93 | 749.5 |
| arguments4-gnd-n32-v4-t2 | ok | 43 | 0.3363 | 81.51 | 843.8 |
| arguments4-gnd-n64-v4-t2 | ok | 51 | 2.628 | 588.3 | 917.3 |
| arguments4-gnd-n128-v4-t2 | stage_timeout | 60 |  |  | 1131 |
| rule-options-scoped-ipog-n8-v4-t2 | ok | 29 | 0.0007119 | 2.356 | 841 |
| rule-options-scoped-ipog-n8-v8-t2 | ok | 105 | 0.004122 | 19.84 | 831.5 |
| rule-options-scoped-ipog-n8-v16-t2 | ok | 257 | 0.04309 | 217 | 835.9 |
| rule-options-scoped-ipog-n8-v32-t2 | ok | 2114 | 0.9166 | 4062 | 916.9 |
| rule-options-scoped-gnd-n8-v4-t2 | ok | 26 | 0.01009 | 13.79 | 821.9 |
| rule-options-scoped-gnd-n8-v8-t2 | ok | 92 | 0.1159 | 93.58 | 846.7 |
| rule-options-scoped-gnd-n8-v16-t2 | ok | 342 | 1.859 | 780 | 986.8 |
| rule-options-scoped-gnd-n8-v32-t2 | rss_limit |  |  |  | 2067 |
| rule-options-whole-ipog-n8-v4-t2 | ok | 29 | 0.01261 | 10.16 | 840.8 |
| rule-options-whole-ipog-n8-v8-t2 | ok | 105 | 1.069 | 424.1 | 886.8 |
| rule-options-whole-ipog-n8-v16-t2 | resource_limit |  |  |  | 1339 |
| rule-options-noop_scoped-ipog-n8-v16-t2 | ok | 256 | 0.04329 | 216.9 | 761.4 |
| rule-options-noop_scoped-ipog-n8-v32-t2 | ok | 2131 | 0.9298 | 4063 | 918.1 |
| alldifferent-budget1000000-unsat-n9-v8 | ok |  | 0.02323 | 16.73 | 787.6 |
| alldifferent-budget1000000-unsat-n10-v9 | ok |  | 0.2213 | 150.5 | 852.7 |
| alldifferent-budget1000000-unsat-n11-v10 | resource_limit |  | 0.2329 | 152.6 | 857.5 |
| alldifferent-budget10000000-unsat-n9-v8 | ok |  | 0.02369 | 16.73 | 766.8 |
| alldifferent-budget10000000-unsat-n10-v9 | ok |  | 0.2201 | 150.5 | 814.2 |
| alldifferent-budget10000000-unsat-n11-v10 | ok |  | 2.361 | 1505 | 874 |
| alldifferent-budget10000000-unsat-n12-v11 | resource_limit |  | 3.045 | 1526 | 876.2 |
| alldifferent-cover-sat-ipog-n4-v4 | ok | 20 | 0.0003172 | 0.4594 | 836 |
| alldifferent-cover-unsat-ipog-n6-v5 | ok | 0 | 0.003854 | 6.11 | 818.6 |
| alldifferent-cover-sat-gnd-n4-v4 | ok | 13 | 0.002016 | 3.413 | 723.6 |
| alldifferent-cover-unsat-gnd-n6-v5 | ok | 0 | 0.003929 | 6.114 | 810.1 |
| alldifferent-cover-unsat-ipog-n8-v7 | ok | 0 | 0.1008 | 90.5 | 834.5 |
| whole-default-budget-ipog-n32-v2 | resource_limit |  |  |  | 1548 |
