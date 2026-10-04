# viz-profile.R: the profile faces of the viz first batch (U-M4-03;
# design memo docs/devlog/2026-10-04-M4-03-viz-memo.md):
#   plot_catalog_profile      -- one column, channel bars, class colors
#   plot_signature_catalog    -- multi-signature facet grid
#   plot_reference_comparison -- estimate vs reference side-by-side bars
#   plot_reconstruction_panel -- original vs rebuilt + per-channel residual
#
# Shared semantics (memo §2): canonical-order inputs enforced, share or
# count mode, class separation lines for SBS96, simplified mono for
# DBS78/ID83 (palette freeze deferred to M7).

#' Plot one profile column in COSMIC style
#'
#' Channel-level bar profile of one catalog sample or one signature:
#' substitution-class colors (the verified COSMIC SBS palette), class
#' separation lines, 5'-flank labels rotated vertical. DBS78/ID83 inputs
#' render in a simplified single-color style (their palettes are frozen
#' at M7).
#'
#' @param matrix An m x 1 numeric matrix (or a named numeric vector) in a
#'   supported canonical channel order (SBS96, DBS78, ID83), or an
#'   [MsSignature] (uses its first signature).
#' @param column Column name or index when `matrix` has several columns.
#' @param mode "share" (normalize the column to 1) or "count" (raw
#'   mutations on the y axis).
#'
#' @return A ggplot object.
#'
#' @export
plot_catalog_profile <- function(matrix, column = 1L,
                                 mode = c("share", "count")) {
  .ms_viz_require_ggplot()
  mode <- match.arg(mode)
  prep <- .ms_viz_prep_profile(matrix, column, mode)
  pal <- if (prep$table == "SBS96") {
    .ms_viz_channel_colors(prep$labels)
  } else {
    rep(.ms_viz_mono_color, length(prep$labels))
  }
  df <- data.frame(
    channel = factor(prep$labels, levels = prep$labels),
    value = prep$values,
    color = pal,
    x = seq_along(prep$labels)
  )
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$x, y = .data$value,
                                        fill = .data$color)) +
    ggplot2::scale_fill_identity() +
    ggplot2::geom_col(width = 0.85) +
    ggplot2::scale_x_continuous(
      breaks = seq_along(prep$labels),
      labels = prep$axis_labels,
      expand = c(0.01, 0)
    ) +
    ggplot2::labs(
      x = NULL,
      y = if (mode == "share") "Fraction of mutations" else "Mutations",
      title = prep$title
    ) +
    .ms_viz_theme() +
    ggplot2::theme(legend.position = "none")
  if (prep$table == "SBS96") {
    # The six class-separation lines: after each 16-channel block.
    # The registry is 5'-flank blocked (A/C/G/T x 24 channels each): the
    # visually honest separators are the three flank boundaries. (The
    # audited first draft drew 5 lines at 16-channel offsets, which
    # lands on no real boundary in this order — the class identity is
    # carried by the bar colors themselves.)
    bounds <- c(24.5, 48.5, 72.5)
    p <- p + ggplot2::geom_vline(xintercept = bounds, colour = "grey40",
                                 linewidth = 0.3)
  }
  p
}

#' Plot a signature set as a facet grid
#'
#' One panel per signature, the same COSMIC semantics as
#' [plot_catalog_profile()].
#'
#' @param matrix An m x k numeric matrix in canonical order (k <= 20
#'   sensible), or an [MsSignature].
#' @param columns Column selection (default: all).
#' @param mode "share" or "count" (see [plot_catalog_profile()]).
#'
#' @return A ggplot object.
#' @export
plot_signature_catalog <- function(matrix, columns = NULL,
                                   mode = c("share", "count")) {
  .ms_viz_require_ggplot()
  mode <- match.arg(mode)
  prep <- .ms_viz_prep_profile(matrix, NULL, mode)
  k <- ncol(prep$matrix)
  if (!is.null(columns)) {
    idx <- .ms_viz_resolve_columns(prep$matrix, columns)
  } else {
    idx <- seq_len(k)
  }
  long <- do.call(rbind, lapply(idx, function(j) {
    data.frame(
      signature = prep$colnames[j],
      channel = factor(prep$labels, levels = prep$labels),
      value = prep$matrix[, j],
      color = if (prep$table == "SBS96") {
        .ms_viz_channel_colors(prep$labels)
      } else {
        rep(.ms_viz_mono_color, length(prep$labels))
      },
      x = seq_along(prep$labels),
      stringsAsFactors = FALSE
    )
  }))
  ggplot2::ggplot(long, ggplot2::aes(x = .data$x, y = .data$value, fill = .data$color)) +
    ggplot2::scale_fill_identity() +
    ggplot2::geom_col(width = 0.85) +
    ggplot2::facet_wrap(~signature) +
    ggplot2::scale_x_continuous(breaks = seq_along(prep$labels),
                                labels = prep$axis_labels,
                                expand = c(0.01, 0)) +
    ggplot2::labs(x = NULL,
                  y = if (mode == "share") "Fraction of mutations" else "Mutations") +
    .ms_viz_theme() +
    ggplot2::theme(legend.position = "none")
}

#' Compare an estimated profile against a reference profile
#'
#' Side-by-side bars per channel (estimate at half width left, reference
#' at half width right) with a shared y scale.
#'
#' @param estimated m x 1 (or named vector) in canonical order.
#' @param reference m x 1 (or named vector), same channel space.
#' @param mode "share" or "count".
#'
#' @return A ggplot object.
#' @export
plot_reference_comparison <- function(estimated, reference,
                                      mode = c("share", "count")) {
  .ms_viz_require_ggplot()
  mode <- match.arg(mode)
  pe <- .ms_viz_prep_profile(estimated, NULL, mode)
  pr <- .ms_viz_prep_profile(reference, NULL, mode)
  if (!identical(pe$labels, pr$labels)) {
    msuiter_abort(
      "input",
      "estimated and reference must share the canonical channel order",
      i = "viz reindexes nothing",
      j = sprintf("rows: %d vs %d", length(pe$labels), length(pr$labels)),
      c = "order both matrices by the same registry labels"
    )
  }
  df <- rbind(
    data.frame(channel = pe$labels, x = seq_along(pe$labels) - 0.21,
               value = pe$values, which = "estimated", alpha = 1),
    data.frame(channel = pe$labels, x = seq_along(pe$labels) + 0.21,
               value = pr$values, which = "reference", alpha = 0.45)
  )
  pal <- if (pe$table == "SBS96") .ms_viz_channel_colors(pe$labels) else
    rep(.ms_viz_mono_color, length(pe$labels))
  df$color <- rep(pal, 2L)
  # ONE paint per group (the audited first draft painted everything
  # opaque, then re-painted the reference at 45% — the blend stayed
  # fully saturated).
  ggplot2::ggplot(df, ggplot2::aes(x = .data$x, y = .data$value,
                                   fill = .data$color)) +
    ggplot2::scale_fill_identity() +
    ggplot2::geom_col(ggplot2::aes(alpha = .data$alpha), width = 0.4) +
    ggplot2::scale_alpha_identity() +
    ggplot2::scale_x_continuous(breaks = seq_along(pe$labels),
                                labels = pe$axis_labels,
                                expand = c(0.01, 0)) +
    ggplot2::labs(x = NULL,
                  y = if (mode == "share") "Fraction of mutations" else "Mutations") +
    ggplot2::annotate("text", x = 4, y = max(df$value) * 0.95,
                      label = "dark: estimated | light: reference",
                      hjust = 0, size = 3, colour = "grey30") +
    .ms_viz_theme() +
    ggplot2::theme(legend.position = "none") + ggplot2::scale_fill_identity()
}

#' Original vs reconstruction with a per-channel residual strip
#'
#' Top: the observed catalog column and its reconstruction
#' (signatures %*% exposures) overlaid as side-by-side bars. Bottom: the
#' per-channel residual (observed − reconstructed), red positive, blue
#' negative.
#'
#' @param counts m x 1 observed column (canonical order).
#' @param signatures m x k dictionary (canonical order).
#' @param exposures k x 1 exposure vector matching the dictionary
#'   columns (rownames = signature labels when available).
#' @param mode "share" or "count".
#'
#' @return A ggplot object.
#' @export
plot_reconstruction_panel <- function(counts, signatures, exposures,
                                      mode = c("share", "count")) {
  .ms_viz_require_ggplot()
  mode <- match.arg(mode)
  pc <- .ms_viz_prep_profile(counts, NULL, mode)
  ps <- .ms_viz_prep_profile(signatures, NULL, "share")
  if (!identical(pc$labels, ps$labels)) {
    msuiter_abort(
      "input",
      "counts and signatures must share the canonical channel order",
      j = sprintf("rows: %d vs %d", length(pc$labels), length(ps$labels))
    )
  }
  exposures <- as.matrix(exposures)
  if (nrow(exposures) != ncol(ps$matrix)) {
    msuiter_abort(
      "input",
      "exposures rows must match the signature columns",
      j = sprintf("exposures rows: %d; signatures: %d",
                  nrow(exposures), ncol(ps$matrix))
    )
  }
  fitted <- as.numeric(ps$matrix %*% exposures)
  if (mode == "share") {
    # Both sides are shares (prep normalized the observed column; the
    # reconstruction of share-signatures at share-exposures sums to 1 up
    # to float noise) — normalize the fitted side onto the same scale.
    fitted <- fitted / sum(fitted)
  }
  residual <- pc$values - fitted
  pal <- if (pc$table == "SBS96") .ms_viz_channel_colors(pc$labels) else
    rep(.ms_viz_mono_color, length(pc$labels))
  df <- rbind(
    data.frame(channel = pc$labels, x = seq_along(pc$labels) - 0.21,
               value = pc$values, which = "observed",
               color = pal),
    data.frame(channel = pc$labels, x = seq_along(pc$labels) + 0.21,
               value = fitted, which = "reconstructed",
               color = pal),
    data.frame(channel = pc$labels, x = seq_along(pc$labels),
               value = residual, which = "residual", color = NA)
  )
  df$which <- factor(df$which, levels = c("observed", "reconstructed",
                                          "residual"))
  ggplot2::ggplot(df, ggplot2::aes(x = .data$x, y = .data$value)) +
    ggplot2::geom_col(
      data = subset(df, which != "residual"),
      ggplot2::aes(fill = .data$color, alpha = .data$which),
      width = 0.4
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::geom_col(
      data = subset(df, which == "residual"),
      ggplot2::aes(colour = .data$value >= 0), width = 0.8
    ) +
    ggplot2::scale_colour_manual(values = c(`TRUE` = "#E42926",
                                            `FALSE` = "#03BDEF"),
                                 guide = "none") +
    ggplot2::scale_alpha_manual(values = c(observed = 1,
                                           reconstructed = 0.45),
                                guide = "none") +
    ggplot2::facet_grid(which ~ ., scales = "free_y", switch = "y") +
    ggplot2::scale_x_continuous(breaks = seq_along(pc$labels),
                                labels = pc$axis_labels,
                                expand = c(0.01, 0)) +
    ggplot2::labs(x = NULL, y = if (mode == "share") "Fraction" else "Mutations") +
    .ms_viz_theme() +
    ggplot2::theme(legend.position = "none")
}

# ---------------------------------------------------------------------------
# Internal: input preparation shared by the profile faces.
# ---------------------------------------------------------------------------

# Normalize a profile input into list(labels, values, matrix, colnames,
# table, axis_labels, title). `column` selects one column (index or
# name) or NULL for "keep all".
.ms_viz_prep_profile <- function(matrix, column = NULL, mode = "share") {
  if (S7::S7_inherits(matrix, MsSignature)) {
    colnames(matrix@signatures) <- if (is.null(colnames(matrix@signatures))) {
      paste0("sig", seq_len(ncol(matrix@signatures)))
    } else {
      colnames(matrix@signatures)
    }
    matrix <- matrix@signatures
  }
  if (is.numeric(matrix) && is.null(dim(matrix))) {
    nm <- names(matrix)
    matrix <- matrix(matrix, ncol = 1L, dimnames = list(nm, NULL))
  }
  if (!is.numeric(matrix) || !is.matrix(matrix)) {
    msuiter_abort(
      "input",
      "profile input must be a numeric matrix (or named vector, or MsSignature)",
      j = paste0("received: ", class(matrix)[1L]),
      c = "pass m x k with canonical registry rownames"
    )
  }
  labels <- rownames(matrix)
  table_nm <- .ms_viz_check_table(labels)
  if (!is.null(column)) {
    idx <- .ms_viz_resolve_columns(matrix, column)
    colnm <- colnames(matrix)[idx]
    if (length(colnm) == 1L && !is.na(colnm)) {
      title <- colnm
    } else {
      title <- paste0("column ", idx)
    }
    values <- matrix[, idx]
    matrix <- matrix[, idx, drop = FALSE]
  } else {
    if (ncol(matrix) == 1L) {
      values <- as.numeric(matrix[, 1L])
      title <- if (!is.null(colnames(matrix))) colnames(matrix)[1L] else NULL
    } else {
      values <- NULL
      title <- NULL
    }
  }
  if (mode == "share") {
    if (!is.null(values)) {
      total <- sum(values)
      if (total > 0) values <- values / total
    }
    totals <- colSums(matrix)
    matrix[, totals > 0] <- sweep(matrix[, totals > 0, drop = FALSE],
                                  2L, totals[totals > 0], "/")
  }
  # The COSMIC axis label: the 5'-flank + 3'-flank context ("A__T" style
  # for SBS96: flank5 + flank3 around the bracketed substitution).
  axis_labels <- if (table_nm == "SBS96") {
    # "A[C>A]A": 5' flank at 1, 3' flank at 7 (the audited first draft
    # read character 6 — the closing bracket).
    paste0(substr(labels, 1, 1), " ", substr(labels, 7, 7))
  } else {
    labels
  }
  list(
    labels = as.character(labels),
    values = values,
    matrix = matrix,
    colnames = if (is.null(colnames(matrix))) {
      paste0("col", seq_len(ncol(matrix)))
    } else {
      colnames(matrix)
    },
    table = table_nm,
    axis_labels = axis_labels,
    title = title
  )
}

.ms_viz_resolve_columns <- function(matrix, columns) {
  cn <- colnames(matrix)
  if (is.numeric(columns) || is.integer(columns)) {
    idx <- as.integer(columns)
    if (any(idx < 1L) || any(idx > ncol(matrix))) {
      msuiter_abort(
        "input",
        "column index out of range",
        j = sprintf("requested: %s; columns: %d",
                    msuiter_quote_trunc(idx), ncol(matrix))
      )
    }
    return(idx)
  }
  if (is.character(columns) && !is.null(cn)) {
    missing <- setdiff(columns, cn)
    if (length(missing) > 0L) {
      msuiter_abort(
        "input",
        "requested column names are absent",
        j = paste0("missing: ", msuiter_quote_trunc(missing))
      )
    }
    return(match(columns, cn))
  }
  msuiter_abort(
    "input",
    "columns must be indices or (when the matrix has colnames) names",
    i = "the column argument takes integer indices or colnames",
    j = paste0("received: ", msuiter_quote_trunc(columns)),
    c = "pass an index in [1, ncol] or the colname strings"
  )
}
