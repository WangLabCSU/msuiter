# ROADMAP checkbox-truth guard (U-M7-04 slice-A; controller ruling 2026-10-10;
# GO-04D check-layout hardening).
#
# Repository-drift semantics (same pattern as test-ffi-surface-drift.R):
# every checked ([x]) ROADMAP line inside the M6s / M7 / G sections must
# carry a parenthetical evidence citation containing a path:line reference
# or a commit-hash token -- a claim of completion is a claim that can be
# audited. The check itself lives in tools/docs-sync.R (single source of
# truth with the API-surface half); this test drives the script end-to-end
# and asserts both halves report green.
#
# These units are REPOSITORY-ONLY by nature: tools/docs-sync.R validates
# docs/ROADMAP.md, NAMESPACE and _pkgdown.yml against each other -- none of
# which travel in the installed tree. Under R CMD check they therefore skip
# on an explicit repository-ness gate (.ms_root locatable + the artifact
# present under it), never on an accidental miss of test_path('../../...')
# above the check directory (see helper-check-layout.R).

.docs_repo_file <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    skip(paste0(rel, " not available (R CMD check context)"))
  }
  f
}

test_that("docs-sync enforces ROADMAP checkbox evidence citations", {
  script <- .docs_repo_file("tools/docs-sync.R")
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
  src <- .docs_repo_file("_pkgdown.yml")
  dst <- tempfile(pattern = pattern)
  writeLines(readLines(src, warn = FALSE), dst)
  dst
}

test_that("docs-sync indexes every NAMESPACE export in the pkgdown reference index", {
  script <- .docs_repo_file("tools/docs-sync.R")
  out <- tempfile("docs-sync-idx-")
  rc <- system2("Rscript", script, stdout = out, stderr = FALSE)
  msgs <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_match(msgs, "pkgdown-index: OK")
  expect_identical(rc, 0L)
})

test_that("pkgdown-index half catches an export dropped from the reference index", {
  script <- .docs_repo_file("tools/docs-sync.R")
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
  script <- .docs_repo_file("tools/docs-sync.R")
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
