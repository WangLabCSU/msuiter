#!/usr/bin/env Rscript
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
  stop("run_sigminer.R: --counts/--params/--outdir are required")
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

# ---- pin guard (mirror of the Dockerfile build assert; fails loudly) ----
version <- as.character(packageVersion("sigminer"))
if (!identical(version, "2.3.1")) {
  fail(paste("SigMiner pin drift: image carries", version, "want 2.3.1"))
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
e1 <- bp_extract_signatures(catalog, seed = seed)
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
cat(sprintf("[run_sigminer] %d samples x %d signatures -> %s\n",
            ncol(exposure), nrow(exposure), out))
