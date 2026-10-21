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

# <!-- census-exempt tokens: 0 2 8 9 -->
# (fan-out run 39671292067 forensics: the refuted cat(file = stderr()) report
# emission and its guard -- two 0L operands plus one run-id zero -- left this
# file as a proven-dead channel; every remaining numeral claim stands.
# run 39686575425 forensics: the tamper re-anchor retired the adjudicated-dead
# comment-homed patch strings -- their 8/9 (dead ASCII-control ranges) and one
# 2 (a dead src[i + 2L] index line) left with them; the tamper now excises the
# .cjk_regex block structurally and attests its own landing.)

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
  # Evidence rides the expectation's info= (call sites below), not a print:
  # a test context sinks stdout AND stderr AND swallows message() (all three
  # measured across fan-out runs 39657954877 / 39665540072 / 39671292067),
  # so the failure message -- which expect_* embeds info= into and the shard
  # runner renders in full -- is the only channel out of a red test.
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
  # The tamper targets the .cjk_regex block itself, anchored on its defining
  # shape: run 39686575425 forensics -- a textual needle (a class-name string)
  # was silently re-homed onto the forensics comment that quoted it, the patch
  # no-op'd the rule and the red half went red for the wrong reason. A
  # structural anchor cannot be shadowed by a comment.
  j <- grep("^\\.cjk_regex <- paste0\\($", src)
  k <- if (length(j) == 1L) {
    cl <- grep("^\\)$", src[(j + 1L):length(src)])
    if (length(cl)) j + cl[1L] else integer(0)
  } else integer(0)
  if (length(j) != 1L || length(k) != 1L) {
    stop("census class block not locatable for the tamper (j=",
         paste0(j, collapse = ","), " k=", paste0(k, collapse = ","),
         ") -- the red half cannot attest a live battery")
  }
  # Tamper: excise the numeric block and ship one ASCII-control range no
  # control string can hit. The tampered copy runs the SAME control
  # battery; a battery that still reports FIRES under this tamper is a lie --
  # the assertions below pin that it cannot.
  src[j:k] <- c(".cjk_regex <- paste0(",
                "  \"[\\\\x{1}-\\\\x{1f}]\")")
  # The excision is attested before the run: the Han-block digits are carried
  # only by the rule, so their survival would mean the tamper missed it.
  if (any(grepl("4e00", src, fixed = TRUE))) {
    stop("tamper was a no-op: the Han-block digits survived the excision")
  }
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
  expect_identical(r$status, 0L, info = r$out)
  expect_match(r$out, "cjk-census: SELF-TEST OK", info = r$out)   # controls ride every run
  expect_match(r$out, "normative CJK outside quote/code context: 0 line\\(s\\)",
               info = r$out)
  expect_match(r$out, "cjk-census: OK", info = r$out)
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
