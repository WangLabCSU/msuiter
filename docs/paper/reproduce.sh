#!/usr/bin/env bash
# msuiter paper reproduction face (PP-1 lane; docs/paper/reproduction-proof.md).
#
#   --verify  (default) dry-run verification of every sealed number quoted in
#             docs/paper/paper-draft.md against committed bytes: no container,
#             no network, no long campaign. Each face prints FACE <name> rc=<n>;
#             any FAIL exits non-zero.
#   --full    additionally prints the operator-side regeneration recipes (and
#             the renv restore plan) without executing them. Regeneration is
#             operator-gated work, never a dry-run claim.
#
# Environment for the R-side scenario faces: set MSUITER_REPRO_LIB to a
# library holding a build OF THIS TREE (R CMD INSTALL --library=<that> <tree>)
# so the installed identity is the tree's, never an ambient stale one
# (house SIM-provisioning trust law). Unset => the user library is used as-is.
#
# Synthetic-only law: every artifact touched here is the frozen G0 synthetic
# regime (master seed 20260928) or a committed witness table. Post-cap witness
# law: the O5 face speaks the floor-table epoch pinned at
# bench/m7/tests/test_p6_floor_governance.py:156; the bootstrap campaign
# predates that epoch and the draft quotes it labeled epoch-mismatched.
# Portable to bash 3.2 (no associative arrays).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:---verify}"
FAILURES=0
STAMP=$$

logpath() { printf '/tmp/msuiter-reproduce-%s-%s.log' "$1" "$STAMP"; }

say() { printf '%s\n' "$*"; }

expect() { # expect <label> <file> <literal>: byte-grep for a literal
  local label="$1" file="$2" lit="$3"
  if LC_ALL=C grep -c -F "$lit" "$file" >/dev/null 2>&1; then
    printf 'PIN  %-24s ok  %s\n' "$label" "$lit"
  else
    printf 'PIN  %-24s MISSING %s in %s\n' "$label" "$lit" "$file"
    FAILURES=$((FAILURES + 1))
  fi
}

expectface() { # expectface <label> <literal>: grep that face's own log
  expect "$1" "$(logpath "$1")" "$2"
}

runface() { # runface <label> <workdir> <cmd...>
  local label="$1" wd="$2"; shift 2
  local log; log="$(logpath "$label")"
  local t0 t1 rc
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ( cd "$wd" && "$@" ) > "$log" 2>&1
  rc=$?
  t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf 'FACE %-24s rc=%d %s .. %s log=%s\n' "$label" "$rc" "$t0" "$t1" "$log"
  [ "$rc" -eq 0 ] || FAILURES=$((FAILURES + 1))
}

cd "$REPO" || exit 2
say "== msuiter reproduce: mode=$MODE repo=$REPO =="

#--- Face 1: bench/m7 unit-test surface --------------------------------------
runface m7-tests bench/m7 python3 -m tests.run_all
expectface m7-tests "364/364 tests passed."

#--- Face 2: O5 parity census (MEASURED-then-STATED; refuses witness drift) ---
runface o5-parity bench/m7 python3 -m tools.parity_recompute
expectface o5-parity "lines=147 breaches=147"
expectface o5-parity "epoch=f3e894a6933a2ffb"

#--- Face 3: bootstrap campaign, shared oracle over the sealed outdir --------
# host + hw_profile expectations are read from the campaign's own seal.json,
# so the face is one command; the verifier re-derives the ratio from the arm
# witness bytes (ratio-fidelity) and re-checks that MEASURED-false holds.
BOOTDIR="$REPO/bench/results/bootstrap_vs_sigminer_20261013T175859Z"
BOOTSEAL="$BOOTDIR/seal.json"
BOOT_HOST=$(python3 -c "import json,sys;sys.stdout.write(json.load(open(sys.argv[1]))['host'])" "$BOOTSEAL")
BOOT_HWP=$(python3 -c "import json,sys;sys.stdout.write(json.load(open(sys.argv[1]))['hw_profile'])" "$BOOTSEAL")
runface bootstrap-campaign bench/m7 python3 -m tools.verify_campaign \
  --campaign ../results/bootstrap_vs_sigminer_20261013T175859Z \
  --host "$BOOT_HOST" --hw-profile "$BOOT_HWP"
expectface bootstrap-campaign '"ok": true'
expectface bootstrap-campaign "claimed 15.36600758177 vs recomputed 15.36600758176629"
expect sealed-ratio   "$BOOTDIR/result.md" "1.536600758177e+01"
expect sealed-verdict "$BOOTDIR/result.md" "MEASURED-false 15.37x"
expect sealed-secondary docs/PERFORMANCE.md "14.2209x"

#--- Face 4: yardstick pins (fixture digest + claimed field bytes) -----------
runface yardstick-pins bench/m7 python3 tools/verify_yardstick_pins.py

#--- Face 5: commit-object message bytes (P10 bridge, P-1 re-adjudication) --
runface commit-objects "$REPO" bash -c \
  'git show -s --format=%B 2296f49 | grep -F "landing ratio 2.3004" && git show -s --format=%B 8213192 | grep -F "MEASURED-FALSE (23.7-32.2x)"'

#--- Face 6: sealed P-1 original gate table -----------------------------------
expect p1-table bench/results/p6_regen_20261016-011928/result.md "FAIL — 18 offending class(es)"

#--- Face 7: scenario runners (synthetic; self-adjudicating, rc is the law) --
if [ -n "${MSUITER_REPRO_LIB:-}" ]; then
  USRLIB=$(python3 -c 'import os,sys;sys.stdout.write(os.path.expanduser("~/Library/R/arm64/4.5/library"))')
  export R_LIBS_USER="$MSUITER_REPRO_LIB"
  [ -n "$USRLIB" ] && [ -d "$USRLIB" ] && export R_LIBS_SITE="$USRLIB"
fi
runface scen-atlas     "$REPO" Rscript bench/scenarios/run_atlas.R
expectface scen-atlas "OVERALL PASS"
runface scen-hrd       "$REPO" Rscript bench/scenarios/run_hrd.R
expectface scen-hrd "OVERALL PASS"
runface scen-treatment "$REPO" Rscript bench/scenarios/run_treatment.R
expectface scen-treatment "OVERALL PASS"

#--- Face 8: seed-regime bank (master seed + per-campaign Seeds.txt) ---------
expect seed-master "$BOOTDIR/result.md" "seed: 20260928 (G0 master"
SEEDS_OK=1
for d in "$BOOTDIR" \
         "$REPO/bench/results/p6_regen_20261016-011928" \
         "$REPO/bench/results/p6_regen_20261023-044026" \
         "$REPO/bench/results/docker_m7_degraded_20261010-202330"; do
  [ -f "$d/Seeds.txt" ] || { say "PIN  seeds-bank MISSING $d/Seeds.txt"; FAILURES=$((FAILURES + 1)); SEEDS_OK=0; }
done
[ "$SEEDS_OK" -eq 1 ] && say "PIN  seeds-bank                   ok  4/4 committed Seeds.txt present"

if [ "$MODE" = "--full" ]; then
  say "-- full-mode recipes (printed, not executed; operator-gated) -----------"
  say "# bootstrap regeneration one-key shot (bench/bootstrap/README.md):"
  say "export M7_HW_PROFILE='host-R campaign | Apple Silicon | 10 cores | hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2'"
  say "TS=; Rscript --vanilla bench/bootstrap/run_campaign.R -- --outdir bench/results/bootstrap_vs_sigminer_TS --mode full"
  say "# container recipes (committed Dockerfiles; image digests attested in"
  say "#   bench/results/docker_m7_PILOT_20261008-200152/image_inspect_*.json):"
  say "docker build -f bench/m7/adapters/Dockerfile.sigprofiler  bench/m7/adapters"
  say "docker build -f bench/m7/adapters/Dockerfile.sigminer     bench/m7/adapters"
  say "docker build -f bench/m7/adapters/Dockerfile.nmf_yardstick bench/m7/adapters"
  say "# R-side dependency freeze (docs/paper/renv.lock, Posit renv JSON; 111"
  say "#   pinned packages, R 4.5.2 stamp; readback: lockfile_read attestations"
  say "#   banked in the lane manifest):"
  say "Rscript -e 'lf <- renv::lockfile_read(file = \"docs/paper/renv.lock\", project = NULL); print(lf\$R\$Version); print(length(lf\$Packages))'"
  say "# replay into a clean library: renv::restore(lockfile = \"docs/paper/renv.lock\", library = <dir>, prompt = FALSE)"
fi

say "== reproduce: FAILURES=$FAILURES =="
if [ "$FAILURES" -eq 0 ]; then
  say "REPRODUCE-VERDICT PASS"; exit 0
else
  say "REPRODUCE-VERDICT FAIL"; exit 1
fi
