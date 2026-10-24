#!/usr/bin/env Rscript
# Declared-namespace-use gate (CI warning-zero, 2026-10-23).
#
# R CMD check's two "checking dependencies ... " blocks are the family this
# gate makes visible without waiting for a check arm. Push-run
# 39864490318 (ubuntu-latest/R release) printed, byte-verbatim:
#   * checking dependencies in R code ... WARNING
#       'loadNamespace' or 'requireNamespace' call not declared from: 'digest'
#       Missing or unexported object: 'tools::R_user_cache_dir'
#   * checking for unstated dependencies in 'tests' ... WARNING
#       '::' or ':::' import not declared from: 'R6'
#       'library' or 'require' call not declared from: 'R6'
# The two WARNINGs were annotations; no local gate saw them until CI did.
# This tool invokes R's own scanners -- the exact functions the check driver
# runs (tools:::.check_packages_used / ..._in_tests, same WARNING classifier)
# -- so the verdict is byte-identical to an arm's, never a hand-rolled
# approximation. --selftest drives synthetic packages through both
# directions (declared-clean and violat-firing); a gate that cannot fire is
# refused house-wide.
#
# usage: check-dep-declaration.R [--root=<dir>] [--selftest]

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

# The check driver's own WARNING classifier (.check_packages, byte-clone).
.warn.re <- "(not declared from|Missing or unexported|Including base/recommended)"

# R's check driver runs each scan through R_runR2 -- a fresh child process.
# This build's scanners print locale-translated prose (under zh_CN the very
  # needle strings come back translated into Chinese characters,
# 'R6'", byte-measured 2026-10-23), so an in-process scan under a non-English
# locale is silently vacuous. Pin LC_ALL=C in the scan child, as an en_US CI
# runner is anyway -- the gate reads the same bytes the arms printed.
.scan.pkg <- function(dir) {
  ex <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(ex)) ex <- paste0(ex, ".exe")
  if (!file.exists(ex)) stop("check-dep-declaration: Rscript not found under ", R.home("bin"))
  of <- tempfile("depdecl-scan-"); ef <- paste0(of, ".err")
  # The scan rides a script file, not -e argv: this build's system2 renders
  # args through sh -c unquoted (the check-layout-sim .run3 law, measured)
  # and any paren in inline code dies as a syntax error.
  code <- c(
    "Sys.setenv(\"_R_CHECK_PACKAGES_USED_IN_TESTS_USE_SUBDIRS_\" = \"TRUE\")",
    paste0("setwd(\"", gsub("\"", "\\\\\"", dir), "\")"),
    "print(tools:::.check_packages_used(dir = \".\"))",
    "print(tools:::.check_packages_used_in_tests(\".\", \"tests\"))")
  sf <- tempfile("depdecl-scan-src.R")
  writeLines(code, sf)
  old <- Sys.getenv("LC_ALL")
  Sys.setenv(LC_ALL = "C")
  on.exit(if (is.na(old)) Sys.unsetenv("LC_ALL") else Sys.setenv(LC_ALL = old), add = TRUE)
  st <- suppressWarnings(system2(ex, c(sf), stdout = of, stderr = ef, wait = TRUE))
  txt <- character()
  if (file.exists(of)) txt <- c(txt, readLines(of, warn = FALSE))
  if (!is.na(st) && identical(as.integer(st), 0L)) {
    txt[grepl(.warn.re, txt)]
  } else {
    err <- if (file.exists(ef)) paste0(readLines(ef, warn = FALSE), collapse = " | ") else "(no stderr)"
    stop("check-dep-declaration: scan child failed (status ",
         if (is.na(st)) "NA" else as.character(st), "): ", err)
  }
}

selftest <- function() {
  fix <- tempfile("depdecl-selftest-")
  dir.create(fix, recursive = TRUE)
  on.exit(unlink(fix, recursive = TRUE), add = TRUE)
  mk <- function(name, suggests) {
    d <- file.path(fix, name)
    dir.create(file.path(d, "R"), recursive = TRUE)
    dir.create(file.path(d, "tests", "testthat"), recursive = TRUE)
    writeLines(c("Package: fxx", "Version: 1.0", "Title: Declared-use fixture",
                 "Description: Synthetic package for the dep-declaration controls.",
                 "Author: msuiter CI", "Maintainer: msuiter CI <ci@example.invalid>",
                 "License: GPL-2", if (nzchar(suggests)) suggests),
               file.path(d, "DESCRIPTION"))
    writeLines(c("export(f)", "export(g)", "export(h)"), file.path(d, "NAMESPACE"))
    # digest: optional accelerator probed via requireNamespace and used via
    # :: (the R-code block needles). tools::R_user_cache_dir: does not exist
    # in the tools namespace at all -- "Missing or unexported" needle (the catalog-currency-harvest
    # landmine; clean side uses the exported R_user_dir instead).
    writeLines(c("f <- function() {",
                 "  requireNamespace(\"digest\", quietly = TRUE)",
                 "  digest::digest(\"x\", algo = \"sha256\", serialize = FALSE)",
                 "}"),
               file.path(d, "R", "probe.R"))
    writeLines(if (name == "red")
                 "g <- function() tools::R_user_cache_dir(\"fxx\")"
               else "g <- function() tools::R_user_dir(\"fxx\", which = \"cache\")",
               file.path(d, "R", "cache.R"))
    writeLines(c("h <- function() {",
                 "  requireNamespace(\"digest\", quietly = TRUE)",
                 "  digest::digest(\"y\", algo = \"sha256\", serialize = FALSE)",
                 "}"),
               file.path(d, "tests", "testthat", "helper.R"))
    d
  }
  defects <- character()
  expect <- function(cond, msg) if (!isTRUE(cond)) defects <- c(defects, msg)
  red <- .scan.pkg(mk("red", ""))
  expect(length(red) > 0L, "self-test: violat fixture produced NO warnings (gate is vacuous)")
  expect(any(grepl("not declared from", red) & grepl("digest", red, fixed = TRUE)),
         "self-test: digest not-declared needle did not fire")
  expect(any(grepl("Missing or unexported", red) &
             grepl("R_user_cache_dir", red, fixed = TRUE)),
         "self-test: tools::R_user_cache_dir missing-or-unexported needle did not fire")
  expect(any(grepl("::", red, fixed = TRUE) & grepl("digest", red, fixed = TRUE)),
         "self-test: tests-block '::' not-declared needle did not fire")
  clean <- .scan.pkg(mk("clean", "Suggests: digest"))
  expect(length(clean) == 0L,
         paste0("self-test: declared-clean fixture still warned: ",
                paste0(clean, collapse = " | ")))
  if (length(defects)) {
    for (dd in defects) cat("DEPDECL SELF-TEST FAILED:", dd, "\n", sep = " ", file = stderr())
    quit(status = 1L)
  }
  cat("DEPDECL SELF-TEST OK (violat fires, clean clean)\n")
  quit(status = 0L)
}

if ("--selftest" %in% .args) selftest()

root <- .kv("root", getwd())
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  p <- normalizePath(root)
  while (!file.exists(file.path(p, "DESCRIPTION"))) {
    up <- dirname(p)
    if (identical(up, p)) quit(status = 2L)
    p <- up
  }
  root <- p
}
hits <- .scan.pkg(root)
if (length(hits)) {
  cat("undeclared-namespace-use: ", length(hits), " check-scan WARNING line(s):\n",
      sep = "", file = stderr())
  for (hn in hits) cat("  ", hn, "\n", sep = "", file = stderr())
  quit(status = 1L)
}
cat("undeclared-namespace-use: clean (R's own two scanners, subdirs law on)\n")
