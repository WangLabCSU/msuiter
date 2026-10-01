# test-xval-m2-extract.R -- M2 acceptance gate, sigminer extraction-layer
# cross-validation (bench/xval-m2/run_xval.R, distilled). Guard: on the same
# separable synthetic SBS96 catalog, msuiter's default extraction pipeline
# (D16) and sigminer 2.3.1's NMF extraction (sig_extract, brunet/KL default)
# must BOTH recover every planted signature (cosine > 0.9) and agree with
# each other (greedy best-match cosine > 0.95) -- three-way evidence with
# the known truth, so a layout/handoff bug on either side cannot pass.
#
# API note (bench/xval-m2/result.md issue 1): sigminer's fixed-k NMF entry
# point is sig_extract(nmf_matrix, n_sig = k); sig_auto_extract() has no k
# argument (auto-K). The input is samples x channels and $Signature.norm is
# the column-normalized signature matrix; output rows keep the input channel
# order (asserted here as the order audit).
#
# Dependency policy: sigminer is Suggests -- skipped when absent, so CI
# without it pays nothing and the guard runs wherever it exists.

test_that("extraction pipeline agrees with sigminer on a separable truth (M2 xval)", {
  skip_if_not_installed("sigminer")
  suppressPackageStartupMessages(library(sigminer))

  .ms_ensure_nmf()

  # -- the bench truth, verbatim (seed 20260930): 3 signatures x 96 SBS96
  #    channels (27 exclusive anchors + 15 shared background each), 12
  #    samples in four groups of 3 (three near-pure groups + one mixed) ----
  tables <- get("channel_tables", envir = asNamespace("msuiter"))
  canon <- as.character(tables[["SBS96"]]$labels)
  expect_length(canon, 96L)

  ns <- 12L
  k <- 3L
  truth <- withr::with_seed(20260930, {
    w <- matrix(0, nrow = 96L, ncol = k)
    for (s in seq_len(k)) {
      idx <- ((s - 1L) * 27L + 1L):(s * 27L)
      w[idx, s] <- 0.5 + runif(27L)
    }
    w[(k * 27L + 1L):(k * 27L + 15L), ] <- 0.04
    w <- sweep(w, 2, colSums(w), "/")
    h <- matrix(0, nrow = k, ncol = ns)
    for (j in seq_len(ns)) {
      dom <- ((j - 1L) %/% 3L) + 1L
      for (s in seq_len(k)) {
        h[s, j] <- if (dom == 4L || s == dom) 800 + 400 * runif(1) else 30 * runif(1)
      }
    }
    list(w = w, h = h, counts = round(w %*% h))
  })

  counts <- truth$counts
  storage.mode(counts) <- "numeric"
  dimnames(counts) <- list(canon, sprintf("S%02d", seq_len(ns)))

  # -- msuiter: the D16 default pipeline (test-path catalog construction) ----
  cat1 <- ms_catalog(
    counts = counts,
    channels = list(name = "SBS96", labels = canon),
    samples = colnames(counts),
    provenance = list(genome = "SYN-xval-m2")
  )
  fit <- ms_extract(cat1, k = k)
  sig_ms <- fit@signatures
  expect_identical(rownames(sig_ms), canon) # no channel permutation

  # -- sigminer: fixed-k NMF, package defaults (brunet = KL, nrun = 10) ------
  sig_sg <- sig_extract(t(counts), n_sig = k, seed = 123456)$Signature.norm
  expect_identical(rownames(sig_sg), canon) # no channel permutation

  # -- helpers: unit columns, greedy 1-1 matching on a cosine grid -----------
  unit <- function(m) sweep(m, 2, colSums(m^2)^0.5, "/")
  greedy <- function(C) {
    keep_r <- logical(nrow(C))
    keep_c <- logical(ncol(C))
    out <- list()
    repeat {
      sub <- C
      sub[keep_r, ] <- -Inf
      sub[, keep_c] <- -Inf
      if (all(!is.finite(sub))) break
      w <- arrayInd(which.max(sub), dim(sub))
      keep_r[w[1]] <- TRUE
      keep_c[w[2]] <- TRUE
      out[[length(out) + 1L]] <- c(w[1], w[2], C[w[1], w[2]])
    }
    do.call(rbind, out)
  }

  # -- gate 1: both engines recover every planted signature (cosine > 0.9) ---
  truth_n <- unit(truth$w)
  rec_ms <- greedy(crossprod(truth_n, unit(sig_ms)))
  rec_sg <- greedy(crossprod(truth_n, unit(sig_sg)))
  expect_true(all(rec_ms[, 3] > 0.9),
    info = sprintf("msuiter recovery: %s", paste(round(rec_ms[, 3], 4), collapse = ", ")))
  expect_true(all(rec_sg[, 3] > 0.9),
    info = sprintf("sigminer recovery: %s", paste(round(rec_sg[, 3], 4), collapse = ", ")))

  # -- gate 2: the engines agree with each other (best-match cosine > 0.95) --
  pair <- greedy(crossprod(unit(sig_ms), unit(sig_sg)))
  expect_length(pair[, 3], k)
  expect_true(all(pair[, 3] > 0.95),
    info = sprintf("best-match: %s", paste(round(pair[, 3], 4), collapse = ", ")))
})
