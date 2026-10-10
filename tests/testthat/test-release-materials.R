# Release-materials sync guards (U-M7-04 slice-C, C1; GO-04D check-layout fix).
#
# inst/CITATION repeats Package/Title/Version/Authors, so it is a generated
# artifact: tools/gen-citation.R is the single extraction site. These units
# keep the generated file from ever holding independent truth:
#   1. byte-exact regeneration (all lines except the year snapshot);
#   2. the committed year is either the 0.1.0 release year read from NEWS.md
#      or the current year -- no typed year can go stale silently, and a
#      new year never forces a midnight-January regeneration red;
#   3. the URL triangle, SPLIT so each leg is honest about its context:
#      DESCRIPTION <-> CITATION executes wherever both are locatable (repo OR
#      installed tree -- never vacuous there), while the _pkgdown.yml leg is
#      repository-only by nature (buildignored, so never in the tarball) and
#      says so with an explicit skip.
#
# Resource location goes through .ms_src()/.cit_src() in
# helper-check-layout.R (ancestor-walk to the package root, then the
# installed tree) -- never test_path('../../...'), which under R CMD check
# resolves above the check directory and reads blind.

.dfield <- function(lines, key) {
  hit <- grep(paste0("^", key, ":"), lines)
  if (length(hit) != 1L) {
    stop(sprintf("release-materials: field '%s' must appear exactly once in DESCRIPTION (found %d)",
                 key, length(hit)), call. = FALSE)
  }
  trimws(sub(paste0("^", key, ":[[:space:]]*"), "", lines[hit[1]]))
}

test_that("inst/CITATION regenerates byte-exactly from DESCRIPTION", {
  script <- .ms_src("tools/gen-citation.R")
  if (is.na(script)) {
    skip("tools/gen-citation.R not available (R CMD check context)")
  }
  cit <- .cit_src()
  if (is.na(cit)) {
    skip("inst/CITATION not available (R CMD check context)")
  }
  out <- tempfile("gen-citation-")
  rc <- system2("Rscript", c(script, paste0("--out=", out)),
                stdout = FALSE, stderr = FALSE)
  expect_identical(rc, 0L)
  drop_year <- function(ls) ls[!grepl("^  year = \"[0-9]{4}\",$", ls)]
  expect_identical(drop_year(readLines(cit, warn = FALSE)),
                   drop_year(readLines(out, warn = FALSE)))
})

test_that("committed CITATION year is the release year or the current year", {
  cit <- .cit_src()
  if (is.na(cit)) {
    skip("inst/CITATION not available (R CMD check context)")
  }
  newsf <- .ms_src("NEWS.md")
  if (is.na(newsf)) {
    skip("NEWS.md not available (R CMD check context)")
  }
  ly <- grep('^  year = "[0-9]{4}",$', readLines(cit, warn = FALSE),
             value = TRUE, perl = TRUE)
  expect_length(ly, 1L)
  hy <- regmatches(ly, gregexec('year = "([0-9]{4})"', ly, perl = TRUE))[[1]]
  expect_length(hy, 2L)
  y_cit <- hy[2L]
  news <- readLines(newsf, warn = FALSE)
  # The 0.1.0 heading carries a full-width paren (byte-measured) -- match
  # the date shape instead of the punctuation, and require exactly one line
  # so the 0.1.0.9000 dev heading can never enter through it.
  ml <- grep("^# msuiter 0\\.1\\.0.{0,3}[0-9]{4}-[0-9]{2}-[0-9]{2}",
             news, value = TRUE, perl = TRUE)
  expect_length(ml, 1L)
  hn <- regmatches(ml, gregexec('^# msuiter 0\\.1\\.0.{0,3}?([0-9]{4})-[0-9]{2}-[0-9]{2}',
                                ml, perl = TRUE))[[1]]
  expect_length(hn, 2L)
  y_news <- hn[2L]
  expect_true(y_cit %in% c(y_news, format(Sys.time(), "%Y")))
})

# The triangle's two legs have different contexts by nature. Splitting them
# keeps each honest: DESCRIPTION <-> CITATION executes wherever both are
# locatable (installed tree included -- the pair ships together), while the
# _pkgdown.yml leg is repository-only and skips with an explicit reason
# rather than silently disappearing.
test_that("URL triangle: DESCRIPTION <-> CITATION", {
  dfile <- .ms_src("DESCRIPTION")
  if (is.na(dfile)) {
    skip("DESCRIPTION not locatable (R CMD check context)")
  }
  cfile <- .cit_src()
  if (is.na(cfile)) {
    skip("inst/CITATION not available (R CMD check context)")
  }
  d <- readLines(dfile, warn = FALSE)
  url_d <- .dfield(d, "URL")
  expect_match(url_d, "^https?://")
  expect_identical(.dfield(d, "BugReports"), paste0(url_d, "/issues"))

  # Capturing shims (same capture model the C1 validator used): read the
  # bibentry fields as emitted, not as re-derived from the object classes.
  cap <- new.env(baseenv())
  shims <- new.env(baseenv())
  assign("bibentry", function(...) { assign("bib", list(...), envir = cap); invisible(NULL) }, shims)
  assign("citFooter", function(...) invisible(NULL), shims)
  assign("citHeader", function(...) invisible(NULL), shims)
  assign("citEntry", function(...) invisible(NULL), shims)
  eval(parse(text = paste(readLines(cfile, warn = FALSE), collapse = "\n")), envir = shims)
  expect_identical(cap$bib$url, url_d)
})

test_that("URL triangle: DESCRIPTION <-> _pkgdown.yml (repository-only leg)", {
  dfile <- .ms_src("DESCRIPTION")
  if (is.na(dfile)) {
    skip("DESCRIPTION not locatable (R CMD check context)")
  }
  yfile <- .ms_src("_pkgdown.yml")
  if (is.na(yfile)) {
    skip("_pkgdown.yml not shipped in the tarball (repository-only site config)")
  }
  url_d <- .dfield(readLines(dfile, warn = FALSE), "URL")
  yml <- readLines(yfile, warn = FALSE)
  hit <- grep("^url:", yml)
  expect_length(hit, 1L)
  url_y <- trimws(sub("^url:[[:space:]]*", "", yml[hit[1]]))
  expect_identical(url_y, url_d)
})
