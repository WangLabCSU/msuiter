# MsBenchmark: mlr3-style score tibble
# (results with .engine/.scenario/.metric/.estimate) + settings.

test_that("valid MsBenchmark constructs and prints a one-line summary", {
  bench <- ms_benchmark(results = .make_benchmark_results(),
    settings = list(seed = 7))
  expect_is_ms(bench, "MsBenchmark")
  expect_identical(bench@settings$seed, 7)

  printed <- capture.output(print(bench))
  expect_length(printed, 1)
  expect_match(printed[1], "MsBenchmark")
  expect_match(printed[1], "3 results")
})

test_that("results must carry the four score columns", {
  bad <- .make_benchmark_results()
  bad$.metric <- NULL
  expect_ms_error(
    ms_benchmark(results = bad, settings = list()),
    "benchmark", regexp = "metric"
  )
})

test_that("score column types are validated", {
  bad <- .make_benchmark_results()
  bad$.estimate <- as.character(bad$.estimate)
  expect_ms_error(
    ms_benchmark(results = bad, settings = list()),
    "benchmark", regexp = "estimate"
  )
})

test_that("NA estimates are rejected", {
  bad <- .make_benchmark_results()
  bad$.estimate[2] <- NA_real_
  expect_ms_error(
    ms_benchmark(results = bad, settings = list()),
    "benchmark", regexp = "NA"
  )
})

test_that("RDS round trip preserves dispatch and validity", {
  bench <- ms_benchmark(results = .make_benchmark_results(), settings = list())
  bench2 <- .roundtrip(bench)
  expect_identical(format(bench2), format(bench))
  expect_no_error(S7::validate(bench2))
  expect_is_ms(bench2, "MsBenchmark")
})
