# io-catalog.R: catalog/signature file interop, first format (U-M4-02;
# design memo docs/devlog/2026-10-04-M4-02-design-memo.md §2).
#
# COSMIC txt — the layout of the bundled upstream reference files
# (inst/reference/refdb/COSMIC_v3.6/*.txt): TSV, first header column
# "Type", one row per channel label in the CANONICAL registry order, one
# column per signature (probabilities) or sample (counts). The interop
# first rule is enforced on both faces: labels must equal the canonical
# registry order exactly — no silent reordering, no silent subsets.
#
# Deferred formats (SigProfiler txt / WTSI long) are recorded in the memo
# §0: no upstream specimen was verifiable in this batch — unverified
# layouts do not ship.

# The registry tables reachable from this face, with their R-side label
# vectors (single source of truth = the generated channel registry,
# R/sysdata.rda `channel_tables`).
.ms_io_channel_tables <- function() {
  tables <- get("channel_tables", envir = asNamespace("msuiter"))
  lapply(tables, function(tb) tb$labels)
}

# Resolve the canonical label vector for a matrix: the label set must
# equal exactly one registry table, in order. Returns the table name.
.ms_io_formats <- c("cosmic", "sigprofiler")
.ms_io_header_col <- c(cosmic = "Type", sigprofiler = "MutationType")

.ms_io_resolve_table <- function(labels, channel_table = NULL) {
  tables <- .ms_io_channel_tables()
  if (!is.null(channel_table)) {
    if (!is.character(channel_table) || length(channel_table) != 1L ||
        !channel_table %in% names(tables)) {
      msuiter_abort(
        "input",
        "channel_table must name one of the registry tables",
        i = "the table pins the canonical label order",
        j = paste0("received: ", msuiter_quote_trunc(channel_table)),
        c = paste0("use one of: ", paste(names(tables), collapse = ", "))
      )
    }
    want <- tables[[channel_table]]
    if (!identical(as.character(labels), want)) {
      bad <- which(as.character(labels) != want)[1L]
      msuiter_abort(
        "input",
        sprintf("labels do not match the %s canonical order", channel_table),
        i = "the interop contract is exact registry order, no reordering",
        j = sprintf("first mismatch at row %d: %s vs %s", bad,
                    labels[bad], want[bad]),
        c = "reorder the matrix with the registry labels before export"
      )
    }
    return(channel_table)
  }
  hit <- names(tables)[vapply(tables, function(tb) {
    identical(as.character(labels), tb)
  }, logical(1L))]
  if (length(hit) == 1L) {
    return(hit)
  }
  msuiter_abort(
    "input",
    "labels do not match any registry channel table exactly",
    i = "ms_import/ms_export accept only canonical-order registry labels",
    j = sprintf("rows: %d; first label: %s", length(labels), labels[1L]),
    c = paste0("order the matrix by one of: ", paste(names(tables), collapse = ", "))
  )
}

# sha256 of a file's exact bytes (the import provenance digest); reuses
# the fit face's FIPS 180-4 implementation.
.ms_io_file_sha256 <- function(file) {
  tryCatch({
    bytes <- readBin(file, "raw", file.size(file))
    .ms_fit_sha256(bytes)
  }, error = function(e) NULL)
}

#' Export a catalog or signature set in a file format
#'
#' Writes the channel x column matrix of an [MsCatalog] (counts) or
#' [MsSignature] (probabilities) in the requested format. The first
#' interop format is `cosmic` (the bundled COSMIC v3.6 file layout: TSV,
#' "Type" first header column, one row per channel label in canonical
#' registry order).
#'
#' @param x An [MsCatalog] or [MsSignature].
#' @param format `"cosmic"` (the bundled reference layout, first header
#'   column "Type") or `"sigprofiler"` (first header column
#'   "MutationType"; verified against upstream specimens — memo §4).
#'   WTSI long format is deferred (no verifiable upstream specimen).
#' @param file Output path; `NULL` returns the assembled data.frame
#'   instead of writing.
#'
#' @return The data.frame (file = NULL) or the file path, invisibly.
#'
#' @export
ms_export <- function(x, format = "cosmic", file = NULL) {
  if (!format %in% .ms_io_formats) {
    msuiter_abort(
      "option",
      "format must be one of the verified formats",
      i = "WTSI long format is deferred pending an upstream specimen ([V] discipline)",
      j = paste0("received: ", msuiter_quote_trunc(format),
                 "; verified: ", paste(.ms_io_formats, collapse = ", ")),
      c = "see docs/devlog/2026-10-04-M4-02-design-memo.md §2/§4"
    )
  }
  if (S7::S7_inherits(x, MsCatalog)) {
    mat <- x@counts
    cols <- x@samples
  } else if (S7::S7_inherits(x, MsSignature)) {
    mat <- x@signatures
    cols <- colnames(mat)
  } else {
    msuiter_abort(
      "input",
      "x must be an MsCatalog or an MsSignature",
      i = "the interop face exports channel x column matrices",
      j = paste0("received: ", class(x)[1L]),
      c = "pass a catalog (counts) or a signature set (probabilities)"
    )
  }
  table_nm <- .ms_io_resolve_table(rownames(mat))
  if (is.null(cols)) {
    cols <- if (S7::S7_inherits(x, MsCatalog)) x@samples else
      paste0("col", seq_len(ncol(mat)))
  }
  out <- data.frame(..hdr.. = rownames(mat), stringsAsFactors = FALSE)
  names(out)[1L] <- .ms_io_header_col[[format]]
  for (j in seq_len(ncol(mat))) {
    out[[cols[j]]] <- mat[, j]
  }
  if (is.null(file)) {
    out
  } else {
    # 17 significant digits: write.table encodes numerics through
    # as.character (15 digits), which truncated the upstream COSMIC
    # 16-digit literals at max rel err 3.98e-15 (audit P2-3b). Pre-format
    # the numeric columns explicitly, then write as characters.
    num <- vapply(out, is.numeric, logical(1L))
    out[num] <- lapply(out[num], function(v) format(v, digits = 17L,
                                                    trim = TRUE))
    utils::write.table(out, file = file, sep = "\t", quote = FALSE,
                       row.names = FALSE)
    invisible(file)
  }
}

#' Import a file into a catalog or signature set
#'
#' Reads a `cosmic`-format TSV ("Type" first header column) and returns an
#' [MsCatalog] (kind = "catalog", integer counts) or an [MsSignature]
#' (kind = "signatures"). The channel table is inferred by exact label-set
#' match against the registry, or pinned via `channel_table`.
#'
#' @param file Input path.
#' @param format `"cosmic"` or `"sigprofiler"` (see [ms_export()]).
#' @param kind `"catalog"` (integer counts) or `"signatures"`
#'   (probabilities; the zero-column exposure face, validator-revised
#'   U-M4-02).
#' @param channel_table Optional registry table name pinning the label
#'   order (SBS96/SBS192/SBS384/SBS1536/DBS78); inferred when omitted.
#'
#' @return An [MsCatalog] or an [MsSignature].
#'
#' @export
ms_import <- function(file, format = "cosmic",
                      kind = c("catalog", "signatures"),
                      channel_table = NULL) {
  if (!format %in% .ms_io_formats) {
    msuiter_abort(
      "option",
      "format must be one of the verified formats",
      i = "WTSI long format is deferred pending an upstream specimen ([V] discipline)",
      j = paste0("received: ", msuiter_quote_trunc(format),
                 "; verified: ", paste(.ms_io_formats, collapse = ", ")),
      c = "see docs/devlog/2026-10-04-M4-02-design-memo.md §2/§4"
    )
  }
  kind <- match.arg(kind)
  if (!is.character(file) || length(file) != 1L || is.na(file) || !nzchar(file) ||
      !file.exists(file)) {
    msuiter_abort(
      "input",
      "file must be a path to an existing file",
      i = "ms_import() reads a catalog/signature TSV from disk",
      j = paste0("received: ", msuiter_quote_trunc(file)),
      c = "pass the TSV path returned by ms_export()"
    )
  }
  tab <- utils::read.delim(file, sep = "\t", header = TRUE,
                           check.names = FALSE, stringsAsFactors = FALSE)
  want_hdr <- .ms_io_header_col[[format]]
  if (ncol(tab) < 2L || !identical(names(tab)[1L], want_hdr)) {
    msuiter_abort(
      "input",
      sprintf("%s-format files need a \"%s\" first header column", format, want_hdr),
      i = if (format == "cosmic") "the layout anchor is the bundled COSMIC v3.6 reference file"
          else "the layout anchor is the pinned SigProfilerAssignment specimen (tests fixture)",
      j = paste0("received header: ", msuiter_quote_trunc(names(tab))),
      c = paste0("pass a file written by ms_export(format = \"", format, "\")")
    )
  }
  labels <- tab[[1L]]
  table_nm <- .ms_io_resolve_table(labels, channel_table = channel_table)
  mat <- as.matrix(tab[, -1L, drop = FALSE])
  rownames(mat) <- labels
  if (kind == "catalog") {
    if (any(!is.finite(mat)) || any(mat < 0) || any(mat != floor(mat))) {
      msuiter_abort(
        "input",
        "catalog import needs finite non-negative whole-number counts",
        i = "a catalog is integer mutation counts",
        j = sprintf("offending entries: %d",
                    sum(!is.finite(mat) | mat < 0 | mat != floor(mat))),
        c = "import probabilities with kind = \"signatures\""
      )
    }
    samples <- colnames(mat)
    if (is.null(samples)) {
      samples <- paste0("sample", seq_len(ncol(mat)))
    }
    return(ms_catalog(
      counts = mat,
      channels = list(name = table_nm, labels = labels),
      samples = samples,
      provenance = list(genome = "imported", format = format, file = file)
    ))
  }
  # signatures: the probability face. The legal empty exposure (k x 0,
  # rownames = signature labels) rides along; the catalog summary carries
  # the import provenance (memo §2): file path + the sha256 of the exact
  # file bytes, in the declared build field alongside the label-set hash.
  file_hash <- .ms_io_file_sha256(file)
  sig_cols <- colnames(mat)
  if (is.null(sig_cols)) {
    sig_cols <- paste0("signature", seq_len(ncol(mat)))
  }
  colnames(mat) <- sig_cols
  exposures <- matrix(0, nrow = ncol(mat), ncol = 0L,
    dimnames = list(sig_cols, character(0L)))
  ms_signature(
    signatures = mat,
    exposures = exposures,
    stability = list(),
    k_evidence = data.frame(k = integer(0L), cv = numeric(0L)),
    engine = "imported",
    seed = 0,
    catalog_summary = list(
      n_channels = nrow(mat), n_samples = 0L, channel_name = table_nm,
      channel_hash = msuiter_hash_labels(as.character(labels)),
      build = if (is.null(file_hash)) "imported" else
        paste0("imported:sha256=", file_hash)
    )
  )
}
