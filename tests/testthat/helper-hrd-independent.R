# helper-hrd-independent.R -- the SECOND, INDEPENDENT derivation of the HRD
# sub-scores for the dual-derivation cross-adjudication (novelty-scan §4 R8).
#
# Provenance: read from the published classifier definitions of Cortes-Castro
# et al., "Development of a Bioinformatic Method to Identify Homologous
# Recombination Deficiency in Cancer Genomes" (Cancer Research, 2020): pLOH is
# the fraction of the autosome genome carried in loss-of-heterozygosity, and
# aneuploidy counts the autosome arms whose measured copy burden departs from
# the modal ploidy. NO file of the implementation lineage behind the shipping
# verbatim face was consulted for this derivation; the independence is also
# enforced mechanically by test-hrd-independent.R, which scans this file for
# any symbol of that lineage (a scan the header itself must survive).
#
# ADJUDICATION TABLE -- the published definitions leave these readings open;
# each choice is made here EXPLICITLY and is probed at its boundary by the
# law test, so the two derivations can never part silently:
#   (1) segment widths are CLOSED intervals: width = end - start + 1.
#   (2) the LOH reading folds the minor copy first: minor' = min(total - minor,
#       minor); a segment is in LOH iff total >= 1 AND minor' == 0.
#   (3) a segment spanning a chromosome's arm table end to end contributes
#       half its copy number to each arm (0.5/0.5 split), not full weight per
#       arm; otherwise the arm fraction is the closed overlap over the closed
#       arm length.
#   (4) the acrocentric p-arm blacklist (13,14,15,21,22) is consulted ONLY
#       under the explicit opt-in; a chromosome whose only touched arm is a
#       blacklisted p-arm under the opt-in is skipped, not scored.
#   (5) NA handling: pLOH drops rows missing start/end/state/minor (the fold
#       is undefined without any of them); the arm scan drops rows missing
#       start/end/state only (the copy burden needs no minor column).
#   (6) the autosome universe is chr1..chr22 under the "chr" prefix.

.HI_AUTOSOMES <- paste0("chr", 1:22)
.HI_BLACKLIST_P_ARMS <- c(13L, 14L, 15L, 21L, 22L)

# Paper definition, adjudications (1), (2), (5-pLOH), (6): the fraction of
# the injected autosome-genome denominator carried in LOH.
.hrd_ind_ploh <- function(segments, chr_size) {
  seg <- segments[segments$chromosome %in% .HI_AUTOSOMES, , drop = FALSE]
  seg <- seg[!(is.na(seg$start) | is.na(seg$end) | is.na(seg$state) |
                is.na(seg$minor_cn)), , drop = FALSE]
  seg$minor_cn <- pmin(seg$state - seg$minor_cn, seg$minor_cn)
  loh <- seg[seg$state >= 1L & seg$minor_cn == 0L, , drop = FALSE]
  sum(loh$end - loh$start + 1L) / chr_size
}

# Paper definition, adjudications (1), (3), (4), (5-arms), (6): count the
# touched autosome arms whose measured copy burden departs from the modal
# ploidy after rounding.
.hrd_ind_aneuploidy_count <- function(segments, arms, ploidy,
                                      rm_black_arms = FALSE) {
  samples <- unique(segments$sample)
  out <- vapply(samples, function(s) {
    segs <- segments[segments$sample == s &
                       segments$chromosome %in% .HI_AUTOSOMES, , drop = FALSE]
    segs <- segs[!(is.na(segs$start) | is.na(segs$end) |
                     is.na(segs$state)), , drop = FALSE]
    count <- 0L
    for (chrom in .HI_AUTOSOMES) {
      cs <- segs[segs$chromosome == chrom, , drop = FALSE]
      if (nrow(cs) == 0L) next
      ca <- arms[arms$chrom == chrom, , drop = FALSE]
      if (nrow(ca) == 0L) next
      p_lo <- min(ca$arm_start[ca$location == "p"])
      q_hi <- max(ca$arm_end[ca$location == "q"])
      spans_all <- any(cs$start <= p_lo & cs$end >= q_hi)
      total <- 0
      touched <- FALSE
      for (i in seq_len(nrow(cs))) {
        for (j in seq_len(nrow(ca))) {
          loc <- ca$location[j]
          if (rm_black_arms &&
              as.integer(sub("chr", "", chrom)) %in% .HI_BLACKLIST_P_ARMS &&
              loc == "p") {
            next
          }
          ov <- min(cs$end[i], ca$arm_end[j]) -
                max(cs$start[i], ca$arm_start[j]) + 1L
          if (ov <= 0L) next
          fr <- if (spans_all) 0.5 else
            ov / (ca$arm_end[j] - ca$arm_start[j] + 1L)
          total <- total + cs$state[i] * fr
          touched <- TRUE
        }
      }
      if (!touched) next
      if (as.integer(round(total - ploidy[1L])) != 0L) count <- count + 1L
    }
    count
  }, integer(1))
  unname(out)
}
