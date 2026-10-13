# The five-expert review synthesis adjudication (Synthesis, 2026-09-28)

> The five independent reviews are in this directory, 01–05. This document is the editor-in-chief's adoption adjudication — every review opinion is sorted into **adopt (fix the documents at once) / adopt (schedule it into the roadmap) / partly adopt / do not adopt (the reason recorded)**. The review originals are preserved unchanged; this document is the single effective caliber; where it conflicts with a review, this document prevails.

## 1. The one-sentence conclusions of the five reviews

| The review | The conclusion |
|---|---|
| 01 the computational biologist | **conditional trust** — the three flagship claims of the science layer (MSU-Fit coverage, MSU-Corr, the multi-evidence K) would be pierced by a single page; the HRD/RNA workflows as they stand are clinically dangerous and dishonest; the M0–M8 timelines are unrealistic |
| 02 the Rust/R expert | **conditional go** — the contracts of the Rust runtime layer (the RNG version, concurrency/fork, panics, the FFI boundary, the distribution budget) are almost wholly missing and must be written up at M0 |
| 03 the ML/statistician | **major revision** — the statistical claims are generally 1–2 grades stronger than the protocols support; downgrade "calibrated / distribution-free / lossless / first" to the level the protocols actually support |
| 04 the software-development expert | **conditional pass** — the "paper wishlist" is not a delivery plan; there is no v1 cut line, the bit-for-bit acceptance collides with the clean-room policy, as do the parallelization and the determinism |
| 05 the Nature editor | **the current positioning = Genome Biology/NC, not Nature Methods** — the only statistical contribution big enough for the top journal is "the calibrated statistics of exposure inference"; cut the 8 MSU-* down to 2–3; the three-act structure needs re-ordering |

## 2. The cross-corroboration (≥2 reviewers independently raised it = must change)

1. **The CI/calibration claims lack an estimand** (01#1, 03#2, 05#2/5/7)
2. **The conformal "distribution-free" is mathematically untenable under heterogeneous N** (01#11d, 03#1)
3. **MSU-Corr will be read as a Cornet derivative**: the gauge is unidentifiable, the baseline is missing, the ablation is missing, the m protocol is missing (01#7, 03#3, 05#2/risk 1)
4. **The determinism claims lack thread-count invariance** (02#3, 04#3)
5. **"Bit-for-bit" conflates the discrete semantics with the floating-point kernels, and collides with the clean-room strategy** (02#8, 04#2)
6. **The timelines are underestimated by ~3×, no minimal v1** (01's annex note, 04#1, 05 risk 3)
7. **The handles/.state are complexity paid for a capability that does not exist** (02#4, 04#11)
8. **The K selection lacks a default adjudication rule** (01#9, 03#4)
9. **The "first/lossless/distribution-free" over-claims** (01#11, 03 throughout)
10. **The 8 MSU-* dilute the contribution** (04 implicit, 05#2 explicit)

## 3. The adoption adjudications (fix the documents at once)

| # | The adjudication | The adopted content | The landing site |
|---|---|---|---|
| A1 | adopt | **The statistical contract**: the three-layer estimand (presence=the LRT χ²₁; magnitude=the support-conditional absolute exposure; zeroing=a decision rule with separately measured composite coverage); the calibration under both the multinomial and NB generative models; the coverage as a curve of N×Shannon; the Fisher intervals interior-only; "boundary parameters get tests, not intervals" | ARCH §7 |
| A2 | adopt | **The conformal down-scoping**: Mondrian by TMB bin + a studentized score; the claim rewritten as the per-stratum empirical coverage; the quantile tables shipped with the package | ARCH §5/§7 |
| A3 | adopt | **The method-naming contraction**: keep only the **MSU-Fit / MSU-LowCount / MSU-Infer** named methods (the headline cluster); the extraction pipeline / the correlation engine / the damage tempo / the tensor / the catalog IR all demote to **framework components** (losing the MSU- prefix) | ARCH §5 |
| A4 | adopt | **The correlation-engine downgrade**: pre-registered falsiable claims (simultaneously beating MvNMF+correlated refit and the original Cornet over r∈{0.8,0.9,0.95}); the gauge-fixed reporting (the embedding vectors are forbidden to interpret); m<K via held-out; the volume regularization and the embedding separated by ablation; the five modalities reduced to the SBS+DBS demonstration | ARCH §5/ROADMAP v1.x (the deferred items) |
| A5 | adopt | **The stateless FFI**: delete the handle registry and the `.state` property; the S7 embedded object becomes a **snapshot summary** (the dimensions + the channel-table hash + the refdb version); keep of the caugi pattern only the read-only aesthetics | ARCH §2/§3 |
| A6 | adopt | **The self-developed RNG**: the PCG64 + SplitMix64 stream layout (written into the paper's Methods), independent of rand's RNG surface (which carries no across-version guarantee); the across-version golden tests | ARCH §2 |
| A7 | adopt | **The concurrency contract**: parallelism only across independent units; a fixed reduction order within a unit; the thread-invariance identical() tests; the per-call ThreadPool (abandoning the global pool); the `msuiter.threads` option (2 during checks); Makevars -j2; R_CheckUserInterrupt at the main-thread chunk boundaries + the workers' AtomicBool | ARCH §2/§9 |
| A8 | adopt | **The two-layer acceptance terminology**: **the semantic bit-for-bit** (the channel arithmetic / the protocol steps / the tie rules / the default parameters — the integer and label goldens, a hard acceptance) vs **the numerical protocol equivalence** (the floating-point kernels — fixed seed + tolerance); the R NMF brunet cross-check = a one-off fixed-platform experiment, not into the CI gate | ARCH §7/ROADMAP |
| A9 | adopt | **The benchmarking upgrade**: add purity/caller/class-specific count intervals (SV 10–10³, CN 10–10⁴) / the hypermutant arm / the joint adversarial cell / the off-catalog signature cell; the three-layer calibration-selection-evaluation scenario isolation (different generators); **the primary metric = the Hungarian one-to-one** (the greedy + the threshold sweep as an appendix, splitting penalised); the protocol frozen and shipped with the package | ARCH §8 |
| A10 | adopt | **The K adjudication rule**: the hierarchical decision (SUITOR argmin → the stability veto → the Wilcoxon downgraded to diagnostics); the split/merge semantics of the Hungarian unmatched; the meta-rule evaluated over the full grid | ARCH §7 |
| A11 | adopt | **The catalog-completeness contract**: the MNV 2–5/>5, complex/double-indel routing table + the skip ledger; the DBS reconnection algorithm for split VCFs; the MNV golden fixtures; the explicit routing of complex events | ARCH §7/ROADMAP M1s/M1c |
| A12 | adopt | **The workflow-scope safety**: the HRDetect coefficient mode **WGS-only** + the allele-specific-CN-caller whitelist + WES marked experimental; the RNA workflow's minimal caller requirements + the pseudogene panel + the matched-DNA-validation estimand + the research-use annotation | ARCH §7/ROADMAP M6s |
| A13 | adopt | **The refdb governance**: the precedence (by default the bundled one prevails, the provenance pins the version); the schema_version forward rejection; updates pinned to a commit SHA + a burned-in manifest + fail-closed; the update tests fixture-ized; **v1 bundles only the human SBS/DBS/ID**; a missing build = a `build_independent: true` declaration (a relabel, not derived) + an honest notice at query time | ARCH §6 |
| A14 | adopt | **The API freezing**: `method = ms_nmf(...)` as a first-class S7 object + the string sugar; the custom generics uniformly `ms_`-prefixed (the hardhat naming stays a documentation concept only); the new §3.5 Error & lifecycle (the rlang class/i-j-c/bare stop forbidden/the lifecycle policy/the ffi-surface.md freezing procedure) | ARCH §3 |
| A15 | adopt | **The CI completion**: the matrix adds R 4.3 (Linux at least) + devel (allowed to fail); the valgrind/ASAN scheduled job; the CI benchmarking gate downgraded to a sanity bound (<5s), the speedup-ratio acceptance moved into the pinned-hardware bench; dependabot + cargo audit; codecov (R≥85%, Rust reports without a gate); the fixture refresh script + the PR-template check item; the rhub/--as-cran pre-submission | ARCH §9 |
| A16 | adopt | **The dual-track roadmap**: v0.1 (~6 weeks: SBS96/192/384/1536+DBS78, KL-NMF+NNLS, a single method, CI, r-universe) → v0.2 (~12 weeks: +ID83, the K selection, the three fitting methods, bootstrap CIs, refdb v1, 6 viz figures) → v1.0 (~5–6 months: the MSU-Fit calibration, the HRD report, pkgdown); **ID89/Infer/Tempo/Tensor/Lda/Supervised/CN-SV fitting/RNA/therapy deferred to v1.x**; M8 split into M8a/M8b | ROADMAP v3 |
| A17 | adopt | **The governance**: the registry gains the engine_version/contract_version/certified tri-states; the non-certified engines get a benchmarking warning + a trust-boundary statement; the monthly reverse-dependency matrix; CONTRIBUTING/CoC/templates | ARCH §3.4 |
| A18 | adopt | **The honest hypermutator naming**: `ms_stratify_hypermutants()` (classify+exclude+forced refit, not "normalization"); common/rare promoted into the atlas workflow; the Cornet 10–40× recalibration demoted to a correlation-engine-internal hyperparameter (sweep-verified + de-rescaled + forbidden on the NMF path) | ARCH §5/§7 |
| A19 | adopt | **The paper repositioning**: the headline = **"Calibrated inference of mutational signature exposures"** (Framing A) + the ecosystem support (B); **the two-week pilot coverage experiment (2 tools × a TMB grid) front-loaded before any narrative writing as a kill-criterion gate**; the case studies upgraded by three paths (treatment records/RNA-only/low-count panels) needing cohort collaborators; all seven kill criteria accepted | ARCH §10/ROADMAP the G gates |
| A20 | adopt | The rest: β=1 as the default is the multinomial MLE (delete the "three-noise" marketing or provide the protocol); the zero-pseudo-count policy; the SUITOR fold/imputation semantics replicated bit-for-bit (the semantic layer); hurdle/structural zeros for the DM; the twobit over `Cursor<Mmap>` ADR; the column-major+NA hard FFI contract; panic=Result with the boundary converting to error; the workspace dependency-direction assertions + `forbid(unsafe_code)`; the MSU↔function mapping table + `ms_sitrep()`; the docs-sync CI; the ADRs split into their own directory | everywhere |

## 4. Partly adopt / do not adopt

| The review opinion | The adjudication | The reason |
|---|---|---|
| 04#1 suggests deferring the SUITOR CV to v0.2 optional | **partly adopt** | the MSU-Fit headline leans on the calibration narrative but the K-selection rules lean on the CV — v0.1 has no CV, v0.2 adds it as a switch (agreeing with 04); but the K-adjudication-rule documentation is written in full once at v0.2 |
| 05 "name only MSU-Fit/LowCount/Infer" | **adopt but keep the component names** | the components still need engineering names (the extraction pipeline etc.), they just no longer appear as "methods" in the paper abstract |
| 01#3 lifts the MNV fix into M1 | **adopt** | the MNV routing is a semantic-correctness issue (without the fix the DBS/SBS catalogs are systematically distorted), not a deferrable feature; it lands at M1s (see A11) |
| 05 "cut MSU-Tensor out of the abstract" | **adopt + keep the exploration slot** | the TensorSignatures biological motivation is real; it demotes to exploratory (held-out likelihood for the K + the Kruskal checks), scheduled for v1.x |
| 04#9 the ADRs into their own directory | **adopt (lightweight)** | establish docs/adr/, migrate D1–D16 in first (16 entries already existed when the adjudication landed, incl. D15/D16); the research documents gain the archival statement |
| 02#11 the self-developed ~300-line twobit reader | **partly adopt** | the M0 spike tries both roads (the crate over Cursor\<Mmap\> vs self-developed), deciding the ADR by the byte-swap/big-endian validation results; the default inclination is the crate |

## 5. The organizing action items of the editorial suggestions (needing the author's own decisions/driving, not solvable by documents)

1. **The two-week pilot coverage experiment** (the G0 gate): the nominal vs actual coverage of 2 competing tools × a TMB grid — verifying the ground of the "the competitors' CIs are miscalibrated" narrative, before all paper writing.
2. **The statistics co-author** (the conformal/CoDA theory parts) + **the clinical/cohort collaborator** (one of the treatment records / RNA-only / FFPE panel) — locked before M3, otherwise the case studies are destined to be decorative (the editorial kill criterion #4).
3. **The co-maintainer**: found before M1s (the bus factor + CRAN + the reviewing triple need; i.e. the G1 gate).
4. Review the competitive landscape quarterly (the publication dynamics of Cornet/MuSiCal/SPA), triggering the ROADMAP's kill-criteria reassessment.

## 6. The documents in effect

- ARCHITECTURE.md **v2.2** (the implementation of this document's adjudications)
- ROADMAP.md **v3** (the dual track + the G gates)
- The review originals 01–05 are kept as the evidence and the paper's rebuttal material
