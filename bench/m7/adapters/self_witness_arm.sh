#!/bin/sh
# P6 arm build-time self-witness — the frozen self_witness.sh contract, plus
# exactly the arm layers (everything below the frozen guards is additive; the
# four-file/sidecar block is byte-faithful to the reference witness).
#
# Run under RUN --network=none at bake. The composed argv is
# competitors/_p6_common.child_argv verbatim (counts/catalog/params/outdir +
# the roster-carried --backend face token), executed through the frozen
# m7_entry.py rusage launcher on the stage2-proven mini_cell fixtures.
#
# Build dies unless ALL of:
#   FROZEN CONTRACT (as self_witness.sh): rc=0; intervals.csv exact seven-
#   column header + >=1 data row; errors.log; timing.json sidecar schema
#   (ru_utime/ru_stime/cpu_seconds/exit_status, exit 0, cpu = utime+stime).
#   ARMS: the baked /work/arm_pin.json (roster-mirrored via the tested emitter
#   tools/p6_emit_arm_pins.py) is present and its face is admissible; the
#   provisioning set is exact — synchronicity + lpSolve load (the BFS
#   EXTRA_ROOTS of install_sigminer_arm.R), doParallel + matrixStats ABSENT
#   (route-parity law: the reference slice3-r5 image never carried doParallel,
#   so its presence would silently flip NMF's .pbackend and contaminate the
#   attribution ratios; matrixStats' only tip-era site is simulation.R, off
#   the cell path — its presence here is image drift).
#   RUST FACE: MSUITER_KERNEL_BIN is set, executable, and answers the stable
#   batch-entry handshake ("protocol=1" in --version, the same token
#   sigminer's R/rust_backend.R gate requires); the msuiter R namespace loads.
# Any undeclared runtime dependency is a build-time death here, never a
# mid-measurement auto-install (the network-none guarantee of the frozen law).
set -e
export OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 R_LIMIT_THREADS=1 GOMAXPROCS=1
export MSUITER_THREADS=1 STAN_OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

IN=/work/mini/in
OUT=/work/mini/out
PIN=/work/arm_pin.json

test -s "$PIN"
TOOL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tool"])' "$PIN")
FACE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["face"])' "$PIN")
TREE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tree_sha"])' "$PIN")
case "$FACE" in
  R|rust) ;;
  *) echo "[self-witness-arm] arm pin face invalid: $FACE" >&2; exit 1 ;;
esac
case "$TREE" in
  ???*) ;;  # >=3 chars; the roster test owns the 40-hex law — presence echo only
  *) echo "[self-witness-arm] arm pin tree_sha missing" >&2; exit 1 ;;
esac

test -s "$IN/counts.csv"
test -s "$IN/catalog.csv"
test -s "$IN/params.json"
test -s /work/run_sigminer_arm.R
test -s /work/install_sigminer_arm.R

python3 /work/m7_entry.py --params "$IN/params.json" --outdir "$OUT" -- \
  Rscript /work/run_sigminer_arm.R --counts "$IN/counts.csv" \
  --catalog "$IN/catalog.csv" --params "$IN/params.json" --outdir "$OUT" \
  --backend "$FACE"

# ---- frozen four-file/sidecar guards (verbatim from self_witness.sh) -------
test -s "$OUT/intervals.csv"
test -s "$OUT/errors.log"
test -s "$OUT/timing.json"
head -n 1 "$OUT/intervals.csv" |
  grep -q -x 'sample_id,signature,estimate,lo95,hi95,estimand,zeroed'
awk -F, 'NR > 1 && NF == 7 { n++ } END { exit (n >= 1 ? 0 : 1) }' \
  "$OUT/intervals.csv"
python3 -c '
import json, sys
t = json.load(open("/work/mini/out/timing.json"))
keys = ("ru_utime", "ru_stime", "cpu_seconds", "exit_status")
ok = (all(k in t for k in keys) and t["exit_status"] == 0
      and abs(t["cpu_seconds"] - (t["ru_utime"] + t["ru_stime"])) < 1e-9)
sys.exit(0 if ok else 1)'

# ---- provisioning set: exact, both faces -----------------------------------
# Each probe runs in its own fresh Rscript process (requireNamespace attaches,
# so a load probe must never share a session with an absence probe).
Rscript -e 'if (!requireNamespace("synchronicity", quietly = TRUE))
  stop("provisioning drift: synchronicity (BFS EXTRA_ROOT, runtime-fallback seed) absent")'
Rscript -e 'if (!requireNamespace("lpSolve", quietly = TRUE))
  stop("provisioning drift: lpSolve (BFS EXTRA_ROOT, runtime-fallback seed) absent")'
Rscript -e 'if (requireNamespace("doParallel", quietly = TRUE))
  stop("route-parity breach: doParallel present — reference cells all ran use_dopar=FALSE;
         an arm image carrying it silently flips NMF .pbackend and contaminates attribution")'
Rscript -e 'if (requireNamespace("matrixStats", quietly = TRUE))
  stop("provisioning drift: matrixStats present — not provisioned by the arm resolver
         (its only tip-era site is simulation.R, off the cell path)")'

# ---- rust face: kernel-boundary gates --------------------------------------
if [ "$FACE" = rust ]; then
  test -n "${MSUITER_KERNEL_BIN:-}" || {
    echo "[self-witness-arm] MSUITER_KERNEL_BIN unset — the baked kernel identity is ENV, not folklore" >&2; exit 1; }
  test -x "$MSUITER_KERNEL_BIN" || {
    echo "[self-witness-arm] MSUITER_KERNEL_BIN not executable: $MSUITER_KERNEL_BIN" >&2; exit 1; }
  # Stable batch-entry handshake — the exact token sigminer's
  # R/rust_backend.R .kernel_resolve/handshake gate requires pre-first-call.
  "$MSUITER_KERNEL_BIN" --version | grep -q 'protocol=1' || {
    echo "[self-witness-arm] kernel handshake refused (--version lacks protocol=1)" >&2; exit 1; }
  Rscript -e 'if (!requireNamespace("msuiter", quietly = TRUE))
    stop("rust face without the msuiter R namespace — install layer drift")'
fi

echo "[self-witness-arm] $TOOL face=$FACE tree=$(printf %.10s "$TREE") mini-cell OK: rc 0, sidecar schema valid, provisioning set exact, face gates satisfied"
