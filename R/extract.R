# extract.R: the extraction entry point ms_extract() (U-M1s-12; D16 default
# pipeline assembled in U-M2-03).
#
# ARCHITECTURE.md sections 3.1/3.2: ms_extract() is the third link of the
# working grammar (ms_variants() |> ms_tally() |> ms_extract() |> ...). It
# dispatches on an [MsCatalog] and resolves the engine spec (A14: an MsEngine
# object is the first-class citizen, strings are sugar resolved through
# match_ms_engine()).
#
# Two paths behind one generic:
#   * method = NULL  -> the D16 DEFAULT: the consensus-CV extraction
#     pipeline (U-M2-03): multi-initialization KL ensemble (parallel Rust
#     driver) -> Hungarian consensus (iterative reassignment, U-M2-01) ->
#     per-sample NNLS refit -> SUITOR CV evidence (U-M2-02). The result
#     carries the stability and k_evidence slots (ARCHITECTURE 3.2).
#   * explicit spec  -> the M1s SINGLE-METHOD path through the registry
#     (fit_engine -> the registered fit_fn -> .ms_extract_rust): one seeded
#     KL-NMF fit. This is where the "single seeded fit" lives after the
#     default switch -- as the first-class ms_nmf(engine = "kl") spec, not
#     as a new variant string (the MsNmf validation surface stays frozen;
#     string sugar "nmf" keeps resolving to it).
#
# Assembly layer duties (no semantics added beyond display):
#   * labels: signatures carry the catalog channel labels as rownames and
#     Sig1..k as colnames; exposures carry Sig1..k as rownames and the
#     catalog sample labels as colnames;
#   * display normalization: the kernels return RAW factors W/H. W columns
#     are normalized to sum 1 (the catalog convention for signatures) and
#     each H row is multiplied by the same factor, so the W*H
#     reconstruction is preserved up to floating-point rounding (both
#     paths; the pipeline's refit exposures rescale identically);
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
#' [match_ms_engine()]. All violations raise `msuiter_error_*` conditions.
#'
#' @param catalog An [MsCatalog] object, as returned by [ms_tally()] or
#'   [ms_catalog()].
#' @param k Single positive whole number of signatures to extract; must not
#'   exceed `min(nrow(counts), ncol(counts))` (a rank-k NMF needs at most
#'   one rank per channel and per sample).
#' @param method `NULL` (default) or an [MsEngine] spec ([ms_nmf()]) / a
#'   single registered engine name (`"nmf"`).
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @details
#' **Default (D16, U-M2-03): the consensus-CV extraction pipeline.**
#' `method = NULL` runs the ARCHITECTURE section 5 default path at the
#' requested rank: a multi-initialization KL-NMF ensemble (initialization
#' seeds only, no bootstrap -- PI ruling 2026-09-30), the iterative
#' Hungarian consensus of the stacked replicate signatures (SigProfiler
#' v1.5 semantics, U-M2-01), a per-sample NNLS refit of the exposures
#' against the consensus signatures, and the SUITOR cross-validation
#' evidence on the rank grid `1..k` (U-M2-02). Package defaults are frozen:
#' `replicates = 8`, `max_iter = 200`, `seed = 1`, `k_folds = 10`,
#' `n_seeds = 10` (the seed count is a documented divergence from the
#' SUITOR upstream 30; the effective values are recorded in the result's
#' `stability` slot). The result fills the [MsSignature] `stability` and
#' `k_evidence` slots; `engine` reads `"nmf-pipeline"`. `k_folds` is
#' clamped to the channel count (a catalog with fewer than two channels
#' cannot run the CV path -- pass an explicit single-method spec there).
#' The `selected` column of `k_evidence` records which rank the K
#' arbitration ([ms_select_k()]) would pick within the evaluated grid.
#'
#' **Single-method path (M1s).** An explicit method keeps the single
#' seeded KL-NMF fit: `ms_extract(cat, 3, ms_nmf(engine = "kl", seed =
#' 42))` reproduces the M1s result across versions (hyper-parameters are
#' frozen on the spec). This is the retained form of the pre-M2 default --
#' a first-class spec, not a new variant string.
#'
#' Normalization declaration (both paths): the kernels return raw factors
#' W (channels x signatures) and H (signatures x samples). The assembly
#' layer scales each W column to sum 1 (the catalog convention for
#' signature profiles) and multiplies each H row by the same factor, so
#' the `signatures %*% exposures` reconstruction of the counts is
#' preserved up to floating-point rounding; exposures therefore carry the
#' per-sample mutation mass attributed to each signature.
#'
#' @return An [MsSignature] object with the extracted `signatures`,
#'   `exposures`, the source `catalog_summary` snapshot (A5: dimensions,
#'   channel-table hash, build -- never the catalog), the engine name, the
#'   seed and the method evidence: the pipeline path fills `stability` and
#'   `k_evidence`; the single-method path leaves them empty (M1s shape).
#'
#' @seealso [ms_nmf()] for the engine factory, [ms_select_k()] for the K
#'   arbitration over a rank grid, [ms_tally()] for the upstream catalog,
#'   [ms_signature()] for the low-level constructor.
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

# Method: MsCatalog -> MsSignature. Two paths: method = NULL runs the D16
# consensus-CV pipeline (U-M2-03); an explicit spec resolves through the
# registry into the single seeded fit (M1s, unchanged).
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

  # --- D16 default (U-M2-03): the consensus-CV extraction pipeline.
  if (is.null(method)) {
    return(.ms_extract_pipeline(catalog, k))
  }

  # --- explicit method resolution (A14): object first-class, string sugar.
  #     Unknown names fail inside match_ms_engine() with the full list of
  #     registered engines.
  spec <- match_ms_engine(method)
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
    msuiter_abort(
      "input",
      "`k` must be a positive integer.",
      i = "the rank is the number of signature columns the kernel factors",
      j = paste0("received k = ", format(k)),
      c = "pass k >= 1 (and <= min(channels, samples))",
      data = list(context = "FFI argument validation (rank k >= 1)")
    )
  }
  max_iter <- .ms_validate_count(max_iter, "max_iter")
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
      !is.finite(seed) || seed < 0 || seed != floor(seed) || seed > 2^31 - 1) {
    msuiter_abort(
      "input",
      "`seed` must be a single integer in [0, 2^31 - 1].",
      i = "each seed selects one PCG64 stream at the FFI boundary (i32 range)",
      j = paste0("`seed` received: ", msuiter_quote_trunc(seed)),
      c = "pass a single whole number in [0, 2^31 - 1]",
      data = list(context = "FFI argument validation (RNG seed)")
    )
  }
  if (!is.character(engine) || length(engine) != 1L || is.na(engine) ||
      !engine %in% c("kl", "eu")) {
    msuiter_abort(
      "input",
      '`engine` must be a single string, one of "kl" or "eu".',
      i = "the M1s kernel ships exactly two NMF variants (KL and Euclidean)",
      j = paste0("`engine` received: ", msuiter_quote_trunc(engine)),
      c = 'pass "kl" (default) or "eu"',
      data = list(context = "FFI argument validation (NMF variant switch)")
    )
  }
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(ms_extract_rust(
    t(counts), k, max_iter, as.integer(seed), engine, n_threads
  ))
}

# ---------------------------------------------------------------------------
# D16 default pipeline (U-M2-03): frozen package defaults, the FFI wrapper
# over ms_pipeline_rust, and the MsSignature assembly of the consensus-CV
# path. Phase semantics live in the Rust core (src/rust/src/pipeline.rs);
# this layer owns the display normalization, labels, evidence assembly and
# the arbitration hookup (the rules themselves live in R/kselect-select.R).
# ---------------------------------------------------------------------------

# Frozen hyper-parameters of the default path. CV budget = folds 10 /
# seeds 10 per the PI ruling (2026-09-30): an explicit, documented
# divergence from the SUITOR upstream 30 seeds; the ensemble is
# multi-initialization only (no bootstrap).
.ms_pipeline_defaults <- list(
  replicates = 8L,
  max_iter = 200L,
  seed = 1,
  k_folds = 10L,
  n_seeds = 10L
)

# Scalar gate for the pipeline hyper-parameters (FFI contract 4, first
# layer): a single whole number >= `minimum`.
.ms_pipeline_check_scalar <- function(x, name, minimum) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
    x != trunc(x) || x < minimum) {
    msuiter_abort(
      "input",
      sprintf("`%s` must be a single whole number >= %d.", name, minimum),
      i = "pipeline hyper-parameters cross the FFI as validated scalars",
      j = paste0("`", name, "` received: ", msuiter_quote_trunc(x)),
      c = sprintf("pass a single whole number >= %d for `%s`", minimum, name),
      data = list(context = "FFI argument validation (pipeline hyper-parameter)")
    )
  }
  as.integer(x)
}

# Seed gate (same domain as .ms_extract_rust: PCG64 streams are addressed
# with an i32 master seed at the boundary).
.ms_pipeline_check_seed <- function(seed) {
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
    !is.finite(seed) || seed < 0 || seed != floor(seed) || seed > 2^31 - 1) {
    msuiter_abort(
      "input",
      "`seed` must be a single integer in [0, 2^31 - 1].",
      i = "each seed selects one PCG64 stream at the FFI boundary (i32 range)",
      j = paste0("`seed` received: ", msuiter_quote_trunc(seed)),
      c = "pass a single whole number in [0, 2^31 - 1]",
      data = list(context = "FFI argument validation (RNG seed)")
    )
  }
  as.integer(seed)
}

#' Pipeline kernel wrapper over ms_pipeline_rust (U-M2-03).
#'
#' Internal wrapper: ensemble (parallel replicates) -> Hungarian consensus
#' -> per-sample NNLS refit -> SUITOR CV grid on ranks 1..k, all inside one
#' stateless Rust call. Returns the RAW consensus signatures and refit
#' exposures plus the CV/stability evidence; display normalization and
#' labels are the assembly layer's job.
#' @param counts channels x samples double matrix (no NA/NaN).
#' @param k,replicates,max_iter,seed,k_folds,n_seeds Validated scalars
#'   (`replicates >= 2` — the consensus silhouette needs two members per
#'   cluster; `k` in [1, min(m, n)] is re-checked kernel-side).
#' @param threads NULL or a single non-negative integer pool size
#'   (`.ms_resolve_threads()`); the ensemble phase honors the per-call
#'   pool, the sequential phases are bounded.
#' @return Named list: `consensus_W` (channels x k), `nnls_exposures` (k x
#'   samples), `stability_per_cluster` (k), `avg_stability`, `cv_per_rank`
#'   (ranks 1..k, NA = no finite fold), `cv_per_rank_train`,
#'   `fold_test_deviance` (k x k_folds, NA = fold had no finite seed),
#'   `argmin_rank` (0 = none), consensus bookkeeping.
#' @keywords internal
#' @noRd
.ms_pipeline_rust <- function(counts, k, replicates, max_iter, seed,
                              k_folds, n_seeds, threads = NULL) {
  counts <- .ms_validate_matrix(counts, "counts")
  k <- .ms_pipeline_check_scalar(k, "k", 1L)
  replicates <- .ms_pipeline_check_scalar(replicates, "replicates", 2L)
  max_iter <- .ms_pipeline_check_scalar(max_iter, "max_iter", 1L)
  seed <- .ms_pipeline_check_seed(seed)
  k_folds <- .ms_pipeline_check_scalar(k_folds, "k_folds", 2L)
  n_seeds <- .ms_pipeline_check_scalar(n_seeds, "n_seeds", 1L)
  n_threads <- .ms_resolve_threads(threads)
  # Layout contract (docs/ffi-surface.md, ms_pipeline_rust row): the Rust
  # kernel consumes the row-major m x n counts, so t(counts) is passed --
  # the same identity as .ms_extract_rust().
  .msffi_check(ms_pipeline_rust(
    t(counts), k, replicates, max_iter, seed, k_folds, n_seeds, n_threads
  ))
}

# The D16 default path: pipeline run at the user's rank + MsSignature
# assembly (labels, display normalization, stability/k_evidence slots).
.ms_extract_pipeline <- function(catalog, k) {
  counts <- catalog@counts
  d <- .ms_pipeline_defaults
  # SUITOR precondition: every fold must hold out at least one row per
  # column, so k_folds must not exceed the channel count. The default path
  # clamps deterministically (the effective value is recorded in the
  # result's stability slot); fewer than two channels cannot run the CV
  # path at all.
  k_folds <- min(d$k_folds, nrow(counts))
  if (k_folds < 2L) {
    msuiter_abort(
      "input",
      "the catalog has fewer than 2 channels: the consensus-CV default path cannot build cross-validation folds",
      i = "the CV phase needs k_folds >= 2 <= channels (every fold holds out at least one row per column)",
      j = sprintf("catalog has %d channels", nrow(counts)),
      c = "pass an explicit single-method spec, e.g. ms_extract(cat, k, ms_nmf())"
    )
  }
  hyper <- list(
    replicates = d$replicates,
    max_iter = d$max_iter,
    seed = d$seed,
    k_folds = k_folds,
    n_seeds = d$n_seeds
  )
  res <- .ms_pipeline_rust(
    counts = counts, k = k, replicates = hyper$replicates,
    max_iter = hyper$max_iter, seed = hyper$seed,
    k_folds = hyper$k_folds, n_seeds = hyper$n_seeds
  )
  .ms_assemble_pipeline_signature(catalog, k, res, hyper)
}

# MsSignature assembly of one pipeline result (U-M2-03). Single-row
# k_evidence: the extracted rank with its own CV-curve entry (the grid
# arbitration over a full rank grid is ms_select_k()'s job).
.ms_assemble_pipeline_signature <- function(catalog, k, res, hyper) {
  counts <- catalog@counts
  signatures <- res$consensus_W
  exposures <- res$nnls_exposures

  # --- display normalization: identical convention to the single-method
  #     path (W columns to sum 1, H rows by the same factors).
  col_sums <- colSums(signatures)
  if (any(!is.finite(col_sums)) || any(col_sums <= 0)) {
    msuiter_abort(
      "signature",
      "the fit degenerated: a signature column has no positive mass",
      i = paste(
        "consensus centroids must have strictly positive column sums for",
        "the display normalization; a degenerate column means the fit collapsed"
      ),
      j = msuiter_quote_trunc(which(!is.finite(col_sums) | col_sums <= 0)),
      c = paste(
        "the catalog looks degenerate for this rank; fall back to a",
        "single fit with ms_nmf(seed = ) or inspect the counts"
      )
    )
  }
  signatures <- sweep(signatures, 2, col_sums, `/`)
  exposures <- sweep(exposures, 1, col_sums, `*`)

  # --- labels: strictly by position (the kernel's row/column order IS the
  #     catalog's -- the FFI layout contract).
  sig_labels <- sprintf("Sig%d", seq_len(k))
  dimnames(signatures) <- list(rownames(counts), sig_labels)
  dimnames(exposures) <- list(sig_labels, catalog@samples)

  # --- evidence: one row for the extracted rank; CV columns from this
  #     call's own rank curve (1..k). The arbitration marks is_argmin /
  #     passes_veto / selected; with a single evaluated row the fallback
  #     semantics are degraded by construction (no warning here: ms_extract
  #     does not choose k -- ms_select_k() is the arbitration surface).
  ev <- .ms_k_evidence_frame(
    grid = k,
    res_by_k = stats::setNames(list(res), as.character(k)),
    full = res,
    n_cells = nrow(counts) * ncol(counts),
    k_folds = hyper$k_folds,
    cv = TRUE
  )
  ev <- .ms_k_arbitrate(ev, cv = TRUE, explicit = FALSE)

  stability <- list(
    avg_stability = res$avg_stability,
    per_signature_stability = stats::setNames(
      as.list(res$stability_per_cluster), sig_labels
    ),
    n_replicates = hyper$replicates,
    consensus_restarts = 50L,
    best_restart = res$consensus_best_restart,
    n_rounds = res$consensus_n_rounds,
    converged = res$consensus_converged,
    hyper_parameters = hyper
  )

  ms_signature(
    signatures = signatures,
    exposures = exposures,
    catalog_summary = msuiter_catalog_summary(catalog),
    engine = "nmf-pipeline",
    seed = hyper$seed,
    stability = stability,
    k_evidence = ev
  )
}
