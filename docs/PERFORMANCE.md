# msuiter performance anchoring

Single entry point for every speed claim about msuiter. This document
contains **no independently retyped numbers**: each value is a
verbatim, path:line-pinned quotation of a committed bench artifact,
extracted by the commands listed at the bottom in the same command
window that wrote this file, and sealed by the digests in the final
section. To audit any claim, re-run the extraction — do not trust the
rendering.

## Measured speedups (authoritative)

Source: `bench/m1s/result.md` — the M1s acceptance-gate bench summary
(`bench/m1s/result.md:1`):

> # bench/m1s · the M1s acceptance-gate bench summary (the U-M1s-13 companion; the pinned-hardware caliber, not into the CI)

The three measured kernels, quoted exactly from the summary table:

| workload | measured speedup | original target | verdict (vs original) |
|---|---|---|---|
| catalog generation, SBS96 @ 10⁶ mutations | `2.6×` | ≥50× | speedup FAIL; <5s PASS |
| KL-NMF, 96×1000, k=10, 100 iterations | `2.3×` | ≥100× | FAIL |
| batch NNLS, 101×10³, k=10 | `1.8×` | ≥10× | FAIL |

Baselines (from the same cells): SPMG for catalog generation, the
C-kernel R package `brunet` for KL-NMF, and `scipy` per-sample
linear algebra for batch NNLS — see the verbatim rows directly below.

Verbatim table rows (`bench/m1s/result.md:11, 13, 14`):

```
| the catalog generation SBS96 (the 10⁶ mutations) | ≥50× SPMG and <5s single-core | 2.6× (ours 3.73s vs SPMG 9.82s); <5s ✓ | **speedup FAIL; <5s PASS** |
| the NMF KL (96×1000, k=10, 100 iter) | ≥100× R NMF | 2.3× (ours 205ms vs brunet 0.47s) | **FAIL** |
| the batch NNLS (101×10³, k=10) | ≥10× the per-sample scipy | 1.8× (ours 6.7ms vs scipy 11.2ms) | **FAIL** |
```

And the summary's own adjudication of the pre-recalibration targets (`bench/m1s/result.md:17`):

> The ROADMAP M1s acceptance row "catalog generation ≥50× SPMG; NMF ≥100× R NMF" does not hold under this bench —

## Framing: the Plan-A recalibration (PI ruling 2026-10-05)

The original ≥50×/≥100×/≥10× rhetoric was written against baselines
that were never themselves measured — `brunet` already ships a C
kernel, and SPMG on clean input is vectorised. The PI ruling of
2026-10-05 recalibrated acceptance to the MEASURED C-class baselines,
and moved the original rhetoric to a naive-R/Python framing (`docs/ROADMAP.md:116`, verbatim; the blockquote spans `docs/ROADMAP.md:115-116`):

> [English twin of the retired ruling original; CJK corpus] phase-2, issue #25, 2026-10-19; the Chinese original lives in git blob sha256 8b905eb8151cde0c75dee4b3d3b61f5efb72cffa0e38729b6119d74615718a91). **Acceptance (v0.1 release)**: ~~catalog generation >=50x SPMG; NMF >=100x R NMF~~ -> **Plan-A caliber (PI adjudication 2026-10-05)**: the original multipliers were written against an unmeasured baseline (brunet is already a C kernel; SPMG on clean input is already vectorized); recalibrated against the measured C baselines -- catalog 2.6x SPMG (3.73s, <5s OK), NMF 2.3x R NMF brunet (C core), NNLS 1.8x scipy; the original 50x/100x/10x rhetoric moved to the naive R/Python implementation caliber (the full-pipeline dense arm at the SPMG 46s caliber may still support 50x; re-check at the hardware-pinned bench). All fixtures green; installable from r-universe. **M1s 14/14 closed.**

## Targets table (ARCHITECTURE cross-reference)

The canonical class targets, verbatim from `docs/ARCHITECTURE.md:315-321`:

<!-- census-exempt tokens: 51 260 266 (the ROADMAP/ARCHITECTURE line pins in this file were re-anchored from the baseline line numbers 51, 260-266, 266 to the translated files' 116, 315-321, 321; the old pins are named here for the numeric-preservation guard) -->

```
| Kernel | Baseline | Target |
|---|---|---|
| the catalog generation SBS96 (10⁶ mutations) | SPMG | ≥50× and <5 s single core |
| NMF KL (96×1000, k=10, 100 iter) | R NMF / rust-NMF | ≥100× R NMF; the rust-NMF alignment (tolerance) |
| the batch NNLS (101×10³) | scipy nnls per sample | ≥10× |
| the all-sample fitting | SPA ~0.21 s/sample | aligned or better |
| bootstrap (10³×10³) | sigminer serial | ≥100× |
```

## MEASURED: bootstrap vs sigminer -- the >=100x target measured FALSE

The targets table's final row (`docs/ARCHITECTURE.md:321`) sets the bootstrap
benchmark against sigminer's serial bootstrapper at >=100x:

```
| bootstrap (10³×10³) | sigminer serial | ≥100× |
```

**Status: MEASURED -- the >=100x row is false as a claim and must never be
quoted as achieved.** The RB-10 authoritative single-shot campaign
(`bench/results/bootstrap_vs_sigminer_20261013T175859Z/result.md`,
committed read-only in this PR) adjudicated the row on the pinned campaign
host:

| quantity | measured value |
|---|---|
| tier | B |
| ratio (A1 bootstrap / A2 sigminer serial) | 1.536600758177e+01 (15.37x) |
| verdict | **MEASURED-false 15.37x** |
| secondary A1/A3 (pool-scaling isolation) | 14.2209x |

Evidence chain, all committed inside the outdir: seed 20260928 (G0 master;
shape K=1000 S=1000 n_sig=50); the data seal `{"sha256":
"cc094225d599a6765dbc7958a445609459ded0f32f2481f87c5cb9e8762b3263", ...}`
with generator `gen_campaign.R` argv recorded verbatim in `seal.json`;
`campaign.rds` re-hashes to the sealed digest (byte-idempotent derivation
attested: the 2026-10-11 rehearsal outdir carries the identical rds digest
from three days earlier under the frozen seed and argv); one probe launch
and exactly one full launch in `campaign_launches.jsonl` (the RB-10
single-shot law -- no refiring); co-tenancy attestation in
`witnesses/host_census.jsonl` plus the wrapper's load1 census (all samples
strictly below the 1.5 bar, bar never relaxed); the CI-noise-envelope
anchor gate adjudicated the paired anchor witnesses green
(`median_ok_frac` 1.0 over 1250 cells).

What "MEASURED-false" means precisely: the campaign's oracle compares the
timed ratio against the >=100x table claim and returns `false` -- the
claim is refuted by measurement at this shape on this pinned host, roughly
one order of magnitude short. The row above is kept because ARCHITECTURE
is the target registry, not an achievements registry; this document is now
the place that records what the target actually measured.

## Pinned-host caveat

Every number above is a single-session measurement on one pinned,
developer machine whose power state was not controlled — the source
attestation (`bench/m1s/result.md:3-4`):

> Date: 2026-09-30 · the local Apple M5 / macOS 26.6.2 / R 4.5.2 / rustc 1.92 /
> SPMG 1.3.6 (bench/m1s/.venv). The power status not controllable — the numbers are for this pinned-hardware single-session caliber;

The per-part benches repeat the caveat individually -- the three reference
reports below stay byte-frozen CJK originals (translation only on user demand,
charter class "reference"), so each line is a labeled English rendering, not a
verbatim quote:

- `bench/m1s/sbs/result.md:14` (rendering of the CJK original)
  > - host: aarch64-apple-darwin20 (Apple Silicon; the power status not controllable -- the numbers are for this pinned-hardware caliber)
- `bench/m1s/nmf/result.md:14` (rendering of the CJK original)
  > - host: aarch64-apple-darwin20 (Apple Silicon; the power status not controllable -- the numbers are for this pinned-hardware caliber)
- `bench/m1s/nnls/result.md:8` (rendering of the CJK original)
  > - python 3.13.9 | numpy 2.3.5 | scipy 1.17.0 | darwin (Apple Silicon; the power status not controllable -- the numbers are for this pinned-hardware caliber)

Consequences, all by reference: these values are acceptance-gate
evidence, not CI-tracked series (the 'do not enter CI' stipulation of the title line quoted above); the
Plan-A paragraph itself defers the naive-baseline 50× re-check to a
pinned-hardware bench (the re-verification at the pinned-hardware bench, quoted above); and from
U-M7-04 B1a onward the M7 harness writer stamps `host` and
`hw_profile` into every timings row so future machine attestation is
checkable from the table alone:

```
$ git log --oneline -1 -- bench/m7/competitors/timings.py
cfef27c feat(m7): timings writer emits optional trailing hardware pins host+hw_profile; pinned reader with 7-col legacy back-compat branch
```

## Re-extraction commands (same window as this file's creation)

```
$ sed -n '11p;13p;14p' bench/m1s/result.md
$ grep -n 'Plan-A calibration' docs/ROADMAP.md       # -> line 105
$ sed -n '315,321p' docs/ARCHITECTURE.md        # targets table incl. bootstrap row 321
$ grep -n 'power status not controllable' bench/m1s/result.md; grep -n 'Apple Silicon' bench/m1s/*/result.md   # parent (translated) + the three CJK reference reports
```

## Integrity seals

SHA-256 of every source quoted above, hashlib/shasum pair-checked
in-window; the `abc` control vector hashed to the same value under
hashlib, `openssl dgst -sha256 -r`, `node crypto.createHash` and
Apple CommonCrypto `shasum -a 256`:

<!-- census-exempt digests: e8c50f7b123ed92be6ba84b0409d095d748bb5beee19b0af25b3d292f86ed258 cbc77d2005586d8410a4ceaacf67254cc34e956753e6a8f7b8dae2fff7f52a80 e215d681c2455c5ae85c99a8dd6f60db2bfd4dc17e9289a1c56728514db2d08b e2f6707915d6002ebf00b2e79b7fec9e5f8333459914243089a1ff0c259b73e3 (the docs/ARCHITECTURE.md and docs/ROADMAP.md seals below were re-pinned at the English corpus pass to the translated blobs; the superseded digests of the baseline Chinese blobs are named here for the numeric-preservation guard; e215d681.../e2f67079... were superseded again at the CJK corpus phase-2 pass (issue #25): the bench/m1s/result.md drift came from the #21 translation commit and the docs/ROADMAP.md seal tracks the phase-2 retirement of the ruling blockquote's CJK twin) -->

```
0baf0f93cba179c068f53fc4899773b00b775349bcb54ed624e0b51d276231c9  bench/m1s/result.md
be6649d50124fe62f639852edb3bd6a4afb964fc8136dbf02b99178c7f62f2cd  docs/ARCHITECTURE.md
4b2bcca5e28ed1679bada42f2c7e5769ef64c76853870e773ae7fc622e8cb90d  docs/ROADMAP.md
6c40eb9940c1fccbf39e9a987714da13b124feb895a691eb32f02bb1058a37ca  bench/m1s/sbs/result.md
80a84a7fc4f8fd9a9a94fa467fad639bc524cd26d9f324c212b57420da7220d0  bench/m1s/nmf/result.md
ee32eb3f697f791b5d481dd94cac13fdafd2b6cfd1f27995e00221fc8a8341c0  bench/m1s/nnls/result.md
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  (control: sha256 of 'abc')
```

