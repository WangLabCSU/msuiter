# run_xval.R -- M1s acceptance gate: toy cross-validation of msuiter's SBS96
# tallying against sigminer and (optional) MutationalPatterns, plus a pure-R
# naive recomputation as an anti-"false agreement" third opinion.
#
# Design (docs/research/04 section 1, SPMG semantics):
#   * A toy "patch genome" is cut from REAL hg19 (BSgenome.Hsapiens.UCSC.hg19,
#     required by both sigminer and MutationalPatterns; msuiter reads the same
#     sequence through its own 2bit path -- one reference, three readers).
#   * 264 SNVs across 3 chromosomes x 3 samples: one targeted variant for each
#     of the 96 COSMIC channels (so every channel cell is exercised, not just
#     the dense ones) plus 168 seeded random SNVs. Minimum same-chromosome
#     spacing 3 bp keeps +/-1 flanks unambiguous and out of DBS-merge and
#     context-contamination territory.
#   * Engines compared cell-by-cell AFTER aligning by channel label (spelling/
#     order differences must never produce phantom agreement or phantom noise).
#   * The naive tally is recomputed from first principles in base R from the
#     same extracted sequence: agreement of three independent implementations
#     is the methodology guard against a coincidental match.
#
# Run: Rscript bench/xval/run_xval.R   (writes artifacts next to this script)

## ---------------------------------------------------------------- setup ----

.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  if (length(f) > 0L) dirname(normalizePath(f)) else normalizePath(getwd())
}
ROOT <- dirname(dirname(.script_dir()))
OUT <- file.path(ROOT, "bench", "xval")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

.message <- function(...) cat(sprintf(...), "\n", sep = "")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(file.path(ROOT, "R"))) {
  pkgload::load_all(ROOT, quiet = TRUE)
} else {
  library(msuiter)
}
suppressPackageStartupMessages({
  library(sigminer)
  library(BSgenome.Hsapiens.UCSC.hg19)
})

.message("msuiter: %s | sigminer: %s | R %s",
  tryCatch(as.character(pkgload::inst_pack_version(ROOT)),
    error = function(e) "dev-load"),
  as.character(packageVersion("sigminer")), getRversion()
)

SEED <- 20260928L
set.seed(SEED)

## ------------------------------------------------- toy reference genome ----
# Three real hg19 windows; asserted ACGT-only (no N) so both context paths
# see the identical sequence. The windows become the whole chromosomes of the
# 2bit patch genome on the msuiter side.

regions <- data.frame(
  chrom = c("chr1", "chr7", "chr12"),
  start = c(1000001L, 55000001L, 10000001L),
  end = c(1200000L, 55250000L, 10100000L),
  stringsAsFactors = FALSE
)

.seq_of <- function(r) {
  s <- as.character(BSgenome::getSeq(Hsapiens, r$chrom, r$start, r$end))
  strsplit(s, "")[[1L]]
}
seqs <- setNames(lapply(seq_len(nrow(regions)), function(i) .seq_of(regions[i, ])),
  regions$chrom)
stopifnot(all(vapply(seqs, function(s) all(s %in% c("A", "C", "G", "T")), logical(1))))
.message("patch genome: %s (ACGT-only verified)",
  paste0(sprintf("%s:%d-%d(%dkb)", regions$chrom, regions$start, regions$end,
    (regions$end - regions$start + 1L) %/% 1000L), collapse = " "))

# 2bit writer: same packing contract as tests/testthat/helper-tally.R
# (T=0 C=1 A=2 G=3, first base in the high bits), generalized to arbitrary
# sequences; N runs are emitted as N blocks (none expected here).
.write_2bit <- function(path, seqs) {
  u32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "little")
  code <- c(T = 0L, C = 1L, A = 2L, G = 3L)
  pack <- function(bases) {
    b <- code[bases]
    b[is.na(b)] <- 0L # non-ACGT packs as zero and is declared as N below
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
    if (filled > 0L) {
      out[k + 1L] <- as.raw(bitwShiftL(acc, 2L * (4L - filled)))
    }
    out
  }
  n_blocks <- function(bases) {
    is_n <- !(bases %in% c("A", "C", "G", "T"))
    if (!any(is_n)) return(list(nb = integer(0), nl = integer(0)))
    r <- rle(is_n)
    st <- cumsum(c(0L, r$lengths))[seq_len(length(r$lengths))] # 0-based starts
    list(nb = st[r$values], nl = r$lengths[r$values])
  }
  recs <- lapply(names(seqs), function(nm) {
    s <- seqs[[nm]]
    blk <- n_blocks(s)
    list(name = nm, size = length(s), dna = pack(s),
      nb = blk$nb, nl = blk$nl)
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
two_bit <- file.path(OUT, "patch_hg19.2bit")
.write_2bit(two_bit, seqs)
stopifnot(file.size(two_bit) > 0L)

## ------------------------------------------------------ toy variant set ----
# 96 targeted (one per COSMIC channel, sample = cycling S1..S3) + 168 random
# = 264 SNVs; min same-chromosome spacing 3 bp across ALL samples.

CANON <- character(0L)
for (t in c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G"))
  for (f5 in c("A", "C", "G", "T"))
    for (f3 in c("A", "C", "G", "T"))
      CANON <- c(CANON, paste0(f5, "[", t, "]", f3))
stopifnot(length(CANON) == 96L) # COSMIC order: 3' fastest, 5' second, type major

.chrom_of_channel <- function(ch) { # channel -> region to search, spread around
  k <- match(ch, CANON)
  regions$chrom[((k - 1L) %% 3L) + 1L]
}
.sample_of_channel <- function(ch) {
  k <- match(ch, CANON)
  sprintf("S%d", ((k - 1L) %% 3L) + 1L)
}

used <- new.env(parent = emptyenv()) # chrom -> sorted positions
.too_close <- function(ch, pos, gap = 3L) {
  u <- used[[ch]]
  length(u) > 0L && any(abs(u - pos) < gap)
}
.keep <- function(ch, pos) {
  used[[ch]] <- sort(c(used[[ch]], pos))
}

rows <- list()
add_row <- function(ch, pos, ref, alt, sample) {
  stopifnot(!.too_close(ch, pos))
  .keep(ch, pos)
  rows[[length(rows) + 1L]] <<- data.frame(
    chrom = ch, pos = pos, ref_ = ref, alt = alt, sample = sample,
    stringsAsFactors = FALSE
  )
}

# targeted pass: first (seeded-shuffled) unused position matching the full
# trinucleotide, searched in the channel's home region with wraparound
for (ch in CANON) {
  f5 <- substr(ch, 1L, 1L)
  ref <- substr(ch, 3L, 3L)
  alt <- substr(ch, 5L, 5L)
  f3 <- substr(ch, 7L, 7L)
  chr <- .chrom_of_channel(ch)
  s <- seqs[[chr]]
  L <- length(s)
  # center i runs 2..L-1: 5' flank s[i-1], center s[i], 3' flank s[i+1]
  cand <- which(s[1:(L - 2L)] == f5 & s[2:(L - 1L)] == ref &
    s[3:L] == f3) + 1L
  cand <- sample(cand) # seeded
  hit <- cand[!vapply(cand, function(p) .too_close(chr, p), logical(1))]
  if (length(hit) == 0L) stop("no position for channel ", ch)
  add_row(chr, hit[1L], ref, alt, .sample_of_channel(ch))
}

# random pass to 264 (center must be a pyrimidine: all variants stay SNVs with
# unambiguous pyrimidine-oriented channels; alts seeded over the 3 options)
while (length(rows) < 264L) {
  chr <- sample(regions$chrom, 1L)
  s <- seqs[[chr]]
  p <- sample(2L:(length(s) - 1L), 1L)
  if (s[p] %in% c("C", "T") && !.too_close(chr, p)) {
    alt <- sample(setdiff(c("A", "C", "G", "T"), s[p]), 1L)
    add_row(chr, p, s[p], alt, sprintf("S%d", (length(rows) %% 3L) + 1L))
  }
}

variants <- do.call(rbind, rows)
variants$global_start <- integer(nrow(variants))
for (i in seq_len(nrow(regions))) {
  m <- variants$chrom == regions$chrom[i]
  variants$global_start[m] <- regions$start[i] + variants$pos[m] - 1L
}
variants <- variants[order(variants$chrom, variants$global_start), ]
rownames(variants) <- NULL

per_sample <- table(factor(variants$sample, levels = c("S1", "S2", "S3")))
.message("variants: %d SNVs | per sample S1=%d S2=%d S3=%d | min spacing 3bp",
  nrow(variants), per_sample[["S1"]], per_sample[["S2"]], per_sample[["S3"]])
stopifnot(nrow(variants) == 264L, per_sample[["S1"]] > 60L)

# ref-allele integrity against the (real hg19) sequence we extracted
.ref_ok <- mapply(function(ch, p, r) seqs[[ch]][p] == r,
  variants$chrom, variants$pos, variants$ref_)
stopifnot(all(.ref_ok))

write.csv(variants[, c("chrom", "global_start", "ref_", "alt", "sample")],
  file.path(OUT, "variants.csv"), row.names = FALSE)

ms_table <- data.frame(
  chrom = variants$chrom,
  start = variants$pos, # region-local: the 2bit patch carries only the windows
  end = variants$pos,
  ref = variants$ref_,
  alt = variants$alt,
  sample = variants$sample,
  stringsAsFactors = FALSE
)

## ------------------------------------------------------- msuiter engine ----
ms_var <- ms_variants(ms_table, genome = "hg19-patch(bench/xval)",
  caller = "bench-xval", matched_normal = "none")
ms_cat <- ms_tally(ms_var, genome = two_bit, mode = "SBS96")
mat_ms <- ms_cat@counts
stopifnot(is.matrix(mat_ms), nrow(mat_ms) == 96L)
labs_ms <- ms_cat@channels$labels
.message("msuiter: %d channels x %d samples (%s)", nrow(mat_ms),
  ncol(mat_ms), paste(colnames(mat_ms), collapse = ","))

## ------------------------------------------------------ sigminer engine ----
maf_df <- data.frame(
  Hugo_Symbol = "SYN",
  Tumor_Sample_Barcode = variants$sample,
  Chromosome = variants$chrom,
  Start_Position = variants$global_start,
  End_Position = variants$global_start,
  Reference_Allele = variants$ref_,
  Tumor_Seq_Allele2 = variants$alt,
  Variant_Type = "SNP",
  Variant_Classification = "Missense_Mutation",
  stringsAsFactors = FALSE
)
mat_sg <- tryCatch({
  maf <- read_maf(maf_df, verbose = FALSE)
  tb <- suppressMessages(sig_tally(maf, mode = "SBS",
    ref_genome = "BSgenome.Hsapiens.UCSC.hg19", genome_build = "hg19",
    keep_only_matrix = TRUE))
  # keep_only_matrix=TRUE returns the matrix directly (samples x channels);
  # a list-shaped return carries it in $SBS96 / $all_matrices$SBS96.
  if (is.matrix(tb) || is.array(tb)) tb else if (!is.null(tb$SBS96)) tb$SBS96 else tb$all_matrices$SBS96
}, error = function(e) {
  .message("sig_tally() failed (%s); trying internal generate_matrix_SBS",
    conditionMessage(e))
  sigminer:::generate_matrix_SBS(maf_df,
    BSgenome::getBSgenome("BSgenome.Hsapiens.UCSC.hg19"), genome_build = "hg19")
})
if (!is.matrix(mat_sg)) mat_sg <- as.matrix(mat_sg)
if (ncol(mat_sg) == 96L && nrow(mat_sg) == 3L) {
  mat_sg <- t(mat_sg) # engine convention: msuiter keeps channels x samples
}
.message("sigminer: %d channels x %d samples (%s)", nrow(mat_sg),
  ncol(mat_sg), paste(colnames(mat_sg), collapse = ","))

## -------------------------------------------------- MutationalPatterns -----
mat_mp <- NA
mp_status <- "not run"
if (requireNamespace("MutationalPatterns", quietly = TRUE) &&
  requireNamespace("Biostrings", quietly = TRUE)) {
  mp_status <- tryCatch({
    suppressPackageStartupMessages({
      library(MutationalPatterns)
      library(Biostrings)
    })
    grl <- GenomicRanges::GRangesList(lapply(c("S1", "S2", "S3"), function(sm) {
      m <- variants$sample == sm
      gr <- GenomicRanges::GRanges(variants$chrom[m],
        IRanges::IRanges(variants$global_start[m], variants$global_start[m]),
        strand = "*",
        ref = Biostrings::DNAStringSet(variants$ref_[m]),
        # VCF-style ALT (one element per record): MP 3.20.1's
        # .find_substitution does width(unlist(alt)) and crashes on a plain
        # DNAStringSet (unlist -> DNAString has no width method).
        alt = as(Biostrings::DNAStringSet(variants$alt[m]),
          "DNAStringSetList"))
      GenomeInfoDb::genome(gr) <- "hg19"
      gr
    }))
    names(grl) <- c("S1", "S2", "S3")
    mm <- mut_matrix(grl, BSgenome::getBSgenome("BSgenome.Hsapiens.UCSC.hg19"))
    if (!is.matrix(mm)) mm <- as.matrix(mm)
    mat_mp <<- mm
    paste0("MutationalPatterns ", packageVersion("MutationalPatterns"))
  }, error = function(e) paste0("MP failed: ", conditionMessage(e)))
} else {
  mp_status <- "MutationalPatterns not installed (optional; skipped)"
}
.message("MutationalPatterns: %s", mp_status)

## ------------------------------------------------- naive base-R engine -----
# From first principles: fold each SNV to the pyrimidine orientation using the
# extracted sequence itself; no package code involved.
naive_labels <- CANON
mat_nv <- matrix(0L, nrow = 96L, ncol = 3L,
  dimnames = list(naive_labels, c("S1", "S2", "S3")))
revc <- c(A = "T", C = "G", G = "C", T = "A")
for (i in seq_len(nrow(variants))) {
  s <- seqs[[variants$chrom[i]]]
  p <- variants$pos[i]
  f5 <- s[p - 1L]
  ref <- s[p]
  alt <- variants$alt[i]
  f3 <- s[p + 1L]
  if (ref %in% c("G", "A")) { # complement-flip to pyrimidine orientation
    f5 <- revc[[f3]]
    f3 <- revc[[s[p - 1L]]]
    ref <- revc[[ref]]
    alt <- revc[[alt]]
  }
  lab <- paste0(f5, "[", ref, ">", alt, "]", f3)
  mat_nv[lab, variants$sample[i]] <- mat_nv[lab, variants$sample[i]] + 1L
}

## --------------------------------------------------------- comparison ------
engines <- list(
  msuiter = list(mat = mat_ms, labels = labs_ms),
  sigminer = list(mat = mat_sg, labels = rownames(mat_sg)),
  naiveR = list(mat = mat_nv, labels = naive_labels)
)
if (is.matrix(mat_mp)) engines[["MutationalPatterns"]] <-
  list(mat = mat_mp, labels = rownames(mat_mp))

names(engines) <- ifelse(names(engines) == "MutationalPatterns", "MP", names(engines))

# 1) label-set and order audit (spelling/order differences would otherwise
#    be invisible or phantom); msuiter's order is the reference frame
.message("\n== channel label audit (order reference: msuiter) ==")
lab_report <- data.frame()
ref_order <- as.character(engines[["msuiter"]]$labels)
for (nm in names(engines)) {
  lab_report <- rbind(lab_report, data.frame(
    engine = nm,
    n_labels = length(engines[[nm]]$labels),
    set_eq_msuiter = identical(sort(as.character(engines[[nm]]$labels)), sort(ref_order)),
    order_eq_msuiter = identical(as.character(engines[[nm]]$labels), ref_order)
  ))
}
print(lab_report, row.names = FALSE)
extra <- unique(unlist(lapply(engines, function(e) setdiff(e$labels, ref_order))))
missing <- unique(unlist(lapply(engines, function(e) setdiff(ref_order, e$labels))))
if (length(extra)) .message("labels not in msuiter set: %s",
  paste(extra, collapse = ", "))
if (length(missing)) .message("msuiter labels missing: %s",
  paste(missing, collapse = ", "))

# 2) per-sample totals and per-class totals
.message("\n== totals audit ==")
totals <- sapply(engines, function(e) colSums(e$mat[, colnames(e$mat), drop = FALSE]))
per_sample_vec <- as.integer(per_sample[c("S1", "S2", "S3")])
names(per_sample_vec) <- c("S1", "S2", "S3")
common_cols <- Reduce(intersect, lapply(engines, function(e) colnames(e$mat)))
print(t(totals[common_cols, , drop = FALSE]))
.message("input per sample: S1=%d S2=%d S3=%d", per_sample_vec[1],
  per_sample_vec[2], per_sample_vec[3])

classes <- substr(CANON, 3L, 5L)
.class_totals <- function(e) {
  idx <- match(CANON, engines[[e]]$labels)
  m <- engines[[e]]$mat[idx, , drop = FALSE] # rows now in CANON order
  storage.mode(m) <- "numeric"
  rowsum(m, group = classes) # classes is CANON-ordered, matching m's rows
}
ctab <- sapply(names(engines), function(e) as.numeric(rowSums(.class_totals(e))))
rownames(ctab) <- rownames(.class_totals(names(engines)[1]))
print(ctab)

# 3) cell-by-cell identity, label-aligned
.message("\n== cell-by-cell identity (label-aligned) ==")
eng <- names(engines)
pairs <- combn(eng, 2L, simplify = FALSE)
mismatch_total <- 0L
for (pr in pairs) {
  a <- engines[[pr[1]]]
  b <- engines[[pr[2]]]
  cols <- intersect(colnames(a$mat), colnames(b$mat))
  ia <- match(CANON, a$labels)
  ib <- match(CANON, b$labels)
  ma <- a$mat[ia, cols, drop = FALSE]
  mb <- b$mat[ib, cols, drop = FALSE]
  mode(ma) <- "integer"
  mode(mb) <- "integer"
  d <- ma != mb
  n <- sum(d)
  mismatch_total <- mismatch_total + n
  .message("%s vs %s: %s (%d x %d cells)",
    pr[1], pr[2], if (n == 0L) "IDENTICAL" else sprintf("%d MISMATCH(ES)", n),
    nrow(ma), length(cols))
  if (n > 0L) {
    w <- which(d, arr.ind = TRUE)
    diff <- data.frame(channel = CANON[w[, "row"]], sample = cols[w[, "col"]],
      a = ma[w], b = mb[w])
    diff$pair <- paste(pr, collapse = "~")
    write.csv(diff, file.path(OUT, "diff_cells.csv"), row.names = FALSE)
    print(head(diff, 20L), row.names = FALSE)
  }
}

# 4) coverage proof for the anti-false-agreement argument: every channel cell
#    type is exercised (each channel hit in at least one sample by construction;
#    verify empirically on the naive matrix)
.message("\n== coverage: %d/96 channels hit at least once (targeted pass) ==",
  sum(rowSums(mat_nv) > 0L))
stopifnot(sum(rowSums(mat_nv) > 0L) == 96L)

## ------------------------------- ref-mismatch semantics probe --------------
# msuiter validates REF against the genome and skips mismatches; do the R
# packages? One correct-REF variant and one wrong-REF variant, far apart.
.message("\n== REF-mismatch semantics probe ==")
probe <- data.frame(
  chrom = c("chr1", "chr1"),
  pos = c(10000L, 150000L), # region-local (patch genome coordinates)
  ref_true = sapply(c(10000L, 150000L), function(p) seqs[["chr1"]][p]),
  stringsAsFactors = FALSE
)
probe$ref_claimed <- probe$ref_true
probe$ref_claimed[2L] <- ifelse(probe$ref_true[2L] == "C", "A", "C")
probe$alt <- ifelse(probe$ref_claimed == "C", "G", "T")
probe$sample <- c("S1", "S1")

# msuiter
pv <- ms_variants(data.frame(chrom = probe$chrom, start = probe$pos,
  end = probe$pos, ref = probe$ref_claimed, alt = probe$alt,
  sample = probe$sample, stringsAsFactors = FALSE),
  genome = "probe", caller = "bench-xval", matched_normal = "none")
pc <- tryCatch(ms_tally(pv, genome = two_bit, mode = "SBS96"),
  error = function(e) conditionMessage(e))
if (!is.character(pc)) { # S7 objects fail inherits(); tryCatch errors return character
  pm <- pc@counts
  if (!is.matrix(pm)) pm <- as.matrix(pm)
  lab_of <- function(p, r, a) { # expected channel under "trust the MAF" semantics
    s <- seqs[["chr1"]]
    f5 <- s[p - 1L]; f3 <- s[p + 1L]; ref <- r; alt2 <- a
    if (ref %in% c("G", "A")) { f5b <- revc[[f3]]; f3 <- revc[[s[p-1L]]]; f5 <- f5b; ref <- revc[[ref]]; alt2 <- revc[[alt2]] }
    paste0(f5, "[", ref, ">", alt2, "]", f3)
  }
  c1 <- as.integer(pm[lab_of(probe$pos[1], probe$ref_claimed[1], probe$alt[1]), 1L])
  l2 <- lab_of(probe$pos[2], probe$ref_claimed[2], probe$alt[2])
  c2 <- if (l2 %in% rownames(pm)) as.integer(pm[l2, 1L]) else 0L
  .message("msuiter: counted total=%d; claimed-channel counts: true-ref=%d, wrong-ref=%d (wrong-ref=0 means REF was validated and skipped)",
    as.integer(sum(pm)), c1, c2)
} else {
  .message("msuiter: error -> %s", as.character(pc))
}

# sigminer
pm_sg <- tryCatch({
  mdf <- data.frame(Hugo_Symbol = "SYN", Tumor_Sample_Barcode = probe$sample,
    Chromosome = probe$chrom, Start_Position = regions$start[1] + probe$pos - 1L,
    End_Position = regions$start[1] + probe$pos - 1L,
    Reference_Allele = probe$ref_claimed, Tumor_Seq_Allele2 = probe$alt,
    Variant_Type = "SNP", Variant_Classification = "Missense_Mutation",
    stringsAsFactors = FALSE)
  maf2 <- read_maf(mdf, verbose = FALSE)
  tb2 <- suppressMessages(sig_tally(maf2, mode = "SBS",
    ref_genome = "BSgenome.Hsapiens.UCSC.hg19", genome_build = "hg19",
    keep_only_matrix = TRUE))
  m <- if (is.matrix(tb2) || is.array(tb2)) tb2 else if (!is.null(tb2$SBS96)) tb2$SBS96 else tb2$all_matrices$SBS96
  if (ncol(m) == 96L && nrow(m) <= 3L) m <- t(m)
  total <- sum(m)
  .message("sigminer: counted total=%d (does NOT validate REF vs genome if wrong-ref channel nonzero)", total)
  rw <- which(m[, "S1"] > 0L)
  .message("sigminer hit channels: %s", paste(rownames(m)[rw], m[rw, "S1"], collapse = ", "))
  total
}, error = function(e) { .message("sigminer: error -> %s", conditionMessage(e)); NA })

# MutationalPatterns
if (is.matrix(mat_mp)) tryCatch({
  library(MutationalPatterns); library(Biostrings)
  g2 <- GenomicRanges::GRanges(probe$chrom,
    IRanges::IRanges(regions$start[1] + probe$pos - 1L,
      regions$start[1] + probe$pos - 1L),
    strand = "*", ref = Biostrings::DNAStringSet(probe$ref_claimed),
    alt = as(Biostrings::DNAStringSet(probe$alt), "DNAStringSetList"))
  GenomeInfoDb::genome(g2) <- "hg19"
  mm2 <- mut_matrix(GenomicRanges::GRangesList(probe = g2),
    BSgenome::getBSgenome("BSgenome.Hsapiens.UCSC.hg19"))
  .message("MutationalPatterns: counted total=%d; hit channels: %s",
    sum(mm2), paste(paste(rownames(mm2)[which(mm2 > 0L)], mm2[mm2 > 0L],
      sep = "="), collapse = ", "))
}, error = function(e) .message("MutationalPatterns: error -> %s",
  conditionMessage(e)))

## ------------------------------------------------------------- persist ----
write.csv(round(mat_ms[labs_ms, , drop = FALSE]), file.path(OUT, "counts_msuiter.csv"))
write.csv(round(mat_sg), file.path(OUT, "counts_sigminer.csv"))
write.csv(mat_nv, file.path(OUT, "counts_naiveR.csv"))
if (is.matrix(mat_mp)) write.csv(round(mat_mp), file.path(OUT, "counts_MP.csv"))
write.csv(lab_report, file.path(OUT, "label_audit.csv"), row.names = FALSE)

.message("\nmismatch cells across all pairs: %d", mismatch_total)
.message("artifacts in %s", OUT)
