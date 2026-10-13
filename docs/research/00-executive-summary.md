# msuiter research executive summary (Executive Summary)
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-27. Method: GitHub issue archaeology (WangLabCSU/msuiter#1, all the open issues of ShixiangWang/sigminer), a close reading of the whole SigProfiler family's source, 5-way parallel deep research (the extraction methods / the fitting inference / the application scenarios / the repository-by-repository source audit / the standards and data licenses), and a broad retrieval over PubMed + bioRxiv + the academic databases.
> Every report in this directory is first-hand verified (marked [V] = verified by reading the source/full text, [U] = not fully verified) and can be used directly as material for the paper's Related Work / Methods.

## 1. The project positioning (from msuiter#1 and the sigminer#456 v3 roadmap)

- The goal: **the next-generation mutational-signature ecosystem with performance on par with SigProfiler, integrating the domain's best algorithms**.
- The technical route: a Rust computational substrate + the R package's user interface (the rextendr bridge); modular, orthogonal, DRY, TDD.
- The paper orientation: the three pillars -- ① the architecture and implementation ② the performance and benchmark ③ the application-scenario case studies.

## 2. The methodological state of the art (see the 01/02 reports)

### Extraction (de novo extraction)
| The method | The core idea | The state |
|---|---|---|
| SigProfilerExtractor | the KL-MU NMF + 100 multinomial resamplings per rank + the Hungarian consensus clustering + the stability selection | the industry's gold standard, slow (2,500 NMFs, day-scale) |
| SignatureAnalyzer (PCAWG) | the ARD evidence-maximisation automatic K determination (L1W.L2H), the KL-MU + the prior shrunk | no rank sweep needed but prone to splitting flat signatures |
| MuSiCal / Sonata | the likelihood-sparse NNLS fit + mvNMF (the logdet volume regularisation) + Cornet (correlation-aware) | the current methodological frontier (the Park lab) |
| SUITOR | the entry-wise 10-fold CV K selection (ECM≈KL-MU) | the best-calibrated K selection |
| mSigHdp | the hierarchical Dirichlet process | the best sensitivity to rare signatures, slow |
| signeR / BayesPowerNMF / BASCULE | Bayesian (Gibbs / the power posterior / SVI) | posterior uncertainty, MCMC slow |
| deep learning | MUSE-XAE / SigNet etc. | **not one became the mainstream winner**; no investment for now |

**The key empirics**: rust-NMF proved "the NNDSVD initialisation is the magic, not the algorithm" (NNDSVD+25 iterations ≈ a random initialisation + several hundred); the KL multiplicative update on count data is the statistically correct MLE (the multinomial/Poisson equivalence).

### Fitting (fitting / attribution)
- Medo 2024 Nat Commun (12 tools): **SigProfilerAssignment and MuSiCal are best at high counts; pruning the reference catalog is harmful; flat signatures (SBS5/40) are systematically underestimated; the fitting error ∝ 1/√N and correlates with the signature's Shannon entropy**.
- Jiang et al. Brief Bioinform 26(1):bbaf042 (2025, epub 2024-11; 13 tools): **PASA** (the forward search + LRT) is first on DBS/ID, MuSiCal first on SBS; the core insight -- **the reconstruction-similarity metrics carry no information** (in 99/100 gastric-cancer samples there exist wrong attributions whose reconstruction beats the true one); precision/recall must be used for evaluation.
- The likelihood-loss theory: the multinomial likelihood (KL) is the correct MLE for count data; cosine can only do reporting, not inference; the substantive difference between QP and NNLS is only the Σe=1 equality constraint.
- **The three paper-grade gaps** (which we can occupy):
  1. the coverage of the exposure CIs has never been validated by any tool (Medo raises this open question explicitly);
  2. no tool does proper statistical compositional-data analysis (CoDA/log-ratio) on the exposures;
  3. the panel/ctDNA case of <100 mutations has no principled general fitting tool (SigMA covers only SBS3/HRD).

### Post-processing
- the per-mutation allocation probability (proportional allocation) -- nobody conditions it or propagates the uncertainty; the per-signature TSB/RTT tests -- nobody supports them natively; signature timing (TrackSig/CloneSig) and the deconvolution of treatment history are near-zero-competition areas.

## 3. The application panorama (see the 03 report)

11 major application classes → the Top-10 deliverable workflows: the HRD clinical composite report, the atlas refit, the exposure-attribution epidemiology, the joint extraction of the five variant classes (Everall 2026, the first SV reference set), the repair-deficiency diagnostics (MSI/POLE/MUTYH via signatures), the treatment-history forensics, the normal-tissue low-count mode, the RNA-seq signature module, the ctDNA mode, the preclinical toxicology across species.

## 4. The engineering facts (see the 04/05 reports)

- **The performance hot spot**: SigProfilerMatrixGenerator's pure-Python byte-by-byte loop is the whole stack's biggest CPU black hole -> the Rust port yields the largest gain; its "pre-encoded chromosome byte string (the base+strand single-byte enumeration)" design can be ported to mmap directly.
- **The channel semantics must be replicated bit-for-bit** (the bit-compatibility targets): SPMG's ID83 classification (the repeat walk + the longest microhomology match + the forward-priority tie-breaking rule + the Q-chain disambiguation), the SBS 6144/1536 main indices, the DBS Q-flag flips, the precise definitions of CN48/SV32 (the 48/32 row labels were fully scraped and archived).
- **The channel-order trap**: the two orderings of SBS96 coexist (COSMIC flank-major vs Nature2013 substitution-major); normalisation by label is mandatory (the lesson of MutationalPatterns issue #60).
- **The license mines**: rust-NMF(GPL≥2)/RcppML(GPL≥3)/mSigAct(GPL-3)/NNLM(BSD-2 usable)/SPMG(BSD-2 usable)/Sonata(MIT usable)/sigminer bayesianNMF.R(Broad BSD-3 portable) → **reimplement the core cleanly from the paper formulas, avoiding GPL contagion**.
- **The COSMIC data**: the official T&C forbids redistribution; the whole-field practice is bundling the Alexandrov lab's BSD-2 mirror (the SigProfilerAssignment repo). The plan: bundle (with the provenance pinned to that mirror) + on-demand updates.
- **CRAN**: networking at install time is forbidden -> the cargo vendor template (string2path verified workable); r-polars ships only to GitHub/r-universe. Keep the Rust dependencies lean (faer is huge; a self-written SVD/Cholesky can avoid it).
- **The Rust ecosystem**: extendr-api latest 0.9.0 (2026-04-16, 0.8.2 being the last of the 0.8 line; incl. the faer/ndarray integration), savvy 0.11, the twobit crate 0.2.2 (a pure-Rust 2bit genome reader, random access) → the genome-context extraction can fully sidestep BSgenome's 3GB memory. The S7 class system (RConsortium): CRAN 0.2.2 stable, adopted by ggplot2 4.0, 104 CRAN packages, the Bioc2026 invited talk -- adopting it at the R package layer is safe (see report 06).

## 5. The competitive landscape in one sentence

SigProfiler = the Python gold standard but slow and closed; on the R side sigminer/MutationalPatterns are pure-R and slow with stale COSMIC versions; MuSiCal = the Python frontier method; **nobody offers an R ecosystem with Rust-grade performance + complete statistical inference + the five variant classes unified + application workflows** -- that is msuiter's ecological niche.

## 6. The document index (the full library)

**The research reports (this directory, all of snapshot nature)**
- [01-extraction-methods.md](01-extraction-methods.md) — the extraction-method panorama and the NMF-engine zoo (incl. the update equations)
- [02-fitting-inference.md](02-fitting-inference.md) — fitting, attribution, uncertainty, post-processing analysis
- [03-applications.md](03-applications.md) — the application literature and scenarios → the workflow-module requirement mapping (incl. the PMIDs)
- [04-source-audit.md](04-source-audit.md) — the repository-by-repository source audit (the algorithms precise to file:line, the licenses)
- [05-standards-data.md](05-standards-data.md) — the COSMIC license, the channel standards, the genome readers, the visualization, the benchmarks, the CRAN policy
- [06-s7-class-system.md](06-s7-class-system.md) — the state of the S7 class system, the design patterns and the method-dispatch blueprint
- [07-algorithm-zoo.md](07-algorithm-zoo.md) — the full stocktake of the tiered algorithm zoo + the self-development opportunity list
- [08-fact-check-audit.md](08-fact-check-audit.md) — the whole-corpus fact-check audit (the discrepancy adjudications)

**The live documents (the single authoritative caliber)**
- [../ARCHITECTURE.md](../ARCHITECTURE.md) — architecture v2.2 (the decisions D1–D16, the layering, the scientific contracts)
- [../ROADMAP.md](../ROADMAP.md) — the dual-track roadmap v3 (v0.1/v0.2/v1.0 + the G0–G3 organizational gates)
- [../CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) — the capability-coverage matrix (the completeness authoritative checklist)
- [../reviews/00-synthesis.md](../reviews/00-synthesis.md) — the five-expert review adjudication (01–05 are the evidence originals)
