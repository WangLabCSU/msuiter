# Research report 05: the data standards, the licenses, the genome readers, the visualization, the benchmarks and the engineering practice
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-27. Everything except the items marked UNVERIFIED was verified by actually reading the pages/sources/repositories.

---

## 1. The COSMIC reference-data license and distribution

### The license statement (verified, quoted)

The COSMIC signatures site states: although downloading the signatures requires no login, **"use of the data is still subject to the COSMIC Terms and Conditions"**, the terms at **https://www.cosmickb.org/terms/** (the old URL 302s to cosmickb.org/licensing/). The key points (the terms as revised 2025-10-30):

- COSMIC belongs to **Genome Research Limited (the Wellcome Sanger Institute)**; academic use is free but a "non-exclusive, royalty-free academic-use right".
- **The C(g) clause: "COSMIC data may never be packaged or distributed further to a customer, such as via a download or on-premise installation"** — no packaging/redistribution without a commercial license (QIAGEN).
- The 4.7 clause forbids redistributing, sublicensing, selling COSMIC or giving third parties access over the public internet (except "Publication Enablement" or a commercial license).
- The 4.6 clause: training AI models on COSMIC data without written consent is forbidden. The disclosure is limited to publications carrying the COSMIC-version acknowledgement.

### The field's actual practice (all verified against the repositories)

| The tool | The license | Bundles COSMIC signatures? |
|---|---|---|
| SigProfilerAssignment (SigProfilerSuite) | **BSD-2-Clause** | yes — `data/Reference_Signatures/{GRCh37,GRCh38,mm9,mm10,mm39,rn6,rn7}/`, the SBS/DBS/ID/CN/**RNA-SBS** txt files, COSMIC v1→v3.6 (incl. the exome variants) |
| SigProfilerPlotting/MatrixGenerator/Extractor/Simulator | BSD-2-Clause | MatrixGenerator carries the channel definitions/TSB references; no signature matrices |
| MutationalPatterns | **MIT** (Bioc) | yes — `inst/extdata/signatures/`: the snv/dbs COSMIC v3.1, v3.2 (GRCh37/38/mm10), converted to the MP channel order via `inst/scripts/Format_signatures.R` |
| deconstructSigs | **no LICENSE file** | yes — signatures.cosmic.rda etc. |
| sigminer | MIT (CRAN) | yes — v3.1 SBS/DBS/ID/TSB + PCAWG176/TCGA CNS/RS + Nik-lab + SIGNAL |
| mSigPortal | GPL-3 | served as a service (JSON), not bundled |
| mmsig/sigfit/signature.tools.lib | various (**signature.tools.lib = a BSD-3 style + academic-only restriction (no clinical use, non-profit-limited, modified versions must be shared); not OSI-standard, treat at the GPL level (formulas for reference only)**) | each bundles its signature references |

### The interpretation and the conclusion

**The de facto universal practice** is redistributing the *numeric signature matrices*: they originate from the peer-reviewed papers (Alexandrov 2013, PCAWG/Alexandrov 2020), curated and distributed **by the very laboratory that generates the official COSMIC signature files (the Alexandrov Lab) under BSD-2-Clause** inside the SigProfiler suite. No signature-analysis package bundles from cancer.sanger.ac.uk; everyone bundles the SigProfiler-suite copies. The COSMIC T&C textually forbids "packaging or distributing" COSMIC data and is silent on the signature matrices themselves; the practical legal touch surface is the BSD-2 SigProfiler files. **This is an interpretation, not a legal opinion — the formal gap between the T&C and the practice should be flagged to users (the marker: legal ambiguity).**

**The recommendation: bundle (primary) + on-demand download (secondary)**:
- Bundle the SBS/DBS/ID/CN/SV/RNA-SBS matrices, **pinning the provenance to the `SigProfilerSuite/SigProfilerAssignment` raw GitHub** (the BSD-2 upstream, byte-identical to the COSMIC content), with per-file version metadata (e.g. `COSMIC_v3.6_SBS_GRCh38.txt`) + the COSMIC and PCAWG paper citations. Packaging BSD-2 data under MIT/Apache is fine.
- The on-demand download goes via the same GitHub raw mirror (stable, active: v3.5 2026-01, v3.6 2026-07), **not** via cancer.sanger.ac.uk (a login gate, the T&C restrictions, no stable raw URL).
- The mSigPortal JSON and the USARC xlsx are second-tier convenience mirrors.

## 2. The channel standards and the history

### SBS96 — two incompatible row orders exist in the field (verified)

1. **The "COSMIC/SigProfiler order" (flank-major)** — used by the COSMIC v3 txt files, SigProfilerAssignment, SigProfilerPlotting, sigminer. The outer loop = the 5'-base (A,C,G,T), then the 6 substitution classes, then the 3'-base: `A[C>A]A A[C>A]C ... A[T>G]T C[C>A]A ... T[T>G]T`.
2. **The "Nature-2013/deconstructSigs/MutationalPatterns order" (substitution-major)** — verified via the deconstructSigs `signatures.cosmic.rda` column names and MP's `mut_96_occurrences.R` (tidyr::crossing substitution-major): `A[C>A]A ... T[C>A]T A[C>G]A ... T[T>G]T`.

**The known mismatch bug**: the MutationalPatterns GitHub **issue #60 "Order of SNV types in mutation matrix"** is exactly this trap; the MP maintainers confirmed its COSMIC reference was pre-converted to the MP order. Feeding a COSMIC-order catalog into deconstructSigs silently produces wrong exposures. **A new tool must: (a) fix one canonical order internally; (b) validate the input row order by labels rather than position; (c) provide converters.**

### The canonical label lists (scraped from SigProfilerSuite/SigProfilerAssignment@HEAD, the COSMIC v3.6 files)

**⚠️ The per-build availability matrix (revised on the 2026-09-28 recheck)** — the mirror is *not* "five classes × all builds":

| build | SBS | DBS | ID | CN | SV | RNA-SBS |
|---|---|---|---|---|---|---|
| GRCh37 | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| GRCh38 | ✓ | ✓ | — | — | ✓ | — |
| mm9/mm10/mm39 | ✓ | ✓ | — | — | — | — |
| rn6/rn7 | ✓ | ✓ | — | — | — | — |

(The missing builds of ID/CN/SV/RNA-SBS must be self-derived or converted across builds by labels — the architecture was adjusted accordingly.)
Also the column-count checks: the SBS file = 96 rows + a 102-column header (Type + 101 signatures); DBS 23 (22 signatures); ID 26 (25); CN 27 (26); RNA-SBS 6 (5); SV 13 (12).

- **SBS96**: `A[C>A]A … T[T>G]T` (flank-major).
- **DBS78**: `AC>CA AC>CG … TT>GG` (56 dinucleotide-context classes × 3 ref>alt within a group; the group order AC×9, AT×6, CC×9, CG×6, CT×9, GC×6, TA×6, TC×9, TG×9, TT×9).
- **ID83**: `1:Del:C:0…5`, `1:Del:T:0-5`, `1:Ins:C:0-5`, `1:Ins:T:0-5`, `2..5:Del:R:0-5`, `2..5:Ins:R:0-5`, the microhomology `2:Del:M:1`, `3:Del:M:1-2`, `4:Del:M:1-3`, `5:Del:M:1-5` (83 in total).
- **CN48** (the exact 48 rows of `COSMIC_v3.6_CN_GRCh37.txt`): `0:homdel:{0-100kb,100kb-1Mb,>1Mb}`(3), then `1:LOH:`, `2:LOH:`, `3-4:LOH:`, `5-8:LOH:`, `9+:LOH:`, `2:het:`, `3-4:het:`, `5-8:het:`, `9+:het:` each × {0-100kb,100kb-1Mb,1Mb-10Mb,10Mb-40Mb,>40Mb} (45 rows). The grammar `<totalCN>:<LOH|het>:<segment-size>`. sigminer has the companion `CN48-Map.txt`.
- **SV32** (`COSMIC_v3.6_SV_GRCh38.txt`): {clustered, non-clustered} × {del, tds, inv} × {1-10Kb, 10-100Kb, 100Kb-1Mb, 1Mb-10Mb, >10Mb} (30) + `clustered_trans` + `non-clustered_trans` (2) = 32.
- **RNA-SBS 192** (`COSMIC_v3.6_RNA-SBS_GRCh37.txt` — **the repository has GRCh37 only, no GRCh38 RNA-SBS file**, verified): **192 rows = 12 non-identical ref>alt classes** ([A>C] [A>G] [A>T] [C>A] [C>G] [C>T] [G>A] [G>C] [G>T] [T>A] [T>C] [T>G]) **× 16 flanks (5'×3')**, i.e. the `A[A>C]A` form. **Key: this is not the pyrimidine-normalized 6-class scheme** — 16 ref>alt combinations minus the 12 identical classes.

### The TSB / "192" vs "384" disambiguation (verified in the SPMG source)

SPMG defines `tsb = ["T","U","N","B"]`, `tsb_I = ["T","U","N","B","Q"]` (the indels use Q), `bias_sort = {T:0,U:1,N:3,B:2,Q:4}`; `tsb_stat` runs the strand-bias test over the **24, 384, 6144** contexts. Hence:
- **SBS24** = 6 substitution classes × 4 strand states (T/U/N/B) — a pure strand bias.
- **SBS192** (`save_tsb_192.py`) = 96 × {T,U} — the transcribed regions' strands only.
- **SBS384** = 96 × 4; **SBS6144** = 1536 × 4; the sample portrait separately uses SBS1536 and DBS312.
- The sigminer TSB mode = 192 (T/U); MutationalPatterns' `mut_matrix_stranded` = 192; the COSMIC public TSB matrices follow the T/U 192 style (the COSMIC-site file details UNVERIFIED).

## 3. The genome-context fetch performance (the basis of the Rust fast path)

- **SPMG (Python)**: download the genome FASTA → `save_chrom_strings.py` turns **each chromosome into a single plain-text string file** cached under `references/chromosomes/chrom_string/<genome>/`; at runtime it opens `chrom+".txt"` and slices strings. The speed comes from the flat file cache; the price is a ~3.2 GB disk cache + an install step.
- **MutationalPatterns (R)**: `Biostrings::getSeq(BSgenome, gr)` + label construction + `factor(levels)` counting.
- **sigminer/deconstructSigs (R)**: repeated `BSgenome::getSeq`.
- The R-native performance surface (reasoning, unbenchmarked): after the full BSgenome load (~3 GB human) getSeq is fast but the load is heavy; `Rsamtools::FaFile` (htslib faidx) is C-fast but with per-call overhead; **`rtracklayer` natively supports 2bit** — the lightest-memory indexed R path; `chartr/substr + match` is the fastest pure-R post-processing against hash tables.
- **The Rust fast path (the crates verified, 2026-09)**:
  - **`twobit` 0.2.2** (jbethune/rust-twobit, MIT, 2026-03, ~14.8k downloads): a pure-Rust zero-dependency UCSC 2bit reader, indexed random access `read_sequence("chr1", 48..74)`, an **`open_and_read` full-in-memory caching mode**, N-mask support.
  - **`noodles` 0.116.0** (active, 2026-08) + `noodles-fasta` 0.66.0 + bgzf: production-grade indexed FASTA.
  - `bio` 4.0.1 (rust-bio); `rust-htslib` 1.0.1 (2026-06, ~667k downloads, the BAM/BCF interoperability alternative).
- **The zero-copy 2bit-reader sketch**: `memmap2::Mmap` the .2bit → parse the header/Pair index → batch the variants grouped by chromosome → decode only the needed 4bit-packed words into preallocated buffers → build the `X[N>M]Y` labels inside Rust → return only the label indices to R. A WGS catalog needs at most ±1..7 bases per variant; the disk-indexed random access is already near-optimal; one mmap + sorted-interval decoding sidesteps the BSgenome 3GB load and the Python string cache's 3.2GB disk. **The precedent check: no mainstream R/Bioconductor package was found to read a reference genome via Rust (best knowledge)** — r-polars is the nearest engineering template.

## 4. The visualization landscape

- **SigProfilerPlotting** (matplotlib, BSD-2, updated 2026-09): plotSBS/DBS/ID/CNV/SV (the signature profiles and per-sample counts, the percentage option, aggregate); `sample_portrait.samplePortrait()` needs the full-grid matrices; the official R wrapper SigProfilerPlottingR. **The de facto style standard** (the stacked colour bars, the class-grouped channels, the dual top-%/bottom-count axes, the trinucleotide sublabels).
- **sigminer** (ggplot2): show_sig_profile (mode=SBS/copynumber/DBS/ID/RS; style=default|cosmic — the cosmic style is faithful to SigProfiler), show_sig_exposure, show_catalogue, show_sig_similarity, the bootstrap stability plots.
- **MutationalPatterns**: ~30 plotting functions — plot_96/192_profile, plot_contribution(_heatmap), plot_compare_profiles, plot_original_vs_reconstructed, plot_cosine_heatmap, plot_river, plot_rainfall, plot_spectrum, plot_strand_bias, plot_enrichment_depletion, plot_lesion_segregation etc.
- **mSigPortal** (the NCI web): the catalog/profile plots, the vs-reference comparisons, the clustering cosine views, the exposure summaries; mSigSDK supports private large-scale computation.
- Others: YAPSA, signeR, musicatk, signifinder, TBSignatureProfiler (the r-universe tracks verified).

### The canonical figure-type list for a modern implementation (~18)

1. the SBS96 sample-catalog bar plot (count/%); 2. the SBS6/24 mini-catalogs; 3. the de novo signature profiles; 4. the TSB 192 profile; 5. the DBS78 profile; 6. the ID83 profile; 7. the CN48 profile/heatmap; 8. the SV32 profile/heatmap; 9. the sample-portrait multi-context grid; 10. the stacked exposure bars; 11. the exposure heatmap; 12. the cosine-similarity heatmap (sample×signature); 13. the similarity scatter (signature vs COSMIC, q-value annotations); 14. the original-vs-reconstructed comparison panel; 15. the riverplot; 16. the rainfall plot; 17. the strand-bias/TSB statistic plots; 18. the bootstrap stability curves + contribution bootstraps. Plus the enrichment/region plots (the MP family).

**The ggplot2-native requirements**: vector output as a first citizen (cairo_pdf/svglite; SPP already produces PDFs), the canonical COSMIC 6-class palette + the DBS/ID/CN/SV palettes, the class-group separators and the bottom annotation strips (the 192's T/U strands), the dual top-%/bottom-count axes, the small-multiple facet grids, the signature ordering control (alphabetical vs COSMIC), **the input-order validation** (§2). CRAN has no signature-visualization dedicated package (the scan verified: only mutSignatures and aws.signature were false hits; "SigVis" does not exist).

## 5. The benchmark infrastructure

### The public generators/datasets (all verified)

- **SigProfilerSimulator** (SigProfilerSuite, BSD-2): simulates realistic SBS/DBS/ID catalogs preserving the contexts; the paper Bergstrom et al., BMC Bioinformatics 2020;21:438. **The field's standard zero-model generator.**
- sigminer's `simulate_catalogs` — the R-native generator.
- **Medo 2024**: 12 fitting tools × synthetic catalogs (8 cancer types' empirical signature weights) + the PCAWG real data (146 samples >50k SBS). **The code + synthetic data: https://github.com/8medom/SigFitTest** (the Code availability verified).
- **Jiang 2024**: **the code/data: https://github.com/Rozen-Lab/sig_attribution_paper_code and Rozen-Lab/sig_attribution_low_variance** (verified).
- **Islam 2022**: the standard extraction-tool benchmark (>20k tumors + simulations).
- **Wu 2022**: the correlated-signature benchmark doi:10.1038/s41598-021-04207-6.
- The PCAWG catalogs: served by the mSigPortal public projects (the production app CBIIT/nci-webtools-dceg-mSigPortal; this environment could not pin a direct link — cite the portal).

### The design recommendations for a modern (scIB-style) benchmark suite

- **The scenario grid**: TMB (10²–10⁶) × the number of active signatures (1–20+) × the signature correlation (0/medium/high — per Wu 2022) × the exposure sparsity × the noise (Poisson resampling) × the platform (WGS/WES/panel via the exome/BED opportunity masks) × the reference mis-specification (the true signature absent — Medo's key stressor).
- **The metrics**: the signature-detection precision/recall/F1 (with a matching tolerance), the exposure error (L1 + per-sample cosine), the reconstruction cosine, runtime/memory; **the misallocation mass onto absent signatures (exposure bias)**.
- **The Top-5 concrete adoptions**: (1) the SigProfilerSimulator (the context-preserving zero model); (2) the SigFitTest synthetic + PCAWG catalogs (Medo); (3) the Rozen-Lab synthetic_data + benchmarking harness; (4) the Wu 2022 correlated generator; (5) the mSigPortal PCAWG/TCGA public catalogs as real-data anchors.

## 6. Reproducibility and engineering practice

- **Seeds**: the SigProfilerExtractor documents a `seeds` parameter (Seeds.txt reproducible); **the SigProfilerAssignment shows no seeds parameter (search-verified)**. The recommendation: first-citizen seed control across the whole chain, persisted per run (the Seeds.txt style).
- **Containers/distribution**: no official SigProfiler Docker (Docker Hub has only community images such as lculibrk/sigprofiler ~1k pulls); the official distribution is PyPI + bioconda (bioconda: sigprofilerassignment 1.1.5, sigprofilerextractor 1.4.1, sigprofilermatrixgenerator 1.3.3 — verified on anaconda.org).
- **The workflow ecosystem**: the nf-core/modules includes **`sigprofiler`** (the MatrixGenerator+Extractor, with tests) and **`sparsesignatures`** (R) — verified in the nf-core/modules tree, both using bioconda containers. A next-generation tool should deliver a PR-ready nf-core module.
- **CI**: SigProfilerPlotting has GHA; sigminer/MP use testthat (snapshot/example tests); Bioc runs the multi-platform daily checks. The standard practice = testthat + golden-file fixtures + rcmdcheck + codecov.
- **r-universe**: `shixiangwang.r-universe.dev` hosts sigminer (17 packages); the r-universe indexes YAPSA/MP/musicatk/signifinder/TBSignatureProfiler — a viable soft-release channel.
- **The CRAN policy toward Rust packages** (quoted from cran.r-project.org/web/packages/policies.html): "Packages should be of the minimum necessary size"; "As a general rule, neither data nor documentation should exceed 5MB"; "Source package tarballs should if possible not exceed 10MB" (a moderate exemption can be requested); multithreaded code during checks must "never exceed 2 concurrent"; the examples "each within a few seconds"; third-party code: "It is much preferred that third-party source software should be included within the package" (a vendor tarball). **A wording-precision note**: CRAN has no literal "networking forbidden at install time" clause; the actual constraints are "external-resource usage must be minimized, https obligatory, graceful degradation, precompiled-binary downloads are a last resort and need CRAN's consent" — the conclusion is unchanged: vendor every dependency. CRAN has a dedicated **"Using Rust"** page (cran.r-project.org/web/packages/using_rust.html, verified 200). **The template: r-polars** — tools/prep-lib.R + lib-sums.tsv checksums and vendoring the whole dependency tree, compiling statically at install time (repo-verified).
- Also: the 2-thread cap during checks → rayon must be `RAYON_NUM_THREADS`-aware / run within the thread count registered in R (an engineering note).

## 7. The standards organizations/communities

- **No GA4GH or ELIXIR signature-analysis standards work was found** (Europe PMC "mutational signatures"×ELIXIR/GA4GH: zero relevant hits; no "recommendations/consensus/guidelines/handbook" titled paper). Marked: absence verified 2026-09.
- The de facto standards: the COSMIC curation (Tudor et al. NAR 2024 doi:10.1093/nar/gkad986), the PCAWG unified processing (Alexandrov Nature 2020), the NCI mSigPortal (Zhang et al. AACR 2021 doi:10.1158/1538-7445.am2021-211) + mSigSDK (doi:10.48550/arxiv.2308.02995).
- mSignatureDB (NAR 2018 doi:10.1093/nar/gkx1133) exists; there is no "signature-analysis handbook" publication (absence verified). The nearest thing to reporting guidance is the benchmark papers' recommendations (Medo 2024, Jiang 2024) — **a new ecosystem can fill this gap via a "reporting checklist" (the signature-catalog version, the genome build, the channel order, the fitting method, the reference-constraint strategy, the seeds).**

## 8. The key file paths / follow-up URLs

- COSMIC T&C: https://www.cosmickb.org/terms/ ; licensing: https://www.cosmickb.org/licensing/
- The reference-signature mirror (BSD-2): https://github.com/SigProfilerSuite/SigProfilerAssignment/tree/HEAD/SigProfilerAssignment/data/Reference_Signatures/
- An ordering-conversion example: UMCUGenetics/MutationalPatterns `inst/scripts/Format_signatures.R`; the ordering issue: UMCUGenetics/MutationalPatterns#60
- Benchmarks: https://github.com/8medom/SigFitTest ; https://github.com/Rozen-Lab/sig_attribution_paper_code
- Rust: crates.io/crates/twobit (jbethune/rust-twobit), noodles, bio, rust-htslib
- The CRAN Rust policy: https://cran.r-project.org/web/packages/using_rust.html ; the vendor template: https://github.com/pola-rs/r-polars (tools/prep-lib.R, lib-sums.tsv); string2path (CRAN + vendor.tar.xz)

**The unverified/ambiguous items are annotated inline**: the formal legal gap between the COSMIC T&C and the practice; the mSigPortal production-API stability; the sigminer CRAN license ID; the SigProfilerAssignment's missing seed support; the MP ID channel-label scheme vs the COSMIC ID83 ordering; the absence of R-package precedents for reading genomes in Rust (best knowledge).
