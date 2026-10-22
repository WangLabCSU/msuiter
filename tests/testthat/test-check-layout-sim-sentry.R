# CI shard-sentry unit (moved out of test-check-layout-sim.R verbatim,
# 2026-10-21 shard restructure; docs/devlog). It is the full-simulate half
# of the GO-04D instrument: build the real check layout from the real
# tarball (real .Rbuildignore semantics), execute the REAL test files from
# inside it, and require SIM-VERDICT: PASS with zero unauthorized skips.
# Its own ~20-minute cost is why it stands as a shard of its own: one file,
# one test_that, one schedulable arm.
#
# Pre-fix demonstration: at 21d63d8's tree this unit is RED (errored
# URL-triangle unit under the simulated layout); see /tmp/m7probe/
# c5d-sim-red.log. Recursion guard: inside the simulated run itself the
# entrypoint exports SIM_CHECK_LAYOUT_ACTIVE=1 and this unit skips.

test_that("check-layout-sim: full suite is green under the simulated check layout", {
  if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
    skip("already running inside the simulated check layout (recursion guard)")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  out <- tempfile("check-layout-sim-out-")
  rc <- system2(.ms_rscript(), c(sim, paste0("--root=", .ms_root)),
                stdout = out, stderr = FALSE)
  lines <- readLines(out, warn = FALSE)
  if (length(lines) > 20L) lines <- lines[(length(lines) - 19L):length(lines)]
  msgs <- paste(lines, collapse = "\n")
  expect_identical(rc, 0L,
                   info = paste0("check-layout-sim tail (last ",
                                 length(lines), " lines):\n", msgs))
  expect_match(msgs, "SIM-VERDICT: PASS")
})
