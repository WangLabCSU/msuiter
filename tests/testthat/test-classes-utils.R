# Unit tests for the channel-label hashing helper (R/classes-utils.R).
# The hash feeds the MsSignature catalog_summary snapshot (A5), so it must be
# deterministic across sessions, platforms and RDS round trips.

test_that("label hash is a stable hex digest", {
  h <- msuiter_hash_labels(c("A[C>A]A", "A[C>A]C", "T[T>G]T"))
  expect_type(h, "character")
  expect_length(h, 1)
  expect_match(h, "^[0-9a-f]{32}$") # md5 hex digest
  expect_identical(
    h,
    msuiter_hash_labels(c("A[C>A]A", "A[C>A]C", "T[T>G]T"))
  )
})

test_that("label hash is order sensitive and content sensitive", {
  a <- c("A[C>A]A", "A[C>A]C")
  b <- c("A[C>A]C", "A[C>A]A")
  expect_false(identical(msuiter_hash_labels(a), msuiter_hash_labels(b)))
  expect_false(identical(
    msuiter_hash_labels(a),
    msuiter_hash_labels(c("A[C>A]A", "A[C>A]C", "A[C>A]G"))
  ))
})

test_that("label hash rejects NA and non-character input", {
  expect_ms_error(msuiter_hash_labels(c("A", NA)), "input")
  expect_ms_error(msuiter_hash_labels(1:3), "input")
})

test_that("label hash handles the empty vector and unicode deterministically", {
  expect_identical(msuiter_hash_labels(character(0)), msuiter_hash_labels(character(0)))
  # Same bytes across sessions regardless of native encoding.
  labels <- enc2utf8(c("A[C>A]A", "信号A"))
  expect_identical(msuiter_hash_labels(labels), msuiter_hash_labels(labels))
})
