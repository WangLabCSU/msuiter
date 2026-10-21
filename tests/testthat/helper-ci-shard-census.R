# Shared executed-work census for the sharded CI lanes (CI restructure,
# 2026-10-21). One reporter class serves every consumer -- the repo-mode
# shard runner (tools/ci/run-testthat-shard.R), the coverage shard runner
# (tools/ci/run-covr-shard.R), and tests/testthat.R when
# MSUITER_SHARD_FILTER asks it to run one shard -- so an attestation line
# means the same thing in every lane:
#
#   MSUITER-ATTEST kind=<k> shard=<n> files=<f> tests=<t> executed=<e>
#                  pass=<p> fail=<x> error=<x> skip=<s> warn=<w> status=<ok|vacuous>
#
# "executed" counts test_that units that survived to a non-skip outcome:
# "an arm that ran no tests gates nothing" -- every strict consumer dies on
# executed == 0. The census is reporter-side (not results-object-side) so
# the counts exist even when stop_on_failure cuts the run short.

# Registry-contract files call msuiter_registry_reset() and the built-in
# engine rows stay wiped until a later file re-arms them; serial alphabet
# happened to interleave a healer, shard composition makes that order an
# adversary. Re-arm the certified rows idempotently at every file boundary
# (the wrappers guard on exists(); same pattern test-m2-e2e.R sanctions).
.ci_rearm_engines <- function() {
  ns <- tryCatch(asNamespace("msuiter"), error = function(e) NULL)
  if (is.null(ns)) return(invisible(NULL))
  for (nm in c("msuiter_register_ard_engine", "msuiter_register_sparse_engine",
               "msuiter_register_nmf_engine")) {
    fn <- tryCatch(get(nm, envir = ns, inherits = FALSE), error = function(e) NULL)
    detail <- if (!is.function(fn)) "not resolvable in the namespace" else tryCatch({
      fn()
      NULL
    }, error = function(e) conditionMessage(e))
    if (!is.null(detail)) {
      try(cat("REARM-DEGRADED[", nm, "]: ", detail, "\n", sep = "",
              file = stderr()), silent = TRUE)
    }
  }
  invisible(NULL)
}

.ci_census_reporter <- function() {
  if (!requireNamespace("R6", quietly = TRUE)) {
    stop("R6 unavailable -- the shard census needs testthat's Reporter base")
  }
  R6::R6Class("MsuiterCensusReporter",
    inherit = testthat::Reporter,
    public = list(
      lane = "suite", shard = NA_integer_, n_file = 0L, n_test = 0L,
      n_pass = 0L, n_fail = 0L, n_error = 0L, n_skip = 0L, n_warn = 0L,
      initialize = function(lane = "suite", shard = NA_integer_) {
        self$lane <- lane
        self$shard <- shard
      },
      start_file = function(file = "") {
        .ci_rearm_engines()
        self$n_file <- self$n_file + 1L
        # stderr, not stdout: a hard halt loses block-buffered stdout (the
        # covr child witnessed this), and these breadcrumbs are the last
        # words of a dead shard -- they must arrive unbuffered.
        try(cat("FILE[", self$lane, "#", self$shard, "] ", basename(file), "\n",
                sep = "", file = stderr()), silent = TRUE)
      },
      start_test = function(context = "", test = "") { self$n_test <- self$n_test + 1L },
      add_result = function(context = "", test = "", result = NULL) {
        # A census that counts failures without naming them is a census that
        # cannot be debugged: defects are LOUD, the detail lands in the shard
        # log beside the attestation that died on them. try()-wrapped -- the
        # print must never be able to eat the count or the run.
        if (inherits(result, "expectation_failure") ||
            inherits(result, "expectation_error")) {
          kind <- if (inherits(result, "expectation_error")) "ERROR" else "FAIL"
          line <- paste0(kind, "[", self$lane, "#", self$shard, "] ", test, "\n",
                         paste0("  : ", sub("\n$", "", conditionMessage(result)),
                                collapse = "\n"), "\n")
          try(cat(line, sep = "", file = stderr()), silent = TRUE)
        }
        if (inherits(result, "expectation_failure")) self$n_fail <- self$n_fail + 1L
        else if (inherits(result, "expectation_error")) self$n_error <- self$n_error + 1L
        else if (inherits(result, "expectation_skip")) self$n_skip <- self$n_skip + 1L
        else if (inherits(result, "expectation_warning")) self$n_warn <- self$n_warn + 1L
        else self$n_pass <- self$n_pass + 1L
      },
      show_status = function() {},
      n_executed = function() {
        as.integer(max(0L, self$n_test - self$n_skip))
      },
      attestation = function() {
        status <- if (self$n_executed() > 0L && self$n_fail == 0L &&
                      self$n_error == 0L) "ok" else "vacuous"
        paste0("MSUITER-ATTEST kind=", self$lane,
               " shard=", if (is.na(self$shard)) "-" else self$shard,
               " files=", self$n_file, " tests=", self$n_test,
               " executed=", self$n_executed(), " pass=", self$n_pass,
               " fail=", self$n_fail, " error=", self$n_error,
               " skip=", self$n_skip, " warn=", self$n_warn,
               " status=", status)
      }
    ))
}

# Parse a committed shard-manifest TSV (see tools/ci/gen-shard-manifest.R):
# comment lines (#...), a '# k=' header, then tab-separated rows
# shard<TAB>file<TAB>seconds. Returns list(k, rows=data.frame).
.ci_parse_manifest <- function(path) {
  lines <- readLines(path, warn = FALSE)
  k <- suppressWarnings(as.integer(sub("^#\\s*k=\\s*", "", grep("^#\\s*k=", lines, value = TRUE))))
  if (length(k) != 1L || is.na(k)) stop("manifest lacks a unique '# k=' header: ", path)
  rows <- lines[!grepl("^\\s*(#|$)", lines)]
  if (length(rows) && identical(strsplit(rows[1L], "\t", fixed = TRUE)[[1]],
                        c("shard", "file", "seconds"))) rows <- rows[-1L]
  parsed <- strsplit(rows, "\t", fixed = TRUE)
  bad <- lengths(parsed) != 3L
  if (any(bad)) stop("malformed manifest rows: ", paste(rows[bad], collapse = " | "))
  df <- as.data.frame(do.call(rbind, lapply(parsed, as.character)),
                      stringsAsFactors = FALSE, row.names = NULL)
  names(df) <- c("shard", "file", "seconds")
  df$shard <- as.integer(df$shard)
  df$seconds <- as.integer(df$seconds)
  if (any(is.na(df$shard)) || any(is.na(df$seconds)) || any(df$seconds < 0L)) {
    stop("non-numeric or negative manifest fields: ", path)
  }
  list(k = k, rows = df)
}

# testthat filter for one shard: the file stems (test- prefix and .R suffix
# stripped, as test_dir matches them) as an anchored alternation with every
# regex metacharacter escaped. The shard roster and the executed roster must
# agree by construction, not by luck.
.ci_shard_stems <- function(files) sub("\\.R$", "", sub("^test-", "", files))
.ci_regex_meta <- c("[", "]", "*", "+", "?", "(", ")", "{", "}", "|", "^", "$", ".", "\\")
.ci_regex_escape <- function(x) {
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  paste0(vapply(chars, function(ch)
    if (ch %in% .ci_regex_meta) paste0("\\", ch) else ch, character(1)),
    collapse = "")
}
.ci_shard_filter <- function(rows, shard) {
  stems <- .ci_shard_stems(rows$file[rows$shard == shard])
  if (!length(stems)) stop("manifest names no files for shard ", shard)
  paste0("^(?:", paste(vapply(stems, .ci_regex_escape, character(1)), collapse = "|"), ")$")
}
