# viz-batch2.R: the four CAPABILITY-MATRIX promised faces (U-M4-03b;
# design memo docs/devlog/2026-10-24-M4-03b-viz-batch2-memo.md).
#
# Every face renders an ALREADY-CERTIFIED result: the plots draw what the
# backing faces stored (never re-deriving thresholds, ranks or rosters).
# Shared invariants, per the batch-1 memo: ggplot2 is required first
# (Suggests-absent is the structured package error, before any input
# validation), canonical order is enforced via .ms_viz_check_table, and
# the return is always a ggplot object.

# ---------------------------------------------------------------------------
# Shared input plumbing
# ---------------------------------------------------------------------------

.ms_viz_require_frame <- function(x, cols, what, call = rlang::caller_call()) {
  if (!is.data.frame(x)) {
    msuiter_abort(
      "input",
      paste0(what, " must be the data.frame returned by the backing face"),
      i = "backing faces return a plain data.frame; pass it through untouched",
      j = paste0("received: ", class(x)[[1]]),
      c = "pass the certified frame unchanged",
      call = call
    )
  }
  miss <- setdiff(cols, names(x))
  if (length(miss)) {
    msuiter_abort(
      "input",
      paste0(what, " is missing certified columns"),
      i = paste0("required: ", paste(cols, collapse = ", ")),
      j = paste0("missing: ", paste(miss, collapse = ", ")),
      c = "the frame must be the untouched backing-face return",
      call = call
    )
  }
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# plot_qc_dashboard
# ---------------------------------------------------------------------------

#' QC dashboard: burden bars plus the sentry shares
#'
#' Two stacked panels over the sample axis of an ms_qc_report() frame:
#' top, log10 burden bars colored by the stored burden class; bottom,
#' the gt-share and artifact-share sentry points colored by the stored
#' qc_flag. The stored values are drawn as-is -- the dashboard never
#' re-thresholds. The ms_qc_provenance attribute (when present) rides
#' into the title.
#'
#' @param qc The data.frame returned by ms_qc_report().
#'
#' @return A ggplot object.
#' @export
plot_qc_dashboard <- function(qc) {
  .ms_viz_require_ggplot()
  .ms_viz_require_frame(
    qc,
    c("sample", "total", "log10_total", "burden_class", "gt_share",
      "ct_share", "artifact_share", "artifact_sigs", "qc_flag"),
    "qc report"
  )
  n <- nrow(qc)
  if (n == 0L) {
    msuiter_abort(
      "input",
      "qc report has no samples to plot",
      i = "the report validated but carries zero rows",
      j = "nrow(qc) == 0",
      c = "run ms_qc_report() over a non-empty catalog"
    )
  }
  burden <- data.frame(
    panel = "burden",
    x = seq_len(n),
    y = qc$log10_total,
    fill = as.character(qc$burden_class),
    stringsAsFactors = FALSE
  )
  sentries <- rbind(
    data.frame(panel = "sentries", x = seq_len(n), y = qc$gt_share,
               colour = as.character(qc$qc_flag), stringsAsFactors = FALSE),
    data.frame(panel = "sentries", x = seq_len(n), y = qc$artifact_share,
               colour = as.character(qc$qc_flag), stringsAsFactors = FALSE)
  )
  # Dead samples carry certified-NA shares: no point to draw, so the
  # unmeasured rows are dropped at the data layer -- explicit, in place
  # of the render-time removed-rows warning. Flags of drawn rows ride on.
  sentries <- sentries[!is.na(sentries$y), , drop = FALSE]
  prov <- attr(qc, "ms_qc_provenance", exact = TRUE)
  ggplot2::ggplot() +
    ggplot2::geom_col(
      data = burden,
      ggplot2::aes(x = .data$x, y = .data$y, fill = .data$fill),
      width = 0.7
    ) +
    ggplot2::scale_fill_manual(
      name = "Burden",
      values = c(dead = "#8A8A8A", low = "#03BDEF", standard = "#046282",
                 high = "#E42926"),
      drop = FALSE
    ) +
    ggplot2::geom_point(
      data = sentries,
      ggplot2::aes(x = .data$x, y = .data$y, colour = .data$colour),
      size = 2
    ) +
    ggplot2::scale_colour_manual(
      name = "Flag",
      values = c(ok = "#046282", watch = "#03BDEF", artifact = "#E42926"),
      drop = FALSE
    ) +
    ggplot2::facet_grid(panel ~ ., scales = "free_y", switch = "y") +
    ggplot2::scale_x_continuous(breaks = seq_len(n), labels = qc$sample,
                                expand = c(0.02, 0)) +
    ggplot2::labs(x = NULL, y = NULL,
                  title = if (is.character(prov)) paste0("MSuiter QC | ", prov)
                          else "MSuiter QC") +
    .ms_viz_theme()
}

# ---------------------------------------------------------------------------
# plot_pseudosig_contribution
# ---------------------------------------------------------------------------

#' Artifact-signature contribution ranking
#'
#' Ranked bars of the per-sample artifact share from ms_qc_roster_share():
#' ordered by descending share, colored by the stored artifact_flag, with
#' the contributing signature names labelled (capped at `top`, the
#' remainder marked "+N"). Samples whose share is certified-NA (zero
#' exposure) carry no bar; their "na" flag entry stays in the legend.
#'
#' @param qc_roster The data.frame returned by ms_qc_roster_share().
#' @param top Maximum number of signature names shown per sample.
#'
#' @return A ggplot object.
#' @export
plot_pseudosig_contribution <- function(qc_roster, top = 3L) {
  .ms_viz_require_ggplot()
  .ms_viz_require_frame(
    qc_roster,
    c("sample", "exposure_total", "artifact_share", "artifact_sigs",
      "artifact_flag"),
    "roster share"
  )
  top <- as.integer(top)
  if (is.na(top) || top < 1L) {
    msuiter_abort(
      "input",
      "top must be a whole number >= 1",
      i = "top caps how many signature names are labelled per sample",
      j = paste0("received: ", top),
      c = "pass a single integer value, e.g. top = 3L"
    )
  }
  # Zero-exposure samples carry a certified-NA share: no bar to draw, so
  # they are dropped at the data layer after the ranking; the "na" flag
  # legend entry rides on the drop = FALSE scale, not on a phantom bar.
  ord <- order(qc_roster$artifact_share, decreasing = TRUE, na.last = TRUE)
  ord <- ord[!is.na(qc_roster$artifact_share[ord])]
  n <- length(ord)
  lev <- qc_roster$sample[ord]
  y <- qc_roster$artifact_share[ord]
  bars <- data.frame(
    x = seq_len(n),
    y = y,
    fill = as.character(qc_roster$artifact_flag[ord]),
    sample = factor(lev, levels = lev),
    stringsAsFactors = FALSE
  )
  labels <- vapply(seq_len(n), function(i) {
    sigs <- strsplit(qc_roster$artifact_sigs[ord[[i]]], "; ?")[[1]]
    sigs <- sigs[nzchar(sigs)]
    if (!length(sigs)) return("")
    extra <- max(0L, length(sigs) - top)
    paste0(paste(sigs[seq_len(min(length(sigs), top))], collapse = ";"),
           if (extra > 0L) paste0(" +", extra))
  }, character(1L))
  texts <- data.frame(
    x = seq_len(n),
    y = y + 0.02,
    label = labels,
    stringsAsFactors = FALSE
  )
  ggplot2::ggplot() +
    ggplot2::geom_col(
      data = bars,
      ggplot2::aes(x = .data$x, y = .data$y, fill = .data$fill),
      width = 0.7
    ) +
    ggplot2::scale_fill_manual(
      name = "Flag",
      values = c(ok = "#046282", artifact = "#E42926", na = "#8A8A8A"),
      drop = FALSE
    ) +
    ggplot2::geom_text(
      data = texts,
      ggplot2::aes(x = .data$x, y = .data$y, label = .data$label),
      size = 3, hjust = 0.5, colour = "grey25"
    ) +
    ggplot2::scale_x_continuous(breaks = seq_len(n), labels = lev,
                                expand = c(0.02, 0)) +
    ggplot2::labs(x = NULL, y = "Artifact share of exposure") +
    .ms_viz_theme() +
    ggplot2::theme(legend.position = "right")
}

# ---------------------------------------------------------------------------
# plot_hypermutator_burden
# ---------------------------------------------------------------------------

#' Hypermutator burden histogram with the stored cutoff line
#'
#' Histogram of MsStratification@@totals with the samples partitioned by
#' the stored hyper/nonhyper adjudication and a dashed vertical at the
#' stored @cutoff. Nothing is re-thresholded: the plot draws the class
#' as adjudicated; `show_gmm` annotates the GMM diagnostics that
#' produced the cutoff.
#'
#' @param strat An MsStratification (from ms_stratify_hypermutants()).
#' @param show_gmm Annotate the GMM cutoff diagnostics in the subtitle.
#'
#' @return A ggplot object.
#' @export
plot_hypermutator_burden <- function(strat, show_gmm = TRUE) {
  .ms_viz_require_ggplot()
  if (!S7::S7_inherits(strat, MsStratification)) {
    msuiter_abort(
      "input",
      "strat must be an MsStratification from ms_stratify_hypermutants()",
      i = "the plot draws the stored partition and cutoff; it cannot rebuild them",
      j = paste0("received: ", class(strat)[[1]]),
      c = "pass the MsStratification object unchanged"
    )
  }
  totals <- strat@totals
  if (!length(totals)) {
    msuiter_abort(
      "input",
      "stratification carries no sample totals to plot",
      i = "the histogram needs at least one sample burden",
      j = "length(@totals) == 0",
      c = "re-run ms_stratify_hypermutants() over a non-empty cohort"
    )
  }
  if (!all(strat@hyper %in% names(totals))) {
    msuiter_abort(
      "input",
      "stratification is corrupt: hyper roster names absent from @totals",
      i = "@hyper must be a subset of the names of @totals",
      j = paste0("orphans: ",
                 paste(setdiff(strat@hyper, names(totals)), collapse = ", ")),
      c = "re-run ms_stratify_hypermutants(); report the corruption upstream"
    )
  }
  df <- data.frame(
    sample = names(totals),
    total = unname(totals),
    fill = names(totals) %in% strat@hyper,
    stringsAsFactors = FALSE
  )
  vdf <- data.frame(xintercept = strat@cutoff)
  subtitle <- if (isTRUE(show_gmm)) {
    g <- strat@gmm
    sprintf("GMM cutoff %g | retained mean %g sd %g n %d; n_fits %d, converged %s",
            strat@cutoff, g$retained_mean, g$retained_sd, g$retained_n,
            g$n_fits, as.character(g$converged))
  }
  ggplot2::ggplot() +
    ggplot2::geom_histogram(
      data = df,
      ggplot2::aes(x = .data$total, fill = .data$fill),
      boundary = 0, bins = 30L, colour = "grey90"
    ) +
    ggplot2::scale_fill_manual(
      name = "Hypermutator",
      values = c(`FALSE` = "#038193", `TRUE` = "#E42926")
    ) +
    ggplot2::geom_vline(
      data = vdf,
      ggplot2::aes(xintercept = .data$xintercept),
      colour = "#E42926", linetype = 2
    ) +
    ggplot2::labs(x = "Sample burden", y = "Samples", subtitle = subtitle) +
    .ms_viz_theme()
}

# ---------------------------------------------------------------------------
# plot_opportunity_distribution
# ---------------------------------------------------------------------------

#' Trinucleotide opportunity landscape
#'
#' The 96-channel opportunity vector (genome or exome effective base
#' counts) as bars on the log10 scale, colored by the substitution class
#' parsed from the channel label, with one tick every 12 channels.
#' Explicit `opps` vectors must carry the SBS96 labels in canonical
#' order -- the viz never reorders silently.
#'
#' @param opps Optional named numeric vector of 96 opportunities; NULL
#'   resolves the bundled table via `from`.
#' @param from "human-genome" (default) or "human-exome"; ignored when
#'   `opps` is supplied.
#'
#' @return A ggplot object.
#' @export
plot_opportunity_distribution <- function(opps = NULL,
                                         from = c("human-genome",
                                                  "human-exome")) {
  .ms_viz_require_ggplot()
  if (is.null(opps)) {
    from <- if (is.character(from) && length(from) >= 1L) from[[1L]] else ""
    table <- .ms_convert_opps
    if (!from %in% names(table)) {
      msuiter_abort(
        "input",
        "unknown opportunity table",
        i = paste0("bundled: ", paste(names(table), collapse = ", ")),
        j = paste0("received: ", from),
        c = "pick one of the bundled tables or pass an explicit opps vector"
      )
    }
    opps <- table[[from]]
  } else {
    if (!is.numeric(opps) || length(opps) != 96L ||
        is.null(names(opps)) || anyNA(names(opps)) ||
        !all(names(opps) != "")) {
      msuiter_abort(
        "input",
        "opps must be a named numeric vector of 96 opportunities",
        i = "names = the SBS96 labels in canonical order",
        j = sprintf("received: %s of length %d", class(opps)[[1]],
                    length(opps)),
        c = "use plot_opportunity_distribution(from = ...) for the bundled tables"
      )
    }
    .ms_viz_check_table(names(opps), "SBS96")
  }
  labels <- names(opps)
  df <- data.frame(
    x = seq_len(96L),
    y = log10(opps),
    fill = unname(substr(labels, 3L, 5L)),
    stringsAsFactors = FALSE
  )
  ticks <- character(96L)
  every <- seq(12L, 96L, by = 12L)
  ticks[every] <- labels[every]
  ggplot2::ggplot() +
    ggplot2::geom_col(
      data = df,
      ggplot2::aes(x = .data$x, y = .data$y, fill = .data$fill),
      width = 0.7
    ) +
    ggplot2::scale_fill_manual(
      name = "Class",
      values = .ms_viz_sbs_palette
    ) +
    ggplot2::scale_x_continuous(breaks = seq_len(96L), labels = ticks,
                                expand = c(0.01, 0)) +
    ggplot2::labs(x = NULL, y = "log10 opportunities") +
    .ms_viz_theme()
}
