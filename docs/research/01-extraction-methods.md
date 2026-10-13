# Research report 01: the de novo signature-extraction method panorama and the NMF compute engines
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-27. Annotation convention: [V] = verified by reading the source/full text; [search] = abstract-level verification only; [unverified] = could not be confirmed, keep in doubt.

---

## 1. Cornet / Sonata — the single most important finding (the user-designated biorxiv paper)

**The paper**: Jin H, Geiger B, Glodzik D, Gulhan DC, Park PJ. "Correlation-aware discovery of co-occurring mutational signatures in cancer." bioRxiv 2026.09.14.751548 (posted 2026-09-21, the original MuSiCal team). **DOI `10.64898/2026.09.14.751548`** (bioRxiv switched to the `10.64898` prefix from 2026; the old `10.1101/...` does not resolve). CC-BY-NC, version 1. **[V — the Europe PMC metadata + the full text (via a jina.ai mirror to sidestep the bioRxiv 403)]**

**The software**: `parklab/Sonata`, Python, **MIT license**, pip name `sonata-tools`, AnnData native. It carries three models: `so.models.NMF` (the KL-NMF), `so.models.MvNMF` (the minimum-volume NMF), `so.models.Cornet`. Integrated into a MuSiCal-style de novo pipeline (bootstrap → fit → filter → cluster → K selection). **[V — the source]**

### 1.1 The exact model form (source `src/sonata/models/cornet.py`, `_utils_cornet.py`)

- The generative model: `X_vd ~ Poisson((WH)_vd)`, the signatures being W's columns (column normalization on the probability simplex), the key innovation — **the exposure is parameterized as a low-rank bilinear form in log space**:

  `h_kd = exp(α_k + β_d + l_k · u_d)`

  where `α_k` is the signature bias (K-dim), `β_d` the sample bias (D-dim, absorbing the sequencing depth), `l_k ∈ R^m` the signature embedding, `u_d ∈ R^m` the sample embedding, `m ≤ K` (default m=K).
- The embedding's Gaussian prior `N(0, σ²I)` with σ² **adaptively learned**.
- The objective (called the ELBO in the code): `Σ_vd [x_vd log((WH)_vd) − (WH)_vd]` (the Poisson KL) `− Σ_k‖l_k‖²/(2σ²) − Σ_d‖u_d‖²/(2σ²) − (K+D)m·log(2πσ²)`.
- The lineage: **Paisley, Blei & Jordan (2014) correlated NMF** (the stochastic variational inference) → Cornet replaces it with a deterministic MAP coordinate ascent. The docstring cites it explicitly. **[V]**

### 1.2 The optimization algorithm (the exact update order of `_update_parameters`)

Each iteration:
1. The sample bias (in closed form): `β_d = log Σ_v x_vd − log Σ_k exp(α_k + l_k·u_d)` (the log-sum-exp softmax, enforcing Σ_k h_kd = the sample's total counts).
2. Recompute the exposure `h = exp(α + β + L Uᵀ)` (numba JIT).
3. **The auxiliary sufficient statistic** (the KL-MU responsibility trick, avoiding materialising a 3-dim tensor): `aux_kd = Σ_v x_vd·p_vkd`, where `p_vkd = w_kv h_kd/(WH)_vd`, i.e. `aux = Hᵀ ⊙ (W (V ⊘ WH))ᵀ`.
4. The signature bias (in closed form): `α_k = log Σ_d aux_kd − log Σ_d exp(β_d + l_k·u_d)`.
5. The embeddings: for each `l_k` (with U fixed) and `u_d` (with L fixed) solve the **concave subproblem** `max_l Σ_d aux_kd(l·u_d) − Σ_d exp(α_k+β_d+l·u_d) − ‖l‖²/(2σ²)` — the scipy Newton-CG with analytic gradient and Hessian (the Hessian only m×m); the sample embedding maxiter=3.
6. The variance (in closed form): `σ² = mean(concat(L,U)²)` (clipped ε).
7. The signatures: after the standard KL multiplicative update, column-normalize.

The defaults: the NNDSVD initialisation, min_iterations=500, max_iterations=10000, tol=1e-7, convergence checked every 10 iterations. **[V]**

### 1.3 The paper's claims [V — the full text checked sentence by sentence]

- The synthetic benchmark (1000 datasets; 3 signatures, induced exposure correlation): the standard NMF+NNLS degrades sharply past pairwise correlation r ≳ 0.8 (**a median of 20–41% of the weights gets attributed to cross-contamination**), while Cornet stays correct to r ≈ 0.98. The bit-for-bit numbers: NMF **median cosine error 0.032–0.13 (0.8 < r ≤ 0.98)**, cross-contamination median 20–41%; Cornet **median cosine error 0.0039–0.033**, cross-contamination 2–11%.
- The real-data findings: a cleanly resolved SBS88 (colibactin) in PCAWG colorectal (where NMF splits it fuzzily); SBS88 in the GEL head-and-neck; SBS84/85 in BNHL without clustering constraints; SBS93 shown to be a composite; **bladder cancer's SBS4/SBS92 split into 92a/92b, with 92a tracking the ERCC2 (cisplatin) status**.
- The preprocessing rule the paper declares: **rescale the catalog so the mean sample TMB = 10–40× the channel count V** (the original wording "average tumor mutational burden across samples was between 10 V and 40 V"; SBS96 → ~1000–4000 counts/sample) — it sets the "temperature" of the log-normal exposure distribution and controls the sparse/cluster behaviour. **[V]**

### 1.4 The significance for msuiter

The whole Cornet model ≈ **400 lines of dense linear algebra** (the elementwise exp/log-sum-exp + one O(VMK) matmul + a tiny Newton solve) — the cheapest solution to the correlated-signature problem (Wu 2022 proved it breaks the NMF). MIT-licensed, directly referenceable. MvNMF and the input-rescaling rule are likewise worth adopting.

---

## 2. SignatureAnalyzer (Broad/PCAWG) — the ARD automatic K determination (source-level verification)

The code: `sigminer/R/bayesianNMF.R` (the Broad Institute BSD-3 copyright header, "Copyright (c) 2017, Broad Institute"); the algorithm's origin: **Tan & Févotte, IEEE TPAMI 35:1592–1605 (2013)** (the ARD of the beta-divergence NMF). **[V]**

- The prior: the default variant `BayesNMF.L1W.L2H` = **W exponential (L1) + H half-normal (L2)**; also `L1KL` (exponential/exponential) and `L2KL`.
- The inference: **neither Gibbs nor variational** — a deterministic **type-II maximum likelihood (evidence maximisation) ARD**. The per-component prior precision `λ_k = 1/β_k` updates in closed form:
  - L1W/L2H: `β_k ← C / (Σ_i w_ik + ½ Σ_j h_jk² + b0)`, `C = N + M/2 + a0 − 1`
  - L1KL: `λ_k ← (Σ_i w_ik + Σ_j h_jk + b0)/C`, `C = N + M + a0 + 1`, `b0 = sqrt((a0−1)(a0−2)·mean(V)/K0)`
- The factor updates: **the KL multiplicative update with the ARD penalty** `H ← H ⊙ (Wᵀ(V ⊘ WH)) ⊘ (Wᵀ1 + diag(β)H)`; the L2 variants use the square-root MU.
- **The K-determination mechanism**: start from `K0`=max (e.g. 96); the ARD shrinks useless components until the prior precision crosses the hard threshold (`β.cut = (C/b0)/1.25`; dead when `colSums(W) < 1e-5` or `β > β.cut`). Convergence: `max|Δβ/β| < 1e-5` or n.iter (default **2,000,000 iterations**!). The defaults a0=10, b0=5.
- The known defects: in the SUITOR simulation SignatureAnalyzer misreported 17/20 times on single-signature data (prone to splitting flat signatures) **[search — the SUITOR paper]**; BayesPowerNMF 2026 reports high cosine errors for some cancer types.

**Assessment**: the ARD is the only production-grade rank-sweep-free automatic K determination; 10⁶ iterations in R are extremely slow → a Rust fused kernel can speed it up by orders of magnitude.

---

## 3. SUITOR — the entry-wise CV K determination (not optimal transport)

Lee D, Wang D, Yang XR, Shi J, Landi MT, Zhu B. "SUITOR: Selecting the number of mutational signatures." PLoS Comput Biol 18(4):e1009309, 2022 (NCI DCEG). The code `binzhulab/SUITOR` (R/Bioc). **[V — the PMC9009674 full text]**

- **The Poisson NMF + entry-wise unsupervised K-fold CV**: holdout by matrix **cell** (the index modulo 10 within each tumour) → the training matrix with MCAR missingness → the missing counts imputed by the conditional mean (the E step), i.e. the **ECM algorithm** (provably equivalent to the KL-MU, monotone in likelihood).
- The selection: `ERR_r = Σ_folds −log Pr(held-out|fit)`, take the argmin; the defaults tol 1e-5, max 2000 iterations, **300 random initialisations**.
- The results: the smallest held-out error on PCAWG (2,540 tumours); 91% sensitivity (cosine>0.8) on the in-vitro mutagenesis benchmark vs 45–82% for the competitors; zero misreports on single-signature data.
- **The porting note**: entry-wise CV in Rust is just a mask + partial-sum reduction; simple to implement and the **best-calibrated K-selection method**.

---

## 4. signeR — the empirical-Bayesian Gibbs NMF

Rosales RA et al., Bioinformatics 33(1):8–16 (2017). Bioconductor. **[V — read signeR.R on rdrr.io]**

- The Poisson NMF + **Gamma priors** (for the signatures P and the exposures E), with an **exponential hyperprior** over the shape of the Gamma rate hyperparameter (the hierarchical Gamma–exponential, not a Dirichlet); the hyperparameters estimated by the empirical-Bayesian EM (≤100 rounds).
- The inference: **Gibbs sampling** (a C backend); with K known: 10,000 burn-in + 2,000 posterior samples; for the K-determining run: 1,000+1,000. The K selection: the Gibbs likelihood BIC, a coarse-to-fine grid.
- The posterior → the credible intervals of the signatures and exposures; the 2023 follow-up (Drummond, BMC Bioinformatics) propagates the exposure posterior into the clinical association (PMC10664385).
- Runtime: 10⁴-scale MCMC × the candidate K's → the slowest mainstream tool, unfit for large cohorts.

## 5. BayesPowerNMF — the power posterior (NEW 2026)

Xue C, Miller JW, Carter SL. PLoS Comput Biol 2026, DOI 10.1371/journal.pcbi.1014372. The code `TARPS-group/BayesPowerNMF` (Python, MIT). **[V — repo+full text]**

- The Poisson NMF + a row-wise Dirichlet prior on the signatures + a **compressive Gamma prior** on the exposures (the Zito & Miller compressive Bayesian NMF) → the column-sparse shrinkage determines K automatically.
- The key trick: **the likelihood raised to a power α∈[0,1]** (the power posterior) to resist model mis-specification (contamination, over-dispersion, perturbation); α is picked via simulation calibration.
- Stan NUTS/HMC, 4 chains × 10k warmup + 10k draws; claims the best precision/recall under mis-specification (vs SigProfilerExtractor/SignatureAnalyzer/SigMoS), recovering the truth from as few as ~30 samples; 95% credible intervals.
- **For msuiter**: the α-power likelihood is a one-line change to the KL/Poisson engine (multiply the gradient by α), usable as a noise-resistant "robustness knob".

## 6. BASCULE — the Bayesian NMF + DP clustering + GPU SVI (NEW late 2025)

Buscaroli E et al., Genome Biology 27:15 (2025), DOI 10.1186/s13059-025-03835-9. **[V — the PMC full text]**

- The SBS/DBS/ID joint tensor; the Poisson likelihood; Dirichlet priors on the exposures and the de novo signatures; **the construction of the de novo prior ω gives low prior concentration to features already explained by the fixed COSMIC catalog** — i.e. **residual-aware de novo extraction** (fit the catalog first, the de novo absorbs only the residual).
- Pyro stochastic variational inference (GPU); two stages (first fit the catalog, then add de novo); post pruning (de novo with cosine ≥ ~0.9 to an existing one is dropped); the BIC for K; a DP mixture over the exposures for automatic clustering.
- Speed: GPU, 1,000 samples ~6 min vs SigProfiler/SparseSignatures/FitMS 30–559 min.
- **For msuiter**: the "residual-aware prior" is the most practical idea of 2025 (killing the repeated re-splitting of SBS40/5), adoptable inside a deterministic MU.

## 7. The Shiraishi model family: pmsignature and HiLDA

- **pmsignature** (Shiraishi 2015 PLoS Genet e1005657; `friend1ws/pmsignature`, R+C++): a signature = **the product of per-feature independent multinomials** `P(m|k) = Π_l F[k,l,feature_l(m)]` (the 6 substitution classes, any flank length, strand, transcript orientation). The EM inference (C++ `EMalgorithm.cpp`), sparse data storage (mutation, sample, count). **[V — the source]**
- The failure analysis: (a) the output is not in the 96-channel format, cannot be compared to COSMIC directly; (b) the per-feature independence assumption cannot express certain correlated flank structures; (c) the PCAWG/SigProfiler ecosystem lock-in. **[partly search]**
- **HiLDA** (PLoS Genet 2019, PMC6717498; USCbiostats): the hLDA on the Shiraishi representation, positioned as **the hierarchical test of the two groups' exposure difference** (Gibbs + the permutation test) rather than discovery. Also Matsutani 2019 Bioinformatics 35:4543 (the VB-LDA automatic K).
- **The keep/drop**: keep the Shiraishi-style factorised representation as an internal feature-engineering option (the strand/flank extension for free); the exchange format stays the SBS96/1536 one.

## 8. The deep-learning route — an honest assessment

| The method | What it is | The source | The conclusion |
|---|---|---|---|
| MUSE-XAE | an autoencoder: the nonlinear encoder + the non-negative linear decoder + the minimum-volume regularisation, Adam + the Poisson NLL | Bioinformatics 40(5):btae320, 2024; `compbiomed-unito/MUSE-XAE` | peer-reviewed and credible; but the fidelity is not visibly better than running MV-NMF directly; low adoption |
| SigNet | an ANN **refitter** (learns the inverse of the NNLS, gives prediction intervals, usable at low counts) | bioRxiv 2023.12.06.570467; `weghornlab/SigNet` | useful for the low-TMB fit/uncertainty, not an extractor, niche |
| Egendal 2025 | an NN for signature-based patient stratification | DOI 10.54337/aau815838821 | no methodological contribution |
| "deep unfolding NMF" (Nasser 2022) | an unrolled optimization network | **[unverified — the original source not found]** | skip |

**Conclusion: as of 2026-09, not one deep-learning extractor became a credible winner**. The frontier turned to (a) better-posed linear models + identifiability regularisation (Cornet/MvNMF), (b) Bayesian uncertainty, (c) rigorous model selection. "SigDC/MSNet/DeepMS" do not exist (name collisions with unrelated literature). **DL does not deserve an engine seat; a SigNet-style amortised refit is a possible future feature.**

## 9. The other extraction methods and the benchmarking landscape

- **Sonata `so.models.MvNMF`** (read from the `parklab/Sonata` source): `KL(V‖WH) + λ·log det(WᵀW + δI)` (Leplat, Gillis & Ang, IEEE TSP 68:3400–3410, 2020); the MM multiplicative update + the backtracking line search + the W column normalization. **The linear-world antidote for the identifiability of correlated/overcomplete signatures**. [V]
- **SparseSignatures**: the L1-penalized Poisson NMF + bi-cross-validation (known); the SUITOR benchmark shows fragility to mutation-calling errors.
- **SigMoS** (the Rosenberg group; cited as a comparator by BayesPowerNMF): overfits large cohorts. [search]
- **mSigHdp**: the HDP; the best sensitivity to rare signatures, slow (known).
- "Sigmoid" appears only in Islam 2022 [unverified]; Clomial is a clonal genotype deconvolution, not a signature tool; "MutationalSignatureAnalysis MATLAB / SP-Signatures / AutoSig / Gaussian-process extractor" were none found.
- **The benchmarking literature**: Islam 2022 Cell Genomics (the standard extractor benchmark); Wu 2022 Sci Rep 12:390 (the correlated-signature failure benchmark); **no new systematic extraction benchmark in 2023–2026** (excluding each tool's own benchmark) — **this is msuiter's paper's direct opportunity**.

## 10. The compute-engine zoo (with the update equations)

Notation: V ∈ R_+^{M×N} (M channels × N samples), V ≈ WH, W ∈ R_+^{M×K} the signatures, H ∈ R_+^{K×N} the exposures.

**(a) The KL-divergence multiplicative update** (Lee–Seung 2001; = the EM of the multinomial PCA / Poisson likelihood, Cemgil 2009):
```
H ← H ⊙ (Wᵀ(V ⊘ WH)) ⊘ (Wᵀ 1_M)
W ← W ⊙ ((V ⊘ WH)Hᵀ) ⊘ (1_M Hᵀ)
```
Cost: 3 GEMM + 2 elementwise divisions ≈ 4·MNK flops/iteration. Monotone non-increasing KL (Zangwill: global convergence to a stationary point); locally linearly convergent; sensitive to the initialisation; supports sparse V. Users: SigProfilerExtractor (PyTorch), MutationalPatterns (brunet), rust-NMF brunet, Sonata NMF, Cornet's W step.

**(b) The Frobenius/EU MU**: `H ← H ⊙ (WᵀV) ⊘ (WᵀWH)` — same cost; a Gram-ised implementation drops it to O(MK²+NK²+MNK) (NNLM `lee_ls`, rust-NMF `lee`). On count data it makes the wrong noise assumption.

**(c) HALS** (Cichocki 2007–2009; RcppML): per-component `h_k ← max(0, h_k + (g_k − G h_k)/G_kk)`, the Gram `G = WᵀW` incrementally updated; a sweep costs MNK + (M+N)K², cheaper when K≪M,N. The monotonicity guarantee holds under the Frobenius (KL-HALS has no general guarantee).

**(d) The ANLS active set** (Kim & Park 2007): each NNLS block solved exactly; the fewest iterations, the priciest iteration, the most complex implementation. NNLm (linxihui) implements the related **sequential coordinate descent SCD**: the KL version uses a quadratic surrogate minimized per coordinate, provably convergent, supporting L1/L2/missing masks. **[V — base_algorithms.cpp]**

**(e) Projected gradient / acceleration**: Lin 2007 Armijo line search; the Nesterov acceleration; rust-NMF `dnmf` is 26% faster than `lee` with no quality loss. [V — README]

**(f) The beta-divergence MM** (Févotte & Idier 2011; Marmin 2023 Signal Processing, cited by Cornet):
```
H ← H ⊙ [Wᵀ(V ⊘ WH)^{β̃}] ⊘ [Wᵀ(WH)^{β̃}], β̃ = β−1 (1≤β≤2)
```
β=2 Frobenius / β=1 KL / β=0 IS. The MM construction guarantees monotonicity for every β; Marmin 2023 gives the joint MM updating W and H simultaneously. The same O(MNK) cost, one extra pow. **"One kernel, three noise models" — the recommended engine.**

**(g) The Poisson NMF via EM/CCCP**: the soft EM latent-count assignment `c_vkd = x_vd·w_kv h_kd/(WH)_vd` + closed-form M steps — algebrically equivalent to the KL-MU (which is the basis of the SUITOR ECM argument), but it opens the stochastic/mini-batch/mirror-descent variants and the latent-count priors (the BASCULE/BayesPowerNMF route). Cornet's aux statistic is exactly this latent-count aggregation.

**The rust-NMF measured facts [V — lib.rs + README]**: bit-equivalent to R NMF: brunet/lee/offset/nsNMF/snmf-r/snmf-l/hals/ehals/dnmf/lsnmf + NNDSVD; ndarray 0.16 + rayon (no BLAS); pbmc8k (3000×1500, rank 8, 16 threads): lee+NNDSVD@25 iter = 0.19 s, brunet 0.41 s, hals 0.13 s; the best ARI = lee+NNDSVD 0.889 vs lee+random 0.568. **The core empirical law: "the NNDSVD initialisation is the magic, not the algorithm"**. ~76× over R (Lee, bit-equivalent) up to ~215× (HALS+NNDSVD@25 iter). **License GPL≥2 (inherited from the R NMF port) — reference only, its code must not be copied.**

## 11. The initialisation and K-selection best practices

- **NNDSVD** (Boutsidis & Gallopoulos 2008): the deterministic SVD initialisation; the variants NNDSVDa (zeros filled with the mean), NNDSVDar (zeros filled with small random). Sonata also has the `flat` + random + separable-NMF (SEMF) initialisations. At M≈100–1500, K≤30 the SVD is microsecond-scale.
- **The trustworthiness ranking of the K-selection methods**:
  1. **Held-out CV (SUITOR)** — the best calibrated, costly (K×folds×restarts) but perfectly parallel;
  2. **the MuSiCal stability/significance after pruning** (see the 02 report);
  3. **the ARD automatic K** (no sweep but a recorded over-splitting);
  4. **the consensus stability: the silhouette over the replicate exposures** (the SigProfiler default; the cophenetic of Brunet 2004 and the dispersion of Kim-Park 2007 are its ancestors). **Using the cophenetic alone is no longer defensible** (insensitive to rare signatures: Islam 2022; unstable under correlated signatures: Wu 2022), auxiliary diagnostic only;
  5. the BIC (signeR/BASCULE, reasonable within a likelihood framework);
  6. the HDP/shrinkage automatic K (truly non-parametric but slow/sensitive).
- **The recommendation**: the multi-start NNDSVD+random consensus silhouette (for compatibility) **+** the SUITOR-style CV error as the flagship statistic (the differentiator) **+** an optional ARD mode (the fast automatic K triage), reporting all three.

## 12. The pre-extraction catalog preprocessing

- **The hypermutators**: SigProfiler uses a 1-D GMM (`GaussianMixture(n_components=2, covariance_type="full")`) over the per-sample total mutation counts to determine the cutoff, the default manual_cutoff=**9600** (`subroutines.py:149` `get_normalization_cutoff`), then rescales per `matrix_normalization`: the default **`"gmm"`**, optional `"100X"`, `"log2"`, `"none"`, or pass a positive integer directly as a manual cutoff (`sigpro.py` ~L318; `README.md:93`; `docs/3. Using the Tool - Input.md:64`). **[V — the SigProfilerSuite/SigProfilerExtractor source]** (note: the repository migrated from AlexandrovLab to the SigProfilerSuite organization). The fixed literature thresholds >10 mut/Mb (hypermutated), >100 (ultra).
- **The common-then-rare two stages** (Degasperi 2022 Science 376:eabl9283): FitMS = **Fit Multi-Step** (PMID 35949260, PMC7613262). First fix the common signatures (the organ's RefSig T1–T4; `constrainedFit` uses the limSolve constrained NNLS), then search the rare signatures against the residual; the two strategies `constrainedFit` vs `errorReduction`, the paper's conclusion **errorReduction wins**: *"A rare signature is considered present if the reduction in error is at least 15%"*; the second step assumes 1 or 2 rare signatures exist. Implemented in `signature.tools.lib` (the Zenodo Code S1/S2). **[V]**
- **The opportunity normalization / exome↔genome**: the exposures keep both concepts of "activity share" and "per-Mb rate"; the sig_convert-style conversions are preserved.
- **The 2023–2026 new ideas**: ①the Cornet/Sonata input rescaling (10–40× the channel count); ②the MuSiCal denoising and consistency loop; ③the BASCULE residual-aware prior; ④the BayesPowerNMF α-power likelihood; ⑤the SUITOR entry-wise masking doubling as a QC score.

## 13. The Rust engine candidate designs (the shortlist)

| # | The design | The kernel | The K selection | The advantages | The disadvantages |
|---|---|---|---|---|---|
| E1 | **the MM beta-divergence kernel (β=1 default) + the ARD mode + the NNDSVDa initialisation** | MU/MM (4MNK) + the ARD hyperparameter update | the ARD automatic + the consensus silhouette | compatible with SigProfiler/MP; provably monotone; GPL-clean (reimplemented from Tan–Févotte/the paper formulas) | the MU converges slowly in the tail (cheap at this scale); the ARD over-splits flat signatures |
| E2 | **E1 + the SUITOR-style entry-wise CV module** | as above + the masked KL evaluation | the CV error as the flagship | the best-calibrated K; a strong paper differentiator; reuses E1 (needs mask support) | the K×folds extra cost (perfectly parallel) |
| E3 | **the Cornet port** | the MU over W + the O(MNK) aux + the tiny Newton | inheriting the MuSiCal-style pipeline | solves the correlated-signature problem; an MIT reference; positioned for the next generation | sensitive to the input rescaling; the embeddings introduce a tuning surface; no posterior at a single point |
| E4 | **the MvNMF volume-regularisation mode** | the MU class + the K×K logdet + the line search | same as E1 | identifiability under correlation without embeddings; a switch-style regularisation of E1 | λ/δ need choosing; over-regularisation distorts pure signatures |
| E5 | the Bayesian mode (the compressive/shrinkage-prior MAP or SVI) | MU+the prior term (the ARD is its α→MAP limit) or a hand-written ADVI | the shrinkage automatic K + CI | the posterior uncertainty (no Rust suite has it); the residual-aware catalog prior | the highest complexity; a hand-written SVI in Rust is a large undertaking |

**The recommendation**: E1+E2 as the core (sharing 90% of the code), E3 as the flagship second model, E4 as a flag of E1, E5 deferred. The engine surface ≈ 6 kernels + 1 SVD + 1 Newton/L-BFGS utility.

## 14. The citation list

(the key entries; the full ones are the inline citations in the body)
1. Jin et al. Cornet. bioRxiv 2026.09.14.751548, DOI 10.64898/2026.09.14.751548; Sonata: github.com/parklab/Sonata (MIT)
2. Paisley, Blei & Jordan 2014 (the correlated-NMF lineage)
3. Lee et al. SUITOR. PLoS Comput Biol 18(4):e1009309 (2022). PMC9009674
4. Rosales et al. signeR. Bioinformatics 33(1):8–16 (2017); Drummond 2023 PMC10664385
5. Xue et al. BayesPowerNMF. PLoS Comput Biol (2026) doi:10.1371/journal.pcbi.1014372
6. Buscaroli et al. BASCULE. Genome Biol 27:15 (2025) doi:10.1186/s13059-025-03835-9
7. Kim et al. SignatureAnalyzer. Nat Genet 2016 doi:10.1038/ng.3557; Tan & Févotte IEEE TPAMI 35:1592–1605 (2013)
8. Shiraishi et al. PLoS Genet 11(12):e1005657 (2015); Yang et al. HiLDA PMC6717498; Matsutani Bioinformatics 35:4543 (2019)
9. Pancotti et al. MUSE-XAE. Bioinformatics 40(5):btae320 (2024); Serrano et al. SigNet bioRxiv 2023.12.06.570467
10. Leplat, Gillis & Ang. IEEE TSP 68:3400–3410 (2020); Boutsidis & Gallopoulos SIAM J Matrix Anal Appl 30:60 (2008)
11. Lee & Seung NIPS 2000 / Nature 401:788 (1999) / Nature 2001 (KL); Févotte & Idier Neural Comput 23:2421 (2011); Marmin, Goulart & Févotte, Signal Processing 209:109048 (2023) doi:10.1016/j.sigpro.2023.109048
12. Kim & Park 2007/2008; Brunet PNAS 101:4164 (2004); Cichocki 2007–2009; Cemgil 2009
13. Islam et al. Cell Genomics 2:100131 (2022); Degasperi et al. Science 376:eabl9283 (2022); Wu et al. Sci Rep 12:390 (2022)
- The code: parklab/Sonata (MIT), binzhulab/SUITOR, TARPS-group/BayesPowerNMF (MIT), friend1ws/pmsignature, USCbiostats/HiLDA, omicverse/rust-NMF (GPL≥2, reference), linxihui/NNLM (BSD-2), zdebruine/RcppML (GPL≥3, the ideas), weghornlab/SigNet, compbiomed-unito/MUSE-XAE, sigminer R/bayesianNMF.R (Broad BSD-3, portable)

## 15. The explicitly unverified items

- The SigMoS citation details; the Sigmoid details (grepping "sigmoid" in the Islam 2022 full text = 0 hits — the term does not exist); mmsig2/MATLAB-MSA/SP-Signatures/AutoSig (not found, most likely do not exist)
- **Closed (this verification round, 2026-09-28)**:
  - the Cornet quantitative-benchmark numbers → **verified in full** (see §1.3); the DOI prefix corrected to `10.64898` (see §1)
  - the SigProfilerExtractor hypermutator parameters → **the original `gmm_cutoff`/`rescale`/`quadratical` claims were falsified**; the true parameter is `matrix_normalization` (default `"gmm"`; see §12)
  - the Degasperi rare-stage weighting → **verified**: the FitMS `errorReduction` strategy, the error-reduction ≥15% threshold (see §12)
  - the RcppML license → **GPL (>= 3)**, v1.0.0 (confirmed)
  - the Marmin 2023 DOI → `10.1016/j.sigpro.2023.109048` (Signal Processing **209**, art. 109048, Aug 2023; the authors Marmin, Henrique de Morais Goulart, Févotte)
  - the rust-NMF speedup ratios → the headline numbers should be **76× (bit-equivalent, lee) and ~215× (hals+NNDSVD, 25 iter)**; `280×` is an extrapolation from the single-row loose configuration (10 iter, 0.45 s) and is not fit as a headline
- **The license mines**: rust-NMF is GPL≥2 for its odd-parity-check implementation; RcppML GPL≥3; Sonata is MIT-safe; sigminer bayesianNMF.R is the Broad BSD-3 (portable with attribution); in every case the algorithm itself is published and can be freely reimplemented
