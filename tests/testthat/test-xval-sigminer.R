# test-xval-sigminer.R -- M1s acceptance gate, sigminer toy cross-validation
# (bench/xval/run_xval.R, distilled). Guard: msuiter's SBS96 catalog must be
# cell-identical to sigminer 2.x's on a real hg19 window when channels are
# aligned BY LABEL (never by position -- sigminer 2.3.1 happens to share
# msuiter's 5'-context-major order, but label alignment is the contract).
#
# A pure-R recomputation from the same sequence is included as a third
# opinion, so a coincidental two-way agreement cannot pass the test.
#
# Dependency policy: sigminer and BSgenome.Hsapiens.UCSC.hg19 are Suggests
# (the BSgenome data package is ~750 MB) -- both skipped when absent, so CI
# without them pays nothing and the guard runs wherever they exist.

test_that("SBS96 catalog is cell-identical to sigminer (label-aligned xval)", {
  skip_if_not_installed("sigminer")
  skip_if_not_installed("BSgenome.Hsapiens.UCSC.hg19")
  suppressPackageStartupMessages({
    library(sigminer)
    library(BSgenome.Hsapiens.UCSC.hg19)
  })

  # -- toy patch genome: one real hg19 window, verified ACGT-only ------------
  WIN_START <- 1000001L
  WIN_END <- 1050000L
  seq1 <- strsplit(as.character(getSeq(Hsapiens, "chr1",
    WIN_START, WIN_END)), "")[[1L]]
  skip_if_not(all(seq1 %in% c("A", "C", "G", "T")),
    message = "hg19 window contains non-ACGT bases")

  # 2bit writer: same packing contract as helper-tally.R (T=0 C=1 A=2 G=3,
  # first base in the high bits), parameterized; N runs declared as N blocks.
  .write_2bit_xval <- function(path, seqs) {
    u32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "little")
    code <- c(T = 0L, C = 1L, A = 2L, G = 3L)
    pack <- function(bases) {
      b <- code[bases]
      b[is.na(b)] <- 0L
      out <- raw((length(b) + 3L) %/% 4L)
      acc <- 0L
      filled <- 0L
      k <- 0L
      for (x in b) {
        acc <- bitwOr(bitwShiftL(acc, 2L), x)
        filled <- filled + 1L
        if (filled == 4L) {
          k <- k + 1L
          out[k] <- as.raw(acc)
          acc <- 0L
          filled <- 0L
        }
      }
      if (filled > 0L) out[k + 1L] <- as.raw(bitwShiftL(acc, 2L * (4L - filled)))
      out
    }
    recs <- lapply(names(seqs), function(nm) {
      s <- seqs[[nm]]
      is_n <- !(s %in% c("A", "C", "G", "T"))
      nb <- integer(0L)
      nl <- integer(0L)
      if (any(is_n)) {
        r <- rle(is_n)
        st <- cumsum(c(0L, r$lengths))[seq_along(r$lengths)]
        nb <- st[r$values]
        nl <- r$lengths[r$values]
      }
      list(name = nm, size = length(s), dna = pack(s), nb = nb, nl = nl)
    })
    off <- 16L + sum(vapply(recs, function(r) 1L + nchar(r$name) + 4L, 0L))
    index <- raw()
    body <- raw()
    for (r in recs) {
      index <- c(index, as.raw(nchar(r$name)), charToRaw(r$name), u32(off))
      rec <- c(u32(r$size), u32(length(r$nb)), u32(r$nb), u32(r$nl),
        u32(0L), u32(0L), r$dna)
      body <- c(body, rec)
      off <- off + length(rec)
    }
    con <- file(path, "wb")
    on.exit(close(con), add = TRUE)
    writeBin(c(u32(0x1A412743), u32(0L), u32(length(recs)), u32(0L), index, body),
      con)
    invisible(path)
  }

  # -- variant set: one SNV per COSMIC channel (96 total, 3 samples x 32) ----
  # Deterministic: first spaced position (>= 3 bp apart: no adjacent-pair DBS
  # merging, clean +/-1 flanks) matching each channel's full trinucleotide.
  CANON <- character(0L)
  for (t in c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G")) {
    for (f5 in c("A", "C", "G", "T")) {
      for (f3 in c("A", "C", "G", "T")) {
        CANON <- c(CANON, paste0(f5, "[", t, "]", f3))
      }
    }
  }

  L <- length(seq1)
  used <- integer(0L)
  pos <- integer(0L)
  ref <- character(0L)
  alt <- character(0L)
  for (ch in CANON) {
    f5 <- substr(ch, 1L, 1L)
    r <- substr(ch, 3L, 3L)
    a <- substr(ch, 5L, 5L)
    f3 <- substr(ch, 7L, 7L)
    cand <- which(seq1[1:(L - 2L)] == f5 & seq1[2:(L - 1L)] == r &
      seq1[3:L] == f3) + 1L
    cand <- cand[cand >= 3L & cand <= L - 2L]
    cand <- cand[!vapply(cand, function(p) any(abs(used - p) < 3L), logical(1))]
    # Hard failure, not a skip: the window and the pinned BSgenome version are
    # deterministic — a missing context here is a regression (genome/label
    # drift), and skipping would silently disarm the acceptance-gate xval.
    if (length(cand) == 0L) {
      stop(sprintf("context %s not found in the pinned hg19 window (BSgenome drift?)", ch))
    }
    used <- c(used, cand[1L])
    pos <- c(pos, cand[1L])
    ref <- c(ref, r)
    alt <- c(alt, a)
  }
  sample_col <- sprintf("S%d", (seq_along(pos) - 1L) %% 3L + 1L)
  expect_length(pos, 96L)
  expect_identical(as.integer(table(sample_col)), c(32L, 32L, 32L))

  two_bit <- withr::local_tempfile(fileext = ".2bit")
  .write_2bit_xval(two_bit, list(chr1 = seq1))

  # -- msuiter side -----------------------------------------------------------
  # NOTE: window-local coordinates -- the patch 2bit carries only the 50 kb
  # window as its chr1, while sigminer/MP below read the same variants at the
  # real hg19 coordinates through the BSgenome.
  ms_var <- ms_variants(
    data.frame(
      chrom = "chr1",
      start = pos,
      end = pos,
      ref = ref,
      alt = alt,
      sample = sample_col,
      stringsAsFactors = FALSE
    ),
    genome = "hg19-patch(test-xval)", caller = "test-xval",
    matched_normal = "none"
  )
  ms_cat <- ms_tally(ms_var, genome = two_bit, mode = "SBS96")
  mat_ms <- ms_cat@counts
  labs_ms <- as.character(ms_cat@channels$labels)

  # -- naive base-R recomputation (third opinion, from first principles) ------
  mat_nv <- matrix(0L, nrow = 96L, ncol = 3L,
    dimnames = list(CANON, c("S1", "S2", "S3")))
  for (i in seq_along(pos)) {
    lab <- paste0(seq1[pos[i] - 1L], "[", ref[i], ">", alt[i], "]",
      seq1[pos[i] + 1L])
    mat_nv[lab, sample_col[i]] <- mat_nv[lab, sample_col[i]] + 1L
  }

  # -- sigminer side ----------------------------------------------------------
  maf <- read_maf(data.frame(
    Hugo_Symbol = "SYN",
    Tumor_Sample_Barcode = sample_col,
    Chromosome = "chr1",
    Start_Position = WIN_START + pos - 1L,
    End_Position = WIN_START + pos - 1L,
    Reference_Allele = ref,
    Tumor_Seq_Allele2 = alt,
    Variant_Type = "SNP",
    Variant_Classification = "Missense_Mutation",
    stringsAsFactors = FALSE
  ), verbose = FALSE)
  tb <- suppressMessages(sig_tally(maf, mode = "SBS",
    ref_genome = "BSgenome.Hsapiens.UCSC.hg19", genome_build = "hg19",
    keep_only_matrix = TRUE))
  mat_sg <- if (is.matrix(tb) || is.array(tb)) tb else tb$all_matrices$SBS96
  if (ncol(mat_sg) == 96L && nrow(mat_sg) == 3L) {
    mat_sg <- t(mat_sg) # normalize to channels x samples
  }
  labs_sg <- as.character(rownames(mat_sg))

  # -- assertions ---------------------------------------------------------------
  # 1) same 96-label vocabulary, compared as sets first (spelling differences
  #    must surface as a set failure, not as a grid misalignment)
  expect_setequal(labs_ms, labs_sg)
  expect_setequal(labs_ms, CANON)

  # 2) totals: every record counted exactly once, per sample
  expect_identical(as.integer(colSums(mat_ms)), rep(32L, 3L))
  expect_identical(as.integer(colSums(mat_sg)), rep(32L, 3L))
  expect_identical(as.integer(colSums(mat_nv)), rep(32L, 3L))

  # 3) the grid: cell-identical after label alignment (the acceptance gate)
  align <- function(mat, labels) {
    out <- mat[match(CANON, labels), c("S1", "S2", "S3"), drop = FALSE]
    storage.mode(out) <- "integer"
    out
  }
  expect_identical(align(mat_ms, labs_ms), align(mat_sg, labs_sg))

  # 4) anti-false-agreement: the same grid against a from-scratch recomputation
  expect_identical(align(mat_ms, labs_ms), align(mat_nv, CANON))

  # 5) coverage proof: one targeted SNV per channel means the naive grid is
  #    0/1 everywhere and every one of the 96 channels is exercised
  expect_true(all(mat_nv %in% c(0L, 1L)))
  expect_true(all(rowSums(mat_nv) == 1L))

  # 6) order audit: sigminer 2.3.1 shares msuiter's 5'-context-major channel
  #    order (documented xval finding, bench/xval/result.md). Not part of the
  #    contract -- assertion 3 is label-aligned -- but recorded so an upstream
  #    reorder is noticed rather than silently absorbed.
  expect_equal(labs_ms, labs_sg)
})
