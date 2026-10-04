# calibrate-real.R: the real-data downsampling sanity harness (U-M3b-06;
# ARCHITECTURE section 5 MSU-Fit row "真实数据 sanity = 高 TMB 降采样覆盖
# 检验", design memo docs/devlog/2026-10-04-M3b-design-memo.md section 4,
# data-source protocol in inst/sanity/README.md).
#
# NON-CLAIM DISCIPLINE (memo section 4, frozen wording): this harness is a
# SANITY / STABILITY instrument on real data, never a calibration
# declaration. The pseudo-truth is itself an estimator (carries measurement
# error) and real catalogs violate the fitted model (identifiability,
# exposure heterogeneity) -- S(N) numbers must never be written into a
# coverage claim; the synthetic grid (ms_calibration_grid) remains the only
# calibration-declaration carrier.
#
# Protocol (memo section 4):
#   (1) the caller supplies a real catalog (top-TMB-decile samples; see
#       inst/sanity/README.md for the PCAWG/TCGA acquisition and governance
#       protocol) -- this unit NEVER downloads or embeds real data;
#   (2) the frozen production face fits the FULL catalog -> the point
#       estimate h_hat is the declared pseudo-truth;
#   (3) each dilution level N down-samples every live sample:
#       counts_diluted ~ Multinomial(N, counts_j / total_j) -- the same
#       law as engine::resample::multinomial, drawn here through base R's
#       rmultinom on a fixed seed (the Rust primitive has no FFI face; the
#       harness is not a calibration-declaration face, so the base-R draw
#       is protocol-documented rather than a kernel surface);
#   (4) each diluted catalog runs the production face + CI (percentile or
#       BCa), and S(N) = the fraction of pseudo-truth entries with
#       pseudo-truth share >= 0.05 covered by the diluted CIs;
#   (5) acceptance: S(N) within +-0.05 of the caller-supplied synthetic
#       main-arm curve at the same N (union the wider [0.90, 1.00] floor
#       per level, memo "取宽者"), and no systematic monotonicity
#       inversion along N.
#
# Error protocol: all violations raise msuiter_error_* conditions.

# Frozen sanity constants (memo section 4; re-freezing moves the protocol
# docs and tests together):
.MS_SANITY_TOLERANCE <- 0.05           # |S(N) - synthetic| band half-width
.MS_SANITY_FLOOR <- c(lo = 0.90, hi = 1.00)  # the "or" floor band (取宽者)
.MS_SANITY_SHARE_FLOOR <- 0.05         # pseudo-truth share kept for S(N)

# ---------------------------------------------------------------------------
# Pure criteria helpers (unit-tested directly; called from the gated
# context above, so they re-check only their own local shape)
# ---------------------------------------------------------------------------

# Monotonicity of the S(N) curve: a step (N_i -> N_{i+1}) INVERTS when
# S drops by more than the tolerance (MC noise slack). The inversion is
# SYSTEMATIC when a strict majority of steps invert -- isolated dips stay
# inside the noise slack by construction.
#' @noRd
.ms_sanity_monotonicity <- function(s, tolerance) {
  if (!is.numeric(s) || length(s) < 1L || anyNA(s) ||
      any(!is.finite(s)) || any(s < 0) || any(s > 1)) {
    msuiter_abort(
      "input",
      "s must be a numeric vector of coverage fractions in [0, 1] without NA",
      i = "the monotonicity gate reads the S(N) curve of the sanity harness",
      j = paste0("received: ", msuiter_quote_trunc(s)),
      c = "pass the s column of the harness S(N) curve"
    )
  }
  if (!is.numeric(tolerance) || length(tolerance) != 1L || is.na(tolerance) ||
      !is.finite(tolerance) || tolerance < 0 || tolerance > 1) {
    msuiter_abort(
      "input",
      "tolerance must be a single number in [0, 1]",
      i = "the tolerance is the MC-noise slack of the step-inversion test",
      j = paste0("received: ", msuiter_quote_trunc(tolerance)),
      c = "pass the frozen 0.05 (memo section 4)"
    )
  }
  if (length(s) < 2L) {
    return(list(
      n_inversions = 0L,
      inverted_at = integer(0L),
      systematic_inversion = FALSE
    ))
  }
  steps <- diff(s)
  inverted <- which(steps < -tolerance)
  list(
    n_inversions = length(inverted),
    # The 1-based index of the level a drop leaves (the higher-N end).
    inverted_at = as.integer(inverted + 1L),
    systematic_inversion = 2L * length(inverted) > length(steps)
  )
}

# The +/-0.05 synthetic comparison, "or" the wider [0.90, 1.00] floor band
# per level (memo: "或 [0.90, 1.00] 地板，取宽者"). Without a synthetic
# curve the floor band alone is the criterion (recorded as such).
#' @noRd
.ms_sanity_window <- function(s, levels, synthetic, tolerance) {
  if (!is.numeric(tolerance) || length(tolerance) != 1L || is.na(tolerance) ||
      !is.finite(tolerance) || tolerance < 0 || tolerance > 1) {
    msuiter_abort(
      "input",
      "tolerance must be a single number in [0, 1]",
      i = "the tolerance is the |S(N) - synthetic| band half-width",
      j = paste0("received: ", msuiter_quote_trunc(tolerance)),
      c = "pass the frozen 0.05 (memo section 4)"
    )
  }
  if (!is.numeric(levels) || length(levels) != length(s) || anyNA(levels)) {
    msuiter_abort(
      "input",
      "levels must be a numeric vector aligned with s",
      i = "the synthetic comparison matches the harness N axis into the synthetic curve",
      j = paste0("received: ", msuiter_quote_trunc(levels)),
      c = "pass the harness dilution_sizes axis"
    )
  }
  floor_ok <- s >= .MS_SANITY_FLOOR[[1L]] & s <= .MS_SANITY_FLOOR[[2L]]
  if (is.null(synthetic)) {
    return(list(
      synthetic_used = FALSE,
      deviation = rep(NA_real_, length(s)),
      within = unname(floor_ok)
    ))
  }
  if (!is.data.frame(synthetic) || !is.numeric(synthetic$n) ||
      !is.numeric(synthetic$coverage) || anyNA(synthetic$n) ||
      anyNA(synthetic$coverage) || anyDuplicated(synthetic$n) > 0L) {
    msuiter_abort(
      "input",
      "synthetic must be a data.frame with unique numeric columns n and coverage",
      i = "the synthetic curve is the main-arm grid curve at the same N values",
      j = paste0("received: ", msuiter_quote_trunc(class(synthetic)[1L])),
      c = "pass a subset of ms_calibration_grid() output renamed to (n, coverage)"
    )
  }
  matched <- match(levels, synthetic$n)
  if (anyNA(matched)) {
    msuiter_abort(
      "input",
      "the synthetic curve must cover every dilution size of the harness",
      i = "the memo criterion compares S(N) against the synthetic main-arm curve at the SAME N",
      j = paste0("dilution sizes missing from synthetic: ",
        msuiter_quote_trunc(levels[is.na(matched)])),
      c = "run ms_calibration_grid() over the harness N axis and subset it to (n, coverage)"
    )
  }
  ref <- synthetic$coverage[matched]
  dev <- abs(s - ref)
  band_ok <- dev <= tolerance
  list(
    synthetic_used = TRUE,
    deviation = dev,
    within = unname(band_ok | floor_ok)
  )
}

# ---------------------------------------------------------------------------
# User face: ms_calibration_sanity()
# ---------------------------------------------------------------------------

#' Real-data downsampling sanity harness for exposure confidence intervals
#'
#' `ms_calibration_sanity()` runs the M3b real-data sanity protocol (design
#' memo docs/devlog/2026-10-04-M3b-design-memo.md section 4) on a
#' CALLER-SUPPLIED real catalog: the frozen production face fits the full
#' catalog (the point estimate is the declared **pseudo-truth**), every
#' dilution level \eqn{N \in} `dilution_sizes` down-samples each live
#' sample through \eqn{\mathrm{Multinomial}(N,\ \mathrm{counts}_j /
#' \mathrm{total}_j)} `n_dilutions` times, each diluted catalog is refit
#' with the production face + CI, and \eqn{S(N)} -- the coverage of the
#' pseudo-truth entries with pseudo-truth share >= 0.05 -- forms the
#' downsampling curve.
#'
#' **This is a sanity/stability instrument, never calibration evidence**
#' (memo section 4, non-claim discipline): the pseudo-truth is an estimator
#' and real data violate the fitted model. Data acquisition and governance
#' (PCAWG WGS primary / TCGA GDC open WXS secondary, WES and panel axes
#' deferred to M4 by PI ruling) live in
#' \code{inst/sanity/README.md}; this function never downloads data.
#'
#' @param catalog_real An [MsCatalog] holding the real counts (channels x
#'   samples). Samples with zero total are dead and excluded from the
#'   dilution draws (their pseudo-truth is zero anyway).
#' @param sigs_real The dictionary to fit against: a numeric matrix
#'   (channels x signatures) or an [MsSignature], resolved exactly as in
#'   [ms_fit()] (channel alignment by label, display normalization).
#' @param n_boot Single positive whole number: bootstrap replicates of every
#'   diluted fit (the memo protocol uses 1000; the default here is the
#'   reduced 200 for interactive budgets).
#' @param bca Single logical (default `FALSE`): read the BCa face of the
#'   diluted CIs instead of the percentile face (fallback cells are
#'   bit-identical to percentile either way).
#' @param dilution_sizes Increasing vector of positive whole numbers: the
#'   dilution (downsampled mutation total per sample) axis; the memo
#'   protocol is \code{c(100, 1000, 10000)}. Every level must be a strict
#'   downsample of every live sample (level <= the smallest live total).
#' @param n_dilutions Single positive whole number in \eqn{[1, 4096]}:
#'   dilution replicates per level (the memo protocol uses 100).
#' @param synthetic NULL (default) or a data.frame with columns `n` and
#'   `coverage`: the synthetic MAIN-arm calibration curve to compare
#'   against (a subset of [ms_calibration_grid()] output over the same N
#'   axis, run at the frozen protocol). With NULL the acceptance falls back
#'   to the floor band \eqn{[0.90, 1.00]} alone (recorded in the result).
#' @param tolerance Single number in \eqn{[0, 1]}: the |S(N) - synthetic|
#'   band half-width (frozen 0.05, PI ruling) and the step-inversion noise
#'   slack.
#' @param seed Single non-negative whole number: the base seed. The
#'   dilution draws consume base R's RNG seeded exactly once (draws run in
#'   fixed level x replicate x sample order; the caller's RNG state is
#'   restored on exit), and the bootstrap of dilution (level i, replicate d)
#'   uses the derived PCG64 seed `seed + (i-1)*n_dilutions + (d-1)` -- the
#'   whole result is a pure function of the inputs.
#' @param nb_size,n_threads As in [ms_fit()] / [ms_fit_bootstrap()].
#'
#' @details
#' **The pseudo-truth.** The full catalog is fit once with the production
#' face (`"likelihood_bidirectional"`, zero_threshold 0.01, rescale), the
#' same face the synthetic grid declares on. Kept entries are the
#' (signature, sample) cells whose pseudo-truth share is >= 0.05; S(N)
#' pools over kept entries x dilution replicates.
#'
#' **Acceptance.** `pass = all(within) && !systematic_inversion`, where
#' `within` is per level: |S(N) - synthetic(N)| <= `tolerance`, OR S(N)
#' inside the wider floor band [0.90, 1.00] (the memo's "取宽者" union);
#' without a synthetic curve, the floor band alone. A level-to-level drop
#' steeper than `tolerance` is an inversion; the inversion is systematic
#' when a strict majority of steps invert.
#'
#' @return A list of class `ms_calibration_sanity` with elements:
#'   `pass`; `s_curve` (data.frame `n`, `s`, `se`, `tallies`, `deviation`,
#'   `within` -- `deviation` is |S(N) - synthetic(N)| (NA without a
#'   synthetic curve) and `within` the per-level acceptance: the
#'   +/-`tolerance` band around the synthetic value OR the floor band
#'   [0.90, 1.00], whichever wider, floor alone without a synthetic curve);
#'   `synthetic_used`; `n_inversions`, `inverted_at`,
#'   `systematic_inversion`; `tolerance`; `floor_band`; `share_floor`;
#'   `dilution_sizes`; `n_dilutions`; `n_boot`; `bca`; `seed`; `nb_size`;
#'   `method`; `kept` (data.frame `signature`, `sample`, `truth`,
#'   `truth_share` -- the pseudo-truth entries S(N) is measured on);
#'   `n_live_samples`; `dead_samples`. All violations raise
#'   `msuiter_error_*` conditions.
#'
#' @seealso [ms_calibration_grid()] for the synthetic comparison curve,
#'   [ms_fit_bootstrap()] for the interval face, and
#'   \code{inst/sanity/README.md} for the data protocol.
#' @export
ms_calibration_sanity <- function(catalog_real, sigs_real, n_boot = 200,
                                  bca = FALSE,
                                  dilution_sizes = c(100, 1000, 10000),
                                  n_dilutions = 100, synthetic = NULL,
                                  tolerance = .MS_SANITY_TOLERANCE, seed = 1,
                                  nb_size = 8, n_threads = NULL) {
  # --- shape gates ----------------------------------------------------------
  if (!S7::S7_inherits(catalog_real, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog_real must be an MsCatalog object",
      i = "the sanity harness dilutes a real catalog the caller supplies (it never downloads data)",
      j = paste0("received: ", msuiter_quote_trunc(class(catalog_real)[1L])),
      c = "tally the real variant set into an MsCatalog with ms_tally() first"
    )
  }
  if (!is.logical(bca) || length(bca) != 1L || is.na(bca)) {
    msuiter_abort(
      "input",
      "bca must be a single TRUE or FALSE",
      i = "bca selects which CI face the diluted fits report",
      j = paste0("received: ", msuiter_quote_trunc(bca)),
      c = "leave the default FALSE for the percentile face"
    )
  }
  if (!is.numeric(n_dilutions) || length(n_dilutions) != 1L ||
      is.na(n_dilutions) || !is.finite(n_dilutions) ||
      n_dilutions != floor(n_dilutions) || n_dilutions < 1 ||
      n_dilutions > 4096) {
    msuiter_abort(
      "input",
      "n_dilutions must be a single whole number in [1, 4096]",
      i = "n_dilutions is the dilution replicate count per level (the memo protocol uses 100)",
      j = paste0("received: ", msuiter_quote_trunc(n_dilutions)),
      c = "pass 100 (protocol), or fewer for smoke runs"
    )
  }
  if (!is.numeric(tolerance) || length(tolerance) != 1L || is.na(tolerance) ||
      !is.finite(tolerance) || tolerance < 0 || tolerance > 1) {
    msuiter_abort(
      "input",
      "tolerance must be a single number in [0, 1]",
      i = "the tolerance is the |S(N) - synthetic| band half-width (frozen 0.05, PI ruling)",
      j = paste0("received: ", msuiter_quote_trunc(tolerance)),
      c = "leave the frozen default 0.05"
    )
  }
  .ms_calibration_gate_n_grid(dilution_sizes) # positive whole, increasing
  .ms_fit_gate_boot(n_boot, seed)
  .ms_fit_gate_nb_size(nb_size)
  n_threads_resolved <- .ms_resolve_threads(n_threads)

  # --- dictionary resolution + pseudo-truth (the production face) ----------
  prep <- .ms_fit_prepare_dictionary(catalog_real, sigs_real)
  counts_full <- prep$counts
  totals_full <- colSums(counts_full)
  live <- which(totals_full > 0)
  dead <- setdiff(seq_along(totals_full), live)
  if (length(live) == 0L) {
    msuiter_abort(
      "input",
      "the catalog has no sample with a positive mutation total",
      i = "the dilution primitive Multinomial(N, counts/total) needs positive channel distributions",
      j = "every sample column is all-zero",
      c = "tally a catalog with mutations (an empty catalog has no sanity to run)"
    )
  }
  # Strict-downsampling contract: every level strictly down-samples every
  # live sample.
  if (any(dilution_sizes > min(totals_full[live]))) {
    msuiter_abort(
      "input",
      "every dilution size must downsample every live sample",
      i = "the protocol dilutes high-TMB catalogs (level <= smallest live sample total)",
      j = sprintf("smallest live total: %.0f; requested levels: %s",
        min(totals_full[live]), msuiter_quote_trunc(dilution_sizes)),
      c = "lower the dilution axis, or restrict the catalog to higher-TMB samples"
    )
  }
  point <- .ms_fit_rust(counts_full, prep$signatures, "likelihood_bidirectional",
    nb_size, .ms_fit_defaults$eps, .ms_fit_defaults$max_iter, 0.01)
  h_hat <- point$exposures # k x n (count scale, rescale semantics)
  col_tot <- colSums(h_hat)
  # Pseudo-truth shares (zero-total fits degenerate to 0, never NaN).
  shares <- matrix(0, nrow = nrow(h_hat), ncol = ncol(h_hat))
  pos <- col_tot > 0
  if (any(pos)) {
    shares[, pos] <- sweep(h_hat[, pos, drop = FALSE], 2L, col_tot[pos], `/`)
  }
  kept <- shares >= .MS_SANITY_SHARE_FLOOR
  if (!any(kept)) {
    msuiter_abort(
      "fit",
      "no pseudo-truth entry reaches the share floor",
      i = sprintf("S(N) is measured over pseudo-truth entries with share >= %s",
        format(.MS_SANITY_SHARE_FLOOR)),
      j = "the full-catalog production fit kept no entry above the floor",
      c = "fit a dictionary that actually describes the catalog, or lower the protocol floor (re-freeze both sides)"
    )
  }

  # --- dilution draws (base RNG, fixed order, state restored on exit) ------
  boot_span <- length(dilution_sizes) * n_dilutions # double arithmetic
  if (seed > 2147483647 - boot_span) {
    msuiter_abort(
      "input",
      "seed + (levels x dilutions) must stay within [0, 2^31 - 1]",
      i = "each dilution fit derives its bootstrap seed as seed + offset",
      j = sprintf("seed = %.0f, span = %d", seed, boot_span),
      c = "lower the seed or the dilution budget"
    )
  }
  had_seed <- exists(".Random.seed", envir = .GlobalEnv)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else {
      rm(list = ".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(seed))

  tallies <- integer(length(dilution_sizes))
  covered <- integer(length(dilution_sizes))
  kept_live <- kept[, live, drop = FALSE]
  n_tallies_per_fit <- sum(kept_live)
  for (i in seq_along(dilution_sizes)) {
    n_level <- as.integer(dilution_sizes[[i]])
    # The pseudo-truth dilutes with the catalog: each live sample's truth
    # entries are rescaled onto the level's total (N), so the diluted CI
    # and the truth live on the same count scale (the dilution conserved
    # totals exactly, factor = N / total_j).
    truth_level <- h_hat[, live, drop = FALSE] *
      rep(n_level / totals_full[live], each = nrow(h_hat))
    for (d in seq_len(as.integer(n_dilutions))) {
      dil <- matrix(0, nrow = nrow(counts_full), ncol = ncol(counts_full))
      for (j in live) {
        dil[, j] <- as.numeric(stats::rmultinom(
          1, size = n_level, prob = counts_full[, j] / totals_full[[j]]
        ))
      }
      boot_seed <- as.integer(seed + (i - 1L) * as.integer(n_dilutions) + d - 1L)
      boots <- .ms_fit_bootstrap_rust(dil, prep$signatures,
        "likelihood_bidirectional", n_boot, nb_size, 0.01, boot_seed,
        n_threads_resolved, bca)
      lo <- if (isTRUE(bca)) boots$bca_lower else boots$ci_lower
      hi <- if (isTRUE(bca)) boots$bca_upper else boots$ci_upper
      lo <- lo[, live, drop = FALSE]
      hi <- hi[, live, drop = FALSE]
      hit <- kept_live & lo <= truth_level & truth_level <= hi
      tallies[[i]] <- tallies[[i]] + n_tallies_per_fit
      covered[[i]] <- covered[[i]] + sum(hit)
    }
  }

  s_curve <- data.frame(
    n = as.numeric(dilution_sizes),
    s = covered / tallies,
    se = sqrt((covered / tallies) * (1 - covered / tallies) / tallies),
    tallies = tallies,
    stringsAsFactors = FALSE
  )
  crit <- .ms_sanity_window(s_curve$s, s_curve$n, synthetic, tolerance)
  s_curve$deviation <- crit$deviation
  s_curve$within <- crit$within
  mono <- .ms_sanity_monotonicity(s_curve$s, tolerance)

  kept_df <- data.frame(
    signature = rep(prep$labels, times = ncol(h_hat))[as.vector(kept)],
    sample = rep(catalog_real@samples, each = nrow(h_hat))[as.vector(kept)],
    truth = as.vector(h_hat)[as.vector(kept)],
    truth_share = as.vector(shares)[as.vector(kept)],
    stringsAsFactors = FALSE
  )

  res <- list(
    pass = all(s_curve$within) && !mono$systematic_inversion,
    s_curve = s_curve,
    synthetic_used = crit$synthetic_used,    n_inversions = mono$n_inversions,
    inverted_at = mono$inverted_at,
    systematic_inversion = mono$systematic_inversion,
    tolerance = as.numeric(tolerance),
    floor_band = .MS_SANITY_FLOOR,
    share_floor = .MS_SANITY_SHARE_FLOOR,
    dilution_sizes = as.numeric(dilution_sizes),
    n_dilutions = as.integer(n_dilutions),
    n_boot = as.integer(n_boot),
    bca = bca,
    seed = as.integer(seed),
    nb_size = as.numeric(nb_size),
    method = "likelihood_bidirectional",
    kept = kept_df,
    n_live_samples = length(live),
    dead_samples = catalog_real@samples[dead]
  )
  class(res) <- "ms_calibration_sanity"
  res
}

#' Print a calibration sanity result
#'
#' Compact print of an `ms_calibration_sanity` result: the pass verdict, a
#' one-line protocol echo and the S(N) curve table.
#'
#' @param x An `ms_calibration_sanity` result as returned by
#'   [ms_calibration_sanity()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.ms_calibration_sanity <- function(x, ...) {
  verdict <- if (isTRUE(x$pass)) "PASS" else "FAIL"
  cat(sprintf("ms_calibration_sanity: %s\n", verdict))
  cat(sprintf(
    "  S(N) over levels %s | %d dilutions/level | kept entries: %d | synthetic: %s\n",
    msuiter_quote_trunc(x$dilution_sizes), x$n_dilutions, nrow(x$kept),
    if (x$synthetic_used) "supplied" else "floor band only"
  ))
  print(x$s_curve[, c("n", "s", "se", "within")], row.names = FALSE)
  if (x$systematic_inversion) {
    cat(sprintf(
      "  systematic inversion along N (%d inverted steps at levels %s)\n",
      x$n_inversions, msuiter_quote_trunc(x$inverted_at)
    ))
  }
  invisible(x)
}
