# test-scenario-stratify.R -- the CS-5 hypermutator-stratify law units
# (pillar 3). The scenario adjudicates the certified SigProfiler-frozen
# stratification face (R/stratify.R) against a self-planted synthetic cohort
# (D3: planted truth only): order-of-magnitude hypermutants must be caught at
# recall/precision 1, the protocol twin must re-derive the committed verdict,
# the manual floor must re-adjudicate, the boundary must be strict, and the
# certified silence/degenerate branches must speak. The witness bytes under
# bench/scenarios/out/ are the committed verdict; this unit re-derives them
# from the committed plant through the public faces -- a drift between
# runner, kernel, twin, or evidence reddens here before print.
# Framing law (novelty-scan E9, Framing-B): the cutoff rule is a faithful
# upstream replication, NOT an algorithmic claim; the object is the DECISION
# RECORD only -- no "exclusion/refit happened" wording (M2 pending,
# R/stratify.R:21-25), and no diagnostic-grade (MUTYH/MSI/TMB-high) claim
# anywhere (paper-draft declined block).

.sx_out <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.sx_tsv <- function(fname) {
  read.csv(.sx_out(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE)
}

.sx_csv <- function(fname) {
  read.csv(.sx_out(fname), header = TRUE, stringsAsFactors = FALSE)
}

.sx_samples <- paste0("ST", formatC(1:50, width = 2L, flag = "0"))
# the face-proven jittered bimodal bulk (certified-converging under the
# frozen EM tol; mirrors run_stratify.R exactly) + six far spikes
.sx_bulk <- vapply(0:43L, function(i)
  8400 + 1400 * (i %% 13) + 260 * (i %% 7) + 80 * (i %% 3), numeric(1))
.sx_hyper <- 81000 + c(0, 15000, 39000, 52000, 64000, 77000)
.sx_totals <- as.integer(c(.sx_bulk, .sx_hyper))
.sx_hyper_planted <- .sx_samples[45:50]

# Floor/boundary cohort: near-unimodal bulk so the manual floor dominates,
# with the boundary twins at exactly floor / floor+1 under the floored regime.
.sx_fb_samples <- paste0("FB", formatC(1:6, width = 2L, flag = "0"))
.sx_fb_totals <- as.integer(c(9999L, 10000L, 10000L, 10001L, 20000L, 20001L))
.sx_fb_manual <- 20000L

test_that("the CS-5 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  f <- file.path(.ms_root, "bench", "scenarios", "run_stratify.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_stratify_hypermutants", src, fixed = TRUE))
  # Decision-record-only rail made audible in the runner itself.
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
})

test_that("the committed plant is the frozen 50-sample arithmetic ramp", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  plant <- .sx_tsv("stratify_plant_totals.tsv")
  expect_identical(names(plant), c("sample", "total", "planted_hyper"))
  expect_identical(plant$sample, .sx_samples)
  expect_identical(as.integer(plant$total), .sx_totals)
  expect_identical(as.integer(plant$planted_hyper),
                   as.integer(c(rep(0L, 44L), rep(1L, 6L))))
})

test_that("the committed partition adjudicates the planted truth at 1", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  part <- .sx_csv("stratify_partition.csv")
  expect_identical(part$sample, .sx_samples)
  expect_identical(as.integer(part$total), .sx_totals)
  hits <- part$sample[as.integer(part$is_hyper) == 1L]
  # recall/precision 1 against the planted roster
  expect_identical(hits, .sx_hyper_planted)
  expect_identical(as.integer(part$is_hyper),
                   as.integer(c(rep(0L, 44L), rep(1L, 6L))))
  scal <- .sx_csv("stratify_scalars.csv")
  expect_identical(nrow(scal), 1L)
  expect_identical(as.integer(scal$n_hyper), 6L)
  expect_identical(as.integer(scal$n_nonhyper), 44L)
  # the frozen strict rule: every hyper total strictly above the cutoff,
  # every bulk total at or below it
  cut <- as.numeric(scal$cutoff)
  expect_true(all(part$total[hits == part$sample] > cut))
  expect_true(all(part$total[!(part$sample %in% hits)] <= cut))
})

test_that("the public face and the protocol twin re-derive the witnesses", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  plant <- .sx_tsv("stratify_plant_totals.tsv")
  totals <- setNames(as.numeric(plant$total), plant$sample)
  scal <- .sx_csv("stratify_scalars.csv")
  part <- .sx_csv("stratify_partition.csv")
  st <- ms_stratify_hypermutants(totals, seed = 1)
  expect_identical(st@cutoff, as.numeric(scal$cutoff))
  expect_identical(st@hyper, .sx_hyper_planted)
  expect_identical(st@nonhyper, .sx_samples[-(45:50)])
  expect_identical(as.integer(st@n_hyper), 6L)
  expect_identical(as.integer(st@n_nonhyper), 44L)
  expect_identical(st@policy, "exclude_de_novo_then_refit")
  expect_identical(names(st@gmm),
                   c("retained_mean", "retained_sd", "retained_n",
                     "n_fits", "converged"))
  expect_true(isTRUE(st@gmm$converged))
  # exact on the integer-verdict columns, toleranced on the libm-drift pair
  expect_equal(st@gmm$retained_n, as.numeric(scal$retained_n))
  expect_equal(st@gmm$n_fits, as.numeric(scal$n_fits))
  expect_equal(st@gmm$retained_mean, as.numeric(scal$retained_mean),
               tolerance = 1e-9)
  expect_equal(st@gmm$retained_sd, as.numeric(scal$retained_sd),
               tolerance = 1e-9)
  twin <- msuiter:::msuiter_stratify_twin(as.numeric(totals), 0, 1)
  expect_identical(twin$cutoff, as.numeric(scal$cutoff))
  expect_identical(twin$hypermutant_idx,
                   which(as.integer(part$is_hyper) == 1L) - 1L)
  expect_identical(twin$n_hypermutants, 6)
  expect_equal(twin$cluster_stats$retained_mean,
               as.numeric(scal$retained_mean), tolerance = 1e-9)
  expect_equal(twin$cluster_stats$retained_sd,
               as.numeric(scal$retained_sd), tolerance = 1e-9)
})

test_that("the verdict is seed-invariant across the certified seed range", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  plant <- .sx_tsv("stratify_plant_totals.tsv")
  totals <- setNames(as.numeric(plant$total), plant$sample)
  scal <- .sx_csv("stratify_scalars.csv")
  base <- ms_stratify_hypermutants(totals, seed = 1)
  for (s in 2:8) {
    st <- ms_stratify_hypermutants(totals, seed = s)
    expect_identical(st@cutoff, base@cutoff, info = paste0("seed ", s))
    expect_identical(st@hyper, base@hyper, info = paste0("seed ", s))
    expect_identical(st@nonhyper, base@nonhyper, info = paste0("seed ", s))
  }
  expect_identical(base@hyper, .sx_hyper_planted)
  expect_identical(base@cutoff, as.numeric(scal$cutoff))
})

test_that("the manual floor re-adjudicates and the boundary is strict", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  floored <- ms_stratify_hypermutants(
    setNames(.sx_fb_totals, .sx_fb_samples), manual_cutoff = .sx_fb_manual,
    seed = 1)
  expect_identical(floored@cutoff, as.numeric(.sx_fb_manual))
  # boundary twins: total == floor is nonhyper, total == floor+1 is hyper
  expect_identical(floored@hyper, "FB06")
  expect_true("FB05" %in% floored@nonhyper)
  inert <- ms_stratify_hypermutants(
    setNames(.sx_fb_totals, .sx_fb_samples), manual_cutoff = 0, seed = 1)
  # with an inert floor the derived rule separates the true outliers
  expect_true(inert@cutoff < .sx_fb_manual)
  expect_setequal(inert@hyper, c("FB05", "FB06"))
  if (!is.na(.ms_root)) {
    fl <- .sx_csv("stratify_floor.csv")
    expect_setequal(unique(fl$regime), c("floored", "inert"))
    expect_identical(as.integer(fl$is_hyper[fl$regime == "floored"]),
                     as.integer(floored@hyper == fl$sample[fl$regime == "floored"]))
    expect_identical(as.integer(fl$is_hyper[fl$regime == "inert"]),
                     as.integer(inert@hyper == fl$sample[fl$regime == "inert"]))
  }
})

test_that("the catalog path and the totals path deliver one verdict", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  plant <- .sx_tsv("stratify_plant_totals.tsv")
  totals <- as.integer(plant$total)
  lab <- as.character(msuiter:::.ms_io_channel_tables()$SBS96)
  # integer-valued, non-negative, column sums hit the witnessed totals exactly
  mat <- matrix(1L, nrow = 96L, ncol = 50L,
                dimnames = list(lab, plant$sample))
  mat[1L, ] <- totals - 95L
  cat1 <- ms_catalog(mat, list(name = "SBS96", labels = lab), plant$sample,
                     provenance = list(genome = "GRCh37"))
  st <- ms_stratify_hypermutants(cat1, seed = 1)
  scal <- .sx_csv("stratify_scalars.csv")
  expect_identical(st@cutoff, as.numeric(scal$cutoff))
  expect_identical(st@hyper, .sx_hyper_planted)
  expect_identical(as.integer(st@n_hyper), 6L)
})

test_that("the burden plot pins the stored cutoff and partition", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  if (!requireNamespace("ggplot2", quietly = TRUE)) skip("ggplot2 unavailable")
  plant <- .sx_tsv("stratify_plant_totals.tsv")
  totals <- setNames(as.numeric(plant$total), plant$sample)
  st <- ms_stratify_hypermutants(totals, seed = 1)
  p <- plot_hypermutator_burden(st)
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomVline"), logical(1L))))
  vline <- unlist(lapply(p$layers, function(l) {
    if (inherits(l$geom, "GeomVline")) l$data$xintercept else numeric(0)
  }), use.names = FALSE)
  expect_equal(vline, st@cutoff)
  hist <- Filter(function(l) inherits(l$geom, "GeomBar"), p$layers)[[1L]]
  d1 <- hist$data
  hyper <- as.character(d1$fill) == "TRUE"
  expect_setequal(as.character(d1$sample[hyper]), st@hyper)
  expect_equal(d1$total[hyper], unname(st@totals[st@hyper]))
})

test_that("the certified silence and degenerate branches speak", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  # unimodal cohort: zero hypermutants (the certified silence branch)
  uni <- setNames(as.numeric(12000L + 130L * (0:19)),
                   paste0("SU", formatC(1:20, width = 2L, flag = "0")))
  st0 <- ms_stratify_hypermutants(uni, seed = 1)
  expect_identical(as.integer(st0@n_hyper), 0L)
  expect_identical(st0@hyper, character(0))
  expect_identical(as.integer(st0@n_nonhyper), 20L)
  # all-identical cohort: the certified degenerate branch, cutoff == value,
  # strict > keeps every sample nonhyper
  dg <- setNames(rep(777, 6), paste0("SD", 1:6))
  st1 <- ms_stratify_hypermutants(dg, seed = 1)
  expect_identical(st1@cutoff, 777)
  expect_identical(as.integer(st1@n_hyper), 0L)
  if (!is.na(.ms_root)) {
    dw <- .sx_csv("stratify_degenerate.csv")
    expect_identical(as.numeric(dw$cutoff[1L]), 777)
    expect_identical(as.integer(dw$n_hyper[1L]), 0L)
  }
})

test_that("the certified constants are re-pinned, not re-implied", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  expect_identical(msuiter:::msuiter_gmm_var_reg, 1e-6)
  expect_identical(msuiter:::msuiter_gmm_tol, 1e-8)
  expect_identical(msuiter:::msuiter_gmm_max_iter, 200L)
  plant <- .sx_tsv("stratify_plant_totals.tsv")
  totals <- setNames(as.numeric(plant$total), plant$sample)
  st <- ms_stratify_hypermutants(totals, seed = 1)
  expect_identical(st@policy, "exclude_de_novo_then_refit")
  expect_identical(as.integer(st@seed), 1L)
})
