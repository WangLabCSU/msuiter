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
  expect_match(out$r_version, "^R version")
  expect_type(out$threads, "list")
  expect_identical(out$threads$effective, .ms_resolve_threads())
  # Data that does not ship yet is reported honestly, not guessed.
  expect_match(out$refdb, "not yet available")
  expect_true(all(grepl("not yet available|M1s|planned", out$not_yet_available)))
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
