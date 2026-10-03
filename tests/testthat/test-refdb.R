# test-refdb.R: the bundled reference database (U-M3a-06).
#
# Governance is the contract: bundled existence, provenance/license fields,
# SHA-256 manifest verification (fail-closed on tampering), schema_version
# forward rejection (fail-closed on a newer schema), and channel-order
# agreement with the canonical channel registry. Everything here is
# OFFLINE: the bundle ships in inst/reference/refdb and the doctored-bundle
# fixtures are tempdir copies -- no test ever touches the network.

# The bundle layout inside the loader's root directory (manifest -> name +
# version subdirectory -> files).
.refdb_tmp_bundle <- function() {
  src <- system.file("reference", "refdb", package = "msuiter")
  tmp <- file.path(tempdir(), paste0("refdb-fixture-", as.integer(Sys.time()) + sample.int(1e6, 1)))
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(src, full.names = TRUE), tmp, recursive = TRUE)
  tmp
}

test_that("the bundle ships and resolves to governed MsRefDb objects", {
  refs <- ms_refdb_bundled()
  expect_setequal(names(refs), c("SBS_GRCh37", "SBS_GRCh38", "DBS_GRCh37", "DBS_GRCh38", "ID"))
  for (nm in names(refs)) {
    obj <- refs[[nm]]
    expect_is_ms(obj, "MsRefDb")
    meta <- obj@metadata
    expect_identical(meta$version, "v3.6")
    expect_identical(meta$schema_version, "1")
    expect_identical(meta$license, "BSD-2-Clause")
    expect_match(meta$sha256, "^[0-9a-f]{64}$")
    expect_false(anyNA(meta$availability))
  }
  # Build-specific objects carry the single build; the ID set carries the
  # A13 declaration (NA build only together with build_independent = TRUE).
  expect_identical(refs$SBS_GRCh37@metadata$build, "GRCh37")
  expect_identical(refs$SBS_GRCh38@metadata$build, "GRCh38")
  expect_false(refs$SBS_GRCh37@metadata$build_independent)
  expect_true(is.na(refs$ID@metadata$build))
  expect_true(refs$ID@metadata$build_independent)
  expect_identical(refs$ID@metadata$availability, "GRCh37")
  # Dimensions of the v1 scope: SBS96 x 101 signatures, DBS78 x 22, ID83 x 25.
  expect_identical(dim(refs$SBS_GRCh37@matrices$SBS_GRCh37), c(96L, 101L))
  expect_identical(dim(refs$SBS_GRCh38@matrices$SBS_GRCh38), c(96L, 101L))
  expect_identical(dim(refs$DBS_GRCh37@matrices$DBS_GRCh37), c(78L, 22L))
  expect_identical(dim(refs$DBS_GRCh38@matrices$DBS_GRCh38), c(78L, 22L))
  expect_identical(dim(refs$ID@matrices$ID_GRCh37), c(83L, 25L))
  # Matrices are non-negative, finite and column-normalized upstream mass.
  for (nm in names(refs)) {
    m <- refs[[nm]]@matrices[[1]]
    expect_true(all(is.finite(m)))
    expect_gte(min(m), 0)
    expect_true(all(colSums(m) > 0))
  }
})

test_that("channel order matches the canonical channel registry", {
  refs <- ms_refdb_bundled()
  # SBS96 / DBS78 rows are in the channel-registry canonical order (label
  # alignment is by ORDER here because both sides are canonical; the fit
  # layer additionally matches by label).
  expect_identical(rownames(refs$SBS_GRCh37@matrices$SBS_GRCh37), channel_tables$SBS96$labels)
  expect_identical(rownames(refs$SBS_GRCh38@matrices$SBS_GRCh38), channel_tables$SBS96$labels)
  expect_identical(rownames(refs$DBS_GRCh37@matrices$DBS_GRCh37), channel_tables$DBS78$labels)
  expect_identical(rownames(refs$DBS_GRCh38@matrices$DBS_GRCh38), channel_tables$DBS78$labels)
})

test_that("build selection honors precedence and the A13 declaration", {
  refs37 <- ms_refdb_bundled(build = "GRCh37")
  expect_setequal(names(refs37), c("SBS_GRCh37", "DBS_GRCh37", "ID"))
  # GRCh38 has no official ID set upstream: the build-independent ID83 set
  # is served WITH the transparency note (ARCHITECTURE section 6).
  expect_message(
    refs38 <- ms_refdb_bundled(build = "GRCh38"),
    regexp = "build-independent"
  )
  expect_setequal(names(refs38), c("SBS_GRCh38", "DBS_GRCh38", "ID"))
  # A build with no coverage at all outside the build-independent set:
  # SBS/DBS are skipped with a note, ID is served with its declaration.
  expect_message(
    res_mm10 <- ms_refdb_bundled(build = "mm10"),
    regexp = "no SBS reference set"
  )
  expect_setequal(names(res_mm10), "ID")
  # Scalar gates.
  expect_ms_error(ms_refdb_bundled(version = "v9.9"), "refdb", regexp = "v3.6")
  expect_ms_error(ms_refdb_bundled(version = 3.6), "refdb")
  expect_ms_error(ms_refdb_bundled(build = c("GRCh37", "GRCh38")), "refdb")
  expect_ms_error(ms_refdb_bundled(build = 37), "refdb")
})

test_that("the governance manifest carries provenance and license", {
  man <- ms_refdb_manifest()
  expect_identical(man$schema_version, "1")
  expect_identical(man$name, "COSMIC")
  expect_identical(man$version, "v3.6")
  # ADR D3: the Alexandrov-lab BSD-2 mirror, pinned to an upstream commit.
  expect_identical(man$upstream$repo, "SigProfilerSuite/SigProfilerAssignment")
  expect_match(man$upstream$commit, "^[0-9a-f]{40}$")
  expect_identical(man$license, "BSD-2-Clause")
  expect_match(man$license_note, "BSD-2")
  expect_false(grepl("cancer.sanger.ac.uk", man$upstream$url_base, fixed = TRUE))
  # Per-file records pin class, build and digests.
  expect_setequal(names(man$files), c(
    "COSMIC_v3.6_SBS_GRCh37.txt", "COSMIC_v3.6_SBS_GRCh38.txt",
    "COSMIC_v3.6_DBS_GRCh37.txt", "COSMIC_v3.6_DBS_GRCh38.txt",
    "COSMIC_v3.6_ID_GRCh37.txt"
  ))
  for (nm in names(man$files)) {
    e <- man$files[[nm]]
    expect_match(e$sha256, "^[0-9a-f]{64}$")
    expect_true(e$class %in% c("SBS", "DBS", "ID"))
    expect_true(is.character(e$channels) && is.character(e$signatures))
  }
  # The ID entry declares the missing build per A13.
  id <- man$files$COSMIC_v3.6_ID_GRCh37.txt
  expect_true(id$build_independent)
  expect_identical(id$availability, "GRCh37")
})

test_that("SHA-256 manifest verification fails closed on tampering", {
  tmp <- .refdb_tmp_bundle()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  # Untouched copy loads.
  expect_type(.ms_refdb_load_bundle(tmp)$manifest, "list")
  # Flip one byte of one shipped matrix: the digest gate refuses.
  target <- file.path(tmp, "COSMIC_v3.6", "COSMIC_v3.6_DBS_GRCh37.txt")
  lines <- readLines(target)
  lines[2] <- sub("^AC", "XX", lines[2])
  writeLines(lines, target, sep = "\n")
  expect_ms_error(.ms_refdb_load_bundle(tmp), "refdb", regexp = "SHA-256")
  # Deleting a manifest-listed file refuses too.
  tmp2 <- .refdb_tmp_bundle()
  on.exit(unlink(tmp2, recursive = TRUE), add = TRUE)
  file.remove(file.path(tmp2, "COSMIC_v3.6", "COSMIC_v3.6_SBS_GRCh38.txt"))
  expect_ms_error(.ms_refdb_load_bundle(tmp2), "refdb", regexp = "missing")
  # A missing manifest refuses (the manifest is the root of trust).
  tmp3 <- .refdb_tmp_bundle()
  on.exit(unlink(tmp3, recursive = TRUE), add = TRUE)
  file.remove(file.path(tmp3, "refdb_manifest.rds"))
  expect_ms_error(.ms_refdb_load_bundle(tmp3), "refdb", regexp = "manifest")
})

test_that("schema_version forward rejection fails closed", {
  tmp <- .refdb_tmp_bundle()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  man <- readRDS(file.path(tmp, "refdb_manifest.rds"))
  man$schema_version <- "2" # a future, unreadable schema
  saveRDS(man, file.path(tmp, "refdb_manifest.rds"))
  expect_ms_error(
    .ms_refdb_load_bundle(tmp),
    "refdb",
    regexp = "outside the supported set"
  )
})

test_that("label drift against the manifest fails closed", {
  tmp <- .refdb_tmp_bundle()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  # Rewrite a file with a different (sorted) channel order: digests are
  # recomputed over the new bytes, so the LABEL gate is what must fire --
  # doctor the manifest digest accordingly.
  target <- file.path(tmp, "COSMIC_v3.6", "COSMIC_v3.6_ID_GRCh37.txt")
  lines <- readLines(target)
  hdr <- strsplit(lines[1], "\t", fixed = TRUE)[[1]]
  body <- do.call(rbind, strsplit(lines[-1], "\t", fixed = TRUE))
  ord <- order(body[, 1])
  lines2 <- c(paste(hdr, collapse = "\t"),
    apply(body[ord, , drop = FALSE], 1, paste, collapse = "\t"))
  writeLines(lines2, target, sep = "\n")
  man <- readRDS(file.path(tmp, "refdb_manifest.rds"))
  entry <- man$files$COSMIC_v3.6_ID_GRCh37.txt
  # Digest updated to the reordered bytes (so only the LABEL gate can fire):
  # the manifest keeps the canonical order while the file no longer matches.
  entry$sha256 <- .ms_fit_sha256(readBin(target, "raw", file.info(target)$size))
  man$files$COSMIC_v3.6_ID_GRCh37.txt <- entry
  saveRDS(man, file.path(tmp, "refdb_manifest.rds"))
  expect_ms_error(
    .ms_refdb_load_bundle(tmp),
    "refdb",
    regexp = "disagrees with the manifest labels"
  )
})
