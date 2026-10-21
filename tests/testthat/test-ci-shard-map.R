# CI shard-topology unit (wall-clock restructure, 2026-10-21).
#
# The committed shard manifest is the single source of truth for how the
# testthat suite fans out across the guards shards, the coverage shards, and
# the per-platform check-test fan-outs. This unit is the roster census that
# keeps that source honest: exhaustive over the on-disk test roster, disjoint,
# byte-stable, and its instruments proven to FIRE (cjk-census self-test
# family: a scanner without a firing positive control is vacuous and
# refused). Baseline forensics and the before/after ledgers live in the lane
# manifest (/tmp/ciopt/manifest.md) and docs/devlog/.

.ci_require_checkout <- function() {
  if (is.na(.ms_root)) {
    skip("requires the source checkout (installed-package check context)")
  }
}

# Instrument locators are hard expectations, never silent skips: in a
# checkout a missing instrument is a census failure (vacuous-green law).
.ci_ci_locate <- function(name) {
  p <- .ms_src(paste0("tools/ci/", name))
  expect_false(is.na(p), info = paste0("shard instrument missing: tools/ci/", name))
  if (is.na(p)) stop("missing instrument: ", name)
  p
}

.ci_spawn <- function(bin, argv) {
  # File-mode capture: the renamed-R system2 build drops in-band output text
  # (helper-kernel-pipeline.R law), so status lives in the return value and
  # the transcript in files.
  out <- tempfile("ci-out-"); err <- tempfile("ci-err-")
  rc <- suppressWarnings(system2(bin, argv, stdout = out, stderr = err))
  list(status = as.integer(rc),
       out = paste0(readLines(out, warn = FALSE), collapse = "\n"),
       err = paste0(readLines(err, warn = FALSE), collapse = "\n"))
}

.ci_manifest_dir <- function() file.path(.ms_root, "tests", "testthat")
.ci_test_roster <- function() list.files(.ci_manifest_dir(), pattern = "^test-.*[.]R$")

test_that("the shard instruments are committed next to the manifest", {
  .ci_require_checkout()
  for (name in c("gen-shard-manifest.R", "run-testthat-shard.R", "run-covr-shard.R",
                 "shard-manifest.tsv", "shard-weights.tsv", "fanout-configs.tsv",
                 "ci-shard-aggregate.py", "covmerge.py")) {
    p <- .ms_src(paste0("tools/ci/", name))
    expect_true(isTRUE(file.exists(p)), info = name)   # file.exists(NA) is FALSE: missing instrument = red
  }
})

test_that("the manifest partition is exhaustive, disjoint, and ordered", {
  .ci_require_checkout()
  m <- .ci_parse_manifest(.ci_ci_locate("shard-manifest.tsv"))
  expect_identical(sort(as.character(m$rows$file)), sort(.ci_test_roster())) # nothing lost, nothing invented
  expect_identical(anyDuplicated(m$rows$file), 0L)                          # disjoint (renamed-R returns the first dup index, 0 = none)
  expect_identical(sort(unique(m$rows$shard)), seq_len(m$k))                 # numbered 1..K, no gaps
  for (s in seq_len(m$k)) {
    sh <- m$rows$file[m$rows$shard == s]
    expect_gte(length(sh), 1L)                 # an empty shard is a vacuous arm
    expect_identical(sh, sort(sh))             # deterministic order within shard
  }
})

test_that("regenerating the manifest byte-matches the committed witness", {
  .ci_require_checkout()
  gen <- .ci_ci_locate("gen-shard-manifest.R")
  weights <- .ci_ci_locate("shard-weights.tsv")
  committed <- .ci_ci_locate("shard-manifest.tsv")
  outs <- vapply(seq_len(2L), function(i) {
    o <- tempfile("shard-manifest-rep-")
    r <- .ci_spawn(.ms_rscript(), c(gen, paste0("--weights=", weights),
                                    paste0("--out=", o)))
    expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err))
    paste0(readLines(o, warn = FALSE), collapse = "\n")
  }, character(1))
  expect_identical(outs[1L], outs[2L])                        # generator is deterministic
  expect_identical(outs[1L],
                   paste0(readLines(committed, warn = FALSE), collapse = "\n"))
})

test_that("the weights roster keeps lockstep with the test roster", {
  .ci_require_checkout()
  lines <- readLines(.ci_ci_locate("shard-weights.tsv"), warn = FALSE)
  data <- lines[!grepl("^\\s*(#|$)", lines)]
  if (length(data) && identical(strsplit(data[1L], "\t", fixed = TRUE)[[1L]],
                                c("file", "seconds", "expects"))) data <- data[-1L]
  rows <- strsplit(data, "\t", fixed = TRUE)
  files <- vapply(rows, `[`, character(1), 1L)
  expect_identical(sort(files), sort(.ci_test_roster()))
  secs <- suppressWarnings(as.integer(vapply(rows, `[`, character(1), 2L)))
  expect_false(any(is.na(secs)))
  expect_gte(min(secs), -1L)   # weights steer balance only; the reporter census is the truth
})

test_that("the fan-out roster pins the four non-representative arms", {
  .ci_require_checkout()
  lines <- readLines(.ci_ci_locate("fanout-configs.tsv"), warn = FALSE)
  rows <- strsplit(lines[!grepl("^\\s*(#|$)", lines)], "\t", fixed = TRUE)
  got <- paste0(vapply(rows, `[`, character(1), 1L), "/",
                vapply(rows, `[`, character(1), 2L))
  expect_identical(sort(got), sort(c("ubuntu-latest/oldrel-1", "macos-latest/release",
                                     "macos-latest/oldrel-1", "windows-latest/oldrel-1")))
})

test_that("the aggregator census FIRES on its shipped self-test controls", {
  .ci_require_checkout()
  r <- .ci_spawn("python3", c(.ci_ci_locate("ci-shard-aggregate.py"), "--self-test"))
  expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err))
  expect_match(r$out, "missing-shard control FIR")
  expect_match(r$out, "zero-executed control FIR")
  expect_match(r$out, "unknown-shard control FIR")
  expect_match(r$out, "good control stays GREEN")
  expect_match(r$out, "AGGREGATE SELF-TEST OK")
})

test_that("a tampered attestation set reddens the strict aggregator", {
  .ci_require_checkout()
  agg <- .ci_ci_locate("ci-shard-aggregate.py")
  dir <- tempfile("attest-tamper-"); dir.create(dir, recursive = TRUE)
  mani <- tempfile("mini-manifest-")
  writeLines(c("# k=2", "shard\tfile\tseconds",
               "1\ttest-alpha.R\t5", "2\ttest-beta.R\t5"), mani)
  write_attest <- function(shard, nfile, executed) {
    writeLines(paste0("MSUITER-ATTEST kind=guards shard=", shard,
                      " files=", nfile, " tests=3 executed=", executed,
                      " pass=3 fail=0 error=0 skip=0 warn=0 status=ok"),
               file.path(dir, paste0("shard-", shard, ".attest")))
  }
  write_attest(1L, 1L, 3L); write_attest(2L, 1L, 3L)
  run <- function() .ci_spawn("python3", c(agg, paste0("--manifest=", mani),
                                            paste0("--attest-dir=", dir),
                                            "--kind", "guards"))
  r <- run()
  expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err)) # control: green set passes
  unlink(file.path(dir, "shard-2.attest"))                          # a shard vanishes
  r <- run()
  expect_identical(r$status, 1L); expect_match(r$out, "missing attestation")
  write_attest(2L, 1L, 0L)                                          # ... and returns having run nothing
  r <- run()
  expect_identical(r$status, 1L); expect_match(r$out, "zero executed")
})

test_that("the runner census FIRES: zero executed work kills the shard", {
  .ci_require_checkout()
  r <- .ci_spawn(.ms_rscript(), c(.ci_ci_locate("run-testthat-shard.R"), "--self-test"))
  expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err))
  expect_match(r$out, "zero-executed control FIR")
  expect_match(r$out, "vacuous attestation FIR")
  expect_match(r$out, "good control GREEN")
  expect_match(r$out, "RUNNER SELF-TEST OK")
})

test_that("shard filters select exactly their roster and nothing else", {
  .ci_require_checkout()
  m <- .ci_parse_manifest(.ci_ci_locate("shard-manifest.tsv"))
  roster <- .ci_test_roster()
  for (s in seq_len(m$k)) {
    f <- .ci_shard_filter(m$rows, s)
    own <- .ci_shard_stems(m$rows$file[m$rows$shard == s])
    alien <- setdiff(.ci_shard_stems(roster), own)
    expect_true(all(grepl(f, own)), info = paste0("shard ", s, " lost a file"))
    expect_true(!any(grepl(f, alien)), info = paste0("shard ", s, " reached foreign files"))
  }
})
