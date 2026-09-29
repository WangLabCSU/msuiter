# FFI contract probes (U-M0-09): end-to-end tests through the real FFI.
#
# Rust-side unit tests (src/rust/src/probes.rs) cover the pure cores with
# plain cargo test; this file covers the R wrappers, the R-side validators
# (contract 3 first layer) and the error-condition mapping.

# ---------------------------------------------------------------------------
# Contract 2: column-major layout (asymmetric golden round-trip)
# ---------------------------------------------------------------------------

test_that("column-major probe reproduces R's own column-major flattening", {
  m <- matrix(as.numeric(1:12), nrow = 3) # 3x4, column-major fill
  golden <- sum(seq_along(m) * as.numeric(m))
  expect_identical(.msffi_column_major_probe(m), golden)
})

test_that("column-major probe discriminates a row-major misread", {
  # Non-square + asymmetric fill: the row-major misread of the same buffer
  # (what a transpose bug computes) assigns different weights and must
  # disagree. The R golden for the misread is computed by flattening R's
  # 3x4 matrix in ROW-major order.
  m <- matrix(as.numeric(1:12), nrow = 3)
  col_read <- .msffi_column_major_probe(m)
  row_major_flat <- as.numeric(t(m)) # what the buggy reader believes
  golden_misread <- sum(seq_along(row_major_flat) * row_major_flat)
  expect_false(isTRUE(all.equal(col_read, golden_misread)))

  # Positive control: the transposed matrix has its own (different) golden.
  expect_false(identical(col_read, .msffi_column_major_probe(t(m))))
  mt <- t(m)
  expect_identical(
    .msffi_column_major_probe(mt),
    sum(seq_along(mt) * as.numeric(mt))
  )
})

test_that("column-major probe is exact for integer-valued matrices", {
  m <- matrix(c(3, 1, 4, 1, 5, 9, 2, 6), nrow = 2) # 2x4
  expect_identical(
    .msffi_column_major_probe(m),
    sum(seq_along(m) * as.numeric(m))
  )
})

# ---------------------------------------------------------------------------
# Contract 3: NA/NaN rejection (R validator first, Rust scan second)
# ---------------------------------------------------------------------------

test_that("R validator rejects NA/NaN before the FFI with i/j payload", {
  m <- matrix(as.numeric(1:6), nrow = 2)
  m[2, 3] <- NA_real_ # flat position 6 -> (i = 2, j = 3)
  err <- tryCatch(.msffi_na_probe(m), error = identity)
  expect_s3_class(err, "msuiter_error_na")
  expect_identical(err$i, 2L)
  expect_identical(err$j, 3L)
  expect_match(err$context, "anyNA")

  m_nan <- matrix(as.numeric(1:6), nrow = 2)
  m_nan[1, 2] <- NaN # flat position 3 -> (i = 1, j = 2)
  err2 <- tryCatch(.msffi_na_probe(m_nan), error = identity)
  expect_s3_class(err2, "msuiter_error_na")
  expect_identical(err2$i, 1L)
  expect_identical(err2$j, 2L)
})

test_that("Rust NA scan is the second layer when the validator is bypassed", {
  # Call the generated passthrough directly: an NA that slips past the R
  # validator must still fail the whole call. Both build modes are valid:
  #   * release (R CMD check): the explicit scan returns the frozen
  #     `msuiter_error_rust` condition with 1-based i/j payload;
  #   * debug (devtools::load_all): the contract-3 debug_assert! fires
  #     first — the panic is caught and rethrown as a hard R error.
  m <- matrix(as.numeric(c(1, 2, 3, NaN, 5, 6)), nrow = 3) # (i = 1, j = 2)
  res <- tryCatch(msffi_na_probe(m), error = identity)
  if (inherits(res, "msuiter_error_rust")) {
    expect_identical(res$topic, "na")
    expect_identical(res$i, 1L)
    expect_identical(res$j, 2L)
  } else {
    expect_s3_class(res, "error")
    expect_match(conditionMessage(res), "contract 3")
  }
  # Clean matrices pass the scan and return the element count.
  expect_identical(msffi_na_probe(matrix(as.numeric(1:6), nrow = 3)), 6L)
})

# ---------------------------------------------------------------------------
# Contracts 4/5: Result<_, MsError> -> R condition mapping
# ---------------------------------------------------------------------------

test_that("error probe maps out-of-bounds indices to msuiter_error_rust", {
  err <- tryCatch(.msffi_error_probe(2, 6), error = identity)
  expect_s3_class(err, "msuiter_error_rust")
  expect_identical(err$topic, "bounds")
  expect_identical(err$i, 2L)
  expect_identical(err$j, 6L)
  expect_true(is.character(err$c) && nzchar(err$c))
  expect_match(err$message, "4x3")

  # tryCatch handler sees class + payload end to end.
  payload <- tryCatch(
    .msffi_error_probe(0, 1),
    msuiter_error_rust = function(e) c(i = e$i, j = e$j)
  )
  expect_identical(payload, c(i = 0L, j = 1L))
})

test_that("error probe returns a deterministic value in bounds", {
  expect_identical(.msffi_error_probe(1, 1), 0)
  expect_identical(.msffi_error_probe(4, 3), 11)
})

# ---------------------------------------------------------------------------
# Contract 7: interrupt mechanism
# ---------------------------------------------------------------------------

test_that("interrupt probe validates arguments and completes normally", {
  expect_identical(.msffi_interrupt_probe(8L), 8L)
  expect_identical(.msffi_interrupt_probe(0L), 0L)
  # Negative args are caught by the R validator (first layer)...
  err <- tryCatch(.msffi_interrupt_probe(-1L, 1L), error = identity)
  expect_s3_class(err, "msuiter_error_input")
  # ...and the Rust-side argument guard is reachable via the passthrough.
  err2 <- tryCatch(msffi_interrupt_probe(-1L, 1L), error = identity)
  expect_s3_class(err2, "msuiter_error_rust")
  expect_identical(err2$topic, "argument")
  expect_identical(err2$i, -1L)
})

# ---------------------------------------------------------------------------
# Contract 6: per-call thread pool and thread-count invariance
# ---------------------------------------------------------------------------

test_that("thread probe output is identical across thread counts (A7)", {
  a <- .msffi_thread_probe(1000, 42, threads = 1L)
  b <- .msffi_thread_probe(1000, 42, threads = 4L)
  c <- .msffi_thread_probe(1000, 42, threads = NULL) # option/default path
  expect_identical(a, b)
  expect_identical(a, c)
  expect_length(a, 1000)
  expect_true(all(a >= 0 & a < 1))
})

test_that("thread probe honors the msuiter.threads option", {
  withr::local_options(msuiter.threads = 3L)
  base <- .msffi_thread_probe(500, 7, threads = 1L)
  expect_identical(base, .msffi_thread_probe(500, 7)) # option path, same bits
  expect_identical(.ms_resolve_threads(), 3L)
  expect_identical(.ms_resolve_threads(9L), 9L) # explicit argument wins
})

test_that("thread resolution applies the _R_CHECK_LIMIT_CORES_ default", {
  withr::local_options(msuiter.threads = NULL)
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "true")
  expect_identical(.ms_resolve_threads(), 2L)
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "")
  expect_identical(.ms_resolve_threads(), 0L)
})

test_that("thread resolution rejects malformed options", {
  withr::local_options(msuiter.threads = "lots")
  err <- tryCatch(.ms_resolve_threads(), error = identity)
  expect_s3_class(err, "msuiter_error_option")
})

test_that("thread probe validates its arguments", {
  err <- tryCatch(.msffi_thread_probe(-1, 42, threads = 1L), error = identity)
  expect_s3_class(err, "msuiter_error_input")
  err2 <- tryCatch(.msffi_thread_probe(10, -1, threads = 1L), error = identity)
  expect_s3_class(err2, "msuiter_error_input")
  # Rust-side argument guards, reachable through the passthrough.
  err3 <- tryCatch(msffi_thread_probe(-1L, 42L, 1L), error = identity)
  expect_s3_class(err3, "msuiter_error_rust")
  expect_identical(err3$topic, "argument")
})

# ---------------------------------------------------------------------------
# Contracts 6/7 on the real kernel: parallel KL-NMF replicate driver
# ---------------------------------------------------------------------------

# Synthetic m x n count catalog (deterministic, integer-valued, contains
# structural zeros — every 40th channel count vanishes).
.msffi_synthetic_counts <- function(m = 12L, n = 9L) {
  matrix(as.numeric((seq_len(m * n) * 7L) %% 40L), nrow = m)
}

test_that("real-kernel replicate objectives are identical across thread counts (A7)", {
  counts <- .msffi_synthetic_counts()
  a <- .msffi_nmf_replicates_probe(counts, k = 2L, replicates = 5L,
                                   max_iter = 10L, seed = 42L, threads = 1L)
  b <- .msffi_nmf_replicates_probe(counts, k = 2L, replicates = 5L,
                                   max_iter = 10L, seed = 42L, threads = 4L)
  c <- .msffi_nmf_replicates_probe(counts, k = 2L, replicates = 5L,
                                   max_iter = 10L, seed = 42L, threads = NULL)
  expect_identical(a, b)
  expect_identical(a, c)
  expect_type(a, "double")
  expect_length(a, 5L)
  expect_true(all(is.finite(a)))
})

test_that("replicate driver is reproducible and seed-sensitive", {
  counts <- .msffi_synthetic_counts()
  one <- .msffi_nmf_replicates_probe(counts, 2L, 4L, 8L, 7L, threads = 2L)
  expect_identical(
    one,
    .msffi_nmf_replicates_probe(counts, 2L, 4L, 8L, 7L, threads = 3L)
  )
  expect_false(identical(
    one,
    .msffi_nmf_replicates_probe(counts, 2L, 4L, 8L, 8L, threads = 2L)
  ))
})

test_that("replicate driver validates arguments and NA (R side first)", {
  counts <- .msffi_synthetic_counts()
  err <- tryCatch(
    .msffi_nmf_replicates_probe(counts, 2L, 4L, 8L, 42L, threads = "many"),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_option")
  err_k <- tryCatch(
    .msffi_nmf_replicates_probe(counts, 0L, 4L, 8L, 42L, threads = 1L),
    error = identity
  )
  expect_s3_class(err_k, "msuiter_error_input")
  err_rep <- tryCatch(
    .msffi_nmf_replicates_probe(counts, 2L, 0L, 8L, 42L, threads = 1L),
    error = identity
  )
  expect_s3_class(err_rep, "msuiter_error_input")
  err_seed <- tryCatch(
    .msffi_nmf_replicates_probe(counts, 2L, 4L, 8L, -1L, threads = 1L),
    error = identity
  )
  expect_s3_class(err_seed, "msuiter_error_input")
  bad <- counts
  bad[2, 3] <- NA_real_
  err_na <- tryCatch(
    .msffi_nmf_replicates_probe(bad, 2L, 4L, 8L, 42L, threads = 1L),
    error = identity
  )
  expect_s3_class(err_na, "msuiter_error_na")
})

test_that("replicate driver Rust guards stay reachable through the passthrough", {
  counts <- .msffi_synthetic_counts()
  err <- tryCatch(
    msffi_nmf_replicates_probe(counts, 0L, 4L, 8L, 42L, 1L),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_identical(err$topic, "argument")
  # Negative counts are rejected by the engine kernel's own validation,
  # surfacing as a whole-call error with 1-based i/j payload (contract 5:
  # no partial results).
  neg <- counts
  neg[3, 1] <- -5
  err_neg <- tryCatch(
    msffi_nmf_replicates_probe(neg, 2L, 4L, 8L, 42L, 1L),
    error = identity
  )
  expect_s3_class(err_neg, "msuiter_error_rust")
  expect_identical(err_neg$topic, "argument")
  expect_identical(err_neg$i, 3L)
  expect_identical(err_neg$j, 1L)
})

# ---------------------------------------------------------------------------
# Validators (shared)
# ---------------------------------------------------------------------------

test_that("matrix validator rejects non-matrices and coerces integers", {
  err <- tryCatch(.msffi_column_major_probe(1:12), error = identity)
  expect_s3_class(err, "msuiter_error_input")
  err2 <- tryCatch(.msffi_column_major_probe("a"), error = identity)
  expect_s3_class(err2, "msuiter_error_input")
  # Integer matrices are coerced to double before crossing the boundary.
  m <- matrix(1:6L, nrow = 2)
  expect_identical(
    .msffi_column_major_probe(m),
    sum(seq_along(m) * as.numeric(m))
  )
})

test_that("build info probe reports the compiled toolchain", {
  info <- .msffi_build_info()
  expect_type(info, "list")
  expect_named(info, c("package_version", "rustc_version", "target_os", "target_arch"))
  # The Rust crate version (0.0.0) trails the R package version on purpose:
  # the workspace Cargo.toml is the frozen budget artifact.
  expect_identical(info$package_version, "0.0.0")
  # "1.97.1 (...)": recorded by build.rs from cargo's own $RUSTC, prefix stripped.
  expect_match(info$rustc_version, "^[0-9]")
})
