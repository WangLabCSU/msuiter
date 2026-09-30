# FFI contract probes: validated R wrappers over the `msffi_*` Rust exports
# (U-M0-09; docs/ARCHITECTURE.md section 2, docs/ffi-surface.md).
#
# Layering (mirrors the future kernel wrappers):
#   Rust #[extendr] fn            -> generated passthrough (R/extendr-wrappers.R)
#   `.msffi_*` (this file)        -> argument coercion + R-side validators + error surfacing
#
# Error protocol (contracts 3/5, ARCHITECTURE section 3.5):
#   * any Rust `Err(MsError)` arrives as a condition object with class
#     `msuiter_error_rust` carrying the i/j/c payload; `.msffi_check()`
#     re-signals it with `stop()` so `tryCatch` handlers see it;
#   * the R-side validators fire FIRST (anyNA etc.) and abort through the
#     shared `msuiter_abort()` (R/classes-utils.R) with class
#     `msuiter_error_<topic>` and the i/j/c bullet payload on
#     `cnd$msuiter_error`. The ffi-specific condition fields are kept as
#     TOP-LEVEL fields via the `data=` compatibility hatch: the literal
#     `context` string (rlang reserves `c` for child conditions) and the
#     integer i/j offender coordinates of the anyNA validator, mirroring
#     the `msuiter_error_rust` shape (docs/ffi-surface.md, unified
#     2026-09-28 -- the interim `rlang::abort(context=)` form is gone).

# ---------------------------------------------------------------------------
# Thread-pool resolution (contract 6)
# ---------------------------------------------------------------------------

#' Resolve the effective per-call thread-pool size.
#'
#' Precedence: explicit `threads` argument > `msuiter.threads` option >
#' default. The default is rayon's own default (all cores), sent as `0L`
#' to the FFI; under `_R_CHECK_LIMIT_CORES_` (R CMD check --as-cran) the
#' default is capped at 2 (ARCHITECTURE section 2, contract 6).
#'
#' @param threads NULL or a single non-negative integer.
#' @return Integer(1): 0 = "rayon default" sentinel, otherwise the pool size.
#' @keywords internal
#' @noRd
.ms_resolve_threads <- function(threads = NULL) {
  value <- if (!is.null(threads)) threads else getOption("msuiter.threads")
  if (is.null(value)) {
    if (nzchar(Sys.getenv("_R_CHECK_LIMIT_CORES_", ""))) {
      return(2L)
    }
    return(0L)
  }
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      !is.finite(value) || value < 0 || value != floor(value)) {
    msuiter_abort(
      "option",
      "`msuiter.threads` must be NULL or a single non-negative integer.",
      i = "msuiter.threads sets the per-call thread-pool size (0 = rayon default)",
      j = paste0("received object of class: ", class(value)[1L]),
      c = "set the option or the threads argument to NULL or a single non-negative integer",
      data = list(context = "per-call thread-pool resolution (msuiter.threads)")
    )
  }
  as.integer(value)
}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

#' Re-signal an `msuiter_error_rust` condition surfaced by the Rust core.
#' @noRd
.msffi_check <- function(res) {
  if (inherits(res, "msuiter_error_rust")) {
    stop(res)
  }
  res
}

#' Validate a double matrix for the FFI boundary (contract 2/3, first layer).
#'
#' Coerces integer input to double (R kernels receive REALSXP matrices) and
#' rejects everything else, plus any NA/NaN, before a single byte crosses
#' the boundary.
#' @noRd
.ms_validate_matrix <- function(x, arg = "x") {
  if (!is.matrix(x)) {
    msuiter_abort(
      "input",
      sprintf("`%s` must be a matrix.", arg),
      i = "the FFI boundary only accepts matrix arguments",
      j = paste0("`", arg, "` received: ", class(x)[1L]),
      c = paste0("pass a numeric matrix in `", arg, "`"),
      data = list(context = "FFI argument validation (matrix)")
    )
  }
  if (is.integer(x)) {
    # Plain assignment statement: `storage.mode(x) <- v` modifies x in
    # place; nesting it (`x <- storage.mode(x) <- v`) would bind the RHS
    # string, not the coerced object.
    storage.mode(x) <- "double"
  }
  if (!is.double(x)) {
    msuiter_abort(
      "input",
      sprintf("`%s` must be a double (numeric) matrix.", arg),
      i = "the Rust kernels read REALSXP matrices",
      j = paste0("`", arg, "` received: ", class(x)[1L]),
      c = paste0("pass a double (numeric) matrix in `", arg, "`"),
      data = list(context = "FFI argument validation (REALSXP)")
    )
  }
  if (anyNA(x)) {
    k <- which(is.na(x))[1L]
    nrow <- nrow(x)
    i <- (k - 1L) %% nrow + 1L
    j <- (k - 1L) %/% nrow + 1L
    msuiter_abort(
      "na",
      sprintf("`%s` must not contain NA/NaN (first offender at row %d, column %d).", arg, i, j),
      i = "NA/NaN cannot cross the FFI boundary (contract 3)",
      j = sprintf("first offender in `%s`: row %d, column %d", arg, i, j),
      c = "drop or impute the offending entries before the call",
      data = list(
        i = i,
        j = j,
        context = "anyNA() validation on the R side of the FFI boundary (contract 3, first layer)"
      )
    )
  }
  x
}

#' Validate a single non-negative integer-ish scalar.
#'
#' Zero is allowed everywhere: `i`/`j` below 1 must reach the Rust bounds
#' probe so the contract-4 error path stays reachable from R.
#' @noRd
.ms_validate_count <- function(x, arg) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x != floor(x) || x < 0L) {
    msuiter_abort(
      "input",
      sprintf("`%s` must be a single non-negative integer.", arg),
      i = "FFI integer arguments must be scalar, finite, non-negative integers",
      j = paste0("`", arg, "` received: ", msuiter_quote_trunc(x)),
      c = paste0("pass a single non-negative integer in `", arg, "`"),
      data = list(context = "FFI argument validation (non-negative integer scalar)")
    )
  }
  as.integer(x)
}

# ---------------------------------------------------------------------------
# Validated probe wrappers
# ---------------------------------------------------------------------------

#' Column-major layout probe (contract 2).
#'
#' Computes the asymmetric golden positional checksum of a double matrix
#' read in column-major order. Golden round-trip: equals
#' `sum(seq_along(m) * as.numeric(m))` for any integer-valued matrix, and
#' differs from the row-major misread for any non-square matrix.
#' @keywords internal
#' @noRd
.msffi_column_major_probe <- function(x) {
  x <- .ms_validate_matrix(x, "x")
  .msffi_check(msffi_column_major_probe(x))
}

#' NA rejection probe (contract 3, second layer).
#'
#' The R validator above rejects NA/NaN first; this wrapper then reaches
#' the Rust scan, which would fail the whole call with an
#' `msuiter_error_rust` condition if an NA ever slipped past the validator.
#' @keywords internal
#' @noRd
.msffi_na_probe <- function(x) {
  x <- .ms_validate_matrix(x, "x")
  .msffi_check(msffi_na_probe(x))
}

#' Result-to-condition mapping probe (contracts 4/5).
#'
#' 1-based indices into a virtual 4x3 matrix; out-of-bounds indices come
#' back as `msuiter_error_rust` conditions with i/j/c payload, in-bounds
#' indices as the deterministic column-major offset.
#' @keywords internal
#' @noRd
.msffi_error_probe <- function(i, j) {
  i <- .ms_validate_count(i, "i")
  j <- .ms_validate_count(j, "j")
  .msffi_check(msffi_error_probe(i, j))
}

#' Interrupt mechanism probe (contract 7).
#'
#' Polls `R_CheckUserInterrupt` on the main thread at every chunk boundary
#' and runs a trivial worker unit on the per-call pool. Returns the number
#' of chunks processed. A real user interrupt during a chunk boundary
#' propagates into R natively (stateless FFI: nothing left behind).
#' @keywords internal
#' @noRd
.msffi_interrupt_probe <- function(n_chunks, threads = NULL) {
  n_chunks <- .ms_validate_count(n_chunks, "n_chunks")
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(msffi_interrupt_probe(n_chunks, n_threads))
}

#' Thread-invariance probe (contract 6).
#'
#' Returns one f64 in [0, 1) per item, each drawn from its own PCG64 stream
#' (canonical layout v1). Output depends only on `(n_items, seed)` — never
#' on the thread count. `threads` follows `.ms_resolve_threads()` when
#' NULL.
#' @keywords internal
#' @noRd
.msffi_thread_probe <- function(n_items, seed, threads = NULL) {
  n_items <- .ms_validate_count(n_items, "n_items")
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
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(msffi_thread_probe(n_items, as.integer(seed), n_threads))
}

#' Real-kernel parallel replicate driver (contracts 6/7, U-M1s-05).
#'
#' Runs `replicates` independent KL-NMF fits of `counts` (m channels x n
#' samples) on the per-call thread pool. Replicate `r` draws its seeded
#' initializer from its own PCG64 stream
#' `StreamId{replicate: r, rank: 0, fold: 0}` (canonical layout v1) and the
#' kernel stays single-threaded inside each unit; results are returned
#' ordered by replicate index. The output depends only on
#' `(counts, k, max_iter, seed, replicates)` — never on the thread count:
#' threads 1 and N give `identical()` vectors. `threads` follows
#' `.ms_resolve_threads()` when NULL.
#' @keywords internal
#' @noRd
.msffi_nmf_replicates_probe <- function(counts, k, replicates, max_iter,
                                        seed, threads = NULL) {
  counts <- .ms_validate_matrix(counts, "counts")
  k <- .ms_validate_count(k, "k")
  replicates <- .ms_validate_count(replicates, "replicates")
  max_iter <- .ms_validate_count(max_iter, "max_iter")
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
  if (replicates < 1L) {
    msuiter_abort(
      "input",
      "`replicates` must be a positive integer.",
      i = "the driver runs one independent fit per replicate",
      j = paste0("received replicates = ", format(replicates)),
      c = "pass replicates >= 1",
      data = list(context = "FFI argument validation (replicates >= 1)")
    )
  }
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
  n_threads <- .ms_resolve_threads(threads)
  .msffi_check(msffi_nmf_replicates_probe(
    counts, k, replicates, max_iter, as.integer(seed), n_threads
  ))
}

#' Build info probe (feeds [ms_sitrep()]).
#'
#' Named list with `package_version`, `rustc_version`, `target_os` and
#' `target_arch` of the compiled Rust core.
#' @keywords internal
#' @noRd
.msffi_build_info <- function() {
  .msffi_check(msffi_build_info())
}

# ---------------------------------------------------------------------------
# Catalog tally kernel (U-M1s-09): ms_tally_rust
# ---------------------------------------------------------------------------

#' Validate one tally table switch (single non-NA logical).
#' @noRd
.ms_validate_switch <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    msuiter_abort(
      "input",
      sprintf("`%s` must be a single TRUE or FALSE.", arg),
      i = "the table switches select which channel matrices the kernel counts",
      j = paste0("`", arg, "` received: ", class(x)[1L], " of length ", length(x)),
      c = paste0("pass TRUE or FALSE in `", arg, "`"),
      data = list(context = "FFI argument validation (tally table switch)")
    )
  }
  x
}

#' Catalog tally over a 2bit reference genome (U-M1s-09).
#'
#' Internal FFI wrapper over the Rust assembly core: routes records
#' (SNV / adjacent DBS / reconnected block substitution / explicit indel
#' skips, `catalog::mnv`), fetches reference contexts from a memory-mapped
#' 2bit genome (mapped and released within the call, D12) and counts the
#' enabled channel tables. `ms_tally_rust` is an FFI-internal name: the
#' user-facing API is the `ms_tally()` generic (U-M1s-11).
#'
#' Policy (M1s, documented in `docs/ffi-surface.md` and the Rust module):
#' * chromosome matching is EXACT against the 2bit index names — no `chr`
#'   prefix normalization; unmatched names come back as
#'   `skipped:unknown_chrom` ledger rows, never an error;
#' * `pos` is 1-based and integer-valued, converted to 0-based internally;
#' * `ref_`/`alt` must be uppercase ACGT: anything else is ledgered per
#'   record (`skipped:invalid_base`), never silently coerced;
#' * `strand` carries the transcription annotation for SBS192/SBS384
#'   (`T`/`U`/`B`/`N`; B/N records have no SBS192 channel and are dropped
#'   from that matrix only);
#' * a non-ACGT byte in the SBS +/-2 window or the DBS dinucleotide, a
#'   REF-vs-genome mismatch and a context window crossing a chromosome
#'   edge each skip the record into the ledger (SPMG parity);
#' * the ledger is switch-independent: context checks run even when the
#'   corresponding tables are disabled;
#' * DBS pairs are excluded from all SBS matrices (SPMG `dinuc_sub == 1`);
#' * `(chrom, sample)` partitions run in parallel on a per-call thread pool
#'   (FFI contract 6); output is bit-identical for every thread count and
#'   pinned so by tests on both sides of the FFI.
#'
#' @param genome_path Path to an (uncompressed) UCSC 2bit reference genome.
#' @param chrom,pos,ref_,alt,sample,strand Equal-length per-record columns.
#' @param want_sbs96,want_sbs192,want_sbs384,want_sbs1536,want_dbs78
#'   Table switches; disabled tables come back as `table x 0` matrices.
#' @param threads NULL or a single non-negative integer pool size; passed
#'   through `.ms_resolve_threads()` (`msuiter.threads` option precedence,
#'   `_R_CHECK_LIMIT_CORES_` cap, 0 = rayon default sentinel).
#'
#' @return Named list: `sbs96`, `sbs192`, `sbs384`, `sbs1536`, `dbs78`
#'   integer matrices (channels x samples; rows in canonical `channels.rs`
#'   order labelled from the R channel registry, columns in
#'   first-appearance order of `sample`); `ledger`, one
#'   `record TAB destination` line per input record in input order;
#'   `n_skipped`; `n_variants`.
#' @keywords internal
#' @noRd
.ms_tally_rust <- function(genome_path, chrom, pos, ref_, alt, sample, strand,
                           want_sbs96 = TRUE, want_sbs192 = FALSE,
                           want_sbs384 = FALSE, want_sbs1536 = FALSE,
                           want_dbs78 = FALSE, threads = NULL) {
  if (!is.character(genome_path) || length(genome_path) != 1L || is.na(genome_path)) {
    msuiter_abort(
      "input",
      "`genome_path` must be a single string.",
      i = "the tally kernel memory-maps one uncompressed 2bit genome per call",
      j = paste0("`genome_path` received: ", class(genome_path)[1L]),
      c = "pass a single non-NA file path to a .2bit genome",
      data = list(context = "FFI argument validation (genome path)")
    )
  }
  n <- length(chrom)
  for (nm in c("chrom", "ref_", "alt", "sample", "strand")) {
    x <- get(nm)
    if (!is.character(x) || anyNA(x)) {
      msuiter_abort(
        "input",
        sprintf("`%s` must be a character vector without NA.", nm),
        i = "the per-record tally columns cross the FFI as string vectors",
        j = sprintf("`%s` received: %s (anyNA = %s)", nm, class(x)[1L], anyNA(x)),
        c = "pass equal-length character columns without NA",
        data = list(context = "FFI argument validation (tally record columns)")
      )
    }
    if (length(x) != n) {
      msuiter_abort(
        "input",
        sprintf("`%s` has length %d, expected %d (columns must agree).", nm, length(x), n),
        i = "the per-record tally columns must be the same length",
        j = sprintf("`%s` has length %d vs %d", nm, length(x), n),
        c = "align all record columns to one entry per variant",
        data = list(context = "FFI argument validation (tally record columns)")
      )
    }
  }
  # Contract 3, first layer: pos crosses as double; NA/NaN rejected here.
  if (!is.numeric(pos) || anyNA(pos) || !all(is.finite(pos))) {
    msuiter_abort(
      "na",
      "`pos` must be a finite numeric vector without NA/NaN.",
      i = "NA/NaN cannot cross the FFI boundary (contract 3)",
      j = paste0("`pos` has ", sum(!is.finite(pos)), " NA/NaN or non-finite entries"),
      c = "drop or fix the offending positions before the call",
      data = list(
        context = "anyNA() validation on the R side of the FFI boundary (contract 3, first layer)"
      )
    )
  }
  if (any(pos < 1) || any(pos != floor(pos))) {
    bad <- which(pos < 1 | pos != floor(pos))[1L]
    msuiter_abort(
      "input",
      "`pos` must be integer-valued and 1-based.",
      i = "positions are 1-based and converted to 0-based inside the kernel",
      j = sprintf("first offender: pos = %s", format(pos[bad])),
      c = "pass 1-based integer-valued positions",
      data = list(context = "FFI argument validation (1-based variant positions)")
    )
  }
  if (!all(strand %in% c("T", "U", "B", "N"))) {
    msuiter_abort(
      "input",
      "`strand` must only contain T, U, B or N.",
      i = "the transcription annotation feeds the strand-aware SBS tables",
      j = paste0(
        "unexpected codes: ",
        msuiter_quote_trunc(unique(strand[!strand %in% c("T", "U", "B", "N")]))
      ),
      c = "annotate every record with one of T, U, B or N",
      data = list(context = "FFI argument validation (transcription strand codes)")
    )
  }
  want_sbs96 <- .ms_validate_switch(want_sbs96, "want_sbs96")
  want_sbs192 <- .ms_validate_switch(want_sbs192, "want_sbs192")
  want_sbs384 <- .ms_validate_switch(want_sbs384, "want_sbs384")
  want_sbs1536 <- .ms_validate_switch(want_sbs1536, "want_sbs1536")
  want_dbs78 <- .ms_validate_switch(want_dbs78, "want_dbs78")

  res <- .msffi_check(ms_tally_rust(
    genome_path, chrom, as.numeric(pos), ref_, alt, sample, strand,
    want_sbs96, want_sbs192, want_sbs384, want_sbs1536, want_dbs78,
    .ms_resolve_threads(threads)
  ))

  # Canonical row labels come from the R channel registry (sysdata.rda,
  # lazily loaded into the namespace) via the get(asNamespace) pattern of
  # test-channels-sync.R — the Rust side ships raw canonical-ordered
  # buffers, the labels stay R-side (single source of truth, D5).
  tables <- get("channel_tables", envir = asNamespace("msuiter"))
  tbl_of <- list(
    sbs96 = "SBS96", sbs192 = "SBS192", sbs384 = "SBS384",
    sbs1536 = "SBS1536", dbs78 = "DBS78"
  )
  samples <- unique(sample)
  for (nm in names(tbl_of)) {
    m <- res[[nm]]
    # Disabled tables are table x 0: R requires dimnames lengths to match
    # the (zero) dimensions, so columns get character(0) there.
    cols <- if (ncol(m) > 0L) samples else character(0)
    dimnames(m) <- list(tables[[tbl_of[[nm]]]]$labels, cols)
    res[[nm]] <- m
  }
  res
}
