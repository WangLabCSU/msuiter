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

# Method: MsCatalog -> MsFit. Resolves the dictionary (matrix or
# MsSignature), aligns and normalizes it, runs the kernel through the FFI
# wrapper and assembles the validated MsFit.
S7::method(ms_fit, MsCatalog) <- function(catalog, signatures, method = "nnls",
                                          nb_size = 8, zero_threshold = 0.01) {
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

  # --- scalar gates (FFI contract 4, first layer) --------------------------
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
