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
