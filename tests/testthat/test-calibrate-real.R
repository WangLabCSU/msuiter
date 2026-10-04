# U-M3b-06: ms_calibration_sanity() -- the real-data downsampling sanity
# harness. End to end on a SYNTHETIC catalog (no network, no real data in
# the repo, per the inst/sanity/README.md protocol): the pseudo-truth
# mechanics, the S(N) curve assembly, the +/-0.05 synthetic comparison
# ("or" the wider floor band), the monotonicity gate, determinism, and the
# error protocol. The pure criteria helpers are pinned directly.

# Tuned fixture: a single dominant signature (the secondary signature is
# null), so the kept-entry set is the dominant exposure at share ~1 and
# the diluted percentile CIs cover the diluted pseudo-truth at every level
# -- a stable PASS across seeds (the S(N) curve pins at 1, 1). The
# `mixed` variant keeps the secondary signature (shares ~0.16): the
# diluted CIs then undercover at small dilution levels -- the stable FAIL
# fixture for the within/inversion gates (S(50) ~ 0.90 -> S(200) ~ 0.81 at
# the pinned protocol, a drop past the tolerance = one inverted step).
.ms_sanity_fixture <- function(mixed = FALSE) {
  withr::with_seed(23, {
    m <- 24L
    n <- 4L
    k <- 2L
    w <- matrix(0, nrow = m, ncol = k)
    for (s in seq_len(k)) {
      col <- rep(0, m)
      idx <- ((s - 1L) * 12L + 1L):(s * 12L)
      col[idx] <- 0.5 + runif(12L)
      w[, s] <- col / sum(col)
    }
    h <- matrix(0, nrow = k, ncol = n)
    for (j in seq_len(n)) {
      h[, j] <- c(600 + 300 * runif(1),
        if (mixed) 100 + 50 * runif(1) else 0)
    }
    counts <- round(w %*% h)
  })
  labels <- sprintf("CH%02d", seq_len(24L))
  samples <- sprintf("F%02d", seq_len(4L))
  dimnames(counts) <- list(labels, samples)
  catalog <- ms_catalog(
    counts = counts,
    channels = list(name = "SYN24", labels = labels),
    samples = samples,
    provenance = list(genome = "SYN-true")
  )
  sigs <- w
  dimnames(sigs) <- list(labels, c("SIGa", "SIGb"))
  list(catalog = catalog, sigs = sigs)
}

test_that("ms_calibration_sanity runs end to end and PASSES the clean case", {
  fx <- .ms_sanity_fixture()
  res <- ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 50,
    dilution_sizes = c(50, 200), n_dilutions = 5, seed = 11, n_threads = 1)
  expect_s3_class(res, "ms_calibration_sanity")
  expect_true(res$pass)
  # S(N) curve: one row per level, kept entries x dilutions tallied, all
  # covered (the pinned clean case), floor-only criterion recorded.
  expect_identical(nrow(res$s_curve), 2L)
  expect_named(res$s_curve,
    c("n", "s", "se", "tallies", "deviation", "within"))
  expect_identical(res$s_curve$n, c(50, 200))
  expect_identical(res$s_curve$s, c(1, 1))
  expect_identical(res$s_curve$se, c(0, 0))
  expect_identical(res$s_curve$tallies, c(20L, 20L)) # 4 kept x 5 dilutions
  expect_identical(res$s_curve$within, c(TRUE, TRUE))
  expect_false(res$synthetic_used)
  expect_identical(res$s_curve$deviation, rep(NA_real_, 2L))
  expect_false(res$systematic_inversion)
  expect_identical(res$n_inversions, 0L)
  # Protocol echoes.
  expect_identical(res$tolerance, 0.05)
  expect_identical(res$floor_band, c(lo = 0.90, hi = 1.00))
  expect_identical(res$share_floor, 0.05)
  expect_identical(res$method, "likelihood_bidirectional")
  expect_identical(res$n_boot, 50L)
  expect_identical(res$seed, 11L)
  # The kept table: the dominant signature in every sample.
  expect_identical(unique(res$kept$signature), "SIGa")
  expect_identical(nrow(res$kept), 4L)
  expect_true(all(res$kept$truth_share >= res$share_floor))
  # The print face renders the PASS verdict without error.
  expect_match(paste(capture.output(print(res)), collapse = "\n"), "PASS")
})

test_that("the harness is deterministic in (seed, inputs)", {
  fx <- .ms_sanity_fixture()
  a <- ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 30,
    dilution_sizes = c(50, 200), n_dilutions = 4, seed = 11)
  b <- ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 30,
    dilution_sizes = c(50, 200), n_dilutions = 4, seed = 11)
  expect_identical(a$s_curve, b$s_curve)
  expect_identical(a$kept, b$kept)
  # The caller's RNG state survives the call (the harness restores it).
  before <- if (exists(".Random.seed", envir = .GlobalEnv)) {
    get(".Random.seed", envir = .GlobalEnv)
  }
  ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 20,
    dilution_sizes = c(50), n_dilutions = 2, seed = 11)
  if (is.null(before)) {
    expect_false(exists(".Random.seed", envir = .GlobalEnv))
  } else {
    expect_identical(get(".Random.seed", envir = .GlobalEnv), before)
  }
})

test_that("the +/-0.05 synthetic comparison drives the verdict both ways", {
  fx <- .ms_sanity_fixture()
  # Synthetic curve AT the observed S(N): deviation 0 -> PASS (union gate).
  agree <- ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 50,
    dilution_sizes = c(50, 200), n_dilutions = 5, seed = 11,
    synthetic = data.frame(n = c(50, 200), coverage = c(1, 1)))
  expect_true(agree$synthetic_used)
  expect_identical(agree$s_curve$deviation, c(0, 0))
  expect_true(agree$pass)
  # The mixed fixture undercovers along the axis (pinned seed: S ~ 0.92
  # -> ~ 0.67, a drop past the tolerance = one systematic inversion); a
  # synthetic curve far below (0.5) misses the tolerance band AND the
  # floor band at the deep level -> FAIL on both axes.
  mixed <- .ms_sanity_fixture(mixed = TRUE)
  disagree <- ms_calibration_sanity(mixed$catalog, mixed$sigs, n_boot = 20,
    dilution_sizes = c(50, 200), n_dilutions = 3, seed = 5,
    synthetic = data.frame(n = c(50, 200), coverage = c(0.5, 0.5)))
  expect_false(disagree$pass)
  expect_identical(disagree$s_curve$tallies, c(24L, 24L)) # 8 kept x 3
  expect_equal(disagree$s_curve$s, c(11 / 12, 2 / 3), tolerance = 1e-12)
  expect_false(all(disagree$s_curve$within))
  expect_true(disagree$systematic_inversion)
  expect_identical(disagree$inverted_at, 2L)
  # Missing dilution level in the synthetic curve is a structured error.
  expect_ms_error(ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 20,
    dilution_sizes = c(50, 200), n_dilutions = 2, seed = 11,
    synthetic = data.frame(n = c(50), coverage = 1)), "input")
  # Malformed synthetic table.
  expect_ms_error(ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 20,
    dilution_sizes = c(50), n_dilutions = 2, seed = 11,
    synthetic = data.frame(x = 1)), "input")
})

test_that("the floor band alone gates when no synthetic curve is supplied", {
  fx <- .ms_sanity_fixture()
  res <- ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 50,
    dilution_sizes = c(50, 200), n_dilutions = 5, seed = 11)
  # S = 1 sits inside [0.90, 1.00] even though deviation is undefined.
  expect_false(res$synthetic_used)
  expect_true(all(res$s_curve$within))
  # A synthetic curve that agrees within 0.05 keeps a boundary S in-window
  # through the floor union (the memo's "取宽者").
  edge <- ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = 50,
    dilution_sizes = c(50), n_dilutions = 5, seed = 11,
    synthetic = data.frame(n = 50, coverage = 0.90))
  expect_true(all(edge$s_curve$within))
})

test_that("dead samples are excluded and recorded", {
  fx <- .ms_sanity_fixture()
  counts <- fx$catalog@counts
  counts[, 4L] <- 0
  catalog <- ms_catalog(counts = counts,
    channels = fx$catalog@channels, samples = fx$catalog@samples,
    provenance = fx$catalog@provenance)
  res <- ms_calibration_sanity(catalog, fx$sigs, n_boot = 30,
    dilution_sizes = c(50), n_dilutions = 3, seed = 2)
  expect_identical(res$n_live_samples, 3L)
  expect_identical(res$dead_samples, "F04")
  expect_false("F04" %in% res$kept$sample)
})

test_that("the monotonicity gate: tolerance slack and the systematic rule", {
  # Dyadic values: a drop of exactly the tolerance is noise, not an
  # inversion (exact in binary arithmetic).
  expect_identical(
    .ms_sanity_monotonicity(c(0.875, 0.8125), 0.0625)$n_inversions, 0L)
  one <- .ms_sanity_monotonicity(c(0.875, 0.75, 0.875), 0.0625)
  expect_identical(one$n_inversions, 1L)
  expect_identical(one$inverted_at, 2L)
  expect_false(one$systematic_inversion) # 1 of 2 steps: not a majority
  both <- .ms_sanity_monotonicity(c(0.875, 0.75, 0.625), 0.0625)
  expect_identical(both$n_inversions, 2L)
  expect_identical(both$inverted_at, c(2L, 3L))
  expect_true(both$systematic_inversion)
  # A single-level curve has nothing to invert.
  single <- .ms_sanity_monotonicity(0.95, 0.05)
  expect_false(single$systematic_inversion)
  # Bad shapes.
  expect_ms_error(.ms_sanity_monotonicity(c(0.5, NA), 0.05), "input")
  expect_ms_error(.ms_sanity_monotonicity(c(1.5, 0.5), 0.05), "input")
  expect_ms_error(.ms_sanity_monotonicity(0.5, 1.5), "input")
})

test_that("the window criterion helper: tolerance band and floor union", {
  s <- c(0.85, 0.92, 0.97)
  levels <- c(50, 100, 200)
  # Floor-only criterion (no synthetic curve).
  floor_only <- .ms_sanity_window(s, levels, NULL, 0.05)
  expect_identical(floor_only$within, c(FALSE, TRUE, TRUE))
  expect_identical(floor_only$deviation, rep(NA_real_, 3L))
  # Synthetic at 1.0: boundary deviation 0.05 stays in (<=), the wider
  # deviations survive only through the floor union (the memo's 取宽者).
  synth <- data.frame(n = levels, coverage = c(1, 1, 1))
  w <- .ms_sanity_window(s, levels, synth, 0.05)
  expect_identical(w$within, c(FALSE, TRUE, TRUE))
  expect_equal(w$deviation, c(0.15, 0.08, 0.03), tolerance = 1e-12)
  # Misaligned levels are a structured error.
  expect_ms_error(.ms_sanity_window(s, c(50, 100), synth, 0.05), "input")
  expect_ms_error(.ms_sanity_window(s, levels, synth, 1.5), "input")
})

test_that("sanity error paths are structured msuiter_error_* conditions", {
  fx <- .ms_sanity_fixture()
  run <- function(dilution_sizes = c(50), n_dilutions = 2, n_boot = 20,
                  seed = 11, nb_size = 8, bca = FALSE,
                  tolerance = .MS_SANITY_TOLERANCE, ...) {
    ms_calibration_sanity(fx$catalog, fx$sigs, n_boot = n_boot,
      dilution_sizes = dilution_sizes, n_dilutions = n_dilutions,
      seed = seed, nb_size = nb_size, bca = bca, tolerance = tolerance, ...)
  }
  expect_ms_error(ms_calibration_sanity("not-a-catalog", fx$sigs), "input")
  expect_ms_error(run(dilution_sizes = c(200, 50)), "input") # decreasing
  expect_ms_error(run(dilution_sizes = 0), "input")
  expect_ms_error(run(dilution_sizes = 10^9), "input") # above the live totals
  expect_ms_error(run(n_dilutions = 0), "input")
  expect_ms_error(run(n_dilutions = 4097), "input")
  expect_ms_error(run(tolerance = 1.5), "input")
  expect_ms_error(run(n_boot = 0), "input")
  expect_ms_error(run(seed = -1), "input")
  expect_ms_error(run(nb_size = 0), "input")
  expect_ms_error(run(bca = NA), "input")
  # An all-zero catalog has nothing to dilute.
  zero <- fx$catalog@counts
  zero[] <- 0
  catalog <- ms_catalog(counts = zero, channels = fx$catalog@channels,
    samples = fx$catalog@samples, provenance = fx$catalog@provenance)
  expect_ms_error(ms_calibration_sanity(catalog, fx$sigs), "input")
  # A seed too close to the i32 ceiling cannot host the derived offsets.
  expect_ms_error(run(seed = 2147483647L), "input")
})
