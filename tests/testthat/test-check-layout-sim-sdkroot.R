# U-M8 release-eng item 3: SDKROOT self-discovery for the harness's fallback
# R CMD INSTALL (tools/check-layout-sim.R, .sdkroot_default).
#
# Motivating environment facts (devlog 2026-10-01 / 2026-10-04, harness block
# 2b): on macOS CLT machines whose MacOSX.sdk alias dangles (SDK 27
# libSystem.B.tbd trips tapi) the native build needs SDKROOT pinned to a
# working SDK; previously the operator had to export it BEFORE driving the
# harness. .sdkroot_default now offers that ambient default itself: it probes
# xcrun --show-sdk-path, then the standard CLT SDK directory -- on darwin
# only, and only while SDKROOT is unset/empty. An explicitly exported value
# (e.g. the devlog-pinned MacOsX26.5.sdk) always wins untouched, and when
# nothing trustworthy is found the helper returns NA and the environment is
# left exactly as it was (the branch CI's checked toolchain walks).
#
# The units drive the REAL extracted helper through .sim_defs (now shared via
# helper-check-layout.R) with an injected xcrun stub and fabricated SDK dirs:
# no unit reads the host's xcrun, /Library/Developer/CommandLineTools, or the
# ambient SDKROOT.

.fake.sdk <- function(with.include = TRUE) {
  d <- tempfile("fake-sdk-")
  target <- if (with.include) file.path(d, "usr", "include") else d
  dir.create(target, recursive = TRUE)
  if (!dir.exists(target)) {
    skip(paste0("cannot fabricate probe fixture at ", target))
  }
  d
}
# Stub xcrun: one echo line to stdout (+ optional non-zero rc). The helper
# invokes its xcrun argument by ABSOLUTE path, so no PATH resolution is
# involved anywhere -- mirrored here by construction.
.xcrun.stub <- function(stdout.text, rc = 0L) {
  p <- tempfile("xcrun-stub-")   # tempfile's parent Rtmp dir exists; p does not
  writeLines(c("#!/bin/sh",
               paste0("printf '%s\\n' '", stdout.text, "'"),
               paste0("exit ", as.integer(rc))),
             p)
  Sys.chmod(p, mode = "0755")
  p
}
.UNSET <- function(name, default = "") default   # ambient: nothing exported

test_that("SDKROOT self-discovery: an explicitly set SDKROOT is never touched", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  # the stub WOULD be adopted if consulted -- returning NA proves the
  # override branch short-circuits BEFORE any probe
  sdk <- .fake.sdk()
  stub <- .xcrun.stub(sdk)
  out <- f(getenv = function(name, default = "") {
             if (identical(name, "SDKROOT")) "/pinned/MacOsX26.5.sdk" else default
           },
           os = "darwin", xcrun = stub, clt.sdk = .fake.sdk())
  expect_identical(out, NA_character_)
})

test_that("SDKROOT self-discovery: unset SDKROOT adopts a healthy xcrun probe", {
  # The fixture executes a POSIX shebang stub; windows runners cannot
  # faithfully run the darwin probe. This path is exercised for real by the
  # macOS CI arm and the local macOS battery. Stated as a registered skip
  # reason rather than skip_on_os: the check-layout-sim Skip Law (ledger in
  # tools/check-layout-sim.R) admits only described reasons, not testthat's
  # generic "On Windows".
  if (identical(.Platform$os.type, "windows")) {
    skip("POSIX shebang stub executor not installed on this platform")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  sdk <- .fake.sdk()
  out <- f(getenv = .UNSET, os = "darwin",
           xcrun = .xcrun.stub(sdk), clt.sdk = "/no/such/clt/sdk")
  expect_identical(out, sdk)
})

test_that("SDKROOT self-discovery: an empty-string SDKROOT counts as unset", {
  if (identical(.Platform$os.type, "windows")) {
    skip("POSIX shebang stub executor not installed on this platform")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  sdk <- .fake.sdk()
  out <- f(getenv = function(name, default = "") "", os = "darwin",
           xcrun = .xcrun.stub(sdk), clt.sdk = "/no/such/clt/sdk")
  expect_identical(out, sdk)
})

test_that("SDKROOT self-discovery: stays out on non-darwin platforms", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  # both probes healthy -- a non-NA return here would poison linux CI
  out <- f(getenv = .UNSET, os = "linux",
           xcrun = .xcrun.stub(.fake.sdk()), clt.sdk = .fake.sdk())
  expect_identical(out, NA_character_)
})

test_that("SDKROOT self-discovery: absent xcrun falls through to the CLT SDK dir", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  clt <- .fake.sdk()
  out <- f(getenv = .UNSET, os = "darwin",
           xcrun = "/no/such/xcrun", clt.sdk = clt)
  expect_identical(out, clt)
})

test_that("SDKROOT self-discovery: a probe dir without usr/include is rejected", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  broken <- .fake.sdk(with.include = FALSE)          # exists, but no usr/include
  clt <- .fake.sdk()                                  # healthy fallback candidate
  out <- f(getenv = .UNSET, os = "darwin",
           xcrun = .xcrun.stub(broken), clt.sdk = clt)
  expect_identical(out, clt)
})

test_that("SDKROOT self-discovery: failing xcrun rc falls through, nothing found gives NA", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".sdkroot_default")
  f <- get(".sdkroot_default", envir = env)
  # rc != 0: probe output ignored despite naming a real SDK
  sdk <- .fake.sdk()
  out1 <- f(getenv = .UNSET, os = "darwin",
            xcrun = .xcrun.stub(sdk, rc = 1L), clt.sdk = "/no/such/clt/sdk")
  expect_identical(out1, NA_character_)
  # nothing discoverable at all: graceful NA (the CI branch -- env untouched)
  out2 <- f(getenv = .UNSET, os = "darwin",
            xcrun = "/no/such/xcrun", clt.sdk = "/no/such/clt/sdk")
  expect_identical(out2, NA_character_)
})
