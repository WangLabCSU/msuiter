# Shared fixtures for the U-M1s-12 extraction tests (ms_nmf / ms_extract).
#
# Everything is synthetic: a 96 x 12 catalog (ASYMMETRIC on purpose -- the
# transposition guard of the FFI layout contract) built from a separable
# truth with the sample-purity structure that makes the dictionary
# identifiable (each signature owns 32 exclusive anchor channels; three
# near-pure sample groups pin the rays, one fully mixed group), mirroring
# the acceptance construction of the Rust kernel tests.

# Re-arm the package's own engine row (idempotent): registry-contract test
# files reset the shared registry, and test file order is not contractual.
.ms_ensure_nmf <- function() {
  msuiter_register_nmf_engine()
  invisible(NULL)
}

# Separable truth (list w, h, counts): 3 signatures x 96 channels, 12
# samples in four groups of 3 (dominant + <=5% cross exposure).
.ms_extract_truth <- function(seed = 11) {
  m <- 96L
  n <- 12L
  k <- 3L
  withr::with_seed(seed, {
    w <- matrix(0, nrow = m, ncol = k)
    for (s in seq_len(k)) {
      col <- rep(0, m)
      idx <- ((s - 1L) * 32L + 1L):(s * 32L)
      col[idx] <- 0.5 + runif(32L)
      w[, s] <- col / sum(col)
    }
    h <- matrix(0, nrow = k, ncol = n)
    for (j in seq_len(n)) {
      dom <- ((j - 1L) %/% 3L) + 1L # groups 1..3 near-pure, 4 mixed
      for (s in seq_len(k)) {
        h[s, j] <- if (dom == 4L || s == dom) 500 + 1000 * runif(1) else 50 * runif(1)
      }
    }
    counts <- round(w %*% h)
  })
  list(w = w, h = h, counts = counts)
}

# The synthetic 96 x 12 MsCatalog carrying the truth above.
.ms_extract_catalog <- function(seed = 11) {
  truth <- .ms_extract_truth(seed)
  labels <- sprintf("CH%03d", seq_len(nrow(truth$counts)))
  samples <- sprintf("T%02d", seq_len(ncol(truth$counts)))
  dimnames(truth$counts) <- list(labels, samples)
  ms_catalog(
    counts = truth$counts,
    channels = list(name = "SYN96", labels = labels),
    samples = samples,
    provenance = list(genome = "SYN-true")
  )
}

# Ensure + build in one call (every extraction test starts here).
.ms_extract_fixture <- function(seed = 11) {
  .ms_ensure_nmf()
  .ms_extract_catalog(seed)
}

# Cosine between two flattened matrices (reconstruction gate).
.ms_cos <- function(a, b) {
  a <- as.numeric(a)
  b <- as.numeric(b)
  sum(a * b) / sqrt(sum(a * a) * sum(b * b))
}

# ---------------------------------------------------------------------------
# U-M2-03 fixtures: the consensus-CV default pipeline and ms_select_k().
# ---------------------------------------------------------------------------

# Lean separable truth (48 channels x 9 samples, k_true = 3): 16 exclusive
# anchor channels per signature, three near-pure sample groups with a
# 200-count cross exposure -- strong enough for the SUITOR CV argmin to
# land on the true rank while the over-split ranks (4, 5) fail the
# stability veto (the k-select evidence fixture).
.ms_kselect_truth <- function(seed = 11, m = 48L, n = 9L, k = 3L,
                              cross = 200, group = 3L) {
  withr::with_seed(seed, {
    anchors <- m %/% k
    w <- matrix(0, nrow = m, ncol = k)
    for (s in seq_len(k)) {
      col <- rep(0, m)
      idx <- ((s - 1L) * anchors + 1L):(s * anchors)
      col[idx] <- 0.5 + runif(anchors)
      w[, s] <- col / sum(col)
    }
    h <- matrix(0, nrow = k, ncol = n)
    for (j in seq_len(n)) {
      dom <- ((j - 1L) %/% group) + 1L
      for (s in seq_len(k)) {
        h[s, j] <- if (s == dom) 500 + 1000 * runif(1) else cross * runif(1)
      }
    }
    counts <- round(w %*% h)
  })
  list(w = w, h = h, counts = counts)
}

# The synthetic 48 x 9 MsCatalog carrying the truth above.
.ms_kselect_catalog <- function(seed = 11) {
  truth <- .ms_kselect_truth(seed)
  labels <- sprintf("CH%03d", seq_len(nrow(truth$counts)))
  samples <- sprintf("T%02d", seq_len(ncol(truth$counts)))
  dimnames(truth$counts) <- list(labels, samples)
  ms_catalog(
    counts = truth$counts,
    channels = list(name = "SYN48", labels = labels),
    samples = samples,
    provenance = list(genome = "SYN-true")
  )
}

# Catalog + lean pipeline hyper-parameters in one call (the CI-budget
# settings used by every k-select evidence test).
.ms_kselect_fixture <- function(seed = 11) {
  .ms_ensure_nmf()
  list(
    catalog = .ms_kselect_catalog(seed),
    replicates = 6L,
    max_iter = 150L,
    seed = 1,
    k_folds = 5L,
    n_seeds = 3L
  )
}
