# testthat 3e runner (standard).
library(testthat)
library(msuiter)

# Sharded CI fan-out (2026-10-21). covr runs this INSTALLED entrypoint
# through tools::testInstalledPackage, which offers no filter argument and
# no reporter slot, so the covr shard runner (tools/ci/run-covr-shard.R)
# drives it with two environment handoffs: MSUITER_TESTTHAT_FILTER selects a
# manifest shard, MSUITER_CENSUS_ATTEST names the file this process writes
# its MSUITER-ATTEST verdict to (census reporter sourced from the same
# helper the testthat lanes use -- one verdict format everywhere). Unset,
# both branches collapse to the historical verbatim full-suite call.
.filter <- Sys.getenv("MSUITER_TESTTHAT_FILTER", "")
.attest <- Sys.getenv("MSUITER_CENSUS_ATTEST", "")
if (nzchar(.attest)) {
  unlink(.attest)
  source(file.path("testthat", "helper-ci-shard-census.R"))
  rp <- .ci_census_reporter()$new(
    lane = "coverage",
    shard = suppressWarnings(as.integer(Sys.getenv("MSUITER_CENSUS_SHARD", "NA"))))
  test_check("msuiter", filter = .filter, reporter = rp, stop_on_failure = TRUE)
  writeLines(rp$attestation(), .attest)
} else if (nzchar(.filter)) {
  test_check("msuiter", filter = .filter, stop_on_failure = TRUE)
} else {
  test_check("msuiter")
}
