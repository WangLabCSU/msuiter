# ms-simulate.R: the catalog scenario simulator, first version
# (CAPABILITY-MATRIX L-G "ms_simulate() | M7 (内核 M1s)"; design memo
# docs/devlog/2026-10-05-simulate-memo.md).
#
# This face delivers the MUTATION-COUNT layer: a signature dictionary +
# exposure profile -> a synthetic catalog. The generative laws align
# verbatim with the M3b calibration driver's GenerativeArm grammar:
#   multinomial -- exactly-N draws per sample (rmultinom, the M3b sanity
#                  harness law; benchmarks and tests share one wording);
#   poisson    -- per-channel Poisson (the exact NB limit);
#   nb         -- per-channel gamma-Poisson mixture NB(mu_c, kappa).
# Genome-realistic placement (VCF-level, context/target-region aware)
# is deferred to the M7 full set ([V] scope note in the memo).
#
# Determinism: one seed, sequential per sample column (base R RNG).
# The M3b calibration driver draws from the Rust PCG64 streams — the two
# faces are BOTH deterministic but stream-independent (documented).

#' Simulate a catalog from a signature dictionary
#'
#' Draws synthetic mutation counts from a dictionary and an exposure
#' profile. The multinomial arm conserves the target burden exactly per
#' sample; the poisson/nb arms draw per channel (the NB arm introduces
#' Jiang-style overdispersion, Var = mu + mu^2/kappa).
#'
#' @param signatures An m x k numeric matrix in a supported canonical
#'   channel order (SBS96 or DBS78), or an [MsSignature].
#' @param exposures A k x n matrix; columns summing to 1 (or near it)
#'   are read as shares and scaled to `burden`, larger columns as
#'   count-scale activities (the target is then the column sums).
#' @param arm "multinomial" (exactly N per sample), "poisson", or "nb".
#' @param size The NB size kappa (arm = "nb" only).
#' @param burden Target per-sample mutation total for share exposures.
#' @param seed Single non-negative finite seed.
#'
#' @return An [MsCatalog] with the draw recorded in provenance.
#'
#' @export
ms_simulate <- function(signatures, exposures, arm = "multinomial",
                        size = 8, burden = 1000, seed = 1) {
  if (S7::S7_inherits(signatures, MsSignature)) {
    signatures <- signatures@signatures
  }
  if (!is.numeric(signatures) || !is.matrix(signatures)) {
    msuiter_abort(
      "input",
      "signatures must be a numeric matrix (or an MsSignature)",
      i = "ms_simulate() draws catalogs from a signature dictionary",
      j = paste0("received: ", class(signatures)[1L]),
      c = "pass m x k in a supported canonical channel order"
    )
  }
  labels <- rownames(signatures)
  registry <- get("channel_tables", envir = asNamespace("msuiter"))
  table_nm <- NULL
  for (nm in c("SBS96", "DBS78")) {
    if (identical(as.character(labels), registry[[nm]]$labels)) {
      table_nm <- nm
      break
    }
  }
  if (is.null(table_nm)) {
    msuiter_abort(
      "input",
      "signatures must carry a supported canonical channel order",
      i = "supported: SBS96, DBS78",
      j = sprintf("rows: %d; first label: %s", length(labels),
                  if (length(labels) >= 1L) labels[1L] else "(none)"),
      c = "order the matrix by the registry labels"
    )
  }
  exposures <- as.matrix(exposures)
  if (!is.numeric(exposures) || nrow(exposures) != ncol(signatures)) {
    msuiter_abort(
      "input",
      "exposures must be k x n matching the dictionary columns",
      i = "one exposure column per simulated sample",
      j = sprintf("exposures: %d x %d; dictionary: %d signatures",
                  nrow(exposures), ncol(exposures), ncol(signatures)),
      c = "pass share columns (sum 1) or count-scale activities"
    )
  }
  if (!arm %in% c("multinomial", "poisson", "nb")) {
    msuiter_abort(
      "option",
      "arm must be one of multinomial, poisson, nb",
      i = "the grammar matches the M3b calibration driver's GenerativeArm",
      j = paste0("received: ", msuiter_quote_trunc(arm)),
      c = "pick a generative arm from the frozen set"
    )
  }
  if (arm == "nb" && (!is.numeric(size) || length(size) != 1L ||
                      !is.finite(size) || size <= 0)) {
    msuiter_abort(
      "input",
      "size (kappa) must be a single positive finite number",
      i = "kappa sets the NB overdispersion Var = mu + mu^2/kappa",
      j = paste0("received: ", msuiter_quote_trunc(size)),
      c = "NB variance is mu + mu^2/kappa"
    )
  }
  if (!is.numeric(burden) || length(burden) != 1L || !is.finite(burden) ||
      burden < 1 || burden != floor(burden)) {
    msuiter_abort(
      "input",
      "burden must be a single positive whole number",
      i = "share exposures are scaled to this per-sample total",
      j = paste0("received: ", msuiter_quote_trunc(burden)),
      c = "pass e.g. 1000"
    )
  }
  if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed) ||
      seed < 0) {
    msuiter_abort(
      "input",
      "seed must be a single non-negative finite number",
      i = "the seed seeds the sequential per-sample draws",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "record the integer seed used for the simulation"
    )
  }

  n <- ncol(exposures)
  totals <- colSums(exposures)
  is_share <- totals > 0.9 & totals < 1.1
  probs <- sweep(signatures, 2L, colSums(signatures), "/")
  # mu per sample: the channel expectation vector. Share columns scale
  # to `burden`; count columns carry their own total.
  mu_list <- lapply(seq_len(n), function(j) {
    scale <- if (is_share[j]) burden else 1
    as.numeric(signatures %*% (exposures[, j] * scale))
  })

  set.seed(seed)
  counts <- matrix(0, nrow = nrow(signatures), ncol = n)
  for (j in seq_len(n)) {
    mu <- mu_list[[j]]
    if (arm == "multinomial") {
      p <- mu / sum(mu)
      counts[, j] <- stats::rmultinom(1, size = round(sum(mu)), prob = p)
    } else if (arm == "poisson") {
      counts[, j] <- stats::rpois(length(mu), mu)
    } else {
      counts[, j] <- vapply(mu, function(m) {
        if (m <= 0) return(0)
        lambda <- stats::rgamma(1, shape = size, scale = m / size)
        stats::rpois(1, lambda)
      }, numeric(1))
    }
  }
  rownames(counts) <- labels
  samples <- colnames(exposures)
  if (is.null(samples)) {
    samples <- paste0("sim", seq_len(n))
  }
  colnames(counts) <- samples
  ms_catalog(
    counts = counts,
    channels = list(name = table_nm, labels = as.character(labels)),
    samples = samples,
    provenance = list(
      genome = "simulated", arm = arm, size = if (arm == "nb") size else NULL,
      seed = seed, burden = burden,
      exposure_scale = if (any(is_share)) "share" else "count"
    )
  )
}
