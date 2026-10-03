#!/usr/bin/env Rscript
# Build the bundled reference signature database v1 (U-M3a-06).
#
# Downloads the COSMIC v3.6 human reference signature matrices from the
# Alexandrov-lab BSD-2 mirror (SigProfilerSuite/SigProfilerAssignment --
# NOT a cancer.sanger.ac.uk download; docs/research/05 section 1 and
# ADR D3 pin this provenance) at a PINNED upstream commit, verifies every
# file against the SHA-256 digests recorded below, canonicalizes the
# SBS96/DBS78 channel order to the msuiter channel registry
# (R/sysdata.rda, built by data-raw/build_channels.R), and writes:
#
#   inst/reference/refdb/COSMIC_v3.6/<file>.txt   verbatim mirror files
#   inst/reference/refdb/refdb_manifest.rds       governance manifest
#       (schema_version, version, upstream commit, license, per-file
#        sha256 over the exact shipped bytes, channel/signature labels)
#
# At load time R/refdb.R re-verifies every digest (fail-closed) using the
# SAME SHA-256 implementation (parsed out of R/fit.R below so the builder
# and the loader can never drift apart).
#
# Run:  Rscript data-raw/build_refdb.R
#
# Network: this script downloads ~0.4 MB ONCE (the only network step of the
# refdb unit). Check-time is fully offline: tests read the committed bundle
# under inst/reference and never touch the network. The script is
# deterministic and idempotent -- no timestamps, no randomness; re-running
# it against the pinned commit must reproduce byte-identical outputs (any
# upstream drift is a hard stop, never a silent re-pin).

.repo_root <- local({
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) > 0L) dirname(dirname(normalizePath(f[1]))) else normalizePath(".")
})

# ---------------------------------------------------------------------------
# Provenance pin (ADR D3 / research/05 section 1): the Alexandrov-lab BSD-2
# mirror, one immutable commit. Bumping the pin is a deliberate, reviewed
# act: update commit + digests together, never one of them.
# ---------------------------------------------------------------------------
.pin <- list(
  repo = "SigProfilerSuite/SigProfilerAssignment",
  commit = "ff61b0f56d43c916582b7c505ce72364c883dfbd",
  tag = "v1.1.5",
  url_base = paste(
    "https://raw.githubusercontent.com/SigProfilerSuite/SigProfilerAssignment",
    "ff61b0f56d43c916582b7c505ce72364c883dfbd",
    "SigProfilerAssignment/data/Reference_Signatures",
    sep = "/"
  ),
  license = "BSD-2-Clause",
  # v1 scope (ARCHITECTURE section 6, entry 2): human SBS/DBS GRCh37+GRCh38
  # and GRCh37 ID only; everything else goes through the (future)
  # ms_update_refdb() cache path.
  files = c(
    "GRCh37/COSMIC_v3.6_SBS_GRCh37.txt",
    "GRCh38/COSMIC_v3.6_SBS_GRCh38.txt",
    "GRCh37/COSMIC_v3.6_DBS_GRCh37.txt",
    "GRCh38/COSMIC_v3.6_DBS_GRCh38.txt",
    "GRCh37/COSMIC_v3.6_ID_GRCh37.txt"
  ),
  # SHA-256 of each source file at the pinned commit (fail-closed: upstream
  # drift stops the build instead of re-pinning silently).
  sha256 = c(
    "GRCh37/COSMIC_v3.6_SBS_GRCh37.txt" =
      "282126c3ba21a2eab89b43f249865461df516891149a85e699188622f2111623",
    "GRCh38/COSMIC_v3.6_SBS_GRCh38.txt" =
      "a93e33d45fdace6e08778f80ca87c6d784da71a6eb4fa9cf7775380f6daffec7",
    "GRCh37/COSMIC_v3.6_DBS_GRCh37.txt" =
      "c57c4213b7f84679fae9ba585d102d925cbe6629e588a892506a7b9391579475",
    "GRCh38/COSMIC_v3.6_DBS_GRCh38.txt" =
      "3f37e17e9301a36037457cc3dfe68752664c2c6a39909f9b1d9c6fd0a235ee6a",
    "GRCh37/COSMIC_v3.6_ID_GRCh37.txt" =
      "0dd53f8f18a7c7d8f631a128300b3f52fecbda99c29bcd3f66df1ed7b9f7579b"
  )
)

.version <- "v3.6"
.schema_version <- "1"

# Governance facts per class. ID channel labels are build-agnostic (indel
# contexts, no genome-coordinate semantics), so the GRCh37-only set ships
# with build = NA + build_independent = TRUE (the ARCHITECTURE section 6
# "missing build" declaration) and availability records where official
# reference sets exist upstream.
.class_facts <- list(
  SBS = list(
    files = c("GRCh37/COSMIC_v3.6_SBS_GRCh37.txt", "GRCh38/COSMIC_v3.6_SBS_GRCh38.txt"),
    availability = c("GRCh37", "GRCh38")
  ),
  DBS = list(
    files = c("GRCh37/COSMIC_v3.6_DBS_GRCh37.txt", "GRCh38/COSMIC_v3.6_DBS_GRCh38.txt"),
    availability = c("GRCh37", "GRCh38")
  ),
  ID = list(
    files = "GRCh37/COSMIC_v3.6_ID_GRCh37.txt",
    availability = "GRCh37"
  )
)

# ---------------------------------------------------------------------------
# SHA-256 (FIPS 180-4): parse the implementation OUT of R/fit.R so the
# manifest digests and the loader's verification share one code path.
# ---------------------------------------------------------------------------
.sha_env <- local({
  src <- parse(file.path(.repo_root, "R", "fit.R"))
  ev <- new.env(parent = globalenv())
  wanted <- c(
    ".ms_fit_sha256_k", ".ms_fit_sha256_h0", ".ms_fit_xor32", ".ms_fit_and32",
    ".ms_fit_not32", ".ms_fit_rotr32", ".ms_fit_add32", ".ms_fit_sha256"
  )
  for (e in src) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        is.symbol(e[[2]]) && as.character(e[[2]]) %in% wanted) {
      eval(e, ev)
    }
  }
  missing <- setdiff(wanted, ls(ev, all.names = TRUE))
  if (length(missing)) {
    stop("build_refdb: could not extract SHA-256 helpers from R/fit.R: ",
      paste(missing, collapse = ", "), call. = FALSE)
  }
  ev
})
.sha256_raw <- function(bytes) .sha_env$.ms_fit_sha256(bytes)
.sha256_file <- function(path) {
  .sha256_raw(readBin(path, "raw", file.info(path)$size))
}

.stop <- function(...) stop("build_refdb: ", ..., call. = FALSE)

# ---------------------------------------------------------------------------
# 1. Download (or reuse the staged copy) + verify against the pinned digests.
# ---------------------------------------------------------------------------
.stage_dir <- file.path(.repo_root, "data-raw", "reference", "refdb_stage")
dir.create(.stage_dir, recursive = TRUE, showWarnings = FALSE)

.staged <- file.path(.stage_dir, basename(.pin$files))
names(.staged) <- .pin$files
for (rel in .pin$files) {
  dest <- .staged[[rel]]
  if (!file.exists(dest)) {
    url <- paste(.pin$url_base, rel, sep = "/")
    tmp <- paste0(dest, ".part")
    ok <- tryCatch({
      download.file(url, tmp, mode = "wb", quiet = TRUE)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok || !file.exists(tmp)) {
      .stop("download failed for ", rel, " (network is required ONCE for this script)")
    }
    file.rename(tmp, dest)
  }
  got <- .sha256_file(dest)
  want <- .pin$sha256[[rel]]
  if (!identical(got, want)) {
    .stop("SHA-256 mismatch for ", rel, "\n  pinned: ", want, "\n  actual: ", got,
      "\nupstream moved -- update the pin (commit + digests) deliberately, never silently")
  }
}

# ---------------------------------------------------------------------------
# 2. Channel registry for canonical order (built by data-raw/build_channels.R).
# ---------------------------------------------------------------------------
sysdata <- new.env(parent = emptyenv())
load(file.path(.repo_root, "R", "sysdata.rda"), envir = sysdata)
if (!exists("channel_tables", envir = sysdata, inherits = FALSE)) {
  .stop("R/sysdata.rda does not carry channel_tables -- run data-raw/build_channels.R first")
}
.canon <- list(SBS = sysdata$channel_tables$SBS96$labels, DBS = sysdata$channel_tables$DBS78$labels)

# ---------------------------------------------------------------------------
# 3. Parse + canonicalize + structural checks; build the manifest entries.
# ---------------------------------------------------------------------------
.parse_matrix <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) < 2L) .stop("degenerate mirror file: ", path)
  header <- strsplit(lines[1L], "\t", fixed = TRUE)[[1L]]
  if (header[1L] != "Type") .stop("mirror file header must start with 'Type': ", path)
  sigs <- header[-1L]
  rows <- strsplit(lines[-1L], "\t", fixed = TRUE)
  if (any(lengths(rows) != length(sigs) + 1L)) {
    .stop("ragged mirror file: ", path)
  }
  channels <- vapply(rows, function(r) r[[1L]], character(1L))
  vals <- t(vapply(rows, function(r) as.numeric(r[-1L]), numeric(length(sigs))))
  m <- matrix(vals, nrow = length(channels), ncol = length(sigs),
    dimnames = list(channels, sigs))
  if (anyNA(m) || any(!is.finite(m))) .stop("NA/non-finite cells in ", path)
  if (any(m < 0)) .stop("negative cells in ", path)
  cs <- colSums(m)
  if (any(cs <= 0) || any(cs > 1 + 1e-6)) {
    .stop("signature columns must have positive mass (sum <= 1 + 1e-6): ", path)
  }
  m
}

.canonicalize <- function(m, class) {
  labels <- .canon[[class]]
  if (is.null(labels)) {
    # No canonical registry for this class yet (ID83 in v1): keep the mirror
    # order; the manifest records the labels and the loader enforces them
    # exactly (fail-closed on drift).
    return(m)
  }
  if (!setequal(rownames(m), labels)) {
    .stop("channel labels of the ", class, " matrix do not cover the canonical registry")
  }
  m[labels, , drop = FALSE] # canonical order (research/05 section 2)
}

entries <- list()
for (rel in .pin$files) {
  cls <- sub("^COSMIC_v[0-9.]+_([A-Z-]+)_GRCh[0-9]+\\.txt$", "\\1", basename(rel))
  if (!cls %in% names(.class_facts)) {
    .stop("could not derive the reference class of ", rel, " (got '", cls, "')")
  }
  m <- .canonicalize(.parse_matrix(.staged[[rel]]), cls)
  facts <- .class_facts[[cls]]
  build <- sub("^.*_(GRCh[0-9]+)\\.txt$", "\\1", basename(rel))
  entries[[basename(rel)]] <- list(
    class = cls,
    build = build,
    build_independent = FALSE,
    availability = facts$availability,
    sha256 = .pin$sha256[[rel]],
    bytes = as.integer(file.info(.staged[[rel]])$size),
    n_channels = nrow(m),
    n_signatures = ncol(m),
    channels = rownames(m),
    signatures = colnames(m)
  )
}
# The ID set: build-agnostic declaration (ARCHITECTURE section 6).
id_entry <- entries[["COSMIC_v3.6_ID_GRCh37.txt"]]
id_entry$build_independent <- TRUE
entries[["COSMIC_v3.6_ID_GRCh37.txt"]] <- id_entry

# ---------------------------------------------------------------------------
# 4. Ship the verbatim mirror bytes + the manifest into inst/reference.
# ---------------------------------------------------------------------------
.bundle_dir <- file.path(.repo_root, "inst", "reference", "refdb", paste0("COSMIC_", .version))
dir.create(.bundle_dir, recursive = TRUE, showWarnings = FALSE)
for (rel in .pin$files) {
  ok <- file.copy(.staged[[rel]], file.path(.bundle_dir, basename(rel)),
    overwrite = TRUE)
  if (!ok) .stop("could not copy ", rel, " into the bundle")
}
# The shipped bytes must hash EXACTLY like the pinned sources (the copy is
# the last place drift could enter).
for (rel in .pin$files) {
  shipped <- .sha256_file(file.path(.bundle_dir, basename(rel)))
  if (!identical(shipped, .pin$sha256[[rel]])) {
    .stop("shipped bytes of ", rel, " do not match the pinned digest")
  }
}

manifest <- list(
  schema_version = .schema_version,
  name = "COSMIC",
  version = .version,
  classes = names(.class_facts),
  upstream = list(
    repo = .pin$repo,
    commit = .pin$commit,
    tag = .pin$tag,
    url_base = .pin$url_base
  ),
  license = .pin$license,
  license_note = paste(
    "Reference matrices are redistributed from the Alexandrov-lab BSD-2-Clause",
    "mirror (SigProfilerSuite/SigProfilerAssignment, pinned commit above) -- NOT",
    "a cancer.sanger.ac.uk download. COSMIC terms formally prohibit",
    "redistribution of COSMIC data; the residual gap is flagged as legally",
    "ambiguous in docs/research/05 section 1 (domain practice: every signature",
    "tool bundles the same BSD-2 numerical matrices)."
  ),
  citations = c(
    "Alexandrov LB et al. (2020) The repertoire of mutational signatures in human cancer. Nature 578:94-101",
    "PCAWG Consortium (2020) Pan-cancer analysis of whole genomes. Nature 578:82-93"
  ),
  files = entries
)
saveRDS(manifest, file.path(.repo_root, "inst", "reference", "refdb", "refdb_manifest.rds"))

total <- sum(vapply(entries, function(e) e$bytes, numeric(1L)))
cat(sprintf(
  "build_refdb: bundled COSMIC %s at commit %s -- %d files, %d bytes, digests verified\n",
  .version, substr(.pin$commit, 1, 12), length(entries), total
))
