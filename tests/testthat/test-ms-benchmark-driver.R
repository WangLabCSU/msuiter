# U-M7-pre: ms_run_benchmark() -- the grid driver first version (design
# memo docs/devlog/2026-10-05-benchmark-design-memo.md, D1 stage 1 + D2
# PROVISIONAL).
#
# Anchors: seed determinism (same seed -> identical results table), the
# results schema (MsBenchmark validator + the six metrics), single-cell
# error isolation (a failing extraction records cell_error and the grid
# continues), the provisional settings echo, and structured errors.

.ms_bd_grid <- function() {
  list(
    easy = ms_benchmark_grid(name = "easy", n_samples = 6, burden = 3000,
      k_active = 2, arm = "multinomial")
  )
}

test_that("grid and engine validation errors are structured", {
  sc <- ms_benchmark_grid(name = "s", n_samples = 6, burden = 3000,
    k_active = 2)
  expect_ms_error(ms_run_benchmark("junk"), "input")
  expect_ms_error(ms_run_benchmark(list(sc)), "input") # unnamed
  bad <- sc; bad$name <- NULL
  expect_ms_error(ms_run_benchmark(list(s = bad)), "input")
  expect_ms_error(ms_run_benchmark(list(s = sc), engines = list()),
    "input")
  expect_ms_error(ms_run_benchmark(list(s = sc),
    engines = list(nmf = ms_nmf()), seed = -1), "input")
})

test_that("scenario constructor validation errors are structured", {
  expect_ms_error(ms_benchmark_grid(name = ""), "input")
  expect_ms_error(ms_benchmark_grid(n_samples = 3), "input")
  expect_ms_error(ms_benchmark_grid(burden = 100), "input")
  expect_ms_error(ms_benchmark_grid(k_active = 1), "input")
  expect_ms_error(ms_benchmark_grid(k_active = 21), "input")
  expect_ms_error(ms_benchmark_grid(arm = "warp"), "option")
  expect_ms_error(ms_benchmark_grid(arm = "nb", size = 0), "input")
})

test_that("the driver runs a tiny cell with the full metric schema", {
  skip_if_not_installed("ggplot2") # registry assembly pulls the viz deps
  bm <- ms_run_benchmark(.ms_bd_grid(),
    engines = list(nmf = ms_nmf()), seed = 1)
  expect_is_ms(bm, "MsBenchmark")
  metrics <- bm@results$.metric
  expect_setequal(metrics, c("precision", "recall", "f1",
    "paired_l1_abs", "paired_l1_comp", "runtime_s"))
  expect_identical(unique(bm@results$.engine), "nmf")
  expect_identical(unique(bm@results$.scenario), "easy")
  # No error row on the easy cell.
  expect_false("cell_error" %in% metrics)
  # The provisional echo rides in settings.
  expect_match(bm@settings$defaults, "PROVISIONAL")
  expect_match(bm@settings$defaults, "D1 stage 1 + D2", fixed = TRUE)
})

test_that("seed determinism: identical seeds give identical tables", {
  a <- ms_run_benchmark(.ms_bd_grid(),
    engines = list(nmf = ms_nmf()), seed = 7)
  b <- ms_run_benchmark(.ms_bd_grid(),
    engines = list(nmf = ms_nmf()), seed = 7)
  # Runtime varies; every other metric is a bitwise function of the seed.
  a2 <- a@results[a@results$.metric != "runtime_s", ]
  b2 <- b@results[b@results$.metric != "runtime_s", ]
  expect_identical(a2, b2)
})

test_that("single-cell error isolation: the grid continues", {
  sc <- ms_benchmark_grid(name = "doomed", n_samples = 6, burden = 3000,
    k_active = 2, arm = "multinomial")
  # testthat 3e's own mocking (no withr dependency needed on the Suggests
  # list -- local_mocked_bindings ships with testthat itself).
  testthat::local_mocked_bindings(
    ms_extract = function(catalog, k, method = NULL, ...) {
      stop("mocked extraction failure")
    },
    .package = "msuiter"
  )
  bm <- ms_run_benchmark(list(doomed = sc),
    engines = list(nmf = ms_nmf()), seed = 1)
  # The failed cell reports ONLY its cell_error row (the container
  # validator rejects NA estimates).
  expect_identical(nrow(bm@results), 1L)
  expect_identical(bm@results$.metric, "cell_error")
  expect_identical(bm@results$.estimate, 1)
})
