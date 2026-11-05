#!/usr/bin/env Rscript
# Sharded repo-mode testthat runner (CI restructure 2026-10-21).
#
# One process, one shard of the committed manifest. The census reporter
# (tests/testthat/helper-ci-shard-census.R -- shared with the in-suite units
# so an attestation line means the same thing in every lane) writes one
# MSUITER-ATTEST verdict to --attest=. A shard whose process dies mid-run
# simply leaves no attestation: the aggregator's missing-shard census is the
# net. A shard that COMPLETES having executed zero non-skipped tests is
# caught here too -- an arm that ran nothing gates nothing.
#
# usage: run-testthat-shard.R --manifest=<tsv> --shard=<n> --kind=<k>
#                             --mode=repo|installed [--root=<dir>]
#                             [--attest=<file>] [--tier=<T0,T1>] [--self-test]
# tier   = committed manifest tiers to run (issue #76); the lane skips a
#          shard with no file in its tiers (loud, exit 0, no attestation)
#          and REFUSES tier T2 -- the heavy class is tools/test-heavy.R's
#          face, not the CI shard fleet's
# repo     = devtools semantics: package loaded from source, full suite env
# installed = R CMD INSTALL'd package (fan-out arms; helpers still resolve
#             to the checkout via the ancestor walk, so the run is a
#             superset of the historical check-test phase, never weaker)
# kind     = guards | fanout (attestation lane label; strictness is the
#             aggregator's call)

.args <- local({
  ca <- try(commandArgs(trailingOnly = TRUE), silent = TRUE)
  if (inherits(ca, "try-error")) ca <- character()
  ca <- as.character(ca); ca <- ca[nzchar(ca)]
  seps <- which(ca == "--args")
  if (length(seps)) ca <- ca[(seps[1L] + 1L):length(ca)]
  ca
})
.kv <- function(flag, default) {
  hit <- grep(paste0("^--?", flag, "="), .args)
  if (length(hit) == 0L) default else sub(paste0("^--?", flag, "="), "", .args[hit[1L]])
}

root <- .kv("root", getwd())
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  root <- local({
    p <- normalizePath(getwd())
    while (!file.exists(file.path(p, "DESCRIPTION"))) {
      up <- dirname(p)
      if (identical(up, p)) quit(status = 2L)
      p <- up
    }
    p
  })
}
source(file.path(root, "tests", "testthat", "helper-ci-shard-census.R"))

# The verdict helpers (.ci_gate_verdict, .ci_is_failure, .ci_counts_failure,
# .ci_loud_failures, .ci_result_verdict) are shared from
# tests/testthat/helper-ci-shard-census.R -- sourced above, and the same
# bytes tools/test-heavy.R runs through.
#
# The lane plan: which files of one manifest shard the requested tiers
# actually run. A shard whose tier window is empty is skipped LOUDLY by
# the caller (a passing face with zero output is a silent green, refused
# by the CLI-face law); a shard reaching tier T2 is a DEFECT: the two
# provisioning simulations live in tests/heavy and belong to
# tools/test-heavy.R, never to the CI shard fleet.
.ci_lane_plan <- function(rows, shard, tiers) {
  sel <- rows[rows$shard == shard & rows$tier %in% tiers, , drop = FALSE]
  if (!nrow(sel)) return(list(skip = TRUE, defect = NA_character_, files = character()))
  if (any(sel$tier == "T2")) {
    return(list(skip = TRUE, defect = "T2",
                files = sel$file[sel$tier == "T2"]))
  }
  list(skip = FALSE, defect = NA_character_, files = sel$file)
}

is.self.test <- function() {
  hit <- grep("^--?self-test($|[=])", .args)
  if (!length(hit)) return(FALSE)
  val <- sub("^--?self-test=?", "", .args[hit[1L]])
  identical(val, "") || identical(val, "1") || identical(val, "TRUE")
}
if (is.self.test()) {
  # Firing-control self-test on synthetic fixtures: no package needed, the
  # controls must be observed to FIRE, a silent pass is itself a failure.
  library(testthat)
  dir <- tempfile("runner-selftest-"); dir.create(dir, recursive = TRUE)
  tf <- function(name, lines) writeLines(lines, file.path(dir, name))
  tf("test-good.R", c("test_that('two passes', { expect_true(TRUE); expect_true(TRUE) })"))
  tf("test-allskip.R", "test_that('skips', skip('by design'))")
  tf("test-red.R", "test_that('loud red', { expect_identical(1L, 2L) })")
  tf("test-slow.R", "test_that('deep tier', { expect_true(TRUE) })")
  manifest <- file.path(dir, "manifest.tsv")
  writeLines(c("# k=4", "shard\tfile\tseconds\ttier",
               "1\ttest-good.R\t1\tT0", "2\ttest-allskip.R\t1\tT0",
               "3\ttest-red.R\t1\tT0", "4\ttest-slow.R\t1\tT1"), manifest)
  m <- .ci_parse_manifest(manifest)

  # Tier-law controls run against the production predicate itself.
  p.skip <- .ci_lane_plan(m$rows, 4L, c("T0"))
  if (!isTRUE(p.skip$skip) || length(p.skip$files) || !is.na(p.skip$defect)) {
    cat("RUNNER SELF-TEST FAILED: T0-empty-shard skip control did not FIRE\n", sep = "")
    quit(status = 1L)
  }
  cat("T0-empty-shard skip control FIR\n", sep = "")
  p.deep <- .ci_lane_plan(m$rows, 4L, c("T0", "T1"))
  if (isTRUE(p.deep$skip) || !identical(p.deep$files, "test-slow.R")) {
    cat("RUNNER SELF-TEST FAILED: T1-inclusion control did not FIRE\n", sep = "")
    quit(status = 1L)
  }
  cat("T1-inclusion control FIR\n", sep = "")
  p.heavy <- .ci_lane_plan(rbind(m$rows, data.frame(shard = 1L, file = "test-heavy.R",
                                   seconds = 1L, tier = "T2", stringsAsFactors = FALSE)),
                           1L, c("T0", "T1", "T2"))
  if (!identical(p.heavy$defect, "T2")) {
    cat("RUNNER SELF-TEST FAILED: T2-refusal control did not FIRE\n", sep = "")
    quit(status = 1L)
  }
  cat("T2-refusal control FIR\n", sep = "")
  run_shard <- function(shard) {
    rp <- .ci_census_reporter()$new(lane = "selftest", shard = shard)
    res <- test_dir(dir, filter = .ci_shard_filter(m$rows, shard), reporter = rp,
                    stop_on_failure = FALSE, load_helpers = FALSE,
                    load_package = "none")
    loud <- capture.output(
      rv <- .ci_result_verdict(res, "selftest", shard),
      type = "message")
    list(rp = rp, verdict = max(.ci_gate_verdict(rp), rv), loud = loud)
  }
  g <- run_shard(1L)
  if (!identical(g$rp$n_executed(), 1L) || identical(g$rp$n_pass, 0L) ||
      g$verdict != 0L) {
    cat("RUNNER SELF-TEST FAILED: good control did not stay GREEN\n", sep = "")
    quit(status = 1L)
  }
  cat("good control GREEN\n", sep = "")
  s <- run_shard(2L)
  if (!identical(s$rp$n_executed(), 0L) || s$verdict == 0L) {
    cat("RUNNER SELF-TEST FAILED: zero-executed control did not FIRE\n", sep = "")
    quit(status = 1L)
  }
  cat("zero-executed control FIR\n", sep = "")
  if (!grepl("status=vacuous", s$rp$attestation(), fixed = TRUE)) {
    cat("RUNNER SELF-TEST FAILED: vacuous attestation control did not FIRE\n", sep = "")
    quit(status = 1L)
  }
  cat("vacuous attestation FIR\n", sep = "")
  # The L6 law: a counted failure speaks through the data stream and dies --
  # with reporter-independence proven by counting the block, not trusting
  # delegation. This control is the injected-failure incident made permanent.
  rd <- run_shard(3L)
  if (!any(grepl("LOUDFAIL[selftest#3] loud red", rd$loud, fixed = TRUE))) {
    cat("RUNNER SELF-TEST FAILED: loud-failure control did not SPEAK\n", sep = "")
    quit(status = 1L)
  }
  if (rd$verdict == 0L) {
    cat("RUNNER SELF-TEST FAILED: loud-failure control did not DIE\n", sep = "")
    quit(status = 1L)
  }
  cat("loud-failure control SPEAK+FI\n", sep = "")
  cat("RUNNER SELF-TEST OK\n", sep = "")
  quit(status = 0L)
}

manifest <- .kv("manifest", file.path(root, "tools", "ci", "shard-manifest.tsv"))
shard <- as.integer(.kv("shard", NA_character_))
kind <- .kv("kind", "guards")
mode <- .kv("mode", "repo")
tiers <- trimws(strsplit(.kv("tier", "T0,T1,T2"), ",", fixed = TRUE)[[1L]])
attest <- .kv("attest", file.path(tempdir(), paste0("msuiter-attest-", kind,
                                                    "-", shard, "-", mode, ".attest")))
if (is.na(shard) || !mode %in% c("repo", "installed")) quit(status = 2L)
m <- .ci_parse_manifest(manifest)
if (shard < 1L || shard > m$k) {
  # file = stderr(): the house print idiom. cat's R-4.5 stderr= argument
  # ECHOES the value (cat("y\n", stderr = TRUE) prints "y TRUE" -- measured),
  # poisoning transcripts with phantom TRUE tokens.
  cat(paste0("run-testthat-shard: DEFECT shard ", shard, " outside k=", m$k, "\n"),
      sep = "", file = stderr())
  quit(status = 2L)
}
plan <- .ci_lane_plan(m$rows, shard, tiers)
if (isTRUE(plan$skip)) {
  if (identical(plan$defect, "T2")) {
    cat(paste0("run-testthat-shard: DEFECT shard ", shard,
               " reaches tier T2 (", paste0(plan$files, collapse = ", "),
               ") -- the heavy class runs via tools/test-heavy.R, not the ",
               "shard fleet\n"), sep = "", file = stderr())
    quit(status = 2L)
  }
  # Speak the skip: a passing face that says nothing is a silent green.
  cat(paste0("run-testthat-shard: shard ", shard, " holds no ",
             paste0(tiers, collapse = "/"), " file -- tier skip, no attestation\n"),
      sep = "")
  quit(status = 0L)
}
dir.create(dirname(attest), recursive = TRUE, showWarnings = FALSE)
unlink(attest)   # never attest from a previous incarnation of this path

library(testthat)
rp <- .ci_census_reporter()$new(lane = kind, shard = shard)
filter <- .ci_roster_filter(plan$files)
tdir <- file.path(root, "tests", "testthat")
if (identical(mode, "repo")) {
  if (!requireNamespace("devtools", quietly = TRUE)) quit(status = 2L)
  res <- devtools::test(pkg = root, filter = filter, reporter = rp,
                        stop_on_failure = FALSE)
} else {
  old <- getwd(); setwd(root); on.exit(setwd(old))
  pkg <- sub("^Package:\\s*", "",
             grep("^Package:", readLines(file.path(root, "DESCRIPTION"),
                                          warn = FALSE), value = TRUE)[1L])
  res <- test_dir(tdir, filter = filter, reporter = rp,
                  stop_on_failure = FALSE, package = pkg,
                  load_package = "installed")
}
v <- max(.ci_gate_verdict(rp), .ci_result_verdict(res, kind, shard))
writeLines(rp$attestation(), attest)
cat(rp$attestation(), "\n", sep = "")
if (v != 0L) {
  cause <- if (rp$n_executed() <= 0L) {
    "completed having executed zero non-skipped tests -- vacuous shard dies"
  } else {
    paste0(rp$n_fail + rp$n_error,
           " counted failure(s)/error(s) -- see the LOUDFAIL blocks above")
  }
  cat(paste0("run-testthat-shard: DEFECT shard ", shard, " ", cause, "\n"),
      sep = "", file = stderr())
}
quit(status = v)
