# U-M4 remainder: ms_exposure_test() -- the differential-mining face
# (CAPABILITY-MATRIX L-F "exposure 嵌入 + 差异挖掘 🔶 M4" 的另一半).
#
# Anchors: wilcox.test parity (the R twin IS the implementation -- the
# assertions pin the BH family semantics, the NA all-tied face, and the
# separation behavior on a designed fixture), and structured errors.

.ms_et_expo <- function(n1 = 6, n2 = 6) {
  set.seed(3)
  expo <- matrix(c(rgamma(12, 5, 1), rgamma(12, 5, 5)), nrow = 2,
    ncol = n1 + n2)
  rownames(expo) <- c("S1", "S2")
  list(expo = expo, groups = c(rep("A", n1), rep("B", n2)))
}

test_that("designed separation is detected with BH family semantics", {
  fx <- .ms_et_expo()
  r <- ms_exposure_test(fx$expo, fx$groups)
  expect_named(r, c("signature", "median_group1", "median_group2",
    "statistic", "p_raw", "p_bh", "pass_bh"))
  expect_identical(r$signature, c("S1", "S2"))
  # Separated draws: both raw p at the same rank-sum value, significant.
  expect_lt(r$p_raw[1], 0.01)
  expect_identical(r$p_raw[1], r$p_raw[2])
  expect_true(all(r$pass_bh))
  # Medians land on the right sides (group A = rgamma rate 1 = high,
  # group B = rate 5 = low in the fixture).
  expect_gt(r$median_group1[1], r$median_group2[1])
  # BH identity: q == p.adjust over the family.
  expect_identical(r$p_bh, stats::p.adjust(r$p_raw, method = "BH"))
})

test_that("the all-tied face is NA, not a fake p", {
  expo0 <- matrix(0, 2, 12, dimnames = list(c("S1", "S2"), NULL))
  fx <- .ms_et_expo()
  r <- ms_exposure_test(expo0, fx$groups)
  expect_true(all(is.na(r$p_raw)))
  expect_true(all(is.na(r$p_bh)))
  expect_false(any(r$pass_bh))
})

test_that("error paths are structured", {
  fx <- .ms_et_expo()
  expect_ms_error(ms_exposure_test("junk", fx$groups), "input")
  expect_ms_error(ms_exposure_test(fx$expo, groups = 1:12), "input")
  expect_ms_error(ms_exposure_test(fx$expo, fx$groups[-1]), "input")
  # Three groups rejected (the pairwise split is the caller's decision).
  g3 <- c(rep("A", 4), rep("B", 4), rep("C", 4))
  expect_ms_error(ms_exposure_test(fx$expo[, ], g3), "input")
  expect_ms_error(ms_exposure_test(fx$expo, fx$groups, alpha = 1.5),
    "input")
})
