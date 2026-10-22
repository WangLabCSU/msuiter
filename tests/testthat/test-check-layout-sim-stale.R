# CI shard-stale unit (moved out of test-check-layout-sim.R verbatim,
# 2026-10-21 shard restructure; docs/devlog). It carries the provisioning
# tree-identity law of the P4 lane; like its sentry sibling it stands as a
# shard of its own because its green path drives one full simulate.
#
# Recursion guard: inside the simulated run itself the entrypoint exports
# SIM_CHECK_LAYOUT_ACTIVE=1 and this unit skips.

# The provisioning tree-identity law (the P4 lane, 2026-10-15). The simulated
# layout must exercise the build of the tree under test -- a candidate install
# that was not built from that very tree is STALE and may never serve.
# Witnessed RED on the lane battery (05-full-suite-HEAD.log of the lane
# record): with the ambient install lagging the lane's Collate, the resolver
# short-circuited onto it, the nested run executed the lane's new test file
# against the old build, and the full-suite self-test unit above broke for a
# breakage that does not exist in the layout at all (the recorded
# provision-lib hazard). The unit stages that class deterministically and
# HERMETICALLY: the candidate is synthesized from the tree's own DESCRIPTION
# (Version and Collate verbatim, one token renamed) plus a synthesized
# CITATION -- the resolver's acceptance needs dir + DESCRIPTION + CITATION and
# its staleness read needs only the DESCRIPTION, so those three files are the
# whole candidate and no ambient install is consulted (staging from one was
# host-dependent: the PR #29 CI witness shows a CITATION-less R CMD check
# install yields a candidate that silently misses the acceptance gate before
# the staleness read ever runs). The candidate is rejected before it is ever
# used, so it carries no loadable R code.
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
  stalelib <- tempfile("sim-stalelib-")
  dir.create(file.path(stalelib, "msuiter"), recursive = TRUE)
  # Tamper: the staged candidate lags the tree under test in exactly the
  # shape of the hazard -- its build identity no longer matches the source.
  tree_desc <- readLines(file.path(.ms_root, "DESCRIPTION"), warn = FALSE)
  hit <- grep("'zzz.R'", tree_desc, fixed = TRUE)
  expect_true(length(hit) >= 1L,
               info = paste0("tree DESCRIPTION lacks the zzz.R Collate token:\n",
                             paste(tree_desc, collapse = "\n")))
  tampered <- tree_desc
  tampered[hit[1L]] <- gsub("'zzz.R'", "'zzz-stale-renamed.R'", tampered[hit[1L]],
                            fixed = TRUE)
  writeLines(tampered, file.path(stalelib, "msuiter", "DESCRIPTION"))
  writeLines("Synthesized CITATION for the stale-candidate fixture.",
             file.path(stalelib, "msuiter", "CITATION"))
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
