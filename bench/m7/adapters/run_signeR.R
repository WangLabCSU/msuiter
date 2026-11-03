#!/usr/bin/env Rscript
# U-M7-02 signeR 2.12.0 cell runner (harness-side; design memo §2c/§3,
# PI-confirmed identity ruling 2026-11-02).
#
# Contract: run inside the harness-built competitor image, launched by
# adapters/m7_entry.py:
#   Rscript run_signeR.R --counts <csv> --catalog <csv> --params <json> --outdir <dir>
# Reads the simulated 96-channel catalogue (sample_id x channel), drives the
# package's documented entry point at its DOCUMENTED DEFAULTS (zero
# threshold/parameter overrides, memo §3), and writes the adapter-protocol
# long table to <outdir>/intervals.csv (+ errors.log).
#
# Call-surface truth (signeR-c probe03, the package's own tarball bytes):
# NAMESPACE exports signeR; the Rd \usage block documents every other
# argument default; K (nsig) is ESTIMATED at the default (the algorithm
# selects it — no threshold/K invention is needed or made); Opport=NA
# activates the package's own documented uniform-opportunity path; the Rd
# \value block documents Ehat (median of the E-posterior samples) as the
# point-exposure surface the long table reads. The seed argument is absent
# from the documented usage → the run is non-seedable and says so in
# runner_notes.json (memo §3), never a silent reproducibility claim.
#
# Interval honesty (house convention, memo §9d): point exposures, no
# documented bounds — absent bounds are NaN, never masquerading as
# zero-width (the sigminer/sigprofiler runners set the same rule).

suppressWarnings(suppressMessages({
  library(signeR)
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
  stop("run_signeR.R: --counts/--params/--outdir are required")
}
# --catalog is protocol-carried (reference mount). The de-novo cell at
# documented defaults does not consume it: reference matching is the
# scoring-side job (memo §4), never an extraction lever.
catalog_path <- getArg("--catalog")

dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
err_log <- file.path(outdir, "errors.log")
writeLines("", err_log)

fail <- function(msg) {
  writeLines(paste0("FATAL ", format(Sys.time()), " ", msg), err_log)
  stop(msg, call. = FALSE)
}

# ---- pin guard (mirror of the build-time assert; fails loudly) ----
version <- as.character(packageVersion("signeR"))
if (!identical(version, "2.12.0")) {
  fail(paste("signeR pin drift: image carries", version, "want 2.12.0"))
}

raw <- read.csv(counts_path, row.names = 1L, check.names = FALSE)
if (nrow(raw) < 1L || ncol(raw) < 2L) {
  fail("counts.csv carries no sample x channel matrix")
}
M <- as.matrix(raw)
storage.mode(M) <- "double"
rownames(M) <- rownames(raw)
# channel keys ride the file's own header bytes (syntactic mangling off at
# read time; the long table re-keys samples on the row labels verbatim)
params <- fromJSON(paste(readLines(params_path, warn = FALSE), collapse = "\n"))

# ---- documented entry point at defaults: the single argument is M ----
fit <- tryCatch(
  signeR::signeR(M = M),
  error = function(e) fail(paste0("signeR() failed: ", conditionMessage(e))))
if (!is.list(fit) || is.null(fit$Ehat)) {
  fail("signeR() returned no documented Ehat exposure surface")
}
E <- as.matrix(fit$Ehat)
                        if (!is.matrix(E)) {
  fail("Ehat is not a matrix")
}
# orientation law (measured 2026-11-03, SHAPE-VIOLATION E 1 x 2 M 2 x 96):
# the fit delivers Ehat in the coef face signatures x samples; the documented
# table face (Rd \value, median of E samples) is samples x signatures.
if (nrow(E) != nrow(M) && ncol(E) == nrow(M)) E <- t(E)
if (nrow(E) != nrow(M) || ncol(E) < 1L) {
  cat(sprintf("SHAPE-VIOLATION E %d x %d M %d x %d ISM %d\n", nrow(E), ncol(E), nrow(M), ncol(M), as.integer(is.matrix(E))))
  fail("Ehat shape disagrees with the input sample axis")
}
if (is.null(rownames(E))) rownames(E) <- rownames(M)
labels <- colnames(E)
if (is.null(labels)) labels <- paste0("S", seq_len(ncol(E)))

# ---- witness sidecar: commit the extracted spectrum so the scoring side
# can OBSERVE the de-novo calls (PERF P4 idiom, mirrors run_sigminer.R; an
# empty/non-conforming matrix commits NO witness — the cell then honestly
# declares de-novo-unresolved instead of fabricating one) ----
Phat <- fit$Phat  # documented: estimated signatures, median of P samples
cat(sprintf("PHAT-PROBE ISN %d DIM %d x %d\n", as.integer(is.null(Phat)),
            as.integer(if (!is.null(Phat)) nrow(Phat) else -1L),
            as.integer(if (!is.null(Phat)) ncol(Phat) else -1L)))
if (is.matrix(Phat) && nrow(Phat) == ncol(E) && ncol(Phat) == ncol(M)) Phat <- t(Phat)
if (!is.null(Phat) && is.matrix(Phat) && ncol(Phat) == ncol(E) &&
    nrow(Phat) == ncol(M)) {
  header_line <- scan(counts_path, what = "", nmax = 1L, sep = "\n",
                       quiet = TRUE)[[1L]]
  header_tokens <- trimws(strsplit(header_line, ",", fixed = TRUE)[[1L]])[-1L]
  if (length(header_tokens) == ncol(M)) {
    con <- file(file.path(outdir, "spectra.csv"), open = "wt")
    on.exit(close(con))
    writeLines("signature,channel,value", con)
    for (k in seq_len(ncol(Phat))) {
      for (ch in seq_len(nrow(Phat))) {
        writeLines(paste0(labels[[k]], ",", header_tokens[[ch]], ",",
                          sprintf("%.17g", Phat[ch, k])), con)
      }
    }
  }
}

# ---- adapter-protocol long table ------------------------------------------
rows <- list()
for (i in seq_len(nrow(E))) {
  sample <- rownames(E)[[i]]
  for (j in seq_len(ncol(E))) {
    v <- as.numeric(E[[i, j]])
    vs <- if (is.na(v)) "NaN" else sprintf("%.4f", v)
    rows[[length(rows) + 1L]] <- c(sample, labels[[j]], vs, "NaN", "NaN",
                                    "absolute", if (identical(v, 0)) "1" else "0")
  }
}
if (!length(rows)) fail("no exposure rows produced")
out <- file.path(outdir, "intervals.csv")
con <- file(out, "w")
writeLines("sample_id,signature,estimate,lo95,hi95,estimand,zeroed", con)
for (r in rows) writeLines(paste(r, collapse = ","), con)
close(con)

# ---- reproducibility honesty (memo §3): documented usage carries no seed --
notes <- list(competitor = "signeR", version = version,
              seed = params$seed,
              non_seedable = "signeR documents no seed parameter (memo §3)",
              nsign = if (!is.null(fit$Nsign)) fit$Nsign else NA)
writeLines(toJSON(notes, auto_unbox = TRUE, pretty = TRUE),
           file.path(outdir, "runner_notes.json"))

cat(sprintf("[run_signeR] %d samples x %d signatures -> %s\n",
            nrow(E), ncol(E), out))
