# Scaling benchmark measurements

Each job is an isolated serial process. RSS includes Julia, compilation, setup, all runs and diagnostics; allocation is cumulative warm-call allocation, not peak memory. Cold calls include compilation. Censored jobs have no completed warm estimate.

| Job | Status | Cases | Warm median s | Warm allocated MiB | Peak RSS MiB |
|:--|:--|--:|--:|--:|--:|
| arguments-ipog-n8-v2-t2 | ok | 9 | 9.562e-05 | 0.1651 | 750.2 |
| arguments-ipog-n16-v2-t2 | ok | 11 | 0.0002285 | 0.8344 | 731.9 |
| arguments-ipog-n32-v2-t2 | ok | 13 | 0.0008535 | 4.99 | 715.7 |
| arguments-ipog-n64-v2-t2 | ok | 15 | 0.004315 | 34.72 | 822.6 |
| arguments-ipog-n128-v2-t2 | ok | 17 | 0.03405 | 254.9 | 834.2 |
| arguments-ipog-n256-v2-t2 | ok | 19 | 0.2906 | 1947 | 951.9 |
| arguments-ipog-n512-v2-t2 | ok | 21 | 2.522 | 1.583e+04 | 1935 |
| arguments-ipog-n1024-v2-t2 | rss_limit |  |  |  | 2051 |
| arguments-gnd-n8-v2-t2 | ok | 8 | 0.0007259 | 0.9489 | 723.1 |
| arguments-gnd-n16-v2-t2 | ok | 10 | 0.004122 | 2.977 | 722.7 |
| arguments-gnd-n32-v2-t2 | ok | 12 | 0.02438 | 11.92 | 724.4 |
| arguments-gnd-n64-v2-t2 | ok | 14 | 0.1697 | 65.1 | 739.2 |
| arguments-gnd-n128-v2-t2 | ok | 17 | 2.164 | 474.1 | 837.8 |
| arguments-gnd-n256-v2-t2 | stage_timeout | 19 |  |  | 1562 |
| arguments-gnd-n512-v2-t2 | skipped_after_limit |  |  |  |  |
| arguments-gnd-n1024-v2-t2 | skipped_after_limit |  |  |  |  |
| options-ipog-n8-v4-t2 | ok | 28 | 0.0003352 | 1.113 | 709.6 |
| options-ipog-n8-v8-t2 | ok | 103 | 0.003169 | 13.59 | 715.8 |
| options-ipog-n8-v16-t2 | ok | 256 | 0.0396 | 169.4 | 739.7 |
| options-ipog-n8-v32-t2 | ok | 1991 | 0.7798 | 3624 | 887.9 |
| options-ipog-n8-v64-t2 | ok | 7168 | 11.31 | 5.273e+04 | 900.9 |
| options-gnd-n8-v4-t2 | ok | 27 | 0.006699 | 4.092 | 716.1 |
| options-gnd-n8-v8-t2 | ok | 93 | 0.08531 | 24.85 | 752.3 |
| options-gnd-n8-v16-t2 | ok | 344 | 1.371 | 232.1 | 778.4 |
| options-gnd-n8-v32-t2 | stage_timeout | 1298 |  |  | 782.7 |
| options-gnd-n8-v64-t2 | skipped_after_limit |  |  |  |  |
| mixed-ipog-n16-v4-t2 | ok | 10 | 0.0002802 | 0.9543 | 741.8 |
| mixed-ipog-n16-v16-t2 | ok | 32 | 0.0006872 | 3.022 | 735.6 |
| mixed-ipog-n16-v64-t2 | ok | 128 | 0.004652 | 30.53 | 754.5 |
| mixed-ipog-n16-v256-t2 | ok | 512 | 0.07729 | 446.7 | 804.5 |
| mixed-gnd-n16-v4-t2 | ok | 13 | 0.004412 | 3.821 | 751.9 |
| mixed-gnd-n16-v16-t2 | ok | 32 | 0.01485 | 10.65 | 714.3 |
| mixed-gnd-n16-v64-t2 | ok | 128 | 0.1742 | 73.52 | 721.1 |
| mixed-gnd-n16-v256-t2 | ok | 512 | 2.901 | 838.1 | 799.3 |
| strength3-ipog-n12-v3-t3 | ok | 74 | 0.006279 | 31.43 | 730.4 |
| strength3-gnd-n12-v3-t3 | ok | 68 | 0.2243 | 39.72 | 749.9 |
| strength4-ipog-n12-v3-t4 | ok | 267 | 0.1371 | 644.1 | 813.3 |
| strength4-gnd-n12-v3-t4 | ok | 244 | 5.899 | 603.6 | 774.1 |
| strength5-ipog-n12-v3-t5 | ok | 918 | 1.933 | 9661 | 883.1 |
| strength5-gnd-n12-v3-t5 | stage_timeout |  |  |  | 787.8 |
| noop_scoped-ipog-n8-v2-t2 | ok | 9 | 0.0001787 | 0.4541 | 728.5 |
| noop_scoped-ipog-n16-v2-t2 | ok | 11 | 0.0006095 | 2.53 | 751 |
| noop_scoped-ipog-n32-v2-t2 | ok | 13 | 0.003196 | 15.69 | 724.4 |
| noop_scoped-ipog-n64-v2-t2 | ok | 15 | 0.02137 | 107.5 | 735.6 |
| noop_scoped-gnd-n8-v2-t2 | ok | 8 | 0.001351 | 2.453 | 749.4 |
| noop_scoped-gnd-n16-v2-t2 | ok | 10 | 0.004982 | 7.254 | 731.5 |
| noop_scoped-gnd-n32-v2-t2 | ok | 12 | 0.02866 | 25.08 | 731.3 |
| noop_scoped-gnd-n64-v2-t2 | ok | 14 | 0.1868 | 120.8 | 756.3 |
| noop_whole-ipog-n8-v2-t2 | ok | 9 | 0.000344 | 0.6253 | 730.4 |
| noop_whole-ipog-n16-v2-t2 | ok | 11 | 0.001616 | 3.798 | 736.9 |
| noop_whole-ipog-n32-v2-t2 | ok | 13 | 0.01206 | 25.06 | 736 |
| noop_whole-ipog-n64-v2-t2 | ok | 15 | 0.1201 | 180.5 | 766.3 |
| noop_whole-gnd-n8-v2-t2 | ok | 8 | 0.003984 | 7.405 | 737.1 |
| noop_whole-gnd-n16-v2-t2 | ok | 10 | 0.03638 | 53.98 | 747.2 |
| noop_whole-gnd-n32-v2-t2 | ok | 12 | 0.2268 | 258.4 | 848.6 |
| noop_whole-gnd-n64-v2-t2 | ok | 14 | 1.362 | 1310 | 1763 |
| scoped-ipog-n8-v2-t2 | ok | 7 | 0.0002015 | 0.4318 | 758.6 |
| scoped-ipog-n16-v2-t2 | ok | 9 | 0.0006217 | 2.434 | 736.9 |
| scoped-ipog-n32-v2-t2 | ok | 11 | 0.003521 | 15.4 | 739.5 |
| scoped-ipog-n64-v2-t2 | ok | 13 | 0.02281 | 106.4 | 747.2 |
| scoped-gnd-n8-v2-t2 | ok | 8 | 0.001309 | 2.333 | 751.2 |
| scoped-gnd-n16-v2-t2 | ok | 10 | 0.005083 | 6.729 | 739.8 |
| scoped-gnd-n32-v2-t2 | ok | 13 | 0.02932 | 25.31 | 747.2 |
| scoped-gnd-n64-v2-t2 | ok | 14 | 0.1853 | 118.7 | 759.1 |
| whole-ipog-n8-v2-t2 | ok | 7 | 0.0005037 | 0.6872 | 759.2 |
| whole-ipog-n16-v2-t2 | ok | 9 | 0.2575 | 87.45 | 757 |
| whole-ipog-n32-v2-t2 | resource_limit |  |  |  | 838.3 |
| whole-ipog-n64-v2-t2 | skipped_after_limit |  |  |  |  |
| whole-gnd-n8-v2-t2 | ok | 8 | 0.004502 | 7.294 | 752 |
| whole-gnd-n16-v2-t2 | ok | 10 | 0.788 | 257.4 | 826.5 |
| whole-gnd-n32-v2-t2 | resource_limit |  |  |  | 830.2 |
| whole-gnd-n64-v2-t2 | skipped_after_limit |  |  |  |  |
| matching-ipog-n8-v2-t2 | ok | 8 | 0.0002336 | 0.4986 | 751.9 |
| matching-ipog-n16-v2-t2 | ok | 10 | 0.0007767 | 2.845 | 741.8 |
| matching-ipog-n32-v2-t2 | ok | 13 | 0.004556 | 18.21 | 748 |
| matching-ipog-n64-v2-t2 | ok | 14 | 0.02756 | 127.1 | 745.5 |
| matching-gnd-n8-v2-t2 | ok | 7 | 0.002337 | 4.462 | 757.7 |
| matching-gnd-n16-v2-t2 | ok | 10 | 0.01524 | 31.51 | 759.8 |
| matching-gnd-n32-v2-t2 | ok | 12 | 0.06756 | 139.7 | 739.7 |
| matching-gnd-n64-v2-t2 | ok | 14 | 0.3956 | 658.5 | 992.6 |
| chain-ipog-n8-v2-t2 | ok | 8 | 0.0003397 | 0.62 | 753.9 |
| chain-ipog-n16-v2-t2 | ok | 11 | 0.001899 | 4.009 | 752.9 |
| chain-ipog-n32-v2-t2 | ok | 14 | 0.01321 | 28.04 | 821.3 |
| chain-ipog-n64-v2-t2 | ok | 15 | 0.117 | 194.6 | 824.1 |
| chain-gnd-n8-v2-t2 | ok | 8 | 0.003466 | 5.909 | 742.6 |
| chain-gnd-n16-v2-t2 | ok | 10 | 0.02859 | 45.22 | 752.1 |
| chain-gnd-n32-v2-t2 | ok | 13 | 0.1838 | 240.9 | 808.8 |
| chain-gnd-n64-v2-t2 | ok | 16 | 1.053 | 1188 | 1501 |
| equality-ipog-n8-v2-t2 | ok | 2 | 0.0008378 | 2.388 | 743.1 |
| equality-ipog-n16-v2-t2 | ok | 2 | 0.009823 | 36.07 | 734.1 |
| equality-ipog-n32-v2-t2 | ok | 2 | 0.1632 | 534.1 | 738 |
| equality-ipog-n64-v2-t2 | ok | 2 | 2.722 | 8582 | 815.8 |
| equality-gnd-n8-v2-t2 | ok | 2 | 0.001555 | 3.637 | 727.9 |
| equality-gnd-n16-v2-t2 | ok | 2 | 0.01442 | 43.18 | 732.2 |
| equality-gnd-n32-v2-t2 | ok | 2 | 0.1843 | 561.3 | 753.1 |
| equality-gnd-n64-v2-t2 | ok | 2 | 2.843 | 8692 | 818 |
| equality-cheap-explanations-ipog-n8-v2-t2 | ok | 2 | 0.000503 | 0.9667 | 742.5 |
| equality-cheap-explanations-ipog-n16-v2-t2 | ok | 2 | 0.00309 | 7.801 | 744.5 |
| equality-cheap-explanations-ipog-n32-v2-t2 | ok | 2 | 0.02482 | 59.14 | 731.8 |
| equality-cheap-explanations-ipog-n64-v2-t2 | ok | 2 | 0.2071 | 487.1 | 829.1 |
| equality-cheap-explanations-gnd-n8-v2-t2 | ok | 2 | 0.001259 | 2.216 | 744.2 |
| equality-cheap-explanations-gnd-n16-v2-t2 | ok | 2 | 0.007465 | 14.91 | 727.1 |
| equality-cheap-explanations-gnd-n32-v2-t2 | ok | 2 | 0.04319 | 86.28 | 729.2 |
| equality-cheap-explanations-gnd-n64-v2-t2 | ok | 2 | 0.3269 | 597.1 | 881.3 |
| pattern-ipog-n8-v2-t2 | ok | 7 | 0.0002171 | 0.4318 | 741.3 |
| pattern-ipog-n16-v2-t2 | ok | 9 | 0.0007032 | 2.434 | 717 |
| pattern-gnd-n8-v2-t2 | ok | 8 | 0.001357 | 2.333 | 723.7 |
| pattern-gnd-n16-v2-t2 | ok | 10 | 0.004893 | 6.729 | 670.2 |
| macro-ipog-n8-v2-t2 | ok | 7 | 0.0001936 | 0.4314 | 728.8 |
| macro-ipog-n16-v2-t2 | ok | 9 | 0.000612 | 2.434 | 721.3 |
| macro-gnd-n8-v2-t2 | ok | 8 | 0.001404 | 2.333 | 735.2 |
| macro-gnd-n16-v2-t2 | ok | 10 | 0.00494 | 6.729 | 713.6 |
| lazy_scoped-ipog-n8-v2-t2 | ok | 7 | 0.0001768 | 0.4329 | 748.6 |
| lazy_scoped-ipog-n16-v2-t2 | ok | 9 | 0.000671 | 2.435 | 723.4 |
| lazy_scoped-gnd-n8-v2-t2 | ok | 8 | 0.001306 | 2.334 | 743.5 |
| lazy_scoped-gnd-n16-v2-t2 | ok | 10 | 0.004888 | 6.73 | 717.5 |
| global_budget-ipog-n8-v2-t2 | ok | 8 | 0.0003223 | 0.6275 | 731.8 |
| global_budget-ipog-n16-v2-t2 | ok | 11 | 0.001976 | 4.222 | 707.8 |
| global_budget-gnd-n8-v2-t2 | ok | 8 | 0.003658 | 6.985 | 733 |
| global_budget-gnd-n16-v2-t2 | ok | 10 | 0.04584 | 67.27 | 728.6 |
| core-ipog-n8-v2-t2 | ok | 9 | 7.737e-05 | 0.149 | 720.6 |
| core-ipog-n32-v2-t2 | ok | 13 | 0.0008005 | 4.929 | 715.2 |
| core-ipog-n64-v2-t2 | ok | 15 | 0.004021 | 34.59 | 725.4 |
| core-gnd-n8-v2-t2 | ok | 8 | 0.0007316 | 0.9341 | 755 |
| core-gnd-n32-v2-t2 | ok | 12 | 0.02431 | 11.86 | 715.3 |
| core-gnd-n64-v2-t2 | ok | 14 | 0.1692 | 64.98 | 719.6 |
| public-ipog-n8-v2-t2 | ok | 9 | 0.000113 | 0.1648 | 722.4 |
| public-ipog-n32-v2-t2 | ok | 13 | 0.0008725 | 4.99 | 713.9 |
| public-ipog-n64-v2-t2 | ok | 15 | 0.004176 | 34.72 | 815.4 |
| public-gnd-n8-v2-t2 | ok | 8 | 0.0007987 | 0.9487 | 752.9 |
| public-gnd-n32-v2-t2 | ok | 12 | 0.02448 | 11.91 | 754.1 |
| public-gnd-n64-v2-t2 | ok | 14 | 0.1693 | 65.1 | 750.1 |
| named-ipog-n8-v2-t2 | ok | 9 | 0.0001189 | 0.1739 | 757.5 |
| named-ipog-n32-v2-t2 | ok | 13 | 0.0009552 | 5.027 | 825.4 |
| named-ipog-n64-v2-t2 | ok | 15 | 0.004351 | 34.81 | 749.6 |
| named-gnd-n8-v2-t2 | ok | 8 | 0.0007784 | 0.9578 | 755.5 |
| named-gnd-n32-v2-t2 | ok | 12 | 0.02596 | 11.95 | 739.4 |
| named-gnd-n64-v2-t2 | ok | 14 | 0.1695 | 65.19 | 819.2 |
| positional-ipog-n8-v2-t2 | ok | 9 | 0.00018 | 0.1763 | 761.8 |
| positional-ipog-n32-v2-t2 | ok | 13 | 0.001039 | 5.037 | 762.8 |
| positional-ipog-n64-v2-t2 | ok | 15 | 0.004461 | 34.85 | 821 |
| positional-gnd-n8-v2-t2 | ok | 8 | 0.0008285 | 0.9601 | 833.8 |
| positional-gnd-n32-v2-t2 | ok | 12 | 0.02467 | 11.96 | 818.9 |
| positional-gnd-n64-v2-t2 | ok | 14 | 0.1699 | 65.23 | 754.5 |
| seed-ipog-n8-v2-t2 | ok | 9 | 0.0001192 | 0.1856 | 829 |
| seed-ipog-n32-v2-t2 | ok | 13 | 0.001094 | 7.066 | 816.9 |
| seed-ipog-n64-v2-t2 | ok | 15 | 0.006169 | 52.18 | 821.5 |
| seed-gnd-n8-v2-t2 | ok | 8 | 0.0006043 | 0.848 | 802.8 |
| seed-gnd-n32-v2-t2 | ok | 12 | 0.01789 | 10.99 | 803.2 |
| seed-gnd-n64-v2-t2 | ok | 14 | 0.1267 | 60.31 | 824.7 |
| stronger-ipog-n8-v2-t2 | ok | 14 | 0.0002184 | 0.4946 | 750.1 |
| stronger-ipog-n32-v2-t2 | ok | 14 | 0.001217 | 7.852 | 748.5 |
| stronger-ipog-n64-v2-t2 | ok | 15 | 0.006303 | 53.64 | 818.2 |
| stronger-gnd-n8-v2-t2 | ok | 14 | 0.002421 | 1.806 | 803 |
| stronger-gnd-n32-v2-t2 | ok | 15 | 0.02883 | 13.79 | 742.7 |
| stronger-gnd-n64-v2-t2 | ok | 15 | 0.1789 | 67.32 | 827 |
| coverage-ipog-n8-v2-t2 | ok |  | 5.083e-05 | 0.0522 | 774 |
| coverage-ipog-n16-v2-t2 | ok |  | 0.0001153 | 0.1899 | 780.1 |
| coverage-ipog-n32-v2-t2 | ok |  | 0.0003729 | 0.8335 | 774.8 |
| coverage-ipog-n64-v2-t2 | ok |  | 0.001286 | 4.276 | 747.6 |
| coverage-ipog-n128-v2-t2 | ok |  | 0.006143 | 25.5 | 754.3 |
| report-ipog-n8-v2-t2 | ok | 9 | 0.0003081 | 0.3532 | 745.3 |
| report-ipog-n16-v2-t2 | ok | 11 | 0.002024 | 3.141 | 757.2 |
| report-ipog-n32-v2-t2 | ok | 13 | 0.01597 | 32.1 | 761.4 |
| report-ipog-n64-v2-t2 | ok | 15 | 0.1922 | 335.5 | 835.3 |
| report-ipog-n128-v2-t2 | rss_limit |  |  |  | 2184 |
| collect-ipog-n8-v2-t2 | ok |  | 3.459e-06 | 0.0006561 | 759.3 |
| collect-ipog-n16-v2-t2 | ok |  | 5.417e-06 | 0.00148 | 758.6 |
| collect-ipog-n32-v2-t2 | ok |  | 5.292e-06 | 0.00351 | 774.3 |
| collect-ipog-n64-v2-t2 | ok |  | 4.917e-06 | 0.007904 | 819.9 |
| collect-ipog-n128-v2-t2 | ok |  | 5.25e-06 | 0.01962 | 820.3 |
| iterate-ipog-n8-v2-t2 | ok |  | 3.834e-06 | 3.052e-05 | 753.9 |
| iterate-ipog-n16-v2-t2 | ok |  | 3.833e-06 | 3.052e-05 | 755.7 |
| iterate-ipog-n32-v2-t2 | ok |  | 5.916e-06 | 4.578e-05 | 755.6 |
| iterate-ipog-n64-v2-t2 | ok |  | 3.333e-05 | 0.01561 | 758.5 |
| iterate-ipog-n128-v2-t2 | ok |  | 6.667e-05 | 0.03532 | 756.5 |
| export-ipog-n8-v2-t2 | ok |  | 4.208e-05 | 0.02135 | 793 |
| export-ipog-n16-v2-t2 | ok |  | 9.65e-05 | 0.05438 | 730.5 |
| export-ipog-n32-v2-t2 | ok |  | 0.0002178 | 0.133 | 815.5 |
| export-ipog-n64-v2-t2 | ok |  | 0.0005929 | 0.3136 | 724 |
| export-ipog-n128-v2-t2 | ok |  | 0.001902 | 0.7189 | 827.5 |
| upgrade-ipog-n8-v2-t2 | ok | 18 | 0.0002458 | 0.6686 | 790.8 |
| upgrade-ipog-n16-v2-t2 | ok | 26 | 0.0018 | 9.817 | 800.5 |
| upgrade-ipog-n32-v2-t2 | ok | 35 | 0.03349 | 149.6 | 886.5 |
| upgrade-ipog-n64-v2-t2 | ok | 45 | 0.6231 | 2323 | 1415 |
| topup-ipog-n8-v2-t2 | ok | 9 | 9.425e-05 | 0.1525 | 791.4 |
| topup-ipog-n16-v2-t2 | ok | 11 | 0.0002428 | 0.8196 | 788 |
| topup-ipog-n32-v2-t2 | ok | 13 | 0.000814 | 5.29 | 771.4 |
| topup-ipog-n64-v2-t2 | ok | 15 | 0.004348 | 38.44 | 744.1 |
| audit_half-ipog-n8-v2-t2 | ok |  | 0.0001316 | 0.08232 | 738.4 |
| audit_half-ipog-n16-v2-t2 | ok |  | 0.0002303 | 0.3511 | 783.8 |
| audit_half-ipog-n32-v2-t2 | ok |  | 0.0006618 | 1.566 | 723.7 |
| audit_half-ipog-n64-v2-t2 | ok |  | 0.002606 | 8.087 | 756 |
| audit_empty-ipog-n8-v2-t2 | ok |  | 0.0001962 | 0.2463 | 719.5 |
| audit_empty-ipog-n16-v2-t2 | ok |  | 0.0007687 | 1.302 | 751 |
| audit_empty-ipog-n32-v2-t2 | ok |  | 0.003266 | 7.66 | 758.2 |
| audit_empty-ipog-n64-v2-t2 | ok |  | 0.01612 | 49.82 | 729.9 |
| tabulated_scope-ipog-n8-v4-t2 | ok | 59 | 0.00254 | 5.949 | 720.7 |
| tabulated_scope-ipog-n16-v4-t2 | ok | 59 | 0.00554 | 20.79 | 734.4 |
| tabulated_scope-gnd-n8-v4-t2 | ok | 62 | 0.03546 | 56.03 | 758.5 |
| tabulated_scope-gnd-n16-v4-t2 | ok | 62 | 0.09834 | 114.2 | 833.5 |
| lazy_scope-ipog-n8-v4-t2 | ok | 59 | 0.003959 | 7.468 | 728.5 |
| lazy_scope-ipog-n16-v4-t2 | ok | 59 | 0.007741 | 22.3 | 713.1 |
| lazy_scope-gnd-n8-v4-t2 | ok | 62 | 0.03783 | 56.39 | 756.7 |
| lazy_scope-gnd-n16-v4-t2 | ok | 62 | 0.1087 | 114.4 | 828.1 |
| invalid-ipog-n4-v2-t2 | ok | 14 | 0.000141 | 0.1552 | 825.3 |
| invalid-ipog-n8-v2-t2 | ok | 25 | 0.00034 | 0.7066 | 746.2 |
| invalid-ipog-n16-v2-t2 | ok | 43 | 0.001043 | 3.69 | 716.2 |
| invalid-ipog-n32-v2-t2 | ok | 77 | 0.004833 | 22.15 | 719.7 |
| invalid-gnd-n4-v2-t2 | ok | 14 | 0.0003909 | 0.7405 | 726.8 |
| invalid-gnd-n8-v2-t2 | ok | 24 | 0.001393 | 2.828 | 728.3 |
| invalid-gnd-n16-v2-t2 | ok | 42 | 0.006617 | 11.57 | 736.4 |
| invalid-gnd-n32-v2-t2 | ok | 76 | 0.04395 | 52.97 | 713.8 |
| partition-ipog-n8-v2-t2 | ok | 9 | 9.871e-05 | 0.1729 | 815.9 |
| partition-ipog-n32-v2-t2 | ok | 13 | 0.000844 | 5.035 | 715 |
| partition-ipog-n64-v2-t2 | ok | 15 | 0.005337 | 34.83 | 733.3 |
| realize-ipog-n8-v2-t2 | ok |  | 1.962e-05 | 0.003769 | 794.5 |
| realize-ipog-n32-v2-t2 | ok |  | 7.433e-05 | 0.01486 | 714.2 |
| realize-ipog-n64-v2-t2 | ok |  | 0.0001479 | 0.09277 | 757.5 |
| factorial-ipog-n8-v2-t2 | ok | 256 | 0.0004515 | 0.44 | 709.2 |
| factorial-ipog-n12-v2-t2 | ok | 4096 | 0.007971 | 9.522 | 732.4 |
| factorial-ipog-n16-v2-t2 | ok | 65536 | 0.1523 | 188.5 | 837.3 |
| factorial-ipog-n20-v2-t2 | resource_limit |  |  |  | 730.2 |
| excursion-ipog-n8-v2-t2 | ok | 37 | 0.0001499 | 0.1326 | 720.6 |
| excursion-ipog-n32-v2-t2 | ok | 529 | 0.00324 | 3.741 | 736 |
| excursion-ipog-n64-v2-t2 | ok | 2081 | 0.0201 | 26.83 | 719.5 |
| excursion-ipog-n128-v2-t2 | ok | 8257 | 0.1328 | 187.2 | 745.7 |
| gnd-candidates10-gnd10-n8-v2-t2 | ok | 8 | 0.0002341 | 0.3229 | 742.1 |
| gnd-candidates10-gnd10-n16-v2-t2 | ok | 11 | 0.001072 | 1.459 | 718 |
| gnd-candidates10-gnd10-n32-v2-t2 | ok | 13 | 0.005705 | 8.225 | 798.8 |
| gnd-candidates10-gnd10-n64-v2-t2 | ok | 15 | 0.03827 | 56.33 | 730.6 |
| alldifferent-sat-ipog-n3-v3-t2 | ok |  | 1.971e-05 | 0.004211 | 718.1 |
| alldifferent-unsat-ipog-n4-v3-t2 | ok |  | 2.375e-05 | 0.006409 | 700 |
| alldifferent-sat-ipog-n4-v4-t2 | ok |  | 1.696e-05 | 0.0056 | 739.7 |
| alldifferent-unsat-ipog-n5-v4-t2 | ok |  | 3.008e-05 | 0.01535 | 736.2 |
| alldifferent-sat-ipog-n5-v5-t2 | ok |  | 1.725e-05 | 0.007919 | 745.4 |
| alldifferent-unsat-ipog-n6-v5-t2 | ok |  | 9.808e-05 | 0.05554 | 723.3 |
| alldifferent-sat-ipog-n6-v6-t2 | ok |  | 1.779e-05 | 0.009689 | 709.2 |
| alldifferent-unsat-ipog-n7-v6-t2 | ok |  | 0.0004176 | 0.3047 | 714.5 |
| alldifferent-sat-ipog-n7-v7-t2 | ok |  | 1.946e-05 | 0.01157 | 722.7 |
| alldifferent-unsat-ipog-n8-v7-t2 | ok |  | 0.002928 | 2.097 | 722.2 |
| alldifferent-sat-ipog-n8-v8-t2 | ok |  | 2.279e-05 | 0.0143 | 710.5 |
| alldifferent-unsat-ipog-n9-v8-t2 | resource_limit |  | 0.02112 | 15.27 | 740.1 |
| alldifferent-sat-ipog-n9-v9-t2 | ok |  | 2.642e-05 | 0.0209 | 738.8 |
| alldifferent-unsat-ipog-n10-v9-t2 | skipped_after_limit |  |  |  |  |
