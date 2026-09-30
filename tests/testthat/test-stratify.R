# U-M1c-02: GMM hypermutant stratification.
#
# The integer goldens below are THE SAME values pinned by the Rust kernel
# tests (src/rust/engine/src/stats.rs): the R side is a protocol twin of
# engine::stats and must reproduce them bit-for-bit on the shared fixtures.
#
# The MAIN path of ms_stratify_hypermutants() goes through the FFI
# (ms_stratify_rust, M2 pipeline plan slot); the pure-R twin is kept as the
# reference implementation (msuiter_stratify_twin) and pinned to it below.

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
# Twin vs FFI: the main path runs the Rust kernel (ms_stratify_rust); the
# pure-R protocol twin must stay identical on every integer/structural
# outcome (cutoff, group rosters, counts, convergence flag). retained_mean/
# retained_sd are the only drift-eligible fields (libm) and are pinned by
# the engine goldens instead.
# ---------------------------------------------------------------------------

test_that("FFI main path is identical to the pure-R protocol twin", {
  combos <- list(
    list(
      what = "bimodal cohort (6 injected hypermutants)",
      totals = setNames(bimodal_cohort(), sprintf("S%02d", 1:50)),
      manual_cutoff = 0, seed = 1
    ),
    list(
      what = "lone outlier (500000 against a 40-sample ramp)",
      totals = setNames(ramp_with_outlier(), sprintf("S%02d", 1:41)),
      manual_cutoff = 0, seed = 3
    ),
    list(
      what = "manual floor wins (20000 over the derived 13804)",
      totals = setNames(bimodal_cohort(), sprintf("S%02d", 1:50)),
      manual_cutoff = 20000, seed = 42
    ),
    list(
      what = "all-identical degenerate cohort",
      totals = setNames(rep(7000, 30), sprintf("S%02d", 1:30)),
      manual_cutoff = 0, seed = 3
    ),
    list(
      what = "single sample",
      totals = setNames(12345, "SOLO"),
      manual_cutoff = 0, seed = 1
    )
  )
  for (cmb in combos) {
    twin <- msuiter_stratify_twin(cmb$totals, cmb$manual_cutoff, cmb$seed)
    s <- ms_stratify_hypermutants(
      cmb$totals, manual_cutoff = cmb$manual_cutoff, seed = cmb$seed
    )
    expect_identical(s@cutoff, twin$cutoff, info = cmb$what)
    expect_identical(
      s@hyper, names(cmb$totals)[twin$hypermutant_idx + 1L], info = cmb$what
    )
    expect_identical(
      s@nonhyper,
      if (length(twin$hypermutant_idx) > 0L) {
        names(cmb$totals)[-c(twin$hypermutant_idx + 1L)]
      } else {
        names(cmb$totals)
      },
      info = cmb$what
    )
    expect_identical(s@n_hyper, twin$n_hypermutants, info = cmb$what)
    expect_identical(
      s@n_nonhyper, length(cmb$totals) - twin$n_hypermutants, info = cmb$what
    )
    expect_identical(
      s@gmm$retained_n, twin$cluster_stats$retained_n, info = cmb$what
    )
    expect_identical(
      s@gmm$n_fits, twin$cluster_stats$n_fits, info = cmb$what
    )
    expect_identical(
      s@gmm$converged, twin$cluster_stats$converged, info = cmb$what
    )
  }
})

test_that("twin and FFI agree end-to-end through an MsCatalog", {
  totals <- bimodal_cohort()
  samples <- sprintf("S%02d", seq_along(totals))
  labels <- paste0("CH", 1:4)
  counts <- matrix(0, 4, length(totals), dimnames = list(labels, samples))
  counts[1, ] <- totals
  cat1 <- ms_catalog(counts, list(name = "SYN4", labels = labels), samples,
    provenance = list(genome = "GRCh38")
  )
  twin <- msuiter_stratify_twin(totals, 100 * 4L, 1)
  s <- ms_stratify_hypermutants(cat1, seed = 1)
  expect_identical(s@cutoff, twin$cutoff)
  expect_identical(s@hyper, samples[twin$hypermutant_idx + 1L])
  expect_identical(s@n_hyper, twin$n_hypermutants)
})

test_that("kernel-side second-layer guards surface msuiter_error_rust", {
  # The R validators are the first layer (msuiter_error_input); these go
  # straight at the FFI wrapper to pin the second layer and the unified
  # error face (Rust core -> msuiter_error_rust condition, i/j payload).
  err <- tryCatch(
    .ms_stratify_rust(matrix(c(1, -5), nrow = 1), 0, 1),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_identical(err$topic, "argument")
  expect_identical(err$i, 1L)
  expect_identical(err$j, 2L)

  # Fractional counts are outside the counts domain.
  err <- tryCatch(
    .ms_stratify_rust(matrix(1.5, nrow = 1, ncol = 1), 0, 1),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_match(err$message, "integer-valued")

  # Inf passes anyNA and is caught by the kernel scan as `na`.
  err <- tryCatch(
    .ms_stratify_rust(matrix(c(Inf, 2), nrow = 1), 0, 1),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_identical(err$topic, "na")

  # No sample columns: the kernel's own empty guard.
  err <- tryCatch(
    .ms_stratify_rust(matrix(numeric(0), nrow = 1, ncol = 0), 0, 1),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_match(err$message, "no samples")

  # Through the public API: a seed beyond the 2^53 wire bound (the Rust
  # conditions carry the i/j/c payload as TOP-LEVEL fields, not the
  # msuiter_abort structure, so the raw class/topic assertions apply).
  err <- tryCatch(
    ms_stratify_hypermutants(setNames(1, "a"), seed = 1e16),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_match(err$message, "seed")
})

test_that("empty totals vectors are rejected as input errors", {
  expect_ms_error(ms_stratify_hypermutants(setNames(numeric(0), character(0)), seed = 1), "input")
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
