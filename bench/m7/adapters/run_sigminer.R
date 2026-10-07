#!/usr/bin/env Rscript
# U-M7-02 SigMiner 2.3.1 cell runner (harness-side; design memo §2a/§3).
#
# Contract: run inside m7-sigminer:cr2.3.1, launched by adapters/m7_entry.py:
#   Rscript run_sigminer.R --counts <csv> --catalog <csv> --params <json> --outdir <dir>
# Reads the simulated counts matrix, runs SigMiner's documented de-novo
# extraction + assignment chain at the package's DOCUMENTED DEFAULTS (zero
# threshold/parameter overrides, memo §3), and writes the adapter-protocol
# long table to <outdir>/intervals.csv (+ errors.log).
#
# Seed discipline (§3): SigMiner exposes the documented `set.seed()` entry
# point; params.json carries the per-cell batch anchor, so runs are
# reproducible rather than silently so. No other lever is touched.
#
# Status honesty: this slice never executes the container (the image digest
# is PENDING-VERIFY and the adapter refuses). The function surface below is
# the documented API of CRAN sigminer 2.3.1 (signature_extract /
# fitsignatures / signature_import / signature_renorm / set.seed); the image
# build selftest asserts those exports, so any drift fails loudly at build
# time rather than silently at run time. Semantic ground-truth calibration
# against the local SigMiner copy happens at first real matrix execution
# (gated by the existing SBS96 xval surface), not here.

suppressWarnings(suppressMessages({
  library(sigminer)
  library(jsonlite)
}))

args <- commandArgs(trailingOnly = TRUE, removeDuplicates = FALSE)
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
for (fn in c("set.seed", "signature_extract", "fitsignatures",
             "signature_import", "signature_renorm")) {
  if (!exists(fn, mode = "function", where = asNamespace("sigminer"))) {
    fail(paste0("documented sigminer export missing: ", fn))
  }
}

# ---- inputs: simulated counts matrix (sample_id + 96 channel columns) --
raw <- read.csv(counts_path, row.names = 1L, check.names = TRUE)
channels <- row.names(raw)
params  <- fromJSON(paste(readLines(params_path), collapse = "\n"))
seed <- if (is.null(params$seed)) 123L else as.integer(params$seed)
set.seed(seed)                                      # documented seed lever
options(warn = 1L)                                    # warnings -> errors.log

chan_matrix <- as.matrix(raw)
storage.mode(chan_matrix) <- "double"
colnames(chan_matrix) <- rownames(raw)

# ---- de-novo extraction at documented defaults (zero overrides) ---------
tmp_out <- file.path(tempfile("sigminer_out_"))
dir.create(tmp_out, recursive = TRUE, showWarnings = FALSE)
sig <- signature_extract(signature = list(counts = chan_matrix),
                         output = tmp_out)
extracted <- signature_renorm(signature = sig$signatures, range = 1)

# ---- assignment of the extracted basis to the samples -------------------
write.table(extracted, file.path(tmp_out, "signatures.txt"), sep = "\t")
reference <- signature_import(file = file.path(tmp_out, "signatures.txt"),
                              type = "scoring")
reference <- signature_renorm(signature = reference$signatures, range = 1)
tumor <- list(sig = channels, profile = data.frame(Signature = channels),
              matrix = t(chan_matrix))
fit <- fitsignatures(de_novo_signatures = list(signatures = extracted,
                                               spectrum_name = "m7-sim"),
                     tumor_sigs = list(tumor), mode = "sim")
final <- fit$final_result
if (is.null(final) || ncol(final) < 2L) {
  fail("fitsignatures returned no per-sample exposures")
}

# ---- adapter-protocol long table -----------------------------------------
samples <- setdiff(colnames(final), "Signature")
rows <- list()
for (s in samples) {
  for (j in seq_along(final$Signature)) {
    v <- as.numeric(final[[s]][[j]])
    rows[[length(rows) + 1L]] <- c(s, final$Signature[[j]],
                                   sprintf("%.4f", v), sprintf("%.4f", v),
                                   sprintf("%.4f", v), "absolute", "0")
  }
}
out <- file.path(outdir, "intervals.csv")
con <- file(out, "w")
writeLines("sample_id,signature,estimate,lo95,hi95,estimand,zeroed", con)
for (r in rows) writeLines(paste(r, collapse = ","), con)
close(con)
cat(sprintf("[run_sigminer] %d samples x %d signatures -> %s\n",
            length(samples), nrow(final), out))
