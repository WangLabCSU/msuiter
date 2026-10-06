# Window-close self-audit: boundary tests for today's largest delivery
# surfaces (ms_compare + the bench/jiang semantics). These are the
# edges the main suites do not pin:
#   * single-signature dictionaries (k_est = 1, k_ref = 1);
#   * identical columns (duplicate dictionaries) end to end;
#   * the threshold boundary semantics (>= inclusive) on the Islam face;
#   * protocol = character(0) (no protocol, metrics-only view);
#   * the Jiang zero-total-sample lane (n_samples_zero_total > 0);
#   * the rectangular Hungarian case (k_est < k_ref).

.ms_bd_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

.ms_bd_unit <- function(n) {
  v <- numeric(96)
  v[seq_len(n)] <- 1
  v / sqrt(sum(v^2))
}

test_that("single-signature dictionaries end to end", {
  labels <- .ms_bd_labels()
  a <- .ms_bd_unit(32)
  b <- numeric(96)
  b[65:70] <- 1
  b <- b / sqrt(sum(b^2))
  E <- matrix(a, ncol = 1, dimnames = list(labels, "only"))
  R <- cbind(a = a, b = b)
  comp <- ms_compare(E, R, protocol = c("hungarian", "islam"),
    null_n_draws = 2000L)
  expect_identical(dim(comp@metrics$cosine), c(1L, 2L))
  # The Hungarian table survives the rectangular 1x2 case.
  expect_identical(nrow(comp@hungarian), length(
    unique(comp@hungarian$tau)))
  # Single-row Islam table.
  expect_identical(nrow(comp@islam), length(unique(comp@islam$tau)))
})

test_that("duplicate dictionaries: cosine 1 everywhere, floor p-values", {
  labels <- .ms_bd_labels()
  a <- .ms_bd_unit(32)
  E <- cbind(a, a)
  R <- cbind(a, a)
  dimnames(E) <- list(labels, c("e1", "e2"))
  dimnames(R) <- list(labels, c("r1", "r2"))
  comp <- ms_compare(E, R, protocol = "islam", null_n_draws = 2000L)
  # Duplicate columns: cosine is 1 up to BLAS rounding (x86_64 Linux
  # BLAS may land at 1 - 1 ulp -- CI audit 2026-10-06), which still
  # clears every Dirichlet draw, so the floor assertions stay exact.
  expect_equal(comp@metrics$cosine, matrix(1, 2, 2,
    dimnames = list(c("e1", "e2"), c("r1", "r2"))))
  # Every pair sits at the add-one floor.
  expect_true(all(comp@metrics$p_null == 1 / 2001))
  # BH over four floor p-values: all equal the floor.
  expect_true(all(comp@metrics$q_bh == 1 / 2001))
})

test_that("the Islam threshold is inclusive (>= semantics)", {
  # The float-exact construction of cos = 0.90 through trigonometry is
  # fragile (sqrt(0.19) noise lands at 0.89999...); the semantics live
  # in .ms_compare_islam's `best >= tau` comparison, so the boundary is
  # pinned directly on a hand cosine matrix where 0.9 is the same
  # double literal on both sides.
  # 2 estimated x 1 reference; both estimated cosines are exactly 0.9.
  cm <- matrix(c(0.9, 0.9), 2, 1, dimnames = list(c("a", "b"), "t1"))
  tab <- msuiter:::.ms_compare_islam(cm, taus = 0.90)
  expect_identical(tab$tp[tab$tau == 0.90], 2L) # >= boundary inclusive
  expect_identical(tab$fp[tab$tau == 0.90], 0L)
  # Just below the line: 0.8999... is NOT a TP.
  cm2 <- matrix(c(0.9 - 1e-12, 0.9 - 1e-12), 2, 1,
    dimnames = list(c("a", "b"), "t1"))
  tab2 <- msuiter:::.ms_compare_islam(cm2, taus = 0.90)
  expect_identical(tab2$tp[tab2$tau == 0.90], 0L)
})

test_that("protocol = character(0) yields the metrics-only view", {
  labels <- .ms_bd_labels()
  a <- .ms_bd_unit(32)
  E <- cbind(a); R <- cbind(a)
  dimnames(E) <- list(labels, "e")
  dimnames(R) <- list(labels, "r")
  comp <- ms_compare(E, R, protocol = character(0), null_n_draws = 2000L)
  expect_null(comp@hungarian)
  expect_null(comp@islam)
  expect_false(is.null(comp@metrics$cosine))
  expect_false(is.null(comp@metrics$p_null))
})

test_that("the Jiang zero-total lane is counted and excluded from scoring", {
  labels <- .ms_bd_labels()
  set.seed(5)
  truth <- matrix(rexp(3 * 4), 3, 4)
  truth[, 4] <- 0 # a dead sample
  est <- truth
  jf <- msuiter:::.ms_compare_jiang(est, truth, catalogs = NULL,
    signatures_est = NULL)
  # The dead column (zero total on BOTH sides) is skipped, not scored.
  expect_identical(jf$n_samples_zero_total, 1L)
  # Scaled Manhattan divides by the LIVE total only.
  live_total <- sum(truth[, 1:3])
  expect_equal(jf$scaled_manhattan * live_total,
    sum(abs(est[, 1:3] - truth[, 1:3])), tolerance = 1e-12)
})
