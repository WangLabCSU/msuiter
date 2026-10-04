# viz-bootstrap.R: the bootstrap CI faces (CAPABILITY-MATRIX L-F
# "bootstrap：CI 误差条、分布、覆盖率曲线（校准诊断图） | ✅ M3b/M4").
# The coverage-curve half is plot_calibration_curve() (U-M3b-05, the
# audited M3b face); this file adds the exposure-CI error bars and the
# bootstrap distribution faces for ms_fit_bootstrap() results.
#
# An MsFit from ms_fit_bootstrap() carries: exposures (k x n), with
# attributes ci_lower / ci_upper / support_stability / n_boot / seed /
# ci_level, and the support table with boot_stability. These faces read
# that contract directly (R/fit.R, U-M3a-03).

#' Bootstrap CI error bars for one sample's exposures
#'
#' Point exposures with their percentile/BCa CI whiskers for one sample,
#' ordered by exposure share. Zero-support signatures (share-zeroed by
#' the fit) are dropped unless `show_zero = TRUE`.
#'
#' @param fit An [MsFit] produced by [ms_fit_bootstrap()].
#' @param sample Sample name or index (one column).
#' @param show_zero Keep share-zeroed signatures in the plot.
#'
#' @return A ggplot object.
#' @export
plot_boot_ci <- function(fit, sample = 1L, show_zero = FALSE) {
  .ms_viz_require_ggplot()
  if (!S7::S7_inherits(fit, MsFit)) {
    msuiter_abort(
      "input",
      "fit must be an MsFit produced by ms_fit_bootstrap()",
      i = "the CI face reads the bootstrap attributes (ci_lower/ci_upper)",
      j = paste0("received: ", class(fit)[1L]),
      c = "pass the ms_fit_bootstrap() result"
    )
  }
  ci_lo <- attr(fit@exposures, "ci_lower")
  ci_hi <- attr(fit@exposures, "ci_upper")
  if (is.null(ci_lo) || is.null(ci_hi)) {
    msuiter_abort(
      "input",
      "the MsFit carries no bootstrap CI attributes",
      i = "ms_fit() point fits have no interval; bootstrap only",
      j = "ci_lower/ci_upper absent",
      c = "pass the ms_fit_bootstrap() result"
    )
  }
  idx <- .ms_viz_resolve_sample(fit@exposures, sample)
  sigs <- rownames(fit@exposures)
  if (is.null(sigs)) sigs <- paste0("sig", seq_len(nrow(fit@exposures)))
  df <- data.frame(
    signature = sigs,
    estimate = fit@exposures[, idx],
    lo = ci_lo[, idx],
    hi = ci_hi[, idx],
    stringsAsFactors = FALSE
  )
  stab <- attr(fit@exposures, "support_stability")
  if (!is.null(stab)) df$stability <- stab[, idx]
  if (!show_zero) df <- df[df$estimate > 0 | df$hi > 0, , drop = FALSE]
  df$signature <- factor(df$signature, levels = df$signature[order(-df$estimate)])
  n_boot <- attr(fit@exposures, "n_boot")
  level <- attr(fit@exposures, "ci_level")
  sub <- if (!is.null(level) && length(level) == 2L) {
    sprintf(" (%.0f%% CI, %d boots)", 100 * (level[2] - level[1]), n_boot)
  } else {
    ""
  }
  ggplot2::ggplot(df, ggplot2::aes(x = .data$signature,
                                   y = .data$estimate)) +
    ggplot2::geom_point(size = 2.6, colour = "#2166AC") +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$lo, ymax = .data$hi),
                           width = 0.25, colour = "#2166AC") +
    ggplot2::labs(
      x = NULL, y = "Exposure (mutations)",
      title = paste0("Bootstrap CIs: ", .ms_viz_sample_name(fit@exposures, idx),
                     sub)
    ) +
    .ms_viz_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45,
                                                       vjust = 1, hjust = 1))
}

#' Bootstrap exposure distributions for one sample
#'
#' Per-signature histograms of the RAW boot draws for one sample, with
#' the point estimate and the CI bounds marked. Requires the fit to
#' carry the draws cube (re-run [ms_fit_bootstrap()] with
#' `return_draws = TRUE`); without it the CI endpoints are the only
#' stored summary and the structured error says so.
#'
#' @inheritParams plot_boot_ci
#' @param bins Histogram bin count per signature (default 30).
#'
#' @return A ggplot object.
#'
#' @export
plot_boot_distribution <- function(fit, sample = 1L, bins = 30L) {
  .ms_viz_require_ggplot()
  if (!S7::S7_inherits(fit, MsFit)) {
    msuiter_abort(
      "input",
      "fit must be an MsFit produced by ms_fit_bootstrap(return_draws = TRUE)",
      i = "the histogram face reads the boot_draws attribute",
      j = paste0("received: ", class(fit)[1L]),
      c = "re-run ms_fit_bootstrap(..., return_draws = TRUE)"
    )
  }
  draws <- attr(fit@exposures, "boot_draws")
  if (is.null(draws)) {
    msuiter_abort(
      "input",
      "the MsFit carries no boot_draws attribute",
      i = "the raw draws are only stored when ms_fit_bootstrap() was called with return_draws = TRUE",
      j = "boot_draws absent",
      c = "re-run ms_fit_bootstrap(..., return_draws = TRUE)"
    )
  }
  idx <- .ms_viz_resolve_sample(fit@exposures, sample)
  sigs <- rownames(fit@exposures)
  if (is.null(sigs)) sigs <- paste0("sig", seq_len(nrow(fit@exposures)))
  ci_lo <- attr(fit@exposures, "ci_lower")
  ci_hi <- attr(fit@exposures, "ci_upper")
  est <- fit@exposures[, idx]
  long <- do.call(rbind, lapply(seq_len(nrow(draws)), function(a) {
    data.frame(
      signature = sigs[a],
      value = as.numeric(draws[a, idx, ]),
      estimate = unname(est[a]),
      lo = unname(ci_lo[a, idx]),
      hi = unname(ci_hi[a, idx]),
      stringsAsFactors = FALSE
    )
  }))
  long$signature <- factor(long$signature, levels = sigs[order(-est)])
  ggplot2::ggplot(long, ggplot2::aes(x = .data$value)) +
    ggplot2::geom_histogram(bins = bins, fill = "#2166AC",
                            colour = "white", linewidth = 0.2) +
    ggplot2::geom_vline(ggplot2::aes(xintercept = .data$estimate),
                        linewidth = 0.6) +
    ggplot2::geom_vline(ggplot2::aes(xintercept = .data$lo),
                        linetype = "dashed", colour = "grey40",
                        linewidth = 0.4) +
    ggplot2::geom_vline(ggplot2::aes(xintercept = .data$hi),
                        linetype = "dashed", colour = "grey40",
                        linewidth = 0.4) +
    ggplot2::facet_wrap(~signature, scales = "free_x") +
    ggplot2::labs(x = "Boot exposure (mutations)", y = "Replicates",
                  title = paste0("Bootstrap distributions: ",
                                 .ms_viz_sample_name(fit@exposures, idx))) +
    .ms_viz_theme() +
    ggplot2::theme(strip.text = ggplot2::element_text(face = "bold"))
}

#' Bootstrap stability bar face
#'
#' Per-signature bootstrap support stability for one sample against the
#' 0.95 floor (the M3b calibration driver's CALIBRATION_STABILITY_FLOOR
#' -- the compound zeroing rule's stability clause).
#'
#' @inheritParams plot_boot_ci
#'
#' @return A ggplot object.
#' @export
plot_boot_stability <- function(fit, sample = 1L) {
  .ms_viz_require_ggplot()
  if (!S7::S7_inherits(fit, MsFit)) {
    msuiter_abort(
      "input",
      "fit must be an MsFit produced by ms_fit_bootstrap()",
      i = "the stability face reads the support_stability attribute",
      j = paste0("received: ", class(fit)[1L]),
      c = "pass the ms_fit_bootstrap() result"
    )
  }
  stab <- attr(fit@exposures, "support_stability")
  if (is.null(stab)) {
    msuiter_abort(
      "input",
      "the MsFit carries no support_stability attribute",
      i = "stability comes from ms_fit_bootstrap()",
      j = "support_stability absent",
      c = "pass the ms_fit_bootstrap() result"
    )
  }
  idx <- .ms_viz_resolve_sample(fit@exposures, sample)
  sigs <- rownames(fit@exposures)
  if (is.null(sigs)) sigs <- paste0("sig", seq_len(nrow(fit@exposures)))
  df <- data.frame(signature = sigs, stability = stab[, idx],
                   stringsAsFactors = FALSE)
  df$signature <- factor(df$signature, levels = df$signature[order(-df$stability)])
  ggplot2::ggplot(df, ggplot2::aes(x = .data$signature,
                                   y = .data$stability)) +
    ggplot2::geom_col(width = 0.7, fill = "#2166AC") +
    ggplot2::geom_hline(yintercept = 0.95, linetype = "dashed",
                        colour = "#E42926", linewidth = 0.4) +
    ggplot2::annotate("text", x = 1, y = 0.95,
                      label = "stability floor 0.95", hjust = -0.05,
                      vjust = -0.4, size = 2.8, colour = "grey30") +
    ggplot2::ylim(0, 1) +
    ggplot2::labs(x = NULL, y = "Boot support stability",
                  title = paste0("Bootstrap stability: ",
                                 .ms_viz_sample_name(fit@exposures, idx))) +
    .ms_viz_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45,
                                                       vjust = 1, hjust = 1))
}

# Sample resolution shared by the three faces.
.ms_viz_resolve_sample <- function(exposures, sample) {
  n <- ncol(exposures)
  if (is.numeric(sample) || is.integer(sample)) {
    idx <- as.integer(sample)
    if (length(idx) != 1L || idx < 1L || idx > n) {
      msuiter_abort(
        "input",
        "sample index out of range",
        i = "sample selects one exposure column",
        j = sprintf("requested: %d; columns: %d", idx, n),
        c = "use an index in [1, ncol] or a sample name"
      )
    }
    return(idx)
  }
  if (is.character(sample)) {
    cn <- colnames(exposures)
    if (is.null(cn) || !sample %in% cn) {
      msuiter_abort(
        "input",
        "sample name not found among the exposure columns",
        i = "sample selects one exposure column by colname",
        j = sprintf("requested: %s", msuiter_quote_trunc(sample)),
        c = "use a colname of the exposure matrix or an index"
      )
    }
    return(match(sample, cn))
  }
  msuiter_abort(
    "input",
    "sample must be an index or a column name",
    i = "one sample per CI face",
    j = paste0("received: ", msuiter_quote_trunc(sample))
  )
}

.ms_viz_sample_name <- function(exposures, idx) {
  cn <- colnames(exposures)
  if (!is.null(cn)) cn[idx] else sprintf("column %d", idx)
}
