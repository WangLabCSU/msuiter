# kselect-select.R: the default K-arbitration surface ms_select_k()
# (U-M2-03; ARCHITECTURE.md sections 3.1/5, design memo
# docs/devlog/2026-09-30-M2-pipeline-design-memo.md section 3).
#
# Three-layer arbitration over a rank grid, evaluated on pipeline evidence
# (one ms_pipeline_rust call per rank: consensus stability at that rank +
# the SUITOR CV curve that spans the grid):
#
#   layer 1 -- SUITOR argmin: k* = argmin_k CV.te (first minimum, i.e. the
#              lowest rank on ties; the CV columns can be switched off with
#              cv = FALSE, which demotes the arbitration to layer 2 alone);
#   layer 2 -- stability veto, thresholds = the documented upstream
#              defaults (SigProfiler sigpro.py:352-354, memo section 3 --
#              referenced, not recalibrated): avg >= 0.8 AND
#              min_cluster >= 0.2 AND avg + min >= 1.0. A vetoed k* falls
#              back to the first rank in CV-error ascending order (lowest
#              rank on ties; k ascending when cv = FALSE) that passes;
#   layer 3 -- Wilcoxon: DIAGNOSTIC ONLY (deliberate divergence, PI
#              ruling: upstream SigProfiler lets ranksums p < 0.05 steer
#              the search; we do not). The evidence columns
#              wilcoxon_p_vs_prev / wilcoxon_l2_median_delta are honest
#              NA placeholders in this unit.
#
# Undecidable grids: explicit ms_select_k() calls ERROR
# (msuiter_error_kselect, full evidence table attached); the default
# ms_extract() path is degrade-to-argmin (its k is user-fixed anyway, so
# the arbitration there only annotates the evidence table).
#
# All violations raise msuiter_error_* conditions; bare stop() is banned.

# Veto thresholds: the upstream documented defaults (memo section 3 --
# "上游默认值的引用，非我方校准声明"; any recalibration goes through the
# D13 four-piece review before entering the contract).
.MS_VETO_AVG_MIN <- 0.8
.MS_VETO_CLUSTER_MIN <- 0.2
.MS_VETO_SUM_MIN <- 1.0

# The k_evidence column schema (memo section 3). Order is contractual:
# tests pin it as the evidence-table surface.
.ms_k_evidence_columns <- c(
  "k", "cv_test_deviance", "cv_test_mse", "cv_train_mse",
  "fold_test_deviance", "n_seeds_converged", "avg_stability",
  "min_cluster_stability", "per_signature_stability",
  "wilcoxon_p_vs_prev", "wilcoxon_l2_median_delta", "passes_veto",
  "is_argmin", "selected", "veto_reason"
)

# Layer-2 flag + reason for one rank from its consensus stability stats.
# NA stability (a degenerate consensus) fails the veto conservatively.
.ms_veto_reason <- function(avg_stability, min_cluster_stability) {
  if (length(avg_stability) != 1L || is.na(avg_stability) ||
    length(min_cluster_stability) != 1L || is.na(min_cluster_stability)) {
    return("stability statistics unavailable")
  }
  reasons <- character(0)
  if (avg_stability < .MS_VETO_AVG_MIN) {
    reasons <- c(reasons, sprintf("avg_stability %.4g < %.1f", avg_stability, .MS_VETO_AVG_MIN))
  }
  if (min_cluster_stability < .MS_VETO_CLUSTER_MIN) {
    reasons <- c(reasons, sprintf(
      "min_cluster_stability %.4g < %.1f", min_cluster_stability, .MS_VETO_CLUSTER_MIN
    ))
  }
  if (avg_stability + min_cluster_stability < .MS_VETO_SUM_MIN) {
    reasons <- c(reasons, sprintf(
      "avg + min_cluster_stability %.4g < %.1f",
      avg_stability + min_cluster_stability, .MS_VETO_SUM_MIN
    ))
  }
  if (length(reasons) == 0L) "" else paste(reasons, collapse = "; ")
}

# Build the memo-schema evidence frame.
#
#   grid      ascending unique integer ranks (the evidence rows)
#   res_by_k  named list (character(k)) of pipeline results, one per grid
#             rank -- the stability source for that row
#   full      the pipeline result whose CV curve spans 1..max(grid); the
#             CV source for every row (the curve of a rank-k call covers
#             1..k and is seed/fold/rank-determined, so values taken from
#             the widest call equal the values any narrower call reports)
#   n_cells   m*n of the source catalog (the MSErr denominators)
#   k_folds   effective fold count (the training MSErr denominator)
#   cv        FALSE demotes every CV column to NA (memo section 3: layer 1
#             absent)
.ms_k_evidence_frame <- function(grid, res_by_k, full, n_cells, k_folds,
                                 cv = TRUE, counts = NULL) {
  n <- length(grid)
  cv_te <- rep(NA_real_, n)
  cv_tr <- rep(NA_real_, n)
  folds_list <- vector("list", n)
  is_argmin <- rep(FALSE, n)
  if (isTRUE(cv)) {
    curve <- full$cv_per_rank
    curve[is.nan(curve)] <- NA_real_
    curve_tr <- full$cv_per_rank_train
    curve_tr[is.nan(curve_tr)] <- NA_real_
    # The FFI vector is rank-major (cv.rs aggregate fills ranks × folds in
    # rank order); matrix() defaults to column-major fill, which scrambles
    # every row whose rank differs from k_folds (audited P1-1). byrow=TRUE
    # restores rank-major row semantics.
    fold_mat <- matrix(full$fold_test_deviance, nrow = length(curve),
      ncol = k_folds, byrow = TRUE)
    fold_mat[is.nan(fold_mat)] <- NA_real_
    for (i in seq_len(n)) {
      rk <- grid[i]
      if (rk <= length(curve)) {
        cv_te[i] <- curve[rk]
        cv_tr[i] <- curve_tr[rk]
        folds_list[[i]] <- fold_mat[rk, ]
      }
    }
    # Layer-1 evidence: first minimum of the finite curve = lowest rank on
    # ties (upstream which.min semantics).
    if (any(!is.na(curve))) {
      ord <- order(curve, seq_along(curve), na.last = NA)
      argmin_rank <- ord[1L]
      is_argmin[grid == argmin_rank] <- TRUE
    }
  } else {
    for (i in seq_len(n)) folds_list[[i]] <- rep(NA_real_, k_folds)
  }

  avg <- rep(NA_real_, n)
  mn <- rep(NA_real_, n)
  per_sig <- vector("list", n)
  wx_p <- rep(NA_real_, n)
  wx_med <- rep(NA_real_, n)
  prev_resid <- NULL
  for (i in seq_len(n)) {
    res <- res_by_k[[as.character(grid[i])]]
    avg[i] <- res$avg_stability
    stab <- res$stability_per_cluster
    mn[i] <- min(stab)
    per_sig[[i]] <- stab
    # Layer-3 diagnostic (deliberate divergence, PI ruling 2026-09-30):
    # paired signed-rank of the per-sample L2 refit residuals between the
    # previous and the current grid rank, on the RAW consensus W and its
    # RAW NNLS refit (the reconstruction is conserved, so the residual is
    # well-defined). DIAGNOSTIC ONLY -- it never arbitrates.
    if (!is.null(counts)) {
      resid <- sqrt(colSums((counts - res$consensus_W %*% res$nnls_exposures)^2))
      wx_med[i] <- stats::median(resid)
      if (!is.null(prev_resid) && length(resid) == length(prev_resid)) {
        d <- resid - prev_resid
        wx_p[i] <- if (all(d == 0)) NA_real_ else
          suppressWarnings(stats::wilcox.test(d, correct = FALSE,
            exact = FALSE)$p.value)
      }
      prev_resid <- resid
    }
  }

  ev <- data.frame(
    k = as.integer(grid),
    cv_test_deviance = cv_te,
    cv_test_mse = ifelse(is.na(cv_te), NA_real_, sqrt(cv_te / n_cells)),
    cv_train_mse = ifelse(is.na(cv_tr), NA_real_, sqrt(cv_tr / (n_cells * (k_folds - 1L)))),
    avg_stability = avg,
    min_cluster_stability = mn,
    passes_veto = NA,
    is_argmin = is_argmin,
    selected = FALSE,
    stringsAsFactors = FALSE
  )
  ev$fold_test_deviance <- folds_list
  # ECM convergence per seed is not yet surfaced by the CV kernel
  # (engine/cv.rs aggregates errors only): honest placeholder, documented.
  ev$n_seeds_converged <- NA_integer_
  ev$per_signature_stability <- per_sig
  # Wilcoxon layer: diagnostic-only by PI ruling -- real values when the
  # per-rank fits are available, NA at the first rank (no previous fit).
  ev$wilcoxon_p_vs_prev <- wx_p
  # The median per-sample residual AT this rank (the "l2 median" of the
  # schema); the paired delta against the previous rank is the p column.
  ev$wilcoxon_l2_median_delta <- wx_med
  ev$veto_reason <- mapply(.ms_veto_reason, avg, mn, USE.NAMES = FALSE)
  ev$passes_veto <- !nzchar(ev$veto_reason)
  ev[, .ms_k_evidence_columns]
}

# The three-layer arbitration (module docs). Mutates is_argmin (reset from
# the CV evidence), passes_veto, veto_reason and selected.
#
#   cv        layer-1 switch (FALSE = veto-only arbitration)
#   explicit  TRUE = ms_select_k() surface: an undecidable grid (no rank
#             passes the veto) raises msuiter_error_kselect with the full
#             evidence table attached; FALSE = the default-pipeline
#             annotation: degrade to the argmin (or the lowest rank) with
#             a warning, never an error.
.ms_k_arbitrate <- function(ev, cv = TRUE, explicit = TRUE,
                            call = rlang::caller_call()) {
  # Layer-1 evidence arrives in the frame (first minimum of the CV curve,
  # lowest rank on ties); with cv = FALSE the argmin column stays FALSE by
  # definition (layer 1 absent).
  if (!isTRUE(cv)) {
    ev$is_argmin[] <- FALSE
  }

  # Fallback scan order: CV-error ascending (lowest rank on ties, NAs
  # last), or plain k ascending when layer 1 is absent.
  if (isTRUE(cv)) {
    ord <- order(ev$cv_test_deviance, ev$k, na.last = TRUE)
  } else {
    ord <- order(ev$k)
  }

  passing <- which(ev$passes_veto)
  sel_idx <- NULL
  if (any(ev$is_argmin) && ev$passes_veto[which(ev$is_argmin)]) {
    sel_idx <- which(ev$is_argmin)
  } else if (length(passing) > 0L) {
    in_ord <- passing[order(match(passing, ord))]
    sel_idx <- in_ord[1L]
  }

  if (is.null(sel_idx)) {
    if (isTRUE(explicit)) {
      msuiter_abort(
        "kselect",
        "K selection is undecidable: no rank in the grid passes the stability veto",
        i = paste(
          "layer-2 veto (avg >= 0.8, min_cluster >= 0.2, sum >= 1.0) rejected",
          "every candidate rank"
        ),
        j = paste0(
          "veto reasons: ",
          paste(sprintf("k=%d: %s", ev$k, ev$veto_reason), collapse = "; ")
        ),
        c = paste(
          "inspect the attached k_evidence table (condition field), widen",
          "the rank grid, or raise the replicate count"
        ),
        data = list(k_evidence = ev)
      )
    }
    # Default-pipeline degradation (memo section 3): take the argmin (or
    # the lowest rank when layer 1 is absent) and warn.
    fallback <- if (any(ev$is_argmin)) which(ev$is_argmin) else ord[1L]
    sel_idx <- fallback[1L]
    rlang::warn(
      "K selection is undecidable: no rank passes the stability veto; falling back to the CV argmin (evidence table attached to the result)",
      body = c(
        i = "the stability veto rejected every rank in the evaluated grid",
        j = sprintf("falling back to k = %d", ev$k[sel_idx]),
        c = "call ms_select_k() explicitly for the full evidence table"
      )
    )
  }

  ev$selected[sel_idx] <- TRUE
  ev
}

#' Select the number of signatures from a rank grid
#'
#' `ms_select_k()` evaluates the consensus-CV extraction pipeline over a
#' grid of candidate ranks and applies the default three-layer K
#' arbitration (ARCHITECTURE section 5): the SUITOR CV argmin (layer 1),
#' the consensus stability veto (layer 2, upstream default thresholds
#' `avg >= 0.8`, `min_cluster >= 0.2`, sum `>= 1.0`) and a diagnostic-only
#' Wilcoxon layer (layer 3; deliberate divergence from the upstream
#' ranksums-steered search, PI ruling 2026-09-30 -- the diagnostic columns
#' are placeholders in this unit).
#'
#' @param catalog An [MsCatalog] object, as returned by [ms_tally()] or
#'   [ms_catalog()].
#' @param k_grid positive whole-number ranks to evaluate; each must not
#'   exceed `min(nrow(counts), ncol(counts))`. The grid is evaluated in
#'   ascending order.
#' @param replicates single whole number >= 2: ensemble fits per rank
#'   (multi-initialization only, no bootstrap).
#' @param max_iter single positive whole number: KL-NMF iterations per
#'   ensemble fit and ECM rounds per CV unit.
#' @param seed single whole number in [0, 2^31 - 1] seeding every stream.
#' @param k_folds single whole number in [2, nrow(counts)]: SUITOR folds.
#' @param n_seeds single positive whole number: SUITOR seeds per (rank,
#'   fold) -- the documented v0.2 budget divergence from the upstream 30.
#' @param cv single logical: run layer 1? `cv = FALSE` fills the CV
#'   evidence columns with NA and arbitrates on the stability veto alone
#'   (memo section 3). Budget note: the v0.2 kernel face computes the CV
#'   grid inside the pipeline call regardless; `cv = FALSE` currently only
#'   changes the arbitration inputs.
#' @param threads NULL or a single non-negative integer pool size (the
#'   ensemble phase runs on the per-call pool).
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @return A named list with:
#'   * `k`: the selected rank (single positive integer),
#'   * `k_evidence`: the evidence table (data.frame, one row per grid
#'     rank) with the memo schema: `k`, `cv_test_deviance`, `cv_test_mse`,
#'     `cv_train_mse`, `fold_test_deviance` (list column, per-fold held-out
#'     deviance), `n_seeds_converged` (placeholder NA: the CV kernel does
#'     not yet surface per-seed convergence), `avg_stability`,
#'     `min_cluster_stability`, `per_signature_stability` (list column),
#'     `wilcoxon_p_vs_prev` / `wilcoxon_l2_median_delta` (placeholders,
#'     diagnostic layer not implemented), `passes_veto`, `is_argmin`,
#'     `selected`, `veto_reason`.
#'
#'   An undecidable grid (no rank passes the veto) raises
#'   `msuiter_error_kselect` with the full evidence table attached as the
#'   `k_evidence` condition field.
#'
#' @seealso [ms_extract()] for the default extraction at a fixed rank.
#' @export
ms_select_k <- S7::new_generic(
  "ms_select_k",
  "catalog",
  function(catalog, k_grid, replicates = 8L, max_iter = 200L, seed = 1,
           k_folds = 10L, n_seeds = 10L, cv = TRUE, threads = NULL, ...)
    S7::S7_dispatch()
)

# Dots discipline (same rule as ms_extract()).
.ms_select_k_abort_dots <- function(dots) {
  if (length(dots) == 0L) {
    return(invisible(NULL))
  }
  labels <- names(dots)
  if (is.null(labels)) {
    labels <- rep("", length(dots))
  }
  labels[!nzchar(labels)] <- "<positional>"
  msuiter_abort(
    "input",
    "unknown argument passed to ms_select_k()",
    i = "ms_select_k() has no passthrough arguments",
    j = paste0("unexpected: ", msuiter_quote_trunc(labels)),
    c = "check the argument spelling against ?ms_select_k"
  )
}

# Validate the rank grid at the API boundary: positive whole numbers,
# deduplicated, ascending, within min(channels, samples).
.ms_select_k_check_grid <- function(k_grid, counts) {
  label <- "k_grid must be positive whole numbers"
  if (!is.numeric(k_grid) || length(k_grid) < 1L || anyNA(k_grid) ||
    any(!is.finite(k_grid)) || any(k_grid != trunc(k_grid)) || any(k_grid < 1)) {
    msuiter_abort(
      "input",
      label,
      i = "the grid enumerates the candidate signature counts to arbitrate",
      j = paste0("received: ", msuiter_quote_trunc(k_grid)),
      c = "pass e.g. k_grid = 2:5"
    )
  }
  bound <- min(nrow(counts), ncol(counts))
  if (any(k_grid > bound)) {
    msuiter_abort(
      "input",
      sprintf("every k in k_grid must not exceed min(channels, samples) = %d", bound),
      i = "a rank-k NMF needs k <= min(nrow(counts), ncol(counts))",
      j = sprintf("offending k: %s (catalog has %d channels x %d samples)",
        msuiter_quote_trunc(k_grid[k_grid > bound]), nrow(counts), ncol(counts)),
      c = "drop the offending ranks from the grid"
    )
  }
  sort(unique(as.integer(k_grid)))
}

S7::method(ms_select_k, MsCatalog) <- function(catalog, k_grid, replicates = 8L,
                                               max_iter = 200L, seed = 1,
                                               k_folds = 10L, n_seeds = 10L,
                                               cv = TRUE, threads = NULL, ...) {
  .ms_select_k_abort_dots(list(...))

  counts <- catalog@counts
  if (ncol(counts) < 1L) {
    msuiter_abort(
      "input",
      "the catalog has no samples to extract signatures from",
      i = "K selection needs at least one sample column",
      j = sprintf("catalog: %d channels x %d samples", nrow(counts), ncol(counts)),
      c = "tally a non-empty variant set with ms_tally() first"
    )
  }
  if (!is.logical(cv) || length(cv) != 1L || is.na(cv)) {
    msuiter_abort(
      "input",
      "cv must be a single TRUE or FALSE",
      i = "cv switches the SUITOR argmin layer (layer 1) of the arbitration",
      j = paste0("received: ", msuiter_quote_trunc(cv)),
      c = "pass cv = TRUE (default) or cv = FALSE (veto-only arbitration)"
    )
  }
  grid <- .ms_select_k_check_grid(k_grid, counts)
  # SUITOR precondition: every fold must hold out at least one row per
  # column, so k_folds must not exceed the channel count (kernel-side
  # structured error otherwise; the gate here is the user-facing message).
  if (k_folds > nrow(counts)) {
    msuiter_abort(
      "input",
      sprintf("k_folds must not exceed the channel count (%d)", nrow(counts)),
      i = "every fold must hold out at least one row per column (SUITOR precondition)",
      j = sprintf("k_folds = %d, catalog has %d channels", as.integer(k_folds), nrow(counts)),
      c = "lower k_folds"
    )
  }

  # One pipeline call per grid rank: the stability source for that rank's
  # evidence row. The widest call's CV curve spans 1..max(grid) and is
  # seed/fold/rank-determined, so it doubles as the CV source for every
  # row (values equal the narrower calls' curves bit for bit).
  res_by_k <- vector("list", length(grid))
  full <- NULL
  for (i in seq_along(grid)) {
    res <- .ms_pipeline_rust(
      counts = counts, k = grid[i], replicates = replicates,
      max_iter = max_iter, seed = seed, k_folds = k_folds, n_seeds = n_seeds,
      threads = threads
    )
    res_by_k[[i]] <- res
    names(res_by_k)[i] <- as.character(grid[i])
    if (is.null(full) || grid[i] == max(grid)) {
      full <- res
    }
  }

  ev <- .ms_k_evidence_frame(
    grid = grid,
    res_by_k = res_by_k,
    full = full,
    n_cells = nrow(counts) * ncol(counts),
    k_folds = as.integer(k_folds),
    cv = cv,
    counts = counts
  )
  ev <- .ms_k_arbitrate(ev, cv = cv, explicit = TRUE)

  list(k = ev$k[ev$selected][1L], k_evidence = ev)
}

# Fallback: anything that is not an MsCatalog gets a project error instead
# of the raw S7 dispatch failure.
S7::method(ms_select_k, S7::class_any) <- function(catalog, k_grid,
                                                   replicates = 8L, max_iter = 200L,
                                                   seed = 1, k_folds = 10L,
                                                   n_seeds = 10L, cv = TRUE,
                                                   threads = NULL, ...) {
  msuiter_abort(
    "input",
    "catalog must be an MsCatalog object",
    i = "ms_select_k() dispatches on MsCatalog",
    j = paste0("received: ", class(catalog)[1L]),
    c = "build the catalog with ms_tally() first"
  )
}
