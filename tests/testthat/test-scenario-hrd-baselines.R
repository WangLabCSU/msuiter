# test-scenario-hrd-baselines.R: R7 competitor-baseline scenario laws
# (novelty-scan 2026-11-10: "HRD must be benchmarked against
# HRDetect/SigProfiler-assignment on identical inputs").
#
# The runner bench/scenarios/run_hrd_baselines.R plants a six-sample cohort on
# real GRCh37 coordinates, scores it with scarHRD's public scar_score() face
# (reference="grch37") and with msuiter's ms_hrd_report() under injected
# real-GRCh37 geometry, and commits the comparison witness plus the planted
# cohort and arm fixtures. This law test never invokes scarHRD: the committed
# scarHRD columns are adjudicated against hand-traced goldens derived from the
# scarHRD 0.1.1 verbatim sources (shift -> preprocess.hrd -> calc.hrd /
# calc.ai_new / calc.lst, per-chromosome ploidy grouped by the written A
# column, centromere geometry from chrominfo_grch37). The msuiter columns are
# adjudicated end to end: the witness must equal a fresh ms_hrd_report()
# scoring of the committed cohort, which must equal the Cortes-Castro dual
# oracles in helper-hrd.R.

.hrd_bl_out <- function() file.path(.ms_root, "bench", "scenarios", "out")
.hrd_bl_root <- function() file.path(.ms_root, "bench", "scenarios")

.hrd_bl_chr_size <- 2881033286 # exact pLOH denominator, sigminer hg19 law
.hrd_bl_chroms <- paste0("chr", 1:6) # planted arm table coverage

# Hand-traced scarHRD 0.1.1 goldens, derived column-by-column from the
# verbatim sources. B1 clean diploid; B2 telomeric AI + partial LOH + LST
# pair (+ chrX drop-law probe); B3 interstitial AI + partial LOH + LST pair;
# B4 whole-chromosome LOH (chrDel exclusion: scarHRD scores nothing);
# B5 balanced odd state collapsed by shrink (whole-chrom AI only);
# B6 six-autosome whole-chrom state-4 LOH: the composite-positive that
# scarHRD's chrDel rule and whole-chrom AI rule both silence.
.hrd_bl_scarhrd_goldens <- function() {
  data.frame(
    sample = paste0("B", 1:6),
    scarhrd_hrd_loh = c(0L, 1L, 1L, 0L, 0L, 0L),
    scarhrd_tai     = c(0L, 1L, 1L, 0L, 0L, 0L),
    scarhrd_lst     = c(0L, 1L, 1L, 0L, 0L, 0L),
    scarhrd_hrd_sum = c(0L, 3L, 3L, 0L, 0L, 0L),
    stringsAsFactors = FALSE
  )
}

.hrd_bl_read <- function(name, sep) {
  read.csv(file.path(.hrd_bl_out(), name), header = TRUE, sep = sep,
           stringsAsFactors = FALSE, check.names = FALSE)
}

.hrd_bl_cohort <- function() {
  c0 <- .hrd_bl_read("hrd_baselines_cohort.tsv", "\t")
  for (k in c("start", "end", "state", "minor_cn")) c0[[k]] <- as.integer(c0[[k]])
  c0
}

.hrd_bl_arms <- function() {
  a <- .hrd_bl_read("hrd_baselines_arms.tsv", "\t")
  for (k in c("arm_start", "arm_end")) a[[k]] <- as.integer(a[[k]])
  a
}

.hrd_bl_witness <- function() .hrd_bl_read("hrd_baselines_witness.csv", ",")

.hrd_bl_report <- function() {
  ms_hrd_report(.hrd_bl_cohort(), genome = "GRCh37", caller = "ascat",
                assay = "wgs", chr_size = .hrd_bl_chr_size,
                arms = .hrd_bl_arms(), ploidy = 2)
}

test_that("the baselines runner stands executable beside its siblings", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.hrd_bl_root(), "run_hrd_baselines.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  expect_match(src, "--file=", fixed = TRUE)   # sibling argv probe pattern
  expect_match(src, "quit(", fixed = TRUE)      # verdict face
  expect_match(src, "scar_score", fixed = TRUE) # competitor public face
  expect_match(src, "ms_hrd_report", fixed = TRUE)
})

test_that("witness carries the hand-traced scarHRD goldens", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  w <- .hrd_bl_witness()
  g <- .hrd_bl_scarhrd_goldens()
  w <- w[order(w$sample), , drop = FALSE]
  expect_identical(as.character(w$sample), g$sample)
  for (k in c("scarhrd_hrd_loh", "scarhrd_tai", "scarhrd_lst",
              "scarhrd_hrd_sum")) {
    expect_identical(as.integer(w[[k]]), g[[k]], info = k)
  }
})

test_that("msuiter columns agree end to end with the dual oracles", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  w <- .hrd_bl_witness()
  w <- w[order(w$sample), , drop = FALSE]
  rows <- as.data.frame(.hrd_bl_report())
  rows <- rows[order(rows$sample), , drop = FALSE]
  expect_identical(as.character(rows$sample), as.character(w$sample))
  segs <- .hrd_bl_cohort()
  for (i in seq_len(nrow(rows))) {
    s <- rows$sample[i]
    sub <- segs[segs$sample == s, , drop = FALSE]
    expect_equal(as.numeric(w$ploh_fraction[i]),
                 as.numeric(rows$ploh_fraction[i]), tolerance = 1e-12)
    expect_identical(as.integer(w$aneuploidy_count[i]),
                     as.integer(rows$aneuploidy_count[i]))
    expect_equal(rows$ploh_fraction[i],
                 .hrd_ref_ploh(sub, .hrd_bl_chr_size), tolerance = 1e-12)
    expect_identical(as.integer(rows$aneuploidy_count[i]),
                     .hrd_ref_aneuploidy_count(sub, .hrd_bl_arms(), 2,
                                               rm_black_arms = FALSE))
  }
})

test_that("the planted composite arm fires exactly one HRD call", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  w <- .hrd_bl_witness()
  w <- w[order(w$sample), , drop = FALSE]
  # Only B6 is double-positive (pLOH >= 0.4 AND aneuploidy >= 4); every
  # scarHRD-silenced row is a single-estimand row, never a composite call.
  expect_identical(as.integer(w$hrd_score), c(0L, 0L, 0L, 0L, 0L, 1L))
})

test_that("geometry attribution columns name each tool's own coordinates", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  w <- .hrd_bl_witness()
  expect_true(all(grepl("grch37", w$geometry_scarhrd, fixed = TRUE)))
  expect_true(all(grepl("2881033286", w$geometry_msuiter, fixed = TRUE)))
  expect_true(all(grepl("chrominfo", w$geometry_scarhrd, fixed = TRUE)))
})

test_that("the arm fixture is self-consistent with the planted cohort spans", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  a <- .hrd_bl_arms()
  c0 <- .hrd_bl_cohort()
  expect_identical(sort(unique(as.character(a$chrom))),
                   sort(.hrd_bl_chroms))
  for (ch in .hrd_bl_chroms) {
    arm <- a[a$chrom == ch, , drop = FALSE]
    expect_identical(nrow(arm), 2L)
    p <- arm[arm$location == "p", , drop = FALSE]
    q <- arm[arm$location == "q", , drop = FALSE]
    expect_identical(as.integer(p$arm_start), 1L)
    span <- c0[c0$chromosome == ch, , drop = FALSE]
    expect_identical(as.integer(q$arm_end), max(span$end))
    expect_true(q$arm_start > p$arm_end)
  }
})
