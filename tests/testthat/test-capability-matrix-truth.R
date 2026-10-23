# Capability-matrix truthfulness gate (docs-honesty law, 2026-10-23).
#
# The gate logic lives once, in tools/check-capability-matrix.R (see its
# header for the full contract); this file is the testthat face of it,
# adding the runtime cross-check the source-tree context makes possible:
# the NAMESPACE roster the validator parses must itself agree with the
# loaded namespace, and the static variant anchor must agree with the
# kernel's live .ms_nmf_variants. In the check layout the tools file is
# not locatable and the units skip sanctioned -- the CI docs job runs the
# same validator over the source tree, so no context goes uncovered.

.ms_cm_tools <- function() {
  dir <- normalizePath(getwd(), mustWork = TRUE)
  for (i in seq_len(12L)) {
    f <- file.path(dir, "tools", "check-capability-matrix.R")
    if (file.exists(f) && file.exists(file.path(dir, "DESCRIPTION")))
      return(list(root = dir, file = f))
    up <- normalizePath(file.path(dir, ".."), mustWork = TRUE)
    if (identical(up, dir)) break
    dir <- up
  }
  NULL
}

.ms_cm_src <- .ms_cm_tools()
if (!is.null(.ms_cm_src))
  sys.source(.ms_cm_src$file, envir = globalenv())

.ms_cm_need <- function() {
  if (is.null(.ms_cm_src))
    skip("capability-matrix validator tools/check-capability-matrix.R not locatable (R CMD check context)")
}

test_that("checkmarked capabilities are NAMESPACE-truthful and namespace-agreeing", {
  .ms_cm_need()
  a <- .ms_cm_audit(.ms_cm_src$root)
  expect_gte(length(a$claims), 10L) # a thin claim-set would mean the parser died
  expect_identical(a$api, character(0),
    info = paste0("checkmarked-but-unexported: ",
                  paste0(a$api, collapse = ", ")))
  # the two truths must agree: everything NAMESPACE lists is really in the
  # loaded namespace (a hand-diverged NAMESPACE reddens here, not at install)
  runtime <- getNamespaceExports("msuiter")
  missing <- setdiff(a$exports, as.character(runtime))
  expect_identical(missing, character(0),
    info = paste0("NAMESPACE lists exports absent from the namespace: ",
                  paste0(missing, collapse = ", ")))
})

test_that("checkmarked engine choices are legal kernel variants, statically and live", {
  .ms_cm_need()
  a <- .ms_cm_audit(.ms_cm_src$root)
  expect_gte(length(a$engines), 1L)
  expect_identical(a$engine, character(0),
    info = paste0("phantom engine faces: ", paste0(a$engine, collapse = ", ")))
  expect_identical(sort(a$legal), sort(as.character(msuiter:::.ms_nmf_variants)),
    info = "the static .ms_nmf_variants anchor and the live kernel roster have diverged")
})

test_that("the gate discriminates: planted phantoms redden every face", {
  # Positive controls with teeth: a fabricated matrix carrying a ghost API
  # and a ghost engine must FAIL the very predicates above -- a gate that
  # cannot go red on an invented capability is decoration, not governance.
  .ms_cm_need()
  r <- .ms_cm_selfcheck()
  expect_true(r$fired_api,
    info = "ghost API escaped the delivered-claim predicate")
  expect_true(r$fired_engine,
    info = "ghost engine variant escaped the engine predicate")
  expect_true(r$excluded_deferred,
    info = "a deferred-marked row leaked into the delivered-reading")
})
