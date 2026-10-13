# msuiter implementation plan (IMPLEMENTATION-PLAN) -- the executable decomposition of ROADMAP v3

> Version: **v1 (2026-09-28)**. Upstream authorities: [ROADMAP.md](ROADMAP.md) (the sole authoritative definition of the version tracks and milestones), [ARCHITECTURE.md](ARCHITECTURE.md) §0 D1–D16 (the constitution), [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md) (the completeness authoritative checklist).
> This document introduces no new scope: it translates the ROADMAP's milestones into work units (U-*), each carrying deliverable paths, acceptance criteria (citing the D clauses), dependencies and estimates. Any conflict with the ROADMAP/matrix is resolved in favor of the upstream source and goes through docs-sync for correction.
> Execution: each work unit runs one round per the PI team workflow of [.agents/skills/msuiter-team/SKILL.md](../.agents/skills/msuiter-team/SKILL.md); the devlog file name uses the unit ID (`docs/devlog/YYYY-MM-DD-<U-ID>.md`, the directory is created with the first unit).

---

## 1. General rules of execution

1. The unit loop (one round per unit): read the state -> PI decomposition (≤3 work slices) -> for units touching algorithm semantics/statistical claims, issue a design memo first (the signature expert + the computational-biologist in parallel, landing in the devlog, implementing only after the PI adjudication) -> TDD implementation (tests before the implementation) -> the PI integration self-check (`cargo test` / testthat / the acceptance criteria ticked one by one) -> the independent audit (fed only with the deliverables, PASS/REVISE ≤2 rounds) -> the devlog + ticking the ROADMAP + updating the CAPABILITY-MATRIX status column.
2. Acceptance-term ahead annotation (D11): each unit's acceptance criteria is annotated with one of three classes -- [bit-for-bit]: the semantics replicated bit-for-bit with golden tests (the channel arithmetic / the protocol steps / the tie-breaking rules / the default parameters, the integers and the labels, the hard acceptance) | [equivalence]: the numerical protocol equivalence (the fixed seed + the tolerance, a one-off platform experiment, not entering the CI gate) | [engineering]: an executable acceptance (all tests green / the build artifacts / the documentation's presence).
3. The parallelism rule: the Rust track (the engine/catalog crate) and the R track (S7/io/the generics) advance in parallel; within a track, serial by the dependencies; before the FFI contracts (U-M0-09) are frozen, the R track makes no kernel-call hookup.
4. The scope iron law: only the current unit (the msuiter-team hard constraint 1); design defects discovered during the implementation and "while-at-it optimisations" are recorded in the devlog's leftovers, without expanding the unit. A deviation touching D1–D16, the G gates or the kill criteria -> stop and report to the user, do not amend the constitution on your own.
5. The progress governance: the estimation unit is a "focused working day" (the honest caliber for one person + AI agents, having absorbed the review's ~3× upward adjustment; a unit's day count is a budget, not a commitment). Every Friday the PI re-plans the next week; at a milestone's acceptance the kill criteria are re-reviewed; **two consecutive weeks of slippage trigger a re-estimation** (the early-warning line of the "slippage >100%" kill criterion).
6. The state record: the unit-level progress is governed by the devlog, the milestone-level ticking by the ROADMAP checkboxes, the capability status by the CAPABILITY-MATRIX -- this file sets no separate status column (avoiding a dual source of truth).

## 2. The work-unit dependency graph (the v0.1 segment)

```
U-M0-01 scaffolding ─┬─ U-M0-03 S7 skeletons ── U-M0-04 registry table ─┐
                     ├─ U-M0-05 channel tables ──────────────────────────┼─→ the R track (U-M1s-10/11/12)
                     ├─ U-M0-06 self-developed RNG ─── U-M1s-04 resampling┤
                     └─ U-M0-09 FFI hard contracts ── U-M1s-09 exports ──┘
U-M0-02 spike (the W1 hard deadline) ─ ADR (the twobit two options / the vendor bytes) ─→ U-M1s-08 the 2bit fast path
U-M1s the Rust track: U-M1s-01 linalg/NNLS → 02 KL-MM → 03 NNDSVDa → 05 thread-invariance
U-M1s the catalog:   U-M1s-13 the fixture infrastructure (depends on 05) → 06 SBS → 07 DBS+MNV
the G0 pilot experiment (W1–2, the author himself) → the Framing ADR — independent of the code tracks, not blocking M0/M1s
```

The unnumbered cross-cutting items: U-M0-07 (the CI matrix), U-M0-08 (the governance files), U-M0-10 (the ADR directory migration) have no code dependency and run in parallel at any time.

## 3. The v0.1 week-by-week schedule (~6 weeks: M0 the engineering foundations + M1s the engine and the catalog core)

| Week | The tracks' parallel content | Notes |
|---|---|---|
| **W1** | U-M0-01 scaffolding, U-M0-02 spike (**the W1 hard deadline**), U-M0-08 the governance files, U-M0-10 the ADR migration, **the G0 kick-off** | The spike and the scaffolding are the plan's critical path; the G0 protocol is frozen and the experiment begins |
| **W2** | U-M0-03 the S7 skeletons, U-M0-05 the channel tables, U-M0-06 the RNG, U-M0-07 the CI | **the G0 close-out**: the report + the Framing ADR (deciding the M7 paper headline, not blocking the code) |
| **W3** | U-M0-04 the registry table, U-M0-09 the FFI contracts + `ms_sitrep()`, **the M0 acceptance review**; the Rust track warms up with U-M1s-01 | The FFI-contract freezing = the R-track's unlock point; the G1 co-maintainer invitation should have gone out |
| **W4** | U-M1s-01 NNLS, 02 KL-MM, 03 NNDSVDa, 04 resampling, 05 thread-invariance, 13 the fixture infrastructure, 06 the SBS start | The engine-crate completion week |
| **W5** | U-M1s-07 DBS+MNV, 08 the 2bit fast path, 09 the FFI exports, 10 `ms_variants()`, 11 `ms_tally()` | The semantic-correctness focus week (an MNV routing distortion = the systematic SBS/DBS error, A11) |
| **W6** | U-M1s-12 `ms_extract()` single-method, 14 the one-off KL cross-check, the hardware-pinned bench, **the v0.1 release gate** | The buffer and polish days are reserved in this week |

### 3.1 The M0 work-unit table (the 2-week budget + the W3 closing acceptance)

| ID | Unit | The key deliverables | Acceptance (the D11 annotation) | The dependencies | The estimate |
|---|---|---|---|---|---|
| U-M0-01 | the rextendr scaffolding + the Cargo workspace | `DESCRIPTION`/`Makevars.in`/`src/rust/` (the workspace: the FFI shell crate at the root + the `engine/`, `catalog/` members, the rextendr convention) /`R/msuiter-package.R`/`zzz.R` | [engineering] the dependencies = the shrunk list (extendr-api default-features=false, ndarray, rayon, memmap2; **no rand**, D2/ARCH §2); the engine+catalog `#![forbid(unsafe_code)]`; the deny ban direction rules; cargo test's empty spin green + check green | — | 2–3 d |
| U-M0-02 | **the M0 spike** (the W1 deadline) | the real cargo vendor + the xz byte-count report; the rustc 1.71 × {Linux, macOS, Windows} build proofs; the twobit two options (the crate over `Cursor<Mmap>` vs the self-developed reader) with byte-swap/big-endian validation → two ADRs | [engineering] the numbers land in the ADRs (D4/D7); a vendor over budget -> a dependency-re-shrinking decision recorded | 01 | 3 d |
| U-M0-03 | the S7 class skeletons (no `.state`) | `R/classes/*.R` (delivered as flat `R/classes-*.R` per ARCHITECTURE §3.1 flat-module law; load order via DESCRIPTION `Collate`): the seven classes MsVariants/MsCatalog/MsSignature/MsFit/MsRefDb/MsEngine/MsBenchmark + the validators; all cross-references are snapshot summaries (the dimensions + the channel-table hash + the refdb version, A5) | [engineering] a bad label/dimension/NA must throw and the error's class is asserted; the full-generic behaviour tests after saveRDS/load (D8/D12) | 01 | 3 d |
| U-M0-04 | the engine registry table + the contract tests | `register_ms_engine(name, mode, engine_class, fit_fn, packages, tags, engine_version, contract_version, certified)` (A17) | [engineering] when the string-sugar parsing fails, list all the available engine names; the non-certified warning logic | 03 | 2 d |
| U-M0-05 | the channel-registry single source of truth | `data-raw/build_channels.R` → the R data + the Rust constants + the build-time consistency assertion against the COSMIC files + the docs-sync CI | [engineering] drift goes red (D5) | 01 | 2 d |
| U-M0-06 | the self-developed RNG module | `engine/rng.rs`: the PCG64 + SplitMix64 stream layout (the per-replicate/rank/fold counter streams, A6; the layout written into the paper's Methods) | [bit-for-bit] the cross-version golden: a fixed seed → the fixed first N u64 | 01 | 2 d |
| U-M0-07 | the CI system | `.github/`: the 3 OS × {release, oldrel, R-4.3(Linux), devel} matrix, rcmdcheck --as-cran, cargo test/clippy/deny(ban)/audit, valgrind+ASAN scheduled, dependabot, codecov (A15); **the wiring claim (handed off from U-M0-01/02/05/06)**: tools/check-dep-direction.sh, tools/vendor.sh --check, tools/rng-kat.py, tools/docs-sync.R, the deny full four sections, the matrixmultiply ≥0.3.10 pinned-version protection (the dependabot policy), the rustc 1.71 × Linux/Windows build proofs (the ADR 0002 §4.4/§5 leftovers), **the repo-mode testthat** (the drift-guard-class tests skip under the R CMD check context -- the CI must run the full `devtools::test()` on a checkout, incl. test-channels-sync/reference) | [engineering] the whole matrix green | 01 | 2 d |
| U-M0-08 | the governance files | CONTRIBUTING (incl. the third-party-engine onboarding checklist)/CoC/the issue and PR templates (incl. the FFI-surface-change and fixture-refresh check items)/the README skeleton/NEWS.md/`_pkgdown.yml` | [engineering] present and the templates renderable | — | 1 d |
| U-M0-09 | the FFI hard contracts landed + sitrep | the stateless export skeletons (D12: no handle/no `.state`); the column-major "transpose-detector" unit probe; the anyNA rejection; the `Result<_, MsError>` boundary converted to a condition; the `R_CheckUserInterrupt` chunk polling; the per-call ThreadPool + the `msuiter.threads` option (the default 2 during checks); `ms_sitrep()`; the establishment of `docs/ffi-surface.md` | [engineering] the detector/error-path/interrupt tests pass; a panic -> the whole call errors with no partial result | 01 | 3 d |
| U-M0-10 | the ADR directory migration | the establishment of `docs/adr/`, D1–D16 migrated in (the synthesis §4 lightweight-adoption item) | [engineering] all 16 entries present and consistent with ARCH §0 | — | 0.5 d |

**The M0 acceptance gate** (the ROADMAP's original wording): check fully green; the S7 validation tests pass; the RNG golden passes; the vendor byte counts land in the ADRs.

### 3.2 The M1s work-unit table (the 4-week budget)

| ID | Unit | The key deliverables | Acceptance (the D11 annotation) | The dependencies | The estimate |
|---|---|---|---|---|---|
| U-M1s-01 | linalg + NNLS | `engine/linalg.rs` (the pivoted Cholesky/LDLᵀ, the triangular solve) + `engine/nnls.rs` (Lawson-Hanson on the Gram: the pivot LDLᵀ + the ε‖G‖ ridge) | [engineering] the KKT assertions + the ill-conditioned Gram tests (ARCH §9) | 01 | 2 d |
| U-M1s-02 | the KL-MM MU kernel | `engine/nmf.rs` the β=1 default (= the multinomial MLE, D6); the ε policy (the denominator `max(·,ε)`/`log(ε+·)`) documented | [equivalence] vs R NMF brunet, see U-M1s-14; [engineering] the KL monotonicity + the ε-behaviour tests | 01 | 3 d |
| U-M1s-03 | the NNDSVDa initialisation | `engine/nndsvd.rs` the randomised SVD: q≥3 power iterations + oversampling≥16 | [engineering] the exact Gram-SVD cross-check property test | 01 | 2 d |
| U-M1s-04 | the multinomial resampling | `engine/resample.rs` + the RNG counter-stream wiring | [bit-for-bit] the sampling sequence for a fixed seed is golden | 06 | 1–2 d |
| U-M1s-05 | the thread-invariance | the per-call ThreadPool wired into the engines; parallelism between units / a fixed reduction order within a unit (A7) | [engineering] the same seed gives `identical()` outputs for threads∈{1,N}, a hard CI test | 02/04 | 2 d |
| U-M1s-06 | the SBS channel families | `catalog/sbs.rs` the byte arithmetic of SBS96/192/384/1536 | [bit-for-bit] the SPMG cross-check golden (research/04 §1) | 05, 13 | 3 d |
| U-M1s-07 | DBS78 + the MNV routing | `catalog/dbs.rs` (the Q-chain rules) + `catalog/mnv.rs` (the 2–5bp/>5bp/complex indel/double indel routing table + the re-join of adjacent records across split VCFs + the skip ledger into the provenance, A11) | [bit-for-bit] the SPMG DBS/MNV/complex golden; the explicit routing failure modes | 06, 13 | 3 d |
| U-M1s-08 | the 2bit fast path | `catalog/genome.rs` (implemented per the U-M0-02 spike ADR's chosen option) | [engineering] the byte-swap/big-endian validation + the cross-check against BSgenome | 02 | 2 d |
| U-M1s-09 | the FFI exports | `ms_tally_rust()` / `ms_extract_rust()`; the freezing of `docs/ffi-surface.md` (the per-release review artifact) | [engineering] the surface diff becomes a PR-template check item | 09(M0), 06/07 | 1 d |
| U-M1s-10 | `ms_variants()` | `R/io/variants.R` (delivered as `R/io-variants.R` per ARCHITECTURE §3.1 flat-module law; DESCRIPTION `Collate`): the VCF/BCF/MAF/TSV read-time validation → MsVariants; the somaticness signals (the caller/normal provenance, the VAF floor, the FILTER pass-through) | [engineering] the full validator tests on bad inputs (the L-A M1s row) | 03 | 2 d |
| U-M1s-11 | `ms_tally()` | `R/catalog/tally.R` (delivered as `R/catalog-tally.R` per ARCHITECTURE §3.1 flat-module law; DESCRIPTION `Collate`) the generic dispatch + the MsCatalog assembly; the minimal annotation-cache set (the transcript chain, supporting SBS192/384) | [engineering] the catalog cross-validated vs sigminer/MP toys | 09(M0), 10 | 2–3 d |
| U-M1s-12 | `ms_extract()` single-method | the single-method KL extraction + `print/format` (the consensus-CV pipeline belongs to M2) | [engineering] the end-to-end smoke (a toy-data cosine within a reasonable band) | 11 | 2 d |
| U-M1s-13 | the golden-standard fixture infrastructure | the fixture generation scripts + the golden-file management + the refresh scripts (the PR-check-item linkage, A15) | [engineering] the fixtures reproducibly generated | 05 | 1 d |
| U-M1s-14 | the one-off KL cross-check | the fixed-platform experiment vs R NMF brunet, `‖ΔW‖/‖W‖<1e-10` | [equivalence] the report lands in the devlog/ADR, **not entering the CI gate** (D11/A8) | 02 | 1 d |

**The v0.1 release gate** (the ROADMAP's original wording): the catalog generation ≥50× SPMG (the hardware-pinned bench; the CI carries only the <5s sanity bound); the NMF ≥100× R NMF; all fixtures green; installable from r-universe; the CAPABILITY-MATRIX's M1s-related rows updated; NEWS + the GitHub Release.

## 4. The medium-granularity units of v0.2 / v1.0 (refined against the then-current state before starting; the dependency graph updated at that time)

### 4.1 v0.2 (a further ~12 weeks)

**M1c · the catalog completeness + ID83 (3 weeks)**

| ID | Unit | The acceptance essentials |
|---|---|---|
| U-M1c-01 | ID83 (the bit-for-bit replication of the SPMG semantics: the repeated walk / the MH forward-priority / the capping / the Q rule) + the ID83 golden | [bit-for-bit] |
| U-M1c-02 | the GMM stratifier `ms_stratify_hypermutants()` (the classification + the de novo exclusion + the forced refit, A18) | [engineering] + the stratification-scenario tests |
| U-M1c-03 | the CN input and the CN48 feature space (the `ms_segments()` allele-specific caller mapping; the CAPABILITY-MATRIX L-A/L-B M1c rows) | [bit-for-bit] the CN48 labels |
| U-M1c-04 | the SV input and SV32 (the `ms_sv()` BEDPE/SV VCF + the `catalog/pcf.rs` exactPcf clustered; the matrix M1c row) | [bit-for-bit] the SV32 labels |

**M2 · the unified extraction pipeline (5 weeks)**

| ID | Unit | The acceptance essentials |
|---|---|---|
| U-M2-01 | `engine/consensus.rs`: the cosine distance + the rectangular Hungarian + the explicit split/merge semantics for the unmatched (compatible with the Islam threshold sweep, A10) | [engineering] the Hungarian brute-force cross-check |
| U-M2-02 | the SUITOR CV as an optional switch (the folds taken by sequence modulo + the conditional-mean imputation semantics [bit-for-bit]) + the `ms_select_k()` default adjudication rule documented and implemented (the CV argmin → the stability veto → the Wilcoxon diagnostic-only, A10) | the adjudication-rule document = the contract |
| U-M2-03 | the `ms_extract()` default consensus-CV pipeline assembly (the stratification → the ensemble → the consensus → the adjudication → the NNLS refit; the Wilcoxon diagnostic-only) | the end-to-end tests |
| U-M2-04 | `ms_ard()` (the SignatureAnalyzer ARD, in Rust) | [engineering] + the degeneration tests |
| U-M2-05 | `ms_sparse()` (the volume-regularised mvNMF + L1, in Rust) | [engineering] |
| U-M2-06 | the registry table wired for MsNmf/MsArd/MsSparse + all contract tests passing + `vignettes/extending.Rmd` | the third-party extension path walkable |
| U-M2-07 | the end-to-end synthetic tests (cosine>0.95) + the Islam 2022 protocol reproduction (the greedy max-cosine ≥0.90) | [bit-for-bit] the protocol steps |

**M3a · the fitting three methods + bootstrap (4 weeks)**

| ID | Unit | The acceptance essentials |
|---|---|---|
| U-M3a-01 | `engine/likelihood.rs`: the multinomial/NB LL + the ϵ stepping + the χ²₁ LRT + Fisher (the interior support only) | [engineering] |
| U-M3a-02 | `ms_fit()` three methods: nnls / likelihood_bidirectional (the MuSiCal semantics) [equivalence: the numerical trajectory] / lrt | the two-layer annotation, per-method acceptance |
| U-M3a-03 | `ms_fit_bootstrap()` (Rust parallel) + `ms_test_presence()` (the NB χ²₁ LRT + BH) | the seed determinism + the cross-thread consistency |
| U-M3a-04 | QP / em / the exposure-sparsification zeroing rules (the matrix L-D v0.2 row) | [engineering] |
| U-M3a-05 | the per-mutation assignment + the unassigned-residual pseudosignature + the TSB test + the de novo→catalog decomposition annotation (the matrix L-D/L-E v0.2 rows) | [engineering] |
| U-M3a-06 | refdb v1: the bundled human SBS/DBS/ID + the precedence/schema_version/manifest/build_independent governance (A13) | the fixture-ised update path, zero networking during checks |

**The v0.2 acceptance gate**: the Jiang-protocol benchmarking (an activity>0 match + the Combined Score) lands in the first tier's reasonable band; refdb v1 released; the matrix updated.

### 4.2 v1.0 (a further ~3–4 months)

**M3b · the MSU-Fit calibration statistics (6 weeks; the G2 gate must be reached within this period)**
- U-M3b-01 the three estimand layers landed (D13/A1): the presence LRT / the support-conditional absolute exposure CI (BCa or the layered calibrated-percentile) / the zeroing compound coverage.
- U-M3b-02 the multinomial + NB dual generative-model calibration: the coverage × N × Shannon curves; the Fisher interior intervals; the real-data downsampling sanity protocol.
- U-M3b-03 the G0 outcome written into the narrative decision (the Framing A/B ADR finalised).

**M4 · the similarity calibration library + viz (3 weeks)**
- U-M4-01 the `ms_compare()` calibrated-similarity library: the multi-metric + the analytic/empirical null distributions + the Hungarian primary metric / Islam greedy / Jiang activity three-protocol reference implementations [bit-for-bit].
- U-M4-02 `ms_qc_report()` + `ms_downsample()` + the first batch of `ms_import/ms_export` (the SigProfiler txt / the COSMIC txt / the WTSI long format).
- U-M4-03 the first viz batch of 8 figure types (the COSMIC palette, the canonical order, vector output) + the first exposure-UMAP version + `ms_convert()`.

**M6s · the HRD workflow (3 weeks; the scope-safety contract in force, A12)**
- U-M6s-01 `ms_hrd_report()`: the HRDetect coefficient mode **WGS-only** + the allele-specific CN caller whitelist (Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA) + WES marked experimental + the reference-fidelity test (the coefficients [bit-for-bit]) + the uncertainty reporting.

**M7 · the benchmark completeness + the paper (8–10 weeks)**
- U-M7-01 the full scenario grid (ARCH §8 upgraded edition) + the calibration/selection/evaluation three-layer scenario isolation + the protocol freeze shipped with the package.
- U-M7-02 the competitor-container harness (`bench/` only) + the hardware-pinned bench full table + `ms_benchmark()` end-to-end.
- U-M7-03 the paper draft (the headline per the G0 Framing ADR) + the renv/Docker/seed one-command reproduction + the bioRxiv co-posting.
- U-M7-04 the full pkgdown site + the MSU↔function mapping table + CITATION + the performance-anchoring documentation.

**M8 · the release engineering**
- U-M8-01 (the M8a materials week): the cargo vendor final review + r-universe + the GitHub Releases binaries + the nf-core module PR.
- U-M8-02 (M8b, a wall clock of 4–8 weeks rolling): the CRAN submission and its iteration.

**The v1.0 acceptance gate**: the CRAN submission launched; the paper's three pillar materials (the architecture / the performance / the applications) all prepared (ARCH §10).

## 5. The G gates and the kill criteria schedule (the author's own actions, not delegable to the team)

| The gate | The timing | The action | The outcome/decision |
|---|---|---|---|
| **G0** | **immediately (W1–W2, in parallel with M0)** | the pilot coverage experiment: the nominal vs actual coverage of 2 competing tools × the TMB grid. The default tool candidates are MuSiCal / SigProfilerAssignment, finalised at the protocol freeze by the signature-expert brief | the G0 report + the **Framing A/B ADR**; preceding all paper-narrative writing (the precondition of U-M7-03) |
| **G1** | within M1s (≤W6) | the co-maintainer candidate list and the invitations (the threefold need: the bus factor + CRAN + reviewers) | the DESCRIPTION co-maintainer landed; unmet = a kill criterion |
| **G2** | during / before the close of M3b | the statistics co-author (the conformal/CoDA theory) + the clinical/cohort collaborator (the treatment records / RNA-only / FFPE panel, one of the three) locked in | the collaboration agreement; otherwise the case study is destined to be decorative and the GB/NC ceiling is actively accepted |
| **G3** | each quarter (the next ~2026-12) | the competitive-landscape re-review (the Cornet/MuSiCal/SPA dynamics) + the kill-criteria re-estimation | the review memo lands in the devlog |

**The kill criteria** (ARCH §10; any one triggers → stop the current track, report the pivot options to the user): the pilot experiment falsifies; Cornet formally publishes and presses down the correlation component; no cohort collaboration before M3b; a competitor releases calibrated CIs; the slippage >100%; no co-maintainer.

## 6. The kickoff checklist (act in week 1)

> [2026-10-13] Week-1 kickoff snapshot; boxes intentionally left unchecked as authored. These gates/units are tracked authoritatively in [docs/ROADMAP.md](ROADMAP.md) (M0 checklist rows, G-gate schedule rows, the G0 row) — the ROADMAP supersedes this checklist.

- [ ] **the G0 protocol frozen and kicked off** (the author + the signature expert; a two-week window, the outcome written into the Framing ADR)
- [ ] **U-M0-01 the scaffolding** + **U-M0-02 the spike** (the spike's W1 hard deadline -- the vendor numbers determine every subsequent build decision)
- [ ] U-M0-08 the governance files + U-M0-10 the ADR directory migration (no code dependency, immediately parallel)
- [ ] the G1 co-maintainer candidate list started (an author calendar item)
- [ ] `docs/devlog/` established when the first work unit starts (the first devlog = U-M0-01)
