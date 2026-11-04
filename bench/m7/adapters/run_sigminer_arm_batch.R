#!/usr/bin/env Rscript

# ===========================================================================
# run_sigminer_arm_batch.R — MECHANICAL FORK of the byte-frozen
# adapters/run_sigminer_arm.R, for the ONE pre-registered batch-bridge arm
# sigminer_post_v3_rust_batch (R1-PARITY Phase-B, controller ruling (ii)
# 2026-11-04). The frozen original is ZERO-TOUCH: its bytes are pinned by
# Dockerfile.sigminer.tree and they are what the 147 committed parity rows
# were measured through, so this face reaches the world as a separate file
# with its own committed byte-pin, never as a widening of that allow-list.
# Derived mechanically by anchor-matched replacement
# (/tmp/r1lane/derive_run_batch_fork.py, every anchor matches exactly once);
# the deltas are ONLY:
#   1. pin guard: the 2.3.1 hard-pin becomes the arm identity read from
#      /work/arm_pin.json (roster-derived, COPYed at bake): expected package
#      version, face, and the witnessed NAMESPACE bytes re-hashed from the
#      INSTALLED library (braces to the installer's belt).
#   2. --backend R|rust is consumed and must agree with arm_pin.face (two
#      sources, one truth; disagreement is fatal, never a fallback).
#   3. call site: the batch face adds ONLY backend = "rust_batch" to the same
#      frozen bp_extract_signatures(catalog, seed = seed) call (the third
#      documented extraction value, best_practice.R — everything else rides
#      package defaults, zero-override law). It is the arm's single delta from
#      its rust twin: the 4000 certified fits arrive at the kernel as the
#      manifest rows of one batch invocation per (rank, bootstrap) unit
#      instead of one process spawn per fit. WHAT the kernel computes is
#      untouched — same certified binary family, same frozen 20x50x4 geometry,
#      same per-run seed law — so bit-identity against the spawn face is a
#      TRANSPORT invariant, attested by tools/batch_bridge_bit_identity.py.
#   4. the identity footer names this fork, so no log line can be read as
#      having come from the frozen runner's bytes.
# Everything below (documented-defaults chain, NaN bounds, seven-column long
# table, errors.log discipline) is the frozen contract, unchanged.
# ===========================================================================
# U-M7-02 SigMiner 2.3.1 cell runner (harness-side; design memo §2a/§3/§9d).
#
# Contract: run inside m7-sigminer:cr2.3.1, launched by adapters/m7_entry.py:
#   Rscript run_sigminer.R --counts <csv> --catalog <csv> --params <json> --outdir <dir>
# Reads the simulated 96-channel catalogue (sample_id x channel), drives the
# package's documented best-practice NMF extraction chain at its DOCUMENTED
# DEFAULTS (zero threshold/parameter overrides, memo §3), and writes the
# adapter-protocol long table to <outdir>/intervals.csv (+ errors.log).
#
# API truth (slice-3, memo §9c.2/§9d): the pre-slice chain was call-site
# fiction — its five "documented" names exist 0/5 in the CRAN 2.3.1
# NAMESPACE, in EVERY published version (verified against the witnessed
# Archive tarball, sha256 b2836c76..1953b). The real extraction/assignment
# surface is the witnessed bp_* best-practice family: bp_extract_signatures
# (sample-by-component catalogue input) -> bp_get_sig_obj at the extraction
# result's own suggested rank -> sig_exposure absolute accessor. Every call
# site is pinned host-side against the verbatim NAMESPACE fixture by
# tests/test_sigminer_api_contract.py, so un-witnessed names cannot
# re-enter without failing a unit.
#
# Seed discipline (§3): the package's own documented reproducibility lever
# is the `seed` parameter of its extraction entry point (its docstring:
# "a random seed to make reproducible result"); the per-cell batch anchor
# from params.json flows there verbatim. No other lever is touched. (The
# pre-slice header claimed a package-documented seed entry point that the
# witnessed NAMESPACE shows 0 times — base R is where that name lives.)
#
# Interval honesty (house convention, memo §9d): the extraction chain
# reports point exposures and no confidence bounds — absent bounds are
# written as NaN, never masquerading as zero-width ones (the sibling
# run_sigprofiler.py sets the same rule).
#
# Status honesty: the image gate lives on the Python adapter side
# (PENDING-VERIFY -> AdapterUnavailable, skip-not-skip). The pin guard below
# mirrors the build-time asserts; the image build selftest asserts the full
# witnessed NAMESPACE contract.

suppressWarnings(suppressMessages({
  library(sigminer)
  library(jsonlite)
}))

args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) == 0L) default else args[[i[1L] + 1L]]
}
counts_path <- getArg("--counts")
params_path <- getArg("--params")
outdir      <- getArg("--outdir")
if (is.null(counts_path) || is.null(params_path) || is.null(outdir)) {
  stop("run_sigminer_arm_batch.R: --counts/--params/--outdir are required")
}
# --catalog is protocol-carried (COSMIC reference mount). The de-novo cell
# at documented defaults does not consume it: reference matching is the
# scoring-side get_sig_similarity job (memo §4), never an extraction lever.
catalog_path <- getArg("--catalog")

dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
err_log <- file.path(outdir, "errors.log")
writeLines("", err_log)

fail <- function(msg) {
  writeLines(paste0("FATAL ", format(Sys.time()), " ", msg), err_log)
  stop(msg, call. = FALSE)
}

# ---- arm pin guard (roster-attested identities; fails loudly) -----------
# /work/arm_pin.json is COPYed from the committed arm_pins/<tool>.json at
# bake; the same bytes the installer resolved and the registry attested.
backend_arg <- getArg("--backend")
# This fork serves exactly one face. The two documented faces of the lineage
# stay where they belong -- in the frozen runner, whose allow-list this file
# must never be read as widening.
if (is.null(backend_arg) || !backend_arg %in% c("rust_batch")) {
  fail(paste0("--backend rust_batch is required, got ",
              if (is.null(backend_arg)) "(absent)" else backend_arg))
}
pin_path <- "/work/arm_pin.json"
if (!file.exists(pin_path)) {
  fail(paste0("arm pin file absent: ", pin_path))
}
pin <- fromJSON(paste(readLines(pin_path), collapse = "\n"))
version <- as.character(packageVersion("sigminer"))
if (!identical(version, pin$expected_version)) {
  fail(paste("SigMiner pin drift: image carries", version,
             "want the pre-registered", pin$expected_version))
}
if (!identical(backend_arg, pin$face)) {
  fail(paste0("argv --backend=", backend_arg, " disagrees with arm_pin face=",
              pin$face, " — two identity sources must agree, never a fallback"))
}
face <- pin$face
sha256_file <- function(path) {
  ## Byte-idiom imported verbatim from the frozen resolver's sha256File
  ## (install_sigminer.R:83-98, slice-3 pre-flight): the system2
  ## stdout=<variable> form returns nothing readable under Rscript on
  ## base 4.3.3 -- the file-redirect form is the deterministic contract.
  ## Recorded bake death #5 (2026-10-15): the fork's vector-capture form
  ## died "sha256sum unreadable" on a file that was there and readable.
  o <- tempfile(); e <- tempfile()
  st <- system2("sha256sum", c("--", path), stdout = o, stderr = e)
  if (!identical(st, 0L))
    fail(paste0("sha256sum failed on witness bytes (status ", st, "): ",
                paste(readLines(e, warn = FALSE), collapse = " | ")))
  ln <- readLines(o, warn = FALSE)
  if (!length(ln)) fail(paste0("sha256sum printed no digest for ", path))
  strsplit(trimws(ln[[1L]]), " ")[[1L]][[1L]]
}
ns_installed <- system.file("NAMESPACE", package = "sigminer")
if (!nzchar(ns_installed) || !file.exists(ns_installed)) {
  fail("installed sigminer NAMESPACE not locatable for the braces assert")
}
ns_now <- sha256_file(ns_installed)
if (!identical(ns_now, pin$ns_sha256)) {
  fail(paste0("installed NAMESPACE hash ", ns_now,
              " is not the pre-registered ", pin$ns_sha256))
}
CORE_API <- c("bp_extract_signatures", "bp_get_sig_obj", "bp_get_stats",
              "sig_extract", "sig_fit", "sig_fit_bootstrap", "sig_estimate",
              "sig_exposure", "sig_names")
for (fn in CORE_API) {
  if (!exists(fn, mode = "function", where = asNamespace("sigminer"))) {
    fail(paste0("witnessed sigminer export missing: ", fn))
  }
}

# ---- inputs: simulated catalogue (sample_id row names x 96 channels) ----
raw <- read.csv(counts_path, row.names = 1L, check.names = TRUE)
params <- fromJSON(paste(readLines(params_path), collapse = "\n"))
seed <- if (is.null(params$seed)) 123L else as.integer(params$seed)
options(warn = 1L)                 # warnings -> visible on the cell stderr

catalog <- as.matrix(raw)
storage.mode(catalog) <- "double"
rownames(catalog) <- rownames(raw)         # bp_* wants sample-by-component
colnames(catalog) <- colnames(raw)

# ---- documented best-practice extraction at defaults (zero overrides) ----
# The single forwarded argument is the documented reproducibility seed:
# bp_extract_signatures(catalog, seed = seed) — range/n_bootstrap/n_nmf_run/
# RTOL/min_contribution stay at their documented defaults (memo §3).
# Batch face: the frozen call site plus the single documented transport token,
# nothing else (zero-override law). face came from arm_pin and was just
# required to agree with --backend, so this branch cannot be reached by a
# mismatched pair of identity sources.
e1 <- bp_extract_signatures(catalog, seed = seed, backend = "rust_batch")
signum <- e1$suggested
if (is.null(signum)) {
  fail("bp_extract_signatures reported no suggested signature number")
}
obj <- bp_get_sig_obj(e1, signum)
exposure <- sig_exposure(obj, type = "absolute")   # signatures x samples
if (is.null(exposure) || !is.matrix(exposure) ||
    ncol(exposure) < 1L || nrow(exposure) < 1L) {
  fail("sig_exposure returned no per-sample exposures")
}
labels <- rownames(exposure)
if (is.null(labels)) labels <- paste0("S", seq_len(nrow(exposure)))

# ---- witness sidecar (PERF P4 remediation): commit the
# extracted spectrum so the scoring side can OBSERVE the de novo calls.
# Signature-object contract (sigminer 2.3.1): obj$Signature is the
# channels x signatures extraction matrix, columns aligned with labels;
# its channel row-names must equal the counts header (the sim's frozen
# channel set), which is exactly what the scoring side's strict-coverage
# law validates. An empty/non-conforming matrix commits NO witness — the
# cell then honestly declares de-novo-unresolved instead of fabricating
# one. %.17g is the exact round-trip rendering for the doubles.
spectra <- obj$Signature
witness_channels <- NULL
if (!is.null(spectra) && is.matrix(spectra) &&
    ncol(spectra) == length(labels) && nrow(spectra) == ncol(catalog) &&
    identical(rownames(spectra), colnames(catalog))) {
  # channel keys ride the on-disk header bytes: read.csv(check.names = TRUE)
  # syntactically mangles non-NAME columns (A[C>A]A -> A.C.A.A) and the
  # scoring-side witness contract is keyed on the file's own labels.
  header_line <- scan(counts_path, what = "", nmax = 1L, sep = "\n",
                      quiet = TRUE)[[1L]]
  header_tokens <- trimws(strsplit(header_line, ",", fixed = TRUE)[[1L]])[-1L]
  if (length(header_tokens) == ncol(catalog)) witness_channels <- header_tokens
}
if (!is.null(witness_channels)) {
  con <- file(file.path(outdir, "spectra.csv"), open = "wt")
  on.exit(close(con))
  writeLines("signature,channel,value", con)
  for (k in seq_len(ncol(spectra))) {
    for (ch in seq_len(nrow(spectra))) {
      writeLines(paste0(labels[[k]], ",", witness_channels[[ch]], ",",
                        sprintf("%.17g", spectra[ch, k])), con)
    }
  }
}

# ---- adapter-protocol long table ------------------------------------------
rows <- list()
for (j in seq_len(ncol(exposure))) {
  sample <- colnames(exposure)[[j]]
  for (i in seq_len(nrow(exposure))) {
    v <- as.numeric(exposure[[i, j]])
    vs <- if (is.na(v)) "NaN" else sprintf("%.4f", v)
    rows[[length(rows) + 1L]] <- c(sample, labels[[i]], vs, "NaN", "NaN",
                                   "absolute", "0")
  }
}
out <- file.path(outdir, "intervals.csv")
con <- file(out, "w")
writeLines("sample_id,signature,estimate,lo95,hi95,estimand,zeroed", con)
for (r in rows) writeLines(paste(r, collapse = ","), con)
close(con)
cat(sprintf("[run_sigminer_batch_arm] %s face=%s tree=%s: %d samples x %d signatures -> %s\n",
            pin$tool, face, substr(pin$tree_sha, 1L, 10L),
            ncol(exposure), nrow(exposure), out))
