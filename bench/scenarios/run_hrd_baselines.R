#!/usr/bin/env Rscript
# run_hrd_baselines.R: R7 competitor-baseline expedition (novelty-scan
# 2026-11-10: "HRD must be benchmarked against HRDetect/SigProfiler-assignment
# on identical inputs"). Plants the six-sample B1-B6 cohort on real GRCh37
# coordinates, scores it with the scarHRD 0.1.1 public face scar_score()
# (reference="grch37") and with ms_hrd_report() under injected sigminer hg19
# geometry, and commits cohort/arms/witness files under out/. The law test
# reads the committed bytes only; scarHRD and sigminer are local expedition
# requirements, never CI dependencies.

.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  if (length(f) > 0L) dirname(normalizePath(f[[1L]])) else normalizePath(getwd())
}
ROOT <- dirname(dirname(.script_dir()))
OUT <- file.path(ROOT, "bench", "scenarios", "out")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(file.path(ROOT, "R"))) {
  suppressWarnings(suppressMessages(pkgload::load_all(ROOT, quiet = TRUE)))
  ns <- asNamespace("msuiter")
  if (exists("as.data.frame.MsHrdReport", envir = ns, inherits = FALSE)) {
    assign("as.data.frame.MsHrdReport", get("as.data.frame.MsHrdReport", envir = ns),
           envir = globalenv())
  }
} else {
  library(msuiter)
}
if (!requireNamespace("scarHRD", quietly = TRUE)) {
  stop("scarHRD 0.1.1 is the competitor face of this expedition; install it first")
}
if (!requireNamespace("sigminer", quietly = TRUE)) {
  stop("sigminer is the local hg19 geometry ground truth for this expedition")
}

HRD_BL_CHR_SIZE <- 2881033286 # exact pLOH denominator (sigminer hg19 law)
BL_CHROMS <- paste0("chr", 1:6)
BL_WRITTEN_PLOIDY <- list(B1 = 2L, B2 = 3L, B3 = 3L, B4 = 2L, B5 = 3L, B6 = 2L)

# --- hg19 geometry from the sigminer ground-truth tables ---------------------------
# chromsize.hg19/centromeres.hg19 carry positional-integer rownames: column-match
# on $chrom, never rowname-subset (measured law).
load_bl_geometry <- function() {
  pkg <- find.package("sigminer")
  if (!length(pkg) || !nzchar(pkg[[1L]])) {
    stop("sigminer ground-truth package not locatable")
  }
  rd <- file.path(pkg[[1L]], "data", "Rdata")
  if (!file.access(rd)) stop("sigminer ground-truth Rdata not readable: ", rd)
  e <- new.env(parent = emptyenv())
  lazyLoad(rd, envir = e)
  cs <- get("chromsize.hg19", envir = e)
  ct <- get("centromeres.hg19", envir = e)
  one <- function(v, ch, what) {
    if (length(v) != 1L || is.na(v)) stop("hg19 ", what, " not unique for ", ch)
    as.integer(v)
  }
  size <- list(); left <- list(); right <- list()
  for (ch in BL_CHROMS) {
    size[[ch]] <- one(cs$size[cs$chrom == ch], ch, "size")
    row <- ct[ct$chrom == ch, , drop = FALSE]
    if (nrow(row) != 1L) stop("hg19 centromere not unique for ", ch)
    left[[ch]] <- one(row$left.base, ch, "centromere left")
    right[[ch]] <- one(row$right.base, ch, "centromere right")
  }
  list(size = size, left.base = left, right.base = right)
}

# --- the planted cohort -------------------------------------------------------------
# Hand-traced scarHRD 0.1.1 goldens (HRD-LOH, Telomeric AI, LST, HRD-sum), derived
# from the verbatim sources; see the law test header for the derivation law.
BL_GOLDENS <- list(
  B1 = c(0L, 0L, 0L, 0L), B2 = c(1L, 1L, 1L, 3L), B3 = c(1L, 1L, 1L, 3L),
  B4 = c(0L, 0L, 0L, 0L), B5 = c(0L, 0L, 0L, 0L), B6 = c(0L, 0L, 0L, 0L))
BL_PLANTED_TRUTH <- list(
  B1 = "clean diploid baseline",
  B2 = "telomeric AI plus partial LOH plus one LST pair; chrX drop-law probe",
  B3 = "interstitial AI plus partial LOH plus one LST pair",
  B4 = "whole-chromosome LOH silenced by the scarHRD chrDel exclusion",
  B5 = "balanced odd state collapsed by shrink to whole-chromosome AI",
  B6 = "six-autosome whole-chrom state-4 LOH: composite-positive, scarHRD-silenced")

.bl_seg <- function(sample, chrom, start, end, state, minor) {
  data.frame(sample = sample, chromosome = chrom, start = as.integer(start),
             end = as.integer(end), state = as.integer(state),
             minor_cn = as.integer(minor), caller = "ascat", assay = "wgs",
             stringsAsFactors = FALSE)
}

build_bl_cohort <- function(geom) {
  if (geom$size$chr1 != 249250621L || geom$size$chr2 != 243199373L ||
      geom$size$chr3 != 198022430L) {
    stop("hg19 sizes drifted from the planted cohort coordinates")
  }
  rows <- list(
    .bl_seg("B1", "chr1", 1, 249250621, 2, 1),
    .bl_seg("B2", "chr2", 1, 120000000, 3, 1),
    .bl_seg("B2", "chr2", 120000001, 243199373, 3, 0),
    .bl_seg("B2", "chrX", 1, 155271560, 2, 1),
    .bl_seg("B3", "chr1", 1, 200000000, 3, 1),
    .bl_seg("B3", "chr1", 200000001, 249250621, 3, 0),
    .bl_seg("B4", "chr3", 1, 198022430, 2, 0),
    .bl_seg("B5", "chr2", 1, 150000000, 3, 1),
    .bl_seg("B5", "chr2", 150000001, 243199373, 3, 1))
  for (ch in BL_CHROMS) {
    rows[[length(rows) + 1L]] <- .bl_seg("B6", ch, 1, geom$size[[ch]], 4, 0)
  }
  do.call(rbind, rows)
}

build_bl_arms <- function(geom) {
  do.call(rbind, lapply(BL_CHROMS, function(ch) {
    data.frame(chrom = c(ch, ch), location = c("p", "q"),
               arm_start = c(1L, geom$right.base[[ch]]),
               arm_end = c(geom$left.base[[ch]], geom$size[[ch]]),
               stringsAsFactors = FALSE)
  }))
}

# --- the scarHRD face ----------------------------------------------------------------
# 8-col TSV grammar (shift law): total, A written first, B, ploidy. A_cn is the
# written major; calc.ai_new groups per-chromosome ploidy by this written column
# (probe-confirmed), so the caller-side major/minor convention carries the signal.
run_bl_scarhrd <- function(cohort, tmp) {
  do.call(rbind, lapply(paste0("B", 1:6), function(s) {
    sub <- cohort[cohort$sample == s, , drop = FALSE]
    tab <- data.frame(sample = sub$sample, chromosome = sub$chromosome,
                      start = sub$start, end = sub$end,
                      total_cn = sub$state, A_cn = sub$state - sub$minor_cn,
                      B_cn = sub$minor_cn, ploidy = BL_WRITTEN_PLOIDY[[s]])
    f <- file.path(tmp, paste0(s, "_bl.tsv"))
    write.table(tab, f, sep = "\t", row.names = FALSE, quote = FALSE)
    r <- scarHRD::scar_score(f, reference = "grch37", chr.in.names = TRUE,
                              m = NULL, seqz = FALSE, outputdir = tmp)
    data.frame(sample = s,
               scarhrd_hrd_loh = as.integer(r[1L, "HRD"]),
               scarhrd_tai = as.integer(r[1L, "Telomeric AI"]),
               scarhrd_lst = as.integer(r[1L, "LST"]),
               scarhrd_hrd_sum = as.integer(r[1L, "HRD-sum"]))
  }))
}

# --- expedition ------------------------------------------------------------------------
verdict <- TRUE
.check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (!ok) verdict <<- FALSE
  cat(sprintf("[%s] %s\n", if (ok) " ok " else "FAIL", label))
}

geom <- load_bl_geometry()
cohort <- build_bl_cohort(geom)
arms <- build_bl_arms(geom)
tmp <- tempfile("hrd-bl-out-"); dir.create(tmp, recursive = TRUE)
scar <- run_bl_scarhrd(cohort, tmp)
msr <- as.data.frame(ms_hrd_report(cohort, genome = "GRCh37", caller = "ascat",
                                   assay = "wgs", chr_size = HRD_BL_CHR_SIZE,
                                   arms = arms, ploidy = 2))
msr <- msr[order(msr$sample), , drop = FALSE]

for (s in paste0("B", 1:6)) {
  got <- as.integer(scar[scar$sample == s, 2:5])
  .check(paste0("scarHRD face speaks the hand-traced goldens for ", s),
         identical(got, BL_GOLDENS[[s]]))
}
.check("exactly one composite HRD call, on the planted double-positive B6",
       identical(as.integer(msr$hrd_score),
                 as.integer(c(0, 0, 0, 0, 0, 1))) &&
         identical(as.character(msr$sample), paste0("B", 1:6)))

witness <- data.frame(
  sample = scar$sample,
  planted_truth = unlist(lapply(scar$sample, function(s) BL_PLANTED_TRUTH[[s]])),
  scarhrd_hrd_loh = scar$scarhrd_hrd_loh, scarhrd_tai = scar$scarhrd_tai,
  scarhrd_lst = scar$scarhrd_lst, scarhrd_hrd_sum = scar$scarhrd_hrd_sum,
  ploh_fraction = as.numeric(msr$ploh_fraction[match(scar$sample, msr$sample)]),
  aneuploidy_count = as.integer(msr$aneuploidy_count[match(scar$sample, msr$sample)]),
  hrd_score = as.integer(msr$hrd_score[match(scar$sample, msr$sample)]),
  geometry_scarhrd = rep("scarHRD 0.1.1 chrominfo_grch37 centromere-snapped arms",
                         nrow(scar)),
  geometry_msuiter = rep(paste0("sigminer hg19 arms; pLOH denominator=",
                                HRD_BL_CHR_SIZE, " (injected)"), nrow(scar)),
  stringsAsFactors = FALSE)

write.table(cohort, file.path(OUT, "hrd_baselines_cohort.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
write.table(arms, file.path(OUT, "hrd_baselines_arms.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
write.csv(witness, file.path(OUT, "hrd_baselines_witness.csv"), row.names = FALSE)

cat(sprintf("== HRD baselines: %s (cohort=%d arms=%d witness=%d; evidence: %s)\n",
            if (verdict) "VERIFIED" else "DEFECT", nrow(cohort), nrow(arms),
            nrow(witness), file.path("bench", "scenarios", "out")), sep = "")
quit(save = "no", status = if (verdict) 0L else 1L)
