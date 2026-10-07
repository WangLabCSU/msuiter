# ms_sitrep() (U-M0-09): the diagnostics surface of the platform.

test_that("ms_sitrep prints a report and returns the sections invisibly", {
  out <- withr::with_options(
    list(msuiter.threads = NULL),
    expect_invisible(ms_sitrep())
  )
  expect_type(out, "list")
  expect_named(
    out,
    c("r_version", "package_version", "rust_core", "threads", "refdb",
      "options", "not_yet_available")
  )
  expect_identical(out$package_version, as.character(utils::packageVersion("msuiter")))
  # R devel self-reports as "R Under development (unstable) (<date> r<n>)"
  # instead of "R version 4.x.y ..." -- the sitrep section passes
  # R.version.string through verbatim (honesty contract), so the assertion
  # admits both shapes (r-lib devel arm, CI audit 2026-10-07).
  expect_match(out$r_version, "^R (version|Under development)")
  expect_type(out$threads, "list")
  expect_identical(out$threads$effective, .ms_resolve_threads())
  # refdb v1 shipped (U-M3a-06): reported as bundled, not "not yet".
  expect_match(out$refdb, "COSMIC v3.6 bundled")
  # Data that does not ship yet is reported honestly, not guessed.
  expect_true(all(grepl("planned|M3b", out$not_yet_available)))
})

test_that("ms_sitrep output mentions the core facts", {
  report <- withr::with_options(
    list(msuiter.threads = 4L),
    testthat::capture_output_lines(ms_sitrep())
  )
  expect_true(any(grepl("msuiter", report)))
  expect_true(any(grepl("Rust core", report)))
  expect_true(any(grepl("msuiter.threads", report)))
  expect_true(any(grepl("Refdb", report)))
})
