# Research report 07: the complete algorithm-zoo inventory and the self-development opportunity list
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-28. Filling the coverage gaps of the first five reports (20 items verified one by one), and producing the tiered algorithm-zoo master table (driving the implementation scope) plus the self-developed integrated-method shortlist. The verification means: Europe PMC/NCBI eutils/OpenAlex, the GitHub sources, direct readings of the normative documents. The **[unverified]** items are marked.

---

## §1 The gap-audit conclusions (20 items)

1. **musicatk** (Bioconductor 2.6.0, LGPL-3; Chevalier 2021 Cancer Research doi:10.1158/0008-5472/CAN-21-0899): the S4 `musica` object = the mutation annotations + the multi-channel count tables (SBS96/DBS78/ID/TSB/RS and the combinations) + `result_collection` (multi-algorithm × multi-K). The discovery: `algorithm="lda"` (the topicmodels LDA, signatures=exp(β), exposures=γ) or `"nmf"` (+ an ε pseudo-count). The prediction: the LDA posterior or decompTumor2Sig. It includes UMAP/kmeans/cosine comparisons/Shiny. **Value: the multi-catalog object model + the topic model as a first citizen — adopt the design ideas.**
2. **signifinder** (Bioconductor, AGPL-3): **out of domain** — the gene-expression tumor signatures (RNA/microarray scoring), not mutational signatures. Excluded.
3. **TBSignatureProfiler** (Bioconductor, MIT): **out of domain** — the tuberculosis transcriptome signatures. Excluded.
4. **TensorSignatures** (Vöhringer, Nat Commun 12, 2021, doi:10.1038/s41467-021-23551-9; github.com/sagar87/tensorsignatures; PyPI 0.5.1 unmaintained, TensorFlow 1.x): **the non-negative tensor factorization (NTF) + the negative-binomial noise**, the count tensor = channel × sample × tissue × genomic-attribute bins (replication timing/transcriptional direction/functional elements); the BIC fixes K; the signatures and the "genomic-state response curves" are jointly learned. Applied on the PCAWG 2,778 + HMF 3,824. **Value: solves the "signatures vary with the genomic state" that the 96-vector NMF cannot express — a self-development reimplementation target (see §3.1).**
5. **Pollock**: **an errata** — Storrs et al.'s pollock is a single-cell-expression cell-type classifier (ding-lab, Bioinf Adv 2022), **there is no mutational-signature version** (PubMed zero hits). Skipped.
6. **SigFormer** (Zhang, Niu, Zong; bioRxiv 2026-01-21, PMID 41648438, doi:10.64898/2026.01.20.700228, PMC12871590): a set-conditional transformer, the reference signature set × the sample catalog cross-attention; claims to beat MuSiCal under high noise / overcomplete catalogs; **explicitly outputs an "unattributable residual"** instead of force-fitting flat signatures. **A preprint not peer reviewed; the public repository is confirmed = github.com/zonglab/SigFormer (MIT, the README self-describes as a "mutational-signature decomposition and analysis toolkit for SBS96 profiles"; no paper citation, not yet cross-linked with the bioRxiv preprint)**. Absorb the ideas: the residual channel, the noise-robust refit.
7. **mSigSDK / mSigPortal**: the computation layer = a SigProfiler-stack wrapper; no independent publication index; **"mSigSDK" gets zero hits across the GitHub/PyPI/Bioconductor registries (the empirical search of 2026-09-28), its existence could not be confirmed**; the portal JSON schema unreachable [unverified].
8. **SIGNAL**: signal.mutationalsignatures.com = **Degasperi A et al., "A practical framework and online tool for mutational signatures analyses…", Nature Cancer 1:150–162, 2020, doi:10.1038/s43018-020-0027-5**. MutationalPatterns bundles its 2020-07-03 download: the reference / tissue-specific / exposure (**the Kucab 2019 Cell experimental-mutagen signatures**) + artifact, four faces. **The license (verified by reading the source 2026-09-28) = the LICENCE file of `signature.tools.lib` carries BSD-3-style clauses + academic-research-only restrictions (clause 5 forbids clinical-care use; clause 6 limits to non-profit institutions and excludes research commissioned/collaborated with for-profit entities; clause 7 requires modified versions be shared freely) — not a standard OSI license, like a GPL it is unusable for direct code reuse, usable only as an algorithmic-semantics reference.** The repository's `data/` bundled reference sets are enumerable (RefSigSBS_v2.03, RefSigDBS_v1.01, RefSigv1_Subs/Rearr, COSMIC_v3.2 SBS/DBS GRCh37, Breast560_rearrangement, PCAWG sigs, ConversionMatrix). **The Sanger site (the four faces reference/tissue-specific/exposure/artifact) is JS-rendered, static scraping unreachable [unverified].**
9. **The Nik-Zainal RefSig/hierarchy**: v1 = Degasperi 2020 Nat Cancer; **v2 = Science 376:eabl9283 (2022)** (12,222 GEL WGS; **adds 40 SBS + 18 DBS**; common/rare; FitMS; the hierarchy T1/T2/T3 common + T0–T4 rare incl. the **QC amber/red artifact signatures**) — verified via the signature.tools.lib README.
10. **The USARC/CN40/CNV48/CN176 provenance**: USARC = Steele CD, Cancer Cell 35:441-456.e8, 2019 (doi:10.1016/j.ccell.2019.02.002); **CN40 = Wang S, PLoS Genet 17(5):e1009557, 2021** (the sigminer authors' own method); **CNV48 = Steele Nature 2022** (the 48-component `CNstate:sizeclass` labels, the reference matrix in the SigProfilerExtractor `data/CNV_signatures.txt`); **CN176 = Tao Z, Wang S, … Liu X-S, Brief Bioinform 2023, doi:10.1093/bib/bbad053** (TCGA176/PCAWG176).
11. **The Drews breakpoint features**: **Drews RM et al., "A pan-cancer compendium of chromosomal instability", Nature 606:976–983, 2022, doi:10.1038/s41586-022-04789-9** (7,880 tumors, **17 CN signatures**); the feature family = segsize/bp10MB/osCN/bpchrarm/copynumber/changepoint (an extension of Macintyre 2018); `calculateActivityDrews` fits `Drews2022_TCGA_Signatures` with **`limSolve::lsei`**.
12. **The Koh 2025 new indel taxonomy**: **Koh GCC, … Zou X, Nik-Zainal S. "A redefined InDel taxonomy provides insights into mutational signatures." Nat Genet 57:1132–1141, 2025, doi:10.1038/s41588-025-02152-y**. The motivation: ID83 cannot separate the MMR/polymerase-repair-deficiency signatures in the isogenic models. The new taxonomy = **flanking context + informative base order (longer homopolymers) → 89 subtypes + a 476-channel full catalog**; the 100kGP 7 cancer types → **37 indel signatures (27 new)**; the **PRRDetect** repair-deficiency classifier. The software: github.com/Nik-Zainal-Group/indelsig.tools.lib (`indel_classifier89`, `gen_catalogue89`, the `indel_highspecific` filter [drops repeats ≥10, indels >100bp]; the NNLM fit). **The new indel standard — native support is differentiation.**
13. **Damage segregation/rainfall**: the classic = **Aitken SJ et al., Nature 583:265–270, 2020, doi:10.1038/s41586-020-2435-1** (the replication-strand-phased strand-bias run scans); the follow-ups Anderson Nature 2024 (doi:10.1038/s41586-024-07490-1), Ginno Nat Genet 2024 (doi:10.1038/s41588-024-01712-y), Spencer Chapman Nature 2025 (the SBS19 persistent damage). The implementations are minimal repositories only (J0bbie/LesionSegR, tomsasani/lesion-segregation). Rainfall/kataegis: ≥6 mutations + a mean intermutation distance ≤1000bp (Nik-Zainal 2012 Cell); the classic implementations maftools::rainfallPlot, MutationalPatterns::plot_rainfall.
14. **RTA/topography**: SigProfilerTopography (Otlu, Cell Reports 42:112930, 2023, doi:10.1016/j.celrep.2023.112930) = the topographic effects of chromatin/histones/TFs/replication/transcription on the signature activity. The standard strand-bias test = MutationalPatterns' `mut_strand/strand_bias_test`. **The RTA has no canonical standalone tool** (only the Yaacov 2023 ad-hoc metric; TensorSignatures models the RT dependence directly) — the gap is confirmed.
15. **Similarity/comparison**: the cosine is the only de facto standard (the chance baseline of random non-negative 96-vectors ≈0.75, computed by Islam 2022); sigminer has the cosine only (source-verified); decompTumor2Sig additionally has Euclidean/correlation/SIM(Shiraishi); the JSD/Hellinger are scattered. **There is no principled metric-comparison paper** (the 2022–2026 searches); "signature ontology"/"MSpoisson" do not exist. A gap.
16. **SuperSigs**: Afsari B et al., eLife 10:e61082, 2021 (doi:10.7554/eLife.61082). The algorithm (source-verified at TomasettiLab/supersigs): selecting the "surviving mutations" via the nested partition / minimal σ-algebra (`generate_min_sigma_algebra`) + the age-corrected logistic regressions + the nested-CV feature selection. The Bioconductor **supersigs** v1.21.0. No successor.
17. **Exposure regressions/associations**: the only formalized method = **Morrill Gavarró L, Couturier DL, Markowetz F. "A Dirichlet-multinomial mixed model for determining differential abundance of mutational signatures." BMC Bioinformatics, 2025, doi:10.1186/s12859-025-06055-x** (the compositional DM mixed-effects differential-abundance model). The rest of the application literature is all ad hoc Wilcoxon/Cox. **The gap is confirmed: there is no unified compositional regression/survival framework.**
18. **The VCF/MAF/BCF standards**: the VCF hts-specs **v4.5 current** (the multi-sample FORMAT/AC/GT ploidies/the symbolic SV alts/the left-align+multiallelic splitting as the encoding preconditions); the BCF v2 (BGZF + indexed random access); the MAF = the TCGA/GDC normative columns (Chromosome/Start_Position/Reference_Allele/Tumor_Seq_Allele2/Tumor_Sample_Barcode/Variant_Classification). Splitting multi-sample VCFs into per-sample catalogs is a hotbed of somatic/germline confusion and ploidy bugs — a typed IO layer is a differentiator.
19. **The catalog-format interoperability matrix** (all source-verified): the SigProfiler txt (the SubType/Type header TSV), the COSMIC txt, the SIGNAL txt, the MutationalPatterns R matrices/RDS, the **WTSI long format** (`MutationType|Trinucleotide|Sample|count`, common in old sets), the signature.tools.lib catalogs, the sigminer RDS, the mSigPortal JSON [unverified], the **ICAMS** (steverozen/ICAMS, the canonical in-memory catalog + strand-awareness + normalization semantics); "MSA format/sigverse" do not exist.
20. **The exact definitions of the benchmarking metric protocols** (must be replicated bit-for-bit):
   - **The Islam 2022 extraction protocol** (Cell Genomics 2:100179, doi:10.1016/j.xgen.2022.100179): each extracted signature **counts a TP if its maximum cosine against any true signature ≥ 0.90**; FP = a max cosine < 0.90 against all the truths; FN = an unmatched truth. Precision=TP/(TP+FP); sensitivity=TP/|truth|; F1. The robustness sweeps thresholds 0.80–0.90. **A greedy per-extracted-signature classification — not a one-to-one Hungarian** (the one-to-one/one-to-many are used only for describing the relations to COSMIC).
   - **The Jiang 2025 fitting protocol** (bbaf042): the synthetic spectra = **negative-binomial channel sampling**, the dispersion calibrated to real reconstruction precisions; **the matching is by activity>0 (no cosine)**: TP=true>0 and estimated>0; FP=true 0, estimated>0; Specificity=(absent and not attributed)/absent count; **scaled Manhattan = Σ|â−a|/n mutations**; **Combined Score = (1−scaled Manhattan) + Precision + Recall**; a "reasonable reconstruction" = cosine > 0.969 (the median of the true attributions).
   - Plus one: Medo 2024 doi:10.1038/s41467-024-53711-6 (synthetic + the real 146 PCAWG >50k SBS).

---

## §2 The tiered algorithm-zoo master table

Status: **Rust** = engine-native implementation; **R** = the R-interface implementation; **Adapt** = an external-tool benchmark adapter (benchmarking only, not into the ms_* API); **Skip**; ★ = a self-development improvement candidate.

### (a) Catalogs/representations
| The algorithm | The semantics | The source | The status | The improvement |
|---|---|---|---|---|
| SBS96 | the canonical substitution channels | Alexandrov 2013/2020 | Rust | ★ the cornerstone, losslessly retained |
| SBS384/1536/6144 | the context+strand extensions | PCAWG/SigProfiler | Rust | ★ the high-resolution channels are underused |
| DBS78 | the dinucleotide channels | Alexandrov 2020 | Rust | — |
| ID83 | the canonical indels | Alexandrov 2020 | Rust | the backward compatibility |
| **ID89/476** | the base-order+flanking indels | Koh 2025; indelsig.tools.lib | Rust | ★ the new standard, early support = differentiation |
| RS32/RS38/BRCA560 | the rearrangement channels | Nik-Zainal 2016; Degasperi 2020 | Rust | — |
| CN40/Drews21/CNV48/CN176 | the copy-number feature spaces | Wang 2021; Macintyre 2018; Steele 2022; Tao 2023 | Rust | ★ the unified typed feature IR |
| TSB/RT/composite channels | the transcriptional/replication strand channels | musicatk; MP | Rust | ★ the core first citizens |
| the tensor representation (channel×sample×tissue×attribute bins) | the genomic-state awareness | TensorSignatures 2021 | Rust | ★ see §3.1 |
| the musica multi-catalog object | mutations+multi-catalogs+results unified | musicatk | a design concept | ★ the object model adopted into the Rust core |
| the Shiraishi feature vectors | the context-free substitution representation | Shiraishi 2015 | Skip (interoperability via the outside) | — |

### (b) Preprocessing/normalization
| The algorithm | The semantics | The status | The improvement |
|---|---|---|---|
| VCF/BCF parsing, left-aligning, multiallelic splitting | the hts-specs v4.5 | Rust (noodles/hts-rs) | ★ typed, tested, streaming |
| MAF import (the GDC columns) | validated at read | Rust | ★ |
| the opportunity normalization | genome/exome/panel | Rust | ★ panel/coverage-aware — the field's weak spot |
| the repeat/mappability/low-complexity filters | removing the untrustworthy regions | Rust | ★ the unified filter registry |
| the strand/RT annotations (GENCODE/Repli-seq) | the per-mutation annotation cache | Rust | ★ a first citizen |
| depth downsampling | fairness across samples | Rust | — |

### (c) Extraction
| The algorithm | The semantics | The status | The improvement |
|---|---|---|---|
| the KL-Poisson NMF MU (Brunet) | the industry core | Rust | ★ the deterministic reimplementation |
| the NNLS/HALS NMF | fast alternation | Rust | ★ |
| the LDA/topic model | the generative multinomial | Rust | ★ the Poisson-NMF/LDA unification |
| the Bayesian HMC/Gibbs NMF | the posterior | Adapt (sigfit/signeR as benchmark comparators only) | — |
| the ARD-NMF | the automatic rank | Rust | ★ |
| **the NTF+negative binomial (the genomic-state tensor)** | the signature×attribute response | Rust | ★ §3.1 |
| the supervised extraction (the minimal σ-algebra + logistic regressions) | the factor supervision | R (native) + a Rust kernel | ★ the supervised module |
| the SigProfilerExtractor full loop | the reference standard | Adapt (the benchmark reference) + a reimplemented Rust kernel checked against it | — |
| the attention single-sample refit (the SigFormer idea) | the residual channel | Watch (no code) | absorb the residual idea |

### (d) K selection
| The algorithm | The status |
|---|---|
| the resampling stability + cophenetic/dispersion/silhouette-MC (the SigProfiler suite) | Rust ★ the deterministic reimplementation |
| the reconstruction-error elbow/plateau | Rust (diagnostics only) |
| the tensor/NB-model BIC | Rust ★ |
| the held-out likelihood (the MuSiCal style) | Rust (semantics audited) |
| the SUITOR entry-wise CV | Rust ★ the flagship |
| the Bayesian marginal likelihood (signeR/BayesPowerNMF) | Adapt |

### (e) Fitting/attribution
| The algorithm | The status | The improvement |
|---|---|---|
| the QP/NNLS catalog fit | Rust | ★ the fast path |
| the multinomial/Poisson EM fit | Rust | ★ the default path |
| the mmsig EM + bootstrap-filtered refit | an R port | — |
| the MuSiCal likelihood-sparse NNLS | Rust (audited) | beaten on the benchmark |
| the SigProfilerAssignment full set | Adapt (the reference) | — |
| the FitMS hierarchical fit (T1-T3/T0-T4 + unexplained detection) | a Rust port | ★ the pipeline reuse |
| the LDA-posterior refit | Rust | — |
| the low-burden specialists (the SigMA-style binomial tail aggregation) | Adapt | ★ §3.4 |
| the sampling likelihood (sigLASSO) | Adapt | — |
| the CN-feature-space constrained LS (Drews/Macintyre) | Rust | ★ unified with the count-space CN fitting |
| the per-mutation posterior allocation | Rust | ★ |
| the SigFormer-style attention refit | Watch | §3.4 |

### (f) Uncertainty/inference
| The algorithm | The status | The improvement |
|---|---|---|
| the signature/exposure bootstrap | Rust | ★ |
| the presence LRT (the mSigAct style) | Rust | — |
| the HMC/Gibbs posterior | Adapt | — |
| the profile likelihood/Fisher information | Rust | ★ (nobody implements it) |
| **the conformal prediction intervals** | a new concept | ★ §3.4 |

### (g) Post-fitting analyses
| The algorithm | The status | The improvement |
|---|---|---|
| the TSB tests | Rust | ★ per-signature (nobody does it) |
| the RTA metrics | Rust | ★ §3.6 (no canonical tool) |
| the damage-segregation scans (the strand-phased HMM/runs) | Rust | ★ §3.6 |
| the rainfall/kataegis | Rust | — |
| the exposure UMAP/kmeans + differential | Rust | ★ |
| **the DM mixed-model differential abundance (Morrill 2025)** | an R port | ★ §3.5 |
| the survival/Cox on the exposures | Rust/R | ★ §3.5 formalized |
| the signature timing vs CN events (the TrackSig style) | Adapt | — |
| HRDetect (a probit linear classifier + bootstrap) | Rust | ★ the bit-for-bit coefficient-validated tests |
| **PRRDetect** (the ID89 repair-deficiency classification) | Rust | ★ |
| the tissue-of-origin classifier (Nguyen 2022, doi:10.1038/s41467-022-31666-w) | a candidate | — |
| the phylogeny-aware exposure evolution (PhySigs/Palimpsest) | Adapt | — |

### (h) Similarity/comparison
| The algorithm | The status | The improvement |
|---|---|---|
| the cosine (the chance baseline ≈0.75) | Rust | ★ the zero-calibration threshold |
| the correlation/Euclidean/JSD/Hellinger | Rust | ★ §3.3 the metric study |
| the signature hierarchical clustering | Rust | — |
| the 1-to-1/1-to-many composite matching | Rust | ★ the Hungarian + the Islam greedy, the dual protocols |

### (i) QC/artifacts
| The algorithm | The status | The improvement |
|---|---|---|
| the artifact reference signatures (SBS17a/b, FFPE, chemotherapy) | a Rust catalog | — |
| the amber/red QC tiers | Rust | ★ woven into the fit tiers |
| the unexplained-residual detection | Rust | ★ §3.4 |
| the catalog legality/low-count warnings | Rust | — |
| the PoN/artifact region masks | Rust | ★ |

### (j) Simulation/generators
| The algorithm | The status | The improvement |
|---|---|---|
| the realistic-genome-placement simulator (the SigProfilerSimulator style) | Rust | ★ |
| the scenario generators (easy/medium/hard) | Rust | ★ the exact replication of the Islam 2022 scenarios |
| the NB channel sampler (the calibrated dispersion) | Rust | ★ the Jiang protocol |
| SynSig synthetic spectra + evaluation | Adapt (steverozen/SynSig) | ★ |
| CN genome simulation | Adapt (markowetzlab/CINSignatureGenomeSimulation) | — |

---

## §3 The self-developed integrated-method shortlist (the self-creation opportunity list — the paper's methodological core)

1. **The genomic-state tensor engine ("TensorSignatures done right")**: TS proved the signatures respond to the replication-timing/transcription/element states, but its TF1 implementation died and there is no mainstream integration. Self-develop: a Rust NTF + the NB noise + GPU + BIC/LOO for the K + five modalities sharing the exposures. The novelty: the first multi-modality, multi-attribute generative signature model.
2. **A single catalog IR, multi-channel projections**: the indels (83 vs 89/476), the CN (40/21/48/176), the SV (32/38) are scattered across mutually incompatible tools with varied fitting styles. Self-develop: a typed catalog intermediate representation + lossless projections + a joint exposure with a cross-projection consistency prior. The novelty: a cross-modality unified exposure semantics, for the first time making the CN-signature benchmarks comparable.
3. **The calibrated-similarity and matching library**: the cosine is alone, the thresholds uncalibrated, the matching protocols inconsistent. Self-develop: multiple metrics + analytic/empirical null distributions (by channel count × burden) + the exact reference implementations of the Hungarian/Islam-greedy/Jiang-activity tri protocols. The novelty: the field-missing "signature-comparison metrology" paper + the reference implementations.
4. **The low-burden refit: the explicit residual + coverage guarantees**: the SigFormer (no code) proposition + the SigMA stall + the normal-tissue/ctDNA pain points. Self-develop: a likelihood-calibrated refit + a sparse prior + a residual channel + **conformal prediction intervals** (distribution-free coverage guarantees). The novelty: distribution-free guarantees for attribution — the field's first.
5. **The compositional exposure-regression kit**: only Morrill 2025's DM mixed model formalized the between-group tests; there is no survival/case-control/longitudinal framework. Self-develop: DM/logistic-normal mixed models (fixed+random effects, a burden offset) + Cox/AFT extensions + multiple corrections; reproduce Morrill first, then extend. The novelty: the first unified exposure-association framework (the R-side flagship).
6. **The damage-tempo analysis**: the damage segregation + TSB + RTA as first citizens. Self-develop: streaming strand-phased run/HMM scans over the encoded phase + calibrated p values + the joint report (the segregation index/TSB/RTA/rainfall). The novelty: the per-sample integrated "damage tempo" profile; linked with the tensor engine's RT bins.
7. **The deterministic high-performance NMF core**: the SigProfiler loops are slow and nondeterministic across runs; the K selection is fragmented. Self-develop: a Rust KL-NMF (MU+HALS) + deterministic seeds + a resampling stability loop; certified by the exact reproduction of the Islam 2022 F1 curves. The novelty: the certified determinism + speed orders — the engineering-paper material and the suite's trustworthiness anchor.
8. **The interoperability and provenance layer**: the catalog formats are fragmented, the portal schemas closed, the signature-set versions/licenses a mess. Self-develop: the lossless import/export of the verified formats + a JSON schema we publish (filling the mSigPortal gap) + versioned citable signature-set packages (etiology/cohort/license/DOI). The novelty: the field's "catalog package manager".

**The out-of-domain exclusions (verified)**: signifinder, TBSignatureProfiler (the expression signatures), pollock (the cell classifier). **Non-existent/unconfirmed**: the public mSigSDK, the mSigPortal schema, the SigFormer repository, the SIGNAL license and set counts, "MSA format", "sigverse".
