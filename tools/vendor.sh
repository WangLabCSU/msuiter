#!/usr/bin/env sh
# Regenerate the offline vendor tarball and report its byte budget.
# Baseline: docs/adr/0002-vendor-budget.md §2 (33 crates current; effective baseline
# = 2026-10-31 memmap2 0.9.12 patch bump row).
#
# The tarball is NOT committed: CRAN submission (U-M8-01) attaches a freshly
# generated one to the source package. CI (U-M0-07) runs `--check` to catch
# vendor drift (dependency budget discipline, ARCHITECTURE.md §2 / D4).
#
# Determinism note (xz size band REFUTED and retired 2026-10-20; measured
# basis main push-run 39289131194, 2026-10-19T16:53:28Z, and docs/adr/
# 0002-vendor-budget.md): the uncompressed byte count is an exact invariant
# of the Cargo.lock dependency set (file contents are OS-independent) and is
# checked exactly. The tar count is checked exactly on the Linux release-gate
# platform (GNU tar). The xz count is RUNNER-ENVIRONMENT-DETERMINED (xz
# build, threading, CPU topology): the old ±0.1% band rested on a "~0.01%
# across xz builds" premise that run 39289131194 refuted -- 1941840 B
# against the 1744176 B baseline (+11.3%) while BOTH byte-exact laws matched
# exactly (16911999 / 18319360, the pre-2026-10-31 anchors). xz is therefore
# REPORTED freely but governed
# only by the compressor-sanity law 0 < xz < tar; the content-invariance law
# this gate exists to protect is carried by the uncompressed and tar byte
# baselines. Pinned by tests/testthat/test-vendor-gate-law.R.
set -eu

# Baselines are CARGO-VERSION-RELATIVE (audit 2026-10-05): the release
# gate pins MSRV 1.71 (release.yml Install Rust step), so the baselines
# are the 1.71 vendor output. Local default-toolchain runs (1.92) vendor
# +326 KB and will show DRIFT by design -- regenerate with
# `rustup run 1.71.0 sh tools/vendor.sh` to verify.
BASELINE_UNCOMPRESSED=16928778
BASELINE_TAR=18339840
BASELINE_XZ=1744176   # context/report only -- the xz LAW is sanity-only (see the header note)

# ---------------------------------------------------------------------------
# Test harness seams (used ONLY by tests/testthat/test-vendor-gate-law.R;
# never set in production). MSUITER_VENDOR_SYNTH names a directory holding a
# synthetic `vendor/` tree: the measurement runs over that tree and `cargo
# vendor` is skipped (no network, no src/rust write, no root). The companion
# seams -- MSUITER_VENDOR_BASE_{UNCOMPRESSED,TAR,XZ} (baseline injection),
# MSUITER_VENDOR_OS (platform-branch identity), MSUITER_VENDOR_FAKE_XZ
# (compressor-output size simulation) -- are honoured only when
# MSUITER_VENDOR_SYNTH is set, so the production defaults (these
# measurements and the law against them) stay byte-identical.
# ---------------------------------------------------------------------------
SYNTH="${MSUITER_VENDOR_SYNTH:-}"
if [ -n "$SYNTH" ]; then
  if [ -n "${MSUITER_VENDOR_BASE_UNCOMPRESSED:-}" ]; then BASELINE_UNCOMPRESSED="$MSUITER_VENDOR_BASE_UNCOMPRESSED"; fi
  if [ -n "${MSUITER_VENDOR_BASE_TAR:-}" ]; then BASELINE_TAR="$MSUITER_VENDOR_BASE_TAR"; fi
  if [ -n "${MSUITER_VENDOR_BASE_XZ:-}" ]; then BASELINE_XZ="$MSUITER_VENDOR_BASE_XZ"; fi
fi

filesize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

if [ -n "$SYNTH" ]; then
  [ -d "$SYNTH/vendor" ] || { echo "vendor.sh: MSUITER_VENDOR_SYNTH=$SYNTH has no vendor/ tree" >&2; exit 2; }
  cd "$SYNTH"
else
  cd "$(dirname "$0")/../src/rust"
  cargo vendor vendor > /tmp/msuiter-vendor-config.txt
fi
UNCOMPRESSED=$(find vendor -type f -print0 | xargs -0 stat -f%z 2>/dev/null | awk '{s+=$1} END {print s}')
[ -n "$UNCOMPRESSED" ] || UNCOMPRESSED=$(find vendor -type f -print0 | xargs -0 stat -c%s | awk '{s+=$1} END {print s}')

rm -f /tmp/msuiter-vendor.tar /tmp/msuiter-vendor.tar.xz
tar -cf /tmp/msuiter-vendor.tar vendor
TAR=$(filesize /tmp/msuiter-vendor.tar)
tar -cJf /tmp/msuiter-vendor.tar.xz vendor
if [ -n "$SYNTH" ] && [ -n "${MSUITER_VENDOR_FAKE_XZ:-}" ]; then
  # Synthetic seam (unit only): replace the compressor output with a file of
  # the chosen byte size -- simulates runner-environment xz output drift and
  # degenerate compressor behaviour against UNCHANGED measured content.
  if [ "$MSUITER_VENDOR_FAKE_XZ" -gt 0 ]; then
    head -c "$MSUITER_VENDOR_FAKE_XZ" /dev/urandom > /tmp/msuiter-vendor.tar.xz
  else
    : > /tmp/msuiter-vendor.tar.xz
  fi
fi
XZ=$(filesize /tmp/msuiter-vendor.tar.xz)

rm -rf vendor /tmp/msuiter-vendor.tar
echo "vendor uncompressed: ${UNCOMPRESSED} B (baseline ${BASELINE_UNCOMPRESSED} B)"

# Platform note (audit 2026-10-05; law amendment 2026-10-20): tar/xz
# containers are ARCHIVE-FORMAT relative (macOS bsdtar vs the Linux runner's
# GNU tar + xz settings); the uncompressed byte sum is the platform-
# independent dependency-set identity. The container laws (tar exact match,
# xz compressor sanity) are enforced only on Linux (the release gate
# platform); darwin checks the uncompressed exact match and reports the
# containers.
OS_NAME=$(uname -s)
if [ -n "$SYNTH" ] && [ -n "${MSUITER_VENDOR_OS:-}" ]; then
  OS_NAME="$MSUITER_VENDOR_OS"   # synthetic seam: drive the platform branch
fi
if [ "$OS_NAME" = "Linux" ]; then
  echo "vendor tar:          ${TAR} B (baseline ${BASELINE_TAR} B)"
  echo "vendor tar.xz:       ${XZ} B (sanity law 0 < xz < tar; size is runner-environment-determined -- context baseline ${BASELINE_XZ} B is report-only, not a byte law)"
else
  echo "vendor tar:          ${TAR} B (darwin: the container laws are enforced on the Linux release gate only)"
  echo "vendor tar.xz:       ${XZ} B (darwin: the container laws are enforced on the Linux release gate only)"
fi

if [ "${1:-}" = "--check" ]; then
  fail() { echo "vendor.sh: DRIFT DETECTED: $1" >&2; exit 1; }
  [ "$UNCOMPRESSED" -eq "$BASELINE_UNCOMPRESSED" ] || fail "uncompressed size drifted (dependency set changed? update ADR 0002)"
  if [ "$OS_NAME" = "Linux" ]; then
    [ "$TAR" -eq "$BASELINE_TAR" ] || fail "tar size drifted beyond the exact match (archive format or dependency drift; update ADR 0002)"
    { [ "$XZ" -gt 0 ] && [ "$XZ" -lt "$TAR" ]; } \
      || fail "xz sanity violated: ${XZ} B not in (0, tar=${TAR}) -- the compressor must actually compress (xz size is environment-determined, not a byte law; ADR 0002)"
  fi
  echo "vendor.sh: --check OK (no drift vs ADR 0002)"
fi
