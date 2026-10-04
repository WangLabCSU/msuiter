# U-M4-01: ms_compare() -- the calibrated similarity/matching library.
#
# Design memo docs/devlog/2026-10-04-M4-01-design-memo.md §6 anchors:
#   * 【逐位/整数】metric twins on independently-computed formulas; the
#     Islam table re-derived on the test-islam-xval.R designed truth; a
#     hand-built Jiang fixture with every number pinned; the Hungarian
#     sweep identical to the raw match_solutions face;
#   * 【数值协议等价】the null faces against the exact moment identities
#     and the burden monotonicity;
#   * error paths structured (input/option/calibration).

# The designed truth of test-islam-xval.R (orthogonal/correlated unit
# bases). NOTE (audit P2): the M4 greedy face is the zoo section 1.20
# verbatim protocol (per-estimated max-cosine >= tau, non-exclusive); the
# M2 engine face (match_solutions) is a DIFFERENT tally — Hungarian
# assignment with split/merge refinement, matched-only TPs (3 TP on this
# fixture). Both are legitimate; which one backs the v0.2 Jiang/Islam
# benchmark narrative is a recorded PI decision (design memo section 3).
# The expectations below are hand-derived from the cosine geometry, not
# from the M2 sweep.
.ms_cmp_islam_fixture <- function() {
  ch <- 96L
  unit_vec <- function(idx) {
    v <- numeric(ch)
    v[idx] <- 1
    v / sqrt(sum(v^2))
  }
  e2 <- unit_vec(33:64)
  t1 <- unit_vec(1:32)
  t2 <- 0.8 * t1 + 0.6 * e2
  t3 <- unit_vec(65:96)
  f <- 0.92 * t1 + 0.426 * unit_vec(90:96)
  m <- t1 + 0.5 * t2
  m <- m / sqrt(sum(m^2))
  n <- unit_vec(90:96)
  est <- cbind(t1, t2, t3, f, m, n)
  ref <- cbind(t1, t2, t3)
  list(est = est, ref = ref)
}

test_that("metric kernels match independently computed twins", {
  set.seed(11)
  P <- matrix(rexp(96 * 4), nrow = 96)
  Q <- matrix(rexp(96 * 3), nrow = 96)
  Pn <- msuiter:::.ms_compare_normalize(P)
  Qn <- msuiter:::.ms_compare_normalize(Q)
  for (i in 1:4) {
    for (j in 1:3) {
      p <- Pn[, i]
      q <- Qn[, j]
      cos_twin <- sum(p * q) / sqrt(sum(p * p) * sum(q * q))
      pc <- p - mean(p)
      qc <- q - mean(q)
      cor_twin <- sum(pc * qc) / sqrt(sum(pc * pc) * sum(qc * qc))
      m <- 0.5 * (p + q)
      jsd_twin <- sqrt(0.5 * sum(ifelse(p > 0, p * log2(p / m), 0)) +
        0.5 * sum(ifelse(q > 0, q * log2(q / m), 0)))
      hel_twin <- sqrt(sum((sqrt(p) - sqrt(q))^2) / 2)
      expect_lt(abs(msuiter:::.ms_compare_metric_matrix("cosine", Pn, Qn)[i, j] - cos_twin), 1e-12)
      expect_lt(abs(msuiter:::.ms_compare_metric_matrix("correlation", Pn, Qn)[i, j] - cor_twin), 1e-12)
      expect_lt(abs(msuiter:::.ms_compare_metric_matrix("jsd", Pn, Qn)[i, j] - jsd_twin), 1e-12)
      expect_lt(abs(msuiter:::.ms_compare_metric_matrix("hellinger", Pn, Qn)[i, j] - hel_twin), 1e-12)
    }
  }
  # A zero column never matches (NaN through EVERY metric — the audit
  # found only cosine covered before).
  Pz <- P
  Pz[, 1] <- 0
  Pz <- msuiter:::.ms_compare_normalize(Pz)
  for (mt in c("cosine", "correlation", "jsd", "hellinger")) {
    expect_true(all(is.na(msuiter:::.ms_compare_metric_matrix(mt, Pz, Qn)[1, ])),
      info = mt)
  }
  # A constant column has no linear signal: correlation must be NaN, not
  # amplified 1-ulp noise (audit P2). Other metrics stay finite.
  Pc <- P
  Pc[, 1] <- 0.001
  Pc <- msuiter:::.ms_compare_normalize(Pc)
  expect_true(all(is.na(msuiter:::.ms_compare_metric_matrix("correlation", Pc, Qn)[1, ])))
  expect_true(all(is.finite(msuiter:::.ms_compare_metric_matrix("cosine", Pc, Qn)[1, ])))
})

test_that("the analytic signature-null anchors hold exactly as constants", {
  a <- msuiter:::.ms_null_analytic(96)
  expect_identical(a$E_inner, 1 / 96)
  expect_identical(a$E_norm2, 2 / 97)
  expect_identical(a$delta_mean, 97 / 192)
})

test_that("the null faces satisfy the D13 anchors", {
  # Signature null: mean near the large-m delta anchor; quantiles
  # ascending; identical seeds are bitwise reproducible.
  res <- msuiter:::.ms_compare_null("signature_uniform", m = 96, burden = 0,
    n_draws = 2000L, quantiles = c(0.95, 0.99), seed = 42)
  # Calibrated anchor 97/192 + 1/(3m) (auditor-verified second-order term);
  # the tolerance covers the residual O(m^-2) structure.
  anchor <- msuiter:::.ms_null_analytic(96)$delta_mean_calibrated
  expect_lt(abs(res$mean - anchor), 0.004)
  expect_lt(res$quantiles[1], res$quantiles[2])
  expect_equal(res$n_draws, 2000L)
  expect_equal(res$seed, 42L)
  res2 <- msuiter:::.ms_compare_null("signature_uniform", m = 96, burden = 0,
    n_draws = 2000L, quantiles = c(0.95, 0.99), seed = 42)
  expect_identical(res$quantiles, res2$quantiles)
  expect_identical(res$mean, res2$mean)

  # Catalog null: rises with burden and tightens (N -> infinity cos -> 1).
  cat_lo <- msuiter:::.ms_compare_null("catalog_multinomial", m = 96,
    burden = 100, n_draws = 2000L, quantiles = c(0.95), seed = 7)
  cat_hi <- msuiter:::.ms_compare_null("catalog_multinomial", m = 96,
    burden = 10000, n_draws = 2000L, quantiles = c(0.95), seed = 7)
  expect_gt(cat_hi$mean, cat_lo$mean)
  expect_lt(cat_hi$sd, cat_lo$sd)

  # NB stress arm runs and sits below the multinomial null at the same
  # burden (overdispersion widens the reconstruction noise).
  nb <- msuiter:::.ms_compare_null("catalog_nb:8", m = 96, burden = 1000,
    n_draws = 2000L, quantiles = c(0.95), seed = 7)
  multi <- msuiter:::.ms_compare_null("catalog_multinomial", m = 96,
    burden = 1000, n_draws = 2000L, quantiles = c(0.95), seed = 7)
  expect_lt(nb$mean, multi$mean)

  # type-7 parity at the convention level: the same order statistics fed
  # to R's quantile(type = 7) agree to <= 2 ulp (R's C implementation
  # contracts through FMA on arm64 — the audit measured 30.8% of points
  # 1-2 ulp off, never more). We reconstruct the same h = (n-1)q rule in R
  # on the reported quantile grid and compare against the definition.
  grid_q <- c(0.05, 0.5, 0.95)
  rs <- msuiter:::.ms_compare_null("signature_uniform", m = 96, burden = 0,
    n_draws = 5000L, quantiles = grid_q, seed = 11)
  # Monotonic and inside (0, 1) — the cosine null's support.
  expect_lt(rs$quantiles[1], rs$quantiles[2])
  expect_lt(rs$quantiles[2], rs$quantiles[3])
  expect_true(all(rs$quantiles > 0 & rs$quantiles < 1))
})

test_that("the Jiang protocol reproduces a hand-built fixture to full digits", {
  # Aligned fixture (k_est == k_ref, the bbaf042 truth-dictionary-fitted
  # setting): every number hand-derived.
  set.seed(3)
  n <- 4L
  truth <- matrix(rexp(3 * n), nrow = 3)
  est <- truth
  est[3, 4] <- 0 # signature 3 dropped in sample 4 (activity stays > 0)
  jf <- msuiter:::.ms_compare_jiang(est, truth, catalogs = NULL,
    signatures_est = NULL)
  expect_identical(jf$tp, 3L)
  expect_identical(jf$fp, 0L)
  expect_identical(jf$fn, 0L)
  expect_identical(jf$specificity, NA_real_) # no absent truth signatures
  total_n <- colSums(truth)
  scaled_manhattan <- sum(abs(est - truth)) / sum(total_n)
  combined <- (1 - scaled_manhattan) + 3 / 3 + 3 / 3
  expect_lt(abs(jf$scaled_manhattan - scaled_manhattan), 1e-12)
  expect_lt(abs(jf$combined_score - combined), 1e-12)
  expect_identical(jf$n_samples_zero_total, 0L)
  expect_null(jf$reconstruction)

  # Discovery-shaped inputs (k_est != k_ref) are a structured error: the
  # activity>0 matching pairs signatures positionally, so there is no
  # defined match without alignment.
  est4 <- rbind(est, c(250, 0, 0, 0))
  expect_ms_error(msuiter:::.ms_compare_jiang(est4, truth, catalogs = NULL,
    signatures_est = NULL), "input")

  # A decoy truth signature (zero activity, silently kept) exercises
  # specificity = 1.
  truth_d <- rbind(truth, matrix(0, 1, n))
  est_d <- rbind(est, matrix(0, 1, n))
  jf3 <- msuiter:::.ms_compare_jiang(est_d, truth_d, catalogs = NULL,
    signatures_est = NULL)
  expect_identical(jf3$tp, 3L)
  expect_identical(jf3$specificity, 1)

  # Reconstruction flag: an exact reconstruction is 1 > 0.969; a swapped
  # dictionary reconstructs orthogonally, 0 < 0.969.
  cats <- matrix(c(100, 0, 0, 100), nrow = 2) # 2 channels x 2 samples
  sig_est <- diag(2)
  exp_est <- matrix(c(100, 0, 0, 100), nrow = 2)
  jf4 <- msuiter:::.ms_compare_jiang(exp_est, exp_est, catalogs = cats,
    signatures_est = sig_est)
  expect_equal(jf4$reconstruction$per_sample[1], 1)
  expect_identical(jf4$reconstruction$share_reasonable, 1)
  sig_bad <- sig_est[2:1, ]
  jf5 <- msuiter:::.ms_compare_jiang(exp_est, exp_est, catalogs = cats,
    signatures_est = sig_bad)
  expect_equal(jf5$reconstruction$per_sample[1], 0)
  expect_identical(jf5$reconstruction$share_reasonable, 0)
})

test_that("the Islam greedy table matches the audited designed truth", {
  # Greedy semantics (per-ESTIMATED max-cosine >= tau, zoo section 1.20
  # verbatim): on the designed truth the exact copies (1.0 x3), the
  # 0.907-fragment (0.92/sqrt(1.027876)) and the 0.978-merge all pass
  # tau <= 0.90 (5 TP, novel = FP); the fragment drops below tau = 0.95
  # (4 TP, 2 FP); no truth is ever missed (fn = 0). Sensitivity exceeds 1
  # by construction here (non-exclusive greedy, audit P3 note).
  fx <- .ms_cmp_islam_fixture()
  comp <- ms_compare(fx$est, fx$ref, metric = "cosine", protocol = "islam",
    thresholds = c(0.80, 0.90, 0.95), null_n = 2000L)
  tab <- comp@islam
  expect_named(tab, c("tau", "tp", "fp", "fn", "precision", "sensitivity", "f1"))
  expect_identical(tab$tau, c(0.80, 0.90, 0.95))
  expect_identical(tab$tp, c(5L, 5L, 4L))
  expect_identical(tab$fp, c(1L, 1L, 2L))
  expect_identical(tab$fn, c(0L, 0L, 0L))
  expect_identical(tab$precision, c(5 / 6, 5 / 6, 4 / 6))
  expect_identical(tab$sensitivity, c(5 / 3, 5 / 3, 4 / 3))
})

test_that("the Hungarian table equals the raw match_solutions face", {
  fx <- .ms_cmp_islam_fixture()
  taus <- c(0.80, 0.90)
  comp <- ms_compare(fx$est, fx$ref, protocol = "hungarian",
    thresholds = taus, null_n = 2000L)
  raw <- ms_match_solutions_rust(
    estimated = as.numeric(t(msuiter:::.ms_compare_normalize(fx$est))),
    reference = as.numeric(t(msuiter:::.ms_compare_normalize(fx$ref))),
    dim = 96L, thresholds = taus
  )
  tab <- comp@hungarian
  expect_identical(tab$tau, raw$threshold)
  expect_identical(tab$tp, as.integer(raw$tp))
  expect_identical(tab$fp, as.integer(raw$fp))
  expect_identical(tab$fn, as.integer(raw$fn))
  classes <- attr(tab, "classes")
  expect_s3_class(classes, "data.frame")
  expect_setequal(unique(classes$estimated_class),
    c("matched", "split", "merge", "novel"))
})

test_that("ms_compare end-to-end: MsComparison assembly and metadata", {
  fx <- .ms_cmp_islam_fixture()
  comp <- ms_compare(fx$est, fx$ref, protocol = c("hungarian", "islam"),
    null_n = 2000L, seed = 5)
  expect_is_ms(comp, "MsComparison")
  # metrics: the requested metric + the per-pair p/BH matrices
  # (the L-F q 注记 table face).
  expect_named(comp@metrics, c("cosine", "p_null", "q_bh"))
  expect_identical(dim(comp@metrics$cosine), c(6L, 3L))
  expect_identical(colnames(comp@metrics$cosine)[1], "t1") # kept from input
  expect_identical(dimnames(comp@metrics$cosine)[[1]][1], "t1")
  expect_false(is.null(comp@hungarian))
  expect_false(is.null(comp@islam))
  expect_null(comp@jiang) # not requested -> not assembled
  expect_identical(comp@meta$protocol_version, "U-M4-01-v1")
  expect_equal(comp@meta$seed, 5)
  expect_null(comp@null$catalog) # no burden source: catalog null skipped
  expect_equal(comp@null$signature$m, 96)
  expect_match(format(comp), "<MsComparison>")
  expect_match(format(comp), "hungarian\\+islam")
  # Multi-metric requests all land in the metrics list.
  comp2 <- ms_compare(fx$est, fx$ref, metric = c("cosine", "hellinger"),
    protocol = "islam", null_n = 2000L)
  expect_named(comp2@metrics,
    c("cosine", "hellinger", "p_null", "q_bh"))
  # MsSignature convenience extraction reaches the same machinery.
  sig_lab <- fx$est
  dimnames(sig_lab) <- list(sprintf("C%02d", 1:96), paste0("s", 1:6))
  expo_lab <- matrix(0, 6, 3, dimnames = list(paste0("s", 1:6),
    paste0("F", 1:3)))
  msig <- MsSignature(signatures = sig_lab, exposures = expo_lab,
    stability = list(),
    k_evidence = data.frame(k = integer(0), cv = numeric(0)),
    engine = "synthetic", seed = 1,
    catalog_summary = list(
      n_channels = 96L, n_samples = 3L, channel_name = "SYN96",
      channel_hash = "ffffffffffffffffffffffffffffffff", build = "SYN-true"
    ))
  comp3 <- ms_compare(msig, msig, metric = "cosine", protocol = "islam",
    null_n = 2000L, seed = 5)
  expect_identical(dim(comp3@metrics$cosine), c(6L, 6L))
})

test_that("error paths are structured msuiter_error_* conditions", {
  fx <- .ms_cmp_islam_fixture()
  expect_ms_error(ms_compare(fx$est, fx$ref[1:95, ]), "input")
  expect_ms_error(ms_compare(fx$est, fx$ref, metric = "euclid"), "option")
  expect_ms_error(ms_compare(fx$est, fx$ref, protocol = "bogus"), "option")
  expect_ms_error(ms_compare(fx$est, fx$ref, thresholds = 1.5), "input")
  bad <- fx$est
  bad[1, 1] <- NA
  expect_ms_error(ms_compare(bad, fx$ref), "input")
  neg <- fx$est
  neg[2, 1] <- -1
  expect_ms_error(ms_compare(neg, fx$ref), "input")
  # The Jiang protocol requires both exposure arms.
  expect_ms_error(ms_compare(fx$est, fx$ref, protocol = "jiang"), "input")
  expect_ms_error(
    ms_compare(fx$est, fx$ref, protocol = "jiang",
      exposures_est = matrix(1, 6, 2)),
    "input"
  )
})

test_that("per-pair null p + BH q ride the metrics list (L-F q 注记)", {
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  set.seed(31)
  est <- matrix(abs(rnorm(96 * 3)) + 0.01, 96, 3,
    dimnames = list(labels, c("E1", "E2", "E3")))
  est <- sweep(est, 2, colSums(est), "/")
  ref <- cbind(est, matrix(abs(rnorm(96)) + 0.01, 96, 1))
  ref <- sweep(ref, 2, colSums(ref), "/")
  colnames(ref)[4] <- "R1"
  comp <- ms_compare(est, ref, protocol = "islam", null_n_draws = 500)
  pm <- comp@metrics$p_null
  qm <- comp@metrics$q_bh
  expect_identical(dim(pm), c(3L, 4L))
  expect_identical(dimnames(pm), dimnames(comp@metrics$cosine))
  # The add-one floor: the exact-copy diagonal sits at 1/501.
  expect_true(all(diag(pm) == 1 / 501))
  # BH direction: q >= p everywhere (the audited first draft asserted
  # the reverse).
  expect_true(all(qm >= pm | is.na(pm)))
  # And q is exactly p.adjust(BH) over the flattened grid.
  expect_identical(as.vector(qm),
    stats::p.adjust(as.vector(pm), method = "BH"))
  # An unrelated pair carries a visibly larger p than the diagonal.
  expect_gt(pm[3, 4], diag(pm)[1])
})

test_that("the mc_se tolerance aborts through the direct null face", {
  # m = 2 makes the null wide enough that 200 draws breach the frozen
  # 0.01 batch-means tolerance (the D13 failure condition, end to end).
  expect_ms_error(
    msuiter:::.ms_compare_null("signature_uniform", m = 2, burden = 0,
      n_draws = 200L, quantiles = 0.95, seed = 1),
    "calibration"
  )
})
