# Shared infrastructure for the S7 class skeleton (U-M0-03):
#   * error discipline  (ARCHITECTURE.md section 3.5): every validator
#     violation raises `msuiter_error_<topic>` via rlang::abort with the
#     i/j/c three-part information payload (i = what is wrong, j = where,
#     c = how to fix). Bare stop() is banned.
#   * channel-label hashing: deterministic digest feeding the MsSignature
#     `catalog_summary` snapshot (A5: dimension + channel-table hash + build,
#     never an embedded MsCatalog).
#   * snapshot-summary builders used by later units (ms_extract, ms_fit).

# Abort with the project-wide error contract. `topic` becomes the condition
# class `msuiter_error_<topic>`; `i`, `j` and `c` are mandatory single
# strings (info / location / fix) stored on the condition as the
# `msuiter_error` payload and rendered as message bullets.
msuiter_abort <- function(topic, message, i, j, c, call = rlang::caller_call()) {
  stopifnot(
    is.character(topic), length(topic) == 1L, nzchar(topic),
    is.character(message), length(message) == 1L, nzchar(message)
  )
  parts <- list(topic = topic, i = i, j = j, c = c)
  for (nm in c("i", "j", "c")) {
    if (!is.character(parts[[nm]]) || length(parts[[nm]]) != 1L || is.na(parts[[nm]]) || !nzchar(parts[[nm]])) {
      # Programmer error, never a user-facing path; still respects the
      # no-bare-stop() discipline.
      rlang::abort(
        sprintf("msuiter_abort: bullet '%s' must be a non-empty string", nm),
        class = "msuiter_error_internal"
      )
    }
  }
  rlang::abort(
    message,
    class = paste0("msuiter_error_", topic),
    msuiter_error = parts,
    body = c(i = i, j = j, c = c),
    call = call
  )
}

# Render a truncated, quoted list of offending labels/indices for `j` bullets.
msuiter_quote_trunc <- function(x, max_n = 10L) {
  x <- as.character(x)
  if (length(x) == 0L) {
    return("(none)")
  }
  shown <- utils::head(x, max_n)
  out <- paste0("'", shown, "'", collapse = ", ")
  if (length(x) > max_n) {
    out <- paste0(out, ", ... (", length(x), " total)")
  }
  out
}

# ---------------------------------------------------------------------------
# Channel-label hashing
# ---------------------------------------------------------------------------

# Deterministic digest of a channel label vector.
#
# Implementation note: base R has no raw-vector digest, so the canonical form
# (length-prefixed UTF-8 lines) is written to a temp file and digested with
# tools::md5sum. This is deterministic across sessions and platforms, and
# cheap: validators run at the API boundary only, never in hot loops. The
# length prefix makes {"a", "b"} and {"a\nb"} collide-proof.
msuiter_hash_labels <- function(labels) {
  if (!is.character(labels) || anyNA(labels)) {
    msuiter_abort(
      "input",
      "channel labels to hash must be a character vector without NA",
      i = "the label digest is only defined for plain label vectors",
      j = paste0("received: ", class(labels)[1L], " with anyNA = ", anyNA(labels)),
      c = "pass the canonical channel labels (character, NA free)"
    )
  }
  payload <- paste0(
    paste(c(as.character(length(labels)), enc2utf8(labels)), collapse = "\n"),
    "\n"
  )
  path <- tempfile("msuiter-label-hash-")
  on.exit(unlink(path), add = TRUE)
  con <- file(path, open = "wb")
  writeBin(charToRaw(payload), con)
  close(con) # flush before digesting: md5sum must see the buffered bytes
  unname(tools::md5sum(path))
}

# ---------------------------------------------------------------------------
# Snapshot-summary builders (A5: objects reference each other only through
# small summaries: dimensions + channel-table hash + build/version)
# ---------------------------------------------------------------------------

# Snapshot summary of an MsCatalog, embedded in MsSignature@catalog_summary.
msuiter_catalog_summary <- function(catalog) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog summary can only be derived from an MsCatalog",
      i = "catalog_summary snapshots are derived from validated MsCatalog objects",
      j = paste0("received: ", class(catalog)[1L]),
      c = "build the catalog with ms_catalog() first"
    )
  }
  list(
    n_channels = length(catalog@channels$labels),
    n_samples = length(catalog@samples),
    channel_name = catalog@channels$name,
    channel_hash = catalog@channels$hash,
    build = catalog@provenance$genome
  )
}

# Snapshot summary of an MsRefDb, embedded in MsFit@reference_summary.
msuiter_refdb_summary <- function(refdb) {
  if (!S7::S7_inherits(refdb, MsRefDb)) {
    msuiter_abort(
      "input",
      "reference summary can only be derived from an MsRefDb",
      i = "reference_summary snapshots are derived from validated MsRefDb objects",
      j = paste0("received: ", class(refdb)[1L]),
      c = "build the reference database with ms_refdb() first"
    )
  }
  signature_labels <- unique(unlist(lapply(refdb@matrices, colnames), use.names = FALSE))
  list(
    version = refdb@metadata$version,
    class = refdb@metadata$class,
    build = refdb@metadata$build,
    schema_version = refdb@metadata$schema_version,
    sha256 = refdb@metadata$sha256,
    n_signatures = length(signature_labels)
  )
}

