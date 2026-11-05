# Shared resources for the tier-T2 heavy battery under tests/heavy (issue
# #76, 2026-11-05; docs/devlog/2026-11-05-ci-pr-gate-tiering-ruling.md).
# The two check-layout-sim provisioning simulations moved out of
# tests/testthat: they still resolve the repository through the sanctioned
# check-layout-safe helpers, which live beside the repo-mode battery. The
# heavy face (tools/test-heavy.R) and testthat's own helper auto-source run
# this file first; sourcing is idempotent (the helpers are pure definitions).

.ms_heavy_pkg_root <- function(start = getwd()) {
  d <- normalizePath(start, mustExist = TRUE)
  while (TRUE) {
    desc <- file.path(d, "DESCRIPTION")
    if (file.exists(desc)) {
      hdr <- tryCatch(readLines(desc, n = 5L, warn = FALSE),
                      error = function(e) character())
      if (any(grepl("^Package:\\s*msuiter\\s*$", hdr))) return(d)
    }
    parent <- dirname(d)
    if (identical(parent, d)) return(NA_character_)
    d <- parent
  }
}

.ms_heavy_root <- .ms_heavy_pkg_root()
if (is.na(.ms_heavy_root)) {
  stop("tests/heavy: no msuiter package root above ", getwd(),
       " -- run tools/test-heavy.R from the checkout")
}
source(file.path(.ms_heavy_root, "tests", "testthat", "helper-check-layout.R"))
