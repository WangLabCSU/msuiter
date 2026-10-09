# ROADMAP checkbox-truth guard (U-M7-04 slice-A; controller ruling 2026-10-10).
#
# Repository-drift semantics (same pattern as test-ffi-surface-drift.R):
# every checked ([x]) ROADMAP line inside the M6s / M7 / G sections must
# carry a parenthetical evidence citation containing a path:line reference
# or a commit-hash token -- a claim of completion is a claim that can be
# audited. The check itself lives in tools/docs-sync.R (single source of
# truth with the API-surface half); this test drives the script end-to-end
# and asserts both halves report green. Skips under R CMD check of a
# tarball, where tools/ is not shipped.

test_that("docs-sync enforces ROADMAP checkbox evidence citations", {
  script <- testthat::test_path("../../tools/docs-sync.R")
  if (!file.exists(script)) {
    skip("tools/docs-sync.R not available (R CMD check context)")
  }
  out <- tempfile("docs-sync-")
  # The guard speaks via cat() on stdout; stderr is the Rscript noise floor.
  rc <- system2("Rscript", script, stdout = out, stderr = FALSE)
  msgs <- paste(readLines(out, warn = FALSE), collapse = "\n")
  # The checkbox half must exist and speak...
  expect_match(msgs, "checkbox-truth")
  # ...and the whole guard must be green against the repository as it stands.
  expect_identical(rc, 0L)
})
