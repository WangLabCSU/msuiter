#!/usr/bin/env Rscript
# Deterministic shard-map generator for the sharded CI lanes (restructure
# 2026-10-21). Reads the committed measured weights and partitions every
# on-disk tests/testthat/test-*.R file into exactly one of K shards via
# longest-processing-time-first bin packing (files ordered by descending
# seconds, ties by name; each goes to the currently lightest shard).
#
# Output is a comment header plus a fixed column layout, so regenerating at
# the same inputs is byte-identical -- test-ci-shard-map.R pins that witness.
# The manifest is the single partition consumed by the guards matrix, the
# covr matrix, and the per-platform check-test fan-out.
#
# usage: gen-shard-manifest.R --weights=<path> --out=<path> [--k=6] [--root=<dir>]

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
weights <- .kv("weights", NULL)
out <- .kv("out", NULL)
k <- as.integer(.kv("k", "6"))
# Root: explicit --root=, else the sanctioned ancestor walk for a package
# DESCRIPTION (same premise as tests/testthat/helper-check-layout.R's .ms_root).
root <- .kv("root", NULL)
if (is.null(root)) {
  root <- local({
    p <- normalizePath(getwd())
    while (TRUE) {
      if (file.exists(file.path(p, "DESCRIPTION"))) break
      up <- dirname(p)
      if (identical(up, p)) quit(status = 2L)   # fail closed: pass --root=
      p <- up
    }
    p
  })
}
if (is.null(weights) || is.null(out) || !file.exists(weights)) {
  quit(status = 2L)
}
roster <- list.files(file.path(root, "tests", "testthat"),
                     pattern = "^test-.*[.]R$")

lines <- readLines(weights, warn = FALSE)
data <- lines[!grepl("^\\s*(#|$)", lines)]
if (!length(data) || !identical(strsplit(data[1L], "\t", fixed = TRUE)[[1]],
                                c("file", "seconds", "expects"))) {
  stop("weights file lacks the 'file\\tseconds\\texpects' header row")
}
rows <- strsplit(data[-1L], "\t", fixed = TRUE)
wfile <- vapply(rows, `[`, character(1), 1L)
wsec <- suppressWarnings(as.numeric(vapply(rows, `[`, character(1), 2L)))
if (any(is.na(wsec))) stop("non-numeric seconds in weights")
if (!identical(sort(wfile), sort(roster))) {
  stop("weights roster drifts from disk: missing=",
       paste0(setdiff(roster, wfile), collapse = ", "),
       " extra=", paste0(setdiff(wfile, roster), collapse = ", "))
}
secs <- setNames(wsec, wfile)

# LPT bin packing: heaviest first, always onto the currently lightest shard
# (ties break toward the lower shard id); deterministic, no RNG, no clock.
order_idx <- order(-secs[roster], roster, method = "radix")
load <- rep_len(0, k)
assign <- rep_len(NA_integer_, length(roster))
for (i in order_idx) {
  s <- which.min(load)
  assign[i] <- s
  load[s] <- load[s] + secs[[roster[i]]]
}

body <- data.frame(shard = assign, file = roster,
                      stringsAsFactors = FALSE)
body$seconds <- as.integer(round(secs[body$file]))
body <- body[order(body$shard, body$file, method = "radix"), ]
writeLines(c(paste0("# k=", k),
             "shard\tfile\tseconds",
             paste0(body$shard, "\t", body$file, "\t", body$seconds)),
           out)
makespan <- max(tapply(body$seconds, list(body$shard), sum))
cat(paste0("gen-shard-manifest: k=", k, " files=", length(roster),
              " makespan=", makespan, "s -> ", out, "\n"), sep = "")
