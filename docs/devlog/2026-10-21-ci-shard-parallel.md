# 2026-10-21 -- CI wall-clock restructure: shard-parallel attested arms

Lane: ci-optimization (branch `feat/ci-shard-parallel`, base `b03a404`).
Goal: PR wall-clock <= 35 min at the 95th-percentile arm with zero test
removal or weakening. The full lane manifest (measured before/after tables,
evidence paths, decisions) is `/tmp/ciopt/manifest.md`; this devlog records
what the repository itself needs to remember.

## Why the old shape could not hold

The banked baseline (run 39536641469) put `guards` at 79 min owned by one
serial repo-mode testthat process (4754 s step) and `coverage` at 63 min
owned by one `covr::package_coverage(type = "all")` pass (3777 s). The
file-level census over the guards transcript shows why re-balancing alone
fails: `test-check-layout-sim.R` alone measured 2496 s of the 4562 s suite
(54%) -- two ~20-minute nested simulates inside single `test_that` bodies.
No partition of that file into shards can finish under 35 min, and the
card forbids removing or weakening it.

## What changed

1. **The sim file was split, verbatim, 1 -> 3** (`test-check-layout-sim.R`
   keeps the argv/boot units; `test-check-layout-sim-sentry.R` takes the
   full-suite sentry unit; `test-check-layout-sim-stale.R` takes the
   stale-candidate law unit). `test_that` bodies are byte-identical to
   `git show HEAD:...` (containment-asserted at extraction); headers add
   provenance. Tests are unchanged in number and content; only the file
   boundary moved so the scheduler can place the two heavy units on
   different shards.
2. **One committed partition, three consumers.**
   `tools/ci/shard-manifest.tsv` (generated deterministically by
   `tools/ci/gen-shard-manifest.R`, an LPT bin-pack over the measured
   `tools/ci/shard-weights.tsv`) drives the guards shards, the per-platform
   check-test fan-outs, and the covr shards. `guard-prep` byte-gates the
   committed witness against a live regeneration, and
   `tests/testthat/test-ci-shard-map.R` (9 units, written RED first) is the
   in-suite census: exhaustive, disjoint, ordered, byte-stable, with the
   aggregator's and runner's self-test controls required to print their
   FIR lines (vacuous-green law).
3. **Arms.** `guard-prep` (static guards + single vendor + matrix emit) ->
   `guards-shards` (one shared `R CMD INSTALL`, K=6 parallel attested
   `run-testthat-shard.R` processes) -> `guards` (strict census aggregate).
   The four representative `R CMD check` arms stay verbatim; the other four
   run `check --no-tests` + INSTALL + K attested shards
   (`R-CMD-check-fanout`, matrix emitted from
   `tools/ci/fanout-configs.tsv`). `coverage` fans K instrumented
   `covr::package_coverage(type = "tests")` shards plus examples/vignettes
   through `covmerge.py` to the same `cobertura.xml` codecov contract; its
   census aggregate runs `--advisory`, matching the arm's long-standing
   `continue-on-error` law -- defects are LOUD, not fatal.
4. **The no-vacuous-green net.** Every shard process ends by writing an
   `MSUITER-ATTEST` line (files/tests/executed/pass/fail/error/skip/status)
   via the shared census reporter in
   `tests/testthat/helper-ci-shard-census.R`. `tools/ci/ci-shard-aggregate.py`
   dies on a missing attestation, on `executed == 0`, on unknown shards, on
   failures; the workflow never aggregates hand-typed fixtures. Both
   instruments ship self-tests that must be observed FIRING, and the live
   proof is banked: when the runner was momentarily broken (missing
   `package =` for `test_dir(load_package = "installed")`) the aggregate
   printed `DEFECT missing attestation ... (6)` rather than passing.
5. **Dependency caching.** `use-cache: true` now on every
   `setup-r-dependencies` step (previously absent -- the cold oldrel-1
   install measured 931 s). First run on a fresh key is still cold; that is
   a per-key one-off, not steady state.

## Laws this lane encoded

* **pre_clean = FALSE on covr shards is load-bearing.** `covr`'s pre-clean
  deletes the shared `src/rust/target` tree; K shards on one checkout
  delete each other's live cargo build (witnessed locally as
  incremental-deletion corruption). Each shard isolates its *install* via
  `install_path = tempfile()`; cargo's own lock serializes the shared
  *build*.
* **One in-tree INSTALL per process group.** Concurrent
  `R CMD INSTALL .` race `src/Makevars`' `rm -Rf src/.cargo` clean-up.
  The topology gives each job one install and every shard runs against it.
* **The fan-out shape is `test_dir(..., load_package = "installed")` from
  the checkout** -- a superset of the old installed check-test phase:
  helpers resolve `.ms_root`, so drift guards and the sim family execute
  instead of skipping. The heavy sim units take the lane's own (identity-
  attested) install rather than re-provisioning, which is what removes the
  parallel-provision contention the old single process paid for serially.
* **K=6.** The makespan (sentry ~1250 s) sets the floor; six shards balance
  the tail to ~378 s so parallel wall ~= makespan. More shards add
  bootstraps without shrinking the floor.
* **The census reporter re-arms the certified engine rows at every file
  boundary.** Registry-contract files call `msuiter_registry_reset()` and
  the wipe persists until a later file re-registers; the historical serial
  order was green only because `test-m2-e2e.R` (which re-arms ard/sparse
  idempotently, its own comment: "test file order is not contractual")
  happened to sort between the poisoners and the victims. Shard composition
  makes file order an adversary, so the shared reporter calls the three
  registration wrappers (guarded-idempotent by design) before each file --
  scheduler infrastructure; no test body or assertion is touched.
* **Shard breadcrumbs print to stderr.** The covr child's death transcript
  arrived truncated when the reporter printed to block-buffered stdout
  (redirected file: the buffered tail was lost at the halt); FILE/FAIL/ERROR
  lines are a dead shard's last words and must stream unbuffered.
* **`.ms_root` recognizes only a CHECKOUT DESCRIPTION.** The ancestor-walk
  from the test cwd accepted any `Package: msuiter` DESCRIPTION -- and an
  INSTALLED one says the same, so covr's installed testthat child resolved
  the root INTO its temp library, where the committed-file laws
  (`src/rust/Cargo.toml`, `tools/ci/*`) LOUDLY died. The `Built:` stamp
  INSTALL writes is the discriminator: a checkout or extracted-tarball
  DESCRIPTION never carries it, so gating contexts resolve unchanged and
  the install context now takes the documented NA-skip path with an
  explicit reason. (The historical covr main step had been dying exactly
  this way, tryCatch-swallowed under continue-on-error -- a vacuous green
  that the attestation net refuses to inherit.)
* Local validation exports `SDKROOT` to the Xcode SDK: a workaround for a
  malformed `libSystem.B.tbd` in this machine's Command-Line-Tools beta
  SDK. CI runners are unaffected and the workflows do not set it.

## Roster delta

Check-run arms 13 -> 15: adds `guard-prep` and `guards-shards`; the eight
`R-CMD check --*` display names are preserved verbatim (two jobs emit the
same four names). `tools/ci-selfcheck.py` polices the new contract (roster
count, matrix union disjointness vs. fan-out TSV, `--no-tests` binding,
strict-vs-advisory posture per arm, instrument existence) with its
deep-checks sections untouched.
