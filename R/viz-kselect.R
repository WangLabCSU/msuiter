# viz-kselect.R: the K-selection evidence faces (CAPABILITY-MATRIX L-F
# "K 选择证据：稳定性曲线、CV 误差、多证据表可视化 | ✅ M2/M4"; the
# ms_select_k() evidence table is the M2 contract, U-M2-02/03).
#
#   plot_k_cv_curve       -- CV test deviance vs k, argmin marked
#   plot_k_stability      -- avg + min-cluster stability vs k, veto lines
#
# Both read the k_evidence data.frame from ms_select_k() (the memo-3
# schema; R/kselect-select.R .ms_k_evidence_columns). ggplot2 Suggests,
# the viz batch conventions (canonical inputs, structured errors with
# the full i/j/c payload).

#' Plot the CV-error curve from K-selection evidence
#'
#' The layer-1 arbitration evidence at a glance: CV test deviance per
#' rank with the argmin rank (the first minimum) highlighted. Ranks that
#' failed the layer-2 stability veto are marked.
#'
#' @param k_evidence The `k_evidence` data.frame returned by
#'   [ms_select_k()] (columns k / cv_test_deviance / avg_stability /
#'   passes_veto / is_argmin / selected).
#'
#' @return A ggplot object.
#' @export
plot_k_cv_curve <- function(k_evidence) {
  .ms_viz_require_ggplot()
  ev <- .ms_viz_check_k_evidence(k_evidence)
  argmin <- ev$k[ev$is_argmin]
  selected <- ev$k[ev$selected]
  p <- ggplot2::ggplot(ev, ggplot2::aes(x = .data$k,
                                        y = .data$cv_test_deviance)) +
    ggplot2::geom_line(colour = "grey40", linewidth = 0.5) +
    ggplot2::geom_point(ggplot2::aes(colour = .data$passes_veto),
                        size = 2.4) +
    ggplot2::scale_colour_manual(values = c(`TRUE` = "#2166AC",
                                            `FALSE` = "#E42926"),
                                 name = "passes veto",
                                 na.translate = FALSE) +
    ggplot2::scale_x_continuous(breaks = ev$k) +
    ggplot2::labs(x = "Rank k", y = "CV test deviance",
                  title = .ms_viz_k_title(argmin, selected)) +
    .ms_viz_theme()
  if (length(selected) == 1L && !is.na(selected)) {
    p <- p + ggplot2::geom_point(data = ev[ev$k == selected, ],
                                 shape = 21, size = 4.2, stroke = 1.2,
                                 colour = "black", fill = NA)
  }
  p
}

#' Plot the consensus-stability curves from K-selection evidence
#'
#' The layer-2 arbitration evidence: the average per-cluster stability
#' and the minimum cluster stability per rank, with the upstream veto
#' thresholds (avg >= 0.8, min >= 0.2) as reference lines.
#'
#' @inheritParams plot_k_cv_curve
#'
#' @return A ggplot object.
#' @export
plot_k_stability <- function(k_evidence) {
  .ms_viz_require_ggplot()
  ev <- .ms_viz_check_k_evidence(k_evidence)
  long <- rbind(
    data.frame(k = ev$k, value = ev$avg_stability, stat = "avg"),
    data.frame(k = ev$k, value = ev$min_cluster_stability,
               stat = "min cluster"),
    stringsAsFactors = FALSE
  )
  ggplot2::ggplot(long, ggplot2::aes(x = .data$k, y = .data$value,
                                     colour = .data$stat)) +
    ggplot2::geom_line(linewidth = 0.5) +
    ggplot2::geom_point(size = 2.2) +
    ggplot2::geom_hline(yintercept = 0.8, linetype = "dashed",
                        colour = "grey40", linewidth = 0.4) +
    ggplot2::geom_hline(yintercept = 0.2, linetype = "dashed",
                        colour = "grey40", linewidth = 0.4) +
    ggplot2::annotate("text", x = min(ev$k), y = 0.8,
                      label = "avg veto 0.80", hjust = -0.05, vjust = -0.4,
                      size = 2.8, colour = "grey30") +
    ggplot2::annotate("text", x = min(ev$k), y = 0.2,
                      label = "min veto 0.20", hjust = -0.05, vjust = -0.4,
                      size = 2.8, colour = "grey30") +
    ggplot2::scale_x_continuous(breaks = ev$k) +
    ggplot2::ylim(0, 1) +
    ggplot2::labs(x = "Rank k", y = "Consensus stability",
                  colour = NULL,
                  title = .ms_viz_k_title(ev$k[ev$is_argmin],
                                          ev$k[ev$selected])) +
    .ms_viz_theme()
}

# The shared evidence-schema guard (the ms_select_k memo-3 columns).
.ms_viz_check_k_evidence <- function(k_evidence) {
  required <- c("k", "cv_test_deviance", "avg_stability",
                "min_cluster_stability", "passes_veto", "is_argmin",
                "selected")
  if (!is.data.frame(k_evidence)) {
    msuiter_abort(
      "input",
      "k_evidence must be the data.frame returned by ms_select_k()",
      i = "the K-selection faces read the memo-3 evidence schema",
      j = paste0("received: ", class(k_evidence)[1L]),
      c = "pass the k_evidence slot of the ms_select_k() result"
    )
  }
  missing <- setdiff(required, names(k_evidence))
  if (length(missing) > 0L) {
    msuiter_abort(
      "input",
      "k_evidence is missing required columns",
      i = paste0("required: ", paste(required, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(missing)),
      c = "pass the k_evidence data.frame unmodified"
    )
  }
  k_evidence
}

.ms_viz_k_title <- function(argmin, selected) {
  a <- if (length(argmin) == 1L && !is.na(argmin)) argmin else NA
  s <- if (length(selected) == 1L && !is.na(selected)) selected else NA
  if (!is.na(a) && !is.na(s) && a == s) {
    return(sprintf("argmin = selected k = %d", a))
  }
  if (!is.na(a) && !is.na(s)) {
    return(sprintf("argmin %d, selected %d (veto or default)", a, s))
  }
  if (!is.na(s)) return(sprintf("selected k = %d", s))
  "K-selection evidence"
}
