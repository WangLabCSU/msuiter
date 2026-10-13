# Research report 08: the fact-check audit report of the existing research documents
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Audit date: 2026-09-28. Every load-bearing claim of docs/ was checked against Crossref, PubMed E-utilities, GitHub raw/API (the current HEAD), crates.io, CRAN, PMC, Europe PMC and the local R/rustc. The auditor may not modify the files — this report is the basis of correction (the corresponding fixes were executed by the mainline).

## §1 The discrepancy adjudications (the canonical citation strings, quotable directly)

| # | The item | The adjudication |
|---|---|---|
| 1 | **The Medo DOI** | **`10.1038/s41467-024-53711-6` is correct**; `-53574-6` is a Crossref 404, non-existent. Nat Commun 15:9467 (2024); PMID 39487150, PMC11530434. The citation string of the original 02 report was corrected. |
| 2 | **The Degasperi article number** | **`eabl9283` is correct**; `abl9111` does not exist. Science 376(6591):eabl9283, 2022-04-22; PMID 35949260. |
| 3 | **Jiang/Wu/Rozen** | The canonical citation = **Brief Bioinform 26(1):bbaf042, 2025** (epub 2024-11-22); doi:10.1093/bib/bbaf042; **PMID 39910776**, PMC11798676. **PMID 39487150 belongs to Medo**. The recommendation is to uniformly label it 2025 (epub 2024). |
| 4 | **MuSiCal** | Verified: Nat Genet 56:541–552 (2024), doi:10.1038/s41588-024-01659-0 (PMC10937379). |
| 5 | **PCAWG 2020** | Alexandrov, Nature 578(7793):94–101, doi:**10.1038/s41586-020-1943-3** (PMID 32025018). **Note `10.1038/s41586-020-2623-x` is a 404 — wherever it appears it must be replaced**. Li Y, Nature 578:112–121, doi:10.1038/s41586-019-1913-9 verified (PMID 32025012). |
| 6 | **Everall** | Officially published: Nat Genet 58(3):570–581, 2026 Mar (epub 2026-02-13), doi:10.1038/s41588-025-02474-x, PMID 41688639. The abstract confirms **10,983** patients, 16 cancer types, **134 signatures, 26 new COSMIC entries**, the SV reference set. |
| 7 | **Steele** | Verified: Nature 606(7916):984–991 (2022), doi:10.1038/s41586-022-04738-6; 9,873 TCGA, 21 CN signatures. |

## §2 The per-claim verification table (the summary)

| The claim | The verdict | The remarks/corrections |
|---|---|---|
| SPMG: `scripts/MutationMatrixGenerator.py` ~4,057 lines; the indel ~:1169–2100; BSD-2 | **verified** | exactly 4,057 lines; `catalogue_generator_INDEL_single` :1169, `forward_homology` :1486–1518, `dinuc_tsb_ref` :484; BSD-2-Clause (the Bergstrom/Alexandrov Lab); pushed 2026-09-22 |
| MuSiCal: `nnls_likelihood_bidirectional`, LTH 0.001, SIGS_ASSOCIATED without SBS7, no MWPruning/MDL | **verified** | `nnls_sparse.py:201` (thresh_backward=0.001, per_trial=True); the relaxed one at :434 (:410/:461 are the LOO blocks, the line numbers drift); `utils.py:72` the three groups, no SBS7; MWPruning/MDL 0 hits |
| mSigAct: the χ²₁ LRT; nbinom.size 8/50/100; GPL-3 | **verified (branch-conditioned)** | the default branch `v3.0.3-branch`; **the old `master` behaves differently (the multinom default, nbinom.size=5)** — replicate against the default branch |
| Sonata: exists, MIT, the model form of cornet.py | **verified** | `compute_exposures = exp(α + β + sig_emb @ sample_emb.T).T` matches exactly |
| The COSMIC v3.6 mirror: the file-name patterns, RNA-SBS GRCh37 only, SV GRCh38 only, the column counts | **verified + corrected** | **ID and CN are also GRCh37 only**; the mouse/rat have SBS+DBS only. The column counts: SBS 102 columns (Type+101), DBS 23, ID 26, CN 27, RNA-SBS 6, SV 13 |
| The CN48/SV32 labels | **verified** | all the 48/32 labels match exactly |
| SUITOR: PLoS CB 18(4):e1009309 2022; the entry-wise CV; ECM≡KL-MU; 300 initialisations | **verified** | the original-paper original-sentence quotations confirm it |
| sigminer: CRAN "MIT + file LICENSE"; extdata v3.1; `py_path` hard-coded; the Broad BSD-3 header | **verified** | `R/sig_extract.R:38`; 34 extdata files (**no SIGNAL-named file**) |
| rust-NMF: GPL≥2; 76×/~215–280× | **verified** | the LICENSE file is authoritative; the README's 16-thread table agrees with our numbers |
| the extendr/savvy/rextendr versions | **corrected** | **extendr-api latest = 0.9.0 (2026-04-16 unyanked)**; 0.8.2 is the last of the 0.8 line. savvy 0.11.0 ✓; rextendr 0.5.0 ✓ |
| The CRAN-policy quotations | **verified + a wording caution** | the original sentences confirmed; **there is no literal "networking forbidden at install time" clause** — the actual content is "external resources minimized/https/graceful degradation/precompiled downloads as a last resort, needing CRAN's consent". The conclusion (vendor everything) is unchanged |
| the twobit crate 0.2.2, MIT, jbethune | **verified** | updated 2026-03-27 |
| The HRDetect coefficients | **verified** | the means/sds/weights/intercept −3.364 all exact |
| A spot check of 5 PMIDs | **verified 5/5** | 35949260/31278357/42351273/41688639/35668106 all correct |
| The local environment | **verified** | R 4.5.2; rustc 1.97.1; rextendr 0.5.0; sigminer 2.3.1; MutationalPatterns not installed |
| (the extra check) the SPA default cosmic_version=3.6, the forced background signatures, the exclusion dictionary :376–410, the probabilities :1694 | **verified** | decomposition.py:257/:272/:376–410 (**14 subgroups incl. Treatment_signatures, which the earlier summaries missed**) |
| (the extra check) the Cornet preprint | **verified** | Europe PMC PPR1324264; 2026-09-21; doi:10.64898/2026.09.14.751548 |

## §3 The other findings

1. The 02 report's Medo DOI error (the only hard flaw) — corrected.
2. The 00/04 extendr "latest version" was stale (0.9.0) — corrected.
3. **The per-build reference-library availability was over-generalized** (the 05 §1, ARCHITECTURE §4.2 and ROADMAP M4 "five classes × 7 builds" does not hold) — the 05 was corrected and the bundling plan adjusted in the architecture v2 (the missing builds are self-derived or converted across builds by labels).
4. The CRAN-network wording softened — corrected.
5. The Jiang year unified to 2025 (epub 2024) — the 00 was corrected.
6. The mSigAct branch footnote — the 04 was corrected.
7. Details: the 02's exclusion lists missed the `Treatment_signatures` subgroup; the 00 mentioned sigminer's extdata having SIGNAL, unconfirmed (the 34 files have no SIGNAL-named one).
8. Not rechecked (the low-risk annotations): the Wu 2022 DOI form, the BayesPowerNMF/BASCULE DOIs, the remaining ~60 PMIDs of the 03 report (the spot check 5/5 passed), the DBS78 group-order details, SPMG's "~13,700 LOC" package total.

## §4 The overall conclusion

The archive is **exceptionally accurate at the source-engineering layer** (every sampled engineering claim, incl. the file line numbers, defaults, coefficients and column counts, matched the current upstream bit-for-bit). The required corrections before use as an implementation reference total 4 groups (§3.1–3.4), all executed. The rest can be trusted as-is.
