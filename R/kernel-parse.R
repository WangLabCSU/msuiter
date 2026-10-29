# P2 kernel parse fast path: vectorized readers for the protocol-1 output
# bytes (parity plan P2, pair L4; lane card /tmp/perf2lane/lane-task.md).
#
# The forensics base (§7.2) measured parse_outputs at 63.589 s -- 8.9% of
# the 712 s rust-tip wall, over 8000 output-set parses. The reference route
# in R/kernel-pipeline.R reads per row into a list of field vectors; this
# file flattens the same law: one file read, a vectorized per-row
# field-count check (commas-per-row -- fields are commas + 1), ONE strsplit
# of the comma-joined body, ONE as.numeric pass, direct matrix assembly.
#
# THE LAW: the fast route is an identical()-grade clone of the reference
# route -- same doubles, same shape, same fault classes. The TDD family
# pins this on real certified bytes, seeded %.17e edge grids, a
# one-digit-mutation sharpness control, and fault equivalence including the
# ragged-rows-with-matching-flat-total class (which is exactly why the
# per-row field-count law is reconstructed rather than traded for a flat
# token count). A fast reader that drifts one unit-in-the-last-place
# corrupts every downstream tally, so any edit here must keep that family
# green.

## ---- fast matrix reader -----------------------------------------------------

# Vectorized drop-in for kp_read_matrix_csv(). Fail-closed on the same
# classes: missing file, wrong row count, ragged rows (per-row comma count
# must hit ncols - 1 -- an empty field survives the comma law but dies at
# the finite check, exactly as in the reference route), non-finite values
# (NaN/Inf/empty -> NA all die here), negative entries.
kp_read_matrix_fast <- function(path, nrows, ncols, name) {
  if (!file.exists(path)) {
    stop("msuiter-kernel did not produce ", name,
         " in the output directory: ", path, domain = NA)
  }
  nrows <- as.integer(nrows)
  ncols <- as.integer(ncols)
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  if (!identical(length(lines), nrows)) {
    stop(name, " must hold exactly ", nrows, " rows, got ", length(lines),
         ".", domain = NA)
  }
  # Per-row field-count law, reconstructed vectorized: fields = commas + 1.
  # This is the check a flat token count cannot replace -- "1,2 / 3,4,5,6"
  # totals 6 tokens for a 2 x 3 law and is a ragged-row fault.
  commas <- nchar(gsub("[^,]", "", lines))
  bad <- which(commas != ncols - 1L)
  if (length(bad)) {
    stop(name, " row ", bad[[1L]], " has ", commas[[bad[[1L]]]] + 1L,
         " comma-separated fields, expected ", ncols, ".", domain = NA)
  }
  toks <- strsplit(paste(lines, collapse = ","), ",", fixed = TRUE)[[1L]]
  vals <- suppressWarnings(as.numeric(toks))
  if (any(!is.finite(vals))) {
    stop(name, " contains a non-finite value.", domain = NA)
  }
  if (any(vals < 0)) {
    hit <- which(vals < 0)[[1L]]
    stop(name, " contains a negative entry (flattened position ",
         hit, ").", domain = NA)
  }
  matrix(vals, nrow = nrows, ncol = ncols, byrow = TRUE)
}

## ---- fast trace reader ------------------------------------------------------

# Vectorized drop-in for kp_read_trace_csv(): header, the objective rows
# demanded by the asked trace shape (.kp_trace_t: the kernel's endpoints
# face or the full ceremony), every row a t,objective PAIR (the comma-count
# law again is what a flat split cannot certify), the t column integer-
# shaped and following that shape's witness set without gaps, every
# objective finite. Returns the objective vector -- the identical doubles
# the reference route's per-row loop produces (the same as.numeric applied
# to the same %.17e text).
kp_read_trace_fast <- function(path, iters.expect, name,
                               shape = c("endpoints", "full")) {
  shape <- shape[[1L]]
  if (!file.exists(path)) {
    stop("msuiter-kernel did not produce ", name,
         " in the output directory: ", path, domain = NA)
  }
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  if (!length(lines) || !identical(lines[[1L]], "t,objective")) {
    stop(name, " must start with the 't,objective' header.", domain = NA)
  }
  rows <- lines[-1L]
  want <- .kp_trace_t(iters.expect, shape, name)
  if (!identical(length(rows), length(want))) {
    stop(name, " does not match the '", shape, "' trace shape: asked ",
         length(want), " objective rows, got ", length(rows), ".",
         domain = NA)
  }
  commas <- nchar(gsub("[^,]", "", rows))
  bad <- which(commas != 1L)
  if (length(bad)) {
    stop(name, " row is not a t,objective pair: ", rows[[bad[[1L]]]],
         domain = NA)
  }
  toks <- strsplit(paste(rows, collapse = ","), ",", fixed = TRUE)[[1L]]
  t.tok <- toks[seq_len(2L * length(rows)) %% 2L == 1L]
  o.tok <- toks[seq_len(2L * length(rows)) %% 2L == 0L]
  ts <- suppressWarnings(as.integer(t.tok))
  if (anyNA(ts)) {
    hit <- which(is.na(ts))[[1L]]
    stop(name, " row ", hit, " is unreadable: ", rows[[hit]], domain = NA)
  }
  if (!identical(ts, want)) {
    stop(name, " iteration column does not follow the '", shape,
         "' trace shape.", domain = NA)
  }
  obj <- suppressWarnings(as.numeric(o.tok))
  if (any(!is.finite(obj))) {
    hit <- which(!is.finite(obj))[[1L]]
    stop(name, " row ", hit, " is unreadable: ", rows[[hit]], domain = NA)
  }
  obj
}

## ---- the fast case bundle ---------------------------------------------------

# The consumption bundle: W, H, objective and meta read through the fast
# route, structurally identical (and value-identical) to what
# kp_attest_case assembles via the reference readers. The meta map keeps the
# reference reader: fifteen lines are not where the time is (forensics
# §7.2), and the asked-vs-reported attestation law stays a single route.
kp_parse_case_fast <- function(out.dir, m, n, k, iters,
                               trace.shape = c("endpoints", "full")) {
  list(
    W = kp_read_matrix_fast(file.path(out.dir, "W.csv"), m, k, "W.csv"),
    H = kp_read_matrix_fast(file.path(out.dir, "H.csv"), k, n, "H.csv"),
    objective = kp_read_trace_fast(file.path(out.dir, "trace.csv"),
                                    iters, "trace.csv",
                                    shape = trace.shape[[1L]]),
    meta = kp_read_meta_csv(file.path(out.dir, "meta.csv"))
  )
}
