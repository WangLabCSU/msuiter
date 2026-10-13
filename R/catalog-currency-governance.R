# catalog-currency-governance.R: the governance core of the P5
# catalog-currency instrument (see R/catalog-currency.R for the mission
# header). Shared constants, boundary validators, the SHA-256 discipline
# (the same .ms_fit_sha256 the refdb builder/loader use), the fail-closed
# committed-registry gate, and the shipped-refdb cross-check. Collated
# before the other catalog-currency parts; every .ms_cc_* helper lives in
# the catalog-currency-* files.
# ---------------------------------------------------------------------------
# Constants (single sources of truth for names and formats).
# ---------------------------------------------------------------------------

.MS_CC_SCHEMA <- "1"
.MS_CC_VERDICTS <- c("ok", "behind", "drift", "corrupt", "no-cache", "inconsistent")
.MS_CC_DOC_KEYS <- c("reference_data", "availability_data")
.MS_CC_DOC_SCRIPT_ID <- c(reference_data = "reference-data",
                          availability_data = "availability-data")
.MS_CC_DOC_FILE <- c(reference_data = "reference_data.json",
                     availability_data = "availability_data.json")
.MS_CC_SOURCES_DIR <- "sources"
.MS_CC_RECORD_FILE <- "record.rds"
.MS_CC_CANDIDATE_FILE <- "candidate_registry.rds"
.MS_CC_RECORD_KIND <- "catalog-currency-record"
.MS_CC_REGISTRY_KIND <- "catalog-currency-registry"
.MS_CC_VERSION_RE <- "^[0-9]+(\\.[0-9]+){0,2}$"
.MS_CC_SHA256_RE <- "^[0-9a-f]{64}$"
.MS_CC_COMMIT_RE <- "^[0-9a-f]{40,64}$"
.MS_CC_MAX_SOURCE_BYTES <- 5e7 # defensive cap on any single source document
.MS_CC_SCRIPT_CLOSE <- "</script>" # terminates a JSON script carrier

# ---------------------------------------------------------------------------
# Boundary validators (topic: msuiter_error_catalog_currency; the house
# i/j/c bullet contract via msuiter_abort).
# ---------------------------------------------------------------------------

.ms_cc_abort <- function(message, i, j, c, call = rlang::caller_call()) {
  msuiter_abort("catalog_currency", message, i = i, j = j, c = c, call = call)
}

.ms_cc_arg_string <- function(x, name, allow_null = FALSE, call = rlang::caller_call()) {
  if (is.null(x) && allow_null) {
    return(NULL)
  }
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    .ms_cc_abort(
      sprintf("`%s` must be a single non-empty string%s", name,
              if (allow_null) " or NULL" else ""),
      i = sprintf("`%s` names one path or label and is validated at the boundary", name),
      j = sprintf("received: %s", msuiter_quote_trunc(x)),
      c = sprintf("pass one non-empty string to `%s`", name),
      call = call
    )
  }
  x
}

.ms_cc_arg_flag <- function(x, name, call = rlang::caller_call()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    .ms_cc_abort(
      sprintf("`%s` must be TRUE or FALSE", name),
      i = sprintf("`%s` selects one behavior, not a collection", name),
      j = sprintf("received: %s", msuiter_quote_trunc(x)),
      c = sprintf("pass TRUE or FALSE to `%s`", name),
      call = call
    )
  }
  x
}

.ms_cc_arg_dir <- function(x, name, call = rlang::caller_call()) {
  x <- .ms_cc_arg_string(x, name, call = call)
  normalizePath(x, mustWork = FALSE)
}

.ms_cc_arg_existing_path <- function(x, name, call = rlang::caller_call()) {
  if (is.null(x)) {
    return(NULL)
  }
  x <- .ms_cc_arg_string(x, name, call = call)
  abs <- normalizePath(x, mustWork = FALSE)
  if (!file.exists(abs)) {
    .ms_cc_abort(
      sprintf("the `%s` path does not exist", name),
      i = sprintf("`%s` is an injected-source override: one downloads-page file or a split document directory", name),
      j = abs,
      c = "point `source` at an existing file or directory, or pass NULL for the official-site fetch",
      call = call
    )
  }
  abs
}

.ms_cc_check_version <- function(v, what, call = rlang::caller_call()) {
  if (!is.character(v) || length(v) != 1L || is.na(v) || !grepl(.MS_CC_VERSION_RE, v)) {
    .ms_cc_abort(
      sprintf("%s is not a COSMIC release label", what),
      i = "release labels are dot-separated numbers, e.g. \"3.6\"",
      j = sprintf("received: %s", msuiter_quote_trunc(v)),
      c = "correct the registry or the source document carrying the label",
      call = call
    )
  }
  v
}

.ms_cc_version_key <- function(v) {
  parts <- strsplit(v, ".", fixed = TRUE)[[1L]]
  key <- rep(0, 3L)
  key[seq_along(parts)] <- as.numeric(parts)
  key
}

# -1 / 0 / 1 comparison of two validated release labels.
.ms_cc_version_cmp <- function(a, b) {
  ka <- .ms_cc_version_key(a)
  kb <- .ms_cc_version_key(b)
  diff <- ka - kb
  hit <- which(diff != 0)[1L]
  if (is.na(hit)) 0L else if (diff[hit] > 0) 1L else -1L
}

.ms_cc_latest_version <- function(versions) {
  if (!length(versions)) {
    .ms_cc_abort(
      "a release list was empty",
      i = "the official reference document must name at least one human_cancer release",
      j = "(empty vector)",
      c = "re-run ms_catalog_currency_update() against a source that carries the reference block"
    )
  }
  for (v in versions) .ms_cc_check_version(v, "a release label")
  best <- versions[1L]
  for (v in versions[-1L]) {
    if (.ms_cc_version_cmp(v, best) > 0L) best <- v
  }
  best
}

# ---------------------------------------------------------------------------
# SHA-256: the SAME implementation the refdb builder/loader use (R/fit.R),
# so digests computed here are comparable with every other governed digest
# in the project. Byte law: a document's digest is taken over its EXACT
# payload bytes, and the cache stores EXACTLY those bytes.
# ---------------------------------------------------------------------------

# SHA-256 over exact bytes. The canonical project implementation is the
# pure-R .ms_fit_sha256 (R/fit.R), shared with the refdb builder/loader so
# every governed digest in msuiter is the same function. That kernel is a
# faithful but interpreted loop; when the `digest` package is available (it
# is an Imports dependency) we delegate to its identical SHA-256 (verified
# equal to the system `shasum` and to .ms_fit_sha256), reserving the pure-R
# path as the fallback so the result is byte-for-byte the same either way.
.ms_cc_sha256_raw <- function(raw_bytes) {
  if (requireNamespace("digest", quietly = TRUE)) {
    ns <- asNamespace("digest")
    return(ns$digest(raw_bytes, algo = "sha256", serialize = FALSE))
  }
  .ms_fit_sha256(raw_bytes)
}

.ms_cc_sha256_text <- function(text) {
  .ms_cc_sha256_raw(charToRaw(text))
}

.ms_cc_sha256_file <- function(path) {
  size <- file.info(path)$size
  if (is.na(size) || size > .MS_CC_MAX_SOURCE_BYTES) {
    .ms_cc_abort(
      "a governed source document is missing or unreasonably large",
      i = sprintf("source documents are capped at %d bytes", as.integer(.MS_CC_MAX_SOURCE_BYTES)),
      j = path,
      c = "re-run ms_catalog_currency_update() to re-derive the cache"
    )
  }
  .ms_cc_sha256_raw(readBin(path, "raw", size))
}

# ---------------------------------------------------------------------------
# The committed registry: read + fail-closed schema gate (the refdb loader
# pattern).
# ---------------------------------------------------------------------------

.ms_cc_bundled_registry <- function() {
  system.file("catalog-currency", "catalog_registry.rds", package = "msuiter")
}

.ms_cc_registry_field <- function(x, name, what, regex = NULL) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x) ||
      (!is.null(regex) && !grepl(regex, x))) {
    .ms_cc_abort(
      sprintf("the registry field '%s' is malformed", name),
      i = sprintf("the registry pins %s", what),
      j = sprintf("received: %s", msuiter_quote_trunc(x)),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R (never hand-edit digests)",
      call = rlang::caller_call(2L)
    )
  }
  x
}

.ms_cc_validate_registry <- function(reg) {
  if (!is.list(reg)) {
    .ms_cc_abort(
      "the catalog-currency registry is not a list",
      i = "the sidecar is a saved governance record (readRDS)",
      j = sprintf("received: %s", class(reg)[1L]),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  if (!is.character(reg$schema_version) || length(reg$schema_version) != 1L ||
      is.na(reg$schema_version)) {
    .ms_cc_abort(
      "the catalog-currency registry carries no readable schema_version",
      i = "schema_version is the forward-compatibility gate (fail-closed)",
      j = sprintf("received: %s", msuiter_quote_trunc(reg$schema_version)),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  if (!identical(reg$schema_version, .MS_CC_SCHEMA)) {
    .ms_cc_abort(
      sprintf("catalog-currency registry schema_version '%s' is outside the supported set ('%s') -- refusing to read a forward-incompatible sidecar",
              reg$schema_version, .MS_CC_SCHEMA),
      i = "forward rejection: analysis must never reason over a registry it cannot fully validate",
      j = sprintf("kind: %s", msuiter_quote_trunc(reg$kind)),
      c = "upgrade msuiter, or rebuild the sidecar with a supported schema"
    )
  }
  if (!identical(reg$kind, .MS_CC_REGISTRY_KIND)) {
    .ms_cc_abort(
      "the sidecar at this path is not a catalog-currency registry",
      i = sprintf("the registry must carry kind '%s'", .MS_CC_REGISTRY_KIND),
      j = sprintf("kind received: %s", msuiter_quote_trunc(reg$kind)),
      c = "point `registry` at catalog_registry.rds (the committed digest sidecar)"
    )
  }
  .ms_cc_registry_field(reg$package, "package", "the owning package ('msuiter')")
  if (!identical(reg$package, "msuiter")) {
    .ms_cc_abort(
      sprintf("the registry belongs to package '%s', not msuiter", reg$package),
      i = "a sidecar from another package is a wiring mistake, never a fallback",
      j = reg$package,
      c = "restore the committed msuiter sidecar"
    )
  }
  .ms_cc_check_version(reg$pinned_release, "the registry's pinned_release")
  .ms_cc_registry_field(reg$mirror$repo, "mirror$repo", "the BSD-2 mirror repository")
  .ms_cc_registry_field(reg$mirror$commit, "mirror$commit", "the pinned mirror commit (hex)",
                        regex = .MS_CC_COMMIT_RE)
  .ms_cc_registry_field(reg$mirror$license, "mirror$license", "the mirror license label")
  .ms_cc_registry_field(reg$refdb$version, "refdb$version", "the shipped refdb version label")
  if (!is.character(reg$refdb$governed_files) || !length(reg$refdb$governed_files) ||
      anyNA(reg$refdb$governed_files) || !all(nzchar(reg$refdb$governed_files))) {
    .ms_cc_abort(
      "the registry's refdb$governed_files is malformed",
      i = "it names the refdb manifest entries the snapshot agreement is checked against",
      j = sprintf("received: %s", msuiter_quote_trunc(reg$refdb$governed_files)),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  if (!is.character(reg$official$page_url) || length(reg$official$page_url) != 1L ||
      !grepl("^https://", reg$official$page_url) || is.na(reg$official$page_url)) {
    .ms_cc_abort(
      "the registry's official page URL is malformed",
      i = "the canonical downloads page must be reached over https",
      j = sprintf("received: %s", msuiter_quote_trunc(reg$official$page_url)),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  if (!is.list(reg$official$documents) ||
      !setequal(names(reg$official$documents), .MS_CC_DOC_KEYS)) {
    .ms_cc_abort(
      "the registry's official documents block is malformed",
      i = sprintf("it must carry exactly the documents %s",
                  paste0("'", .MS_CC_DOC_KEYS, "'", collapse = ", ")),
      j = sprintf("received: %s", msuiter_quote_trunc(names(reg$official$documents))),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  for (k in .MS_CC_DOC_KEYS) {
    d <- reg$official$documents[[k]]
    .ms_cc_registry_field(d$url, sprintf("official$documents$%s$url", k),
                          "the canonical document location (https)")
    if (!grepl("^https://", d$url)) {
      .ms_cc_abort(
        sprintf("official$documents$%s$url is not an https URL", k),
        i = "source documents are fetched over https only",
        j = d$url,
        c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
      )
    }
    .ms_cc_registry_field(d$script_id, sprintf("official$documents$%s$script_id", k),
                          "the structural carrier the payload sits in")
    if (!identical(d$script_id, .MS_CC_DOC_SCRIPT_ID[[k]])) {
      .ms_cc_abort(
        sprintf("official$documents$%s$script_id disagrees with the carrier contract", k),
        i = sprintf("the canonical carrier for '%s' is <script id=\"%s\">",
                    k, .MS_CC_DOC_SCRIPT_ID[[k]]),
        j = d$script_id,
        c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
      )
    }
    .ms_cc_registry_field(d$sha256, sprintf("official$documents$%s$sha256", k),
                          "the SHA-256 digests of the measured document bytes",
                          regex = .MS_CC_SHA256_RE)
    if (!is.numeric(d$bytes) || length(d$bytes) != 1L || is.na(d$bytes) ||
        d$bytes <= 0 || d$bytes > .MS_CC_MAX_SOURCE_BYTES) {
      .ms_cc_abort(
        sprintf("official$documents$%s$bytes is malformed", k),
        i = "the sidecar records the measured size of the canonical payload",
        j = sprintf("received: %s", msuiter_quote_trunc(d$bytes)),
        c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
      )
    }
  }
  if (!is.character(reg$official$releases) || !length(reg$official$releases) ||
      anyNA(reg$official$releases)) {
    .ms_cc_abort(
      "the registry's official release list is malformed",
      i = "it records the available release labels from the measured source document",
      j = sprintf("received: %s", msuiter_quote_trunc(reg$official$releases)),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  for (v in reg$official$releases) .ms_cc_check_version(v, "an available release label")
  .ms_cc_check_version(reg$official$latest_release, "the registry's latest_release")
  .ms_cc_check_version(reg$official$structure_release, "the registry's structure_release")
  if (!is.list(reg$official$structure) || !length(reg$official$structure)) {
    .ms_cc_abort(
      "the registry's structural (shape) facts are missing",
      i = "shape facts describe the class/build counts of the structure_release",
      j = "(empty structure)",
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  .ms_cc_validate_structure(reg$official$structure, "registry official$structure")
  if (!is.list(reg$matrix_bytes) || !identical(reg$matrix_bytes$status, "UNMEASURED") ||
      !is.null(reg$matrix_bytes$sha256) ||
      !is.character(reg$matrix_bytes$policy) || length(reg$matrix_bytes$policy) != 1L ||
      !nzchar(reg$matrix_bytes$policy)) {
    .ms_cc_abort(
      "the registry's matrix-bytes leg is not recorded as UNMEASURED",
      i = "the official COSMIC matrix downloads are login-gated; recording a fabricated digest there is banned (D3 + zero-fabrication law)",
      j = sprintf("status: %s", msuiter_quote_trunc(reg$matrix_bytes$status)),
      c = "rebuild the sidecar with data-raw/build_catalog_registry.R"
    )
  }
  reg
}

# Structural shape validation: class -> build -> one bounded profile_count.
# Only SHAPES are described here -- never per-signature numeric content.
.ms_cc_validate_structure <- function(s, what) {
  if (!is.list(s) || is.null(names(s)) || !all(nzchar(names(s)))) {
    .ms_cc_abort(
      sprintf("%s must be a named list (variant class -> build -> count)", what),
      i = "shape facts name the class/build cells the official release publishes",
      j = sprintf("received: %s", msuiter_quote_trunc(names(s))),
      c = "re-derive the record with ms_catalog_currency_update()"
    )
  }
  for (cl in names(s)) {
    cell <- s[[cl]]
    if (!is.list(cell) || is.null(names(cell)) || !all(nzchar(names(cell))) ||
        !length(cell)) {
      .ms_cc_abort(
        sprintf("%s$%s must be a non-empty named build->count list", what, cl),
        i = "shape facts name the genome builds the class publishes for the release",
        j = sprintf("received: %s", msuiter_quote_trunc(names(cell))),
        c = "re-derive the record with ms_catalog_currency_update()"
      )
    }
    for (bd in names(cell)) {
      n <- cell[[bd]]
      if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 0 || n > 1e5) {
        .ms_cc_abort(
          sprintf("%s$%s$%s is not a bounded scalar profile count", what, cl, bd),
          i = "profile counts are structural (how many profiles the class publishes), never content",
          j = sprintf("received: %s", msuiter_quote_trunc(n)),
          c = "re-derive the record with ms_catalog_currency_update()"
        )
      }
    }
  }
  invisible(TRUE)
}

.ms_cc_read_registry <- function(path, call = rlang::caller_call()) {
  located <- is.character(path) && length(path) == 1L && !is.na(path) && nzchar(path)
  if (!located || !file.exists(path)) {
    .ms_cc_abort(
      "the catalog-currency registry is missing",
      i = "the committed digest sidecar governs every currency check",
      j = if (located) path else "system.file(catalog-currency/catalog_registry.rds) resolved to nothing",
      c = "restore inst/catalog-currency/catalog_registry.rds or rebuild it with data-raw/build_catalog_registry.R",
      call = call
    )
  }
  reg <- tryCatch(readRDS(path),
                  error = function(e) NULL, warning = function(w) NULL)
  if (is.null(reg)) {
    .ms_cc_abort(
      "the catalog-currency registry could not be read",
      i = "the sidecar is a readRDS governance record (a corrupt sidecar fails closed, never best-effort)",
      j = path,
      c = "restore the committed sidecar or rebuild it with data-raw/build_catalog_registry.R",
      call = call
    )
  }
  .ms_cc_validate_registry(reg)
}

.ms_cc_validate_injected_manifest <- function(man) {
  ok <- is.list(man) &&
    is.character(man$version) && length(man$version) == 1L && nzchar(man$version) &&
    is.list(man$files) && length(man$files) >= 1L &&
    !is.null(names(man$files)) && all(nzchar(names(man$files))) &&
    is.list(man$upstream) &&
    is.character(man$upstream$repo) && length(man$upstream$repo) == 1L && nzchar(man$upstream$repo) &&
    is.character(man$upstream$commit) && length(man$upstream$commit) == 1L &&
    nzchar(man$upstream$commit)
  if (!ok) {
    .ms_cc_abort(
      "the injected `refdb_manifest` is not a governance manifest",
      i = "`refdb_manifest` is a test/automation seam: pass the object from ms_refdb_manifest() or NULL",
      j = sprintf("received: %s", msuiter_quote_trunc(names(man))),
      c = "pass NULL (the function reads the governed manifest itself) or a complete manifest"
    )
  }
  man
}

.ms_cc_refdb_findings <- function(reg, man) {
  findings <- character()
  if (!identical(man$version, reg$refdb$version)) {
    findings <- c(findings, sprintf(
      "the shipped refdb manifest says version '%s' but the sidecar pins '%s'",
      man$version, reg$refdb$version))
  }
  if (!setequal(names(man$files), reg$refdb$governed_files)) {
    findings <- c(findings, sprintf(
      "the shipped refdb manifest governs {%s} but the sidecar expects {%s}",
      paste(names(man$files), collapse = ", "),
      paste(reg$refdb$governed_files, collapse = ", ")))
  }
  if (!identical(man$upstream$commit, reg$mirror$commit)) {
    findings <- c(findings, sprintf(
      "the shipped refdb manifest pins mirror commit %.12s... but the sidecar pins %.12s...",
      man$upstream$commit, reg$mirror$commit))
  }
  if (!identical(man$upstream$repo, reg$mirror$repo)) {
    findings <- c(findings, sprintf(
      "the shipped refdb manifest mirrors '%s' but the sidecar pins '%s'",
      man$upstream$repo, reg$mirror$repo))
  }
  findings
}

# ---------------------------------------------------------------------------
# The cache's own integrity record: read fail-closed. A present-but-unreadable
# or foreign record is a hard stop (never a silent no-cache pass); a wholly
# absent cache reads as NULL (the actionable `no-cache` verdict).
# ---------------------------------------------------------------------------
.ms_cc_read_record <- function(cache) {
  rec_path <- .ms_cc_record_path(cache)
  if (!dir.exists(cache) || !file.exists(rec_path)) {
    return(NULL)
  }
  rec <- tryCatch(readRDS(rec_path), error = function(e) NULL, warning = function(w) NULL)
  if (!is.list(rec) || !identical(rec$kind, .MS_CC_RECORD_KIND) ||
      !identical(rec$schema_version, .MS_CC_SCHEMA) ||
      !is.list(rec$documents) || !setequal(names(rec$documents), .MS_CC_DOC_KEYS) ||
      !is.character(rec$releases) || !length(rec$releases) ||
      !is.character(rec$latest_release) || !is.character(rec$structure_release)) {
    .ms_cc_abort(
      "the cache record could not be trusted",
      i = "record.rds is the cache's own integrity record; an unreadable or foreign record fails closed",
      j = rec_path,
      c = "re-derive the cache with ms_catalog_currency_update()"
    )
  }
  for (k in .MS_CC_DOC_KEYS) {
    d <- rec$documents[[k]]
    if (!is.character(d$sha256) || length(d$sha256) != 1L || !grepl(.MS_CC_SHA256_RE, d$sha256)) {
      .ms_cc_abort(
        sprintf("the cache record's digest for '%s' is malformed", k),
        i = "the record pins the exact bytes each cached document must have",
        j = sprintf("received: %s", msuiter_quote_trunc(d$sha256)),
        c = "re-derive the cache with ms_catalog_currency_update()"
      )
    }
  }
  rec
}
