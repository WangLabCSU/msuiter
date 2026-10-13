# ADR 0001: the 2bit reader selection — adopting the `twobit` crate (over `Cursor<Mmap>`)

- Status: accepted (2026-09-28)
- Adjudication unit: the U-M0-02 M0 spike (the W1 hard deadline)
- The upstream basis: ARCHITECTURE.md §0 D7, §2 (the catalog/genome.rs entries); reviews/00-synthesis.md §4 the last row (02#11: try both roads, decide the ADR by the byte-swap/big-endian validation results, the default inclination the crate)
- Unlocked: the reserved slot of `twobit` in the workspace dependency budget (D7); `catalog/genome.rs` (U-M1s-08)

## 1. The background

The Rust fast path of `ms_tally()` needs to random-access the 2bit reference genome by chromosome (an in-process mmap, used-then-released, D12 stateless). D7 reserved the two roads, and this ADR adjudicates them by experimental evidence:

- **Plan A (the crate)**: the third-party `twobit` crate wrapped over a memory-mapping buffer (the `Cursor<Mmap>` form).
- **Plan B (self-developed)**: a 244-line self-developed reader (zero new dependency).

## 2. The experiment setup (reproducible)

The experiment crate sits at `tools/spike/twobit-spike/` (checked into the repository together with this ADR as reproducible evidence; an independent `Cargo.toml` + `[workspace]` isolation, not a member of the package workspace, excluded from the R package tarball via `.Rbuildignore`), with three components:

1. **The fixture generator** (`src/fixture.rs`): deterministically generates complete 2bit files from logical content (the magic 0x1A412743, version 0, multi-chromosome index, the 4-bit packed bases T=0/C=1/A=2/G=3 with the first base in the high bits, the N block, the mask block, the reserved), while also producing a **big-endian layout variant** (every u32 field byte-swapped) and the bit-for-bit ground truth (the sequences with the N substitution, the soft-mask lowercase variant, the block coordinates, the chrom sizes). The fixtures cover: sizes that are not multiples of 4 (chr1=1003, chrM=17, chr2=4000); the N block at position 0, in the middle, spanning the file end, two adjacent blocks; the soft block overlapping the N block (N takes precedence, consistent with the crate's post-processing order).
2. **The two-plan reader**: A = `twobit::TwoBitFile::from_buf(...)` (including the measured `Cursor<&Mmap>`); B = the self-developed prototype (`src/own.rs`, 244 lines, likewise an `AsRef<[u8]>` zero-copy parse + random access by chromosome offset).
3. **The test matrix** (`tests/spike.rs`, 7 entries): the full ground-truth bit-for-bit comparison of {little-endian, big-endian} × {crate, self-developed} (the whole sequences + 8 windows/chromosome + the N/soft block coordinates + the chrom sizes + the softmask toggle) + the cross-check of the two readers + the `Cursor<&Mmap>` form (a real file mmap) + the bad-magic rejection.

**The byte-swap/big-endian validation caliber**: the little-endian and the big-endian file of the same logical content must both be parsed correctly by the reader and agree bit-for-bit in output (a checkable proxy for big-endian host correctness). The `twobit` crate auto-detects via the magic and its reversed value (0x4327411A) and flips all the u32 fields.

## 3. The experiment results

| The test | rustc 1.97.1 (stable) | rustc 1.71.0 (MSRV) |
|---|---|---|
| the crate × little-endian = ground truth | pass | pass |
| the crate × big-endian = ground truth | pass | pass |
| the self-developed × little-endian = ground truth | pass | pass |
| the self-developed × big-endian = ground truth | pass | pass |
| the crate ≡ the self-developed (both layouts, the sequences + the block coordinates) | pass | pass |
| the crate over `Cursor<&Mmap>` (both layouts, a real file mmap) | pass | pass |
| the two readers reject the bad magic | pass | pass |

`cargo test` 7/7 all green (each of the two toolchains ran a pass). The caliber issue discovered and fixed along the way: the index record's `nameSize` is **1 byte** per the UCSC specification (not a u32) — the crate implementation is correct, the fixture's first version was wrong and has been corrected, the two agreeing on this semantics.

## 4. The adjudication dimensions

| The dimension | Plan A: twobit 0.2.2 | Plan B: self-developed |
|---|---|---|
| License (D1) | **MIT** (Bethune & Smirnov), not GPL ✓ | none |
| Runtime dependencies | **0** | 0 |
| MSRV | no declaration; **measured: compiles + tests pass on 1.71.0** (the accompanying libc 0.2.189 and memmap2 0.9.11 likewise pass) | measured pass on 1.71 |
| The API fit (the Cursor<Mmap> streaming + the random access by chromosome) | `TwoBitFile::from_buf(&mmap)` (`Cursor<&Mmap>: Read+Seek`, zero-copy); the header/index parsed once, the sequences random-accessed by offset; `read_sequence(range)`/`chrom_names/sizes`/`hard_masked_blocks`/`soft_masked_blocks`/`base_counts`/`enable_softmask` | equivalent capability prototype-verified, but the whole maintenance self-carried |
| The big-endian/byte-swap | built-in detection, the experiment passes bit-for-bit | self-implemented, the experiment passes bit-for-bit |
| Maintenance activity | 0.2.2 released on **2026-03-27** (an update within the year, fixing the big-endian reads among others); 5 versions since 2020; the repo github.com/jbethune/rust-twobit; ~14.8k crates.io downloads | the whole lifecycle cost self-carried |
| The size/impact surface | 24.7 KB of source, 1554 lines, the vendor increment ~0.09 MB uncompressed (+0.017 MB after xz, see ADR 0002) | 0 |
| The watch-outs | the crate internally contains `unsafe { String::from_utf8_unchecked }` (provably safe under ASCII); it exists only inside the dependency, engine/catalog still `#![forbid(unsafe_code)]`; errors go through `Result` (the bad magic is cleanly rejected per the measurement, no panic) | none |

## 5. The decision

**Adopt plan A: the `twobit` crate (version 0.2.2, `twobit = "0.2.2"`)**. The prior inclination toward the crate is confirmed by the evidence: a clean license, zero runtime dependencies, the measured MSRV meets the bar, the API matches the `Cursor<Mmap>` form of ARCH §2 word for word, active maintenance.

The dependency-unlock record (the D7 reserved slot):
- `src/rust/Cargo.toml` `[workspace.dependencies]` adds `twobit = "0.2.2"`;
- `src/rust/catalog/Cargo.toml` declares `twobit = { workspace = true }` (the genome.rs implementation belongs to U-M1s-08, this unit does not touch the rest);
- `deny.toml`: after the review corrections the full `cargo deny check` is green — the licenses whitelist adds `Unicode-3.0` (the `(MIT OR Apache-2.0) AND Unicode-3.0` of unicode-ident), the three crate manifests add `license = "Apache-2.0"` (clearing the unlicensed), the advisories adopt the `unmaintained = "workspace"` policy (the paste RUSTSEC-2024-0421 arrives transitively via extendr-api 0.9, unfixable by us, and does not block; when upgrading extendr-api re-check the full check, the checklist goes into the U-M0-08 CONTRIBUTING); the ban rules are unaffected.

**The rollback clause**: the dependency is pinned via the vendor (ADR 0002), the supply-chain risk bounded. Should the upstream go unmaintained and block upgrades, the self-developed prototype of plan B (244 lines + this ADR's interface contract, `tools/spike/twobit-spike/src/own.rs`) is the verified fallback path, and switching affects only `catalog/genome.rs`.

## 6. The U-M1s-08 interface contract (to be observed on the self-developed fallback or wrapping)

- The input: an `AsRef<[u8]>` buffer (an mmap used-then-released, D12 stateless); the header/index parsed once, the sequences random-accessed by `(offset, i/4)`.
- The byte order: magic==0x1A412743 → as is; magic==0x4327411A → all the u32 fields swapped; the index `nameSize` is 1 byte.
- The decoding: 2 bit/base, the first base in a byte in the high bits, T=0/C=1/A=2/G=3; after decoding, the N block positions get 'N', the soft block positions then get lowercased (the order fixed); the packed bits of the N block are don't-care.
- The errors: `Result<_, E>`, a format error does not panic; a version ≠0 is rejected.

## 7. The residues

- This experiment covered macOS arm64 only (R 4.5.2, xz 5.6.4, rustc 1.71.0/1.97.1); the big-endian irrelevance on Linux/Windows is carried over by the same test matrix in the U-M0-07 CI matrix (the tests are portable, the experiment crate is checked in with this ADR, `cargo test` inside `tools/spike/twobit-spike/` re-runs directly).
- The experiment crate is not in the release tarball (`/tools/spike` is in `.Rbuildignore`); the comparison caliber of `tests/spike.rs` lands at U-M1s-08 as the formal tests of `catalog/genome.rs` (the BSgenome cross-check counted separately).
