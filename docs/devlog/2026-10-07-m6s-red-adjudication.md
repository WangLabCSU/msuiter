# U-M6s-01 RED batch adjudications (T1 → T2 GREEN handoff)

The RED batch (`test(m6s): ms_hrd_report RED 批次…`, cherry-picked as
`038ec43`) was authored strictly against the design memo
(`docs/devlog/2026-10-07-m6s-hrd-report-design.md`, §1/§2/§3.3). The dry-run
is all-red for the intended reason (`'ms_hrd_report' is not an exported
object`), and every hand-derived golden reproduces under the verbatim
SigMiner oracle in `tests/testthat/helper-hrd.R`. Nine points where the memo
was silent were flagged for adjudication; resolutions below bind the GREEN
batch (T2). Where the memo is authoritative, the memo wins unchanged.

## 1. Segment column layout — memo §2 confirmed
Input frame columns are `sample/chromosome/start/end/state/minor_cn/caller/assay`
(memo §2). The `seg_median_ratio/tumor_purity/cellularity` fields do not feed
either verbatim score and are **not** required nor validated by
`ms_hrd_report()`. GREEN must not add hidden dependencies on them.

## 2. Error topics — memo verbatim + package convention
Verbatim gates keep the memo topics exactly: `hrd-wes-experimental`
(WES assay) and `hrd-caller-whitelist` (non-whitelisted caller).
Malformed input and unsupported genome build follow the established
`msuiter_abort` topics `input` and `genome` (cf. `io-segments` precedent).
GREEN adopts these and no others.

## 3. Return-column spellings — ratified
`ploh_fraction` (normalised pLOH score), `aneuploidy_count` (non-zero-flag
autosomes), `hrd_score` (composite; see §4). RED pins presence/type; these
spellings are now the API contract.

## 4. Composite `hrd_score` — pinned for GREEN with provenance
`hrd_score = 1L` iff `ploh_fraction >= 0.4` **and** `aneuploidy_count >= 4`
(Cortes-Castro convention). Provenance to be cited in both the implementation
docstring and the memo amendment: Cortes-Castro et al., *Cancer Research*
2020, which defines the combined pLOH + aneuploidy classifier with these
cut-offs. GREEN must (a) verify the exact bibliographic record and the
cut-offs against the primary source before citing it, and (b) add the numeric
golden block to `test-hrd-reference.R` **before** flipping the assertion; the
RED batch deliberately carries no numeric pin here (no-invent rule).

## 5. Geometry injection — ratify dots, refdb supplies defaults in GREEN
Reference geometry (arm table, centromere-equivalent spans, ploidy,
`chr_size`) is injectable via `...` for test determinism (RED relies on this).
GREEN sources production defaults from refdb (`get_cn_ploidy`, hg19 build
table) so that a plain `ms_hrd_report(seg)` call needs no geometry
arguments. Injected values always win over refdb defaults.

## 6. Whole-chrom `fraction/2` — RED reading confirmed
Memo verbatim "whole-chrom split `fraction/2`" means each of the two arms of
a whole-chromosome-covered autosome carries `fraction = 0.5` (summing to 1.0
per chromosome), so
`flag = as.integer(round(sum(state * fraction) - ploidy[1]))` is computed
over the two half-weight arms. This matches the memo §1 replay; the 0.5
per-arm convention is ratified.

## 7. Blacklist scope — p-arms only, skip-not-scored
Blacklist {13, 14, 15, 21, 22} applies to their **p-arms** only (memo §1
verbatim; the task's looser "chromosome" wording is superseded). An autosome
whose only covered arm is a blacklisted p-arm contributes **nothing** (is
skipped), rather than scoring `round(0 - ploidy)`. RED encodes exactly this.

## 8. Diagnostic columns — GREEN defines, RED pins shape only
`n_windows_scored` (count over injected geometry's window binning),
`coverage_note`, `ploidy_source` (enum: `"user"` when `ploidy` injected,
else refdb-derived path). Numeric semantics arrive with GREEN alongside the
refdb wiring of §5; RED asserts presence/type/enum only.

## 9. Caller casing — lowercase exact-match with input normalisation
The whitelist is the five lowercase labels
`{battenberg, ascat, facets, purple, sequenza}`. GREEN normalises the caller
argument to lowercase before comparison (documented behaviour); case-sensitivity
of the stored labels is not part of the contract. Unknown/nonstring caller
still hits `hrd-caller-whitelist` per §2.

## GREEN batch entry conditions (T2)
1. §4 composite numeric golden added first (test-first discipline preserved).
2. Implementation lives in `R/hrd-report.R`; docs via roxygen with
   usethis/devtools workflow; `docs-sync` guard must pass.
3. Full repo-mode testthat suite green including the 33 RED blocks;
   `R CMD check --as-cran` gate per CI contract.
4. Phase PR merges the whole feat branch (design memo + RED + GREEN) as one
   big-phase PR per the PR mandate.
