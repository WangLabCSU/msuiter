# U-M3b-04: ms_calibration_grid() + ms_calibration_verdict() -- the R
# assembly face of the calibration Monte Carlo grid.
#
# Everything is synthetic (the separable-truth pattern of test-fit.R). The
# Rust suite (src/rust/src/calibrate.rs) pins the calibration SEMANTICS
# (window landing at the M = 500 reduced protocol, NB monotonicity,
# compound tallies); here the R FACE is pinned: curve assembly shape and
# cell order, the verdict twin (bit-equal to the kernel-side membership),
# determinism + thread invariance, and the first-layer error protocol.

# Truth dictionary of the small grid: a delta target on channel 0 plus a
# medium partner (the Rust suite's shape, M = 8 channels, k = 2) -- a
# well-conditioned pair the bidirectional fit keeps at every tested share.
.ms_calib_fixture <- function() {
  m <- 8L
  k <- 2L
  sigs <- matrix(0, nrow = m, ncol = k)
  sigs[1, 1] <- 1
  sigs[, 2] <- c(0, 0.30, 0.25, 0.15, 0.10, 0.08, 0.07, 0.05)
  sigs
}

test_that("ms_calibration_grid assembles the tidy curve in kernel cell order", {
  sigs <- .ms_calib_fixture()
  df <- ms_calibration_grid(sigs, n_grid = c(100, 200), shares = c(0.10, 0.50),
    m = 3, n_boot = 20, seed = 7, n_threads = 1)
  expect_s3_class(df, "data.frame")
  expect_identical(nrow(df), 4L) # 2 x 2 grid
  expect_named(df, c(
    "n", "share", "cell", "mean_coverage", "se", "n_reps", "pass_window",
    "true_zero", "false_keep", "false_zero", "kept_covered", "kept_missed"
  ))
  # Cell order: n_grid-major x shares (the kernel's contract), 1-based ids.
  expect_identical(df$n, c(100, 100, 200, 200))
  expect_identical(df$share, c(0.10, 0.50, 0.10, 0.50))
  expect_identical(df$cell, 1:4)
  # Fractions and their binomial standard errors on [0, 1]; every replicate
  # tallies both truth-supported signatures (k = 2, shares > 0).
  expect_true(all(df$mean_coverage >= 0 & df$mean_coverage <= 1))
  expect_true(all(df$se >= 0 & df$se <= 1))
  expect_identical(df$n_reps, rep(3L, 4L))
  p <- df$mean_coverage
  expect_equal(df$se, sqrt(p * (1 - p) / 6), tolerance = 1e-12)
  # Confusion tallies: with shares > 0 there is no decoy and (on this
  # separable truth) no false-zero; the kept cells carry all tallies.
  expect_true(all(df$true_zero == 0))
  expect_true(all(df$false_keep == 0))
  expect_identical(df$false_zero + df$kept_covered + df$kept_missed,
    rep(6, 4L))
  # Protocol echoes ride along as attributes.
  expect_identical(attr(df, "window"), c(0.930, 0.970))
  expect_identical(attr(df, "arm"), "multinomial")
  expect_identical(attr(df, "bca"), FALSE)
  expect_identical(attr(df, "n_boot"), 20L)
  expect_identical(attr(df, "seed"), 7L)
  expect_identical(attr(df, "n_grid"), c(100, 200))
  expect_identical(attr(df, "shares"), c(0.10, 0.50))
})

test_that("the verdict twin matches the kernel membership bit-for-bit", {
  sigs <- .ms_calib_fixture()
  df <- ms_calibration_grid(sigs, n_grid = c(100, 200), shares = c(0.10, 0.50),
    m = 3, n_boot = 20, seed = 7, n_threads = 1)
  v <- ms_calibration_verdict(df)
  expect_named(v, c("all_in_window", "per_cell_in", "failing_cells", "window"))
  expect_identical(v$per_cell_in, unname(df$pass_window)) # kernel verdict
  expect_identical(v$failing_cells, as.integer(which(!df$pass_window)))
  expect_identical(v$all_in_window, all(df$pass_window))
  expect_identical(v$window, c(lo = 0.930, hi = 0.970)) # table's attribute
  # Explicit window overrides the attribute.
  v2 <- ms_calibration_verdict(df, window = c(0.0, 1.0))
  expect_true(v2$all_in_window)
  expect_identical(v2$failing_cells, integer(0))
  expect_identical(v2$window, c(lo = 0, hi = 1))
})

test_that("verdict membership is inclusive and failing cells ascend", {
  mk <- function(coverage) {
    data.frame(mean_coverage = coverage, stringsAsFactors = FALSE)
  }
  v <- ms_calibration_verdict(mk(c(0.94, 0.970, 0.929, 0.971, 0.930)))
  expect_identical(v$per_cell_in, c(TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(v$failing_cells, c(3L, 4L))
  expect_false(v$all_in_window)
  v_all <- ms_calibration_verdict(mk(c(0.930, 0.970)))
  expect_true(v_all$all_in_window)
  expect_identical(v_all$failing_cells, integer(0))
})

test_that("the grid is deterministic and thread-invariant through the R face", {
  sigs <- .ms_calib_fixture()
  one <- ms_calibration_grid(sigs, n_grid = c(100, 200),
    shares = c(0.10, 0.50), m = 3, n_boot = 20, seed = 7, n_threads = 1)
  two <- ms_calibration_grid(sigs, n_grid = c(100, 200),
    shares = c(0.10, 0.50), m = 3, n_boot = 20, seed = 7, n_threads = 2)
  expect_identical(one, two) # contract 6: threads {1, N} identical
  again <- ms_calibration_grid(sigs, n_grid = c(100, 200),
    shares = c(0.10, 0.50), m = 3, n_boot = 20, seed = 7, n_threads = 1)
  expect_identical(one, again)
  other <- ms_calibration_grid(sigs, n_grid = c(100, 200),
    shares = c(0.10, 0.50), m = 3, n_boot = 20, seed = 8, n_threads = 1)
  expect_false(identical(one, other)) # a different seed moves the grid
})

test_that("bca = TRUE selects the BCa face and echoes the arm protocol", {
  sigs <- .ms_calib_fixture()
  df <- ms_calibration_grid(sigs, n_grid = c(1000), shares = c(0.25),
    m = 2, n_boot = 20, bca = TRUE, seed = 3, n_threads = 1)
  expect_identical(nrow(df), 1L)
  expect_identical(attr(df, "bca"), TRUE)
  pois <- ms_calibration_grid(sigs, n_grid = c(1000), shares = c(0.25),
    m = 2, n_boot = 20, arm = "poisson", seed = 3, n_threads = 1)
  expect_identical(attr(pois, "arm"), "poisson")
  nb <- ms_calibration_grid(sigs, n_grid = c(1000), shares = c(0.25),
    m = 2, n_boot = 20, arm = "nb:8", seed = 3, n_threads = 1)
  expect_identical(attr(nb, "arm"), "nb")
})

test_that("grid error paths are structured msuiter_error_* conditions", {
  sigs <- .ms_calib_fixture()
  run <- function(n_grid = c(100, 200), shares = c(0.10, 0.50), m = 3,
                  n_boot = 20, seed = 7, bca = FALSE, n_samples = 1,
                  nb_size = 8, arm = "multinomial",
                  window = .MS_CALIBRATION_WINDOW, ...) {
    ms_calibration_grid(sigs, n_grid = n_grid, shares = shares, m = m,
      n_boot = n_boot, seed = seed, bca = bca, n_samples = n_samples,
      nb_size = nb_size, arm = arm, window = window, ...)
  }
  # sigs shape / domain.
  expect_ms_error(ms_calibration_grid("not-a-matrix", 100, 0.5, m = 2), "input")
  expect_ms_error(ms_calibration_grid(matrix(c(0.5, NA)), 100, 0.5, m = 2), "na")
  bad <- sigs; bad[1, 1] <- -1
  expect_ms_error(ms_calibration_grid(bad, 100, 0.5, m = 2), "input")
  expect_ms_error(ms_calibration_grid(sigs, n_grid = 0, shares = 0.5, m = 2), "input")
  # n_grid axis: whole / range / strictly increasing.
  expect_ms_error(run(n_grid = c(200, 100)), "input")
  expect_ms_error(run(n_grid = c(100.5)), "input")
  expect_ms_error(run(n_grid = c(NA)), "input")
  expect_ms_error(run(n_grid = 2^31), "input")
  expect_ms_error(run(n_grid = integer(0)), "input")
  # shares domain.
  expect_ms_error(run(shares = 1.5), "input")
  expect_ms_error(run(shares = -0.1), "input")
  expect_ms_error(run(shares = NA), "input")
  expect_ms_error(run(shares = numeric(0)), "input")
  # Monte Carlo scalars.
  expect_ms_error(run(m = 0), "input")
  expect_ms_error(run(m = 2.5), "input")
  expect_ms_error(run(n_boot = 0), "input")
  expect_ms_error(run(seed = -1), "input")
  expect_ms_error(run(n_samples = 0), "input")
  expect_ms_error(run(nb_size = 0), "input")
  expect_ms_error(run(bca = NA), "input")
  # Arm selector.
  expect_ms_error(run(arm = "wald"), "input")
  expect_ms_error(run(arm = "nb"), "input")
  expect_ms_error(run(arm = "nb:-1"), "input")
  expect_ms_error(run(arm = "nb:x"), "input")
  # Window domain (grid face and verdict face).
  expect_ms_error(run(window = c(0.97, 0.93)), "input")
  expect_ms_error(run(window = c(-0.1, 0.97)), "input")
  expect_ms_error(run(window = c(0.93, NA)), "input")
  expect_ms_error(run(window = 0.5), "input")
  # Verdict face: table shape.
  expect_ms_error(ms_calibration_verdict("not-a-df"), "input")
  expect_ms_error(ms_calibration_verdict(data.frame(x = 1)), "input")
  expect_ms_error(
    ms_calibration_verdict(data.frame(mean_coverage = NA_real_)), "input")
  expect_ms_error(
    ms_calibration_verdict(data.frame(mean_coverage = 0.95), window = c(2, 1)),
    "input")
})

test_that("the FFI wrapper validates the boundary before crossing", {
  sigs <- .ms_calib_fixture()
  # NA matrix at the boundary (contract 3, first layer).
  na_sigs <- sigs
  na_sigs[1, 1] <- NA
  expect_ms_error(.ms_calibration_grid_rust(
    na_sigs, 100, 0.5, 1, 2, 10, 8, FALSE, "multinomial", 1, c(0.93, 0.97)),
    "na")
  # The happy path returns the kernel list the assembly consumes.
  res <- .ms_calibration_grid_rust(
    sigs, 100, 0.5, 1, 2, 10, 8, FALSE, "multinomial", 1, c(0.93, 0.97))
  expect_type(res, "list")
  expect_named(res, c(
    "mean_coverage", "se", "n_reps", "n_grid", "shares", "arm", "bca",
    "n_boot", "nb_size", "seed", "true_zero", "false_keep", "false_zero",
    "kept_covered", "kept_missed", "window_lo", "window_hi", "all_in_window",
    "per_cell_in", "failing_cells"
  ))
})
