# Shared fixtures and the verbatim ground-truth reference used by the
# U-M6s-01 ms_hrd_report() RED batch (test-hrd-report.R, test-hrd-reference.R).
#
# The reference functions below are byte-for-byte re-implementations of the
# two Cortes-Castro HRD scores as captured in the design memo
# docs/devlog/2026-10-07-m6s-hrd-report-design.md, section 1 -- whose single
# ground truth is cran/SigMiner R/get_pLOH_score.R and R/get_Aneuploidy_score.R.
# They are the oracle the golden tests compare ms_hrd_report() against. When
# upstream drifts, the verbatim blocks here and the report's own copy
# (R/hrd-reference.R, to land in the GREEN batch) must move together -- the
# same doctrine as test-channels-reference.R for catalog coefficients.
#
# Everything in this file is synthetic: no refdb, no network, no genome
# package. Reference geometry that would otherwise be genome-derived
# (the pLOH denominator and the aneuploidy arm table) is INJECTED by the
# tests as an explicit argument, so no biological constant is invented here;
# the report and the oracle consume the identical injected value.

# --- verbatim anchors (design memo section 1) --------------------------------

# autosome-only: rm_chrs = c("chrX","chrY")
.HRD_RM_CHRS <- c("chrX", "chrY")

# autosomes 1..22 (aneuploidy is defined over 1..22)
.HRD_AUTOSOMES <- paste0("chr", 1:22)

# the five allele-specific callers on the report whitelist
.HRD_CALLERS <- c("battenberg", "ascat", "facets", "purple", "sequenza")

# blacklisted acrocentric p-arms, optional via rm_black_arms. The memo names
# these as P-ARMS (the task text said "chromosome"); the memo is authoritative
# (section 1, "blacklisted p-arms 13,14,15,21,22"), so this is the p-arm set.
.HRD_BLACKLIST_PARMS <- c(13L, 14L, 15L, 21L, 22L)

# a fixed test denominator so the pLOH score is a hand-checkable number; both
# the oracle and the report receive this exact value through the API.
.HRD_TEST_CHR_SIZE <- 1000000

# --- canonical segment table (design memo section 2 column contract) ---------
# columns: sample, chromosome, start, end, state (integer CN), minor_cn,
# caller, assay. start/end are 1-based closed bp.

.make_hrd_segments <- function(sample, chromosome, start, end, state, minor_cn,
                               caller = "ascat", assay = "wgs") {
  data.frame(
    sample = sample,
    chromosome = chromosome,
    start = as.integer(start),
    end = as.integer(end),
    state = as.integer(state),
    minor_cn = as.integer(minor_cn),
    caller = caller,
    assay = assay,
    stringsAsFactors = FALSE
  )
}

# Two-sample fixture with hand-derived pLOH goldens.
#
#   sample S1 (autosome-only, chr_size = .HRD_TEST_CHR_SIZE):
#     A chr1    1..100  state2 minor0  fold pmin(2,0)=0   -> LOH, len 100
#     B chr1    200..249 state3 minor3 fold pmin(0,3)=0   -> LOH, len  50 (major==0 caught by the pmin fold)
#     C chr1    300..329 state4 minor2 fold pmin(2,2)=2   -> not LOH (balanced)
#     D chr1    400..409 state0 minor0 state>=1 fails     -> not LOH (homdel)
#     E chr2    1..1    state1 minor0  fold pmin(1,0)=0   -> LOH, len   1 (>=1 boundary, +1 length convention)
#     X chrX    1..1000 state2 minor0  autosome-only      -> EXCLUDED (would add 1000 if counted)
#     Y chrY    1..2000 state1 minor0  autosome-only      -> EXCLUDED (would add 2000 if counted)
#   LOH total 151 bp -> ploh_fraction = 151 / 1e6 = 0.000151
#
#   sample S2:
#     F chr1 1..500   state1 minor0 -> LOH, len 500
#     G chr1 600..799 state3 minor1 fold pmin(2,1)=1 -> not LOH
#     H chr1 NA..NA   state2 minor0 -> NA, dropped (never error)
#   LOH total 500 bp -> ploh_fraction = 500 / 1e6 = 0.0005
.make_hrd_basic_segments <- function() {
  rbind(
    .make_hrd_segments(
      sample = rep("S1", 7),
      chromosome = c("chr1", "chr1", "chr1", "chr1", "chr2", "chrX", "chrY"),
      start = c(1, 200, 300, 400, 1, 1, 1),
      end = c(100, 249, 329, 409, 1, 1000, 2000),
      state = c(2, 3, 4, 0, 1, 2, 1),
      minor_cn = c(0, 3, 2, 0, 0, 0, 0)
    ),
    .make_hrd_segments(
      sample = rep("S2", 3),
      chromosome = rep("chr1", 3),
      start = c(1, 600, NA),
      end = c(500, 799, NA),
      state = c(1, 3, 2),
      minor_cn = c(0, 1, 0)
    )
  )
}

.HRD_PLOH_GOLDEN <- c(S1 = 151 / .HRD_TEST_CHR_SIZE, S2 = 500 / .HRD_TEST_CHR_SIZE)

# whole-chromosome segment spanning both arms of chr1 (see .hrd_arms_chr1).
.make_hrd_whole_chrom <- function(state, sample = "S1", chrom = "chr1") {
  # arm spans are 1..500000 (p) and 500001..1000000 (q) for chr1.
  .make_hrd_segments(
    sample = sample, chromosome = chrom, start = 1, end = 1000000,
    state = state, minor_cn = 0L
  )
}

# single arm-only segment (for the blacklisted 13p differential).
.make_hrd_arm_segment <- function(state, sample, chrom, arm_start, arm_end,
                                  start, end) {
  .make_hrd_segments(
    sample = sample, chromosome = chrom, start = start, end = end,
    state = state, minor_cn = 0L
  )
}

# aneuploidy arm geometry, INJECTED so no centromere position is invented.
.hrd_arms_chr1 <- function() {
  data.frame(
    chrom = c("chr1", "chr1"),
    location = c("p", "q"),
    arm_start = c(1L, 500001L),
    arm_end = c(500000L, 1000000L),
    stringsAsFactors = FALSE
  )
}
.hrd_arms_chr13 <- function() {
  data.frame(
    chrom = c("chr13", "chr13"),
    location = c("p", "q"),
    arm_start = c(1L, 200001L),
    arm_end = c(200000L, 800000L),
    stringsAsFactors = FALSE
  )
}
.hrd_arms_both <- function() rbind(.hrd_arms_chr1(), .hrd_arms_chr13())

# Read one report field for one sample from the as.data.frame() face. The
# report's row-labelling is not fixed by the memo, so the contract tests key on
# a `sample` column rather than assuming row names equal sample ids.
.hrd_row <- function(df, sample, column) {
  i <- which(df$sample == sample)
  if (!length(i)) return(NA)
  df[[column]][[i[1L]]]
}

# --- verbatim reference: pLOH --------------------------------------------------
# verbatim cran/SigMiner R/get_pLOH_score.R semantics (memo section 1):
#   autosome-only (rm_chrs chrX,chrY); minor_cn <- pmin(segVal-minor, minor);
#   LOH when segVal >= 1 & folded minor == 0; score = sum(end-start+1)/chr_size.
.hrd_ref_ploh <- function(segments, chr_size = .HRD_TEST_CHR_SIZE) {
  seg <- segments[segments$chromosome %in% .HRD_AUTOSOMES, , drop = FALSE]
  seg <- seg[!(is.na(seg$start) | is.na(seg$end) |
               is.na(seg$state) | is.na(seg$minor_cn)), , drop = FALSE]
  # verbatim LOH-multiplicity fold: pmin(segVal - minor_cn, minor_cn)
  seg$minor_cn <- pmin(seg$state - seg$minor_cn, seg$minor_cn)
  loh <- seg[seg$state >= 1L & seg$minor_cn == 0L, , drop = FALSE]
  sum(loh$end - loh$start + 1L) / chr_size
}

# --- verbatim reference: aneuploidy -------------------------------------------
# verbatim flag expression (memo section 1):
#   flag = as.integer(round(sum(segVal * fraction) - ploidy[1]))
.hrd_ref_aneuploidy_flag <- function(segVal, fraction, ploidy) {
  as.integer(round(sum(segVal * fraction) - ploidy[1L]))
}

# verbatim whole-chromosome split: p,q each receive fraction/2.
.hrd_ref_whole_chrom_arms <- function(fraction = 1) {
  list(p = fraction / 2, q = fraction / 2)
}

# per-sample aneuploidy count = number of autosomes whose per-arm flag != 0.
.hrd_ref_aneuploidy_count <- function(segments, arms, ploidy,
                                      rm_black_arms = FALSE) {
  samples <- unique(segments$sample)
  out <- vapply(samples, function(s) {
    segs <- segments[segments$sample == s &
                       segments$chromosome %in% .HRD_AUTOSOMES, , drop = FALSE]
    segs <- segs[!(is.na(segs$start) | is.na(segs$end) | is.na(segs$state)), ,
                 drop = FALSE]
    count <- 0L
    for (chrom in .HRD_AUTOSOMES) {
      cs <- segs[segs$chromosome == chrom, , drop = FALSE]
      if (nrow(cs) == 0L) next
      ca <- arms[arms$chrom == chrom, , drop = FALSE]
      if (nrow(ca) == 0L) next
      # whole-chromosome detection: some segment spans both arms end to end
      p_start <- min(ca$arm_start[ca$location == "p"])
      q_end <- max(ca$arm_end[ca$location == "q"])
      is_whole <- any(cs$start <= p_start & cs$end >= q_end)
      total <- 0
      covered <- character(0)
      for (i in seq_len(nrow(cs))) {
        for (j in seq_len(nrow(ca))) {
          loc <- ca$location[j]
          if (rm_black_arms && as.integer(sub("chr", "", chrom)) %in% .HRD_BLACKLIST_PARMS &&
              loc == "p") next
          ov <- min(cs$end[i], ca$arm_end[j]) - max(cs$start[i], ca$arm_start[j]) + 1L
          if (ov <= 0L) next
          fr <- if (is_whole) 0.5 else ov / (ca$arm_end[j] - ca$arm_start[j] + 1L)
          total <- total + cs$state[i] * fr
          covered <- c(covered, loc)
        }
      }
      if (length(covered) == 0L) next
      if (.hrd_ref_aneuploidy_flag(total, 1, ploidy) != 0L) count <- count + 1L
    }
    count
  }, integer(1))
  unname(out) # positional per-sample vector; tests compare single-sample scalars
}
