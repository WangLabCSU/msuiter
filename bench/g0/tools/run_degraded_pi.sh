#!/bin/sh
# G0 authoritative `degraded` profile — 8-way arm-sharded parallel driver.
#
# Protocol compliance (adjudication §PI-5): profile=degraded, adapter=docker,
# provider=cosmic-file, F2/F3 frozen inputs derived by tools/g0-derive-inputs.R
# (bitwise identical to the 2026-10-07 14:01 smoke that proved the pipeline).
#
# Sharding discipline: cells are keyed `tool__arm__N` under a single cachedir
# (disjoint per arm) and judgment is a pure recomputation over the full cell
# set, so arm shards may run concurrently and the final serial pass hits the
# cache and emits the authoritative judgment/timings. Equivalence of this
# orchestration vs a serial run was rehearsed (mock adapter): judgment,
# coverage and Seeds outputs byte-equal after timestamp normalisation.
set -eu
# dirname (not `dir`: a GNU ls alias absent on darwin -- a failed command
# substitution here would silently cd elsewhere under set -e).
cd "$(dirname "$0")/.."   # -> bench/g0

export G0_SIGNATURES_PATH="$PWD/cache/g0_signatures.csv"
export G0_CATALOG_PATH="$PWD/cache/g0_catalog.csv"
test -s "$G0_SIGNATURES_PATH" || { echo "F3 signatures missing — run tools/g0-derive-inputs.R"; exit 2; }
test -s "$G0_CATALOG_PATH"    || { echo "F3 catalog missing — run tools/g0-derive-inputs.R"; exit 2; }

CACHE=cache/degraded_pi
SH_OUT=cache/degraded_pi/shard_out
rm -rf "$SH_OUT"; mkdir -p "$SH_OUT/logs"

common="--profile degraded --adapter docker --provider cosmic-file --cachedir $CACHE"
pids=""
names=""
shard() {  # shard <tag> <arms...>
  tag=$1; shift
  arms=$(printf '%s,' "$@" | sed -E 's/,$//')
  python3 run_grid.py $common --arms "$arms" \
    --outdir "$SH_OUT/$tag" > "$SH_OUT/logs/$tag.log" 2>&1 &
  pids="$pids $!"; names="$names $tag"
}

# Balanced over the measured per-cell rates (STL is the long pole; the
# 1e5/1e6 comp_pole tier is its own shard as the critical path).
shard main            main
shard comp_clock_only comp_clock_only
shard comp_mmr        comp_mmr
shard comp_flat_triple comp_flat_triple
shard comp_strong_flat comp_strong_flat
shard nb              nb
shard clock_sparse    clock sparse
shard comp_pole       comp_pole

fail=""
set +e
for p in $pids; do wait "$p" || fail="$fail $p"; done
set -e
[ -z "$fail" ] || { echo "SHARD FAILURE:$fail (see $SH_OUT/logs)"; exit 1; }

# Final serial pass: full grid over the now-complete cache → authoritative
# judgment; tool invocations are cache hits, so this step is minutes.
ts=$(date +%Y%m%d-%H%M%S)
OUT=../results/docker_degraded_pi_$ts
python3 run_grid.py $common --outdir "$OUT"
# Roll shard-level tool timings into the authoritative outdir (the cache-hit
# pass itself records none; every measured second stays attributable).
i=0
for tag in main comp_clock_only comp_mmr comp_flat_triple comp_strong_flat nb clock_sparse comp_pole; do
  for f in "$SH_OUT/$tag"/timings_degraded_*.csv; do
    [ -e "$f" ] || continue
    if [ "$i" -eq 0 ]; then cp "$f" "$OUT/timings_sharded_master.csv"; i=1
    else tail -n +2 "$f" >> "$OUT/timings_sharded_master.csv"; fi
  done
done
echo "AUTHORITATIVE-RUN-COMPLETE outdir=$OUT"
