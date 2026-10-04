# calibrate.R: the R assembly face of the MSU-Fit calibration experiment
# (U-M3b-04; ARCHITECTURE section 5 MSU-Fit row, design memo
# docs/devlog/2026-10-04-M3b-design-memo.md sections 1-3, PI ruling
# 2026-10-04).
#
# `ms_calibration_grid()` drives the Monte Carlo grid measurement behind the
# M3b empirical-coverage claim through the U-M3b-03 kernel face
# (`ms_calibration_grid_rust`, src/rust/src/calibrate.rs): per grid cell
# (one catalog size N x one true share) the kernel draws `m` replicates from
# the selected generative arm, fits each with the PRODUCTION face
# (likelihood_bidirectional + share zeroing at 0.01 + rescale) and tallies
# whether the true exposure lies inside the selected CI face (percentile or
# BCa) over every truth-supported signature -- the estimand-(2) marginal
# coverage -- plus the estimand-(3) compound-zeroing confusion tallies.
#
# The R face owns curve assembly (one tidy row per cell) and the window
# verdict. The acceptance window and its semantics live kernel-side
# (calibrate.rs `CALIBRATION_WINDOW`); the frozen constants below are the
# R-side mirror used as defaults -- re-freezing moves both sides together.
#
# The grid driver is a CALIBRATION-BENCH instrument (memo section 5, the
# U-M3b-03 row: the driver never becomes a silent user promise); it is
# exported here because the R curve/verdict/plot/sanity faces of M3b need a
# stable, documented callable. The empirical-coverage DECLARATION itself is
# made by the bench at the frozen protocol (M = 2000, n_boot = 1000, the
# 11 x 3 x 6 grid over the truth dictionaries), not by this function's
# arguments.
#
# Error protocol: all violations raise msuiter_error_* conditions
# (ARCHITECTURE section 3.5); the R validators fire first and the kernel
# re-validates every domain behind the boundary.

# Frozen 4SE acceptance window (kernel calibrate.rs CALIBRATION_WINDOW;
# memo section 1.3: M = 2000 reps gives 4*sqrt(0.95*0.05/2000) ~ 0.0195
# around the 0.95 nominal level). Inclusive at both ends.
.MS_CALIBRATION_WINDOW <- c(lo = 0.930, hi = 0.970)

# Bare arm names accepted by the kernel's GenerativeArm::parse; "nb:<size>"
# strings select the negative-binomial arm with an explicit size.
.MS_CALIBRATION_ARMS <- c("multinomial", "poisson")

# ---------------------------------------------------------------------------
# Scalar gates (first layer; the kernel re-checks every domain)
# ---------------------------------------------------------------------------

# The swept catalog-size axis: positive whole numbers, strictly increasing
# (the R-face curve contract -- a calibration curve is read along an
# increasing N axis), each within the i32 wire range.
.ms_calibration_gate_n_grid <- function(n_grid) {
  if (!is.numeric(n_grid) || length(n_grid) < 1L || anyNA(n_grid) ||
      any(!is.finite(n_grid)) || any(n_grid != floor(n_grid)) ||
      any(n_grid < 1) || any(n_grid > 2147483647)) {
    msuiter_abort(
      "input",
      "n_grid must be a vector of whole numbers in [1, 2^31 - 1]",
      i = "n_grid is the swept catalog-size (mutation burden) axis of the calibration grid",
      j = paste0("received: ", msuiter_quote_trunc(n_grid)),
      c = "pass positive whole catalog sizes, e.g. c(50, 100, 250, 500, 1000)"
    )
  }
  if (length(n_grid) > 1L && any(diff(n_grid) <= 0)) {
    msuiter_abort(
      "input",
      "n_grid must be strictly increasing",
      i = "the calibration curve is read along an increasing N axis (U-M3b-04 R-face contract)",
      j = paste0("offending pair: ", msuiter_quote_trunc(n_grid)),
      c = "sort n_grid ascending, e.g. sort(unique(n_grid))"
    )
  }
  invisible(NULL)
}

# The true-share axis: finite fractions in [0, 1] (0 = the decoy cell of the
# estimand-(3) FPR point; the memo share axis spans both sides of the 0.01
# zeroing anchor).
.ms_calibration_gate_shares <- function(shares) {
  if (!is.numeric(shares) || length(shares) < 1L || anyNA(shares) ||
      any(!is.finite(shares))) {
    msuiter_abort(
      "input",
      "shares must be a finite numeric vector without NA",
      i = "shares is the swept TRUE share of the target signature (estimand 2 axis)",
      j = paste0("received: ", msuiter_quote_trunc(shares)),
      c = "pass fractions in [0, 1], e.g. c(0.005, 0.01, 0.02, 0.05, 0.10, 0.25)"
    )
  }
  bad <- which(shares < 0 | shares > 1)
  if (length(bad) > 0L) {
    msuiter_abort(
      "input",
      "every share must lie in [0, 1]",
      i = "a share is the target signature's fraction of the true exposure spectrum",
      j = sprintf("first offender at position %d: %s", bad[1],
        format(shares[bad[1]])),
      c = "pass fractions in [0, 1] (0 makes the target a decoy)"
    )
  }
  invisible(NULL)
}

# The Monte Carlo replicate count `m` (the memo's capital M: replicates per
# grid cell) -- the window's 4SE width is derived at m = 2000.
.ms_calibration_gate_m <- function(m) {
  if (!is.numeric(m) || length(m) != 1L || is.na(m) || !is.finite(m) ||
      m != floor(m) || m < 1 || m > 2147483647) {
    msuiter_abort(
      "input",
      "m must be a single whole number in [1, 2^31 - 1]",
      i = "m is the Monte Carlo replicate count per grid cell (the memo's M; the 4SE window derivation assumes m = 2000)",
      j = paste0("received: ", msuiter_quote_trunc(m)),
      c = "pass the frozen bench protocol value 2000, or a reduced m for smoke runs"
    )
  }
  invisible(NULL)
}

# The synthetic sample count per replicate (the memo's catalogs are single
# synthetic samples; the kernel supports n >= 1).
.ms_calibration_gate_n_samples <- function(n_samples) {
  if (!is.numeric(n_samples) || length(n_samples) != 1L || is.na(n_samples) ||
      !is.finite(n_samples) || n_samples != floor(n_samples) ||
      n_samples < 1 || n_samples > 2147483647) {
    msuiter_abort(
      "input",
      "n_samples must be a single whole number in [1, 2^31 - 1]",
      i = "n_samples is the number of synthetic catalog columns drawn per replicate",
      j = paste0("received: ", msuiter_quote_trunc(n_samples)),
      c = "leave the default 1 (one synthetic sample per replicate, the memo protocol)"
    )
  }
  invisible(NULL)
}

# The generative arm selector: "multinomial" (main arm), "poisson" (the
# exact NB limit) or "nb:<size>" with a positive finite (or inf) size.
.ms_calibration_gate_arm <- function(arm) {
  ok_shape <- is.character(arm) && length(arm) == 1L && !is.na(arm) &&
    nzchar(arm)
  if (!ok_shape) {
    msuiter_abort(
      "input",
      "arm must be a single string",
      i = paste("the arm selects the generative model:",
        paste(.MS_CALIBRATION_ARMS, collapse = ", "), 'or "nb:<size>"'),
      j = paste0("received: ", msuiter_quote_trunc(arm)),
      c = 'pass "multinomial" (default main arm), "poisson" or "nb:8"'
    )
  }
  ok <- arm %in% .MS_CALIBRATION_ARMS ||
    (startsWith(arm, "nb:") && {
      size <- suppressWarnings(as.numeric(substr(arm, 4L, nchar(arm))))
      length(size) == 1L && !is.na(size) && (is.finite(size) && size > 0 ||
        is.infinite(size) && size > 0)
    })
  if (!ok) {
    msuiter_abort(
      "input",
      "arm must be one of \"multinomial\", \"poisson\" or \"nb:<size>\"",
      i = "the two arms must never be mixed into one calibration claim (memo section 2.2)",
      j = paste0('received: "', arm, '"'),
      c = 'pass "multinomial" (main arm), "poisson" (exact NB limit) or "nb:8" (the kappa = 8 stress anchor)'
    )
  }
  invisible(NULL)
}

# The acceptance window: two finite fractions in [0, 1], lo <= hi.
.ms_calibration_gate_window <- function(window) {
  if (!is.numeric(window) || length(window) != 2L || anyNA(window) ||
      any(!is.finite(window)) || any(window < 0) || any(window > 1) ||
      window[[1]] > window[[2]]) {
    msuiter_abort(
      "input",
      "window must be c(lo, hi): two finite numbers in [0, 1] with lo <= hi",
      i = "the window is the inclusive 4SE acceptance band of the coverage verdict",
      j = paste0("received: ", msuiter_quote_trunc(window)),
      c = "pass the frozen default c(0.930, 0.970), or re-derive it with the memo's 4SE construction"
    )
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# User face: ms_calibration_grid() + ms_calibration_verdict()
# ---------------------------------------------------------------------------

#' Monte Carlo calibration grid for exposure confidence intervals
#'
#' `ms_calibration_grid()` measures the **empirical coverage** of the
#' [ms_fit_bootstrap()] confidence intervals over a grid of catalog sizes
#' and true signature shares -- the M3b calibration experiment behind the
#' MSU-Fit estimand-(2) declaration (design memo
#' docs/devlog/2026-10-04-M3b-design-memo.md, sections 1-3, PI ruling
#' 2026-10-04). Per grid cell (one catalog size N x one true share) the
#' kernel draws `m` synthetic replicates from the selected generative arm,
#' fits each with the production face (`"likelihood_bidirectional"`, share
#' zeroing at 0.01, TMB rescale) and tallies whether the true exposure lies
#' inside the selected CI face over every truth-supported signature (the
#' marginal coverage event), plus the compound-zeroing confusion tallies
#' (estimand 3).
#'
#' @param sigs Numeric matrix (channels x signatures): the truth dictionary
#'   of ONE entropy arm of the memo's N x H* x share grid (the entropy axis
#'   is a separate call per truth dictionary). Columns must be non-negative
#'   with positive mass; the channel count is arbitrary (the kernel
#'   normalizes the truth spectrum internally, memo section 2.1).
#' @param n_grid Increasing vector of positive whole numbers: the swept
#'   catalog-size (mutation burden N) axis, e.g. the memo's 11 log points
#'   `c(50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000)`.
#' @param shares Numeric vector in \eqn{[0, 1]}: the swept TRUE share of the
#'   target signature (dictionary column 1; the residual mass splits equally
#'   over the remaining columns, last entry taking the exact remainder --
#'   the kernel's frozen truth convention). Share 0 makes the target a decoy
#'   (the estimand-(3) FPR cell).
#' @param m Single positive whole number: Monte Carlo replicates per grid
#'   cell (the memo's M; the frozen bench protocol is `m = 2000`, which
#'   derives the default 4SE acceptance window).
#' @param n_boot Single positive whole number: bootstrap replicates inside
#'   every Monte Carlo fit (frozen protocol: 1000).
#' @param bca Single logical (default `FALSE`): read the BCa face instead of
#'   the percentile face for the coverage event (the PI-ruled default
#'   interval family; `bca = FALSE` reads the plain percentile bounds).
#' @param n_threads NULL (resolve the `msuiter.threads` option, capped by
#'   `_R_CHECK_LIMIT_CORES_`) or a single non-negative integer pool size;
#'   0 means the rayon default. Parallelism runs BETWEEN (cell x replicate)
#'   units only; the output is bit-identical for every thread count.
#' @param seed Single non-negative whole number: the master seed of the
#'   canonical PCG64 stream layout (the grid is a bitwise function of it;
#'   memo section 2.1 stream layout).
#' @param n_samples Single positive whole number (default 1): synthetic
#'   catalog columns per replicate (the memo protocol is one synthetic
#'   sample per replicate).
#' @param nb_size Single positive number: the negative-binomial size of the
#'   fit face (mSigAct `nbinom.size`; default 8, the SBS96 anchor). Only
#'   used by the likelihood methods internally; see [ms_fit()].
#' @param arm Single string: the generative model --
#'   `"multinomial"` (default; the total-conserving MAIN arm, the
#'   calibration-declaration carrier), `"poisson"` (the exact negative-
#'   binomial limit) or `"nb:<size>"` (the Jiang per-channel overdispersion
#'   stress arm, e.g. `"nb:8"` at the mSigAct kappa anchor). The two arm
#'   families must never be mixed into one calibration claim (memo section
#'   2.2).
#' @param window Numeric `c(lo, hi)`: the inclusive acceptance band of the
#'   verdict (default `c(0.930, 0.970)`, the frozen 4SE window at
#'   `m = 2000`).
#'
#' @details
#' **Truth convention (frozen).** Grid cell `c = n_idx * length(shares) +
#' share_idx` (1-based in the returned table) draws its truth spectrum as:
#' signature 1 carries `share * N`; the residual `N - share * N` splits
#' equally over signatures 2..k (the last entry takes the exact remainder),
#' so the spectrum sums to N exactly in double arithmetic. A `k = 1`
#' dictionary degenerates to the single signature carrying the whole
#' catalog.
#'
#' **Determinism.** The output is a pure function of the inputs:
#' `threads 1` and `N` are bit-identical, and the same `seed` reproduces the
#' table bitwise. MC streams live on `StreamId\{replicate, rank: cell_id,
#' fold: 0\}` -- disjoint from the bootstrap (`rank = 0`) and CV
#' (`fold >= 1`) bands.
#'
#' **Result.** A data.frame with one row per grid cell (n_grid-major x
#' shares order): `n` (catalog size), `share` (true share), `cell`
#' (1-based cell id), `mean_coverage` (pooled marginal coverage fraction),
#' `se` (binomial standard error at the observed fraction), `n_reps`
#' (replicates aggregated), `pass_window` (kernel-side window membership),
#' and the confusion tallies `true_zero` / `false_keep` / `false_zero` /
#' `kept_covered` / `kept_missed` (estimand 3, memo section 3). Attributes
#' carry the protocol echoes (`window`, `arm`, `bca`, `n_boot`, `seed`,
#' `n_samples`, `nb_size`). Feed the table to [ms_calibration_verdict()]
#' for the structured verdict and to [plot_calibration_curve()] for the
#' coverage-vs-N curve.
#'
#' All violations raise `msuiter_error_*` conditions.
#'
#' @return A data.frame (one row per grid cell) carrying the protocol
#'   attributes described above.
#'
#' @seealso [ms_calibration_verdict()] for the verdict,
#'   [plot_calibration_curve()] for the curve,
#'   [ms_fit_bootstrap()] for the interval face being measured.
#' @export
ms_calibration_grid <- function(sigs, n_grid, shares, m = 2000,
                                n_boot = 1000, bca = FALSE, n_threads = NULL,
                                seed = 1, n_samples = 1, nb_size = 8,
                                arm = "multinomial",
                                window = .MS_CALIBRATION_WINDOW) {
  # --- first-layer validation (R face) -------------------------------------
  sigs <- .ms_validate_matrix(sigs, "sigs")
  if (nrow(sigs) < 1L || ncol(sigs) < 1L) {
    msuiter_abort(
      "input",
      "sigs must have at least one channel row and one signature column",
      i = "the truth dictionary defines the generative model of every grid cell",
      j = sprintf("received: %d x %d", nrow(sigs), ncol(sigs)),
      c = "pass a channels x signatures truth matrix with positive column masses"
    )
  }
  if (any(sigs < 0)) {
    bad <- which(sigs < 0)[1L]
    msuiter_abort(
      "input",
      "sigs must be non-negative",
      i = "signature profiles are channel mass fractions",
      j = sprintf("first offender at row %d, column %d",
        (bad - 1L) %% nrow(sigs) + 1L, (bad - 1L) %/% nrow(sigs) + 1L),
      c = "pass a non-negative truth dictionary"
    )
  }
  .ms_calibration_gate_n_grid(n_grid)
  .ms_calibration_gate_shares(shares)
  .ms_calibration_gate_m(m)
  .ms_fit_gate_boot(n_boot, seed)
  if (!is.logical(bca) || length(bca) != 1L || is.na(bca)) {
    msuiter_abort(
      "input",
      "bca must be a single TRUE or FALSE",
      i = "bca selects which CI face the coverage event reads",
      j = paste0("received: ", msuiter_quote_trunc(bca)),
      c = "leave the default FALSE for the percentile face, or TRUE for the BCa face (the PI-ruled default family)"
    )
  }
  .ms_calibration_gate_n_samples(n_samples)
  .ms_fit_gate_nb_size(nb_size)
  .ms_calibration_gate_arm(arm)
  .ms_calibration_gate_window(window)
  n_threads_resolved <- .ms_resolve_threads(n_threads)

  # --- kernel face (re-validates every domain; layout: R passes t(sigs)) ---
  res <- .ms_calibration_grid_rust(
    sigs = sigs, n_grid = n_grid, shares = shares, n_samples = n_samples,
    m = m, n_boot = n_boot, nb_size = nb_size, bca = bca, arm = arm,
    seed = seed, window = window, n_threads = n_threads_resolved
  )

  # --- curve assembly: one tidy row per cell (n_grid-major x shares) -------
  out <- data.frame(
    n = rep(as.numeric(n_grid), each = length(shares)),
    share = rep(as.numeric(shares), times = length(n_grid)),
    cell = seq_along(res$mean_coverage),
    mean_coverage = res$mean_coverage,
    se = res$se,
    n_reps = rep(as.integer(res$n_reps), length(res$mean_coverage)),
    pass_window = as.logical(res$per_cell_in),
    true_zero = res$true_zero,
    false_keep = res$false_keep,
    false_zero = res$false_zero,
    kept_covered = res$kept_covered,
    kept_missed = res$kept_missed,
    stringsAsFactors = FALSE
  )
  attr(out, "window") <- as.numeric(window)
  attr(out, "arm") <- res$arm
  attr(out, "bca") <- res$bca
  attr(out, "n_boot") <- res$n_boot
  attr(out, "seed") <- res$seed
  attr(out, "n_samples") <- as.integer(n_samples)
  attr(out, "nb_size") <- as.numeric(nb_size)
  attr(out, "n_grid") <- as.numeric(n_grid)
  attr(out, "shares") <- as.numeric(shares)
  out
}

#' Structured window verdict over a calibration grid
#'
#' `ms_calibration_verdict()` re-derives the M3b acceptance verdict of a
#' [ms_calibration_grid()] table in pure R -- the twin of the kernel-side
#' `calibration_verdict` (same inclusive membership semantics, pinned equal
#' by tests): a cell passes iff its `mean_coverage` lies inside the
#' inclusive `[lo, hi]` window.
#'
#' @param calibration A data.frame as returned by [ms_calibration_grid()]
#'   (must expose a numeric, NA-free `mean_coverage` column).
#' @param window Numeric `c(lo, hi)`: the acceptance band. Defaults to the
#'   table's recorded `window` attribute, falling back to the frozen
#'   `c(0.930, 0.970)`.
#'
#' @return A named list:
#'   * `all_in_window` -- single logical, TRUE iff every cell passed;
#'   * `per_cell_in` -- logical vector, window membership per cell (input
#'     order);
#'   * `failing_cells` -- integer vector of the 1-based cell indices outside
#'     the window (empty when `all_in_window` is TRUE);
#'   * `window` -- the band actually applied.
#'
#'   All violations raise `msuiter_error_*` conditions.
#'
#' @seealso [ms_calibration_grid()] for the measurement,
#'   [plot_calibration_curve()] for the visual verdict.
#' @export
ms_calibration_verdict <- function(calibration, window = NULL) {
  if (!is.data.frame(calibration) ||
      !is.numeric(calibration$mean_coverage) ||
      anyNA(calibration$mean_coverage) || nrow(calibration) < 1L) {
    msuiter_abort(
      "input",
      "calibration must be a data.frame with an NA-free numeric mean_coverage column",
      i = "the verdict judges the per-cell pooled coverage fractions of a calibration grid",
      j = paste0("received: ", msuiter_quote_trunc(class(calibration)[1L])),
      c = "pass the table returned by ms_calibration_grid()"
    )
  }
  if (is.null(window)) {
    window <- attr(calibration, "window")
  }
  if (is.null(window)) {
    window <- .MS_CALIBRATION_WINDOW
  }
  .ms_calibration_gate_window(window)
  lo <- as.numeric(window[[1L]])
  hi <- as.numeric(window[[2L]])
  per_cell_in <- calibration$mean_coverage >= lo &
    calibration$mean_coverage <= hi
  failing <- which(!per_cell_in)
  list(
    all_in_window = length(failing) == 0L,
    per_cell_in = unname(per_cell_in),
    failing_cells = as.integer(failing),
    window = c(lo = lo, hi = hi)
  )
}

# ---------------------------------------------------------------------------
# FFI wrapper over ms_calibration_grid_rust (U-M3b-03 kernel face). Layout
# contract (lib.rs module docs): R passes t(sigs) -- the k x m column-major
# flat buffer IS the row-major m x k truth dictionary the kernel reads.
# The kernel re-validates every scalar domain (contract 4).
# ---------------------------------------------------------------------------

#' Calibration-grid kernel wrapper over ms_calibration_grid_rust.
#' @param sigs,n_grid,shares,n_samples,m,n_boot,nb_size,bca,arm,seed,window,n_threads
#'   Validated arguments of [ms_calibration_grid()].
#' @return Named list from the kernel: per-cell aggregates, protocol echoes
#'   and the kernel-side verdict fields.
#' @keywords internal
#' @noRd
.ms_calibration_grid_rust <- function(sigs, n_grid, shares, n_samples, m,
                                      n_boot, nb_size, bca, arm, seed,
                                      window, n_threads = NULL) {
  sigs <- .ms_validate_matrix(sigs, "sigs")
  n_threads_resolved <- .ms_resolve_threads(n_threads)
  .msffi_check(ms_calibration_grid_rust(
    t(sigs), as.integer(n_grid), as.numeric(shares), as.integer(n_samples),
    as.integer(m), as.integer(n_boot), as.numeric(nb_size), bca,
    as.character(arm), as.integer(seed), as.numeric(window[[1L]]),
    as.numeric(window[[2L]]), n_threads_resolved
  ))
}
