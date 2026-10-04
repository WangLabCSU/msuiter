# U-M4-02c: ms_convert() -- opportunity conversion (design memo
# docs/devlog/2026-10-04-M4-02c-convert-memo.md).
#
# Anchors: the sigminer cross-check (the maintainer's own upstream
# implementation, numeric agreement 1e-12), the same-opportunity
# identity, the roundtrip reversibility, the pinned table anchor values,
# and structured error paths.

.ms_cv_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

.ms_cv_sig <- function(k = 3) {
  sig <- matrix(runif(96 * k) + 0.01, nrow = 96)
  sig <- sweep(sig, 2, colSums(sig), "/")
  rownames(sig) <- .ms_cv_labels()
  colnames(sig) <- paste0("S", seq_len(k))
  sig
}

test_that("the opportunity table carries the pinned anchor values", {
  g <- msuiter:::.ms_convert_opps$`human-genome`
  e <- msuiter:::.ms_convert_opps$`human-exome`
  # Literal pins (sigminer human_trinuc_freqs, our label order).
  expect_equal(g[["A[C>A]A"]], 1.14e8, tolerance = 0)
  expect_equal(g[["A[C>A]C"]], 6.6e7, tolerance = 0)
  expect_equal(as.numeric(e[["T[T>G]T"]]), 2850934, tolerance = 0)
  # Magnitude sanity anchors (memo §1).
  expect_equal(sum(g), 8.505e9, tolerance = 1e-6)
  expect_equal(sum(e), 153221364, tolerance = 1e-6)
  # All positive and finite.
  expect_true(all(g > 0) && all(e > 0))
})

test_that("same-opportunity conversion is the identity", {
  sig <- .ms_cv_sig()
  out <- ms_convert(sig, from = "human-genome", to = "human-genome")
  expect_lt(max(abs(out - sig)), 1e-12)
  # Columns still sum to 1.
  expect_lt(max(abs(colSums(out) - 1)), 1e-12)
})

test_that("the exome conversion matches sigminer's sig_convert numerically", {
  skip_if_not_installed("sigminer")
  set.seed(7)
  sig <- .ms_cv_sig()
  ours <- ms_convert(sig, from = "human-genome", to = "human-exome")
  theirs <- sigminer::sig_convert(sig, from = "human-genome",
    to = "human-exome")
  # sigminer returns in its own row order; compare by label.
  expect_true(setequal(rownames(ours), rownames(theirs)))
  expect_lt(max(abs(ours[rownames(theirs), , drop = FALSE] - theirs)),
    1e-12)
  # And back.
  back <- ms_convert(ours, from = "human-exome", to = "human-genome")
  theirs_back <- sigminer::sig_convert(theirs, from = "human-exome",
    to = "human-genome")
  expect_lt(max(abs(back[rownames(theirs_back), ] - theirs_back)), 1e-12)
})

test_that("roundtrip reversibility and zero-column honesty", {
  set.seed(11)
  sig <- .ms_cv_sig(2)
  sig[, 2] <- 0 # a degenerate zero signature
  fwd <- ms_convert(sig, from = "human-genome", to = "human-exome")
  expect_true(all(is.finite(fwd)))
  expect_identical(sum(fwd[, 2]), 0) # zero stays zero, no NaN
  back <- ms_convert(fwd, from = "human-exome", to = "human-genome")
  expect_lt(max(abs(back[, 1] - sig[, 1])), 1e-8)
})

test_that("the MsSignature method converts signatures and keeps exposures", {
  labels <- .ms_cv_labels()
  sig <- matrix(runif(96 * 2) + 0.01, 96, 2, dimnames = list(labels,
    c("A", "B")))
  sig <- sweep(sig, 2, colSums(sig), "/")
  expo <- matrix(c(100, 50), 2, 1, dimnames = list(c("A", "B"), "T1"))
  s1 <- ms_signature(sig, expo, list(n_channels = 96L, n_samples = 1L,
    channel_name = "SBS96", channel_hash = "ffffffffffffffffffffffffffffffff",
    build = "SYN"), engine = "synthetic", seed = 1)
  s2 <- ms_convert(s1, "human-genome", "human-exome")
  expect_is_ms(s2, "MsSignature")
  expect_false(identical(s2@signatures, s1@signatures))
  expect_identical(s2@exposures, s1@exposures) # untouched by design
  expect_lt(max(abs(colSums(s2@signatures) - 1)), 1e-12)
})

test_that("custom opportunity vectors work and error paths are structured", {
  sig <- .ms_cv_sig(1)
  custom <- rep(1, 96); names(custom) = .ms_cv_labels()
  out <- ms_convert(sig, from = "human-genome", to = custom)
  # to = uniform re-expresses the signature as source-opportunities-free:
  # sig/o_from renormalized. Hand-derive for one channel.
  o_from <- msuiter:::.ms_convert_opps$`human-genome`
  want <- sig[, 1] / o_from
  want <- want / sum(want)
  expect_lt(max(abs(out[, 1] - want)), 1e-12)
  expect_ms_error(ms_convert(sig, from = "human-genome", to = "panel-x"),
    "option")
  bad <- rep(1, 96); bad[1] <- 0; names(bad) <- .ms_cv_labels()
  expect_ms_error(ms_convert(sig, from = "human-genome", to = bad),
    "input")
  neg <- rep(1, 96); neg[2] <- -1; names(neg) <- .ms_cv_labels()
  expect_ms_error(ms_convert(sig, from = neg, to = "human-genome"),
    "input")
  # Unnamed custom vectors align positionally to the registry labels
  # (the rownames check pins the matrix order). An all-1 target
  # re-expresses free of the genome bias — hand-derive.
  wrong_nm <- rep(1, 96)
  out2 <- ms_convert(sig, from = "human-genome", to = wrong_nm)
  o_from <- msuiter:::.ms_convert_opps$`human-genome`
  want2 <- sig[, 1] / o_from
  want2 <- want2 / sum(want2)
  expect_lt(max(abs(out2[, 1] - want2)), 1e-12)
  shuffled <- sig[sample(96), , drop = FALSE]
  expect_ms_error(ms_convert(shuffled, from = "human-genome",
    to = "human-exome"), "input")
  expect_ms_error(ms_convert("junk"), "input")
})
