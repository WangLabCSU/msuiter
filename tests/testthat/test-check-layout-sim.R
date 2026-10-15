# GO-04D regression unit (slice-D defect class).
#
# The PR #14 battery proved that a guard can execute green in every context
# EXCEPT the R CMD check test phase -- whose cwd (tests/testthat, a SIBLING
# of the extracted tree) makes test_path('../../...') read above the check
# directory. Only a live run under that exact layout catches the class. This
# unit drives tools/check-layout-sim.R -- which builds the layout from the
# REAL tarball (real .Rbuildignore semantics) and executes the REAL test
# files from inside it -- and requires a SIM-VERDICT: PASS with zero
# unauthorized skips.
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

# The provisioning tree-identity law (the P4 lane, 2026-10-15). The simulated
# layout must exercise the build of the tree under test -- a candidate install
# that was not built from that very tree is STALE and may never serve.
# Witnessed RED on the lane battery (05-full-suite-HEAD.log of the lane
# record): with the ambient install lagging the lane's Collate, the resolver
# short-circuited onto it, the nested run executed the lane's new test file
# against the old build, and the full-suite self-test unit above broke for a
# breakage that does not exist in the layout at all (the recorded
# provision-lib hazard). The unit stages that class deterministically: copy
# the installed msuiter build into a candidate lib, rename one Collate token
# in the copy (Collate is INSTALL-time load order only -- the copy stays
# functionally loadable), and require the resolver to name the rejection and
# provision from the tree instead.
test_that("check-layout-sim: a stale provisioning candidate is rejected, never used", {
  if (identical(Sys.getenv("SIM_CHECK_LAYOUT_ACTIVE", ""), "1")) {
    skip("already running inside the simulated check layout (recursion guard)")
  }
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  # The guard's green path provisions a fresh INSTALL from --root=, which
  # needs the full source tree (Rust workspace manifest included).
  if (!file.exists(file.path(.ms_root, "src", "rust", "Cargo.toml"))) {
    skip("provisioning a fresh INSTALL requires the source checkout")
  }
  inst_desc <- system.file(package = "msuiter", "DESCRIPTION",
                           lib.loc = .libPaths())
  if (is.na(inst_desc)) {
    skip("no installed msuiter build to stage a stale candidate from")
  }
  pkgdir <- dirname(inst_desc)
  stalelib <- tempfile("sim-stalelib-")
  dir.create(stalelib, recursive = TRUE)
  # File-by-file staging with the sanctioned copy primitives (this build has
  # no dir.copy/dir.remove; cleanup rides base unlink below).
  src_files <- list.files(pkgdir, recursive = TRUE, full.names = TRUE,
                          all.files = TRUE)
  for (f in src_files) {
    rel <- substring(f, nchar(pkgdir) + 2L)
    dst <- file.path(stalelib, "msuiter", rel)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    file.copy(f, dst, overwrite = TRUE)
  }
  # Tamper: the staged candidate lags the tree under test in exactly the
  # shape of the hazard -- its build identity no longer matches the source.
  dpath <- file.path(stalelib, "msuiter", "DESCRIPTION")
  dl <- readLines(dpath, warn = FALSE)
  hit <- grep("'zzz.R'", dl, fixed = TRUE)
  expect_true(length(hit) >= 1L,
               info = paste0("installed DESCRIPTION lacks the zzz.R Collate token:\n",
                             paste(dl, collapse = "\n")))
  dl[hit[1L]] <- gsub("'zzz.R'", "'zzz-stale-renamed.R'", dl[hit[1L]],
                      fixed = TRUE)
  writeLines(dl, dpath)
  out <- tempfile("sim-stalelib-out-")
  err <- tempfile("sim-stalelib-err-")
  rc <- system2(.ms_rscript(), c(sim, paste0("--root=", .ms_root),
                                 paste0("--lib=", stalelib)),
                stdout = out, stderr = err)
  txt <- paste0(paste(readLines(out, warn = FALSE), collapse = "\n"), "\n",
                paste(readLines(err, warn = FALSE), collapse = "\n"))
  tail <- if (length(txt) && nzchar(txt)) {
    ln <- strsplit(txt, "\n", fixed = TRUE)[[1]]
    if (length(ln) > 25L) ln <- ln[(length(ln) - 24L):length(ln)]
    paste(ln, collapse = "\n")
  } else ""
  expect_match(txt, "stale candidate",
               info = paste0("the resolver used the stale candidate without naming it:\n", tail))
  expect_identical(rc, 0L,
                   info = paste0("the simulated layout did not go green once the stale build was staged:\n", tail))
  expect_match(txt, "SIM-VERDICT: PASS",
               info = paste0("SIM-VERDICT tail:\n", tail))
  unlink(stalelib, recursive = TRUE)
})
