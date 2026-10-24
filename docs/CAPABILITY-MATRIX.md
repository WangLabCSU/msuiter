# msuiter capability coverage matrix (CAPABILITY-MATRIX)

> Version: v1 (2026-09-28). **This matrix is the authoritative checklist of platform
> completeness** -- it enumerates, systematically, the full capability space of
> mutational signature analysis (data -> representation -> identification ->
> quantification -> inference -> visualization -> application workflows ->
> mining -> platform layer) and annotates each capability with: the
> mainstream/advanced methods, the engine-equivalent (the ms_* API), the
> default method, the visualization deliverable, the delivery milestone. Update
> once per completed milestone; any claim of "we cover X" is adjudicated
> against this matrix.
> Status legend: ✅ delivered (the shipped API/face; machine-checked by the
> capability-matrix truth gate -- a checkmark on an unexported name reddens
> the suite) · 🔶 partial (a baseline version ships in v1) · ⏳ deferred to
> v1.x · 🔭 exploratory · ❌ explicitly not done. Architecture-ready designs
> live in ARCHITECTURE.md; this matrix records what ships.
> Milestone codenames (the sole authoritative definitions are in
> [ROADMAP.md](ROADMAP.md)): **M0** engineering foundations (v0.1) · **M1s**
> engine-and-catalog core (v0.1) · **M1c** catalog completeness + ID83
> (v0.2) · **M2** unified extraction pipeline (v0.2) · **M3a** fitting three
> methods + bootstrap (v0.2) · **M3b** MSU-Fit calibration statistics
> (v1.0) · **M4** similarity library + viz (v1.0) · **M6s** HRD workflow
> (v1.0) · **M7** benchmark completeness + the paper · **M8** release
> engineering. There is no M5 and no M6 (cancelled by review adjudication,
> see reviews/00 A4/A16).

**How to answer "what does msuiter cover"**: the three user tiers of needs ->
① identification and quantification = L-C + L-D; ② basic visualization = L-F;
③ application-scenario workflows and visual data mining = L-G; "what you did
not think of" = L-A/L-B/L-E/L-H + the ⚡ items annotated per layer.

---

## L-A data acquisition, QC and preprocessing

| Capability | Mainstream/advanced methods | Engine-equivalent (ms_* API) | Default | Viz | Milestone |
|---|---|---|---|---|---|
| variant reading: multi-sample VCF/BCF, GDC MAF, TSV, Xena | hts-specs v4.5; left-align + multi-allele splitting | `ms_variants()` (validate on read) | ✅ | — | M1s |
| somatic confidence: caller/normal provenance, VAF floor, FILTER passthrough | domain practice | MsVariants validator | ✅ | low-VAF sensitivity curve | M1s |
| CNV input: ASCAT/ABSOLUTE/Battenberg/FACETS/PURPLE/SEQUENZA/PCAWG/CNVkit (allele-specific) | SPMG 8-caller mapping | `ms_segments()` | ✅ | CN profile/circos | M1c(v0.2) |
| SV input: BEDPE, SV VCF, caller outputs | chain->type derivation | `ms_sv()` | ✅ | SV profile | M1c(v0.2) |
| reference genome: BSgenome-compatible + 2bit fast path; GRCh37/38, T2T, mm9/10/39, rn6/7, custom | the SPMG pre-encoded byte-string idea | `genome =` argument | ✅ 2bit recommended | — | M0/M1s |
| annotation cache: transcription chains (GENCODE), replication timing (Repli-seq bins), chromatin/elements, mappability, callable BED | MP/TensorSignatures data pipelines | annotation layer (into MsCatalog provenance) | ✅ | — | M1s–M4 |
| sample QC: burden distribution + mechanism-level pseudosignature sentinels (first version delivered U-M4-02b; contamination/sex checks ⏳, Degasperi amber/red faithful replication ⏳v1.x) | domain practice (ICAMS/SigProfiler QC) | `ms_qc_report()` | ✅ first version | QC dashboard page | M4 |
| pseudosignature detection and removal: FFPE/oxoG mechanism sentinels + COSMIC pseudosignature exposure share (first version delivered U-M4-02b), Excerno-style filtering ⏳, amber/red grading ⏳v1.x | Degasperi 2022; Excerno | pseudosignature fitting + filter registry | 🔶 first version | pseudosignature-contribution plot | M4 (the amber/red fitting tiers ⏳v1.x) |
| hypermutator stratification: GMM cutoff + de novo exclusion + forced refit | SigProfiler | `ms_stratify_hypermutants()` | ✅ | burden distribution + cutoff plot | M1c(v0.2) |
| opportunity normalization: the exome<->genome converter + custom opportunity vectors ✅ (U-M4-02c; within-likelihood opportunities ⏳v1.x, the panel built-in table ⏳ no [V] anchor) | the sigfit within-likelihood opportunities; sig_convert | `ms_convert()` + within-likelihood opportunities | 🔶 first version | opportunity distribution plot | M4 |
| depth downsampling / common depth | SigProfiler | `ms_downsample()` | ✅ | — | M4 |

## L-B catalog representation

| Capability | Methods/standards | Engine-equivalent | Default | Viz | Milestone |
|---|---|---|---|---|---|
| the SBS channel family: 6/24/96/192/288/384/1536/6144 | COSMIC/SigProfiler (bit-for-bit semantics) | `ms_tally(mode =)` | SBS96/192 | full-family profile plots | M1s/M1c |
| the DBS channel family: 78/186/312/1248/2976 | SPMG Q-chain rules | as above | DBS78 | DBS profile/portrait | M1s(78)/⏳ the rest |
| MNV/complex/double-indel routing + skip ledger | SPMG | `mnv.rs` + provenance | ✅ | — | M1s |
| the ID channel family: 28/83/89/96/150/415/476 | ID83 = SPMG bit-for-bit; ID89/476 = Koh 2025 | `indel83.rs`->`indel89.rs` | ID83 (89⏳v1.x) | ID profile | 83=M1c; 89=v1.x |
| the CN feature space: CN48 (Steele) / CN40 (Wang) / Macintyre 36 components / Drews features / CN176 (Tao) | each original paper | `cnv_features.R` (a unified typed IR) | CN48 | CN48 spectra/heatmaps | M1c(v0.2) |
| SV channels: SV32/RS38/PCAWG16 | exactPcf clustered | `sv_features.rs/R` | SV32 | SV spectra/heatmaps | M1c(v0.2) |
| RNA-SBS192 (non-nucleotide-normalized, 12 ref>alt x 16 flanks) | COSMIC v3.4+/TRACERx | `ms_tally(mode="rna_sbs")` | — | RNA profile | ⏳v1.x (with the RNA workflow) |
| the multi-catalog single object (musica-style) + the catalog IR (lossless coarsening fine->coarse; refining needs variant-level recomputation) | the musicatk concepts | the MsCatalog family | ✅ | — | M1s/M1c |
| catalog simulator: genome-realistic placement, scenario generators, NB-calibrated sampling | SigProfilerSimulator/SynSig/Jiang | `ms_simulate()` | ✅ | scenario schematic | M7 (kernel M1s) |
| format interoperability: COSMIC txt + SigProfiler txt ✅ ([V] dual formats, tests fixture anchors), the signatures import face ✅; the WTSI long format ⏳ (no upstream real sample), the MP matrix / sigminer RDS / ICAMS semantics ⏳ | the interoperability matrix (research 07 §1.19) | `ms_import/ms_export` | 🔶 dual formats | — | M4 (the rest ⏳) |

## L-C signature identification (de novo extraction) -- the engine-equivalence matrix

| Engine (method =) | Mainstream source/lineage | Implementation layer | Status | Default |
|---|---|---|---|---|
| `ms_nmf(engine="kl")` | Brunet KL-MU (the SigProfiler/MP golden-standard kernel) | Rust | ✅ M1s | **the kernel of the default extraction pipeline** |
| `ms_nmf(engine="eu")` | Lee-EU MM-MU | Rust | ✅ M1s | optional |
| `ms_nmf(engine="hals")` | HALS (the RcppML idea) | Rust | ⏳ v1.x | the kernel attests "deliberately absent" (src/rust/engine/src/nmf.rs) |
| `ms_nmf(engine="nsnmf"/"offset"/"lsnmf")` | the full R NMF family | Rust | ⏳ on demand | — |
| `ms_ard()` | SignatureAnalyzer ARD (Tan–Févotte; the Broad formula) | Rust | ✅ M2 | diagnostic mode |
| `ms_sparse()` | the volume-regularized mvNMF (Leplat–Gillis) + L1 (the SparseSignatures idea) | Rust | ✅ M2 | optional |
| `ms_correlated()` | correlation-aware (the Cornet/Paisley lineage, self-developed optimization) | Rust | ⏳ v1.x | optional (kept or dropped by outcome once pre-registered falsifiable claims qualify, reviews/00 A4) |
| `ms_tensor()` | NTF+NB tensor (the modern re-implementation of TensorSignatures) | Rust | 🔭 v1.x | — |
| `ms_lda()` | topic models (the musicatk/topicmodels lineage) | Rust | ⏳ v1.x | — |
| `ms_hdp()` | mSigHdp (HDP; sensitive to rare signatures) | Adapt (a bench comparison) ->⏳ own implementation v1.x | ⏳ | — |
| `ms_bayes()` | signeR Gibbs / sigfit HMC / BayesPowerNMF power posterior | Adapt (bench) ->⏳ | ⏳ | — |
| `ms_supervised()` | SuperSigs (the minimal sigma-algebra + logistic regression) | native R | ⏳ v1.x | — |
| deep-learning extractors | no credible winner (research 01 §8) | ❌ (absorbing only the residual idea) | ❌ | — |
| **the consensus-CV pipeline (default)** | SigProfiler consensus + SUITOR CV + multi-evidence K adjudication (a self-developed integration) | Rust+R | ✅ M2 | **the `ms_extract()` default** |

**The full K-selection set** (`ms_select_k()`): cophenetic/dispersion
(diagnostic), silhouette consensus, SUITOR entry-wise CV,
bi-cross-validation, likelihood pruning, ARD automatic K, BIC, gap, Wilcoxon
(diagnostic), randomized-baseline controls -> the default adjudication rule
(CV argmin -> stability veto -> diagnostic report). ✅ M2 (some diagnostics
⏳).
**Pre-extraction strategy**: hypermutator stratification ✅, the
common/rare two-stage (atlas workflow) 🔶v1.x, denoising 🔶.

## L-D signature quantification (fitting/attribution) -- the engine-equivalence matrix

| Engine (ms_fit method =) | Mainstream source | Implementation layer | Status | Default |
|---|---|---|---|---|
| `"nnls"` | Lawson-Hanson (the deconstructSigs/MP family baseline) | Rust | ✅ M1s | starting baseline |
| `"qp"` | SignatureEstimation QP (Σe=1) | Rust/quadprog | ✅ v0.2 | optional |
| `"likelihood"` (bidirectional) | MuSiCal semantics (ϵ=0.001 stepwise) | Rust | ✅ v0.2 | **the MSU-Fit primary mode** |
| `"lrt"` | PASA/mSigAct (the NB χ²₁ forward search) | Rust | ✅ v0.2 | **the MSU-Fit primary mode** |
| `"em"` / backward elimination | mmsig/MP strict | R | 🔶 v0.2 | hematologic-tumor compatible |
| `"lasso"` | sigLASSO/StarSignDNA (the L1 Poisson MAP) | Rust | ⏳ v1.x | — |
| `"bayes"` | sigfit/signeR posteriors | Adapt→⏳ | ⏳ | — |
| `"sa"` / `"anneal"` | simulated annealing (the sigminer SA/STL) | R | ⏳ v1.x | — |
| `"best_subset"` | MP best_subset (brute-force over small catalogs) | Rust | ⏳ v1.x | — |
| exposure sparsification: bleedingFilter/auto_reduce/zeroing rules | STL/sigminer/sigfit | R/Rust | ✅ v0.2 | optional |

**Catalog management**: the COSMIC v3.2–3.6 versioning ✅, the organ RefSig
T1–T4 hierarchy 🔶v1.x, the exposure-signature panels (Kucab/SIGNAL)
🔶v1.x, the connected groups (making the SPA/MuSiCal roster difference
explicit) ✅, background forcing (SBS1/5) ✅, the etiology/pseudosignature
subgroups ✅, the parent/child signature policies ✅.
**Uncertainty (MSU-Fit)**: bootstrap CI (support-conditional) ✅, χ²₁ LRT
p/q ✅, Fisher interior ✅, conformal (Mondrian by TMB) 🔶v1.x, Bayesian
posterior ⏳, **the coverage-calibration protocol** ✅ (M3b).
**Per-mutation assignment**: proportional assignment + the unassigned-residual
pseudosignature ✅ v0.2, Bayesian assignment ⏳.
**Similarity/matching (the calibrated similarity library, `ms_compare()`, a
framework component)**: cosine (null-calibrated: the dual signature/catalog
null-distribution faces `ms_compare_null_rust`, type-7 quantiles + the frozen
MC-SE tolerance) / correlation / JSD / Hellinger ✅ (U-M4-01), Hungarian
one-to-one (primary) + Islam greedy + Jiang activity, the three protocols ✅
(U-M4-01; Jiang requires the k_est=k_ref true-catalog fitting caliber), the
entropy-matched Dirichlet null distribution ✅ (U-M7-pre the shape-conditional
face `ms_compare_shape_null_rust`: the Multinomial(N,u)/N reconstruction
noise conditioned on the reference shape and burden -- alpha_total=N the
continuous limit, no entropy dichotomy needed; the scatter plot
null_family = "shape_conditional" read directly), signature clustering ✅
(ms_cluster_signatures: threshold-graph connected components, deterministic
with no RNG, medoid + size table; the threshold default 0.90 the Islam
line).
**de novo->catalog decomposition (signature annotation)**: the MuSiCal match
semantics + flat cleaning ✅ v0.2.
**Special modes**: panel/ctDNA low counts (MSU-LowCount) 🔶 v1.0, RNA mode
⏳v1.x, single-cell pooling ⏳.

## L-E post-fitting analysis

| Capability | Method | Status | Viz |
|---|---|---|---|
| the per-signature TSB test (no one has done it natively, self-developed) | Poisson/binomial UTS-vs-TS + uncertainty propagation | ✅ v0.2 | strand-bias plot |
| RTA / replication-timing asymmetry | self-developed (no canonical tool in the domain) | ⏳ v1.x | RT profile |
| the damage-segregation sweep (Aitken 2020) + rainfall/kataegis | chain partitioning run/HMM | ⏳ v1.x | damage-rhythm trajectory plot |
| signature timing (the TrackSig-style CCF trajectories) | changepoint + multinomial EM | ⏳ v1.x | trajectory plot |
| inter-group comparison: the Wilcoxon baseline + the DM mixture model (MSU-Infer) + CoDA | Morrill 2025 reproduction + extension | 🔶 from v1.0 | forest plot / boxline + test annotation |
| survival/clinical association (uncertainty propagation) | multiple imputation + Cox | ⏳ v1.x | KM/forest plot |
| the compound determination: the HRD report (the WGS-only contract), PRRDetect, MSI/MMR, tissue of origin | the HRDetect coefficients / Koh 2025 | HRD ✅ v1.0; the rest ⏳ | the HRD report page |
| exposure embedding (UMAP/kmeans) ✅ + differential mining ✅ (ms_exposure_test: the two-group Wilcoxon + BH, the all-tied NA face) | the musicatk idea | ✅ M4 | embedding scatter / clustering plot |

## L-F basic visualization (native ggplot2; the COSMIC style specification: canonical order enforced, the official palette, class-group separation, dual axes, vector output)

| Figure-type family | Coverage | Milestone |
|---|---|---|
| catalog/spectra plots: SBS6/24/96/192/384/1536, DBS78, ID83(89), CN48, SV32, RNA-SBS192 -- sample catalogs + signature spectra + reference spectra | ✅ the first 8 figures M4, the full set M7 | M4/M7 |
| the raw-vs-reconstructed comparison panel (per-channel residuals) | ✅ M4 | M4 |
| exposure: stacked bars ✅, heatmaps ✅, riverplot ✅ (ggalluvial Suggests, PI permission 2026-10-05) | ✅ M4 | M4 |
| similarity: cosine heatmaps, vs-COSMIC scatter plots (cosine + the null-distribution empirical p annotation ✅; the ms_compare per-pair p_null/q_bh BH matrices ✅ -- add-one MC + p.adjust, the conservative all-cell view) | ✅ M4 | M4 |
| the K-selection evidence: the CV error curve + the stability double line + the veto line (the U-M4-03 residual item, the ms_select_k evidence table read directly) | ✅ M2/M4 | M4 |
| bootstrap: CI error bars + stability bars (the U-M4-03 residual item) + the coverage curve (the M3b face); the distribution histogram ⏳M7 (the draws do not land in MsFit -- the upgrade arm) | ✅ M3b/M4 | M4 |
| strand-bias/TSB plots, rainfall, damage-segregation trajectories, RT profiles | 🔶 (TSB v0.2, the rest v1.x) | phased |
| the sample-portrait multi-context grid (the SBS/DBS/ID full-family buckets) | ⏳ v1.x | v1.x |
| CN/SV dedicated: spectra+heatmaps+circos-style profiles | 🔶 v1.0 | v1.0 |
| group-comparison/association plots (boxline+tests, forest plots, enriched-set scatter) | ✅ v1.0 | M4/M6s |

## L-G application-scenario workflows and visual data mining

| Workflow | Scenario (the research 03 ranking) | Status | Mining/visualization deliverable |
|---|---|---|---|
| `ms_atlas_fit()` (the common/rare two-stage atlas mode) | the standard flow of pan-cancer studies | ⏳ v1.x | the cohort signature-landscape heatmap + the common/rare Sankey plot |
| `ms_hrd_report()` | clinical HRD compound (Top-1) | ✅ v1.0 | the HRD report page (the verdict + uncertainty + text) |
| `ms_exposure_panel()` | exposure-attribution epidemiology (Top-3) | ⏳ v1.x | geography/age/exposure-association plots |
| `ms_lowcount_report()` | panel/ctDNA (Top-5/9) | ⏳ v1.x | the sensitivity bound + the conformal interval plot |
| cohort mining: the signature x clinical/genomic-feature association sweep + multiple correction + visualization (**the visual data-mining layer**) | a formalization of domain practice (MSU-Infer) | 🔶 v1.0/v1.x | association heatmaps / forest plots / interactive tables |
| `ms_damage_tempo()` | damage rhythm (near-zero competition) | ⏳ v1.x | the trajectory + test composite plot |
| `ms_rna_report()` | the RNA-only cohort (Top-8; the G2 conditional upgrade) | ⏳ v1.x | the DNA-RNA concordance plot |
| therapy forensics / cross-species / CHIP | Top-6/10 | ⏳ v1.x | the therapy timeline plot |
| the unified report engine (the provenance checklist; the multi-page HTML/PDF presentation ⏳ v1.x) | no standard in the domain (a blank) | ✅ v1.0 | common across all workflows |

## L-H platform layer

| Capability | Status |
|---|---|
| the central object + the workflow grammar (the Seurat doctrine, D16) | ✅ architecture finalized |
| the engine registry + the third-party extension API + certified governance | ✅ architecture finalized, delivered M0/M2 |
| the provenance/reporting standard (a domain blank) | ✅ carried by all objects |
| CLI (a Rust bin, for the bench and pipelines) | ⏳ v1.x |
| the nf-core module / Docker / parquet exchange (consumable by Python) | ⏳ M8/v1.x |
| the tutorial culture: get-started -> the full-workflow vignettes + pkgdown | ✅ phased M4–M7 |

### L-H API surface (the complete set of `ms_*` names; docs-sync CI checks this table against ROADMAP/ARCHITECTURE)

| API (`ms_*`) | Layer | Description | Milestone |
|---|---|---|---|
| `ms_variants()` `ms_tally()` `ms_extract()` `ms_fit()` `ms_compare()` `plot()` | L2/L3 | the trunk of the unified workflow grammar (the six variant classes share one grammar; swapping the engine does not change the pipeline) | M1s/M2/M3a/M4 |
| `ms_select_k()` | L3 | the K-selection adjudication rule (CV argmin -> stability veto -> Wilcoxon diagnostic) | M2 (some diagnostics ⏳) |
| `ms_fit_bootstrap()` `ms_test_presence()` | L3 | the bootstrap CI (support-conditional) and the presence LRT (NB χ²₁ + BH) | M3a |
| `ms_calibration_grid()` `ms_calibration_verdict()` `plot_calibration_curve()` `ms_calibration_sanity()` | L3 | the calibration experiment faces: the MC coverage grid (assembled over the `ms_calibration_grid_rust` kernel face) + the verdict-window verdict + the coverage-curve plot + the real-data downsampling sanity harness (sanity is never written as calibration evidence; the data-acquisition/governance protocol inst/sanity/README.md, real data never enters the repository) | M3b |
| `register_ms_engine()` `match_ms_engine()` `ms_engines()` | L3 | the engine-registry extension entry + string-sugar resolution (A14, listing every available engine name on failure) + the catalog of registered engines; the certified tri-state governance (A17), resolving to a non-certified engine warns once | M0 |
| `ms_engine()` `fit_engine()` `required_pkgs()` `ms_extract_signatures()` `ms_extract_exposures()` `ms_extract_fit_time()` | L3 | the engine-registry S7 generics (the `ms_extract_*` are generic accessors; only the latter two enter the FFI surface) | M0/M2 |
| `ms_benchmark()` | L3 | the mlr3-style benchmark grid; a non-certified engine emits an explicit warning | M0 skeleton / M7 complete |
| `ms_sitrep()` | L3 | environment/dependency/refdb/thread diagnostics | M0 |
| `ms_qc_report()` `ms_downsample()` `ms_convert()` | L2 | the QC report, depth downsampling, opportunity conversion | from the M0 skeleton |
| `ms_update_refdb()` | L2 | reference-library update (the cache-side extender for CN/SV/RNA-SBS/mouse sets) | ⏳ M4 |
| `ms_import()` `ms_export()` `ms_segments()` `ms_sv()` `ms_simulate()` | L2 | format interoperability, allele-specific CN / SV input, the catalog simulator (the first version of the ms_simulate variant-count layer: the multinomial/poisson/nb three arms, VCF-level placement ⏳M7) | M1c (CN/SV) / M4 (interoperability) / M7-pre (simulate) |
| `ms_stratify_hypermutants()` | L2 | hypermutator stratification (classification + de novo exclusion + forced refit) | M1c |
| `ms_atlas_fit()` `ms_hrd_report()` `ms_exposure_panel()` `ms_lowcount_report()` `ms_rna_report()` `ms_damage_tempo()` | L4 | application workflows | see L-G |
| `ms_nmf()` `ms_ard()` `ms_sparse()` `ms_lda()` `ms_correlated()` `ms_tensor()` `ms_supervised()` `ms_hdp()` `ms_bayes()` | L3 | the engine factories (S7 objects as first-class citizens, strings as sugar; the L-C/L-D status columns govern) | see L-C |
| `ms_tally_rust()` `ms_extract_rust()` | L1 | **FFI internals** (not a user-API promise; frozen and governed by `docs/ffi-surface.md`, from M0) | M0/M1s |

---

## ⚡ the "you might not have thought of" list (coverage added by this matrix)

1. **QC is a first-class layer** (L-A): the sample-QC report, pseudosignature
   detection and removal, amber/red grading -- a domain pain point (research
   03 §11.5), not an add-on feature.
2. **opportunity normalization and the panel opportunity catalog**: WES/panel
   refits against a WGS reference systematically bias flat signatures
   -- the within-likelihood opportunities + `ms_convert()`.
3. **MNV/complex routing and the DBS re-join after VCF splitting**: left
   unpatched, the SBS/DBS catalogs are systematically distorted (semantic
   correctness, not performance).
4. **genome hygiene**: the contig whitelist, sex-chromosome opportunity
   correction, the per-sample ploidy opportunities, chrM routing, T2T.
5. **the simulator as a platform capability**: the null models / scenario
   generators are built-in (shared by the benchmark and the tests), not
   external scripts.
6. **the report engine and the provenance checklist**: no reporting standard
   in the domain -- every analysis carries auditable metadata.
7. **the calibration diagnostic plots**: the coverage curve as a
   first-class visualization (the honest display of MSU-Fit).
8. **cohort visual data mining**: the signature x feature association sweep
   + multiple correction + graphics -- the day-to-day operation of an
   application paper.
9. **the engine-equivalence matrix itself**: any mainstream method one row
   away (D15), the benchmark culture made everyday.
10. **Python/pipeline interoperability**: parquet exchange + CLI +
    nf-core -- the domain's center of gravity is in Python, do not lock
    down into R.

## The self-check against the Seurat analogy (D16)

| The Seurat success ingredient | the msuiter counterpart | matrix landing |
|---|---|---|
| the unified object (the Seurat object) | MsVariants/MsCatalog/MsSignature/MsFit | L-H |
| the workflow grammar (NormalizeData→…→UMAP) | ms_variants→ms_tally→ms_extract→ms_fit→ms_compare→plot | L-H |
| the integration of all methods | the engine-equivalence matrices (L-C/L-D) | L-C/L-D |
| the trustworthy default pipeline | the consensus-CV pipeline + MSU-Fit/LowCount/Infer | §5 the default path |
| tutorials/ecosystem | the vignettes/pkgdown/nf-core/extension API | L-H/L-G |

**Matrix governance**: at each milestone's acceptance the PI updates this
matrix (the status columns + new capability rows); the docs-sync CI verifies
that the ms_* function names promised in the matrix agree with
ROADMAP/ARCHITECTURE (the enumeration carrier is the L-H "API surface"
table; a user API that appears in ARCH/ROADMAP without being listed in that
table counts as drift, except the ms_*_rust FFI internals, governed
separately by docs/ffi-surface.md).
