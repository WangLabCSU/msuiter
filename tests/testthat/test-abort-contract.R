# The abort-contract law (R/classes-utils.R docs; ARCHITECTURE section 3.5):
# every `msuiter_abort()` call passes the mandatory i/j/c three-part payload,
# so a violation raises the structured `msuiter_error_<topic>` condition (the
# `msuiter_error` payload plus the three message bullets) rather than a bare
# base-R `missingArgError`/`getvarError` whose message prints in the locale's
# language and carries no payload.
#
# A missing argument parses cleanly, so no reader that only inspects present
# tokens can see it: the 2026-11-24 sweep found 15 sites in R/ that passed two
# or three of the five names (a genuine residual -- an earlier commit fixed the
# property validators but not the counts/k0/k guards). This file is the reader
# that sees the absence.

# Census one source text: a data.frame(line, missing) over every
# msuiter_abort() call whose argument list omits any of i/j/c. getParseData
# yields byte-true line numbers and nesting, so a NESTED call's own commas are
# never read as the outer call's argument separators.
.abort_census_text <- function(text) {
  empty <- data.frame(line = integer(0), missing = character(0),
                      stringsAsFactors = FALSE)
  pd <- utils::getParseData(parse(text = text, keep.source = TRUE))
  if (is.null(pd) || nrow(pd) == 0L) return(empty)
  nr <- nrow(pd)
  calls <- which(pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "msuiter_abort")
  if (length(calls) == 0L) return(empty)
  out <- lapply(calls, function(r) {
    opn <- which(pd$token == "'('" & seq_len(nr) > r)[1L]
    if (is.na(opn)) return(NULL)
    depth <- 0L
    cls <- NA_integer_
    for (i in opn:nr) {
      tok <- pd$token[i]
      if (tok == "'('") depth <- depth + 1L
      else if (tok == "')'") {
        depth <- depth - 1L
        if (depth == 0L) { cls <- i; break }
      }
    }
    if (is.na(cls) || cls <= opn + 1L) return(NULL)
    d <- 0L
    subs <- character(0L)
    for (i in (opn + 1L):(cls - 1L)) {
      tok <- pd$token[i]
      if (tok == "'('") d <- d + 1L
      else if (tok == "')'") d <- d - 1L
      else if (tok == "SYMBOL_SUB" && d == 0L) subs <- c(subs, pd$text[i])
    }
    data.frame(line = pd$line1[r],
               missing = paste(setdiff(c("i", "j", "c"), subs), collapse = ","),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, out)
  if (is.null(out)) empty else out
}

.abort_root <- function(start = testthat::test_path()) {
  d <- normalizePath(start)
  while (nzchar(dirname(d)) != nchar(d)) {
    f <- file.path(d, "DESCRIPTION")
    if (file.exists(f) &&
        any(grepl("^Package: msuiter", readLines(f, warn = FALSE)))) {
      return(d)
    }
    d <- dirname(d)
  }
  # The simulated check layout runs the copied tests as a sibling of the
  # package dir -- no DESCRIPTION ancestry there. Absent root is the
  # check-context signal, spoken by the sanctioned skip, not a stop.
  NA_character_
}

test_that("a census sees a missing i/j/c bullet (firing control)", {
  bad <- "f <- function() { msuiter_abort('input', 'msg', i = 'x', j = 'y') }"
  expect_identical(.abort_census_text(bad)$missing, "c")
  good <- paste0("f <- function() { msuiter_abort('input', 'msg', i = 'x', ",
                 "j = 'y', c = 'z') }")
  expect_false(any(nzchar(.abort_census_text(good)$missing)))
  # A nested call's commas belong to the inner list, not the outer arg list.
  nest <- paste0("f <- function() { msuiter_abort('input', 'msg', i = 'x', ",
                 "j = paste(c('a', 'b'), collapse = ','), c = 'z') }")
  expect_false(any(nzchar(.abort_census_text(nest)$missing)))
})

test_that("every msuiter_abort() call carries the mandatory i/j/c payload", {
  root <- .abort_root()
  if (is.na(root)) {
    skip(paste0("the abort census parses the R/ sources: requires the source ",
                "checkout, which the check layout does not ship ",
                "(R CMD check context)"))
  }
  files <- list.files(file.path(root, "R"), pattern = "[.]R$",
                      full.names = TRUE)
  total <- 0L
  offenders <- character()
  for (f in files) {
    res <- .abort_census_text(paste(readLines(f, warn = FALSE), collapse = "\n"))
    total <- total + nrow(res)
    bad <- res[nzchar(res$missing), , drop = FALSE]
    if (nrow(bad) > 0L) {
      offenders <- c(offenders, sprintf("%s:%d (missing %s)", basename(f),
                                        bad$line, bad$missing))
    }
  }
  # Window liveness on the real tree: a scan reading nothing would pass blind.
  expect_gt(total, 100L)
  expect_identical(offenders, character())
})
