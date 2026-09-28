# MsCatalog: the L2 tally container.
#
# counts: channels x samples numeric matrix, rownames = channel labels;
# channels: channel-registry snapshot (name + labels + computed hash) --
#   a small snapshot of the registry, never the full registry object;
# samples: sample ids (identities, matched by label);
# provenance: named list carrying at least the genome build.

#' MsCatalog: channel-count matrix with a channel-registry snapshot
#'
#' An [MsCatalog] holds a channels x samples count matrix, a snapshot of the
#' channel registry (canonical labels + deterministic hash), the sample ids
#' and provenance. Counts are matched to channels strictly by label: the
#' rownames of `counts` must be identical, element by element, to the
#' registry labels.
#'
#' @param counts numeric matrix (channels x samples) with rownames equal to
#'   the channel labels and colnames equal to `samples`.
#' @param channels channel-registry snapshot: a named list with `name`
#'   (table id, e.g. `"SBS96"`) and `labels` (canonical labels). A `hash`
#'   element is computed automatically and must not be forged.
#' @param samples character vector of sample ids.
#' @param provenance named list; must carry `genome` (the build label).
#'
#' @export
MsCatalog <- S7::new_class(
  "MsCatalog",
  package = "msuiter",
  properties = list(
    counts = S7::new_property(S7::class_any),
    channels = S7::new_property(S7::class_list),
    samples = S7::new_property(S7::class_character),
    provenance = S7::new_property(S7::class_list)
  ),
  validator = function(self) msuiter_validate_catalog(self)
)

msuiter_validate_catalog <- function(self) {
  counts <- self@counts

  if (!is.matrix(counts) || !is.numeric(counts)) {
    msuiter_abort(
      "catalog",
      "counts must be a numeric matrix (channels x samples)",
      i = "MsCatalog stores one count per channel and sample",
      j = paste0("received: ", class(counts)[1L]),
      c = "tally variants with ms_tally() to obtain a count matrix"
    )
  }

  row_lab <- rownames(counts)
  col_lab <- colnames(counts)
  if (is.null(row_lab) || is.null(col_lab)) {
    msuiter_abort(
      "catalog",
      "counts must carry both channel labels (rownames) and sample labels (colnames)",
      i = "labels are the only legal matching key (never position)",
      j = paste0(
        "rownames missing: ", is.null(row_lab),
        "; colnames missing: ", is.null(col_lab)
      ),
      c = "name the matrix dimensions before constructing MsCatalog"
    )
  }

  dup_rows <- row_lab[duplicated(row_lab)]
  dup_cols <- col_lab[duplicated(col_lab)]
  if (length(dup_rows) > 0L || length(dup_cols) > 0L) {
    msuiter_abort(
      "catalog",
      "channel and sample labels must be unique",
      i = "duplicated labels make label matching ambiguous",
      j = paste0(
        "duplicated channel labels: ", msuiter_quote_trunc(unique(dup_rows)),
        "; duplicated sample labels: ", msuiter_quote_trunc(unique(dup_cols))
      ),
      c = "de-duplicate or rename labels"
    )
  }

  if (anyNA(counts) || any(!is.finite(counts))) {
    msuiter_abort(
      "catalog",
      "counts must not contain NA or non-finite values",
      i = "the FFI contract rejects NA; the catalog layer adds no pseudo-counts",
      j = paste0("offending cells: ", msuiter_quote_trunc(which(is.na(counts) | !is.finite(counts)))),
      c = "fix the upstream tally output"
    )
  }

  if (any(counts < 0)) {
    msuiter_abort(
      "catalog",
      "counts must be non-negative",
      i = "negative mutation counts are impossible",
      j = paste0("offending cells: ", msuiter_quote_trunc(which(counts < 0))),
      c = "check the tally pipeline for subtraction errors"
    )
  }

  # Channel-registry snapshot structure: exactly name + labels + hash.
  channels <- self@channels
  if (!is.list(channels) || !setequal(names(channels), c("name", "labels", "hash"))) {
    msuiter_abort(
      "catalog",
      "the channel snapshot must be a list with fields name, labels, hash",
      i = "the snapshot keeps the registry's canonical labels and their digest",
      j = paste0("received fields: ", msuiter_quote_trunc(names(channels))),
      c = "construct the catalog through ms_catalog(), which slices the snapshot"
    )
  }
  name1 <- channels$name
  if (!is.character(name1) || length(name1) != 1L || is.na(name1) || !nzchar(name1)) {
    msuiter_abort(
      "catalog",
      "the channel snapshot field 'name' must be a single non-empty string",
      i = "the table name identifies the channel set (e.g. SBS96)",
      j = paste0("received: ", msuiter_quote_trunc(name1)),
      c = 'pass the registry table name, e.g. name = "SBS96"'
    )
  }
  labels <- channels$labels
  if (!is.character(labels) || anyNA(labels) || any(!nzchar(labels))) {
    msuiter_abort(
      "catalog",
      "channel labels in the snapshot must be a character vector without NA",
      i = "channel labels are canonical identities",
      j = paste0("received: ", class(labels)[1L], " of length ",
        length(labels), " with anyNA = ", anyNA(labels)),
      c = "pass the canonical labels from the channel registry"
    )
  }
  if (anyDuplicated(labels) != 0L) {
    msuiter_abort(
      "catalog",
      "channel labels in the snapshot must be unique",
      i = "duplicated channel labels are not canonical order",
      j = paste0("duplicated: ", msuiter_quote_trunc(unique(labels[duplicated(labels)]))),
      c = "use the canonical registry ordering"
    )
  }

  # Dimensions must agree, then labels must agree element by element.
  if (nrow(counts) != length(labels) || ncol(counts) != length(self@samples)) {
    msuiter_abort(
      "catalog",
      "counts dimensions disagree with the registry snapshot or the samples",
      i = "counts is channels x samples",
      j = sprintf(
        "nrow = %d vs %d labels; ncol = %d vs %d samples",
        nrow(counts), length(labels), ncol(counts), length(self@samples)
      ),
      c = "align the count matrix with the registry labels and sample ids"
    )
  }
  if (!identical(row_lab, labels)) {
    offenders <- row_lab[row_lab != labels]
    msuiter_abort(
      "catalog",
      "channel labels of counts do not match the registry snapshot",
      i = "matching is by label, element by element, never by position",
      j = paste0("first offending labels: ", msuiter_quote_trunc(offenders, 5L)),
      c = "reorder or rename counts rows to the canonical registry labels"
    )
  }
  if (!identical(col_lab, self@samples)) {
    offenders <- col_lab[col_lab != self@samples]
    msuiter_abort(
      "catalog",
      "sample labels of counts do not match the samples property",
      i = "matching is by label, element by element, never by position",
      j = paste0("first offending labels: ", msuiter_quote_trunc(offenders, 5L)),
      c = "align colnames(counts) with the samples vector"
    )
  }

  # The stored digest must be the true digest of the stored labels.
  hash <- channels$hash
  if (!is.character(hash) || length(hash) != 1L || is.na(hash) ||
    !grepl("^[0-9a-f]{32}$", hash)) {
    msuiter_abort(
      "catalog",
      "the channel snapshot field 'hash' must be an md5 hex digest",
      i = "the digest pins the channel table inside snapshot summaries (A5)",
      j = paste0("received: ", msuiter_quote_trunc(hash)),
      c = "let ms_catalog() compute the hash; do not set it by hand"
    )
  }
  if (!identical(hash, msuiter_hash_labels(labels))) {
    msuiter_abort(
      "catalog",
      "the stored channel hash does not match the stored labels",
      i = "snapshot hashes must be derived, not asserted",
      j = paste0("stored: ", hash),
      c = "rebuild the catalog with ms_catalog()"
    )
  }

  samples <- self@samples
  if (!all(nzchar(samples)) || anyNA(samples)) {
    msuiter_abort(
      "catalog",
      "sample labels must be non-empty strings without NA",
      i = "sample ids are identities matched by label",
      j = paste0("offending labels: ",
        msuiter_quote_trunc(samples[!nzchar(samples) | is.na(samples)])),
      c = "provide one non-empty id per sample"
    )
  }

  provenance <- self@provenance
  if (!is.list(provenance) || !is.character(names(provenance)) ||
    any(!nzchar(names(provenance)))) {
    msuiter_abort(
      "catalog",
      "catalog provenance must be a named list",
      i = "provenance carries the genome build and tally context",
      j = paste0("received: ", class(provenance)[1L]),
      c = "provide at least genome = \"<build>\""
    )
  }
  genome <- provenance$genome
  if (!is.character(genome) || length(genome) != 1L || is.na(genome) || !nzchar(genome)) {
    msuiter_abort(
      "catalog",
      "catalog provenance must carry the genome build as 'genome'",
      i = "the build is required to query reference signatures",
      j = paste0("received: ", msuiter_quote_trunc(genome)),
      c = 'record the build, e.g. provenance = list(genome = "GRCh38")'
    )
  }
  NULL
}

#' Construct an MsCatalog object
#'
#' Builds and validates an [MsCatalog]. The channel-snapshot hash is computed
#' from the labels; violations raise errors of class `msuiter_error_catalog`.
#'
#' @inheritParams MsCatalog
#' @return An [MsCatalog] object.
#' @examples
#' labels <- paste0("CH", 1:4)
#' counts <- matrix(1:8, 4, 2, dimnames = list(labels, c("S1", "S2")))
#' cat1 <- ms_catalog(counts, list(name = "SYN4", labels = labels),
#'   c("S1", "S2"), provenance = list(genome = "GRCh38"))
#' cat1
#' @export
ms_catalog <- function(counts, channels, samples, provenance) {
  # The snapshot stores exactly name + labels + derived hash; anything else
  # attached to the registry table (decomposition metadata, ...) stays out.
  labels <- channels$labels
  if (is.null(labels)) {
    labels <- character(0)
  }
  snapshot <- list(
    name = channels$name,
    labels = as.character(labels),
    hash = msuiter_hash_labels(as.character(labels))
  )
  out <- MsCatalog(
    counts = counts, channels = snapshot, samples = samples,
    provenance = provenance
  )
  out
}

# One-line print/format: class name / table id / dimensions.
S7::method(format, MsCatalog) <- function(x, ...) {
  sprintf(
    "<MsCatalog> %s: %d channels x %d samples",
    x@channels$name, nrow(x@counts), ncol(x@counts)
  )
}

S7::method(print, MsCatalog) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
