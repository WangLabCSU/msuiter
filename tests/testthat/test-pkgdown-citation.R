# test-pkgdown-citation.R: DS-3 citation law (docs/site v1).
# inst/CITATION is the package citation face (utils::citation reads it after
# installation). The M7 delivery requires the citation form to be complete and
# fabrication-free: package-only entries (authors, title, version, repository
# URL, year), NO method-paper DOI, NO "submitted"/"in press" bib that does not
# exist. A methods-paper entry may only ever appear as an honest TODO comment
# once a real venue exists. The sync guards (byte-exact regeneration from
# DESCRIPTION, URL triangle, year honesty) live in
# tests/testthat/test-release-materials.R and are not repeated here; this file
# owns the field-completeness, registration and anti-fabrication halves, with
# constructed-broken controls for every scan (dead-metric law).

# --- scan/gate helpers --------------------------------------------------------

# Case-insensitive substring presence without capture-group regexes.
.ds3_contains_ci <- function(lines, token) {
  any(vapply(lines, function(l) {
    grepl(token, tolower(l), fixed = TRUE)
  }, logical(1), USE.NAMES = FALSE))
}

.ds3_is_comment <- function(l) startsWith(trimws(l), "#")

# Fabrication surface: a bib entry may not claim a DOI, a press state or a
# paper. Comment lines may carry an honest TODO for the future method-paper
# entry; they may not assert one.
.ds3_fabrication_violations <- function(lines) {
  v <- character(0)
  bad <- c("doi", "10.", "submitted", "in press", "in-press", "accepted",
           "manuscript", "paper")
  body <- lines[!.ds3_is_comment_vec(lines)]
  for (t in bad) if (.ds3_contains_ci(body, t)) {
    v <- c(v, paste0("CITATION body asserts forbidden token: ", t))
  }
  com <- lines[.ds3_is_comment_vec(lines)]
  for (i in seq_along(com)) {
    low <- tolower(com[i])
    claims <- any(vapply(c("manuscript", "paper", "submitted", "doi"),
                         function(t) grepl(t, low, fixed = TRUE),
                         logical(1), USE.NAMES = FALSE))
    if (claims && !grepl("todo", low, fixed = TRUE)) {
      v <- c(v, paste0("CITATION comment claims a paper state without an ",
                       "honest TODO marker: ", com[i]))
    }
  }
  if (length(lines) == 0L) v <- c(v, "vacuous scan: zero CITATION lines inspected")
  v
}

.ds3_is_comment_vec <- function(lines) {
  vapply(lines, .ds3_is_comment, logical(1), USE.NAMES = FALSE)
}

# Evaluate inst/CITATION (a bibentry(...) + citFooter(...) script) against
# collector shims -- the same call shape utils::citation uses at read time.
.ds3_eval_citation <- function(lines) {
  captured <- new.env(parent = globalenv())  # search path reaches person()
  assign("bibentry", function(...) {
    a <- list(...)
    assign("bibentry", a, envir = captured)
    invisible(a)
  }, envir = captured)
  assign("citFooter", function(...) {
    assign("citFooter", c(...), envir = captured)
    invisible(NULL)
  }, envir = captured)
  exprs <- parse(text = lines)
  eval(exprs, envir = captured)
  if (exists("bibentry", envir = captured, inherits = FALSE)) {
    get("bibentry", envir = captured, inherits = FALSE)
  } else {
    NULL
  }
}

.ds3_repo_file <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    skip(paste0(rel, " not available (R CMD check context)"))
  }
  f
}

.ds3_citation_lines <- function() {
  readLines(.ds3_repo_file("inst/CITATION"), warn = FALSE)
}

# --- laws ----------------------------------------------------------------------

test_that("DS-3 the CITATION bibentry carries the required package fields", {
  lines <- .ds3_citation_lines()
  ent <- .ds3_eval_citation(lines)
  expect_false(is.null(ent), info = "inst/CITATION yielded no bibentry() call")
  for (f in c("bibtype", "title", "author", "year", "url")) {
    expect_true(!is.null(ent[[f]]) && !identical(ent[[f]], ""),
                info = paste0("required field missing/empty: ", f))
  }
  expect_identical(ent$bibtype, "Manual")
  expect_true(grepl("msuiter", ent$title, fixed = TRUE))
  expect_true(grepl("https://", ent$url, fixed = TRUE))
  # version is present and equals the DESCRIPTION Version -- compared by
  # reference, never retyped as a literal.
  desc <- readLines(.ds3_repo_file("DESCRIPTION"), warn = FALSE)
  hit <- Filter(function(l) startsWith(l, "Version:"), desc)
  expect_length(hit, 1L)
  ver <- trimws(sub("^Version:", "", hit[1]))
  expect_true(grepl(ver, paste0(ent$note, collapse = " "), fixed = TRUE) ||
               grepl(ver, paste0(ent$textVersion, collapse = " "), fixed = TRUE),
              info = paste0("CITATION carries neither note nor textVersion ",
                            "mentioning the DESCRIPTION Version ", ver))
})

test_that("DS-3 the CITATION body is fabrication-free and the scan fires on a planted DOI (positive control)", {
  lines <- .ds3_citation_lines()
  v <- .ds3_fabrication_violations(lines)
  expect_identical(v, character(0), info = paste0(v, collapse = "\n"))
  # constructed-broken control: the scanner must name what was planted.
  tampered <- append(lines, "  doi = \"10.1038/does-not-exist\",",
                     after = 1L)
  v2 <- .ds3_fabrication_violations(tampered)
  expect_true(length(v2) > 0L)
  expect_true(any(grepl("forbidden token: doi", v2, fixed = TRUE)))
  tampered2 <- append(lines, "# method paper, submitted to Nature Methods",
                      after = 1L)
  v3 <- .ds3_fabrication_violations(tampered2)
  expect_true(any(grepl("without an honest TODO marker", v3, fixed = TRUE)))
  # the honest form of the same claim must stay green:
  honest <- append(lines,
    "# TODO(paper): the method-paper entry lands here once a real venue exists",
    after = 1L)
  expect_identical(.ds3_fabrication_violations(honest), character(0))
})

test_that("DS-3 the DESCRIPTION License field is the sealed bundle form", {
  desc <- readLines(.ds3_repo_file("DESCRIPTION"), warn = FALSE)
  lic <- Filter(function(l) startsWith(l, "License:"), desc)
  expect_length(lic, 1L)
  expect_identical(lic[1], "License: file LICENSE")
})

test_that("DS-3 citation() resolves the package citation to a non-NULL object", {
  # utils::citation reads the INSTALLED inst/CITATION; the repository half of
  # the law (field completeness above) runs on the committed bytes, this half
  # proves the registration face works end-to-end. An installed msuiter is
  # required -- skip (with a reason) when absent.
  if (!nzchar(system.file("CITATION", package = "msuiter"))) {
    skip("no installed msuiter to read CITATION from (development context)")
  }
  cit <- suppressWarnings(utils::citation(package = "msuiter"))
  expect_false(is.null(cit))
  expect_true(inherits(cit, "citation"))
  txt <- paste0(testthat::capture_output_lines(print(cit)), collapse = "\n")
  expect_true(grepl("Wang", txt, fixed = TRUE), info = txt)
  expect_true(grepl("msuiter", txt, fixed = TRUE), info = txt)
})

test_that("DS-3 the empty-file vacuous gate fires on a zero-line CITATION", {
  v <- .ds3_fabrication_violations(character(0))
  expect_true(any(grepl("vacuous scan", v, fixed = TRUE)))
})
