#!/usr/bin/env sh
# Regenerate the offline vendor tarball and report its byte budget.
# Baseline: docs/adr/0002-vendor-budget.md §2 (33 crates current; effective baseline
# = 2026-09-30 memmap2/libc increment row).
#
# The tarball is NOT committed: CRAN submission (U-M8-01) attaches a freshly
# generated one to the source package. CI (U-M0-07) runs `--check` to catch
# vendor drift (dependency budget discipline, ARCHITECTURE.md §2 / D4).
#
# Determinism note: the uncompressed byte count is an exact invariant of the
# Cargo.lock dependency set (file contents are OS-independent) and is checked
# exactly. The tar count varies a few hundred bytes between bsdtar (macOS)
# and GNU tar (Linux) archive formats — ±0.5% band. The xz count varies with
# the xz build (~0.01% across versions) — ±0.1% band.
set -eu

# Baselines are CARGO-VERSION-RELATIVE (audit 2026-10-05): the release
# gate pins MSRV 1.71 (release.yml Install Rust step), so the baselines
# are the 1.71 vendor output. Local default-toolchain runs (1.92) vendor
# +326 KB and will show DRIFT by design -- regenerate with
# `rustup run 1.71.0 sh tools/vendor.sh` to verify.
BASELINE_UNCOMPRESSED=16911999
BASELINE_TAR=18319360
BASELINE_XZ=1744176
TAR_TOL_PCT=0.5
XZ_TOL_PCT=0.1

filesize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }
within_tol() { # value baseline tol_pct
  awk -v v="$1" -v b="$2" -v t="$3" 'BEGIN { d = (v - b) * 100.0 / b; if (d < 0) d = -d; exit !(d <= t) }'
}

cd "$(dirname "$0")/../src/rust"

cargo vendor vendor > /tmp/msuiter-vendor-config.txt
UNCOMPRESSED=$(find vendor -type f -print0 | xargs -0 stat -f%z 2>/dev/null | awk '{s+=$1} END {print s}')
[ -n "$UNCOMPRESSED" ] || UNCOMPRESSED=$(find vendor -type f -print0 | xargs -0 stat -c%s | awk '{s+=$1} END {print s}')

rm -f /tmp/msuiter-vendor.tar /tmp/msuiter-vendor.tar.xz
tar -cf /tmp/msuiter-vendor.tar vendor
TAR=$(filesize /tmp/msuiter-vendor.tar)
tar -cJf /tmp/msuiter-vendor.tar.xz vendor
XZ=$(filesize /tmp/msuiter-vendor.tar.xz)

rm -rf vendor /tmp/msuiter-vendor.tar
echo "vendor uncompressed: ${UNCOMPRESSED} B (baseline ${BASELINE_UNCOMPRESSED} B)"

# Platform note (audit 2026-10-05): tar/xz containers are ARCHIVE-FORMAT
# relative (macOS bsdtar vs the Linux runner's GNU tar + xz settings);
# the uncompressed byte sum is the platform-independent dependency-set
# identity. tar/xz bands are enforced only on Linux (the release gate
# platform); darwin checks the uncompressed exact match.
OS_NAME=$(uname -s)
if [ "$OS_NAME" = "Linux" ]; then
  echo "vendor tar:          ${TAR} B (baseline ${BASELINE_TAR} B)"
  echo "vendor tar.xz:       ${XZ} B (baseline ${BASELINE_XZ} B, ±${XZ_TOL_PCT}%)"
else
  echo "vendor tar:          ${TAR} B (darwin: tar/xz bands are enforced on the Linux release gate only)"
  echo "vendor tar.xz:       ${XZ} B (darwin: tar/xz bands are enforced on the Linux release gate only)"
fi

if [ "${1:-}" = "--check" ]; then
  fail() { echo "vendor.sh: DRIFT DETECTED: $1" >&2; exit 1; }
  [ "$UNCOMPRESSED" -eq "$BASELINE_UNCOMPRESSED" ] || fail "uncompressed size drifted (dependency set changed? update ADR 0002)"
  if [ "$OS_NAME" = "Linux" ]; then
    [ "$TAR" -eq "$BASELINE_TAR" ] || fail "tar size drifted beyond the exact match (archive format or dependency drift; update ADR 0002)"
    within_tol "$XZ" "$BASELINE_XZ" "$XZ_TOL_PCT" || fail "xz size outside ±${XZ_TOL_PCT}% band (update ADR 0002)"
  fi
  echo "vendor.sh: --check OK (no drift vs ADR 0002)"
fi
