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

#' Export a catalog or signature set in a file format
#'
#' Writes the channel x column matrix of an [MsCatalog] (counts) or
#' [MsSignature] (probabilities) in the requested format. The first
#' interop format is `cosmic` (the bundled COSMIC v3.6 file layout: TSV,
#' "Type" first header column, one row per channel label in canonical
#' registry order).
#'
#' @param x An [MsCatalog] or [MsSignature].
#' @param format Only `"cosmic"` in this batch (see the design memo §0 for
#'   the deferred formats).
#' @param file Output path; `NULL` returns the assembled data.frame
#'   instead of writing.
#'
#' @return The data.frame (file = NULL) or the file path, invisibly.
#'
#' @export
ms_export <- function(x, format = "cosmic", file = NULL) {
  if (!identical(format, "cosmic")) {
    msuiter_abort(
      "option",
      "format must be \"cosmic\" in this batch",
      i = "SigProfiler txt and WTSI long formats are deferred pending [V] verification",
      j = paste0("received: ", msuiter_quote_trunc(format)),
      c = "see docs/devlog/2026-10-04-M4-02-design-memo.md §0"
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
  out <- data.frame(Type = rownames(mat), stringsAsFactors = FALSE)
  for (j in seq_len(ncol(mat))) {
    out[[cols[j]]] <- mat[, j]
  }
  if (is.null(file)) {
    out
  } else {
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
#' @param format Only `"cosmic"` in this batch.
#' @param kind Only `"catalog"` in this batch: signature-set import is
#'   deferred because the MsSignature validator's exposure face cannot
#'   carry a legal zero-column matrix (colnames() is NULL at 0 columns) —
#'   an audited validator change lands first.
#' @param channel_table Optional registry table name pinning the label
#'   order (SBS96/SBS192/SBS384/SBS1536/DBS78); inferred when omitted.
#'
#' @return An [MsCatalog].
#'
#' @export
ms_import <- function(file, format = "cosmic", kind = "catalog",
                      channel_table = NULL) {
  if (!identical(format, "cosmic")) {
    msuiter_abort(
      "option",
      "format must be \"cosmic\" in this batch",
      i = "SigProfiler txt and WTSI long formats are deferred pending [V] verification",
      j = paste0("received: ", msuiter_quote_trunc(format)),
      c = "see docs/devlog/2026-10-04-M4-02-design-memo.md §0"
    )
  }
  if (!identical(kind, "catalog")) {
    msuiter_abort(
      "option",
      "kind must be \"catalog\" in this batch",
      i = "signature-set import is deferred: the MsSignature validator's exposure face cannot carry a legal zero-column matrix (colnames() is NULL at 0 columns)",
      j = paste0("received: ", msuiter_quote_trunc(kind)),
      c = "see docs/devlog/2026-10-04-M4-02-design-memo.md section 2"
    )
  }
  if (!is.character(file) || length(file) != 1L || is.na(file) || !nzchar(file) ||
      !file.exists(file)) {
    msuiter_abort(
      "input",
      "file must be a path to an existing file",
      i = "ms_import() reads a cosmic-format TSV from disk",
      j = paste0("received: ", msuiter_quote_trunc(file)),
      c = "pass the TSV path returned by ms_export()"
    )
  }
  tab <- utils::read.delim(file, sep = "\t", header = TRUE,
                           check.names = FALSE, stringsAsFactors = FALSE)
  if (ncol(tab) < 2L || !identical(names(tab)[1L], "Type")) {
    msuiter_abort(
      "input",
      "cosmic-format files need a \"Type\" first header column",
      i = "the layout anchor is the bundled COSMIC v3.6 reference file",
      j = paste0("received header: ", msuiter_quote_trunc(names(tab))),
      c = "pass a file written by ms_export(format = \"cosmic\")"
    )
  }
  labels <- tab$Type
  table_nm <- .ms_io_resolve_table(labels, channel_table = channel_table)
  mat <- as.matrix(tab[, -1L, drop = FALSE])
  rownames(mat) <- labels
  if (any(!is.finite(mat)) || any(mat < 0) || any(mat != floor(mat))) {
    msuiter_abort(
      "input",
      "catalog import needs finite non-negative whole-number counts",
      i = "a catalog is integer mutation counts",
      j = sprintf("offending entries: %d",
                  sum(!is.finite(mat) | mat < 0 | mat != floor(mat))),
      c = "signature-probability files wait for the signatures import face"
    )
  }
  samples <- colnames(mat)
  if (is.null(samples)) {
    samples <- paste0("sample", seq_len(ncol(mat)))
  }
  ms_catalog(
    counts = mat,
    channels = list(name = table_nm, labels = labels),
    samples = samples,
    provenance = list(genome = "imported", format = "cosmic", file = file)
  )
}
