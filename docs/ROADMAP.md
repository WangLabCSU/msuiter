# msuiter roadmap (ROADMAP) -- v3 (dual-track versioning + organizational action gates)

> v3 (2026-09-28): restructured per the five-expert review adjudication
> ([reviews/00-synthesis.md](reviews/00-synthesis.md)) -- the original M0-M8
> estimates were systematically underestimating by ~3x and carried no
> minimal-shareable-version cut line; this revision adopts the **dual-track
> versioning scheme** and makes the organizational action items that require
> the author's own push explicit as the G-gates.
> Principles unchanged: every deliverable is in releasable state; TDD first;
> the three paper pillars are bound to milestones.
> Executable decomposition (work units / dependency graph / v0.1 week-by-week
> schedule / G-gate actions / kickoff checklist):
> [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md).

## Version-track overview

| Version | Duration (realistic estimate) | Content | Release |
|---|---|---|---|
| **v0.1** | ~6 weeks | minimal usable core (see M0+M1s) | r-universe + GitHub Releases |
| **v0.2** | further ~12 weeks | complete SBS/DBS/ID method chain | r-universe |
| **v1.0** | further ~3-4 months | MSU-Fit calibration + HRD reporting + release engineering | CRAN submission launched |
| **v1.x** | rolling | see the "deferred list" | rolling |

Honest total for one person + AI agents: **~12-18 months to submission-grade
benchmark completeness** (editorial review #3).

## Organizational action gates (G-gates -- non-documentation work, author-driven)

- **G0 (immediately, 2 weeks)**: leading coverage experiment -- nominal vs
  actual coverage of 2 competing tools x the TMB grid. **Kill-criterion
  gate**: the outcome decides whether the paper headline runs Framing A
  (calibrated statistics) or Framing B (ecosystem). Precedes all paper
  narrative writing.
- **G1 (before M1s)**: find a co-maintainer (needed threefold: bus factor +
  CRAN + reviewers).
- **G2 (during / before close of M3b)**: statistics co-author (conformal /
  CoDA theory) + clinical/cohort collaborator (treatment records / RNA-only /
  FFPE panel, one of the three) locked in; otherwise the case study is
  destined to be decorative and the GB/NC ceiling is actively accepted.
- **G3 (each quarter)**: competitive-landscape re-review (Cornet/MuSiCal/SPA
  dynamics), kill criteria re-estimated.

---

## v0.1 (~6 weeks)

### M0 -- engineering foundations (2 weeks; the original 0.5-1 week estimate was rejected by review)

- [x] rextendr scaffolding + Cargo workspace (shrunk dependency budget:
  extendr-api default-features=false, ndarray, rayon, memmap2; **no rand**)
- [x] **M0 spike (numbers within one week)**: real cargo vendor + xz byte
  counts + rustc 1.71 three-platform build proofs + the twobit two options
  (crate over Cursor\<Mmap\> vs self-developed) with byte-swap/big-endian
  validation -> ADRs (ADR 0001/0002; 0001/0002; macOS arm64 already proven, the
  Linux/Windows build proofs are carried by CI)
- [x] **S7 class skeletons (no .state)**: MsVariants/MsCatalog/MsSignature/
  MsFit/MsRefDb/MsEngine/MsBenchmark; all cross-references are snapshot
  summaries; full-generic behavior tests after saveRDS/load (flat prefixed
  naming classes-*.R, see ARCH section 3.1 implementation note)
- [x] engine registry table (with certified/engine_version/contract_version
  fields) + contract test suite
- [x] `data-raw/build_channels.R` channel-registry single source of truth +
  docs-sync CI (drift goes red) (docs-sync script green; CI wiring handed
  over to U-M0-07)
- [x] **self-developed RNG module**: PCG64 + SplitMix64 stream layout +
  cross-version golden tests (canonical post-step pcg64; tools/rng-kat.py
  independent KAT)
- [x] `.github/`: 3 OS x {release, oldrel, R-4.3(Linux), devel} matrix,
  rcmdcheck --as-cran, cargo test/clippy/deny(ban)/audit,
  valgrind+ASAN scheduled, dependabot, codecov (U-M0-07 complete;
  `tools/ci-selfcheck.py` asserts every wiring, PASS)
- [x] governance files: CONTRIBUTING (incl. the third-party engine onboarding
  checklist), CoC, issue/PR templates (incl. the FFI-surface change and
  fixture-refresh check items), README skeleton, NEWS.md, `_pkgdown.yml`
  (U-M0-08 complete)
- [x] `ms_sitrep()`; FFI hard contracts landed (column-major / NA / Result
  errors / interrupts / per-call thread pools) (docs/ffi-surface.md frozen
  artifact + drift guard built)

**Acceptance**: check fully green; S7 validation tests pass; RNG golden
pass; the vendor size numbers land in the ADRs.

### M1s -- v0.1 engine and catalog (4 weeks; the full "engine and catalog" split into M1s/M1c/M2, with M1c/M2 continuing in v0.2)

- [x] engine: KL-MM MU, NNDSVDa (q>=3 + exact Gram-SVD cross-check),
  Lawson-Hanson NNLS (pivot LDLᵀ + KKT assertions), multinomial resampling,
  **thread-invariance identical() tests** (U-M1s-01-05; KL cross-check vs R
  NMF brunet PASS, ||deltaW||~1e-15)
- [x] catalog: SBS96/192/384/1536 + DBS78 + **MNV/complex routing module**
  (skip ledger) + 2bit fast path (U-M1s-06/07/08; SPMG source line-by-line
  cross-check + independent audit re-derivation)
- [x] golden-standard fixtures (**bit-for-bit semantics**): SPMG SBS/DBS/MNV
  cross-checks, sigminer/MP toy cross-validation (the SPMG cross-check =
  hand-derived golden + upstream source line-by-line reconciliation +
  two-sided layout pincer; the sigminer/MP toy cross-validation folded into
  the M1s acceptance bench)
- [x] `ms_variants/ms_tally/ms_extract` (single method) + `print/format`
  (U-M1s-09/10/11/12; the three rings of the workflow grammar through)
- [x] KL numerical-protocol equivalence cross-check: vs R NMF brunet (fixed
  platform, one-off experiment, tolerance 1e-10) (U-M1s-14 PASS:
  ||deltaW||F/||W||F ~ 1e-15, one-command reproduction in
  tools/kl-crosscheck)

**Acceptance (v0.1 release)**: ~~catalog generation >=50x SPMG; NMF >=100x
R NMF~~ -> **Plan-A calibration (PI adjudication 2026-10-05)**: the original
multipliers were written against an unmeasured baseline (brunet is already a
C kernel; SPMG on clean input is already vectorized); recalibrated against
the measured C baseline -- catalog 2.6x SPMG (3.73s, <5s ✓), NMF
2.3x R NMF brunet (C core), NNLS 1.8x scipy; the original 50x/100x/10x
rhetoric moved to the naive R/Python implementation caliber (the full-pipeline
dense arm at the SPMG 46s caliber would still support 50x; to be revisited
when the hardware-pinned bench lands). All fixtures green; installable from
r-universe. **M1s 14/14 ✅ closed.**

> Preserved ruling original (authoritative, verbatim):
> **验收（v0.1 发布）**：~~目录生成 ≥50× SPMG；NMF ≥100× R NMF~~ → **方案 A 口径（PI 裁决 2026-10-05）**：原倍数写于未实测基线（brunet 即 C 内核、SPMG 干净输入即向量化）；按实测 C 基线重校准——目录 2.6× SPMG（3.73s，<5s ✓）、NMF 2.3× R NMF brunet（C 核）、NNLS 1.8× scipy，原 50×/100×/10× 修辞移至朴素 R/Python 实现口径（全管线 dense 臂 SPMG 46s 口径 50× 或成立，钉硬件 bench 时复核）。夹具全绿；r-universe 可安装。**M1s 14/14 ✅ 关闭。**

---

## v0.2 (further ~12 weeks)

### M1c -- catalog completeness + ID83 (3 weeks)

- [x] ID83 (bit-for-bit replication of SPMG semantics: repeated walk / MH
  forward-priority / capping / Q rule) + ID83 golden (U-M1c-01; 38 golden +
  audit 2xP0 fixes + oracle cross-check; the design memo carries the
  parity=master/v1.3.6 both-hold evidence)
- [x] GMM stratifier (`ms_stratify_hypermutants` semantics landed)
  (U-M1c-02; source evidence overturned the popular narrative -- no log /
  no mean+2sd floor / upstream recalibrating everyone is our deliberate
  divergence; audit PASS)

### M2 -- unified extraction pipeline (5 weeks)

- [x] `ms_extract()` default pipeline (ensemble + consensus + **K-default
  adjudication rule** documented + refit); SUITOR-style CV as an optional
  switch (during v0.2); Wilcoxon diagnostic-only (U-M2-03;
  folds=10/seeds=10/replicates=8 divergences recorded)
- [x] explicit semantics for Hungarian-unmatched split/merge (compatible
  with the Islam threshold sweep) (U-M2-01 consensus.rs; the Islam-protocol
  reproduction is pinned in test-islam-xval.R)
- [x] engine registry wired for MsNmf/MsArd/MsSparse; contract tests all
  pass; `extending.Rmd` (U-M2-04/05/06: the ard/sparse/nmf trio certified
  and registered; extending.Rmd completed in the M2 closing batch)
- [x] end-to-end synthetic tests (cosine>0.95); Islam 2022 protocol
  reproduction (**bit-for-bit semantics**: greedy max-cosine >=0.90)
  (test-m2-e2e.R + test-islam-xval.R + bench/xval-m2 sigminer three-way
  mutual proof 0.99999+)

### M3a -- fitting three methods + bootstrap (4 weeks)

- [x] `ms_fit()`: nnls / likelihood_bidirectional (MuSiCal semantics,
  numerical-protocol equivalence) / lrt (U-M3a-02/03/04; the
  bootstrap/presence/assign/TSB/rescale/connected chain fully delivered)
- [x] `ms_fit_bootstrap()` (Rust parallel) + `ms_test_presence()` (NB chi2_1
  LRT + BH) (U-M3a-03; after the pooled-null-distribution P0 fix the whole
  calibration matrix lands in the judgment window, n=1..16)

**v0.2 acceptance (release)**: the Jiang-protocol benchmarking evidence is
delivered (bench/jiang, 4b3c8b4: the multinomial arm PASS -- CS min 2.72 >=
2.3 and aggregate specificity 0.864 >= 0.85; the nb8 stress arm passes CS at
2.41 while spec 0.743 does not pass -- attribution of the kappa=8 stress
value vs the bbaf042 per-tool calibration plus the two PI options are written
into result.md, **pending PI endorsement of the judgment basis**); refdb v1
delivered (U-M3a-06: the COSMIC v3.6 BSD-2 mirror pin ff61b0f
byte-verified bundled + precedence/schema_version/manifest governance + the
build_independent declaration, fully offline tests).

---

## v1.0 (further ~3-4 months)

### M3b -- MSU-Fit calibration statistics (6 weeks; **the G2 gate must be reached in this period**)

- [x] the three estimand layers landed: presence LRT / support-conditional
  absolute exposure CI (BCa) / zeroing compound coverage (U-M3b-01/02/03;
  the 198-cell calibration grid fully lands in the judgment window -- after
  the pooled-null-distribution P0 fix; the layered calibrated-percentile
  upgrade arm recorded in the M3b design memo; the G2 gate was not reached
  -- no co-author locked in, the GB/NC ceiling actively accepted)
- [x] dual generative models (multinomial + NB) calibration; coverage x N x
  Shannon curves; Fisher interior intervals; the real-data downsampling
  sanity protocol (U-M3b-02/04/05/06: calibrate.rs + the full
  ms_calibration_grid/verdict/plot/sanity chain, the final-review +
  confirmation-round audit closed at cf0751e)
- [x] **the G0 pilot experiment outcome written into the narrative decision**
  (Framing A vs B) -- blocked on the author-side COSMIC v3.6 catalog file
  (G0_CATALOG_PATH) -- the degraded-authority run closed out and recorded
  with adjudication verdict=A
  (bench/results/docker_degraded_pi_20261007-212438/judgment_degraded_20261008-013750.md:10;
  main@1dd50d1 #7)

### M4 -- similarity calibration library + viz (3 weeks)

- [x] **calibrated similarity library (`ms_compare()`, a framework
  component)**: multi-metric + analytic/empirical null distributions + the
  three-protocol reference implementations Hungarian primary metric / Islam
  greedy / Jiang activity (golden-standard tests) (U-M4-01,
  ca69806+cd67c71; the adversarial audit P1 stream-band collision + P2x6
  all fixed -- calibration anchor +1/(3m), type-7 <=2ulp, correlation guard;
  the Islam dual-caliber benchmarking proper = a PI adjudication item,
  recorded in memo section 8; the bench/jiang benchmarking pending)
- [x] sample QC report `ms_qc_report()` (burden-distribution / pseudosignature
  contribution first version -- mechanism sentinels gt/ct + the COSMIC
  pseudosignature name roster, 19 entries' share; amber/red faithful
  replication hourglass v1.x) + `ms_downsample()` (U-M4-02/02b,
  5f832cb+eeea14c audit closed)
- [x] format interoperability `ms_import/ms_export` (first batch: COSMIC txt
  done, SigProfiler txt done ([V] triple anchors + real-sample sha256
  pinned), signatures import face done (the validator 0-column exposure
  revision); the WTSI long format hourglass -- no upstream real sample, the
  [V] discipline deferred); `ms_convert()` exome<->genome opportunistic
  conversion done (U-M4-02c, 6e30982+eeea14c; opportunistic within the
  likelihood hourglass v1.x)
- [x] viz first batch of 8 figure types (the COSMIC palette byte-for-bit [V]
  + canonical order + vector) + the exposure embedding (UMAP/kmeans) first
  version + `ms_convert()` opportunistic conversion (exome done; the panel
  built-in table hourglass -- no [V] anchor; opportunistic within the
  likelihood hourglass v1.x) (U-M4-03, dca484a+4a133e9+35d712a audit
  closed: the render-path guard / error protocol / graphic correctness all
  fixed)

### M6s -- HRD workflow (3 weeks; the scope-safety contract in force)

- [x] `ms_hrd_report()`: **HRDetect coefficient mode, WGS-only**; allele-specific CN caller whitelist (Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA); WES mode marked experimental; the "reference fidelity test" (coefficients bit-for-bit); uncertainty reporting (evidence: R/hrd-report.R:222 export; man/ms_hrd_report.Rd; tests/testthat/test-hrd-reference.R; main@2fc7e04 #6)

### M7 -- benchmark completeness + paper (8-10 weeks)

- [x] full scenario grid (ARCH section 8 upgraded edition: purity / caller / co-adversarial / out-of-catalog / hypermutator arms / category-count intervals) + three-layer scenario isolation + protocol freeze (**the prerequisite design memo is frozen** docs/devlog/2026-10-05-benchmark-design-memo.md -- API / scenario axes / scoring contracts / acceptance anchors / PI adjudications D1+D2 adopted (TP-only) 2026-10-05 -- driver v1 delivered) (evidence: docs/devlog/2026-10-05-benchmark-design-memo.md:3 frozen entry; bench/results/docker_m7_degraded_20261009-184833/ the full 42-cell authoritative run; main@f90ea1d #13)
- [x] competitor-container harness (bench/ only); the hardware-pinned bench full table; `ms_benchmark()` end-to-end (evidence: bench/m7/competitor-container harness [U-M7-02 #10-#12, bench/ domain only]; NAMESPACE:21 `ms_benchmark` export + tests/testthat/test-ms-benchmark-driver.R + man/ms_benchmark.Rd; the hardware-pinned full table bench/results/docker_m7_degraded_20261010-202330/timings_sharded_master.csv 42 rows all ok, zero cached [authoritative single shot, shard pass with zero cache hits], reader validator rc=0 with an empty-bucket verdict, docs/devlog/2026-10-10-m7-hardware-pin.md, the "Fresh ignition -- verbatim attestation" section)
- [x] bootstrap-vs-sigminer authoritative campaign closed: the >=100x targets row MEASURED-false at 15.37x, tier B, secondary A1/A3 14.2209x (single authoritative ignition under the co-tenancy bar, data seal re-verified byte-identical) (evidence: bench/results/bootstrap_vs_sigminer_20261013T175859Z/result.md:4; docs/PERFORMANCE.md:68; bench/results/bootstrap_vs_sigminer_20261013T175859Z/witnesses/host_census.jsonl:1)
- [ ] paper draft (headline A or B per the G0 outcome) + renv/Docker/seed
  one-command reproduction + bioRxiv co-posting
- [ ] pkgdown full site + the MSU<->function mapping table + CITATION +
  performance-anchoring documentation

### M8 -- release engineering (M8a materials week + M8b CRAN iteration (wall clock 4-8 weeks rolling))

- [ ] cargo vendor final review + r-universe + GitHub Releases binaries +
  nf-core module PR + CRAN submission

---

## Deferred to v1.x (hard non-goals, review adjudication)

- the ID89/476 (Koh 2025) channels and PRRDetect -- deferred under the
  precondition of the mapping table first
- MSU-Infer extensions (DM hurdle / structural zeros, survival / longitudinal),
  MSU-LowCount (Mondrian conformal full scope)
- the correlation engine (kept or dropped by outcome once pre-registered
  falsifiable claims qualify; the five-modal display covers SBS+DBS only)
- mutational-rhythm analysis, the NTF tensor engine (exploratory),
  MsLda/MsSupervised, CN/SV fitting
- the RNA workflow (**conditional upgrade**: pulled forward when the G2
  cohort collaboration is RNA-only), therapy forensics
- Shiny / portal, deep learning, a native Bayesian backend (unchanged)

## Dependency graph and the G-gates

```
G0 (pilot experiment, immediately) ───────────────────┐ (outcome decides the paper headline)
M0 ─ M1s ─(v0.1)─ M1c ─ M2 ─ M3a ─(v0.2)
                 └─ G1 (co-maintainer)
                      M3b (incl. the G2 cohort gate) ─ M4 ─ M6s ─ M7 ─ M8 ─(v1.0)
G3 (quarterly competitive review) ───────────────────┘
```
