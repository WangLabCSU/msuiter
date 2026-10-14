# test-r-floor-ops.R -- R-floor operator guard (hygiene gate for the declared floor).
#
# DESCRIPTION pins `Depends: R (>= 4.3.0)`. Base gained operators ABOVE that
# floor, and any R 4.3 arm aborts on them with "could not find function" the
# moment an exercising path runs -- silently today, because the offending
# lines are not exercised on that arm. The host R (4.5.x) *has* these
# operators, so no executable test can catch such a use on the development
# machine: this static source census is the gate.
#
# Registry entries are one line each: operator token + the evidence that
# condemns it. `%||%`: bundled doc/NEWS, section "CHANGES IN R 4.4.0"
# ("`%||%` newly in base is an expressive idiom for ... if (!is.null(L)) L
# else R", NEWS around L1151); container-probed absent in R 4.3.3, present
# in 4.5.2. First-fixed sites: R/hrd-report.R (print.MsHrdReport null
# default) and tests/testthat/test-ms-benchmark-driver.R (mocked ms_simulate).
#
# Tarball-context skip: R CMD check of a built tarball ships neither R/ nor
# tests/testthat/ sources, mirroring the repo-mode drift guards
# (test-ffi-surface-drift.R, test-channels-sync.R).

# Operator registry: names = forbidden tokens, values = condemning evidence.
# A future above-floor operator is one new line here.
.ms_floor_ops <- c(
  "%||%" = paste("base-only from R 4.4.0 (bundled NEWS, 'CHANGES IN R 4.4.0');",
                 "DESCRIPTION floor is R >= 4.3.0")
)

# Static census over [.]R sources: every non-comment occurrence of a
# registered token is a hit. Comments are stripped first, so *citing* an
# operator in a comment (as the floor law does) stays legal. `except`
# matches by basename -- test_path() and list.files() resolve to different
# spellings of the same file, so full-path set arithmetic is unreliable here.
.ms_floor_census <- function(dir, except = character(0)) {
  files <- list.files(dir, pattern = "[.][Rr]$", full.names = TRUE, recursive = TRUE)
  files <- files[!(basename(files) %in% basename(except))]
  hits <- character(0)
  for (f in files) {
    code <- sub("#.*$", "", readLines(f, warn = FALSE))
    for (op in names(.ms_floor_ops)) {
      bad <- grep(op, code, fixed = TRUE)
      if (length(bad)) {
        hits <- c(hits, sprintf("%s:%d  [%s]  %s",
                                basename(f), bad, .ms_floor_ops[[op]], trimws(code[bad])))
      }
    }
  }
  hits
}

test_that("package and test sources stay free of above-floor base operators", {
  rdir <- testthat::test_path("../../R")
  if (!dir.exists(rdir)) {
    # Wording note: the skip must speak the sanctioned ledger vocabulary of
    # tools/check-layout-sim.R (SANCTIONED_ENDS "(R CMD check context)") --
    # an unlisted skip reason is an UNAUTHORIZED_SKIP and fails the sim.
    skip("package sources not available (R CMD check context)")
  }
  hits <- c(
    .ms_floor_census(rdir),
    .ms_floor_census(testthat::test_path("."),
                     except = testthat::test_path("test-r-floor-ops.R"))
  )
  expect_equal(hits, character(0))
})
