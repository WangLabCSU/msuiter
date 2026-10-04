# U-M4 remainder: the bootstrap CI/stability faces (CAPABILITY-MATRIX
# L-F "bootstrap：CI 误差条、分布、覆盖率曲线 | ✅ M3b/M4" -- the
# coverage curve is the M3b face; this adds the MsFit interval faces).
#
# Anchors: attribute contract reading (ci_lower/ci_upper/stability),
# honest-scope rejection of the histogram face (the draws are not
# stored), point-fit guard, and the rendered structures.

.ms_bt_fixture <- function() {
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  set.seed(42)
  sigs <- matrix(abs(rnorm(96 * 2)) + 0.01, 96, 2,
    dimnames = list(labels, c("A", "B")))
  sigs <- sweep(sigs, 2, colSums(sigs), "/")
  counts <- round(as.numeric(sigs %*% c(600, 400)))
  counts <- matrix(counts, 96, 1, dimnames = list(labels, "T1"))
  cat1 <- ms_catalog(counts, list(name = "SBS96", labels = labels),
    "T1", provenance = list(genome = "GRCh37"))
  boot <- ms_fit_bootstrap(cat1, sigs, method = "nnls", n_boot = 30,
    seed = 1)
  list(catalog = cat1, sigs = sigs, boot = boot)
}

test_that("the CI face renders point + errorbar with the contract title", {
  skip_if_not_installed("ggplot2")
  fx <- .ms_bt_fixture()
  p <- plot_boot_ci(fx$boot)
  expect_s3_class(p, "ggplot")
  geoms <- vapply(p$layers, function(l) class(l$geom)[1L],
    character(1L), USE.NAMES = FALSE)
  expect_true("GeomPoint" %in% geoms)
  expect_true("GeomErrorbar" %in% geoms)
  # Title carries the CI level and boot count from the attributes.
  expect_match(p$labels$title, "95% CI")
  expect_match(p$labels$title, "30 boots")
  # CI bounds ordered in the built data.
  built <- ggplot2::ggplot_build(p)
  d <- built$data[[2]]
  expect_true(all(d$ymin <= d$ymax))
})

test_that("the stability face renders with the 0.95 floor line", {
  skip_if_not_installed("ggplot2")
  fx <- .ms_bt_fixture()
  p <- plot_boot_stability(fx$boot)
  expect_s3_class(p, "ggplot")
  hlines <- unlist(lapply(p$layers, function(l) {
    if (inherits(l$geom, "GeomHline")) l$data$yintercept else numeric(0)
  }), use.names = FALSE)
  expect_identical(hlines, 0.95)
  built <- ggplot2::ggplot_build(p)
  expect_true(all(built$data[[1]]$y >= 0 & built$data[[1]]$y <= 1))
})

test_that("the histogram face reads the draws cube; guards are structured", {
  skip_if_not_installed("ggplot2")
  fx <- .ms_bt_fixture()
  # U-M7-pre: the draws face unlocked the real histogram.
  boot_d <- ms_fit_bootstrap(fx$catalog, fx$sigs, method = "nnls",
    n_boot = 40, seed = 1, return_draws = TRUE)
  p <- plot_boot_distribution(boot_d)
  expect_s3_class(p, "ggplot")
  # ggplot2 renders histograms as GeomBar/GeomRect (no GeomHistogram).
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomBar"), logical(1L))))
  # The draws cube reproduces the CI attributes: quantile(type = 7)
  # parity within 2 ulp (R's FMA contraction -- the compare.rs type-7
  # audit finding, same situation).
  d <- attr(boot_d@exposures, "boot_draws")
  ci_lo <- attr(boot_d@exposures, "ci_lower")
  ci_hi <- attr(boot_d@exposures, "ci_upper")
  for (a in seq_len(nrow(d))) {
    q <- unname(quantile(d[a, 1, ], probs = c(0.025, 0.975), type = 7))
    expect_lt(abs(q[1] - ci_lo[a, 1]), 1e-9)
    expect_lt(abs(q[2] - ci_hi[a, 1]), 1e-9)
  }
  # Without return_draws the attribute is absent -> structured error.
  expect_ms_error(plot_boot_distribution(fx$boot), "input")
  # A point fit (no CI attributes) is rejected.
  point <- ms_fit(fx$catalog, fx$sigs, method = "nnls")
  expect_ms_error(plot_boot_ci(point), "input")
  expect_ms_error(plot_boot_stability(point), "input")
  expect_ms_error(plot_boot_ci("junk"), "input")
  # Bad sample selectors.
  expect_ms_error(plot_boot_ci(fx$boot, sample = 9), "input")
  expect_ms_error(plot_boot_ci(fx$boot, sample = "NOPE"), "input")
})
