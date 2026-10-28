# P8-CS-3 — treatment-forensics reporting face design memo

Date: 2026-10-28. Branch: `feat/p8-scenarios` from `main@309ab5bd`.
Phase-8 scenario/case-study lane; the third application-scenario case study
(`docs/research/03-applications.md` section 3).

## The differentiation claim (quoted, not paraphrased)

`docs/research/03-applications.md` section 3, verbatim:

> **The implied workflow — the "treatment forensics mode"**: fit against the
> treatment reference set (SBS11/25/31/32/35/36 + the treatment ID/SV
> patterns) → validate against the treatment records → the clonal timing
> (the clone = pre-treatment, the subclone = during-treatment) → the
> longitudinal relapse-pair differences. **No mainstream tool offers a
> treatment-history reporting module — a differentiation opportunity.**

This lane delivers the first slice of that module: the reporting face over a
treatment-restricted reference subset plus a treatment-record adjudication.
The longitudinal relapse-pair difference face is explicitly out of scope
here (it needs a paired-sample fit-difference face that no shipped API yet
provides; it is left as a named follow-up, not silently pretended).

## Delivered face

`ms_treatment_report(catalog, treatments = NULL, clonality = NULL,
exposure_map = NULL, n_boot = 200, seed = 1, build = "GRCh37",
method = "nnls")` — R/treatment-report.R.

The governed default exposure map binds each therapy class to its officially
recognised signature identities (recognition anchors per section 3:
temozolomide SBS11 PMID 39656916; platinum SBS31/SBS35 PMID 32366847;
thiopurine SBS32 PMID 31697823):

| Class | Governed signatures |
|---|---|
| `temozolomide` | `SBS11` |
| `platinum` | `SBS31`, `SBS35` |
| `thiopurine` | `SBS32` |

## Design decisions

1. **Identity governance through the refdb only.** Every signature label
   (default map or caller-supplied `exposure_map`) is resolved against the
   sealed `ms_refdb_bundled()` SBS96 roster; an unresolvable label or a
   build with no SBS set fails closed with an `msuiter_error_refdb`
   condition. No COSMIC numeric is committed anywhere (law D3): the served
   dictionary bytes come from the digests-verified bundle at runtime.

2. **Delegation, never duplication.** Point estimates come from the public
   fit face and interval estimates from `ms_fit_bootstrap(return_draws =
   TRUE)` — the group-contrast and clonal-split confidence bounds are
   quantiles of per-replicate group means computed from the single
   bootstrap-truth tensor `attr(exposures, "boot_draws")`
   `[signature, sample, replicate]`. The module contains no resampler and
   no kernel re-entry of its own. A law unit asserts point-column
   equality against an independent `ms_fit()` pass.

3. **Clonal/subclonal timing split.** With a caller-supplied `clonal_fraction
   in [0, 1]` per sample x signature cell, the pre-treatment share of each
   exposed sample's fitted exposure is `cf * E` and the during-treatment
   share `(1 - cf) * E` (the clone-pre/subclone-during reading of section
   3); the two point columns sum to the association mean by construction,
   which a law unit pins at `tolerance = 1e-12`, and a fully-clonal cohort
   must put the entire activity pre-treatment.

4. **Honest degradation.** With `treatments = NULL` the association face
   ships an empty (contract-shaped) table plus an attestation row
   `face = "association", status = "degraded"` naming
   `no-treatment-records`; the same discipline governs the timing face
   (`no-clonality-records`). Degradation is a ledger attestation, never a
   fabricated zero.

5. **S3 report object, print exercised.** The `MsTreatmentReport` form
   follows the shipped `MsHrdReport` precedent: `as.data.frame()` yields
   the association table; `timing`, `attestation` and `provenance` ride as
   attributes; the print face speaks the refdb version, run parameters and
   the attestation ledger, and is exercised through `capture.output()` in
   the law units (not merely constructed).

6. **Determinism.** Same seed, byte-identical tables; different seed moves
   the bootstrap bounds. `is_associated` is an effect-size call: the
   bootstrap contrast interval must clear zero by `.MS_TRT_ASSOC_FLOOR`
   (50 exposure-count units). Officially recognised therapy signatures are
   correlated reference vectors, so a sibling of a truly planted signature
   absorbs a deterministic few-count share under NNLS refit; a raw
   interval-excludes-zero rule would promote that artefact, and the
   scenario's a-priori law would be false rather than the floor calibrated.
   Provenance carries `refdb_version`, `build`, `method`, `n_boot`,
   `seed`, the served dictionary labels and a FIPS-180-4 SHA-256 over their
   canonical serialization (`.ms_fit_sha256`, the package's single digest
   primitive).

## Non-goals and named follow-ups

- Longitudinal relapse-pair differencing (paired fit-delta face, absent).
- Treatment ID/SV-pattern fitting (section 3 lists "the treatment ID/SV
  patterns"): ID83/CN/SV reference matrices have no R-side tally/fit path
  through the public API today (Phase-8 CS-1 attestation), so this face is
  SBS96-only and says so.
- 5-FU and radiation classes (no COSMIC-recognised single-label binding of
  comparable strength in the bundled roster): excluded deliberately from
  the governed default, addable through `exposure_map` governance.

## Law units

`tests/testthat/test-treatment-report.R` (12 units) + the
`tests/testthat/helper-treatment.R` synthetic cohort (17 samples, planted
activites are hand-set numbers on the sealed bundled dictionary served via
`ms_refdb_bundled()`; law-unit truth: exactly the planted
treatment-x-signature cells associate). RED/GREEN witnesses and the budget
ledger live under `/tmp/p8lane/logs/`.
