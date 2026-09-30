# U-M1c-02: GMM hypermutant stratification.
#
# The integer goldens below are THE SAME values pinned by the Rust kernel
# tests (src/rust/engine/src/stats.rs): the R side is a protocol twin of
# engine::stats and must reproduce them bit-for-bit on the shared fixtures.

# Fixtures mirroring stats::tests (same arithmetic formulas).
bimodal_cohort <- function() {
  v <- numeric(0)
  for (i in 0:43) {
    v <- c(v, 4200 + 700 * (i %% 13) + 130 * (i %% 7) + 40 * (i %% 3))
  }
  c(v, 81000, 96000, 120000, 133000, 145000, 158000)
}

ramp_with_outlier <- function() {
  c(4800 + 37 * (0:39), 500000)
}

# ---------------------------------------------------------------------------
# PCG64 KAT: the pure-R stream replication must reproduce the FROZEN rng.rs
# goldens (docs-pinned bit patterns, independently re-derived by
# tools/rng-kat.py). Any diff here means the R twin drifted from the
# canonical MsRng layout.
# ---------------------------------------------------------------------------

test_that("pure-R PCG64 matches the frozen rng.rs goldens", {
  words <- msuiter_rng_words_hex(42, 3)
  expect_identical(words[1], "0ad917fbf73da447")
  expect_identical(words[2], "a98d2e04188c8d56")
  expect_identical(words[3], "7ba8f275b1e7fcab")

  offset <- msuiter_rng_words_hex(42, 1, replicate = 7, rank = 3, fold = 5)
  expect_identical(offset, "52bd0376edbea6a8")

  zero_seed <- msuiter_rng_words_hex(0, 1, replicate = 1, rank = 2, fold = 3)
  expect_identical(zero_seed, "e51971891d4876f2")
})

# ---------------------------------------------------------------------------
# Golden cutoffs (cross-language: identical to the Rust kernel goldens).
# ---------------------------------------------------------------------------

test_that("bimodal cohort: cutoff, groups and model match the Rust golden", {
  x <- bimodal_cohort()
  totals <- setNames(x, sprintf("S%02d", seq_along(x)))
  s <- ms_stratify_hypermutants(totals, manual_cutoff = 0, seed = 1)

  expect_identical(s@cutoff, 13804)
  expect_is_ms(s, "MsStratification")
  expect_identical(s@hyper, sprintf("S%02d", 45:50))
  expect_identical(s@n_hyper, 6)
  expect_identical(s@n_nonhyper, 44)
  expect_identical(s@gmm$retained_n, 44)
  expect_identical(s@gmm$n_fits, 2)
  expect_true(s@gmm$converged)
  # Model parameters sit inside the EM tolerance ball and are pinned
  # bit-exactly only in the Rust kernel (libm drift across languages);
  # the cross-language contract is the integer cutoff + retained set.
  expect_true(abs(s@gmm$retained_mean - 8496.129238) < 1)
  expect_identical(s@policy, "exclude_de_novo_then_refit")
})

test_that("cutoff is seed-robust on separated cohorts (seeds 1-8)", {
  totals <- setNames(bimodal_cohort(), sprintf("S%02d", 1:50))
  for (seed in 1:8) {
    s <- ms_stratify_hypermutants(totals, manual_cutoff = 0, seed = seed)
    expect_identical(s@cutoff, 13804, info = paste("seed", seed))
  }
})

test_that("extreme outlier is pruned (Rust golden 6375)", {
  totals <- setNames(ramp_with_outlier(), sprintf("S%02d", 1:41))
  s <- ms_stratify_hypermutants(totals, manual_cutoff = 0, seed = 1)
  expect_identical(s@cutoff, 6375)
  expect_identical(s@gmm$retained_n, 40)
  expect_identical(s@hyper, "S41")
  expect_true(abs(s@gmm$retained_mean - 5521.5) < 1e-9)
})

test_that("degenerate inputs degrade like the upstream try/except", {
  same <- setNames(rep(7000, 30), sprintf("S%02d", 1:30))
  s <- ms_stratify_hypermutants(same, manual_cutoff = 0, seed = 1)
  expect_identical(s@cutoff, 7000)
  expect_identical(s@hyper, character(0))
  expect_identical(s@gmm$n_fits, 1)

  one <- setNames(12345, "SOLO")
  s1 <- ms_stratify_hypermutants(one, manual_cutoff = 0, seed = 1)
  expect_identical(s1@cutoff, 12345)
  expect_identical(s1@gmm$n_fits, 0)
})

test_that("manual_cutoff floors the derived value (call-site convention)", {
  totals <- setNames(bimodal_cohort(), sprintf("S%02d", 1:50))
  expect_identical(
    ms_stratify_hypermutants(totals, manual_cutoff = 9600, seed = 1)@cutoff,
    13804
  )
  expect_identical(
    ms_stratify_hypermutants(totals, manual_cutoff = 20000, seed = 1)@cutoff,
    20000
  )
})

# ---------------------------------------------------------------------------
# End-to-end through an MsCatalog.
# ---------------------------------------------------------------------------

test_that("catalog path: injected hypermutants are separated end-to-end", {
  totals <- bimodal_cohort()
  samples <- sprintf("S%02d", seq_along(totals))
  labels <- paste0("CH", 1:4)
  # All mass in channel 1 keeps the totals exact by construction.
  counts <- matrix(0, 4, length(totals), dimnames = list(labels, samples))
  counts[1, ] <- totals
  cat1 <- ms_catalog(counts, list(name = "SYN4", labels = labels), samples,
    provenance = list(genome = "GRCh38")
  )
  # Default manual_cutoff = 100 x 4 channels = 400 (below the derived
  # cutoff): the call-site convention must stay inert here.
  s <- ms_stratify_hypermutants(cat1, seed = 1)
  expect_identical(s@cutoff, 13804)
  expect_identical(s@hyper, sprintf("S%02d", 45:50))
  expect_identical(s@nonhyper, sprintf("S%02d", 1:44))
  expect_identical(s@totals, setNames(totals, samples))
})

test_that("stratification is deterministic: same input, identical object", {
  totals <- setNames(bimodal_cohort(), sprintf("S%02d", 1:50))
  a <- ms_stratify_hypermutants(totals, manual_cutoff = 9600, seed = 42)
  b <- ms_stratify_hypermutants(totals, manual_cutoff = 9600, seed = 42)
  expect_identical(a, b)
})

test_that("classification predicate is strictly greater than the cutoff", {
  totals <- c(a = 9600, b = 9601)
  s <- ms_stratify_hypermutants(totals, manual_cutoff = 9600, seed = 1)
  # Two-sample tie: majority tie-break keeps the low cluster (Rust golden),
  # then the floor applies; equality is NOT hypermutated.
  expect_identical(s@cutoff, 9600)
  expect_identical(s@hyper, "b")
  expect_identical(s@nonhyper, "a")
})

# ---------------------------------------------------------------------------
# Object discipline: format, validator, error paths.
# ---------------------------------------------------------------------------

test_that("format prints the decision line", {
  totals <- setNames(bimodal_cohort(), sprintf("S%02d", 1:50))
  s <- ms_stratify_hypermutants(totals, manual_cutoff = 0, seed = 1)
  expect_match(format(s), "<MsStratification> GMM cutoff 13804: 6/50 hypermutated")
  expect_match(format(s), "refit pending")
  expect_invisible(print(s))
})

test_that("validator rejects tampered stratification objects", {
  totals <- setNames(bimodal_cohort(), sprintf("S%02d", 1:50))
  s <- ms_stratify_hypermutants(totals, manual_cutoff = 0, seed = 1)
  expect_ms_error(S7::set_props(s, n_hyper = 7), "stratify")
  expect_ms_error(S7::set_props(s, policy = "rescale_to_cutoff"), "stratify")
})

test_that("input violations raise structured msuiter_error_input", {
  expect_ms_error(ms_stratify_hypermutants(c(1, 2, 3), seed = 1), "input")
  expect_ms_error(ms_stratify_hypermutants(c(a = 1, b = NA), seed = 1), "input")
  expect_ms_error(ms_stratify_hypermutants(c(a = 1), seed = 0.5), "input")
  expect_ms_error(
    ms_stratify_hypermutants(c(a = 1), manual_cutoff = -1, seed = 1),
    "input"
  )

  labels <- paste0("CH", 1:2)
  empty <- ms_catalog(
    matrix(0, 2, 0, dimnames = list(labels, character(0))),
    list(name = "SYN2", labels = labels), character(0),
    provenance = list(genome = "GRCh38")
  )
  expect_ms_error(ms_stratify_hypermutants(empty, seed = 1), "input")
})
