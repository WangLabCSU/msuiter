#!/usr/bin/env Rscript
# R-version banner attestation (CI warning-zero, 2026-10-23).
#
# The warning-zero sweep was asked whether the "R 4.3" fan-out arm really
# runs R 4.3 or silently rides a fallback install -- the DESCRIPTION floor
# would otherwise be an UNPROVEN claim. Measured answer from the archived
# run 39864490318 log: the arm printed the resolver banner
# '"r_version": "R version 4.3.3 (2024-02-29)"', the cache key
# 'Ubuntu 24.04.5 LTS-R version 4.3.3 ...', the check banner
# '* using R version 4.3.3 (2024-02-29)' and satrep 'R version 4.3.3 ...'
# -- five independent attestations, no fallback. Settling that cost five
# greps over five differently-phrased banners; this tool makes the lane
# attest the fact itself, once, fail-closed:
#   * every fan-out arm / guards-shards / guard-prep run must print
#     MSUITER-R-VERSION-ATTEST ... status=ok or the step reddens;
#   * the arm's R must satisfy the DESCRIPTION Depends: R (>= x.y) floor
#     (an arm under its own declared floor cannot certify that floor);
#   * a NUMERIC matrix label (4.3) must be the resolved version's prefix --
#     a silent resolver fallback to another install is caught here.
# Parsing failure is refusal, never silence (fail-closed law).
#
# usage: attest-r-version.R [--root=<dir>] [--label=<matrix label>]
#                           [--selftest]

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

.vparse <- function(v) {
  parts <- strsplit(trimws(v), ".", fixed = TRUE)[[1L]]
  parts <- parts[grepl("^[0-9]+$", parts)]
  if (!length(parts)) return(NA_integer_)
  suppressWarnings(as.integer(parts))
}
# v1 >= v2 elementwise (shorter side zero-padded). NA on unparseable input.
.vge <- function(v1, v2) {
  a <- .vparse(v1); b <- .vparse(v2)
  if (is.na(a[1L]) || is.na(b[1L])) return(NA)
  n <- max(length(a), length(b))
  if (length(a) < n) a[(length(a) + 1L):n] <- 0L
  if (length(b) < n) b[(length(b) + 1L):n] <- 0L
  all(a >= b)
}

.desc.floor <- function(root) {
  dcf <- file.path(root, "DESCRIPTION")
  if (!file.exists(dcf)) stop("attest-r-version: no DESCRIPTION at ", root)
  txt <- readLines(dcf, warn = FALSE)
  hit <- grepl("^Depends:[[:space:]]*R[[:space:]]*\\(", txt)
  if (!any(hit)) stop("attest-r-version: DESCRIPTION has no Depends: R (>= x.y) floor")
  line <- txt[hit][1L]
  # sub-chain over regmatches-after=: this build's regmatches carries no
  # after= argument (measured 2026-10-23, the renamed-argument family).
  tail <- sub("^.*R[[:space:]]*\\(>=[[:space:]]*", "", line)
  cap <- sub("[^0-9.].*$", "", tail)
  if (!grepl("^[0-9]+(\\.[0-9]+)*$", cap))
    stop("attest-r-version: cannot parse the R floor: ", line)
  cap
}

# Returns list(status = 0/1, line = the spoken attestation).
.check <- function(root, label, floor.override = NULL) {
  say <- function(payload) {
    line <- paste0("MSUITER-R-VERSION-ATTEST ", payload)
    cat(line, "\n", sep = "", file = stderr())
    line
  }
  # Key-shape law (Renamed-R build, measured 2026-10-23): the version list
  # uses major + minor (minor carries the patch), NOT upstream's
  # major.minor + patch, and getRversion is a bare scalar here. Read both
  # shapes so the attestation speaks the same bytes on either build.
  mm <- version[["major.minor"]]; pt <- version[["patch"]]
  ver <- if (!is.null(mm) && !is.null(pt)) paste0(mm, ".", pt)
         else paste0(version[["major"]], ".", version[["minor"]])
  vstring <- version[["version.string"]]
  if (!is.character(vstring) || !nzchar(vstring))
    stop("attest-r-version: R.version$version.string is empty -- refused")
  floor <- if (!is.null(floor.override)) floor.override else .desc.floor(root)
  ok.floor <- .vge(ver, floor)
  if (is.na(ok.floor) || !ok.floor) {
    return(list(status = 1L, line = say(paste0(
      "label=", label, " version=", vstring, " floor=", floor,
      " status=refused (R ", ver, " under the DESCRIPTION floor ", floor,
      " or unparseable)"))))
  }
  # Numeric matrix label: the resolver must have honored the pin exactly.
  if (grepl("^[0-9]+(\\.[0-9]+)*$", label)) {
    want <- .vparse(label); have <- .vparse(ver)
    n <- length(want)
    if (length(have) < n || !identical(have[seq.int(n)], want)) {
      return(list(status = 1L, line = say(paste0(
        "label=", label, " version=", vstring,
        " status=refused (resolver delivered ", ver, " for label ", label, ")"))))
    }
  }
  list(status = 0L, line = say(paste0(
    "label=", label, " version=", vstring, " floor=", floor, " status=ok")))
}

.walk.to.root <- function(start) {
  p <- normalizePath(start)
  while (!file.exists(file.path(p, "DESCRIPTION"))) {
    up <- dirname(p)
    if (identical(up, p)) return(NA_character_)
    p <- up
  }
  p
}

if ("--selftest" %in% .args) {
  root <- .walk.to.root(.kv("root", getwd()))
  if (is.na(root)) quit(status = 2L)
  defects <- character()
  expect <- function(cond, msg) if (!isTRUE(cond)) defects <- c(defects, msg)
  ok <- .check(root, "release")
  expect(identical(ok$status, 0L),
         paste0("self-test: honest check refused (control cannot be green): ", ok$line))
  expect(grepl("status=ok", ok$line), "self-test: the ok attestation was not spoken")
  imp <- .check(root, "release", floor.override = "99.0")
  expect(identical(imp$status, 1L), "self-test: impossible floor did NOT redden")
  expect(grepl("status=refused", imp$line), "self-test: floor refusal line was not spoken")
  lbl <- .check(root, "99.9")
  expect(identical(lbl$status, 1L), "self-test: impossible numeric label did NOT redden")
  expect(grepl("status=refused", lbl$line), "self-test: label refusal line was not spoken")
  if (length(defects)) {
    for (dd in defects) cat("R-VERSION SELF-TEST FAILED:", dd, "\n", sep = " ", file = stderr())
    quit(status = 1L)
  }
  cat("R-VERSION SELF-TEST OK (green, floor-refusal fires, label-refusal fires)\n")
  quit(status = 0L)
}

root <- .walk.to.root(.kv("root", getwd()))
if (is.na(root)) quit(status = 2L)
quit(status = .check(root, .kv("label", "unlabeled"))$status)
