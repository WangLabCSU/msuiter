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

# GO-05 fix: the documented optional --root= (usage, line 32) must survive an
# argument-less launch; .kv's NULL default spells "required", so the sentinel
# for "absent" here is NA, which the self-locating fallback below already
# speaks (witnessed RED: tests/testthat/test-check-layout-sim.R boot unit).
root <- .kv("root", NA_character_)
if (is.na(root)) {
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
desc_tf <- file.path(root, "DESCRIPTION")
if (!file.exists(desc_tf)) {
  cat("check-layout-sim: ERROR no DESCRIPTION under --root= (", desc_tf,
      ") -- not a package root\n", sep = "")
  quit(status = 2L)
}
desc <- readLines(desc_tf, warn = FALSE)
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
# preflights green, so the fallback is effectively dev-local. When SDKROOT is
# not exported the harness now self-discovers an ambient default ahead of the
# provisioning INSTALL (.sdkroot_default: the xcrun --show-sdk-path answer,
# then the Xcode platform SDK dir newest-first, then the standard CLT SDK
# dir -- each candidate gated structurally on usr/include AND functionally by
# a minimal -isysroot link through the build's clang); an explicitly exported
# SDKROOT -- e.g. the devlog-pinned MacOsX26.5.sdk -- always wins, untouched.
# U-M8 release-eng: SDKROOT ambient default for the provisioning INSTALL's
# native build. Pure + probes injected, so the shared .sim_defs extraction
# lets tests/testthat/test-check-layout-sim-sdkroot.R drive every branch
# offline. Contract: proposes a darwin SDKROOT only while it is currently
# unset/empty -- an explicit override returns NA so callers leave the
# environment exactly as found; NA also answers when nothing trustworthy is
# discoverable (the branch CI's checked toolchain walks). Two acceptance
# legs: the proposed-dir gate (dir + usr/include) rejects dangling aliases
# and half-provisioned CLTs, and the functional gate accepts a candidate only
# after a real minimal -isysroot link through the build's clang succeeds.
# The functional leg is what the witnessed machine state demands (2026-10-15,
# reproducing block 2b's 2026-10-10 hazard note): the CLT SDK 27 answers
# xcrun --show-sdk-path with rc 0 and carries usr/include, yet every link
# through it dies on a tapi "unknown architecture" parse of its
# libSystem.B.tbd -- a structurally clean candidate can be build-hostile, and
# only an executed link can tell. Candidate order: the xcrun answer, then
# the Xcode platform SDK dir (newest first), then the standard CLT dir; the
# first candidate passing BOTH legs wins.
.sdkroot_default <- function(getenv = Sys.getenv,
                             os = if (is.character(R.version[["os"]]))
                                    R.version[["os"]] else "",
                             xcrun = "/usr/bin/xcrun",
                             clt.sdk = "/Library/Developer/CommandLineTools/MacOSX.sdk",
                             xcode.sdkdir = file.path(
                               "/Applications/Xcode.app", "Contents", "Developer",
                               "Platforms", "MacOSX.platform", "Developer",
                               "SDKs"),
                             clang = "clang",
                             arch = NULL) {
  # The darwin gate is a prefix test done with primitives, not a ^ regex:
  # the renamed base in this build misbehaves on anchors (measured 2026-10-15
  # -- anchored patterns miss matches their unanchored forms find). The live
  # platform field answers the version-suffixed darwinNN form (measured
  # darwin20), and an unrecognized or empty value declines injection.
  if (!length(os) || !is.character(os) ||
      !identical(substring(os[1L], 1L, 6L), "darwin"))
    return(NA_character_)
  cur <- try(getenv("SDKROOT", ""), silent = TRUE)
  if (!inherits(cur, "try-error") && is.character(cur) &&
      length(cur) == 1L && nzchar(cur)) {
    return(NA_character_)                    # explicit override wins, untouched
  }
  # The probe's -arch token rides the build's own arch when any source
  # speaks it: a non-empty .Platform$r_arch, else the token after -arch in
  # R CMD config CC. With neither, the flag is simply omitted (length-zero
  # collapse in the argv below) and clang answers with its default -- the
  # discriminator is the SDK's tbd parse, which needs no particular arch.
  if (is.null(arch)) {
    arch <- character(0)
    # Either renamed spelling of the platform field, but NOT R.version's
    # arch entry: its token is not one the host clang accepts (measured
    # "invalid arch name" 2026-10-15), while the build's own CC record is.
    for (a1 in list(.Platform$r_arch, .Platform$r.arch)) {
      if (is.character(a1) && length(a1) == 1L && nzchar(a1)) {
        arch <- a1
        break
      }
    }
    if (!length(arch)) {
      of <- tempfile("sdkroot-cc-")
      rc <- tryCatch(suppressWarnings(suppressMessages(
               system2(file.path(R.home(), "bin", "R"),
                       c("CMD", "config", "CC"), stdout = of,
                       stderr = "/dev/null"))),
             error = function(e) 1L)
      if (identical(rc, 0L) && file.exists(of)) {
        toks <- trimws(unlist(strsplit(paste(readLines(of, warn = FALSE),
                                             collapse = " "),
                                       " ", fixed = TRUE)))
        hit <- match("-arch", toks)
        if (!is.na(hit) && hit < length(toks) && nzchar(toks[hit + 1L]))
          arch <- toks[hit + 1L]
      }
      if (file.exists(of)) unlink(of)
    }
  }
  .usable.sdk <- function(p) {
    is.character(p) && length(p) == 1L && nzchar(p) && dir.exists(p) &&
      dir.exists(file.path(p, "usr", "include"))
  }
  # The functional leg mirrors the build's own link shape (-arch +
  # -dynamiclib) on a two-instruction dylib; any toolchain failure -- the
  # tapi/tbd parse among them -- disqualifies the candidate.
  .links <- function(sdk) {
    # The ".c" DOT is load-bearing: clang picks the language from the file
    # suffix, and a dot-less fileext leaves it as a bare token that ld
    # reports as an unknown file type (measured 2026-10-15).
    src <- tempfile(fileext = ".c")
    out <- tempfile()
    writeLines("int m(void){return 0;}", src)
    st <- tryCatch(suppressWarnings(suppressMessages(
             system2(clang, c(if (length(arch)) c("-arch", arch),
                             "-dynamiclib", "-isysroot", sdk, src, "-o", out)))),
           error = function(e) 101L)
    unlink(c(src, out))
    identical(as.integer(st), 0L)
  }
  .offer <- function(p) if (.usable.sdk(p) && .links(p)) p
  probe <- NA_character_
  if (file.exists(xcrun)) {
    of <- tempfile("sdkroot-probe-")
    rc <- tryCatch(suppressWarnings(suppressMessages(
             system2(xcrun, "--show-sdk-path", stdout = of, stderr = "/dev/null"))),
           error = function(e) 1L)
    if (identical(rc, 0L) && file.exists(of)) {
      hit <- trimws(readLines(of, warn = FALSE))
      hit <- hit[nzchar(hit)]
      if (length(hit) == 1L) {
        p <- .offer(hit[1L])
        if (!is.null(p)) probe <- p
      }
    }
    if (file.exists(of)) unlink(of)
  }
  if (is.na(probe) && dir.exists(xcode.sdkdir)) {
    # Newest first: the version-suffixed SDK names sort above any bare
    # alias, so the most recent registered platform SDK answers first.
    sdks <- sort(list.files(xcode.sdkdir, pattern = "[.]sdk$",
                            full.names = FALSE), decreasing = TRUE)
    for (s in sdks) {
      p <- .offer(file.path(xcode.sdkdir, s))
      if (!is.null(p)) { probe <- p; break }
    }
  }
  if (is.na(probe)) {
    p <- .offer(clt.sdk)
    if (!is.null(p)) probe <- p
  }
  probe
}
## The provisioning tree-identity guard: what the simulated layout runs
## against must be the build of the tree under test. R CMD INSTALL rewrites
## the source DESCRIPTION (the Collate list is re-wrapped onto one line), so
## identity is decided on the two fields that shape a build -- Version and
## the Collate file set -- not on raw bytes. A stale candidate is NAMED and
## skipped; provisioning falls through to the fresh INSTALL below, never a
## silent wrong build. Witnessed RED (tests/testthat/test-check-layout-sim.R,
## the stale-candidate unit; lane log 10-unit-stalelib-RED.log): with the
## ambient install lagging the lane's Collate, the nested run executed the
## lane's new test file against the old build and the sim self-test broke
## for a breakage that does not exist in the layout (the recorded
## provision-lib hazard).
.collate_files <- function(x) {
  hs <- grep("^Collate:", x)
  if (!length(hs)) return(character(0))
  blk <- x[seq(hs[1L], length(x))]
  nxt <- grep("^[^[:space:]]", blk)
  nxt <- nxt[nxt > 1L]
  if (length(nxt)) blk <- blk[seq_len(nxt[1L] - 1L)]
  toks <- unlist(strsplit(blk, "'", fixed = TRUE))
  keep <- !is.na(toks) & nchar(toks) >= 3L &
    substring(toks, nchar(toks) - 1L) == ".R"
  sort(unique(toks[keep]))
}
.stale_candidate <- function(l) {
  di <- tryCatch(readLines(file.path(l, pkg, "DESCRIPTION"), warn = FALSE),
                 error = function(e) NULL)
  if (is.null(di)) return(TRUE)
  get_v <- function(x) {
    v <- grep("^Version:", x, value = TRUE)
    if (length(v)) trimws(sub("^Version:[[:space:]]*", "", v[1L]))
    else NA_character_
  }
  !identical(get_v(di), get_v(desc)) ||
    !identical(.collate_files(di), .collate_files(desc))
}
.provision_lib <- function() {
  cand <- if (nzchar(lib)) c(lib, .libPaths()) else .libPaths()
  for (l in cand) {
    p <- file.path(l, pkg)
    if (dir.exists(p) &&
        file.exists(file.path(p, "DESCRIPTION")) &&
        file.exists(file.path(p, "CITATION"))) {
      if (.stale_candidate(l)) {
        cat("check-layout-sim: stale candidate", p,
            "rejected -- its installed Version/Collate lag the tree under",
            "test; provisioning a fresh INSTALL instead\n")
        next
      }
      return(l)
    }
  }
  new <- tempfile(paste0("rlib-", pkg, "-"))
  dir.create(new, recursive = TRUE)   # INSTALL refuses a missing --library dir
  # SDKROOT ambient default for the native build (block 2b). This build's
  # system2 cannot carry an env vector (measured, .run3), so the value rides
  # the harness process instead of the spawn -- scoped to the one INSTALL
  # below: set only when discovery has something to offer (which by
  # .sdkroot_default's contract requires SDKROOT to be currently unset/empty)
  # and reverted in the finally arm, which fires on every exit path including
  # an error mid-spawn. (sys.onExit exists but this 4.5.2 build's signature
  # has no local= arm -- measured -- so its attach-frame is not leaned on.)
  # --library= (NOT -l=): this build warns "unknown option" on -l= and then
  # silently targets the USER library (measured near-miss 2026-10-10).
  .install <- function() .run3(.Rbin, c("CMD", "INSTALL", "--no-byte-compile",
                                        "--no-docs",
                                        paste0("--library=", new), root), "install")
  sdk <- .sdkroot_default()
  ins <- if (is.na(sdk)) .install() else {
    cat("check-layout-sim: SDKROOT unset -- self-discovered ", sdk,
        " (provisioning INSTALL only)\n", sep = "")
    Sys.setenv(SDKROOT = sdk)
    tryCatch(.install(), finally = Sys.unsetenv("SDKROOT"))
  }
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
  # Two shapes are the measured truth: the historical three-expression
  # library/library/test_check runner, and the documented shard-handoff
  # runner (tests/testthat.R, 2026-10-21) whose only difference is that
  # the bare call became the env-unset fallback of a documented dispatch.
  # Both are policed: the handoff shape is only accepted when the file
  # STILL carries the verbatim bare test_check('msuiter') call -- so a
  # future edit cannot drop the suite without this preflight dying.
  ".has_bare_call <- function(e, target) {",
  "  if (identical(e, target)) return(TRUE)",
  "  if (!is.call(e)) return(FALSE)",
  "  any(vapply(as.list(e), .has_bare_call, logical(1), target = target))",
  "}",
  "bare <- quote(test_check('msuiter'))",
  "hist_shape <- length(shipped) == 3L &&",
  "  identical(as.character(shipped[[3L]][[1L]]), 'test_check') &&",
  "  identical(as.character(shipped[[3L]][[2L]]), 'msuiter')",
  "runner.txt <- paste0(readLines(runner.file, warn = FALSE), collapse = '\\n')",
  "handoff_shape <- grepl('MSUITER_TESTTHAT_FILTER', runner.txt) &&",
  "  grepl('MSUITER_CENSUS_ATTEST', runner.txt) &&",
  "  any(vapply(as.list(shipped), .has_bare_call, logical(1), target = bare))",
  "if (!hist_shape && !handoff_shape) {",
  "  stop('shipped runner is no longer the measured library/library/test_check shape (nor the documented shard-handoff shape)')",
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
