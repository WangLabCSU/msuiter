# U-M4 remainder: ms_cluster_signatures() -- the signature clustering
# face (CAPABILITY-MATRIX L-F "签名聚类 🔶" first version).
#
# Anchors: the designed 4-signature fixture (two near-duplicates + two
# orthogonal), threshold monotonicity, medoid semantics, determinism
# under threshold, the audit-driven loop guard, and structured errors.

.ms_cl_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

.ms_cl_fixture <- function() {
  # Pure spike vectors: orthogonal supports give EXACT zeros (a 0.01
  # background made every pair weakly correlated and broke the
  # threshold-monotonicity design).
  mk <- function(idx) {
    v <- numeric(96)
    v[idx] <- 1
    v / sqrt(sum(v^2))
  }
  s1 <- mk(1:32)
  s2 <- mk(33:64)
  s3 <- mk(65:96)
  s1b <- s1 + 0.05 * s2
  s1b <- s1b / sqrt(sum(s1b^2))
  sigs <- cbind(s1, s2, s3, s1b)
  rownames(sigs) <- .ms_cl_labels()
  colnames(sigs) <- c("S1", "S2", "S3", "S1b")
  sigs
}

test_that("designed clusters form and the medoid is the central member", {
  sigs <- .ms_cl_fixture()
  r <- ms_cluster_signatures(sigs, threshold = 0.90)
  expect_named(r, c("signature", "cluster", "is_medoid", "cluster_size"))
  # S1 + S1b merge; the singletons stay separate.
  expect_identical(r$cluster[r$signature == "S1"],
                   r$cluster[r$signature == "S1b"])
  expect_false(r$cluster[r$signature == "S2"] == r$cluster[r$signature == "S1"])
  expect_false(r$cluster[r$signature == "S3"] == r$cluster[r$signature == "S1"])
  # Sizes: C1 = 2 (descending-size labels), C2 = C3 = 1.
  expect_identical(r$cluster_size, c(2L, 1L, 1L, 2L))
  # Medoids: one per cluster; the near-duplicate cluster's medoid is one
  # of its two members.
  expect_identical(sum(r$is_medoid), 3L)
  expect_true(r$is_medoid[r$signature == "S2"])
  expect_true(r$is_medoid[r$signature == "S3"])
  expect_identical(sum(r$is_medoid & r$cluster == "C1"), 1L)
  # The cosine matrix rides as an attribute.
  cm <- attr(r, "cosines")
  expect_identical(dim(cm), c(4L, 4L))
  expect_equal(unname(diag(cm)), rep(1, 4)) # float-parity (dput rounds)
})

test_that("threshold monotonicity: higher threshold splits clusters", {
  sigs <- .ms_cl_fixture()
  r90 <- ms_cluster_signatures(sigs, threshold = 0.90)
  r999 <- ms_cluster_signatures(sigs, threshold = 0.999)
  expect_gt(length(unique(r999$cluster)), length(unique(r90$cluster)))
  # A very low threshold cannot merge EXACTLY orthogonal signatures
  # (their cosines are 0): the floor is 3 clusters on this fixture.
  r05 <- ms_cluster_signatures(sigs, threshold = 0.05)
  expect_identical(length(unique(r05$cluster)), 3L)
})

test_that("the clustering is deterministic and permutation-stable in labels", {
  sigs <- .ms_cl_fixture()
  a <- ms_cluster_signatures(sigs, threshold = 0.90)
  b <- ms_cluster_signatures(sigs, threshold = 0.90)
  expect_identical(a, b)
  # Permuting the input columns preserves the PARTITION (S1 with S1b,
  # S2 and S3 singletons) and the medoid status; the label NAMES may
  # renumber with the descending-size order of the permuted input.
  perm <- c(3L, 1L, 4L, 2L)
  rp <- ms_cluster_signatures(sigs[, perm], threshold = 0.90)
  cl <- setNames(rp$cluster, rp$signature)
  expect_identical(cl[["S1"]], cl[["S1b"]])
  expect_false(cl[["S2"]] == cl[["S1"]])
  expect_false(cl[["S3"]] == cl[["S1"]])
  expect_identical(rp$is_medoid[rp$signature == "S1b"],
                   a$is_medoid[a$signature == "S1b"])
})

test_that("error paths are structured", {
  sigs <- .ms_cl_fixture()
  expect_ms_error(ms_cluster_signatures("junk"), "input")
  # No colnames -> structured (the identities are the colnames).
  anon <- sigs
  colnames(anon) <- NULL
  expect_ms_error(ms_cluster_signatures(anon), "input")
  dup <- sigs[, c(1, 1, 2, 3)]
  colnames(dup) <- c("S1", "S1", "S2", "S3")
  expect_ms_error(ms_cluster_signatures(dup), "input")
  expect_ms_error(ms_cluster_signatures(sigs, threshold = 0), "input")
  expect_ms_error(ms_cluster_signatures(sigs, threshold = 1.5), "input")
  expect_ms_error(ms_cluster_signatures(sigs[, 1, drop = FALSE]), "input")
  nan_sig <- sigs
  nan_sig[1, 1] <- NA
  expect_ms_error(ms_cluster_signatures(nan_sig), "input")
})
