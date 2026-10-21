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
  out <- paste0(as.character(res), collapse = "\n")
  if (!identical(if (is.null(st)) 0L else as.integer(st), 0L)) {
    # The census report (VIOLATION rows carry file:line previews) lives in the
    # CAPTURED stdout -- speak it on red, or the shard transcript loses the
    # very evidence the gate exists to emit (windows fan-out run 39657954877:
    # three assertions, zero actuals).
    message(out)
  }
  list(status = if (is.null(st)) 0L else as.integer(st), out = out)
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

test_that("the specs enrollment covers the governed surface (firing control)", {
  tool <- .ms_census_root()
  if (is.null(tool)) {
    skip("requires the source checkout (installed-package check context)")
  }
  r <- .ms_run_census(tool, character(0))
  out_lines <- strsplit(r$out, "\n")[[1]]
  enrolled <- function(path) {
    # Regex-escape every non-alphanumeric path character instead of trusting
    # the reader to spot an unescaped metacharacter.
    esc <- paste0(vapply(strsplit(path, "")[[1L]], function(ch) {
      if (grepl("^[[:alnum:]_/-]$", ch)) ch else paste0("\\", ch)
    }, character(1L)), collapse = "")
    any(grepl(paste0("^", esc, "\\s+normative\\s"), out_lines, perl = TRUE))
  }
  # Hidden-by-absence is the defect ([[governance-scan-integrity]]): every
  # specs glob must demonstrably admit a representative it governs, including
  # the files this pass pulled in from outside the old hand-curated roster.
  for (path in c("R/zzz.R",
                 "README.md",
                 "tools/ci-selfcheck.py",
                 "tools/deep-checks/run_valgrind_leg.sh",
                 "tools/deep-checks/valgrind-canary/src/main.rs",
                 ".github/workflows/scheduled.yml",
                 "tests/testthat/test-cjk-census.R",
                 "src/rust/engine/src/assign.rs",
                 "bench/g0/g0/__init__.py")) {
    expect_true(enrolled(path), info = paste0("not enrolled: ", path))
  }
})
