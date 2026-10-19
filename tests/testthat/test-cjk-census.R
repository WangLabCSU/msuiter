# test-cjk-census.R: attestation units for the English-only census instrument
# (tools/cjk-census.R; governance-scan-integrity law: a zero corpus verdict is
# only trustworthy while the scanner demonstrably fires). The instrument runs
# its Han + kana positive controls on EVERY invocation -- these units close
# the loop from the suite side: (1) the controls fire on the shipped scanner,
# (2) the controls GO DARK on a tampered character class (red half: proves the
# control battery is load-bearing and the unit assertions are live), (3) the
# full census exits green over the corpus. Vacuously-green instrumentation is
# the historic failure mode (BSD grep -P no-op, undecoded perl) -- a control
# that cannot fail attests nothing, hence the tamper half is mandatory.

.ms_census_root <- function() {
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  if (!file.exists(file.path(root, "DESCRIPTION")) ||
      system2("git", c("-C", root, "rev-parse", "--git-dir"),
              stdout = NULL, stderr = NULL) != 0L) {
    return(NULL)
  }
  tool <- file.path(root, "tools", "cjk-census.R")
  if (!file.exists(tool)) {
    # source checkout established, instrument absent -- a real defect, never
    # a silent pass.
    stop("tools/cjk-census.R missing from the source checkout")
  }
  tool
}

# system2 on this base returns the captured output vector with the exit
# status in attr(res, "status"), warning on any nonzero status (house idiom,
# test-kernel-cli.R .kernel_status). Spawns go R.home-absolute: R CMD check
# poisons PATH with R_check_bin stubs (helper-check-layout.R).
.ms_run_census <- function(tool, args) {
  res <- suppressWarnings(system2(.ms_rscript(), c(tool, args),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
        out = paste0(as.character(res), collapse = "\n"))
}

test_that("the census controls FIRE on the shipped scanner (green attestation)", {
  tool <- .ms_census_root()
  if (is.null(tool)) {
    skip("requires the source checkout (installed-package check context)")
  }
  r <- .ms_run_census(tool, "--self-test")
  expect_identical(r$status, 0L)
  expect_match(r$out, "SELF-TEST han FIRES")          # two Han ideographs
  expect_match(r$out, "SELF-TEST kana FIRES")         # two hiragana
  expect_match(r$out, "SELF-TEST ascii stays dark")   # negative control
  expect_match(r$out, "cjk-census: SELF-TEST OK")
})

test_that("a tampered character class takes the controls DARK and fails the gate", {
  tool <- .ms_census_root()
  if (is.null(tool)) {
    skip("requires the source checkout (installed-package check context)")
  }
  src <- readLines(tool, warn = FALSE)
  i <- grep("\\p{Han}", src, fixed = TRUE)   # the class definition line
  if (length(i) != 1L) {
    stop("census class definition not locatable for the tamper (",
         length(i), " hits) -- the red half cannot attest a live battery")
  }
  # Tamper: replace the CJK character class with an ASCII-control range that
  # no control string can hit. The tampered copy runs the SAME control
  # battery; a battery that still reports FIRES under this tamper is a lie --
  # the assertions below pin that it cannot.
  src[i]        <- "  \"[\\\\x{1}-\\\\x{8}\","
  src[i + 1L]   <- "  \"\\\\x{9}-\\\\x{9}\","
  src[i + 2L]   <- "  \"\\\\x{a}-\\\\x{1f}]\""
  bad <- tempfile("census-tampered-", fileext = ".R")
  on.exit(unlink(bad), add = TRUE)
  writeLines(src, bad, useBytes = TRUE)
  r <- .ms_run_census(bad, "--self-test")
  expect_identical(r$status, 1L)                     # misbehaving controls = exit 1
  expect_match(r$out, "SELF-TEST han FAILED TO FIRE")
  expect_match(r$out, "SELF-TEST kana FAILED TO FIRE")
  expect_match(r$out, "SELF-TEST ascii stays dark")  # negative control honest
  expect_match(r$out, "MUST NOT be trusted")         # the advisory fires with it
})

test_that("the full census exits green over the normative corpus", {
  tool <- .ms_census_root()
  if (is.null(tool)) {
    skip("requires the source checkout (installed-package check context)")
  }
  r <- .ms_run_census(tool, character(0))
  expect_identical(r$status, 0L)
  expect_match(r$out, "cjk-census: SELF-TEST OK")              # controls ride every run
  expect_match(r$out, "normative CJK outside quote/code context: 0 line\\(s\\)")
  expect_match(r$out, "cjk-census: OK")
})
