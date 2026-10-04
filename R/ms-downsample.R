# ms-downsample.R: common-depth downsampling of a catalog (U-M4-02;
# design memo docs/devlog/2026-10-04-M4-02-design-memo.md §1).
#
# The semantic anchor is the SHIPPED M3b sanity protocol (R/calibrate-real.R):
# counts*_j ~ Multinomial(N, counts_j / total_j) drawn through base R's
# rmultinom on a fixed seed, sequentially per sample column. One law, one
# wording, package-wide. This is a data-preparation operation (no FFI face,
# no inference claim); the honest approximation note: with-replacement
# multinomial stands in for without-replacement subset selection
# (multivariate hypergeometric, the recorded upgrade arm).

#' Downsample a catalog to a common depth
#'
#' Down-samples every live sample of an [MsCatalog] to a common mutation
#' burden through \code{Multinomial(depth, counts_j / total_j)} — the same
#' law as the real-data sanity harness. Samples already at or below
#' `depth` are kept verbatim (never upsampled); zero-total samples stay
#' zero. Deterministic for a given catalog and seed.
#'
#' @param catalog An [MsCatalog].
#' @param depth A positive whole number (the common depth) or the string
#'   `"min"` (use the smallest live-sample total).
#' @param seed Single finite seed for the multinomial draws.
#'
#' @return A new [MsCatalog] with the same channels/labels/samples and a
#'   `downsample` provenance record.
#'
#' @export
ms_downsample <- function(catalog, depth = "min", seed = 1) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog",
      i = "ms_downsample() operates on cataloged mutation counts",
      j = paste0("received: ", class(catalog)[1L]),
      c = "pass the object returned by ms_catalog() / ms_tally()"
    )
  }
  counts <- catalog@counts
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) || !is.finite(seed) ||
      seed < 0) {
    msuiter_abort(
      "input",
      "seed must be a single non-negative finite number",
      i = "the seed makes the downsampling reproducible",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "record the integer seed used for the draws"
    )
  }
  totals <- colSums(counts)
  live <- totals > 0
  depth_val <- if (is.character(depth) && length(depth) == 1L && depth == "min") {
    if (!any(live)) {
      msuiter_abort(
        "input",
        "depth = \"min\" needs at least one live sample",
        i = "every sample has a zero total",
        j = "the minimum is undefined over an empty set",
        c = "pass a numeric depth or a catalog with mutations"
      )
    }
    min(totals[live])
  } else if (is.numeric(depth) && length(depth) == 1L && is.finite(depth) &&
             depth > 0 && depth == floor(depth)) {
    as.numeric(depth)
  } else {
    msuiter_abort(
      "input",
      "depth must be a positive whole number or \"min\"",
      i = "the common depth is the multinomial draw size N",
      j = paste0("received: ", msuiter_quote_trunc(depth)),
      c = "pass e.g. 3000 or \"min\""
    )
  }

  out <- counts
  # One seed, one sequential stream over the sample columns (the sanity
  # harness convention): reproducible for a given catalog + seed.
  set.seed(seed)
  for (j in seq_len(ncol(counts))) {
    tj <- totals[j]
    if (!live[j] || tj <= depth_val) {
      next
    }
    out[, j] <- as.numeric(stats::rmultinom(1L, size = depth_val,
                                     prob = counts[, j] / tj))
  }
  kept <- sum(live & totals <= depth_val)
  provenance <- c(catalog@provenance, list(downsample = list(
    depth = depth_val, seed = seed,
    n_downsampled = sum(live & totals > depth_val),
    n_kept_verbatim = kept
  )))
  ms_catalog(
    counts = out,
    channels = catalog@channels,
    samples = catalog@samples,
    provenance = provenance
  )
}
