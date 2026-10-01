# ROADMAP M2 acceptance item: the default extraction pipeline on a
# separable synthetic catalog recovers every planted signature with
# reconstruction cosine > 0.95, and the ard/sparse engines register and
# run through the registry (U-M2-04/05/06 integration).

test_that("M2 end-to-end: separable synthetic catalog recovers signatures", {
  ch <- 96L
  ns <- 12L
  k <- 3L
  # Three orthogonal signature supports (32 channels each), unit vectors.
  sigs <- t(vapply(0:(k - 1L), function(s) {
    v <- numeric(ch)
    v[(s * 32L + 1L):((s + 1L) * 32L)] <- 1
    v / sqrt(sum(v^2))
  }, numeric(ch)))
  # Exposures: each sample dominated by one signature + small background.
  H <- matrix(0.01, k, ns)
  for (j in seq_len(ns)) {
    H[(j - 1L) %% k + 1L, j] <- 10
  }
  V <- t(sigs) %*% H
  # NOTE: build the counts DIRECTLY from V (channels x samples). A
  # byrow=TRUE reshape here scrambles the planted channel-block separability
  # and the recovery cosine collapses to ~0.35 (test bug, fixed).
  counts <- round(100 * V)
  dimnames(counts) <- list(paste0("C", seq_len(ch)), paste0("S", seq_len(ns)))

  cat1 <- ms_catalog(
    counts = counts,
    channels = list(name = "SYN96", labels = paste0("C", seq_len(ch))),
    samples = paste0("S", seq_len(ns)),
    provenance = list(genome = "SYN")
  )
  fit <- ms_extract(cat1, k = k) # default pipeline path (D16)

  # Per-signature reconstruction/recovery cosine > 0.95: match each
  # planted signature to its best recovered row (greedy, labels aligned
  # by design since the supports are disjoint).
  rec <- fit@signatures # channels x signatures
  rec_n <- sweep(rec, 2L, sqrt(colSums(rec^2)), "/")
  sig_n <- sweep(sigs, 1L, sqrt(rowSums(sigs^2)), "/")
  cos_mat <- sig_n %*% rec_n
  best <- apply(cos_mat, 1L, max)
  expect_true(all(best > 0.95), info = paste(round(best, 4), collapse = ", "))

  # MsSignature carries the pipeline evidence (stability + k_evidence).
  expect_true(length(fit@stability) > 0L || is.list(fit@stability))
  expect_true(nrow(fit@k_evidence) >= 1L)
})

test_that("ard and sparse engines register, parse and extract", {
  # Other test files reset the registry and re-arm only nmf; re-arm the
  # M2 rows idempotently so this block is order-independent.
  msuiter_register_ard_engine()
  msuiter_register_sparse_engine()

  # Registry rows present after load (registration helpers run at attach).
  expect_true("ard" %in% ms_engines()$name)
  expect_true("sparse" %in% ms_engines()$name)

  ch <- 48L
  ns <- 6L
  labels <- paste0("C", seq_len(ch))
  counts <- matrix(1:(ch * ns) * 7, ch, ns)
  dimnames(counts) <- list(labels, paste0("S", seq_len(ns)))

  cat1 <- ms_catalog(
    counts = counts,
    channels = list(name = "SYN48", labels = labels),
    samples = paste0("S", seq_len(ns)),
    provenance = list(genome = "SYN")
  )

  # String sugar resolves through match_ms_engine.
  fit_ard <- ms_extract(cat1, k = 2, method = "ard")
  expect_true(S7::S7_inherits(fit_ard, MsSignature))
  expect_true(nrow(fit_ard@signatures) == ch)
  expect_true(ncol(fit_ard@signatures) <= 2L) # ARD may prune

  # Audited P0 regression: the ARD pruned faces must be row-major (a
  # column-block assembly scrambled every k_est >= 2 extraction through R).
  # Separable 96x12 truth: ms_ard(k = 3) must recover all planted
  # signatures at cosine >= 0.95 through the FULL R path.
  ch96 <- 96L
  k3 <- 3L
  sigs96 <- t(vapply(0:(k3 - 1L), function(s) {
    v <- numeric(ch96)
    v[(s * 32L + 1L):((s + 1L) * 32L)] <- 1
    v / sqrt(sum(v^2))
  }, numeric(ch96)))
  H96 <- matrix(0.01, k3, 12L)
  for (j in seq_len(12L)) H96[(j - 1L) %% k3 + 1L, j] <- 10
  c96 <- round(100 * t(sigs96) %*% H96)
  dimnames(c96) <- list(paste0("C", seq_len(ch96)), paste0("S", seq_len(12L)))
  cat96 <- ms_catalog(c96, list(name = "SYN96", labels = paste0("C", seq_len(ch96))),
    paste0("S", seq_len(12L)), list(genome = "SYN"))
  fit96 <- ms_extract(cat96, k = k3, method = "ard")
  rec_n <- sweep(fit96@signatures, 2L, sqrt(colSums(fit96@signatures^2)), "/")
  sig_n <- sweep(sigs96, 1L, sqrt(rowSums(sigs96^2)), "/")
  best <- apply(sig_n %*% rec_n, 1L, max)
  expect_true(all(best > 0.95), info = paste(round(best, 4), collapse = ", "))

  fit_sp <- ms_extract(cat1, k = 2, method = ms_sparse(variant = "l1", lambda = 0.1, mu = 0.1))
  expect_true(S7::S7_inherits(fit_sp, MsSignature))
  expect_true(all(is.finite(as.numeric(fit_sp@signatures))))

  # Object first-class citizen: identical results via spec object.
  fit_ard2 <- ms_extract(cat1, k = 2, method = ms_ard())
  expect_identical(fit_ard@signatures, fit_ard2@signatures)

  # Bad variant rejected by the spec validator (msuiter_error_engine).
  expect_error(ms_sparse(variant = "elastic"), class = "msuiter_error_engine")
})
