#!/bin/sh
# P6 authoritative campaign ignition -- the lane manifest SS5 launcher
# (/tmp/p6lane/logs/00-manifest-preregistration.md: "Exactly ONE authoritative
# campaign ignition, outdir bench/results/p6_regen_<UTCstamp>/, fresh
# campaign cachedir bench/m7/cache/p6_regen_<UTCstamp>/, floor gate ON").
#
# This file is a STRUCTURAL SIBLING of the proven tools/run_m7_bench.sh (the
# RB-08 strict-serial cure): same shards, same order, same pre-flight and
# census layers (they live in run_bench itself), same single UTC stamp binding
# cachedir and outdir, --floor-gate ON by default (the calibration probes ran
# it OFF -- the asymmetry is the law, not a convenience). The deltas are the
# banked p6_regen_* naming and the required competitor list: this campaign
# measures the eight-tool set (both reference arms + the six P6 arms), and
# silence on --competitors is a misconfiguration, not a default.
#
# FAN-OUT LAW: fan-out=1 by construction. There is no `&` in this file and
# none may be added (the RB-08 SHARD-OOM postmortem seal extends here by
# discipline; the text seal test_driver_is_fan_out_free_by_text binds the
# reference driver). Launch it detached from the OUTSIDE:
#   M7_COMPETITORS=... M7_HW_PROFILE='10 vCPU / 8 GB class' \
#     nohup sh tools/p6_ignition.sh > /tmp/p6lane/logs/<stamp>.ignition.log 2>&1
#
# DEATH PROTOCOL (SS5 resume law -- the ONLY legal resume shape): re-invoke
# with M7_REUSE_CACHE=<the campaign cachedir> and, per the witnessed-cell
# inventory in the shard logs, M7_SKIP_SHARDS="tag tag ..." for shards whose
# cells are all witnessed. NO new cachedir, NO new outdir stamp: the single
# ignition identity survives its deaths. Every resume is recorded in the
# devlog with its witnessed-cell forensics.
set -eu
cd "$(dirname "$0")/.."   # -> bench/m7

if [ -z "${M7_COMPETITORS:-}" ]; then
  echo "M7_COMPETITORS unset: the P6 campaign is the eight-tool set; an" \
       "accidental legacy-pair-only campaign must not masquerade as the" \
       "authoritative pass" >&2
  exit 2
fi
if [ -z "${M7_HW_PROFILE:-}" ]; then
  echo "M7_HW_PROFILE unset: the authoritative final pass would refuse to" \
       "file (U-M7-04 GO-05) -- export the machine-class pin before ignition" >&2
  exit 2
fi
if [ -e /tmp/p6lane/.campaign-running ]; then
  # The marker is PID-bound: a clean crash leaves it behind but its holder is
  # dead, and the SS5 death protocol must remain invocable; a LIVE holder
  # means this really is a second concurrent campaign -- refused (the marker
  # is also the co-tenancy law's first line).
  mp=$(cat /tmp/p6lane/.campaign-running 2>/dev/null || echo "")
  if [ -n "$mp" ] && kill -0 "$mp" 2>/dev/null; then
    echo "second ignition refused: campaign pid $mp is alive (single-ignition" \
         "law, also a co-tenancy law)" >&2
    exit 2
  fi
  echo "[ignition] adopting marker of dead pid ${mp:-?} (death protocol)"
fi

PROFILE=${M7_PROFILE:-degraded}
ADAPTER=${M7_ADAPTER:-docker}
PROVIDER=${M7_PROVIDER:-synthetic}
FLOOR_GATE=${M7_FLOOR_GATE:-on}
SKIP_SHARDS=${M7_SKIP_SHARDS:-}

ts=$(date -u +%Y%m%d-%H%M%S)
if [ -n "${M7_REUSE_CACHE:-}" ]; then
  CACHE="$M7_REUSE_CACHE"
  if ! OUT=$(cat "$CACHE/.p6_outdir" 2>/dev/null) || [ -z "$OUT" ]; then
    echo "M7_REUSE_CACHE=$M7_REUSE_CACHE carries no .p6_outdir pointer --" \
         "resuming would invent a second authoritative outdir" >&2
    exit 2
  fi
  echo "[ignition] RESUME (witnessed-cell protocol): cachedir=$CACHE outdir=$OUT"
else
  CACHE="cache/p6_regen_$ts"
  OUT="../results/p6_regen_$ts"
  mkdir -p "$CACHE"
  echo "$OUT" > "$CACHE/.p6_outdir"
fi
echo $$ > /tmp/p6lane/.campaign-running

SH_OUT="$CACHE/shard_out"
if [ -z "${M7_REUSE_CACHE:-}" ]; then
  rm -rf "$SH_OUT"          # fresh ignition: no shard bytes may pre-exist
fi                          # resume: witnessed shard tables are PRESERVED
mkdir -p "$SH_OUT/logs"

common="--profile $PROFILE --adapter $ADAPTER --provider $PROVIDER"
common="$common --competitors $M7_COMPETITORS --cachedir $CACHE"
common="$common --floor-gate $FLOOR_GATE"

skip_p() {  # skip_p <tag>: shard fully witnessed on resume
  for s in $SKIP_SHARDS; do [ "$s" = "$1" ] && return 0; done
  return 1
}

shard() {                       # shard <tag> <arms...>  -- foreground only
  tag=$1; shift
  if skip_p "$tag"; then
    echo "[ignition] shard $tag SKIPPED (witnessed-cell resume law)"
    return 0
  fi
  arms=$(printf '%s,' "$@" | sed -E 's/,$//')
  echo "[ignition] serial shard $tag (arms=$arms) starting $(date -u +%H:%M:%S)"
  if ! python3 run_bench.py $common --arms "$arms" --shard-tag "$tag" \
      --outdir "$SH_OUT/$tag" > "$SH_OUT/logs/$tag.log" 2>&1; then
    echo "SHARD FAILURE: $tag (see $SH_OUT/logs/$tag.log) -- halting per" \
         "RB-08(7): defect candidates are reported, not outrun. Resume is" \
         "legal ONLY via M7_REUSE_CACHE + M7_SKIP_SHARDS (death protocol)" >&2
    rm -f /tmp/p6lane/.campaign-running
    exit 1
  fi
  echo "[ignition] serial shard $tag complete $(date -u +%H:%M:%S)"
}

# Arm balance identical to the proven reference driver: light-first, so a
# defect candidate in a cheap cell halts the pass before the heavy pole tier
# spends hours. 8 tools x 21 classes, one container at a time, machine-wide.
shard main             main
shard comp_clock_only  comp_clock_only
shard comp_mmr         comp_mmr
shard comp_flat_triple comp_flat_triple
shard comp_strong_flat comp_strong_flat
shard nb               nb
shard clock_sparse     clock sparse
shard comp_pole        comp_pole

# Final serial pass: full grid over the now-complete cache -> authoritative
# fairness attestation + timings; every invocation is a cache hit. The
# hardware-pin authority gate lives in run_bench.main and refuses to file the
# authoritative table without the operator's M7_HW_PROFILE.
python3 run_bench.py $common --outdir "$OUT"
i=0
for tag in main comp_clock_only comp_mmr comp_flat_triple comp_strong_flat \
           nb clock_sparse comp_pole; do
  for f in "$SH_OUT/$tag"/timings_m7_*.csv; do
    [ -e "$f" ] || continue
    if [ "$i" -eq 0 ]; then cp "$f" "$OUT/timings_sharded_master.csv"; i=1
    else tail -n +2 "$f" >> "$OUT/timings_sharded_master.csv"; fi
  done
done
rm -f /tmp/p6lane/.campaign-running
echo "P6-AUTHORITATIVE-RUN-COMPLETE outdir=$OUT cachedir=$CACHE"
