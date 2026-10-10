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

# --- half three: _pkgdown.yml reference-index completeness (U-M7-04 slice-C) -
#
# Green half: every NAMESPACE export carries a reference-index entry. The
# red half drives the checker against a TEMPORARY tampered copy of
# _pkgdown.yml (--pkgdown= override), so the tamper detection is proven
# without ever committing a broken site index.

.pkgdown_copy <- function(pattern) {
  src <- testthat::test_path("../../_pkgdown.yml")
  if (!file.exists(src)) {
    skip("_pkgdown.yml not available (R CMD check context)")
  }
  dst <- tempfile(pattern = pattern)
  writeLines(readLines(src, warn = FALSE), dst)
  dst
}

test_that("docs-sync indexes every NAMESPACE export in the pkgdown reference index", {
  script <- testthat::test_path("../../tools/docs-sync.R")
  if (!file.exists(script)) {
    skip("tools/docs-sync.R not available (R CMD check context)")
  }
  out <- tempfile("docs-sync-idx-")
  rc <- system2("Rscript", script, stdout = out, stderr = FALSE)
  msgs <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_match(msgs, "pkgdown-index: OK")
  expect_identical(rc, 0L)
})

test_that("pkgdown-index half catches an export dropped from the reference index", {
  script <- testthat::test_path("../../tools/docs-sync.R")
  if (!file.exists(script)) {
    skip("tools/docs-sync.R not available (R CMD check context)")
  }
  tf <- .pkgdown_copy("pkgdown-tamper-")
  lines <- readLines(tf, warn = FALSE)
  hit <- grep("^[[:space:]]+- ms_sitrep$", lines)
  expect_length(hit, 1L)
  writeLines(lines[-hit], tf)
  out <- tempfile("docs-sync-tamper-")
  rc <- system2("Rscript", c(script, paste0("--pkgdown=", tf)),
                stdout = out, stderr = FALSE)
  msgs <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_identical(rc, 1L)
  expect_match(msgs, "export missing from the index: ms_sitrep")
})

test_that("pkgdown-index half flags ghost entries with no export and no Rd", {
  script <- testthat::test_path("../../tools/docs-sync.R")
  if (!file.exists(script)) {
    skip("tools/docs-sync.R not available (R CMD check context)")
  }
  tf <- .pkgdown_copy("pkgdown-ghost-")
  lines <- readLines(tf, warn = FALSE)
  hit <- grep("^[[:space:]]+- ms_sitrep$", lines)
  expect_length(hit, 1L)
  lines <- append(lines, "  - ms_no_such_export", after = hit[1])
  writeLines(lines, tf)
  out <- tempfile("docs-sync-ghost-")
  rc <- system2("Rscript", c(script, paste0("--pkgdown=", tf)),
                stdout = out, stderr = FALSE)
  msgs <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_identical(rc, 1L)
  expect_match(msgs, "index entry with no export and no man/ms_no_such_export.Rd")
})
