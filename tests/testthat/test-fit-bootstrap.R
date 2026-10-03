# U-M3a-03: ms_fit_bootstrap() + ms_test_presence().
#
# Everything is synthetic (the separable-truth pattern of test-fit.R): a
# 24-channel x 6-sample catalog from a two-signature truth with exclusive
# anchor channels. Bootstrap: CI coverage of the truth, seed determinism,
# thread invariance, method reuse, error paths. Presence: the kernel face
# vs the MsFit aggregation face, BH semantics (the pure-R twin pinned
# bit-for-bit against the kernel), size/power smoke, error paths.

# Separable truth (list w, h, counts): 2 signatures x 24 channels, 6
# samples in three groups of 2. `null_second = TRUE` removes signature 2
# from the generative truth (h[2, ] = 0) -- the null model of the
# presence size smoke.
.ms_boot_truth <- function(seed = 23, null_second = FALSE) {
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
        h[s, j] <- if (null_second && s == 2L) 0 else
          if (dom == 3L || s == dom) 400 + 800 * runif(1) else 30 * runif(1)
      }
    }
    counts <- round(w %*% h)
  })
  list(w = w, h = h, counts = counts)
}

.ms_boot_catalog <- function(truth) {
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

.ms_boot_fixture <- function(seed = 23, null_second = FALSE) {
  truth <- .ms_boot_truth(seed, null_second)
  catalog <- .ms_boot_catalog(truth)
  sigs <- truth$w
  dimnames(sigs) <- list(rownames(catalog@counts), c("SIGa", "SIGb"))
  list(truth = truth, catalog = catalog, sigs = sigs)
}

test_that("ms_fit_bootstrap returns an MsFit whose CI covers the truth", {
  fx <- .ms_boot_fixture()
  boot <- ms_fit_bootstrap(fx$catalog, fx$sigs, method = "nnls",
    n_boot = 25, seed = 1)
  expect_is_ms(boot, "MsFit")
  expect_identical(boot@engine, "nnls")
  # Point exposures: labelled k x samples, non-negative, like ms_fit.
  expect_identical(dim(boot@exposures), c(2L, 6L))
  expect_identical(rownames(boot@exposures), c("SIGa", "SIGb"))
  expect_true(all(boot@exposures >= 0))
  # CI attributes: labelled k x samples, ordered bounds, stability on [0,1].
  ci_low <- attr(boot@exposures, "ci_lower")
  ci_up <- attr(boot@exposures, "ci_upper")
  stab <- attr(boot@exposures, "support_stability")
  expect_identical(dim(ci_low), c(2L, 6L))
  expect_identical(dimnames(ci_low), dimnames(boot@exposures))
  expect_identical(dimnames(ci_up), dimnames(boot@exposures))
  expect_identical(dimnames(stab), dimnames(boot@exposures))
  expect_true(all(ci_low <= ci_up))
  expect_true(all(stab >= 0 & stab <= 1))
  expect_identical(attr(boot@exposures, "n_boot"), 25L)
  expect_identical(attr(boot@exposures, "seed"), 1L)
  expect_identical(attr(boot@exposures, "ci_level"), c(lower = 0.025, upper = 0.975))
  # The support tidy table gains the boot_stability column; the tests table
  # is the point fit's (identical to ms_fit's on the same inputs).
  expect_named(boot@support,
    c("signature", "sample", "exposure", "share", "active", "boot_stability"))
  expect_named(boot@tests, c("signature", "sample", "lrt_stat", "lrt_p", "se"))
  ref_fit <- ms_fit(fx$catalog, fx$sigs, method = "nnls")
  expect_identical(boot@tests, ref_fit@tests)
  # Coverage: the truth lies inside the percentile CI for the dominant
  # near-pure cells (strong signal; the Rust suite pins the 95%-level
  # calibration on simulated experiments, this is the end-to-end guard).
  truth_h <- fx$truth$h
  for (j in 1:4) { # the two near-pure groups
    dom <- if (j <= 2L) "SIGa" else "SIGb"
    a <- match(dom, c("SIGa", "SIGb"))
    # Coverage: truth inside the percentile interval.
    expect_lte(ci_low[a, j], truth_h[a, j])
    expect_gte(ci_up[a, j], truth_h[a, j])
    expect_identical(stab[a, j], 1) # every replicate keeps the dominant exposure
  }
  # The support table's boot_stability mirrors the attribute grid.
  stab_lookup <- boot@support$boot_stability[
    boot@support$signature == "SIGa" & boot@support$sample == "F01"]
  expect_identical(stab_lookup, stab["SIGa", "F01"])
})

test_that("bootstrap is seed-deterministic and thread-invariant end to end", {
  fx <- .ms_boot_fixture()
  grab <- function(threads) {
    withr::with_options(list(msuiter.threads = threads), {
      ms_fit_bootstrap(fx$catalog, fx$sigs, n_boot = 12, seed = 7)
    })
  }
  a <- grab(1)
  b <- grab(2)
  expect_identical(a@exposures, b@exposures)
  expect_identical(attr(a@exposures, "ci_lower"), attr(b@exposures, "ci_lower"))
  expect_identical(attr(a@exposures, "ci_upper"), attr(b@exposures, "ci_upper"))
  expect_identical(
    attr(a@exposures, "support_stability"),
    attr(b@exposures, "support_stability")
  )
  expect_identical(a@support, b@support)
  # A different seed moves at least one percentile bound.
  c1 <- ms_fit_bootstrap(fx$catalog, fx$sigs, n_boot = 12, seed = 8)
  expect_false(identical(
    attr(a@exposures, "ci_lower"),
    attr(c1@exposures, "ci_lower")
  ))
})

test_that("bootstrap reuses the three methods", {
  fx <- .ms_boot_fixture()
  for (method in c("nnls", "likelihood_bidirectional", "lrt")) {
    boot <- ms_fit_bootstrap(fx$catalog, fx$sigs, method = method,
      n_boot = 4, seed = 3)
    expect_identical(boot@engine, method)
    expect_true(all(attr(boot@exposures, "ci_lower") <=
      attr(boot@exposures, "ci_upper")))
    expect_true(all(attr(boot@exposures, "support_stability") >= 0 &
      attr(boot@exposures, "support_stability") <= 1))
  }
})

test_that("bootstrap error paths are structured msuiter_error_* conditions", {
  fx <- .ms_boot_fixture()
  expect_ms_error(ms_fit_bootstrap("not-a-catalog", fx$sigs), "input")
  expect_ms_error(ms_fit_bootstrap(fx$catalog, "not-a-matrix"), "input")
  expect_ms_error(ms_fit_bootstrap(fx$catalog, fx$sigs, n_boot = 0), "input")
  expect_ms_error(ms_fit_bootstrap(fx$catalog, fx$sigs, n_boot = 12.5), "input")
  expect_ms_error(ms_fit_bootstrap(fx$catalog, fx$sigs, seed = -1), "input")
  expect_ms_error(ms_fit_bootstrap(fx$catalog, fx$sigs, method = "em"), "input")
  expect_ms_error(ms_fit_bootstrap(fx$catalog, fx$sigs, nb_size = 0), "input")
})

test_that("presence test (catalog face) separates present from absent signatures", {
  fx <- .ms_boot_fixture()
  pres <- ms_test_presence(fx$catalog, fx$sigs)
  expect_s3_class(pres, "data.frame")
  expect_identical(nrow(pres), 2L)
  expect_named(pres, c("signature", "stat", "p_raw", "p_bh", "pass_bh"))
  expect_identical(pres$signature, c("SIGa", "SIGb"))
  expect_true(all(pres$p_raw >= 0 & pres$p_raw <= 1))
  expect_true(all(pres$p_bh >= pres$p_raw))
  expect_identical(pres$pass_bh, pres$p_bh <= 0.05)
  # Both signatures carry real mass in the mixed truth -> both decisively
  # present at the cohort level.
  expect_true(all(pres$pass_bh), info = "both signatures present")
  expect_true(all(pres$stat > 10), info = "decisive statistics")

  # Null truth: SIGb generates nothing -> it must not pass, SIGa must.
  fx0 <- .ms_boot_fixture(seed = 31, null_second = TRUE)
  pres0 <- ms_test_presence(fx0$catalog, fx0$sigs)
  a <- pres0[pres0$signature == "SIGa", ]
  b <- pres0[pres0$signature == "SIGb", ]
  expect_true(a$pass_bh, info = "present signature detected (power)")
  expect_false(b$pass_bh, info = "absent signature not flagged (size)")
})

test_that("presence size smoke stays at level over null replicates", {
  # 40 fixed-seed null catalogs (SIGb generates nothing): the BH verdict on
  # the absent signature must reject well below the familywise level's
  # MC noise (deterministic given the seed; the exact calibration is the
  # Rust suite's MC contract).
  rejects <- 0L
  for (r in 1:40) {
    fx0 <- .ms_boot_fixture(seed = 100 + r, null_second = TRUE)
    pres0 <- ms_test_presence(fx0$catalog, fx0$sigs)
    if (pres0$pass_bh[pres0$signature == "SIGb"]) rejects <- rejects + 1L
  }
  expect_lte(rejects, 6L)
})

test_that("presence test (MsFit face) agrees with the catalog face", {
  fx <- .ms_boot_fixture()
  fit <- ms_fit(fx$catalog, fx$sigs, method = "lrt")
  from_fit <- ms_test_presence(fit)
  from_cat <- ms_test_presence(fx$catalog, fx$sigs)
  expect_identical(nrow(from_fit), 2L)
  expect_named(from_fit, c("signature", "stat", "p_raw", "p_bh", "pass_bh"))
  expect_identical(from_fit$signature, from_cat$signature)
  # Same evidence machinery: equality is analytic (the R path re-derives
  # p-values from the pooled statistic), not bit-level.
  expect_equal(from_fit$stat, from_cat$stat, tolerance = 1e-8)
  expect_equal(from_fit$p_raw, from_cat$p_raw, tolerance = 1e-8)
  expect_equal(from_fit$p_bh, from_cat$p_bh, tolerance = 1e-8)
  expect_identical(from_fit$pass_bh, from_cat$pass_bh)
  # The MsFit face re-derives p_raw with the pure-R mixture twin: pin it
  # against the hand-computed exact pooled null (n = 6 samples here).
  n6 <- ncol(fit@exposures)
  hand <- vapply(from_fit$stat, function(d) {
    sum(dbinom(1:n6, n6, 0.5) * pchisq(d, df = 1:n6, lower.tail = FALSE))
  }, numeric(1L), USE.NAMES = FALSE)
  expect_equal(from_fit$p_raw, hand, tolerance = 1e-10)
  # The MsFit face must reject a stray signatures argument.
  expect_ms_error(ms_test_presence(fit, fx$sigs), "input")
})

test_that("the exact pooled-null twin matches the kernel semantics", {
  # n = 1: bit-identical to the Self-Liang boundary half-tail (the kernel's
  # n = 1 degeneracy, mirrored in R).
  stat <- c(0, 0.5, 2.705543454095404, 12, 40)
  expect_identical(
    .ms_presence_pooled_p(stat, 1),
    0.5 * pchisq(stat, df = 1, lower.tail = FALSE)
  )
  # n = 2 (hand-derivable): P = 1/2 * P(chi^2_1 > D) + 1/4 * P(chi^2_2 > D)
  # (the delta_0 atom is 0 for D >= 0). Golden from 30-digit mpmath.
  expect_equal(
    .ms_presence_pooled_p(c(0.5, 3.841458820694124, 12), 2),
    c(0.43445025686132795, 0.06162501612152111, 0.0008856907967362144),
    tolerance = 1e-12
  )
  # D = 0: every chi^2_m term is 1, the atom is 0 -> p = 1 - 2^-n (the
  # computed weight sum; also pins the dbinom far-tail underflow parity).
  expect_equal(.ms_presence_pooled_p(0, 2), 0.75, tolerance = 1e-12)
  expect_equal(.ms_presence_pooled_p(0, 1500), 1, tolerance = 1e-12)
  # Degenerate thresholds mirror the kernel: negative -> 1, +Inf -> 0.
  expect_identical(.ms_presence_pooled_p(c(-1, Inf), 4), c(1, 0))
  # Error paths.
  expect_ms_error(.ms_presence_pooled_p(numeric(0), 4), "input")
  expect_ms_error(.ms_presence_pooled_p(1, 0), "input")
})

test_that("presence H0 calibration matrix (exact pooled null, R face)", {
  # P0 acceptance, R face: under H0 (signature 2 absent, signature 1
  # present; Poisson-limit NB) the BH verdict on the absent signature must
  # stay at level for EVERY cohort size. The old chi^2_1 half-tail
  # reference measured 0.117/0.261/0.557/0.920 at n = 2/4/8/16 (the
  # independent audit's phenomenon); the exact Binomial(n, 1/2)-mixed
  # chi^2 reference restores calibration. Fixed seeds, deterministic.
  sigs <- cbind(c(0.5, 0.5), c(0.9, 0.1))
  n_reps <- 400L
  for (n in c(1L, 2L, 4L, 8L, 16L)) {
    # Fresh Poisson catalogs per replicate: a (2, n, n_reps) cube of
    # i.i.d. Poisson(500) draws (both channels, matching the kernel
    # suite's H0 fixture); stored as double for the FFI boundary.
    counts <- withr::with_seed(9000 + n, {
      array(as.numeric(rpois(n_reps * 2L * n, 500)), dim = c(2L, n, n_reps))
    })
    rejects <- 0L
    for (r in seq_len(n_reps)) {
      res <- .ms_test_presence_rust(matrix(counts[, , r], nrow = 2L), sigs, 1e8)
      if (isTRUE(res$pass_bh[2])) rejects <- rejects + 1L
    }
    rate <- rejects / n_reps
    expect_true(
      rate >= 0.02 && rate <= 0.08,
      info = sprintf("H0 pass_bh rate at n=%d: %.4f (%d/%d)", n, rate,
        rejects, n_reps)
    )
  }
})

test_that("the pure-R BH twin is bit-identical to the kernel fold-back", {
  fx <- .ms_boot_fixture()
  res <- .ms_test_presence_rust(fx$catalog@counts, fx$sigs, 8)
  twin <- .ms_bh_adjust(res$lrt_p_raw)
  expect_identical(twin, res$lrt_p_bh)
  # And the hand-derived golden (mirrors the Rust bh_golden_fold_back):
  # sorted m/i scaling [0.02, 0.02, 0.04, 0.04] folds back monotonically
  # and maps back to the original order.
  expect_identical(
    .ms_bh_adjust(c(0.01, 0.04, 0.03, 0.005)),
    c(0.02, 0.04, 0.04, 0.02)
  )
  expect_identical(.ms_bh_adjust(c(0.5, 0.6)), c(0.6, 0.6))
  expect_identical(.ms_bh_adjust(0.3), 0.3)
  expect_ms_error(.ms_bh_adjust(c(0.5, NA)), "input")
  expect_ms_error(.ms_bh_adjust(c(0.5, 1.5)), "input")
  expect_ms_error(.ms_bh_adjust(numeric(0)), "input")
})

test_that("presence error paths are structured msuiter_error_* conditions", {
  fx <- .ms_boot_fixture()
  expect_ms_error(ms_test_presence("not-a-catalog", fx$sigs), "input")
  expect_ms_error(ms_test_presence(fx$catalog, "not-a-matrix"), "input")
  expect_ms_error(ms_test_presence(fx$catalog, fx$sigs, nb_size = 0), "input")
  expect_ms_error(ms_test_presence(fx$catalog, fx$sigs, nb_size = NA), "input")
  bad <- fx$sigs[1:12, ]
  expect_ms_error(ms_test_presence(fx$catalog, bad), "input")
  # An MsFit cannot carry unlabelled exposures: the class validator (topic
  # "fit") fires before the presence table could be keyed -- the presence
  # label guard is defense in depth behind it.
  expect_ms_error(
    MsFit(
      exposures = matrix(c(1, 2), nrow = 2L),
      engine = "synthetic",
      reference_summary = list(version = "adhoc-1", class = "adhoc",
        build = NA_character_, schema_version = "1", sha256 = strrep("0", 64L),
        n_signatures = 2L),
      support = data.frame(), tests = data.frame()
    ),
    "fit"
  )
})
