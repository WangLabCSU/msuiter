# bench/results/ — campaign artifact index

Every directory here is a **committed, immutable measurement campaign**:
benchmarks, floor-table calibrations, parity censuses, and their fairness
attestations. These bytes are the anchors the paper cites
(`vignettes/articles/paper-draft.qmd` Tables 1–2, Appendix A) and the
reproduction face re-derives (`vignettes/articles/reproduction-proof.qmd`).

House laws that bind this directory:

* **Append-only.** Campaign directories are never edited or pruned after
  landing; corrections land as new directories plus supersession notes in
  the erratum devlogs.
* **MEASURED-then-STATED.** Every timing figure in the paper quotes one of
  the witness/CSV files here, by path.
* **Epoch law.** Floor-table epochs pinned at
  `bench/m7/tests/test_p6_floor_governance.py:173-174`:
  `PRECAP_SEALED_EPOCH = 6b3a66bc9d0224eb`,
  `POST_CAP_EPOCH_PIN = b1ce0f176cec2633`.

## Directory index (chronological)

| directory | class | what it carries |
|---|---|---|
| `docker_degraded_pi_20261007-212438` | PI degraded run | first docker-adapter degraded-profile coverage + timings (PI era) |
| `docker_m7_PILOT_20261008-200152` | m7 pilot | slice3 pilot incl. cell-argv probe RED/DEFECT/GREEN progression + image-inspect records |
| `docker_m7_degraded_20261009-184833` | m7 degraded run | benchmark + judgment; carries `EVIDENCE-ADDENDUM.md` (RB-08/09 lineage) |
| `docker_m7_degraded_20261010-202330` | m7 degraded run | benchmark + judgment; superseded by the p6 regen campaigns |
| `m7_floor_calibration_20261009` | calibration | first REP-1 floor calibration; carries the FRESHNESS-REPLAY DEFECT witness (RB-09 class) |
| `bootstrap_vs_sigminer_20261011T024301Z` | bootstrap campaign | first bootstrap-vs-sigminer campaign (superseded by the 20261013 re-run) |
| `bootstrap_vs_sigminer_20261013T175859Z` | bootstrap campaign | **authoritative bootstrap seal**: 15.36600758177x (MEASURED-false), result.md + seal.json |
| `m7_floor_calibration_p6_20261017` | calibration | P6-era floor-table calibration |
| `p6_regen_20261016-011928` | regen campaign | gen-1 P6 regen; `result.md` carries the sealed P-1 gate table (`FAIL — 18 offending class(es)`); `nmf_yardstick_authoritative.json` yardstick pin |
| `m7_floor_calibration_p7cap_20261025-125823` | calibration | **the six gen-2 post-cap faces** (126 census witness refs) |
| `p6_regen_20261023-044026` | regen campaign | gen-2 P6 regen (147-cell era); carries the reissued-scoring addendum |
| `m7_floor_calibration_p7cap_legacy_20261027-083955` | calibration | gen-2 pre-law `sigminer` face (21 census witness refs) |
| `accept_rerun_20261028` | calibration fragment | accepted-rerun witnesses (gate-fail era repair) |
| `m7_floor_calibration_p7cap_20261104T093543Z` | calibration | gen-3 batch-bridge face `sigminer_post_v3_rust_batch` — **witnesses withdrawn 2026-11-15** (superseded by the r2 re-mint); ledger + anchors fragment kept as provenance |
| `m7_floor_calibration_p6_20261115-023000` | calibration | **the batch-bridge r2 re-mint**: `sigminer_post_v3_rust_batch` on the post-P11 kernel (21 census witness refs; epoch re-pin `b1ce0f176cec2633`) |
| `m7_floor_calibration_p7cap_legacy_20261111-144552` | calibration | **the yardstick**: sigprofiler SS3 re-mint (168 census witness refs, all 21 classes; witnesses re-stamped onto `b1ce0f176cec2633` 2026-11-15) |
| `p6_regen_20261111-095635` | regen campaign | **gen-4 authoritative run**: 168/168 cells ok, census `census_regen_20261114.txt` (md5 36ce2ca8fa815ccf4cd64e225c563931), epoch `cfdcc51dbb9b7041`, ~65.5 h wall, 8 serial shards; Hungarian P/R/F1 verdict in `judgment_m7_degraded_20261114-112641.md` |

## Supersession chain (parity censuses)

`p6_regen_20261023-044026` (147/147 @ `f3e894a6933a2ffb`) → superseded by
**`p6_regen_20261111-095635`** (168/168 @ `cfdcc51dbb9b7041`, banked
`census_regen_20261114.txt`) → the batch arm re-anchored onto the post-P11
kernel r2 re-mint and the census re-banked (168/168 @ `b1ce0f176cec2633`,
banked `p6_regen_20261111-095635/census_regen_20261115.txt`) — the current
committed O5 record. The supersession records are
`vignettes/articles/devlog-2026-11-14-gen4-census-erratum.qmd` then
`vignettes/articles/devlog-2026-11-15-batch-bridge-r2-remint.qmd`; sealed
devlog bodies are byte-exact and are superseded only through errata.

## Regeneration

None of these directories is regenerated in place. Replay recipes are
printed (never executed) by `inst/repro/reproduce.sh --full`; the
one-command verification face is `MSUITER_REPRO_LIB=<stage-dir> bash
inst/repro/reproduce.sh --verify`.
