# viz-exposure-similarity.R: exposure + similarity faces of the viz
# first batch (U-M4-03; design memo docs/devlog/2026-10-04-M4-03-viz-memo.md):
#   plot_exposure_stacked    -- per-sample stacked exposure bars
#   plot_exposure_heatmap    -- samples x signatures tile heatmap
#   plot_similarity_heatmap  -- cosine heatmap (ms_compare metrics face)
#   plot_cosmic_scatter      -- estimate vs COSMIC reference scatter

#' Stacked exposure bars per sample
#'
#' One bar per sample, stacked by signature exposure. In share mode the
#' bars are normalized to 1 (compositional view); in count mode they sum
#' to the sample burden.
#'
#' @param exposures k x n exposure matrix (rownames = signature labels),
#'   or an [MsSignature] (uses its exposures).
#' @param mode "share" (default) or "count".
#' @param signature_order character ordering of the signature labels
#'   (default: dictionary order).
#'
#' @return A ggplot object.
#' @export
plot_exposure_stacked <- function(exposures, mode = c("share", "count"),
                                  signature_order = NULL) {
  .ms_viz_require_ggplot()
  mode <- match.arg(mode)
  prep <- .ms_viz_prep_exposure(exposures, mode, signature_order)
  ggplot2::ggplot(prep$long, ggplot2::aes(x = .data$sample,
                                          y = .data$value,
                                          fill = .data$signature)) +
    ggplot2::geom_col(width = 0.8) +
    ggplot2::labs(x = NULL,
                  y = if (mode == "share") "Exposure share" else "Exposure (mutations)",
                  fill = NULL) +
    .ms_viz_theme()
}

#' Exposure heatmap (samples x signatures)
#'
#' Tile heatmap of the exposure matrix; rows are samples, columns are
#' signatures. Share mode scales each sample column to 1.
#'
#' @inheritParams plot_exposure_stacked
#'
#' @return A ggplot object.
#' @export
plot_exposure_heatmap <- function(exposures, mode = c("share", "count"),
                                  signature_order = NULL) {
  .ms_viz_require_ggplot()
  mode <- match.arg(mode)
  prep <- .ms_viz_prep_exposure(exposures, mode, signature_order)
  ggplot2::ggplot(prep$long, ggplot2::aes(x = .data$signature,
                                          y = .data$sample,
                                          fill = .data$value)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.4) +
    ggplot2::scale_fill_gradient(low = "#F5F5F5", high = "#2166AC",
                                 name = if (mode == "share") "share" else "count") +
    ggplot2::labs(x = NULL, y = NULL) +
    .ms_viz_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45,
                                                       vjust = 1, hjust = 1))
}

#' Similarity heatmap from an ms_compare result
#'
#' Tiles the cosine matrix of an [MsComparison] (or any named similarity
#' matrix); the diagonal reads 1 for self-comparisons.
#'
#' @param similarity A k_est x k_ref numeric matrix (e.g.
#'   `ms_compare(...)\@metrics$cosine`).
#' @param high Colour at similarity 1.
#'
#' @return A ggplot object.
#' @export
plot_similarity_heatmap <- function(similarity, high = "#B2182B") {
  .ms_viz_require_ggplot()
  if (!is.numeric(similarity) || !is.matrix(similarity)) {
    msuiter_abort(
      "input",
      "similarity must be a numeric matrix",
      i = "pass ms_compare(...)@metrics$cosine or an equivalent named matrix",
      j = paste0("received: ", class(similarity)[1L]),
      c = "the heatmap tiles the k_est x k_ref similarity grid"
    )
  }
  est <- rownames(similarity)
  if (is.null(est)) est <- paste0("est", seq_len(nrow(similarity)))
  ref <- colnames(similarity)
  if (is.null(ref)) ref <- paste0("ref", seq_len(ncol(similarity)))
  df <- expand.grid(estimated = est, reference = ref,
                    stringsAsFactors = FALSE)
  df$value <- as.vector(similarity)
  ggplot2::ggplot(df, ggplot2::aes(x = .data$reference, y = .data$estimated,
                                   fill = .data$value)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.4) +
    ggplot2::scale_fill_gradient2(low = "#F5F5F5", mid = "#F4A582",
                                  high = high, midpoint = 0.75,
                                  limits = c(NA, 1), name = "cosine") +
    ggplot2::labs(x = NULL, y = NULL) +
    .ms_viz_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45,
                                                       vjust = 1, hjust = 1))
}

#' Estimate vs COSMIC reference scatter
#'
#' Per-channel scatter of an estimated profile against a reference
#' profile with the identity line and a cosine annotation.
#'
#' @param estimated m x 1 (or named vector) in canonical order.
#' @param reference m x 1 (or named vector), same space.
#' @param label Optional title (e.g. the reference signature name); the
#'   cosine is annotated automatically.
#'
#' @return A ggplot object.
#' @export
plot_cosmic_scatter <- function(estimated, reference, label = NULL) {
  .ms_viz_require_ggplot()
  pe <- .ms_viz_prep_profile(estimated, NULL, "share")
  pr <- .ms_viz_prep_profile(reference, NULL, "share")
  if (!identical(pe$labels, pr$labels)) {
    msuiter_abort(
      "input",
      "estimated and reference must share the canonical channel order",
      i = "the scatter pairs channels positionally in one space",
      j = sprintf("rows: %d vs %d", length(pe$labels), length(pr$labels)),
      c = "order both matrices by the same registry labels"
    )
  }
  cos <- sum(pe$values * pr$values) /
    sqrt(sum(pe$values^2) * sum(pr$values^2))
  df <- data.frame(reference = pr$values, estimated = pe$values)
  ttl <- if (is.null(label)) "" else paste0(label, " — ")
  ggplot2::ggplot(df, ggplot2::aes(x = .data$reference, y = .data$estimated)) +
    ggplot2::geom_point(colour = "#2166AC", size = 1.6, alpha = 0.85) +
    ggplot2::geom_abline(slope = 1, intercept = 0, colour = "grey40",
                         linewidth = 0.4, linetype = "dashed") +
    ggplot2::annotate("text", x = Inf, y = -Inf, hjust = 1.05, vjust = -0.5,
                      label = sprintf("cosine = %.3f", cos), size = 3.2,
                      colour = "grey20") +
    ggplot2::labs(x = "Reference share", y = "Estimated share",
                  title = trimws(paste0(ttl, "channel-level comparison"))) +
    .ms_viz_theme()
}

# ---------------------------------------------------------------------------
# Internal: exposure prep shared by the two exposure faces.
# ---------------------------------------------------------------------------

.ms_viz_prep_exposure <- function(exposures, mode, signature_order) {
  if (S7::S7_inherits(exposures, MsSignature)) {
    exposures <- exposures@exposures
  }
  exposures <- as.matrix(exposures)
  if (!is.numeric(exposures) || !is.matrix(exposures)) {
    msuiter_abort(
      "input",
      "exposures must be a numeric k x n matrix (or an MsSignature)",
      i = "the exposure faces read one column per sample",
      j = paste0("received: ", class(exposures)[1L]),
      c = "pass the fit/refit exposure matrix"
    )
  }
  sigs <- rownames(exposures)
  if (is.null(sigs)) {
    sigs <- paste0("sig", seq_len(nrow(exposures)))
  }
  samples <- colnames(exposures)
  if (is.null(samples)) {
    samples <- paste0("sample", seq_len(ncol(exposures)))
  }
  if (!is.null(signature_order)) {
    missing <- setdiff(signature_order, sigs)
    if (length(missing) > 0L) {
      msuiter_abort(
        "input",
        "signature_order names are absent from the exposure rows",
        i = "the order must be a permutation of the signature labels",
        j = paste0("missing: ", msuiter_quote_trunc(missing)),
        c = "use the rownames of the exposure matrix"
      )
    }
    sigs <- signature_order
    exposures <- exposures[sigs, , drop = FALSE]
  }
  if (mode == "share") {
    totals <- colSums(exposures)
    keep <- totals > 0
    exposures[, keep] <- sweep(exposures[, keep, drop = FALSE], 2L,
                               totals[keep], "/")
  }
  long <- do.call(rbind, lapply(seq_len(ncol(exposures)), function(j) {
    data.frame(
      sample = samples[j],
      signature = factor(sigs, levels = rev(sigs)), # stack bottom-up
      value = as.numeric(exposures[, j]),
      stringsAsFactors = FALSE
    )
  }))
  long$sample <- factor(long$sample, levels = unique(samples))
  list(long = long)
}
