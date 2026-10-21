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

# Loudness lives in the DATA STREAM, not the reporter chain: test_dir returns
# the full expectation list, and we render failures from that object directly.
# Rationale (run 39646023270, fan-out macos/oldrel-1, shard-5): with
# stop_on_failure = TRUE, testthat's StopReporter wraps our reporter and the
# halt races the delegation -- on that arm's testthat the process died before
# the wrapped reporter could print the failed expectation, leaving
# "! Test failures. Execution halted" with ZERO failure detail in the log
# (the injected-failure control on this host proves the delegation order is
# testthat-version-dependent, so evidence may not depend on it).
# stop_on_failure is therefore FALSE and the verdict below re-reads results.
.ci_is_failure <- function(r) {
  inherits(r, "expectation_failure") || inherits(r, "expectation_error")
}

# A reported failure counts unless it is an EXPECTED failure (expect_failure()
# / known_fail(): testthat marks those expected = TRUE) -- those are passes.
.ci_counts_failure <- function(r) {
  .ci_is_failure(r) && !isTRUE(attr(r, "expected")) && !isTRUE(tryCatch(r$expected, error = function(e) FALSE))
}

# Walk testthat's result nesting (results -> files -> expectations) and print
# one block per counted failure, independently of any reporter delegation.
# NO unlist(): unlist FLATTENS a lone expectation object into its fields (the
# probe that pinned this law), and for-in over a list iterates elements
# without flattening. An expectation IS a list, so the class check must
# precede the recursion.
.ci_loud_failures <- function(res, lane, shard) {
  n <- 0L
  for (r in res) {
    if (inherits(r, "expectation")) {
      if (!.ci_counts_failure(r)) next
    } else if (is.list(r)) {
      n <- n + .ci_loud_failures(r, lane, shard)
      next
    } else next
    n <- n + 1L
    test <- attr(r, "test")
    if (is.null(test)) test <- tryCatch(r$test, error = function(e) NULL)
    if (is.null(test)) test <- "<file level>"
    msg <- tryCatch(conditionMessage(r), error = function(e) NULL)
    if (is.null(msg) || !nzchar(msg)) msg <- tryCatch(as.character(r$message), error = function(e) "")
    if (!nzchar(msg)) msg <- paste0("<", paste0(class(r), collapse = "/"), ">")
    # Full multi-line message: testthat sinks BOTH stdout and stderr inside a
    # test context (measured: the census report's cat(file = stderr()) emission
    # vanished from the transcript too), so the only channel that reaches the
    # log from inside a test is the expectation's own failure message -- and
    # expect_*() carries an author-supplied info= in it. Truncating to line
    # one throws away exactly the evidence that channel exists to carry.
    msg <- paste0(substring(msg, 1L, 4000L), collapse = "")
    msg <- gsub("[\r\t]", " ", msg)
    # message(): the unbuffered stderr channel that survives a halt AND is
    # capturable by the self-test's capture.output(type = "message") -- raw
    # cat(stderr = TRUE) bypasses the sink (pinned empirically).
    message(paste0("LOUDFAIL[", lane, "#", shard, "] ", test, "\n  : ", msg))
  }
  n
}

# Verdict from the data stream: counted failures die even if every reporter
# in the chain swallowed them.
.ci_result_verdict <- function(res, lane, shard) {
  f <- .ci_loud_failures(res, lane, shard)
  if (f > 0L) 1L else 0L
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
  manifest <- file.path(dir, "manifest.tsv")
  writeLines(c("# k=3", "shard\tfile\tseconds",
               "1\ttest-good.R\t1", "2\ttest-allskip.R\t1",
               "3\ttest-red.R\t1"), manifest)
  m <- .ci_parse_manifest(manifest)

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
dir.create(dirname(attest), recursive = TRUE, showWarnings = FALSE)
unlink(attest)   # never attest from a previous incarnation of this path

library(testthat)
rp <- .ci_census_reporter()$new(lane = kind, shard = shard)
filter <- .ci_shard_filter(m$rows, shard)
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
