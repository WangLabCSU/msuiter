# MsFit: exposures / support / tests + reference_summary snapshot + engine.

test_that("valid MsFit constructs and prints a one-line summary", {
  refdb <- .make_refdb()
  # U-M3a-02: `ms_fit` is now the fitting generic (R/fit.R); precomputed
  # parts assemble through the S7 class constructor, which validates too.
  fit <- MsFit(
    exposures = .make_exposures(),
    engine = "msu-fit",
    reference_summary = msuiter_refdb_summary(refdb),
    support = data.frame(),
    tests = data.frame()
  )
  expect_is_ms(fit, "MsFit")
  expect_identical(fit@engine, "msu-fit")
  expect_identical(nrow(fit@support), 0L)
  expect_identical(nrow(fit@tests), 0L)

  printed <- capture.output(print(fit))
  expect_length(printed, 1)
  expect_match(printed[1], "MsFit")
  expect_match(printed[1], "2 signatures")
  expect_match(printed[1], "3 samples")
  expect_match(printed[1], "msu-fit")
})

test_that("reference_summary is a snapshot with the contracted fields", {
  refdb <- .make_refdb()
  ref_summary <- msuiter_refdb_summary(refdb)
  expect_named(ref_summary,
    c("version", "class", "build", "schema_version", "sha256", "n_signatures"))
  expect_identical(ref_summary$version, "1.0.0")
  expect_identical(ref_summary$n_signatures, 2L)
  expect_false("matrices" %in% names(ref_summary))
  expect_lt(object.size(ref_summary), object.size(refdb))
})

test_that("fit exposures are validated", {
  ref_summary <- msuiter_refdb_summary(.make_refdb())
  exp1 <- .make_exposures()
  exp1[1, 1] <- -2
  expect_ms_error(
    MsFit(exposures = exp1, engine = "msu-fit", reference_summary = ref_summary, support = data.frame(), tests = data.frame()),
    "fit", regexp = "negative"
  )
  exp2 <- .make_exposures()
  exp2[1, 1] <- NA_real_
  expect_ms_error(
    MsFit(exposures = exp2, engine = "msu-fit", reference_summary = ref_summary, support = data.frame(), tests = data.frame()),
    "fit", regexp = "NA"
  )
  # Duplicated exposure row labels are rejected (labels are identities).
  exp3 <- .make_exposures()
  rownames(exp3)[2] <- "SIG1"
  expect_ms_error(
    MsFit(exposures = exp3, engine = "msu-fit", reference_summary = ref_summary, support = data.frame(), tests = data.frame()),
    "fit", regexp = "duplicate"
  )
})

test_that("reference_summary structure is validated", {
  bad <- msuiter_refdb_summary(.make_refdb())
  bad$sha256 <- NULL
  expect_ms_error(
    MsFit(exposures = .make_exposures(), engine = "msu-fit", reference_summary = bad, support = data.frame(), tests = data.frame()),
    "fit", regexp = "reference_summary"
  )
})

test_that("support and tests must be data frames", {
  expect_ms_error(
    S7::set_props(
      MsFit(exposures = .make_exposures(), engine = "msu-fit", reference_summary = msuiter_refdb_summary(.make_refdb()), support = data.frame(), tests = data.frame()),
      support = "nope"
    ),
    "fit"
  )
})

test_that("RDS round trip preserves dispatch and validity", {
  fit <- MsFit(exposures = .make_exposures(), engine = "msu-fit", reference_summary = msuiter_refdb_summary(.make_refdb()), support = data.frame(), tests = data.frame())
  fit2 <- .roundtrip(fit)
  expect_identical(format(fit2), format(fit))
  expect_no_error(S7::validate(fit2))
  expect_is_ms(fit2, "MsFit")
})
