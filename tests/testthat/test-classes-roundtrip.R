# Cross-cutting D12/A5 contract tests:
#   * every class is RDS-safe (saveRDS -> readRDS keeps full generic behavior),
#   * no .state property, no external pointers, no handles anywhere.

.test_objects <- function() {
  refdb <- .make_refdb()
  list(
    variants = ms_variants(.make_variants_table(), "GRCh38",
      .make_variants_provenance()),
    catalog = .make_catalog(),
    signature = .make_signature(),
    fit = ms_fit(.make_exposures(), "msu-fit", msuiter_refdb_summary(refdb)),
    refdb = refdb,
    benchmark = ms_benchmark(results = .make_benchmark_results(), settings = list())
  )
}

test_that("RDS round trips keep generic behavior identical for every class", {
  for (nm in names(.test_objects())) {
    x <- .test_objects()[[nm]]
    x2 <- .roundtrip(x)
    expect_identical(format(x2), format(x), info = nm)
    expect_identical(capture.output(print(x2)), capture.output(print(x)), info = nm)
    expect_no_error(S7::validate(x2))
    # Property access survives (dispatch on the round-tripped class vector).
    expect_identical(S7::prop_names(x2), S7::prop_names(x), info = nm)
  }
})

test_that("no class carries .state, externalptr or handles (D12/A5)", {
  for (nm in names(.test_objects())) {
    x <- .test_objects()[[nm]]
    expect_false(".state" %in% S7::prop_names(x), info = nm)
    for (p in S7::prop_names(x)) {
      v <- S7::prop(x, p)
      expect_false(typeof(v) == "externalptr", info = sprintf("%s@%s", nm, p))
      if (is.list(v)) {
        expect_false(any(vapply(v, function(el) typeof(el) == "externalptr", logical(1))),
          info = sprintf("%s@%s", nm, p))
      }
    }
  }
  # Same for the abstract engine spec.
  expect_false(".state" %in% S7::prop_names(MsEngine))
})
