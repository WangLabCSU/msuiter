# test-scenario-qc-artifacts.R -- the CS-4 artifact-forensics law units
# (pillar 3). The scenario adjudicates the built-in mechanism sentries and
# the artifact-roster share against a self-planted synthetic cohort
# (D3: planted truth only): spiked C>A (oxoG-reading) and C>T (FFPE
# deamination) samples must be caught at recall 1, sub-threshold roster
# controls and clean samples must speak the silence branches, and a dead
# sample must speak the NA branch. The witness bytes under
# bench/scenarios/out/ are the committed verdict; this unit re-derives
# them from the committed plant through the public faces -- a drift
# between runner, faces, or evidence reddens here before print.
# Framing law (novelty-scan R6): methods-demonstration only; the declined
# Degasperi amber/red tiering and any diagnostic-grade (MUTYH/MSI) wording
# are out of scope by law, mirroring the declined list at
# R/ms-qc-sentries.R:13-20.

.qa_out <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.qa_tsv <- function(fname) {
  read.csv(.qa_out(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE)
}

.qa_csv <- function(fname) {
  read.csv(.qa_out(fname), header = TRUE, stringsAsFactors = FALSE)
}

.qa_samples <- paste0("QC", formatC(1:13, width = 2L, flag = "0"))
.qa_gt_planted <- paste0("QC", formatC(1:4, width = 2L, flag = "0"))
.qa_ct_planted <- paste0("QC", formatC(5:8, width = 2L, flag = "0"))
.qa_clean <- paste0("QC", formatC(9:12, width = 2L, flag = "0"))
.qa_dead <- "QC13"
.qa_roster_planted <- paste0("QC", formatC(1:4, width = 2L, flag = "0"))

test_that("the CS-4 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  f <- file.path(.ms_root, "bench", "scenarios", "run_qc_artifacts.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  for (face in c("ms_qc_sentries", "ms_qc_roster_share", "ms_qc_provenance",
                 "ms_qc_mechanism_channels", "ms_qc_artifact_roster")) {
    expect_true(grepl(face, src, fixed = TRUE), info = face)
  }
})

test_that("the committed plant is the frozen 96-channel SBS96 shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  counts <- .qa_tsv("qc_plant_counts.tsv")
  expect_identical(counts[[1L]], as.character(msuiter:::.ms_io_channel_tables()$SBS96))
  expect_identical(names(counts)[-1L], .qa_samples)
  expect_type(counts[[2L]], "integer")
  dict <- .qa_tsv("qc_plant_dict.tsv")
  expect_identical(dict[[1L]], as.character(msuiter:::.ms_io_channel_tables()$SBS96))
  expect_identical(names(dict)[-1L], c("SBS1", "SBS5", "SBS43", "SBS45b"))
  expo <- .qa_tsv("qc_plant_exposures.tsv")
  expect_identical(expo[[1L]], c("SBS1", "SBS5", "SBS43", "SBS45b"))
  expect_identical(names(expo)[-1L], .qa_samples)
})

test_that("the sentries catch exactly the planted spike families", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  w <- .qa_csv("qc_sentries.csv")
  expect_identical(w$sample, .qa_samples)
  expect_identical(w$planted_family,
    c(rep("gt", 4L), rep("ct", 4L), rep("clean", 4L), "dead"))
  expect_equal(sort(w$sample[w$gt_verdict == "hit"]), sort(.qa_gt_planted))
  expect_equal(sort(w$sample[w$ct_verdict == "watch"]), sort(.qa_ct_planted))
  clean_rows <- w[w$sample %in% c(.qa_clean, .qa_dead), , drop = FALSE]
  expect_true(all(clean_rows$gt_verdict %in% c("ok", "na")))
  expect_true(all(clean_rows$ct_verdict %in% c("ok", "na")))
  dead_row <- w[w$sample == .qa_dead, , drop = FALSE]
  expect_identical(dead_row$gt_verdict, "na")
  expect_identical(dead_row$ct_verdict, "na")
  expect_true(all(is.na(dead_row$gt_share)) && all(is.na(dead_row$ct_share)))
})

test_that("the roster share hits exactly the planted roster exposures", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  w <- .qa_csv("qc_artifact_share.csv")
  expect_identical(w$sample, .qa_samples)
  expect_equal(sort(w$sample[w$artifact_flag == "hit"]), sort(.qa_roster_planted))
  expect_equal(as.numeric(w$planted_roster_hit[w$sample %in% .qa_roster_planted]),
               rep(1, 4L))
  expect_equal(as.numeric(w$planted_roster_hit[!(w$sample %in% .qa_roster_planted)]),
               rep(0, 9L))
  hit_sigs <- w$artifact_sigs[w$artifact_flag == "hit"]
  expect_true(all(grepl("SBS43", hit_sigs, fixed = TRUE) |
                   grepl("SBS45b", hit_sigs, fixed = TRUE)))
})

test_that("fresh public-face calls re-derive the committed witness bytes", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  counts <- .qa_tsv("qc_plant_counts.tsv")
  labels <- as.character(msuiter:::.ms_io_channel_tables()$SBS96)
  mat <- matrix(as.integer(unlist(counts[-1L], use.names = FALSE)),
    nrow = 96L, dimnames = list(labels, .qa_samples))
  cat <- ms_catalog(mat, list(name = "SBS96", labels = labels), .qa_samples,
    provenance = list(genome = "GRCh37"))
  sen <- ms_qc_sentries(cat)
  wit <- .qa_csv("qc_sentries.csv")
  expect_equal(sen$gt_share, wit$gt_share, tolerance = 1e-12)
  expect_equal(sen$ct_share, wit$ct_share, tolerance = 1e-12)
  expect_identical(sen$gt_verdict, wit$gt_verdict)
  expect_identical(sen$ct_verdict, wit$ct_verdict)
  expect_identical(sen$qc_flag, wit$qc_flag)
  dict <- .qa_tsv("qc_plant_dict.tsv")
  dmat <- matrix(as.numeric(unlist(dict[-1L], use.names = FALSE)),
    nrow = 96L, dimnames = list(labels, c("SBS1", "SBS5", "SBS43", "SBS45b")))
  expo <- .qa_tsv("qc_plant_exposures.tsv")
  emat <- matrix(as.numeric(unlist(expo[-1L], use.names = FALSE)),
    nrow = 4L, dimnames = list(c("SBS1", "SBS5", "SBS43", "SBS45b"), .qa_samples))
  sh <- ms_qc_roster_share(cat, dmat, emat)
  wit2 <- .qa_csv("qc_artifact_share.csv")
  expect_equal(sh$artifact_share, wit2$artifact_share, tolerance = 1e-12)
  expect_identical(sh$artifact_sigs, wit2$artifact_sigs)
  expect_identical(sh$artifact_flag, wit2$artifact_flag)
})

test_that("the clean and sub-threshold branches speak measured silence", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  w <- .qa_csv("qc_sentries.csv")
  unspiked <- w[w$planted_family %in% c("clean", "dead"), , drop = FALSE]
  expect_equal(sum(unspiked$gt_verdict == "hit"), 0)
  expect_equal(sum(unspiked$ct_verdict == "watch"), 0)
  w2 <- .qa_csv("qc_artifact_share.csv")
  expect_equal(sum(w2$artifact_flag[w2$sample %in% .qa_clean] == "hit"), 0)
})

test_that("the certified constants and rosters stay pinned under the scenario", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  d <- msuiter:::.ms_qc_defaults
  expect_equal(d$artifact_share_flag, 0.05)
  expect_equal(d$gt_share_flag, 0.30)
  expect_equal(d$ct_share_watch, 0.40)
  ros <- ms_qc_artifact_roster()
  expect_equal(nrow(ros), 19L)
  expect_true(all(c("SBS27", "SBS43", "SBS45", "SBS95") %in% ros$name))
  ch <- ms_qc_mechanism_channels()
  expect_equal(nrow(ch), 32L)
  expect_equal(sum(ch$mechanism == "oxoG"), 16L)
  expect_equal(sum(ch$mechanism == "ffpe"), 16L)
})

test_that("the provenance checklist is complete and speaks no failure", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  w <- .qa_csv("qc_provenance.csv")
  expect_identical(w$check, c("catalog.class", "channel.space", "provenance.genome",
    "provenance.keys", "refdb.pin", "roster.pin", "thresholds.declared",
    "msuiter.version"))
  expect_true(!any(w$status == "fail"))
  expect_true(all(w$status[w$check %in% c("refdb.pin", "roster.pin",
    "thresholds.declared")] == "pass"))
})
