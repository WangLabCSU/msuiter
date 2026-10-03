# refdb.R: the bundled reference signature database (U-M3a-06).
#
# v1 bundles the human COSMIC v3.6 reference matrices from the Alexandrov-lab
# BSD-2 mirror (SigProfilerSuite/SigProfilerAssignment at a pinned commit;
# NOT a cancer.sanger.ac.uk download -- docs/research/05 section 1, ADR D3):
# SBS96 and DBS78 for GRCh37 + GRCh38, ID83 for GRCh37. Everything beyond
# that scope (CN/SV/RNA-SBS, mouse/rat) belongs to the future
# ms_update_refdb() cache path (tools::R_user_dir), never to the bundle
# (ARCHITECTURE section 6, entry 2: CRAN 5MB guideline).
#
# Governance (fail-closed at every step):
#   * schema_version of the manifest is above the supported set -> structured
#     refusal (forward rejection, never a best-effort read);
#   * every shipped file's SHA-256 is re-computed over the exact bytes at
#     load time and compared against the manifest (the digests were pinned
#     by data-raw/build_refdb.R against the upstream commit);
#   * channel and signature labels must match the manifest EXACTLY (order
#     included): SBS96/DBS78 rows are in the canonical channel-registry
#     order (tests/testthat/test-channels-sync.R semantics), ID83 keeps the
#     mirror order recorded in the manifest;
#   * analysis pins the version recorded in each MsRefDb's provenance
#     metadata (precedence: explicit arguments > bundled default; the cache
#     is a later unit and explicit versions that are not bundled are
#     refused, never silently substituted).
#
# Naming note (contract deviation, reported in the unit report): the task
# contract names the bundled accessor ms_refdb(version, build), but
# ms_refdb(matrices, metadata) is ALREADY the exported MsRefDb constructor
# (R/classes-refdb.R, outside this unit's file set). The accessor therefore
# ships as ms_refdb_bundled(); semantics follow the contract otherwise.
# The bundled accessor returns a named LIST of MsRefDb objects (one per
# class/build) because the MsRefDb validator requires all matrices of one
# object to share their channel labels, which SBS96/DBS78/ID83 do not.

# Supported manifest schema versions of this package. A manifest written by
# a NEWER schema (forward-incompatible layout) is refused here -- raise the
# set only together with the reader support (never optimistically).
.MS_REFDB_SUPPORTED_SCHEMAS <- "1"

# ---------------------------------------------------------------------------
# Internal loader: read the bundle from one directory, verify integrity,
# return the manifest plus the parsed matrices. `dir` is an override seam
# for the fixture tests (doctored manifests/files); production callers use
# the bundled default.
# ---------------------------------------------------------------------------

.ms_refdb_read_matrix <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) < 2L) {
    msuiter_abort(
      "refdb",
      sprintf("reference file '%s' is degenerate (fewer than two lines)", basename(path)),
      i = "bundled reference matrices are SigProfiler TSV exports",
      j = basename(path),
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  header <- strsplit(lines[1L], "\t", fixed = TRUE)[[1L]]
  if (length(header) < 2L || header[1L] != "Type") {
    msuiter_abort(
      "refdb",
      sprintf("reference file '%s' has no 'Type' header column", basename(path)),
      i = "bundled reference matrices are SigProfiler TSV exports",
      j = basename(path),
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  sigs <- header[-1L]
  rows <- strsplit(lines[-1L], "\t", fixed = TRUE)
  if (any(lengths(rows) != length(sigs) + 1L)) {
    msuiter_abort(
      "refdb",
      sprintf("reference file '%s' is ragged (inconsistent column count)", basename(path)),
      i = "every channel row must carry one value per signature",
      j = basename(path),
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  channels <- vapply(rows, function(r) r[[1L]], character(1L))
  vals <- t(vapply(rows, function(r) as.numeric(r[-1L]), numeric(length(sigs))))
  if (anyNA(vals) || any(!is.finite(vals))) {
    msuiter_abort(
      "refdb",
      sprintf("reference file '%s' contains NA or non-finite values", basename(path)),
      i = "the MsRefDb contract rejects NA cells (the FFI does the same)",
      j = basename(path),
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  matrix(vals, nrow = length(channels), ncol = length(sigs),
    dimnames = list(channels, sigs))
}

.ms_refdb_load_bundle <- function(dir = NULL) {
  bundled <- is.null(dir)
  if (bundled) {
    dir <- system.file("reference", "refdb", package = "msuiter")
  }
  if (length(dir) != 1L || !nzchar(dir) || !dir.exists(dir)) {
    msuiter_abort(
      "refdb",
      "the bundled reference database is missing",
      i = "msuiter ships inst/reference/refdb with the package",
      j = if (bundled) "system.file(reference/refdb) resolved to nothing" else dir,
      c = "reinstall the package, or rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  manifest_path <- file.path(dir, "refdb_manifest.rds")
  if (!file.exists(manifest_path)) {
    msuiter_abort(
      "refdb",
      "the reference manifest (refdb_manifest.rds) is missing",
      i = "the manifest pins schema_version, provenance and the SHA-256 digests",
      j = dir,
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  manifest <- readRDS(manifest_path)
  if (!is.list(manifest) || !is.character(manifest$schema_version) ||
      length(manifest$schema_version) != 1L || is.na(manifest$schema_version)) {
    msuiter_abort(
      "refdb",
      "the reference manifest carries no readable schema_version",
      i = "schema_version is the forward-compatibility gate (fail-closed)",
      j = paste0("received: ", msuiter_quote_trunc(manifest$schema_version)),
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  if (!manifest$schema_version %in% .MS_REFDB_SUPPORTED_SCHEMAS) {
    msuiter_abort(
      "refdb",
      paste0(
        "reference manifest schema_version '", manifest$schema_version,
        "' is above the supported set (",
        paste(.MS_REFDB_SUPPORTED_SCHEMAS, collapse = ", "),
        ") -- refusing to read a forward-incompatible bundle"
      ),
      i = "forward rejection: analysis must never pin an unreadable reference",
      j = paste0("bundle version: ", manifest$version),
      c = "upgrade msuiter, or rebuild the bundle with a supported schema"
    )
  }

  files <- manifest$files
  if (!is.list(files) || length(files) == 0L ||
      is.null(names(files)) || any(!nzchar(names(files)))) {
    msuiter_abort(
      "refdb",
      "the reference manifest carries no file entries",
      i = "each entry pins one shipped matrix (sha256, labels, build)",
      j = dir,
      c = "rebuild the bundle with data-raw/build_refdb.R"
    )
  }
  data <- list()
  for (nm in names(files)) {
    entry <- files[[nm]]
    path <- file.path(dir, paste0(manifest$name, "_", manifest$version), nm)
    if (!file.exists(path)) {
      msuiter_abort(
        "refdb",
        sprintf("bundled reference file '%s' is missing", nm),
        i = "the manifest lists files that must ship with the package",
        j = path,
        c = "reinstall the package, or rebuild the bundle with data-raw/build_refdb.R"
      )
    }
    bytes <- readBin(path, "raw", file.info(path)$size)
    got <- .ms_fit_sha256(bytes)
    if (!identical(got, entry$sha256)) {
      msuiter_abort(
        "refdb",
        sprintf("SHA-256 mismatch for bundled reference file '%s'", nm),
        i = "the manifest digest pins the exact shipped bytes (fail-closed)",
        j = sprintf("expected %s, got %s", entry$sha256, got),
        c = "reinstall the package, or rebuild the bundle with data-raw/build_refdb.R"
      )
    }
    m <- .ms_refdb_read_matrix(path)
    if (!identical(rownames(m), entry$channels) ||
        !identical(colnames(m), entry$signatures) ||
        nrow(m) != entry$n_channels || ncol(m) != entry$n_signatures) {
      msuiter_abort(
        "refdb",
        sprintf("bundled reference file '%s' disagrees with the manifest labels", nm),
        i = "labels (order included) are the only legal matching key (never position)",
        j = sprintf(
          "%d x %d parsed, %d x %d in the manifest",
          nrow(m), ncol(m), entry$n_channels, entry$n_signatures
        ),
        c = "rebuild the bundle with data-raw/build_refdb.R"
      )
    }
    data[[nm]] <- list(entry = entry, matrix = m)
  }
  list(manifest = manifest, data = data)
}

# Object-level digest: SHA-256 over the canonical "name:digest" join of the
# object's member files (one stable summary for MsRefDb metadata$sha256 --
# the per-file digests stay in the manifest).
.ms_refdb_object_digest <- function(files) {
  payload <- paste(paste(names(files), files, sep = ":"), collapse = "\n")
  .ms_fit_sha256(charToRaw(paste0(payload, "\n")))
}

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------

#' The bundled reference signature database (COSMIC v3.6)
#'
#' Returns the reference signature matrices bundled with the package:
#' human COSMIC v3.6 SBS96 and DBS78 for GRCh37 + GRCh38, and ID83 (the
#' build-agnostic indel set, sourced from GRCh37). The data comes from the
#' Alexandrov-lab BSD-2-Clause mirror (SigProfilerAssignment at a pinned
#' commit) -- not from cancer.sanger.ac.uk; see [ms_refdb_manifest()] for
#' the full provenance and license record.
#'
#' **Governance (fail-closed).** Every call re-verifies the bundle: the
#' manifest `schema_version` is checked against the supported set (a
#' forward-incompatible bundle is refused, never read best-effort), every
#' file's SHA-256 is recomputed over the exact bytes, and channel/signature
#' labels must match the manifest exactly (order included). An explicit
#' `version` is honored only if it IS the bundled version -- anything else
#' is a structured refusal (the on-demand cache is a later unit), so an
#' analysis can never silently run against a different reference than it
#' named (precedence discipline, ARCHITECTURE section 6).
#'
#' **Naming deviation (documented).** The bundled accessor is
#' `ms_refdb_bundled()` because `ms_refdb()` is already the exported
#' [MsRefDb] constructor.
#'
#' @param version NULL (default; the bundled version) or the requested
#'   version string. Only the bundled version (`"v3.6"`) resolves;
#'   anything else is refused with the available version in the message.
#' @param build NULL (default; every build of each class) or a single
#'   genome build (`"GRCh37"` / `"GRCh38"`). A class with no official set
#'   for the requested build but declared `build_independent` (ID83) is
#'   served with a message naming the nearest official build, exactly as
#'   ARCHITECTURE section 6 prescribes.
#' @return A named list of [MsRefDb] objects, one per class/build:
#'   `SBS_GRCh37`, `SBS_GRCh38`, `DBS_GRCh37`, `DBS_GRCh38` and `ID` (the
#'   build-agnostic indel set). A list (not a single object) because one
#'   MsRefDb requires all its matrices to share channel labels. Each
#'   object's metadata carries `version` (`"v3.6"`), `class`, `build`,
#'   `schema_version` (`"1"`), `sha256` (a summary digest over the member
#'   files' manifest digests), `license` (`"BSD-2-Clause"`),
#'   `build_independent` and `availability`.
#' @seealso [ms_refdb_manifest()] for the governance record, [MsRefDb] for
#'   the container, [ms_fit()] for fitting against a dictionary.
#' @export
ms_refdb_bundled <- function(version = NULL, build = NULL) {
  bundle <- .ms_refdb_load_bundle()
  manifest <- bundle$manifest

  if (!is.null(version)) {
    if (!is.character(version) || length(version) != 1L || is.na(version) ||
        !nzchar(version)) {
      msuiter_abort(
        "refdb",
        "version must be NULL or a single non-empty string",
        i = "precedence: an explicit version is honored only when it IS bundled",
        j = paste0("received: ", msuiter_quote_trunc(version)),
        c = paste0("pass NULL for the bundled version (", manifest$version, ")")
      )
    }
    if (!identical(version, manifest$version)) {
      msuiter_abort(
        "refdb",
        sprintf("reference version '%s' is not bundled", version),
        i = paste(
          "precedence: the bundle is the only source in v1 -- an explicit",
          "version that is not bundled is refused, never substituted"
        ),
        j = sprintf("bundled: %s (cache/update path ships in a later unit)", manifest$version),
        c = "call ms_refdb_bundled() without `version` to pin the bundled database"
      )
    }
  }

  if (!is.null(build)) {
    if (!is.character(build) || length(build) != 1L || is.na(build) || !nzchar(build)) {
      msuiter_abort(
        "refdb",
        "build must be NULL or a single non-empty string",
        i = "the build selects the genome build of the returned reference sets",
        j = paste0("received: ", msuiter_quote_trunc(build)),
        c = 'pass "GRCh37" or "GRCh38", or NULL for every bundled build'
      )
    }
  }

  # Assemble one MsRefDb per (class, build); build-agnostic sets keep the
  # plain class name (e.g. "ID").
  out <- list()
  for (cls in manifest$classes) {
    hits <- Filter(function(x) identical(x$entry$class, cls), bundle$data)
    if (length(hits) == 0L) {
      next # defensive: the v1 manifest always carries SBS/DBS/ID
    }
    exact <- Filter(function(x) is.null(build) || identical(x$entry$build, build), hits)
    target <- exact
    if (length(target) == 0L) {
      independent <- Filter(function(x) isTRUE(x$entry$build_independent), hits)
      if (length(independent) == 0L) {
        message(sprintf(
          "ms_refdb_bundled: no %s reference set for build %s (official builds: %s) -- skipped",
          cls, build, paste(hits[[1L]]$entry$availability, collapse = ", ")
        ))
        next
      }
      # Honest transparency note (ARCHITECTURE section 6): serving the
      # build-independent set for a build with no official reference set.
      message(sprintf(
        "ms_refdb_bundled: no official %s reference set for build %s -- serving the declared build-independent set (nearest official build(s): %s)",
        cls, build, paste(independent[[1L]]$entry$availability, collapse = ", ")
      ))
      target <- independent
    }
    for (nm in names(target)) {
      entry <- target[[nm]]$entry
      m <- target[[nm]]$matrix
      stem <- sub("^COSMIC_v[0-9.]+_", "", nm)
      stem <- sub("\\.txt$", "", stem)
      object_name <- if (isTRUE(entry$build_independent)) cls else stem
      # metadata$build is NA exactly when the set is declared
      # build-independent (A13; the validator enforces the pairing).
      meta_build <- if (isTRUE(entry$build_independent)) NA_character_ else entry$build
      out[[object_name]] <- MsRefDb(
        matrices = stats::setNames(list(m), stem),
        metadata = list(
          version = manifest$version,
          class = cls,
          build = meta_build,
          schema_version = manifest$schema_version,
          sha256 = .ms_refdb_object_digest(stats::setNames(entry$sha256, nm)),
          license = manifest$license,
          build_independent = isTRUE(entry$build_independent),
          availability = entry$availability
        )
      )
    }
  }
  if (length(out) == 0L) {
    msuiter_abort(
      "refdb",
      sprintf("no bundled reference set resolves for build '%s'", build),
      i = "the v1 bundle covers GRCh37/GRCh38 SBS + DBS and build-independent ID",
      j = paste0("requested build: ", build),
      c = 'pass build = NULL, or "GRCh37" / "GRCh38"'
    )
  }
  out
}

#' The governance manifest of the bundled reference database
#'
#' Returns the reference governance manifest after a full integrity
#' verification (schema gate + per-file SHA-256 + label match): the bundled
#' version, schema_version, upstream provenance (repository, pinned commit
#' and tag, source URL), license (BSD-2-Clause Alexandrov-lab mirror, with
#' the documented legal-ambiguity note), citations, and per-file records
#' (class, build, build_independent, availability, sha256, size, channel
#' and signature labels).
#'
#' @return A named list (the manifest). Every field is safe to embed in a
#'   provenance record; the per-file `sha256` digests pin the exact bytes.
#' @seealso [ms_refdb_bundled()] for the resolved matrices.
#' @export
ms_refdb_manifest <- function() {
  .ms_refdb_load_bundle()$manifest
}
