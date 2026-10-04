# U-M4-02: ms_downsample() + COSMIC-format interop (design memo
# docs/devlog/2026-10-04-M4-02-design-memo.md).
#
# Anchors: the sanity-harness multinomial law (bitwise reproducible for a
# given catalog + seed), the registry canonical label order on both interop
# faces, and the REAL bundled COSMIC v3.6 reference file as the import
# specimen (upstream bytes, in-repo).

.ms_ds_catalog <- function() {
  labels <- sprintf("CH%02d", 1:8)
  counts <- matrix(0, nrow = 8, ncol = 3,
    dimnames = list(labels, c("S1", "S2", "S3")))
  counts[, 1] <- c(100, 50, 40, 30, 20, 10, 0, 0) # total 250
  counts[, 2] <- c(10, 10, 10, 10, 10, 10, 10, 10) # total 80
  counts[, 3] <- 0 # a dead sample
  ms_catalog(counts, list(name = "SYN8", labels = labels),
    c("S1", "S2", "S3"), provenance = list(genome = "SYN-true"))
}

test_that("ms_downsample thins deep samples, keeps shallow and dead ones", {
  cat1 <- .ms_ds_catalog()
  ds <- ms_downsample(cat1, depth = 100, seed = 7)
  expect_is_ms(ds, "MsCatalog")
  expect_identical(dim(ds@counts), c(8L, 3L))
  # Sample 1 (250 -> 100): thinned, exactly 100 total.
  expect_identical(sum(ds@counts[, 1]), 100)
  # Sample 2 (80 <= 100): kept verbatim.
  expect_identical(ds@counts[, 2], cat1@counts[, 2])
  # Sample 3: dead stays dead.
  expect_identical(sum(ds@counts[, 3]), 0)
  # Provenance records the operation.
  expect_identical(ds@provenance$downsample$depth, 100)
  expect_identical(ds@provenance$downsample$n_downsampled, 1L)
  expect_identical(ds@provenance$downsample$n_kept_verbatim, 1L)
  # Labels/channels/samples untouched.
  expect_identical(ds@channels$labels, cat1@channels$labels)
  expect_identical(ds@samples, cat1@samples)
})

test_that("ms_downsample is bitwise reproducible and depth = min works", {
  cat1 <- .ms_ds_catalog()
  a <- ms_downsample(cat1, depth = 100, seed = 7)
  b <- ms_downsample(cat1, depth = 100, seed = 7)
  expect_identical(a@counts, b@counts)
  c2 <- ms_downsample(cat1, depth = 100, seed = 8)
  expect_false(identical(a@counts[, 1], c2@counts[, 1]))
  # depth = "min": the smallest LIVE total (80 here) — sample 2 kept
  # (equal, not below), sample 1 thinned to 80.
  ds <- ms_downsample(cat1, depth = "min", seed = 3)
  expect_identical(sum(ds@counts[, 1]), 80)
  expect_identical(sum(ds@counts[, 2]), 80)
})

test_that("ms_downsample error paths are structured", {
  cat1 <- .ms_ds_catalog()
  expect_ms_error(ms_downsample("not-a-catalog"), "input")
  expect_ms_error(ms_downsample(cat1, depth = 0), "input")
  expect_ms_error(ms_downsample(cat1, depth = 10.5), "input")
  expect_ms_error(ms_downsample(cat1, depth = "min", seed = -1), "input")
  dead_labels <- cat1@channels$labels
  dead <- ms_catalog(matrix(0, 8, 3, dimnames = list(dead_labels,
    c("S1", "S2", "S3"))), list(name = "SYN8", labels = dead_labels),
    c("S1", "S2", "S3"), provenance = list(genome = "SYN-true"))
  expect_ms_error(ms_downsample(dead, depth = "min"), "input")
})

test_that("cosmic export roundtrips counts bit-for-bit", {
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  counts <- matrix(sample(0:50, 96 * 3, replace = TRUE), nrow = 96,
    dimnames = list(labels, c("T1", "T2", "T3")))
  cat1 <- ms_catalog(counts, list(name = "SBS96", labels = labels),
    c("T1", "T2", "T3"), provenance = list(genome = "GRCh37"))
  out <- ms_export(cat1, format = "cosmic")
  expect_identical(names(out), c("Type", "T1", "T2", "T3"))
  expect_identical(as.character(out$Type), labels)
  path <- tempfile(fileext = ".txt")
  on.exit(unlink(path), add = TRUE)
  ms_export(cat1, format = "cosmic", file = path)
  # The written file is TSV with the "Type" header column.
  head_line <- readLines(path, n = 1L, warn = FALSE)
  expect_identical(strsplit(head_line, "\t", fixed = TRUE)[[1L]][1L], "Type")
  back <- ms_import(path, format = "cosmic", kind = "catalog")
  expect_is_ms(back, "MsCatalog")
  expect_identical(back@counts, counts)
  expect_identical(back@samples, c("T1", "T2", "T3"))
  expect_identical(back@channels$name, "SBS96")
})

test_that("the REAL bundled COSMIC v3.6 file exercises the import reader", {
  # The upstream specimen (signature probabilities, not counts) must reach
  # the integer gate and fail with the structured catalog error -- proving
  # the reader parses the real bytes, header and labels included. The
  # signatures import face is deferred (design memo section 2).
  path <- system.file("reference/refdb/COSMIC_v3.6/COSMIC_v3.6_SBS_GRCh37.txt",
    package = "msuiter")
  skip_if(!nzchar(path), "bundled COSMIC file unavailable")
  expect_ms_error(ms_import(path, format = "cosmic", kind = "catalog"),
    "input")
  expect_ms_error(ms_import(path, format = "cosmic", kind = "signatures"),
    "option")
})

test_that("interop error paths are structured", {
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  cat1 <- ms_catalog(matrix(1, 96, 1, dimnames = list(labels, "S")),
    list(name = "SBS96", labels = labels), "S",
    provenance = list(genome = "GRCh37"))
  expect_ms_error(ms_export(cat1, format = "sigprofiler"), "option")
  expect_ms_error(ms_export("junk"), "input")
  # Label order is the interop contract: a shuffled label vector against
  # the pinned table is rejected (catalogs with mismatched labels cannot
  # exist -- the MsCatalog validator enforces registry order -- so the
  # resolution helper is the exact violation point).
  expect_ms_error(
    msuiter:::.ms_io_resolve_table(sample(labels),
      channel_table = "SBS96"),
    "input"
  )
  expect_ms_error(ms_import(tempfile(), format = "cosmic"), "input")
  expect_ms_error(ms_import(tempfile(), format = "nope"), "option")
  bad_labels <- labels
  expect_ms_error(
    msuiter:::.ms_io_resolve_table(bad_labels[1:90], channel_table = "NOPE"),
    "input"
  )
})
