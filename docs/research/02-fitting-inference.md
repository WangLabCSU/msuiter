# Research report 02: fitting/attribution, exposure statistical inference and post-processing analysis
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-27. Method annotation: [V] = verified by cloning the source to /tmp/fitresearch or reading the full text; [U] = not fully verified. Repositories read closely: parklab/MuSiCal, steverozen/mSigAct, Rozen-Lab/mSigTools, AlexandrovLab/SigProfilerAssignment, Nik-Zainal-Group/signature.tools.lib, kgori/sigfit, lrgr/signature-estimation-py, evenrus/mmsig. Papers read closely: bbaf042 (PMC11798676), MuSiCal (PMC10937379), Medo 2024 (PMC11530434), sigLASSO (PMC7368050).

---

## 1. The exact algorithmic form of each tool

### 1.1 MuSiCal — likelihood-sparse NNLS [V]

**Terminology correction**: the code and the paper contain **no "MWPruning", "MDL penalty" or "catalog denoising"** (grep: 0 hits). What actually exists is:
- **LTH = the likelihood threshold ϵ** (the paper's real term), default 0.001, applied on the **per-mutation** (per-trial) multinomial log-likelihood scale (normalized by Σx, independent of the total counts).
- "MW" = the **Mann–Whitney U test**: used in (a) wrappedMVNMF to select λ̃; (b) K selection.
- "Denoising" ≈ the **flat-signature cleanup after matching** (`_clean_W_s`) + preprocessing (cohort stratification, Gini outlier removal).

**The core refit algorithm (`nnls_likelihood_bidirectional`, the default)** (`musical/nnls_sparse.py`):
1. The full-catalog NNLS initial solution; the support set R⁰ = {j: h_j>0}.
2. **The backward step**: for each j∈R, re-solve the NNLS on R∖{j}; compute the per-mutation multinomial logL: `L = Σᵢ xᵢ·log(pᵢ)/Σx` (p = W_R h / Σ(W_R h), clipped at 1e-16); Δⱼ = L_current − L_(−j); remove the smallest Δ if Δ < ϵ_backward; otherwise stop.
3. **The forward step**: symmetrically add the one that maximizes Δ and exceeds ϵ_forward.
4. Alternate backward/forward until both stop (max_iter 1000; an anti-deadlock guard).
5. Finally re-solve the NNLS on the surviving support. The connected signatures holding preserved signatures are re-added before the final NNLS.
- The ϵ-grid variant: {0} ∪ geomspace(1e-4, 5, 50) (SparseNNLSGrid).
- **The relaxed variant**: leaves one re-solve using the **whole** catalog except the deleted one (testing redundancy against the full catalog) — the relaxed function sits at `nnls_sparse.py:434` (:410/:461 are the LOO blocks; the line numbers drift with upstream, navigation only).
- The other methods: thresh_naive/thresh (the exposure-share threshold iteration, default 0.05), cosine_bidirectional (ϵ=0.01).
- **The TMB recalibration** (the N option): scale up to N total mutations, run the sparse search, then re-solve on the original counts.
- **Matching** (`refit.py:match`): the same SparseNNLS machinery decomposes each de novo signature into a sparse non-negative mixture of catalog signatures; the old-style `match_signature_to_catalog`: cosine ≥ 0.99 accepts a single signature, otherwise single/double/triple-signature NNLS (a minimum coefficient of 0.1).
- **The flat-signature cleanup** (`_clean_W_s`, defaults min_sum_0p01=0.15, min_sig_contrib_ratio=0.25): a background-fit verdict → re-solve.
- **The connected signatures** (utils.py SIGS_ASSOCIATED): [SBS2,13], [SBS17a,17b], [SBS10a,b,c,d,28]. **Note: no SBS7a-d** (unlike SPA! see §7).
- **The de novo side**: mvNMF = the KL error + λ̃·log₁₀det(WᵀW+δI), δ=1; `wrappedMVNMF` sweeps the λ̃ grid (1e-10→2.0, 32 points), picking the **largest** λ̃ whose "per-sample error distribution is not significantly worse than the smallest λ̃" (Mann-Whitney U, alternative='less', p≤0.05; or a 90th-percentile tail test); K selection: the replicate filter (MW + the tail test) → the cosine-average linkage clustering → the stability (mean silhouette ≥0.8, minimum ≥0.2, ≥20% of replicates surviving) → the adjacent-K significance test → algorithm1 (the largest K in stable∩significant) / algorithm2 (the smallest K in stable∩insignificant) / consistency (the gap statistic).
- **The in-silico calibration**: simulate X multinomially from (W_s,H_s), re-run the same pipeline and compare the cosine, used to select LTH.

### 1.2 mSigAct — the exposure likelihood-ratio test [V]

Source: `R/SignaturePresenceTest1.R`, `R/OptimizeExposure.R`, `R/DefaultManyOpts.R`, `R/MAPAssignActivity1.R`, `R/ForwardSearch.R`, `R/LLHSpectrum*.R`.

- **The likelihood**: multinomial or **negative binomial** (the default): `Σᵢ dnbinom(xᵢ; mu=reconᵢ, size=nbinom.size)`; nbinom.size = 8 (SBS96) / 50 (DBS78) / 100 (ID83). The exposure is solved by **nloptr**: a global NLOPT_GN_DIRECT (maxeval 1e4) + a local NLOPT_COBYLA; the final value is rescaled to Σx.
- **The signature-presence test**: the full-signature fit vs the fit minus the target signature; the statistic = 2(ll_with − ll_without), **p = the upper tail of χ²₁**. H0: "the spectrum can be reasonably reconstructed without the target signature". **No Monte Carlo** (the current behavior is the asymptotic χ²).
- **MAPAssignActivity** (the backward combinatorial search): start from the NNLS best support (those with exposure ≥0.5); enumerate removal subsets for df=1..max.level(5) (≤1000), refit after each removal and perform the df-degrees-of-freedom LRT; a removal is allowed when p ≥ p.thresh (default `0.001/(4·n_sigs)`, Bonferroni-style); necessary subsets are recorded, supersets skipped. MAP = ll + log P(M), with P(M) a per-cancer-type signature-prevalence prior.
- **PASA** (Jiang 2024's new algorithm = ForwardSearch + the presence test):
  1. the per-signature presence test (the multinomial LRT, χ²₁); those with p ≥ 0.1 are dropped from the candidate set (order-independent);
  2. **ForwardSearch**: start from the empty set; each step fit candidates∪selected for every candidate and perform the LRT against the full model (df = n_full − n_selected); **add the one with the largest p**; stop when max p > p.thresh; otherwise keep the full-signature fit. Step 1 is multinomial, step 2 negative binomial.
- The guardrail: by default it drops samples with <100 SBS / <25 DBS-ID.

### 1.3 The PASA benchmark results (bbaf042) [V]

- 13 tools, 2700 synthetic samples (9 PCAWG cancer types × SBS/DBS/ID). The composite score = (1 − the scaled Manhattan distance) + precision + recall.
- **SBS: PASA 2.64 ≈ MuSiCal 2.62 (no significant difference) > FitMS 2.57 > the rest; DBS: PASA 2.78 > FitMS 2.74 ≫ MuSiCal 2.57 (SPA has high precision but a significantly lower recall); ID: PASA 2.81 > FitMS 2.73 ≫ MuSiCal 2.68**. From the F1 / recall+specificity angle: MuSiCal first on SBS, PASA second; PASA first on DBS/ID. The ranking varies sharply by cancer type; skin melanoma is the hardest (the common false negatives are SBS1/SBS5, not the SBS7a/b confusion).
- The non-sparse NNLS family (SignatureEstimation/SigsPack/mutSignatures): recall 0.943 but precision < 0.615. The uniform-proportion pruning (the deconstructSigs style) causes false negatives.
- **The key conceptual result**: in 99/100 synthetic gastric-cancer spectra there exist "wrong attributions that reconstruct better than the truth" (a median of 11,189 distinct attributions with cosine>0.969 per spectrum); the reconstruction-similarity metrics carry **no information**, evaluation must use precision/recall.
- CPU: MSA slow by >5 orders of magnitude; PASA >4; MuSiCal ~10× over PASA.
- The catalog-update recommendation (SBS40→40a/b/c): with no tissue-distribution prior, **keep the parent signature SBS40 in the fit** [V — the original quotation].

### 1.4 The incremental facts of SigProfilerAssignment [V]

- The new-version defaults: `cosmic_version=3.6`, `add_background_signatures=True` (**forcing SBS1+SBS5 into the catalog** — a direct response to the Medo flat-signature-underestimation finding), `exclude_signature_subgroups` (the etiology-based exclusion lists: MMR/POL/HR/BER/chemo/immuno/APOBEC/tobacco/UV/AA/colibactin/**artifact**(SBS27,43,45–60,95)/lymphoid, hard-coded in `decomposition.py:376-410`).
- `collapse_to_SBS96=True`: the 1536/288-channel de novo signatures are folded to 96 **only in the decomposition step**.
- `new_signature_thresh_hold=0.8`: a de novo refit cosine < 0.8 counts as a new signature.
- `probabilities(W,H)` (`decompose_subroutines.py:1694`): P(signature k produced the mutation in channel i) = W[i,k]H[k,s]/Σ_k W[i,k]H[k,s] — the proportional-allocation "responsibility", **not a Bayesian posterior**, ignoring the mutation context outside the channel.

### 1.5 signature.tools.lib FitMS [V]

- The two-layer fit: the common layer (the organ's RefSig T1/T2/T3; the default **KLD objective**, via the `nnlm` package; optionally NNLS / simulated annealing; the bleeding filter; bootstrap default nboot=200; the exposure filter fixedThreshold 5% or Gini scaling; the p value = the empirical P(exposure<threshold)) + **the FitMS multi-step**: search the rare signatures against the residual (the T0–T4 green QC layers; `multiStepMode="errorReduction"` requires a MAD error reduction ≥ minErrorReductionPerc; minCosSimRareSig=0.8; maxRareSigsPerSample=1 by default). It does not support replottting / the COSMIC catalog (RefSig only).
- **bleedingFilter** (`SignatureFitLib.R:424-473`): iteratively move an entire signature's exposures onto another signature, accepting the move that best preserves the cosine with a loss ≤ α — a de facto exposure-sparsification trick.
- The per-mutation assignment: `assignSignatureProbabilityToMutations` = the exposure-weighted channel posterior + an optional "unassigned" pseudo-signature (the positive residual).
- `sampleStrandBias`: the transcriptional (UTS/TS) and replicational (leading/lagging) strand biases, with/without the trinucleotide context.

### 1.6 sigfit [V]

- Stan: family ∈ {multinomial, Poisson, negbin, normal}; the exposure simplex + a Dirichlet(κ) prior; **expected_counts = activities × signatures ⊙ opportunities** (the opportunities inside the likelihood, not a catalog transform); HPD intervals.
- `convert_signatures`: sig ← (sig/opp_from)⊙opp_to then renormalize. **The CI zeroing rule**: a 95% CI lower bound < 0.01 ⇒ set to 0 (Medo proved it significantly helpful).

### 1.7 sigLASSO [V]

Li, Crawford & Gerstein, Nat Commun 11:3575 (2020). The generative model: L = Multinomial(m|p) × Gaussian(p|Sw, σ²) × Π_k exp(−λc_k w_k) (a Laplace prior + the per-signature penalty vector c encoding the strength of the prior knowledge); explicit support for unassigned mutations; cannot do DBS/ID (bbaf042 [V]).

### 1.8 The QP family [V]

`signature-estimation-py` and `mSigTools::optimize_exposure_QP` share the same form: M and P normalized to sum-1; solve min eᵀ(PᵀP)e − (MᵀP)ᵀe s.t. Σe=1, e≥0 (quadprog, Goldfarb-Idnani).
**The analysis**: when P's columns all sum to 1, the LS on the fractions ≡ the NNLS on the raw counts (differing by the constant 1/N²); **the only substantive difference is the Σe=1 equality constraint** — when the catalog cannot explain part of the spectrum the two diverge (the NNLS shrinks the total exposure; the QP must spend the full weight of 1). Every implementation uses quadprog; **no osqp usage** [V grep].

## 2. The uncertainty-quantification landscape

| The method | The tool | The mechanism | The remarks |
|---|---|---|---|
| Multinomial/parametric bootstrap | sigminer, SigsPack, mmsig, signature.tools.lib(nboot=200), MSA, StarSignDNA(200 reps) | resample the mutations → refit → percentile CIs; STL turns it into empirical p values; StarSignDNA adds a t test | the cheapest defensible; captures sampling noise only |
| Bayesian posterior | sigfit (HMC, 4 likelihoods), signeR (MCMC) | the full exposure posterior → HPD/credible intervals | the only natively calibrated intervals; the sigfit CI zeroing proved beneficial per Medo |
| Analytic (the Fisher information / the Δ method) | **none** | I = N·Σᵢ(wᵢ)⁻¹∇wᵢ∇wᵢᵀ | **zero PubMed hits [V] — greenfield** |
| Profile likelihood | none | — | — |
| LRT | mSigAct/PASA (χ²₁ + the BH q + the AIC weights) | tests, not intervals | the only production-grade test framework; the boundary's asymptotic χ²₁ is correct |
| Simulation-calibrated thresholds | MSA; MuSiCal in-silico calibration | empirical FPR calibration on synthetic replicates | costly |

**The statistical principles**: given the catalog and Σh=N the counts are multinomial; the exposures are **compositional data** (on the simplex) → (i) the intervals should respect the simplex geometry (the Dirichlet family, log-ratios); (ii) "is S active" is a **model-selection/LRT problem** (the boundary of the parameter space — χ²₁ is exactly the boundary's asymptotic); (iii) the bootstrap should resample the mutations (multinomial), not the channels. **The gaps [V: the literature is missing]**: no joint CIs; no combination of "LRT selection + a bootstrap CI conditional on the support"; no CI coverage validation (Medo raises this open question explicitly). **The greenfield opportunity**: analytic/bootstrap CIs conditional on the support + a calibrated LRT.

## 3. The loss-function theory

The generative model: each mutation is drawn independently, P(channel i) = (We)ᵢ/Σ(We).
- **The multinomial MLE (KL)**: the correct MLE of the channel probabilities at a fixed N. The Poisson (λ=We) is equivalent to the multinomial once profiled over the total counts — the differences are only (i) whether the total carries information (it does not for W on the simplex) (ii) over-dispersion modeling (negbin trades in robustness — mSigAct's default).
- **The raw-count Frobenius/LS**: the MLE only under homoscedastic Gaussians (unreasonable); weights the high-count channels; ignores the heteroscedasticity Var(xᵢ)≈N·wᵢ.
- **The normalized-fraction Frobenius (QP)**: the same minimization set as the raw-count NNLS (§1.8).
- **KL vs LS behavior**: KL weights by 1/wᵢ (the relative error) → the rare high-information channels matter more. **MuSiCal ED Fig 5b/c [V]: with 1000 SBS3 + a little SBS5, the cosine can only resolve it once SBS5≥9%, while the multinomial LL is still significant at 2% (20 SNVs); the cosine stepwise refit identifies the correct active set with no threshold needed.**
- **cosine**: scale-invariant, with no statistical foundation on counts — use it only for reporting / matching thresholds.
- **The L1-penalized Poisson**: sigLASSO, StarSignDNA — the MAP under a Laplace prior; sparsity via shrinkage rather than search. Medo: at small N, sigLASSO is among the best at suppressing false positives.
- **The empirical evidence**: no paper proves the loss's optimality; at the benchmark level the three likelihood-based methods (PASA/MuSiCal/sigLASSO) hold the top places, the LS/NNLS family trails, and both benchmark papers list likelihood usage as a difference factor [V original quotations].

## 4. Opportunity normalization, exome↔genome, panels, low counts

- **The opportunity mechanism [V]**: sigfit puts the opportunities inside the likelihood (per-sample support); SPA ships the COSMIC `*_exome` catalog files (per build); MuSiCal has no exome conversion (only the TMB recalibration); sigminer's sig_convert is a sigfit port.
- **Panels/small counts**: the state of the art is weak. **SigMA** (Gulhan, Nat Genet 2019;51:912–919 [V abstract]) is the only classic panel method: likelihood measures + an ML classifier, deciding HRD/SBS3 from dozens of targeted-panel mutations. bbaf042 drops <100 SBS; mSigAct by default drops <100 SBS / <25 DBS-ID; MuSiCal uses ≥100 IDs + cancer-type thresholds; the common cutoffs are ≥50 (the SigProfiler docs) or ≥200. **Medo proved no universal threshold is meaningful** (the difficulty is signature-specific — the Shannon flatness; the error ~1/√N). "SigProfilerPanel" could not be confirmed to exist (zero hits in the GitHub/PyPI registries, the empirical search of 2026-09-28; the AlexandrovLab organization has no such repository, PyPI has no such package). **The second greenfield: a principled general low-count fitter (negbin/multinomial LRT + a panel-opportunity catalog + a calibrated LRT) does not exist.**
- **The TMB dependence**: Medo Fig 1c [V]: as N drops the error and the false-positive weight rise steeply; **the flat signatures (SBS5, SBS40) are systematically underestimated at every N** (what Medo explicitly lists is SBS5/40; SBS1 is an "easy" signature, not in this list); past >10,000 mutations most tools avoid false positives; on the real PCAWG 50k+ samples the top tools still widely disagree.

## 5. Post-fitting analyses

(a) **The per-mutation assignment**: SPA's probabilities (proportional allocation, channel-level) + the VCF join; signature.tools.lib is the equivalent + an optional "unassigned" pseudo-signature (the positive residual). **Nobody conditions on genomic features (replication timing, expression) or propagates the exposure uncertainty** — a differentiator we can build.
(b) **The post-fit TSB**: no tool natively computes a per-signature TSB — mmsig is sample-level (a Poisson per context + the MM1/SBS35 pooling) [V]; STL's sampleStrandBias is sample-level [V]; SPA's 192/288 catalogs + the per-mutation probabilities make it derivable but it does not output the test [V by absence]. The design: the per-mutation allocation probabilities × the strand annotation → a per-signature Poisson/binomial UTS-vs-TS test + uncertainty propagation. The replication-timing analysis lives in SigProfilerTopography (not read closely [U]).
(c) **Clonal timing/dynamics**: TrackSig (Rubanova 2020, doi:10.1038/s41467-020-14352-7; the CCF-axis changepoint + the per-segment exposure); CloneSig (Nat Commun 2021, doi:10.1038/s41467-021-24992-y, joint with ITH); TRACERx evolution (Nature 2023 doi:10.1038/s41586-023-05783-5) as an application exemplar. Clock timing (the SBS1 vs SBS5 ratio vs age) appears in applications; "MutationalChronology/mrtSig" zero hits [V — does not exist]. Supervised covariate signatures: Afsari eLife 2021 SuperSigs (PMID 33491650); **nobody formalized a post-hoc "exposure ~ covariates" regression framework**.
(d) **Between-group comparison**: the practice is casual — sigminer is heuristic; Medo uses Wilcoxon; cohort-level tests exist only in the Rozen lab's mSigBG (the background-mutation model; not read closely [U]). **There is no CoDA/log-ratio treatment anywhere [V search] — the third greenfield**.
(e) **Survival/clinical association**: purely practical with no standard (Cox/logistic on the exposures); nobody adjusts for the compositional constraint or the fitting uncertainty.

## 6. Catalogs, folding, thresholds

- COSMIC is currently v3.6 (SPA has already defaulted to 3.6). **The release-number correspondence was verified (the official Sanger signatures site, 2026-09-28): v3.6 was released with COSMIC v104 (2026-05), the previous v3.5 with v103 (2025-11); v3 first appeared with v89 (2013-05).**
- **The folding/linkage handling diverges**: the SPA groups [SBS2+13, SBS7a-d, **SBS10a+b**, SBS17a+b] vs **MuSiCal [SBS2,13], [SBS17a,17b], [SBS10a,b,c,d,28] (no SBS7 group) [V source]** — note SPA only groups **SBS10a/SBS10b** together, while MuSiCal groups **all of SBS10a–d with SBS28**; the two differ in grouping granularity over the POLE subtypes; a design decision is needed (the MuSiCal list is PMS2/POLE-driven; SPA adds the UV subtypes).
- The SPA etiology exclusion lists include artifacts (SBS27,43,45–60,95; DBS14) — a de facto "curated catalog" API.
- The similarity thresholds: MuSiCal matching accepts cosine ≥ 0.99; SPA judges new signatures below 0.8; FitMS rare candidates ≥ 0.8; **there is no community standard for the RSS/reconstruction thresholds** — bbaf042 proved cosine>0.969 still tolerates thousands of attributions; reporting the RSS alone carries no information.
- The zeroing conventions (all per Medo [V]): the sigfit CI lower bound<0.01; deconstructSigs <0.06; the COSMIC family <10 mutations; MuSiCal LTH; the SPA add/remove penalties + the forced SBS1/5 background.

## 7. The requirement mapping for our suite

1. **The fitting engine (Rust)**: (a) the NNLS (Lawson-Hanson/FNNLS) + the Σe=1 QP (reusing the quadprog semantics); (b) the multinomial and negbin likelihood kernels (vectorized, SIMD); (c) a stepwise backward/forward sparse solver, **with two selectable picking modes: the per-mutation LL threshold ϵ (the MuSiCal style) and χ²-LRT pruning (the PASA style)**; (d) the greedy subset-removal MAP + prevalence priors (the expert mode).
2. **The inference layer (new, differentiating)**: the per-signature LRT p/q values + multinomial bootstrap CIs conditional on the support + an optional HMC posterior; **CI coverage tests on synthetic ground truth (nobody has done it)**; compositional-data outputs + an honest simplex geometry.
3. **The catalogs**: versioned (v3.2/3.4/3.5/3.6) × (genome/exome opportunity normalization) dual faces; etiology/artifact subgroup labels (the SPA style); the parent/child signature relations and policies (fit the parent by default, split on demand); the connected groups catalog-configurable.
4. **The opportunities**: first-citizen opportunity vectors (genome, exome, any panel BED) used inside the likelihood (the sigfit style) + catalog-conversion tools; the panel mode = a SigMA-style low-count classifier + a calibrated LRT (<100 mutations).
5. **The post-processing**: the per-mutation allocation probabilities (channel-level + context annotations) + an optional unassigned; the per-signature TSB/RTT tests derived from the assignments; the exposure → between-group tests with uncertainty (a Wilcoxon baseline + the log-ratio/CoDA tests in design) + regressions/survival aids that propagate the fitting uncertainty.

## 8. The key citations

1. Jin et al. MuSiCal. Nat Genet 56:541–552 (2024) doi:10.1038/s41588-024-01659-0
2. Jiang, Wu & Rozen. The PASA benchmark. Brief Bioinform 26(1):bbaf042 (2025) doi:10.1093/bib/bbaf042
3. Medo, Ng & Medová. Nat Commun 15:9467 (2024) doi:10.1038/s41467-024-53711-6 (PMID 39487150; note: do not use -53574-6, that DOI does not exist)
4. Li, Crawford & Gerstein. sigLASSO. Nat Commun 11:3575 (2020) doi:10.1038/s41467-020-17388-x
5. Gulhan et al. SigMA. Nat Genet 51:912–919 (2019) doi:10.1038/s41588-019-0390-2
6. Gori & Baez-Ortega. sigfit. bioRxiv 372896 (2018/2020)
7. Rosenthal deconstructSigs (2019); Blokzijl MutationalPatterns (2018); Letouzé YAPSA; Huang SignatureEstimation QP; Senkin MSA BMC Bioinform 22:540 (2021); Rustad mmsig (2021); Degasperi Science 2022
8. Rubanova TrackSig (2020); CloneSig (2021); TRACERx (2023); Afsari SuperSigs eLife 10:e61082 (2021)
- The sources: github.com/parklab/MuSiCal, steverozen/mSigAct, Rozen-Lab/mSigTools, AlexandrovLab/SigProfilerAssignment, Nik-Zainal-Group/signature.tools.lib, kgori/sigfit, lrgr/signature-estimation-py, evenrus/mmsig, gersteinlab/siglasso

**Explicitly unverified / non-existent**: MuSiCal's "MWPruning/MDL penalty/catalog denoising" (does not exist); the mSigAct "Monte Carlo p values" (the current behavior is the χ² LRT); "SigProfilerPanel" (not found); "mrtSig/MutationalChronology" (not found); the COSMIC version-release correspondence (it may drift); the "Wu 2022 loss theory" reference (unidentified); the internals of SigProfilerTopography/mSigBG (not read closely); osqp usage (none found).
