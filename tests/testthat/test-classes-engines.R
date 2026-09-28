# MsEngine: abstract spec (name / mode / params / deterministic / packages /
# label). Concrete engine specs are registered by U-M0-04; here we exercise
# the abstract contract with a local subclass.

.KnownEngine <- S7::new_class("KnownEngine",
  package = "msuiter.test",
  parent = MsEngine,
  properties = list()
)

test_that("MsEngine is abstract", {
  expect_error(MsEngine(), regexp = "abstract")
})

test_that("concrete engine specs construct and print", {
  eng <- .KnownEngine(
    name = "nmf_kl",
    mode = "extract",
    params = list(rank = 5L),
    deterministic = TRUE,
    packages = character(0)
  )
  expect_is_ms(eng, "MsEngine")
  expect_true(S7::S7_inherits(eng, MsEngine))
  # label is optional; printing falls back to the engine name
  expect_identical(eng@label, "")

  printed <- capture.output(print(eng))
  expect_length(printed, 1)
  expect_match(printed[1], "MsEngine")
  expect_match(printed[1], "nmf_kl")
  expect_match(printed[1], "extract")
})

test_that("engine spec fields are validated", {
  expect_ms_error(
    .KnownEngine(name = "Bad Name", mode = "extract", params = list(),
      deterministic = TRUE),
    "engine", regexp = "name"
  )
  expect_ms_error(
    .KnownEngine(name = "x", mode = "transform", params = list(),
      deterministic = TRUE),
    "engine", regexp = "mode"
  )
  expect_ms_error(
    .KnownEngine(name = "x", mode = "extract", params = list(),
      deterministic = NA),
    "engine", regexp = "deterministic"
  )
  expect_ms_error(
    .KnownEngine(name = "x", mode = "extract", params = list(a = 1),
      deterministic = TRUE, packages = c("ggplot2", NA)),
    "engine", regexp = "packages"
  )
})

test_that("engine specs survive RDS round trips", {
  eng <- .KnownEngine(name = "ard", mode = "fit", params = list(),
    deterministic = FALSE, packages = "msuiter")
  eng2 <- .roundtrip(eng)
  expect_identical(format(eng2), format(eng))
  expect_is_ms(eng2, "MsEngine")
})
