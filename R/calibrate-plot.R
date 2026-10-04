# calibrate-plot.R: the calibration-curve visualization face (U-M3b-05;
# ARCHITECTURE section 5 MSU-Fit row "校准诊断图", CAPABILITY-MATRIX item 7
# "覆盖率曲线作为一等可视化", design memo docs/devlog/2026-10-04-M3b-design-memo.md
# section 2.3 "覆盖率曲线读法").
#
# `plot_calibration_curve()` renders one [ms_calibration_grid()] table as
# the empirical-coverage-vs-N curve: one panel per true share, the frozen
# 4SE acceptance window as a shaded band, per-cell binomial standard errors
# as error bars and failing cells (outside the window) as red cross
# markers -- the acceptance gate made visually auditable (the automated
# gate itself is ms_calibration_verdict(); the plot never re-judges).
#
# ggplot2 is a Suggests dependency (the dependency budget is closed,
# D2/D4): the face degrades to a structured msuiter_error_* condition when
# the package is absent instead of failing at load time.
#
# Error protocol: all violations raise msuiter_error_* conditions.

# Require the suggested ggplot2 at call time (never at load time).
.ms_calibration_require_ggplot2 <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    msuiter_abort(
      "package",
      "ggplot2 is required for plot_calibration_curve() but is not installed",
      i = "the calibration-curve face renders through ggplot2 (a Suggests dependency)",
      j = paste0("requireNamespace('ggplot2') returned FALSE (search path: ",
        paste(.libPaths(), collapse = .Platform$path.sep), ")"),
      c = "install ggplot2 (install.packages('ggplot2')) and retry"
    )
  }
  invisible(NULL)
}

# Validate the calibration table's plot-facing columns (the shared shape of
# the ms_calibration_grid() output).
.ms_calibration_plot_table <- function(calibration_df, needs_se = TRUE) {
  if (!is.data.frame(calibration_df)) {
    msuiter_abort(
      "input",
      "calibration_df must be a data.frame",
      i = "the curve face renders one ms_calibration_grid() table",
      j = paste0("received: ", msuiter_quote_trunc(class(calibration_df)[1L])),
      c = "pass the table returned by ms_calibration_grid()"
    )
  }
  required <- c("n", "share", "mean_coverage", "pass_window")
  if (needs_se) required <- c(required, "se")
  missing <- setdiff(required, names(calibration_df))
  if (length(missing) > 0L) {
    msuiter_abort(
      "input",
      "calibration_df is missing required columns",
      i = "the curve face reads the ms_calibration_grid() output shape (n / share / mean_coverage / se / pass_window)",
      j = paste0("missing columns: ", msuiter_quote_trunc(missing)),
      c = "pass the unmodified table returned by ms_calibration_grid()"
    )
  }
  if (!is.numeric(calibration_df$n) || anyNA(calibration_df$n) ||
      any(calibration_df$n <= 0)) {
    msuiter_abort(
      "input",
      "calibration_df$n must be positive numeric catalog sizes",
      i = "the x axis is the mutation-burden axis on a log scale",
      j = paste0("received: ", msuiter_quote_trunc(calibration_df$n)),
      c = "pass the unmodified table returned by ms_calibration_grid()"
    )
  }
  if (!is.numeric(calibration_df$mean_coverage) ||
      anyNA(calibration_df$mean_coverage)) {
    msuiter_abort(
      "input",
      "calibration_df$mean_coverage must be numeric without NA",
      i = "the y axis is the empirical coverage fraction per cell",
      j = paste0("received: ", msuiter_quote_trunc(calibration_df$mean_coverage)),
      c = "pass the unmodified table returned by ms_calibration_grid()"
    )
  }
  invisible(NULL)
}

#' Plot the calibration coverage curve of a grid measurement
#'
#' `plot_calibration_curve()` renders an empirical-coverage-vs-N curve from
#' an [ms_calibration_grid()] table (U-M3b-05): one facet per true share,
#' the acceptance window as a shaded band, per-cell binomial standard
#' errors as error bars, and cells outside the window as red cross markers.
#' The plot is the visual twin of [ms_calibration_verdict()] -- it never
#' re-judges, it only marks the kernel-side `pass_window` column.
#'
#' @importFrom rlang .data
#'
#' @param calibration_df A data.frame as returned by [ms_calibration_grid()]
#'   (columns `n`, `share`, `mean_coverage`, `se`, `pass_window`).
#' @param window Numeric `c(lo, hi)`: the shaded acceptance band. Defaults
#'   to the table's recorded `window` attribute, falling back to the frozen
#'   `c(0.930, 0.970)`.
#' @param se Single logical (default `TRUE`): draw the binomial standard
#'   errors (requires the `se` column).
#'
#' @return A ggplot object. All violations raise `msuiter_error_*`
#'   conditions (including the missing-ggplot2 case: ggplot2 is a Suggests
#'   dependency and is required only at call time).
#'
#' @seealso [ms_calibration_grid()] for the measurement,
#'   [ms_calibration_verdict()] for the automated gate.
#' @export
plot_calibration_curve <- function(calibration_df, window = NULL, se = TRUE) {
  if (!is.logical(se) || length(se) != 1L || is.na(se)) {
    msuiter_abort(
      "input",
      "se must be a single TRUE or FALSE",
      i = "se toggles the per-cell binomial error bars",
      j = paste0("received: ", msuiter_quote_trunc(se)),
      c = "leave the default TRUE, or pass FALSE for bare curves"
    )
  }
  .ms_calibration_plot_table(calibration_df, needs_se = se)
  if (is.null(window)) {
    window <- attr(calibration_df, "window")
  }
  if (is.null(window)) {
    window <- .MS_CALIBRATION_WINDOW
  }
  .ms_calibration_gate_window(window)
  lo <- as.numeric(window[[1L]])
  hi <- as.numeric(window[[2L]])
  .ms_calibration_require_ggplot2()

  df <- calibration_df
  df$share_f <- factor(
    format(df$share, trim = TRUE, digits = 3),
    levels = format(sort(unique(df$share)), trim = TRUE, digits = 3)
  )
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$n, y = .data$mean_coverage)) +
    # The shaded acceptance band spans the panel behind the data. The band
    # edges are FINITE (a decade beyond the swept axis) because the log10
    # x transform produces NaN warnings on +/-Inf inputs.
    ggplot2::annotate(
      "rect",
      xmin = min(df$n) / 10, xmax = max(df$n) * 10,
      ymin = pmax(0, lo), ymax = pmin(1, hi),
      fill = "grey60", alpha = 0.30
    ) +
    ggplot2::geom_hline(
      yintercept = 0.95, linetype = 2, colour = "grey35", linewidth = 0.4
    )
  if (se) {
    p <- p + ggplot2::geom_errorbar(
      ggplot2::aes(
        ymin = pmax(0, .data$mean_coverage - .data$se),
        ymax = pmin(1, .data$mean_coverage + .data$se)
      ),
      width = 0.04, colour = "grey45"
    )
  }
  p <- p +
    ggplot2::geom_line(ggplot2::aes(group = .data$share_f), linewidth = 0.6) +
    ggplot2::geom_point(size = 2.1, colour = "steelblue4") +
    ggplot2::scale_x_log10() +
    ggplot2::facet_wrap(~ share_f, dir = "v") +
    ggplot2::coord_cartesian(ylim = c(0, 1))

  if (!is.logical(df$pass_window) || anyNA(df$pass_window)) {
    msuiter_abort(
      "input",
      "calibration_df$pass_window must be logical without NAs",
      i = "hand-built tables must pass the kernel verdict column verbatim",
      j = paste0("class: ", paste(class(df$pass_window), collapse = "/"),
                 "; NAs: ", sum(is.na(df$pass_window)))
    )
  }
  if (se && anyNA(df$se)) {
    msuiter_abort(
      "input",
      "calibration_df$se must be non-missing when se = TRUE",
      j = paste0("NAs: ", sum(is.na(df$se)))
    )
  }
  fail <- df[!df$pass_window, , drop = FALSE]
  if (nrow(fail) > 0L) {
    p <- p + ggplot2::geom_point(
      data = fail,
      ggplot2::aes(x = .data$n, y = .data$mean_coverage),
      inherit.aes = FALSE,
      colour = "firebrick", shape = 4, size = 3.4, stroke = 1.2
    )
  }
  # Caption echoes: NULL attributes (a hand-built table) degrade to NA/0.
  arm_echo <- attr(df, "arm"); if (is.null(arm_echo)) arm_echo <- NA_character_
  bca_echo <- attr(df, "bca"); if (is.null(bca_echo)) bca_echo <- NA
  boot_echo <- attr(df, "n_boot"); if (is.null(boot_echo)) boot_echo <- 0L
  seed_echo <- attr(df, "seed"); if (is.null(seed_echo)) seed_echo <- 0L
  p <- p +
    ggplot2::labs(
      x = "Catalog size N (mutations, log scale)",
      y = "Empirical coverage of the true exposure",
      title = "MSU-Fit calibration grid: coverage vs N",
      subtitle = sprintf(
        "Acceptance window [%.3f, %.3f] shaded; red crosses mark failing cells (%d/%d)",
        lo, hi, nrow(fail), nrow(df)
      ),
      caption = sprintf(
        "arm: %s | bca: %s | n_boot: %d | seed: %d",
        format(arm_echo), format(bca_echo),
        as.integer(boot_echo), as.integer(seed_echo)
      )
    ) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(legend.position = "none")
  p
}
