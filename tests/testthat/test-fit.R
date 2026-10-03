# ms_fit(): reference-based exposure fitting (U-M3a-02).
#
# Everything is synthetic: a separable 24-channel x 6-sample catalog built
# from a two-signature truth with exclusive anchor channels (the
# asymmetric-golden discipline of the FFI layout contract: m != n, so a
# transposed handoff cannot pass the recovery gates). Three-method
# recovery, evidence tables, method sugar, error paths, determinism.

# Separable truth (list w, h, counts): 2 signatures x 24 channels, 6
# samples in three groups of 2 (two near-pure groups + one mixed).
.ms_fit_truth <- function(seed = 23) {
  m <- 24L
  n <- 6L
  k <- 2L
  withr::with_seed(seed, {
    w <- matrix(0, nrow = m, ncol = k)
    for (s in seq_len(k)) {
      col <- rep(0, m)
      idx <- ((s - 1L) * 12L + 1L):(s * 12L)
      col[idx] <- 0.5 + runif(12L)
      w[, s] <- col / sum(col)
    }
    h <- matrix(0, nrow = k, ncol = n)
    for (j in seq_len(n)) {
      dom <- ((j - 1L) %/% 2L) + 1L # groups 1..2 near-pure, 3 mixed
      for (s in seq_len(k)) {
        h[s, j] <- if (dom == 3L || s == dom) 400 + 800 * runif(1) else 30 * runif(1)
      }
    }
    counts <- round(w %*% h)
  })
  list(w = w, h = h, counts = counts)
}

.ms_fit_catalog <- function(seed = 23) {
  truth <- .ms_fit_truth(seed)
  labels <- sprintf("CH%02d", seq_len(nrow(truth$counts)))
  samples <- sprintf("F%02d", seq_len(ncol(truth$counts)))
  dimnames(truth$counts) <- list(labels, samples)
  ms_catalog(
    counts = truth$counts,
    channels = list(name = "SYN24", labels = labels),
    samples = samples,
    provenance = list(genome = "SYN-true")
  )
}

.ms_fit_fixture <- function(seed = 23) {
  truth <- .ms_fit_truth(seed)
  catalog <- .ms_fit_catalog(seed)
  sigs <- truth$w
  colnames(sigs) <- c("SIGa", "SIGb")
  dimnames(sigs) <- list(rownames(catalog@counts), c("SIGa", "SIGb"))
  list(truth = truth, catalog = catalog, sigs = sigs)
}

# Reconstruction cosine of counts vs S %*% exposures (flattened).
.ms_fit_recon_cos <- function(fit, sigs, counts) {
  recon <- as.vector(sigs %*% fit@exposures)
  obs <- as.vector(counts)
  sum(recon * obs) / sqrt(sum(recon^2) * sum(obs^2))
}

test_that("all three methods fit a separable catalog to an MsFit", {
  fx <- .ms_fit_fixture()
  for (method in c("nnls", "likelihood_bidirectional", "lrt")) {
    fit <- ms_fit(fx$catalog, fx$sigs, method = method)
    expect_is_ms(fit, "MsFit")
    expect_identical(fit@engine, method)
    # exposures: signatures x samples, fully labelled, non-negative.
    expect_identical(dim(fit@exposures), c(2L, 6L))
    expect_identical(rownames(fit@exposures), c("SIGa", "SIGb"))
    expect_identical(colnames(fit@exposures), colnames(fx$catalog@counts))
    expect_true(all(fit@exposures >= 0))
    # Separable truth reconstructs to cosine >= 0.99 for every method.
    expect_gte(.ms_fit_recon_cos(fit, fx$sigs, fx$catalog@counts), 0.99)
    # tidy evidence tables: one row per (signature, sample).
    expect_identical(nrow(fit@support), 12L)
    expect_identical(nrow(fit@tests), 12L)
    expect_named(fit@support, c("signature", "sample", "exposure", "share", "active"))
    expect_named(fit@tests, c("signature", "sample", "lrt_stat", "lrt_p", "se"))
    expect_true(all(fit@tests$lrt_stat >= 0))
    expect_true(all(fit@tests$lrt_p >= 0 & fit@tests$lrt_p <= 0.5))
    # adhoc reference_summary: contracted snapshot fields + sha256 hex.
    expect_named(fit@reference_summary,
      c("version", "class", "build", "schema_version", "sha256", "n_signatures"))
    expect_identical(fit@reference_summary$class, "adhoc")
    expect_true(is.na(fit@reference_summary$build))
    expect_match(fit@reference_summary$sha256, "^[0-9a-f]{64}$")
    expect_identical(fit@reference_summary$n_signatures, 2L)
  }
})

test_that("exposures recover the truth on near-pure samples (nnls)", {
  fx <- .ms_fit_fixture()
  fit <- ms_fit(fx$catalog, fx$sigs)
  for (j in 1:4) { # the two near-pure groups
    h_est <- fit@exposures[, j]
    h_true <- fx$truth$h[, j]
    cos <- sum(h_est * h_true) / sqrt(sum(h_est^2) * sum(h_true^2))
    expect_true(cos >= 0.99, info = paste("sample", j, "cosine", cos))
  }
})

test_that("default method is nnls and string sugar validates", {
  fx <- .ms_fit_fixture()
  expect_identical(
    ms_fit(fx$catalog, fx$sigs)@engine,
    "nnls"
  )
  cnd <- expect_ms_error(
    ms_fit(fx$catalog, fx$sigs, method = "em"),
    "input", regexp = "three methods"
  )
  expect_match(conditionMessage(cnd), "lrt", all = FALSE)
})

test_that("MsSignature input dispatches to its signatures matrix", {
  fx <- .ms_fit_fixture()
  h_labelled <- fx$truth$h
  dimnames(h_labelled) <- list(c("SIGa", "SIGb"), colnames(fx$catalog@counts))
  sig_obj <- ms_signature(
    signatures = fx$sigs,
    exposures = h_labelled,
    catalog_summary = list(
      n_channels = nrow(fx$sigs), n_samples = 6L, channel_name = "SYN24",
      channel_hash = msuiter_hash_labels(rownames(fx$sigs)),
      build = "SYN-true"
    ),
    engine = "synthetic-engine",
    seed = 1234
  )
  from_obj <- ms_fit(fx$catalog, sig_obj)
  from_mat <- ms_fit(fx$catalog, fx$sigs)
  expect_identical(from_obj@exposures, from_mat@exposures)
  expect_identical(from_obj@tests, from_mat@tests)
})

test_that("zeroing zeroes tiny-share exposures and marks the tables", {
  fx <- .ms_fit_fixture()
  # Scale the mixed-group truth so one signature holds a < 1% share in the
  # mixed samples is hard to force exactly; instead shrink the catalog
  # counts of one near-pure group's minority channel: simpler route — fit
  # with an aggressive threshold so every minority exposure is zeroed.
  fit <- ms_fit(fx$catalog, fx$sigs, zero_threshold = 0.2)
  # In the near-pure groups the minority signature carries < 20% share.
  minority <- fit@support[fit@support$signature == "SIGb" &
    fit@support$sample %in% c("F01", "F02"), ]
  expect_true(all(!minority$active))
  expect_true(all(minority$exposure == 0))
  # Zeroed entries keep share 0 and lose their interval (boundary).
  expect_true(all(minority$share == 0))
  zeroed_tests <- fit@tests[fit@tests$signature == "SIGb" &
    fit@tests$sample %in% c("F01", "F02"), ]
  expect_true(all(is.na(zeroed_tests$se)))
  # Shares of active rows sum to 1 per sample (up to rounding).
  per_sample <- aggregate(share ~ sample, data = fit@support, FUN = sum)
  expect_true(all(abs(per_sample$share - 1) < 1e-8))
})

test_that("presence tests separate present from absent signatures (lrt)", {
  fx <- .ms_fit_fixture()
  fit <- ms_fit(fx$catalog, fx$sigs, method = "lrt")
  # The DOMINANT signature of every near-pure sample must be decisively
  # present; a tiny minority exposure (< 30 of ~1400 mutations) may
  # legitimately be ambiguous, so only the p-value domain is pinned there.
  expect_true(all(fit@tests$lrt_p >= 0 & fit@tests$lrt_p <= 0.5))
  dom_a <- fit@tests[fit@tests$sample %in% c("F01", "F02") &
    fit@tests$signature == "SIGa", ] # group 1: SIGa dominant
  dom_b <- fit@tests[fit@tests$sample %in% c("F03", "F04") &
    fit@tests$signature == "SIGb", ] # group 2: SIGb dominant
  expect_true(all(dom_a$lrt_p < 0.01), info = "group-1 dominant decisively present")
  expect_true(all(dom_b$lrt_p < 0.01), info = "group-2 dominant decisively present")
  # And the deterministic boundary case: an all-zero sample scores p = 0.5.
  cat0 <- fx$catalog
  cat0@counts[, 1] <- 0
  fit0 <- ms_fit(cat0, fx$sigs, method = "lrt")
  expect_true(all(fit0@tests$lrt_p[fit0@tests$sample == "F01"] == 0.5))
  expect_true(all(fit0@support$exposure[fit0@support$sample == "F01"] == 0))
})

test_that("channel labels align by label, not by position", {
  fx <- .ms_fit_fixture()
  permuted <- fx$sigs[rev(seq_len(nrow(fx$sigs))), ]
  fit_ref <- ms_fit(fx$catalog, fx$sigs)
  fit_per <- ms_fit(fx$catalog, permuted)
  # After label re-alignment the permutation must change nothing.
  expect_identical(fit_per@exposures, fit_ref@exposures)
  # A dictionary over the wrong channel table is an input error.
  bad <- fx$sigs[1:12, ]
  expect_ms_error(
    ms_fit(fx$catalog, bad),
    "input", regexp = "channel dimension"
  )
  broken <- fx$sigs
  rownames(broken)[1] <- "NOPE"
  expect_ms_error(
    ms_fit(fx$catalog, broken),
    "input", regexp = "missing from signatures"
  )
})

test_that("error paths are structured msuiter_error_* conditions", {
  fx <- .ms_fit_fixture()
  # Non-MsCatalog dispatch fallback.
  expect_ms_error(ms_fit("not-a-catalog", fx$sigs), "input")
  # Dictionary form.
  expect_ms_error(
    ms_fit(fx$catalog, as.numeric(fx$sigs)),
    "input", regexp = "matrix"
  )
  # Degenerate dictionary column.
  degenerate <- fx$sigs
  degenerate[, 2] <- 0
  expect_ms_error(
    ms_fit(fx$catalog, degenerate),
    "signature", regexp = "no positive mass"
  )
  # Duplicate signature labels.
  dup <- fx$sigs
  colnames(dup)[2] <- "SIGa"
  expect_ms_error(
    ms_fit(fx$catalog, dup),
    "input", regexp = "unique"
  )
  # Scalar domains.
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, nb_size = 0), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, nb_size = -1), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, zero_threshold = 1.5), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, zero_threshold = NA), "input")
})

test_that("fitting is deterministic across calls", {
  fx <- .ms_fit_fixture()
  a <- ms_fit(fx$catalog, fx$sigs, method = "likelihood_bidirectional")
  b <- ms_fit(fx$catalog, fx$sigs, method = "likelihood_bidirectional")
  expect_identical(a@exposures, b@exposures)
  expect_identical(a@support, b@support)
  expect_identical(a@tests, b@tests)
  expect_identical(a@reference_summary, b@reference_summary)
})

test_that("the adhoc digest is a real SHA-256 (FIPS 180-4 vectors)", {
  sha <- function(s) .ms_fit_sha256(charToRaw(s))
  # Known vectors.
  expect_identical(sha(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  expect_identical(sha("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  # Long payload crossing several blocks (56+ bytes of padding boundary).
  expect_identical(
    sha(strrep("msuiter", 40L)),
    "08974900a77747ec8e6912ed26caad16c28132924a3355f350faa2e477867b30"
  )
  # The labels-digest canonical form (length-prefixed UTF-8 lines).
  expect_identical(
    .ms_fit_sha256_labels(c("SBS1", "SBS2")),
    "e3b332c7ed06cfcb684b85cd801c8a2e6c13402b83ee1c6d33d1e0cad8e48fac"
  )
})

# ---------------------------------------------------------------------------
# U-M3a-05: TMB rescale + connected-signature rejoin (FixAndRefit).
# ---------------------------------------------------------------------------

# Golden fixture mirroring the Rust connected golden: 2 channels, 1 sample,
# dictionary (0.6, 0.4) / (0.5, 0.5), counts (58, 42). The bidirectional
# method removes the second signature; connected = 2 rejoins it at its
# initial NNLS value 20 and re-optimizes the first signature to exactly 80
# (hand-derived: rhs = 51.6 - 0.5 * 20 = 41.6; 41.6 / 0.52 = 80).
.ms_fit_connected_fixture <- function() {
  labels <- c("CH1", "CH2")
  counts <- matrix(c(58, 42), nrow = 2, dimnames = list(labels, "S01"))
  sigs <- matrix(c(0.6, 0.4, 0.5, 0.5), nrow = 2, dimnames = list(labels, c("SIGa", "SIGb")))
  catalog <- ms_catalog(
    counts = counts,
    channels = list(name = "SYN2", labels = labels),
    samples = "S01",
    provenance = list(genome = "SYN")
  )
  list(catalog = catalog, sigs = sigs, counts = counts)
}

test_that("connected FixAndRefit rejoins the clock signature (golden)", {
  fx <- .ms_fit_connected_fixture()
  ref <- ms_fit(fx$catalog, fx$sigs, method = "likelihood_bidirectional",
    rescale = FALSE)
  # Without the rejoin the sparse refit keeps only SIGa (h0 = 99.2308...).
  expect_identical(ref@support$active, c(TRUE, FALSE))
  # connected = 2: SIGb is FIXED at its initial NNLS value 20, SIGa is
  # re-optimized on the residual to exactly 80.
  fit <- ms_fit(fx$catalog, fx$sigs, method = "likelihood_bidirectional",
    rescale = FALSE, connected = 2)
  expect_equal(as.numeric(fit@exposures), c(80, 20), tolerance = 1e-8)
  expect_true(all(fit@support$active))
  # Presence evidence is untouched by the post-steps (bit-identical grids).
  expect_identical(ref@tests$lrt_stat, fit@tests$lrt_stat)
  expect_identical(ref@tests$lrt_p, fit@tests$lrt_p)
})

test_that("rescale restores the original per-sample totals (conservation)", {
  fx <- .ms_fit_connected_fixture()
  # The bidirectional solution sums to 99.23... < 100 on this fixture; the
  # default rescale multiplies it back onto the 100-mutation total.
  raw <- ms_fit(fx$catalog, fx$sigs, method = "likelihood_bidirectional",
    rescale = FALSE)
  expect_equal(sum(raw@exposures), 51.6 / 0.52, tolerance = 1e-8)
  rescaled <- ms_fit(fx$catalog, fx$sigs, method = "likelihood_bidirectional")
  expect_equal(sum(rescaled@exposures), sum(fx$counts), tolerance = 1e-12)
  # Shares and zeroing decisions are invariant (per-sample scale invariance).
  expect_identical(raw@support$active, rescaled@support$active)
  expect_equal(raw@support$share, rescaled@support$share, tolerance = 1e-12)
})

test_that("default rescale keeps separable recovery and conserves totals", {
  fx <- .ms_fit_fixture()
  fit <- ms_fit(fx$catalog, fx$sigs, zero_threshold = 0)
  expect_gte(.ms_fit_recon_cos(fit, fx$sigs, fx$catalog@counts), 0.99)
  expect_equal(colSums(fit@exposures), colSums(fx$catalog@counts),
    tolerance = 1e-12
  )
})

test_that("connected rejoin keeps separable recovery (regression)", {
  fx <- .ms_fit_fixture()
  fit <- ms_fit(fx$catalog, fx$sigs, connected = 1, zero_threshold = 0)
  expect_gte(.ms_fit_recon_cos(fit, fx$sigs, fx$catalog@counts), 0.99)
  # With the nnls method the full-dictionary rejoin is (numerically) the
  # plain fit: every component already sits at its initial NNLS value.
  plain <- ms_fit(fx$catalog, fx$sigs, zero_threshold = 0, rescale = FALSE)
  full <- ms_fit(fx$catalog, fx$sigs, connected = c(1, 2),
    zero_threshold = 0, rescale = FALSE)
  expect_equal(as.vector(full@exposures), as.vector(plain@exposures),
    tolerance = 1e-8
  )
})

test_that("connected and rescale gates raise structured errors", {
  fx <- .ms_fit_fixture()
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, connected = 0), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, connected = 3), "input",
    regexp = "1, k]"
  )
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, connected = c(1, 1)), "input",
    regexp = "distinct"
  )
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, connected = "SIGa"), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, connected = NA), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, rescale = "yes"), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, rescale = NA), "input")
  expect_ms_error(ms_fit(fx$catalog, fx$sigs, rescale = c(TRUE, TRUE)), "input")


test_that("connected spec is order-insensitive (audited P1-1 regression)", {
  ch <- 24L
  ns <- 6L
  counts <- matrix(1:(ch * ns), ch, ns)
  dimnames(counts) <- list(paste0("C", seq_len(ch)), paste0("S", seq_len(ns)))
  cat1 <- ms_catalog(
    counts = counts,
    channels = list(name = "SYN24", labels = labels <- paste0("C", seq_len(ch))),
    samples = paste0("S", seq_len(ns)),
    provenance = list(genome = "SYN")
  )
  sigs <- matrix(1:(ch * 2), ch, 2)
  fit12 <- ms_fit(cat1, sigs, method = "nnls", connected = c(1, 2))
  fit21 <- ms_fit(cat1, sigs, method = "nnls", connected = c(2, 1))
  # Audited P1-1: reversed input previously corrupted FixAndRefit
  # (exposures (999, 0) instead of the fixed-component solution).
  expect_identical(fit12@exposures, fit21@exposures)
  expect_true(all(is.finite(fit21@exposures)))
})
})
