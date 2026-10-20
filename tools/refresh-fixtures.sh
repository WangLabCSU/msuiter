#!/usr/bin/env bash
# =============================================================================
# tools/refresh-fixtures.sh -- one-shot regeneration entry for the
# repo-regenerable fixtures (U-M1s-13).
#
# Against CONTRIBUTING.md section 5, the "fixture / golden refresh protocol
# (team iron law)":
#   * ANY golden-fixture update (bit-exact semantic goldens, numeric-protocol
#     goldens, RNG goldens, channel reference files) must state its upstream
#     reason in the matching devlog (docs/devlog/YYYY-MM-DD-<unit>.md);
#     golden changes without a stated reason are refused outright. This
#     script only regenerates -- it is never itself a reason to update: after
#     a regeneration, a non-empty git diff means STOP and write the devlog
#     first.
#   * RNG-golden regeneration requires a fresh LAYOUT_ID (section 5; domain
#     separation) and is out of this script's scope.
#   * The channel registry's single source of truth is
#     data-raw/build_channels.R; after any regeneration the
#     test-channels-sync.R and tools/docs-sync.R guards must both be green.
#
# Channel table (fixture -> regeneration entry):
#   1. channel table (R/sysdata.rda + src/rust/catalog/src/channels.rs)
#        -> Rscript data-raw/build_channels.R
#      deterministic, idempotent, no network (self-attesting clause in that
#      script's header); this script runs it directly.
#   2. channel-reference (tools/channel-reference/*.txt)
#      SigProfilerPlotting upstream anchors; re-downloading needs network ->
#      only the manual command is printed, never auto-run (changes must
#      carry an upstream reason in a devlog + an updated provenance note in
#      that directory's README).
#   3. kl-crosscheck experiment inputs (tools/kl-crosscheck/data/inputs/)
#        -> MSUITER_FIXTURES_ONLY=1 Rscript tools/kl-crosscheck/run_experiment.R
#      fixtures-only mode: generates the inputs only (seeds are recorded
#      inside the script), does not run the cross-check experiment itself.
#      Note: data/outputs/ holds the RECORDED experiment's products
#      (U-M1s-14 result.md) and is out of regeneration scope; to re-run the
#      full experiment drop that environment variable (~1.5 minutes).
#   4. tally/2bit fixtures (22-record golden batch + LE 2bit writer): no
#      script needed -- generated inside the tests, regenerated on every
#      test run, with zero on-disk footprint in the repository:
#        - R side: tests/testthat/helper-tally.R (.tally_write_2bit /
#          .tally_golden_records; the single source for test-ffi-tally.R and
#          test-catalog-tally.R since U-M1s-13);
#        - Rust side: the inline golden generators in src/rust/src/tally.rs
#          and src/rust/catalog/tests/genome/fixture.rs.
#      (bench/m1s performance fixtures likewise: generated deterministically
#      by the bench scripts, never landed in the repository.)
#
# Requires: R (>= 4.3) + the NMF package (channel 3); git (idempotency
# self-check).
#
# Usage:
#   bash tools/refresh-fixtures.sh           # regenerate (channels 1, 3) + print channel 2
#   bash tools/refresh-fixtures.sh --check   # idempotency: assert the tree is clean after regeneration
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECK_MODE=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=1
fi

say() { printf '%s\n' "$*"; }

# --- snapshot: record the tree state at entry; the idempotency assertion =
#     = regeneration introduces no NEW drift -----------------------------------
#     (a clean tree at entry is NOT required: what is asserted is AFTER == BEFORE,
#      i.e. the regeneration entry itself is idempotent and touches no fixture; if
#      uncommitted content already existed at entry, drift detection is relative
#      to the entry state.)
snapshot() {
  git status --porcelain
}
BEFORE="$(snapshot)"

# --- channel 1: the channel table (deterministic, idempotent, no network) ----
say "== [1/3] channel table: Rscript data-raw/build_channels.R =="
Rscript data-raw/build_channels.R

# --- channel 3: kl-crosscheck experiment inputs (generate the inputs only,
#     do not run the experiment itself) -----------------------------------------
say ""
say "== [2/3] kl-crosscheck inputs: MSUITER_FIXTURES_ONLY=1 Rscript tools/kl-crosscheck/run_experiment.R =="
MSUITER_FIXTURES_ONLY=1 Rscript tools/kl-crosscheck/run_experiment.R

# --- channel 2: channel-reference (needs network; prints the command only) --
say ""
say "== [3/3] channel-reference (tools/channel-reference/*.txt) -- needs network, run manually =="
say "  Sources (see that directory's README.md for the full provenance and license):"
say "    SigProfilerPlotting @ master, commit 9be822faafc9b9933c75b78f0d59f2bfa35d657b"
say "    path sigProfilerPlotting/reference_formats/{SBS96,SBS384,SBS1536,DBS78}.txt (BSD-2-Clause)"
say "  Manual refresh command template:"
say "    for f in SBS96 SBS384 SBS1536 DBS78; do"
say "      curl -fsSL \\\\"
say "        \"https://raw.githubusercontent.com/AlexandrovLab/SigProfilerPlotting/9be822faafc9b9933c75b78f0d59f2bfa35d657b/sigProfilerPlotting/reference_formats/\${f}.txt\" \\\\"
say "        -o \"tools/channel-reference/\${f}.txt\""
say "    done"
say "  After a refresh you MUST: compare the diff, update the README.md provenance note"
say "    (source/date/license), state the upstream reason in a devlog, and keep"
say "    testthat's test-channels-reference.R green."

# --- channel 4: tally/2bit fixtures -- generated inside the tests, no script
#     (see the header channel-table note) ---------------------------------------

# --- idempotency verdict ------------------------------------------------------
AFTER="$(snapshot)"
say ""
say "== idempotency self-check (regeneration must introduce no new drift: AFTER == BEFORE) =="
if [[ "$AFTER" == "$BEFORE" ]]; then
  say "PASS: the regeneration entry is idempotent -- the tree state after regeneration is"
  say "      line-identical to entry (fixtures and committed content byte-identical)."
else
  say "DIFF non-empty -- regeneration introduced new drift (a golden change must first"
  say "      carry its upstream reason in a devlog, CONTRIBUTING section 5):"
  say "$AFTER"
  say "(git diff --stat)"
  git diff --stat | tail -n 5
  if [[ "$CHECK_MODE" == "1" ]]; then
    say "--check mode: FAIL."
    exit 1
  else
    say "(not --check mode: the differences are kept for human review; commit them with a"
    say " devlog once the reason is confirmed.)"
  fi
fi
