# U-M4-02b: ms_qc_report() -- the sample-level QC report first version
# (design memo docs/devlog/2026-10-04-M4-02b-qc-memo.md).
#
# Anchors: the COSMIC artifact roster pinned LITERALLY (20 names, the
# 2026-10-04 verification); hand-derived burden/sentinel numbers on a
# constructed SBS96 catalog; a synthetic artifact dictionary with every
# artifact_share digit pinned; structured error paths.

.ms_qc_sbs96_labels <- function() {
  msuiter:::.ms_io_channel_tables()$SBS96
}

# A small SBS96 catalog with controlled sentinel shares: sample 1
# heavy G>T (oxoG-like), sample 2 heavy C>T (FFPE-like), sample 3
# balanced, sample 4 dead.
.ms_qc_catalog <- function() {
  labels <- .ms_qc_sbs96_labels()
  counts <- matrix(0L, nrow = 96, ncol = 4, dimnames = list(labels,
    c("oxoG_like", "ffpe_like", "balanced", "dead")))
  gt <- grep("C>A", labels) # 16 channels (the pyrimidine view of G>T)
  ct <- grep("C>T", labels) # 16 channels
  rest <- setdiff(seq_len(96), c(gt, ct)) # 64 channels
  # Share arithmetic on per-channel counts: 16·g vs 64·r gives
  # g/(g+4r); g=6, r=1 => 96/160 = 0.6 (gt) and 0 (ct); the mirrored
  # column gives ct 0.6 by symmetry.
  counts[gt, 1] <- 6L
  counts[rest, 1] <- 1L
  counts[ct, 2] <- 6L
  counts[rest, 2] <- 1L
  counts[rest[1:30], 3] <- 10L # total 300, no sentinel channels
  ms_catalog(counts, list(name = "SBS96", labels = labels),
    colnames(counts), provenance = list(genome = "GRCh37"))
}

test_that("the COSMIC artifact roster is pinned literally", {
  want <- c("SBS27", "SBS43", paste0("SBS", 45:60), "SBS95")
  expect_identical(msuiter:::.ms_qc_artifact_sbs, want)
  # The enumerated COSMIC list is 19 names (SBS27, SBS43, SBS45-SBS60,
  # SBS95); the fetched page prose said "20 signatures total" — the
  # enumeration is the pin, not the prose count.
  expect_identical(length(want), 19L)
  # sanity: SBS30/36/18 are NOT in the roster (real signatures).
  expect_false("SBS30" %in% want)
  expect_false("SBS36" %in% want)
  expect_false("SBS18" %in% want)
})

test_that("burden and sentinel shares are hand-derived exact", {
  cat1 <- .ms_qc_catalog()
  rep1 <- ms_qc_report(cat1)
  expect_identical(rep1$total, c(160, 160, 300, 0))
  expect_identical(rep1$burden_class,
    c("standard", "standard", "standard", "dead"))
  expect_identical(rep1$gt_share, c(0.6, 0, 0, NA_real_))
  expect_identical(rep1$ct_share, c(0, 0.6, 0, NA_real_))
  expect_identical(rep1$log10_total[1], log10(160))
  expect_true(is.na(rep1$log10_total[4]))
  # Flags: sample 1 artifact (gt 0.6 >= 0.30); sample 2 watch (ct 0.6
  # >= 0.40 watch line, below the artifact share line — the sentinel
  # clause is gt-only); sample 3 ok; sample 4 dead (no signal).
  expect_identical(rep1$qc_flag, c("artifact", "watch", "ok", "ok"))
})

test_that("artifact_share is exact on a synthetic dictionary", {
  cat1 <- .ms_qc_catalog()
  labels <- .ms_qc_sbs96_labels()
  # 3 signatures: a real-like (SBS1-shaped), an artifact-named one, and
  # an unnamed filler whose stem is not on the roster.
  sigs <- matrix(0, nrow = 96, ncol = 3, dimnames = list(labels,
    c("SBS1", "SBS43", "my_real_sig")))
  sigs[grep("^A\\[C>T\\]A$", labels), 1] <- 1
  sigs[grep("^A\\[C>A\\]A$", labels), 2] <- 1
  sigs[grep("^A\\[C>G\\]A$", labels), 3] <- 1
  sigs <- sweep(sigs, 2, colSums(sigs), "/")
  # Exposures: sample 1 = 50% artifact; sample 2 = 10% (below 0.05? no,
  # above); sample 3 = 0%; sample 4 = all artifact but zero total.
  expo <- matrix(0, nrow = 3, ncol = 4, dimnames = list(
    c("SBS1", "SBS43", "my_real_sig"), colnames(cat1@counts)))
  expo[, 1] <- c(50, 50, 0)
  expo[, 2] <- c(90, 10, 0)
  expo[, 3] <- c(100, 0, 0)
  expo[, 4] <- c(0, 0, 0) # zero total -> NA share
  rep1 <- ms_qc_report(cat1, signatures = sigs, exposures = expo)
  expect_identical(rep1$artifact_share, c(0.5, 0.1, 0, NA_real_))
  expect_identical(rep1$artifact_sigs,
    c("SBS43", "SBS43", NA_character_, NA_character_))
  # sample 1/2 flag artifact by share; sample 4 is the zero-exposure
  # dead column (NA share, no signal) -> ok.
  expect_identical(rep1$qc_flag, c("artifact", "artifact", "ok", "ok"))
  # Name-stem matching: a suffixed artifact name still matches.
  colnames(sigs)[2] <- "SBS43b"
  rownames(expo)[2] <- "SBS43b"
  rep2 <- ms_qc_report(cat1, signatures = sigs, exposures = expo)
  expect_identical(rep2$artifact_share[1], 0.5)
})

test_that("error paths are structured", {
  cat1 <- .ms_qc_catalog()
  labels <- .ms_qc_sbs96_labels()
  expect_ms_error(ms_qc_report("junk"), "input")
  # Non-SBS96 space rejected via the sentinel channel count.
  labels8 <- sprintf("CH%02d", 1:8)
  cat8 <- ms_catalog(matrix(1, 8, 1, dimnames = list(labels8, "S")),
    list(name = "SYN8", labels = labels8), "S",
    provenance = list(genome = "SYN-true"))
  expect_ms_error(ms_qc_report(cat8), "input")
  # Exposure column mismatch (2 signatures x 5 columns != 4 samples).
  sigs <- matrix(0, 96, 2, dimnames = list(labels, c("a", "b")))
  expect_ms_error(ms_qc_report(cat1, signatures = sigs,
    exposures = matrix(1, 2, 5)), "input")
  # Channel-space mismatch: a non-registry label set.
  sigs_bad <- matrix(0, 96, 2, dimnames = list(paste0("X", 1:96),
    c("a", "b")))
  expect_ms_error(ms_qc_report(cat1, signatures = sigs_bad,
    exposures = matrix(1, 2, 4)), "input")
  # Exposure rows != signature columns.
  expect_ms_error(ms_qc_report(cat1, signatures = sigs,
    exposures = matrix(1, 3, 4)), "input")
  # The label protocol: mislabeled exposure rows are rejected even when
  # the shapes all match (audit P2-4c — positional misassignment).
  expo_mis <- matrix(1, 2, 4, dimnames = list(c("b", "a"),
    c("oxoG_like", "ffpe_like", "balanced", "dead")))
  expect_ms_error(ms_qc_report(cat1, signatures = sigs,
    exposures = expo_mis), "input")
  # The strand_bias_p placeholder column is in the contract (memo §3).
  rep1 <- ms_qc_report(cat1)
  expect_true("strand_bias_p" %in% names(rep1))
  expect_true(all(is.na(rep1$strand_bias_p)))
})
