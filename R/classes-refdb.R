# MsRefDb: the L2 versioned reference signature library.
#
# matrices: named list of signature matrices (channels x signatures), all
#   sharing the same channel labels (matched by label, element-wise);
# metadata: governance fields per ARCHITECTURE.md sections 3.2/6 -- version,
#   class, build, schema_version, sha256, license, build_independent,
#   availability. A missing build must be declared via build_independent
#   (A13: relabel, not derived).

#' MsRefDb: versioned reference signature database
#'
#' An [MsRefDb] bundles reference signature matrices with governance metadata.
#' The metadata carries `version`, `class` (e.g. `"SBS"`), `build`,
#' `schema_version`, `sha256`, `license`, `build_independent` and
#' `availability`. A `build` of NA is only legal together with
#' `build_independent = TRUE` (A13). Violations raise `msuiter_error_refdb`.
#'
#' @param matrices named list of numeric matrices (channels x signatures);
#'   all matrices must share the same channel labels.
#' @param metadata named list with the governance fields listed above.
#'
#' @export
MsRefDb <- S7::new_class(
  "MsRefDb",
  package = "msuiter",
  properties = list(
    matrices = S7::new_property(S7::class_list),
    metadata = S7::new_property(S7::class_list)
  ),
  validator = function(self) msuiter_validate_refdb(self)
)

msuiter_validate_refdb <- function(self) {
  matrices <- self@matrices
  if (!is.list(matrices) || length(matrices) == 0L) {
    msuiter_abort(
      "refdb",
      "matrices must be a non-empty named list",
      i = "an MsRefDb bundles at least one reference signature matrix",
      j = paste0("received: ", class(matrices)[1L], " of length ",
        length(matrices)),
      c = "pass the reference matrices as a named list"
    )
  }
  if (is.null(names(matrices)) || any(!nzchar(names(matrices)))) {
    msuiter_abort(
      "refdb",
      "every reference matrix must be named",
      i = "matrix names identify reference sets (e.g. PCAWG)",
      j = paste0("names: ", msuiter_quote_trunc(names(matrices))),
      c = "name every list element"
    )
  }

  channel_labels <- NULL
  for (nm in names(matrices)) {
    m <- matrices[[nm]]
    if (!is.matrix(m) || !is.numeric(m)) {
      msuiter_abort(
        "refdb",
        sprintf("reference matrix '%s' must be a numeric matrix", nm),
        i = "reference signatures are channel-space matrices",
        j = paste0("received: ", class(m)[1L]),
        c = "pass numeric matrices with full dimnames"
      )
    }
    if (is.null(rownames(m)) || is.null(colnames(m))) {
      msuiter_abort(
        "refdb",
        sprintf("reference matrix '%s' must carry rownames and colnames", nm),
        i = "labels are the only legal matching key (never position)",
        j = sprintf(
          "rownames missing: %s; colnames missing: %s",
          is.null(rownames(m)), is.null(colnames(m))
        ),
        c = "set the matrix dimnames"
      )
    }
    if (anyNA(m) || any(!is.finite(m))) {
      msuiter_abort(
        "refdb",
        sprintf("reference matrix '%s' must not contain NA or non-finite values", nm),
        i = "the FFI contract rejects NA",
        j = paste0("offending cells: ", msuiter_quote_trunc(which(is.na(m) | !is.finite(m)))),
        c = "fix the reference matrix source"
      )
    }
    if (any(m < 0)) {
      msuiter_abort(
        "refdb",
        sprintf("reference matrix '%s' must be non-negative", nm),
        i = "reference signatures are non-negative by definition",
        j = paste0("offending cells: ", msuiter_quote_trunc(which(m < 0))),
        c = "check the reference matrix source"
      )
    }
    if (is.null(channel_labels)) {
      channel_labels <- rownames(m)
    } else if (!identical(rownames(m), channel_labels)) {
      offenders <- rownames(m)[!rownames(m) %in% channel_labels]
      msuiter_abort(
        "refdb",
        "reference matrices must share the same channel labels",
        i = "channel labels are matched by label, element by element",
        j = sprintf(
          "matrix '%s' disagrees; offending labels: %s",
          nm, msuiter_quote_trunc(offenders)
        ),
        c = "project all matrices onto one common channel space"
      )
    }
  }

  metadata <- self@metadata
  required <- c("version", "class", "build", "schema_version", "sha256",
    "license", "build_independent", "availability")
  if (!is.list(metadata) || !is.character(names(metadata)) ||
    any(!nzchar(names(metadata)))) {
    msuiter_abort(
      "refdb",
      "metadata must be a named list",
      i = paste0("governance fields: ", paste(required, collapse = ", ")),
      j = paste0("received: ", class(metadata)[1L]),
      c = "provide the governance metadata"
    )
  }
  absent <- setdiff(required, names(metadata))
  if (length(absent) > 0L) {
    msuiter_abort(
      "refdb",
      "reference metadata is missing governance fields",
      i = paste0("governance fields: ", paste(required, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "record the missing field(s) in metadata"
    )
  }
  for (nm in c("version", "class", "schema_version", "license")) {
    v <- metadata[[nm]]
    if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) {
      msuiter_abort(
        "refdb",
        sprintf("metadata field '%s' must be a single non-empty string", nm),
        i = "governance fields pin the reference set identity",
        j = paste0("received: ", msuiter_quote_trunc(v)),
        c = "record the field as a single string"
      )
    }
  }
  indep <- metadata$build_independent
  if (!is.logical(indep) || length(indep) != 1L || is.na(indep)) {
    msuiter_abort(
      "refdb",
      "metadata field 'build_independent' must be a single TRUE or FALSE",
      i = "build independence is an explicit declaration (A13)",
      j = paste0("received: ", msuiter_quote_trunc(indep)),
      c = "set build_independent = TRUE only for build-agnostic sets"
    )
  }
  build <- metadata$build
  if (!is.character(build) || length(build) != 1L ||
    (!is.na(build) && !nzchar(build))) {
    msuiter_abort(
      "refdb",
      "metadata field 'build' must be a single string, or NA if build independent",
      i = "NA build is legal only together with build_independent = TRUE",
      j = paste0("received: ", msuiter_quote_trunc(build)),
      c = "record the genome build, or declare build independence"
    )
  }
  if (is.na(build) && !indep) {
    msuiter_abort(
      "refdb",
      "a missing build must be declared via build_independent = TRUE",
      i = "build-agnostic reference sets must say so explicitly (A13)",
      j = paste0("build = NA, build_independent = ", indep),
      c = "record the build, or set build_independent = TRUE"
    )
  }
  if (!is.character(metadata$sha256) || length(metadata$sha256) != 1L ||
    is.na(metadata$sha256) || !grepl("^[0-9a-f]{64}$", metadata$sha256)) {
    msuiter_abort(
      "refdb",
      "metadata field 'sha256' must be a sha256 hex digest",
      i = "the digest pins the reference content (A13 manifest)",
      j = paste0("received: ", msuiter_quote_trunc(metadata$sha256)),
      c = "record the sha256 of the reference source"
    )
  }
  avail <- metadata$availability
  if (!is.character(avail) || anyNA(avail)) {
    msuiter_abort(
      "refdb",
      "metadata field 'availability' must be a character vector without NA",
      i = "availability lists the builds with official reference sets",
      j = paste0("received: ", class(avail)[1L], " of length ", length(avail)),
      c = "list known builds, or pass character(0)"
    )
  }
  NULL
}

#' Construct an MsRefDb object
#'
#' Builds and validates an [MsRefDb] with its governance metadata.
#'
#' @inheritParams MsRefDb
#' @return An [MsRefDb] object.
#' @examples
#' m <- matrix(c(0.9, 0.1, 0.1, 0.9), 2, 2,
#'   dimnames = list(c("A[C>A]A", "C[C>A]A"), c("SBS1", "SBS5")))
#' refdb <- ms_refdb(list(m = m),
#'   metadata = list(
#'     version = "1", class = "SBS", build = "GRCh38", schema_version = "1",
#'     sha256 = paste0(rep("a", 64), collapse = ""), license = "CC0-1.0",
#'     build_independent = FALSE, availability = "GRCh38"
#'   ))
#' refdb
#' @export
ms_refdb <- function(matrices, metadata) {
  out <- MsRefDb(matrices = matrices, metadata = metadata)
  out
}

# One-line print/format: class name / class field / version / matrix count.
S7::method(format, MsRefDb) <- function(x, ...) {
  sprintf(
    "<MsRefDb> class: %s | version: %s | %d matrices",
    x@metadata$class, x@metadata$version, length(x@matrices)
  )
}

S7::method(print, MsRefDb) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
