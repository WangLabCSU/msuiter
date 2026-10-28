#!/usr/bin/env Rscript
# bench/scenarios/run_hrd.R -- the executable HRD scoring scenario
# (Phase-8 CS-2; docs/research/03-applications.md section 4). Synthetic
# cohorts carry PLANTED pLOH/aneuploidy truth adjudicated byte-exact against
# the verbatim Cortes-Castro dual oracles (helper-hrd.R is the authority).
# The scenario adds no scoring semantics of its own.

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
} else {
  library(msuiter)
}
source(file.path(ROOT, "tests", "testthat", "helper-hrd.R"))

verdict <- TRUE
.check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (!ok) verdict <<- FALSE
  cat(sprintf("[%s] %s\n", if (ok) " ok " else "FAIL", label))
}
cat("== HRD scenario: start ==\n")

# The planted geometry (same truth as the CS-2 law file): H1 pLOH-heavy and
# aneuploid, H2 LOH-only, H3 aneuploid-only, H4 clean.
chr_size <- .HRD_TEST_CHR_SIZE
arms <- do.call(rbind, lapply(c("chr1", "chr2", "chr13", "chr17", "chr22"),
  function(ch) data.frame(chrom = c(ch, ch), location = c("p", "q"),
    arm_start = c(1L, chr_size %/% 2L + 1L),
    arm_end = c(chr_size %/% 2L, chr_size), stringsAsFactors = FALSE)))
whole <- function(sample, chrom, state, minor) {
  .make_hrd_segments(sample, chrom, start = 1L, end = chr_size,
                     state = state, minor_cn = minor)
}
segs <- do.call(rbind, c(
  lapply(c("chr1", "chr2", "chr13", "chr17", "chr22"),
         function(ch) whole("H1", ch, 5L, 0L)),
  lapply(c("chr1", "chr2", "chr13", "chr17", "chr22"),
         function(ch) whole("H3", ch, 3L, 1L)),
  list(.make_hrd_segments("H2", "chr1", start = 1L, end = 450000L,
                          state = 2L, minor_cn = 0L),
       whole("H4", "chr1", 2L, 1L))))
report <- ms_hrd_report(segs, genome = "GRCh37", caller = "ascat",
                        assay = "wgs", chr_size = chr_size,
                        arms = arms, ploidy = 2)
rows <- as.data.frame(report)
rows <- rows[order(rows$sample), , drop = FALSE]
write.csv(rows, file.path(OUT, "hrd_report.csv"), row.names = FALSE)

oracle_ok <- TRUE
for (i in seq_len(nrow(rows))) {
  s <- rows$sample[i]
  sub <- segs[segs$sample == s, , drop = FALSE]
  oracle_ok <- oracle_ok &&
    identical(rows$ploh_fraction[i],
              .hrd_ref_ploh(sub, .HRD_TEST_CHR_SIZE)) &&
    identical(rows$aneuploidy_count[i],
              .hrd_ref_aneuploidy_count(sub, arms, 2, rm_black_arms = FALSE))
}
.check("adjudications are byte-exact against the dual oracles", oracle_ok)
.check("composite truth: only the double-positive sample calls HRD",
       identical(rows$hrd_score[rows$sample == "H1"], 1L) &&
         all(rows$hrd_score[rows$sample != "H1"] == 0L))
b <- as.data.frame(ms_hrd_report(segs, genome = "GRCh37", caller = "ascat",
                                 assay = "wgs", chr_size = .HRD_TEST_CHR_SIZE,
                                 arms = arms, ploidy = 2))
.check("seeded reruns are byte-identical", identical(rows, b))
printed <- paste(capture.output(print(report)), collapse = "\n")
.check("print face speaks provenance and ledger",
       grepl("<msuiter HRD report>", printed, fixed = TRUE) &&
         grepl("caller=ascat", printed, fixed = TRUE))
degraded <- as.data.frame(ms_hrd_report(segs, genome = "GRCh37",
                                        caller = "ascat", assay = "wgs",
                                        chr_size = .HRD_TEST_CHR_SIZE, ploidy = 2))
.check("missing arm table degrades to attestation, never fabrication",
       all(degraded$aneuploidy_count == 0L) &&
         all(grepl("no-arm-table", degraded$coverage_note, fixed = TRUE)))
cat(sprintf("== HRD scenario: %s == (evidence: %s)\n",
            if (verdict) "OVERALL PASS" else "OVERALL FAIL", OUT))
quit(save = "no", status = if (verdict) 0L else 1L)
