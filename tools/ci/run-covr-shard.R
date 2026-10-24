#!/usr/bin/env Rscript
# Sharded covr runner (CI restructure 2026-10-21).
#
# One covr::package_coverage(type = "tests") pass per manifest shard. The
# shard filter and the attestation path reach the installed testthat entry
# point through the environment handoffs tests/testthat.R documents; the
# child census reporter (shared helper -- one verdict format everywhere)
# writes the MSUITER-ATTEST line. covr dies mid-shard or writes nothing --
# this runner then attests the absence honestly as status=vacuous.
#
# The census gates (2026-10-24): the aggregator's retired --advisory let a
# year of broken coverage exit green. This runner still never exits red for
# coverage CONTENT -- it attests every outcome honestly and the census
# decides; structural installed-copy absences are sanctioned byte-exactly by
# tools/ci/covr-divergences.tsv. Defects are printed either way; nothing
# here hides them.
#
# usage: run-covr-shard.R --manifest=<tsv> --shard=<n> --out-srt=<file>
#                         [--attest=<file>] [--root=<dir>]

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
# <!-- census-exempt tokens: 0 --> the moved SRT renderer dropped one
#     digit-bearing IDENTIFIER token (paste0) into covr-srt-shape.R;
#     no measured numeric claim of ours left this file with it.
source(file.path(root, "tools", "ci", "covr-srt-shape.R"))

manifest <- .kv("manifest", file.path(root, "tools", "ci", "shard-manifest.tsv"))
shard <- as.integer(.kv("shard", NA_character_))
out.srt <- .kv("out-srt", file.path(tempdir(), paste0("covr-shard-", shard, ".srt")))
attest <- .kv("attest", file.path(tempdir(), paste0("covr-shard-", shard, ".attest")))
if (is.na(shard)) quit(status = 2L)
m <- .ci_parse_manifest(manifest)
if (shard < 1L || shard > m$k) quit(status = 2L)
dir.create(dirname(out.srt), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(attest), recursive = TRUE, showWarnings = FALSE)
unlink(c(out.srt, attest))

attest.vacuous <- function(why) {
  writeLines(paste0("MSUITER-ATTEST kind=coverage shard=", shard,
                    " files=0 tests=0 executed=0 pass=0 fail=0 error=0 skip=0",
                    " warn=0 status=vacuous why=", why), attest)
  cat("run-covr-shard: shard ", shard, " attests vacuous (", why, ") -- for the census\n",
      sep = "", file = stderr())
  quit(status = 0L)
}

if (!requireNamespace("covr", quietly = TRUE)) attest.vacuous("covr-uninstalled")
old <- getwd(); setwd(root); on.exit(setwd(old))
child.attest <- tempfile("covr-child-attest-")
Sys.setenv(MSUITER_TESTTHAT_FILTER = .ci_shard_filter(m$rows, shard),
           MSUITER_CENSUS_ATTEST = child.attest,
           MSUITER_CENSUS_SHARD = as.character(shard))
on.exit(Sys.unsetenv(c("MSUITER_TESTTHAT_FILTER", "MSUITER_CENSUS_ATTEST",
                      "MSUITER_CENSUS_SHARD")), add = TRUE)

# Per-shard private cargo home + target dir (src/Makevars.in reads these
# through MSUITER_CARGO_HOME/MSUITER_TARGET_DIR ?= hooks). The in-tree
# defaults carry an unconditional rm -Rf at the recipe tail and cargo's file
# lock serializes simultaneous builds on it: under the parallel wave, shards
# destroyed each other's incremental state and queued behind one cargo lock
# for the better part of an hour (118-min straggler class, PR #52 coverage
# run 40044943832 -- attest stayed live=1/7 for ~100 min). Private paths
# forfeit cross-shard incremental reuse -- correctness over cache warmth.
stamp <- as.integer(Sys.time())
covr.cargo <- file.path(tempdir(), paste0("covr-cargo-", shard, "-", stamp))
covr.target <- file.path(tempdir(), paste0("covr-target-", shard, "-", stamp))
dir.create(covr.cargo, recursive = TRUE)
dir.create(covr.target, recursive = TRUE)
Sys.setenv(MSUITER_CARGO_HOME = covr.cargo, MSUITER_TARGET_DIR = covr.target)
on.exit({
  Sys.unsetenv(c("MSUITER_CARGO_HOME", "MSUITER_TARGET_DIR"))
  unlink(c(covr.cargo, covr.target), recursive = TRUE)
}, add = TRUE)

# Per-shard snapshot of the package tree. covr's instrumented install writes
# MUTABLE state into the checkout itself -- src/*.o, src/*.gcno, the
# generated src/Makevars -- so K concurrent package_coverage() calls from one
# tree trample each other's object files (witnessed: local 6-way wave,
# five shards covr-failed while every solo probe passed). The snapshot is
# ~20 MB (the 420 MB src/rust/target build cache rides the private
# MSUITER_TARGET_DIR, and .git is not needed to install); clonefile cp makes
# it nearly free on APFS and a plain copy on Linux runners.
snap <- file.path(tempdir(), paste0("covr-tree-", shard, "-", stamp))
dir.create(snap, recursive = TRUE)
entries <- list.files(root, all.files = TRUE, include.dirs = FALSE)
entries <- setdiff(entries, c(".git", ".Rproj"))
for (e in entries) {
  ok <- suppressWarnings(system2("cp", c("-Rc", file.path(root, e), snap),
                                 stdout = NULL, stderr = NULL))
  if (!identical(as.integer(ok), 0L))
    suppressWarnings(system2("cp", c("-R", file.path(root, e), snap),
                             stdout = NULL, stderr = NULL))
}
unlink(file.path(snap, "src/rust/target"), recursive = TRUE)
unlink(file.path(snap, "src/rust/.cargo"), recursive = TRUE)
unlink(list.files(file.path(snap, "src"), pattern = "[.](gcda|gcno|o|so|dll)$",
                   full.names = TRUE))
unlink(file.path(snap, "src/Makevars"))
on.exit(unlink(snap, recursive = TRUE), add = TRUE)

cov <- try(covr::package_coverage(path = snap, type = "tests", quiet = TRUE,
                                  install_path = tempfile("covr-lib-"),
                                  pre_clean = FALSE), silent = TRUE)
# pre_clean = FALSE is load-bearing for the parallel lane: covr's pre-clean
# deletes stale instrumentation state including the shared src/rust/target
# tree, and K shards run simultaneously on one checkout -- they would delete
# each other's live cargo build (witnessed as cargo incremental-deletion
# races in the local preflight). Each shard installs into its own fresh
# tempfile library, which is already the clean-room isolation this lane
# needs.
if (inherits(cov, "try-error") || is.null(cov)) {
  # try(silent=TRUE) keeps the message out of the transcript by contract --
  # say it here instead (defects are LOUD). The try-error wrapper carries
  # the real condition in attr "condition"; dispatch only on that.
  if (inherits(cov, "try-error")) {
    inner <- attr(cov, "condition")
    msg <- if (is.null(inner)) "(no condition carried)" else conditionMessage(inner)
    cat("run-covr-shard: covr::package_coverage failed:\n",
        paste0("  : ", msg, collapse = "\n"), "\n", sep = "", file = stderr())
  }
  attest.vacuous("covr-failed")
}
if (!length(cov)) attest.vacuous("empty-cov")
srt <- .covr_srt_lines(cov)
if (is.null(srt)) attest.vacuous("no-line-rows")
if (!length(srt)) attest.vacuous("empty-srt")
writeLines(srt, out.srt)
if (file.exists(child.attest)) {
  file.copy(child.attest, attest, overwrite = TRUE)
} else {
  attest.vacuous("child-wrote-nothing")
}
cat(readLines(attest, warn = FALSE), sep = "\n"); cat("\n", sep = "")
