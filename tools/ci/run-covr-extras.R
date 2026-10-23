#!/usr/bin/env Rscript
# Covr extras runner (examples + vignettes) for the coverage lane.
#
# This leg once lived as an inline heredoc in ci.yml whose SRT render went
# through covr::to_srt -- an object covr does not export (3.6.5 exports
# tally_coverage/to_cobertura; witness: push-run 39864490318 coverage job:
# "to_srt is not an exported object from namespace:covr"). The stop landed
# outside any tryCatch, the background child exited 1, and the surrounding
# `wait || rc=1` fed that 1 to a continue-on-error step: the whole
# examples/vignettes coverage leg vanished (covmerge fragments=3, not 5)
# while the step reported success. A committed runner owns this leg now, and
# every outcome is attested -- sanctioned failure prints its verdict and
# exits 0; the only red is a defect that cannot even speak (an escape
# crash), loud by design. The shard runner run-covr-shard.R keeps its own
# MSUITER-ATTEST verdict through the shared census helper; this leg speaks
# the EXTRAS-ATTEST family, one line per type.
#
# usage: run-covr-extras.R [--types=examples,vignettes] [--out-srt-prefix=/tmp]
#                          [--root=<dir>] [--selftest]
# The merge step's glob contract: <prefix>msuiter-extras-<type>.srt.

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

.resolve.root <- function(wd) {
  p <- normalizePath(wd)
  while (!file.exists(file.path(p, "DESCRIPTION"))) {
    up <- dirname(p)
    if (identical(up, p)) return(NA_character_)
    p <- up
  }
  p
}

.execables <- function() {
  rs <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(rs)) rs <- paste0(rs, ".exe")
  rb <- file.path(R.home("bin"), "R")
  if (!file.exists(rb)) rb <- paste0(rb, ".exe")
  if (!file.exists(rs) || !file.exists(rb))
    stop("run-covr-extras: Rscript/R binary not found under ", R.home("bin"))
  list(Rscript = rs, R = rb)
}

# Byte-frozen fixture for the self-test: the good stub's tally and the exact
# SRT bytes that tally must render (the covr-srt-shape contract, one source).
.STUB_ROWS <- data.frame(
  filename = c("R/fit.R", "R/fit.R", "R/score.R"),
  line     = c(10L, 11L, 4L),
  value    = c(5L, 0L, 2L),
  stringsAsFactors = FALSE
)
.STUB_SRT <- c("5|R/fit.R:10", "0|R/fit.R:11", "2|R/score.R:4")

.run.production <- function() {
  root <- .kv("root", getwd())
  if (!file.exists(file.path(root, "DESCRIPTION"))) {
    root <- .resolve.root(root)
    if (is.na(root)) quit(status = 2L)
  }
  source(file.path(root, "tools", "ci", "covr-srt-shape.R"))
  types <- strsplit(.kv("types", "examples,vignettes"), ",", fixed = TRUE)[[1L]]
  prefix <- .kv("out-srt-prefix", "/tmp")
  attest <- function(ty, status, why = NULL, lines = NULL) {
    line <- paste0("EXTRAS-ATTEST type=", ty, " status=", status,
                   if (is.null(why)) "" else
                     paste0(" why=", gsub("[\r\n]+", " ", paste0(why, collapse = " "), useBytes = TRUE)),
                   if (is.null(lines)) "" else paste0(" lines=", lines))
    cat(line, "\n", sep = "", file = stderr())
  }
  for (ty in types) {
    cov <- tryCatch(covr::package_coverage(path = root, type = ty, quiet = TRUE,
                                           install_path = tempfile("covr-lib-"),
                                           pre_clean = FALSE),
                    error = function(e) e)
    # pre_clean = FALSE for the run-covr-shard.R reason: covr's pre-clean
    # wipes the shared src/rust/target tree the parallel shards compile into.
    if (inherits(cov, "error")) { attest(ty, "covr-failed", conditionMessage(cov)); next }
    if (!length(cov)) { attest(ty, "empty-cov"); next }
    srt <- .covr_srt_lines(cov)
    if (is.null(srt)) { attest(ty, "no-line-rows"); next }
    if (!length(srt)) { attest(ty, "empty-srt"); next }
    out <- paste0(prefix, "msuiter-extras-", ty, ".srt")
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    writeLines(srt, out)
    attest(ty, "ok", lines = length(srt))
  }
  quit(status = 0L)
}

.run.selftest <- function() {
  root <- .resolve.root(getwd())
  if (is.na(root)) stop("run-covr-extras: no DESCRIPTION ancestor for --selftest")
  ex <- .execables()
  covmerge <- file.path(root, "tools", "ci", "covmerge.py")
  if (!file.exists(covmerge)) stop("run-covr-extras: covmerge.py missing -- the roundtrip control cannot run")
  python <- Sys.which("python3")
  py <- if (!is.na(python[1L]) && nzchar(python[1L])) as.character(python[1L]) else NA_character_
  if (is.na(py)) stop("run-covr-extras: python3 not on PATH -- the covmerge roundtrip control cannot run")

  fix <- tempfile("covr-extras-selftest-")
  dir.create(fix, recursive = TRUE)
  on.exit(unlink(fix, recursive = TRUE), add = TRUE)
  stubs.src <- file.path(fix, "stub-src"); out.dir <- file.path(fix, "out")
  # This Renamed-R build rejects vector dir.create paths ("invalid 'path'
  # argument") -- the no-dir.copy family. Scalar calls only.
  dir.create(stubs.src, recursive = TRUE)
  dir.create(out.dir, recursive = TRUE)

  # paste() not paste0(): this build's paste0 ignores sep (measured 2026-10-23).
  tally.body <- paste(
    "tally_coverage <- function(cov, by, ...) {",
    "  if (!identical(by, \"line\")) stop(\"unexpected by=\", by)",
    paste0("  data.frame(filename = c(",
           paste0("\"", .STUB_ROWS$filename, "\"", collapse = ", "), "),"),
    paste0("                     line = c(", paste0(.STUB_ROWS$line, "L", collapse = ", "), "),"),
    paste0("                     value = c(", paste0(.STUB_ROWS$value, "L", collapse = ", "), "))"),
    "}", sep = "\n")

  write.stub <- function(name, with.tally, cov.body) {
    d <- file.path(stubs.src, name)
    dir.create(file.path(d, "R"), recursive = TRUE)
    writeLines(c("Package: covr", "Version: 0.0.0",
                 "Title: covr stub for the run-covr-extras self-test",
                 "Description: Synthetic stand-in installed on R_LIBS_USER.",
                 "Author: msuiter CI", "Maintainer: msuiter CI <ci@example.invalid>",
                 "License: GPL-2"), file.path(d, "DESCRIPTION"))
    writeLines(if (with.tally) c("export(package_coverage)", "export(tally_coverage)")
               else "export(package_coverage)",
               file.path(d, "NAMESPACE"))
    writeLines(c(cov.body, "", if (with.tally) tally.body), file.path(d, "R", "stub.R"))
    d
  }
  cov.ok <- "package_coverage <- function(path, type, quiet = TRUE, install_path = NULL, pre_clean = TRUE, ...) structure(list(type = type), class = \"covr-stub-coverage\")"
  cov.bad <- "package_coverage <- function(path, type, quiet = TRUE, install_path = NULL, pre_clean = TRUE, ...) stop(\"instrumented self-test failure\")"

  stubs <- list(
    good    = write.stub("good",    TRUE,  cov.ok),
    broken  = write.stub("broken",  TRUE,  cov.bad),
    phantom = write.stub("phantom", FALSE, cov.ok)
  )

  # The child sees ONLY its leg's stub library plus base packages: the real
  # covr can never leak into a control (search order puts R_LIBS_USER ahead
  # of the distribution library, so the stub shadows even a host covr).
  old.env <- Sys.getenv(c("R_LIBS_USER", "R_LIBS_SITE", "R_PROFILE", "R_ENIRON"))
  on.exit({
    gone <- names(old.env)[sapply(old.env, is.na)]
    keep <- old.env[!sapply(old.env, is.na)]
    Sys.unsetenv(gone)
    if (length(keep)) do.call(Sys.setenv, as.list(keep))
  }, add = TRUE)
  Sys.setenv(R_LIBS_SITE = "", R_PROFILE = "no", R_ENIRON = "no")

  run.child <- function(leg, type) {
    lib <- file.path(fix, paste0("lib-", leg))
    dir.create(lib, recursive = TRUE)
    st <- suppressWarnings(system2(ex$R, c("CMD", "INSTALL", "--no-docs",
                                            paste0("--library=", lib), stubs[[leg]]),
                                   stdout = file.path(out.dir, paste0("install-", leg, ".out")),
                                   stderr = file.path(out.dir, paste0("install-", leg, ".err")),
                                   wait = TRUE))
    if (is.na(st) || !identical(as.integer(st), 0L) || !file.exists(file.path(lib, "covr"))) {
      log <- character()
      for (lf in c(file.path(out.dir, paste0("install-", leg, ".out")),
                  file.path(out.dir, paste0("install-", leg, ".err"))))
        if (file.exists(lf)) log <- c(log, readLines(lf, warn = FALSE))
      stop("run-covr-extras: self-test stub ", leg, " failed to install: ",
           paste0(log, collapse = " | "))
    }
    srt <- file.path(out.dir, paste0("msuiter-extras-", type, ".srt"))
    unlink(srt)
    cap.o <- file.path(out.dir, paste0("cap-", leg, ".out"))
    cap.e <- file.path(out.dir, paste0("cap-", leg, ".err"))
    Sys.setenv(R_LIBS_USER = lib)
    r <- suppressWarnings(system2(ex$Rscript,
        c(file.path(root, "tools", "ci", "run-covr-extras.R"),
          paste0("--types=", type), paste0("--out-srt-prefix=", paste0(out.dir, "/")),
          paste0("--root=", root)),
        stdout = cap.o, stderr = cap.e, wait = TRUE))
    txt <- character()
    for (cf in c(cap.o, cap.e))
      if (file.exists(cf)) txt <- c(txt, readLines(cf, warn = FALSE))
    list(status = as.integer(r), txt = paste0(txt, collapse = "\n"), srt = srt)
  }

  defects <- character()
  expect <- function(cond, msg) if (!isTRUE(cond)) defects <<- c(defects, msg)

  # Control 1 (green + byte truth): the good stub must produce the pinned SRT
  # bytes AND covmerge must agree on their meaning.
  g <- run.child("good", "good")
  expect(identical(g$status, 0L), "good control: child status not 0")
  expect(grepl("EXTRAS-ATTEST type=good status=ok lines=3$", g$txt),
         "good control: did not speak status=ok lines=3")
  have <- if (file.exists(g$srt)) readLines(g$srt, warn = FALSE) else character()
  expect(identical(have, .STUB_SRT),
         paste0("good control: SRT bytes drift: ", paste0(have, collapse = " / ")))
  mr <- file.path(out.dir, "merged.srt"); mx <- file.path(out.dir, "cobertura.xml")
  cm <- suppressWarnings(system2(py, c(covmerge, "--fragments", g$srt,
                                       "--out-srt", mr, "--cobertura", mx),
                                 stdout = file.path(out.dir, "covmerge.out"),
                                 stderr = file.path(out.dir, "covmerge.err"),
                                 wait = TRUE))
  expect(!is.na(cm) && identical(as.integer(cm), 0L), "good control: covmerge refused the fragment")
  mtxt <- if (file.exists(mr)) paste0(readLines(mr, warn = FALSE), collapse = "\n") else ""
  expect(identical(mtxt, paste0(.STUB_SRT, collapse = "\n")),
         "good control: covmerge merged bytes drift")
  xml <- if (file.exists(mx)) paste0(readLines(mx, warn = FALSE), collapse = "\n") else ""
  expect(grepl("lines-valid=\"3\"", xml) && grepl("lines-covered=\"2\"", xml),
         "good control: cobertura says instrumented/covered not 3/2")

  # Control 2 (firing): package_coverage raising must attest covr-failed with
  # the verbatim message and write no SRT -- exit 0 (advisory posture).
  b <- run.child("broken", "broken")
  expect(identical(b$status, 0L), "broken control: sanctioned path must exit 0")
  expect(grepl("EXTRAS-ATTEST type=broken status=covr-failed why=instrumented self-test failure", b$txt),
         "broken control: did not speak the attested covr-failed verdict")
  expect(!file.exists(b$srt), "broken control: wrote an SRT anyway")

  # Control 3 (firing, the to_srt-class phantom): the consumed tally object
  # missing must attest no-line-rows, never escape as a crash.
  p <- run.child("phantom", "phantom")
  expect(identical(p$status, 0L), "phantom control: sanctioned path must exit 0")
  expect(grepl("EXTRAS-ATTEST type=phantom status=no-line-rows", p$txt),
         "phantom control: did not speak the attested no-line-rows verdict")
  expect(!file.exists(p$srt), "phantom control: wrote an SRT anyway")

  if (length(defects)) {
    for (dd in defects) cat("EXTRAS SELF-TEST FAILED:", dd, "\n", sep = " ", file = stderr())
    quit(status = 1L)
  }
  cat("EXTRAS SELF-TEST OK (3 controls: ok bytes + covmerge agreement, covr-failed, no-line-rows)\n")
  quit(status = 0L)
}

if ("--selftest" %in% .args) .run.selftest() else .run.production()
