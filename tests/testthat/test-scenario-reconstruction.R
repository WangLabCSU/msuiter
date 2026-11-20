# test-scenario-reconstruction.R -- the CS-7 reconstruction-witness law units
# (pillar 3). The scenario plants a seeded SBS96 cohort (ms_simulate,
# count-scale exposures) and adjudicates the shipped Jiang reconstruction
# flag of ms_compare -- the per-sample cosine of each catalog column
# against signatures_est %*% exposures_est, censused against the cited line
# 0.969 -- under five arms (exact, stochastic-clean, artifakt, degenerate,
# ladder) driven through the EXPORTED face alone. The witness bytes under
# bench/scenarios/out/ are the committed verdict: a drift in the generator,
# the kernel's reconstruction block, or the flag's payload reddens here
# before print.
# Framing law: DECISION RECORD only. The flag's documented discriminative
# behavior (clean plants pass the line, planted corruption fails it, the
# corruption ladder's committed last-pass rung) is an OBSERVED, COMMITTED
# fact -- never a calibration claim: 0.969 is a cited upstream median, not
# an anchor, and cosine above it remains necessary-not-sufficient
# (R/ms-compare.R header; research-02). The hard rails are the two hard
# share rails (clean arms share_reasonable == 1, the artifakt arm == 0),
# the NA bit of the degenerate column, and the monotone law on the ladder.
# No new estimation machinery, no sanity harness, no bootstrap, no
# intervals -- the declined rails are spoken by the runner itself
# ([attest] rails) and grepped here. The pillar-2 idiom of reaching the
# internal helper directly (msuiter:::) is BANNED here and grepped away.

.rs_out <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.rs_csv <- function(fname) {
  read.csv(.rs_out(fname), header = TRUE, stringsAsFactors = FALSE)
}

.rs_tsv <- function(fname) {
  read.csv(.rs_out(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE)
}

# Frozen scenario constants -- mirrored byte-identically in
# bench/scenarios/run_reconstruction.R (single source of truth is the pair
# of files; a drift reddens the scalars unit below).
.CS7_SIG <- c("SBS1", "SBS2", "SBS13", "SBS88")
.CS7_K <- 4L
.CS7_N <- 8L
.CS7_SAMPLES <- paste0("R", formatC(1:8, width = 2L, flag = "0"))
.CS7_TOT <- c(1600, 1800, 2000, 2200, 2400, 2600, 3000, 3600)
.CS7_W <- c(0.40, 0.25, 0.20, 0.15)          # circulant per-sample weights
.CS7_PLANT_SEED <- 9L
.CS7_CMP_SEED <- 2L
.CS7_NULL_N <- 200L
.CS7_NULL_DRAWS <- 200L
.CS7_COSINE_LINE <- 0.969
# Census domain ceiling with a one-ulp slack: cos(x, x) measures at
# 1 + 1 ulp on this platform's sqrt path (probe: cos = 1.0000000000000002
# on 2 of 8 exact-arm columns), so the domain verdict must not be undone
# by representation alone.
.CS7_COSINE_HI <- 1 + 4 * .Machine$double.eps
.CS7_RUNGS <- c(0, 0.10, 0.18, 0.25, 0.32, 0.40, 0.50)
.CS7_DEAD_COL <- 3L
.CS7_ART_ROT <- c(2L, 3L, 4L, 1L)             # planted dictionary rotation

# The dictionary: bundled bytes only (never downloaded), columns
# normalized to sum 1 in the canonical channel order.
.cs7_dict <- function() {
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  dict <- mat[, .CS7_SIG, drop = FALSE]
  sweep(dict, 2L, colSums(dict), "/")
}

# The frozen count-scale exposure plan (k x n): sample j carries the
# weight pattern .CS7_W rotated by (j - 1) mod 4, scaled by TOT[j].
# Every cell is a strict fraction of its column total -- the planted
# dictionary rotation therefore perturbs EVERY column's shape (the
# artifakt arm's share-to-0 rail rests on this).
.cs7_exposures <- function() {
  E <- matrix(0, nrow = .CS7_K, ncol = .CS7_N,
              dimnames = list(.CS7_SIG, .CS7_SAMPLES))
  for (j in seq_len(.CS7_N)) {
    idx <- ((seq_len(.CS7_K) - 1L + (j - 1L)) %% .CS7_K) + 1L
    E[, j] <- .CS7_W[idx] * .CS7_TOT[j]
  }
  E
}

# The corruption twin: exposure rows shifted by one signature, so blending
# toward it moves each sample's bulk into the wrong signature.
.cs7_exposures_wrong <- function() {
  E <- .cs7_exposures()
  E[c(2L, 3L, 4L, 1L), , drop = FALSE]
}

.cs7_ladder_exposures <- function(w) {
  E <- .cs7_exposures()
  (1 - w) * E + w * .cs7_exposures_wrong()
}

# The deterministic exact plant: the linear expectation itself (no RNG),
# so the face's own reconstruction must read it at cosine 1.
.cs7_exact_catalog <- function() {
  fitted <- .cs7_dict() %*% .cs7_exposures()
  dimnames(fitted) <- list(rownames(.cs7_dict()), .CS7_SAMPLES)
  fitted
}

# The stochastic plant: the package's own generator at the frozen seed.
# Totals are deterministic under the multinomial arm (size = round(sum(mu))).
.cs7_plant <- function() {
  ms_simulate(signatures = .cs7_dict(), exposures = .cs7_exposures(),
              seed = .CS7_PLANT_SEED)
}

# Hand-written cosine mirroring the shipped scalar exactly (the
# dual-derivation leg): plain portable arithmetic only.
.cs7_cos <- function(x, y) {
  nx <- sqrt(sum(x * x))
  ny <- sqrt(sum(y * y))
  if (nx == 0 || ny == 0) {
    return(NA_real_)
  }
  sum(x * y) / (nx * ny)
}

# A face call of the committed shape: the EXPORTED ms_compare only, jiang
# requested, the flag fed, the null MC small and seed-frozen.
.cs7_face <- function(estimated, reference, exposures_est, exposures_ref,
                      catalogs, signatures_est) {
  ms_compare(estimated, reference, metric = "cosine", protocol = "jiang",
             exposures_est = exposures_est, exposures_ref = exposures_ref,
             catalogs = catalogs, signatures_est = signatures_est,
             null_n = .CS7_NULL_N, null_n_draws = .CS7_NULL_DRAWS,
             seed = .CS7_CMP_SEED)
}

test_that("the CS-7 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "bench", "scenarios", "run_reconstruction.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_compare", src, fixed = TRUE))
  expect_true(grepl("ms_simulate", src, fixed = TRUE))
  expect_true(grepl("ms_refdb_bundled", src, fixed = TRUE))
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  # Rail 2, spoken by absence: the pillar-2 internal-helper idiom is
  # banned from the scenario and its law alike.
  expect_false(grepl("msuiter:::", src, fixed = TRUE))
  # Declined rails made audible in the runner itself.
  expect_true(grepl("conformal", src, fixed = TRUE))
  expect_true(grepl("calibrate-real", src, fixed = TRUE))
})

test_that("the scalars witness pins the frozen scenario constants", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  scal <- .rs_csv("cs7_scalars.csv")
  expect_identical(nrow(scal), 1L)
  expect_identical(as.numeric(scal$cosine_line), .CS7_COSINE_LINE)
  expect_identical(as.character(scal$dict_roster), paste(.CS7_SIG, collapse = ","))
  expect_identical(as.integer(scal$k), .CS7_K)
  expect_identical(as.integer(scal$n_samples), .CS7_N)
  expect_identical(as.character(scal$totals),
                   paste0(.CS7_TOT, collapse = ","))
  expect_identical(as.character(scal$weights),
                   paste0(.CS7_W, collapse = ","))
  expect_identical(as.integer(scal$plant_seed), as.integer(.CS7_PLANT_SEED))
  expect_identical(as.integer(scal$cmp_seed), as.integer(.CS7_CMP_SEED))
  expect_identical(as.integer(scal$null_n), as.integer(.CS7_NULL_N))
  expect_identical(as.integer(scal$null_n_draws), as.integer(.CS7_NULL_DRAWS))
  expect_identical(as.character(scal$rung_values),
                   paste0(.CS7_RUNGS, collapse = ","))
  expect_identical(as.integer(scal$dead_col), as.integer(.CS7_DEAD_COL))
  # the shipped line itself, straight from the face's defaults
  expect_identical(as.numeric(msuiter:::.ms_compare_defaults$reconstruction_cosine),
                   .CS7_COSINE_LINE)
})

test_that("the planted cohort re-derives byte-exactly at the frozen seed", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  plant <- .rs_csv("cs7_plant.csv")
  expect_identical(names(plant)[1L], "channel")
  expect_identical(names(plant)[-1L], .CS7_SAMPLES)
  cat <- .cs7_plant()
  expect_identical(plant$channel, as.character(rownames(cat@counts)))
  for (s in .CS7_SAMPLES) {
    expect_identical(as.integer(plant[[s]]), as.integer(cat@counts[, s]))
  }
  expect_identical(as.integer(unname(colSums(cat@counts))),
                   as.integer(round(colSums(.cs7_exposures()))))
})

test_that("the exact arm reads its own expectation: all-pass, dual-derivation EXACT", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  per <- .rs_csv("cs7_per_sample.csv")
  arms <- .rs_csv("cs7_arms.csv")
  exact <- per[per$arm == "exact", , drop = FALSE]
  expect_identical(exact$sample, .CS7_SAMPLES)
  # hard rail: the clean reconstruction censuses every sample above the line
  expect_identical(as.integer(exact$pass), rep(1L, .CS7_N))
  expect_identical(as.integer(exact$is_na), rep(0L, .CS7_N))
  exact_row <- arms[arms$arm == "exact", , drop = FALSE]
  expect_identical(as.integer(exact_row$share_reasonable), 1L)
  # fresh re-derivation through the exported face, EXACT on the bits,
  # dual-derivation EXACT on the floats (portable arithmetic only)
  dict <- .cs7_dict()
  fitted <- dict %*% .cs7_exposures()
  cmp <- .cs7_face(dict, dict, .cs7_exposures(), .cs7_exposures(),
                   .cs7_exact_catalog(), dict)
  fresh <- cmp@jiang$reconstruction$per_sample
  expect_identical(as.integer(fresh > .CS7_COSINE_LINE), as.integer(exact$pass))
  hand <- vapply(seq_len(.CS7_N), function(j) {
    .cs7_cos(.cs7_exact_catalog()[, j], fitted[, j])
  }, numeric(1L))
  expect_identical(fresh, hand)
})

test_that("the stochastic clean arm passes every sample at the frozen seed", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  per <- .rs_csv("cs7_per_sample.csv")
  arms <- .rs_csv("cs7_arms.csv")
  clean <- per[per$arm == "clean", , drop = FALSE]
  expect_identical(clean$sample, .CS7_SAMPLES)
  # hard rail: an honest reconstruction never trips the shipped flag
  expect_identical(as.integer(clean$pass), rep(1L, .CS7_N))
  expect_identical(as.integer(clean$is_na), rep(0L, .CS7_N))
  clean_row <- arms[arms$arm == "clean", , drop = FALSE]
  expect_identical(as.integer(clean_row$share_reasonable), 1L)
  # fresh re-derivation: bytes frozen on the bits, payload census on the
  # floats (D11 posture; the floats here are portable basic arithmetic,
  # the exact-dual-derivation leg above pins their values anyway)
  cat <- .cs7_plant()
  dict <- .cs7_dict()
  cmp <- .cs7_face(dict, dict, .cs7_exposures(), .cs7_exposures(),
                   cat@counts, dict)
  expect_identical(as.integer(cmp@jiang$reconstruction$per_sample > .CS7_COSINE_LINE),
                   as.integer(clean$pass))
  expect_true(all(is.na(cmp@jiang$reconstruction$per_sample) ==
                     (as.integer(clean$is_na) == 1L)))
})

test_that("the artifakt arm is censused below the line", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  per <- .rs_csv("cs7_per_sample.csv")
  arms <- .rs_csv("cs7_arms.csv")
  art <- per[per$arm == "artifakt", , drop = FALSE]
  expect_identical(art$sample, .CS7_SAMPLES)
  # hard rail: the planted dictionary rotation trips EVERY sample -- the
  # circulant exposure design (every signature carries weight in every
  # sample) is what makes this rail bite
  expect_identical(as.integer(art$pass), rep(0L, .CS7_N))
  expect_identical(as.integer(art$is_na), rep(0L, .CS7_N))
  art_row <- arms[arms$arm == "artifakt", , drop = FALSE]
  expect_identical(as.integer(art_row$share_reasonable), 0L)
  expect_true(as.numeric(art_row$median_cosine) < .CS7_COSINE_LINE)
  # fresh re-derivation through the exported face
  dict <- .cs7_dict()
  rot <- dict[, .CS7_ART_ROT, drop = FALSE]
  cmp <- .cs7_face(rot, dict, .cs7_exposures(), .cs7_exposures(),
                   .cs7_exact_catalog(), rot)
  fresh <- cmp@jiang$reconstruction$per_sample
  expect_identical(as.integer(fresh > .CS7_COSINE_LINE), as.integer(art$pass))
  # the dual-derivation pair, EXACT: same inputs, hand-written expression
  fitted <- rot %*% .cs7_exposures()
  hand <- vapply(seq_len(.CS7_N), function(j) {
    .cs7_cos(.cs7_exact_catalog()[, j], fitted[, j])
  }, numeric(1L))
  expect_identical(fresh, hand)
})

test_that("the degenerate column speaks its NA bit", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  per <- .rs_csv("cs7_per_sample.csv")
  arms <- .rs_csv("cs7_arms.csv")
  deg <- per[per$arm == "degenerate", , drop = FALSE]
  expect_identical(deg$sample, .CS7_SAMPLES)
  want_na <- rep(0L, .CS7_N)
  want_na[.CS7_DEAD_COL] <- 1L
  expect_identical(as.integer(deg$is_na), want_na)
  expect_identical(as.integer(deg$pass), as.integer(1L - want_na))
  deg_row <- arms[arms$arm == "degenerate", , drop = FALSE]
  expect_identical(as.integer(deg_row$n_na), 1L)
  # the surviving columns keep the clean verdict (share is na.rm'd over them)
  expect_identical(as.integer(deg_row$share_reasonable), 1L)
  # fresh re-derivation: zero the dead column of the exact plant
  dead <- .cs7_exact_catalog()
  dead[, .CS7_DEAD_COL] <- 0
  dict <- .cs7_dict()
  cmp <- .cs7_face(dict, dict, .cs7_exposures(), .cs7_exposures(),
                   dead, dict)
  fresh <- cmp@jiang$reconstruction$per_sample
  expect_identical(as.integer(is.na(fresh)), want_na)
  expect_identical(as.integer(stats::na.omit(fresh) > .CS7_COSINE_LINE),
                   as.integer(deg$pass[as.integer(want_na) == 0L]))
})

test_that("the corruption ladder is monotone and its last-pass rung is committed", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lad <- .rs_csv("cs7_ladder.csv")
  expect_identical(names(lad), c("rung", "share_pass", "is_pass"))
  expect_identical(as.numeric(lad$rung), .CS7_RUNGS)
  shares <- as.numeric(lad$share_pass)
  expect_true(all(diff(shares) <= 0))                    # non-increasing in w
  expect_identical(shares[1L], 1)                        # rung 0 is the clean arm
  last_pass <- if (any(lad$is_pass == 1L)) max(as.numeric(lad$rung[lad$is_pass == 1L])) else NA_real_()
  scal <- .rs_csv("cs7_scalars.csv")
  committed <- scal$last_pass_rung
  if (is.na(last_pass)) {
    expect_true(is.na(as.numeric(committed)))
  } else {
    expect_identical(as.numeric(committed), as.numeric(last_pass))
  }
  # dual-derivation at the two decisive rungs: rung 0 (clean) and the tail.
  # The fresh bits must aggregate to the committed share byte (portable
  # arithmetic), and the committed is_pass bit is the share==1 verdict.
  dict <- .cs7_dict()
  for (w in c(.CS7_RUNGS[1L], .CS7_RUNGS[length(.CS7_RUNGS)])) {
    cmp <- .cs7_face(dict, dict, .cs7_ladder_exposures(w), .cs7_exposures(),
                     .cs7_exact_catalog(), dict)
    bits <- as.integer(cmp@jiang$reconstruction$per_sample > .CS7_COSINE_LINE)
    row <- lad[abs(as.numeric(lad$rung) - w) < 1e-12, , drop = FALSE]
    expect_identical(mean(bits), as.numeric(row$share_pass))
    expect_identical(as.integer(row$is_pass),
                     as.integer(as.numeric(row$share_pass) == 1))
  }
})

test_that("the witness payload census: every scored column alive and in-domain", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  per <- .rs_csv("cs7_per_sample.csv")
  expect_identical(names(per), c("sample", "arm", "per_sample", "is_na", "pass"))
  ok_num <- as.integer(per$is_na) == 1L
  expect_true(all(as.character(per$pass) %in% c("0", "1")))
  expect_true(all(as.character(per$is_na) %in% c("0", "1")))
  vals <- as.numeric(per$per_sample)
  expect_true(all(is.na(vals)[ok_num]))                  # NA cells flagged
  expect_true(all(vals[!ok_num] >= 0) && all(vals[!ok_num] <= .CS7_COSINE_HI))
  expect_identical(as.integer(per$pass[!ok_num]),
                   as.integer(vals[!ok_num] > .CS7_COSINE_LINE))
  arms <- .rs_csv("cs7_arms.csv")
  expect_identical(names(arms),
                   c("arm", "cosine_line", "median_cosine",
                     "share_reasonable", "n_na"))
  expect_true(all(as.numeric(arms$cosine_line) == .CS7_COSINE_LINE))
  expect_true(all(is.finite(as.numeric(arms$median_cosine))))
  expect_true(all(as.numeric(arms$median_cosine) >= 0 &
                     as.numeric(arms$median_cosine) <= .CS7_COSINE_HI))
  expect_true(all(as.numeric(arms$share_reasonable) >= 0 &
                     as.numeric(arms$share_reasonable) <= 1))
  expect_true(all(is.finite(as.numeric(arms$n_na)) &
                     as.numeric(arms$n_na) >= 0))
})

test_that("the degenerate side facts speak", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  deg <- .rs_tsv("cs7_degenerates.tsv")
  expect_identical(names(deg), c("check", "value"))
  vals <- setNames(deg$value, deg$check)
  expect_identical(as.integer(vals[["same_seed_reproducible"]]), 1L)
  expect_identical(as.integer(vals[["cross_seed_plant_differs"]]), 1L)
  expect_identical(as.integer(vals[["artifakt_share_zero"]]), 1L)
  expect_identical(as.integer(vals[["clean_share_one"]]), 1L)
  expect_identical(as.integer(vals[["exact_share_one"]]), 1L)
  expect_identical(as.integer(vals[["degenerate_n_na_one"]]), 1L)
})
