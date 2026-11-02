#!/bin/sh
# G0 authoritative `primary` profile — the ONE authoritative ignition of the
# paper's quantitative spine (first coverage-measured intervals claim).
#
# Protocol compliance (adjudication §PI-5): profile=primary, adapter=docker,
# provider=cosmic-file, F2/F3 frozen; the execution design is pre-booked in
# docs/devlog/2026-11-02-g0-primary-pi-design-booking.md (fan-out, bands,
# ledger law, nine-column pin class — this file is its instrument).
#
# FAIL-CLOSED LAW: every input is operator-exported, there are no silent
# defaults; any refusal exits rc 2 naming its cause. The co-tenancy BAR
# (load1 > 10.0 = the 10-vCPU class) and the measurement-image census are
# constants, not knobs: exporting G0_PI_LOAD_BAR is itself a refusal.
#
# FAN-OUT LAW: machine-wide concurrent-container cap 4 (the degraded run's
# measured exit-137 rate at 8-way fan-out is booked evidence; the cap may be
# lowered by the operator, never raised). Resume is legal ONLY via
# G0_REUSE_CACHE (death protocol): the cachedir pointer re-reads the ONE
# outdir, the ledger must show exactly one full row, and no new row is
# appended — a resume is not an ignition.
#
# Launch detached from the OUTSIDE:
#   G0_SIGNATURES_PATH=... G0_CATALOG_PATH=... \
#   G0_HW_PROFILE='10 vCPU / 8 GB class' \
#     nohup sh tools/run_primary_pi.sh > /tmp/g0plane/logs/<stamp>.ignition.log 2>&1
set -eu
# dirname (not `dir`: a GNU ls alias absent on darwin — a failed command
# substitution here would silently cd elsewhere under set -e).
cd "$(dirname "$0")/.."   # -> bench/g0

PIN_SIG=80e911998764667dcb715e7390671e32aa2bbe657a43be398e5e8319305ba29e
PIN_CAT=733e38c50b94f7dc59cef15eb042fc4359a818314fb3efb3824a7c54642c3f60
FANOUT_CAP=4
LOAD_BAR=10.0
MEASUREMENT_TOKENS="g0-sigfit g0-stl sigminer sigprofiler"
ALL_SHARDS="main comp_clock_only comp_mmr comp_flat_triple comp_strong_flat nb clock_sparse comp_pole"
SYSCTL=${G0_PI_SYSCTL:-/usr/sbin/sysctl}

die2() { echo "$*" >&2; exit 2; }

[ -z "${G0_PI_LOAD_BAR:-}" ] || die2 "co-tenancy BAR is not an operator knob"
REHEARSAL=${G0_PI_REHEARSAL:-}
case "$REHEARSAL" in ""|mock) : ;; *) die2 "G0_PI_REHEARSAL must be mock or unset" ;; esac

# -- operator-exported inputs (fail-closed) ----------------------------------------
if [ "$REHEARSAL" = mock ]; then
  [ -n "${G0_PI_REPS:-}" ] || die2 "rehearsal requires explicit G0_PI_REPS (calibration is never defaulted)"
  case "$G0_PI_REPS" in ''|*[!0-9]*) die2 "G0_PI_REPS must be an integer" ;; esac
  [ "$G0_PI_REPS" -ge 1 ] && [ "$G0_PI_REPS" -le 5 ] || die2 "G0_PI_REPS out of calibration range 1..5"
  ADAPTER=mock; PROVIDER=synthetic; REPSARG="--reps $G0_PI_REPS"
else
  [ -z "${G0_PI_REPS:-}" ] || die2 "reps is frozen at 200 for the authoritative profile; G0_PI_REPS is rehearse-only"
  ADAPTER=docker; PROVIDER=cosmic-file; REPSARG=""
fi
[ -n "${G0_HW_PROFILE:-}" ] || die2 "G0_HW_PROFILE unset or blank — measure with the canonical pin exported (GO-05 seal twin)"
case "$G0_HW_PROFILE" in *[![:space:]]*) : ;; *) die2 "G0_HW_PROFILE unset or blank — a blank pin refuses like an absent one" ;; esac

if [ "$REHEARSAL" != mock ]; then
  [ -n "${G0_SIGNATURES_PATH:-}" ] || die2 "G0_SIGNATURES_PATH unset (the 5x96 ground truth must be operator-exported)"
  [ -n "${G0_CATALOG_PATH:-}" ]    || die2 "G0_CATALOG_PATH unset (the F3 fit catalog must be operator-exported)"
  [ -s "${G0_SIGNATURES_PATH}" ] || die2 "G0_SIGNATURES_PATH file missing or empty: $G0_SIGNATURES_PATH"
  [ -s "${G0_CATALOG_PATH}" ]    || die2 "G0_CATALOG_PATH file missing or empty: $G0_CATALOG_PATH"
  # reading tests: the digests must be truly consumed from the bytes
  got=$(shasum -a 256 "$G0_SIGNATURES_PATH" | awk '{print $1; exit}')
  [ "$got" = "$PIN_SIG" ] || die2 "tampered digest: signatures ground truth ($G0_SIGNATURES_PATH)"
  got=$(shasum -a 256 "$G0_CATALOG_PATH" | awk '{print $1; exit}')
  [ "$got" = "$PIN_CAT" ] || die2 "tampered digest: fitting catalog ($G0_CATALOG_PATH)"
fi

FANOUT=$FANOUT_CAP
if [ -n "${G0_PI_FANOUT:-}" ]; then
  case "$G0_PI_FANOUT" in ''|*[!0-9]*) die2 "G0_PI_FANOUT must be an integer" ;; esac
  [ "$G0_PI_FANOUT" -ge 1 ] && [ "$G0_PI_FANOUT" -le "$FANOUT_CAP" ] \
    || die2 "G0_PI_FANOUT above the fan-out cap $FANOUT_CAP (spare-core posture, never raised)"
  FANOUT=$G0_PI_FANOUT
fi
SHARDS_PLAN=${G0_PI_SHARDS:-$ALL_SHARDS}
for s in $SHARDS_PLAN; do
  hit=0
  for a in $ALL_SHARDS; do [ "$s" = "$a" ] && hit=1; done
  [ "$hit" = 1 ] || die2 "unknown shard tag in G0_PI_SHARDS: $s"
done

# -- campaign identity + single-ignition ledger ------------------------------------
ts=$(date -u +%Y%m%d-%H%M%S)
if [ -n "${G0_REUSE_CACHE:-}" ]; then
  [ "$REHEARSAL" != mock ] || die2 "resume is an authoritative-face protocol"
  CACHE="$G0_REUSE_CACHE"
  [ -d "$CACHE" ] || die2 "G0_REUSE_CACHE names no campaign cachedir: $CACHE"
  OUT=$(cat "$CACHE/.primary_pi_outdir" 2>/dev/null || echo "")
  [ -n "$OUT" ] || die2 "M7_REUSE-style resume carries no .primary_pi_outdir pointer — resuming would invent a second authoritative outdir"
  LEDGER="$OUT/campaign_launches.jsonl"
  [ -f "$LEDGER" ] || die2 "ledger refuses: resume without its ignition ledger"
  nf=$(grep -c '"mode":[[:space:]]*"full"' "$LEDGER" 2>/dev/null || true)
  [ "${nf:-0}" -eq 1 ] || die2 "ledger refuses: resume sees ${nf:-0} full rows (single-ignition law)"
  RESUME=1
else
  CACHE=${G0_PI_CACHEDIR:-cache/primary_pi}
  if [ "$REHEARSAL" = mock ]; then
    OUT=${G0_PI_OUTDIR:-../results/docker_primary_pi_rehearsal_$ts}
  else
    OUT=${G0_PI_OUTDIR:-../results/docker_primary_pi_$ts}
  fi
  [ -e "$CACHE/.primary_pi_outdir" ] && die2 "campaign already ignited under $CACHE — the identity survives its deaths: resume via G0_REUSE_CACHE"
  LEDGER="$OUT/campaign_launches.jsonl"
  nf=0; [ -f "$LEDGER" ] && nf=$(grep -c '"mode":[[:space:]]*"full"' "$LEDGER" 2>/dev/null || true)
  [ "${nf:-0}" -ge 2 ] && die2 "ledger refuses: double-full-row ignition"
  [ "${nf:-0}" -ge 1 ] && die2 "ledger refuses: fresh ignition onto an existing full row"
  RESUME=0
fi

# PID-bound holder marker: a dead holder is adoptable (death protocol), a live
# one means a true second concurrent campaign — refused (the marker is also
# the co-tenancy law's first line).
MARKER="$CACHE/.campaign-running"
if [ -f "$MARKER" ]; then
  mp=$(cat "$MARKER" 2>/dev/null || echo "")
  if [ -n "$mp" ] && kill -0 "$mp" 2>/dev/null; then
    echo "second ignition refused: campaign pid $mp is alive (single-ignition law, also a co-tenancy law)" >&2
    exit 2
  fi
  echo "[ignition] adopting marker of dead pid ${mp:-?} (death protocol)"
fi

# -- pre-flight: images + co-tenancy census (authoritative face only) ---------------
if [ "$REHEARSAL" != mock ]; then
  for img in g0-sigfit g0-stl; do
    iid=$(docker images -q "$img" 2>/dev/null | tr -d '[:space:]' || true)
    [ -n "$iid" ] || die2 "image missing: $img (build per bench/g0/README.md §4 before ignition)"
  done
  if ! PS_LINES=$(docker ps --format '{{.Names}} {{.Image}}' 2>&1); then
    die2 "docker ps census failed — the co-tenancy gate cannot attest: $PS_LINES"
  fi
  for tok in $MEASUREMENT_TOKENS; do
    if printf '%s\n' "$PS_LINES" | grep -q -- "$tok"; then
      live=$(printf '%s\n' "$PS_LINES" | grep -- "$tok" | tr '\n' ';')
      die2 "co-tenancy refused: live measurement container(s) [$live] — the matrix domain is busy; a refusal is an event to report, not to route around"
    fi
  done
  LOADRAW=$("$SYSCTL" -n vm.loadavg 2>/dev/null) || die2 "load sampler failed — the co-tenancy gate cannot attest"
  set -- $(printf '%s' "$LOADRAW" | tr -c '0123456789.' ' ')
  LOAD1=${1:-}
  case "$LOAD1" in ''|.|*[!0-9.]*) die2 "load sampler produced no attestation: [$LOADRAW]" ;; esac
  if awk -v a="$LOAD1" -v b="$LOAD_BAR" 'BEGIN{exit (a+0 > b+0) ? 0 : 1}'; then
    die2 "co-tenancy refused: load1=$LOAD1 over BAR=$LOAD_BAR (spare-core premise broken; report, do not relax)"
  fi
fi

if [ "${G0_PI_PREFLIGHT:-}" = 1 ]; then
  if [ "$REHEARSAL" = mock ]; then
    echo "PREFLIGHT-PASS gates=mode,pin,identity,ledger,marker face=rehearsal"
  else
    echo "PREFLIGHT-PASS gates=env,digests,pin,identity,ledger,marker,images,tenancy fanout=$FANOUT"
  fi
  exit 0
fi

# -- ignition -----------------------------------------------------------------------
mkdir -p "$CACHE" "$OUT/witnesses"
echo $$ > "$CACHE/.campaign-running"
if [ "$RESUME" != 1 ]; then
  mode=full; [ "$REHEARSAL" = mock ] && mode=rehearsal
  printf '{"kind":"launch","mode":"%s","ts":"%s"}\n' "$mode" "$(date -u +%FT%TZ)" \
    >> "$LEDGER"
fi
[ -e "$CACHE/.primary_pi_outdir" ] || echo "$OUT" > "$CACHE/.primary_pi_outdir"

if [ "$REHEARSAL" != mock ]; then
  printf '{"kind":"census","ts":"%s","load1":"%s","bar":"%s","live_measurement":false,"hw_profile":"%s","fanout":%s,"ps":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$LOAD1" "$LOAD_BAR" "$(printf '%s' "$G0_HW_PROFILE" | tr '"' "'")" \
    "$FANOUT" "$(printf '%s\n' "$PS_LINES" | tr '"' "'" | tr '\n' ';')" \
    >> "$OUT/witnesses/host_census.jsonl"
fi

SH_OUT="$CACHE/shard_out"
[ "$RESUME" = 1 ] || rm -rf "$SH_OUT"          # resume PRESERVES witnessed shard tables
mkdir -p "$SH_OUT/logs"

common="--profile primary --adapter $ADAPTER --provider $PROVIDER --cachedir $CACHE"
[ -n "$REPSARG" ] && common="$common $REPSARG"

shard_arms() {
  case "$1" in
    main) echo main ;;
    comp_clock_only) echo comp_clock_only ;;
    comp_mmr) echo comp_mmr ;;
    comp_flat_triple) echo comp_flat_triple ;;
    comp_strong_flat) echo comp_strong_flat ;;
    nb) echo nb ;;
    clock_sparse) echo clock,sparse ;;
    comp_pole) echo comp_pole ;;
    *) die2 "unknown shard $1" ;;
  esac
}
skip_shard() {
  for s in ${G0_SKIP_SHARDS:-}; do [ "$s" = "$1" ] && return 0; done
  return 1
}

pids=""; tags=""; nact=0; shardfail=""
for tag in $SHARDS_PLAN; do
  if skip_shard "$tag"; then
    echo "[ignition] shard $tag SKIPPED (witnessed resume law)"
    continue
  fi
  arms=$(shard_arms "$tag")
  echo "[ignition] shard $tag start $(date -u +%FT%TZ) (fan-out $nact/$FANOUT)"
  python3 run_grid.py $common --arms "$arms" --outdir "$SH_OUT/$tag" \
    > "$SH_OUT/logs/$tag.log" 2>&1 &
  pids="$pids $!"; tags="$tags $tag"; nact=$((nact + 1))
  if [ "$nact" -ge "$FANOUT" ]; then
    set -- $pids; f=$1; shift; pids="$*"
    set -- $tags; ft=$1; shift; tags="$*"
    if ! wait "$f"; then shardfail="$shardfail $ft"; fi
    nact=$((nact - 1))
  fi
done
while [ -n "$pids" ]; do
  set -- $pids; f=$1; shift; pids="$*"
  set -- $tags; ft=$1; shift; tags="$*"
  if ! wait "$f"; then shardfail="$shardfail $ft"; fi
done
if [ -n "$shardfail" ]; then
  echo "SHARD FAILURE:$shardfail (see $SH_OUT/logs) — defect candidates are reported, not outrun; resume is legal ONLY via G0_REUSE_CACHE (death protocol)" >&2
  rm -f "$CACHE/.campaign-running"
  exit 1
fi

# Final serial pass over the full plan: authoritative judgment (and the repair
# leg — cache-skip demands intervals.csv+errors.log, so an exit-137 casualty
# re-measures once, serially, at full wall). Rehearsal narrows to its plan.
final_arms=""
if [ "$REHEARSAL" = mock ]; then
  for tag in $SHARDS_PLAN; do
    final_arms="$final_arms,$(shard_arms "$tag")"
  done
  final_arms=$(printf '%s' "$final_arms" | sed -E 's/^,//')
  python3 run_grid.py $common --arms "$final_arms" --outdir "$OUT" --with-lrt-diagnostic
else
  python3 run_grid.py $common --outdir "$OUT" --with-lrt-diagnostic
fi

ftimings=$(ls -t "$OUT"/timings_primary_*.csv 2>/dev/null | head -1)
[ -n "$ftimings" ] || die2 "final pass left no timings table"
python3 tools/rollup_timings.py --shard-root "$SH_OUT" --final "$ftimings" \
  --host "$(hostname)" --hw-profile "$G0_HW_PROFILE" \
  --out "$OUT/timings_sharded_master.csv"
python3 tools/verify_hardware_pin.py --table "$OUT/timings_sharded_master.csv" \
  --host "$(hostname)" --hw-profile "$G0_HW_PROFILE" \
  || { echo "reader verifier refused the authoritative table" >&2
       rm -f "$CACHE/.campaign-running"
       exit 1; }

rm -f "$CACHE/.campaign-running"
if [ "$REHEARSAL" = mock ]; then
  echo "REHEARSAL-COMPLETE outdir=$OUT"
else
  echo "PRIMARY-AUTHORITATIVE-RUN-COMPLETE outdir=$OUT cachedir=$CACHE"
fi
