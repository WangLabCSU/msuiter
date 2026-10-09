#!/bin/sh
# U-M7-03 competitor driver — STRICT SERIAL (fan-out=1), one cachedir.
#
# This file is the RB-08 cure for the Phase-B pass-1 SHARD-OOM defect
# (phase_b_SHARD-OOM_DEFECT.json): the previous version backgrounded eight
# arm-shards at once, and ten containers' worth of self-sizing process
# pools (joblib/LokyBackend, future::MultisessionFuture — beyond the frozen
# BLAS/OpenMP thread caps) over-committed the 10-vCPU VM. Uniformity is
# now enforced by construction, in three layers:
#
#   1. DRIVER: every cell invocation is a foreground process, one at a
#      time. There is no `&` in this file, and none may be added.
#   2. PRE-FLIGHT ASSERT (run_bench, per cell): the driver refuses to
#      launch a cell while ANY measurement-image container is live
#      (`docker ps` census in tools/matrix_governance), outcome logged to
#      the cachedir preflight_log.jsonl — auditable, not just raised.
#   3. WORKER CENSUS + FLOOR GATE (run_bench, per cell): `docker top`
#      sampling records the observed pool width OUTSIDE the four-file
#      guard (cachedir/census/<cell>/census.json), and any cell exceeding
#      3x its pre-registered uncontended floor is flagged defect-floor ->
#      the pass exits non-zero and this driver halts (defect candidates
#      are reported, never averaged away).
#
# The final serial pass then hits the hash+four-file guard and re-emits
# the fairness attestation + timings without re-invoking any competitor;
# the rolled timings_sharded_master.csv keeps every measured second
# attributable (§4.4/§4.5).
#
# Thread caps: injected inside every composed docker command by
# competitors/docker_cmd.py (frozen THREAD_CAPS before the image token) —
# the positional cure for the G0 over-subscription OOM storm; nothing here
# may add or reorder caps.
#
# skip-not-skip: with --adapter docker and an image whose digest is still
# PENDING-VERIFY, the run ends in SKIP and exits non-zero by design. A
# missing environment must be seen, never tallied green (memo §6).
#
# Tunables (environment): M7_PROFILE=degraded M7_ADAPTER=docker
#   M7_COMPETITORS=sigminer,sigprofiler M7_PROVIDER=synthetic
set -eu
cd "$(dirname "$0")/.."   # -> bench/m7

PROFILE=${M7_PROFILE:-degraded}
ADAPTER=${M7_ADAPTER:-docker}
COMPETITORS=${M7_COMPETITORS:-sigminer,sigprofiler}
PROVIDER=${M7_PROVIDER:-synthetic}
CACHE=cache/bench_${PROFILE}_${ADAPTER}
SH_OUT="$CACHE/shard_out"
rm -rf "$SH_OUT"; mkdir -p "$SH_OUT/logs"

common="--profile $PROFILE --adapter $ADAPTER --provider $PROVIDER"
common="$common --competitors $COMPETITORS --cachedir $CACHE"

# Arm balance mirrors the G0 closure driver (STL-pole analog: the heavy
# comp_pole tier rides as its own critical path). Order = light-first: a
# defect candidate in a cheap cell kills the pass before the heavy tier
# spends hours. EVERY shard runs foreground — fan-out=1, no exceptions.
shard() {                       # shard <tag> <arms...>
  tag=$1; shift
  arms=$(printf '%s,' "$@" | sed -E 's/,$//')
  echo "[driver] serial shard $tag (arms=$arms) starting $(date -u +%H:%M:%S)"
  if ! python3 run_bench.py $common --arms "$arms" --shard-tag "$tag" \
      --outdir "$SH_OUT/$tag" > "$SH_OUT/logs/$tag.log" 2>&1; then
    echo "SHARD FAILURE: $tag (see $SH_OUT/logs/$tag.log) — halting per" \
         "RB-08(7): defect candidates are reported, not outrun" >&2
    exit 1
  fi
  echo "[driver] serial shard $tag complete $(date -u +%H:%M:%S)"
}

shard main             main
shard comp_clock_only  comp_clock_only
shard comp_mmr         comp_mmr
shard comp_flat_triple comp_flat_triple
shard comp_strong_flat comp_strong_flat
shard nb               nb
shard clock_sparse     clock sparse
shard comp_pole        comp_pole

# Final serial pass: full grid over the now-complete cache -> authoritative
# fairness attestation + timings; every invocation is a cache hit.
ts=$(date -u +%Y%m%d-%H%M%S)
OUT="../results/docker_m7_${PROFILE}_${ts}"
python3 run_bench.py $common --outdir "$OUT"
# Roll shard-level timings into the authoritative outdir (the cache-hit pass
# itself records none; every measured second stays attributable).
i=0
for tag in main comp_clock_only comp_mmr comp_flat_triple comp_strong_flat \
           nb clock_sparse comp_pole; do
  for f in "$SH_OUT/$tag"/timings_m7_*.csv; do
    [ -e "$f" ] || continue
    if [ "$i" -eq 0 ]; then cp "$f" "$OUT/timings_sharded_master.csv"; i=1
    else tail -n +2 "$f" >> "$OUT/timings_sharded_master.csv"; fi
  done
done
echo "AUTHORITATIVE-RUN-COMPLETE outdir=$OUT"
