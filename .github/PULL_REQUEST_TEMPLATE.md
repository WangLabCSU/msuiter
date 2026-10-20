<!-- Before submitting: tick every box; where a row does not apply, state the
     reason in the description. -->

## What changed

<!-- What was done and why (link the issue / ROADMAP work-unit id, e.g.
     U-M1s-03). -->

## Checklist

- [ ] **FFI-surface change declaration**: does this PR touch the `msffi_*` /
      `ms_*_rust` export surface?
    - **No**.
  - **Yes** -> per the frozen protocol in
    [docs/ffi-surface.md](../docs/ffi-surface.md), the "export manifest"
    and "export detail table" sections were updated in lockstep
    (including `since` and `status`); the drift guard
    `tests/testthat/test-ffi-surface-drift.R` stays green; and the
    change is declared below (added / removed / signature change /
    error-protocol change). A published `ms_*_rust` kernel export is
    frozen: a semantic change = a new export name + the old name
    gets `lifecycle::deprecate_warn`.
- [ ] **fixture / golden refresh**: no golden fixture was updated; or it was
      updated WITH its upstream reason stated in a devlog
      (`docs/devlog/`: upstream version/commit/protocol change or the
      correction basis) -- link: <!-- devlog path -->. An RNG-golden
      regeneration requires a fresh `LAYOUT_ID`.
- [ ] **MSRV pins held**: `matrixmultiply = 0.3.9` and `rayon = 1.10.x`
      did not drift with `cargo update`; `Cargo.lock` is still version 3
      (docs/adr/0002 section 4.4).
- [ ] **Dependency discipline**: no new dependency; or one added WITH an ADR +
      a docs/adr/0002 section 2 vendor-baseline increment +
      `tools/vendor.sh --check` green; the rand family is still at zero.
- [ ] **docs-sync green**: `Rscript tools/docs-sync.R` passes (no drift
      between the ARCH/ROADMAP `ms_*` API and the CAPABILITY-MATRIX L-H
      table).
- [ ] **Tests first**: new behavior ships with tests (red before green);
      error paths assert the condition, not a crash.

## Local acceptance battery

<!-- The full CONTRIBUTING.md section 2 checklist; paste the key output
     summaries. -->

- [ ] Rust: `cargo test` / `cargo clippy -- -D warnings` / `cargo deny check`
      / `tools/check-dep-direction.sh` / `tools/vendor.sh --check` /
      `tools/rng-kat.py` all green
- [ ] R: `devtools::test()` all green; `R CMD check --no-manual` no
      regressions (0 errors / 0 warnings)
- [ ] `Rscript tools/docs-sync.R` green
