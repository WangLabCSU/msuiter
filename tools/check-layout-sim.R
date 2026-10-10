#!/usr/bin/env Rscript
# check-layout-sim.R -- run the testthat suite under a simulated R CMD check
# test layout (U-M7-04 GO-04D, controller addendum 2026-10-10).
#
# Why: the release-materials guard died in CI ONLY under R CMD check. The
# check test phase runs the tests from <out>/<pkg>.Rcheck/tests/testthat --
# a SIBLING of the extracted/installed tree, not inside it (measured live:
# cwd is <pkg>.Rcheck/tests/testthat and testthat::test_path() then hands
# back the raw relative path, so every ../../<repo-artifact> resolves ABOVE
# the check directory). Tests reaching repo files via test_path('../../...')
# must therefore locate them by ancestor-walk / system.file fallback or skip
# with an explicit reason. This harness reproduces that layout from the real
# tarball so the class is caught locally, not in CI.
#
# Contract:
#   1. R CMD build the tarball -- the REAL .Rbuildignore semantics (no docs/,
#      no _pkgdown.yml, no bench/) are enforced, not guessed;
#   2. extract into <tmp>/<pkg>.Rcheck/{<pkg>.Exx, tests} exactly as check
#      presents them (tests/ SIBLING of <pkg>.Exx; asserted);
#   3. execute the REAL test files (never reimplementations) with the live
#      cwd inside <pkg>.Rcheck/tests/testthat, msuiter loaded from --lib=
#      (or the ambient .libPaths());
#   4. print one machine-verifiable line
#        SIM-VERDICT: PASS|FAIL files=<n> FAIL=<f> SKIP=<s> UNAUTHORIZED_SKIP=<u> PASS=<p> WARN=<w>
#      and exit 1 unless FAIL=0 and every skip reason matches the sanctioned
#      allowlist below (an unlisted skip = a guard silently losing teeth).
#
# Recursion guard: SIM_CHECK_LAYOUT_ACTIVE=1 is exported into the simulated
# run, so in-suite units that drive THIS script skip there instead of forking
# unboundedly.
#
# Usage: Rscript tools/check-layout-sim.R [--root=<repo>] [--lib=<dir>]
#        [--filter=<name>] [--keep]
# Exit:  0 SIM-VERDICT PASS; 1 FAIL or unauthorized skip; 2 harness
#        precondition failure (build/extract/load).

.args <- local({
  ca <- try(commandArgs(trailingOnly = TRUE), silent = TRUE)
  if (inherits(ca, "try-error")) ca <- character()
  ca <- as.character(ca)
  ca <- ca[nzchar(ca)]
  seps <- which(ca == "--args")
  if (length(seps)) ca <- ca[(seps[1L] + 1L):length(ca)]
  sub("^--", "", ca[grep("^--", ca)])
})
.kv <- function(k, default = NULL) {
  hit <- grep(paste0("^", k, "="), .args)
  if (!length(hit)) {
    if (is.null(default)) {
      cat("check-layout-sim: ERROR missing --", k, "= argument\n", sep = "")
      quit(status = 2L)
    }
    return(default)
  }
  sub(paste0("^", k, "="), "", .args[hit[1L]])
}
.flag <- function(k) any(.args == k)

# nesting guard: the simulated runner exports SIM_CHECK_LAYOUT_ACTIVE=1, so
# an in-suite unit must never re-drive this harness from inside it (the
# in-suite twin skips on the same marker; this makes a broken marker fail
# closed instead of recursing).
if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
  cat("check-layout-sim: ERROR refusing to nest inside an active simulated run\n")
  quit(status = 2L)
}

.ancestor_pkg_root <- function(pkg, start) {
  d <- normalizePath(start)
  repeat {
    f <- file.path(d, "DESCRIPTION")
    if (file.exists(f)) {
      ls <- readLines(f, n = 40L, warn = FALSE)
      pat <- paste0("^Package:[[:space:]]*", pkg, "[[:space:]]*$")
      if (length(grep(pat, ls))) return(d)
    }
    up <- dirname(d)
    if (identical(up, d)) return(NA_character_)
    d <- up
  }
}
# this build's system2 (measured 2026-10-10): a named env= vector is rendered
# unquoted into an sh -c line (parens in the session environment break it) and
# the "2>&1" stderr magic is quoted as a literal file name. Call subprocesses
# through this helper instead: never env=, always real stdout/stderr paths.
.run3 <- function(cmd, args, tag) {
  of <- file.path(work, paste0(tag, ".out"))
  ef <- file.path(work, paste0(tag, ".err"))
  rc <- system2(cmd, args, stdout = of, stderr = ef)
  txt <- character()
  if (file.exists(of)) txt <- c(txt, readLines(of, warn = FALSE))
  if (file.exists(ef)) txt <- c(txt, readLines(ef, warn = FALSE))
  list(rc = rc, log = txt)
}
# Every subprocess must resolve R.home-ABSOLUTE: when this harness is
# driven from an in-check suite (the in-suite unit under a real R CMD
# check), the parent's PATH carries tools:::add_dummies' par. 1.6 stubs
# prepended (<checkdir>/tests/R_check_bin/{R,Rscript}: echo-warning +
# exit 1, mode 0755 -- re-verified verbatim from the live 4.5.2) and a
# bare-name "R"/"Rscript" spawn dies there (measured CI-shape RED,
# 2026-10-10). Fail-closed: inability to resolve is a STOP, never a
# PATH-resolved fallback that the stubs would silently intercept.
.abs_bin <- function(name) {
  p <- file.path(R.home(), "bin", name)
  if (!file.exists(p)) p <- file.path(R.home(), "bin", paste0(name, ".exe"))
  if (!file.exists(p)) {
    stop("R.home-absolute ", name, " not locatable -- refusing PATH-resolved spawn")
  }
  p
}
.Rbin <- .abs_bin("R")
.Rscript.bin <- .abs_bin("Rscript")

# R string-literal emitter for GENERATED code (GO-04F, windows arms):
# Windows tempfile() hands back backslashed paths and R consumes backslash
# escapes at PARSE time of the generated file ("'\c' is an unrecognized
# escape", <input>:1:70 -- the sim never started there). The model is the
# R-native model of the single-quoted literal: backslashes double FIRST
# (so its escaping is never re-doubled), then a single quote is escaped
# via backslash-quote. R has NO quote-doubling mechanism: the '' form
# mis-lexes as two juxtaposed string constants (measured: <text>:1:16
# unexpected string constant). Anything beyond that model (control
# characters, non-scalars) FAILS CLOSED, so a path the model cannot
# represent is never silently reinterpreted.
.r_str <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    stop("check-layout-sim: generated literal needs a non-missing scalar character path")
  }
  if (grepl("[[:cntrl:]]", x)) {
    stop("check-layout-sim: control character in path -- refusing to emit an unsafe string literal")
  }
  e <- gsub("\\", "\\\\", x, fixed = TRUE)
  e <- gsub("\'", "\\'", e, fixed = TRUE)
  paste0("'", e, "'")
}

root <- .kv("root", NULL)
if (is.null(root)) {
  # package name from the cwd's DESCRIPTION if present, else msuiter default
  desc0 <- file.path(getwd(), "DESCRIPTION")
  pkgguess <- "msuiter"
  if (file.exists(desc0)) {
    l0 <- readLines(desc0, n = 40L, warn = FALSE)
    g <- grep("^Package:[[:space:]]", l0)
    if (length(g)) pkgguess <- trimws(sub("^Package:[[:space:]]*", "", l0[g[1L]]))
  }
  root <- .ancestor_pkg_root(pkgguess, getwd())
  if (is.na(root)) {
    cat("check-layout-sim: ERROR cannot locate package root from ", getwd(),
        " -- pass --root=<repo>\n", sep = "")
    quit(status = 2L)
  }
}
desc <- readLines(file.path(root, "DESCRIPTION"), warn = FALSE)
pg <- grep("^Package:[[:space:]]*", desc)
vg <- grep("^Version:[[:space:]]*", desc)
if (!length(pg) || !length(vg)) {
  cat("check-layout-sim: ERROR --root= lacks Package:/Version: fields\n")
  quit(status = 2L)
}
pkg <- trimws(sub("^Package:[[:space:]]*", "", desc[pg[1L]]))
lib <- .kv("lib", "")
if (!nzchar(lib)) lib <- trimws(Sys.getenv("R_LIBS_PATHS", ""))  # sanctioned temp-lib convention
filter <- .kv("filter", "")
keep <- .flag("keep")

# Sanctioned skip reasons. An unlisted skip means some guard silently lost
# its teeth in the check layout -- that is a harness FAIL, not a pass.
#   1. the repository-drift guards' own documented check-context skips;
#   2. the refdb eol guard (needs a git checkout);
#   3. release-materials legs whose sources are not installed/shipped
#      (tools/gen-citation.R, NEWS.md, _pkgdown.yml -- all buildignored or
#      source-only per .Rbuildignore);
#   4. the GO-04D recursion guard (unit already running inside this sim).
# Matching is REGEX-FREE by necessity: this build's regexpr treats parens as
# literals and does not anchor $ (both measured 2026-10-10) -- only plain
# substring containment and substr-based end-anchoring are dependable.
SANCTIONED_ENDS <- "(R CMD check context)"
SANCTIONED_HAS <- c(
  "requires the source checkout",
  "not installed",
  "not shipped in the tarball",
  "already running inside the simulated check layout"
)
.endswith <- function(s, suf) {
  ns <- nchar(s); nf <- nchar(suf)
  nf <= ns && identical(substr(s, ns - nf + 1L, ns), suf)
}

# Workdir lives OUTSIDE the R session tempdir: quit() removes the session
# tempdir wholesale, which silently defeated --keep (measured 2026-10-10).
.wbase <- dirname(tempdir())
work <- NA_character_
for (.i in 1L:1000L) {
  cand <- tempfile(paste0("check-layout-sim-", pkg, "-"), tmpdir = .wbase)
  if (!file.exists(cand)) {
    dir.create(cand, recursive = TRUE)
    if (dir.exists(cand)) { work <- cand; break }
  }
}
if (is.na(work)) {
  cat("check-layout-sim: ERROR cannot create workdir under ", .wbase, "\n", sep = "")
  quit(status = 2L)
}
if (!keep) on.exit(unlink(work, recursive = TRUE))

## 1. the real tarball ------------------------------------------------------
.wd0 <- getwd()
invisible(setwd(work))   # this build's system2 has no wd= argument (measured)
b <- .run3(.Rbin,
           c("CMD", "build", "--no-build-vignettes", "--no-manual",
             "--compact-vc-exclusions", root),
           "build")
invisible(setwd(.wd0))
if (!identical(b$rc, 0L)) {
  cat(b$log, sep = "\n")
  cat("check-layout-sim: ERROR R CMD build failed (rc ", b$rc, ")\n", sep = "")
  quit(status = 2L)
}
tar <- list.files(work, pattern = paste0("^", pkg, "_.*[.](tar[.]gz|tgz|zip)$"))
if (length(tar) != 1L) {
  cat("check-layout-sim: ERROR expected one tarball, found: ",
      paste0(tar, collapse = ", "), "\n", sep = "")
  quit(status = 2L)
}

## 2. the MEASURED check layout --------------------------------------------
# real check presents: <out>/<pkg>.Rcheck/{<pkg>.Exx (extracted tarball),
# tests (copy, the test-phase cwd lives in tests/testthat)}.
rcheck <- file.path(work, paste0(pkg, ".Rcheck"))
dir.create(rcheck, recursive = TRUE)
t3 <- .run3("tar", c("-xzf", file.path(work, tar), "-C", rcheck), "tar")
if (!identical(t3$rc, 0L)) {
  cat(t3$log, sep = "\n")
  cat("check-layout-sim: ERROR tarball extraction failed (rc ", t3$rc, ")\n", sep = "")
  quit(status = 2L)
}
.raw <- file.path(rcheck, pkg)
if (!dir.exists(.raw)) {
  cat("check-layout-sim: ERROR extraction did not present ", pkg, "/\n", sep = "")
  quit(status = 2L)
}
.exx <- file.path(rcheck, paste0(pkg, ".Exx"))
invisible(file.rename(.raw, .exx))          # this build's file.rename returns visibly
if (!dir.exists(file.path(.exx, "tests"))) {
  cat("check-layout-sim: ERROR the tarball carries no tests/\n")
  quit(status = 2L)
}
.tests <- file.path(rcheck, "tests")
invisible(file.rename(file.path(.exx, "tests"), .tests))   # move out, as check does
if (!dir.exists(.exx) || !dir.exists(.tests)) {
  cat("check-layout-sim: ERROR layout assembly failed under ", rcheck, "\n", sep = "")
  quit(status = 2L)
}
if (!file.exists(file.path(.tests, "testthat.R"))) {
  cat("check-layout-sim: ERROR tests/testthat.R runner missing\n")
  quit(status = 2L)
}
for (absent in c("_pkgdown.yml", "docs", "bench")) {
  if (file.exists(file.path(.exx, absent))) {
    cat("check-layout-sim: ERROR ", absent, " leaked into the tarball -- .Rbuildignore drift\n",
        sep = "")
    quit(status = 2L)
  }
}

## 2b. an installed tree the test phase can load ----------------------------
# The simulated run resolves system.file() fallbacks against a real installed
# tree; preflight the ambient libraries (--lib= first, then .libPaths()) for
# an msuiter install carrying DESCRIPTION+CITATION; only when none exists,
# R CMD INSTALL to a throwaway lib dir (the sanctioned
# R_LIBS_PATHS=/tmp/rlib-$$ pattern -- never the user library). The
# fallback path drives the native build (configure + rust): on this dev
# machine it needs the SDKROOT=...MacOSX.sdk prefix because the CLT SDK 27
# libSystem.B.tbd trips tapi (measured 2026-10-10); CI's checked toolchain
# preflights green, so the fallback is effectively dev-local.
.provision_lib <- function() {
  cand <- if (nzchar(lib)) c(lib, .libPaths()) else .libPaths()
  for (l in cand) {
    p <- file.path(l, pkg)
    if (dir.exists(p) &&
        file.exists(file.path(p, "DESCRIPTION")) &&
        file.exists(file.path(p, "CITATION"))) return(l)
  }
  new <- tempfile(paste0("rlib-", pkg, "-"))
  dir.create(new, recursive = TRUE)   # INSTALL refuses a missing --library dir
  # --library= (NOT -l=): this build warns "unknown option" on -l= and then
  # silently targets the USER library (measured near-miss 2026-10-10).
  ins <- .run3(.Rbin, c("CMD", "INSTALL", "--no-byte-compile", "--no-docs",
                      paste0("--library=", new), root), "install")
  if (!identical(ins$rc, 0L)) {
    cat(ins$log, sep = "\n")
    cat("check-layout-sim: ERROR provisioning R CMD INSTALL failed (rc ",
        ins$rc, ")\n", sep = "")
    quit(status = 2L)
  }
  if (!file.exists(file.path(new, pkg, "CITATION"))) {
    cat("check-layout-sim: ERROR provisioned tree lacks CITATION (inst/CITATION drift?)\n")
    quit(status = 2L)
  }
  new
}
runlib <- .provision_lib()

## 3. execute the REAL test files from inside the check layout -------------
# Config travels via a KEY=VALUE file whose path is embedded in the generated
# runner: this build's system2 cannot carry an env vector intact (measured).
envf <- file.path(work, "sim-env.txt")
writeLines(c(paste0("LIB=", runlib),
             paste0("TESTS=", .tests),
             paste0("RESULT=", work)),
           envf)
runner <- file.path(work, "sim-runner.R")
# The generated runner embeds the config-file path as an R string literal
# (its first line). Windows tempfile() hands back backslashed paths and R
# string literals consume backslash escapes at PARSE time -- the windows
# arm RED of 2026-10-10 ("'\c' is an unrecognized escape in character
# string", <input>:1:70, before the sim body ever ran). Extracting the
# vector to .runner_lines() makes the generator unit-testable against a
# synthetic Windows path; emission must route through .r_str()'s
# fail-closed escaping.
.runner_lines <- function(envf_path) c(
  paste0("envf <- ", .r_str(envf_path)),
  ".cfgf <- local({",
  "  ls <- readLines(envf, warn = FALSE)",
  "  g <- function(k, d) {",
  "    h <- grep(paste0('^', k, '='), ls)",
  "    if (!length(h)) d else sub(paste0('^', k, '='), '', ls[h[1L]])",
  "  }",
  "  list(lib = g('LIB', ''), tests = g('TESTS', ''), result = g('RESULT', ''))",
  "})",
  "libch <- function(s) { s <- trimws(s); if (!nzchar(s)) character() else strsplit(s, .Platform$path.sep)[[1]] }",
  ".libPaths(unique(c(libch(.cfgf$lib), .libPaths())))",
  "# recursion marker for in-suite units that would otherwise re-drive this harness",
  "invisible(Sys.setenv(SIM_CHECK_LAYOUT_ACTIVE = '1'))",
  "suppressMessages(library(testthat))",
  "if (!suppressMessages(requireNamespace('msuiter'))) {",
  "  cat('check-layout-sim: ERROR msuiter not loadable from: ', paste0(.libPaths(), collapse = ' | '), '\\n', sep = '')",
  "  quit(status = 2L)",
  "}",
  "# the verdict needs the COMPLETE manifest: never let testthat's max-fails",
  "# circuit truncate the run (a truncated manifest would hide later files).",
  "# Failures still fail the verdict -- they are counted, not silenced.",
  "invisible(testthat::set_max_fails(Inf))",
  "if (!dir.exists(.cfgf$tests)) stop('TESTS dir missing: ', .cfgf$tests)",
  "setwd(.cfgf$tests)",          # check runs the test phase from inside tests/,
  "# ...and drives the SAME entry as the shipped tests/testthat.R",
  "# (measured: library(testthat); library(msuiter); test_check('msuiter')).",
  "# Only test_check(load_package='installed') parents the test env to the",
  "# package namespace, so internal .ms_* helpers the suite legitimately",
  "# calls resolve exactly as they do under a real R CMD check. The one",
  "# control override is stop_on_failure: test_dir's default TRUE quits at",
  "# the first failure and truncates the manifest; the harness implements",
  "# its own fail semantics through the SIM-VERDICT gate below.",
  "runner.file <- file.path(.cfgf$tests, 'testthat.R')",
  "if (!file.exists(runner.file)) stop('shipped tests/testthat.R missing')",
  "shipped <- parse(file = runner.file)",
  "if (!length(shipped) == 3L ||",
  "    !identical(as.character(shipped[[3L]][[1L]]), 'test_check') ||",
  "    !identical(as.character(shipped[[3L]][[2L]]), 'msuiter')) {",
  "  stop('shipped runner is no longer the measured library/library/test_check shape')",
  "}",
  "res <- testthat::test_check(package = 'msuiter', stop_on_failure = FALSE)",
  "if (!inherits(res, 'testthat_results') && !is.list(res)) {",
  "  cat('check-layout-sim: ERROR shipped runner returned no result set\\n')",
  "  quit(status = 2L)",
  "}",
  ".hc <- function(p, s) { m <- try(regexpr(p, s), silent = TRUE)",
  "  if (inherits(m, 'try-error')) return(FALSE)",
  "  length(m) && !is.na(m[1L]) && m[1L] >= 0L }",
  "# FAIL-CLOSED manifest: walk test-case -> e$results expectation objects",
  "# (testthat 3.3.2 measured: res elements are case lists carrying file/test/",
  "# results; the expectations themselves are the class-bearing objects).",
  "fkeys <- character(); tkeys <- character(); vals <- list(); rsns <- character()",
  "for (e in res) {",
  "  fl <- if (is.null(e$file)) 'NA' else as.character(e$file)",
  "  tl <- if (is.null(e$test)) 'NA' else as.character(e$test)",
  "  cnt <- c(0, 0, 0, 0, 0)",
  "  rsn <- ''",
  "  rs <- if (is.null(e$results)) list() else e$results",
  "  for (x in rs) {",
  "    cs <- paste0(',', paste0(class(x), collapse = ','), ',')",
  "    iserr <- .hc(',expectation_error,', cs)   # errors carry bare 'error' too --",
  "    cnt <- cnt + c(as.integer(!iserr && .hc(',expectation_failure,', cs)),  # match expectation_* only",
  "                   as.integer(.hc(',expectation_skip', cs)),",
  "                   as.integer(.hc(',expectation_success,', cs)),",
  "                   as.integer(.hc(',expectation_warning,', cs)),",
  "                   as.integer(iserr))",
  "    if (.hc(',expectation_skip', cs) && !nzchar(rsn) && !is.null(x$message)) {",
  "      rsn <- paste0(as.character(x$message), collapse = ' ')",
  "      rsn <- sub('^Reason:[[:space:]]*', '', trimws(rsn))",
  "    }",
  "  }",
  "  i <- which(fkeys == fl & tkeys == tl)",
  "  if (!length(i)) {",
  "    fkeys <- c(fkeys, fl); tkeys <- c(tkeys, tl)",
  "    vals[[length(vals) + 1L]] <- cnt; rsns <- c(rsns, rsn)",
  "  } else {",
  "    vals[[i[1L]]] <- vals[[i[1L]]] + cnt",
  "    if (!nzchar(rsns[i[1L]]) && nzchar(rsn)) rsns[i[1L]] <- rsn",
  "  }",
  "}",
  "rows <- character()",
  "for (j in seq_along(fkeys)) {",
  "  v <- vals[[j]]",
  "  rsn <- gsub('[|]', '~', gsub('[\r\n]', ' ; ', rsns[j], fixed = FALSE))",
  "  rows <- c(rows, paste0('SIMTEST|', gsub('[|]', '~', fkeys[j]), '|',",
  "                         gsub('[|]', '~', tkeys[j]), '|',",
  "                         v[1L], '|', v[2L], '|', v[3L], '|', v[4L], '|',",
  "                         v[5L], '|', rsn))",
  "}",
  "writeLines(rows, file.path(.cfgf$result, 'sim-result.tsv'))",
  "quit(status = 0L)"
)
writeLines(.runner_lines(envf), runner)
r3 <- .run3(.Rscript.bin, runner, "sim")
rc <- r3$rc
log <- r3$log
if (!identical(rc, 0L)) {
  cat(log, sep = "\n")
  cat("check-layout-sim: ERROR simulated run exited rc ", rc, "\n", sep = "")
  quit(status = 2L)
}

resfile <- file.path(work, "sim-result.tsv")
if (!file.exists(resfile)) {
  cat(log, sep = "\n")
  cat("check-layout-sim: ERROR simulated run wrote no result manifest\n")
  quit(status = 2L)
}
rows <- readLines(resfile, warn = FALSE)
rows <- rows[grep("^SIMTEST\\|", rows)]
if (!length(rows)) {
  cat("check-layout-sim: ERROR empty result manifest\n")
  quit(status = 2L)
}
parse <- strsplit(rows, "|", fixed = TRUE)
# this build's strsplit DROPS trailing empty fields (base R keeps them;
# measured) -- pad the optional reason column back in.
parse <- lapply(parse, function(r) {
  if (length(r) > 9L) stop("malformed manifest row (", length(r), " fields)")
  if (length(r) < 9L) r <- c(r, rep("", 9L - length(r)))
  r
})
if (!identical(unique(unlist(lapply(parse, length), use.names = FALSE)), 9L)) {
  cat("check-layout-sim: ERROR manifest normalization failed\n")
  quit(status = 2L)
}
# explicit column extraction (this build's vapply takes FUN.VALUE positionally;
# measured) -- no keyword simplification idioms here. Numeric columns coerce
# NA -> 0 defensively; errored units are counted by their own ERR column.
.col <- function(i, numeric. = FALSE) {
  v <- unlist(lapply(parse, function(r) r[[i]]), use.names = FALSE)
  if (numeric.) {
    v <- suppressWarnings(as.numeric(v))
    v[is.na(v)] <- 0
    v
  } else as.character(v)
}
f_file <- .col(2L)
f_test <- .col(3L)
f_fail <- .col(4L, numeric. = TRUE)
f_skip <- .col(5L, numeric. = TRUE)
f_pass <- .col(6L, numeric. = TRUE)
f_warn <- .col(7L, numeric. = TRUE)
f_err  <- .col(8L, numeric. = TRUE)
f_reason <- .col(9L)
ne <- sum(f_err)
nf <- sum(f_fail) + ne   # an errored unit is never a pass and never invisible
ns <- sum(f_skip); np <- sum(f_pass); nw <- sum(f_warn)

# vacuity guard: the guard files that the filter permits must have run
basenames <- sub("^.*[/\\\\]", "", f_file)
required <- c("test-release-materials.R", "test-docs-sync.R")
if (nzchar(filter)) required <- required[grep(filter, required, perl = TRUE)]
for (n in required) {
  if (!any(basenames == n)) {
    cat("check-layout-sim: ERROR ", n, " did not execute in the simulated layout\n",
        sep = "")
    quit(status = 2L)
  }
}

# Skip reasons arrive STRUCTURALLY (manifest column 9, harvested by the runner
# from the skip expectation objects' $message): reporter prose is context-
# dependent (measured), the object field is not. A skip with no reason string
# FAILS CLOSED (unauthorized).
reasons <- unique(trimws(f_reason[f_skip > 0L & nzchar(f_reason)]))
if (ns > 0L && !length(reasons)) {
  reasons <- paste0("<unparsed-skip x", ns, ">")
}
.sanctioned <- function(s) {
  if (.endswith(s, SANCTIONED_ENDS)) return(TRUE)
  for (p in SANCTIONED_HAS) {
    m <- try(regexpr(p, s), silent = TRUE)   # literal patterns only -- measured-safe
    if (!inherits(m, "try-error") && length(m) && !is.na(m[1L]) && m[1L] >= 0L)
      return(TRUE)
  }
  FALSE
}
unauth <- character()
for (s in unique(reasons)) if (!.sanctioned(s)) unauth <- c(unauth, s)

fail <- nf > 0L || length(unauth) > 0L
cat("check-layout-sim: layout=", basename(rcheck), "/tests/testthat (sibling of ",
    pkg, ".Exx/) files=", length(unique(f_file)), " executed\n", sep = "")
if (ne > 0L) cat("check-layout-sim: ERRORed units: ", ne, "\n", sep = "")
# Attribute the failures in the LOG itself: the workdir (and sim-result.tsv
# inside it) is transient without --keep, so identity must not depend on it.
BAD_CAP <- 40L
bad <- which(f_fail > 0L | f_err > 0L)
for (k in head(bad, BAD_CAP)) {
  cat("check-layout-sim: FAILING UNIT ", f_file[k], " :: ", f_test[k],
      " fail=", as.integer(f_fail[k]), " err=", as.integer(f_err[k]),
      if (nzchar(f_reason[k])) paste0(" reason=", f_reason[k]) else "",
      "\n", sep = "")
}
if (length(bad) > BAD_CAP) {
  cat("check-layout-sim:   ... ", length(bad) - BAD_CAP,
      " more (sim-result.tsv in the --keep workdir)\n", sep = "")
}
for (s in unique(reasons)) {
  cat("check-layout-sim: skip[", if (.sanctioned(s)) "sanctioned" else "UNAUTHORIZED",
      "]: ", s, "\n", sep = "")
}
cat("SIM-VERDICT: ", if (fail) "FAIL" else "PASS",
    " files=", length(unique(f_file)), " FAIL=", as.integer(nf),
    " SKIP=", as.integer(ns), " UNAUTHORIZED_SKIP=", length(unauth),
    " PASS=", as.integer(np), " WARN=", as.integer(nw), "\n", sep = "")
if (keep) cat("check-layout-sim: kept workdir ", work, "\n", sep = "")
quit(status = if (fail) 1L else 0L)
