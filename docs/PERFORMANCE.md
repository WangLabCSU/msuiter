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

> # bench/m1s · M1s 验收门 bench 汇总（U-M1s-13 配套；钉硬件口径，不进 CI）

The three measured kernels, quoted exactly from the summary table:

| workload | measured speedup | original target | verdict (vs original) |
|---|---|---|---|
| catalog generation, SBS96 @ 10⁶ mutations | `2.6×` | ≥50× | speedup FAIL；<5s PASS |
| KL-NMF, 96×1000, k=10, 100 iterations | `2.3×` | ≥100× | FAIL |
| batch NNLS, 101×10³, k=10 | `1.8×` | ≥10× | FAIL |

Baselines (from the same cells): SPMG for catalog generation, the
C-kernel R package `brunet` for KL-NMF, and `scipy` per-sample
linear algebra for batch NNLS — see the verbatim rows directly below.

Verbatim table rows (`bench/m1s/result.md:11, 13, 14`):

```
| 目录生成 SBS96（10⁶ 突变） | ≥50× SPMG 且 <5s 单核 | 2.6×（我方 3.73s vs SPMG 9.82s）；<5s ✓ | **speedup FAIL；<5s PASS** |
| NMF KL（96×1000, k=10, 100 iter） | ≥100× R NMF | 2.3×（我方 205ms vs brunet 0.47s） | **FAIL** |
| 批量 NNLS（101×10³, k=10） | ≥10× scipy 逐样本 | 1.8×（我方 6.7ms vs scipy 11.2ms） | **FAIL** |
```

And the summary's own adjudication of the pre-recalibration targets (`bench/m1s/result.md:17`):

> ROADMAP M1s 验收行「目录生成 ≥50× SPMG；NMF ≥100× R NMF」按本 bench 不成立——

## Framing: the Plan-A recalibration (PI ruling 2026-10-05)

The original ≥50×/≥100×/≥10× rhetoric was written against baselines
that were never themselves measured — `brunet` already ships a C
kernel, and SPMG on clean input is vectorised. The PI ruling of
2026-10-05 recalibrated acceptance to the MEASURED C-class baselines,
and moved the original rhetoric to a naive-R/Python framing (`docs/ROADMAP.md:51`, verbatim):

> **验收（v0.1 发布）**：~~目录生成 ≥50× SPMG；NMF ≥100× R NMF~~ → **方案 A 口径（PI 裁决 2026-10-05）**：原倍数写于未实测基线（brunet 即 C 内核、SPMG 干净输入即向量化）；按实测 C 基线重校准——目录 2.6× SPMG（3.73s，<5s ✓）、NMF 2.3× R NMF brunet（C 核）、NNLS 1.8× scipy，原 50×/100×/10× 修辞移至朴素 R/Python 实现口径（全管线 dense 臂 SPMG 46s 口径 50× 或成立，钉硬件 bench 时复核）。夹具全绿；r-universe 可安装。**M1s 14/14 ✅ 关闭。**

## Targets table (ARCHITECTURE cross-reference)

The canonical class targets, verbatim from `docs/ARCHITECTURE.md:260-266`:

```
| 内核 | 基线 | 目标 |
|---|---|---|
| 目录生成 SBS96（10⁶ 突变） | SPMG | ≥50× 且 <5 s 单核 |
| NMF KL（96×1000, k=10, 100 iter） | R NMF / rust-NMF | ≥100× R NMF；rust-NMF 对齐（容差） |
| 批量 NNLS（101×10³） | scipy nnls 逐样本 | ≥10× |
| 全样本拟合 | SPA ~0.21 s/样本 | 对齐或更优 |
| bootstrap（10³×10³） | sigminer 串行 | ≥100× |
```

## UNMEASURED: bootstrap vs sigminer

The targets table's final row (`docs/ARCHITECTURE.md:266`) sets the bootstrap
benchmark against sigminer's serial bootstrapper at ≥100×:

```
| bootstrap（10³×10³） | sigminer 串行 | ≥100× |
```

**Status: UNMEASURED.** No committed artifact in this repository
measures msuiter's bootstrapper against sigminer serial, so this
document deliberately states **no number** for that row — a figure
there would be fabricated. The measurement is a later dispatched
bench task (pinned hardware, per the caveat below); until its result
lands and is cited here, the row stays open.

## Pinned-host caveat

Every number above is a single-session measurement on one pinned,
developer machine whose power state was not controlled — the source
attestation (`bench/m1s/result.md:3-4`):

> 日期：2026-09-30 · 本机 Apple M5 / macOS 26.6.2 / R 4.5.2 / rustc 1.92 /
> SPMG 1.3.6（bench/m1s/.venv）。功耗状态不可控——数字为该钉硬件单次会话口径；

The per-part benches repeat the caveat individually:

- `bench/m1s/sbs/result.md:14`
  > - host: aarch64-apple-darwin20（Apple Silicon；功耗状态不可控，数字为该钉硬件口径）
- `bench/m1s/nmf/result.md:14`
  > - host: aarch64-apple-darwin20（Apple Silicon；功耗状态不可控，数字为该钉硬件口径）
- `bench/m1s/nnls/result.md:8`
  > - python 3.13.9 | numpy 2.3.5 | scipy 1.17.0 | darwin (Apple Silicon；功耗状态不可控，数字为该钉硬件口径)

Consequences, all by reference: these values are acceptance-gate
evidence, not CI-tracked series (`不进 CI`, the title line above); the
Plan-A paragraph itself defers the naive-baseline 50× re-check to a
pinned-hardware bench (`钉硬件 bench 时复核`, quoted above); and from
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
$ grep -n '方案 A 口径' docs/ROADMAP.md          # -> line 51
$ sed -n '260,266p' docs/ARCHITECTURE.md          # targets table incl. bootstrap row 266
$ grep -n '功耗状态不可控' bench/m1s/result.md bench/m1s/*/result.md
```

## Integrity seals

SHA-256 of every source quoted above, hashlib/shasum pair-checked
in-window; the `abc` control vector hashed to the same value under
hashlib, `openssl dgst -sha256 -r`, `node crypto.createHash` and
Apple CommonCrypto `shasum -a 256`:

```
e215d681c2455c5ae85c99a8dd6f60db2bfd4dc17e9289a1c56728514db2d08b  bench/m1s/result.md
e8c50f7b123ed92be6ba84b0409d095d748bb5beee19b0af25b3d292f86ed258  docs/ARCHITECTURE.md
cbc77d2005586d8410a4ceaacf67254cc34e956753e6a8f7b8dae2fff7f52a80  docs/ROADMAP.md
6c40eb9940c1fccbf39e9a987714da13b124feb895a691eb32f02bb1058a37ca  bench/m1s/sbs/result.md
80a84a7fc4f8fd9a9a94fa467fad639bc524cd26d9f324c212b57420da7220d0  bench/m1s/nmf/result.md
ee32eb3f697f791b5d481dd94cac13fdafd2b6cfd1f27995e00221fc8a8341c0  bench/m1s/nnls/result.md
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  (control: sha256 of 'abc')
```

