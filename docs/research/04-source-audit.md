# Research report 04: the per-repository deep source audit
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-27. All repositories were shallow-cloned to /tmp/audit/<NAME>; except where marked "not read", every claim is source-level reading. Fields: language/LOC, license, the core-algorithm files (exact paths), engines, inputs/outputs, the unique ideas worth adopting, the performance-relevant patterns, the maintenance status.

---

## 1. SigProfilerMatrixGenerator (AlexandrovLab) — the most critical repository

- **Language/LOC**: Python, ~13,700 LOC package-wide; the algorithms concentrate in the refactored 4,057-line single file.
- **License/maintenance**: BSD-2-Clause; **very active** — the last commit 2026-09-22 (refactored into `SigProfilerMatrixGenerator/scripts/MutationMatrixGenerator.py`; the old `indel.py`/`dbs.py` no longer exist).
- **Genome access (the key engineering decision)**: at runtime there is no pysam, no 2bit. `install_genome()` downloads the **pre-encoded per-chromosome raw byte files** (`{chrom}.txt`, built by `save_chrom_tsb_separate.py`). Each byte is a 0–19 enumeration, **encoding simultaneously the base and the transcriptional-strand class** (`SigProfilerMatrixGeneratorFunc.py:173-192`): 0–3 = intergenic ACGT (the "N" bias), 4–7 = transcribed, 8–11 = untranscribed, 12–15 = bidirectional, 16–19 = N. The runtime context fetch is `tsb_ref[chrom_string[start-1]][1]` — one dictionary lookup yields the base+strand together. The whole chromosome is loaded as one Python bytes string. **Pre-encoded annotation baking — a brilliant idea, trivially portable to Rust (a per-byte enumeration, zero hashing).**
- **SBS** (`catalogue_generator_single`, `MutationMatrixGenerator.py:350`; the context fetch `:778-788`; the key `:907-917`): the 5-base window (start-3..start+1, 0-based) = trinucleotide ±1 pentanucleotide; if the middle character ≠ REF the mutation is skipped; when REF∈{A,G} revcompl REF/ALT/sequence and flip the bias (the revbias swaps T↔U, 1↔2). The key = `"bias:XY[R>M]ZW"`. The index is built in `SigProfilerMatrixGeneratorFunc.py:1004-1024`: all pyrimidine-centred 5-mers × 3 alts × 4 biases {T,U,N,B} = **SBS6144 = 1536×4 TSB**; the 1536/384/96 are obtained by slicing/grouping that index string.
- **DBS** (`:484-694`): a dinucleotide substitution = adjacent SNVs at a distance of exactly 1 (`dinuc_sub == 1`, `:491`), same sample; MNVs (distance ≤ `mnv=5`) are diverted to seqinfo. The context = the 5'-base + `[XY>NZ]` + the 3'-base. The direction normalization (`dinuc_tsb_ref = ["CC","CT","TC","TT","AA","AG","GA","GG"]`, `:484`): if the **raw reference dinucleotide** does not start with a pyrimidine, mark the bias "Q" (the strand is ambiguous) **and still revcompl-flip the whole 5-mer to the canonical form** (`:673-694`). The main index **DBS2976** = 36 pyrimidine-start forms × 16 flanks × 4 biases (2304) + 42 Q-forms × 16 (672); folded via index-string slicing into 78/186/1248/150/2400 (`matrix_generator_DINUC`, `:3800`). The bidirectional "B" counts are split into T and U toward the larger side by integer division + remainder (`:3925-3960`).
- **INDEL (the 83 channels, the exact algorithm)** (`catalogue_generator_INDEL_single`, `:1169-2100`):
  1. Normalize; a deletion = `len(ref)−len(mut)==len(ref)−1`, an insertion = symmetric, otherwise **complex** (`:1407-1425`).
  2. Strand: take the indel's first affected base; if G/A revcompl, mark strand −1, flip the bias.
  3. **Repeat detection** (del `:1455-1493`): walk backward from `start` stepping by the indel length, walk forward from `start+len`, appending matching tandem units; **no window cap**.
  4. **Microhomology** (`:1494-1542`, only when length>1 and not a repeat): `forward_homology = ref[1:-1]` (the deleted sequence minus its last base), `reverse_homology = ref[2:]`; from long to short: compare the genome [start+len, start+len+i) with `forward_homology[:i]`, and reverse-compare [start−i, start) with `reverse_homology[-i:]`. On a tie → the forward wins. The insertion is symmetric about the insertion point.
  5. **The channel key** (`:1659-1736`): `key1:Del/Ins:key3:key4`; key1 = the length capped at 5; key3 = "R" (repeat)/"M" (MH)/, at 1bp, "C" (pyrimidine) or "T"; key4 = when R: `len(sequence)/key1 − 1` (capped at 5); when M: `len(sequence) − len(indel)` (capped at 0–5); at 1bp: `len(sequence)−1` (capped at 5). ⇒ 83 channels ("1:Del:C:0"…"5:Del:M:5"). The `limited_indel` mode remaps MH insertions as R:0 (the 32-channel simplified version). The "complete" subkey stores the literal sequence (revcompl if G/A-starting) for the 5bp-resolution variants.
  6. **The TSB disambiguation rule** (`:1846-1857`): when the accumulated repeat/MH sequence is all C/T or all G/A the event strand is unresolvable → the bias "Q" ⇒ the **150-channel ID-TSB** matrix.
- **CN48** (`CNVMatrixGenerator.py:21-69, 330-381`): the 48 features = {homdel}×{0-100kb, 100kb-1Mb, >1Mb}(3) + TCN{1,2,3-4,5-8,9+}×{LOH,het}×5 size bins (0-100kb, 100kb-1Mb, 1-10Mb, 10-40Mb, >40Mb)(25+20). **Note TCN1 has LOH only (no "1:het"); homdel has only 3 bins.** The LOH is decided by each of the 8 input formats' hard-coded column names (ASCAT/ASCAT_NGS, ABSOLUTE, Battenberg, PURPLE, FACETS, SEQUENZA, PCAWG, `:75-232`). **Each segment counts 1 (no length weighting).** The length = (end−start)/1e6.
- **SV32** (`SVMatrixGenerator.py`): `processBEDPE` (`:1037-1192`) — the svclass is decided by the breakpoint strands: (+,+)=deletion, (−,−)=tandem duplication, mixed=inversion, different chromosomes=translocation; size=|start1−start2|, 5 bins (1-10Kb, 10-100Kb, 100Kb-1Mb, 1Mb-10Mb, >10Mb); SVs <1kb are dropped (except translocations). `annotateBedpe` (`:797-930`): **clustered** = the breakpoint is in a "kat region": sort the breakpoints per chromosome, compute the breakpoint spacings, run `exactPcf` on the log distances (a piecewise-constant fit, kmin=10 breakpoints/chromosome), mark regions below `thresh_dist`, propagate the marks to any SV whose breakpoint falls in a marked region. `tsv2matrix` (`:1193-1252`): 32 = {del,tds,inv}×5 sizes×{clustered, non-clustered} + 2 translocation channels.
- **Engine**: none. Pure Python per-character loops + per-byte dictionary lookups + pandas `.at[]` increments + file appends. No BLAS, no numpy (except the matrix initialisation), no threads. **The biggest CPU black hole of the SigProfiler stack, the most obvious Rust-porting target.**
- **I/O**: in VCF/CSV (+BED, the exome/panel BED filters, the per-chromosome splitting); out TSV matrices (SBS 96…6144, DBS 78…2976, ID 83/150/simple/complete, CNV48, SV32) + optional plots + the seqinfo/MNV/complex debug files.
- **The unique ideas worth adopting**: the pre-encoded genome+annotation byte strings; the "Q" strand-ambiguous channel family across all three mutation classes; the matrix hierarchy of a main index + string-slice folding; the strict REF-vs-genome validation + the per-mutation skip log.
- **The RNA context: does not exist** (a whole-package grep — no RNA-editing code; only the TSB variants). An "RNA SBS" must be implemented separately.

## 2. MutationalPatterns (UMCUGenetics, Bioconductor)

- Pure R (~60 files). **MIT**. 3.7.1 (devel); the GitHub mirror stopped updating 2022-11-22 (Bioconductor continues via SVN/git.bioconductor.org).
- `extract_signatures.R`: `NMF::nmf(mut+0.0001, rank, method="brunet", nrun=200, seed=123456)` (the KL MU, multicore via the NMF framework) or the ccfindR variational Bayesian. Deterministic seeded defaults.
- `fit_to_signatures.R`: **a per-sample loop of `pracma::lsqnonneg`** (pure-R Lawson-Hanson NNLS).
- `fit_to_signatures_strict.R`: **the backward selection** — full fit → drop the lowest contributor → refit → repeat; stop when the adjacent-iteration cosine similarity drop exceeds max_delta (0.004); there is also a **best_subset** mode (exhaustive n−1 combinations; recommended for ≤10–15 signatures).
- `mut_context.R:37-48`: **`Biostrings::getSeq` on shifted GRanges** (C-grade BSgenome fetches, vectorized) — the "fast" way to fetch contexts in R; then string-concatenation channel keys, `factor(levels=precomputed)` + dplyr counts. Purine-start mutations revcompl the context.
- `get_indel_context.R`: **bounded** repeat counting — take a fixed 19/20bp flank, count repeats by string replacement (`.indel_count_n_repeats`, `:546-566`), take max(left,right); the microhomology is likewise window-capped. **Simpler than SPMG but capped at the window, and it does not match SPMG's exact R/M key4 semantics** (a bounded approximation breaks comparability — the cautionary tale).
- Keep: the channel-factor-ordering philosophy, the strict-refit max_delta concept, the cosine-decay plots. Replace: the lsqnonneg loops, NMF::nmf, all the BSgenome round-trips.

## 3. deconstructSigs

- R 1.9.0, **GPL≥2**, stopped updating 2020-08 (frozen).
- **Not NNLS**: a greedy coordinate descent — start from the best single signature (findSeed); each step, for every candidate do a **golden-section search** of the scalar δ (bounded [−w_i, 100] ⇒ forcing w≥0), take the single-coordinate update with the lowest SSE; repeat while the relative error improvement >1e-3. signatures.limit caps the nonzero signature count. The prefilter: a signature whose weight in some channel ≥0.2 while the sample share <0.01 is removed. Weights <0.06 are zeroed, the remainder recorded as "unknown".
- **The lesson**: the worst solver design in the field (a per-coordinate one-dimensional optimization inside an R closure) — fit only as a benchmark baseline; its channel-prefilter heuristic is a cheap, takeable pruning idea.

## 4. mmsig

- R 0.0.0.9000, **MIT**, stopped updating 2021-04 (research code).
- The **mixture EM** (`R/em_signatures.R`): α starts randomly; E: `probs = (α⊗sig)/rowSums` (weighted by the mutation frequencies); M: `α = colSums(probs)/sum`; the L1 convergence <1e-5, max 2000 iterations. Then the **backward elimination**: remove one non-forced signature at a time → EM refit → compute the cosine loss; drop the least harmful while the min loss < cos_sim_threshold (0.01). Default `force_include = c("SBS1","SBS5")`.
- The TSB module: MutationalPatterns' `mut_matrix_stranded` + the strand-bias test + the mm1 context set (C[C>T]A etc.) T:S ratio tests; bootstrap CIs; reference-genome validation.
- Adopt: the EM+backward elimination (a fast per-sample fitter), the forced-inclusion lists, the bootstrap CIs.

## 5. signature.tools.lib (Nik-Zainal-Group)

- R ~19,200 LOC, v2.5.2, a custom BSD-3-style (Degasperi), **active** (2026-08).
- The fit (`R/SignatureFitLib.R:24-40`): the default **KLD NMF via `NNLM::nnlm(loss="mkl", method="lee")`** (the mathematics = Brunet KL via Rcpp); alternately NNLS, simulated annealing. **bleedingFilter** (`:424-473`): see the 02 report. The **bootstrap fit** (nboot=200) → a p-value filter (the boots≈0 proportion) → a median filter of the exposures.
- The FitMS hierarchy (`R/signatureFitMultiStepLib.R:68-340`): the organ T1/T2/T3; 4 multi-step modes: constrainedFit (an lpSolve-constrained common fit → correlate the positive residual against the rare signatures), partialNMF, errorReduction (adding a rare signature requires a ≥ min % MAD drop), cossimIncrease; accumulate per depth up to maxRareSigsPerSample + permutation deduplication.
- The per-mutation assignment (`assignMutationsSignatureProbability.R:12-120`): P(the mutation came from signature s) = e_s·sig_s[channel]/Σ_s′ — a plain exposure-weighted channel posterior; an optional "unassigned" pseudo-signature = the positive part of (catalogue−reconstruction).
- The extraction (`SignatureExtractionLib.R`): bootstrap catalogs (nboots=20) × NMF (NNLM::nnmf or NMF::nmf brunet/lee/nsNMF), clustering solutions across ranks.
- **HRDetect** (`HRDetect.R`, `applyHRDetectDavies2017` L916-975): the 6 features `del.mh.prop, SNV3, SV3, SV5, hrd, SNV8`; score = sigmoid(−3.364 + Σ w_i·z(log(x_i+1))); hard-coded means (0.218, 2.096, 1.260, 1.935, 2.195, 4.390), sds (0.090, 3.555, 1.657, 1.483, 0.750, 3.179), weights (2.398, 1.611, 1.153, 0.847, 0.667, 0.091). The feature computation includes the HRD-LOH index (ascatToHRDLOH.R), the MH deletion proportion, the SV3/SV5 counts.
- Indels: `vcfToIndelsClassification.R` + `microhomology.R` — the Nik-Zainal-style del.{repeat-mediated, MH-mediated, other}+insertions. **The Koh 2025 classification was not found.**
- The dependency note: NNLm, nnls, lpSolve, gmp, foreach/doParallel. **No HDP (the downstream reports confirm it).**

## 6. mSigAct + mSigTools + mSigPortal (the Rozen lab)

- **mSigAct** (steverozen/mSigAct, v3.0.3, **GPL-3**, active 2025-09): the presence test (the negative-binomial LLH + nlopt GN_DIRECT→COBYLA + χ²₁); MAPAssignActivity (a sparse per-channel integer assignment, style sampled; not read closely); SparseAssignActivity.
- **mSigTools**: Rozen-Lab/mSigTools, GPL-3, on CRAN (the similarity/association tools, small).
- **mSigPortal**: xtmgah/mSigPortal + CBIIT/nci-webtools-dceg-mSigPortal — GPL-3, very active (2026-09-21). A **web portal + R analysis layer** (Shiny-style modules + the precomputed mSigPortalData), not an algorithm library. Borrow the UX only.
- Adopt: the χ²₁ LRT + the NB likelihood = the gold-standard test of "does the signature really exist", mapping 1:1 to a Rust likelihood kernel; the nlopt global+local two-stage pattern. **The branch note**: the semantics above were verified on the default branch `v3.0.3-branch`; the old `master` branch behaves differently (the multinom default, nbinom.size=5 flat) — replicate against the default branch.

## 7. SUITOR

- R + C (`source/src/source.c`), **GPL-2**; the repo stopped 2022-03 (Bioc-maintained).
- `suitor()`: **a per-entry k-fold CV × rank**; the fold pattern operates on the matrix cells; per rank×seed×fold: an EM fit (`EM_alg` L257, the missing-data likelihood / matrix-variational framework) → the held-out deviance; take the rank of the smallest error; getMV() post-fit. The defaults k.fold equal (the op table partly read).
- Adopt: the held-out-entry deviance as a principled rank selector (cheaper than the bi-cross-validation, complementary to the consensus methods).

## 8. signeR

- R + RcppArmadillo, v2.15.2, **GPL-3**, active.
- `src/gibbs_2.cpp` (426 lines, read in full): a hierarchical Bayesian Poisson NMF ("BN2F"). **The 7 Gibbs blocks**: Z (the per-mutation channel→signature assignment), P (the signatures), E (the exposures), Bp/Be (the regression hyperparameters), Ap/Ae (the Gamma-prior shape/rate) — with a log-posterior evaluation. The posterior samples are summarized into the SignExp class (mean/median/sd + exposure credibilities); the hyperparameters are empirical-Bayesian; the best K via the posterior-likelihood BIC; covariate association tests; it ships its own Shiny flow app.
- Adopt: the posterior exposure variability as an uncertainty product; the Z assignment block is essentially a Bayesian per-mutation allocation (echoing the STL posterior idea).

## 9. SparseSignatures

- R v2.23.0, **Apache-2.0**, Bioc-active (danro9685 = Ramazzotti).
- `R/signatures.discovery.lasso.R`, `nmfLassoCV`: a K × λ_α × λ_β grid; β (the signatures) is initialized by NMF, optionally with background signatures; **alternate updates + L1 sparsification of α (the exposures) and β via the nnlasso package**; the model selection is **bi-cross-validation**: mask 1% of the cells, iterate predict/backfill, MSE+loglik, 50 repetitions. `signatures.assignment.lasso.R` is the sparse refit for given signatures. (The published beta-binomial variant was superseded by the LASSO version of the current Bioc package.)

## 10. pmsignature + decompTumor2Sig + HiLDA

- **pmsignature**: R+C++ (Rcpp), v0.3.0, GPL-3. The Shiraishi feature-vector representation (S4 `possibleFeatures`/`featureVectorList`, sparse (feature, sample, count)); the **C++ EM** (`src/EMalgorithm.cpp`: the E step's per-pattern/sample aux θ, the M step's F and Q, an optional background F0, the `checkBoundary.cpp` boundary checks).
- **decompTumor2Sig** (Bioconductor v2.14.0): `Imports: quadprog(>= 1.5-5)` ⇒ the exposure fit uses **QP** (quadprog::solve.QP), supporting the bidirectional Shiraishi↔Alexandrov/COSMIC conversions.
- **HiLDA** (Bioc v1.27.0, GPL-3): reuses the pmsignature EM lineage + **the two-group hierarchical test**: the exposures as per-site latent binary states, an EM + a beta-binomial/normal prior (`hilda_test.R`: pStates1/2, alpha, beta) detecting the global exposure difference between the two groups.

## 11. CNsignatures + CINSignatureQuantification (markowetzlab)

- **CNsignatures** (a script package, **MIT**, Macintyre; stopped 2023-08) — the precise definition of the Macintyre/Boomgarden pipeline (`main_functions.R`):
  1. `extractCopynumberFeatures` (L68): per segment — **segsize** (bp), **bp10MB** (the breakpoint count in 10Mb bins, `helper_functions.R:98-126`), **osCN** (oscillation = the copy-number alternation count), **bpchrarm** (the segment count by centromere distance), **changepoint** (the adjacent-segment boundary |ΔCN|), **copynumber** (the segment CN).
  2. `fitMixtureModels` (L112): per feature, 2–10 component mixtures, BIC-selected — **Gaussians** for segsize/changepoint/copynumber, **Poissons** for the three count features (flexmix EM).
  3. `generateSampleByComponentMatrix` (L192): each segment's `flexmix::posterior()` membership summed per sample ⇒ the sample×component matrix (the standard Breast cohort's BIC selects ~36 components ⇒ the "36-component mixture").
  4. `generateSignatures` (L39): `NMF::nmf(method="brunet")`; or `quantifySignatures` (L27): a projection onto the precomputed component×signature reference matrix.
- **CINSignatureQuantification** (v1.2.0, an "ASL" license, **very active** 2026-09-08): the dual-feature pipeline (`calculateActivityDrews` = the Drews breakpoint-only features; `calculateActivityMac` = the Macintyre 6 features). The exposure inference = **LCD** (`LinCombDecompSigs.R`): `limSolve::lsei(A=component_by_signature, B=sample_by_component, G=I, H=0)` — least squares with non-negativity inequality constraints, per sample. + de novo extraction, a clinical-prediction module (the platinum response).
- Adopt: keep both feature definitions verbatim (interoperability); the reference-component LCD is the fast path of CN signature quantification (a bounded-variable LS that is trivial in Rust).

## 12. TrackSig

- R + a little Py/Perl, **MIT**, stopped updating 2018 (dormant; the sister TrackSigFreq).
- `src/change_points.R`: the mutations sorted by **CCF** (the VAF corrected by purity/ploidy), binned along the trajectory; **the changepoint = a LASSO over the lower-triangular cumulative design matrix** (`cv.glmnet(alpha=1, lambda.1se)`) — the nonzero coefficients = the changepoints, giving piecewise-constant segments; the per-segment exposure via a **multinomial-mixture EM** (`mixture_of_multinomials.R`, initialized from the total fit); bootstrap stability.
- Adopt: the CCF-ordered exposure-trajectory concept + the sparse piecewise-constant fit (a 1-D fused-lasso that is trivial and fast in Rust).

## 13. SigProfilerPlotting

- Python, a single module of 10,000+ lines, BSD-2-Clause, very active (2026-09-21).
- The composition of the COSMIC-style plots (`sigProfilerPlotting.py`): pure matplotlib; per-channel **hard-coded colour groups** (C>A green, C>T red, C>G black + a yellow-band trick (stacked twin bars), T>A purple, T>C blue, T>G grey; the DBS/ID/SV palettes are in function-local colors lists, e.g. L531, L711); the input matrix is **reindexed to the canonical COSMIC channel order** (`order_input_context`, L272-316) before plotting — the 6-subtype grouping + rotated context labels, a sample-normalized y-axis option, PdfPages multi-sample output, a shipped font; added 2025-26, `sample_portrait.py` (needing the full SBS-6/24/96/384/1536 + DBS-78/312 + ID-83/28/96 grid). The entries: plotSBS L2841, plotID L8475, plotDBS L10457, plotSV L1809, plotCNV L2280. The official R wrapper SigProfilerPlottingR exists.
- **The lesson**: the plots = 90% "the mandated canonical channel order + per-class colours"; if the engine always outputs the canonical order → plotting becomes trivial R/JS work.

## 14. The NMF engines: NNLM and RcppML

- **NNLM** (linxihui/NNLM, v0.4.3, **BSD-2-Clause**, light maintenance 2024-05): RcppArmadillo. Alternate updates + **missing-data support** (`src/update_with_missing.cpp`); the methods scd (the sequential coordinate descent with a quadratic surrogate for the KL loss) and lee (the multiplicative); the losses mse/mkl; the regularization interface alpha/beta vectors = [L1, L2, offset] (incl. the orthogonality via the W·W' term, `src/nnmf.cpp:224-233`); mask support; an NNLS entry. **The engine of signature.tools.lib.**
- **RcppML** (zdebruine/RcppML, v1.0.0, **GPL≥3**, active 2026-04): a full Eigen/OpenMP rewrite (the "FactorNet" header library `inst/include/FactorNet/`): alternate **per-column NNLS** — the coordinate descent by default + a batched post-Cholesky-solve clipping (`primitives/cpu/cholesky_clip.hpp`), fused NNLS, masked_nnls.hpp; the Gram-matrix SYRK (`math/blas.hpp` claims ~1.7×); zero-copy mapping of sparse dgCMatrix, mask_zeros; rank selection by speckled CV (`nmf/rank_cv.hpp`); optional CUDA; streaming .spz. README: for large k it recommends solver="cholesky".
- **Note**: both are GPL — no code may be ported into the licensing kernel; the *ideas* (the CD-NNLS + a Cholesky-clip alternative + the SYRK Gram) are public algorithmic knowledge.
- **The rust-NMF supplement**: `rust/src/lib.rs` (2,228 LOC) + `fcnnls.rs` (535 LOC), the stack = ndarray 0.16 + rayon (no BLAS, no extendr — **it is a Python package**). Benchmarks: pbmc8k rank-10, lee bit-equivalent to R NMF **76×** (1.65 s, 100 iters); hals+NNDSVD 10 iters **~218–280×** (~0.45 s); "NNDSVD init is the magic". **GPL≥2 — reference only.**

## 15. IMAPR

- Perl+Python+shell (the dual-alignment RNA somatic-mutation discovery; detect_variants.pl, filter_variants.pl, the stacking_model.py sklearn ensemble). A **"Commons Clause" license = commercial use forbidden**. Not an R package, stopped 2023-06. The only borrowable point: the RNA-variant reliability filtering is ML-based.

## 16. The Rust–R integration state of play (2026)

- **extendr**: **extendr-api latest 0.9.0** (crates.io, 2026-04-16 unyanked; 0.8.2 the last of the 0.8 line), active, a JOSS paper; a macro framework, optional integrations ndarray/serde/**faer**; the rextendr (CRAN 0.5.0) scaffolding. The matrix conversions go **by copy** at the boundary (the 96×N-grade signature matrices are immaterial; avoid crossing the boundary with genome-grade buffers — keep them on the Rust side, return only small results or write in place into preallocated outputs). The ALTREP support exists but is officially marked unstable (the issues #945/#743 unclosed) — do not depend on it for v1.
- **savvy**: v0.11.0, MIT, active (yutannihilation, a former extendr maintainer); explicit Sexp wrapping, no implicit conversions, a minimal API; the production users r-polars and SedonaDB. The documentation is explicit: pick extendr for ergonomics, savvy for explicitness.
- **r-polars** (pola-rs/r-polars, active 2026-09-23, **not on CRAN — a design choice, not a rejection**): the `src/rust/` workspace (Cargo.toml + lock + rust-toolchain.toml); at install time the `configure` picks one of two: (a) compile the Rust library, (b) **download the precompiled static `libr_polars.a` from the GitHub releases + a SHA256 check** (`tools/prep-lib.R`, `tools/lib-sums.tsv`; on r-universe it automatically picks b). **The CRAN policy forbids networking at install time** → CRAN is out; the distribution goes via GitHub releases + r-universe + Posit binaries. The cleanup strips the Makevars/toolchain files from the tarball.
- **CRAN + vendored Rust is proven workable**: **string2path** (on CRAN, updated 2026) packages all the crates as `src/rust/vendor.tar.xz`, unpacking at install time via `Makevars.in` + `src/cargo_vendor_config.toml` (replace-with vendored-sources) + a cleanup script. ⇒ **CRAN does not allow cargo networking; you must cargo vendor and ship the tarball with the package; the smaller the dependencies the better.**
- **faer** (sarah-quinones/faer-rs, MIT, 2.5k stars, active): a full-featured Rust linalg; the official benchmarks are charts (no numbers extractable), positioned as on par with the optimized BLAS/Eigen or better; extendr has an official faer integration. **For this project's real load (mini NMF/NNLS with k≤101), self-written closed-form/CD kernels are more relevant than a full BLAS; faer's vendor footprint is huge and needs weighing.**
- The Rust-genomics R precedents: roxigraph (cboettig, extendr+Oxigraph, on CRAN), bixverse (GregorLueg). The templates: r-polars, string2path.

## 17. The quick checks (existence + one sentence)

- **SigProfilerSingleSample** (SigProfilerSuite): the per-sample attribution against a known signature set + the per-mutation-type probabilities; depends on SPMG/plotting; stopped 2025-01; **the repo has no LICENSE file** (a reuse warning).
- **SigProfilerSimulation**: **does not exist**.
- **SigMA** (parklab): the likelihood fit for low-statistic SNV data (HRD/SBS3); exists, largely dormant.
- "MSA MATLAB/loci2sig", "lightsvd": not found.
- signature.tools.lib has no HDP; the "HDP-based CN signature tool" could not be located (the cpn-sigs-style names missed) — honestly marked: unaudited.

## 18. The final synthesis table

| The tool | The algorithm | The language | The license | The engine | The reuse value for msuiter |
|---|---|---|---|---|---|
| SigProfilerMatrixGenerator | the SBS/DBS/ID/CN48/SV32 catalog construction | Python | BSD-2 | pure-Python loops | **critical**: the channel semantics to replicate bit-for-bit |
| MutationalPatterns | the KL-NMF, the lsqnonneg fit, the strict refit | R | MIT | NMF/pracma/BSgenome | the API shape + the strict-refit concept |
| deconstructSigs | the greedy golden-section coordinate descent | R | GPL≥2 | none | the cautionary baseline; the channel-prefilter idea |
| mmsig | the mixture EM + the backward elimination | R | MIT | pure R | the EM fitter + the forced-inclusion lists |
| signature.tools.lib | the KL fit + bootstrap + bleedingFilter + FitMS + HRDetect | R | BSD-style | NNLM/nnls/lpSolve | the fitting-pipeline semantics, the per-mutation posteriors |
| mSigAct | the NB likelihood LRT (χ²₁), the MAP assignment | R | GPL-3 | nlopt | the test mathematics is portable |
| SUITOR | the k-fold entry CV rank selection | R+C | GPL-2 | custom C | the rank-selection method |
| signeR | the Gibbs BN2F | R+Rcpp | GPL-3 | Armadillo | the posterior-uncertainty concept |
| SparseSignatures | the L1 alternate updates + the cell-mask CV | R | Apache-2.0 | NMF/nnlasso | the CV rank/λ selection |
| pmsignature / decompTumor2Sig / HiLDA | the Shiraishi EM / QP / the LDA group test | R+Rcpp | GPL-3 | custom C++ | the representation + the QP idea |
| CNsignatures / CINSignatureQuantification | the 6 CN features → the GMM/Poisson mixtures(BIC) → NMF/LCD | R | MIT / ASL | flexmix/limSolve | the exact CN-feature definitions |
| trackSig | the CCF trajectory + the LASSO changepoints + the multinomial EM | R/Py | MIT | glmnet | the trajectory concept |
| SigProfilerPlotting | the canonical order + per-class-colour plotting | Python | BSD-2 | matplotlib | the plotting specification |
| NNLM | the KL/MSE NNMF (scd/lee) + regularization + missing | R+Rcpp | BSD-2 | Armadillo | the KL-NMF reference semantics |
| RcppML | the alternate CD/Cholesky-clip NNLS, CV, GPU | R+Rcpp | GPL≥3 | Eigen+OMP+CUDA | the performance ideas only (GPL) |
| rust-NMF | the bit-equivalent Lee/HALS + NNDSVD, fcnnls | Rust(Py pkg) | GPL≥2 | ndarray+rayon | **the NNDSVD conclusion; the benchmarking target** |

## 19. The algorithms that must be replicated bit-for-bit (the bit-compatibility targets)

1. **The SPMG INDEL 83-channel classification** — the repeat walk, the longest-MH match (the forward-priority tie rule), the key1/key3/key4 caps, the 1bp C/T rule, the Q-strand concordant-cluster rule, the `limited_indel` variant. The source: `MutationMatrixGenerator.py:1169-2100` (+1659-1736, 1846-1857).
2. **The SPMG SBS direction + the 6144/1536 hierarchy** — the pentanucleotide fetch, the purine flip, the pyrimidine-centred index. `MutationMatrixGenerator.py:778-917`; `SigProfilerMatrixGeneratorFunc.py:1004-1024`.
3. **The SPMG DBS** — the adjacent-SNV detection, the dinuc_tsb_ref normalization (incl. the Q-flag flip), the 78/186/1248/150/2400/2976 folding (incl. the B split). `:484-694`, `:3800-4057`.
4. **The SPMG CN48 + SV32** — the feature lists, the per-caller LOH, the per-segment count of 1; the SV strand→class mapping, the size bins, the kat-region clustering (exactPcf kmin=10). `CNVMatrixGenerator.py`, `SVMatrixGenerator.py:797-1252`.
5. **The HRDetect Davies-2017 logistic** — the exact coefficients listed above. `HRDetect.py:916-975`.
6. **The Macintyre/Drews CN features + the 36-component posterior summation** — `CNsignatures/helper_functions.R`, `main_functions.R`; the CINsig `*Mac.R`/`*Drews.R`.
7. **The mSigAct NB LRT** — the 2ΔlogLH ~ χ²₁ + the GN_DIRECT+COBYLA two-stage fit. `SignaturePresenceTest1.R`.
8. **The NNLM mkl/lee KL-NMF update semantics** — reproducing the signature.tools.lib-compatible fit (and the bit-equivalent semantics of the R-NMF brunet).

## 20. The ideas worth adopting / the anti-patterns

**Adopt**: the pre-encoded genome+annotation byte arrays (SPMG); the "Q" ambiguous-strand channel across all classes; the matrix hierarchy of a main index + slice folding, count once emit many matrices; the exposure-sparsification trio (the STL bleedingFilter, the mmsig/MP backward elimination with a cosine-delta stop, the best_subset for small signature libraries); the Bayesian per-mutation allocation + the unassigned pseudo-signature; the bootstrap p values + the median-filtered exposures; the NNDSVD default initialization + the few-iteration HALS mode; the SUITOR-style held-out-entry CV for the rank; the LRT presence test (mSigAct); the forced-inclusion lists (mmsig); the CRAN-policy cargo vendor (the string2path template) + the precompiled static libraries (the r-polars template); extendr v0.8.2; keep the genome buffers on the Rust side, the engines uniformly output the canonical order at the boundary (the SPP lesson).

**Anti-patterns**: interpreter per-byte loops over whole chromosomes (SPMG is a warning, not a model); R loops of per-sample pracma::lsqnonneg (MP); the golden-section coordinate descent (deconstructSigs); unregularized over-fitting over a 30-signature catalog (the reason strict/LCD/EM-elimination exist); per-sample whole-genome-object round-trips through BSgenome (MP) — one Rust pass should emit all the matrices; window-capped repeat/MH counts silently deviating from the SPMG keys (the MP indel — a bounded approximation breaks comparability); CRAN packages downloading over the network at install time (r-polars's reason for opting out); GPL engine code leaking into the licensing kernel (RcppML/rust-NMF); the engine output forking from the plotting channel order — normalize once at the boundary.
