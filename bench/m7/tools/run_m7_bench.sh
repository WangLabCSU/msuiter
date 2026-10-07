#!/bin/sh
# U-M7-02 sharded competitor driver — arm shards over one cachedir, then a
# serial cache-hit pass emits the authoritative outputs (minutes, not hours).
#
# Mirrors bench/g0/tools/run_degraded_pi.sh: cells are keyed
# <competitor>__<arm>__N<n> under one cachedir (disjoint per arm), the
# final serial pass hits the hash+four-file guard and re-emits the
# fairness attestation + timings without re-invoking any competitor, and
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

pids=""; names=""
shard() {                       # shard <tag> <arms...>
  tag=$1; shift
  arms=$(printf '%s,' "$@" | sed -E 's/,$//')
  python3 run_bench.py $common --arms "$arms" --shard-tag "$tag" \
      --outdir "$SH_OUT/$tag" > "$SH_OUT/logs/$tag.log" 2>&1 &
  pids="$pids $!"; names="$names $tag"
}

# Arm balance mirrors the G0 closure driver (STL-pole analog: the heavy
# comp_pole tier rides as its own critical path).
shard main             main
shard comp_clock_only  comp_clock_only
shard comp_mmr         comp_mmr
shard comp_flat_triple comp_flat_triple
shard comp_strong_flat comp_strong_flat
shard nb               nb
shard clock_sparse     clock sparse
shard comp_pole        comp_pole

fail=""
set +e
for p in $pids; do wait "$p" || fail="$fail $p"; done
set -e
[ -z "$fail" ] || { echo "SHARD FAILURE:$fail (see $SH_OUT/logs)" >&2; exit 1; }

# Final serial pass: full grid over the now-complete cache → authoritative
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
