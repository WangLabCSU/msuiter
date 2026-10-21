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
#                             [--attest=<file>] [--self-test]
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

# Gate: zero executed work means this shard attests nothing and must die.
# Kept as a named function so the --self-test above proves it FIRES.
.ci_gate_verdict <- function(rp) {
  if (rp$n_executed() <= 0L) 1L else 0L
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
  manifest <- file.path(dir, "manifest.tsv")
  writeLines(c("# k=2", "shard\tfile\tseconds",
               "1\ttest-good.R\t1", "2\ttest-allskip.R\t1"), manifest)
  m <- .ci_parse_manifest(manifest)

  run_shard <- function(shard) {
    rp <- .ci_census_reporter()$new(lane = "selftest", shard = shard)
    test_dir(dir, filter = .ci_shard_filter(m$rows, shard), reporter = rp,
             stop_on_failure = FALSE, load_helpers = FALSE,
             load_package = "none")
    list(rp = rp, verdict = .ci_gate_verdict(rp))
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
  cat("RUNNER SELF-TEST OK\n", sep = "")
  quit(status = 0L)
}

manifest <- .kv("manifest", file.path(root, "tools", "ci", "shard-manifest.tsv"))
shard <- as.integer(.kv("shard", NA_character_))
kind <- .kv("kind", "guards")
mode <- .kv("mode", "repo")
attest <- .kv("attest", file.path(tempdir(), paste0("msuiter-attest-", kind,
                                                    "-", shard, "-", mode, ".attest")))
if (is.na(shard) || !mode %in% c("repo", "installed")) quit(status = 2L)
m <- .ci_parse_manifest(manifest)
if (shard < 1L || shard > m$k) {
  cat("run-testthat-shard: DEFECT shard ", shard, " outside k=", m$k, "\n",
      sep = "", stderr = TRUE)
  quit(status = 2L)
}
dir.create(dirname(attest), recursive = TRUE, showWarnings = FALSE)
unlink(attest)   # never attest from a previous incarnation of this path

library(testthat)
rp <- .ci_census_reporter()$new(lane = kind, shard = shard)
filter <- .ci_shard_filter(m$rows, shard)
tdir <- file.path(root, "tests", "testthat")
if (identical(mode, "repo")) {
  if (!requireNamespace("devtools", quietly = TRUE)) quit(status = 2L)
  devtools::test(pkg = root, filter = filter, reporter = rp,
                 stop_on_failure = TRUE)
} else {
  old <- getwd(); setwd(root); on.exit(setwd(old))
  pkg <- sub("^Package:\\s*", "",
             grep("^Package:", readLines(file.path(root, "DESCRIPTION"),
                                          warn = FALSE), value = TRUE)[1L])
  test_dir(tdir, filter = filter, reporter = rp, stop_on_failure = TRUE,
           package = pkg, load_package = "installed")
}
v <- .ci_gate_verdict(rp)
writeLines(rp$attestation(), attest)
cat(rp$attestation(), "\n", sep = "")
if (v != 0L) {
  cat("run-testthat-shard: DEFECT shard ", shard, " completed having executed ",
      "zero non-skipped tests -- vacuous shard dies\n", sep = "", stderr = TRUE)
}
quit(status = v)
