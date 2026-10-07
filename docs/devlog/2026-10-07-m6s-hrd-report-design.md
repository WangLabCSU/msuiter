# M6s · ms_hrd_report() — ground-truth anchoring & design (U-M6s-01, A12)

**Scope source.** `docs/IMPLEMENTATION-PLAN.md` U-M6s-01: HREscape-style
coefficient mode, WGS-only, allele-specific CN caller whitelist
(Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA), WES flagged experimental,
reference-fidelity tests "coefficients verbatim", uncertainty reporting.
The verbatim requirement makes the upstream reference implementation the
single ground truth: no locally invented thresholds may appear.

## 1. Ground-truth provenance (captured 2026-10-07)

| fact | value |
|---|---|
| authoritative repo | `cran/SigMiner` (CRAN release mirror of the peer-reviewed SigMiner; SigMiner is the SigProfiler-suite tool whose HRD scoring is the Cortes-Castro et al. publication implementation) |
| scoring functions | `R/get_pLOH_score.R`, `R/get_Aneuploidy_score.R` (read from the mirror; no file named `*hrd*` exists — HRD analysis IS these two scores) |
| pLOH definition (verbatim) | segments with `segVal >= 1 & minor_cn == 0`, `minor_cn <- pmin(segVal - minor_cn, minor_cn)`, autosome-only (`rm_chrs = c("chrX","chrY")`), score = `sum(end - start + 1) / chr_size` |
| aneuploidy definition (verbatim) | arm-level (`location` type `p`/`q`, whole-chromosome arms split `p,q` with fraction/2), autosome 1..22, `flag = as.integer(round(sum(segVal * fraction) - ploidy[1]))` per arm; blacklisted p-arms 13,14,15,21,22 optional via `rm_black_arms` |
| ploidy source | `get_cn_ploidy(data)` when `ploidy_df` is NULL |
| genome build | `genome_build = "hg19"` default; msuiter exposes build explicitly (no silent default) |

The fidelity tests in §3 replay **these expressions byte-for-byte**: each
msuiter-side constant is copied into `R/hrd-reference.R` inside a commented
verbatim block that names its upstream file and function, and a golden test
re-executes the upstream expression on shared fixtures and demands identical
output. Upstream drift therefore fails the build instead of silently
diverging — the same doctrine as `test-channels-reference.R` for catalog
coefficients.

## 2. Public API (tidyverse-flavoured, S3 per A12)

```r
ms_hrd_report(
  segments,                      # data.frame: sample, chromosome, start, end,
                                 # state (integer CN), minor_cn, caller, assay
  genome         = c("GRCh37", "GRCh38"),   # explicit, mirrors refdb builds
  caller_whitelist = "auto",                # the five validated callers
  assay          = c("wgs", "wes"),         # wes requires experimental = TRUE
  experimental   = FALSE,
  ...) -> # MsHrdReport S3 (tbl print; as.data.frame; plot-ready columns)
```

* **WGS-only gate.** `assay = "wes"` without `experimental = TRUE` raises the
  `msuiter` error class `hrd-wes-experimental`; with it, every output row
  carries `evidence_tier = "experimental"` (surface = documentation, A12).
* **Caller whitelist gate.** caller values outside the five validated
  callers raise `hrd-caller-whitelist` naming the observed value; the
  whitelist is data (`R/hrd-reference.R`), not scattered conditionals.
* **Uncertainty reporting.** every returned row carries
  `n_windows_scored`, `coverage_note` (caller-ploidy availability), and —
  when ploidy is caller-supplied vs derived — `ploidy_source ∈
  {caller, derived}` (report never silently mixes the two).

## 3. Test plan (TDD, AAA, all English)

1. `test-hrd-reference.R` — verbatim-fidelity goldens: shared fixtures run
   through `R/hrd-reference.R` copies of the upstream expressions and
   against msuiter's path; equality demanded (coefficients AND the
   `pmin(minor)` fold, the +1 length convention, the arm-fraction/2 split).
2. `test-hrd-report.R` — API/gates: whitelist reject, WES gate, explicit
   build, S3 shape, uncertainty columns, error classes.
3. Edge discipline (CLAUDE.MD): N=0 samples, single-segment genomes,
   chromosome sets without chrY, unsorted inputs, NA segments (dropped with
   report, never error).

## 4. Landing

Branch `feat/m6s-hrd-report`, one PR for the whole M6s phase per the
phase-PR mandate; CI green before handoff; NEWS + pkgdown entries land with
the feature, not after.
