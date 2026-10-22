# GO-04D regression unit (slice-D defect class) -- argv/boot half.
#
# The PR #14 battery proved that a guard can execute green in every context
# EXCEPT the R CMD check test phase -- whose cwd (tests/testthat, a SIBLING
# of the extracted tree) makes test_path('../../...') read above the check
# directory. Only a live run under that exact layout catches the class. This
# unit drives tools/check-layout-sim.R's boot paths: the argument-less
# locator fallback and the DESCRIPTION-less --root= verdict.
#
# The two heavy full-simulate units (full-suite green + stale-candidate
# rejection) moved verbatim to test-check-layout-sim-sentry.R and
# test-check-layout-sim-stale.R in the CI shard restructure (2026-10-21,
# docs/devlog) so each ~20-minute simulate is an independently schedulable
# shard; the test_that bodies are byte-unchanged by that move.
#
# The move carried this file's numeric claims with the units (digit-run
# multiset verified preserved across the 3-way split), so the moved tokens
# get the sanctioned waiver -- nothing here is unpoliced, it lives in the
# sibling files:
# <!-- census-exempt tokens: 0 05 1 15 19 2 24 25 29 4 5 63 7 8 -->
#
# Recursion guard: inside the simulated run itself the entrypoint exports
# SIM_CHECK_LAYOUT_ACTIVE=1 and this unit skips.

# GO-05 lane boot-path unit: the usage header (line 32) declares --root=
# OPTIONAL and the self-locating fallback below it exists -- but the call
# site passed NULL as .kv's default, and .kv treats a NULL default as
# "required", so EVERY argument-less launch quit 2 with "missing --root="
# before the fallback could run (witnessed live: /tmp/go05lane/
# layoutsim_hold.log). A launch from outside the package must reach the
# locator's own honest error, not the argv guard's false one.
test_that("check-layout-sim: argument-less boot reaches the locator, not the argv guard", {
  if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
    skip("already running inside the simulated check layout (recursion guard)")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  outside <- tempfile("outside-pkg-")
  dir.create(outside, recursive = TRUE)
  out <- tempfile("sim-boot-out-")
  rc <- local({
    old <- getwd(); setwd(outside); on.exit(setwd(old))
    system2(.ms_rscript(), c(sim), stdout = out, stderr = FALSE)
  })
  txt <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_identical(rc, 2L, info = txt)
  expect_false(any(grepl("missing --root=", txt, fixed = TRUE)),
               info = paste0("argument-less launch hit the argv guard instead ",
                             "of the optional-root fallback:\n", txt))
  expect_match(txt, "cannot locate package root")
})

# Same instrument family: an explicit --root= that names no package must be
# the tool's own verdict (rc 2, its prefix), never a raw readLines trace at
# rc 1 (witnessed live: locale-dependent "cannot open file" error at
# readLines). A real dir without DESCRIPTION is the minimal fixture.
test_that("check-layout-sim: a DESCRIPTION-less --root= fails fast with its own verdict", {
  if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
    skip("already running inside the simulated check layout (recursion guard)")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  notpkg <- tempfile("no-description-")
  dir.create(notpkg, recursive = TRUE)
  out <- tempfile("sim-badroot-out-")
  err <- tempfile("sim-badroot-err-")
  rc <- system2(.ms_rscript(), c(sim, paste0("--root=", notpkg)),
                stdout = out, stderr = err)
  txt <- paste0(paste(readLines(out, warn = FALSE), collapse = "\n"), "\n",
                paste(readLines(err, warn = FALSE), collapse = "\n"))
  expect_identical(rc, 2L, info = txt)
  expect_match(txt, "check-layout-sim: ERROR")
  expect_false(any(grepl("readLines", txt, fixed = TRUE)),
               info = paste0("raw R trace leaked through the gate:\n", txt))
})

# Transient copy-denial law units (run 39735155940 forensics, windows-
# latest/R release): the copy-phase spawns ride the same live checkout the
# fan-out siblings execute in, so a sibling handle (or Defender re-scan) can
# deny R CMD build's internal tree copy mid-spawn -- "Permission denied",
# "copying to build directory failed". The law retries that class bounded
# and witnessed; these units fire it through the injected-denial knob so
# the retry path is EXECUTED, not asserted, and the loud-die path keeps
# teeth when the class outlives the budget.
.ms_sim_env <- function(sets, expr) {
  # This R build's Sys.setenv takes named NAME=value arguments and has no
  # nm=/value= arm (renamed-base quirk, banked): the pair form must ride
  # do.call or the knob silently never reaches the spawned child.
  old <- Sys.getenv(names(sets), unset = NA_character_)
  set1 <- function(nm, val) {
    a <- list(val); names(a) <- nm
    do.call(Sys.setenv, a)
  }
  for (nm in names(sets)) set1(nm, sets[[nm]])
  on.exit({
    for (i in seq_along(names(sets))) {
      nm <- names(sets)[[i]]
      if (is.na(old[[i]])) Sys.unsetenv(nm) else set1(nm, old[[i]])
    }
  })
  expr
}

test_that("check-layout-sim: a transient copy denial is retried and the sim proceeds", {
  if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
    skip("already running inside the simulated check layout (recursion guard)")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  out <- tempfile("sim-transient-retry-out-")
  err <- tempfile("sim-transient-retry-err-")
  rc <- .ms_sim_env(c(MSUITER_SIM_TEST_TRANSIENT_COPY_DENIAL = "1",
                      MSUITER_SIM_TEST_STOP_AFTER = "build"), {
    system2(.ms_rscript(), c(sim, paste0("--root=", .ms_root)),
            stdout = out, stderr = err)
  })
  txt <- paste0(paste(readLines(out, warn = FALSE), collapse = "\n"), "\n",
                paste(readLines(err, warn = FALSE), collapse = "\n"))
  expect_identical(rc, 0L, info = txt)
  expect_true(any(grepl("transient copy denial on build", txt, fixed = TRUE)),
              info = paste0("the retry witness never fired -- the denial was not retried:\n", txt))
  expect_true(any(grepl("TEST-ONLY stop-after=build reached", txt, fixed = TRUE)),
              info = paste0("the sim did not proceed past the retried build:\n", txt))
})

test_that("check-layout-sim: a copy denial that outlives the budget dies loud, never masked", {
  if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
    skip("already running inside the simulated check layout (recursion guard)")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  out <- tempfile("sim-denial-budget-out-")
  err <- tempfile("sim-denial-budget-err-")
  # Injected denials >= the retry budget: every attempt is denied, the real
  # build never runs, and the sim must die on its own loud verdict.
  rc <- .ms_sim_env(c(MSUITER_SIM_TEST_TRANSIENT_COPY_DENIAL = "4",
                      MSUITER_SIM_TEST_STOP_AFTER = "build"), {
    system2(.ms_rscript(), c(sim, paste0("--root=", .ms_root)),
            stdout = out, stderr = err)
  })
  txt <- paste0(paste(readLines(out, warn = FALSE), collapse = "\n"), "\n",
                paste(readLines(err, warn = FALSE), collapse = "\n"))
  expect_false(identical(rc, 0L), info = paste0("budget-exhausted build exited green:\n", txt))
  expect_true(any(grepl("ERROR R CMD build failed", txt, fixed = TRUE)),
               info = paste0("the budget-exhausted path lost its loud verdict:\n", txt))
  expect_true(any(grepl("transient copy denial on build", txt, fixed = TRUE)),
               info = paste0("the retry witness never fired on the budget path:\n", txt))
  expect_false(any(grepl("TEST-ONLY stop-after=build reached", txt, fixed = TRUE)),
               info = paste0("the sim reached post-build stages past a denied build:\n", txt))
})
