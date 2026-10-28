# ms_hrd_report() -- CS-2 scenario law units (03-applications section 4)
# Synthetic cohorts with PLANTED pLOH/aneuploidy ground truth adjudicated
# byte-exact against the verbatim Cortes-Castro dual oracles in
# helper-hrd.R (and through the report, R/hrd-reference.R). The oracles are
# the authority; these units add no scoring semantics of their own.

.hrd_scenario_chr_size <- .HRD_TEST_CHR_SIZE # 1e6, the injected denominator

# Arm geometry over five autosomes (the aneu composite needs count >= 4, so
# the scenario arm table must cover five callable autosomes).
.hrd_scenario_arms <- function() {
  do.call(rbind, lapply(c("chr1", "chr2", "chr13", "chr17", "chr22"), function(ch) {
    data.frame(chrom = c(ch, ch), location = c("p", "q"),
               arm_start = c(1L, .hrd_scenario_chr_size / 2 + 1L),
               arm_end = c(.hrd_scenario_chr_size / 2, .hrd_scenario_chr_size),
               stringsAsFactors = FALSE)
  }))
}

.hrd_whole <- function(sample, chrom, state, minor) {
  .make_hrd_segments(sample, chrom, start = 1L, end = .hrd_scenario_chr_size,
                     state = state, minor_cn = minor)
}

# Planted truths:
#   H1  five autosomes whole-chrom state 5, minor 0: pLOH-heavy AND aneuploid
#       -> composite call (the HRD-positive arm)
#   H2  chr1 partial LOH only                        -> LOH-rich, aneu-poor
#   H3  five autosomes whole-chrom state 3, minor 1  -> aneu-rich, LOH-poor
#   H4  one balanced autosome                        -> clean
.hrd_scenario_segments <- function() {
  rows <- list()
  for (ch in c("chr1", "chr2", "chr13", "chr17", "chr22")) {
    rows[[length(rows) + 1L]] <- .hrd_whole("H1", ch, 5L, 0L)
    rows[[length(rows) + 1L]] <- .hrd_whole("H3", ch, 3L, 1L)
  }
  rows[[length(rows) + 1L]] <- .make_hrd_segments(
    "H2", "chr1", start = 1L, end = 450000L, state = 2L, minor_cn = 0L)
  rows[[length(rows) + 1L]] <- .hrd_whole("H4", "chr1", 2L, 1L)
  do.call(rbind, rows)
}

.hrd_scenario_report <- function(segments = .hrd_scenario_segments(), ...) {
  ms_hrd_report(segments, genome = "GRCh37", caller = "ascat", assay = "wgs",
                chr_size = .hrd_scenario_chr_size,
                arms = .hrd_scenario_arms(), ploidy = 2, ...)
}

.ms_hrd_expect_err <- function(expr, class) {
  expect_error(expr, class = paste0("msuiter_error_", class))
}

test_that("planted adjudications match the dual oracles byte-exact", {
  segs <- .hrd_scenario_segments()
  rep1 <- .hrd_scenario_report(segs)
  rows <- as.data.frame(rep1)
  rows <- rows[order(rows$sample), , drop = FALSE] # first-appearance agnostic
  expect_identical(rows$sample, c("H1", "H2", "H3", "H4"))
  for (i in seq_len(nrow(rows))) {
    s <- rows$sample[i]
    sub <- segs[segs$sample == s, , drop = FALSE]
    expect_identical(rows$ploh_fraction[i],
                     .hrd_ref_ploh(sub, .hrd_scenario_chr_size))
    expect_identical(rows$aneuploidy_count[i],
                     .hrd_ref_aneuploidy_count(sub, .hrd_scenario_arms(),
                                               2, rm_black_arms = FALSE))
  }
  # Composite truth: only the double-positive H1 calls HRD.
  expect_identical(rows$hrd_score, c(1L, 0L, 0L, 0L))
  expect_identical(unique(rows$evidence_tier), "standard")
})

test_that("seeded reruns are byte-identical", {
  a <- as.data.frame(.hrd_scenario_report())
  b <- as.data.frame(.hrd_scenario_report())
  expect_identical(a, b)
  expect_identical(attr(.hrd_scenario_report(), "aneuploidy_detail"),
                   attr(.hrd_scenario_report(), "aneuploidy_detail"))
})

test_that("the print face speaks the provenance and the ledger", {
  out <- paste(capture.output(print(.hrd_scenario_report())), collapse = "\n")
  expect_match(out, "<msuiter HRD report>", fixed = TRUE)
  expect_match(out, "samples=4", fixed = TRUE)
  expect_match(out, "genome=GRCh37", fixed = TRUE)
  expect_match(out, "caller=ascat", fixed = TRUE)
})

test_that("missing geometry degrades to attestation, never fabrication", {
  rep1 <- ms_hrd_report(.hrd_scenario_segments(), genome = "GRCh37",
                        caller = "ascat", assay = "wgs",
                        chr_size = .hrd_scenario_chr_size, ploidy = 2)
  rows <- as.data.frame(rep1)
  expect_true(all(rows$aneuploidy_count == 0L))
  expect_true(all(grepl("no-arm-table", rows$coverage_note, fixed = TRUE)))
  rep2 <- ms_hrd_report(.hrd_scenario_segments(), genome = "GRCh37",
                        caller = "ascat", assay = "wgs",
                        arms = .hrd_scenario_arms(), ploidy = 2)
  rows2 <- as.data.frame(rep2)
  expect_true(all(is.na(rows2$ploh_fraction)))
  expect_true(all(grepl("denominator=absent", rows2$coverage_note,
                        fixed = TRUE)))
  expect_true(all(is.na(rows2$hrd_score)))
})

test_that("the section-4 guardrails speak structured conditions", {
  segs <- .hrd_scenario_segments()
  .ms_hrd_expect_err(
    ms_hrd_report(segs, genome = "GRCh37", caller = "bogus", assay = "wgs",
                  chr_size = .hrd_scenario_chr_size,
                  arms = .hrd_scenario_arms(), ploidy = 2),
    "hrd-caller-whitelist")
  .ms_hrd_expect_err(
    ms_hrd_report(segs, genome = "GRCh37", caller = "ascat", assay = "wes",
                  chr_size = .hrd_scenario_chr_size,
                  arms = .hrd_scenario_arms(), ploidy = 2),
    "hrd-wes-experimental")
})

test_that("the hypermutator exclusion leg pipes end to end", {
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  set.seed(404L)
  counts <- matrix(0L, length(labels), 8L,
                   dimnames = list(labels, paste0("X", 1:8)))
  counts[c(1L, 2L), ] <- matrix(
    as.integer(runif(2 * 8, 200, 400)), 2, 8)
  counts[1L, c(3L, 6L)] <- 8200L # planted hypermutants: an order out
  catalog <- ms_catalog(counts, list(name = "SBS96", labels = labels),
                         colnames(counts),
                         list(genome = "GRCh37", caller = "scenario",
                              matched_normal = "none", stage = "scenario"))
  strat <- ms_stratify_hypermutants(catalog, manual_cutoff = 5000L, seed = 1L)
  expect_true(setequal(c("X3", "X6"), strat@hyper))
  expect_identical(strat@n_hyper, 2)
  p <- plot_hypermutator_burden(strat, show_gmm = FALSE)
  expect_s3_class(p, "ggplot")
  built <- ggplot2::ggplot_build(p)
  expect_true(!is.null(built))
})
