#!/bin/sh
# P6 arm build-time self-witness — the batch-bridge FORK of the byte-frozen
# adapters/self_witness_arm.sh, for the one pre-registered arm
# sigminer_post_v3_rust_batch (R1-PARITY Phase-B, controller ruling (ii)
# 2026-11-04).
#
# The frozen witness is ZERO-TOUCH: its bytes are pinned in
# Dockerfile.sigminer.tree and they are the trust guard the 147 committed
# parity rows were baked under, so this face reaches the build as a separate
# file with its own committed byte-pin -- never as a widening of that guard's
# face allow-list. Everything below the frozen four-file/sidecar block is the
# same law, spoken to this face:
#
#   FROZEN CONTRACT (byte-faithful to self_witness_arm.sh): rc=0; intervals.csv
#   exact seven-column header + >=1 data row; errors.log; timing.json sidecar
#   schema (ru_utime/ru_stime/cpu_seconds/exit_status, exit 0,
#   cpu = utime+stime).
#   ARMS: the baked /work/arm_pin.json is present and its face is the ONE
#   admissible face of this fork; the provisioning set is exact — synchronicity
#   + lpSolve + matrixStats + doParallel all load (the BFS EXTRA_ROOTS of
#   install_sigminer_arm.R; the A4 amendment 2026-10-15 and bake death #6 are
#   the recorded reasons the latter two are in the set).
#   BATCH FACE: this is where the face earns its name, and it is a build-time
#   death rather than a mid-measurement surprise if any part is missing --
#   MSUITER_KERNEL_BIN set, executable, answering the stable protocol=1
#   handshake; the msuiter R namespace loaded AND its kp_serve_unit batch
#   surface present (the face refuses to fall back to the per-fit route, so an
#   image without the bridge could only ever measure the wrong transport);
#   the installed sigminer seam carries the documented batch route (its
#   backend table, its exact-spelling bp validator, and the batch best-of-nrun
#   entry point). The two documented faces of the lineage are asserted to be
#   byte-untouched in the same installed bytes, so a batch image can not be a
#   re-labelled rust image.
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
  rust_batch) ;;
  *) echo "[self-witness-batch-arm] this fork guards the rust_batch face only, arm pin says: $FACE" >&2; exit 1 ;;
esac
case "$TREE" in
  ???*) ;;  # >=3 chars; the roster test owns the 40-hex law — presence echo only
  *) echo "[self-witness-batch-arm] arm pin tree_sha missing" >&2; exit 1 ;;
esac

test -s "$IN/counts.csv"
test -s "$IN/catalog.csv"
test -s "$IN/params.json"
test -s /work/run_sigminer_arm_batch.R
test -s /work/install_sigminer_arm.R

# The composed argv is competitors/_p6_common.child_argv verbatim (counts/
# catalog/params/outdir + the roster-carried --backend face token), executed
# through the frozen m7_entry.py rusage launcher on the P6-regenerated
# mini_cell_p6 fixtures (twenty N100 samples; death #7: the stage2-proven
# 96x1 twin is legitimate history but nndsvd-rank-refusing at k=2).
python3 /work/m7_entry.py --params "$IN/params.json" --outdir "$OUT" -- \
  Rscript /work/run_sigminer_arm_batch.R --counts "$IN/counts.csv" \
  --catalog "$IN/catalog.csv" --params "$IN/params.json" --outdir "$OUT" \
  --backend "$FACE"

# ---- frozen four-file/sidecar guards (verbatim from self_witness_arm.sh) -------
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
Rscript -e 'if (requireNamespace("doParallel", quietly = TRUE)) invisible(NULL) else
  stop("reference-parity drift: the committed slice3-r5 reference image probes TRUE for
         doParallel; an arm image lacking it diverges from the provisioning that
         minted the reference table (A4 amendment, 2026-10-15)")'
Rscript -e 'if (requireNamespace("matrixStats", quietly = TRUE)) invisible(NULL) else
  stop("reference-parity drift: matrixStats absent — the reference image carries it and
         simulation.R:79 rowWeightedMeans needs it ON the cell path (bake death #6)")'

# ---- batch face: the transport gates (a missing part is a build death) -------
test -n "${MSUITER_KERNEL_BIN:-}" || {
  echo "[self-witness-batch-arm] MSUITER_KERNEL_BIN unset — the baked kernel identity is ENV, not folklore" >&2; exit 1; }
test -x "$MSUITER_KERNEL_BIN" || {
  echo "[self-witness-batch-arm] MSUITER_KERNEL_BIN not executable: $MSUITER_KERNEL_BIN" >&2; exit 1; }
# Stable batch-entry handshake — the exact token sigminer's
# R/rust_backend.R .kernel_resolve/handshake gate requires pre-first-call, and
# the token the batch face pays once per unit instead of once per fit.
"$MSUITER_KERNEL_BIN" --version | grep -q 'protocol=1' || {
  echo "[self-witness-batch-arm] kernel handshake refused (--version lacks protocol=1)" >&2; exit 1; }
Rscript -e 'if (!requireNamespace("msuiter", quietly = TRUE))
  stop("batch face without the msuiter R namespace — install layer drift")'
# The batch surface itself: the face has no fallback to the per-fit route, so
# an image whose msuiter carries no kp_serve_unit could only ever mis-measure.
Rscript -e 'fn <- tryCatch(get("kp_serve_unit", envir = asNamespace("msuiter"),
                             mode = "function"), error = function(e) NULL)
  if (!is.function(fn))
    stop("batch face without the msuiter batch bridge: kp_serve_unit() is not a ",
         "function on the installed msuiter namespace — this image cannot serve ",
         "the fit-kl --cases transport it pre-registers")'
# The seam side, probed through the INSTALLED namespace (an installed R
# package carries no loose R/ files -- the lazy-load database is the bytes the
# cell will actually execute, so that is what gets asked). The documented
# routes must still answer exactly as documented, and the batch route must
# answer as pre-registered: an image that is a re-labelled rust image, or a
# seam whose two documented faces drifted, fails here rather than mid-run.
Rscript -e 'ns <- asNamespace("sigminer")
  # .$-on-environment is unreliable across renamed-R builds in the fleet, so
  # every probe below reaches the seam through one explicit getter.
  seam <- function(fn) get(fn, envir = ns, mode = "function")
  need <- function(fn) if (!exists(fn, mode = "function", where = ns))
    stop("installed sigminer seam export missing: ", fn, domain = NA)
  need(".r_assert_backend"); need(".r_assert_bp_backend")
  need(".rust_best_of_nrun"); need(".rust_best_of_nrun_batch")
  need(".rust_routes")
  # the two documented faces: byte-untouched table, byte-untouched semantics
  if (!identical(get(".RUST_BACKENDS", envir = ns), c("R", "rust")))
    stop("the documented backend table moved: ",
         paste(get(".RUST_BACKENDS", envir = ns), collapse = ","), domain = NA)
  if (!identical(seam(".r_assert_backend")("rus"), "rust"))
    stop("documented partial matching (rus -> rust) no longer holds", domain = NA)
  if (!inherits(try(seam(".r_assert_backend")("rust_batch"), silent = TRUE),
                "try-error"))
    stop("the batch token leaked into the documented validator: the two ",
         "documented faces are no longer byte-identical", domain = NA)
  # the batch face: exact spelling only, and it must route
  if (!identical(seam(".r_assert_bp_backend")("rust_batch"), "rust_batch"))
    stop("bp surface does not admit the exact-spelling rust_batch token", domain = NA)
  if (!identical(seam(".r_assert_bp_backend")("rus"), "rust"))
    stop("bp surface no longer delegates the documented faces verbatim", domain = NA)
  if (!identical(sort(get(".RUST_ROUTE_FACES", envir = ns)), c("rust", "rust_batch")))
    stop("the kernel-crossing face set moved: a face can half-route", domain = NA)
  # the in-package face stays off the boundary; both kernel faces cross it
  if (seam(".rust_routes")("R"))
    stop("route predicate false-positives on the in-package face R", domain = NA)
  for (f in c("rust", "rust_batch"))
    if (!seam(".rust_routes")(f))
      stop("face ", f, " does not cross to the certified kernel — a half-routing ",
           "face is not the face this arm pre-registers", domain = NA)
  if (!identical(seam(".rust_routes")("R"), FALSE))
    stop("route predicate does not answer a logical for the documented face",
         domain = NA)'

echo "[self-witness-batch-arm] $TOOL face=$FACE tree=$(printf %.10s "$TREE") mini-cell OK: rc 0, sidecar schema valid, provisioning set exact, batch transport gates satisfied"
