# MsVariants: table + genome + provenance.
# Validator contract (ARCHITECTURE.md section 3.2): required columns /
# coordinate legality / anyNA rejection / somaticness signal fields.

test_that("valid MsVariants constructs and prints a one-line summary", {
  v <- ms_variants(.make_variants_table(), "GRCh38", .make_variants_provenance())
  expect_is_ms(v, "MsVariants")
  expect_identical(v@genome, "GRCh38")
  expect_identical(v@provenance$caller, "synthetic-caller")

  printed <- capture.output(print(v))
  expect_length(printed, 1)
  expect_match(printed[1], "MsVariants")
  expect_match(printed[1], "5 variants")
  expect_match(printed[1], "GRCh38")
  expect_identical(format(v), printed[1])
})

test_that("missing required columns are rejected", {
  bad <- .make_variants_table()
  bad$alt <- NULL
  expect_ms_error(
    ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants",
    regexp = "alt"
  )
})

test_that("coordinate legality is enforced", {
  # start > end
  bad <- .make_variants_table()
  bad$start[2] <- 202
  expect_ms_error(ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants", regexp = "start")
  # zero / negative coordinates
  bad <- .make_variants_table()
  bad$start[1] <- 0
  expect_ms_error(ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants", regexp = "coordinate")
  # empty chromosome or allele strings
  bad <- .make_variants_table()
  bad$chrom[3] <- ""
  expect_ms_error(ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants", regexp = "chrom")
  # allele alphabet
  bad <- .make_variants_table()
  bad$ref[1] <- "X"
  expect_ms_error(ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants", regexp = "allele")
})

test_that("anyNA in the variant table is rejected (FFI contract)", {
  bad <- .make_variants_table()
  bad$start[2] <- NA_real_
  expect_ms_error(
    ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants",
    regexp = "NA"
  )
  bad <- .make_variants_table()
  bad$chrom[1] <- NA_character_
  expect_ms_error(
    ms_variants(bad, "GRCh38", .make_variants_provenance()),
    "variants"
  )
})

test_that("somaticness signal fields are required in provenance", {
  # missing caller
  expect_ms_error(
    ms_variants(.make_variants_table(), "GRCh38", list(matched_normal = "none")),
    "variants",
    regexp = "caller"
  )
  # missing matched-normal provenance
  expect_ms_error(
    ms_variants(.make_variants_table(), "GRCh38", list(caller = "c")),
    "variants",
    regexp = "matched"
  )
  # NA signal field
  expect_ms_error(
    ms_variants(.make_variants_table(), "GRCh38",
      list(caller = "c", matched_normal = NA_character_)),
    "variants"
  )
})

test_that("somaticness option fields are type checked", {
  # optional vaf_floor must be in [0, 1]
  prov <- c(.make_variants_provenance(), list(vaf_floor = 1.5))
  expect_ms_error(ms_variants(.make_variants_table(), "GRCh38", prov),
    "variants", regexp = "vaf_floor")
  # optional vaf column must be in [0, 1]
  tab <- .make_variants_table()
  tab$vaf <- c(0.1, 0.2, 0.3, 0.4, 2)
  expect_ms_error(ms_variants(tab, "GRCh38", .make_variants_provenance()),
    "variants", regexp = "vaf")
  # FILTER passthrough column must be character
  tab <- .make_variants_table()
  tab$filter <- c(1, 0, 1, 0, 1)
  expect_ms_error(ms_variants(tab, "GRCh38", .make_variants_provenance()),
    "variants", regexp = "filter")
})

test_that("RDS round trip preserves dispatch and validity", {
  v <- ms_variants(.make_variants_table(), "GRCh38", .make_variants_provenance())
  v2 <- .roundtrip(v)
  expect_identical(format(v2), format(v))
  expect_no_error(S7::validate(v2))
  expect_is_ms(v2, "MsVariants")
})
