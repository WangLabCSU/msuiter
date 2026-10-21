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
# The 2026-10-21 runner forensics adds the TOOL ATTESTATION ORDER: an
# instrumented canary trip must demonstrably complete its lifecycle (its
# ERROR SUMMARY is REQUIRED) before the roster's census may speak at all,
# and a reportless roster run whose guest produced attestations while
# memcheck exited on a signal adjudicates as the tool's death, not the
# guest's (the silent-core-dump class).
#
# The same day's live-fire adds the REPORT SHAPE LAW: every line memcheck
# authors is ==pid== prefixed while the guest's own stdout is not, so the
# census patterns are pid-tolerant; a fully-freed heap omits the
# definitely-lost line entirely and attests zero loss by its own words
# ("All heap blocks were freed") -- absence of that line is a verdict, not
# an incompleteness. Violation headings likewise ride byte-true (no "bytes"
# suffix), and a trip's content words must be matched by a counted error.
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
  command -v Rscript >/dev/null 2>&1 \
    || die "Rscript is missing -- an arm that cannot spawn its subject attests nothing"
  command -v timeout >/dev/null \
    || die "coreutils timeout is missing -- the wall-clock budget cannot be enforced"
  valgrind --version >/dev/null || die "valgrind --version failed"
  note "$(valgrind --version | head -1) accepted; wall-clock budget ${valgrind_budget_s}s per invocation"
}

# Suppression precedence: env override > vendored reviewed file > opportunistic
# R-installed copies > none. R ships no valgrind.supp of its own -- falsified
# 2026-10-21 against the R 4.6.1 source tarball (full listing, zero hits);
# distro packages maintain their own, and ours is the reviewed artifact
# tools/deep-checks/valgrind.supp. With none in force the ERROR SUMMARY census
# must measure zero unadorned -- suppressions can never soften that gate, and
# the canary pair proves memcheck stays live under whatever file is in force.
resolve_suppressions() { # sets $suppressions ("" allowed) and $suppressions_kind
  suppressions=""; suppressions_kind=""
  cand=${VALGRIND_SUPPRESSIONS:-}
  if [ -n "$cand" ]; then
    [ -f "$cand" ] || die "VALGRIND_SUPPRESSIONS names a missing file: $cand"
    suppressions=$cand
    suppressions_kind=env-override
  elif [ -f "$here/valgrind.supp" ]; then
    suppressions=$here/valgrind.supp
    suppressions_kind=vendored-reviewed
  else
    home=$(Rscript -e 'cat(R.home())')
    for probe in "$home/etc/valgrind.supp" "$home/../etc/valgrind.supp"; do
      if [ -f "$probe" ]; then
        suppressions=$probe
        suppressions_kind=R-installed
        break
      fi
    done
    [ -n "$suppressions_kind" ] || suppressions_kind=none-measured-clean
  fi
}

# run_valgrind executes; it adjudicates only the wall-clock budget. Whether
# the run COUNTS is decided by the report census (tool completion is the
# census's authority), then by the guest exit code -- in that order, so an
# incomplete census can never be masked by an exit-code gate firing first.
run_valgrind() { # run_valgrind <log> <cmd...> -> sets vg_rc (caller adjudicates)
  log=$1; shift
  if [ -n "$suppressions" ]; then
    set -- --suppressions="$suppressions" "$@"
  fi
  if timeout --kill-after=60 "$valgrind_budget_s" \
      valgrind --tool=memcheck --leak-check=full --track-origins=yes \
        --error-exitcode="$vg_error_rc" --num-callers=20 \
        "$@" > "$log" 2>&1
  then vg_rc=0; else vg_rc=$?; fi
  case "$vg_rc" in
    124 | 137) die "the ${valgrind_budget_s}s wall-clock budget was exceeded by: $*" ;;
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
  # Load semantics mirror tests/testthat.R's test_check idiom: the leg
  # consumes the INSTALLED package (load_package="none"), never a pkgload
  # reload of the source tree; the reporter must be a real exported object.
  # Both laws are CI-measured lessons (2026-10-20): an unresolvable symbol
  # CRASHED every file instantly, and auto-loading FAILED the native-bound
  # tests -- the CRASH lines now carry the verbatim reasons so this never
  # again needs an artifact download to diagnose.
  # <!-- census-exempt tokens: 0 --> the superseded CRASH "0 0" placeholder
  # was structural filler, not a measurement; verdicts ride the reason line.
  cat > "$driver" <<'EOF'
args <- commandArgs(TRUE)
files <- strsplit(args[[1]], ";")[[1]]
library(msuiter)
cat(sprintf("VG_BOOT R=%s testthat=%s msuiter-lib=%s\n",
            paste(R.version[6:7], collapse="."),
            as.character(packageVersion("testthat")),
            dirname(dirname(find.package("msuiter")))))
ok <- TRUE
for (f in files) {
  res <- tryCatch(
    testthat::test_file(f, package = "msuiter", load_package = "none",
                        reporter = testthat::SilentReporter$new(),
                        stop_on_failure = FALSE),
    error = function(e) {
      msg <- gsub("[\r\n]+", " | ", conditionMessage(e), perl = TRUE)
      cat(sprintf("VG_TESTFILE %s CRASH %s\n", f, substr(msg, 1, 400)))
      NULL
    })
  if (is.null(res)) { ok <- FALSE; next }
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
  if ! grep -qE '^(==[0-9]+== )?ERROR SUMMARY:' "$log"; then
    guest_saw=$(grep -c '^VG_TESTFILE' "$log" || true)
    tail_ctx=$(tail -5 "$log" | tr '\n' '|' | cut -c1-300)
    if [ "$vg_rc" -ge 129 ] && [ "$vg_rc" -le 192 ]; then
      die "MEMCHECK CORE DIED on signal $((vg_rc - 128)) (rc=$vg_rc) with $guest_saw guest attestation(s) and no report ever produced -- the tool's death is not the guest's (silent-core-dump class; log $log, tail [$tail_ctx])"
    fi
    die "LOUDNESS LAW: no ERROR SUMMARY line in $log (rc=$vg_rc, guest-lines=$guest_saw, tail [$tail_ctx]) -- memcheck never completed; a reportless run attests nothing (the D1 lesson)"
  fi
  grep -qE '^(==[0-9]+== )?HEAP SUMMARY:' "$log" \
    || die "LOUDNESS LAW: no HEAP SUMMARY line in $log -- the run terminated before the census could speak"
  errors=$(sed -nE 's/^(==[0-9]+== )?ERROR SUMMARY: ([0-9]+) error.*/\2/p' "$log" | tail -1)
  lost=$(sed -nE 's/^(==[0-9]+== )?definitely lost: ([0-9]+) bytes.*/\2/p' "$log" | tail -1)
  # a fully-freed heap omits the definitely-lost line and attests zero loss itself
  if [ -z "$lost" ]; then
    grep -qE '^(==[0-9]+== )?All heap blocks were freed' "$log" && lost=0 || true
  fi
  [ -n "$errors" ] && [ -n "$lost" ] \
    || die "the report census is incomplete (ERROR SUMMARY=$errors, definitely-lost=$lost) in $log"
  [ "$errors" -eq 0 ] \
    || die "memcheck reported $errors errors under the native-sentry roster (log $log)"
  [ "$lost" -eq 0 ] \
    || die "memcheck reports $lost bytes definitely lost under the native-sentry roster (log $log)"
  files_passed=$(grep -cE '^VG_TESTFILE [^ ]+ PASS [0-9]+ [0-9]+$' "$log" || true)
  tests_passed=$(sed -n 's/^VG_TESTFILE [^ ]* PASS \([0-9]*\) [0-9]*$/\1/p' "$log" | awk '{s+=$1} END {print s+0}')
  [ "$files_passed" -eq "$roster_n" ] \
    || { vg_evidence=$(grep '^VG_TESTFILE' "$log" | grep -v ' PASS ' | head -6 | tr '\n' ' ' || true)
         die "executed-work census mismatch: $files_passed roster file(s) passed of $roster_n nominated -- attestations: [$vg_evidence] (an arm that runs no files gates nothing -- the D1 lesson)" ; }
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

trip_signal() { # the report text each class is known to produce -- byte-true vs
  # the captured reports (the renamed fork's violation heading carries no "bytes")
  case $1 in
    heap) printf '%s\n' 'Invalid read of size [0-9]+' ;;
    leak) printf '%s\n' 'definitely lost' ;;
  esac
}

assert_trip_reported() { # <class> -- the instrumented trip must REPORT and COMPLETE
  class=$1
  run_canary "$log_dir/canary-trip-$class.log" yes "$class"
  grep -qE '^(==[0-9]+== )?ERROR SUMMARY:' "$log_dir/canary-trip-$class.log" \
    || die "TOOL ATTESTATION: the instrumented $class trip committed its violation but memcheck never emitted its ERROR SUMMARY (rc=$vg_rc) -- the tool cannot complete its lifecycle on this runner; the canaries precede the roster precisely to surface this here (log $log_dir/canary-trip-$class.log)"
  trip_count=$(sed -nE 's/^(==[0-9]+== )?ERROR SUMMARY: ([0-9]+) error.*/\2/p' "$log_dir/canary-trip-$class.log" | tail -1)
  [ -n "$trip_count" ] && [ "$trip_count" -ge 1 ] \
    || die "TOOL ATTESTATION: the instrumented $class trip committed its violation but memcheck's own summary counts $trip_count errors -- content words without a counted error are a contradiction, not a report (log $log_dir/canary-trip-$class.log)"
  if grep -Eq "$(trip_signal "$class")" "$log_dir/canary-trip-$class.log"; then
    note "control: the instrumented $class trip REPORTED its violation under a completed report (memcheck is live)"
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
  if grep -Eq '^(==[0-9]+== )?(ERROR SUMMARY: [1-9]|definitely lost: [1-9])' "$log_dir/canary-clean.log"; then
    die "the CLEAN canary (no violation) produced a memcheck report -- the detection \
is not discriminating (log $log_dir/canary-clean.log)"
  fi
  note "control: the clean canary stayed silent under memcheck"
}

mkdir -p "$log_dir"
probe_valgrind
resolve_suppressions
note "suppressations in force: $suppressions_kind${suppressions:+ (file $suppressions)}"

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
    # Tool attestation precedes guest attestation (2026-10-21 forensics):
    # the canary battery must prove memcheck completes its lifecycle on
    # this runner before a roster census is allowed to adjudicate it.
    build_canary
    assert_trip_silent heap
    assert_trip_silent leak
    assert_trip_reported heap
    assert_trip_reported leak
    assert_clean_silent
    install_package
    build_driver
    cd "$root"
    roster_n=0
    for _ in $roster; do roster_n=$((roster_n + 1)); done
    roster_files=$(printf 'tests/testthat/test-%s.R;' $roster); roster_files=${roster_files%;}
    note "running the native-sentry roster [$roster] under memcheck"
    suite_log=$log_dir/valgrind-suite.log
    run_valgrind "$suite_log" Rscript "$driver" "$roster_files"
    valgrind_report_census "$suite_log"
    [ "$vg_rc" -eq 0 ] \
      || die "the roster run exited rc=$vg_rc although the census claims completion -- memcheck's own error count (exit code $vg_error_rc) contradicts its report (log $suite_log)"
    note "LEG GREEN: memcheck completed and reported (canary-attested), the roster ran, the canaries discriminated live from dead"
    ;;
esac
