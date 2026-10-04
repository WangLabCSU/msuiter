# U-M4-03 remainder: ms_embed() + plot_embedding() -- the exposure
# embedding first version (CAPABILITY-MATRIX L-F 🔶 M4).
#
# Anchors: kmeans bitwise determinism, the seeded-UMAP determinism
# within one uwot version (documented honesty: NOT across versions),
# share-transform geometry, structured error paths, the plot face.

.ms_emb_expo <- function() {
  set.seed(5)
  # Three sample groups with distinct dominant signatures.
  n <- 4
  expo <- matrix(0, nrow = 3, ncol = 3 * n,
    dimnames = list(c("S1", "S2", "S3"), paste0("T", seq_len(3 * n))))
  expo["S1", 1:n] <- runif(n, 80, 120)
  expo["S1", (n + 1):(2 * n)] <- runif(n, 0, 5)
  expo["S1", (2 * n + 1):(3 * n)] <- runif(n, 0, 5)
  expo["S2", 1:n] <- runif(n, 0, 5)
  expo["S2", (n + 1):(2 * n)] <- runif(n, 80, 120)
  expo["S2", (2 * n + 1):(3 * n)] <- runif(n, 0, 5)
  expo["S3", 1:n] <- runif(n, 0, 5)
  expo["S3", (n + 1):(2 * n)] <- runif(n, 0, 5)
  expo["S3", (2 * n + 1):(3 * n)] <- runif(n, 80, 120)
  expo
}

test_that("kmeans embedding is deterministic and recovers the groups", {
  expo <- .ms_emb_expo()
  a <- ms_embed(expo, method = "kmeans", clusters = 3L)
  b <- ms_embed(expo, method = "kmeans", clusters = 3L)
  expect_identical(a, b)
  # The three planted groups land in three distinct clusters: every
  # 4-sample block has exactly one cluster label.
  blocks <- split(a$cluster, rep(1:3, each = 4L))
  each_one <- vapply(blocks, function(x) length(unique(x)) == 1L, logical(1L))
  expect_true(all(each_one))
  expect_length(unique(a$cluster), 3L)
})

test_that("umap embedding is seeded-reproducible and finite", {
  skip_if_not_installed("uwot")
  expo <- .ms_emb_expo()
  a <- ms_embed(expo, method = "umap", seed = 11)
  b <- ms_embed(expo, method = "umap", seed = 11)
  # Same uwot version + same seed: bitwise (honesty note in the docs:
  # NOT claimed across uwot versions).
  expect_identical(a$embed_1, b$embed_1)
  expect_identical(a$embed_2, b$embed_2)
  expect_true(all(is.finite(a$embed_1)) && all(is.finite(a$embed_2)))
  expect_identical(a$sample, colnames(expo))
})

test_that("the share transform bounds the geometry", {
  expo <- .ms_emb_expo()
  a <- ms_embed(expo, method = "kmeans", transform = "share",
    clusters = 3L)
  # embed_1/embed_2 are share columns: in [0, 1].
  expect_true(all(a$embed_1 >= 0 & a$embed_1 <= 1))
  expect_true(all(a$embed_2 >= 0 & a$embed_2 <= 1))
})

test_that("error paths are structured", {
  expo <- .ms_emb_expo()
  expect_ms_error(ms_embed("junk"), "input")
  expect_ms_error(ms_embed(expo, seed = -1), "input")
  expect_ms_error(ms_embed(expo, method = "kmeans", clusters = 99),
    "input")
})

test_that("plot_embedding renders and colours by cluster", {
  skip_if_not_installed("ggplot2")
  expo <- .ms_emb_expo()
  e <- ms_embed(expo, method = "kmeans", clusters = 3L)
  p <- plot_embedding(e)
  expect_s3_class(p, "ggplot")
  expect_true(any(vapply(p$layers, function(l) inherits(l$geom, "GeomPoint"),
    logical(1L))))
  # kmeans table has clusters -> colour mapping present in the labels.
  expect_false(is.null(p$labels$colour))
  # bad input rejected
  expect_ms_error(plot_embedding(data.frame(x = 1:3)), "input")
})
