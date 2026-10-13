# bench/m1s · the M1s acceptance-gate bench summary (the U-M1s-13 companion; the pinned-hardware caliber, not into the CI)

Date: 2026-09-30 · the local Apple M5 / macOS 26.6.2 / R 4.5.2 / rustc 1.92 /
SPMG 1.3.6 (bench/m1s/.venv). The power status not controllable — the numbers are for this pinned-hardware single-session caliber;
the per-item one-key re-run commands are in `README.md`, the full-run numbers in `nmf|sbs|nnls/result.md`.

## The criterion verdicts (the ARCHITECTURE §8 budget rows / the ROADMAP M1s acceptance)

| The budget row | The criterion | The measured | The conclusion |
|---|---|---|---|
| the catalog generation SBS96 (the 10⁶ mutations) | ≥50× SPMG and <5s single-core | 2.6× (ours 3.73s vs SPMG 9.82s); <5s ✓ | **speedup FAIL; <5s PASS** |
| the correctness anchor (the SBS96 per-cell, the 10⁶ dbsfree main arm) | per-cell agreement | diff = 0 cells (the sum both sides 1,000,000) | **PASS** |
| the NMF KL (96×1000, k=10, 100 iter) | ≥100× R NMF | 2.3× (ours 205ms vs brunet 0.47s) | **FAIL** |
| the batch NNLS (101×10³, k=10) | ≥10× the per-sample scipy | 1.8× (ours 6.7ms vs scipy 11.2ms) | **FAIL** |

**The overall verdict: all three speed budget rows miss at the nominal points (FAIL); the correctness anchors all PASS.**
The ROADMAP M1s acceptance row "catalog generation ≥50× SPMG; NMF ≥100× R NMF" does not hold under this bench —
before the v0.1 release gate the PI adjudication is needed: fix the kernels (the per-solution allocations of NMF/NNLS and the per-iteration objective
trajectories of NMF), fix the budget caliber (see below), or demote the acceptance promise.

## The key numbers

- **SBS**: our `ms_tally()` S7 end-to-end 3.73s (the FFI layer 3.74s, the S7 assembly ≈ the noise level);
  SPMG 1.3.6 the standard call (the VCF input + the full 9-matrix set) 9.8s (the dbsfree arm) / 46s (the dense arm).
  The correctness: the 10⁶ main arm the 96×2 per-cell diff 0; the sanity (with the adjacent pairs) the diff-sum exactly = 4 DBS members;
  the dense arm the total reconciliation SPMG−ours = 166,104 = our DBS member count (exact).
- **NMF**: our `fit_kl_with_init` 204.7ms (2.04ms/iter, including the per-iteration kl_objective
  trajectory = the 3rd WH matmul + the 96k ln; the R brunet baseline does not compute the objective per iteration — a same-granularity
  comparison would be better than 2.3× but still more than 1 order of magnitude off the 100×). The T=100 KL final-value relative diff 4.8e-4
  (the information term; the 96×20 protocol equivalence already proved by U-M1s-14).
- **NNLS**: ours 6.73ms vs scipy 11.1ms; the solutions per-cell agree (max|Δx| = 3.8e-11,
  the SSE relative diff 3.7e-16). At the small scale k=10 both sides are the native Lawson-Hanson, the python
  loop does not constitute a baseline disadvantage.

## P0 / findings (the residue list)

1. **SPMG 1.3.6 counts the DBS pair members into the SBS96 as well** (and does not produce the DBS78; the minimal probe:
   1 adjacent pair + 1 isolated → SPMG SBS96=3). We implement per the U-M1s-09 audit semantics (the dinuc_sub==1
   excluded from every SBS matrix). **The upstream behavior the audit relied on does not match the 1.3.6 measurement** —
   the PI needs to re-check the upstream version/code path that docs/research/04 anchors, and the M1c DBS78 unit adjudication.
2. **SPMG 1.3.6 wholly drops exact duplicate records** (sample blind, whole-row comparison; this bench's fixture
   has been deduplicated and aligned by (chrom,pos,sample)) — our tally has no deduplication semantics for duplicate records,
   the M1c needs an explicit policy (the ledger already shows the per-record deduplication hook slot).
3. **The SPMG generation entry CHECKSUMS whitelist** makes the custom genome unusable (the upstream restriction);
   the bench registers a local md5 at runtime to bypass it (zero upstream file changes, the compute path pristine).
4. **The SPMG `<vcf_dir>/input/` conversion cache** silently consumes a stale record set on a re-run
   (spmg_run.py clears it every time now).
5. **The "Rust bin pure-core" caliber is unattainable at the HEAD**: the tally assembly entry `mod tally` is package
   private, and the package code cannot be changed for the bench; substituted with the FFI-layer caliber (including the mmap + the R-side validation +
   the 10⁶-row character-column passing). Should the kernel pure-core number be needed, the U-M1c could consider `pub mod tally` + a driver.
6. **The baseline assumptions of the performance budgets are systematically too optimistic**: the R NMF brunet / scipy nnls are both already the native
   C kernels, the "R/Python baseline" is no longer an order-of-magnitude disadvantage; the msuiter ≥10×/≥100×/≥50×
   needs recalibration (fix the kernel allocations/trajectory overhead, or change the promise to an absolute-latency caliber).

## The caliber

- The protocol is unified as "warm-up 1 + timed 3 take the median" (the SPMG is a minute-scale single wall-clock, honestly annotated).
- All our timings go through the real path of the un-changed package code; every driver is an independent workspace, a path
  dependency only on msuiter-engine (nmf/nnls); the package tree zero changes.
- The bench does not belong to the CI (the ROADMAP: the CI carries only the sanity bound).
