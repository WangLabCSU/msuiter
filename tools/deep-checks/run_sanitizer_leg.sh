#!/usr/bin/env sh
# Sanitizer-leg harness for the Scheduled deep checks (issue #32, D1).
#
# Why this file exists: the 2026-10-12 and 2026-10-19 nightlies ran the
# second sanitizer leg with RUSTFLAGS=-Zsanitizer=undefined, a value rustc
# has never accepted. The leg died at target discovery, produced zero
# sanitizer signal, and looked like an ordinary red build for two weeks.
# The loudness law this harness installs: a sanitizer leg is green only
# when the sanitizer demonstrably executed --
#
#   (1) the real test suite ran under the instrumented build
#       (executed-work census from cargo's own test-result lines);
#   (2) the trip canary -- a deliberate, reviewed violation of the class
#       the leg's sanitizer detects -- produced its report;
#   (3) the clean canary -- the same binary shape with no violation --
#       stayed silent.
#
# A flag rustc never saw, silently ignored, or pointed at a dead
# instrumentation path now fails the leg with a LOUDNESS LAW message,
# instead of passing vacuously.
#
# Usage:
#   run_sanitizer_leg.sh leg      <address|leak>   # the gate itself (CI arm)
#   run_sanitizer_leg.sh selftest <address|leak>   # discriminating control:
#       proves the leg can tell a live sanitizer from a dead one --
#       the trip must be SILENT without instrumentation and LOUD with it.
#
# Sanitizer set: address (spatial memory errors) and leak (unreachable
# allocations at process exit). Both exist in the rustc -Zsanitizer
# vocabulary and both are meaningful on this surface: engine/catalog are
# the index-arithmetic-heavy numeric core (ASan's class, cf. the U-M1c-01
# P0-1 off-bucket audit) and they are the crates where LSan has actually
# found leaks in our code (the 2026-10-19 indel83 report, 648 B / 72
# allocations). ThreadSanitizer is structurally vacuous here: both crates
# are #![forbid(unsafe_code)] with zero threading (thread pools live in
# the FFI shell, which this leg deliberately excludes -- libR is not
# instrumented, ARCHITECTURE.md §9). MemorySanitizer would report through
# non-instrumented std/libc surfaces (the known MSan false-positive regime)
# -- the choice is recorded in the commit message of the D1 remediation.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
workspace=$root/src/rust
canary_manifest=$root/tools/deep-checks/canary/Cargo.toml
suppressions=$root/tools/deep-checks/lsan.supp

die() { printf 'sanitizer-leg[%s]: FAIL: %s\n' "${SAN:-?}" "$1" >&2; exit 1; }
note() { printf 'sanitizer-leg[%s]: %s\n' "${SAN:-?}" "$1"; }

mode=${1:-}
SAN=${2:-}
[ -n "$mode" ] && [ -n "$SAN" ] || die "usage: run_sanitizer_leg.sh <leg|selftest> <address|leak>"
case "$SAN" in
  address | leak) ;;
  *) die "matrix value '$SAN' is outside the harness's known set (address|leak) -- \
add a case, a canary trip, and a justification before growing the matrix (D1 lesson: \
an unmapped matrix value must fail HERE, not at rustc target discovery)" ;;
esac

# One-time init caches (one-per-test-binary, process-lifetime by design)
# are triaged per-site in the suppressions file; genuine leaks are fixed,
# never suppressed. House law: no --ignore-all, no LeakCheck=0, no
# blanket patterns -- every entry carries a per-site justification comment.
if [ -f "$suppressions" ]; then
  export LSAN_OPTIONS="suppressions=$suppressions${LSAN_OPTIONS:+ $LSAN_OPTIONS}"
  note "using reviewed LSan suppressions file $suppressions"
fi

# --- canary build/run helpers --------------------------------------------------
build_canary() { # build_canary <instrumented:yes|no> -> echoes the binary path
  instrumented=$1
  work=$workspace/target/sanitizer-canary-$SAN-$instrumented
  if [ "$instrumented" = yes ]; then
    RUSTFLAGS="-Zsanitizer=$SAN" \
      cargo +nightly build --quiet --manifest-path "$canary_manifest" \
        --target-dir "$work"
  else
    RUSTFLAGS="" \
      cargo +nightly build --quiet --manifest-path "$canary_manifest" \
        --target-dir "$work"
  fi
  bin=$(find "$work/debug" -maxdepth 1 -name msuiter-sanitizer-canary -type f 2>/dev/null | head -1)
  [ -n "$bin" ] || die "canary binary not found after build (instrumented=$instrumented)"
  printf '%s\n' "$bin"
}

run_canary() { # run_canary <bin> <clean|trip> -> echoes combined output
  bin=$1
  kind=$2
  "$bin" "$kind" "$SAN" 2>&1 || true   # sanitizer exit codes are asserted via the report text
}

# The report strings each sanitizer is known to print for our trip shape.
trip_marker() { # echoes a grep-E pattern proving this sanitizer caught its class
  case "$SAN" in
    address) printf '%s\n' 'ERROR: AddressSanitizer|heap-buffer-overflow' ;;
    leak)    printf '%s\n' 'ERROR: LeakSanitizer|LeakSanitizer: detected memory leaks|byte\(s\) leaked in' ;;
  esac
}

assert_trip_reported() { # <bin> -> die if the instrumented trip stays silent
  bin=$1
  out=$(run_canary "$bin" trip)
  if printf '%s\n' "$out" | grep -Eq "$(trip_marker)"; then
    note "control: instrumented trip canary REPORTED the $SAN violation (sanitizer is live)"
  else
    die "LOUDNESS LAW: the $SAN canary committed its violation and the sanitizer \
stayed silent -- the instrumentation never ran. Leg output was: $(printf '%s\n' "$out" | head -5)"
  fi
}

assert_trip_silent() { # <bin> -> die if an UNinstrumented canary somehow reports
  bin=$1
  out=$(run_canary "$bin" trip)
  if printf '%s\n' "$out" | grep -Eq "$(trip_marker)"; then
    die "discrimination control broken: an UNinstrumented canary produced a sanitizer \
report -- the leg could not tell a live sanitizer from a dead one"
  fi
  note "control: uninstrumented trip canary stayed silent (the leg discriminates live vs dead)"
}

assert_clean_silent() { # <bin> -> die if the clean canary trips anything
  bin=$1
  out=$(run_canary "$bin" clean)
  if printf '%s\n' "$out" | grep -Eq 'ERROR: [A-Za-z]*Sanitizer|SUMMARY: [A-Za-z]*Sanitizer'; then
    die "the CLEAN canary (no violation) produced a sanitizer report -- the trip \
detection is not discriminating: $(printf '%s\n' "$out" | head -5)"
  fi
  note "control: clean canary stayed silent under $SAN"
}

# --- rustc acceptance probe (the D1 root cause, caught before cargo) ----------
probe_rustc() {
  probe=$(mktemp -d)
  printf 'fn main() {}\n' > "$probe/p.rs"
  if ! rustc +nightly "$probe/p.rs" -o "$probe/p" "-Zsanitizer=$SAN" 2> "$probe/err"; then
    cat "$probe/err" >&2
    die "rustc rejected -Zsanitizer=$SAN -- this is the D1 defect class (a matrix \
value the toolchain does not implement). rustc's accepted set is address, cfi, \
dataflow, hwaddress, kcfi, kernel-address, kernel-hwaddress, leak, memory, memtag, \
safestack, shadow-call-stack, thread"
  fi
  rm -rf "$probe"
  note "rustc accepts -Zsanitizer=$SAN (target-discovery probe passed)"
}

# --- subcommands ---------------------------------------------------------------
case "$mode" in
  selftest)
    # Discriminating control for the whole harness: the same canary must be
    # silent without instrumentation and loud with it. This is the "a
    # deliberate no-run fixture turns the arm red" proof demanded by D1.
    probe_rustc
    dead=$(build_canary no)
    assert_trip_silent "$dead"
    live=$(build_canary yes)
    assert_trip_reported "$live"
    assert_clean_silent "$live"
    note "SELFTEST OK: the harness distinguishes a live $SAN from a dead one"
    ;;
  leg)
    probe_rustc
    # (1) the real suite under the sanitizer; cargo's own test-result lines
    # are the executed-work census -- a run that discovers zero tests is a
    # D1-style vacuous green.
    suite_log=${SANITIZER_LEG_LOG:-}
    cd "$workspace"
    note "running suite: cargo +nightly test -p msuiter-engine -p msuiter-catalog under $SAN"
    if [ -z "$suite_log" ]; then
      suite_log=$(mktemp /tmp/sanitizer-leg-XXXXXX.log)
    fi
    suite_rc=0
    RUSTFLAGS="-Zsanitizer=$SAN" \
      cargo +nightly test -p msuiter-engine -p msuiter-catalog > "$suite_log" 2>&1 || suite_rc=$?
    cat "$suite_log"
    [ "$suite_rc" -eq 0 ] || die "the suite failed under $SAN (exit $suite_rc; log above, banked copy at $suite_log)"
    runs=$(grep -cE '^ *Running ' "$suite_log" || true)
    results=$(grep -cE '^test result: ok' "$suite_log" || true)
    [ "$runs" -ge 1 ] && [ "$results" -ge 1 ] \
      || die "executed-work census is ZERO (test binaries run: $runs, ok results: $results) -- \
an arm that ran no tests gates nothing (the D1 lesson)"
    passed=$(sed -n 's/^test result: ok\. \([0-9]*\) passed.*/\1/p' "$suite_log" | awk '{s+=$1} END {print s+0}')
    # (2)+(3) canary both ways under the same flags that instrumented the suite.
    live=$(build_canary yes)
    assert_trip_reported "$live"
    assert_clean_silent "$live"
    note "LEG GREEN: rustc accepted the flag, the canary proved the instrumentation \
live, the suite exited clean under $SAN (test binaries run: $runs, ok results: $results, tests passed: $passed)"
    ;;
  *)
    die "unknown subcommand '$mode' (expected: leg | selftest)" ;;
esac
