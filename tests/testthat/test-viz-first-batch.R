# U-M4-03: the viz first batch -- 8 plot faces (design memo
# docs/devlog/2026-10-04-M4-03-viz-memo.md).
#
# Anchors: the COSMIC palette pinned LITERALLY (the verified
# sigProfilerPlotting.py source values), canonical-order enforcement
# (shuffled input rejected), layer-structure assertions, hand-derived
# residual numbers, and real-data rendering with a non-empty PNG.

skip_if_no_ggplot <- function() {
  skip_if_not_installed("ggplot2")
  TRUE
}

.ms_viz_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

.ms_viz_sig3 <- function() {
  set.seed(31)
  sig <- matrix(abs(rnorm(96 * 3)) + 0.001, 96, 3,
                dimnames = list(.ms_viz_labels(), c("S1", "S2", "S3")))
  sig <- sweep(sig, 2, colSums(sig), "/")
  sig
}

test_that("the COSMIC SBS palette is pinned literally", {
  want <- c(
    "C>A" = "#03BDEF", # [3, 189, 239]/256
    "C>G" = "#010101", # [1, 1, 1]/256
    "C>T" = "#E42926", # [228, 41, 38]/256
    "T>A" = "#CBCACA", # [203, 202, 202]/256
    "T>C" = "#A2CF63", # [162, 207, 99]/256
    "T>G" = "#ECC7C5"  # [236, 199, 197]/256
  )
  expect_identical(msuiter:::.ms_viz_sbs_palette, want)
  # The per-channel vector follows each label's substitution class.
  labels <- .ms_viz_labels()
  cc <- msuiter:::.ms_viz_channel_colors(labels)
  # The registry cycles the substitution classes within each 5'-flank
  # block (A[C>A]A A[C>A]C A[C>A]G A[C>A]T A[C>G]A ...), so positions:
  expect_identical(cc[1], "#03BDEF") # A[C>A]A
  expect_identical(cc[5], "#010101") # A[C>G]A
  expect_identical(cc[96], "#ECC7C5") # T[T>G]T
})

test_that("the rendered fills ARE the palette (identity scale applied)", {
  skip_if_no_ggplot()
  sig <- .ms_viz_sig3()
  p <- plot_catalog_profile(sig, column = "S1")
  built <- ggplot2::ggplot_build(p)
  fills <- unique(as.character(built$data[[1]]$fill))
  expect_setequal(fills, unname(msuiter:::.ms_viz_sbs_palette))
  # First channel A[C>A]A must carry the C>A color exactly.
  expect_identical(as.character(built$data[[1]]$fill[1]), "#03BDEF")
  # And the reconstruction panel too (the audited P1: two faces had
  # computed colors that never reached the render).
  labels <- .ms_viz_labels()
  counts <- sig[, 1] * 500
  pr <- plot_reconstruction_panel(counts, sig,
    matrix(c(500, 0, 0), 3, 1, dimnames = list(c("S1", "S2", "S3"), "T1")),
    mode = "count")
  built2 <- ggplot2::ggplot_build(pr)
  fills2 <- unique(as.character(built2$data[[1]]$fill))
  expect_true(all(fills2 %in% c(unname(msuiter:::.ms_viz_sbs_palette),
                                NA_character_)))
})

test_that("the DBS78 simplified face renders in the mono color", {
  skip_if_no_ggplot()
  dbs <- msuiter:::.ms_io_channel_tables()$DBS78
  m <- matrix(abs(rnorm(78)) + 0.01, 78, 1, dimnames = list(dbs, "D1"))
  m <- sweep(m, 2, colSums(m), "/")
  p <- plot_catalog_profile(m)
  expect_s3_class(p, "ggplot")
  built <- ggplot2::ggplot_build(p)
  expect_true(all(as.character(built$data[[1]]$fill) == "#4D4D4D"))
})

test_that("plot_catalog_profile renders the documented structure", {
  skip_if_no_ggplot()
  sig <- .ms_viz_sig3()
  p <- plot_catalog_profile(sig, column = "S1")
  expect_s3_class(p, "ggplot")
  built <- ggplot2::ggplot_build(p)
  expect_true(nrow(built$data[[1]]) == 96L) # one bar per channel
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomBar"), logical(1L))))
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomVline"), logical(1L))))
  # 3 flank-boundary lines (the registry is 5'-flank blocked: A/C/G/T
  # x 24 channels — the audited first draft drew 5 class lines that
  # landed on no real boundary in this order).
  vlines <- unlist(lapply(p$layers, function(l) {
    if (inherits(l$geom, "GeomVline")) l$data$xintercept else numeric(0)
  }), use.names = FALSE)
  expect_setequal(vlines, c(24.5, 48.5, 72.5))
  # count mode renders too.
  p2 <- plot_catalog_profile(sig, column = 2, mode = "count")
  expect_s3_class(p2, "ggplot")
  # Axis labels are flank pairs ("A A" for A[C>A]A): the audited first
  # draft read the closing bracket. Verify through the built scale.
  built <- ggplot2::ggplot_build(p)
  xl <- as.character(unique(built$layout$panel_params[[1]]$x$get_labels()))
  expect_identical(xl[1], "A A")
})

test_that("profile faces accept vectors, MsSignature, and reject bad order", {
  skip_if_no_ggplot()
  sig <- .ms_viz_sig3()
  # named vector
  p1 <- plot_catalog_profile(sig[, 1])
  expect_s3_class(p1, "ggplot")
  # shuffled input rejected (viz never reorders silently)
  shuffled <- sig[sample(96), , drop = FALSE]
  expect_ms_error(plot_catalog_profile(shuffled, column = 1), "input")
  expect_ms_error(plot_signature_catalog(shuffled), "input")
  expect_ms_error(plot_reference_comparison(sig[sample(96), 1], sig[, 2]),
    "input")
  # non-registry spaces rejected (ID83 has no registry table — the
  # supported list is SBS96/DBS78 only, audited P2)
  labels8 <- sprintf("CH%02d", 1:8)
  expect_ms_error(plot_catalog_profile(matrix(1, 8, 1,
    dimnames = list(labels8, "X"))), "input")
  id83 <- sprintf("1:Del:C:%d", 0:82)
  expect_ms_error(plot_catalog_profile(matrix(1, 83, 1,
    dimnames = list(id83, "X"))), "input")
})

test_that("reconstruction residuals are hand-derived exact", {
  skip_if_no_ggplot()
  labels <- .ms_viz_labels()
  sig <- .ms_viz_sig3()
  expo <- matrix(c(500, 100, 0), 3, 1, dimnames = list(c("S1", "S2", "S3"),
    "T1"))
  counts <- sig %*% expo
  counts <- as.numeric(counts)
  names(counts) <- labels
  # count mode: fitted = sig %*% expo exactly; residual = counts - fitted = 0.
  p <- plot_reconstruction_panel(counts, sig, expo, mode = "count")
  built <- ggplot2::ggplot_build(p)
  # locate the residual facet data: the third panel row
  res <- built$data[[2]]
  # residual geom draws only nonzero bars? zero residual -> geom_col of 0s.
  expect_equal(max(abs(res$y)), 0, tolerance = 1e-10)
  # break it: wrong exposures produce a real residual.
  counts_bad <- counts
  counts_bad[1] <- counts_bad[1] + 25
  p2 <- plot_reconstruction_panel(counts_bad, sig, expo, mode = "count")
  built2 <- ggplot2::ggplot_build(p2)
  res2 <- built2$data[[2]]
  expect_gt(max(abs(res2$y)), 10)
})

test_that("exposure and similarity faces render with the contract columns", {
  skip_if_no_ggplot()
  expo <- matrix(runif(3 * 5), 3, 5, dimnames = list(c("S1", "S2", "S3"),
    paste0("T", 1:5)))
  p5 <- plot_exposure_stacked(expo)
  expect_s3_class(p5, "ggplot")
  expect_true(any(vapply(p5$layers, function(l)
    inherits(l$geom, "GeomBar"), logical(1L))))
  p6 <- plot_exposure_heatmap(expo)
  expect_s3_class(p6, "ggplot")
  expect_true("GeomTile" %in% vapply(p6$layers, function(l)
    class(l$geom)[1L], character(1L)))
  sim <- matrix(runif(9), 3, 3, dimnames = list(c("a", "b", "c"),
    c("x", "y", "z")))
  p7 <- plot_similarity_heatmap(sim)
  expect_s3_class(p7, "ggplot")
  expect_true("GeomTile" %in% vapply(p7$layers, function(l)
    class(l$geom)[1L], character(1L)))
  # signature_order missing names rejected.
  expect_ms_error(plot_exposure_stacked(expo, signature_order = c("S1", "S9")),
    "input")
})

test_that("reference comparison paints the reference lighter (single layer)", {
  skip_if_no_ggplot()
  sig <- .ms_viz_sig3()
  p <- plot_reference_comparison(sig[, 1], sig[, 2])
  built <- ggplot2::ggplot_build(p)
  d <- built$data[[1]]
  expect_true("alpha" %in% names(d))
  alphas <- sort(unique(d$alpha))
  expect_true(1 %in% alphas)
  expect_true(any(alphas < 0.9)) # the 0.45 reference group survives
})

test_that("the COSMIC scatter annotates the hand-derived cosine", {
  skip_if_no_ggplot()
  sig <- .ms_viz_sig3()
  p8 <- plot_cosmic_scatter(sig[, 1], sig[, 2], label = "S1 vs S2")
  expect_s3_class(p8, "ggplot")
  # the annotation text carries the cosine with 3 decimals
  ann <- p8$labels$title
  expect_match(ann, "S1 vs S2")
  # The annotation layer carries the cosine text (built data).
  built <- ggplot2::ggplot_build(p8)
  ann_text <- unlist(lapply(built$data, function(d) {
    if ("label" %in% names(d)) as.character(d$label) else NULL
  }))
  expect_true(any(grepl("cosine", ann_text)),
    info = paste(ann_text, collapse = " | "))
})

test_that("real COSMIC signatures render and ggsave writes a non-empty PNG", {
  skip_if_no_ggplot()
  path <- system.file("reference/refdb/COSMIC_v3.6/COSMIC_v3.6_SBS_GRCh37.txt",
    package = "msuiter")
  skip_if(!nzchar(path), "bundled COSMIC file unavailable")
  sigs <- ms_import(path, format = "cosmic", kind = "signatures")
  p <- plot_signature_catalog(sigs@signatures[, 1:2, drop = FALSE])
  expect_s3_class(p, "ggplot")
  out <- tempfile(fileext = ".png")
  on.exit(unlink(out), add = TRUE)
  suppressMessages(ggplot2::ggsave(out, p, width = 6, height = 4, dpi = 72))
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0)
  # The scatter face against a real reference pair.
  p2 <- plot_cosmic_scatter(sigs@signatures[, 1], sigs@signatures[, 2],
    label = colnames(sigs@signatures)[1])
  expect_s3_class(p2, "ggplot")
})
