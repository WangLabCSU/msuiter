#!/usr/bin/env sh
# Valgrind-leg harness for the Scheduled deep checks (issue #32 remediation).
#
# The archived `--use-valgrind` whole-suite runs took 5h+ on the runner and
# were doubly silenced -- a job-level `continue-on-error: true` plus an
# rcmdcheck `error_on = "never"` -- so they could not have failed (the D1
# class). The loudness law this harness installs: a valgrind leg is green
# only when memcheck demonstrably completed (its report census is REQUIRED),
# the nominated native-sentry roster ran under it, and the canary pair
# proves detection: a committed violation REPORTS, the clean run and the
# uninstrumented run stay SILENT.
#
# Usage:
#   run_valgrind_leg.sh leg        # the gate itself (the CI arm)
#   run_valgrind_leg.sh selftest   # canary-only discriminating control
#
# Budget: every valgrind invocation is wall-clocked at ${valgrind_budget_s}
# seconds (default 3300, inside the 120-minute job ceiling); an overrun dies
# loudly instead of drifting into the platform timeout.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
canary_manifest=$here/valgrind-canary/Cargo.toml
canary_work=$root/src/rust/target/valgrind-canary
log_dir=${CHECK_VALGRIND_DIR:-$root/check-valgrind}
valgrind_budget_s=${valgrind_budget_s:-3300}
vg_error_rc=42

# The native-sentry roster: shipped testthat files whose code paths cross the
# R-to-native boundary. The whole suite is not valgrind-budget-coverable
# (2026-10-19 evidence: cancelled at the 360-minute platform ceiling).
#   ffi-probes -- the msffi_* call/error protocol, the direct FFI surface
#   fit        -- the fit numeric path through the engine/catalog call sites
#   extract    -- the extract numeric path (index arithmetic, the ASan class)
roster="ffi-probes fit extract"

die() { printf 'valgrind-leg: FAIL: %s\n' "$1" >&2; exit 1; }
note() { printf 'valgrind-leg: %s\n' "$1"; }

mode=${1:-}
case "$mode" in
  leg | selftest) ;;
  *) die "usage: run_valgrind_leg.sh <leg|selftest>" ;;
esac

probe_valgrind() {
  command -v valgrind >/dev/null 2>&1 \
    || die "the valgrind binary is missing -- an arm without its tool attests nothing"
  command -v timeout >/dev/null \
    || die "coreutils timeout is missing -- the wall-clock budget cannot be enforced"
  valgrind --version >/dev/null || die "valgrind --version failed"
  note "$(valgrind --version | head -1) accepted; wall-clock budget ${valgrind_budget_s}s per invocation"
}

# The interpreter's known-noise suppressions ship with R; without them a
# valgrind-R run drowns the report census, and a drowns-out census gates
# nothing.
resolve_suppressions() {
  cand=${VALGRIND_SUPPRESSIONS:-}
  if [ -z "$cand" ]; then
    home=$(Rscript -e 'cat(R.home())')
    for cand in "$home/etc/valgrind.supp" "$home/../etc/valgrind.supp"; do
      [ -f "$cand" ] && break
    done
  fi
  [ -f "$cand" ] || die "no R valgrind.supp found (set VALGRIND_SUPPRESSIONS to one)"
  printf '%s\n' "$cand"
}

run_valgrind() { # run_valgrind <log> <cmd...> -> sets vg_rc (0 | vg_error_rc ok)
  log=$1; shift
  if timeout --kill-after=60 "$valgrind_budget_s" \
      valgrind --tool=memcheck --leak-check=full --track-origins=yes \
        --error-exitcode="$vg_error_rc" --num-callers=20 \
        --suppressions="$suppressions" "$@" > "$log" 2>&1
  then vg_rc=0; else vg_rc=$?; fi
  case "$vg_rc" in
    0 | "$vg_error_rc") ;;
    124 | 137) die "the ${valgrind_budget_s}s wall-clock budget was exceeded by: $*" ;;
    *) die "valgrind exited rc=$vg_rc under budget: $* (log $log)" ;;
  esac
}

install_package() {
  libdir=$(mktemp -d)
  export R_LIBS_USER="${R_LIBS_USER:+$R_LIBS_USER:}$libdir"
  note "installing the package for the native-sentry roster"
  R CMD INSTALL --library="$libdir" --no-multiarch "$root" \
    >"$log_dir/install.log" 2>&1 \
    || die "R CMD INSTALL failed (log $log_dir/install.log)"
}

build_driver() {
  driver=$(mktemp "${TMPDIR:-/tmp}/valgrind-sentry-XXXXXX")
  # Structured per-file attestations give the executed-work census a
  # machine-checkable signal (the counterpart of cargo's "test result: ok").
  cat > "$driver" <<'EOF'
args <- commandArgs(TRUE)
files <- strsplit(args[[1]], ";")[[1]]
library(msuiter)
ok <- TRUE
for (f in files) {
  res <- tryCatch(
    testthat::test_file(f, reporter = testthat::silent_reporter(),
                        stop_on_failure = FALSE),
    error = function(e) NULL)
  if (is.null(res)) {
    cat(sprintf("VG_TESTFILE %s CRASH 0 0\n", f)); ok <- FALSE; next
  }
  df <- as.data.frame(res)
  npass <- sum(df$passed); nbad <- sum(df$failed + df$error + df$warning)
  cat(sprintf("VG_TESTFILE %s %s %d %d\n", f,
              if (nbad == 0) "PASS" else "FAIL", npass, nbad))
  ok <- ok && nbad == 0
}
quit(status = if (ok) 0L else 1L)
EOF
}

valgrind_report_census() { # <suite-log> -- every attestation line is REQUIRED
  log=$1
  grep -q '^ERROR SUMMARY:' "$log" \
    || die "LOUDNESS LAW: no ERROR SUMMARY line in $log -- memcheck never completed; a reportless run attests nothing (the D1 lesson)"
  grep -q '^HEAP SUMMARY:' "$log" \
    || die "LOUDNESS LAW: no HEAP SUMMARY line in $log -- the run terminated before the census could speak"
  errors=$(sed -n 's/^ERROR SUMMARY: \([0-9]*\) error.*/\1/p' "$log" | tail -1)
  lost=$(sed -n 's/^definitely lost: \([0-9]*\) bytes.*/\1/p' "$log" | tail -1)
  [ -n "$errors" ] && [ -n "$lost" ] \
    || die "the report census is incomplete (ERROR SUMMARY=$errors, definitely-lost=$lost) in $log"
  [ "$errors" -eq 0 ] \
    || die "memcheck reported $errors errors under the native-sentry roster (log $log)"
  [ "$lost" -eq 0 ] \
    || die "memcheck reports $lost bytes definitely lost under the native-sentry roster (log $log)"
  files_passed=$(grep -c '^VG_TESTFILE .* PASS ' "$log" || true)
  tests_passed=$(sed -n 's/^VG_TESTFILE [^ ]* PASS \([0-9]*\) .*/\1/p' "$log" | awk '{s+=$1} END {print s+0}')
  [ "$files_passed" -eq "$roster_n" ] \
    || die "executed-work census mismatch: $files_passed roster file(s) passed of $roster_n nominated (an arm that runs no files gates nothing -- the D1 lesson)"
  [ "$tests_passed" -ge 1 ] \
    || die "executed-work census is ZERO -- an arm that ran no tests gates nothing (the D1 lesson)"
  note "report census: ERROR SUMMARY 0, definitely-lost 0, roster $files_passed/$roster_n files, $tests_passed test(s) passed"
}

build_canary() {
  cargo build --quiet --manifest-path "$canary_manifest" \
    --target-dir "$canary_work" >"$log_dir/canary-build.log" 2>&1 \
    || die "the valgrind canary failed to build (log $log_dir/canary-build.log)"
  canary_bin=$(find "$canary_work/debug" -maxdepth 1 \
    -name msuiter-valgrind-canary -type f | head -1)
  [ -n "$canary_bin" ] || die "the canary binary was not found after the build"
}

run_canary() { # run_canary <log> <valgrind:yes|no> <class>
  log=$1; instrumented=$2; class=$3
  if [ "$instrumented" = yes ]; then
    run_valgrind "$log" "$canary_bin" trip "$class"
  else
    if "$canary_bin" trip "$class" > "$log" 2>&1; then vg_rc=0; else vg_rc=$?; fi
  fi
}

trip_signal() { # the report text each class is known to produce
  case $1 in
    heap) printf '%s\n' 'Invalid read of size [0-9]* bytes' ;;
    leak) printf '%s\n' 'definitely lost: [1-9][0-9]* bytes' ;;
  esac
}

assert_trip_reported() { # <class> -- the instrumented trip must REPORT
  class=$1
  run_canary "$log_dir/canary-trip-$class.log" yes "$class"
  if grep -Eq "$(trip_signal "$class")" "$log_dir/canary-trip-$class.log"; then
    note "control: the instrumented $class trip REPORTED its violation (memcheck is live)"
  else
    die "LOUDNESS LAW: the $class canary committed its violation and memcheck stayed \
silent -- the instrumentation never ran (log $log_dir/canary-trip-$class.log)"
  fi
}

assert_trip_silent() { # <class> -- an UNinstrumented trip must stay SILENT
  class=$1
  run_canary "$log_dir/canary-uninstrumented-$class.log" no "$class"
  if grep -E 'Invalid read|definitely lost' \
      "$log_dir/canary-uninstrumented-$class.log" >/dev/null; then
    die "discrimination control broken: an UNinstrumented $class canary produced a \
memcheck-style report -- the leg could not tell a live tool from a dead one"
  fi
  note "control: the uninstrumented $class trip stayed silent (live vs dead discriminates)"
}

assert_clean_silent() {
  run_valgrind "$log_dir/canary-clean.log" "$canary_bin" clean
  if grep -Eq '^ERROR SUMMARY: [1-9]|^definitely lost: [1-9]' "$log_dir/canary-clean.log"; then
    die "the CLEAN canary (no violation) produced a memcheck report -- the detection \
is not discriminating (log $log_dir/canary-clean.log)"
  fi
  note "control: the clean canary stayed silent under memcheck"
}

mkdir -p "$log_dir"
probe_valgrind
suppressions=$(resolve_suppressions)
note "using R suppressions $suppressions"

case "$mode" in
  selftest)
    build_canary
    assert_trip_silent heap
    assert_trip_silent leak
    assert_trip_reported heap
    assert_trip_reported leak
    assert_clean_silent
    note "SELFTEST OK: the harness distinguishes a live memcheck from a dead one"
    ;;
  leg)
    install_package
    build_driver
    cd "$root"
    roster_n=0
    for _ in $roster; do roster_n=$((roster_n + 1)); done
    roster_files=$(printf 'tests/testthat/test-%s.R;' $roster); roster_files=${roster_files%;}
    note "running the native-sentry roster [$roster] under memcheck"
    suite_log=$log_dir/valgrind-suite.log
    run_valgrind "$suite_log" Rscript "$driver" "$roster_files"
    [ "$vg_rc" -eq 0 ] \
      || die "the native-sentry roster did not pass under memcheck (rc $vg_rc; log $suite_log)"
    valgrind_report_census "$suite_log"
    build_canary
    assert_trip_silent heap
    assert_trip_silent leak
    assert_trip_reported heap
    assert_trip_reported leak
    assert_clean_silent
    note "LEG GREEN: memcheck completed and reported, the roster ran, the canaries discriminated live from dead"
    ;;
esac
