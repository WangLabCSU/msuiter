# ms-cluster.R: signature clustering by cosine-threshold connected
# components (CAPABILITY-MATRIX L-F "签名聚类 🔶" first version).
#
# Semantics (frozen): two signatures join the same cluster iff their
# cosine similarity is >= threshold. Clusters are the connected
# components of that threshold graph -- deterministic, no RNG, no
# restarts. Labels are assigned by descending cluster size, ties broken
# by the first-appearance order of the smallest member index (stable
# under row permutation? NO, by design: the input order is the identity,
# matching the package-wide label protocol). The medoid of a cluster is
# the member with the highest mean cosine to its co-members.
#
# Why not the M2 consensus primitive: consensus_cluster is
# replicate-block structured (Hungarian per block, exactly n_rep members
# per cluster) -- the ensemble semantics. Signature clustering over an
# ARBITRARY set has no replicate structure; the threshold graph is the
# honest first version. Pure R (k_est in practice is small; the cosine
# formula is the same one the ms_compare twins pinned).
#
# Use cases: splitting de novo solution sets, unioning dictionaries
# across cohorts, redundancy checks after extraction.

#' Cluster signatures by cosine similarity
#'
#' Groups a signature set into cosine-threshold connected components:
#' signatures with pairwise cosine >= `threshold` share a cluster. Each
#' cluster reports its size and its medoid (the member with the highest
#' mean within-cluster cosine). Deterministic.
#'
#' @param signatures An m x k numeric matrix (columns sum to 1 after
#'   normalization; canonical rownames enforced as everywhere), or an
#'   [MsSignature].
#' @param threshold Single number in (0, 1]: the cosine join threshold
#'   (default 0.90, the Islam TP line).
#'
#' @return A data.frame with one row per signature: `signature`,
#'   `cluster` (label `C1`, `C2`, ... by descending size),
#'   `is_medoid`, `cluster_size`; the pairwise cosine matrix rides as
#'   attribute `cosines`.
#'
#' @export
ms_cluster_signatures <- function(signatures, threshold = 0.90) {
  if (S7::S7_inherits(signatures, MsSignature)) {
    signatures <- signatures@signatures
  }
  if (!is.numeric(signatures) || !is.matrix(signatures)) {
    msuiter_abort(
      "input",
      "signatures must be a numeric matrix (or an MsSignature)",
      i = "ms_cluster_signatures() groups a signature set by cosine",
      j = paste0("received: ", class(signatures)[1L]),
      c = "pass m x k with canonical registry rownames"
    )
  }
  # The signature identities are the COLUMN names (the row space is the
  # channel space and is not part of the clustering output).
  sig_names <- colnames(signatures)
  if (is.null(sig_names) || anyNA(sig_names) || any(!nzchar(sig_names))) {
    msuiter_abort(
      "input",
      "signatures must carry non-missing non-empty colnames",
      i = "colnames are the cluster identities",
      j = sprintf("colnames missing: %s", is.null(sig_names)),
      c = "set the matrix dimnames before clustering"
    )
  }
  if (anyDuplicated(sig_names) != 0L) {
    msuiter_abort(
      "input",
      "signature labels must be unique",
      i = "duplicated identities make the cluster mapping ambiguous",
      j = paste0("duplicated: ",
                 msuiter_quote_trunc(sig_names[duplicated(sig_names)])),
      c = "rename the signatures before clustering"
    )
  }
  if (!is.numeric(threshold) || length(threshold) != 1L || is.na(threshold) ||
      !is.finite(threshold) || threshold <= 0 || threshold > 1) {
    msuiter_abort(
      "input",
      "threshold must be a single number in (0, 1]",
      i = "the threshold is the cosine join line of the cluster graph",
      j = paste0("received: ", msuiter_quote_trunc(threshold)),
      c = "use e.g. 0.90 (the Islam TP line)"
    )
  }
  k_est <- ncol(signatures)
  if (k_est < 2L) {
    msuiter_abort(
      "input",
      "clustering needs at least two signatures",
      i = "a single signature has no clustering",
      j = paste0("received: ", k_est),
      c = "pass at least two columns"
    )
  }
  # Non-finite / negative channels would corrupt the cosine.
  bad <- sum(!is.finite(signatures) | signatures < 0)
  if (bad > 0L) {
    msuiter_abort(
      "input",
      "signatures must be finite and non-negative",
      i = "share vectors; NaN/negative entries are uninterpretable",
      j = sprintf("offending entries: %d", bad),
      c = "re-normalize the dictionary before clustering"
    )
  }

  # Pairwise cosines on share-normalized columns.
  norms <- sqrt(colSums(signatures^2))
  cos_mat <- crossprod(signatures, signatures) / outer(norms, norms)
  dimnames(cos_mat) <- list(sig_names, sig_names)

  # Connected components over the threshold graph (union-find, the
  # deterministic O(k^2 alpha) pass).
  parent <- seq_len(k_est)
  find <- function(x) {
    while (parent[x] != x) {
      parent[x] <- parent[parent[x]] # path halving
      x <- parent[x]
    }
    x
  }
  for (i in seq_len(k_est - 1L)) {
    # seq_len guard: (i+1):k_est at i = k_est would be the DESCENDING
    # pair (k_est+1, k_est) -- R's colon traps the unwary.
    for (j in (i + 1L):k_est) {
      if (is.finite(cos_mat[i, j]) && cos_mat[i, j] >= threshold) {
        ri <- find(i)
        rj <- find(j)
        if (ri != rj) parent[rj] <- ri
      }
    }
  }
  roots <- vapply(seq_len(k_est), find, integer(1))

  # Cluster label assignment: descending size, ties by smallest member
  # index (both computed on the roots, so the mapping is deterministic).
  root_ids <- sort(unique(roots))
  sizes <- as.integer(table(roots))[as.character(root_ids)]
  names(sizes) <- as.character(root_ids)
  order_idx <- order(sizes, decreasing = TRUE)
  label_of_root <- setNames(
    sprintf("C%d", seq_along(sizes))[order_idx],
    names(sizes)[order_idx]
  )
  cluster_names <- unname(label_of_root[as.character(roots)])

  # Medoid: highest mean within-cluster cosine (ties keep the first
  # member in input order).
  medoid <- logical(k_est)
  for (cl in unique(cluster_names)) {
    members <- which(cluster_names == cl)
    if (length(members) == 1L) {
      medoid[members] <- TRUE
      next
    }
    means <- vapply(members, function(a) {
      others <- setdiff(members, a)
      mean(cos_mat[a, others])
    }, numeric(1L))
    medoid[members[which.max(means)]] <- TRUE
  }

  out <- data.frame(
    signature = sig_names,
    cluster = cluster_names,
    is_medoid = medoid,
    cluster_size = as.integer(table(cluster_names)[cluster_names]),
    stringsAsFactors = FALSE
  )
  attr(out, "cosines") <- cos_mat
  attr(out, "threshold") <- threshold
  out
}
