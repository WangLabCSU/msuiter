#!/usr/bin/env Rscript
# Deterministic shard-map generator for the sharded CI lanes (restructure
# 2026-10-21; the tier column rides issue #76, 2026-11-05). Reads the
# committed measured weights and partitions every on-disk testthat file into
# exactly one of K shards via longest-processing-time-first bin packing
# (files ordered by descending seconds, ties by name; each goes to the
# currently lightest shard).
#
# The roster is the UNION of tests/testthat (tiers T0, T1) and tests/heavy
# (tier T2): the shard manifest is the single explicit roster, and the
# tier column is what separates the PR-gate battery from the scheduled deep
# battery from the local-only provisioning simulations. A file's tier and
# its directory must agree: T2 lives in tests/heavy (testthat auto-discovery
# does not reach it), T0/T1 live in tests/testthat. Roster, tier and weight
# drift all die here, fail-closed.
#
# The T0 weight budget is enforced here as well as in the aggregator: the
# committed tools/ci/pr-gate-budget.tsv names the measured T0 seconds and
# the ceiling they may not pass. Weights moved without a re-seal, or a
# heavy file smuggled into T0, stop the generation.
#
# Output is a comment header plus a fixed column layout, so regenerating at
# the same inputs is byte-identical -- test-ci-shard-map.R pins that
# witness. The manifest is the single partition consumed by the check-arm
# fan-outs (tier-filtered), the covr shards (tier-filtered), and the heavy
# runner (tier T2).
#
# usage: gen-shard-manifest.R --weights=<path> --out=<path> [--k=6]
#                             [--root=<dir>] [--budget=<path>]

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
tt.dir <- file.path(root, "tests", "testthat")
heavy.dir <- file.path(root, "tests", "heavy")
if (!dir.exists(tt.dir) || !dir.exists(heavy.dir)) quit(status = 2L)
tt.roster <- list.files(tt.dir, pattern = "^test-.*[.]R$")
heavy.roster <- list.files(heavy.dir, pattern = "^test-.*[.]R$")

lines <- readLines(weights, warn = FALSE)
data <- lines[!grepl("^\\s*(#|$)", lines)]
if (!length(data) || !identical(strsplit(data[1L], "\t", fixed = TRUE)[[1]],
                                c("file", "seconds", "expects", "tier"))) {
  stop("weights file lacks the 'file\\tseconds\\texpects\\ttier' header row")
}
rows <- strsplit(data[-1L], "\t", fixed = TRUE)
bad <- lengths(rows) != 4L
if (any(bad)) stop("malformed weights rows: ",
                   paste0(data[-1L][bad], collapse = " | "))
wfile <- vapply(rows, `[`, character(1), 1L)
wsec <- suppressWarnings(as.numeric(vapply(rows, `[`, character(1), 2L)))
if (any(is.na(wsec))) stop("non-numeric seconds in weights")
wtier <- vapply(rows, `[`, character(1), 4L)
if (!all(wtier %in% c("T0", "T1", "T2"))) {
  stop("weights tier outside {T0,T1,T2}: ",
       paste0(unique(setdiff(wtier, c("T0", "T1", "T2"))), collapse = ", "))
}
roster <- c(tt.roster, heavy.roster)
if (!identical(sort(wfile), sort(roster))) {
  stop("weights roster drifts from disk: missing=",
       paste0(setdiff(roster, wfile), collapse = ", "),
       " extra=", paste0(setdiff(wfile, roster), collapse = ", "))
}
# Directory--tier lockstep: the tier column is a location law, not a label.
in.t2 <- wtier == "T2"
if (any(in.t2 & !(wfile %in% heavy.roster))) {
  stop("tier-T2 files must live in tests/heavy: ",
       paste0(wfile[in.t2 & !(wfile %in% heavy.roster)], collapse = ", "))
}
if (any(!in.t2 & (wfile %in% heavy.roster))) {
  stop("only tier-T2 files may live in tests/heavy: ",
       paste0(wfile[!in.t2 & (wfile %in% heavy.roster)], collapse = ", "))
}
secs <- setNames(wsec, wfile)
tiers <- setNames(wtier, wfile)

# T0 budget law (hang-budget spirit: the budget is measured and committed;
# drift goes red). Integers on the manifest's own rounding, so the
# aggregator's sum and this sum are the same arithmetic.
budget.path <- .kv("budget", file.path(root, "tools", "ci", "pr-gate-budget.tsv"))
if (!file.exists(budget.path)) quit(status = 2L)
budget <- local({
  b <- readLines(budget.path, warn = FALSE)
  b <- b[!grepl("^\\s*(#|$)", b)]
  kv <- strsplit(b, "\t", fixed = TRUE)
  setNames(suppressWarnings(as.numeric(vapply(kv, `[`, character(1), 2L))),
           vapply(kv, `[`, character(1), 1L))
})
if (!all(c("t0-measured", "t0-ceiling") %in% names(budget))) {
  stop("budget file lacks the t0-measured/t0-ceiling rows")
}
t0sum <- sum(as.integer(round(secs[roster][tiers[roster] == "T0"])))
if (t0sum > budget[["t0-ceiling"]]) {
  stop("DEFECT: T0 weight ", t0sum, " s exceeds the committed ceiling ",
       budget[["t0-ceiling"]], " s (tools/ci/pr-gate-budget.tsv) -- the PR ",
       "gate battery may not grow past its measured budget; re-measure and ",
       "re-seal deliberately")
}
if (t0sum != budget[["t0-measured"]]) {
  stop("DEFECT: T0 weight moved to ", t0sum, " s but the committed ",
       "measurement says ", budget[["t0-measured"]], " s -- weights drifted ",
       "without a re-seal; update tools/ci/pr-gate-budget.tsv deliberately")
}

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
body$tier <- tiers[body$file]
body <- body[order(body$shard, body$file, method = "radix"), ]
writeLines(c(paste0("# k=", k),
             "shard\tfile\tseconds\ttier",
             paste0(body$shard, "\t", body$file, "\t", body$seconds,
                    "\t", body$tier)),
           out)
makespan <- max(tapply(body$seconds, list(body$shard), sum))
cat(paste0("gen-shard-manifest: k=", k, " files=", length(roster),
           " t0-weight=", t0sum, "s (ceiling ", budget[["t0-ceiling"]],
           ") makespan=", makespan, "s -> ", out, "\n"), sep = "")
