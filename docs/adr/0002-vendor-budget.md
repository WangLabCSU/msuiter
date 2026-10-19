# ADR 0002: the vendor size budget and the MSRV build proof (the U-M0-02 spike)

- Status: accepted (2026-09-28); size-law amendment 2026-10-20 (§2, the vendor-gate law repair)
- Adjudication unit: the U-M0-02 M0 spike (the W1 hard deadline)
- The upstream basis: ARCHITECTURE.md §0 D4, §2 build entry 8 (Makevars.in on the string2path pattern + vendor.tar.xz + offline + CARGO_BUILD_JOBS=2 + cleanup; the MSRV target 1.71); IMPLEMENTATION-PLAN.md §3.1 U-M0-02
- Related: ADR 0001 (the twobit unlock, the final dependency tree containing twobit 0.2.2)

## 1. The experiment environment (this machine's proof scope)

macOS arm64 (Darwin 25.6.0), R 4.5.2, xz 5.6.4, cargo/rustc stable 1.97.1, rustc 1.71.0 (rustup minimal profile). **Platform residue: the Linux/Windows build proofs are carried by the U-M0-07 CI matrix, not covered by this ADR.**

## 2. The vendor size numbers (the final dependency tree, with twobit)

The command (in `src/rust/`, the lock state = Cargo.lock v3, matrixmultiply pinned to 0.3.9, see §4):

```sh
cd src/rust
cargo vendor vendor
find vendor -type f -print0 | xargs -0 stat -f%z | awk '{s+=$1} END {print s}'
tar -cf /tmp/vendor.tar vendor && stat -f%z /tmp/vendor.tar
tar -cJf /tmp/vendor.tar.xz vendor && stat -f%z /tmp/vendor.tar.xz   # xz -6 default level
```

| The caliber | The byte count | MiB |
|---|---|---|
| `vendor/` uncompressed (22 crates, 970 files) | **10,674,351** | 10.18 |
| tar (uncompressed) | 13,832,192 | 13.20 |
| **tar.xz (`tar -cJf`, xz -6)** | **1,125,136** | **1.07** |

The reference baseline (the 21 crates before adding twobit: 10,580,063 / 13,652,480 / 1,107,780 bytes); `xz -9e` vs the default `-6` differ <0.1% (1,102,288 vs 1,102,296 @ the baseline), adopting the default level suffices. Compression ratio ≈ 12.3:1.

**The incremental record (appended per this section's discipline)**:

| The date | The unit | The new vendor content | The uncompressed increment | The xz increment | The new baseline (uncompressed / tar / xz) |
|---|---|---|---|---|---|
| 2026-09-28 | U-M0-09 | rayon 1.10.0 + rayon-core 1.12.1 (the FFI per-call thread pool, a dependency within the ARCH §2 budget; the lock pinning because ≥1.11 needs rustc 1.80, the method same as §4) | +1,851,707 B | +282,452 B | **12,526,058 / 16,516,096 / 1,407,588** |
| 2026-09-30 | the U-M1s-08/09 merged record | memmap2 0.9.11 + libc 0.2.189 (libc is a transitive dependency of memmap2, the all-platform generated bindings about 4.4 MB). **The attribution correction (audit)**: the two crates in fact entered the lock as a catalog dev-dependency at U-M1s-06/07/08 (commit 6885078) — cargo vendor includes dev-deps, so the budget had already changed at that point; U-M1s-09 (ms_tally_rust) then raised memmap2 to a root-crate main dependency. The two unrecorded events are folded into this row. **The discipline-gap declaration: the increments were not recorded per this section's discipline, discovered first by the --check rehearsal of the v0.1 release preparation (the baseline stale +37.6%)**; the upward-tracing row "22 crates (the U-M0-02 baseline)" label should likewise be read as "the lock's actual state then" (evolutions such as the syn dual version were not recorded line by line) | +4,712,247 B | +456,028 B | **17,238,305 / 22,952,960 / 1,863,616** |

The current effective baseline = the last row of the above table; the built-in constants of `tools/vendor.sh --check` are updated accordingly (the xz caliber still keeps the ±0.1% version-tolerance band -- SUPERSEDED 2026-10-20 by the size-law amendment at the end of this section).

| 2026-10-05 | the v0.1 release gate (release.yml activation) | **The baseline re-anchored to the MSRV 1.71 toolchain**: the audit found the vendor artifacts are cargo-version-relative — the local 1.92 yields 17,238,305 B, the release gate (MSRV 1.71) yields **16,911,999 B** (the difference of 326,306 B is a cargo packaging-behavior difference, the 33-item dependency set unchanged). The baseline is henceforth pinned to the release-gate toolchain; running --check on the local default toolchain shows DRIFT (by design), the verification command = `rustup run 1.71.0 sh tools/vendor.sh --check` | −326,306 B | −4,633,600 B | **16,911,999 / 18,319,360 / 1,744,176** |

**The budget judgement**: vendor.tar.xz currently ≈ 1.71 MB (the MSRV 1.71 baseline), plus the whole package source (src/rust 13 KB + the R/-side ~48 KB order of magnitude) still far below the CRAN 5 MB package-size guidance line; for subsequent new dependencies every ~0.1 MB xz increment requires an appended record in this ADR, and going over budget triggers the dependency-re-contraction decision (the ARCH §11 risk entry).

**The size-law amendment (2026-10-20, the vendor-gate law repair; supersedes the xz band clause of the effective-baseline row above)**: the law now reads -- UNCOMPRESSED and TAR are BYTE-EXACT laws (uncompressed asserted on every platform; the tar exact match enforced on the Linux release-gate branch); TAR.XZ is REPORTED freely and governed only by the compressor-sanity law `0 < xz < tar` (the compressor must actually compress). Why: the xz byte count is RUNNER-ENVIRONMENT-DETERMINED (xz build, threading configuration, CPU topology), not content-determined -- the "~0.01% across xz builds" premise behind the retired ±0.1% band is refuted by measurement. **The measured basis (this amendment's evidence, numbers verbatim)**: main push-run 39289131194 (main@314d2634, 2026-10-19T16:53:28Z, the guards arm) red-vented with

```
vendor uncompressed: 16911999 B (baseline 16911999 B)   -- EXACT MATCH
vendor tar:          18319360 B (baseline 18319360 B)   -- EXACT MATCH
vendor tar.xz:        1941840 B (baseline 1744176 B)    -- +197,664 B = +11.33%
vendor.sh: DRIFT DETECTED: xz size outside ±0.1% band (update ADR 0002)
```

The same workflow had passed the guards arm hours earlier on an equally-contented checkout: the xz delta is the environment, the content is bit-stable, and the content-invariance law this gate exists to protect is carried by the two byte-exact rows (both matched exactly in the failing run). A same-class control measured locally (2026-10-20, this host, the vendor-gate repair lane): five repeated runs of ONE bit-identical synthetic tree through `tools/vendor.sh` reported xz sizes 540/548/548/540/540 B -- a 1.5% spread against the retired 0.1% band, from the same environment minutes apart. An exactness band on an environment-sensitive quantity is a gate-law defect: it reds main at random with zero content change. The amended law is pinned by the four discriminations of `tests/testthat/test-vendor-gate-law.R` (content tamper RED; xz drift with unchanged content GREEN; each byte-law drift RED; full consistency GREEN -- with firing controls for both sanity clauses). The xz baseline constant 1,744,176 B remains in `tools/vendor.sh` as report context only; the xz increments in the records above stay as historical budget bookkeeping (the package-size guidance reading is a planning figure, not a gate).

## 3. Offline and the CRAN-mode build proofs

### 3.1 Pure cargo offline (the vendor directory used directly)

```sh
mkdir -p .cargo && cp vendor-config.toml .cargo/config.toml
CARGO_HOME="$PWD/.cargo" CARGO_NET_OFFLINE=true cargo build --workspace --offline   # exit 0
CARGO_HOME="$PWD/.cargo" CARGO_NET_OFFLINE=true cargo test  --workspace --offline   # 1 passed (ffi_links_engine_and_catalog)
rm -rf .cargo
```

Under `CARGO_NET_OFFLINE=true` any networking attempt makes cargo error-exit; the measured build/test all green → **offline build is feasible**.

### 3.2 The R-side CRAN mode (the vendor.tar.xz wiring, the full string2path chain)

```sh
cp /tmp/vendor.tar.xz src/rust/vendor.tar.xz        # the Makevars/config.R expected location
env -u NOT_CRAN -u DEBUG R CMD INSTALL . -l /tmp/msuiter-testlib
```

The key evidence of the measured output (exit 0, `* DONE (msuiter)`, and after the installation `library(msuiter)` loads successfully):

- `tools/config.R` detects that `src/rust/vendor.tar.xz` exists → injects the CRAN flags `cargo build -j 2 --offline --lib --release` (`CARGO_BUILD_JOBS=2` synchronously in effect);
- Makevars unpacks `vendor/` from the tarball into `src/vendor`, copies `vendor-config.toml` → `src/.cargo/config.toml` (`=== Using offline vendor tarball ===`);
- the `--print=native-static-libs` RUSTFLAGS take effect; `cargo run --bin document` generates the wrappers;
- `rust_clean` cleans `src/.cargo`, `src/vendor` and `rust/target` (the CRAN-mode cleanup contract holds).

Re-running the same command with the 1.71 toolchain also passes (see §4).

### 3.3 The vendor-artifact check-in strategy

`vendor/` and `vendor.tar.xz` **do not enter git** (both the root `.gitignore` and `src/rust/.gitignore` already cover them, verified via `git check-ignore`); after the spike the two artifacts were deleted from the workspace. At release time (U-M8-01) `tools/vendor.sh` regenerates and attaches them into the CRAN tarball (the script prints the byte counts under the three calibers, for drift comparison against the U-M0-07 CI and this ADR's baseline). `vendor-config.toml` (the offline template) does enter the repository and no longer changes.

## 4. The MSRV proof (rustc 1.71.0)

### 4.1 The baseline lock: failure (recorded exactly)

```text
$ cargo +1.71.0 build --workspace
error: package `matrixmultiply v0.3.11` cannot be built because it requires
rustc 1.75.0 or newer, while the currently active rustc version is 1.71.0
```

The root cause: ndarray 0.16.1's transitive dependency `matrixmultiply` 0.3.11 declares `rust-version = "1.75.0"` explicitly in its Cargo.toml (the same for 0.3.10); the other 22 dependencies (including syn 2.0.119/3.0.6, proc-macro2 1.0.107, once_cell 1.21.4, portable-atomic 1.15.0, twobit 0.2.2, memmap2 0.9.11) are all measured compilable at 1.71.

### 4.2 The fix: lockfile pinning (without relaxing the MSRV)

```sh
cargo update -p matrixmultiply@0.3.11 --precise 0.3.9   # 0.3.9 has no rust-version declaration
cargo +1.71.0 build --workspace   # exit 0 (a cold build)
cargo +1.71.0 test  --workspace   # 1 passed (ffi_links_engine_and_catalog)
```

### 4.3 The 1.71 × CRAN-mode end-to-end

```sh
env -u NOT_CRAN -u DEBUG R_ENVIRON_USER=/tmp/empty-renviron \
  PATH="$HOME/.rustup/toolchains/1.71.0-aarch64-apple-darwin/bin:$PATH" \
  R CMD INSTALL . -l /tmp/msuiter-testlib
# Using cargo 1.71.0 / rustc 1.71.0 → offline vendor tarball → -j 2 --offline --release → * DONE (msuiter)
```

**The conclusion**: the MSRV 1.71 declaration holds, no need to relax D4/§2; the cost is one pinning inside Cargo.lock (matrixmultiply = 0.3.9, already checked in).

### 4.4 The MSRV maintenance constraints (entering the CI/process notices, carried by U-M0-07)

1. **matrixmultiply must not, along `cargo update`, rise to ≥0.3.10** (1.75+); the dependabot/lock check must retain that pin or an equivalent rust-version gate.
2. **Cargo.lock must stay version 3** (v4 needs cargo ≥1.78 to be read); it is currently v3.
3. The this-machine reproduction pitfall: `~/.Renviron` injects `PATH="/Users/wsx/miniconda3/bin/:${PATH}"`, and inside the R subprocess the conda-bundled cargo 1.92.0 shadows the prepended toolchain directory (Makevars appends `~/.cargo/bin` to the PATH tail and cannot correct it). To verify the MSRV on this machine one needs `R_ENVIRON_USER=/tmp/empty-renviron` + the 1.71 bin prepended to the PATH; the CI images have no conda rust, unaffected.

## 5. The acceptance cross-check (the U-M0-02 [engineering] items)

| The item | The result |
|---|---|
| the real vendor + xz byte counts landed into the ADR | §2 (1,125,136 B xz) |
| the offline build proof | §3.1 pass |
| the CRAN-mode wiring proof | §3.2 pass (one pass each on the stable and on the 1.71) |
| the rustc 1.71 build conclusion | §4 pass (matrixmultiply pinned to 0.3.9; the exact error and version recorded) |
| the three-platform build proofs | **Residue**: macOS arm64 proved; the Linux/Windows carried by the U-M0-07 CI matrix |
| the vendor over budget → the dependency re-contraction decision | not triggered (1.07 MB ≪ budget) |
