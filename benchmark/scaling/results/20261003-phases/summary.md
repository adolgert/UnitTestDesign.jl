# Scaling benchmark measurements

Each job is an isolated serial process. RSS includes Julia, compilation, setup, all runs and diagnostics; allocation is cumulative warm-call allocation, not peak memory. Cold calls include compilation. Censored jobs have no completed warm estimate.

| Job | Status | Cases | Warm median s | Warm allocated MiB | Peak RSS MiB |
|:--|:--|--:|--:|--:|--:|
| phases-profile_ipog-none-n32-v2 | ok | 13 | 0.0008288 | 5.04 | 824.1 |
| phases-profile_ipog-noop_scoped-n32-v2 | ok | 13 | 0.004454 | 19.56 | 813.4 |
| phases-profile_ipog-noop_whole-n32-v2 | ok | 13 | 0.01272 | 28.93 | 833.5 |
| phases-profile_ipog-scoped-n32-v2 | ok | 11 | 0.004282 | 19.2 | 811.6 |
| phases-profile_ipog-equality-n32-v2 | ok | 2 | 0.3218 | 1042 | 893.1 |
| phases-profile_ipog-none-n8-v16 | ok | 256 | 0.04016 | 169.1 | 823.2 |
| phases-profile_ipog-bench12-n12-v0 | ok | 22 | 0.001134 | 4.284 | 802 |
| phases-profile_gnd-none-n32-v2 | ok | 12 | 0.02429 | 11.97 | 784.6 |
| phases-profile_gnd-noop_scoped-n32-v2 | ok | 12 | 0.02971 | 28.91 | 792.8 |
| phases-profile_gnd-noop_whole-n32-v2 | ok | 12 | 0.2349 | 262.3 | 852.6 |
| phases-profile_gnd-scoped-n32-v2 | ok | 13 | 0.03011 | 29.18 | 791 |
| phases-profile_gnd-equality-n32-v2 | ok | 2 | 0.3423 | 1069 | 829.5 |
| phases-profile_gnd-none-n8-v16 | ok | 344 | 1.369 | 231.7 | 832.3 |
| phases-profile_gnd-bench12-n12-v0 | ok | 25 | 0.02087 | 42.66 | 830.9 |
