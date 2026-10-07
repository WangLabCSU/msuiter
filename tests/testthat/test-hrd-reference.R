# test-hrd-reference.R -- U-M6s-01 RED batch, per-digit reference fidelity.
#
# Ground-truth anchoring (design memo docs/devlog/2026-10-07-m6s-hrd-report-design.md
# section 1, "Ground-truth provenance"). The single ground truth is
# cran/SigMiner R/get_pLOH_score.R and R/get_Aneuploidy_score.R -- the
# Cortes-Castro et al. HRD implementation carried by the SigProfiler-suite
# SigMiner tool (there is no *hrd* file; HRD analysis IS these two scores).
# The verbatim expressions replayed here, from memo section 1:
#
#   pLOH        : segVal >= 1 & folded minor_cn == 0,
#                 folded minor <- pmin(segVal - minor_cn, minor_cn),
#                 autosome-only (rm_chrs = c("chrX","chrY")),
#                 score = sum(end - start + 1) / chr_size
#   aneuploidy  : flag = as.integer(round(sum(segVal * fraction) - ploidy[1])),
#                 arm-level p/q, whole-chrom arms split p,q with fraction/2,
#                 autosome 1..22, blacklisted p-arms {13,14,15,21,22},
#                 ploidy from get_cn_ploidy(data) when ploidy_df is NULL,
#                 genome_build hg19 (msuiter build = GRCh37)
#
# This is a RED batch: ms_hrd_report() is not yet implemented (the GREEN batch
# is next), so every test_that errors on the msuiter::ms_hrd_report() call and
# is therefore red by construction. The verbatim oracle helpers live in
# helper-hrd.R; reference geometry (pLOH denominator, arm table, ploidy) is
# INJECTED through the API so no biological constant is fabricated here.

# --- pLOH fidelity -----------------------------------------------------------

test_that("pLOH fraction is byte-identical to the SigMiner oracle on both samples", {
  # Arrange
  segs <- .make_hrd_basic_segments()
  expected <- .hrd_ref_ploh(segs[segs$sample == "S1", ], .HRD_TEST_CHR_SIZE)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    segs, genome = "GRCh37", caller = "ascat", assay = "wgs",
    chr_size = .HRD_TEST_CHR_SIZE
  ))

  # Assert -- against the oracle AND the hand-derived golden
  expect_identical(.hrd_row(rep1, "S1", "ploh_fraction"), expected)
  expect_identical(.hrd_row(rep1, "S1", "ploh_fraction"), .HRD_PLOH_GOLDEN[["S1"]])
  expect_identical(.hrd_row(rep1, "S2", "ploh_fraction"), .HRD_PLOH_GOLDEN[["S2"]])
})

test_that("pLOH is autosome-only: chrX and chrY segments never enter the score", {
  # Arrange -- the S1 rows with the sex-chromosome segments *pretending* to be
  # autosomal: this is the (wrong) number we must NOT get if the filter leaked
  basic <- .make_hrd_basic_segments()
  s1 <- basic[basic$sample == "S1", ]
  s1_leak <- s1
  s1_leak$chromosome <- sub("^chr([XY])$", "chr1", s1_leak$chromosome)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    basic, genome = "GRCh37", caller = "ascat", assay = "wgs",
    chr_size = .HRD_TEST_CHR_SIZE
  ))

  # Assert -- reported S1 equals the S1-only oracle (sex rows excluded) and is
  # strictly below the value it would take if chrX/chrY had been folded in.
  expect_identical(.hrd_row(rep1, "S1", "ploh_fraction"),
    .hrd_ref_ploh(s1, .HRD_TEST_CHR_SIZE))
  expect_true(.hrd_row(rep1, "S1", "ploh_fraction") <
    .hrd_ref_ploh(s1_leak, .HRD_TEST_CHR_SIZE))
})

test_that("the pmin fold classifies a major==0 segment (segVal==minor) as LOH", {
  # Arrange -- segment B: segVal 3, minor 3 -> major 0, folded minor 0 => LOH
  seg <- .make_hrd_segments(sample = "Z", chromosome = "chr1", start = 200,
    end = 249, state = 3, minor_cn = 3)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    seg, genome = "GRCh37", caller = "facets", assay = "wgs",
    chr_size = .HRD_TEST_CHR_SIZE
  ))

  # Assert -- a naive minor==0-only filter would score 0; the fold scores 50 bp
  expect_identical(.hrd_row(rep1, "Z", "ploh_fraction"),
    50 / .HRD_TEST_CHR_SIZE)
  expect_identical(.hrd_row(rep1, "Z", "ploh_fraction"),
    .hrd_ref_ploh(seg, .HRD_TEST_CHR_SIZE))
})

test_that("pLOH honours the segVal>=1 floor and the +1 closed-interval length", {
  # Arrange -- segment spans a single bp at segVal 1 -> closed length 1
  seg <- .make_hrd_segments(sample = "Z", chromosome = "chr2", start = 1,
    end = 1, state = 1, minor_cn = 0)
  # a homdel at segVal 0 must stay out (floor), ruling out a bare minor==0 filter
  homdel <- .make_hrd_segments(sample = "Z", chromosome = "chr2", start = 1,
    end = 1000, state = 0, minor_cn = 0)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    rbind(seg, homdel), genome = "GRCh37", caller = "purple", assay = "wgs",
    chr_size = .HRD_TEST_CHR_SIZE
  ))

  # Assert -- +1 gives length 1 (not 0); the segVal>=1 floor keeps homdel out
  expect_identical(.hrd_row(rep1, "Z", "ploh_fraction"),
    1 / .HRD_TEST_CHR_SIZE)
})

test_that("pLOH drops NA segments and never errors on them", {
  # Arrange -- two real LOH segments plus one NA row (memo section 3.3: drop, no error)
  segs <- rbind(
    .make_hrd_segments(sample = "Z", chromosome = "chr1", start = 1, end = 500,
      state = 1, minor_cn = 0), # LOH, closed length 500
    .make_hrd_segments(sample = "Z", chromosome = "chr1", start = 900,
      end = 1100, state = 2, minor_cn = 0), # LOH, closed length 201
    .make_hrd_segments(sample = "Z", chromosome = "chr1", start = NA,
      end = NA, state = 2, minor_cn = 0) # NA coordinate -> dropped
  )

  # Act
  expect_no_error(rep1 <- as.data.frame(msuiter::ms_hrd_report(
    segs, genome = "GRCh37", caller = "sequenza", assay = "wgs",
    chr_size = .HRD_TEST_CHR_SIZE
  )))

  # Assert -- the NA row contributes nothing; both real LOH segments still count
  expect_identical(.hrd_row(rep1, "Z", "ploh_fraction"),
    701 / .HRD_TEST_CHR_SIZE)
})

# --- aneuploidy fidelity -----------------------------------------------------

test_that("aneuploidy flag matches the verbatim round(sum(segVal*fraction)-ploidy) rule", {
  # Arrange -- whole-chromosome chr1 at three copy numbers, caller ploidy 2
  gain <- .make_hrd_whole_chrom(state = 3, sample = "GAIN")
  diploid <- .make_hrd_whole_chrom(state = 2, sample = "DIP")
  loss <- .make_hrd_whole_chrom(state = 1, sample = "LOSS")

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    rbind(gain, diploid, loss), genome = "GRCh37", caller = "battenberg",
    assay = "wgs", arms = .hrd_arms_chr1(), ploidy = 2
  ))

  # Assert -- per the verbatim flag expression at fraction 1 (whole-chrom p+q
  # reunit to 1): round(3-2)=1 -> GAIN; round(2-2)=0 -> DIP; round(1-2)=-1 ->
  # LOSS. The count is the number of non-zero-flag autosomes.
  expect_identical(.hrd_ref_aneuploidy_flag(3, 1, 2), 1L)
  expect_identical(.hrd_ref_aneuploidy_flag(2, 1, 2), 0L)
  expect_identical(.hrd_ref_aneuploidy_flag(1, 1, 2), -1L)
  expect_identical(.hrd_row(rep1, "GAIN", "aneuploidy_count"), 1L)
  expect_identical(.hrd_row(rep1, "DIP", "aneuploidy_count"), 0L)
  expect_identical(.hrd_row(rep1, "LOSS", "aneuploidy_count"), 1L)
})

test_that("the whole-chromosome arm split divides the fraction evenly by two", {
  # Arrange -- the memo's fraction/2 rule for whole-chrom segments
  split <- .hrd_ref_whole_chrom_arms(1)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    .make_hrd_whole_chrom(state = 2), genome = "GRCh37", caller = "ascat",
    assay = "wgs", arms = .hrd_arms_chr1(), ploidy = 2
  ))

  # Assert -- p and q each carry half; if the /2 were omitted the diploid
  # segment would sum to 4.0 (2 per arm unsplit) and flag gained, not neutral.
  expect_identical(split$p, 0.5)
  expect_identical(split$q, 0.5)
  expect_identical(split$p + split$q, 1)
  expect_identical(.hrd_row(rep1, "S1", "aneuploidy_count"), 0L)
})

test_that("aneuploidy is autosome-only and excludes the sex chromosomes", {
  # Arrange -- a sex-chromosome-only sample must never register aneuploidy
  sex <- .make_hrd_segments(sample = "Z", chromosome = "chrX", start = 1,
    end = 100000, state = 4, minor_cn = 0)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    sex, genome = "GRCh37", caller = "ascat", assay = "wgs",
    arms = .hrd_arms_chr1(), ploidy = 2
  ))

  # Assert -- no autosomes covered -> count zero
  expect_identical(.hrd_row(rep1, "Z", "aneuploidy_count"), 0L)
})

test_that("the blacklisted p-arm roster is the acrocentric set {13,14,15,21,22}", {
  # Arrange -- a 13q-only sample: q-arms are never blacklisted, so the acrocentric
  # exclusion must not touch it and the gain still counts.
  seg13q <- .make_hrd_arm_segment(state = 3, sample = "Q", chrom = "chr13",
    arm_start = 200001, arm_end = 800000, start = 200001, end = 800000)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    seg13q, genome = "GRCh37", caller = "ascat", assay = "wgs",
    arms = .hrd_arms_both(), ploidy = 2, rm_black_arms = TRUE
  ))

  # Assert -- the roster constant, and the q-arm gain survives p-arm blacklisting
  expect_identical(.HRD_BLACKLIST_PARMS, c(13L, 14L, 15L, 21L, 22L))
  expect_false(16L %in% .HRD_BLACKLIST_PARMS) # 16 is NOT acrocentric
  expect_false(17L %in% .HRD_BLACKLIST_PARMS)
  expect_identical(.hrd_ref_aneuploidy_count(seg13q, .hrd_arms_both(), 2, TRUE), 1L)
  expect_identical(.hrd_row(rep1, "Q", "aneuploidy_count"), 1L)
})

test_that("rm_black_arms drops a blacklisted 13p gain from the aneuploidy count", {
  # Arrange -- a single 13p segment that would otherwise flag aneuploid
  seg13 <- .make_hrd_arm_segment(state = 3, sample = "B", chrom = "chr13",
    arm_start = 1, arm_end = 200000, start = 1, end = 200000)
  arms <- .hrd_arms_both()

  # Act
  rep_no <- as.data.frame(msuiter::ms_hrd_report(
    seg13, genome = "GRCh37", caller = "ascat", assay = "wgs",
    arms = arms, ploidy = 2, rm_black_arms = FALSE
  ))
  rep_yes <- as.data.frame(msuiter::ms_hrd_report(
    seg13, genome = "GRCh37", caller = "ascat", assay = "wgs",
    arms = arms, ploidy = 2, rm_black_arms = TRUE
  ))

  # Assert -- oracle first (independent of the report), then the report contract.
  # Blacklist removes the only covered arm, so the 13 row is not scored (0, -2).
  expect_identical(.hrd_ref_aneuploidy_count(seg13, arms, 2, FALSE), 1L)
  expect_identical(.hrd_ref_aneuploidy_count(seg13, arms, 2, TRUE), 0L)
  expect_identical(.hrd_row(rep_no, "B", "aneuploidy_count"), 1L)
  expect_identical(.hrd_row(rep_yes, "B", "aneuploidy_count"), 0L)
})

test_that("aneuploidy consumes ploidy[1] and reports it as caller-provided", {
  # Arrange -- caller-supplied ploidy drives the verbatim flag directly
  seg <- .make_hrd_whole_chrom(state = 3)

  # Act
  rep1 <- as.data.frame(msuiter::ms_hrd_report(
    seg, genome = "GRCh37", caller = "ascat", assay = "wgs",
    arms = .hrd_arms_chr1(), ploidy = 2
  ))

  # Assert -- ploidy[1] is what the flag subtracts; provenance is caller
  expect_identical(.hrd_row(rep1, "S1", "ploidy_source"), "caller")
  expect_identical(.hrd_row(rep1, "S1", "aneuploidy_count"), 1L)
})
