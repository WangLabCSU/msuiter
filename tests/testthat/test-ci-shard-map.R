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
.ci_heavy_dir <- function() file.path(.ms_root, "tests", "heavy")
# The manifest partitions the UNION of the two test dirs (issue #76):
# tests/testthat carries tiers T0/T1, tests/heavy carries tier T2.
.ci_test_roster <- function() c(
  list.files(.ci_manifest_dir(), pattern = "^test-.*[.]R$"),
  list.files(.ci_heavy_dir(), pattern = "^test-.*[.]R$"))

test_that("the shard instruments are committed next to the manifest", {
  .ci_require_checkout()
  for (name in c("gen-shard-manifest.R", "run-testthat-shard.R", "run-covr-shard.R",
                 "shard-manifest.tsv", "shard-weights.tsv", "fanout-configs.tsv",
                 "ci-shard-aggregate.py", "covmerge.py",
                 "pr-gate-budget.tsv")) {
    p <- .ms_src(paste0("tools/ci/", name))
    expect_true(isTRUE(file.exists(p)), info = name)   # file.exists(NA) is FALSE: missing instrument = red
  }
  expect_true(isTRUE(file.exists(.ms_src("tools/test-heavy.R"))),
              info = "tools/test-heavy.R -- the tier-T2 one-command face (issue #76)")
})

test_that("the manifest partition is exhaustive, disjoint, and ordered", {
  .ci_require_checkout()
  m <- .ci_parse_manifest(.ci_ci_locate("shard-manifest.tsv"))
  expect_identical(sort(as.character(m$rows$file)), sort(.ci_test_roster())) # nothing lost, nothing invented
  expect_identical(anyDuplicated(m$rows$file), 0L)                          # disjoint (renamed-R returns the first dup index, 0 = none)
  expect_identical(sort(unique(m$rows$shard)), seq_len(m$k))                 # numbered 1..K, no gaps
  # Tier column law (issue #76): every row names a tier, and the tier is
  # a LOCATION law -- the T2 class lives only under tests/heavy and the
  # heavy dir holds nothing else. A shard empty in the PR-gate tiers is
  # lawful (the lane skips it loudly); an unknown tier never is.
  expect_true(all(m$rows$tier %in% c("T0", "T1", "T2")),
              info = "manifest tier outside {T0,T1,T2}")
  heavy.roster <- list.files(.ci_heavy_dir(), pattern = "^test-.*[.]R$")
  expect_true(length(heavy.roster) >= 1L, info = "tests/heavy lost its roster")
  expect_identical(sort(m$rows$file[m$rows$tier == "T2"]), sort(heavy.roster),
                   info = "the tier-T2 class and tests/heavy are not the same set")
  expect_false(any(m$rows$file[m$rows$tier != "T2"] %in% heavy.roster),
               info = "a tests/heavy file rode a non-T2 tier")
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
                                c("file", "seconds", "expects", "tier"))) data <- data[-1L]
  rows <- strsplit(data, "\t", fixed = TRUE)
  expect_true(all(lengths(rows) == 4L),
              info = "weights rows are file\tseconds\texpects\ttier (issue #76)")
  files <- vapply(rows, `[`, character(1), 1L)
  tiers <- vapply(rows, `[`, character(1), 4L)
  names(tiers) <- files
  expect_identical(sort(files), sort(.ci_test_roster()))
  secs <- suppressWarnings(as.integer(vapply(rows, `[`, character(1), 2L)))
  expect_false(any(is.na(secs)))
  expect_gte(min(secs), -1L)   # weights steer balance only; the reporter census is the truth
  expect_true(all(tiers %in% c("T0", "T1", "T2")),
              info = "weights tier outside {T0,T1,T2}")
  # The accepted proposal's tier assignments are law, not taste (issue
  # #76): the T2 class is exactly the two provisioning simulations, T1 is
  # the named scheduled deep battery, and the bit-identity pair may never
  # leave the PR gate.
  expect_identical(sort(files[tiers == "T2"]),
                   sort(c("test-check-layout-sim-sentry.R", "test-check-layout-sim-stale.R")))
  expect_identical(sort(files[tiers == "T1"]),
                   sort(c("test-xval-m2-extract.R", "test-refdb.R",
                          "test-ms-qc-sentries.R", "test-ms-benchmark-driver.R")))
  expect_identical(unname(tiers[sort(c("test-kernel-bit-identity.R", "test-kernel-batch-bridge.R"))]),
                   c("T0", "T0"), info = "the bit-identity battery may not leave the PR gate")
  # The weights tier and the manifest tier are one committed fact, file
  # by file -- a hand-edit on one side alone is a defect.
  m <- .ci_parse_manifest(.ci_ci_locate("shard-manifest.tsv"))
  mt <- m$rows$tier
  names(mt) <- m$rows$file
  expect_identical(mt[files], tiers[files],
                   info = "weights tier drifts from the manifest tier")
})

test_that("the fan-out rosters keep the eight-arm census across the two gates (issue #76)", {
  .ci_require_checkout()
  rd_roster <- function(name) {
    lines <- readLines(.ci_ci_locate(name), warn = FALSE)
    rows <- strsplit(lines[!grepl("^\\s*(#|$)", lines)], "\t", fixed = TRUE)
    expect_true(all(lengths(rows) == 2L), info = name)
    paste0(vapply(rows, `[`, character(1), 1L), "/",
           vapply(rows, `[`, character(1), 2L))
  }
  pr <- rd_roster("fanout-configs.tsv")
  sv <- rd_roster("scheduled-fanout-configs.tsv")
  # The PR gate is three release-R arms (issue #76): the wall-clock ruling
  # moved the five version arms to the nightly version fan-out, where the
  # tier-T1 deep battery gained a release-R witness -- ubuntu/release rides
  # both gates. The historical eight-arm census survives exactly as the union
  # of the two rosters: the schedule moved, the coverage did not.
  expect_identical(sort(pr), sort(c("macos-latest/release", "ubuntu-latest/release",
                                    "windows-latest/release")))
  expect_identical(sort(sv), sort(c("macos-latest/oldrel-1", "ubuntu-latest/4.3",
                                    "ubuntu-latest/devel", "ubuntu-latest/release",
                                    "ubuntu-latest/oldrel-1", "windows-latest/oldrel-1")))
  expect_identical(sort(unique(c(pr, sv))),
                   sort(c("ubuntu-latest/4.3", "ubuntu-latest/release",
                          "ubuntu-latest/devel", "ubuntu-latest/oldrel-1",
                          "windows-latest/release", "windows-latest/oldrel-1",
                          "macos-latest/release", "macos-latest/oldrel-1")))
  # A roster with no live face is a silent green: the version fan-out must
  # ride the scheduled file -- budgeted, deep-tier, and reading its own roster.
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  sched <- readLines(file.path(root, ".github", "workflows", "scheduled.yml"), warn = FALSE)
  h <- which(sched == "  R-CMD-check-version-fanout:")
  expect_identical(length(h), 1L, info = "the scheduled version fan-out vanished")
  win <- sched[seq(from = h + 1L, to = length(sched))]
  nxt <- which(grepl("^  [A-Za-z0-9_-]+:$", win))
  if (length(nxt)) win <- win[seq_len(nxt[1L] - 1L)]
  t <- win[grepl("timeout-minutes:", win, fixed = TRUE)]
  expect_identical(length(t), 1L, info = "version fan-out without an explicit budget")
  expect_identical(trimws(sub("timeout-minutes:", "", t[1L], fixed = TRUE)), "180",
                   info = "the uniform hang-detector ceiling is arm-independent")
  body <- paste0(win, collapse = "\n")
  expect_true(grepl("--tier=T0,T1", body, fixed = TRUE),
              info = "the scheduled arms must run the deep tier, not the PR-gate one")
  expect_true(grepl("scheduled-fanout-configs.tsv", body, fixed = TRUE),
              info = "the version fan-out is not data-driven off its committed roster")
  expect_true(grepl("pr-gate-budget.tsv", body, fixed = TRUE),
              info = "the version census runs without the committed T0 budget")
})

test_that("the CRAN-shape monolithic check rides the scheduled gate, not the PR gate", {
  .ci_require_checkout()
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  rd <- function(f) readLines(file.path(root, ".github", "workflows", f), warn = FALSE)
  ci <- rd("ci.yml")
  sched <- rd("scheduled.yml")
  # The single-process CRAN-shape check keeps its science (serial state, CRAN
  # gates) but loses its per-PR wall-clock veto: it moves to the daily gate.
  expect_false(any(grepl("check-r-package", ci, fixed = TRUE)),
               info = "ci.yml still invokes the monolithic check-r-package action")
  expect_true(any(grepl("check-r-package", sched, fixed = TRUE)),
               info = "scheduled.yml lost the CRAN-shape monolithic check")
})

test_that("the aggregator census FIRES on its shipped self-test controls", {
  .ci_require_checkout()
  r <- .ci_spawn("python3", c(.ci_ci_locate("ci-shard-aggregate.py"), "--self-test"))
  expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err))
  expect_match(r$out, "missing-shard control FIR")
  expect_match(r$out, "zero-executed control FIR")
  expect_match(r$out, "unknown-shard control FIR")
  expect_match(r$out, "good control stays GREEN")
  # Issue #76 controls: the tier-scoped census and the committed budget.
  expect_match(r$out, "tier-empty-shard needs-no-attestation control stays GREEN")
  expect_match(r$out, "tier-deepened census control FIR")
  expect_match(r$out, "tier-blind attestation control FIR")
  expect_match(r$out, "out-of-tier registered marker control stays GREEN")
  expect_match(r$out, "out-of-tier rogue marker control FIR")
  expect_match(r$out, "T0-budget ceiling control FIR")
  expect_match(r$out, "T0-budget headroom control stays GREEN")
  expect_match(r$out, "AGGREGATE SELF-TEST OK")
})

test_that("a tampered attestation set reddens the strict aggregator", {
  .ci_require_checkout()
  agg <- .ci_ci_locate("ci-shard-aggregate.py")
  dir <- tempfile("attest-tamper-"); dir.create(dir, recursive = TRUE)
  mani <- tempfile("mini-manifest-")
  writeLines(c("# k=2", "shard\tfile\tseconds\ttier",
               "1\ttest-alpha.R\t5\tT0", "2\ttest-beta.R\t5\tT0"), mani)
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
  # Issue #76 controls: the lane plan skips, deepens and refuses.
  expect_match(r$out, "T0-empty-shard skip control FIR")
  expect_match(r$out, "T1-inclusion control FIR")
  expect_match(r$out, "T2-refusal control FIR")
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

test_that("the tier partition isolates the deep battery and the heavy class (issue #76)", {
  .ci_require_checkout()
  m <- .ci_parse_manifest(.ci_ci_locate("shard-manifest.tsv"))
  # The xval campaign stands alone in its shard, so the PR-gate window
  # must find that shard empty and the scheduled window must find it
  # exactly there -- this is the de-duplication the ruling bought: the
  # 948 s campaign no longer rides every per-push arm.
  xval.shard <- unique(m$rows$shard[m$rows$file == "test-xval-m2-extract.R"])
  expect_identical(length(xval.shard), 1L)
  p0 <- .ci_tier_rows(m$rows[m$rows$shard == xval.shard, , drop = FALSE], "T0")
  expect_identical(nrow(p0), 0L)
  p01 <- .ci_tier_rows(m$rows[m$rows$shard == xval.shard, , drop = FALSE], c("T0", "T1"))
  expect_identical(p01$file, "test-xval-m2-extract.R")
  # The two heavy files are visible ONLY through the T2 window.
  p2 <- .ci_tier_rows(m$rows, "T2")
  expect_identical(sort(p2$file),
                   sort(c("test-check-layout-sim-sentry.R", "test-check-layout-sim-stale.R")))
  expect_identical(nrow(.ci_tier_rows(p2, c("T0", "T1"))), 0L)
  # An unknown tier is a defect, never a silent empty roster.
  bad <- tryCatch({ .ci_tier_rows(m$rows, "T7"); FALSE },
                  error = function(e) grepl("tier", conditionMessage(e)))
  expect_true(isTRUE(bad), info = ".ci_tier_rows rode an unknown tier unseen")
})

test_that("the committed T0 budget bounds the PR-gate battery and the generator enforces it (issue #76)", {
  .ci_require_checkout()
  bud <- readLines(.ci_ci_locate("pr-gate-budget.tsv"), warn = FALSE)
  kv <- strsplit(bud[!grepl("^\\s*(#|$)", bud)], "\t", fixed = TRUE)
  key <- vapply(kv, `[`, character(1), 1L)
  val <- suppressWarnings(as.integer(vapply(kv, `[`, character(1), 2L)))
  names(val) <- key
  expect_false(any(is.na(val[c("t0-measured", "t0-ceiling")])),
               info = "pr-gate-budget.tsv lacks numeric t0-measured/t0-ceiling rows")
  expect_gte(val[["t0-ceiling"]], val[["t0-measured"]])
  # Recompute the T0 weight from the committed weights table -- the same
  # integer arithmetic the generator and the aggregator run.
  lines <- readLines(.ci_ci_locate("shard-weights.tsv"), warn = FALSE)
  data <- lines[!grepl("^\\s*(#|$)", lines)]
  rows <- strsplit(data[-1L], "\t", fixed = TRUE)
  t0 <- suppressWarnings(as.integer(vapply(rows[lengths(rows) == 4L],
    function(r) if (identical(r[[4L]], "T0")) r[[2L]] else NA_character_, character(1))))
  t0sum <- sum(t0, na.rm = TRUE)
  expect_identical(as.integer(t0sum), as.integer(val[["t0-measured"]]))
  expect_lte(as.integer(t0sum), as.integer(val[["t0-ceiling"]]))
  # Destructive controls against the production generator: drift off the
  # committed measurement must die, over-ceiling must die naming the
  # ceiling, and the tier location law must reject a misclassified row.
  gen <- .ci_ci_locate("gen-shard-manifest.R")
  die <- function(lines2, want) {
    w <- tempfile("weights-tamper-"); writeLines(lines2, w)
    o <- tempfile("manifest-out-")
    r <- .ci_spawn(.ms_rscript(), c(gen, paste0("--weights=", w), paste0("--out=", o)))
    expect_identical(r$status, 1L, info = paste0("generator tolerated the tamper:\n", r$out, "\n", r$err))
    expect_true(any(grepl(want, c(strsplit(r$err, "\n", fixed = TRUE)[[1L]],
                                  strsplit(r$out, "\n", fixed = TRUE)[[1L]]))),
                info = paste0("died, but not on ", want, ": ", r$err, r$out))
  }
  rebuild <- function(line, sec) {
    p <- strsplit(line, "\t", fixed = TRUE)[[1L]]
    paste0(p[1L], "\t", sec, "\t", p[3L], "\t", p[4L])
  }
  bump <- data
  i <- which(vapply(strsplit(data, "\t", fixed = TRUE), `[`, character(1), 1L) ==
             "test-kernel-gate-evidence.R")
  bump[i] <- rebuild(data[i], "100")    # +100: drifts, but still under the ceiling
  die(bump, "moved")
  over <- data
  over[i] <- rebuild(data[i], "3000")   # blows through the ceiling outright
  die(over, "exceeds the committed ceiling")
  mis <- data
  j <- which(sub("\t.*", "", data) == "test-check-layout-sim-sentry.R")
  mis[j] <- sub("T2$", "T0", data[j])
  die(mis, "T2")
})

test_that("tools/test-heavy.R self-test speaks its firing controls (issue #76)", {
  .ci_require_checkout()
  r <- .ci_spawn(.ms_rscript(), c(.ms_src("tools/test-heavy.R"), "--self-test"))
  expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err))
  expect_match(r$out, "tier-validation control FIR")
  expect_match(r$out, "heavy tier-skip roster control FIR")
  expect_match(r$out, "zero-executed gate control FIR")
  expect_match(r$out, "loud-failure verdict control FIR")
  expect_match(r$out, "HEAVY SELF-TEST OK")
})

test_that("job budgets cover the measured tails -- no arm dies on its own timer", {
  # Law from run 39815352743 (2026-10-22): four strikes that read as external
  # cancels were the platform faithfully executing self-declared budgets.
  # ubuntu/oldrel-1 measured 19m45s setup-r + 15m25s setup-r-deps of runner
  # slowness before its 60-minute timer severed a healthy testthat wave at
  # 21 of ~25 minutes; guard-prep likewise died at its 30-minute mark behind
  # a stalled runner. A budget is a hang detector, not a starvation engine:
  # it must exceed the measured tail with headroom.
  .ci_require_checkout()
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  ci <- readLines(file.path(root, ".github", "workflows", "ci.yml"), warn = FALSE)
  budget_line <- function(key) {
    hdr <- paste0("  ", key, ":")
    h <- which(ci == hdr)
    expect_identical(length(h), 1L, info = key)
    win <- ci[(h + 1L):length(ci)]
    t <- win[grepl("timeout-minutes:", win, fixed = TRUE)]
    expect_gte(length(t), 1L)   # a job without an explicit budget is a green-hang invitation
    trimws(sub("timeout-minutes:", "", t[1L], fixed = TRUE))
  }
  expect_identical(budget_line("guard-prep"), "45")     # hot path 1 min; stall class needs slack (strike-3 witness)
  expect_identical(budget_line("guards"), "15")          # aggregator-only, measured 0 min
  expect_identical(budget_line("guards-shards"), "120")  # old 60 starved a healthy arm: green witness 57m27s (run 40822738417 attempt-2, 96 % of the line); two kill witnesses -- PR #60 attempt-1 (all 16 steps run, 61-min wall) and push-run 40844971894 job 123350746358 (steps 1-11 green, step 12 in-flight at 57.5m, severed at 60:13) -- zero hang signatures; 120 = witnessed floor + one pool-slowness class, the uniform fan-out ceiling
  expect_identical(budget_line("coverage"), "180")      # hot 18 min; 90 consumed whole twice by PR #52 (runs 40013789288/40028404425) vs main's 68m53s tail (push-run 39965044133); 120 then consumed whole thrice by PR #56 (run 40667262104 job 122744792649 120m27s; run 40700329158 attempt1 job 122858082848 120m26s + its attempt-2 rerun 120m34s, heartbeat flat 5/6 with live pinned 1/7) -- the straggler-shard class re-created by the manifest re-pack; 180 = witnessed >=118m straggler floor + one runner-slowness class of headroom
  # Second witness (run 39839340513, 2026-10-23): the slow-runner class is a
  # RUNNER property, not an arm property -- the 10-22 strike hit ubuntu/oldrel-1,
  # this one hit ubuntu/release + coverage. An arm whitelist is whack-a-mole;
  # every fan-out arm rides the uniform hang-detector ceiling.
  expect_identical(budget_line("R-CMD-check-fanout"), "180")  # 120 consumed whole twice by push-run 41082179842 on main@a6c5870 (attempt-1 job 124154845151 2h01m03s; targeted rerun-failed attempt-2 job 124412728178 2h00m31s -- both: steps 1-13 completed/success, fan-out wave severed mid-flight, post-steps clean, zero hang signatures); 180 = witnessed >=120m straggler floor + one runner-slowness class, the uniform line the coverage arm already carries
})

test_that("the covr coverage aggregate is ledger-gated, never advisory", {
  .ci_require_checkout()
  ci <- readLines(.ci_ci_locate(file.path("..", "..", ".github", "workflows", "ci.yml")),
                  warn = FALSE)
  # Shell line continuations belong to their command: fold them before the
  # scan, or a --ledger riding the next physical line hides from a --kind scan.
  ci <- gsub("[[:space:]]*\\\\[[:space:]]*\n", " ", paste0(ci, collapse = "\n"))
  ci <- strsplit(ci, "\n", fixed = TRUE)[[1L]]
  line <- grep("--kind coverage", ci, fixed = TRUE, value = TRUE)
  expect_true(any(grepl("--ledger", paste(line, collapse = "\n"), fixed = TRUE)),
               info = "coverage aggregate must consult the divergences ledger")
  expect_false(any(grepl("--advisory", paste(line, collapse = "\n"), fixed = TRUE)),
               label = "coverage aggregate still runs --advisory (vacuous green)")
  expect_false(any(grepl("|| true", paste(line, collapse = "\n"), fixed = TRUE)),
               label = "coverage aggregate still swallows its exit code")
  ledger <- .ci_ci_locate("covr-divergences.tsv")
  expect_true(file.exists(ledger))
  rows <- readLines(ledger, warn = FALSE)
  rows <- rows[!grepl("^#", rows) & nzchar(rows)]
  fields <- strsplit(rows, "\t", fixed = TRUE)
  lens <- vapply(fields, length, integer(1L))
  # Issue #76 retired the two tier-T2 sanction rows -- the covr lane's
  # mandatory --tier=T0,T1 keeps those files out of the coverage roster
  # by construction, and the reverse audit makes a zombie row a defect.
  # An empty active ledger is lawful exactly while that tier law holds;
  # any row must still be the full four-field shape.
  expect_true(identical(lens, integer(0)) || identical(unique(lens), 4L),
                info = "ledger rows are shard\tfiles\twhy\twitness (empty is lawful; issue #76)")
  expect_false(any(grepl("test-check-layout-sim-sentry.R", rows, fixed = TRUE) |
                         grepl("test-check-layout-sim-stale.R", rows, fixed = TRUE)),
               info = "a retired tier-T2 sanction came back without the tier law changing")
  shards <- vapply(fields, `[[`, character(1L), 1L)
  expect_identical(shards, unique(shards), info = "ledger shards must be unique")
  expect_true(all(grepl("^[0-9]+$", shards)), info = "ledger shards are integers")
  witnesses <- vapply(fields, `[[`, character(1L), 4L)
  expect_true(all(nzchar(witnesses)), info = "every sanction carries a witness")
})

test_that("the coverage ledger is reverse-audited and its controls FIRE", {
  .ci_require_checkout()
  agg <- .ci_ci_locate("ci-shard-aggregate.py")
  dir <- tempfile("covr-ledger-"); dir.create(dir, recursive = TRUE)
  mani <- tempfile("covr-mini-manifest-")
  writeLines(c("# k=2", "shard\tfile\tseconds\ttier",
               "1\ttest-a.R\t5\tT0", "2\ttest-b.R\t5\tT0"), mani)
  writeLines("MSUITER-ATTEST kind=coverage shard=1 files=0 tests=1 executed=0 pass=0 fail=0 error=0 skip=1 warn=0 status=vacuous",
             file.path(dir, "shard-1.attest"))
  writeLines("MSUITER-ATTEST kind=coverage shard=2 files=1 tests=4 executed=4 pass=9 fail=0 error=0 skip=0 warn=0 status=ok",
             file.path(dir, "shard-2.attest"))
  run_agg <- function(ledger) {
    args <- c(agg, paste0("--manifest=", mani), paste0("--attest-dir=", dir),
              "--kind", "coverage")
    if (!is.null(ledger)) args <- c(args, paste0("--ledger=", ledger))
    .ci_spawn("python3", args)
  }
  # Without the ledger the vacuous shard is a plain defect (no silent pass).
  r <- run_agg(NULL)
  expect_identical(r$status, 1L, info = paste0(r$out, "\n", r$err))
  expect_match(r$out, "zero executed")
  # The true sanction turns it green -- and says so.
  led <- tempfile("covr-div-"); writeLines(c(
    "# comment row ignored",
    "1\ttest-a.R\t-\twitnessed by the self-test fixture"), led)
  r <- run_agg(led)
  expect_identical(r$status, 0L, info = paste0(r$out, "\n", r$err))
  expect_match(r$out, "SANCTIONED")
  expect_match(r$out, "sanctioned=1")
  # A forged why does not match the attestation's absent why: red stays red.
  led2 <- tempfile("covr-div2-"); writeLines("1\ttest-a.R\tbogus-why\twitness", led2)
  r <- run_agg(led2)
  expect_identical(r$status, 1L)
  expect_match(r$out, "does not match")
  # A covr-failed masquerade is never sanctionable by the census-class row.
  writeLines("MSUITER-ATTEST kind=coverage shard=1 files=0 tests=0 executed=0 pass=0 fail=0 error=0 skip=0 warn=0 status=vacuous why=covr-failed", file.path(dir, "shard-1.attest"))
  r <- run_agg(led)
  expect_identical(r$status, 1L)
  expect_match(r$out, "covr-failed")
  # Stale rows are themselves defects: the ledger may never bank silence.
  writeLines("MSUITER-ATTEST kind=coverage shard=1 files=1 tests=4 executed=4 pass=9 fail=0 error=0 skip=0 warn=0 status=ok", file.path(dir, "shard-1.attest"))
  r <- run_agg(led)
  expect_identical(r$status, 1L)
  expect_match(r$out, "stale divergences row")
})

test_that("the covr merge gate reddens zero fragments and the extras prefix cannot drift", {
  .ci_require_checkout()
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  rd <- function(f) paste0(readLines(file.path(root, f), warn = FALSE), collapse = "\n")
  ci <- rd(".github/workflows/ci.yml")
  # The birth defect (attested 2026-10-24): zero fragments echoed and exited
  # 0 -- a vacuous green under the census law of the same day.
  expect_true(any(grepl("no coverage fragments produced.*exit 1", ci)),
              info = "the covr merge step exits green on zero fragments again")
  expect_false(any(grepl("no coverage fragments produced.*exit 0", ci)),
              info = "the zero-fragment path regressed to the vacuous exit 0")
  # The second birth defect: the call-site passed --out-srt-prefix=/tmp while
  # the writer paste0-joined prefix+name -- every extras fragment ever written
  # landed at "/tmpmsuiter-extras-*" (read-only root on runners), so
  # examples/vignettes coverage silently never merged. The normalizer lives in
  # the runner so no call site can re-miss the slash.
  ex <- rd("tools/ci/run-covr-extras.R")
  expect_true(any(grepl(".dir.prefix(", ex, fixed = TRUE)),
              info = "run-covr-extras lost the prefix normalizer")
  expect_true(any(grepl("prefix <- .dir.prefix(", ex, fixed = TRUE)),
              info = "production no longer routes out-srt-prefix through the normalizer")
})

test_that("a cached R path cannot survive into the cargo jobs", {
  # Law from run 40959865870 (2026-10-30): the rust and msrv cargo jobs share
  # src/rust/target through Swatinem/rust-cache. The extendr-ffi build script
  # (0.9.0, build.rs:212) bakes the absolute R library directory into a
  # rustc-link-search instruction and declares no rerun trigger for R_HOME
  # (:244 covers only R_INCLUDE_DIR), so when setup-r floats the runner's R
  # (release 4.6.1 -> 4.6.2) the restored output still links against the old
  # tree: rust-lld "unable to find library -lR". Any job that restores a
  # shared target and builds the extendr shell crate must drop the
  # extendr-ffi build-script output after the cache restore and before the
  # first full-workspace cargo step.
  .ci_require_checkout()
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  ci <- readLines(file.path(root, ".github", "workflows", "ci.yml"), warn = FALSE)
  job_window <- function(key) {
    h <- which(ci == paste0("  ", key, ":"))
    expect_identical(length(h), 1L, info = key)
    win <- ci[seq(from = h + 1L, to = length(ci))]
    nxt <- which(grepl("^  [A-Za-z0-9_-]+:$", win))
    if (length(nxt)) win[seq_len(nxt[1L] - 1L)] else win
  }
  for (key in c("rust", "msrv")) {
    win <- job_window(key)
    cache_i <- which(grepl("Swatinem/rust-cache@", win, fixed = TRUE))
    cargo_i <- which(grepl("cargo [^\\n]*--workspace", win))
    clean_i <- which(grepl("clean -p extendr-ffi", win, fixed = TRUE))
    # The patterns must speak on the committed bytes before the ordering
    # assertions mean anything (vacuous-green ban).
    expect_true(length(cache_i) >= 1L, info = paste0(key, ": cache restore"))
    expect_true(length(cargo_i) >= 1L, info = paste0(key, ": workspace build"))
    expect_identical(length(clean_i), 1L, info = paste0(key, ": invalidation step"))
    expect_true(cache_i[1L] < clean_i[1L], info = paste0(key, ": restore then invalidate"))
    expect_true(clean_i[1L] < min(cargo_i), info = paste0(key, ": invalidate before link"))
  }
})
