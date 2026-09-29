# extract.R: the extraction entry point ms_extract() (U-M1s-12).
#
# ARCHITECTURE.md sections 3.1/3.2: ms_extract() is the third link of the
# working grammar (ms_variants() |> ms_tally() |> ms_extract() |> ...). It
# dispatches on an [MsCatalog], resolves the engine spec (A14: an MsEngine
# object is the first-class citizen, strings are sugar resolved through
# match_ms_engine(), NULL defaults to ms_nmf()) and runs the extraction
# through the registry (fit_engine -> the registered fit_fn ->
# .ms_extract_rust). M1s ships the SINGLE-METHOD default: one seeded
# KL-NMF fit. The D16 consensus-CV default pipeline arrives in M2
# (docs/ROADMAP.md) and will replace the default then -- documented, not
# silently changed.
#
# Assembly layer duties (no semantics added beyond display):
#   * labels: signatures carry the catalog channel labels as rownames and
#     Sig1..k as colnames; exposures carry Sig1..k as rownames and the
#     catalog sample labels as colnames;
#   * display normalization: the kernel returns RAW factors W/H. W columns
#     are normalized to sum 1 (the catalog convention for signatures) and
#     each H row is multiplied by the same factor, so the W*H
#     reconstruction is preserved up to floating-point rounding;
#   * snapshot summary: catalog_summary = msuiter_catalog_summary(catalog)
#     (A5: dimensions + channel-table hash + build, never the catalog).
#
# All violations raise msuiter_error_* conditions with the i/j/c payload
# (ARCHITECTURE section 3.5); bare stop() is banned.

#' Extract signatures from a catalog
#'
#' `ms_extract()` runs a signature extraction engine on an [MsCatalog] and
#' returns an [MsSignature]. The method is an [MsEngine] spec built with a
#' factory such as [ms_nmf()] (first-class citizen, A14); a single string
#' (`"nmf"`) is sugar resolved against the engine registry via
#' [match_ms_engine()], and `NULL` picks the package default
#' (`ms_nmf()`). All violations raise `msuiter_error_*` conditions.
#'
#' @param catalog An [MsCatalog] object, as returned by [ms_tally()] or
#'   [ms_catalog()].
#' @param k Single positive whole number of signatures to extract; must not
#'   exceed `min(nrow(counts), ncol(counts))` (a rank-k NMF needs at most
#'   one rank per channel and per sample).
#' @param method An [MsEngine] spec ([ms_nmf()]), a single registered
#'   engine name (`"nmf"`), or `NULL` (default: `ms_nmf()`).
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @details
#' M1s default (single method): one seeded KL-NMF fit (D6) on the Rust
#' kernel, deterministic and thread-invariant. The `method = NULL` default
#' is the single KL-NMF method for now; the consensus-CV extraction
#' pipeline (ensemble + consensus + K arbitration) becomes the D16 default
#' in M2 and will replace it documentedly -- hyper-parameters are frozen on
#' the spec, so `ms_extract(cat, 3, ms_nmf(engine = "kl", seed = 42))`
#' keeps reproducing today's result across versions.
#'
#' Normalization declaration: the kernel returns raw factors W (channels x
#' signatures) and H (signatures x samples). The assembly layer scales each
#' W column to sum 1 (the catalog convention for signature profiles) and
#' multiplies each H row by the same factor, so the `signatures %*%
#' exposures` reconstruction of the counts is preserved up to
#' floating-point rounding; exposures therefore carry the per-sample
#' mutation mass attributed to each signature.
#'
#' @return An [MsSignature] object with the extracted `signatures`,
#'   `exposures`, the source `catalog_summary` snapshot (A5: dimensions,
#'   channel-table hash, build -- never the catalog), the engine name, the
#'   seed and empty stability/k_evidence slots (M2 evidence units).
#'
#' @seealso [ms_nmf()] for the engine factory, [ms_tally()] for the
#'   upstream catalog, [ms_signature()] for the low-level constructor.
#' @export
ms_extract <- S7::new_generic(
  "ms_extract",
  "catalog",
  function(catalog, k, method = NULL, ...) S7::S7_dispatch()
)

# Dots discipline (same rule as ms_tally()): no passthrough arguments.
.ms_extract_abort_dots <- function(dots) {
  if (length(dots) == 0L) {
    return(invisible(NULL))
  }
  labels <- names(dots)
  if (is.null(labels)) {
    labels <- rep("", length(dots))
  }
  labels[!nzchar(labels)] <- "<positional>"
  msuiter_abort(
    "input",
    "unknown argument passed to ms_extract()",
    i = "ms_extract() has no passthrough arguments",
    j = paste0("unexpected: ", msuiter_quote_trunc(labels)),
    c = "check the argument spelling against ?ms_extract"
  )
}

# Validate the rank k at the API boundary (the FFI layer re-checks the
# raw scalar; this is the structured, user-facing gate).
.ms_extract_check_k <- function(k, counts) {
  if (!is.numeric(k) || length(k) != 1L || is.na(k) || !is.finite(k) ||
    k != trunc(k) || k < 1) {
    msuiter_abort(
      "input",
      "k must be a single positive whole number",
      i = "k is the number of signatures to extract",
      j = paste0("received: ", msuiter_quote_trunc(k)),
      c = "pass e.g. k = 3 after inspecting the catalog"
    )
  }
  bound <- min(nrow(counts), ncol(counts))
  if (k > bound) {
    msuiter_abort(
      "input",
      sprintf("k must not exceed min(channels, samples) = %d", bound),
      i = "a rank-k NMF needs k <= min(nrow(counts), ncol(counts))",
      j = sprintf("k = %d, catalog has %d channels x %d samples",
        as.integer(k), nrow(counts), ncol(counts)),
      c = "choose a smaller k, or extract from a wider catalog"
    )
  }
  as.integer(k)
}

# Method: MsCatalog -> MsSignature. Single method for M1s; the engine does
# the factorization, this body resolves the spec, validates the rank and
# assembles.
S7::method(ms_extract, MsCatalog) <- function(catalog, k, method = NULL, ...) {
  .ms_extract_abort_dots(list(...))

  counts <- catalog@counts
  if (ncol(counts) < 1L) {
    msuiter_abort(
      "input",
      "the catalog has no samples to extract signatures from",
      i = "extraction needs at least one sample column",
      j = sprintf("catalog: %d channels x %d samples", nrow(counts), ncol(counts)),
      c = "tally a non-empty variant set with ms_tally() first"
    )
  }
  k <- .ms_extract_check_k(k, counts)

  # --- method resolution (A14): object first-class, string sugar, NULL
  #     default. Unknown names fail inside match_ms_engine() with the full
  #     list of registered engines.
  spec <- if (is.null(method)) ms_nmf() else match_ms_engine(method)
  if (!identical(spec@mode, "extract")) {
    msuiter_abort(
      "input",
      "the engine mode must be 'extract' for ms_extract()",
      i = paste(
        "ms_extract() discovers signatures; fitting exposures against a",
        "reference database is ms_fit()"
      ),
      j = sprintf("engine '%s' declares mode '%s'", spec@name, spec@mode),
      c = "pass an extract-mode spec (e.g. ms_nmf()) or use ms_fit()"
    )
  }

  # --- run through the registry (fit_engine dispatches to the registered
  #     fit_fn; the FFI layer validates the raw scalars again).
  raw <- fit_engine(spec, catalog = catalog, k = k)
  signatures <- raw$signatures
  exposures <- raw$exposures

  # --- display normalization: W columns to sum 1, H rows by the same
  #     factors (reconstruction preserved up to floating-point rounding).
  col_sums <- colSums(signatures)
  if (any(!is.finite(col_sums)) || any(col_sums <= 0)) {
    msuiter_abort(
      "signature",
      "the fit degenerated: a signature column has no positive mass",
      i = paste(
        "kernel factors must have strictly positive column sums for the",
        "display normalization; a degenerate column means the fit collapsed"
      ),
      j = msuiter_quote_trunc(which(!is.finite(col_sums) | col_sums <= 0)),
      c = paste(
        "retry with a different seed via ms_nmf(seed = ), or a smaller k"
      )
    )
  }
  signatures <- sweep(signatures, 2, col_sums, `/`)
  exposures <- sweep(exposures, 1, col_sums, `*`)

  # --- labels: strictly by position here (the kernel's row/column order
  #     IS the catalog's -- the layout contract of the FFI handoff), but
  #     carried as labels so everything downstream matches by label.
  sig_labels <- sprintf("Sig%d", seq_len(k))
  dimnames(signatures) <- list(rownames(counts), sig_labels)
  dimnames(exposures) <- list(sig_labels, catalog@samples)

  ms_signature(
    signatures = signatures,
    exposures = exposures,
    catalog_summary = msuiter_catalog_summary(catalog),
    engine = spec@name,
    seed = spec@seed
  )
}

# Fallback: anything that is not an MsCatalog gets a project error instead
# of the raw S7 dispatch failure.
S7::method(ms_extract, S7::class_any) <- function(catalog, k, method = NULL, ...) {
  msuiter_abort(
    "input",
    "catalog must be an MsCatalog object",
    i = "ms_extract() dispatches on MsCatalog",
    j = paste0("received: ", class(catalog)[1L]),
    c = "build the catalog with ms_tally() first (ms_variants() |> ms_tally() |> ms_extract())"
  )
}

# ---------------------------------------------------------------------------
# FFI wrapper over ms_extract_rust (the kernel face of this unit). The
# layout contract (docs/ffi-surface.md, extract.rs module docs): the Rust
# kernel consumes the row-major m x n count matrix; R storage is
# column-major, so t(counts) is passed -- an n x m matrix whose flat buffer
# IS the row-major V. The transposition guard is the asymmetric-golden
# discipline: the acceptance smoke runs on a 96 x 12 catalog (m != n) with
# a reconstruction-cosine gate, which a transposed handoff cannot pass.
# ---------------------------------------------------------------------------

#' Single-method extraction over the FFI (U-M1s-12).
#'
#' Internal wrapper over the Rust kernel: one seeded NMF fit on the
#' canonical zero stream (variant `engine` = `"kl"` or `"eu"`). Returns the
#' RAW (unnormalized) kernel factors; display normalization and label
#' assembly live in `ms_extract()`.
#' @param counts channels x samples double matrix (no NA/NaN).
#' @param k,max_iter,seed Validated scalars (k in [1, min(m, n)] is
#'   re-checked kernel-side with the structured i/j payload).
#' @param engine single string: `"kl"` or `"eu"` (kernel variant switch).
#' @param threads NULL or a single non-negative integer pool size
#'   (`.ms_resolve_threads()`); the M1s single fit is sequential, so the
#'   resolved value only feeds the FFI surface contract.
#' @return Named list: `signatures` (channels x k), `exposures` (k x
#'   samples), `objective` (trace, length max_iter + 1), `iterations`.
#' @keywords internal
#' @noRd
.ms_extract_rust <- function(counts, k, max_iter, seed, engine = "kl",
                             threads = NULL) {
  counts <- .ms_validate_matrix(counts, "counts")
  k <- .ms_validate_count(k, "k")
  if (k < 1L) {
    rlang::abort(
      "`k` must be a positive integer.",
      class = "msuiter_error_input",
      context = "FFI argument validation (rank k >= 1)"
    )
  }
  max_iter <- .ms_validate_count(max_iter, "max_iter")
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
      !is.finite(seed) || seed < 0 || seed != floor(seed) || seed > 2^31 - 1) {
    rlang::abort(
      "`seed` must be a single integer in [0, 2^31 - 1].",
      class = "msuiter_error_input",
      context = "FFI argument validation (RNG seed)"
    )
  }
  if (!is.character(engine) || length(engine) != 1L || is.na(engine) ||
      !engine %in% c("kl", "eu")) {
    rlang::abort(
      '`engine` must be a single string, one of "kl" or "eu".',
      class = "msuiter_error_input",
      context = "FFI argument validation (NMF variant switch)"
    )
  }
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(ms_extract_rust(
    t(counts), k, max_iter, as.integer(seed), engine, n_threads
  ))
}
