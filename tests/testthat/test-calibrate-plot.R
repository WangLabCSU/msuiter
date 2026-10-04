# U-M3b-05: plot_calibration_curve() -- the calibration-curve
# visualization face.
#
# The structure assertions run on a hand-built ms_calibration_grid-shaped
# table (the plot face never re-judges, so a synthetic table is a full
# contract); one integration test renders a REAL tiny grid run. ggsave
# must produce a non-empty PNG (the deliverable's output check).

.ms_plot_df <- function(pass_window = c(TRUE, TRUE), se = TRUE) {
  df <- data.frame(
    n = rep(c(100, 1000), times = 2),
    share = rep(c(0.05, 0.25), each = 2),
    cell = 1:4,
    mean_coverage = c(0.85, 0.94, 0.96, 0.95),
    se = c(0.02, 0.02, 0.02, 0.02),
    pass_window = pass_window,
    stringsAsFactors = FALSE
  )
  attr(df, "window") <- c(0.930, 0.970)
  attr(df, "arm") <- "multinomial"
  attr(df, "bca") <- FALSE
  attr(df, "n_boot") <- 1000L
  attr(df, "seed") <- 7L
  df
}

test_that("plot_calibration_curve renders the documented layer structure", {
  skip_if_not_installed("ggplot2")
  p <- plot_calibration_curve(.ms_plot_df())
  expect_s3_class(p, "ggplot")
  # Layers: the shaded window band (annotate rect) + error bars + the
  # line/point pair over the 0.95 reference line.
  geom_classes <- vapply(p$layers, function(l) class(l$geom)[1L],
    character(1L), USE.NAMES = FALSE)
  expect_true("GeomRect" %in% geom_classes) # the acceptance window band
  expect_true("GeomErrorbar" %in% geom_classes)
  expect_true("GeomLine" %in% geom_classes)
  expect_true("GeomPoint" %in% geom_classes)
  # Axes, log x, facet-per-share, y limits clamped to [0, 1].
  expect_identical(p$labels$x, "Catalog size N (mutations, log scale)")
  expect_identical(p$labels$y, "Empirical coverage of the true exposure")
  expect_s3_class(p$facet, "FacetWrap")
  expect_s3_class(p$coordinates, "CoordCartesian")
  built <- ggplot2::ggplot_build(p)
  expect_identical(nrow(built$layout$layout), 2L) # one panel per share
})

test_that("failing cells add the red cross marker; se = FALSE drops the bars", {
  skip_if_not_installed("ggplot2")
  ok <- plot_calibration_curve(.ms_plot_df(c(TRUE, TRUE, TRUE, TRUE)))
  failing <- plot_calibration_curve(.ms_plot_df(c(FALSE, TRUE, TRUE, TRUE)))
  expect_lt(length(ok$layers), length(failing$layers))
  no_se <- plot_calibration_curve(.ms_plot_df(), se = FALSE)
  geom_classes <- vapply(no_se$layers, function(l) class(l$geom)[1L],
    character(1L), USE.NAMES = FALSE)
  expect_false("GeomErrorbar" %in% geom_classes)
  expect_true("GeomRect" %in% geom_classes) # the band stays
  # Default window: the recorded attribute; an explicit window overrides.
  p9799 <- plot_calibration_curve(.ms_plot_df(), window = c(0.97, 0.99))
  expect_match(p9799$labels$subtitle, "0\\.970, 0\\.990", fixed = FALSE)
})

test_that("the plot renders a real tiny grid and ggsave writes a non-empty PNG", {
  skip_if_not_installed("ggplot2")
  sigs <- matrix(0, nrow = 8, ncol = 2)
  sigs[1, 1] <- 1
  sigs[, 2] <- c(0, 0.30, 0.25, 0.15, 0.10, 0.08, 0.07, 0.05)
  df <- ms_calibration_grid(sigs, n_grid = c(1000), shares = c(0.25, 0.5),
    m = 2, n_boot = 10, seed = 5, n_threads = 1)
  p <- plot_calibration_curve(df)
  expect_s3_class(p, "ggplot")
  out <- tempfile(fileext = ".png")
  on.exit(unlink(out), add = TRUE)
  # A single-N grid leaves one point per geom_line group (an informational
  # ggplot message, not a defect).
  suppressMessages(ggplot2::ggsave(out, p, width = 6, height = 4, dpi = 72))
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0)
})

test_that("plot error paths are structured msuiter_error_* conditions", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(n = 100, share = 0.5, mean_coverage = 0.95,
    pass_window = TRUE, stringsAsFactors = FALSE)
  expect_ms_error(plot_calibration_curve("not-a-df"), "input")
  expect_ms_error(plot_calibration_curve(df, se = NA), "input")
  expect_ms_error(plot_calibration_curve(df, window = c(0.97, 0.93)), "input")
  expect_ms_error(plot_calibration_curve(df, window = c(NA, 1)), "input")
  # Missing required columns: the se column while se = TRUE.
  expect_ms_error(plot_calibration_curve(df), "input")
  bad_n <- transform(df, n = -1)
  expect_ms_error(plot_calibration_curve(bad_n, se = FALSE), "input")
  bad_cov <- transform(df, mean_coverage = NA_real_)
  expect_ms_error(plot_calibration_curve(bad_cov, se = FALSE), "input")
})
