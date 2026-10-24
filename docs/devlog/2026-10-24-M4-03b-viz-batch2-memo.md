# M4-03b — viz batch 2 design memo

Date: 2026-10-24. Branch: `feat/m4-03b-viz-batch2` from `origin/main@258a255`.
Upstream byte-truth: `SigProfilerSuite/SigProfilerPlotting` @ master
`9be822faafc9b9933c75b78f0d59f2bfa35d657b` (fetched 2026-10-24).

## Scope

The four faces `docs/CAPABILITY-MATRIX.md` promises but does not yet ship,
plus the DBS78/ID83 palette freeze the batch-1 memo explicitly deferred:

| Face | Backing face consumed | Matrix row |
|---|---|---|
| `plot_qc_dashboard()` | `ms_qc_report()` data.frame | "QC dashboard page" |
| `plot_pseudosig_contribution()` | `ms_qc_roster_share()` data.frame | "pseudogenic-signature contribution plot" |
| `plot_hypermutator_burden()` | `MsStratification` (@totals, @cutoff, @hyper, @gmm) | "hypermutator burden distribution + GMM cutoff line plot" |
| `plot_opportunity_distribution()` | `msuiter:::.ms_convert_opps` (96 named opportunities) | "opportunity distribution plot" |
| `.ms_viz_dbs78_colors()` / `.ms_viz_id83_colors()` | upstream legend palettes (10 / 16 colors) | batch-1 deferral "M7" |

The face contracts below were locked from a read-only inventory pass of the
live backing faces (`R/ms-qc-report.R`, `R/ms-qc-sentries.R`, `R/stratify.R`,
`R/ms-convert.R`): column names, column order, units, class tags and
fixtures all verified against source, not assumed.

## Upstream byte-truth policy (DBS78/ID83)

`tools/channel-reference/sigProfilerPlotting-9be822f.py` carries the verbatim
upstream file (SHA256 `c5ace1456f802c5b6f2d84e702e4bcf4cac493b21e01752dec2916ae967517c6`,
measured 2026-10-24; md5 `76f970ef1e13684c85548ebbb91ffd9f`).
The palette tests parse the `elif context == "DBS78":` / `elif context ==
"ID83":` blocks out of the committed file line by line (`strsplit` on the
non-digit class; `gregexpr` misreports on this pattern class here, so the
parser is dependency-free line-splitting with per-line arity pins) and
compare the parsed hex vector against the R constants — zero re-typed
literals on either side ([[byte-true-fixtures-law]]). The mapping-table TSVs
(`DBS78.tsv` / `ID83.tsv`, RGB/256) are the second witness: parse and
transcription must agree or the test fails. A digest pin guards the file
itself.

## Contracts

Shared invariants for all four faces (house idiom, per batch-1 memo):

1. First statement is `.ms_viz_require_ggplot()` — Suggests-absent raises
   the `package`-topic structured error, before any other input validation.
2. Canonical-order / roster validation reuses `.ms_viz_check_table()`
   (R/viz-palette.R:50-65) — no re-coded validators.
3. Return value is always a `ggplot2` object; never NULL, never invisible.
4. Every face gets a layer-structure assertion set (facet/geom types,
   discrete level counts, pinned data content) plus a `ggsave`-renders-
   non-empty-PNG check, mirroring batch 1.

### `plot_qc_dashboard(qc)`

`qc` — the plain data.frame `ms_qc_report()` returns (validated columns:
`sample, total, log10_total, burden_class, gt_share, ct_share,
artifact_share, artifact_sigs, qc_flag`). Non-data.frame or missing columns
raise `input`-topic structured errors; zero rows raises too (an empty
dashboard is a bug, not a plot).

Layout (two-panel precedent `plot_reconstruction_panel`,
R/viz-profile.R:240-257: long `panel` column + `facet_grid(panel ~ .,
scales = "free_y", switch = "y")`):

- panel `"burden"`: `geom_col` of `log10_total` per sample, fill = the
  stored `burden_class` (the certified four-level tag `dead`/`low`/
  `standard`/`high` from `.ms_qc_burden_class`; drawn as-is, never
  re-thresholded).
- panel `"sentries"`: `geom_point` of `gt_share` and `artifact_share` per
  sample; colour from the stored `qc_flag` via `scale_colour_manual`
  (`drop = FALSE`) (artifact = `#E42926`, watch = `#03BDEF`, ok =
  `#046282` — house colors only, no invented brand hues). Dead samples
  carry certified-NA shares: unmeasured rows are dropped at the data layer
  (explicit, in place of the render-time removed-rows warning).
- x is the sample factor in report order (not re-sorted: the report is the
  source of truth for ordering).
- `@attr(qc, "ms_qc_provenance")` (catalog digest + sentry thresholds,
  machine-facing) rides into the plot title annotation when present.

### `plot_pseudosig_contribution(qc_roster, top = 3L)`

`qc_roster` — the `MsQcRosterShare`-tagged data.frame from
`ms_qc_roster_share()` (validated columns `sample, exposure_total,
artifact_share, artifact_sigs, artifact_flag`). Bars of `artifact_share`
(sorted descending — the contribution ranking is the point of the face),
fill = `artifact_flag`, and a text label of the `artifact_sigs` string
(semicolon-separated sig list per the backing face; `top` caps the joined
names shown, overflow marked `+N`). Samples whose share is certified-NA
(zero exposure) carry no bar — they are adjudicated out after the ranking
at the data layer; the `na` flag legend entry rides on the `drop = FALSE`
scale, not on a phantom bar.

### `plot_hypermutator_burden(strat, show_gmm = TRUE)`

`strat` — an `MsStratification` (S7). Derivation (never re-thresholded —
the class stores the adjudication, the plot draws it):

```r
samples <- names(strat@totals)
totals  <- as.numeric(strat@totals)
is_hyper <- samples %in% strat@hyper
```

- `geom_histogram(data = df, aes(x = total, fill = fill))`, `boundary = 0`,
  `bins = 30`, fill = hyper `#E42926` / nonhyper `#038193` via
  `scale_fill_manual`. All faces pass their data frame layer-locally
  (`geom_*(data = ...)`), the batch-1 idiom that keeps the pre-stat
  `layer$data` the witness frame for the data-pin tests.
- `geom_vline(xintercept = strat@cutoff)` — the pin test: the layer's
  computed data must carry exactly the stored `@cutoff` (integer-valued by
  the trunc(max(0, mean+2sd)) rule; fixture `test-stratify.R`
  `bimodal_cohort()` pins 13804).
- `show_gmm` annotates `@gmm$n_fits`, `@gmm$converged` (the strict-GMM
  attestation, S7 validity law) in the subtitle.
- `@totals` empty raises `input` (nothing to plot); a `@hyper` name absent
  from `@totals` raises `input` (class-corruption canary). Both are
  defence-in-depth: the certified S7 validator seals zero cohorts and bad
  partitions upstream, which the refusal test witnesses at the class law
  (`expect_error(MsStratification(... zero totals ...), class =
  "msuiter_error_stratify")`).

### `plot_opportunity_distribution(opps = NULL, from = "human-genome")`

`opps` — a named numeric of length 96 in registry order (validated by
`.ms_viz_check_table` against SBS96 labels). `NULL` resolves via
`from` through the same internal table the convert path uses
(`msuiter:::.ms_convert_opps`, keys `human-genome` / `human-exome`) — DRY,
no re-typed opportunity values anywhere in package or tests. Bars of the
(log10-scaled) opportunity per channel, fill = the substitution class parsed
from the bracket core of each 96-label (`substr(label, 3, 5)`: the SBS96
tables span all six classes, C>A/C>G/C>T/T>A/T>C/T>G), coloured through the
full six-entry `.ms_viz_sbs_palette`; x ticks as every 12th label.

## Non-scope

No new algorithmic content: every face renders an existing certified
result. No patchwork/complex-plot dependency. Signature-plot theme tweaks
stay in batch 1's file.

## Test plan

`tests/testthat/test-viz-batch2.R`: per-face layer-structure assertions
(pre-stat `layer$data` data pins through the layer-local-data idiom),
byte-pin palette tests (parsed from the committed upstream file + digest
pin + TSV cross-witness), canonical-order refusal tests, Suggests-absent
structured-error tests (skip-guarded when ggplot2 is installed; the branch
was additionally attested locally by running the faces through a fake
function environment with `requireNamespace` returning FALSE — all four
raised the `package`-topic error before any input validation), and
non-empty-PNG ggsave smokes. The RED/GREEN census reads every terminal
column of `as.data.frame(res)` — raised errors land only in the `error`
column, so reading `failed` alone reports silent green
([[testthat-error-column-law]]).
Fixtures mirror the certified return shapes byte-truthfully (the qc frame
carries the nine certified columns, four burden classes and the three flag
levels; the roster frame the frozen five-column order), and the opportunity
sum pins ride the `test-ms-convert.R` values (`8.505e9` / `153221364`).
