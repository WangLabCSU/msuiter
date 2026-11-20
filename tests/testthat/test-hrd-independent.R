# test-hrd-independent.R -- the independent-reference law units (novelty-scan
# §4 R8: the sigminer-lineage fidelity bar "must be labeled ... until an
# independent reference lands"). The lineage face is R/hrd-reference.R (verbatim
# SigMiner copy) adjudicated by helper-hrd.R's .hrd_ref_* oracle -- one
# implementation family. This unit adds the second, INDEPENDENT derivation
# (helper-hrd-independent.R's .hrd_ind_*): read from the published
# Cortes-Castro et al. 2020 (Cancer Research) classifier definitions, never
# from any SigMiner file, with its conventions named in an adjudication table.
# The two derivations must agree byte-exactly wherever the paper pins the
# reading, and every unpinning convention (interval closure, minor fold,
# blacklist p-arm skip, NA-drop scope) is probed at its boundary and asserted
# identically -- a silent lineage drift trips here before it can reach print.

.hi_chr_size <- 1000000 # the shared fixture denominator scale (helper-hrd.R world)
.hi_r7_chr_size <- 2881033286

.hi_seg <- function(sample, chrom, start, end, state, minor) {
  data.frame(sample = sample, chromosome = chrom, start = as.integer(start),
             end = as.integer(end), state = as.integer(state),
             minor_cn = as.integer(minor), caller = "ascat", assay = "wgs",
             stringsAsFactors = FALSE)
}

# Own-built arm table over five autosome rows (the aneu composite needs
# count >= 4): p=[1, s/2], q=[s/2+1, s] with s = the fixture chromosome size.
.hi_arms <- function() {
  do.call(rbind, lapply(paste0("chr", c(1, 2, 13, 17, 22)), function(ch) {
    data.frame(chrom = c(ch, ch), location = c("p", "q"),
               arm_start = c(1L, .hi_chr_size / 2 + 1L),
               arm_end = c(.hi_chr_size / 2, .hi_chr_size),
               stringsAsFactors = FALSE)
  }))
}

.hi_planted <- function() {
  do.call(rbind, list(
    .hi_seg("P1", "chr1", 1, .hi_chr_size, 5, 0),          # whole LOH, aneu-up
    .hi_seg("P2", "chr1", 1, 400000, 2, 0),                # partial LOH
    .hi_seg("P2", "chr1", 400001, .hi_chr_size, 2, 1),    # balanced rest
    .hi_seg("P3", "chr1", 1, .hi_chr_size, 3, 1),          # aneu-up, no LOH
    .hi_seg("P4", "chr1", 1, .hi_chr_size, 4, 3)))         # the fold trap
}

.hi_r7_cohort <- function() {
  f <- file.path(.ms_root, "bench", "scenarios", "out", "hrd_baselines_cohort.tsv")
  c0 <- read.csv(f, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
  for (k in c("start", "end", "state", "minor_cn")) c0[[k]] <- as.integer(c0[[k]])
  c0
}

test_that("the independent pLOH derivation agrees with the lineage oracle on the planted grammar", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  p <- .hi_planted()
  for (s in unique(as.character(p$sample))) {
    sub <- p[p$sample == s, , drop = FALSE]
    expect_equal(.hrd_ind_ploh(sub, .hi_chr_size),
                 .hrd_ref_ploh(sub, .hi_chr_size), tolerance = 1e-12,
                 info = s)
  }
})

test_that("the independent aneuploidy derivation agrees on the planted grammar", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  p <- .hi_planted()
  for (s in unique(as.character(p$sample))) {
    sub <- p[p$sample == s, , drop = FALSE]
    for (rm_b in c(FALSE, TRUE)) {
      expect_identical(.hrd_ind_aneuploidy_count(sub, .hi_arms(), 2, rm_b),
                       .hrd_ref_aneuploidy_count(sub, .hi_arms(), 2,
                                                 rm_black_arms = rm_b),
                       info = paste0(s, " rm_black_arms=", rm_b))
    }
  }
})

test_that("dual derivation agrees byte-exactly on the R7 committed cohort", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  c0 <- .hi_r7_cohort()
  arms <- read.csv(file.path(.ms_root, "bench", "scenarios", "out",
                             "hrd_baselines_arms.tsv"),
                   header = TRUE, sep = "\t", stringsAsFactors = FALSE)
  arms$arm_start <- as.integer(arms$arm_start)
  arms$arm_end <- as.integer(arms$arm_end)
  for (s in unique(as.character(c0$sample))) {
    sub <- c0[c0$sample == s, , drop = FALSE]
    expect_equal(.hrd_ind_ploh(sub, .hi_r7_chr_size),
                 .hrd_ref_ploh(sub, .hi_r7_chr_size), tolerance = 1e-12,
                 info = s)
    expect_identical(.hrd_ind_aneuploidy_count(sub, arms, 2, FALSE),
                     .hrd_ref_aneuploidy_count(sub, arms, 2, rm_black_arms = FALSE),
                     info = s)
  }
})

test_that("the minor-fold convention is adjudicated identically", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  # state 4, minor 3: folded minor = min(4-3, 3) = 1 -> NOT an LOH under the
  # paper's fold reading; a raw-minor==0 reading would also miss nothing here,
  # so the discriminating row is state 4 minor 4 (folded min(0,4)=0 -> LOH).
  trap <- .hi_seg("T1", "chr1", 1, .hi_chr_size, 4, 3)
  raw <- .hi_seg("T2", "chr1", 1, .hi_chr_size, 4, 4)
  for (s in c("T1", "T2")) {
    sub <- if (s == "T1") trap else raw
    expect_equal(.hrd_ind_ploh(sub, .hi_chr_size),
                 .hrd_ref_ploh(sub, .hi_chr_size), tolerance = 1e-12, info = s)
  }
  expect_true(.hrd_ref_ploh(raw, .hi_chr_size) > 0)
})

test_that("the closed-interval width convention is adjudicated identically", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  full <- .hi_seg("C1", "chr1", 1, .hi_chr_size, 1, 0)
  expect_equal(.hrd_ind_ploh(full, .hi_chr_size), 1, tolerance = 1e-12)
  expect_equal(.hrd_ref_ploh(full, .hi_chr_size), 1, tolerance = 1e-12)
})

test_that("the blacklist p-arm-only skip is adjudicated identically", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  # chr13 covered on its (blacklisted 13) p-arm only: the adjudicated reading
  # SKIPS the chromosome rather than scoring the lone arm.
  solo <- .hi_seg("B1", "chr13", 1, .hi_chr_size / 2, 5, 2)
  for (rm_b in c(FALSE, TRUE)) {
    expect_identical(.hrd_ind_aneuploidy_count(solo, .hi_arms(), 2, rm_b),
                     .hrd_ref_aneuploidy_count(solo, .hi_arms(), 2,
                                               rm_black_arms = rm_b),
                     info = paste0("rm_black_arms=", rm_b))
  }
})

test_that("the NA-drop scope is adjudicated identically", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  good <- .hi_seg("N1", "chr1", 1, 500000, 2, 0)
  bad <- good
  bad$state <- as.integer(NA_integer_)
  sub <- rbind(good, bad)
  expect_equal(.hrd_ind_ploh(sub, .hi_chr_size),
               .hrd_ref_ploh(sub, .hi_chr_size), tolerance = 1e-12)
})

test_that("the independent face shares no lineage symbol and names its source", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "tests", "testthat", "helper-hrd-independent.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(!any(grepl(".hrd_ref", src, fixed = TRUE)))
  expect_true(!any(grepl(".HRD_", src, fixed = TRUE)))
  expect_true(!any(grepl("hrd-reference", src, fixed = TRUE)))
  expect_true(!any(grepl("sigminer", src, fixed = TRUE)))
  expect_match(src, "Cortes-Castro", fixed = TRUE)
})
