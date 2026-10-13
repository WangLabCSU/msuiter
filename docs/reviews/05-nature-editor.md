# The review 05: the Nature journal-editor perspective (an independent assessment, 2026-09-28)

> The reviewer persona: a senior editor responsible for computational-biology method papers (a Nature/Nature Methods perspective), desk assessment, honesty first.
> **The one-sentence overall assessment: this project's research quality and engineering hygiene are in the top 5%, but packaged as it currently is amounts to playing a hand of good cards at Genome Biology odds.**

## 1. Venue: the adjudication (the conclusion first)

**Executed as currently planned, this is not a Nature paper, and most likely not a Nature Methods paper either. It is (if written well) a Genome Biology or Nature Communications paper.**

The field's own publication record (more convincing than any argument):

| The flagship tool/method | The actual publication destination |
|---|---|
| MuSiCal | Nat Genet 2024 |
| SigProfilerExtractor | Cell Genomics 2022 |
| SigProfilerMatrixGenerator | BMC Genomics 2023 |
| PASA/mSigAct | Brief Bioinformatics |
| SUITOR | PLoS Comput Biol |
| BASCULE | Genome Biology 2025 |
| The Medo benchmark | Nat Commun 2024 |
| Cornet | bioRxiv (2026-09, still a preprint) |
| PCAWG/Degasperi/Everall | Nature/Science/Nat Genet (**discovery papers**) |

The pattern: **in this field, Nature/NG goes to the discovery papers; the tool and method papers land in Cell Genomics, Genome Biology, PLoS CB, Brief Bioinform, Nat Commun.** The "architecture/performance/applications" three-act structure is a Bioinformatics/Genome Biology structure — aligning the three-act with "Nature-grade" is a category error.

**The only statistical contribution big enough for the NM/NC narrative core: the MSU-Fit / MSU-LowCount / MSU-Infer cluster — "exposure inference’s calibrated statistics".**

## 2. The novelty-tier ranking

1. **MSU-Fit: the first inference layer that performs empirical coverage-rate measurement on the exposure intervals** — the open question Medo 2024 left in black and white, with no incumbent occupying it; falsiable, benchmarkable. **The only contribution in the whole plan big enough for the top journal's narrative core.**
2. **MSU-LowCount: principled inference (conformal) for panel/ctDNA** — the real wilderness after SigMA, with the biggest clinical sample pool.
3. **MSU-Infer: the formal statistics of CoDA/differential abundance** — no competition, and it makes "the statistics of exposure" a complete subject.
4. The five-modality end-to-end + the Catalog IR + the versioned refdb — a real ecological niche but of **Genome Biology grade**.
5. The Rust performance — real but worth only one "enabling" sentence; the Alexandrov group is moving toward matrix generation/QC, and a speed moat has a shelf life.
6. MSU-Extract — an engineering synthesis of the SigProfiler consensus + the SUITOR CV. Reviewer's one sentence: "engineering synthesis of SigProfiler and SUITOR, in Rust."
7. **MSU-Corr — the highest danger**. Cornet is the Park group's preprint from two weeks ago, and formal publication will most likely be NG/NM grade; it will be written up as "derivative of Cornet". Unless the five-modality joint makes a discovery Cornet cannot, demote it to a component.
8. MSU-Tempo/Tensor — application components, out of the abstract.

**The eight MSU-* names must be cut down to 2–3** — once a reviewer sees through one "wrapper", every name depreciates together.

## 3. The competitive positioning

- The four power centers (Alexandrov/Park/Rozen/Nik-Zainal) each guard their own wedge, and **the "integrated ecosystem" road is exactly the one they structurally will not walk** — no head-on competition, but also structurally low renown.
- **"exposure inference’s statistics" (the calibrated CIs, CoDA, the conformal low-count) is the middle ground none of the four groups has taken**: Rozen has the tests but no interval calibration, Park has the sparse point estimates but no coverage verification, DCEG only handles the K selection. This is the only high ground one can take first and, once taken, hold with defensive depth.
- Under the current plan, a reviewer **will** read msuiter as a "derivative of SigProfiler+MuSiCal engineering synthesis". The defense is not better engineering but having one thesis sentence nobody else has.
- The author is the sigminer author — a double-edged sword: credibility credit, but it will be read as "sigminer v3 redone in Rust". The paper narrative must make the statistics of MSU-Fit stand on its own independent of the author's prior work.

## 4. What the three-act framing lacks

1. **A tool-enabled discovery as the headline** — the Cornet preprint is itself the template (a method + "SBS92a tracks the ERCC2 platinum status"). The current application cases are all "run a workflow" on public data — decorative.
2. **Adoption/community evidence** — "will a domain PI switch pipelines tomorrow".
3. The framing opportunity: **speed is not the product, speed is the precondition that "calibrated statistics are affordable"** — the bootstrap/conformal/CV are all computation-hungry, and SigProfiler's day-scale runtimes make coverage-calibration studies de facto unaffordable. "We are fast *so that* we can afford statistical honesty" is a sentence no competitor has said and that is intrinsically self-consistent — write it into the abstract.

## 5. The top-journal evidence standards

- The benchmarking surface already meets the bar (the three-protocol bit-for-bit replication is rare). Note that PASA has already shown DBS/ID to be MuSiCal's soft ribs — attack there, and do not fight a draw against MuSiCal on SBS.
- **The calibration surface (what the headline needs)**: the nominal-vs-actual coverage-rate heat map of 13 tools × a TMB grid — **if the mainstream tools' "95% CI" really covers only 60–80% under clinical TMB, this figure is Nature Methods' Figure 1.** It must be made real, otherwise the narrative collapses.
- **The real-data consequence (currently wholly missing)**: the calibrated CI must change one published real conclusion (e.g.: the Nacer 2026 disagreement of the 7 HRD methods vs the FDA assay, re-adjudicated with calibrated uncertainty).
- Three-one choice to turn the case studies from decorative to forceful: (a) a treatment-history cohort + real treatment-record concordance; (b) an RNA-seq-only cohort (the matched DNA-RNA subset giving the concordance, the unmatched majority giving the new information); (c) the conformal validity on low-count panels + MUTYH/MSI diagnostic-grade detection.

## 6. The strategic risks, Top 8

| # | The risk | The severity | The mitigation |
|---|---|---|---|
| 1 | MSU-Corr gets crowded out by Cornet's formal publication | high | The five modalities are what Cornet lacks — if a multi-modality-unique result is produced within 12 months it stays, otherwise demote; promise nothing in the abstract |
| 2 | No discovery / no clinical consequence in the cases = a top-journal one-vote veto | high | Start the cohort collaboration (treatment records/RNA-only) at once, ahead of any code |
| 3 | Timeline fantasy (solo, realistically 12–18 months to submission) | high | Cut the scope; re-review the competitive landscape quarterly |
| 4 | The 8 MSU-* dilute the single true contribution | medium-high | Name only 2–3; demote the rest to features |
| 5 | bus factor = 1; without a statistics co-author the conformal/CoDA theory will be attacked | medium-high | Find a statistics co-author + a clinical/cohort collaborator + a co-maintainer |
| 6 | The "sigminer rewrite" perception | medium | Route the narrative around the sigminer lineage, standing on its own via the MSU-Fit statistics |
| 7 | The coverage calibration may falsify itself (the competitors' CIs may not be that bad) | medium | **kill criterion — spend two weeks first on the minimal coverage experiment (2 tools × a TMB grid) before writing any narrative** |
| 8 | The R-only audience is bounded; the COSMIC licensing | medium | A CLI + a parquet/arrow exchange layer makes it consumable by Python; the licensing is already prudent |

## 7. The candidate paper framings

- **A (the recommended main thrust) "Calibrated inference of mutational signature exposures"**: never one of the field's exposure intervals has been verified; the first complete inference layer of the LRT + the support-conditional bootstrap + the coverage calibration + the conformal low-count; the Rust performance makes the calibration feasible at cohort scale in minutes. Target: **Nature Methods (the sprint) / Nat Commun (the realistic landing)**. Figure 1 = the 13-tool × TMB coverage-rate heat map (a red wilderness) + the calibration curves.
- **B (the upgraded fallback) "A unified, bit-compatible ecosystem for five classes of mutational signatures"**: Target **Genome Biology (high probability) / NC**. Figure 1 = the capability-coverage matrix vs all competitors + the speed wall + the 12k WGS end-to-end.
- **C (the highest ceiling, needing collaborators) "Signature surveillance beyond WGS"**: principled inference for panel/ctDNA/RNA-only + real clinical cohort validation. Target: NC; if the clinical validation is strong, NM is in play. **The only path that can grow into a discovery story.**
- A+B can merge; A+C merging is the combination that maximizes the top-journal probability.

## 8. The probability estimates (the honest version)

| The journal | The current plan executed smoothly | The Framing A/C restructure + a real cohort |
|---|---|---|
| Nature Methods | ~5% | 15–25% |
| Nature Communications | 20–30% | 35–45% |
| Genome Biology | 50–60% | 60–70% |
| Bioinformatics (the floor) | 75–85% | same grade |

Nature/NG: only if Framing C grows into a real discovery paper does it enter the conversation.

## 9. Kill criteria / the pivot triggers

1. The extraction benchmark shows parity and not advantage → switch the headline to the Framing A calibrated statistics, with GB as the floor.
2. **The pilot coverage experiment shows the competitors' CIs are basically calibrated → the MSU-Fit headline is falsified → accept the Framing B, do not force-manufacture a difference.**
3. Cornet is accepted at NG/NM and extends to DBS/ID (before M5) → demote MSU-Corr.
4. Before the end of M3, no real cohort/clinical collaboration is locked → the case studies are destined decorative → proactively accept the GB/NC ceiling.
5. SPA/MuSiCal publish a calibrated CI/conformal → the gap closes → pivot to the application/discovery papers.
6. The M3 schedule slips >100% → cut CN/SV/Tensor/RNA, ship only the SBS/DBS/ID + the MSU-Fit core.
7. Persistently solo with no co-maintainer → find the co-maintainer before M1.
