# fit.R: the reference-based fitting entry point ms_fit() (U-M3a-02;
# ARCHITECTURE.md sections 3.2/5, CAPABILITY-MATRIX L-D).
#
# ms_fit() fits per-sample exposures of an MsCatalog's counts against a
# GIVEN signature dictionary -- the mirror image of ms_extract(), which
# discovers signatures. Three methods (research/02 section 1 semantics):
#   * "nnls"                    : per-sample Lawson-Hanson NNLS on the
#                                 K-format Gram pair (G = S'S, b_j = S'v_j),
#                                 the deconstructSigs baseline;
#   * "likelihood_bidirectional": MuSiCal nnls_likelihood_bidirectional --
#                                 backward/forward steps on the per-mutation
#                                 multinomial log-likelihood scale with the
#                                 epsilon threshold (pinned default 0.001,
#                                 research/02 section 1.1);
#   * "lrt"                     : mSigAct-flavoured fit -- negative-binomial
#                                 MLE exposures (concave objective, internal
#                                 safeguarded-Newton ascent, no external
#                                 optimizer, D9) plus the entry-wise presence
#                                 LRT (raw Self-Liang p; BH correction is
#                                 ms_test_presence()'s contract, U-M3a-03).
#
# The default method is "nnls" for THIS unit only: the MSU-Fit default
# orchestration (ARCHITECTURE section 5, D16) is a later unit and needs an
# author-level decision first.
#
# Assembly layer duties (no semantics added beyond display/labels):
#   * signature columns are normalized to sum 1 (the catalog convention) so
#     exposures carry per-sample mutation mass; the kernels see the
#     normalized dictionary;
#   * signatures rows are aligned to the catalog channel labels by label
#     when both label sets exist (positional otherwise);
#   * the kernel's evidence grids become the tidy `support` / `tests`
#     tables of MsFit (NaN standard errors map to NA_real_: boundary
#     parameters get tests, not intervals);
#   * reference_summary is an ADHOC snapshot derived from the signature
#     labels hash (A5: small summary, never an embedded reference);
#   * engine = the method string.
#
# All violations raise msuiter_error_* conditions with the i/j/c payload
# (ARCHITECTURE section 3.5); bare stop() is banned.

# Frozen hyper-parameters of this unit (recorded per the Delta discipline;
# not user-facing yet -- the MSU-Fit orchestration unit owns that decision):
#   eps      : the MuSiCal LTH epsilon of the bidirectional method
#              (research/02 section 1.1, pinned upstream default 0.001);
#   max_iter : the upstream anti-cycling round cap (1000), shared with the
#              internal NB-MLE iteration cap.
.ms_fit_defaults <- list(
  eps = 0.001,
  max_iter = 1000L
)

.ms_fit_methods <- c("nnls", "likelihood_bidirectional", "lrt")

# ---------------------------------------------------------------------------
# Shared preparation (U-M3a-03): dictionary resolution + channel alignment +
# display normalization + label validation, and the scalar-domain gates.
# Extracted VERBATIM from the ms_fit(MsCatalog) method so that
# ms_fit_bootstrap() / ms_test_presence() reuse the identical semantics
# (no behavior change -- the untouched ms_fit tests pin the messages).
# ---------------------------------------------------------------------------

# Dictionary resolution + alignment + normalization + labels. Returns
# list(counts, signatures (normalized k-dictionary), labels).
.ms_fit_prepare_dictionary <- function(catalog, signatures) {
  counts <- catalog@counts
  if (ncol(counts) < 1L) {
    msuiter_abort(
      "input",
      "the catalog has no samples to fit",
      i = "fitting needs at least one sample column",
      j = sprintf("catalog: %d channels x %d samples", nrow(counts), ncol(counts)),
      c = "tally a non-empty variant set with ms_tally() first"
    )
  }

  # --- dictionary resolution: MsSignature or matrix ------------------------
  if (S7::S7_inherits(signatures, MsSignature)) {
    sig_mat <- signatures@signatures
  } else if (is.matrix(signatures)) {
    sig_mat <- signatures
    if (is.integer(sig_mat)) {
      storage.mode(sig_mat) <- "double"
    }
    if (!is.double(sig_mat)) {
      msuiter_abort(
        "input",
        "signatures must be a double (numeric) matrix or an MsSignature",
        i = "the dictionary is the channels x signatures matrix being fitted",
        j = paste0("received: ", class(sig_mat)[1L]),
        c = "pass a numeric matrix, or an MsSignature to reuse its signatures"
      )
    }
  } else {
    msuiter_abort(
      "input",
      "signatures must be a matrix (channels x signatures) or an MsSignature",
      i = "ms_fit() fits exposures against a GIVEN dictionary",
      j = paste0("received: ", class(signatures)[1L]),
      c = "pass a channels x signatures matrix, or an MsSignature from ms_extract()"
    )
  }
  if (nrow(sig_mat) != nrow(counts)) {
    msuiter_abort(
      "input",
      "signatures and catalog must share the channel dimension",
      i = "each signature is a profile over the catalog's channels",
      j = sprintf("catalog has %d channels, signatures have %d",
        nrow(counts), nrow(sig_mat)),
      c = "fit against a dictionary over the same channel table as the catalog"
    )
  }

  # --- channel alignment: by label when both label sets exist -------------
  channel_labels <- rownames(counts)
  sig_labels_rows <- rownames(sig_mat)
  if (!is.null(sig_labels_rows) && !is.null(channel_labels) &&
      !identical(sig_labels_rows, channel_labels)) {
    missing <- setdiff(channel_labels, sig_labels_rows)
    if (length(missing) > 0L) {
      msuiter_abort(
        "input",
        "signature channel labels must cover the catalog channel labels",
        i = "when both label sets exist the dictionaries are matched by label",
        j = paste0("channel labels missing from signatures: ",
          msuiter_quote_trunc(missing)),
        c = "fit against a dictionary over the catalog's channel table"
      )
    }
    sig_mat <- sig_mat[channel_labels, , drop = FALSE]
  }

  # --- display normalization: columns to sum 1 (catalog convention) -------
  col_sums <- colSums(sig_mat)
  if (any(!is.finite(col_sums)) || any(col_sums <= 0)) {
    msuiter_abort(
      "signature",
      "the dictionary degenerated: a signature column has no positive mass",
      i = paste(
        "signature profiles must have strictly positive column sums for the",
        "catalog convention (exposures carry mutation mass)"
      ),
      j = msuiter_quote_trunc(which(!is.finite(col_sums) | col_sums <= 0)),
      c = "remove or repair the degenerate signature column"
    )
  }
  sig_norm <- sweep(sig_mat, 2, col_sums, `/`)

  # --- signature labels ----------------------------------------------------
  sig_labels <- colnames(sig_norm)
  if (is.null(sig_labels)) {
    sig_labels <- sprintf("Sig%d", seq_len(ncol(sig_norm)))
  } else if (anyNA(sig_labels) || any(!nzchar(sig_labels)) ||
             anyDuplicated(sig_labels) > 0L) {
    msuiter_abort(
      "input",
      "signature labels must be non-empty, NA-free and unique",
      i = "the labels key the exposure rows and the evidence tables",
      j = msuiter_quote_trunc(sig_labels[is.na(sig_labels) | !nzchar(sig_labels)]),
      c = "set colnames(signatures) to unique signature labels, or leave them NULL"
    )
  }

  list(counts = counts, signatures = sig_norm, labels = sig_labels)
}

# Scalar gates: the fitting method switch.
.ms_fit_gate_method <- function(method) {
  if (!is.character(method) || length(method) != 1L || is.na(method) ||
      !method %in% .ms_fit_methods) {
    msuiter_abort(
      "input",
      "method must be a single known fitting method",
      i = paste("ms_fit() ships three methods:",
        paste(.ms_fit_methods, collapse = ", ")),
      j = paste0("received: ", msuiter_quote_trunc(method)),
      c = 'pass "nnls" (default), "likelihood_bidirectional" or "lrt"'
    )
  }
  invisible(NULL)
}

# Scalar gates: the mSigAct nbinom.size.
.ms_fit_gate_nb_size <- function(nb_size) {
  if (!is.numeric(nb_size) || length(nb_size) != 1L || is.na(nb_size) ||
      !is.finite(nb_size) || nb_size <= 0) {
    msuiter_abort(
      "input",
      "nb_size must be a single positive number",
      i = "nb_size is the mSigAct nbinom.size of the likelihood columns (larger = closer to Poisson)",
      j = paste0("received: ", msuiter_quote_trunc(nb_size)),
      c = "pass 8 (the SBS96 anchor), or 50 / 100 for DBS78 / ID83 catalogs"
    )
  }
  invisible(NULL)
}

# Scalar gates: the share-zeroing threshold.
.ms_fit_gate_zero_threshold <- function(zero_threshold) {
  if (!is.numeric(zero_threshold) || length(zero_threshold) != 1L ||
      is.na(zero_threshold) || !is.finite(zero_threshold) ||
      zero_threshold < 0 || zero_threshold > 1) {
    msuiter_abort(
      "input",
      "zero_threshold must be a single number in [0, 1]",
      i = "the zeroing decision zeroes exposures whose compositional share falls strictly below the threshold",
      j = paste0("received: ", msuiter_quote_trunc(zero_threshold)),
      c = "pass a share threshold in [0, 1] (default 0.01), or 0 to zero exact zeros only"
    )
  }
  invisible(NULL)
}

# All three ms_fit scalar gates in the ms_fit order.
.ms_fit_gate_fit_args <- function(method, nb_size, zero_threshold) {
  .ms_fit_gate_method(method)
  .ms_fit_gate_nb_size(nb_size)
  .ms_fit_gate_zero_threshold(zero_threshold)
  invisible(NULL)
}

# Scalar gates of the bootstrap face (U-M3a-03): replicate count and master
# seed. Both cross the FFI as i32, so the upper bound is 2^31 - 1.
.ms_fit_gate_boot <- function(n_boot, seed) {
  if (!is.numeric(n_boot) || length(n_boot) != 1L || is.na(n_boot) ||
      !is.finite(n_boot) || n_boot != floor(n_boot) ||
      n_boot < 1 || n_boot > 2147483647) {
    msuiter_abort(
      "input",
      "n_boot must be a single whole number in [1, 2^31 - 1]",
      i = paste("each bootstrap replicate resamples every sample's mutations",
        "(nonparametric multinomial) and refits the selected method"),
      j = paste0("received: ", msuiter_quote_trunc(n_boot)),
      c = "pass 200 (the signature.tools.lib nboot family anchor), or any positive replicate count"
    )
  }
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
      !is.finite(seed) || seed != floor(seed) || seed < 0 || seed > 2147483647) {
    msuiter_abort(
      "input",
      "seed must be a single whole number in [0, 2^31 - 1]",
      i = "the seed addresses the per-boot canonical PCG64 streams (StreamId replicate axis)",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "pass a non-negative whole seed (default 1)"
    )
  }
  invisible(NULL)
}

#' Fit signature exposures against given signatures
#'
#' `ms_fit()` fits per-sample exposures of an [MsCatalog] against a given
#' signature dictionary and returns an [MsFit] -- the mirror image of
#' [ms_extract()], which discovers signatures. The method is a single
#' string: `"nnls"` (default; the Lawson-Hanson baseline), or one of the two
#' likelihood methods: `"likelihood_bidirectional"` (MuSiCal epsilon
#' stepping) and `"lrt"` (negative-binomial MLE + entry-wise presence LRT,
#' mSigAct flavour). All violations raise `msuiter_error_*` conditions.
#'
#' @param catalog An [MsCatalog] object, as returned by [ms_tally()] or
#'   [ms_catalog()].
#' @param signatures The dictionary to fit against: a numeric matrix
#'   (channels x signatures; rows match the catalog channel labels by label
#'   when rownames exist, positionally otherwise), or an [MsSignature]
#'   whose `signatures` matrix is used.
#' @param method Single string: `"nnls"`, `"likelihood_bidirectional"` or
#'   `"lrt"` (the `c(...)` form of the default documents the legal choices;
#'   the default is `"nnls"` for this unit -- the MSU-Fit default
#'   orchestration is a later unit).
#' @param nb_size Single positive number: the negative-binomial size of
#'   every likelihood-based column (mSigAct `nbinom.size`; larger = closer
#'   to Poisson). Default 8, the mSigAct SBS96 anchor (DBS78/ID83 anchors:
#'   50 / 100).
#' @param zero_threshold Single number in \eqn{[0, 1]}: the compositional
#'   share below which an exposure is zeroed (decision rule, sigfit
#'   CI-zeroing family anchor 0.01). Zeroed exposures are set to exactly 0
#'   and reported `active = FALSE`; standard errors exist only on the
#'   interior support ("boundary parameters get tests, not intervals").
#'
#' @details
#' **Method semantics** (research/02 section 1; D11 anchors). `"nnls"`
#' solves, per sample, `argmin ||S t - v_j||_2, t >= 0` through the
#' precomputed Gram pair. `"likelihood_bidirectional"` starts from the full
#' NNLS solution and alternates backward/forward steps on the per-mutation
#' multinomial log-likelihood: a signature leaves when the least costly
#' removal costs less than `eps` (0.001, the pinned MuSiCal LTH default)
#' and enters when the best gain exceeds it, until both steps decline.
#' `"lrt"` maximizes the negative-binomial likelihood over the exposures
#' (warm-started from NNLS; the objective is concave, the internal
#' safeguarded-Newton ascent is deterministic and thread-invariant) and
#' reports, for every signature, the entry-wise presence LRT of the full
#' model against the model refit without it: `D = 2(ll_with - ll_without)`,
#' raw p-value = the Self-Liang boundary half-tail. Presence evidence is
#' method-independent: the LRT columns are always computed at the
#' NB-MLE exposures, so `tests` compares fairly across methods. No
#' BH correction is applied here (that is `ms_test_presence()`,
#' U-M3a-03).
#'
#' **Hyper-parameters frozen for this unit** (recorded per the Delta
#' discipline): bidirectional `eps = 0.001` (upstream LTH default) and the
#' round/iteration cap `max_iter = 1000` (upstream anti-cycling cap).
#'
#' **Result.** The [MsFit] carries: `exposures` (signatures x samples,
#' labelled; zeroed entries exactly 0); `support`, one tidy row per
#' (signature, sample) with the exposure, its compositional share and the
#' zeroing decision; `tests`, one tidy row per (signature, sample) with the
#' presence LRT statistic, raw p-value and interior-support Fisher standard
#' error (NA at the boundary); an adhoc `reference_summary` snapshot
#' derived from the signature labels hash (sha256, FIPS 180-4); and
#' `engine` = the method string.
#'
#' @return An [MsFit] object.
#'
#' @seealso [ms_extract()] for discovery, [ms_catalog()] / [ms_tally()] for
#'   the upstream counts, [MsFit] for the result container.
#' @export
ms_fit <- S7::new_generic(
  "ms_fit",
  "catalog",
  function(catalog, signatures, method = "nnls", nb_size = 8,
           zero_threshold = 0.01) S7::S7_dispatch()
)

# Method: MsCatalog -> MsFit. Resolves the dictionary through the shared
# preparation (U-M3a-03 extraction; semantics unchanged), gates the scalars
# and runs the kernel through the FFI wrapper.
S7::method(ms_fit, MsCatalog) <- function(catalog, signatures, method = "nnls",
                                          nb_size = 8, zero_threshold = 0.01) {
  prep <- .ms_fit_prepare_dictionary(catalog, signatures)
  counts <- prep$counts
  sig_norm <- prep$signatures
  sig_labels <- prep$labels

  # --- scalar gates (FFI contract 4, first layer) --------------------------
  .ms_fit_gate_fit_args(method, nb_size, zero_threshold)

  # --- kernel (the FFI wrapper re-validates the raw scalars) ---------------
  res <- .ms_fit_rust(
    counts = counts, signatures = sig_norm, method = method,
    nb_size = nb_size, tol = .ms_fit_defaults$eps,
    max_iter = .ms_fit_defaults$max_iter, zero_threshold = zero_threshold
  )

  # --- assembly: labels, tidy evidence tables, adhoc reference snapshot ----
  samples <- catalog@samples
  exposures <- res$exposures
  dimnames(exposures) <- list(sig_labels, samples)

  n_samples <- length(samples)
  k <- length(sig_labels)
  signature_col <- rep(sig_labels, times = n_samples)
  sample_col <- rep(samples, each = k)
  exposure_vec <- as.vector(exposures) # column-major: sample-major, then signature
  total_per_sample <- rep(colSums(exposures), each = k) # column-major: k rows per sample
  share_vec <- ifelse(total_per_sample > 0, exposure_vec / total_per_sample, 0)
  support <- data.frame(
    signature = signature_col,
    sample = sample_col,
    exposure = exposure_vec,
    share = share_vec,
    active = as.logical(as.vector(res$support)),
    stringsAsFactors = FALSE
  )
  se_vec <- as.vector(res$se)
  se_vec[is.nan(se_vec)] <- NA_real_ # boundary: no interval, only tests
  tests <- data.frame(
    signature = signature_col,
    sample = sample_col,
    lrt_stat = as.vector(res$lrt_stat),
    lrt_p = as.vector(res$lrt_p),
    se = se_vec,
    stringsAsFactors = FALSE
  )

  reference_summary <- list(
    version = "adhoc-1",
    class = "adhoc",
    build = NA_character_, # labels are build-independent
    schema_version = "1",
    sha256 = .ms_fit_sha256_labels(sig_labels),
    n_signatures = length(sig_labels)
  )

  MsFit(
    exposures = exposures,
    engine = method,
    reference_summary = reference_summary,
    support = support,
    tests = tests
  )
}

# Fallback: anything that is not an MsCatalog gets a project error instead
# of the raw S7 dispatch failure.
S7::method(ms_fit, S7::class_any) <- function(catalog, signatures, method = "nnls",
                                              nb_size = 8, zero_threshold = 0.01) {
  msuiter_abort(
    "input",
    "catalog must be an MsCatalog object",
    i = "ms_fit() dispatches on MsCatalog",
    j = paste0("received: ", class(catalog)[1L]),
    c = "build the catalog with ms_tally() first (ms_variants() |> ms_tally() |> ms_fit())"
  )
}

# ---------------------------------------------------------------------------
# U-M3a-03: ms_fit_bootstrap() -- nonparametric (multinomial) percentile
# bootstrap of the whole fit (research/02 section 2 semantics: resample each
# sample's MUTATIONS, not channels; refit per replicate; percentile CI).
#
# The signature mirrors ms_fit() rather than taking an MsFit: the bootstrap
# resamples the catalog's raw counts, which an MsFit does not carry. The
# selected method (fit@engine in the ms_fit sense) is reused for every
# replicate through the same three-method kernel.
#
# Result (an MsFit like ms_fit's, plus the bootstrap evidence):
#   * exposures carry the CI as ATTRIBUTES (documented U-M3a-03 wire
#     decision -- the Rust face returns the compressed CI summary, not the
#     raw n_boot x k x n cube): `ci_lower` / `ci_upper` (2.5% / 97.5%
#     percentile bounds, labelled k x samples), `support_stability`
#     (frequency of support = 1 across replicates), `n_boot`, `seed`,
#     `ci_level`;
#   * the `support` table gains a `boot_stability` column;
#   * `exposures`/`tests` remain the POINT fit (one unresampled call of the
#     same kernel) -- "boundary parameters get tests, not intervals", the
#     CI is support-conditional evidence, not a replacement for the LRT.
# ---------------------------------------------------------------------------

#' Bootstrap percentile confidence intervals for signature exposures
#'
#' `ms_fit_bootstrap()` quantifies sampling uncertainty of the fitted
#' exposures by **nonparametric (multinomial) bootstrap** (research/02
#' section 2 semantics): every replicate resamples each sample's mutations
#' from its empirical channel distribution, refits the selected method, and
#' the exposure distribution across replicates yields the 2.5% / 97.5%
#' **percentile CI** and the **support stability** (the frequency with
#' which the share-rule zeroing keeps each exposure). Parallelism runs
#' between replicates only (per-call pool, contract 6); the output is a
#' pure function of `(catalog, signatures, method, n_boot, seed)` and is
#' bit-identical for every thread count. All violations raise
#' `msuiter_error_*` conditions.
#'
#' @param catalog An [MsCatalog] object, as returned by [ms_tally()] or
#'   [ms_catalog()].
#' @param signatures The dictionary to fit against: a numeric matrix
#'   (channels x signatures) or an [MsSignature], resolved exactly as in
#'   [ms_fit()].
#' @param method Single string: the fitting method reused for every
#'   replicate (`"nnls"` default, `"likelihood_bidirectional"` or `"lrt"`;
#'   see [ms_fit()]).
#' @param n_boot Single positive whole number: the number of bootstrap
#'   replicates (default 200, the signature.tools.lib `nboot` family
#'   anchor). sigminer's serial budget is cleared by >= 100x on the Rust
#'   per-call pool (CAPABILITY-MATRIX L-D).
#' @param seed Single non-negative whole number: the master seed addressing
#'   the per-boot canonical PCG64 streams (boot `b` draws on
#'   `StreamId{replicate: b, rank: 0, fold: 0}`; per-sample resamples
#'   consume the boot's stream sequentially in fixed sample order). Same
#'   seed, same output -- bit-identically.
#' @param nb_size,zero_threshold As in [ms_fit()].
#' @param n_threads NULL (resolve the `msuiter.threads` option, capped by
#'   `_R_CHECK_LIMIT_CORES_`) or a single non-negative integer pool size;
#'   0 means the rayon default.
#'
#' @details
#' **Result.** An [MsFit] whose point exposures/tests are one ordinary
#' [ms_fit()] run of the selected method, enriched with the bootstrap
#' evidence: the exposures matrix carries `ci_lower`, `ci_upper`,
#' `support_stability` (each a labelled signatures x samples matrix),
#' `n_boot`, `seed` and `ci_level` attributes, and the `support` table
#' gains the `boot_stability` column. The percentile bounds are computed
#' kernel-side with type-7 linear interpolation (the R `quantile` default)
#' over the post-zeroing replicate exposures.
#'
#' @return An [MsFit] object with bootstrap CI attributes.
#'
#' @seealso [ms_fit()] for the point fit, [ms_test_presence()] for the
#'   hypothesis-test axis, [MsFit] for the container.
#' @export
ms_fit_bootstrap <- S7::new_generic(
  "ms_fit_bootstrap",
  "catalog",
  function(catalog, signatures, method = "nnls", n_boot = 200, seed = 1,
           nb_size = 8, zero_threshold = 0.01, n_threads = NULL)
    S7::S7_dispatch()
)

# Method: MsCatalog -> MsFit (bootstrap-enriched). Point fit + bootstrap CI
# through the two FFI faces; assembly reuses the ms_fit conventions.
S7::method(ms_fit_bootstrap, MsCatalog) <- function(catalog, signatures,
                                                    method = "nnls", n_boot = 200,
                                                    seed = 1, nb_size = 8,
                                                    zero_threshold = 0.01,
                                                    n_threads = NULL) {
  prep <- .ms_fit_prepare_dictionary(catalog, signatures)
  .ms_fit_gate_fit_args(method, nb_size, zero_threshold)
  .ms_fit_gate_boot(n_boot, seed)
  n_threads_resolved <- .ms_resolve_threads(n_threads)

  # Point fit (the ms_fit face; identical grids) + the bootstrap CI.
  point <- .ms_fit_rust(prep$counts, prep$signatures, method, nb_size,
    .ms_fit_defaults$eps, .ms_fit_defaults$max_iter, zero_threshold)
  boot <- .ms_fit_bootstrap_rust(prep$counts, prep$signatures, method, n_boot,
    nb_size, zero_threshold, seed, n_threads_resolved)

  # --- assembly: the ms_fit conventions + CI attributes --------------------
  samples <- catalog@samples
  exposures <- point$exposures
  dimnames(exposures) <- list(prep$labels, samples)

  labelled <- function(m) {
    dimnames(m) <- list(prep$labels, samples)
    m
  }
  # Frozen CI levels: the kernel-side BOOTSTRAP_CI_LEVELS pair (2.5/97.5
  # percentile method); re-freezing moves both sides together.
  attr(exposures, "ci_lower") <- labelled(boot$ci_lower)
  attr(exposures, "ci_upper") <- labelled(boot$ci_upper)
  attr(exposures, "support_stability") <- labelled(boot$support_stability)
  attr(exposures, "n_boot") <- boot$n_boot
  attr(exposures, "seed") <- as.integer(seed)
  attr(exposures, "ci_level") <- c(lower = 0.025, upper = 0.975)

  n_samples <- length(samples)
  k <- length(prep$labels)
  signature_col <- rep(prep$labels, times = n_samples)
  sample_col <- rep(samples, each = k)
  exposure_vec <- as.vector(exposures) # column-major: sample-major, then signature
  total_per_sample <- rep(colSums(exposures), each = k) # column-major: k rows per sample
  share_vec <- ifelse(total_per_sample > 0, exposure_vec / total_per_sample, 0)
  support <- data.frame(
    signature = signature_col,
    sample = sample_col,
    exposure = exposure_vec,
    share = share_vec,
    active = as.logical(as.vector(point$support)),
    boot_stability = as.vector(boot$support_stability),
    stringsAsFactors = FALSE
  )
  se_vec <- as.vector(point$se)
  se_vec[is.nan(se_vec)] <- NA_real_ # boundary: no interval, only tests
  tests <- data.frame(
    signature = signature_col,
    sample = sample_col,
    lrt_stat = as.vector(point$lrt_stat),
    lrt_p = as.vector(point$lrt_p),
    se = se_vec,
    stringsAsFactors = FALSE
  )

  reference_summary <- list(
    version = "adhoc-1",
    class = "adhoc",
    build = NA_character_, # labels are build-independent
    schema_version = "1",
    sha256 = .ms_fit_sha256_labels(prep$labels),
    n_signatures = length(prep$labels)
  )

  MsFit(
    exposures = exposures,
    engine = method,
    reference_summary = reference_summary,
    support = support,
    tests = tests
  )
}

# Fallback: dispatch error as a project condition.
S7::method(ms_fit_bootstrap, S7::class_any) <- function(catalog, signatures,
                                                        method = "nnls", n_boot = 200,
                                                        seed = 1, nb_size = 8,
                                                        zero_threshold = 0.01,
                                                        n_threads = NULL) {
  msuiter_abort(
    "input",
    "catalog must be an MsCatalog object",
    i = "ms_fit_bootstrap() dispatches on MsCatalog (the bootstrap resamples the raw counts)",
    j = paste0("received: ", class(catalog)[1L]),
    c = "build the catalog with ms_tally() first"
  )
}

# ---------------------------------------------------------------------------
# FFI wrapper over ms_fit_rust (the kernel face of this unit). The layout
# contract (docs/ffi-surface.md, fit.rs module docs): the Rust kernel
# consumes the row-major m x n counts and the row-major m x k signatures;
# R stores matrices column-major, so t(counts) (n x m) and t(sigs) (k x m)
# are passed -- their flat buffers ARE the kernel's row-major matrices. The
# transposition guard is the asymmetric-golden discipline (acceptance smokes
# on both sides run on m != n shapes).
# ---------------------------------------------------------------------------

#' Fitting kernel wrapper over ms_fit_rust (U-M3a-02).
#'
#' Internal wrapper over the Rust kernel: the three fitting methods on one
#' bounded sequential batch. Returns the RAW kernel grids; label assembly,
#' tidy tables and the adhoc reference snapshot live in `ms_fit()`.
#' @param counts,signatures channels x samples / channels x signatures
#'   double matrices (no NA/NaN).
#' @param method,nb_size,tol,max_iter,zero_threshold Validated scalars
#'   (the kernel re-checks every domain).
#' @param threads NULL or a single non-negative integer pool size
#'   (`.ms_resolve_threads()`); this unit is sequential (A7), the resolved
#'   value only feeds the FFI surface contract.
#' @return Named list: `exposures` (k x samples), `support` (k x samples
#'   integer 0/1), `lrt_stat` / `lrt_p` / `se` (k x samples; NaN = boundary
#'   standard error), `method`, `converged`.
#' @keywords internal
#' @noRd
.ms_fit_rust <- function(counts, signatures, method, nb_size, tol, max_iter,
                         zero_threshold, threads = NULL) {
  counts <- .ms_validate_matrix(counts, "counts")
  signatures <- .ms_validate_matrix(signatures, "signatures")
  if (!is.character(method) || length(method) != 1L || is.na(method) ||
      !method %in% .ms_fit_methods) {
    msuiter_abort(
      "input",
      '`method` must be a single string, one of "nnls", "likelihood_bidirectional", "lrt".',
      i = "the kernel face exposes exactly the three fitting methods of this unit",
      j = paste0("`method` received: ", msuiter_quote_trunc(method)),
      c = 'pass "nnls", "likelihood_bidirectional" or "lrt"',
      data = list(context = "FFI argument validation (fitting method switch)")
    )
  }
  if (!is.numeric(nb_size) || length(nb_size) != 1L || is.na(nb_size) ||
      !is.finite(nb_size) || nb_size <= 0) {
    msuiter_abort(
      "input",
      "`nb_size` must be a single positive number.",
      i = "nb_size is the negative-binomial size at the FFI boundary (f64)",
      j = paste0("`nb_size` received: ", msuiter_quote_trunc(nb_size)),
      c = "pass a single positive number (default 8, the mSigAct SBS96 anchor)",
      data = list(context = "FFI argument validation (NB size)")
    )
  }
  if (!is.numeric(tol) || length(tol) != 1L || is.na(tol) ||
      !is.finite(tol) || tol < 0) {
    msuiter_abort(
      "input",
      "`tol` must be a single non-negative number.",
      i = "tol is the MuSiCal epsilon of the bidirectional method",
      j = paste0("`tol` received: ", msuiter_quote_trunc(tol)),
      c = "pass the epsilon threshold (default 0.001)",
      data = list(context = "FFI argument validation (bidirectional epsilon)")
    )
  }
  if (!is.numeric(max_iter) || length(max_iter) != 1L || is.na(max_iter) ||
      !is.finite(max_iter) || max_iter != floor(max_iter) || max_iter < 1) {
    msuiter_abort(
      "input",
      "`max_iter` must be a single whole number >= 1.",
      i = "max_iter caps the bidirectional rounds and the NB-MLE iterations",
      j = paste0("`max_iter` received: ", msuiter_quote_trunc(max_iter)),
      c = "pass a single whole number >= 1 (default 1000)",
      data = list(context = "FFI argument validation (iteration cap)")
    )
  }
  if (!is.numeric(zero_threshold) || length(zero_threshold) != 1L ||
      is.na(zero_threshold) || !is.finite(zero_threshold) ||
      zero_threshold < 0 || zero_threshold > 1) {
    msuiter_abort(
      "input",
      "`zero_threshold` must be a single number in [0, 1].",
      i = "the zeroing decision runs kernel-side on the returned exposures",
      j = paste0("`zero_threshold` received: ", msuiter_quote_trunc(zero_threshold)),
      c = "pass a share threshold in [0, 1] (default 0.01)",
      data = list(context = "FFI argument validation (zeroing threshold)")
    )
  }
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(ms_fit_rust(
    t(counts), t(signatures), method, as.numeric(nb_size), as.numeric(tol),
    as.integer(max_iter), as.numeric(zero_threshold), n_threads
  ))
}

# ---------------------------------------------------------------------------
# FFI wrapper over ms_fit_bootstrap_rust (U-M3a-03). Same layout contract as
# .ms_fit_rust (t(counts) / t(sigs)); the tol/max_iter hyper-parameters are
# the frozen .ms_fit_defaults on BOTH sides (the kernel face takes
# fit::FIT_EPS / fit::FIT_MAX_ITER, documented there).
# ---------------------------------------------------------------------------

#' Bootstrap kernel wrapper over ms_fit_bootstrap_rust (U-M3a-03).
#' @param counts,signatures channels x samples / channels x signatures
#'   double matrices (no NA/NaN).
#' @param method,n_boot,nb_size,zero_threshold,seed Validated scalars (the
#'   kernel re-checks every domain).
#' @param threads NULL or a single non-negative integer pool size; 0 = the
#'   rayon default. Parallelism is BETWEEN boots (contract 6).
#' @return Named list: `ci_lower` / `ci_upper` / `support_stability`
#'   (k x samples column-major), `n_boot`, `method`, `converged`.
#' @keywords internal
#' @noRd
.ms_fit_bootstrap_rust <- function(counts, signatures, method, n_boot, nb_size,
                                   zero_threshold, seed, threads = NULL) {
  counts <- .ms_validate_matrix(counts, "counts")
  signatures <- .ms_validate_matrix(signatures, "signatures")
  .ms_fit_gate_method(method)
  .ms_fit_gate_nb_size(nb_size)
  .ms_fit_gate_zero_threshold(zero_threshold)
  .ms_fit_gate_boot(n_boot, seed)
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(ms_fit_bootstrap_rust(
    t(counts), t(signatures), method, as.integer(n_boot), as.numeric(nb_size),
    as.numeric(zero_threshold), as.integer(seed), n_threads
  ))
}

# ---------------------------------------------------------------------------
# Adhoc reference snapshot digest (A5/A13): the summary of a user-supplied
# dictionary pins the signature labels. Base R ships no SHA-2 face
# (tools::md5sum only) and the dependency budget is closed (D2/D4), so the
# FIPS 180-4 SHA-256 lives here in pure R. It runs once per ms_fit() call
# at the API boundary (validators never run in hot loops) on a payload of
# a few hundred bytes.
# ---------------------------------------------------------------------------

# The 64 round constants of FIPS 180-4 (hex), parsed to exact doubles via
# 16-bit halves (strtoi overflows past 2^31 on the large constants).
.ms_fit_sha256_k <- vapply(
  c(
    "428a2f98", "71374491", "b5c0fbcf", "e9b5dba5", "3956c25b", "59f111f1",
    "923f82a4", "ab1c5ed5", "d807aa98", "12835b01", "243185be", "550c7dc3",
    "72be5d74", "80deb1fe", "9bdc06a7", "c19bf174", "e49b69c1", "efbe4786",
    "0fc19dc6", "240ca1cc", "2de92c6f", "4a7484aa", "5cb0a9dc", "76f988da",
    "983e5152", "a831c66d", "b00327c8", "bf597fc7", "c6e00bf3", "d5a79147",
    "06ca6351", "14292967", "27b70a85", "2e1b2138", "4d2c6dfc", "53380d13",
    "650a7354", "766a0abb", "81c2c92e", "92722c85", "a2bfe8a1", "a81a664b",
    "c24b8b70", "c76c51a3", "d192e819", "d6990624", "f40e3585", "106aa070",
    "19a4c116", "1e376c08", "2748774c", "34b0bcb5", "391c0cb3", "4ed8aa4a",
    "5b9cca4f", "682e6ff3", "748f82ee", "78a5636f", "84c87814", "8cc70208",
    "90befffa", "a4506ceb", "bef9a3f7", "c67178f2"
  ),
  function(h) {
    strtoi(substr(h, 1, 4), 16L) * 65536 + strtoi(substr(h, 5, 8), 16L)
  },
  numeric(1L)
)

# Initial hash values (FIPS 180-4 section 5.3.3), same 16-bit-halves parse.
.ms_fit_sha256_h0 <- vapply(
  c(
    "6a09e667", "bb67ae85", "3c6ef372", "a54ff53a",
    "510e527f", "9b05688c", "1f83d9ab", "5be0cd19"
  ),
  function(h) {
    strtoi(substr(h, 1, 4), 16L) * 65536 + strtoi(substr(h, 5, 8), 16L)
  },
  numeric(1L)
)

# 32-bit bitwise helpers on exact doubles (all values < 2^32; the R-int
# bitwXor family only sees 16-bit halves, so no overflow ever occurs).
.ms_fit_xor32 <- function(a, b) {
  bitwXor(a %/% 65536L, b %/% 65536L) * 65536 +
    bitwXor(as.integer(a %% 65536), as.integer(b %% 65536))
}
.ms_fit_and32 <- function(a, b) {
  bitwAnd(a %/% 65536L, b %/% 65536L) * 65536 +
    bitwAnd(as.integer(a %% 65536), as.integer(b %% 65536))
}
.ms_fit_not32 <- function(a) 4294967295 - a
.ms_fit_rotr32 <- function(x, n) {
  x %% 2^n * 2^(32 - n) + (x %/% 2^n)
}
.ms_fit_add32 <- function(a, b) (a + b) %% 4294967296

#' Pure-R SHA-256 over a raw vector (FIPS 180-4).
#' @noRd
.ms_fit_sha256 <- function(x) {
  stopifnot(is.raw(x))
  # Padding: 0x80, zero bytes to 56 mod 64, 64-bit big-endian bit length
  # (payload sizes here are far below the 2^53-exact double range).
  bit_len <- length(x) * 8
  x <- c(x, as.raw(0x80))
  while (length(x) %% 64L != 56L) x <- c(x, as.raw(0L))
  len_bytes <- raw(8L)
  bl <- bit_len
  for (i in 8L:1L) {
    len_bytes[i] <- as.raw(bl %% 256)
    bl <- bl %/% 256
  }
  words <- c(x, len_bytes)

  h <- .ms_fit_sha256_h0
  n_blocks <- length(words) %/% 64L
  for (b in seq_len(n_blocks)) {
    base <- (b - 1L) * 64L
    w <- vapply(0L:15L, function(j) {
      as.numeric(words[base + 4L * j + 1L]) * 16777216 +
        as.numeric(words[base + 4L * j + 2L]) * 65536 +
        as.numeric(words[base + 4L * j + 3L]) * 256 +
        as.numeric(words[base + 4L * j + 4L])
    }, numeric(1L))
    for (j in 17L:64L) {
      s0 <- .ms_fit_xor32(
        .ms_fit_xor32(.ms_fit_rotr32(w[j - 15L], 7), .ms_fit_rotr32(w[j - 15L], 18)),
        w[j - 15L] %/% 8
      )
      s1 <- .ms_fit_xor32(
        .ms_fit_xor32(.ms_fit_rotr32(w[j - 2L], 17), .ms_fit_rotr32(w[j - 2L], 19)),
        w[j - 2L] %/% 1024
      )
      w[j] <- .ms_fit_add32(.ms_fit_add32(.ms_fit_add32(w[j - 16L], s0), w[j - 7L]), s1)
    }
    a <- h[1]; bb <- h[2]; cc <- h[3]; dd <- h[4]
    e <- h[5]; f <- h[6]; g <- h[7]; hh <- h[8]
    for (j in 1L:64L) {
      s1 <- .ms_fit_xor32(.ms_fit_xor32(.ms_fit_rotr32(e, 6), .ms_fit_rotr32(e, 11)), .ms_fit_rotr32(e, 25))
      ch <- .ms_fit_xor32(.ms_fit_and32(e, f), .ms_fit_and32(.ms_fit_not32(e), g))
      t1 <- .ms_fit_add32(.ms_fit_add32(.ms_fit_add32(.ms_fit_add32(hh, s1), ch), .ms_fit_sha256_k[j]), w[j])
      s0 <- .ms_fit_xor32(.ms_fit_xor32(.ms_fit_rotr32(a, 2), .ms_fit_rotr32(a, 13)), .ms_fit_rotr32(a, 22))
      maj <- .ms_fit_xor32(.ms_fit_xor32(.ms_fit_and32(a, bb), .ms_fit_and32(a, cc)), .ms_fit_and32(bb, cc))
      t2 <- .ms_fit_add32(s0, maj)
      hh <- g; g <- f; f <- e
      e <- .ms_fit_add32(dd, t1)
      dd <- cc; cc <- bb; bb <- a
      a <- .ms_fit_add32(t1, t2)
    }
    h[1] <- .ms_fit_add32(h[1], a); h[2] <- .ms_fit_add32(h[2], bb)
    h[3] <- .ms_fit_add32(h[3], cc); h[4] <- .ms_fit_add32(h[4], dd)
    h[5] <- .ms_fit_add32(h[5], e); h[6] <- .ms_fit_add32(h[6], f)
    h[7] <- .ms_fit_add32(h[7], g); h[8] <- .ms_fit_add32(h[8], hh)
  }
  # 256-bit big-endian digest as lowercase hex.
  paste(
    vapply(h, function(v) {
      parts <- c(v %/% 16777216 %% 256, v %/% 65536 %% 256, v %/% 256 %% 256, v %% 256)
      paste(sprintf("%02x", as.integer(parts)), collapse = "")
    }, character(1L)),
    collapse = ""
  )
}

# Canonical-labels digest of the fitted dictionary: the same
# length-prefixed UTF-8 payload construction as msuiter_hash_labels
# (classes-utils.R), digested with SHA-256 (the MsFit snapshot contract
# requires a 64-hex digest).
.ms_fit_sha256_labels <- function(labels) {
  if (!is.character(labels) || anyNA(labels)) {
    msuiter_abort(
      "input",
      "signature labels to hash must be a character vector without NA",
      i = "the adhoc reference digest is only defined for plain label vectors",
      j = paste0("received: ", class(labels)[1L], " with anyNA = ", anyNA(labels)),
      c = "fit against a dictionary with plain character labels"
    )
  }
  payload <- paste0(
    paste(c(as.character(length(labels)), enc2utf8(labels)), collapse = "\n"),
    "\n"
  )
  .ms_fit_sha256(charToRaw(payload))
}

# ---------------------------------------------------------------------------
# U-M3a-03: ms_test_presence() -- cohort per-signature presence test with
# Benjamini-Hochberg multiplicity control (research/02 section 2, the
# mSigAct "chi^2_1 + BH q" semantics; CAPABILITY-MATRIX L-D "chi^2_1 LRT
# p/q").
#
# P0 CORRECTION (2026-10 independent audit): the pooled raw p is the exact
# pooled-null tail. Under H0 (signature absent in every sample) each
# per-sample entry-wise statistic is 1/2 * delta_0 + 1/2 * chi^2_1 (the
# Self-Liang boundary law), so the pooled sum over n independent samples is
# EXACTLY Binomial(n, 1/2)-mixed chi^2: sum_m C(n,m)/2^n * chi^2_m. The
# previously shipped reference (a single chi^2_1 half-tail on the pooled
# statistic) is exact only for n = 1 and anti-conservative for n >= 2 (H0
# pass_bh rates 0.135/0.545/0.860 at n = 2/8/16 in the audit's simulation).
# This is a correction of the chi-square REFERENCE, not a new statistic:
# the pooled estimand, the per-sample lrt_p columns, BH and pass_bh logic
# are unchanged; at n = 1 the new p is bit-identical to the old half-tail.
#
# Two dispatch faces over one result shape (k rows, one per signature):
#   * MsCatalog (+ a dictionary): the kernel face -- the entry-wise
#     presence LRT machinery of ms_fit (method-independent by
#     construction), pooled across samples by summing the per-sample
#     statistics, raw p = the exact pooled-null tail (kernel
#     fit::pooled_presence_p), BH over the k-signature family, all
#     computed in the Rust kernel.
#   * MsFit: the same aggregation over the fit's `tests` grid (the kernel
#     evidence is method-independent, so any ms_fit method's grid pools
#     identically) -- stat = sum over samples, raw p = the same exact
#     pooled-null tail re-derived in R (.ms_presence_pooled_p: dbinom
#     weights x pchisq upper tails), BH via the pure-R twin .ms_bh_adjust
#     of the kernel's fold-back.
#
# `pass_bh` uses the frozen family-wise alpha 0.05 (kernel fit::BH_ALPHA;
# raw and adjusted p are returned so callers can re-threshold).
# ---------------------------------------------------------------------------

#' Cohort presence test for signature exposures (BH-corrected LRT)
#'
#' `ms_test_presence()` tests, per signature, the hypothesis that the
#' signature is present in the cohort, with Benjamini-Hochberg multiplicity
#' control over the signature family (research/02 section 2; the mSigAct
#' chi^2_1 + BH q semantics). The evidence is the entry-wise presence LRT
#' of [ms_fit()] -- which is method-independent by construction: per
#' sample, the full NB-MLE model against the model refit without the
#' signature, `D = 2(ll_with - ll_without)`. Per-sample statistics are
#' pooled across the cohort by summation (independent likelihoods add).
#'
#' **Exact pooled null (P0 correction, 2026-10 independent audit).** Under
#' H0 each per-sample statistic follows the Self-Liang boundary law
#' `1/2 * delta_0 + 1/2 * chi^2_1`, so the pooled statistic over n
#' independent samples has the exact null law
#' `sum_m C(n,m)/2^n * chi^2_m` (a Binomial(n, 1/2) mixture of
#' chi-squares); `p_raw` is the strict upper tail of that reference. At
#' n = 1 it is bit-identical to the Self-Liang half-tail
#' `1/2 * pchisq(D, 1, lower.tail = FALSE)`. For n >= 2 the earlier
#' chi^2_1 reference was anti-conservative (the statistic grows with n
#' while the reference does not); this is a correction of the chi-square
#' reference, not a change of estimand. All violations raise
#' `msuiter_error_*` conditions.
#'
#' @param x An [MsCatalog] (together with `signatures`; the test runs in
#'   the Rust kernel) or an existing [MsFit] (the test aggregates the
#'   fit's evidence grid; `signatures` must then be NULL).
#' @param signatures The dictionary for the catalog face: a numeric matrix
#'   (channels x signatures) or an [MsSignature], resolved exactly as in
#'   [ms_fit()]. Ignored (must stay NULL) on the MsFit face.
#' @param nb_size Single positive number: the negative-binomial size
#'   (mSigAct `nbinom.size`; default 8, the SBS96 anchor). Only used on
#'   the catalog face (the MsFit face reuses the fit's evidence).
#' @param ... Reserved for future extensions; unused.
#'
#' @details
#' **Result.** A data.frame with one row per signature (the dictionary
#' order), columns `signature`, `stat` (pooled LRT statistic),
#' `p_raw` (exact pooled-null p-value, before correction), `p_bh`
#' (Benjamini-Hochberg adjusted p over the k-signature family: sorted
#' p x m/i with the cumulative-minimum fold-back, capped at 1) and
#' `pass_bh` (`p_bh <= 0.05`, the frozen family-wise alpha).
#'
#' The BH arithmetic is bit-identical between the Rust kernel and the
#' pure-R twin used on the MsFit face (same operation order, stable
#' tie-breaking; pinned by tests).
#'
#' @return A data.frame with k rows.
#'
#' @seealso [ms_fit()] for the evidence machinery, [ms_fit_bootstrap()]
#'   for the interval axis.
#' @export
ms_test_presence <- S7::new_generic(
  "ms_test_presence",
  "x",
  function(x, signatures = NULL, ..., nb_size = 8) S7::S7_dispatch()
)

# Method: MsCatalog -> kernel face.
S7::method(ms_test_presence, MsCatalog) <- function(x, signatures = NULL,
                                                    ..., nb_size = 8) {
  prep <- .ms_fit_prepare_dictionary(x, signatures)
  .ms_fit_gate_nb_size(nb_size)
  res <- .ms_test_presence_rust(prep$counts, prep$signatures, nb_size)
  data.frame(
    signature = prep$labels,
    stat = res$lrt_stat,
    p_raw = res$lrt_p_raw,
    p_bh = res$lrt_p_bh,
    pass_bh = as.logical(res$pass_bh),
    stringsAsFactors = FALSE
  )
}

# Method: MsFit -> aggregate the fit's evidence grid (k rows).
S7::method(ms_test_presence, MsFit) <- function(x, signatures = NULL,
                                                ..., nb_size = 8) {
  if (!is.null(signatures)) {
    msuiter_abort(
      "input",
      "signatures must stay NULL when x is an MsFit",
      i = "the MsFit face aggregates the fit's own evidence grid",
      j = paste0("received: ", class(signatures)[1L]),
      c = "call ms_test_presence(catalog, signatures) to test a new dictionary"
    )
  }
  labels <- rownames(x@exposures)
  if (is.null(labels) || anyNA(labels) || anyDuplicated(labels) > 0L ||
      !all(nzchar(labels))) {
    msuiter_abort(
      "fit",
      "the fit's exposures must carry non-empty, unique row labels",
      i = "the presence table is keyed by signature label",
      j = msuiter_quote_trunc(labels),
      c = "fit with ms_fit(), which labels the exposures by signature"
    )
  }
  tests <- x@tests
  # Pooled statistic: sum of the per-sample entry-wise statistics, in the
  # exposures' signature order (per signature, samples ascend -- the same
  # accumulation order as the kernel face; equality is analytic, the R
  # path re-derives the p-values from the pooled statistic).
  stat <- vapply(labels, function(s) sum(tests$lrt_stat[tests$signature == s]),
    numeric(1L), USE.NAMES = FALSE
  )
  # The exact pooled-null tail (Binomial(n, 1/2)-mixed chi^2; the pure-R
  # twin of the kernel's fit::pooled_presence_p). n = the fit's sample
  # count; at n = 1 the twin is bit-identical to the Self-Liang half-tail.
  p_raw <- .ms_presence_pooled_p(stat, ncol(x@exposures))
  p_bh <- .ms_bh_adjust(p_raw)
  data.frame(
    signature = labels,
    stat = stat,
    p_raw = p_raw,
    p_bh = p_bh,
    pass_bh = p_bh <= .MS_PRESENCE_BH_ALPHA,
    stringsAsFactors = FALSE
  )
}

# Fallback: dispatch error as a project condition.
S7::method(ms_test_presence, S7::class_any) <- function(x, signatures = NULL,
                                                        ..., nb_size = 8) {
  msuiter_abort(
    "input",
    "x must be an MsCatalog or an MsFit object",
    i = "ms_test_presence() dispatches on the catalog face (kernel) and the MsFit face (aggregation)",
    j = paste0("received: ", class(x)[1L]),
    c = "fit with ms_fit() first, or pass an MsCatalog together with a dictionary"
  )
}

# ---------------------------------------------------------------------------
# FFI wrapper over ms_test_presence_rust (U-M3a-03). Same layout contract as
# .ms_fit_rust (t(counts) / t(sigs)); sequential bounded batch (A7), the
# resolved pool size only feeds the FFI surface contract.
# ---------------------------------------------------------------------------

#' Presence-test kernel wrapper over ms_test_presence_rust (U-M3a-03).
#' @param counts,signatures channels x samples / channels x signatures
#'   double matrices (no NA/NaN).
#' @param nb_size Validated positive scalar (the kernel re-checks).
#' @param threads NULL or a single non-negative integer pool size.
#' @return Named list: `lrt_stat` / `lrt_p_raw` / `lrt_p_bh` (length k),
#'   `pass_bh` (logical k), `converged`.
#' @keywords internal
#' @noRd
.ms_test_presence_rust <- function(counts, signatures, nb_size, threads = NULL) {
  counts <- .ms_validate_matrix(counts, "counts")
  signatures <- .ms_validate_matrix(signatures, "signatures")
  .ms_fit_gate_nb_size(nb_size)
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(ms_test_presence_rust(
    t(counts), t(signatures), as.numeric(nb_size), n_threads
  ))
}

# ---------------------------------------------------------------------------
# The exact pooled-null p-value: the pure-R twin of the kernel's
# fit::pooled_presence_p (P0 correction, 2026-10 independent audit).
#
# Under H0 each per-sample entry-wise statistic is 1/2 * delta_0 +
# 1/2 * chi^2_1 (Self-Liang boundary law) and independent samples make the
# pooled sum D = sum_j D_j exactly Binomial(n, 1/2)-mixed chi^2:
#   p(D) = sum_m C(n,m)/2^n * P(chi^2_m > D).
# The m = 0 atom is P(0 > D) = 0 for every admissible D >= 0 and is
# handled explicitly (R's pchisq(x, df = 0, lower.tail = FALSE) uses a
# different convention at x = 0). dbinom underflows to 0 in the far tails,
# which is exactly the kernel's documented weight-floor skip; both faces
# therefore evaluate the same mathematical quantity to well below the
# 1e-8 face-agreement tolerance.
# ---------------------------------------------------------------------------

#' Exact pooled-null p-value (pure-R twin of fit::pooled_presence_p).
#' @param stat Numeric pooled statistics (any values; NA/Inf pass through
#'   with the same semantics as the kernel: NA -> NA, negative -> 1,
#'   +Inf -> 0).
#' @param n Single positive sample count.
#' @return Numeric vector of pooled-null upper-tail p-values.
#' @keywords internal
#' @noRd
.ms_presence_pooled_p <- function(stat, n) {
  if (!is.numeric(stat) || length(stat) < 1L) {
    msuiter_abort(
      "input",
      "stat must be a non-empty numeric vector",
      i = "the pooled-null tail is evaluated per signature statistic",
      j = paste0("received: ", msuiter_quote_trunc(stat)),
      c = "pass the pooled lrt_stat vector of one presence-test family"
    )
  }
  n <- as.integer(n)
  if (length(n) != 1L || is.na(n) || n < 1L) {
    msuiter_abort(
      "input",
      "n must be a single positive sample count",
      i = "the pooled null is the Binomial(n, 1/2)-mixed chi^2 over n samples",
      j = paste0("received: ", msuiter_quote_trunc(n)),
      c = "pass the fit's sample count (ncol(exposures))"
    )
  }
  m <- seq_len(n + 1L) - 1L
  # C(n,m)/2^n for m = 1..n (the m = 0 atom contributes 0 for D >= 0 and
  # is handled by the d < 0 branch below). Far-tail weights underflow to 0
  # exactly like the kernel's MIXTURE_LN_WEIGHT_FLOOR skip.
  w <- dbinom(m[-1L], size = n, prob = 0.5)
  vapply(
    stat,
    function(d) {
      if (is.na(d)) {
        return(NA_real_)
      }
      if (d < 0) {
        return(1) # every mixture component exceeds a negative threshold
      }
      if (d == Inf) {
        return(0)
      }
      sum(w * pchisq(d, df = m[-1L], lower.tail = FALSE))
    },
    numeric(1L),
    USE.NAMES = FALSE
  )
}

# ---------------------------------------------------------------------------
# BH constants and the pure-R twin of the kernel's Benjamini-Hochberg
# fold-back (fit::bh_adjust). The MsFit face of ms_test_presence() uses the
# twin because the kernel only sees raw catalogs; the arithmetic is
# bit-identical (same operation order, stable ties) and pinned by tests
# against the kernel face.
# ---------------------------------------------------------------------------

# Frozen family-wise alpha of the `pass_bh` verdict (kernel fit::BH_ALPHA;
# re-freezing moves both sides together).
.MS_PRESENCE_BH_ALPHA <- 0.05

# Benjamini-Hochberg step-up adjusted p-values: sort ascending, scale the
# i-th smallest by m/i, cumulative-minimum fold-back from the largest p
# (the "monotone re-fold"), cap at 1. `order()` is stable, matching the
# kernel's first-index tie-breaking; the op order (p * m / i, then the min
# chain, then the cap) mirrors the Rust face bit-for-bit.
.ms_bh_adjust <- function(p) {
  if (!is.numeric(p) || length(p) < 1L || anyNA(p) || any(!is.finite(p)) ||
      any(p < 0) || any(p > 1)) {
    msuiter_abort(
      "input",
      "p-values must be a non-empty numeric vector in [0, 1] without NA",
      i = "the BH correction runs over one family of raw p-values",
      j = paste0("received: ", msuiter_quote_trunc(p)),
      c = "pass the raw p-value vector of one test family"
    )
  }
  m <- length(p)
  ord <- order(p)
  scaled <- p[ord] * m / seq_len(m)
  adj <- rev(cummin(rev(scaled)))
  out <- numeric(m)
  out[ord] <- pmin(1, adj)
  out
}
