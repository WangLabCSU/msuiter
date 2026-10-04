# Real-data sanity protocol (MSU-Fit, M3b U-M3b-06)

> Status: **frozen protocol** (PI ruling 2026-10-04). Source spec:
> `docs/devlog/2026-10-04-M3b-design-memo.md` section 4 and §7 ruling 3.
> Harness entry point: `ms_calibration_sanity()` (R/calibrate-real.R).
>
> **Non-claim discipline (frozen wording).** This protocol produces
> **sanity / stability evidence on real data, never calibration evidence**.
> The pseudo-truth is itself an estimator (it carries measurement error)
> and real catalogs violate the fitted model (weak identifiability,
> exposure heterogeneity). S(N) numbers are reported as a stability check
> alongside the synthetic grid; they never enter a coverage claim
> (ARCHITECTURE.md section 5: "真实数据 sanity").

## 1. What the harness measures

1. The caller supplies a real catalog (an `MsCatalog`) and a signature
   dictionary. **This package never downloads, embeds or commits real
   data**; the acquisition paths below are the sanctioned way for a
   caller to build the catalog locally.
2. The frozen production face (`likelihood_bidirectional`, epsilon 0.001,
   zero threshold 0.01, TMB rescale) fits the FULL catalog; the point
   estimate is the declared **pseudo-truth**.
3. Every dilution level N (the protocol axis K in {100, 1000, 10000})
   down-samples each live sample: `counts_diluted ~
   Multinomial(N, counts_j / total_j)` -- the same generative law as the
   engine's `resample::multinomial` primitive. The harness draws through
   base R's `stats::rmultinom` on a fixed seed because the Rust primitive
   has no FFI face and the harness is not a calibration-declaration face;
   the draw order (level x replicate x sample) and the seed make the run
   reproducible.
4. Each diluted catalog is refit with the production face + bootstrap CI
   (`n_boot` replicates, percentile or BCa face). The pseudo-truth
   **dilutes with the catalog** -- each live sample's truth entries are
   rescaled onto the level total N (factor `N / total_j`, exact because
   the multinomial draw conserves the total) -- and `S(N)` = the fraction
   of pseudo-truth entries with full-catalog pseudo-truth share >= 0.05
   covered by the diluted CIs on that common scale.
5. **Acceptance**: S(N) within +-0.05 of the synthetic MAIN-arm grid curve
   at the same N (run `ms_calibration_grid()` over the same N axis at the
   frozen protocol and subset to `(n, coverage)`), union the wider floor
   band [0.90, 1.00] per level (memo: "取宽者"); and no systematic
   monotonicity inversion along N (a level-to-level drop steeper than
   0.05 is an inversion; a strict majority of steps inverting is
   systematic).

## 2. Data sources (PI ruling 2026-10-04)

### 2.1 Primary: PCAWG WGS (top-TMB decile)

- **What**: PCAWG (Pan-Cancer Analysis of Whole Genomes) donor catalogs,
  consortium reference Nature 578:176-184 (2020),
  doi:10.1038/s41586-020-1962-3. WGS is the only source whose mutation
  burden spans the full N grid (10^2 - 10^6).
- **Acquisition path**: the WTSI/ICGC publicly released signature-style
  channel matrices (the PCAWG signatures publication's public catalog
  matrices; also mirrored by the ICGC data portal and the PCawg
  consolidated SNV calls under PCAWG's open governance). Fetch to a local
  directory, tally or convert into the SBS96 channel convention, and build
  the `MsCatalog` locally.
- **Sample selection**: top mutation-burden (TMB) decile, at least 20
  samples, every selected sample with full-catalog total
  `N_full >= 5 * 10^4` (memo section 4) -- the strict-downsampling gate of
  `ms_calibration_sanity()` enforces level <= smallest live total.
- **Governance**: use only the openly released aggregate channel counts
  (no donor-level genotypes); record the snapshot date and source URL of
  the matrix you fetched in your analysis log. The catalog itself is never
  committed to the repository.

### 2.2 Secondary: TCGA GDC open-access WXS

- **What**: TCGA exome (WXS) catalogs from the GDC open-access tier --
  the cleanest governance line (no dbGaP/token required), but the TMB
  ceiling is ~10^4, so it only populates the N <= 10^4 segment of the
  axis.
- **Acquisition path**: GDC portal open-access MAF/simple somatic mutation
  files -> tally with `ms_variants() |> ms_tally()` (WXS channel
  opportunity caveats apply -- see below).
- **Scope guard**: WXS results are reported as a secondary sanity panel
  only; **the WES/panel platform axis is deferred to M4** (PI ruling) --
  exome opportunity normalization (`ms_convert()` family, M4) must land
  first, so WXS numbers must not be merged into the WGS S(N) curve.

## 3. Usage sketch

```r
catalog <- ms_variants(...) |> ms_tally(...)        # real data, local only
sigs    <- <reference dictionary, e.g. COSMIC v3.6 anchors>

# (a) harness on real data
sanity <- ms_calibration_sanity(catalog, sigs, n_boot = 1000,
                                dilution_sizes = c(100, 1000, 10000),
                                n_dilutions = 100, seed = 2026)

# (b) the synthetic main-arm comparison curve over the SAME N axis
synth <- ms_calibration_grid(sigs, n_grid = c(100, 1000, 10000),
                             shares = c(0.05, 0.10, 0.25), m = 2000,
                             n_boot = 1000, seed = 2026)
synth_curve <- aggregate(mean_coverage ~ n, data = synth,
                         FUN = mean)                  # main-arm summary
names(synth_curve) <- c("n", "coverage")

# (c) the acceptance gate
sanity2 <- ms_calibration_sanity(catalog, sigs, synthetic = synth_curve)
sanity2$pass                                           # sanity PASS / FAIL
plot_calibration_curve(synth)                          # the synthetic curve
```

`sanity$kept` records exactly which pseudo-truth entries S(N) was
measured on; keep it with the report.

## 4. Reading the result (D13 wording discipline)

- PASS means: the real-data downsampling curve is **consistent** with the
  synthetic main-arm curve within the frozen tolerance and shows no
  systematic inversion along N -- a stability statement.
- Do NOT write: "calibrated on real data", "coverage of X% on PCAWG" (as
  a calibration number), or any cross-contamination of S(N) into the
  estimand-(2) coverage tables. Directional disagreement with the NB
  stress arm (real overdispersion -> mild undercoverage along the arm-B
  direction) is a CONSISTENCY signal (memo section 4 step 6), not a
  failure.
