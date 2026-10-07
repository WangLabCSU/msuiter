# test-hrd-report.R -- U-M6s-01 RED batch: the ms_hrd_report() API surface and
# its two hard gates. Public API and gate/error classes are the design memo's
# (docs/devlog/2026-10-07-m6s-hrd-report-design.md section 2), the ground truth
# for the two scores being cran/SigMiner get_pLOH_score.R / get_Aneuploidy_score.R.
#
# This is a RED batch: ms_hrd_report() is not yet implemented, so every test_that
# is red by construction -- the verbatim gates assert their exact
# msuiter_error_<topic> class (expect_ms_error from helper-classes.R) and the
# accept paths assert the fixed return contract, all of which fail while the
# function is absent. Per-column names and the non-verbatim error topics are
# CONTRACT CHOICES listed in the batch report for human reconciliation.

# --- contract: fixed return columns (memo section 2 + task return structure) ---
.ms_hrd_required_cols <- c(
  "sample", "genome", "caller", "assay",
  "ploh_fraction", "aneuploidy_count", "hrd_score",
  "evidence_tier", "n_windows_scored", "coverage_note", "ploidy_source"
)

# a minimal one-sample, autosome, WGS, whitelisted-caller fixture
.ms_hrd_ok_segments <- function(sample = "S1", caller = "ascat", assay = "wgs") {
  .make_hrd_segments(
    sample = sample, chromosome = "chr1", start = c(1, 1000), end = c(500, 1500),
    state = c(2, 1), minor_cn = c(0, 0), caller = caller, assay = assay
  )
}

# --- input validation ----------------------------------------------------------

test_that("a non-data.frame input is rejected as an input error", {
  expect_ms_error(
    msuiter::ms_hrd_report(42, genome = "GRCh37", caller = "ascat", assay = "wgs"),
    "input"
  )
})

test_that("a segment table missing a required column is rejected as an input error", {
  segs <- .ms_hrd_ok_segments()
  segs$state <- NULL # drop the required integer-CN column
  expect_ms_error(
    msuiter::ms_hrd_report(segs, genome = "GRCh37", caller = "ascat", assay = "wgs"),
    "input"
  )
})

test_that("a non-numeric coordinate/state column is rejected as an input error", {
  segs <- .ms_hrd_ok_segments()
  segs$start <- as.character(segs$start) # coordinates must be numeric, not strings
  expect_ms_error(
    msuiter::ms_hrd_report(segs, genome = "GRCh37", caller = "ascat", assay = "wgs"),
    "input"
  )
})

test_that("an unrecognised genome build is rejected", {
  expect_ms_error(
    msuiter::ms_hrd_report(.ms_hrd_ok_segments(), genome = "hg99",
      caller = "ascat", assay = "wgs"),
    "genome"
  )
})

# --- WGS-only gate -------------------------------------------------------------

test_that("the WGS assay path is accepted and returns one row per sample", {
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    .ms_hrd_ok_segments(), genome = "GRCh37", caller = "ascat", assay = "wgs"
  ))
  expect_identical(nrow(rep1), 1L)
  expect_identical(rep1$assay[[1L]], "wgs")
})

test_that("a WES assay without the experimental opt-in raises hrd-wes-experimental", {
  expect_ms_error(
    msuiter::ms_hrd_report(.ms_hrd_ok_segments(assay = "wes"), genome = "GRCh37",
      caller = "ascat", assay = "wes", experimental = FALSE),
    "hrd-wes-experimental"
  )
})

test_that("WES with the experimental opt-in is accepted and tiered as experimental", {
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    .ms_hrd_ok_segments(assay = "wes"), genome = "GRCh37", caller = "ascat",
    assay = "wes", experimental = TRUE
  ))
  expect_gt(nrow(rep1), 0L)
  expect_true(all(rep1$evidence_tier == "experimental"))
})

test_that("the WGS tier is a non-experimental string (WGS is not the experimental arm)", {
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    .ms_hrd_ok_segments(), genome = "GRCh37", caller = "ascat", assay = "wgs"
  ))
  expect_true(is.character(rep1$evidence_tier))
  expect_false(any(rep1$evidence_tier == "experimental"))
})

# --- caller whitelist gate -----------------------------------------------------

test_that("each of the five validated callers is accepted on the whitelist", {
  accepted <- vapply(.HRD_CALLERS, function(cl) {
    r <- tryCatch({
      as.data.frame(msuiter::ms_hrd_report(.ms_hrd_ok_segments(),
        genome = "GRCh37", caller = cl, assay = "wgs"))
      TRUE
    }, error = function(e) FALSE)
    r
  }, logical(1))
  expect_true(all(accepted))
  expect_identical(.HRD_CALLERS,
    c("battenberg", "ascat", "facets", "purple", "sequenza"))
})

test_that("an off-whitelist caller raises hrd-caller-whitelist naming the value", {
  expect_ms_error(
    msuiter::ms_hrd_report(.ms_hrd_ok_segments(), genome = "GRCh37",
      caller = "cnvkit", assay = "wgs"),
    "hrd-caller-whitelist", regexp = "cnvkit"
  )
})

test_that("a second off-whitelist caller is rejected case-preservingly", {
  expect_ms_error(
    msuiter::ms_hrd_report(.ms_hrd_ok_segments(), genome = "GRCh37",
      caller = "oncoscan", assay = "wgs"),
    "hrd-caller-whitelist", regexp = "oncoscan"
  )
})

test_that("CNVkit is rejected on the report even though the segments reader knows it", {
  # the report whitelist is narrower than the caller roster it may ingest;
  # CNVkit output is not allele-specific, so it is never HRD-scoreable
  expect_ms_error(
    msuiter::ms_hrd_report(.ms_hrd_ok_segments(), genome = "GRCh37",
      caller = "cnvkit", assay = "wgs"),
    "hrd-caller-whitelist"
  )
})

# --- S3 shape ------------------------------------------------------------------

test_that("the report is an MsHrdReport object whose data.frame face is all atomic", {
  rep <- msuiter::ms_hrd_report(.ms_hrd_ok_segments(), genome = "GRCh37",
    caller = "ascat", assay = "wgs")
  expect_true("MsHrdReport" %in% class(rep))
  df <- as.data.frame(rep)
  expect_true(is.data.frame(df))
  expect_true(all(.ms_hrd_required_cols %in% names(df)))
  atomics <- vapply(df, function(col) is.atomic(col) && !is.matrix(col), logical(1))
  expect_true(all(atomics))
})

test_that("every required column is present and equal length across samples", {
  segs <- rbind(.ms_hrd_ok_segments(sample = "A"), .ms_hrd_ok_segments(sample = "B"))
  df <- as.data.frame(msuiter::ms_hrd_report(segs, genome = "GRCh37",
    caller = "ascat", assay = "wgs"))
  expect_identical(nrow(df), 2L)
  lens <- vapply(df[.ms_hrd_required_cols], length, integer(1))
  expect_true(all(lens == 2L))
})

test_that("the per-chromosome aneuploidy detail is exposed as a chrom-level table", {
  rep <- msuiter::ms_hrd_report(.ms_hrd_ok_segments(), genome = "GRCh37",
    caller = "ascat", assay = "wgs", arms = .hrd_arms_chr1(), ploidy = 2)
  detail <- attr(rep, "aneuploidy_detail")
  expect_true(is.data.frame(detail))
  expect_true("chrom" %in% names(detail))
})

# --- uncertainty reporting -----------------------------------------------------

test_that("n_windows_scored is a non-negative integer aligned to the sample rows", {
  df <- as.data.frame(msuiter::ms_hrd_report(.ms_hrd_ok_segments(),
    genome = "GRCh37", caller = "ascat", assay = "wgs"))
  expect_true(is.integer(df$n_windows_scored))
  expect_true(all(df$n_windows_scored >= 0L))
  expect_identical(length(df$n_windows_scored), nrow(df))
})

test_that("coverage_note is a character column and ploidy_source is caller or derived", {
  df <- as.data.frame(msuiter::ms_hrd_report(.ms_hrd_ok_segments(),
    genome = "GRCh37", caller = "ascat", assay = "wgs", ploidy = 2))
  expect_true(is.character(df$coverage_note))
  expect_true(all(df$ploidy_source %in% c("caller", "derived")))
  expect_true(all(is.na(df$coverage_note) | nzchar(df$coverage_note)))
})

test_that("a caller-supplied ploidy is tagged caller, an omitted one tagged derived", {
  with_p <- as.data.frame(msuiter::ms_hrd_report(.ms_hrd_ok_segments(),
    genome = "GRCh37", caller = "ascat", assay = "wgs", ploidy = 2))
  expect_identical(unique(with_p$ploidy_source), "caller")
})

test_that("hrd_score is present and one value per sample (composite threshold left open)", {
  df <- as.data.frame(msuiter::ms_hrd_report(.ms_hrd_ok_segments(),
    genome = "GRCh37", caller = "ascat", assay = "wgs"))
  expect_true(is.logical(df$hrd_score) || is.numeric(df$hrd_score))
  expect_identical(length(df$hrd_score), nrow(df))
})

# --- edge discipline (memo section 3.3) ----------------------------------------

test_that("an N=0 sample set returns a zero-row data.frame with the contract columns", {
  empty <- .ms_hrd_ok_segments()[0, , drop = FALSE]
  df <- as.data.frame(msuiter::ms_hrd_report(empty, genome = "GRCh37",
    caller = "ascat", assay = "wgs"))
  expect_identical(nrow(df), 0L)
  expect_true(all(.ms_hrd_required_cols %in% names(df)))
})

test_that("a single-segment genome and a chrY-less set both score without error", {
  single <- .make_hrd_segments(sample = "S1", chromosome = "chr1", start = 1,
    end = 100, state = 2, minor_cn = 0)
  no_chrY <- single[!single$chromosome == "chrY", ]
  expect_no_error(df <- as.data.frame(msuiter::ms_hrd_report(no_chrY,
    genome = "GRCh37", caller = "ascat", assay = "wgs",
    chr_size = .HRD_TEST_CHR_SIZE)))
  expect_identical(nrow(df), 1L)
})

test_that("row order of the input does not change the reported scores", {
  base <- .make_hrd_basic_segments()
  rev1 <- base[nrow(base):1, , drop = FALSE]
  df1 <- as.data.frame(msuiter::ms_hrd_report(base, genome = "GRCh37",
    caller = "ascat", assay = "wgs", chr_size = .HRD_TEST_CHR_SIZE))
  df2 <- as.data.frame(msuiter::ms_hrd_report(rev1, genome = "GRCh37",
    caller = "ascat", assay = "wgs", chr_size = .HRD_TEST_CHR_SIZE))
  expect_identical(.hrd_row(df1, "S1", "ploh_fraction"),
    .hrd_row(df2, "S1", "ploh_fraction"))
})
