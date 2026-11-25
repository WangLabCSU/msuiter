# Fig. 5 roster pin: the section-8 figure manifest's Fig. 5 panel list and the
# section-3.4 witness bullets are one roster rendered twice. CS-1..CS-17 held it;
# CS-18/CS-19/CS-20 were narrated in section 3.4 and never added to the row, and
# nothing read the row, so the drift sat silently across three lanes. These units
# drive tools/manuscript-fig5-roster.R and pin the join both ways.

.ms_roster_file <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    skip(paste0(rel, " not available (R CMD check context)"))
  }
  f
}

# Run the checker against `manuscript` (default: the committed paper draft) and
# return its exit status plus its census transcript.
.roster_run <- function(script, manuscript = NULL) {
  out <- tempfile("fig5-roster-")
  args <- script
  if (!is.null(manuscript)) args <- c(args, paste0("--manuscript=", manuscript))
  rc <- system2(.ms_rscript(), args, stdout = out, stderr = FALSE)
  list(rc = rc, msgs = paste(readLines(out, warn = FALSE), collapse = "\n"))
}

# Copy the committed manuscript to a tempfile, apply `mutator()` to its lines,
# and write the tampered copy back. Never touches committed bytes.
.roster_tamper <- function(src, mutator) {
  dest <- tempfile("paper-draft-", fileext = ".qmd")
  writeLines(mutator(readLines(src, warn = FALSE)), dest)
  dest
}

test_that("the committed Fig. 5 row names every section-3.4 witness lane", {
  script <- .ms_roster_file("tools/manuscript-fig5-roster.R")
  manuscript <- .ms_roster_file("paper/paper-draft.qmd")
  res <- .roster_run(script, manuscript)

  expect_match(res$msgs, "script-truth: 20 cited run_\\*\\.R present")
  expect_match(res$msgs, "OK -- the Fig. 5 panel roster equals")
  expect_identical(res$rc, 0L)
})

test_that("a Fig. 5 row that drops a narrated lane is DRIFT (CS-18 witness)", {
  script <- .ms_roster_file("tools/manuscript-fig5-roster.R")
  src <- .ms_roster_file("paper/paper-draft.qmd")
  # Rewind the row to its pre-CS-18 state: strip the three appended clauses.
  tampered <- .roster_tamper(src, function(lines) {
    sub(", CS-18 convert-witness, CS-19 compare-witness, CS-20 kselect-witness\\)", ")", lines)
  })
  res <- .roster_run(script, tampered)

  expect_identical(res$rc, 1L)
  expect_match(res$msgs, "missing from the Fig. 5 row: CS-18, CS-19, CS-20")
})

test_that("a section-3.4 lane with no Fig. 5 panel is DRIFT (extra panel)", {
  script <- .ms_roster_file("tools/manuscript-fig5-roster.R")
  src <- .ms_roster_file("paper/paper-draft.qmd")
  # Append a phantom lane to the row that section 3.4 never narrates.
  tampered <- .roster_tamper(src, function(lines) {
    sub("CS-20 kselect-witness\\)", "CS-20 kselect-witness, CS-21 phantom-witness)", lines)
  })
  res <- .roster_run(script, tampered)

  expect_identical(res$rc, 1L)
  expect_match(res$msgs, "in the Fig. 5 row but not narrated in section 3.4: CS-21")
})

test_that("a section-3.4 bullet citing an uncommitted witness script is DRIFT", {
  script <- .ms_roster_file("tools/manuscript-fig5-roster.R")
  src <- .ms_roster_file("paper/paper-draft.qmd")
  # Point one citation at a script that is not in the tree.
  tampered <- .roster_tamper(src, function(lines) {
    sub("bench/scenarios/run_kselect_witness\\.R", "bench/scenarios/run_no_such_witness.R", lines)
  })
  res <- .roster_run(script, tampered)

  expect_identical(res$rc, 1L)
  expect_match(res$msgs, "cites uncommitted witness script\\(s\\): bench/scenarios/run_no_such_witness\\.R")
})

test_that("a manuscript with no Fig. 5 row is a structural error, not silent green", {
  script <- .ms_roster_file("tools/manuscript-fig5-roster.R")
  src <- .ms_roster_file("paper/paper-draft.qmd")
  tampered <- .roster_tamper(src, function(lines) {
    grep("^\\|\\s*Fig\\.\\s*5\\s*\\|", lines, invert = TRUE, value = TRUE)
  })
  res <- .roster_run(script, tampered)

  expect_identical(res$rc, 2L)
})
