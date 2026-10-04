#!/bin/sh
# The timing baseline of the solver plan's Phase 0 (design/20261003_solver_plan.md §8):
# the October 3 study's five job lists (STUDY.md), re-run on the source at 2798ecf with
# the study's harness, limits and package versions. Run it on a quiet machine, from the
# repository root:
#
#     sh benchmark/scaling/baseline_2798ecf.sh [NAME]
#
# Results: benchmark/scaling/results/NAME/{main,followup,phases,heap-hint,heap-hint-512m},
# each with results.json, summary.md, flat.csv and the evidence archives, and
# NAME/all_measurements.csv across them (default NAME: 2798ecf-baseline-YYYYMMDD).
#
# How long: the study's own wall clock at 0bc6bae on the Apple M2 was 54.5 minutes for
# the main grid (245 jobs), 17.9 for the follow-up (57), 3.4 for the phases (14), 0.9 and
# 3.6 for the two heap hints (4 each): 80 minutes (results/2026100*/results.json,
# metadata started/finished). 2798ecf has the same row counts at the points re-run
# (plan §2.1), so expect about 80-90 minutes, plus a few minutes to precompile.
#
# What it does, and why:
# - A detached worktree of 2798ecf (BASELINE_TREE, default ../UTD-baseline-2798ecf beside
#   the repository): its src/ is what is measured, and its benchmark/scaling/ is the
#   study's harness. 2798ecf's worker.jl is byte-identical to the one the study ran, its
#   default grid is the study's 245 specs, and its run.py differs only in bookkeeping
#   (recorded Julia flags, environment events, more fingerprinted files).
# - The study's Manifest.toml, taken from results/20261003-m2-v2/protocol_snapshot.zip,
#   so the dependencies are the study's (JSON 1.9.0, Combinatorics 1.0.3).
# - The study's limits: a 2,048 MiB RSS guard everywhere; 20 s warm stages, 60 s first
#   call and setup, 180 s per job for the main grid, the follow-up and the phases; 60 s,
#   120 s and 300 s with the heap hints. run.py's other defaults are the study's.
#
# Set JULIA to pick a Julia (the study used 1.13.1), DRY_RUN=1 to print the commands.
set -eu
COMMIT=2798ecf
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME=${1:-$COMMIT-baseline-$(date +%Y%m%d)}
OUT=$ROOT/benchmark/scaling/results/$NAME
TREE=${BASELINE_TREE:-$(dirname "$ROOT")/UTD-baseline-$COMMIT}
JULIA=${JULIA:-julia}
run() { echo "+ $*"; [ -n "${DRY_RUN:-}" ] || "$@"; }

if [ ! -d "$TREE" ]; then run git -C "$ROOT" worktree add --detach "$TREE" "$COMMIT"; fi
if [ -z "${DRY_RUN:-}" ]; then
    [ "$(git -C "$TREE" rev-parse --short=7 HEAD)" = "$COMMIT" ] || { echo "$TREE is not at $COMMIT" >&2; exit 1; }
    [ -z "$(git -C "$TREE" status --porcelain --untracked-files=no)" ] || { echo "$TREE has local changes" >&2; exit 1; }
    [ -e "$OUT" ] && { echo "$OUT exists; choose another NAME" >&2; exit 1; }
    unzip -p "$ROOT/benchmark/scaling/results/20261003-m2-v2/protocol_snapshot.zip" protocol/Manifest.toml > "$TREE/Manifest.toml"
fi
run "$JULIA" --project="$TREE" --startup-file=no -e 'using Pkg; Pkg.instantiate(); using UnitTestDesign; println(VERSION)'

S=$TREE/benchmark/scaling
run mkdir -p "$OUT"
# What the machine was doing: the baseline is only as quiet as this says.
[ -n "${DRY_RUN:-}" ] || { date; uptime; sysctl -n hw.model machdep.cpu.brand_string 2>/dev/null || true
                           "$JULIA" --version; git -C "$TREE" rev-parse HEAD; } > "$OUT/machine.txt"
run python3 "$S/run.py" --julia "$JULIA" --stage-seconds 20 --out "$OUT/main"
run python3 "$S/run.py" --julia "$JULIA" --stage-seconds 20 --adapter "$S/bench12_adapter.jl" \
    --specs "$S/followup_specs.json" --out "$OUT/followup"
run python3 "$S/run.py" --julia "$JULIA" --stage-seconds 20 --adapter "$S/bench12_adapter.jl" \
    --adapter "$S/phase_adapter.jl" --specs "$S/phase_specs.json" --out "$OUT/phases"
run python3 "$S/run.py" --julia "$JULIA" --specs "$S/heap_specs.json" --julia-arg=--heap-size-hint=1G \
    --stage-seconds 60 --cold-seconds 120 --job-seconds 300 --out "$OUT/heap-hint"
run python3 "$S/run.py" --julia "$JULIA" --specs "$S/heap_specs.json" --julia-arg=--heap-size-hint=512M \
    --stage-seconds 60 --cold-seconds 120 --job-seconds 300 --out "$OUT/heap-hint-512m"

# Evidence archives with the measured tree's own summarize.py, whose root holds the
# measured sources; then the flat CSVs with this checkout's, which adds the plan §7.3
# columns (rows over the best known and over the bound, first-call time).
for study in main followup phases heap-hint heap-hint-512m; do
    run python3 "$S/summarize.py" "$OUT/$study/results.json" --out "$OUT/$study/flat.csv" --archive
done
run python3 "$S/phases.py" "$OUT/phases/results.json" --out "$OUT/phases/native_phases.csv"
run python3 "$ROOT/benchmark/scaling/summarize.py" "$OUT/main/results.json" "$OUT/followup/results.json" \
    "$OUT/phases/results.json" "$OUT/heap-hint/results.json" "$OUT/heap-hint-512m/results.json" \
    --out "$OUT/all_measurements.csv"
echo "baseline: $OUT"
