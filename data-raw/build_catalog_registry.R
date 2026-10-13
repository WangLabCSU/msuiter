#!/usr/bin/env Rscript
# build_catalog_registry.R -- derive the committed catalog-currency
# provenance sidecar (inst/catalog-currency/catalog_registry.rds).
#
# Companion to data-raw/build_refdb.R (same governance laws): every digest
# is MEASURED from fetched bytes inside this script, never re-typed; the
# build is deterministic (no timestamps, no randomness); upstream drift is
# a loud stop, never a silent re-pin. D3 law: the sidecar carries digests,
# URLs, version labels and structural (shape) facts ONLY -- COSMIC numeric
# content never enters it. The login-gated official matrix-bytes leg is
# recorded UNMEASURED by construction (zero-fabrication law).
#
# Usage:
#   Rscript data-raw/build_catalog_registry.R                  # official fetch
#   Rscript data-raw/build_catalog_registry.R --source=DIR|FILE # offline re-pin
#   Rscript data-raw/build_catalog_registry.R --dry-run        # inspect only
#
#   --source   harvest from a captured downloads-page file or a split
#              directory (reference_data.json + availability_data.json)
#              instead of the live fetch; digests still measured from bytes.
#   --dry-run  validate and report; write nothing.
#
# macOS note: the load_all step compiles the Rust/C core -- on broken-SDK
# toolchains export SDKROOT=<working SDK> first (see tools/README notes).

if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("pkgload is required to run this builder", call. = FALSE)
}
suppressPackageStartupMessages(pkgload::load_all(".", quiet = TRUE))

.args <- commandArgs(trailing = FALSE)
.getFlag <- function(prefix) {
  hit <- .args[startsWith(.args, prefix)]
  if (!length(hit)) return(NULL)
  substring(hit[1L], nchar(prefix) + 1L)
}
.source <- .getFlag("--source=")
.dry_run <- any(.args == "--dry-run")

.repo_root <- normalizePath(".", mustWork = TRUE)
.out_path <- file.path(.repo_root, "inst", "catalog-currency",
                      "catalog_registry.rds")

# ---------------------------------------------------------------------------
# 1. The refdb cross-reference: read LIVE through the governed loader, so
#    the sidecar can never disagree with the bytes actually shipped.
# ---------------------------------------------------------------------------
.manifest <- msuiter::ms_refdb_manifest()
cat("refdb cross-reference: version", .manifest$version, "| mirror",
    .manifest$upstream$repo, "@", substr(.manifest$upstream$commit, 1L, 12L), "... |\n")
cat("  governed files:", paste(names(.manifest$files), collapse = ", "), "\n")

# ---------------------------------------------------------------------------
# 2. Harvest the two official source documents (measured digests).
# ---------------------------------------------------------------------------
.page_url <- getOption("msuiter.catalog_currency.page_url", default =
                    "https://cancer.sanger.ac.uk/signatures/downloads/")
.ns <- asNamespace("msuiter")
if (is.null(.source)) {
  cat("harvesting from the official page:", .page_url, "\n")
  .tmp <- file.path(tempdir(), "p5-build-page.html")
  ok <- tryCatch({ download.file(.page_url, .tmp, mode = "wb", quiet = TRUE); TRUE },
                 error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok || !file.exists(.tmp)) {
    stop("the official downloads page could not be fetched -- re-run with ",
         "--source=<capture> for an offline re-pin", call. = FALSE)
  }
  on.exit(unlink(.tmp))
  .html <- rawToChar(readBin(.tmp, "raw", file.info(.tmp)$size))
  .payloads <- list(
    reference_data = .ns$.ms_cc_extract_script(.html, "reference-data"),
    availability_data = .ns$.ms_cc_extract_script(.html, "availability-data")
  )
  .origin_note <- "official-site fetch"
} else {
  cat("harvesting from injected source:", .source, "\n")
  .harv <- .ns$.ms_cc_harvest(.source, .page_url, offline = TRUE)
  .payloads <- list(reference_data = .harv$ref_text,
                  availability_data = .harv$avail_text)
  .origin_note <- paste("injected source:", .harv$origin$mode)
}
.doc_keys <- names(.payloads)
.doc_facts <- setNames(lapply(unname(.doc_keys), function(k) {
  text <- .payloads[[k]]
  list(
    url = .page_url,
    script_id = switch(k, reference_data = "reference-data",
                       availability_data = "availability-data"),
    sha256 = .ns$.ms_cc_sha256_text(text),
    bytes = as.integer(length(charToRaw(text)))
  )
}), .doc_keys)

# ---------------------------------------------------------------------------
# 3. Version labels + structural facts, parsed from the measured payloads.
# ---------------------------------------------------------------------------
.ref <- .ns$.ms_cc_parse_reference(.payloads[["reference_data"]])
.latest <- .ns$.ms_cc_latest_version(.ref$releases)
.pinned <- .manifest$version
# The sidecar pins the refdb release line; measured truth must agree.
if (!grepl("^[0-9]+(\\.[0-9]+){0,2}$", sub("^[vV]", "", .pinned))) {
  stop("unexpected refdb version label: ", .pinned, call. = FALSE)
}
.pinned_release <- sub("^[vV]", "", .pinned)
if (.ns$.ms_cc_version_cmp(.pinned_release, .latest) > 0L) {
  stop("the sidecar would pin '", .pinned_release, "' but the source documents ",
       "only report releases up to '", .latest, "' -- a pin ahead of measured ",
       "truth is a human decision, not a build artifact", call. = FALSE)
}
.structure <- .ns$.ms_cc_parse_availability(.payloads[["availability_data"]], .latest)
cat("measured release line:", paste(.ref$releases, collapse = ", "),
     "| latest:", .latest, "| pinned target:", .pinned_release, "\n")

.registry <- list(
  schema_version = .ns$.MS_CC_SCHEMA,
  kind = .ns$.MS_CC_REGISTRY_KIND,
  package = "msuiter",
  built_by = "data-raw/build_catalog_registry.R (digests measured in-run; deterministic)",
  built_from = .origin_note,
  pinned_release = .pinned_release,
  mirror = list(
    repo = .manifest$upstream$repo,
    commit = .manifest$upstream$commit,
    tag = .manifest$upstream$tag,
    license = .manifest$license
  ),
  refdb = list(
    version = .manifest$version,
    governed_files = names(.manifest$files)
  ),
  official = list(
    site_root = sub("(/signatures/.*)$", "", .page_url),
    page_url = .page_url,
    documents = .doc_facts,
    releases = .ref$releases,
    latest_release = .latest,
    structure_release = .latest,
    structure = .structure
  ),
  matrix_bytes = list(
    status = "UNMEASURED",
    sha256 = NULL,
    policy = paste(
      "The official COSMIC matrix downloads behind the download flow are",
      "login-gated; anonymous digests are not obtainable and fabricating one is",
      "banned. The bytes the package actually ships are governed instead by",
      "the refdb manifest digests (inst/reference/refdb/refdb_manifest.rds),",
      "which the loader re-verifies fail-closed on every load."
    )
  )
)

# ---------------------------------------------------------------------------
# 4. Self-check with the package's own fail-closed gate, then write (or not).
# ---------------------------------------------------------------------------
.tmp_out <- file.path(tempdir(), "catalog_registry_candidate.rds")
saveRDS(.registry, .tmp_out, version = 2L)
invisible(msuiter::ms_catalog_registry(path = .tmp_out))
cat("self-check: the generated sidecar passes the package's own registry gate\n")
for (k in names(.doc_facts)) {
  cat(sprintf("  %-16s sha256 %s (%d bytes)\n", k, .doc_facts[[k]]$sha256,
             .doc_facts[[k]]$bytes))
}
if (.dry_run) {
  cat("--dry-run: nothing written. Candidate at ", .tmp_out, "\n")
  quit(save = "no", status = 0L)
}
dir.create(dirname(.out_path), recursive = TRUE, showWarnings = FALSE)
file.copy(.tmp_out, .out_path, overwrite = TRUE)
unlink(.tmp_out)
cat("wrote ", .out_path, " (review with: Rscript tools/catalog-currency.R registry)\n")
