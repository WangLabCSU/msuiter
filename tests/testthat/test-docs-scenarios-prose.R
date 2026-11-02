# test-docs-scenarios-prose.R: DS-4 US-H2 scenarios-page witness-bound prose law
# (docs/site v4). scenarios.Rmd narrates the scenario atlas whose witnesses are
# committed under bench/scenarios/out/*.csv. The law demands every multi-digit
# numeral in the page prose be EITHER a member of the witness-derived census
# set (re-derived live through the scenarios-gallery tool's scg_numset face --
# one census tool, no fork) OR covered by a sanctioned ms-num marker on the
# same line whose kind/reason contract the law re-checks. An empty witness
# tree is vacuous-RED; a fabricated numeral without witness bytes is named.
# Firing controls: tamper an unmarked numeral -> named; forged marker ->
# named; constructed-perfect witness makes a fabricated numeral pass and its
# removal refuses it again (the census join is live, not decorative).

# --- instrument access (fail-closed, DS-3 posture) --------------------------------

.sp_tool <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- .ms_src("tools/scenarios-gallery.R")
  if (is.na(f) || !file.exists(f)) {
    stop("tools/scenarios-gallery.R missing (US-H2 defect)")
  }
  f
}

# Source the tool without running its CLI main: the MSUITER_TOOL_NO_MAIN marker
# is the source-vs-invoke discriminator the tool family honors.
.sp_env <- function() {
  f <- .sp_tool()
  e <- new.env(parent = globalenv())
  Sys.setenv(MSUITER_TOOL_NO_MAIN = "1")
  on.exit(Sys.unsetenv("MSUITER_TOOL_NO_MAIN"), add = TRUE)
  source(f, local = e)
  need <- c("scg_roster", "scg_witness_dir", "scg_derive",
            "scg_numset", "scg_prose_audit")
  for (n in need) {
    if (!exists(n, envir = e, inherits = FALSE)) {
      stop("scenarios-gallery tool lost its callable face: ", n)
    }
  }
  e
}

# --- page locator -------------------------------------------------------------------

.sp_page <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "vignettes", "scenarios.Rmd")
  if (!file.exists(f)) stop("vignettes/scenarios.Rmd missing from the checkout (US-H2 defect)")
  f
}

# --- memoized single census of page + witnesses -------------------------------------

.sp_state <- new.env()

.sp_run <- function() {
  if (exists("res", envir = .sp_state, inherits = FALSE)) {
    return(get("res", envir = .sp_state))
  }
  e <- .sp_env()
  page <- .sp_page()
  numset <- e$scg_numset(e$scg_witness_dir(.ms_root))
  res <- list(e = e, page = page, numset = numset)
  assign("res", res, envir = .sp_state)
  res
}

# --- green halves -------------------------------------------------------------------

test_that("US-H2 the witness census is non-vacuous and pins the atlas geometry", {
  ctx <- .sp_run()
  expect_true(length(ctx$numset) >= 20L,
               info = paste0("vacuous witness census: only ",
                             length(ctx$numset), " tokens"))
  # the atlas table is 96 channels x 24 samples of planted synthetic truth:
  # both figures must reach the census from the committed bytes themselves
  expect_true("96" %in% ctx$numset,
               info = "96 (atlas channel rows) not witness-derived")
  expect_true("24" %in% ctx$numset,
               info = "24 (atlas sample columns) not witness-derived")
  cat("US-H2 WITNESS CENSUS: tokens=", length(ctx$numset),
      " witnesses=", length(ctx$e$scg_roster(.ms_root)), "\n", sep = "")
})

test_that("US-H2 every prose numeral is witness-bound or sanctioned-marked", {
  ctx <- .sp_run()
  a <- ctx$e$scg_prose_audit(ctx$page, ctx$numset)
  expect_identical(a$violations, character(0),
                   info = paste0(a$violations, collapse = "\n"))
  expect_true(a$bound >= 2L, info = "vacuous: no unmarked numeral reached the census")
  expect_true(a$marked >= 1L, info = "vacuous: no ms-num marker exercised")
  cat("US-H2 PROSE CENSUS: unmarked=", a$bound, " marked=", a$marked,
      " violations=0\n", sep = "")
})

# --- red halves: firing controls ------------------------------------------------------

test_that("US-H2 a tampered unmarked prose numeral is named", {
  ctx <- .sp_run()
  lines <- readLines(ctx$page, warn = FALSE)
  hit <- grep("96-channel", lines, fixed = TRUE)
  expect_length(hit, 1L)
  bad <- lines
  bad[hit] <- sub("96-channel", "97-channel", bad[hit], fixed = TRUE)
  tmp <- tempfile(fileext = ".Rmd"); writeLines(bad, tmp)
  a <- ctx$e$scg_prose_audit(tmp, ctx$numset)
  expect_true(any(grepl("97", a$violations, fixed = TRUE)),
               info = paste0(a$violations, collapse = "\n"))
  expect_true(any(grepl("not witness-bound", a$violations, fixed = TRUE)),
               info = "the tampered numeral must be named as off-census")
})

test_that("US-H2 a forged ms-num marker does not launder an off-census numeral", {
  ctx <- .sp_run()
  lines <- readLines(ctx$page, warn = FALSE)
  hit <- grep("96-channel", lines, fixed = TRUE)
  bad <- lines
  bad[hit] <- paste0(sub("96-channel", "97-channel", bad[hit], fixed = TRUE),
                     " <!-- ms-num kind=\"magic\" reason=\"because\" -->")
  tmp <- tempfile(fileext = ".Rmd"); writeLines(bad, tmp)
  a <- ctx$e$scg_prose_audit(tmp, ctx$numset)
  expect_true(any(grepl("97", a$violations, fixed = TRUE)),
               info = paste0(a$violations, collapse = "\n"))
  expect_true(any(grepl("ms-num marker", a$violations, fixed = TRUE)),
               info = "the contract breach of the marker itself must be named")
})

test_that("US-H2 the census join is live: a constructed witness legitimises its number", {
  ctx <- .sp_run()
  lines <- readLines(ctx$page, warn = FALSE)
  hit <- grep("96-channel", lines, fixed = TRUE)
  bad <- lines
  bad[hit] <- sub("96-channel", "7429-channel", bad[hit], fixed = TRUE)
  tmp <- tempfile(fileext = ".Rmd"); writeLines(bad, tmp)
  # off the census the fabricated numeral is named
  a0 <- ctx$e$scg_prose_audit(tmp, ctx$numset)
  expect_true(any(grepl("7429", a0$violations, fixed = TRUE)),
               info = "fabricated numeral slipped through un-named")
  # a committed witness carrying those bytes legitimises it
  d <- tempfile("us-h2-witnesses-"); dir.create(d)
  w <- file.path(d, "planted.csv")
  writeLines(c("value", "7429"), w)
  ns <- ctx$e$scg_numset(d)
  expect_true("7429" %in% ns, info = "constructed witness did not reach the census")
  a1 <- ctx$e$scg_prose_audit(tmp, ns)
  expect_true(!any(grepl("7429", a1$violations, fixed = TRUE)),
               info = "witness-backed numeral still reddened: the join is broken")
  # remove the witness: the number falls out of the census and reddens again
  unlink(w)
  expect_error(ctx$e$scg_numset(d), "vacuous")
  a2 <- ctx$e$scg_prose_audit(tmp, setdiff(ctx$numset, "7429"))
  expect_true(any(grepl("7429", a2$violations, fixed = TRUE)),
               info = "removing the census join let the page pass")
})

test_that("US-H2 an empty witness tree is vacuous-RED, never empty-green", {
  ctx <- .sp_run()
  d <- tempfile("us-h2-empty-"); dir.create(d)
  expect_error(ctx$e$scg_numset(d), "vacuous")
  # and the CLI face refuses too, with a spoken word
  r <- suppressWarnings(system2(.ms_rscript(),
                                c(.sp_tool(), paste0("--root=", .ms_root),
                                  paste0("--witness-dir=", d), "--prose-check"),
                                stdout = TRUE, stderr = TRUE))
  st <- attr(r, "status")
  expect_true(!is.null(st) && as.integer(st) != 0L, info = "CLI accepted a vacuous tree")
  expect_true(grepl("vacuous", paste0(as.character(r), collapse = "\n"), fixed = TRUE))
})
