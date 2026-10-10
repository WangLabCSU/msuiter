# MsBenchmark: the mlr3-style benchmark grid result container.
#
# results: tidy score tibble with the yardstick-like columns
#   .engine / .scenario / .metric / .estimate; settings: named list of the
#   benchmark configuration (seeds, grid, ...).

#' MsBenchmark: benchmark grid results
#'
#' An [MsBenchmark] stores the score table of an engine x scenario grid:
#' one row per engine/scenario/metric with the columns `.engine`,
#' `.scenario`, `.metric` (character) and `.estimate` (numeric), plus the
#' benchmark `settings`. Violations raise `msuiter_error_benchmark`.
#'
#' @param results data.frame with the score columns described above.
#' @param settings named list of benchmark settings.
#'
#' @export
MsBenchmark <- S7::new_class(
  "MsBenchmark",
  package = "msuiter",
  properties = list(
    results = S7::new_property(S7::class_any),
    settings = S7::new_property(S7::class_list)
  ),
  validator = function(self) msuiter_validate_benchmark(self)
)

msuiter_validate_benchmark <- function(self) {
  results <- self@results
  if (!is.data.frame(results)) {
    msuiter_abort(
      "benchmark",
      "benchmark results must be a data.frame",
      i = "results follow the yardstick-style score tibble layout",
      j = paste0("received: ", class(results)[1L]),
      c = "pass the score tibble returned by ms_benchmark()"
    )
  }
  required <- c(".engine", ".scenario", ".metric", ".estimate")
  absent <- setdiff(required, names(results))
  if (nrow(results) > 0L && length(absent) > 0L) {
    msuiter_abort(
      "benchmark",
      "benchmark results are missing score columns",
      i = paste0("required columns: ", paste(required, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "score the grid into the standard column layout"
    )
  }
  if (nrow(results) > 0L) {
    for (nm in c(".engine", ".scenario", ".metric")) {
      v <- results[[nm]]
      if (!is.character(v) || anyNA(v) || any(!nzchar(v))) {
        msuiter_abort(
          "benchmark",
          sprintf("column '%s' must be character without NA or empty strings", nm),
          i = "engine/scenario/metric are the grid identities",
          j = paste0("received: ", class(v)[1L]),
          c = "keep identity columns as plain labels"
        )
      }
    }
    est <- results$.estimate
    if (!is.numeric(est) || anyNA(est)) {
      msuiter_abort(
        "benchmark",
        "column '.estimate' must be numeric without NA",
        i = "each grid cell carries exactly one estimate per metric",
        j = paste0("received: ", class(est)[1L], " with anyNA = ", anyNA(est)),
        c = "drop cells without estimates or report them as a separate metric"
      )
    }
  }
  settings <- self@settings
  if (!is.list(settings) || (!is.null(names(settings)) && any(!nzchar(names(settings))))) {
    msuiter_abort(
      "benchmark",
      "benchmark settings must be a (named) list",
      i = "settings carry the benchmark configuration for reproducibility",
      j = paste0("received: ", class(settings)[1L]),
      c = "pass seeds/grid/protocol as a named list"
    )
  }
  NULL
}

#' Construct an MsBenchmark object
#'
#' Builds and validates an [MsBenchmark]. Create specs with
#' [ms_benchmark_grid()], execute with [ms_run_benchmark()], store via
#' `ms_benchmark()` -- the trio stays three separate functions by the
#' U-M7-04 ergonomics ruling (no generic merge).
#'
#' @family benchmark
#'
#' @inheritParams MsBenchmark
#' @return An [MsBenchmark] object.
#' @examples
#' results <- data.frame(
#'   .engine = c("e1", "e2"), .scenario = c("sc1", "sc1"),
#'   .metric = c("f1", "f1"), .estimate = c(0.9, 0.7)
#' )
#' ms_benchmark(results, settings = list(seed = 1))
#' @export
ms_benchmark <- function(results, settings = list()) {
  out <- MsBenchmark(results = results, settings = settings)
  out
}

# One-line print/format: class name / result count.
S7::method(format, MsBenchmark) <- function(x, ...) {
  sprintf("<MsBenchmark> %d results", nrow(x@results))
}

S7::method(print, MsBenchmark) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
