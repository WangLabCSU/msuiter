# MsSignature: signatures / exposures / stability / k_evidence / engine / seed
# + catalog_summary snapshot (A5: dimension + channel-table hash + build,
# never an embedded MsCatalog).

test_that("valid MsSignature constructs and prints a one-line summary", {
  sig <- .make_signature()
  expect_is_ms(sig, "MsSignature")
  expect_identical(sig@engine, "synthetic-engine")
  expect_identical(sig@seed, 1234)
  expect_identical(sig@stability, list())
  expect_identical(nrow(sig@k_evidence), 0L)

  printed <- capture.output(print(sig))
  expect_length(printed, 1)
  expect_match(printed[1], "MsSignature")
  expect_match(printed[1], "2 signatures")
  expect_match(printed[1], "3 samples")
  expect_identical(format(sig), printed[1])
})

test_that("catalog_summary is a snapshot summary, not an embedded catalog", {
  catalog <- .make_catalog()
  summary1 <- msuiter_catalog_summary(catalog)
  expect_type(summary1, "list")
  expect_named(summary1, c("n_channels", "n_samples", "channel_name", "channel_hash", "build"))
  expect_identical(summary1$n_channels, 6L)
  expect_identical(summary1$n_samples, 3L)
  expect_identical(summary1$channel_name, "SYN")
  expect_identical(summary1$channel_hash, msuiter_hash_labels(.make_catalog_labels()))
  expect_identical(summary1$build, "GRCh38")
  # No full objects smuggled into the snapshot (A5: no memory doubling).
  expect_false("counts" %in% names(summary1))
  expect_false("signatures" %in% names(summary1))
  expect_lt(object.size(summary1), object.size(catalog))
})

test_that("signature/exposure label agreement is enforced by label", {
  # Exposure rows must be the signature labels, element-wise.
  expect_ms_error(
    ms_signature(
      signatures = .make_signatures(),
      exposures = .make_exposures(sigs = rev(c("SIG1", "SIG2"))),
      catalog_summary = msuiter_catalog_summary(.make_catalog()),
      engine = "synthetic-engine",
      seed = 1
    ),
    "signature",
    regexp = "label"
  )
  # Different label set.
  expect_ms_error(
    ms_signature(
      signatures = .make_signatures(),
      exposures = .make_exposures(sigs = c("SIG1", "SIGX")),
      catalog_summary = msuiter_catalog_summary(.make_catalog()),
      engine = "synthetic-engine",
      seed = 1
    ),
    "signature"
  )
})

test_that("snapshot dimensions must match the matrices", {
  expect_ms_error(
    ms_signature(
      signatures = .make_signatures(labels = .make_catalog_labels(7)),
      exposures = .make_exposures(),
      catalog_summary = msuiter_catalog_summary(.make_catalog()),
      engine = "synthetic-engine",
      seed = 1
    ),
    "signature",
    regexp = "channel"
  )
  expect_ms_error(
    ms_signature(
      signatures = .make_signatures(),
      exposures = .make_exposures(samples = c("S1", "S2")),
      catalog_summary = msuiter_catalog_summary(.make_catalog()),
      engine = "synthetic-engine",
      seed = 1
    ),
    "signature",
    regexp = "sample"
  )
})

test_that("matrices must be non-negative and NA free", {
  sigs <- .make_signatures()
  sigs[2, 1] <- -0.5
  expect_ms_error(
    ms_signature(sigs, .make_exposures(), msuiter_catalog_summary(.make_catalog()),
      "synthetic-engine", 1),
    "signature",
    regexp = "negative"
  )
  sigs <- .make_signatures()
  sigs[2, 1] <- NA_real_
  expect_ms_error(
    ms_signature(sigs, .make_exposures(), msuiter_catalog_summary(.make_catalog()),
      "synthetic-engine", 1),
    "signature",
    regexp = "NA"
  )
  exp1 <- .make_exposures()
  exp1[1, 2] <- NA_real_
  expect_ms_error(
    ms_signature(.make_signatures(), exp1, msuiter_catalog_summary(.make_catalog()),
      "synthetic-engine", 1),
    "signature"
  )
})

test_that("catalog_summary structure is validated", {
  # Missing snapshot fields.
  bad <- msuiter_catalog_summary(.make_catalog())
  bad$channel_hash <- NULL
  expect_ms_error(
    ms_signature(.make_signatures(), .make_exposures(), bad, "synthetic-engine", 1),
    "signature",
    regexp = "catalog_summary"
  )
  # Wrong scalar type.
  bad2 <- msuiter_catalog_summary(.make_catalog())
  bad2$n_channels <- "6"
  expect_ms_error(
    ms_signature(.make_signatures(), .make_exposures(), bad2, "synthetic-engine", 1),
    "signature"
  )
})

test_that("engine and seed are validated", {
  expect_ms_error(
    ms_signature(.make_signatures(), .make_exposures(),
      msuiter_catalog_summary(.make_catalog()), "", 1),
    "signature",
    regexp = "engine"
  )
  expect_ms_error(
    ms_signature(.make_signatures(), .make_exposures(),
      msuiter_catalog_summary(.make_catalog()), "synthetic-engine", NA_real_),
    "signature",
    regexp = "seed"
  )
})

test_that("RDS round trip preserves dispatch, snapshot and validity", {
  sig <- .make_signature()
  sig2 <- .roundtrip(sig)
  expect_identical(format(sig2), format(sig))
  expect_identical(sig2@catalog_summary, sig@catalog_summary)
  expect_no_error(S7::validate(sig2))
  expect_is_ms(sig2, "MsSignature")
})
