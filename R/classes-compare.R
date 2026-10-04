# MsComparison: the result container of ms_compare() (U-M4-01;
# CAPABILITY-MATRIX L-F, design memo docs/devlog/2026-10-04-M4-01-design-memo.md).
#
# metrics:   named list of k_est x k_ref similarity matrices (dimnames kept);
# hungarian: data.frame sweep (one row per threshold) + classification table
#            under attr(..., "classes"), or NULL when the protocol is off;
# islam:     data.frame sweep (greedy max-cosine protocol), or NULL;
# jiang:     list of activity-matching counts/scores (or NULL) -- the
#            bbaf042 fit-evaluation protocol, exposure-driven;
# null:      named list of null evaluations (signature/catalog families),
#            or NULL;
# meta:      named list of protocol version, package version, thresholds,
#            seed and parameter echoes (reproducibility header).

#' MsComparison: signature comparison results
#'
#' An [MsComparison] stores the output of [ms_compare()]: the pairwise
#' similarity `metrics`, the matched-protocol tables (`hungarian`, `islam`,
#' `jiang`) and the null-distribution evaluations (`null`) that carry the
#' zero-calibration of the cosine. Violations raise
#' `msuiter_error_comparison`.
#'
#' @param metrics named list of numeric matrices (k_est x k_ref).
#' @param hungarian,islam data.frame protocol sweeps, or NULL.
#' @param jiang named list of Jiang-protocol results, or NULL.
#' @param null named list of null evaluations, or NULL.
#' @param meta named list of reproducibility metadata.
#'
#' @export
MsComparison <- S7::new_class(
  "MsComparison",
  package = "msuiter",
  properties = list(
    metrics = S7::new_property(S7::class_list),
    hungarian = S7::new_property(S7::class_any),
    islam = S7::new_property(S7::class_any),
    jiang = S7::new_property(S7::class_any),
    null = S7::new_property(S7::class_any),
    meta = S7::new_property(S7::class_list)
  ),
  validator = function(self) msuiter_validate_comparison(self)
)

msuiter_validate_comparison <- function(self) {
  metrics <- self@metrics
  if (!is.list(metrics) || length(metrics) == 0L ||
      (is.null(names(metrics)) || any(!nzchar(names(metrics))))) {
    msuiter_abort(
      "comparison",
      "comparison metrics must be a named non-empty list",
      i = "each entry is a k_est x k_ref similarity matrix",
      j = paste0("received: ", class(metrics)[1L]),
      c = "pass the metrics list returned by ms_compare()"
    )
  }
  for (nm in names(metrics)) {
    mat <- metrics[[nm]]
    if (!is.numeric(mat) || !is.matrix(mat)) {
      msuiter_abort(
        "comparison",
        sprintf("metric '%s' must be a numeric matrix", nm),
        i = "metrics are k_est x k_ref pairwise similarity matrices",
        j = paste0("received: ", class(mat)[1L]),
        c = "pass the metrics list returned by ms_compare()"
      )
    }
  }
  for (nm in c("hungarian", "islam")) {
    tab <- if (nm == "hungarian") self@hungarian else self@islam
    if (!is.null(tab) && !is.data.frame(tab)) {
      msuiter_abort(
        "comparison",
        sprintf("'%s' must be a data.frame or NULL", nm),
        i = "protocol sweeps are tidy per-threshold tables",
        j = paste0("received: ", class(tab)[1L]),
        c = "pass the slots assembled by ms_compare()"
      )
    }
  }
  for (nm in c("jiang", "null")) {
    lst <- if (nm == "jiang") self@jiang else self@null
    if (!is.null(lst) && (!is.list(lst) || is.null(names(lst)))) {
      msuiter_abort(
        "comparison",
        sprintf("'%s' must be a named list or NULL", nm),
        i = "the protocol/null results are named for reproducibility",
        j = paste0("received: ", class(lst)[1L]),
        c = "pass the slots assembled by ms_compare()"
      )
    }
  }
  if (!is.list(self@meta)) {
    msuiter_abort(
      "comparison",
      "meta must be a list",
      i = "meta carries the reproducibility header",
      j = paste0("received: ", class(self@meta)[1L]),
      c = "pass the meta list assembled by ms_compare()"
    )
  }
  NULL
}

#' Construct an MsComparison object
#'
#' Builds and validates an [MsComparison]. The usual constructor is
#' [ms_compare()].
#'
#' @inheritParams MsComparison
#' @return An [MsComparison] object.
#' @export
ms_comparison <- function(metrics, hungarian = NULL, islam = NULL,
                          jiang = NULL, null = NULL, meta = list()) {
  MsComparison(
    metrics = metrics, hungarian = hungarian, islam = islam,
    jiang = jiang, null = null, meta = meta
  )
}

# One-line print/format: metric names + the protocols actually present.
S7::method(format, MsComparison) <- function(x, ...) {
  protocols <- c(
    hungarian = !is.null(x@hungarian),
    islam = !is.null(x@islam),
    jiang = !is.null(x@jiang)
  )
  sprintf(
    "<MsComparison> metrics: %s | protocols: %s",
    paste(names(x@metrics), collapse = ","),
    if (any(protocols)) paste(names(protocols)[protocols], collapse = "+") else "none"
  )
}

S7::method(print, MsComparison) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
