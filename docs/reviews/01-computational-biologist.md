# The review 01: the computational biologist (an independent review, 2026-09-28)

> The reviewer persona: a senior computational biologist in the mutational-signature direction, who has led Nature/Nature Genetics-grade signature atlas projects repeatedly. The review objects: docs/ARCHITECTURE.md, ROADMAP.md, research 00–08.
> **The overall verdict: conditional trust — as it stands it cannot be sent to review; after the P0/P1 repairs a solid paper can be produced.**

## P0 (the blocking grade)

### 1.[P0] The "coverage-calibrated CI" of MSU-Fit defines no estimand, and the Fisher information interval is invalid at the boundary
- **The attack position**: ARCHITECTURE §5 MSU-Fit; ROADMAP M3; the 02 report §2.
- **Why it is a scientific problem**: (a) Estimand missing — is the calibrated CI that of the exposure *fraction* or of the *absolute counts*? A mixture makes the coverage uninterpretable. (b) The boundary mass — the true value is very often exactly 0 (the sparse support); the percentile bootstrap and Wald/Fisher necessarily under-cover at the boundary; the χ²₁ LRT is the right machinery for the boundary problem (Self–Liang), but the support-conditional and the unconditional are two different estimands. (c) Once the CI zeroing rule is folded into the pipeline, the **composite pipeline** coverage must be measured, otherwise the numbers are fake. (d) The generative model of the calibration: the field's test framework (mSigAct) defaults to NB size=8 — the real catalogs are severely over-dispersed; a CI calibrated under the multinomial necessarily fails on the real NB data.
- **The fix**: nail down the three-layer estimand: ① presence = the χ²₁ LRT; ② magnitude|active = the support-conditional bootstrap CI, **calibrated under both the multinomial and the NB (the Jiang dispersion protocol)**, reporting the empirical coverage curve by N and the signature Shannon entropy; ③ the CI zeroing gets its own separate composite-coverage measurement. The Fisher interval is demoted to an interior-only diagnostic or deleted.

### 2.[P0] The HRD workflow overreaches: the HRDetect 2017 coefficients are WGS-trained, yet the "ensemble uncertainty" comes with no ensemble model
- **The attack position**: the 03 Top-10 #1 ("supports WES/WGS"); ROADMAP M6.
- **Why it is a scientific problem**: (a) The six HRDetect features are computable only with WGS-grade input; applying the frozen coefficients to WES/panel is a **patient-harm-grade** risk. (b) LOH/LST/TAI need allele-specific CN — the input contract (the caller whitelist) is unspecified. (c) The archive cites the Nacer 2026 7-method disagreement, yet waves it past with one "ensemble + uncertainty" sentence — no weights, no calibration cohort, no pre-registration.
- **The fix**: the HRDetect-coefficient mode **WGS-only**; the allele-specific CN caller whitelist (Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA); the WES mode must be marked experimental and recalibrated on an independent cohort; the ensemble rule pre-registered; the "HRDetect coefficient-validation test" is renamed the "reference-fidelity test" (it proves only that the coefficients were copied right, not that the WES features are interchangeable).

## P1 (the major grade)

### 3.[P1] The variant-class coverage gap: the MNV split, the complex/double-indel routing and the DBS reconstruction after VCF splitting are all undefined
- SPMG explicitly separates the adjacent SNVs at distance 2–5bp (the MNV); only distance exactly 1 enters DBS78; the hts-specs normalization splits an MNV into consecutive SNVs — a naive counting will systematically inflate the SBS channels and **DBS78 cannot be reconstructed from the split VCF**; the complex-indel routing destination is undeclared.
- **The fix**: the catalog-completeness contract: enumerate the routing destination of every input-event class (SNV/DBS/MNV2-5/MNV>5/complex indel/double indel), with the skip ledger entering the provenance; the reconnection-algorithm specification for the adjacent records of a split VCF; the MNV-adjacency golden fixtures into M1.

### 4.[P1] The Cornet 10–40× recalibration is a model-prior temperature knob, not a data-hygiene standard (and it is [search]-grade unverified)
- For a pure multinomial/KL objective, multiplying everything by a constant changes no estimate — the rule is meaningful only under scale-sensitive regularization (the adaptive σ², the volume term); it also changes the CV deviance scale and the absolute-exposure semantics (a de-rescale is needed, unmentioned).
- **The fix**: demote it to an MSU-Corr-internal hyperparameter; the M7 grid sweep scale ∈ {1,10,40,100}, with the flat-signature under-estimation as the guard metric; explicitly forbidden on the NMF path.

### 5.[P1] The GMM hypermutator handling is misnamed "normalization"; the Degasperi common/rare two-stage has no owner in the architecture
- The GMM step of SigProfiler is **classify and exclude from the de novo, then refit** — it is a stratification, not a normalization; what gets excluded are exactly the APOBEC/POLE/MMR samples, and the cutoff directly decides whether these signatures can be extracted at all; the two-stage strategy has no MSU-* claimant, no milestone, no workflow.
- **The fix**: `ms_stratify_hypermutants()` (the explicit GMM cutoff + the de novo exclusion + the forced refit); promote common/rare to an atlas workflow into M6; add the 5–10% hypermutator arm (TMB 100×) to the benchmark, reporting the APOBEC/POLE P/R sensitivity to the cutoff.

### 6.[P1] The benchmark lacks the two most realistic failure axes — purity and caller dependence; the CN/SV count intervals are mis-scaled
- A purity of 0–70% produces mixed spectra and subclonal structures; two callers on the same BAM give different catalogs (the archive itself cites 41427300); the N of CN/SV is the segment/rearrangement count (tens–hundreds), so the TMB 10²–10⁶ does not apply.
- **The fix**: add purity ∈ {1.0, 0.7, 0.4, 0.2}; the caller axis (≥2 SNV + ≥2 indel callers); the class-specific count intervals (SV 10–10³, CN 10–10⁴); the joint scenario of a flat-signature group at r=0.8 co-existing with a rare signature; the subclonal exposure structure.

### 7.[P1] The scientific delta of MSU-Corr is the weakest: the simpler baseline "MvNMF extraction + correlation-aware refit" is not excluded; m=K is over-parameterized
- The volume regularization and the embedding are bundled together with no ablation; h=exp(α+β+l·u) at m=K carries the rotation/re-parameterization unidentifiability; the five-modality joint forces the different count scales to share the exposure.
- **The fix**: a pre-registered falsiable claim (simultaneously beating MvNMF+correlated refit and the original Cornet over r∈{0.8,0.9,0.95}); write down the gauge-fixing method; m<K + the selection rule (BIC/CV); reduce the five modalities to the SBS+DBS dual-modality demonstration until proven.

### 8.[P1] The RNA workflow is dishonest about its upstream dependencies
- The COSMIC RNA-SBS comes from a specific calling pipeline and filter chain; fitting variants from other pipelines to this reference inherits caller artifacts heavier than the DNA case; the 192 channels need stipulating which chain's context is used; the DNA-RNA concordance needs a paired cohort and a pre-set metric.
- **The fix**: the minimal input requirements (RNA-Mutect2 or STAR 2-pass + documented filters; the RNA editing exclusion; the matched-normal annotation); add the RNA-artifact signatures to the reference panel; the pre-set concordance estimand; lock the case studies to a paired cohort; mark the workflow research-use.

### 9.[P1] The "report all the evidence" K selection has no adjudication rule — it is a dashboard, not a method
- The failure mode is exactly the evidence contradicting one another (the silhouette plateaus on the flat signatures, SUITOR biases toward parsimony, Wilcoxon biases toward lenience); the "agreement rate with SPA" is weaker yet — agreement is not correctness.
- **The fix**: a default adjudication rule (e.g.: within the 1-SE of the CV argmin → the maximum stability → the most parsimonious presence) as the K decision of MSU-Extract, scoring **the single decision rule** with the F1-vs-K over the Islam protocol, replacing the agreement rate.

## P2

### 10.[P2] The genome hygiene is missing: the chromosome whitelist, the sex opportunity correction, the alt contigs, chrM, T2T
- The opportunity vector must match the callable domain (the male chrX, the aneuploidy segments, the alt-contig double counting); **the "across-build derivation" concept is muddled: the ID83/CN48/SV32/RNA-SBS labels themselves are build-irrelevant, the signature matrices are build-agnostic — the real dependency lies only in the exome/panel opportunity catalogs**.
- **The fix**: the contig strategy + the per-sample opportunity vector (the CN segments + the sex + the callable BED); rewrite §6.2; the exome/panel opportunity-normalization reference set is the true gap.

### 11.[P2] The "first/gap" class claims are over-claims against the 2023–2026 literature the archive itself cites
- sigfit/signeR/BayesPowerNMF all produce nominal intervals — the "first" must be narrowed to "**the first empirical coverage-rate measurement of the exposure intervals**"; SigNet already does the low-count refit; Morrill 2025 already is a formal compositional framework; **the conformal "distribution-free" does not hold under heterogeneous N**, needing a grouped/weighted stratified calibration.

### 12.[P2] The multi-sample VCF and the germline/somatic ambiguity: the validation contract does not catch it
- The MsVariants validator does not validate the somaticness signals (the FILTER, the VAF floor, the matched-normal provenance); under ctDNA the CHIP/germline contamination is the first failure mode.
- **The fix**: the extended validation (the caller+normal provenance mandatory, the VAF floor, the confidence-class pass-through, the low-VAF sensitivity curve).

## The overall verdict and the highlights
- **Conditional trust**; the benchmark paper (the panel ②) with the design + the problem-6 added axes has a real contribution; the three headline claims of the panel ① are in the "a serious reviewer will pierce it with a single page" state; writing HRD/RNA into the paper as they stand is clinical danger and scientific dishonesty.
- The annex note: M0–M8 ≈ 15–20 weeks is unrealistic; cut MSU-Tensor/MSU-Tempo down to watch.
- **The three things done well**: the source-level fact-check discipline; the statistical stance is correct and consistent (KL=the count MLE, the cosine demoted, the χ²₁ boundary, the precision/recall stance); the honest competitor and licensing positioning.
