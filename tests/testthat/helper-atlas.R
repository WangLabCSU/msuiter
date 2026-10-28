# Atlas-mode synthetic cohort (Phase-8 CS-1; docs/research/03-applications.md
# section 1). Three-layer generator isolation: (1) TRUTH -- planted signature
# identities and per-sample activities; (2) PLAN -- integer channel counts
# derived from the truth by largest-remainder rounding; (3) EMIT -- canonical
# variant records whose coordinates are valid on a synthetic 2bit genome
# constructed from the served channel labels. No reference numerics are
# committed: profile weights are served from the bundled refdb at call time.
# The 2bit packer is the certified one from helper-tally.R (shared fixture).

.ATLAS_CHRS_SBS <- c("chr1", "chr2")
.ATLAS_CHR_DBS <- "chr3"
.ATLAS_SBS_PERIOD <- 1024L         # 96 channels at stride 4 inside a period
.ATLAS_DBS_PERIOD <- 236L          # 78 adjacent pairs at stride 3 plus a gap
.ATLAS_SLOTS_SBS <- 256L           # corridor positions per sample per channel
.ATLAS_SLOTS_DBS <- 20L
.ATLAS_SAMPLES <- paste0("A", sprintf("%02d", seq_len(24L)))
# Planted identities: three ubiquitous signatures plus two sample-restricted
# ones (the rare leg). Identity only -- weights ride the served refdb. The
# quintet is the min-max-cosine roster (probe-roster-select: max pairwise
# cosine 0.26), so the de novo recall law is a recovery claim, not a
# torture test. SBS3 rides at background level as the association control
# (the first decoy), which keeps its exposure positive and arm-invariant.
.ATLAS_PLANTED <- c("SBS1", "SBS5", "SBS22a", "SBS2", "SBS13")
.ATLAS_COMMON <- c("SBS1", "SBS5", "SBS22a")
.ATLAS_RARE <- c("SBS2", "SBS13")
.ATLAS_DECOY_BG <- "SBS3"
.ATLAS_ACTIVITY_COMMON <- 240
.ATLAS_ACTIVITY_RARE <- 300
.ATLAS_ACTIVITY_DECOY <- 30
# Per-sample activity weights, rotated across signatures: without the
# rotation the columns take only a few distinct shapes, the count matrix
# collapses numerically and five signatures are unrecoverable by any method.
.ATLAS_WVEC <- c(0.75, 1.15, 0.90, 1.25, 0.80, 1.10, 0.95, 1.05, 0.85,
                 1.20, 0.70, 1.00, 1.10, 0.80, 1.20, 0.90, 1.05, 0.75,
                 1.15, 0.85, 0.95, 1.25, 0.70, 1.00)
.atlas_w <- function(k, i) .ATLAS_WVEC[[((i + 5L * k) %% 24L) + 1L]]
.ATLAS_DBS_TOTAL <- 240            # emitted DBS records over a hot roster subset
.ATLAS_ID_N <- 24L                 # ID-carrier records (validator evidence)
.ATLAS_BASE <- c(T = 0L, C = 1L, A = 2L, G = 3L)

.atlas_round_counts <- function(prob, total) {
  raw <- prob * total
  base <- floor(raw)
  left <- total - sum(base)
  if (left > 0L) {
    ord <- order(raw - base, decreasing = TRUE)[seq_len(left)]
    base[ord] <- base[ord] + 1L
  }
  as.integer(base)
}

# Corridor layout: within each period, channel lj owns a fixed offset, and
# sample si owns a fixed slice of periods -- every (sample, channel) cell has
# its own coordinate pool, so cross-record adjacency is impossible by
# construction. Calibration (probe-anchor-calib): the kernel reads the SBS
# context at code[s-1..s+1] for a record with start=s (code is the 1-based
# base vector), so ref bases embed at code[start] onward.
.atlas_center <- function(period, offset, slot) period * slot + offset

.atlas_sbs_offsets <- function(n_labels) 4L * (seq_len(n_labels) - 1L) + 3L
.atlas_dbs_offsets <- function(n_labels) 3L * (seq_len(n_labels) - 1L) + 2L

# SBS96 labels are fixed-format: "L[X>Y]R" (7 characters, position-parsed --
# no regex dependency). Returns the four bases in canonical order.
.atlas_parse_sbs96 <- function(lab) {
  ch <- strsplit(lab, "")[[1L]]
  if (nchar(lab) != 7L || ch[[2L]] != "[" || ch[[4L]] != ">" ||
      ch[[6L]] != "]") {
    stop("unparsable SBS96 label: ", lab, domain = NA)
  }
  list(left = ch[[1L]], ref = ch[[3L]], alt = ch[[5L]], right = ch[[7L]])
}

# Build all three synthetic chromosomes from the served label sets.
.atlas_build_genome <- function(sbs_labels, dbs_labels) {
  parse_sbs <- .atlas_parse_sbs96
  parse_dbs <- function(lab) {
    halves <- strsplit(lab, ">")[[1L]]
    if (nchar(halves[[1L]]) != 2L) stop("unparsable DBS78 label: ", lab, domain = NA)
    list(ref = halves[[1L]], alt = halves[[2L]])
  }
  n_sbs <- length(sbs_labels)
  len_sbs <- .ATLAS_SBS_PERIOD * .ATLAS_SLOTS_SBS * length(.ATLAS_SAMPLES)
  sbs_offsets <- .atlas_sbs_offsets(n_sbs)
  sbs_chrs <- lapply(seq_along(.ATLAS_CHRS_SBS), function(ci) {
    genome <- rep(.ATLAS_BASE[["A"]], len_sbs)
    for (lj in seq_len(n_sbs)) {
      sp <- parse_sbs(sbs_labels[[lj]])
      for (si in seq_along(.ATLAS_SAMPLES)) {
        for (slot in seq_len(.ATLAS_SLOTS_SBS)) {
          p <- .atlas_center(.ATLAS_SBS_PERIOD, sbs_offsets[[lj]],
                             (si - 1L) * .ATLAS_SLOTS_SBS + slot - 1L)
          genome[p - 1L] <- .ATLAS_BASE[[sp$left]]
          genome[p] <- .ATLAS_BASE[[sp$ref]]
          genome[p + 1L] <- .ATLAS_BASE[[sp$right]]
        }
      }
    }
    list(name = .ATLAS_CHRS_SBS[[ci]], size = len_sbs, code = genome)
  })
  n_dbs <- length(dbs_labels)
  len_dbs <- .ATLAS_DBS_PERIOD * .ATLAS_SLOTS_DBS * length(.ATLAS_SAMPLES)
  dbs_offsets <- .atlas_dbs_offsets(n_dbs)
  genome_d <- rep(.ATLAS_BASE[["A"]], len_dbs)
  for (lj in seq_len(n_dbs)) {
    sp <- parse_dbs(dbs_labels[[lj]])
    b1 <- .ATLAS_BASE[[strsplit(sp$ref, "")[[1L]][1L]]]
    b2 <- .ATLAS_BASE[[strsplit(sp$ref, "")[[1L]][2L]]]
    for (si in seq_along(.ATLAS_SAMPLES)) {
      for (slot in seq_len(.ATLAS_SLOTS_DBS)) {
        p <- .atlas_center(.ATLAS_DBS_PERIOD, dbs_offsets[[lj]],
                           (si - 1L) * .ATLAS_SLOTS_DBS + slot - 1L)
        genome_d[p] <- b1
        genome_d[p + 1L] <- b2
      }
    }
  }
  dbs_chr <- list(list(name = .ATLAS_CHR_DBS, size = len_dbs, code = genome_d))
  list(sbs = sbs_chrs, dbs = dbs_chr, len_sbs = len_sbs, len_dbs = len_dbs,
       sbs_offsets = sbs_offsets, dbs_offsets = dbs_offsets)
}

.atlas_write_2bit <- function(path, geo) {
  recs <- lapply(c(geo$sbs, geo$dbs), function(r) {
    list(name = r$name, size = r$size, nb = integer(0), nl = integer(0),
         dna = .tally_pack_bases(r$code))
  })
  .tally_write_bytes(path, .tally_2bit_bytes(recs))
}

# Records: one slice of the corridor per (sample, channel); chromosome
# assignment alternates per label so both SBS corridors carry traffic.
.atlas_emit <- function(plan, geo, sbs_labels, dbs_labels) {
  rows <- list()
  n_chr <- length(.ATLAS_CHRS_SBS)
  for (si in seq_along(.ATLAS_SAMPLES)) {
    sample <- .ATLAS_SAMPLES[[si]]
    for (lj in seq_along(sbs_labels)) {
      n <- plan$sbs[si, lj]
      if (!n) next
      if (n > .ATLAS_SLOTS_SBS) {
        stop("SBS plan cell beyond corridor capacity", domain = NA)
      }
      sp <- .atlas_parse_sbs96(sbs_labels[[lj]])
      chr <- .ATLAS_CHRS_SBS[[(si + lj) %% n_chr + 1L]]
      slots <- seq_len(n)
      pos <- .atlas_center(.ATLAS_SBS_PERIOD, geo$sbs_offsets[[lj]],
                           (si - 1L) * .ATLAS_SLOTS_SBS + slots - 1L)
      rows[[length(rows) + 1L]] <- data.frame(
        chrom = chr, start = pos, end = pos,
        ref = rep(sp$ref, n), alt = rep(sp$alt, n),
        sample = rep(sample, n), stringsAsFactors = FALSE)
    }
    for (lj in seq_along(dbs_labels)) {
      n <- plan$dbs[si, lj]
      if (!n) next
      if (n > .ATLAS_SLOTS_DBS) {
        stop("DBS plan cell beyond corridor capacity", domain = NA)
      }
      halves <- strsplit(dbs_labels[[lj]], ">")[[1L]]
      slots <- seq_len(n)
      pos <- .atlas_center(.ATLAS_DBS_PERIOD, geo$dbs_offsets[[lj]],
                           (si - 1L) * .ATLAS_SLOTS_DBS + slots - 1L)
      # The certified DBS78 shape (golden: "chr2 33/34" pairs into
      # CG>AT): two adjacent single-base records, consumed as one doublet
      # by the ledger routing -- a 2-mer MNV record would divert to the
      # long_mnv/complex bucket instead.
      bs <- c(strsplit(halves[[1L]], "")[[1L]], strsplit(halves[[2L]], "")[[1L]])
      st <- as.vector(rbind(pos, pos + 1L))
      rows[[length(rows) + 1L]] <- data.frame(
        chrom = rep(.ATLAS_CHR_DBS, 2L * n), start = st, end = st,
        ref = rep(bs[1L:2L], n), alt = rep(bs[3L:4L], n),
        sample = rep(sample, 2L * n), stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(chrom = character(), start = integer(),
                      end = integer(), ref = character(),
                      alt = character(), sample = character(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# ID-carrier records: one-bp deletion and insertion shapes, parked in the
# far tail of the DBS corridor genome where no tallied record lives (the
# public API has no ID83 tally mode -- the scenario attests this gap).
.atlas_id_records <- function(len_dbs) {
  base <- len_dbs - 4L * .ATLAS_ID_N
  data.frame(
    chrom = rep(.ATLAS_CHR_DBS, .ATLAS_ID_N),
    start = base + 2L * seq_len(.ATLAS_ID_N),
    end = base + 2L * seq_len(.ATLAS_ID_N) + rep(c(1L, 0L), .ATLAS_ID_N / 2L),
    ref = rep(c("AC", "A"), .ATLAS_ID_N / 2L),
    alt = rep(c("A", "AT"), .ATLAS_ID_N / 2L),
    sample = rep(.ATLAS_SAMPLES, each = .ATLAS_ID_N %/% length(.ATLAS_SAMPLES)),
    stringsAsFactors = FALSE)
}

# PCAWG-shaped CN records and the SV record set (class-ingestion evidence).
.atlas_cn_table <- function() {
  n <- length(.ATLAS_SAMPLES)
  data.frame(
    chromosome = rep(.ATLAS_CHRS_SBS[1L], 2L * n),
    chromosome_start = rep(c(1L, .ATLAS_SBS_PERIOD), n),
    chromosome_end = rep(c(.ATLAS_SBS_PERIOD - 1L, 2L * .ATLAS_SBS_PERIOD), n),
    copy_number = rep(c(1L, 3L), n),
    mutation_type = rep(c("loss", "gain"), n),
    sample = rep(.ATLAS_SAMPLES, each = 2L),
    stringsAsFactors = FALSE)
}
.atlas_sv_table <- function() {
  n <- length(.ATLAS_SAMPLES)
  data.frame(
    chrom1 = rep(.ATLAS_CHRS_SBS[1L], n),
    start1 = rep(501L, n), end1 = rep(4500L, n),
    chrom2 = rep(.ATLAS_CHRS_SBS[2L], n),
    start2 = rep(100001L, n), end2 = rep(104999L, n),
    svclass = rep("deletion", n),
    sample = .ATLAS_SAMPLES,
    stringsAsFactors = FALSE)
}

# The full cohort: truth, plan, emitted variant table and on-disk 2bit.
.atlas_cohort <- function(seed = 4242L,
                          dir = file.path(tempdir(), "msuiter-atlas-fixture")) {
  dir.create(dir, showWarnings = FALSE)
  twobit <- file.path(dir, "synth.2bit")
  refdb <- ms_refdb_bundled(build = "GRCh37")
  sbs_mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  sbs_labels <- rownames(sbs_mat)
  dbs_labels <- if (!is.null(refdb[["DBS_GRCh37"]]))
    rownames(refdb[["DBS_GRCh37"]]@matrices[[1L]]) else
      msuiter:::.ms_io_channel_tables()$DBS78
  if (!all(c(.ATLAS_PLANTED, .ATLAS_DECOY_BG) %in% colnames(sbs_mat))) {
    stop("the bundled roster lacks a planted identity", domain = NA)
  }
  # ---- layer 1: truth
  sigs <- c(.ATLAS_PLANTED, .ATLAS_DECOY_BG)
  arm <- ifelse(seq_along(.ATLAS_SAMPLES) <= 12L, "g1", "g2")
  activity <- matrix(
    0, nrow = length(sigs), ncol = length(.ATLAS_SAMPLES),
    dimnames = list(sigs, .ATLAS_SAMPLES))
  for (k in seq_along(sigs)) {
    sig <- sigs[[k]]
    base <- if (identical(sig, "SBS5")) {
      ifelse(arm == "g1", 520, 180) # the planted arm differential
    } else if (sig %in% .ATLAS_COMMON) {
      rep(.ATLAS_ACTIVITY_COMMON, length(.ATLAS_SAMPLES))
    } else if (sig %in% .ATLAS_RARE) {
      # Disjoint carrier windows: rare signatures sharing one activation
      # column would be numerically inseparable, whatever the extraction.
      j <- which(.ATLAS_RARE == sig)
      ifelse(seq_along(.ATLAS_SAMPLES) > (j - 1L) * 3L &
             seq_along(.ATLAS_SAMPLES) <= j * 3L, .ATLAS_ACTIVITY_RARE, 0)
    } else if (identical(sig, .ATLAS_DECOY_BG)) {
      rep(.ATLAS_ACTIVITY_DECOY, length(.ATLAS_SAMPLES))
    } else {
      stop("unknown planted signature", domain = NA)
    }
    w <- vapply(seq_along(.ATLAS_SAMPLES), function(i) .atlas_w(k, i),
                numeric(1))
    activity[sig, ] <- base * w
  }
  # ---- layer 2: plan
  sbs_plan <- matrix(
    0L, nrow = length(.ATLAS_SAMPLES), ncol = length(sbs_labels),
    dimnames = list(.ATLAS_SAMPLES, sbs_labels))
  for (si in seq_along(.ATLAS_SAMPLES)) {
    probs <- rowSums(sbs_mat[, sigs, drop = FALSE] *
                       rep(activity[, .ATLAS_SAMPLES[[si]]], each = nrow(sbs_mat)))
    total <- sum(probs)
    sbs_plan[si, ] <- .atlas_round_counts(probs / total, as.integer(round(total)))
  }
  dbs_plan <- matrix(
    0L, nrow = length(.ATLAS_SAMPLES), ncol = length(dbs_labels),
    dimnames = list(.ATLAS_SAMPLES, dbs_labels))
  hot <- seq_len(min(12L, length(dbs_labels)))
  dbs_weights <- seq_along(hot)
  for (si in seq_along(.ATLAS_SAMPLES)) {
    w <- dbs_weights * ((si %% 5L) + 1L)
    dbs_plan[si, hot] <- .atlas_round_counts(
      w / sum(w), .ATLAS_DBS_TOTAL %/% length(.ATLAS_SAMPLES))
  }
  # ---- layer 3: emit
  geo <- .atlas_build_genome(sbs_labels, dbs_labels)
  .atlas_write_2bit(twobit, geo)
  variants <- .atlas_emit(list(sbs = sbs_plan, dbs = dbs_plan),
                          geo, sbs_labels, dbs_labels)
  list(
    dir = dir, twobit = twobit, variants = variants,
    id_records = .atlas_id_records(geo$len_dbs),
    cn_table = .atlas_cn_table(), sv_table = .atlas_sv_table(),
    truth = list(samples = .ATLAS_SAMPLES, signatures = .ATLAS_PLANTED,
                 common = .ATLAS_COMMON, rare = .ATLAS_RARE,
                 arm = arm,
                 activity = activity, sbs_plan = sbs_plan,
                 dbs_plan = dbs_plan, sbs_labels = sbs_labels,
                 dbs_labels = dbs_labels)
  )
}
