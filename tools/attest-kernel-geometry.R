#!/usr/local/bin/Rscript
# attest-kernel-geometry.R: the committed generator of the attested
# 96 x 100 kernel geometry (the PERF-P10 law family's fa2 face).
#
# Why this exists: the original fa2 bytes lived only in a /tmp lane
# sandbox and were lost (audit #74 P1-6: four gate files missing
# everywhere, the attestation units skipped vacuously). The law files
# must run on bytes that live in the repository. This generator
# replays a frozen seeded recipe; the bytes it produced are committed,
# the committed bytes are digest-pinned (fa2/COUNTS.sha256), and the
# tests read the committed bytes -- the generator is provenance, never
# a runtime dependency. `--verify` regenerates and re-hashes, proving
# the committed bytes ARE this recipe's output (a dead-metric control
# for the digest ledger itself).
#
# No COSMIC bytes: the truth is K_SRC synthetic spike sources over the
# registry's 96 canonical channel labels, per-sample spike supports
# drawn from the frozen seed. Sparse supports are the point: the PF
# census face the law was attested on was a bootstrap-sparse regime
# (~0.98 zero density); the bootstrapped replication in
# helper-kernel-geometry.R must reproduce that regime, not a dense one.
#
# Usage:
#   Rscript tools/attest-kernel-geometry.R           # regenerate + write
#   Rscript tools/attest-kernel-geometry.R --verify  # regenerate + compare
#
# The seed law is pinned verbatim (kind/normal.kind/sample.kind) so the
# bytes survive an R minor-version walk for as long as the ledger rules.

args <- as.character(commandArgs(FALSE))
verify <- "--verify" %in% args

SEED <- 20261005L          # the audit #74 lane date -- the frozen seed
M <- 96L                   # channels (the SBS96 registry width)
N <- 100L                  # samples
K_SRC <- 4L                # synthetic spike sources per sample
BURDEN <- 2000L            # per-sample mutation total (integer-exact)

fixtures <- file.path("tests/testthat/fixtures/kernel-geometry")
out.dir <- file.path(fixtures, "fa2")
counts.path <- file.path(out.dir, "counts.csv")
digest.path <- file.path(out.dir, "COUNTS.sha256")

.sha <- function(path) {
  info <- file.info(path)
  msuiter:::.ms_cc_sha256_raw(readBin(path, what = "raw", n = info$size))
}

generate <- function() {
  set.seed(SEED, kind = "Mersenne-Twister", normal.kind = "Inversion",
           sample.kind = "Rejection")
  labels <- get("channel_tables", envir = asNamespace("msuiter"))
  labels <- labels[["SBS96"]]$labels
  if (!length(labels) == M) {
    stop("registry SBS96 is not 96-wide", call. = FALSE)
  }
  # K_SRC spike sources: each concentrates on a seeded sparse support.
  sources <- matrix(0, nrow = M, ncol = K_SRC)
  for (s in seq_len(K_SRC)) {
    support <- sort(sample(M, 25L))
    sources[support, s] <- stats::rgamma(length(support), shape = 2)
    sources[, s] <- sources[, s] / sum(sources[, s])
  }
  # Per sample: a spike support over the sources (sparse channels) plus a
  # multinomial draw of exactly BURDEN mutations from the mixed profile.
  mat <- matrix(0L, nrow = M, ncol = N)
  for (j in seq_len(N)) {
    k <- sample(2:6, 1L)
    picks <- sample.int(K_SRC, k, replace = TRUE)
    w <- stats::runif(k, 0.02, 1)
    p <- rowSums(sources[, picks, drop = FALSE] *
                 matrix(w, nrow = M, ncol = k))
    p <- p / sum(p)
    mat[, j] <- stats::rmultinom(1L, size = BURDEN, prob = p)
  }
  colnames(mat) <- paste0("sample", sprintf("%03d", seq_len(N)))
  rownames(mat) <- labels
  if (any(colSums(mat) != BURDEN)) {
    stop(paste0("generated face failed the geometry law ",
                "(an empty sample or a column off the burden)"),
         call. = FALSE)
  }
  mat
}

mat <- generate()
dir.create(out.dir, recursive = TRUE, showWarnings = FALSE)
# The canonical banked orientation: one row per sample, the id column
# first, then the 96 channel columns in registry order.
df <- data.frame(id = colnames(mat), stringsAsFactors = FALSE)
for (c_i in seq_len(M)) df[[rownames(mat)[c_i]]] <- mat[c_i, ]
tmp <- tempfile("attest-geom-")
utils::write.table(df, file = tmp, sep = ",", row.names = FALSE,
                   col.names = TRUE, quote = FALSE)
new.sha <- .sha(tmp)

if (verify) {
  if (!file.exists(counts.path)) {
    stop("committed bytes absent: ", counts.path, call. = FALSE)
  }
  committed <- .sha(counts.path)
  ledger <- readLines(digest.path, warn = FALSE)[1L]
  banked <- sub("[[:space:]].*$", "", trimws(ledger))
  if (!identical(new.sha, committed) || !identical(new.sha, banked)) {
    stop("generator no longer reproduces the committed bytes: generated ",
         new.sha, ", committed ", committed, ", ledger ", banked,
         call. = FALSE)
  }
  cat("attest-kernel-geometry VERIFY ok  sha256=", new.sha, "\n", sep = "")
} else {
  file.copy(tmp, counts.path, overwrite = TRUE)
  writeLines(paste0(new.sha, "  fa2/counts.csv"), con = digest.path)
  cat("attest-kernel-geometry wrote ", counts.path,
      "  sha256=", new.sha, "\n", sep = "")
}
