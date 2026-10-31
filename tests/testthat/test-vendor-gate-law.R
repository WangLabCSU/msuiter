# test-vendor-gate-law.R: the discrimination unit for the vendor-budget gate
# law (tools/vendor.sh --check; law text docs/adr/0002-vendor-budget.md).
#
# Why this exists (measured): main push-run 39289131194 (2026-10-19T16:53:28Z)
# failed the guards arm with BOTH byte-exact laws matching exactly
# (uncompressed 16911999 B, tar 18319360 B) while the xz container measured
# 1941840 B against the 1744176 B baseline -- an 11.3% drift produced by the
# runner environment (xz build, threading, CPU topology), not by content. An
# exactness band on an environment-sensitive quantity is a gate-law defect: it
# reds main at random with zero content change. The law now reads: uncompressed
# and tar are byte-exact laws; xz is reported freely and governed only by the
# compressor-sanity law 0 < xz < tar.
#
# Method (house gate-unit lineage: test-gitignore-hygiene.R): the unit drives
# the REAL tools/vendor.sh through its synthetic-measurement seams in a
# scratch directory -- no cargo, no network, no root, no src/rust writes --
# and pins the four discriminations the controller adjudication demands:
#   1. tampered vendor CONTENT (byte added/removed)           -> gate RED
#      (the load-bearing assertion: the content law still bites);
#   2. xz-size drift with unchanged content, far outside the
#      old 0.1% band                                           -> gate GREEN
#      (this incident's false-positive class, closed);
#   3. uncompressed OR tar baseline drift                       -> gate RED
#      (both byte laws alive);
#   4. fully consistent synthetic tree                          -> GREEN end-to-end
#      (negative control: the whole path runs dark-on-green).
# The xz sanity law gets its own firing controls (xz == 0 and xz == tar must
# both RED), because an unfireable guard is a vacuous gate. The Linux branch
# is exercised by injecting the platform identity through the synthetic seam
# (the law is Linux-enforced in production; this host is darwin -- the
# scratch-directory scenario is the proof surface, stated honestly).
#
# Production-default preservation is pinned from both ends: the script text
# keeps the literal baseline constants and has lost the xz size band, and a
# --check run with NO injected baselines against a synthetic tree must RED on
# the baked-in baselines (they are wired into the law, not just printed).

# Shared capability probe: the instrument is the checkout's tools/vendor.sh;
# installed-package check layouts skip on the sanctioned ledger phrase
# (Skip Law -- check-layout-sim.R SANCTIONED_ENDS/SANCTIONED_HAS).
.ms_vg_root <- function() {
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  if (!file.exists(file.path(root, "DESCRIPTION")) ||
      system2("git", c("-C", root, "rev-parse", "--git-dir"),
              stdout = NULL, stderr = NULL) != 0L) {
    return(NULL)
  }
  script <- file.path(root, "tools", "vendor.sh")
  if (!file.exists(script)) {
    # source checkout established, instrument absent -- a real defect, never
    # a silent pass (cjk-census.R discipline).
    stop("tools/vendor.sh missing from the source checkout")
  }
  script
}

# system2 on this base returns the captured output vector with the exit
# status in attr(res, "status"), warning on any nonzero status (house idiom,
# test-kernel-cli.R .kernel_status). Spawned /bin/sh absolute: PATH is not
# trusted to name a specific shell.
.ms_vg_run <- function(script, env = character(), check = TRUE) {
  res <- suppressWarnings(system2("/bin/sh",
                                  c(script, if (check) "--check" else character()),
                                  env = env, stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
        out = paste0(as.character(res), collapse = "\n"),
        lines = as.character(res))
}

# Capability gate (farm .kpp.posix.rig() lineage: the probe reaches for the
# same absolute binary the mechanism certifies). The rig spawns /bin/sh
# absolute, so the probe reads that exact path. Production enforces the gate
# on Linux and darwin ships a real /bin/sh; the absence is a platform fact,
# not a coverage gap -- and the reason speaks the sanctioned ledger phrase
# (SANCTIONED_HAS "not installed").
if (!file.exists("/bin/sh")) {
  skip("the vendor-gate rig spawns /bin/sh absolute (PATH untrusted): the POSIX shell rig is not installed on this platform")
}

# Deterministic synthetic vendor tree: fixed byte fills at fixed sizes, so
# every rebuild is byte-identical and a calibration stays valid across the
# scenario's runs. One non-multiple-of-512 file keeps tar block padding in
# play (realism, zero arithmetic assumptions -- every expectation is
# calibrated from the script's own printed measurements, never re-derived).
.ms_vg_spec <- c(
  "vendor/alpha/src/lib.rs" = 5120L,
  "vendor/beta/src/lib.rs"  = 3072L,
  "vendor/beta/Cargo.toml"  = 2048L,
  "vendor/gamma/data.bin"   = 777L
)

# Rebuild the scratch tree from a spec (size overrides express both byte
# addition and byte removal). The script removes `vendor/` as its final act
# -- the same production cleanup contract runs in synthetic mode -- so every
# scenario invocation starts from a freshly built tree.
.ms_vg_build <- function(scratch, spec = .ms_vg_spec) {
  dirs <- unique(dirname(file.path(scratch, names(spec))))
  for (d in dirs) {
    # dir.create() reports FALSE (and warns) when the directory already
    # exists -- an existing parent is success, not failure.
    if (!dir.exists(d)) {
      suppressWarnings({ ok <- dir.create(d, recursive = TRUE) })
      if (!ok && !dir.exists(d)) stop("scratch tree not creatable: ", d)
    }
  }
  for (rel in names(spec)) {
    # writeBin to a file path: R opens/writes/closes -- deterministic 'a' fill.
    writeBin(rep(as.raw(97L), as.integer(spec[[rel]])), file.path(scratch, rel))
  }
  invisible(scratch)
}

# Parse one printed measure ("vendor <what>:  12345 B (...") -- anchored to
# the measurement figure, never the parenthetical baseline text.
.ms_vg_measure <- function(r, what) {
  pat <- paste0("^vendor ", gsub("[.]", "[.]", what), ":\\s+([0-9]+) B")
  hit <- which(grepl(pat, r$lines))
  if (!length(hit)) {
    stop("measure row '", what, "' absent from the vendor.sh report:\n", r$out)
  }
  as.numeric(sub(paste0(pat, ".*$"), "\\1", r$lines[hit[1L]]))
}

# Calibrate the three measures of the (untampered) synthetic tree by running
# the script in report mode through the synthetic seam: the script's own
# measurements are the only baseline authority -- no sizes are hard-coded.
.ms_vg_calibrate <- function(script, scratch) {
  .ms_vg_build(scratch)
  r <- .ms_vg_run(script, paste0("MSUITER_VENDOR_SYNTH=", scratch), check = FALSE)
  if (!identical(r$status, 0L)) {
    stop("calibration run rc ", r$status, ":\n", r$out)
  }
  m <- c(uncompressed = .ms_vg_measure(r, "uncompressed"),
         tar          = .ms_vg_measure(r, "tar"),
         xz           = .ms_vg_measure(r, "tar.xz"))
  if (anyNA(m) || any(m <= 0)) {
    stop("calibration produced non-positive measures: ",
         paste0(names(m), "=", m, collapse = ", "))
  }
  m
}

# Scenario: rebuild, inject the calibration as baselines + the Linux platform
# identity (the branch where every law is enforced), run --check.
.ms_vg_check <- function(script, scratch, measures, spec = .ms_vg_spec,
                         fake_xz = NULL) {
  .ms_vg_build(scratch, spec)
  env <- c(paste0("MSUITER_VENDOR_SYNTH=", scratch),
           "MSUITER_VENDOR_OS=Linux",
           paste0("MSUITER_VENDOR_BASE_UNCOMPRESSED=",
                  format(measures[["uncompressed"]], scientific = FALSE, trim = TRUE)),
           paste0("MSUITER_VENDOR_BASE_TAR=",
                  format(measures[["tar"]], scientific = FALSE, trim = TRUE)),
           paste0("MSUITER_VENDOR_BASE_XZ=",
                  format(measures[["xz"]], scientific = FALSE, trim = TRUE)))
  if (!is.null(fake_xz)) {
    env <- c(env, paste0("MSUITER_VENDOR_FAKE_XZ=",
                        format(as.integer(fake_xz), scientific = FALSE, trim = TRUE)))
  }
  .ms_vg_run(script, env)
}

test_that("discrimination 1: tampered vendor CONTENT turns the gate RED (content law alive)", {
  script <- .ms_vg_root()
  if (is.null(script)) {
    skip("requires the source checkout (installed-package check context)")
  }
  scratch <- tempfile("vg-content-"); dir.create(scratch, recursive = TRUE)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  m <- .ms_vg_calibrate(script, scratch)

  # Byte ADDITION to one file: the uncompressed sum moved -- the content law
  # must bite. (The tar count may coincidentally survive under block padding;
  # the law order makes the uncompressed row the first to speak.)
  added <- .ms_vg_spec
  added[["vendor/gamma/data.bin"]] <- 778L
  r <- .ms_vg_check(script, scratch, m, spec = added)
  expect_identical(r$status, 1L)
  expect_match(r$out, "uncompressed size drifted")
  expect_match(r$out, "DRIFT DETECTED")
  expect_false(grepl("check OK", r$out, fixed = TRUE))

  # Byte REMOVAL from the same file.
  removed <- .ms_vg_spec
  removed[["vendor/gamma/data.bin"]] <- 776L
  r <- .ms_vg_check(script, scratch, m, spec = removed)
  expect_identical(r$status, 1L)
  expect_match(r$out, "uncompressed size drifted")
})

test_that("discrimination 2: xz-size drift with UNCHANGED content turns the gate GREEN (incident class closed)", {
  script <- .ms_vg_root()
  if (is.null(script)) {
    skip("requires the source checkout (installed-package check context)")
  }
  scratch <- tempfile("vg-xzdrift-"); dir.create(scratch, recursive = TRUE)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  m <- .ms_vg_calibrate(script, scratch)

  # The incident shape: content untouched (byte laws exact), the compressor
  # output lands far outside the old +/-0.1% band -- faked at the script's
  # measurement seam at tar - 1, which is BOTH < tar (sanity law holds) and
  # a drift of hundreds of percent (the old band would have red this).
  r <- .ms_vg_check(script, scratch, m, fake_xz = as.integer(m[["tar"]] - 1L))
  expect_identical(r$status, 0L)
  expect_match(r$out, "check OK")
  expect_false(grepl("DRIFT DETECTED", r$out, fixed = TRUE))

  # Non-vacuousness (firing control for the scenario itself): the faked xz
  # really sits outside the old band, so a GREEN here is a closed false
  # positive, not an unfired test.
  drift_pct <- abs((m[["tar"]] - 1L) - m[["xz"]]) * 100 / m[["xz"]]
  expect_gte(drift_pct, 5)
  # Sanity held: 0 < xz < tar, and the xz row KEEPS being printed.
  xz_measured <- .ms_vg_measure(r, "tar.xz")
  expect_gt(xz_measured, 0)
  expect_lt(xz_measured, m[["tar"]])
  expect_true(any(grepl("^vendor tar[.]xz:\\s+[0-9]+ B", r$lines)))
})

test_that("discrimination 3: uncompressed OR tar drift turns the gate RED (both byte laws alive)", {
  script <- .ms_vg_root()
  if (is.null(script)) {
    skip("requires the source checkout (installed-package check context)")
  }
  scratch <- tempfile("vg-bytelaw-"); dir.create(scratch, recursive = TRUE)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  m <- .ms_vg_calibrate(script, scratch)

  # The tar law bites when the container moves against the exact baseline.
  # The container is regenerated from content on every run, so the drift is
  # injected at the law's comparison operand (the baseline) -- equivalent by
  # the law's own definition: it fires on TAR != BASELINE_TAR.
  r <- .ms_vg_check(script, scratch,
                    c(uncompressed = m[["uncompressed"]],
                      tar = m[["tar"]] + 4096, xz = m[["xz"]]))
  expect_identical(r$status, 1L)
  expect_match(r$out, "tar size drifted")

  # The uncompressed law bites independently (baseline off by one byte).
  r <- .ms_vg_check(script, scratch,
                    c(uncompressed = m[["uncompressed"]] + 1,
                      tar = m[["tar"]], xz = m[["xz"]]))
  expect_identical(r$status, 1L)
  expect_match(r$out, "uncompressed size drifted")
})

test_that("discrimination 4: a fully consistent synthetic tree is GREEN end-to-end (dark-on-green control)", {
  script <- .ms_vg_root()
  if (is.null(script)) {
    skip("requires the source checkout (installed-package check context)")
  }
  scratch <- tempfile("vg-green-"); dir.create(scratch, recursive = TRUE)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  m <- .ms_vg_calibrate(script, scratch)

  r <- .ms_vg_check(script, scratch, m)
  expect_identical(r$status, 0L)
  expect_match(r$out, "check OK")
  expect_false(grepl("DRIFT DETECTED", r$out, fixed = TRUE))
  # All three rows printed on the enforcement (Linux) branch.
  expect_true(any(grepl("^vendor uncompressed:", r$lines)))
  expect_true(any(grepl("^vendor tar:", r$lines)))
  expect_true(any(grepl("^vendor tar[.]xz:", r$lines)))
})

test_that("the xz sanity law FIRES: degenerate compressor outputs RED (no vacuous guard)", {
  script <- .ms_vg_root()
  if (is.null(script)) {
    skip("requires the source checkout (installed-package check context)")
  }
  scratch <- tempfile("vg-sanity-"); dir.create(scratch, recursive = TRUE)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  m <- .ms_vg_calibrate(script, scratch)

  # xz == 0: a compressor that produced nothing must RED (xz > 0 clause).
  r <- .ms_vg_check(script, scratch, m, fake_xz = 0L)
  expect_identical(r$status, 1L)
  expect_match(r$out, "xz sanity")

  # xz == tar: the stream did not shrink -- the compressor is not compressing
  # (xz < tar clause, boundary-exact: equality is already a violation).
  r <- .ms_vg_check(script, scratch, m, fake_xz = as.integer(m[["tar"]]))
  expect_identical(r$status, 1L)
  expect_match(r$out, "xz sanity")
})

test_that("production defaults are preserved: baked baselines wired into the law, xz size band gone", {
  script <- .ms_vg_root()
  if (is.null(script)) {
    skip("requires the source checkout (installed-package check context)")
  }
  src <- readLines(script, warn = FALSE)
  txt <- paste0(src, collapse = "\n")

  # The ADR 0002 byte baselines ride in the script verbatim (load-bearing
  # constants of the content law -- this unit never edits them).
  expect_match(txt, "BASELINE_UNCOMPRESSED=16928778")
  expect_match(txt, "BASELINE_TAR=18339840")
  # The refuted xz size band must be GONE from the law text (reporting the
  # baseline number as context is free; enforcing it is not).
  expect_false(grepl("xz size outside", txt, fixed = TRUE))

  scratch <- tempfile("vg-defaults-"); dir.create(scratch, recursive = TRUE)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  # No injected baselines on the enforcement branch: the synthetic tree is
  # miles below the baked 16928778/18339840 defaults -- the baked values must
  # be LIVE in the law (not merely printed), so the run REDs on them.
  .ms_vg_build(scratch)
  r <- .ms_vg_run(script, c(paste0("MSUITER_VENDOR_SYNTH=", scratch),
                           "MSUITER_VENDOR_OS=Linux"))
  expect_identical(r$status, 1L)
  expect_match(r$out, "uncompressed size drifted")
  expect_match(r$out, "baseline 16928778 B")
})
