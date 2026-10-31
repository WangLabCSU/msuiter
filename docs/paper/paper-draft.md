# msuiter — manuscript spine (PP-1 draft)

> Lane artifact. Worktree `msuiter-wt/paper`, branch `feat/paper-draft` @ `b92c092`.
> Every sentence-bearing slot below is either **FILLED** from committed, measured
> evidence (each quoted number carries a byte-verifiable source anchor: `file:line`
> or a commit object) or an explicit `[GATED: <gate-name>]` decision block. No gated
> decision has been fished or invented anywhere in this file; the gate register
> (Appendix B) enumerates every gate and its unblock condition.
> Posture: the G2 gate was not reached — no co-author locked in — and the
> **Genome Biology / Nature Communications ceiling is actively accepted**
> (docs/ROADMAP.md:173-180; docs/reviews/05-nature-editor.md §1, §8-9).

---

## Candidate title slots

- Framing A stub: "Calibrated inference of mutational-signature exposures with an
  attestable compute substrate" — positioning per docs/ARCHITECTURE.md §10
  ("fast *so that* statistical honesty is affordable", verbatim there).
- Framing B stub: "msuiter: a bit-compatible, attested platform for five classes
  of mutational signatures" — platform claim per docs/CAPABILITY-MATRIX.md
  (the authoritative completeness checklist, its header).

> [GATED: G0-PRIMARY] The headline A-vs-B choice depends on the operator-gated G0
> primary run, which needs the author-side COSMIC v3.6 catalog file
> (`G0_CATALOG_PATH`; docs/ROADMAP.md:186-191; docs/ARCHITECTURE.md §8 G0 row
> — "the outcome decides whether the headline runs Framing A (calibrated
> statistics) or Framing B (the ecosystem)"). The degraded-authority pilot closed
> with adjudication verdict=A
> (bench/results/docker_degraded_pi_20261007-212438/judgment_degraded_20261008-013750.md:10,
> recorded at docs/ROADMAP.md:186-191), but that pilot does not license the
> headline. Until the primary run lands, no abstract or title slot may assert the
> coverage-validation headline, and the "first inference layer that measures the
> empirical coverage of exposure intervals" phrasing
> (docs/ARCHITECTURE.md §5, named-methods table, MSU-Fit row; mirrored at
> docs/reviews/05-nature-editor.md §2 item 1) may appear in this manuscript only
> inside a gated block such as this one — never in a filled slot.

---

## Abstract

[FILLED — structural frame; the two data-bearing claims are sealed and anchored;
the headline sentence is gated]

The calibration of exposure uncertainty is the field's own declared open question:
the community benchmarks that adjudicate mutational-signature tools report point
estimates and fitting quality but do not audit whether the reported interval
estimates cover at their nominal level (/tmp/noveltylane/novelty-scan-2026-10-30.md §2
E8 [M]-class records: the 12-tool fitting comparison of Medo et al.,
Nat Commun 2024, and the 13-tool attribution benchmark of Jiang et al.,
Brief Bioinform bbaf042 — both re-pinned at DOI pass, Appendix A/§9). msuiter
addresses this by making interval calibration *measurable and cheap*: an R package
with a two-tier Rust core whose numeric kernels are bit-reproducible by
construction, an isolated-process kernel boundary with a frozen, version-stamped
protocol, published RNG stream layouts, and a measurement-and-attestation regime
(single-authoritative-shot campaigns, sealed floor tables with epoch digests,
co-tenancy censuses, hardware-pinned rows, firing constructed controls) that lets
every speed and correctness claim in this paper resolve to committed witness bytes
(docs/PERFORMANCE.md:3-9 zero-fabrication design;
/tmp/noveltylane/novelty-scan-2026-10-30.md §3 item 2, the banked RB-10/P-1/G5
record).

> [GATED: G0-PRIMARY] The abstract's headline sentence — the coverage-validation
> result of the G0 primary run (nominal-vs-actual coverage over the competing
> tools × TMB grid) — is withheld until the operator-side `G0_CATALOG_PATH`
> unblocks the primary run (see the title-slot gate above).

[FILLED — measured-share sentences, each sealed]

Measured share reported here, all on the frozen synthetic regime (master seed
20260928, §4.7): the calibrated-inference faces (coverage grids, verdict windows,
sanity harness) ship as package API (docs/ARCHITECTURE.md §5 named-methods
table; R/calibrate.R face family `ms_calibration_grid` / `ms_calibration_verdict` /
`plot_calibration_curve` / `ms_calibration_sanity`, 198-cell calibration matrix
landed in-window, docs/ROADMAP.md:175-180); the isolated-process batch bridge
multiplies the product bridge face 2.3004x bit-identically (commit object
2296f49, message bytes); and the peer-parity audit of every R-family face against
the compiled yardstick re-measures 147/147 cells breaching the <=2x bar
(§3.3, Table 2 — the honest distance, not a claim of parity).

---

## 1. Introduction

[FILLED]

1. **The field's record.** Tool papers in this domain land in the specialty tier
   (the reviewer-side publication table: docs/reviews/05-nature-editor.md §1 —
   Cell Genomics, Genome Biology, PLoS CB, Brief Bioinform, Nat Commun), and the
   two flagship community benchmarks — the 12-tool fitting comparison and the
   13-tool attribution benchmark (Appendix §9, re-pinned records) — adjudicate
   extraction/fit quality without verifying exposure-interval calibration. That
   omission is the entry point of this work and is stated here only as the
   benchmarks' own posture, never as our novelty claim (the novelty claim proper
   is gated, Abstract/Title).
2. **What msuiter is.** One workflow grammar —
   `ms_variants() |> ms_tally() |> ms_extract() |> ms_fit() |> ms_compare()` —
   over SBS, DBS, indel, CNV, SV and RNA-SBS modalities, with a registry-swappable
   engine platform and the default path set to the self-calibrated methods
   (DESCRIPTION `Collate`/roster; docs/README.md:7 "the Seurat of mutational
   signatures" positioning; engine-registry doctrine D15/D16,
   docs/ARCHITECTURE.md §3.4, §5). The concept-to-API map is the committed
   MSU-MAP (docs/MSU-MAP.md, one row per exported NAMESPACE function, each row
   carrying its paper pillar and its peer counterpart or a recorded NONE reason).
3. **The thesis sentence.** msuiter's originality is architectural and evidential
   rather than algorithmic: it is the mutational-signature stack whose kernel,
   randomness, and measurements are individually attestable bit-for-bit — and the
   calibration audits that this makes affordable are the ones the field's own
   benchmarks declared missing
   (/tmp/noveltylane/novelty-scan-2026-10-30.md §3 one-sentence draft, cited
   as-is per lane law; its (a)-class labels carry the scan's own
   negative-search caveat and targeted re-scan requirement,
   novelty-scan §Method + §Integrity note 2).

## 2. Software overview

[FILLED — DRY law: this section cites the committed architecture corpus rather
than re-prosing it]

- **Two-tier Rust core.** Pure numeric kernels in `src/rust/engine` with
  `#![forbid(unsafe_code)]`, zero FFI, zero dependencies at the kernel tier;
  the FFI shell is the only `unsafe` surface; directionality
  `ffi -> catalog -> engine` is asserted by a committed link witness
  (`src/rust/engine/src/lib.rs:25-29` per the novelty-scan E1 row;
  frozen dependency budget and MSRV pin in `src/rust/Cargo.toml`);
  per-call thread pools, the global rayon pool never used (FFI contract 6).
  Narrative authority: docs/ARCHITECTURE.md §2, docs/README.md "Design pillars".
- **Determinism by construction.** Thread-invariance `identical()` laws,
  fixed-order reductions, published RNG stream layout `MSURNGV1` over
  (replicate, rank, fold) with cross-toolchain golden tests
  (`src/rust/engine/src/rng.rs` docs; novelty-scan §2 E4 [verdict (b)]).
- **Isolated-process kernel boundary.** The `msuiter-kernel` CLI wraps the
  *unmodified* engine kernels behind a frozen, version-stamped protocol-1 CSV
  contract with `%{:.17e}` bit-exact round-trip, one-time handshake, per-case
  receipt attestation, all-or-nothing batches, and an endpoints-trace production
  face (`src/rust/engine/src/bin/msuiter-kernel.rs` protocol docs:1-64;
  `R/kernel-pipeline.R` design laws 15-29; law families in
  tests/testthat/test-kernel-batch-bridge.R, test-kernel-trace-shape.R,
  tests/kernel_cli_protocol.rs).
- **Platform grammar.** Engine registry as *data, not a class explosion* with
  governance fields (`engine_version`, `contract_version`, `certified`);
  six-modality unified tally with two-tier bit-compat acceptance; refdb
  governance with the zero-COSMIC-numeric rule (D3) — authority:
  docs/ARCHITECTURE.md §3.4/§5-§7, docs/MSU-MAP.md, docs/CAPABILITY-MATRIX.md.

## 3. Results

### 3.1 Figure 1 — the coverage heat map

> [GATED: G0-PRIMARY] The Figure 1 data — nominal-vs-actual coverage-rate of the
> competing tools' exposure intervals across the TMB grid
> (docs/reviews/05-nature-editor.md §5: the figure that makes this a top-tier
> paper if real, and §9 kill-criterion 2: if the competitors' intervals turn out
> basically calibrated, the headline is falsified and Framing B takes over) — is
> produced only by the operator-gated G0 primary run (author-side
> `G0_CATALOG_PATH`). No cell values, axis ranges, or coverage percentages may be
> drafted into any filled slot before that run; the figure panel here carries the
> mechanism only.

[FILLED — the mechanism face of the figure, committed and executable today]

Figure 1 renders, on the frozen synthetic regime, the package's own
coverage-instrument face: the calibrated-percentile coverage curves of
`ms_calibration_grid()` over the N x entropy grid with the
`ms_calibration_verdict()` window, the `plot_calibration_curve()` face, and the
`ms_calibration_sanity()` real-data downsampling harness run under its
committed protocol (`inst/sanity/README.md` — and by that protocol's own law,
sanity is never written as calibration evidence). The 198-cell calibration
matrix (dual generative models, multinomial and NB) landed fully in the
judgment window (docs/ROADMAP.md:175-180, U-M3b-01/02/03), and the estimand
layering — presence via the pooled exact-Binomial(1/2)-mixture chi-square-null
LRT, support-conditional magnitude, separately measured zeroing coverage — is
the committed contract (docs/ARCHITECTURE.md §5, MSU-Fit row). The figure
caption's competitor-comparison half is the gated panel above.

### 3.2 Pillar 1 — architecture and implementation

[FILLED — DRY law: narrative rides the committed corpus; this sub-section adds
only the measured spine sentences and cites]

The implementation narrative is *not re-prosed here*; it is the committed
architecture corpus (docs/ARCHITECTURE.md §2-§7), the concept map
(docs/MSU-MAP.md), the capability checklist (docs/CAPABILITY-MATRIX.md), and the
design memos (docs/devlog/ 2026-09-28..2026-10-28, in particular the G0
protocol/protocol-memo trio 2026-09-28, the pipeline design memo 2026-09-30,
the M3b design memo 2026-10-04, the benchmark design memo 2026-10-05 whose
adjudications D1+D2 (TP-only judgment) are the benchmark's law
(docs/ROADMAP.md:229)). The originality scan
(/tmp/noveltylane/novelty-scan-2026-10-30.md, cited as-is) delivers the
per-element verdicts: no primitive in this stack is claimed as algorithmically
new (KL-MU, NNDSVD, Hungarian consensus, CV-K all carry (c)-prior-art findings,
§2), while the certified-compute combination (E1+E4+E5+E6) and the
attestation-regime-as-method (E6+E11) carry the (b)/(a) labels the scan's own
caveats attach to (negative searches pending a targeted re-scan;
novelty-scan §Method, §Integrity note 2).

Measured spine sentences citable today, all anchored:
- 822 new law expectations shipped with the batch-bridge/trace-face family
  (476 bit-identity + 346 batch-bridge; commit object 2296f49 message bytes;
  test files tests/testthat/test-kernel-bit-identity.R and
  test-kernel-batch-bridge.R).
- The whole R-side attestation law set is CI-resident as attested parallel
  shards against one committed manifest (docs/devlog/2026-10-21-ci-shard-parallel.md;
  docs/ARCHITECTURE.md §9 CI row).

### 3.3 Pillar 2 — performance and benchmark

[FILLED — sealed numbers only; every row below is byte-verifiable to its anchor;
rows are NOT parity claims]

Table 1 — sealed campaign verdicts.

| # | Quantity | Sealed value | Anchor (file:line / commit object) |
|---|---|---|---|
| 1 | bootstrap-vs-sigminer, 10^3 x 10^3, authoritative single shot | ratio 15.366x vs the pre-registered >=100x row — the row is **MEASURED-false**, never quotable as achieved | bench/results/bootstrap_vs_sigminer_20261013T175859Z/result.md:4 (`1.536600758177e+01`), :3 (tier B), :5 (verdict bytes "MEASURED-false 15.37x"); docs/PERFORMANCE.md:68,86-88; epoch label below |
| 2 | same campaign, pool-scaling isolation | secondary A1/A3 = 14.2209x | docs/PERFORMANCE.md:88 (verbatim from the same sealed outdir) |
| 3 | P-1 parity re-adjudication post-#53 (comparison-cosine arms vs compiled yardstick, N-grid) | **MEASURED-FALSE**, 23.728x–32.160x | commit object 8213192 message bytes ("P-1 parity verdict MEASURED-FALSE (23.7-32.2x)"); exact pair in the PR #53 body (https://github.com/WangLabCSU/msuiter/pull/53, mergedAt 2026-10-24T23:58:29Z, merge commit 8213192 — banked byte copy sha256 in the lane manifest); sealed original gate table bench/results/p6_regen_20261016-011928/result.md:6 (18 offending classes, 22.166–67.102) |
| 4 | NM-factorization yardstick (rust kernel vs R NMF/brunet, 400 fixed iters, 1 thread) | ratio_r_over_rust = 1.2323x | bench/results/p6_regen_20261016-011928/nmf_yardstick_authoritative.json:9 (`1.2323046734094532`); campaign ledger row bench/results/p6_regen_20261016-011928/result.md:14 |
| 5 | P10 batch bridge on the product bridge face | landing ratio A0/A3 = 2.3004x (per-k 2.74/2.43/2.19/2.04), **bit-identical** | commit object 2296f49 message bytes (measured block: A0 0.14060 s/run, A3 0.06112 s/run); lane bank /tmp/perf10lane/logs/20-p10c-measurement.txt:13 ("LANDING RATIO A0/A3 = 2.3004") |

Epoch discipline on quoted timings (post-cap witness law; the post-cap floor
epoch pins `f3e894a6933a2ffb`, bench/m7/tests/test_p6_floor_governance.py:156):
- rows 1-4 derive from campaigns ignited **before** the cap regime
  (2026-10-13 / 2026-10-16 / 2026-10-24) — each is quoted with its
  verdict-class and labeled **epoch-mismatched (pre-cap witness)**; none of
  them is presented as an attested post-cap timing, and none is a parity row.
- row 5 was measured under the sealed post-cap floor table — the commit's own
  probe recorded "floor_table_epoch f3e894a6933a2ffb unchanged".

Table 2 — O5 parity census, re-run in-lane (not a parity claim: the census).

The Phase-7 O5 face (`bench/m7/tools/parity_recompute.py`, committed by the
#55 lineage 309ab5b) re-reads every R-family face of the sealed floor table
against the compiled sigprofiler yardstick, per class, on the cpu basis, under
MEASURED-then-STATED and PATH-BINDING laws (witness bytes must equal table
bytes or the line is refused). In-lane re-run, this worktree, rc=0
(/tmp/paperlane/logs/o5_parity_recompute.txt): **faces=7 classes=21 lines=147
breaches=147 bar<=2.0x epoch=f3e894a6933a2ffb** — i.e. all 147 R-face x class
cells currently breach the hard <=2x bar against the compiled yardstick
(per-face cpu-basis ranges 13.4045–72.8837; best arms `sigminer_post_p1_rust`
and `sigminer_post_v3_rust`). The lane card's "147/147 <=2x breach list" is
this census; the per-row output carries both bound witness paths on every
printed ratio.

> [GATED: CAMPAIGN-R] No parity or Rust-headline sentence may enter the
> manuscript before the post-P10 full-table regeneration plus the real-data arm
> close the system-level <=2x row (novelty-scan guardrail R1; next-campaign
> ignition). Committed bytes today say BREACH verbatim (commit object 2296f49
> message: "The <=2x peer-parity row stays BREACH at the system level; this
> lane delivers its measured share toward the needed 6.7x, honestly."). The
> defensible present sentences are exactly the Table 1/Table 2 facts plus the
> forensics direction (pipeline-floor localization, docs/research/09 §9 and the
> P7-F five-gate rulings cited there).

Historical framing that may be quoted with its own honesty markers (already
committed): the pre-recalibration >=50x/>=100x/>=10x rhetoric was moved to the
naive-R/Python caliber by the PI ruling of 2026-10-05 and the M1s table measures
2.6x / 2.3x / 1.8x against already-optimized C-class baselines
(docs/PERFORMANCE.md:20-40; the pinned-host caveat rows docs/PERFORMANCE.md:111-130
apply — single developer machine, power state not controllable).

### 3.4 Pillar 3 — application case studies

[FILLED — the committed Phase-8 trio, PR #56 / commit object 5530af6; the
"forceful not decorative" standard is docs/reviews/05-nature-editor.md §4-5, and
the three-in-one cohort choice is exercised with its selection below]

- **CS-1 atlas mode** (`bench/scenarios/run_atlas.R`, #56): the six variant
  classes driven through the public ingestion face, the pipeline adjudicated
  against a-priori generator truth, evidence tables persisted under
  `bench/scenarios/out/` (counts_sbs/counts_dbs/association/presence/prevalence
  /compare_sweep ...); verdict discipline: "every claim is measured here, the
  final line is OVERALL PASS or OVERALL FAIL" (runner header bytes).
- **CS-2 HRD, dual-oracle byte-exactness** (`bench/scenarios/run_hrd.R`, #56):
  planted pLOH/aneuploidy truth adjudicated byte-exact against the verbatim
  Cortes-Castro dual oracles (`tests/testthat/helper-hrd.R` as the authority);
  the composite truth row calls HRD on exactly the double-positive sample;
  seeded reruns byte-identical; a missing arm table degrades to attestation,
  never fabrication (runner bytes :88-93).
- **CS-3 treatment forensics, `ms_treatment_report()`** (`bench/scenarios/run_treatment.R`,
  #56): governed therapy classes adjudicated against the officially recognised
  signatures with the clonal/subclonal timing split on the planted cohort;
  planted fidelity byte-exact, planted contrasts clear the committed adjudication
  floor, timing split additive on the association means; the runner's own
  `[attest]` lines declare the two open faces (no public ID83/CN/SV fit path;
  longitudinal relapse-pair differencing named but not fabricated). Design
  authority: docs/devlog/2026-10-28-p8-treatment-forensics-design.md.

[FILLED — three-in-one selection] Of the three editor-offered paths that turn the
case studies from decorative to forceful (docs/reviews/05-nature-editor.md §5:
(a) a treatment-history cohort with real treatment-record concordance; (b) an
RNA-seq-only cohort; (c) conformal validity on low-count panels with
diagnostic-grade MUTYH/MSI detection), this draft selects **(a) —
treatment-history cohort with treatment-record concordance**, because its
methodological machinery is the one already committed and law-tested (CS-3 is
its synthetic demonstration; the module itself carries the differentiation
posture "no mainstream tool offers a treatment-history reporting module",
docs/research/03-applications.md §3 via the runner's header citation).

> [GATED: G-GATE-COHORT] The *real*-data consequence the editor standard demands
> — one re-adjudicated published conclusion under calibrated uncertainty (the
> review's named candidate: the seven-HRD-methods-vs-FDA-assay disagreement
> re-adjudicated with calibrated intervals, docs/reviews/05-nature-editor.md §5),
> and the real treatment-record concordance for path (a) — requires a cohort
> collaboration that does not exist yet; docs/ARCHITECTURE.md §10 lists "no
> cohort collaboration before M3b" as a pivot trigger and the G2 gate was not
> reached (docs/ROADMAP.md:173-180). Pillar 3 as shipped is a
> methods-demonstration pillar, and the manuscript must describe it so
> (novelty-scan §4 R6 framing law); it may not be dressed as clinical evidence.
> Likewise byte-exactness bars in CS-2 are set against the team's own prior
> package ground truth and must be labeled that way until an independent
> reference lands (novelty-scan §4 R8).

### 3.5 Reproduction and the attestation regime

[FILLED] One-command reproduction engineering (renv lockfile, Docker image
recipes, seed regime banked, sealed-number verification faces) is specified,
dry-run-proven with attested rc codes, and manifested in
`docs/paper/reproduction-proof.md` with its tooling in `docs/paper/reproduce.sh`.
The regime itself — single authoritative shots under the RB-10 law, co-tenancy
censuses, sealed floor tables with epoch digests, per-row hardware pins,
firing constructed controls, MEASURED/UNMEASURED/FIRST-MEASUREMENT-ONLY
citation classes — is the committed `bench/m7` governance layer
(`bench/m7/tools/matrix_governance.py`, `attestation.py`, `verify_campaign.py`
as the shared oracle between harness and reader) and is this manuscript's
methodological originality record (novelty-scan §2 E11 [verdict (a) per
standing doctrine], §3 item 2).

## 4. Methods

### 4.1 Data and simulation regime
[FILLED] All benchmark and case-study data in this paper are synthetic, produced
by the frozen G0 simulator under the master seed 20260928 with per-cell seeds
banked in committed `Seeds.txt` files under `bench/results/*/` (zero-fabrication,
D3 law: zero COSMIC numeric matrices in any repository artifact —
docs/ARCHITECTURE.md §6.2; the bootstrap campaign's seed and shape bytes:
bench/results/bootstrap_vs_sigminer_20261013T175859Z/result.md:8-9).
The real-data G0 primary arm is gated (§3.1).

### 4.2 Kernels, protocols, law families
[FILLED] KL-MU/EU multiplicative-update NMF with division/log-guard-only epsilon
policy and fixed iteration counts; NNDSVD/NNDSVDa inits; exact one-sided Jacobi
SVD; correctness target vs R NMF/brunet ||dW||F/||W||F < 1e-10 fixed-platform
(one-shot, mirroring tools/kl-crosscheck); protocol-1 frozen CSV boundary and
batch bridge as §2; law families live in CI as attested shards
(docs/ARCHITECTURE.md §9; docs/devlog/2026-10-21-ci-shard-parallel.md).

### 4.3 Competitor containment and fairness
[FILLED] Competitor cells run containerized with committed Dockerfiles
(`bench/m7/adapters/Dockerfile.{sigminer,sigminer.tree,sigprofiler,nmf_yardstick}`,
`bench/g0/adapters/`), image inspect attestations committed with the campaign
(`bench/results/docker_m7_PILOT_20261008-200152/image_inspect_*.json`), frozen
thread caps per arm, single authoritative timed shot per heavy arm (RB-10),
co-tenancy witnesses with the load bar never relaxed
(`witnesses/host_census.jsonl` rows, docs/PERFORMANCE.md:99-102).

### 4.4 Scoring law
[FILLED] TP-only Hungarian adjudication (design-memo D1+D2,
docs/ROADMAP.md:229); the #53 cure put every scored column under an
invariance control (constructed-perfect scores perfect; de-novo predictions move
the number) after the name-keyed-join vacuity incident (PR #53 body bytes,
banked; commit object 8213192).

### 4.5 Calibration protocol (D13 four-piece kit)
[FILLED] generative model / estimand / coverage curve / sanity harness, per
docs/ARCHITECTURE.md §5 MSU-Fit row: dual multinomial+NB models, coverage as
curves over N x Shannon entropy, BCa or layered calibrated-percentile,
real-data downsampling sanity under inst/sanity/README.md (never written as
calibration evidence), Fisher intervals only at interior support.

### 4.6 Attestation and citation classes
[FILLED] MEASURED / UNMEASURED / FIRST-MEASURED-ONLY classes govern what this
paper may assert; the zero-fabrication design is structural —
docs/PERFORMANCE.md carries no independently retyped number, only
path:line-pinned quotations with re-extraction commands and integrity seals
(docs/PERFORMANCE.md:3-9, §Integrity seals).

### 4.7 Seed regime
[FILLED] Master seed 20260928 (G0 master) banked per campaign
(`Seeds.txt`, e.g. bench/results/bootstrap_vs_sigminer_20261013T175859Z/Seeds.txt);
per-case batch seeds `seed+i-1`; RNG streams under layout `MSURNGV1`; the
yardstick fixture pins its own seed 1234 and 400 fixed iterations
(bench/results/p6_regen_20261016-011928/nmf_yardstick_authoritative.json:3 and :14);
the full inventory is reproduced by the §3.5 tooling.

## 5. Related work and peer posture

[FILLED — peers (a)/(b) only] The two committed peer surfaces against which this
stack is measured are sigminer (CRAN; the R-family baseline arms and the HRD
ground-truth reference) and sigprofiler (the compiled yardstick face) — named
and quantified through Tables 1-2 and the O5 census, with the comparison
harness itself committed (bench/m7/adapters, registry in
bench/m7/competitors/registry.py listing the 7 R-family faces and the
python-basis yardstick). The field-landscape citations are the re-pinned
bibliography (§9), with the novelty scan's [M]/[U] tier honesty attached where
the scan has not itself re-verified on-page.

> [GATED: PI-C] The third competitor slot — peer (c), the signeR hypothesis — is
> UNVERIFIED by the PI record. Until the PI ruling lands, signeR stays a
> "comparison target pending ruling" and is not named as a peer in any filled
> sentence of this manuscript; peers (a) sigminer and (b) sigprofiler are the
> only quotable comparison identities. (Recorded posture: the novelty executive
> review lists the signeR ruling as pending,
> /tmp/noveltylane/executive-review-2026-10-31.md §2 item 2.)

## 6. Limitations and honest posture

[FILLED]
1. **Venue posture.** The G2 co-author gate was not reached; the GB/NC ceiling is
   actively accepted (docs/ROADMAP.md:173-180; the editor review's probability
   table, docs/reviews/05-nature-editor.md §8). This draft carries that posture:
   it makes no Nature/Nature-Methods claim.
2. **No parity row.** The <=2x peer-parity gate is measured BREACH and stays out
   of every table (§3.3 gate CAMPAIGN-R); the quotable performance content is the
   sealed verdicts and the O5 census.
3. **Synthetic-only.** Every number in this paper derives from the frozen
   synthetic regime (4.1); real-data columns arrive only with the gated G0
   primary and cohort work.
4. **One host.** The headline kernel measurements are pinned-host,
   power-state-uncontrolled single sessions, self-declared as such
   (docs/PERFORMANCE.md:111-130); campaign rows carry host/hw_profile pins so
   their machines are auditable from the tables alone.
5. **Ground-truth lineage.** CS-2's byte-exactness oracle is the team's own
   prior package (CRAN sigminer 2.3.3 lineage), labeled as such (novelty-scan
   §4 R8); an independent reference is named follow-up, not fabricated.
6. **Negative-search caveats.** The (a)-class originality labels in the novelty
   scan rest on the scan's self-declared flaky-backends environment and await a
   targeted re-scan (novelty-scan §Method, §Integrity notes 1-2); the executive
   review accepted the posture with exactly that caveat
   (/tmp/noveltylane/executive-review-2026-10-31.md §2 item 2).

## 7. Data and code availability

[FILLED] The package is the repository under `main`; all campaign bytes, witnesses,
floor tables, law tests, scenario runners and their outputs are committed
(`bench/`, `docs/`, `src/`, `tests/`); this manuscript's numbers resolve to the
Appendix A anchor registry; reproduction is the §3.5 one-command path
(`docs/paper/reproduce.sh`). Zero COSMIC numeric data is in any artifact (D3);
the reference database reaches users through the governed mirror path only
(docs/ARCHITECTURE.md §6.2).

## 8. Figure manifest (bioRxiv co-posting prep; upload itself is out of scope)

| Figure | Content | Status |
|---|---|---|
| Fig. 1 | Coverage heat map: mechanism panel (synthetic, committed faces, §3.1) | mechanism FILLED; competitor/TMB data panel [GATED: G0-PRIMARY] |
| Fig. 2 | Architecture block diagram (two-tier core, FFI shell, kernel CLI boundary) | to be drawn from docs/ARCHITECTURE.md §2 by the controller's illustrator; DRY law: no new claims |
| Fig. 3 | Table 1 as a visual verdict board (MEASURED-false rows shown as such) | data FILLED §3.3 |
| Fig. 4 | O5 census heat strip (7 faces x 21 classes, color=cpu-ratio) | data FILLED §3.3 Table 2 (log banked) |
| Fig. 5 | Scenario adjudication panels (CS-1 atlas, CS-2 dual-oracle, CS-3 treatment) | data FILLED §3.4, outputs bench/scenarios/out/* |
| Suppl. | Calibration curves 198-cell; reproduction protocol; law-family inventories | committed faces cited §4.5, §3.5 |

## 9. Bibliography

Only re-pinned records may carry a DOI. The re-pin pass (this lane, deliverable
3) verified every DOI against publisher metadata via Crossref/OpenAlex, with a
planted-DOI fabrication control that must trip the scanner (DS-1 idiom); the
per-DOI verdict census and sha256s live in the lane manifest. Records whose DOI
did not resolve are listed UNRESOLVED with their search-attested title/venue
metadata and carry no DOI here. [FILLED — pass run 2026-10-31; 37 of 54 records re-pinned to publisher
metadata (34 via the Crossref primary, the rest via the OpenAlex fallback); 17
carry no DOI and are marked not-quotable. Census bytes:
docs/paper/doi-repin-census.tsv (regenerator docs/paper/doi_repin_scan.py;
planted-DOI controls fired on this run:]

The re-pin pass speaks its own evidence:
```
CENSUS docs/paper/doi-repin-census.tsv rows=54 not-verified=17 controls=fired:True
```

| # | record (registry title, re-pinned) | identifier | status |
|---|---|---|---|
| B01 | Undifferentiated Sarcomas Develop through Distinct Evolutionary Pathways | https://doi.org/10.1016/j.ccell.2019.02.002 | VERIFIED (meta) |
| B02 | Topography of mutational signatures in human cancer | https://doi.org/10.1016/j.celrep.2023.112930 | VERIFIED (title+meta) |
| B03 | SVD based initialization: A head start for nonnegative matrix factorization | https://doi.org/10.1016/j.patcog.2007.09.010 | VERIFIED (title+meta) |
| B04 | New SVD based initialization strategy for non-negative matrix factorization | https://doi.org/10.1016/j.patrec.2015.05.019 | VERIFIED (title) |
| B05 | Joint majorization-Minimization for nonnegative matrix factorization with the beta-divergence | https://doi.org/10.1016/j.sigpro.2023.109048 | VERIFIED (meta) |
| B06 | Uncovering novel mutational signatures by de novo extraction with SigProfilerExtractor | https://doi.org/10.1016/j.xgen.2022.100179 | VERIFIED (title+meta) |
| B07 | Reconstructing evolutionary trajectories of mutation signature activities in cancer using TrackSig | https://doi.org/10.1038/s41467-020-14352-7 | VERIFIED (title+meta) |
| B08 | Using sigLASSO to optimize cancer mutation signatures jointly with sampling likelihood | https://doi.org/10.1038/s41467-020-17388-x | VERIFIED (title+meta) |
| B09 | Learning mutational signatures and their multidimensional genomic properties with TensorSignatures | https://doi.org/10.1038/s41467-021-23551-9 | VERIFIED (title+meta) |
| B10 | CloneSig can jointly infer intra-tumor heterogeneity and mutational signature activity in bulk tumor sequencing data | https://doi.org/10.1038/s41467-021-24992-y | VERIFIED (title) |
| B11 | Machine learning-based tissue of origin classification for cancer of unknown primary diagnostics using genome-wide mutation features | https://doi.org/10.1038/s41467-022-31666-w | VERIFIED (title+meta) |
| B12 | A comprehensive comparison of tools for fitting mutational signatures | https://doi.org/10.1038/s41467-024-53711-6 | VERIFIED (meta) |
| B13 | Patterns of somatic structural variation in human cancer genomes | https://doi.org/10.1038/s41586-019-1913-9 | VERIFIED (meta) |
| B14 | The repertoire of mutational signatures in human cancer | https://doi.org/10.1038/s41586-020-1943-3 | VERIFIED (meta) |
| B15 | Pervasive lesion segregation shapes cancer genome evolution | https://doi.org/10.1038/s41586-020-2435-1 | VERIFIED (title+meta) |
| B16 | Signatures of copy number alterations in human cancer | https://doi.org/10.1038/s41586-022-04738-6 | VERIFIED (title+meta) |
| B17 | A pan-cancer compendium of chromosomal instability | https://doi.org/10.1038/s41586-022-04789-9 | VERIFIED (title+meta) |
| B18 | The evolution of lung cancer and impact of subclonal selection in TRACERx | https://doi.org/10.1038/s41586-023-05783-5 | VERIFIED (title) |
| B19 | Strand-resolved mutagenicity of DNA damage and repair | https://doi.org/10.1038/s41586-024-07490-1 | VERIFIED (title+meta) |
| B20 | Detecting the mutational signature of homologous recombination deficiency in clinical samples | https://doi.org/10.1038/s41588-019-0390-2 | VERIFIED (meta) |
| B21 | Accurate and sensitive mutational signature analysis with MuSiCal | https://doi.org/10.1038/s41588-024-01659-0 | VERIFIED (title) |
| B22 | Single-mitosis dissection of acute and chronic DNA mutagenesis and repair | https://doi.org/10.1038/s41588-024-01712-y | VERIFIED (meta) |
| B23 | A redefined InDel taxonomy provides insights into mutational signatures | https://doi.org/10.1038/s41588-025-02152-y | VERIFIED (title+meta) |
| B24 | Comprehensive repertoire of the chromosomal alteration and mutational signatures across 16 cancer types | https://doi.org/10.1038/s41588-025-02474-x | VERIFIED (title+meta) |
| B25 | Accuracy of mutational signature software on correlated signatures | https://doi.org/10.1038/s41598-021-04207-6 | VERIFIED (title) |
| B26 | A practical framework and online tool for mutational signature analyses show intertissue variation and driver dependencies | https://doi.org/10.1038/s43018-020-0027-5 | VERIFIED (title+meta) |
| B27 | MutSignatures: An R Package for Extraction and Analysis of Cancer Mutational Signatures | https://doi.org/10.1101/2020.03.15.992826 | VERIFIED (title) |
| B28 | Abstract 211: Integrative mutational signature portal (mSigPortal) for cancer genomic study | https://doi.org/10.1158/1538-7445.am2021-211 | VERIFIED (title+meta) |
| B29 | A Dirichlet-multinomial mixed model for determining differential abundance of mutational signatures | https://doi.org/10.1186/s12859-025-06055-x | VERIFIED (title) |
| B30 | BASCULE: bayesian inference and clustering of mutational signatures leveraging biological priors | https://doi.org/10.1186/s13059-025-03835-9 | VERIFIED (meta) |
| B31 | SUITOR: Selecting the number of mutational signatures through cross-validation | https://doi.org/10.1371/journal.pcbi.1009309 | VERIFIED (title+meta) |
| B32 | Robust discovery of mutational signatures using power posteriors | https://doi.org/10.1371/journal.pcbi.1014372 | VERIFIED (meta) |
| B33 | mSigSDK -- private, at scale, computation of mutation signatures | https://doi.org/10.48550/arxiv.2308.02995 | VERIFIED (title) |
| B34 | Mutational Signatures Using Neural Networks for Robust Stratification of Cancer Patients | https://doi.org/10.54337/aau815838821 | VERIFIED (title) |
| B35 | SigFormer: an Attention-Based Framework for Robust Single-Sample Mutational Signature Decomposition | https://doi.org/10.64898/2026.01.20.700228 | VERIFIED (title+meta) |
| B36 | Correlation-aware discovery of co-occurring mutational signatures in cancer | https://doi.org/10.64898/2026.09.14.751548 | VERIFIED (title+meta) |
| B37 | Supervised mutational signatures for obesity and other tissue-specific etiological factors in cancer | https://doi.org/10.7554/eLife.61082 | VERIFIED (meta) |
| B38 | Advanced methods for two-class pattern recognition problem formulation for minutiae-based fingerprint verification | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B39 | Somatic ERCC2 mutations are associated with a distinct genomic signature in urothelial tumors | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B40 | (no registry title recovered) | [DOI UNPINNED: NOT-RESOLVED] | not quotable |
| B41 | Deep Unfolding for Non-Negative Matrix Factorization with Application to Mutational Signature Analysis | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B42 | On the Relation Between Linear Autoencoders and Non-Negative Matrix Factorization for Mutational Signature Extraction | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B43 | (no registry title recovered) | [DOI UNPINNED: NOT-RESOLVED] | not quotable |
| B44 | Bayesian Multi-Study Non-Negative Matrix Factorization for Mutational Signatures | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B45 | Benchmarking 13 tools for mutational signature attribution, including a new and improved algorithm | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B46 | BASCULE: Bayesian inference and clustering of mutational signatures leveraging biological priors | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B47 | sigfit: flexible Bayesian inference of mutational signatures | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B48 | CANCERSIGN: a user-friendly and robust tool for identification and classification of mutational signatures and patterns in cancer genomes | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B49 | (no registry title recovered) | [DOI UNPINNED: NOT-RESOLVED] | not quotable |
| B50 | MSA: reproducible mutational signature attribution with confidence based on simulations | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B51 | Model selection and robust inference of mutational signatures using Negative Binomial non-negative matrix factorization | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B52 | MutationalPatterns: the one stop shop for the analysis of mutational processes | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B53 | MutationalPatterns: comprehensive genome-wide analysis of mutational processes | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
| B54 | Bayesian selection and refitting of reference mutational signatures in cancer genomics | [DOI UNPINNED: TITLE-DRIFT] | not quotable |
Unpinned records stay out of every DOI-bearing sentence of this manuscript;
where the text needs one of them it names the search-attested title/venue only.


## Appendix A — Anchor registry

Every number quoted in a filled slot, with its byte-verifiable anchor:

| Value | Anchor | Re-derivation command |
|---|---|---|
| 15.366 (ratio bytes 1.536600758177e+01) | bench/results/bootstrap_vs_sigminer_20261013T175859Z/result.md:4 | `sed -n '4p' <file>` |
| tier B / verdict bytes | same file :3, :5 | `sed -n '3p;5p' <file>` |
| 14.2209 | docs/PERFORMANCE.md:88 | `sed -n '88p' docs/PERFORMANCE.md` |
| 23.728–32.160; "MEASURED-FALSE (23.7-32.2x)" | commit object 8213192 (message bytes) + PR #53 body (banked sha256 in manifest) | `git show -s --format=%B 8213192`; `gh pr view 53 -q .body` |
| 22.166–67.102, 18 offending classes | bench/results/p6_regen_20261016-011928/result.md:6 | `sed -n '6p' <file>` |
| 1.2323 (bytes 1.2323046734094532) | bench/results/p6_regen_20261016-011928/nmf_yardstick_authoritative.json:9 | `sed -n '9p' <file>` |
| 2.3004 (A0 0.14060, A3 0.06112 s/run) | commit object 2296f49 (message bytes) + /tmp/perf10lane/logs/20-p10c-measurement.txt:13 | `git show -s --format=%B 2296f49` |
| O5 census faces=7 classes=21 lines=147 breaches=147 | live re-run bank /tmp/paperlane/logs/o5_parity_recompute.txt (rc=0) | `cd bench/m7 && python3 -m tools.parity_recompute` |
| epoch pin f3e894a6933a2ffb | bench/m7/tests/test_p6_floor_governance.py:156 | `sed -n '156p' <file>` |
| 476+346 law expectations; 364/364 m7 tests | commit object 2296f49 (message); live re-run bank /tmp/paperlane/logs/m7-tests-run-all.txt (rc=0, "364/364 tests passed.") | `cd bench/m7 && python3 -m tests.run_all` |
| 198-cell grid landed | docs/ROADMAP.md:175-180 | `sed -n '175,180p' docs/ROADMAP.md` |
| master seed 20260928 | bench/results/bootstrap_vs_sigminer_20261013T175859Z/result.md:8; per-campaign `Seeds.txt` | `sed -n '8p' <file>` |

## Appendix B — Gate register

| Gate | Blocks | Unblock condition |
|---|---|---|
| G0-PRIMARY | abstract headline, title choice A-vs-B, Fig. 1 data panel, any "first coverage-measured intervals" phrasing | operator-side G0 primary run (author-side `G0_CATALOG_PATH`; docs/ROADMAP.md:186-191) |
| CAMPAIGN-R | any parity/Rust headline sentence, any <=2x PASS row | post-P10 full-table regeneration + real-data arm (next-campaign ignition; novelty-scan §4 R1) |
| PI-C | naming peer (c) / signeR as a comparison target | PI ruling on the signeR hypothesis (executive-review pending item) |
| G-GATE-COHORT | real-cohort treatment concordance, re-adjudicated published conclusion, clinical framing of pillar 3 | cohort collaboration (docs/ARCHITECTURE.md §10 pivot trigger; G2 unreached per docs/ROADMAP.md:173-180) |

*End of spine.*
