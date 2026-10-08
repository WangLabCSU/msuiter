#!/bin/sh
# U-M7-02 smoke rehearsal (memo §10.4): prove the full sharded+serial
# orchestration over a tiny grid with the mock-style fourth spec, before any
# real competitor matrix runs.
#
# Evidence produced:
#   ① shard-vs-serial byte-equality of the authoritative cell outputs
#      (intervals.csv / errors.log / manifest.json byte-identical across the
#      sharded cache and the serial cache; timing.json is the documented
#      exclusion — it is the wall/jitter channel, its ATTRIBUTION is checked
#      instead: every measured second lands in timings_sharded_master.csv);
#   ② the final serial pass of the sharded tree is 100% cache hits
#      (status cached, 0 seconds) — the §4.4 cache-hit recompute idiom;
#   ③ Seeds.txt row-sets identical between the two orchestration modes.
#
# The mock drives the SAME measurement wrapper (adapters/m7_entry.py) and
# the SAME hash+four-file guard as the container path.
set -eu
cd "$(dirname "$0")/.."   # -> bench/m7

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/m7rehearsal_XXXXXX")
trap 'rm -rf "$ROOT"' exit
A="$ROOT/sharded"; B="$ROOT/serial"
mkdir -p "$A/logs"

common="--profile smoke --adapter mock --competitors mock"
# tiny grid: profile smoke = main{N100,N1000} + comp_clock_only{N1000}
# + nb{N1000} @ 5 reps ⇒ 4 cells; sharded one-per-arm, concurrent.
pids=""
for arm in main comp_clock_only nb; do
  python3 run_bench.py $common --arms "$arm" --shard-tag "$arm" \
      --cachedir "$A/cache" --outdir "$A/out_$arm" > "$A/logs/$arm.log" 2>&1 &
  pids="$pids $!"
done
set +e
for p in $pids; do wait "$p" || { echo "SHARD FAILED (see $A/logs)" >&2; exit 1; }; done
set -e
i=0
for arm in main comp_clock_only nb; do
  for f in "$A/out_$arm"/timings_m7_*.csv; do
    [ -e "$f" ] || continue
    if [ "$i" -eq 0 ]; then cp "$f" "$A/timings_sharded_master.csv"; i=1
    else tail -n +2 "$f" >> "$A/timings_sharded_master.csv"; fi
  done
done
python3 run_bench.py $common --cachedir "$A/cache" --outdir "$A/final"
python3 run_bench.py $common --cachedir "$B/cache" --outdir "$B/final"

python3 tools/verify_rehearsal.py "$A" "$B"
echo "MOCK-REHEARSAL-OK root=$ROOT (removed on exit)"
