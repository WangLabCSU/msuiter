# ms_select_k() K arbitration and the D16 default pipeline (U-M2-03).
#
# The Rust side pins the pipeline kernel (src/rust/src/pipeline.rs:
# separable recovery, determinism, thread invariance, structured errors);
# this file replays the arbitration layers through the real FFI: a
# separable 48 x 9 truth with k_true = 3 on the grid 2:5 must select the
# true rank (layer-1 CV argmin at 3, layer-2 veto passing there, over-split
# ranks 4/5 vetoed), the evidence table must carry the memo schema, and the
# undecidable/degrade branches must behave per the design memo (section 3).

# ---------------------------------------------------------------------------
# D16 default path: ms_extract(method = NULL)
# ---------------------------------------------------------------------------

test_that("the default ms_extract() path assembles the pipeline evidence", {
  fixture <- .ms_kselect_fixture()
  sig <- ms_extract(fixture$catalog, 3)

  expect_is_ms(sig, "MsSignature")
  expect_identical(sig@engine, "nmf-pipeline")
  expect_identical(sig@seed, 1)

  # reconstruction gate + display normalization (same convention as the
  # single-method path)
  recon <- sig@signatures %*% sig@exposures
  expect_true(.ms_cos(recon, fixture$catalog@counts) >= 0.98)
  expect_true(all(abs(colSums(sig@signatures) - 1) < 1e-9))
  expect_true(all(sig@exposures >= 0))
  expect_identical(dim(sig@signatures), c(48L, 3L))
  expect_identical(dim(sig@exposures), c(3L, 9L))
  expect_identical(colnames(sig@signatures), c("Sig1", "Sig2", "Sig3"))
  expect_identical(rownames(sig@exposures), c("Sig1", "Sig2", "Sig3"))
  expect_identical(colnames(sig@exposures), fixture$catalog@samples)

  # stability slot: consensus statistics + frozen hyper-parameters
  st <- sig@stability
  expect_setequal(
    names(st),
    c(
      "avg_stability", "per_signature_stability", "n_replicates",
      "consensus_restarts", "best_restart", "n_rounds", "converged",
      "hyper_parameters"
    )
  )
  expect_true(st$avg_stability > 0.9) # separable truth: replicates agree
  expect_identical(st$n_replicates, 8L) # the frozen package default
  expect_identical(st$consensus_restarts, 50L) # upstream restart default
  expect_identical(st$hyper_parameters$k_folds, 10L)
  expect_identical(st$hyper_parameters$n_seeds, 10L)
  expect_identical(names(st$per_signature_stability), c("Sig1", "Sig2", "Sig3"))

  # k_evidence: single row for the extracted rank, memo schema columns
  ev <- sig@k_evidence
  expect_identical(nrow(ev), 1L)
  expect_setequal(
    names(ev),
    c(
      "k", "cv_test_deviance", "cv_test_mse", "cv_train_mse",
      "fold_test_deviance", "n_seeds_converged", "avg_stability",
      "min_cluster_stability", "per_signature_stability",
      "wilcoxon_p_vs_prev", "wilcoxon_l2_median_delta", "passes_veto",
      "is_argmin", "selected", "veto_reason"
    )
  )
  expect_identical(ev$k, 3L)
  expect_true(is.finite(ev$cv_test_deviance))
  expect_identical(length(ev$fold_test_deviance[[1]]), 10L) # k_folds = 10
  # the mse columns are the deviance over m*n (sqrt): cross-checked
  expect_equal(
    ev$cv_test_mse,
    sqrt(ev$cv_test_deviance / (48 * 9)),
    tolerance = 1e-12
  )
  # diagnostic-layer placeholders (deliberate divergence, PI ruling)
  expect_true(is.na(ev$wilcoxon_p_vs_prev))
  expect_true(is.na(ev$wilcoxon_l2_median_delta))
  expect_true(is.na(ev$n_seeds_converged))
})

test_that("the default pipeline is deterministic and degrades with a warning", {
  fixture <- .ms_kselect_fixture()
  # k = 2 under-fits this 3-signature truth: the single evaluated rank
  # fails the stability veto, so the default path takes the documented
  # degrade branch (argmin + warning, memo section 3) -- pinned here
  # end to end, warning included.
  expect_warning(
    a <- ms_extract(fixture$catalog, 2),
    regexp = "undecidable"
  )
  expect_warning(
    b <- ms_extract(fixture$catalog, 2),
    regexp = "undecidable"
  )
  expect_identical(a, b)
  expect_true(a@k_evidence$selected[a@k_evidence$k == 2L])
})

test_that("the assembly twin: kernel raw factors, threads and the R object agree", {
  fixture <- .ms_kselect_fixture()
  cat1 <- fixture$catalog
  sig <- ms_extract(cat1, 3)

  # The same pipeline call at the default hyper-parameters, raw.
  raw <- .ms_pipeline_rust(
    cat1@counts, k = 3, replicates = 8L, max_iter = 200L, seed = 1,
    k_folds = 10L, n_seeds = 10L
  )
  # Thread-count invariance end to end: a 1-thread pool must return the
  # bit-identical pipeline (A7 through the whole assembly).
  one <- withr::with_options(
    list(msuiter.threads = 1L),
    .ms_pipeline_rust(
      cat1@counts, k = 3, replicates = 8L, max_iter = 200L, seed = 1,
      k_folds = 10L, n_seeds = 10L
    )
  )
  expect_identical(raw$consensus_W, one$consensus_W)
  expect_identical(raw$nnls_exposures, one$nnls_exposures)
  expect_identical(raw$cv_per_rank, one$cv_per_rank)

  # Twin reconstruction: the assembled (display-normalized) matrices
  # reproduce the kernel's raw W*H up to floating-point rounding.
  recon_raw <- unname(raw$consensus_W %*% raw$nnls_exposures)
  recon_obj <- unname(sig@signatures %*% sig@exposures)
  expect_equal(recon_obj, recon_raw, tolerance = 1e-8)

  # The pipeline refit recovers the separable truth as well as the
  # single-method path does (W-reconstruction consistency across paths).
  single <- ms_extract(cat1, 3, ms_nmf(max_iter = 300))
  recon_single <- single@signatures %*% single@exposures
  expect_true(.ms_cos(recon_raw, cat1@counts) >= 0.98)
  expect_true(.ms_cos(recon_single, cat1@counts) >= 0.98)
})

# ---------------------------------------------------------------------------
# ms_select_k(): three-layer arbitration over the rank grid
# ---------------------------------------------------------------------------

test_that("ms_select_k() selects the true rank on a separable grid 2:5", {
  fixture <- .ms_kselect_fixture()
  out <- do.call(
    ms_select_k,
    c(list(fixture$catalog, 2:5), fixture[c("replicates", "max_iter", "seed", "k_folds", "n_seeds")])
  )
  expect_identical(out$k, 3L)

  ev <- out$k_evidence
  expect_identical(nrow(ev), 4L)
  expect_identical(ev$k, 2:5)
  # memo schema, in order
  expect_identical(
    names(ev),
    c(
      "k", "cv_test_deviance", "cv_test_mse", "cv_train_mse",
      "fold_test_deviance", "n_seeds_converged", "avg_stability",
      "min_cluster_stability", "per_signature_stability",
      "wilcoxon_p_vs_prev", "wilcoxon_l2_median_delta", "passes_veto",
      "is_argmin", "selected", "veto_reason"
    )
  )
  # layer 1: the CV argmin is the true rank
  expect_true(ev$is_argmin[ev$k == 3L])
  expect_identical(sum(ev$is_argmin), 1L)
  # layer 2: the true rank passes the veto, the over-split ranks fail
  expect_true(ev$passes_veto[ev$k == 3L])
  expect_false(any(ev$passes_veto[ev$k %in% c(4L, 5L)]))
  expect_identical(ev$veto_reason[ev$k == 3L], "")
  expect_match(ev$veto_reason[ev$k == 4L], "stability")
  # selection: argmin passes -> selected, exactly one row
  expect_true(ev$selected[ev$k == 3L])
  expect_identical(sum(ev$selected), 1L)
  # per-fold list column has one entry per fold, finite on the true rank
  expect_identical(length(ev$fold_test_deviance[[which(ev$k == 3L)]]), 5L)
  expect_true(all(is.finite(ev$fold_test_deviance[[which(ev$k == 3L)]])))
  # mse columns cross-check against the deviance
  expect_equal(
    ev$cv_test_mse[ev$k == 3L],
    sqrt(ev$cv_test_deviance[ev$k == 3L] / (48 * 9)),
    tolerance = 1e-12
  )
  # diagnostic placeholders
  expect_true(all(is.na(ev$wilcoxon_p_vs_prev)))
})

test_that("the grid CV curve is identical to the per-rank calls (widest-call source)", {
  fixture <- .ms_kselect_fixture()
  cat1 <- fixture$catalog
  hyper <- fixture[c("replicates", "max_iter", "seed", "k_folds", "n_seeds")]
  out <- do.call(ms_select_k, c(list(cat1, 2:5), hyper))
  wide <- do.call(
    .ms_pipeline_rust,
    c(list(cat1@counts, k = 5L), hyper)
  )
  curve <- wide$cv_per_rank
  curve[is.nan(curve)] <- NA_real_
  expect_equal(out$k_evidence$cv_test_deviance, curve[2:5])
})

test_that("cv = FALSE demotes layer 1 and arbitrates on the veto alone", {
  fixture <- .ms_kselect_fixture()
  out <- do.call(
    ms_select_k,
    c(list(fixture$catalog, 2:5, cv = FALSE),
      fixture[c("replicates", "max_iter", "seed", "k_folds", "n_seeds")])
  )
  ev <- out$k_evidence
  # layer 1 absent: CV columns NA, no argmin; the veto alone selects
  expect_true(all(is.na(ev$cv_test_deviance)))
  expect_true(all(is.na(ev$cv_test_mse)))
  expect_false(any(ev$is_argmin))
  expect_true(ev$selected[ev$k == 3L])
  expect_identical(out$k, 3L)
})

# ---------------------------------------------------------------------------
# Arbitration unit paths on synthetic evidence tables (no pipeline runs)
# ---------------------------------------------------------------------------

.ms_make_ev <- function(cv, avg, mn, k = seq_along(cv)) {
  n <- length(k)
  ev <- data.frame(
    k = as.integer(k),
    cv_test_deviance = cv,
    cv_test_mse = sqrt(cv),
    cv_train_mse = sqrt(cv / 2),
    avg_stability = avg,
    min_cluster_stability = mn,
    passes_veto = mapply(.ms_veto_reason, avg, mn, USE.NAMES = FALSE) == "",
    is_argmin = seq_len(n) == which.min(cv), # layer-1 evidence
    selected = rep(FALSE, n),
    veto_reason = mapply(.ms_veto_reason, avg, mn, USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
  # list columns are assigned post-construction (the same pattern as
  # .ms_k_evidence_frame): one fold triple and one stability pair per row.
  ev$fold_test_deviance <- rep(list(rep(1, 3)), n)
  ev$n_seeds_converged <- NA_integer_
  ev$per_signature_stability <- rep(list(c(1, 1)), n)
  ev$wilcoxon_p_vs_prev <- NA_real_
  ev$wilcoxon_l2_median_delta <- NA_real_
  ev[, msuiter:::.ms_k_evidence_columns]
}

test_that("veto thresholds reject each violated clause and accept the boundary", {
  # clause golden: avg/min/sum thresholds each produce their reason
  expect_match(.ms_veto_reason(0.7, 0.5), "avg_stability")
  expect_match(.ms_veto_reason(0.9, 0.1), "min_cluster_stability")
  expect_match(.ms_veto_reason(0.75, 0.2), "avg \\+ min_cluster_stability")
  expect_match(.ms_veto_reason(0.7, 0.1), "avg_stability.*min_cluster_stability")
  expect_identical(.ms_veto_reason(0.8, 0.2), "") # boundary is inclusive
  expect_match(.ms_veto_reason(NA_real_, 0.5), "unavailable")
})

test_that("a vetoed argmin falls back in CV-error order (memo layer 2)", {
  # k=3 is the CV argmin but fails the veto; k=1 also fails; the first
  # CV-ascending rank that passes is k=2.
  ev <- .ms_make_ev(
    cv = c(10, 20, 5, 30, 40),
    avg = c(0.7, 0.9, 0.5, 0.9, 0.95),
    mn = c(0.5, 0.5, 0.1, 0.5, 0.5)
  )
  out <- .ms_k_arbitrate(ev, cv = TRUE, explicit = TRUE)
  expect_true(out$is_argmin[3L]) # row k=3 is the CV minimum
  expect_true(out$selected[2L]) # first CV-ascending passing rank (k=2)
  expect_identical(sum(out$selected), 1L)
})

test_that("cv-ties keep the lowest rank and cv=FALSE scans k ascending", {
  ev <- .ms_make_ev(
    cv = c(10, 10, 10),
    avg = c(0.9, 0.9, 0.9),
    mn = c(0.5, 0.5, 0.5)
  )
  out <- .ms_k_arbitrate(ev, cv = TRUE, explicit = TRUE)
  expect_true(out$is_argmin[1L]) # first minimum = lowest rank
  expect_true(out$selected[1L])

  # cv = FALSE: layer 1 absent, pure k-ascending veto scan
  ev2 <- .ms_make_ev(
    cv = c(50, 10, 20),
    avg = c(0.5, 0.9, 0.95),
    mn = c(0.1, 0.5, 0.5)
  )
  out2 <- .ms_k_arbitrate(ev2, cv = FALSE, explicit = TRUE)
  expect_false(any(out2$is_argmin))
  expect_true(out2$selected[2L])
})

test_that("an undecidable grid errors explicitly and degrades with a warning in the pipeline", {
  ev <- .ms_make_ev(
    cv = c(10, 20),
    avg = c(0.3, 0.4),
    mn = c(0.1, 0.1)
  )
  cnd <- expect_ms_error(.ms_k_arbitrate(ev, cv = TRUE, explicit = TRUE), "kselect")
  expect_true(!is.null(cnd$k_evidence))
  expect_identical(nrow(cnd$k_evidence), 2L)

  expect_warning(
    out <- .ms_k_arbitrate(ev, cv = TRUE, explicit = FALSE),
    regexp = "veto"
  )
  expect_true(out$selected[1L]) # argmin fallback
})

# ---------------------------------------------------------------------------
# Error paths
# ---------------------------------------------------------------------------

test_that("the rank grid is validated with structured input errors", {
  fixture <- .ms_kselect_fixture()
  cat1 <- fixture$catalog
  hyper <- fixture[c("replicates", "max_iter", "seed", "k_folds", "n_seeds")]
  expect_ms_error(
    do.call(ms_select_k, c(list(cat1, integer(0)), hyper)),
    "input"
  )
  expect_ms_error(do.call(ms_select_k, c(list(cat1, 0), hyper)), "input")
  expect_ms_error(do.call(ms_select_k, c(list(cat1, 2.5), hyper)), "input")
  expect_ms_error(do.call(ms_select_k, c(list(cat1, NA_integer_), hyper)), "input")
  expect_ms_error(do.call(ms_select_k, c(list(cat1, 48.5), hyper)), "input")
  expect_ms_error(
    do.call(ms_select_k, c(list(cat1, c(2, 200)), hyper)),
    "input",
    regexp = "min\\(channels, samples\\)"
  )
  # k_folds beyond the channel count (SUITOR precondition); the override
  # replaces the fixture's k_folds instead of duplicating it
  expect_ms_error(
    do.call(
      ms_select_k,
      c(list(cat1, 2:3, k_folds = 100L), hyper[setdiff(names(hyper), "k_folds")])
    ),
    "input",
    regexp = "channel count"
  )
  # bad cv flag / bad scalars (overrides replace their fixture entry)
  expect_ms_error(
    do.call(ms_select_k, c(list(cat1, 2:3, cv = NA), hyper)), "input"
  )
  expect_ms_error(
    do.call(
      ms_select_k,
      c(list(cat1, 2:3, replicates = 1L), hyper[setdiff(names(hyper), "replicates")])
    ),
    "input"
  )
  expect_ms_error(
    do.call(
      ms_select_k,
      c(list(cat1, 2:3, max_iter = 0L), hyper[setdiff(names(hyper), "max_iter")])
    ),
    "input"
  )
  # dots are argument-spelling errors
  expect_ms_error(
    do.call(ms_select_k, c(list(cat1, 2:3), hyper, list(foo = 1))),
    "input",
    regexp = "unknown argument"
  )
})

test_that("non-catalog input falls back to a structured input error", {
  expect_ms_error(ms_select_k(data.frame(), 2:3), "input")
})

test_that("the pipeline FFI wrapper validates scalars before the boundary", {
  fixture <- .ms_kselect_fixture()
  counts <- fixture$catalog@counts
  expect_error(
    .ms_pipeline_rust(counts, k = 0, replicates = 4, max_iter = 10, seed = 1, k_folds = 3, n_seeds = 2),
    class = "msuiter_error_input"
  )
  expect_error(
    .ms_pipeline_rust(counts, k = 2, replicates = 1, max_iter = 10, seed = 1, k_folds = 3, n_seeds = 2),
    class = "msuiter_error_input",
    regexp = "replicates"
  )
  expect_error(
    .ms_pipeline_rust(counts, k = 2, replicates = 4, max_iter = 0, seed = 1, k_folds = 3, n_seeds = 2),
    class = "msuiter_error_input"
  )
  expect_error(
    .ms_pipeline_rust(counts, k = 2, replicates = 4, max_iter = 10, seed = -1, k_folds = 3, n_seeds = 2),
    class = "msuiter_error_input"
  )
  expect_error(
    .ms_pipeline_rust(counts, k = 2, replicates = 4, max_iter = 10, seed = 1, k_folds = 1, n_seeds = 2),
    class = "msuiter_error_input"
  )
  expect_error(
    .ms_pipeline_rust(counts, k = 2, replicates = 4, max_iter = 10, seed = 1, k_folds = 3, n_seeds = 0),
    class = "msuiter_error_input"
  )
  expect_error(
    .ms_pipeline_rust(counts * NA_real_, k = 2, replicates = 4, max_iter = 10, seed = 1, k_folds = 3, n_seeds = 2),
    class = "msuiter_error_na"
  )
  # kernel-side rank bound: k > min(m, n) surfaces as a structured rust error
  cnd <- tryCatch(
    .ms_pipeline_rust(counts, k = 10, replicates = 4, max_iter = 10, seed = 1, k_folds = 3, n_seeds = 2),
    error = function(e) e
  )
  expect_s3_class(cnd, "msuiter_error_rust")
  expect_identical(cnd$topic, "argument")
})
