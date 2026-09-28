# MsCatalog: counts(channels x samples) + channel-registry snapshot +
# samples + provenance.
# Validator contract: dimension consistency, label-by-label agreement,
# non-negativity, anyNA rejection.

test_that("valid MsCatalog constructs and prints a one-line summary", {
  cat1 <- .make_catalog()
  expect_is_ms(cat1, "MsCatalog")
  expect_identical(cat1@samples, c("S1", "S2", "S3"))

  printed <- capture.output(print(cat1))
  expect_length(printed, 1)
  expect_match(printed[1], "MsCatalog")
  expect_match(printed[1], "6 channels")
  expect_match(printed[1], "3 samples")
  expect_match(printed[1], "SYN")
})

test_that("the channel snapshot stores name, labels and a computed hash", {
  cat1 <- .make_catalog()
  ch <- cat1@channels
  expect_identical(ch$name, "SYN")
  expect_identical(ch$labels, .make_catalog_labels())
  expect_identical(ch$hash, msuiter_hash_labels(ch$labels))
  # Forged hashes are rejected on the mutation path too (validator runs on
  # every property write, not only at construction).
  forged <- ch
  forged$hash <- paste0(rep("0", 32), collapse = "")
  expect_ms_error({cat1@channels <- forged}, "catalog", regexp = "hash")
})

test_that("dimension mismatches are rejected", {
  # channel count != nrow(counts)
  expect_ms_error(
    ms_catalog(
      counts = .make_counts(),
      channels = .make_catalog_channels(labels = .make_catalog_labels(7)),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog",
    regexp = "dimension"
  )
  # sample count != ncol(counts)
  expect_ms_error(
    ms_catalog(
      counts = .make_counts(),
      channels = .make_catalog_channels(),
      samples = c("S1", "S2"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog"
  )
})

test_that("labels are matched by label, never by position", {
  labels <- .make_catalog_labels()
  counts <- .make_counts(labels)
  # Same label set, scrambled order in the registry snapshot: must fail
  # because rownames(counts) and labels are not identical element-wise.
  expect_ms_error(
    ms_catalog(
      counts = counts,
      channels = .make_catalog_channels(labels = rev(labels)),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog",
    regexp = "label"
  )
  # A single divergent label is caught and reported.
  labels2 <- labels
  labels2[4] <- "CHXX"
  expect_ms_error(
    ms_catalog(
      counts = counts,
      channels = .make_catalog_channels(labels = labels2),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog"
  )
  # colnames(counts) must agree with samples element-wise.
  counts2 <- counts
  colnames(counts2) <- c("S1", "S2", "SX")
  expect_ms_error(
    ms_catalog(
      counts = counts2,
      channels = .make_catalog_channels(),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog"
  )
})

test_that("negative counts are rejected", {
  counts <- .make_counts()
  counts[2, 3] <- -1
  expect_ms_error(
    ms_catalog(
      counts = counts,
      channels = .make_catalog_channels(),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog",
    regexp = "negative"
  )
})

test_that("anyNA and non-finite counts are rejected", {
  counts <- .make_counts()
  counts[3, 1] <- NA_real_
  expect_ms_error(
    ms_catalog(
      counts = counts,
      channels = .make_catalog_channels(),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog",
    regexp = "NA"
  )
  counts2 <- .make_counts()
  counts2[3, 1] <- Inf
  expect_ms_error(
    ms_catalog(
      counts = counts2,
      channels = .make_catalog_channels(),
      samples = c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")
    ),
    "catalog"
  )
})

test_that("counts without dimnames and duplicate labels are rejected", {
  counts <- .make_counts()
  counts <- unname(counts)
  expect_ms_error(
    ms_catalog(counts, .make_catalog_channels(), c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")),
    "catalog"
  )
  labels <- .make_catalog_labels()
  labels[2] <- labels[1]
  counts <- .make_counts()
  rownames(counts) <- labels
  expect_ms_error(
    ms_catalog(counts, .make_catalog_channels(labels = labels), c("S1", "S2", "S3"),
      provenance = list(genome = "GRCh38")),
    "catalog",
    regexp = "duplicate"
  )
})

test_that("provenance must carry the genome build", {
  expect_ms_error(
    ms_catalog(.make_counts(), .make_catalog_channels(), c("S1", "S2", "S3"),
      provenance = list(caller = "x")),
    "catalog",
    regexp = "genome"
  )
})

test_that("RDS round trip preserves dispatch and validity", {
  cat1 <- .make_catalog()
  cat2 <- .roundtrip(cat1)
  expect_identical(format(cat2), format(cat1))
  expect_identical(cat2@channels$hash, cat1@channels$hash)
  expect_no_error(S7::validate(cat2))
  expect_is_ms(cat2, "MsCatalog")
})
