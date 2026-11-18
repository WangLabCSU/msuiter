# test-scenario-downsample.R -- the CS-6 downsample-frontier law units
# (pillar 3). The scenario plants a seeded SBS96 cohort through the
# package's own generator (ms_simulate), thins it across a frozen depth
# ladder with ms_downsample, and adjudicates the pooled presence face
# (ms_test_presence, LRT + BH over the planted dictionary) against the
# committed witness bytes under bench/scenarios/out/. The witness bytes
# are the committed verdict: a drift between generator, thinner, kernel,
# or evidence reddens here before print.
# Framing law: DECISION RECORD only. The frontier shape (where the
# borderline signature's pooled verdict flips) is an OBSERVED, COMMITTED
# fact -- never a generalization claim about downsample behavior at large.
# The hard rails are the two planted-extremes adjudications (recall-1 on
# the strong signatures, census-0 on the planted-zero signature), the
# monotone law on the borderline bit, and the byte laws of the thinning
# itself (verbatim-keep, total-clamp, dead-stays-dead, seed reproducible).
# No sanity harness (R/calibrate-real.R untouched), no bootstrap, no
# intervals, no conformal -- the declined rails are spoken by the runner
# itself ([attest] rails) and grepped here.

.ds_out <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.ds_csv <- function(fname) {
  read.csv(.ds_out(fname), header = TRUE, stringsAsFactors = FALSE)
}

.ds_tsv <- function(fname) {
  read.csv(.ds_out(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE)
}

# Frozen scenario constants -- mirrored byte-identically in
# bench/scenarios/run_downsample.R (single source of truth is the pair of
# files; a drift reddens the constants unit below).
.DS_SIG <- c("SBS1", "SBS2", "SBS5", "SBS18")   # dictionary roster (SBS18 planted-zero control)
.DS_STRONG <- c("SBS1", "SBS5")
.DS_BORD <- "SBS2"
.DS_T_STRONG <- c(3000, 3200, 2800, 3400, 3000, 2600)   # S01..S06 totals
.DS_T_BORD <- c(900, 1100)                                # S07..S08 (SBS2 borderline)
.DS_T_SUB <- c(300, 500)                                  # S09..S10 (SBS2 sub-threshold)
.DS_SAMPLES <- paste0("S", formatC(1:10, width = 2L, flag = "0"))
.DS_DEPTHS <- c(400, 800, 1200, 1600, 2400, 3200)
.DS_PLANT_SEED <- 7L
.DS_LADDER_SEED <- 3L
.DS_SEED_RUNG <- 1200
.DS_SEEDS <- 1:8
.DS_BOUND_TOT <- c(1000, 1001, 999, 0, 1000)
.DS_BOUND_DEPTH <- 1000
.DS_BOUND_SEED <- 11L
.DS_BOUND_SAMPLES <- paste0("B", formatC(1:5, width = 2L, flag = "0"))
.DS_BH_ALPHA <- 0.05

# The dictionary, re-derived from the bundled reference (bundled bytes only,
# never downloaded); columns normalized to sum 1, in the canonical channel
# order the generator's registry check requires.
.ds_dict <- function() {
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  dict <- mat[, .DS_SIG, drop = FALSE]
  sweep(dict, 2L, colSums(dict), "/")
}

# The fixed count-scale exposure plan (rows follow .DS_SIG order). Share
# columns would be scaled by `burden`; count columns carry their own totals
# -- the generator's documented contract, pinned here.
.ds_exposures <- function() {
  E <- matrix(0, nrow = length(.DS_SIG), ncol = 10L,
              dimnames = list(.DS_SIG, .DS_SAMPLES))
  sbs1 <- round(.DS_T_STRONG * 0.8)
  E["SBS1", seq_len(6L)] <- as.numeric(sbs1)
  E["SBS5", seq_len(6L)] <- .DS_T_STRONG - sbs1
  E["SBS2", 7:8] <- .DS_T_BORD
  E["SBS2", 9:10] <- .DS_T_SUB
  E
}

# The planted cohort: re-runs the generator at the frozen seed. Totals are
# deterministic under the multinomial arm (size = round(sum(mu))).
.ds_plant <- function() {
  ms_simulate(signatures = .ds_dict(), exposures = .ds_exposures(),
              seed = .DS_PLANT_SEED)
}

# Hand-built direct-counts cohort for the byte-law legs: column j has the
# 96 channels of the canonical SBS96 table as (t-94, 1 x 94, 0), so the
# column total is exactly t (t = 0 gives a dead column).
.ds_hand <- function(totals, samples) {
  registry <- get("channel_tables", envir = asNamespace("msuiter"))
  labels <- as.character(registry[["SBS96"]]$labels)
  counts <- matrix(0, nrow = 96L, ncol = length(totals),
                   dimnames = list(labels, samples))
  for (j in seq_along(totals)) {
    if (totals[j] > 0) {
      counts[1L, j] <- totals[j] - 94L
      counts[2:95, j] <- 1
    }
  }
  ms_catalog(counts = counts,
             channels = list(name = "SBS96", labels = labels),
             samples = samples, provenance = list(genome = "hand"))
}

test_that("the CS-6 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  f <- file.path(.ms_root, "bench", "scenarios", "run_downsample.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_downsample", src, fixed = TRUE))
  expect_true(grepl("ms_test_presence", src, fixed = TRUE))
  expect_true(grepl("ms_simulate", src, fixed = TRUE))
  # Declined rails made audible in the runner itself.
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  expect_true(grepl("conformal", src, fixed = TRUE))
  expect_true(grepl("calibrate-real", src, fixed = TRUE))
})

test_that("the committed plant is the seeded generator at the frozen seed", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  plant <- .ds_csv("cs6_plant.csv")
  expect_identical(names(plant)[1L], "channel")
  expect_identical(names(plant)[-1L], .DS_SAMPLES)
  cat <- .ds_plant()
  expect_identical(plant$channel, as.character(rownames(cat@counts)))
  for (s in .DS_SAMPLES) {
    expect_identical(as.integer(plant[[s]]), as.integer(cat@counts[, s]))
  }
  expect_identical(as.integer(unname(colSums(cat@counts))),
                   as.integer(c(.DS_T_STRONG, .DS_T_BORD, .DS_T_SUB)))
})

test_that("the ladder witnesses dual-derive bit-exactly through the faces", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  lad <- .ds_csv("cs6_ladder.csv")
  expect_identical(names(lad), c("depth", "signature", "stat", "p_bh", "pass_bh"))
  expect_identical(nrow(lad), length(.DS_DEPTHS) * length(.DS_SIG))
  cat <- .ds_plant()
  for (d in .DS_DEPTHS) {
    rows <- lad[lad$depth == d, , drop = FALSE]
    expect_identical(rows$signature, .DS_SIG)
    ds <- ms_downsample(cat, depth = d, seed = .DS_LADDER_SEED)
    pres <- ms_test_presence(ds, signatures = .ds_dict())
    expect_identical(as.integer(pres$pass_bh), as.integer(rows$pass_bh))
    expect_equal(as.numeric(pres$stat), as.numeric(rows$stat), tolerance = 1e-9)
    expect_equal(as.numeric(pres$p_bh), as.numeric(rows$p_bh), tolerance = 1e-9)
  }
})

test_that("the planted extremes adjudicate: recall-1 and census-0", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  lad <- .ds_csv("cs6_ladder.csv")
  for (s in .DS_STRONG) {
    bits <- as.integer(lad$pass_bh[lad$signature == s])
    expect_identical(bits, rep(1L, length(.DS_DEPTHS)),
                     info = paste0("strong-signature recall at 1: ", s))
  }
  ctrl <- lad[lad$signature == "SBS18", , drop = FALSE]
  expect_identical(as.integer(ctrl$pass_bh), rep(0L, length(.DS_DEPTHS)))
  expect_true(all(as.numeric(ctrl$p_bh) > .DS_BH_ALPHA))
})

test_that("the borderline bit is monotone and its flip depth is committed", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  lad <- .ds_csv("cs6_ladder.csv")
  bits <- as.integer(lad$pass_bh[lad$signature == .DS_BORD])
  expect_true(all(diff(bits) >= 0))                      # non-decreasing in depth
  last_pass <- if (any(bits == 1L)) max(.DS_DEPTHS[bits == 1L]) else NA_real_()
  scal <- .ds_csv("cs6_scalars.csv")
  expect_identical(nrow(scal), 1L)
  committed <- scal$sbs2_last_pass_depth
  if (is.na(last_pass)) {
    expect_true(is.na(as.numeric(committed)))
  } else {
    expect_identical(as.numeric(committed), as.numeric(last_pass))
  }
  # dual-derivation: the fresh face reproduces the witnessed bit pattern
  cat <- .ds_plant()
  fresh <- vapply(.DS_DEPTHS, function(d) {
    pres <- ms_test_presence(ms_downsample(cat, depth = d, seed = .DS_LADDER_SEED),
                             signatures = .ds_dict())
    as.integer(pres$pass_bh[pres$signature == .DS_BORD])
  }, integer(1))
  expect_identical(fresh, bits)
})

test_that("the boundary cohort speaks the thinning byte laws", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  bou <- .ds_csv("cs6_boundary.csv")
  expect_identical(names(bou),
                   c("sample", "total", "is_verbatim", "is_dead", "post_total"))
  expect_identical(bou$sample, .DS_BOUND_SAMPLES)
  expect_identical(as.integer(bou$total), as.integer(.DS_BOUND_TOT))
  expect_identical(as.integer(bou$is_verbatim),
                   as.integer(.DS_BOUND_TOT > 0 & .DS_BOUND_TOT <= .DS_BOUND_DEPTH))
  expect_identical(as.integer(bou$is_dead), as.integer(.DS_BOUND_TOT == 0))
  expect_identical(as.integer(bou$post_total),
                   as.integer(pmin(.DS_BOUND_TOT, .DS_BOUND_DEPTH)))
  # re-derive through the face: verbatim columns byte-identical, thinned
  # column clamped to exactly the depth, dead column untouched
  hand <- .ds_hand(.DS_BOUND_TOT, .DS_BOUND_SAMPLES)
  ds <- ms_downsample(hand, depth = .DS_BOUND_DEPTH, seed = .DS_BOUND_SEED)
  for (j in seq_along(.DS_BOUND_TOT)) {
    t <- .DS_BOUND_TOT[j]
    if (t > 0 && t <= .DS_BOUND_DEPTH) {
      expect_identical(as.integer(ds@counts[, j]), as.integer(hand@counts[, j]))
    } else if (t > .DS_BOUND_DEPTH) {
      expect_identical(sum(ds@counts[, j]), as.numeric(.DS_BOUND_DEPTH))
    } else {
      expect_true(all(ds@counts[, j] == 0))
    }
  }
  prov <- ds@provenance$downsample
  expect_identical(as.numeric(prov$depth), as.numeric(.DS_BOUND_DEPTH))
  expect_identical(as.numeric(prov$seed), as.numeric(.DS_BOUND_SEED))
  expect_identical(as.integer(prov$n_kept_verbatim), 3L)
  expect_identical(as.integer(prov$n_downsampled), 1L)
})

test_that("the seed leg: laws are seed-free, bytes are not", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  cat <- .ds_plant()
  clamped <- as.integer(pmin(c(.DS_T_STRONG, .DS_T_BORD, .DS_T_SUB), .DS_SEED_RUNG))
  for (s in .DS_SEEDS) {
    ds <- ms_downsample(cat, depth = .DS_SEED_RUNG, seed = s)
    expect_identical(as.integer(unname(colSums(ds@counts))), clamped)
    # the verbatim column (t = 900 <= 1200) is byte-stable across seeds
    expect_identical(as.integer(ds@counts[, 7L]),
                     as.integer(cat@counts[, 7L]))
  }
  a <- ms_downsample(cat, depth = .DS_SEED_RUNG, seed = 1)
  b <- ms_downsample(cat, depth = .DS_SEED_RUNG, seed = 1)
  expect_identical(a@counts, b@counts)                        # same seed, same bytes
  c2 <- ms_downsample(cat, depth = .DS_SEED_RUNG, seed = 2)
  expect_false(identical(a@counts[, 1L], c2@counts[, 1L]))    # thinned column differs
})

test_that("min-depth, all-dead abort, and certified silence", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  hand <- .ds_hand(.DS_BOUND_TOT, .DS_BOUND_SAMPLES)
  ds <- ms_downsample(hand, depth = "min", seed = .DS_BOUND_SEED)
  prov <- ds@provenance$downsample
  expect_identical(as.numeric(prov$depth), as.numeric(min(.DS_BOUND_TOT[-4L])))
  expect_identical(as.integer(prov$n_downsampled), 3L)
  expect_identical(as.integer(prov$n_kept_verbatim), 1L)
  dead <- .ds_hand(c(0, 0), c("D1", "D2"))
  err <- tryCatch(ms_downsample(dead, depth = "min", seed = 1L),
                  error = function(e) e)
  expect_true(inherits(err, "error"))
  expect_true(grepl("at least one live sample",
                     paste(conditionMessage(err), collapse = " "), fixed = TRUE))
  expect_silent(ms_test_presence(
    ms_downsample(.ds_plant(), depth = .DS_SEED_RUNG, seed = .DS_LADDER_SEED),
    signatures = .ds_dict()))
})

test_that("the degenerate witness carries the side facts", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  deg <- .ds_tsv("cs6_degenerates.tsv")
  expect_identical(names(deg), c("check", "value"))
  vals <- setNames(deg$value, deg$check)
  expect_identical(as.integer(vals[["min_depth"]]), 999L)
  expect_identical(as.integer(vals[["min_n_downsampled"]]), 3L)
  expect_identical(as.integer(vals[["min_n_kept_verbatim"]]), 1L)
  expect_identical(as.integer(vals[["alldead_abort_right_reason"]]), 1L)
  expect_identical(as.integer(vals[["same_seed_reproducible"]]), 1L)
  expect_identical(as.integer(vals[["cross_seed_thinning_differs"]]), 1L)
  expect_identical(as.integer(vals[["certified_silence"]]), 1L)
})

test_that("the scalars witness pins the frozen scenario constants", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  scal <- .ds_csv("cs6_scalars.csv")
  expect_identical(scal$depths, paste0(.DS_DEPTHS, collapse = ","))
  expect_identical(as.integer(scal$plant_seed), as.integer(.DS_PLANT_SEED))
  expect_identical(as.integer(scal$ladder_seed), as.integer(.DS_LADDER_SEED))
  expect_identical(as.integer(scal$bound_depth), as.integer(.DS_BOUND_DEPTH))
  expect_identical(as.integer(scal$bound_seed), as.integer(.DS_BOUND_SEED))
  expect_identical(scal$dict_roster, paste(.DS_SIG, collapse = ","))
  expect_identical(as.numeric(scal$bh_alpha), .DS_BH_ALPHA)
  expect_identical(as.integer(scal$nb_size), 8L)
  expect_identical(as.integer(scal$plant_min_total),
                   as.integer(min(c(.DS_T_STRONG, .DS_T_BORD, .DS_T_SUB))))
  expect_identical(as.numeric(msuiter:::.MS_PRESENCE_BH_ALPHA), .DS_BH_ALPHA)
})
