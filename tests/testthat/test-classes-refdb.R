# MsRefDb: versioned signature library.
# metadata contract (ARCHITECTURE.md sections 3.2/6): version / class / build /
# schema_version / sha256 / license / build_independent / availability.

test_that("valid MsRefDb constructs and prints a one-line summary", {
  refdb <- .make_refdb()
  expect_is_ms(refdb, "MsRefDb")
  expect_identical(names(refdb@matrices), "ref_a")

  printed <- capture.output(print(refdb))
  expect_length(printed, 1)
  expect_match(printed[1], "MsRefDb")
  expect_match(printed[1], "SYN")
  expect_match(printed[1], "1.0.0")
  expect_match(printed[1], "1 matrices")
})

test_that("metadata must carry all governance fields", {
  for (field in c("version", "class", "build", "schema_version", "sha256",
                  "license", "build_independent", "availability")) {
    metadata <- list(
      version = "1.0.0", class = "SYN", build = "GRCh38",
      schema_version = "1", sha256 = paste0(rep("a", 64), collapse = ""),
      license = "CC0-1.0", build_independent = FALSE,
      availability = c("GRCh37", "GRCh38")
    )
    metadata[[field]] <- NULL
    expect_ms_error(
      ms_refdb(
        matrices = list(m = matrix(1, 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))),
        metadata = metadata
      ),
      "refdb",
      regexp = field
    )
  }
})

test_that("build_independent interacts with build per A13", {
  metadata <- list(
    version = "1", class = "SYN", build = NA_character_,
    schema_version = "1", sha256 = paste0(rep("a", 64), collapse = ""),
    license = "CC0-1.0", build_independent = FALSE,
    availability = character(0)
  )
  # NA build without the build_independent declaration is rejected.
  expect_ms_error(ms_refdb(list(m = matrix(1, 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))), metadata),
    "refdb", regexp = "build")
  # Declaring build independence makes the NA build legal.
  metadata$build_independent <- TRUE
  refdb <- ms_refdb(list(m = matrix(1, 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))), metadata)
  expect_true(refdb@metadata$build_independent)
})

test_that("matrices are validated: numeric, NA free, non-negative, labelled", {
  good <- list(m = matrix(1, 2, 2, dimnames = list(c("A", "C"), c("S1", "S2"))))
  metadata <- list(
    version = "1", class = "SYN", build = "GRCh38", schema_version = "1",
    sha256 = paste0(rep("a", 64), collapse = ""), license = "CC0-1.0",
    build_independent = FALSE, availability = character(0)
  )
  # NA entry
  m <- matrix(c(1, NA, 1, 1), 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))
  expect_ms_error(ms_refdb(list(m = m), metadata), "refdb", regexp = "NA")
  # negative entry
  m2 <- matrix(c(1, -1, 1, 1), 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))
  expect_ms_error(ms_refdb(list(m = m2), metadata), "refdb", regexp = "negative")
  # missing dimnames
  expect_ms_error(ms_refdb(list(m = matrix(1, 2, 2)), metadata), "refdb")
  # unnamed list element
  expect_ms_error(ms_refdb(list(matrix(1, 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))), metadata),
    "refdb")
  # inconsistent channel labels across matrices (label, never position)
  m3 <- matrix(1, 2, 2, dimnames = list(c("A", "G"), c("S1", "S2")))
  expect_ms_error(ms_refdb(list(m = good[[1]], m2 = m3), metadata), "refdb",
    regexp = "label")
})

test_that("sha256 must look like a sha256 hex digest", {
  metadata <- list(
    version = "1", class = "SYN", build = "GRCh38", schema_version = "1",
    sha256 = "not-a-digest", license = "CC0-1.0",
    build_independent = FALSE, availability = character(0)
  )
  expect_ms_error(
    ms_refdb(list(m = matrix(1, 2, 2, dimnames = list(c("A", "C"), c("S1", "S2")))), metadata),
    "refdb", regexp = "sha256"
  )
})

test_that("RDS round trip preserves dispatch and validity", {
  refdb <- .make_refdb()
  refdb2 <- .roundtrip(refdb)
  expect_identical(format(refdb2), format(refdb))
  expect_identical(refdb2@metadata$sha256, refdb@metadata$sha256)
  expect_no_error(S7::validate(refdb2))
  expect_is_ms(refdb2, "MsRefDb")
})
