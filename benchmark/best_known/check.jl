# Spot checks of the best-known lookup against the plan's tables: the appendix
# ("t2v2 gives 6, 8, 10, 11, 12, 13 and 14 for k = 8, 32, ..., 1,024"), §2.1,
# §2.9, §5.3 and §5.4. Exits nonzero if any differs. Run from the repository root:
#
#     julia --project=. --startup-file=no benchmark/best_known/check.jl
include(joinpath(@__DIR__, "BestKnown.jl"))
using .BestKnown

const CHECKS = [
    # (t, v, k, best known, where in design/20261003_solver_plan.md)
    [(2, 2, k, n, "appendix, t2v2") for (k, n) in zip((8, 32, 64, 128, 256, 512, 1024), (6, 8, 10, 11, 12, 13, 14))]...,
    (2, 8, 9, 64, "appendix, t2v8's first line"), (2, 3, 4, 9, "appendix, t2v3's first line"),
    (2, 4, 8, 22, "§2.1, 8 × 4"), (2, 8, 8, 64, "§2.1, 8 × 8"), (2, 16, 8, 256, "§2.1, 8 × 16"),
    (2, 32, 8, 1024, "§2.1, 8 × 32 (derived: no page for v = 32)"),
    (2, 64, 8, 4096, "§2.1, 8 × 64 (derived: no page for v = 64)"),
    (2, 8, 10, 76, "§2.1, 10 × 8"), (2, 3, 12, 15, "§2.1, 12 × 3"), (2, 4, 16, 27, "§2.1, 16 × 4"),
    (2, 4, 32, 31, "§2.1, 32 × 4"), (2, 4, 64, 36, "§2.1, 64 × 4"), (2, 4, 128, 40, "§2.1, 128 × 4"),
    (3, 3, 12, 45, "§2.1, 12 × 3 at t = 3"), (4, 3, 12, 189, "§2.1, 12 × 3 at t = 4"),
    (5, 3, 12, 483, "§2.1, 12 × 3 at t = 5"), (4, 4, 15, 508, "§2.1, 15 × 4 at t = 4"),
    (4, 2, 20, 39, "§2.9"), (5, 2, 20, 99, "§2.9"), (6, 2, 20, 300, "§2.9"),
    (4, 3, 20, 271, "§2.9"), (5, 3, 20, 1108, "§2.9"), (6, 3, 20, 4006, "§2.9"),
    (4, 4, 20, 748, "§2.9"), (5, 4, 20, 4060, "§2.9"),
    (2, 6, 3, 36, "§5.4, 3 × 6"), (2, 2, 20, 8, "§5.4, 20 × 2"), (2, 4, 6, 19, "§5.4, 6 × 4"),
    (2, 5, 8, 33, "§5.4, 8 × 5"), (2, 5, 10, 36, "§5.4, 10 × 5"), (2, 5, 30, 45, "§5.4, 30 × 5"),
    (2, 6, 20, 61, "§5.4, 20 × 6"), (2, 5, 40, 49, "§5.3, 40 × 5"), (2, 7, 12, 71, "§5.3, 12 × 7"),
    (2, 10, 20, 155, "§5.3, 20 × 10"), (3, 6, 8, 301, "§5.3, 8 × 6 at t = 3 (the snapshot's 301)"),
]

bad = 0
for (t, v, k, expected, where) in CHECKS
    b = best_known(t, v, k)
    ok = b !== nothing && b.N == expected
    global bad += !ok
    println(rpad(where, 44), " t=$t v=$v k=$k: ", b === nothing ? "none" : "$(b.N) ($(b.source); $(b.status))",
            ok ? "" : "   EXPECTED $expected")
end
for (what, got, expected) in (("lower_bound(3, [7, 5, 4])", lower_bound(3, [7, 5, 4]), 140),
                              ("lower_bound(2, 4, 8)", lower_bound(2, 4, 8), 16),
                              ("best_known(2, 2, 30_000), past the table", best_known(2, 2, 30_000), nothing),
                              ("best_known(2, 32, 40), no page and no derived size", best_known(2, 32, 40), nothing))
    ok = got == expected
    global bad += !ok
    println(rpad(what, 44), " ", got === nothing ? "nothing" : got, ok ? "" : "   EXPECTED $expected")
end
println(length(CHECKS) + 4 - bad, " of ", length(CHECKS) + 4, " checks agree")
exit(bad == 0 ? 0 : 1)
