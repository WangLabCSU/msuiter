# U-M6s-01 -- the HRD reference layer for ms_hrd_report().
#
# Verbatim ground-truth copy (design memo
# docs/devlog/2026-10-07-m6s-hrd-report-design.md section 1). The single
# ground truth is cran/SigMiner R/get_pLOH_score.R and
# R/get_Aneuploidy_score.R -- the Cortes-Castro et al. HRD implementation
# carried by the SigProfiler-suite SigMiner tool (there is no *hrd* file;
# HRD analysis IS these two scores). Each constant and each expression below
# is a byte-for-byte transcription whose upstream file and function are named
# at the point of use, and the fidelity tests (test-hrd-reference.R) replay
# them against the independent oracle in tests/testthat/helper-hrd.R. When
# upstream drifts, this file and that oracle must move together -- the same
# doctrine as test-channels-reference.R for catalog coefficients.
#
# This file holds DATA and the two scoring KERNELS only; it never invents a
# biological constant that the tests have not injected. Reference geometry
# (the pLOH denominator, the arm table, ploidy) arrives through the public
# API as an injected argument -- see R/hrd-report.R.

# --- data: the frozen upstream constants (memo section 1) --------------------

# autosome-only filter: upstream `rm_chrs = c("chrX","chrY")`; HRD is defined
# over the autosomes chr1..chr22 only.
.HRD_RM_CHRS <- c("chrX", "chrY")
.HRD_AUTOSOMES <- paste0("chr", 1:22)

# the five validated allele-specific callers (memo section 2 gate); the
# whitelist is DATA here, not scattered conditionals (adjudication section 2,
# section 9 -- lowercase labels, caller normalised to lowercase on input).
.HRD_CALLERS <- c("battenberg", "ascat", "facets", "purple", "sequenza")

# blacklisted acrocentric P-ARMS, optional via rm_black_arms (memo section 1;
# adjudication section 7 -- an autosome whose only covered arm is a blacklisted
# p-arm is SKIPPED, not scored). Upstream `rm_black_arms`.
.HRD_BLACKLIST_PARMS <- c(13L, 14L, 15L, 21L, 22L)

# the builds msuiter exposes; the caller names one explicitly (memo section 1
# "msuiter exposes build explicitly, no silent default"). Data, not a
# conditional; anything outside this set is an `msuiter_error_genome`.
.HRD_SUPPORTED_BUILDS <- c("GRCh37", "GRCh38")

# assay modalities accepted by the API; "wes" additionally needs the
# experimental opt-in (memo section 2 WGS-only gate).
.HRD_SUPPORTED_ASSAYS <- c("wgs", "wes")

# The two columns the segment frame must carry for the verbatim scorers
# (sample/chromosome/start/end/state/minor_cn plus the caller/assay
# provenance columns; adjudication section 1 -- seg_median_ratio/tumor_purity/
# cellularity do NOT feed either score and are neither required nor validated).
.HRD_REQUIRED_COLS <- c(
  "sample", "chromosome", "start", "end", "state", "minor_cn", "caller", "assay"
)

# Composite classifier cut-offs (adjudication section 4). hrd_score is 1L iff
# the normalised pLOH fraction >= .HRD_PLOH_CUTOFF AND the autosome-level
# aneuploidy count >= .HRD_ANEU_CUTOFF, both comparisons INCLUSIVE. Provenance:
# the combined pLOH + aneuploidy HRD classifier of Cortes-Castro et al.,
# Cancer Research 2020. TODO(paper): confirm the exact bibliographic record
# (DOI/volume/pages) and that these two thresholds are printed verbatim in the
# paper's methods; the numeric values here are the adjudication memo's
# authoritative pin and are exercised only through the already-fidelity-tested
# sub-scores.
.HRD_PLOH_CUTOFF <- 0.4
.HRD_ANEU_CUTOFF <- 4L

# --- kernel: pLOH (verbatim cran/SigMiner R/get_pLOH_score.R) -----------------
# Upstream, over one sample's segments:
#   autosome-only (rm_chrs chrX,chrY);
#   minor_cn <- pmin(segVal - minor_cn, minor_cn)   # the LOH fold
#   LOH when segVal >= 1 & folded minor_cn == 0
#   score = sum(end - start + 1) / chr_size          # closed-interval length
# `chr_size` is the injected pLOH denominator (no genome-derived default is
# invented here -- see R/hrd-report.R geometry resolution).
hrd_ploh_score <- function(segments, chr_size) {
  seg <- segments[segments$chromosome %in% .HRD_AUTOSOMES, , drop = FALSE]
  seg <- seg[!(is.na(seg$start) | is.na(seg$end) |
               is.na(seg$state) | is.na(seg$minor_cn)), , drop = FALSE]
  seg$minor_cn <- pmin(seg$state - seg$minor_cn, seg$minor_cn)
  loh <- seg[seg$state >= 1L & seg$minor_cn == 0L, , drop = FALSE]
  sum(loh$end - loh$start + 1L) / chr_size
}

# --- kernel: aneuploidy (verbatim cran/SigMiner R/get_Aneuploidy_score.R) ------
# Upstream arm-level flag, replayed per (segment x arm) overlap:
#   whole-chromosome split: a segment spanning both arms end-to-end gives each
#     arm fraction = 0.5 (adjudication section 6: the two half-weight arms
#     reunit to 1.0 per chromosome);
#   else fraction = overlap / arm_length;
#   flag = as.integer(round(sum(segVal * fraction) - ploidy[1]))  per arm;
#   autosome counts once when its flag != 0;
#   blacklisted acrocentric p-arms {13,14,15,21,22} optional via
#   rm_black_arms -- a skipped p-arm contributes nothing (adjudication section 7).
# `arms` (chrom/location/arm_start/arm_end) and `ploidy` are injected.
#
# Returns a per-sample list aligned to unique(segments$sample): the count of
# non-zero-flag autosomes, the number of covered arm-windows scored, and a
# chrom-level detail table (exposed as the `aneuploidy_detail` attribute).
hrd_aneuploidy <- function(segments, arms, ploidy, rm_black_arms = FALSE) {
  samples <- unique(segments$sample)
  n <- length(samples)
  count <- integer(n)
  windows <- integer(n)
  det_sample <- character(0)
  det_chrom <- character(0)
  det_covered <- integer(0)
  det_fraction <- numeric(0)
  det_flag <- integer(0)

  for (idx in seq_len(n)) {
    s <- samples[[idx]]
    segs <- segments[segments$sample == s &
                       segments$chromosome %in% .HRD_AUTOSOMES, , drop = FALSE]
    segs <- segs[!(is.na(segs$start) | is.na(segs$end) | is.na(segs$state)), ,
                 drop = FALSE]
    cnt <- 0L
    win <- 0L
    for (chrom in .HRD_AUTOSOMES) {
      cs <- segs[segs$chromosome == chrom, , drop = FALSE]
      if (nrow(cs) == 0L) next
      ca <- arms[arms$chrom == chrom, , drop = FALSE]
      if (nrow(ca) == 0L) next
      p_start <- min(ca$arm_start[ca$location == "p"])
      q_end <- max(ca$arm_end[ca$location == "q"])
      is_whole <- any(cs$start <= p_start & cs$end >= q_end)
      total <- 0
      covered <- character(0)
      for (i in seq_len(nrow(cs))) {
        for (j in seq_len(nrow(ca))) {
          loc <- ca$location[[j]]
          if (rm_black_arms && as.integer(sub("chr", "", chrom)) %in%
              .HRD_BLACKLIST_PARMS && loc == "p") next
          ov <- min(cs$end[[i]], ca$arm_end[[j]]) -
            max(cs$start[[i]], ca$arm_start[[j]]) + 1L
          if (ov <= 0L) next
          fr <- if (is_whole) 0.5 else
            ov / (ca$arm_end[[j]] - ca$arm_start[[j]] + 1L)
          total <- total + cs$state[[i]] * fr
          covered <- c(covered, loc)
        }
      }
      if (length(covered) == 0L) next
      win <- win + length(covered)
      flg <- as.integer(round(total - ploidy[[1L]]))
      if (flg != 0L) cnt <- cnt + 1L
      det_sample <- c(det_sample, s)
      det_chrom <- c(det_chrom, chrom)
      det_covered <- c(det_covered, length(covered))
      det_fraction <- c(det_fraction, total)
      det_flag <- c(det_flag, flg)
    }
    count[[idx]] <- cnt
    windows[[idx]] <- win
  }

  detail <- data.frame(
    sample = det_sample, chrom = det_chrom, arms_covered = det_covered,
    fraction = det_fraction, flag = det_flag, stringsAsFactors = FALSE
  )
  list(count = unname(count), windows = unname(windows), detail = detail)
}
