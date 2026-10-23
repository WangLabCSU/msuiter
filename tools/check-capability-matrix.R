#!/usr/bin/env Rscript
# capability-matrix truth: the checkmark is a proof, not a promise
# (docs-honesty law, 2026-10-23).
#
# docs/CAPABILITY-MATRIX.md is the contract a reader trusts at a glance: a
# checkmark on a row reads as "this ships". The legend once said otherwise
# (checkmark = "designed"), and four claims rode that gap -- a phantom engine
# variant, a never-written epidemiology panel, an M0-skeleton-era refdb
# updater and an HTML/PDF report face that does not exist. This validator
# closes the semantic gap mechanically: the legend now pins checkmark =
# delivered, every delivered-claim must name a NAMESPACE-listed export, and
# every engine="..." a row offers must be in the kernel variant set that
# R/engines-nmf.R declares (.ms_nmf_variants).
#
# One-directional by law: a delivered-claim that cannot be proven reddens the
# run; an unclaimed (deferred, exploratory, not-done) capability is never
# chased. Under-claiming stays green so the matrix drifts toward truth, never
# toward bravado.
#
# One gate, three faces: this CLI (the CI docs job; pure file reads, no
# package load), the tests/testthat/ gate which sources this file (the
# five-gate ledger and local dev), and --self-test which plants a ghost API
# and a ghost engine variant and PROVES the predicates fire -- governance-
# scan law: a gate that cannot go red on an invention is decoration.

.ms_cm_glyphs <- function() {
  # Status glyphs are built from codepoints at runtime, never from source
  # escapes: a mis-typed literal would silently stop matching and the gate
  # would go vacuous-green.
  list(
    delivered = intToUtf8(0x2705L),  # heavy checkmark
    partial   = intToUtf8(0x1F536L), # (partial: v1 baseline)
    deferred  = intToUtf8(0x23F3L),  # hourglass (v1.x)
    notdone   = intToUtf8(0x274CL)   # heavy ballot X
  )
}

# Rows whose STATUS column reads as delivered: a checkmark present and no
# partial/deferred/absent marker anywhere on the row. A mixed row exits the
# delivered-reading instead of being half-trusted -- the safe direction of
# the one-directional law.
.ms_cm_delivered_rows <- function(lines) {
  g <- .ms_cm_glyphs()
  rows <- lines[grepl(g$delivered, lines, fixed = TRUE)]
  if (!length(rows)) return(rows)
  guard <- Reduce(`|`, lapply(g[c("partial", "deferred", "notdone")],
                              function(glyph) grepl(glyph, rows, fixed = TRUE)))
  rows[!guard]
}

# ms_* API claims of a row: the bare name of every backticked call form.
.ms_cm_claims <- function(row) {
  toks <- strsplit(row, "`")[[1L]]
  sub("\\(.*", "", toks[grepl("^ms_[a-z0-9_]+\\(", toks)])
}

# engine="a"/"b" variants a row offers. The matrix enumerates alternatives
# with trailing slash-quotes that sit OUTSIDE the first quote pair, so the
# match spans the whole ("/\"...\"*)" tail -- a phantom hiding in the tail
# must not survive (the hals incident: it lived exactly there).
.ms_cm_engine_claims <- function(row) {
  if (!grepl("ms_nmf", row, fixed = TRUE)) return(character(0))
  hits <- gregexpr('engine *= *"[^"]+"(/"[^"]+")*', row)[[1L]]
  if (!length(hits) || anyNA(hits)) return(character(0))
  # this base's gregexpr yields start positions plus a match.length vector,
  # not the R CMD check era matrix
  raw <- substr(row, hits, hits + attr(hits, "match.length") - 1L)
  raw <- gsub('^engine *= *', "", raw)
  vals <- gsub('["]', "", raw)
  trimws(unlist(strsplit(vals, "/"), use.names = FALSE))
}

# Source-tree root: walk up until DESCRIPTION and NAMESPACE both stand.
# NULL above the check layout (the installed-package tree has neither).
.ms_cm_repo_root <- function(start) {
  dir <- normalizePath(start, mustWork = FALSE)
  for (i in seq_len(12L)) {
    if (all(file.exists(file.path(dir, c("DESCRIPTION", "NAMESPACE")))))
      return(dir)
    up <- normalizePath(file.path(dir, ".."), mustWork = FALSE)
    if (identical(up, dir)) break
    dir <- up
  }
  NULL
}

# Two truths for the two kinds of claim, both pure file reads so the CLI
# face runs in a CI job that installs nothing: the NAMESPACE roster names
# the shipped API, the engine-decl line names the legal kernel variants.

.ms_cm_exports <- function(root) {
  ns <- file.path(root, "NAMESPACE")
  if (!file.exists(ns)) stop("NAMESPACE unreadable at ", root)
  txt <- readLines(ns, warn = FALSE)
  hits <- grep("^export\\(([^)]*)\\)[[:space:]]*$", trimws(txt), value = TRUE)
  if (!length(hits)) stop("NAMESPACE lists no exports -- parser or file is broken")
  sub("^export\\(([^)]*)\\)[[:space:]]*$", "\\1", hits)
}

.ms_cm_variants <- function(root) {
  f <- file.path(root, "R", "engines-nmf.R")
  if (!file.exists(f)) stop("R/engines-nmf.R unreadable at ", root)
  ln <- grep(".ms_nmf_variants <- c(", readLines(f, warn = FALSE),
              fixed = TRUE, value = TRUE)
  # The anchor moving is an emergency, not a silence: a missing declaration
  # would leave the engine face vacuous-green, so it must speak loudly here.
  if (!length(ln)) stop(".ms_nmf_variants declaration not found in ", f)
  toks <- strsplit(ln[[1L]], '"')[[1L]]
  vals <- toks[grepl("^[a-z][a-z0-9_]*$", toks)]
  if (!length(vals)) stop(".ms_nmf_variants parses empty from: ", ln[[1L]])
  vals
}

# Full audit of one matrix against one root. Returns the claim sets and the
# two phantom sets; a dead parser (zero claims across the whole matrix)
# stops instead of reporting an empty, satisfying diff.
.ms_cm_audit <- function(root) {
  matrix <- file.path(root, "docs", "CAPABILITY-MATRIX.md")
  if (!file.exists(matrix)) stop("docs/CAPABILITY-MATRIX.md missing at ", root)
  lines <- readLines(matrix, warn = FALSE)
  rows <- .ms_cm_delivered_rows(lines)
  if (!length(rows)) stop("no delivered rows in the matrix -- glyph parsing died")
  claimed <- unique(unlist(lapply(rows, .ms_cm_claims), use.names = FALSE))
  # FFI-governed internals are the docs/ffi-surface.md population, not here.
  claimed <- claimed[!grepl("_rust$", claimed)]
  if (!length(claimed)) stop("delivered rows name no ms_* API -- claim parsing died")
  legal <- .ms_cm_variants(root)
  exports <- .ms_cm_exports(root)
  eng_rows <- grep("ms_nmf", rows, value = TRUE)
  engines <- unique(unlist(lapply(eng_rows, .ms_cm_engine_claims),
                           use.names = FALSE))
  list(
    claims    = claimed,
    engines   = engines,
    exports   = exports,
    legal     = legal,
    api       = setdiff(claimed, exports),
    engine    = setdiff(engines, legal),
    rows      = length(rows)
  )
}

# Positive controls with teeth: a fabricated matrix carrying a ghost API and
# a ghost engine must FAIL both predicates, and a deferred-marked row must be
# excluded from the delivered-reading (under-claiming is never punished).
.ms_cm_selfcheck <- function() {
  g <- .ms_cm_glyphs()
  row_api <- paste0("| `ms_ghost_panel()` | phantom | ", g$delivered, " v1.0 | x |")
  row_eng <- paste0("| `ms_nmf(engine=\"ghostly\")` | phantom lineage | Rust | ",
                    g$delivered, " M9 | optional |")
  row_def <- paste0("| `ms_ghost2()` | planned | ", g$deferred, " v1.x | x |")
  rows <- .ms_cm_delivered_rows(c(row_api, row_eng, row_def))
  # against a synthetic roster where ms_nmf really ships: the ghost API must
  # be the only phantom surfaced (a true claim is never chased -- the
  # one-directional law under test), the ghost variant the only illegal engine,
  # and the deferred row must never reach the delivered-reading at all.
  api_phantom <- setdiff(unique(c(.ms_cm_claims(row_api), .ms_cm_claims(row_eng))),
                         "ms_nmf")
  engine_phantom <- setdiff(.ms_cm_engine_claims(row_eng), c("kl", "eu"))
  list(
    fired_api           = identical(api_phantom, "ms_ghost_panel"),
    fired_engine        = identical(engine_phantom, "ghostly"),
    excluded_deferred   = length(rows) == 2L &&
                           !any(grepl("ghost2", rows, fixed = TRUE))
  )
}

.ms_cm_selftest <- function() {
  r <- .ms_cm_selfcheck()
  for (nm in names(r))
    cat("self-test", nm, if (r[[nm]]) "fires" else "DOES NOT FIRE", "\n")
  if (all(unlist(r))) quit(status = 0L) else quit(status = 1L)
}

.ms_cm_main <- function(root) {
  a <- .ms_cm_audit(root)
  if (length(a$api)) {
    for (nm in a$api)
      cat("PHANTOM API: `", nm, "` is checkmarked but not in NAMESPACE\n", sep = "")
  }
  if (length(a$engine)) {
    for (v in a$engine)
      cat("PHANTOM ENGINE: engine=\"", v, "\" is checkmarked but outside (.ms_nmf_variants=",
          paste0(a$legal, collapse = "/"), ")\n", sep = "")
  }
  if (length(a$api) || length(a$engine)) quit(status = 1L)
  cat("capability-matrix truth: PASS -- ", a$rows, " delivered rows, ",
      length(a$claims), " API claims all exported, ", length(a$engines),
      " engine claims all legal (", paste0(a$legal, collapse = "/"), ")\n",
      sep = "")
  quit(status = 0L)
}

# CLI face only (house idiom, cf. docs-sync.R: the script rides the
# --file= element of this base's full R invocation vector). Sourcing from
# the testthat gate leaves --file= naming the test runner, so the face
# stays inert there.
.ms_cm_argv <- commandArgs(FALSE)
.ms_cm_script <- sub("^--file=", "",
                     .ms_cm_argv[grepl("^--file=", .ms_cm_argv)])
if (length(.ms_cm_script) &&
    grepl("check-capability-matrix", .ms_cm_script[[1L]], fixed = TRUE)) {
  .ms_cm_root <- .ms_cm_repo_root(
    dirname(normalizePath(.ms_cm_script[[1L]], mustWork = TRUE)))
  if (is.null(.ms_cm_root)) .ms_cm_root <- .ms_cm_repo_root(getwd())
  if (is.null(.ms_cm_root)) {
    cat("capability-matrix truth: no source tree found (no DESCRIPTION above)\n")
    quit(status = 2L)
  }
  if (any(grepl("--self-test", .ms_cm_argv, fixed = TRUE)))
    .ms_cm_selftest()
  .ms_cm_main(.ms_cm_root)
}
