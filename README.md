# msuiter

<!-- badges: start -->
[![R-CMD-check](https://github.com/WangLabCSU/msuiter/actions/workflows/ci.yml/badge.svg)](https://github.com/WangLabCSU/msuiter/actions/workflows/ci.yml)
[![msuiter status badge](https://WangLabCSU.r-universe.dev/badges/msuiter)](https://WangLabCSU.r-universe.dev/msuiter)
[![Docs](https://github.com/WangLabCSU/msuiter/actions/workflows/pkgdown.yaml/badge.svg)](https://wanglabcsu.github.io/msuiter/)
<!-- badges: end -->

**Mutational signature analysis with a Rust compute core.**

msuiter is a modern R package for **extracting, fitting, and interpreting mutational
signatures**, built as the successor of [sigminer](https://github.com/ShixiangWang/sigminer).
Numerical kernels (NMF engines, NNLS, likelihood fitting, channel assignment, resampling,
consensus, genome-context tallying) live in a Rust workspace exposed through a stateless
FFI; the R side provides an S7 object model, an engine registry, and a tidy `ms_*()`
user interface.

One workflow grammar covers the analysis end to end:

```r
ms_variants() |> ms_tally() |> ms_extract() |> ms_fit() |> ms_compare()
```

## Scope

msuiter currently ships extraction and fitting for the small-variant modalities:

- **SBS** catalogs at 96 / 192 / 384 / 1536 channel resolutions
- **DBS** (78 channels) and **ID** (83 channels, SPMG-parity semantics)
- **MNV / complex-substitution routing** with an explicit skip ledger

CNV and SV segment/breakpoint inputs can be constructed and stored, and the RNA-SBS
workflow plus CN/SV *fitting* are planned for later releases — the
[capability matrix](https://wanglabcsu.github.io/msuiter/articles/capability-matrix.html)
is the authoritative coverage checklist.

## Feature highlights

- **Extraction** — `ms_extract()`: ensemble + consensus pipeline with an adjudicated
  default K rule; pluggable engines (NMF / ARD / sparse) selected through the engine
  registry; SUITOR-style CV and stability evidence via `ms_select_k()`.
- **Fitting** — `ms_fit()` with NNLS, bidirectional-likelihood, and LRT methods;
  `ms_test_presence()` for cohort-level presence testing; `ms_fit_bootstrap()` for
  confidence intervals and support stability.
- **Calibrated statistics** — the MSU-Fit family (`ms_calibration_grid()`,
  `ms_calibration_verdict()`, `ms_calibration_sanity()`): coverage-calibrated
  intervals and verdicts for presence calls and exposure uncertainty.
- **Comparison** — `ms_compare()`: multi-metric similarity with analytic and
  empirical null distributions, three match protocols, and exposure-level testing.
- **Quality control** — `ms_qc_report()` with burden and pseudosignature faces,
  hypermutant stratification, and downsampling tools.
- **Applications** — `ms_hrd_report()` (HRDetect-coefficient WGS reporting) and
  `ms_treatment_report()`.
- **Interoperability** — COSMIC and SigProfiler text formats in and out
  (`ms_import()` / `ms_export()`), exome↔genome opportunistic conversion
  (`ms_convert()`), and a provenance-governed bundled COSMIC v3.6 reference
  database (`ms_refdb_bundled()`).
- **Reproducibility** — an in-house PCG64 RNG with frozen stream layout,
  bit-level thread invariance tests, and structured errors (`msuiter_error_*`
  condition classes) at every boundary.

## Installation

The package builds from source: `R CMD INSTALL` compiles the vendored Rust core
offline (toolchain floor: `rustc >= 1.71`, see `SystemRequirements`).

Install the development build from [r-universe](https://wanglabcsu.r-universe.dev):

```r
install.packages("msuiter",
                 repos = c("https://wanglabcsu.r-universe.dev",
                           "https://cloud.r-project.org"))
```

Or from GitHub:

```r
remotes::install_github("WangLabCSU/msuiter")
```

Release binaries (macOS / Linux / Windows) are attached to each
[GitHub release](https://github.com/WangLabCSU/msuiter/releases). There is no CRAN
release yet.

## Quick start

```r
library(msuiter)

# a small synthetic cohort seeded with three bundled COSMIC signatures
ref <- ms_refdb_bundled()$SBS_GRCh38
S   <- ref@matrices[[1]][, 1:3]
E   <- matrix(c(0.5, 0.3, 0.2), 3, 24,
              dimnames = list(colnames(S), paste0("S", 1:24)))
sim <- ms_simulate(S, exposures = E, burden = 2000, seed = 1)

# extraction: de novo signatures from the simulated catalog
# (tiny synthetic data: the K adjudication warns that its stability evidence
#  is thin -- real analyses read the ms_select_k() evidence panel)
ext <- suppressWarnings(ms_extract(sim, k = 3))

# comparison: calibrated similarity against the reference signatures
cmp <- ms_compare(ext@signatures, S,
                  exposures_est = ext@exposures, exposures_ref = E,
                  null_n = 200, null_n_draws = 500, seed = 1L)
cmp

# fitting: exposures against the bundled COSMIC reference
fit <- ms_fit(sim, S, method = "nnls")
fit
```

See [Get started](https://wanglabcsu.github.io/msuiter/articles/get-started.html)
for the five-minute path against committed fixtures, and the tiered task guides
for each stage of the grammar.

## Documentation

The full site (tutorials, guides, technical documentation, and the project's
governance corpus) is published at **https://wanglabcsu.github.io/msuiter/**:

| Tier | Contents |
|---|---|
| [Get started](https://wanglabcsu.github.io/msuiter/articles/get-started.html) | install, the five-minute path, output anatomy |
| [Core workflows](https://wanglabcsu.github.io/msuiter/articles/index.html) | import & formats, catalogs, extraction, fitting |
| [Statistics & comparison](https://wanglabcsu.github.io/msuiter/articles/comparing-signatures.html) | similarity comparison, calibration statistics |
| [Applications & QC](https://wanglabcsu.github.io/msuiter/articles/scenarios.html) | scenario atlas, QC faces, visualization gallery |
| [Reference](https://wanglabcsu.github.io/msuiter/reference/index.html) | every exported function, grouped by topic |
| [Governance corpus](https://wanglabcsu.github.io/msuiter/articles/docs-bridge.html) | architecture, roadmap, performance anchoring, ADRs, research dossiers, devlog |

Key repository documents (rendered on the site): the
[architecture](https://wanglabcsu.github.io/msuiter/articles/architecture.html)
design, the [roadmap](https://wanglabcsu.github.io/msuiter/articles/roadmap.html)
with its organizational gates, the
[capability matrix](https://wanglabcsu.github.io/msuiter/articles/capability-matrix.html),
and the [performance](https://wanglabcsu.github.io/msuiter/articles/performance.html)
anchoring page with its frozen floors and witnesses.

## Status

msuiter is under active development toward a v1.0 CRAN release. The extraction,
fitting, comparison, calibration, QC, HRD, and interoperability surfaces are
delivered and continuously regression-tested; the paper manuscript and the
benchmark campaign are in progress. See the
[roadmap](https://wanglabcsu.github.io/msuiter/articles/roadmap.html) for
milestone status and the [NEWS](https://wanglabcsu.github.io/msuiter/news/index.html)
for changes.

## Citation

If you use msuiter in academic work, please cite the R package:

```r
citation("msuiter")
```

## Contributing

Contributions are welcome. Read
[CONTRIBUTING.md](https://github.com/WangLabCSU/msuiter/blob/main/CONTRIBUTING.md)
for the development workflow, the local acceptance battery, and the engine
onboarding checklist. Please note the project's
[Code of Conduct](https://github.com/WangLabCSU/msuiter/blob/main/CODE_OF_CONDUCT.md).

## License

[Apache-2.0](LICENSE). The bundled COSMIC v3.6 reference data is mirrored from the
Alexandrov-lab BSD-2 distribution (SigProfilerAssignment) with full provenance
governance — see the reference-database faces on the
[MSU map](https://wanglabcsu.github.io/msuiter/articles/msu-map.html) page.

## Author

**Shixiang Wang** — Wang Lab, CSU. Author of
[sigminer](https://github.com/ShixiangWang/sigminer).
