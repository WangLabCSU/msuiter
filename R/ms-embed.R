# ms-embed.R: the exposure embedding first version (U-M4-03 remainder;
# CAPABILITY-MATRIX L-F "exposure 嵌入（UMAP/kmeans）+ 差异挖掘 🔶 M4" —
# the embedding/scatter face; the differential-mining face is a later
# unit).
#
# Semantics (frozen, this batch): the exposure share matrix (samples x
# signatures, compositional) is embedded to 2-D by UMAP (uwot, Suggests;
# the Seurat-grammar analogue of the msuiter working grammar's last
# step). UMAP is stochastic: the seed is a first-class argument and the
# result is bitwise-reproducible for a given uwot version + inputs
# (documented honesty: cross-version reproducibility is NOT claimed —
# uwot does not promise it either). kmeans is the deterministic
# alternative (stats::kmeans with centers = the row of a seed argument;
# nstart fixed) when uwot is absent or the user asks. The kmeans face
# reports the samples' loadings on the first two signature axes (a
# deterministic projection), not a nonlinear embedding.
#
# The face returns the tidy embedding table; the scatter is a thin
# ggplot over it (the viz batch semantics).

#' Embed samples by their exposure profiles
#'
#' Projects the samples of an exposure matrix to 2-D (UMAP via uwot, or
#' a deterministic kmeans-cluster annotation) and returns the tidy
#' embedding with the cluster assignment. With the compositional share
#' transform (default) the geometry lives on the simplex embedding the
#' signatures induce.
#'
#' @param exposures k x n exposure matrix (rows = signatures, columns =
#'   samples), or an [MsSignature].
#' @param method "umap" (uwot; Suggests) or "kmeans" (stats, always
#'   available).
#' @param transform "share" (columns to 1 — default) or "none".
#' @param seed Single seed: UMAP's set.seed / kmeans's centers-first
#'   row. kmeans is bitwise deterministic for a given input regardless.
#' @param clusters kmeans clusters (default 3); ignored by UMAP.
#'
#' @return A data.frame: sample, embed_1, embed_2 (UMAP coordinates, or
#'   for kmeans the sample's loadings on the first two signature axes —
#'   a deterministic projection, not an embedding), cluster.
#'
#' @export
ms_embed <- function(exposures, method = c("umap", "kmeans"),
                     transform = c("share", "none"), seed = 1,
                     clusters = 3L) {
  if (S7::S7_inherits(exposures, MsSignature)) {
    exposures <- exposures@exposures
  }
  exposures <- as.matrix(exposures)
  if (!is.numeric(exposures) || !is.matrix(exposures)) {
    msuiter_abort(
      "input",
      "exposures must be a numeric k x n matrix (or an MsSignature)",
      i = "ms_embed() projects samples in the exposure space",
      j = paste0("received: ", class(exposures)[1L]),
      c = "pass the fit/refit exposure matrix"
    )
  }
  method <- match.arg(method)
  transform <- match.arg(transform)
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
      !is.finite(seed) || seed < 0) {
    msuiter_abort(
      "input",
      "seed must be a single non-negative finite number",
      i = "the seed seeds the stochastic embedding (or the kmeans tie-break)",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "record the integer seed used for the embedding"
    )
  }
  samples <- colnames(exposures)
  if (is.null(samples)) {
    samples <- paste0("sample", seq_len(ncol(exposures)))
  }
  X <- t(exposures) # samples x signatures
  if (transform == "share") {
    totals <- rowSums(X)
    keep <- totals > 0
    X[keep, ] <- X[keep, , drop = FALSE] / totals[keep]
  }
  if (method == "umap") {
    if (!requireNamespace("uwot", quietly = TRUE)) {
      msuiter_abort(
        "package",
        "uwot is required for method = \"umap\"",
        i = "uwot is a Suggests dependency of the embedding face",
        j = "uwot namespace unavailable",
        c = "install.packages(\"uwot\") or use method = \"kmeans\""
      )
    }
    emb <- uwot::umap(as.matrix(X),
                      n_neighbors = min(15, max(2, min(nrow(X) - 1, ncol(X) - 1))),
                      n_components = 2, verbose = FALSE, seed = seed)
    out <- data.frame(
      sample = samples,
      embed_1 = emb[, 1], embed_2 = emb[, 2],
      cluster = NA_integer_,
      stringsAsFactors = FALSE
    )
    out
  } else {
    if (!is.numeric(clusters) || length(clusters) != 1L ||
        clusters < 1L || clusters > ncol(X)) {
      msuiter_abort(
        "input",
        "clusters must be a single integer in [1, n signatures]",
        i = "kmeans partitions the share-simplex samples",
        j = paste0("received: ", msuiter_quote_trunc(clusters),
                   "; signatures: ", ncol(X)),
        c = "kmeans needs at most one cluster per signature dimension"
      )
    }
    set.seed(seed)
    km <- stats::kmeans(X, centers = clusters, nstart = 10L)
    centers_order <- order(km$centers[, 1])
    relabel <- match(km$cluster, centers_order)
    out <- data.frame(
      sample = samples,
      embed_1 = X[, 1], embed_2 = if (ncol(X) >= 2) X[, 2] else rep(0, nrow(X)),
      cluster = as.integer(relabel),
      stringsAsFactors = FALSE
    )
    out
  }
}

#' Test per-signature exposure differences between sample groups
#'
#' The differential-mining half of the embed face (musicatk-style
#' workflow): for each signature, a two-sample Wilcoxon rank-sum test
#' compares the exposures across two groups of samples, with
#' Benjamini-Hochberg correction across the signature family (the same
#' `p.adjust` semantics as ms_test_presence). More than two groups are
#' rejected -- pairwise splits are the caller's design decision, not an
#' implicit default.
#'
#' @param exposures A k x n exposure matrix (rows = signatures), or an
#'   [MsSignature].
#' @param groups A character/factor vector of length n with exactly two
#'   levels; the sample order must match the exposure columns.
#' @param alpha The family-wise alpha for `pass_bh` (frozen default
#'   0.05, the presence-test convention).
#'
#' @return A data.frame: signature, median_group1, median_group2,
#'   statistic, p_raw, p_bh, pass_bh.
#'
#' @references musicatk (Bioconductor) exposure-differentiation
#'   workflow; BH correction semantics per ms_test_presence.
#'
#' @export
ms_exposure_test <- function(exposures, groups, alpha = 0.05) {
  if (S7::S7_inherits(exposures, MsSignature)) {
    exposures <- exposures@exposures
  }
  exposures <- as.matrix(exposures)
  if (!is.numeric(exposures) || !is.matrix(exposures)) {
    msuiter_abort(
      "input",
      "exposures must be a numeric k x n matrix (or an MsSignature)",
      i = "ms_exposure_test() compares per-signature exposures across groups",
      j = paste0("received: ", class(exposures)[1L]),
      c = "pass the fit/refit exposure matrix"
    )
  }
  if (!is.character(groups) && !is.factor(groups)) {
    msuiter_abort(
      "input",
      "groups must be a character vector or factor over the samples",
      i = "the test splits the exposure columns into two groups",
      j = paste0("received: ", class(groups)[1L]),
      c = "pass one group label per sample column"
    )
  }
  groups <- as.character(groups)
  if (length(groups) != ncol(exposures)) {
    msuiter_abort(
      "input",
      "groups must have one label per exposure column",
      i = "the sample order of groups matches the exposure columns",
      j = sprintf("groups: %d; exposure columns: %d", length(groups),
                  ncol(exposures)),
      c = "align the labels with the matrix columns"
    )
  }
  levels <- sort(unique(groups))
  if (length(levels) != 2L) {
    msuiter_abort(
      "input",
      "exactly two groups are required",
      i = "pairwise splits of multi-group designs are the caller's decision",
      j = sprintf("received %d levels: %s", length(levels),
                  msuiter_quote_trunc(levels)),
      c = "subset to the two groups you want compared"
    )
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) ||
      !is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    msuiter_abort(
      "input",
      "alpha must be a single number in (0, 1)",
      i = "the family-wise alpha gates pass_bh",
      j = paste0("received: ", msuiter_quote_trunc(alpha)),
      c = "the frozen convention is 0.05"
    )
  }
  sigs <- rownames(exposures)
  if (is.null(sigs)) sigs <- paste0("sig", seq_len(nrow(exposures)))
  g1 <- groups == levels[1]
  g2 <- groups == levels[2]
  rows <- lapply(seq_len(nrow(exposures)), function(a) {
    x <- exposures[a, g1]
    y <- exposures[a, g2]
    # A signature that is all-zero on both sides (or all-tied) has no
    # evidence: NA rather than a fake p (the presence-test NA face).
    if (all(x == y)) {
      return(data.frame(signature = sigs[a],
        median_group1 = stats::median(x), median_group2 = stats::median(y),
        statistic = NA_real_, p_raw = NA_real_, stringsAsFactors = FALSE))
    }
    wt <- stats::wilcox.test(x, y, exact = FALSE, correct = FALSE)
    data.frame(signature = sigs[a],
      median_group1 = stats::median(x), median_group2 = stats::median(y),
      statistic = unname(wt$statistic), p_raw = wt$p.value,
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$p_bh <- stats::p.adjust(out$p_raw, method = "BH")
  out$pass_bh <- !is.na(out$p_bh) & out$p_bh <= alpha
  out
}

#' Scatter the sample embedding
#'
#' ggplot scatter of an [ms_embed()] table; colours by cluster when
#' present.
#'
#' @param embedding The data.frame returned by [ms_embed()].
#'
#' @return A ggplot object.
#' @export
plot_embedding <- function(embedding) {
  .ms_viz_require_ggplot()
  if (!is.data.frame(embedding) ||
      !all(c("embed_1", "embed_2") %in% names(embedding))) {
    msuiter_abort(
      "input",
      "embedding must be the ms_embed() table (embed_1/embed_2 columns)",
      i = "the scatter reads the embed_1/embed_2 columns (and cluster when present)",
      j = paste0("received: ", class(embedding)[1L]),
      c = "pass the data.frame returned by ms_embed()"
    )
  }
  p <- ggplot2::ggplot(embedding, ggplot2::aes(x = .data$embed_1,
                                               y = .data$embed_2)) +
    ggplot2::geom_point(size = 1.8, alpha = 0.85, colour = "#2166AC") +
    ggplot2::labs(x = "Embedding 1", y = "Embedding 2") +
    .ms_viz_theme()
  if ("cluster" %in% names(embedding) && !all(is.na(embedding$cluster))) {
    p <- p + ggplot2::aes(colour = factor(.data$cluster)) +
      ggplot2::labs(colour = "cluster")
  }
  p
}
