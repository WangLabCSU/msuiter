# U-M4 remainder: the K-selection evidence faces (CAPABILITY-MATRIX L-F
# "K 选择证据 | ✅ M2/M4").
#
# Anchors: layer structure, the argmin/selected marks in the title,
# veto coloring, the schema guard, and a REAL ms_select_k round-trip
# (small grid) rendered through the face.

.ms_kev <- function() {
  ev <- data.frame(
    k = 2:6,
    cv_test_deviance = c(500, 300, 280, 290, 310),
    cv_test_mse = sqrt(c(500, 300, 280, 290, 310) / (48 * 9)),
    cv_train_mse = NA_real_,
    n_seeds_converged = NA_integer_,
    avg_stability = c(0.95, 0.88, 0.85, 0.7, 0.6),
    min_cluster_stability = c(0.9, 0.5, 0.4, 0.1, 0.05),
    wilcoxon_p_vs_prev = c(NA, 0.2, 0.4, 0.6, 0.8),
    wilcoxon_l2_median_delta = c(50, 20, 10, 8, 6),
    passes_veto = c(TRUE, TRUE, TRUE, FALSE, FALSE),
    is_argmin = c(FALSE, FALSE, TRUE, FALSE, FALSE),
    selected = c(FALSE, FALSE, TRUE, FALSE, FALSE),
    veto_reason = c("", "", "", "avg_stability 0.7 < 0.8",
                    "avg_stability 0.6 < 0.8"),
    stringsAsFactors = FALSE
  )
  # List columns attach AFTER construction: data.frame() would recycle
  # the atomic columns against the list elements' lengths.
  ev$fold_test_deviance <- rep(list(rep(NA_real_, 10L)), 5L)
  ev$per_signature_stability <- rep(list(c(0.9, 0.85)), 5L)
  ev
}

test_that("both K-evidence faces render with the documented layers", {
  skip_if_not_installed("ggplot2")
  ev <- .ms_kev()
  p1 <- plot_k_cv_curve(ev)
  expect_s3_class(p1, "ggplot")
  expect_true(any(vapply(p1$layers, function(l)
    inherits(l$geom, "GeomLine"), logical(1L))))
  expect_true(any(vapply(p1$layers, function(l)
    inherits(l$geom, "GeomPoint"), logical(1L))))
  # The selected rank carries the ring mark (a second GeomPoint layer).
  expect_true(sum(vapply(p1$layers, function(l)
    inherits(l$geom, "GeomPoint"), logical(1L))) >= 2L)
  expect_match(p1$labels$title, "argmin = selected k = 4")

  p2 <- plot_k_stability(ev)
  expect_s3_class(p2, "ggplot")
  expect_true(any(vapply(p2$layers, function(l)
    inherits(l$geom, "GeomHline"), logical(1L))))
  # The two veto reference lines.
  hlines <- unlist(lapply(p2$layers, function(l) {
    if (inherits(l$geom, "GeomHline")) l$data$yintercept else numeric(0)
  }), use.names = FALSE)
  expect_setequal(hlines, c(0.8, 0.2))
})

test_that("the title distinguishes argmin from selected", {
  skip_if_not_installed("ggplot2")
  ev <- .ms_kev()
  ev$selected[ev$k == 4] <- FALSE
  ev$selected[ev$k == 3] <- TRUE # selected != argmin
  ev$is_argmin[ev$k == 4] <- TRUE
  p <- plot_k_cv_curve(ev)
  expect_match(p$labels$title, "argmin 4, selected 3")
  # No selection at all.
  ev2 <- .ms_kev()
  ev2$selected <- FALSE
  p2 <- plot_k_cv_curve(ev2)
  expect_match(p2$labels$title, "K-selection evidence")
})

test_that("the schema guard is structured", {
  skip_if_not_installed("ggplot2")
  ev <- .ms_kev()
  expect_ms_error(plot_k_cv_curve("junk"), "input")
  expect_ms_error(plot_k_stability(ev[, 1:5]), "input")
  expect_ms_error(plot_k_cv_curve(ev[, 1:5]), "input")
})

test_that("a REAL ms_select_k run renders through both faces", {
  skip_if_not_installed("ggplot2")
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  set.seed(77)
  sigs <- matrix(abs(rnorm(96 * 3)) + 0.01, 96, 3,
    dimnames = list(labels, c("A", "B", "C")))
  sigs <- sweep(sigs, 2, colSums(sigs), "/")
  counts <- sigs %*% matrix(c(300, 200, 100, 250, 250, 100, 200, 150,
    350), nrow = 3)
  colnames(counts) <- paste0("T", 1:3)
  cat1 <- ms_catalog(counts, list(name = "SBS96", labels = labels),
    colnames(counts), provenance = list(genome = "GRCh37"))
  out <- ms_select_k(cat1, 2:3, replicates = 4L, max_iter = 50L,
    seed = 3, k_folds = 3L, n_seeds = 3L)
  p1 <- plot_k_cv_curve(out$k_evidence)
  p2 <- plot_k_stability(out$k_evidence)
  expect_s3_class(p1, "ggplot")
  expect_s3_class(p2, "ggplot")
})
