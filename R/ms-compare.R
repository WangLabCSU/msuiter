# ms-compare.R: the calibrated similarity/matching library ms_compare()
# (U-M4-01; CAPABILITY-MATRIX L-F, ARCHITECTURE section "指标",
# design memo docs/devlog/2026-10-04-M4-01-design-memo.md).
#
# Four metrics on share-normalized columns (memo §1, frozen definitions):
#   cosine / correlation (Pearson on shares) / jsd (sqrt, bits) / hellinger.
# Two null families behind ms_compare_null_rust (memo §2): the signature
# null (unrelated uniform-Dirichlet signatures, channel count only) and
# the catalog null (truth reconstructed at burden N -- the 零校准 of the
# cosine; "按通道数×负荷"). The frozen MC-SE tolerance (0.01) is enforced
# HERE at the R face: the kernel reports the number, policy lives at the
# boundary.
# Three matching protocols (memo §3):
#   hungarian -- engine::consensus::match_solutions verbatim (U-M2-01),
#                one-to-one, the primary metric;
#   islam     -- per-estimated greedy max-cosine >= tau (Islam 2022
#                semantics, 逐位; the test layer re-derives the
#                test-islam-xval.R table);
#   jiang     -- activity > 0 matching + scaled Manhattan + Combined Score
#                + specificity (bbaf042; exposure-driven, no cosine in the
#                match; the 0.969 "reasonable reconstruction" line is a
#                cited upstream median, not an anchor).
#
# All violations raise msuiter_error_* conditions with the i/j/c payload
# (ARCHITECTURE section 3.5); bare stop() is banned.

# Frozen hyper-parameters of this unit (design memo §2/§5):
#   mc_se_tol      : the null mean's batch-means MC standard error cap;
#   null_n         : the default draw count (20000 -- memo §5 floor 200);
#   null_quantiles : the reported quantile set (type-7, R-parity tested);
#   reconstruction_cosine : the bbaf042 "reasonable reconstruction" line
#                    (cited upstream value 0.969 -- never an anchor).
.ms_compare_defaults <- list(
  mc_se_tol = 0.01,
  null_n = 20000L,
  null_quantiles = c(0.95, 0.99, 0.999),
  reconstruction_cosine = 0.969
)

.ms_compare_metric_names <- c("cosine", "correlation", "jsd", "hellinger")
.ms_compare_protocol_names <- c("hungarian", "islam", "jiang")

# ---------------------------------------------------------------------------
# Metrics (memo §1; all on share-normalized columns; zero columns are NaN)
# ---------------------------------------------------------------------------

# Share-normalize columns; a zero column becomes all-NaN (0/0), which every
# downstream metric propagates and the protocols treat as "never matches".
.ms_compare_normalize <- function(x) {
  sweep(x, 2L, colSums(x), "/")
}

# Pairwise similarity, k_est x k_ref, for one metric name. Inputs are
# share-normalized matrices with at least 2 rows.
.ms_compare_metric_matrix <- function(metric, P, Q) {
  switch(metric,
    cosine = {
      np <- sqrt(colSums(P * P))
      nq <- sqrt(colSums(Q * Q))
      crossprod(P, Q) / outer(np, nq)
    },
    correlation = {
      pc <- sweep(P, 2L, colMeans(P), "-")
      qc <- sweep(Q, 2L, colMeans(Q), "-")
      np <- sqrt(colSums(pc * pc))
      nq <- sqrt(colSums(qc * qc))
      # A constant column carries no linear signal: centering leaves
      # ~1-ulp float noise (colMeans accumulates in C), which the division
      # would amplify into deterministic 1e-16 junk — the frozen contract
      # is NaN (audit P2). Zero-variance detection at the machine-noise
      # scale: the centered norm relative to the uncentered one.
      rel <- np / pmax(sqrt(colSums(P * P)), .Machine$double.xmin)
      relq <- nq / pmax(sqrt(colSums(Q * Q)), .Machine$double.xmin)
      guard <- outer(rel < 1e-12, relq < 1e-12, "|")
      out <- crossprod(pc, qc) / outer(np, nq)
      out[guard] <- NA_real_
      out
    },
    jsd = {
      out <- matrix(NA_real_, nrow = ncol(P), ncol = ncol(Q))
      for (i in seq_len(ncol(P))) {
        for (j in seq_len(ncol(Q))) {
          out[i, j] <- sqrt(.ms_compare_jsd_bits(P[, i], Q[, j]))
        }
      }
      out
    },
    hellinger = {
      out <- matrix(NA_real_, nrow = ncol(P), ncol = ncol(Q))
      sp <- sqrt(P)
      sq <- sqrt(Q)
      for (i in seq_len(ncol(P))) {
        for (j in seq_len(ncol(Q))) {
          d <- sp[, i] - sq[, j]
          out[i, j] <- sqrt(sum(d * d) / 2)
        }
      }
      out
    },
    # nocov start — guarded by the choice gate above
    msuiter_abort("internal", paste0("unreachable metric: ", metric),
      i = "the metric choice gate must have removed unknown names",
      j = paste0("requested: ", paste(metric, collapse = ",")),
      c = "report this as a bug: the choice gate and the switch disagree"
    )
    # nocov end
  )
}

# Jensen–Shannon divergence in bits (log2) with the 0log0 = 0 convention;
# the ms_compare metric is sqrt(JSD) (a true metric, memo §1).
.ms_compare_jsd_bits <- function(p, q) {
  m <- 0.5 * (p + q)
  kl <- function(a, b) {
    i <- a > 0
    sum(a[i] * log2(a[i] / b[i]))
  }
  0.5 * kl(p, m) + 0.5 * kl(q, m)
}

# The analytic anchors of the signature null (memo §2): exact moment
# identities plus the large-m delta approximation with the auditor-verified
# second-order term — the U-M4-01 audit measured a systematic
# delta-approximation bias of +1/(3m) (constant across m in {12, 48, 96},
# 1e6-pair independent MC: m=96 mean 0.508686 vs 97/192 + 1/288 = 0.508681),
# adopted here as the calibrated anchor. Test-layer anchors only.
.ms_null_analytic <- function(m) {
  list(
    E_inner = 1 / m,
    E_norm2 = 2 / (m + 1),
    delta_mean = (m + 1) / (2 * m),
    delta_mean_calibrated = (m + 1) / (2 * m) + 1 / (3 * m)
  )
}

# ---------------------------------------------------------------------------
# Null wrapper (memo §2/§5): the frozen MC-SE tolerance lives here.
# ---------------------------------------------------------------------------

.ms_compare_null <- function(family, m, burden, n_draws, quantiles, seed) {
  res <- .msffi_check(ms_compare_null_rust(
    family = family, m = m, burden = burden,
    n_draws = n_draws, quantiles = quantiles, seed = seed
  ))
  if (res$mc_se > .ms_compare_defaults$mc_se_tol) {
    msuiter_abort(
      "calibration",
      "the null Monte Carlo standard error exceeds the frozen tolerance",
      i = sprintf("family: %s; mc_se = %.4g", res$family, res$mc_se),
      j = sprintf("tolerance: %.4g (ms_compare_defaults$mc_se_tol)",
                  .ms_compare_defaults$mc_se_tol),
      c = "raise null_n or reduce the requested channel count"
    )
  }
  res
}

# The shape-conditional reconstruction-noise null (U-M7-pre upgrade
# arm): conditioned on a reference profile u and a burden N -- the
# memo's "entropy-matched" semantics materialized (shape through u,
# noise scale through alpha_total = N). The MC-SE tolerance is the same
# frozen 0.01 as the other null faces.
.ms_compare_shape_null <- function(profile, burden, n_draws, quantiles, seed) {
  res <- .msffi_check(ms_compare_shape_null_rust(
    profile = as.numeric(profile), burden = burden, n_draws = n_draws,
    quantiles = quantiles, seed = seed
  ))
  if (res$mc_se > .ms_compare_defaults$mc_se_tol) {
    msuiter_abort(
      "calibration",
      "the shape-null Monte Carlo standard error exceeds the frozen tolerance",
      i = sprintf("mc_se = %.4g", res$mc_se),
      j = sprintf("tolerance: %.4g (ms_compare_defaults$mc_se_tol)",
                  .ms_compare_defaults$mc_se_tol),
      c = "raise n_draws"
    )
  }
  res
}

# The conditional tail probability for one observed cosine: draws are
# Multinomial(N, u)/N reconstructions of the GIVEN reference profile --
# "could this deviation arise from sampling noise alone at this shape
# and burden?" Add-one rule, the audited R-twin convention.
.ms_null_emp_pvalue_conditional <- function(observed, profile, burden,
                                            n_draws = 5000L, seed = 1) {
  set.seed(seed)
  total <- sum(profile)
  u <- profile / total
  n_hit <- 0L
  for (r in seq_len(n_draws)) {
    counts <- stats::rmultinom(1, size = burden, prob = u)
    shares <- as.numeric(counts) / burden
    nx <- sqrt(sum(shares^2))
    nu <- sqrt(sum(u^2))
    cos <- sum(shares * u) / (nx * nu)
    if (cos >= observed) n_hit <- n_hit + 1L
  }
  (1 + n_hit) / (n_draws + 1)
}

# ---------------------------------------------------------------------------
# Protocols (memo §3)
# ---------------------------------------------------------------------------

# Hungarian assembly: the FFI sweep (flat per-threshold vectors) becomes
# the tidy sweep table + the per-signature classification table. The
# engine's assignment/TP semantics are untouched (U-M2-01 audited).
.ms_compare_hungarian <- function(P, Q, taus) {
  raw <- ms_match_solutions_rust(
    estimated = as.numeric(t(P)),
    reference = as.numeric(t(Q)),
    dim = nrow(P),
    thresholds = as.numeric(taus)
  )
  k_est <- ncol(P)
  rows <- vector("list", length(raw$threshold))
  classes <- vector("list", length(raw$threshold))
  offset <- 0L
  for (i in seq_along(raw$threshold)) {
    p_i <- raw$p_per_threshold[i]
    idx <- seq.int(offset + 1L, offset + p_i)
    offset <- offset + p_i
    cls <- raw$estimated_class[idx]
    tp <- raw$tp[i]
    fp <- raw$fp[i]
    fn <- raw$fn[i]
    precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
    recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
    f1 <- if (is.finite(precision) && is.finite(recall) && precision + recall > 0) {
      2 * precision * recall / (precision + recall)
    } else {
      NA_real_
    }
    rows[[i]] <- data.frame(
      tau = raw$threshold[i], tp = tp, fp = fp, fn = fn,
      precision = precision, recall = recall, f1 = f1,
      split = sum(cls == "split"), merge = sum(cls == "merge")
    )
    classes[[i]] <- data.frame(
      tau = raw$threshold[i],
      estimate_index = raw$estimate_index[idx],
      estimated_class = cls,
      reference_index = raw$reference_index[idx]
    )
  }
  sweep_df <- do.call(rbind, rows)
  classes_df <- do.call(rbind, classes)
  attr(sweep_df, "classes") <- classes_df
  sweep_df
}

# Islam 2022 greedy protocol (memo §3): per-ESTIMATED max-cosine >= tau
# makes a TP (greedy, not one-to-one); FP = the rest; a truth is FN iff no
# estimated signature reaches tau against it. NaN cosines (degenerate zero
# signatures) can never match.
.ms_compare_islam <- function(cos_mat, taus) {
  k_est <- nrow(cos_mat)
  k_ref <- ncol(cos_mat)
  best <- apply(cos_mat, 1L, function(r) if (all(is.na(r))) NA_real_ else max(r, na.rm = TRUE))
  do.call(rbind, lapply(taus, function(tau) {
    tp_rows <- which(best >= tau)
    tp <- length(tp_rows)
    fp <- k_est - tp
    claimed <- if (tp == 0L) rep(NA_real_, k_ref) else {
      apply(cos_mat[tp_rows, , drop = FALSE], 2L,
            function(col) if (all(is.na(col))) NA_real_ else max(col, na.rm = TRUE))
    }
    # A truth whose every cosine is NaN (degenerate zero signature) can
    # never be claimed: it counts as FN, not NA in the tally.
    fn <- sum(is.na(claimed) | !(claimed >= tau))
    precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
    sensitivity <- if (k_ref > 0) tp / k_ref else NA_real_
    f1 <- if (is.finite(precision) && is.finite(sensitivity) &&
              precision + sensitivity > 0) {
      2 * precision * sensitivity / (precision + sensitivity)
    } else {
      NA_real_
    }
    data.frame(tau = tau, tp = tp, fp = fp, fn = fn,
               precision = precision, sensitivity = sensitivity, f1 = f1)
  }))
}

# Jiang 2025 activity protocol (bbaf042; memo §3): matching on activity > 0
# (no cosine), scaled Manhattan in mutation units, Combined Score =
# (1 - scaled Manhattan) + Precision + Recall, specificity over the absent
# truth signatures, and the optional per-sample "reasonable reconstruction"
# flag (cited 0.969 line). Exposures are count-scale k x n matrices; the
# burden axis is colSums(catalogs) when given, colSums(exposures_ref)
# otherwise (the truth exposures are the generating counts).
.ms_compare_jiang <- function(exposures_est, exposures_ref, catalogs,
                              signatures_est) {
  # The bbaf042 protocol presupposes the TRUE dictionary was fit: the
  # activity>0 matching pairs signatures positionally, so the exposure
  # matrices must be cell-aligned (k_est == k_ref). Discovery-shaped
  # inputs have no 1:1 pairing — a structured argument error, never a
  # silent partial match.
  if (nrow(exposures_est) != nrow(exposures_ref)) {
    msuiter_abort(
      "input",
      "the Jiang protocol needs cell-aligned exposure matrices (the true dictionary fitted)",
      i = sprintf("exposures_est signatures: %d", nrow(exposures_est)),
      j = sprintf("exposures_ref signatures: %d", nrow(exposures_ref)),
      c = "fit the truth dictionary and pass its exposure matrix"
    )
  }
  a <- rowSums(exposures_ref)
  a_hat <- rowSums(exposures_est)
  truth_pos <- a > 0
  est_pos <- a_hat > 0
  tp <- sum(truth_pos & est_pos)
  fp <- sum(!truth_pos & est_pos)
  fn <- sum(truth_pos & !est_pos)
  absent <- sum(!truth_pos)
  specificity <- if (absent > 0) sum(!truth_pos & !est_pos) / absent else NA_real_
  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_

  total_n <- if (!is.null(catalogs)) colSums(catalogs) else colSums(exposures_ref)
  keep <- total_n > 0
  n_skipped <- sum(!keep)
  scaled_manhattan <- if (sum(keep) > 0) {
    sum(abs(exposures_est[, keep, drop = FALSE] -
              exposures_ref[, keep, drop = FALSE])) / sum(total_n[keep])
  } else {
    NA_real_
  }
  combined_score <- if (is.finite(scaled_manhattan)) {
    (1 - scaled_manhattan) + precision + recall
  } else {
    NA_real_
  }

  reconstruction <- NULL
  if (!is.null(catalogs) && !is.null(signatures_est)) {
    fitted <- signatures_est %*% exposures_est
    per_sample <- vapply(seq_len(ncol(catalogs)), function(j) {
      .ms_compare_cosine_scalar(catalogs[, j], fitted[, j])
    }, numeric(1L))
    reconstruction <- list(
      cosine_line = .ms_compare_defaults$reconstruction_cosine,
      median_cosine = stats::median(per_sample, na.rm = TRUE),
      share_reasonable = mean(per_sample > .ms_compare_defaults$reconstruction_cosine,
                              na.rm = TRUE),
      per_sample = per_sample
    )
  }
  list(
    tp = tp, fp = fp, fn = fn, specificity = specificity,
    precision = precision, recall = recall,
    scaled_manhattan = scaled_manhattan, combined_score = combined_score,
    n_samples_zero_total = n_skipped, reconstruction = reconstruction
  )
}

.ms_compare_cosine_scalar <- function(x, y) {
  nx <- sqrt(sum(x * x))
  ny <- sqrt(sum(y * y))
  if (nx == 0 || ny == 0) {
    return(NA_real_)
  }
  sum(x * y) / (nx * ny)
}

# The empirical signature-null tail probability for one observed
# cosine: p = (1 + #{null >= observed}) / (n + 1) over n fresh
# Dirichlet(1..1) pairs (the add-one rule -- an unbiased-ish tail
# estimate that never returns 0). D13: estimation object = the empirical
# tail fraction; generative model = the frozen uniform family; failure
# mode = none (the add-one rule is always defined); precision scales as
# 1/sqrt(n) and is reported through n_draws.
.ms_null_emp_pvalue <- function(observed, m, n_draws = 5000L, seed = 1) {
  if (!is.numeric(observed) || length(observed) != 1L || !is.finite(observed)) {
    msuiter_abort(
      "input",
      "observed must be a single finite cosine",
      i = "the null p-value annotates one pairwise comparison",
      j = paste0("received: ", msuiter_quote_trunc(observed)),
      c = "pass the cosine between one estimated and one reference signature"
    )
  }
  if (!is.numeric(n_draws) || length(n_draws) != 1L || n_draws < 200L ||
      n_draws != floor(n_draws)) {
    msuiter_abort(
      "input",
      "n_draws must be a single whole number >= 200",
      j = paste0("received: ", msuiter_quote_trunc(n_draws)),
      c = "the add-one tail estimate needs a usable denominator"
    )
  }
  set.seed(seed)
  # 2 draws per replicate: one pair per row.
  x <- matrix(stats::rgamma(2 * n_draws * m, shape = 1), nrow = n_draws,
              ncol = 2L * m)
  x <- x / rowSums(x)
  a <- x[, seq_len(m), drop = FALSE]
  b <- x[, m + seq_len(m), drop = FALSE]
  cosines <- rowSums(a * b) / sqrt(rowSums(a^2) * rowSums(b^2))
  (1 + sum(cosines >= observed)) / (n_draws + 1)
}

# ---------------------------------------------------------------------------
# The entry point
# ---------------------------------------------------------------------------

#' Calibrated comparison of two signature dictionaries
#'
#' `ms_compare()` scores an estimated dictionary against a reference one:
#' the pairwise similarity metrics on share-normalized columns, the three
#' matching protocols (Hungarian one-to-one primary, Islam greedy, Jiang
#' activity) and the null-distribution evaluations that calibrate the
#' cosine ("zero-calibration": better than chance at this channel count and
#' burden). The Jiang protocol additionally needs the exposure matrices
#' (activity > 0 matching has no cosine face).
#'
#' @param estimated m x k_est numeric matrix of signatures (columns sum to
#'   1 after normalization; zero columns never match), or an [MsSignature].
#' @param reference m x k_ref numeric matrix with the same channel count,
#'   or an [MsSignature].
#' @param metric character vector among "cosine", "correlation", "jsd",
#'   "hellinger".
#' @param protocol character vector among "hungarian", "islam", "jiang".
#' @param thresholds numeric vector of match thresholds for the
#'   Hungarian/Islam sweeps (default seq(0.80, 0.90, by = 0.01), the
#'   robustness appendix convention).
#' @param exposures_est,exposures_ref optional k x n count-scale activity
#'   matrices (Jiang protocol; required when it is requested).
#' @param catalogs optional m x n count matrix (Jiang reconstruction flag;
#'   also the default burden source for the catalog null).
#' @param signatures_est optional m x k_est matrix for the Jiang
#'   reconstruction flag (the fit's signature dictionary).
#' @param burden positive burden for the catalog null; default = the mean
#'   truth burden (colSums of the reference exposures or catalogs), and
#'   the catalog null is skipped when neither is available.
#' @param null_n draws per null family (>= 200; default 20000).
#' @param null_quantiles quantiles reported for each null, in (0, 1).
#' @param seed master seed of the null Monte Carlo (PCG64 layout v1;
#'   identical seeds are bitwise-reproducible).
#' @param null_n_draws Draws per pairwise empirical null p (>= 200;
#'   default 2000) -- the add-one tail estimate reported in the
#'   `p_null`/`q_bh` metric matrices.
#'
#' @return An [MsComparison].
#'
#' @seealso [MsComparison], [ms_match_solutions_rust] for the raw sweep.
#' @export
ms_compare <- S7::new_generic(
  "ms_compare",
  "estimated",
  function(estimated, reference, metric = "cosine",
           protocol = c("hungarian", "islam", "jiang"),
           thresholds = seq(0.80, 0.90, by = 0.01),
           exposures_est = NULL, exposures_ref = NULL,
           catalogs = NULL, signatures_est = NULL, burden = NULL,
           null_n = .ms_compare_defaults$null_n,
           null_quantiles = .ms_compare_defaults$null_quantiles,
           seed = 1L, null_n_draws = 2000L)
    S7::S7_dispatch()
)

# Shared gates + assembly for every method (no semantics added beyond the
# error payload; the matrix method is the single kernel caller).
.ms_compare_assemble <- function(P, Q, metric, protocol, thresholds,
                                 exposures_est, exposures_ref, catalogs,
                                 signatures_est, burden, null_n,
                                 null_quantiles, seed, null_n_draws = 2000L) {
  # --- input gates (structured, before any null draws burn work) ----------
  for (nm in c("estimated", "reference")) {
    x <- if (nm == "estimated") P else Q
    if (!is.numeric(x) || !is.matrix(x)) {
      msuiter_abort("input", sprintf("%s must be a numeric matrix", nm),
        i = "ms_compare() compares column signatures of a shared channel space",
        j = paste0("received: ", class(x)[1L]),
        c = "pass m x k matrices with matching row counts"
      )
    }
    if (anyNA(x) || any(!is.finite(x)) || any(x < 0)) {
      msuiter_abort("input", sprintf("%s must be finite and non-negative", nm),
        i = "signatures are share vectors; NaN/negative entries are uninterpretable",
        j = paste0("offending entries: ", sum(is.na(x) | !is.finite(x) | x < 0)),
        c = "re-fit or re-normalize the dictionary before comparing"
      )
    }
  }
  if (nrow(P) != nrow(Q)) {
    msuiter_abort("input", "estimated and reference must share the channel count",
      i = sprintf("estimated rows: %d; reference rows: %d", nrow(P), nrow(Q)),
      j = "the metrics compare signatures channel-wise in one space",
      c = "project both dictionaries onto the same channel space"
    )
  }
  m <- nrow(P)
  if (m < 2) {
    msuiter_abort("input", "ms_compare needs at least 2 channels",
      i = paste0("m: ", m),
      j = "the null faces and the metrics are degenerate at m = 1",
      c = "compare dictionaries with at least 2 channels"
    )
  }
  bad_metric <- setdiff(metric, .ms_compare_metric_names)
  if (length(bad_metric) > 0L) {
    msuiter_abort("option", "metric must be among the frozen names",
      i = paste0("unknown: ", paste(bad_metric, collapse = ", ")),
      j = paste0("legal: ", paste(.ms_compare_metric_names, collapse = ", ")),
      c = "pick metrics from the frozen design-memo set"
    )
  }
  bad_protocol <- setdiff(protocol, .ms_compare_protocol_names)
  if (length(bad_protocol) > 0L) {
    msuiter_abort("option", "protocol must be among the frozen names",
      i = paste0("unknown: ", paste(bad_protocol, collapse = ", ")),
      j = paste0("legal: ", paste(.ms_compare_protocol_names, collapse = ", ")),
      c = "pick protocols from the frozen design-memo set"
    )
  }
  if (!is.numeric(thresholds) || length(thresholds) == 0L || anyNA(thresholds) ||
      any(thresholds <= 0 | thresholds >= 1)) {
    msuiter_abort("input", "thresholds must be non-empty numeric in (0, 1)",
      i = paste0("received: ", msuiter_quote_trunc(thresholds)),
      j = "the sweep thresholds are match lines on the cosine scale",
      c = "use e.g. the default seq(0.80, 0.90, by = 0.01)"
    )
  }

  # --- metrics (share-normalized columns) ---------------------------------
  Pn <- .ms_compare_normalize(P)
  Qn <- .ms_compare_normalize(Q)
  metrics <- list()
  for (mt in metric) {
    mat <- .ms_compare_metric_matrix(mt, Pn, Qn)
    est_labels <- if (is.null(colnames(P))) paste0("est", seq_len(ncol(P))) else colnames(P)
    ref_labels <- if (is.null(colnames(Q))) paste0("ref", seq_len(ncol(Q))) else colnames(Q)
    dimnames(mat) <- list(est_labels, ref_labels)
    metrics[[mt]] <- mat
  }

  # --- protocols -----------------------------------------------------------
  hungarian <- if ("hungarian" %in% protocol) {
    .ms_compare_hungarian(Pn, Qn, thresholds)
  } else {
    NULL
  }
  islam <- if ("islam" %in% protocol) {
    # The greedy protocol always reads the COSINE (Islam 2022 semantics),
    # independent of which metrics the user listed.
    .ms_compare_islam(.ms_compare_metric_matrix("cosine", Pn, Qn), thresholds)
  } else {
    NULL
  }
  if ("jiang" %in% protocol) {
    if (is.null(exposures_est) || is.null(exposures_ref)) {
      msuiter_abort("input", "the Jiang protocol needs both exposure matrices",
        i = "activity > 0 matching has no cosine face (bbaf042)",
        j = paste0("missing: ",
                   paste(c("exposures_est", "exposures_ref")[
                     c(is.null(exposures_est), is.null(exposures_ref))
                   ], collapse = ", ")),
        c = "pass the k x n count-scale activity matrices"
      )
    }
    exposures_est <- as.matrix(exposures_est)
    exposures_ref <- as.matrix(exposures_ref)
    if (ncol(exposures_est) != ncol(exposures_ref) ||
        nrow(exposures_est) != ncol(P) || nrow(exposures_ref) != ncol(Q)) {
      msuiter_abort("input", "exposure matrices must be k x n matching the dictionaries",
        i = sprintf("exposures_est: %d x %d; exposures_ref: %d x %d",
                    nrow(exposures_est), ncol(exposures_est),
                    nrow(exposures_ref), ncol(exposures_ref)),
        j = sprintf("expected: %d x n and %d x n (shared n)", ncol(P), ncol(Q)),
        c = "pass the fit outputs for the compared dictionaries"
      )
    }
    if (!is.null(catalogs) && nrow(catalogs) != m) {
      msuiter_abort("input", "catalogs must have the same channel count",
        i = sprintf("catalog rows: %d; channel count: %d", nrow(catalogs), m),
        j = "the reconstruction flag reads per-sample catalog columns",
        c = "pass the catalog the estimated dictionary was fitted to"
      )
    }
    if (!is.null(signatures_est) && (nrow(signatures_est) != m ||
                                     ncol(signatures_est) != ncol(P))) {
      msuiter_abort("input", "signatures_est must be m x k_est",
        i = sprintf("received: %d x %d; expected: %d x %d",
                    nrow(signatures_est), ncol(signatures_est), m, ncol(P)),
        j = "the reconstruction flag rebuilds catalogs from this dictionary",
        c = "pass the estimated signature matrix alongside its exposures"
      )
    }
    jiang <- .ms_compare_jiang(exposures_est, exposures_ref,
                               catalogs, signatures_est)
  } else {
    jiang <- NULL
  }

  # --- per-pair empirical null p + BH (the L-F "q 值注记" table face)
  # Every (est, ref) pair gets an add-one empirical tail probability
  # under the frozen signature-null family, then BH across ALL pairs
  # (the conservative whole-grid view). Same sampler as the scatter
  # annotation (the audited R twin of the Rust kernel law).
  if (!is.null(metrics$cosine)) {
    cm <- metrics$cosine
    pmat <- matrix(NA_real_, nrow(cm), ncol(cm),
                   dimnames = dimnames(cm))
    for (i in seq_len(nrow(cm))) {
      for (j in seq_len(ncol(cm))) {
        v <- cm[i, j]
        if (is.finite(v)) {
          pmat[i, j] <- .ms_null_emp_pvalue(v, m = m, n_draws = null_n_draws,
                                            seed = seed + i - 1L)
        }
      }
    }
    qbh <- matrix(stats::p.adjust(as.vector(pmat), method = "BH"),
                  nrow(cm), ncol(cm), dimnames = dimnames(cm))
    metrics$p_null <- pmat
    metrics$q_bh <- qbh
  }

  # --- nulls (signature family always; catalog family when a burden exists)
  if (is.null(burden)) {
    truth_n <- if (!is.null(catalogs)) colSums(catalogs) else {
      if (!is.null(exposures_ref)) colSums(exposures_ref) else NULL
    }
    burden <- if (!is.null(truth_n) && any(truth_n > 0)) mean(truth_n[truth_n > 0]) else NULL
  }
  null <- list(
    signature = .ms_compare_null(
      family = "signature_uniform", m = m, burden = 0, n_draws = null_n,
      quantiles = null_quantiles, seed = seed
    )
  )
  null$catalog <- if (!is.null(burden)) {
    .ms_compare_null(
      family = "catalog_multinomial", m = m, burden = burden,
      n_draws = null_n, quantiles = null_quantiles, seed = seed
    )
  } else {
    NULL
  }

  ms_comparison(
    metrics = metrics, hungarian = hungarian, islam = islam, jiang = jiang,
    null = null,
    meta = list(
      protocol_version = "U-M4-01-v1",
      package_version = as.character(utils::packageVersion("msuiter")),
      metric = metric, protocol = protocol,
      thresholds = thresholds, k_est = ncol(P), k_ref = ncol(Q), m = m,
      burden = burden, null_n = null_n, null_quantiles = null_quantiles,
      seed = seed
    )
  )
}

# Method: class_any — the kernel path (numeric matrices), with MsSignature
# convenience extraction. Dispatching on the S3 `matrix` base class is
# deliberately avoided (S7 0.2.x registers it as an S3 class that does not
# fire on raw matrices); the assembly layer's structured input gates are
# the type contract.
S7::method(ms_compare, S7::class_any) <- function(
    estimated, reference, metric = "cosine",
    protocol = c("hungarian", "islam", "jiang"),
    thresholds = seq(0.80, 0.90, by = 0.01),
    exposures_est = NULL, exposures_ref = NULL,
    catalogs = NULL, signatures_est = NULL, burden = NULL,
    null_n = .ms_compare_defaults$null_n,
    null_quantiles = .ms_compare_defaults$null_quantiles,
    seed = 1L, null_n_draws = 2000L) {
  est <- if (S7::S7_inherits(estimated, MsSignature)) estimated@signatures else estimated
  ref <- if (S7::S7_inherits(reference, MsSignature)) reference@signatures else reference
  .ms_compare_assemble(est, ref, metric, protocol, thresholds,
                       exposures_est, exposures_ref, catalogs,
                       signatures_est, burden, null_n, null_quantiles, seed,
                       null_n_draws)
}
