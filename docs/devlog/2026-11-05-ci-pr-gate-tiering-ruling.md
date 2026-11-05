# 2026-11-05 -- CI PR-gate tiering ruling: three arms, one tier, nightly depth

Lane: ci-issue-76 (branch `ci/issue-76`, base origin/main@32276be).
Goal: the accepted ruling on issue #76 -- the per-PR battery measured a
~2.5 h wall for work the PR does not need. Four proposals, adopted item by
item; the heavy files MOVED, nothing was removed or weakened.

## Why the old shape could not hold

The issue's measured table (2026-11-04) is the committed basis: the two
check-layout-sim provisioning simulations weighed 1250 s + 1231 s, the xval
campaign 948 s, refdb 373 s, ms-qc sentries 280 s -- together ~75 % of the
suite's 4902.7 s of committed weight, yet every one of them ran on EVERY
one of the eight fan-out arms PLUS a second full-roster pass in
guards-shards PLUS the covr lane. A pull request paid ~2.5 h to re-measure
provisioning physics and the nightly science on every push. The
CI-lean ruling (owner, 2026-10-25) already says long tests live locally;
the manifest simply never said which tier was whose.

## The ruling

1. **Tier is a committed column of the partition.** The manifest rows are
   now `shard<TAB>file<TAB>seconds<TAB>tier`: T0 the PR-gate battery
   (87 files, integer weight 612 s -- re-priced at every fan-out census
   against tools/ci/pr-gate-budget.tsv, ceiling 800), T1 the named
   scheduled deep battery (xval, refdb, ms-qc sentries, benchmark driver),
   T2 the heavy class -- the two simulations moved verbatim to
   `tests/heavy/` and run only through `tools/test-heavy.R`, the local
   one-command face (and the nightly job). The generator enforces the
   location law (T2 lives iff tests/heavy) and dies on budget drift or
   over-ceiling; the byte-gate replay stays exact.
2. **The PR gate fans out three release arms.** `fanout-configs.tsv` is
   now macos/ubuntu/windows x release. The five version arms (ubuntu 4.3,
   devel, the three oldrel-1) moved verbatim -- the hard-mode 4.3
   provisioning, the devel user-agent, the continue-on-error law -- into
   the nightly `R-CMD-check-version-fanout` in scheduled.yml, rostered by
   `tools/ci/scheduled-fanout-configs.tsv` (six arms: the five plus an
   ubuntu/release witness, because the T1 battery needs a release-R Linux
   measurement). The eight-arm census survives as the union of the two
   committed rosters; check-run census 15 -> 10 with its firing control
   flipped in the same breath, -> 9 when the coverage leg followed below.
3. **Depth moved, coverage did not.** The PR-gate fan-out runs
   `--tier=T0` only; the version fan-out runs `--tier=T0,T1`, so every
   test still runs on every platform -- on the cadence that matches its
   cost. The covr runner's `--tier` is mandatory (T0/T1): the T2 files
   were the covr ledger's two vacuous rows, and retiring the rows with the
   tier ruling left the ledger legitimately empty -- an empty active
   ledger is lawful exactly while the tier law holds (the R-side unit
   speaks it, with a ban on the retired names reviving). The covr JOB
   itself -- the leg that instruments the committed suite and never
   vetoes a pull request -- moved verbatim from ci.yml to scheduled.yml:
   its gating census, its zero-fragment merge law, its witnessed 180
   budget and its codecov upload travelled with it.
4. **Keep-as-is, audited.** The rust/msrv shape, the vendored cargo
   contract and the concurrency cancel-in-progress law already match the
   proposal's intent; the Swatinem/rust-cache adoption the issue asked to
   "measure before adopting" is already committed (with the
   extendr-ffi-cache-invalidation law). The bit-identity battery stays in
   T0 as machine law -- pinned in the map and selfcheck units.

## Measured

Weights table (generator-verdict line): `k=6 files=93 t0-weight=612s
(ceiling 800)`; tier sums T0 612.7 s / T1 1809.0 s / T2 2481.0 s. The T0
wave alone packs to a 172 s makespan -- the PR-gate testthat phase is a
~3-minute wave where the full-roster K-wave ran ~25+ min (and rode 10
gates). Projected per-push critical path per slim arm: setup ~2.5 min +
build+check (no-tests) ~14 min + INSTALL ~1 min + T0 wave ~3 min.
Full attestation sweep banked in the lane evidence
(/tmp/issue76lane/evidence): generator byte-gate, aggregator/runner/heavy
self-tests with every new control FIR/GREEN, law units nb/failed/error/
skipped read from `as.data.frame`, ci-selfcheck PASS.

## The second breath: coverage nightly, guards retargeted

The PR gate's second full-roster pass was `guards-shards`: its K-shard
testthat wave duplicated what the three release arms plus the nightly
T1 lanes now carry, so the wave retired -- the lane keeps the shared
`R CMD INSTALL` of the tree under test and the fail-closed
package/namespace declaration census, and its budget came down from the
witnessed 120 (kept as history in the file, with the two co-tenancy kill
witnesses) to the 45-minute guard-prep class.

`guards` -- the attestation gate -- retargeted from that wave onto the
fan-out evidence itself: it downloads the three arms' attestations and
censuses each arm data-driven off the committed roster (`while
IFS=$'\t' read` over `fanout-configs.tsv`; `download-artifact` cannot
loop, so the three download steps are literal while the census is not).
Every census is tier T0, budget-bearing (`--t0-budget`
re-prices the committed measurement on every run), per-arm expected via
`--expect-config`, and `--advisory` stays dead. The retargeted loop is
attested by executing the committed step verbatim against fabricated
evidence (lane evidence, `C3-guards-loop.txt`): complete evidence exits
0; a deleted shard file dies LOUD (`DEFECT missing attestation: ...
(shard 4)`); a missing arm directory -- the shape a forgotten download
step leaves -- dies LOUD (`DEFECT attest-dir absent: ...`, the
aggregator's new attest-dir-absent firing control). Three claims, all
measured.

Hardening caught on the way (all in the same change set): the
generator's four fail-closed exit-2 paths were silent and now speak
(CLI-face law); the census loop's comment guard went from `'\#'` to
`'#'` so bash 3.2 -- the local re-run face -- matches it too; the covr
runner's mandatory-`--tier` DEFECT and loud tier-skip were re-smoked.

## Discrepancies against the issue's 2026-11-04 measurement

The tree drifted since the measurement: 93 test files, not 92; "everything
else <= ~40 s" no longer holds (ms-qc-report 112 s and the kernel pair
172 s + 79 s exceed it) -- ms-qc-report stays T0: it is fast-high-signal,
not named by the proposal, and the ceiling law bounds it anyway. The
issue's "coverage job in the PR gate" is retired by item 3 of the same
ruling -- the leg rides the nightly gate; what the PR gate keeps is the
fan-out, three arms, one tier.
