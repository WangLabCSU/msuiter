# U-M7-pre: ms_simulate() -- the catalog scenario simulator first
# version (design memo docs/devlog/2026-10-05-simulate-memo.md).
#
# Anchors: bitwise seed determinism, exact multinomial burden, the NB
# per-channel variance law (Var = mu + mu^2/kappa => var/mean =
# 1 + mu_c/kappa on a uniform dictionary), share/count exposure scale
# auto-detection, provenance, and structured error paths.

.ms_sim_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

# One flat signature = uniform channels: every mu_c equal, so the NB
# per-channel variance law reads directly off the pooled counts.
.ms_sim_uniform_sig <- function(n_samples, burden, arm, size = 8,
                                seed = 1) {
  labels <- .ms_sim_labels()
  sig <- matrix(1 / 96, 96, 1, dimnames = list(labels, "FLAT"))
  expo <- matrix(1, 1, n_samples, dimnames = list("FLAT",
    paste0("T", seq_len(n_samples))))
  ms_simulate(sig, expo, arm = arm, size = size, burden = burden,
    seed = seed)
}

test_that("multinomial arm conserves the burden and is seed-bitwise", {
  labels <- .ms_sim_labels()
  sig <- matrix(abs(rnorm(96 * 3)) + 0.01, 96, 3,
    dimnames = list(labels, c("S1", "S2", "S3")))
  sig <- sweep(sig, 2, colSums(sig), "/")
  expo <- matrix(rep(1 / 3, 6), 3, 2)
  colnames(expo) <- c("A", "B")
  cat1 <- ms_simulate(sig, expo, arm = "multinomial", burden = 1000,
    seed = 1)
  expect_is_ms(cat1, "MsCatalog")
  expect_identical(as.numeric(colSums(cat1@counts)), c(1000, 1000))
  cat2 <- ms_simulate(sig, expo, arm = "multinomial", burden = 1000,
    seed = 1)
  expect_identical(cat1@counts, cat2@counts)
  # A different seed changes the draw.
  cat3 <- ms_simulate(sig, expo, arm = "multinomial", burden = 1000,
    seed = 2)
  expect_false(identical(cat1@counts, cat3@counts))
  # Provenance records the draw.
  expect_identical(cat1@provenance$arm, "multinomial")
  expect_identical(cat1@provenance$seed, 1)
  expect_identical(cat1@provenance$exposure_scale, "share")
})

test_that("the NB arm obeys the per-channel variance law", {
  # Uniform dictionary => every channel has mu_c = burden/96; the NB
  # law gives var/mean = 1 + mu_c/kappa per channel. 400 replicate
  # columns give a usable variance estimate.
  burden <- 4800 # mu_c = 50
  kappa <- 8
  cat1 <- .ms_sim_uniform_sig(400, burden, arm = "nb", size = kappa,
    seed = 9)
  mu_c <- burden / 96
  want <- 1 + mu_c / kappa
  # Per-channel var/mean, then the median across channels (robust to
  # the few low-count channels).
  vm <- apply(cat1@counts, 1L, function(x) var(x) / mean(x))
  expect_lt(abs(median(vm) - want) / want, 0.15)
  # And the mean tracks mu_c.
  expect_lt(abs(mean(cat1@counts) - mu_c) / mu_c, 0.02)
})

test_that("the poisson arm is the unit-dispersion limit", {
  cat1 <- .ms_sim_uniform_sig(400, 4800, arm = "poisson", seed = 3)
  vm <- apply(cat1@counts, 1L, function(x) var(x) / mean(x))
  expect_lt(abs(median(vm) - 1), 0.12)
})

test_that("count-scale exposures carry their own totals", {
  labels <- .ms_sim_labels()
  sig <- matrix(1 / 96, 96, 1, dimnames = list(labels, "FLAT"))
  expo <- matrix(250, 1, 2, dimnames = list("FLAT", c("A", "B")))
  cat1 <- ms_simulate(sig, expo, arm = "multinomial", seed = 4)
  expect_identical(as.numeric(colSums(cat1@counts)), c(250, 250))
  expect_identical(cat1@provenance$exposure_scale, "count")
})

test_that("DBS78 space works and error paths are structured", {
  dbs <- msuiter:::.ms_io_channel_tables()$DBS78
  sig <- matrix(1 / 78, 78, 1, dimnames = list(dbs, "FLAT"))
  expo <- matrix(1, 1, 1, dimnames = list("FLAT", "T1"))
  cat1 <- ms_simulate(sig, expo, arm = "poisson", burden = 500, seed = 5)
  expect_is_ms(cat1, "MsCatalog")
  expect_identical(cat1@channels$name, "DBS78")

  labels <- .ms_sim_labels()
  sig <- matrix(1 / 96, 96, 1, dimnames = list(labels, "F"))
  expect_ms_error(ms_simulate("junk", expo), "input")
  shuffled <- sig[sample(96), , drop = FALSE]
  expect_ms_error(ms_simulate(shuffled, expo), "input")
  expect_ms_error(ms_simulate(sig, matrix(1, 2, 1)), "input")
  expect_ms_error(ms_simulate(sig, expo, arm = "warp"), "option")
  expect_ms_error(ms_simulate(sig, expo, arm = "nb", size = 0), "input")
  expect_ms_error(ms_simulate(sig, expo, burden = 10.5), "input")
  expect_ms_error(ms_simulate(sig, expo, seed = -2), "input")
})
