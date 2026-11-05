#!/usr/bin/env Rscript
# tools/test-heavy.R -- the one-command local face of the tier-T2 heavy
# battery (issue #76, 2026-11-05; docs/devlog/
# 2026-11-05-ci-pr-gate-tiering-ruling.md).
#
# The two check-layout-sim provisioning simulations weigh ~41 minutes
# measured (1250 s + 1231 s in tools/ci/shard-weights.tsv) and belong to
# neither the per-PR gate nor the covr lane: the manifest's tier column
# marks them T2 and binds them to tests/heavy (the generator's location
# law). This script is their face: it reads the committed partition, runs
# exactly the T2 roster through the shared census reporter, and speaks a
# per-shard attestation with the same data-stream verdict law every sharded
# lane uses (tools/ci/run-testthat-shard.R): zero executed work dies,
# counted failures die, the verdict comes from the results object, not a
# reporter's courtesy.
#
# usage: tools/test-heavy.R [--manifest=<tsv>] [--tier=T2] [--shard=<n>]
#                           [--attest-dir=<dir>] [--self-test]
#   manifest   committed partition (default tools/ci/shard-manifest.tsv)
#   tier       comma list, any of {T0,T1,T2} (default T2 -- the CI lanes
#              own the other tiers through run-testthat-shard.R)
#   shard      optional: run one shard only (its roster must intersect the tier)
#   attest-dir optional: write shard-<n>.attest lines here (the census face)
#   self-test  fixture controls proving the gate FIRES (no package needed)
#
# CI-lean law (owner ruling 2026-10-25): this battery runs LOCALLY and on
# the nightly scheduled job; it must never ride the per-push CI path.
.args <- local({
  ca <- try(commandArgs(trailingOnly = TRUE), silent = TRUE)
  if (inherits(ca, "try-error")) ca <- character()
  if (!length(ca) || !nzchar(ca[[1]])) ca <- grep("^--", commandArgs(trailingOnly = FALSE), value = TRUE)
  ca
})
.kv <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), .args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1L]])
}
root <- .kv("root", getwd())
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  root <- local({
    p <- normalizePath(getwd())
    while (!file.exists(file.path(p, "DESCRIPTION"))) {
      up <- dirname(p)
      if (identical(up, p)) stop("no package root above ", getwd())
      p <- up
    }
    p
  })
}
source(file.path(root, "tests", "testthat", "helper-ci-shard-census.R"))

manifest <- .kv("manifest", file.path(root, "tools", "ci", "shard-manifest.tsv"))
tier.arg <- .kv("tier", "T2")
shard.arg <- .kv("shard", NA_character_)
attest.dir <- .kv("attest-dir", NA_character_)

# ---------------------------------------------------------------- self-test
# Firing controls against the production predicates: an unknown tier must
# die, a T2-only shard must offer no T0 roster (the loud-skip face), zero
# executed work must be fatal, and a counted failure must redden the
# data-stream verdict. Fixtures only; the package is not attached.
if ("self-test" %in% sub("^--", "", .args)) {
  fired <- c()
  td <- tempfile("heavy-selftest-"); dir.create(td, recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE))
  man <- file.path(td, "manifest.tsv")
  writeLines(c("# k=1", "shard\tfile\tseconds\ttier",
               "1\ttest-none.R\t5\tT2"), man)
  bad <- tryCatch({ .ci_tier_rows(data.frame(shard = 1L, file = "x",
                                             seconds = 1L, tier = "T9",
                                             stringsAsFactors = FALSE), "T9"); FALSE },
                  error = function(e) grepl("tier", conditionMessage(e)))
  fired <- c(fired, isTRUE(bad))
  cat(if (isTRUE(bad)) "tier-validation control FIR\n"
      else "SELF-TEST BROKEN: unknown tier rode unseen\n", sep = "")
  m <- .ci_parse_manifest(man)
  plan.empty <- .ci_tier_rows(m$rows, "T0")
  fired <- c(fired, nrow(plan.empty) == 0L)
  cat(if (nrow(plan.empty) == 0L) "heavy tier-skip roster control FIR\n"
      else "SELF-TEST BROKEN: T2-only shard yielded a T0 roster\n", sep = "")
  rp <- .ci_census_reporter()$new(lane = "heavy", shard = 1L)
  fired <- c(fired, .ci_gate_verdict(rp) == 1L)
  cat(if (.ci_gate_verdict(rp) == 1L) "zero-executed gate control FIR\n"
      else "SELF-TEST BROKEN: vacuous heavy shard could attest\n", sep = "")
  fake <- structure(list(message = "self-test failure", test = "constructed",
                         expected = FALSE),
                    class = c("expectation_failure", "expectation",
                              "condition", "error"))
  res <- .ci_result_verdict(list(f1 = list(fake)), "heavy", 1L)
  fired <- c(fired, res == 1L)
  cat(if (res == 1L) "loud-failure verdict control FIR\n"
      else "SELF-TEST BROKEN: counted failure rode unseen\n", sep = "")
  if (!all(fired)) { cat("HEAVY SELF-TEST FAILED\n", sep = ""); quit(status = 1L) }
  cat("HEAVY SELF-TEST OK\n")
  quit(status = 0L)
}

# ---------------------------------------------------------------- production
tiers <- trimws(strsplit(tier.arg, ",", fixed = TRUE)[[1L]])
m <- .ci_parse_manifest(manifest)
shard <- if (is.na(shard.arg)) NA_integer_ else as.integer(shard.arg)
if (!is.na(shard) && (shard < 1L || shard > m$k)) quit(status = 2L)
plan <- .ci_tier_rows(m$rows, tiers)
shards <- if (is.na(shard)) sort(unique(plan$shard)) else shard
if (!length(shards)) {
  # Speak the skip (CLI-face law): a passing face that says nothing is a
  # silent green.
  cat(paste0("test-heavy: no ", paste0(tiers, collapse = "/"),
             " file in the manifest -- nothing to run\n"), sep = "")
  quit(status = 0L)
}
if (!is.na(attest.dir)) dir.create(attest.dir, recursive = TRUE, showWarnings = FALSE)
library(testthat)
heavy.dir <- file.path(root, "tests", "heavy")
status <- 0L
for (s in shards) {
  files <- plan$file[plan$shard == s]
  if (!length(files)) {
    cat(paste0("test-heavy: shard ", s, " holds no ",
               paste0(tiers, collapse = "/"), " file -- tier skip\n"), sep = "")
    next
  }
  rp <- .ci_census_reporter()$new(lane = "heavy", shard = s)
  cat(paste0("test-heavy: shard ", s, " runs ", length(files),
             " file(s): ", paste0(files, collapse = ", "), "\n"), sep = "")
  res <- test_dir(heavy.dir, filter = .ci_roster_filter(files),
                  reporter = rp, stop_on_failure = FALSE)
  v <- max(.ci_gate_verdict(rp), .ci_result_verdict(res, "heavy", s))
  if (!is.na(attest.dir)) {
    writeLines(rp$attestation(),
               file.path(attest.dir, paste0("shard-", s, ".attest")))
  }
  cat(rp$attestation(), "\n", sep = "")
  if (v != 0L) {
    cause <- if (rp$n_executed() <= 0L) {
      "completed having executed zero non-skipped tests -- vacuous shard dies"
    } else {
      paste0(rp$n_fail + rp$n_error,
             " counted failure(s)/error(s) -- see the LOUDFAIL blocks above")
    }
    cat(paste0("test-heavy: DEFECT shard ", s, " ", cause, "\n"),
        sep = "", file = stderr())
    status <- 1L
  }
}
quit(status = status)
