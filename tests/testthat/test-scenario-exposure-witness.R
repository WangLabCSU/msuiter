# test-scenario-exposure-witness.R -- the CS-10 exposure-witness law units
# (pillar 3). The scenario plants six pure-arithmetic signature legs over
# 24 samples in two 12-sample groups and adjudicates the EXPORTED face
# ms_exposure_test() under six arms: designed differentials, a same-
# distribution decoy (escapes the NA face, stays negative), the tied/NA
# face (no fabricated p), a borderline leg frozen at DB = 0.18, the BH
# ladder over two family rosters x three alphas, and the input-law set.
# The witness bytes under bench/scenarios/out/ (cs10_arms.csv,
# cs10_ladder.csv, cs10_scalars.csv, cs10_degenerates.tsv) are the
# committed verdict: a drift in the BH family semantics, the NA-face law,
# the alpha gate, or the two-group law reddens here before print.
# The plant is pure arithmetic -- no RNG, no network, no seed to pin.
# Framing law: DECISION RECORD only. What the face says on planted truth
# -- the pass bits, the flip vectors, the NA censuses, the measured
# borderline rung -- is an OBSERVED, COMMITTED record, never a calibration
# or a coverage claim. Float posture (cross-platform law): integer and
# label verdicts are byte-exact; float columns are re-derived LIVE through
# the same face at a 1e-8 tolerance and get finite/in-domain payload
# censuses -- the witness is the same-run record, never a cross-platform
# seal. The pillar-2 idiom of reaching the package namespace directly
# (msuiter:::) is BANNED here and grepped away.

.rs_out10 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.rs_csv10 <- function(fname) {
  read.csv(.rs_out10(fname), header = TRUE, stringsAsFactors = FALSE,
           na.strings = "")
}

.rs_tsv10 <- function(fname) {
  read.csv(.rs_out10(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE,
           na.strings = "")
}

# Witness columns arrive as strings (na.strings = "" keeps the committed
# "NA" token); the reserved token is mapped back to a real NA BEFORE the
# numeric coercion so the read never warns -- output pristineness law.
.as_num10 <- function(x) {
  x <- as.character(x)
  x[x == "NA"] <- NA_character_
  as.numeric(x)
}

# Frozen scenario constants -- mirrored byte-identically in
# bench/scenarios/run_exposure_witness.R (single source of truth).
.CS10_ROSTER <- c("9.4", "2.6", "9.1", "2.2", "9.8", "2.9")
.CS10_R5 <- setdiff(.CS10_ROSTER, "2.9")
.CS10_N <- 12L
.CS10_DB <- 0.18
.CS10_ALPHAS <- c("0.001", "0.05", "0.2")
# MEASURED pass bits (probe v3 through the real exported face, in
# roster order; the tied leg's NA reads as 0 here, censused separately).
.CS10_PASS6 <- c(1L, 1L, 0L, 0L, 0L, 1L)
.CS10_STAT6 <- c(10, 126, 72, NA, 45, 21)
# MEASURED ladder flip vectors (committed decision record).
.CS10_FLIPS <- list(
  R6 = list("0.001" = character(0), "0.05" = c("9.4", "2.6", "2.9"),
            "0.2" = c("9.4", "2.6", "9.8", "2.9")),
  R5 = list("0.001" = character(0), "0.05" = c("9.4", "2.6"),
            "0.2" = c("9.4", "2.6", "9.8")))

# Plant re-derivation (pure arithmetic; the runner mirrors it verbatim).
.cs10_v8 <- function() (seq_len(.CS10_N) - 1L) / .CS10_N
.cs10_legs <- function() {
  v8 <- .cs10_v8()
  list("9.4" = c(v8, v8 + 0.62), "2.6" = c(v8 + 0.50, v8),
       "9.1" = c(v8, rev(v8)), "2.2" = c(v8, v8),
       "9.8" = c(v8, v8 + .CS10_DB), "2.9" = c(v8, v8 + 0.45))
}
.cs10_mat <- function(names) {
  legs <- .cs10_legs()
  m <- do.call(rbind, lapply(names, function(k) legs[[k]]))
  dimnames(m) <- list(names, NULL)
  m
}
.cs10_groups <- function() c(rep_len("A", .CS10_N), rep_len("B", .CS10_N))
.cs10_run <- function(m, alpha = 0.05) ms_exposure_test(m, .cs10_groups(), alpha = alpha)

# The measured input-law clauses (verbatim key clauses of the aborts).
.CS10_LAWS <- list(
  three_groups = c("exactly two groups are required",
                   "pairwise splits of multi-group designs are the caller's decision"),
  alpha_zero = "alpha must be a single number in (0, 1)",
  alpha_one = "alpha must be a single number in (0, 1)",
  alpha_two = "alpha must be a single number in (0, 1)",
  groups_len = "groups must have one label per exposure column",
  matrix_chr = "exposures must be a numeric k x n matrix (or an MsSignature)",
  groups_list = "groups must be a character vector or factor over the samples")

test_that("the CS-10 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "bench", "scenarios", "run_exposure_witness.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_exposure_test", src, fixed = TRUE))
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  # Hand-engine ban: the BH/Wilcoxon verdicts come from the FACE only.
  expect_false(grepl("wilcox.test", src, fixed = TRUE))
  expect_false(grepl("p.adjust", src, fixed = TRUE))
  # No JSON face here -- the runner must not lean on a JSON dependency.
  expect_false(grepl("jsonlite", src, fixed = TRUE))
  # The network and the seed are spoken for by absence.
  expect_false(grepl("download.file", src, fixed = TRUE))
  expect_false(grepl("url(", src, fixed = TRUE))
  expect_false(grepl("set.seed", src, fixed = TRUE))
  expect_false(grepl("Sys.time", src, fixed = TRUE))
  # Rail spoken by absence: the pillar-2 namespace-reach idiom is banned.
  expect_false(grepl("msuiter:::", src, fixed = TRUE))
})

test_that("the plant re-derives deterministically from frozen arithmetic", {
  v8 <- .cs10_v8()
  expect_equal(v8, (seq_len(.CS10_N) - 1L) / .CS10_N, tolerance = 0)
  expect_equal(length(v8), 12L)
  legs <- .cs10_legs()
  expect_equal(names(legs), .CS10_ROSTER)
  expect_true(all(vapply(legs, function(l) length(l) == 24L, logical(1L))))
  expect_equal(legs[["9.4"]], c(v8, v8 + 0.62), tolerance = 0)
  expect_equal(legs[["2.6"]], c(v8 + 0.50, v8), tolerance = 0)
  expect_equal(legs[["9.1"]], c(v8, rev(v8)), tolerance = 0)
  expect_equal(legs[["2.2"]], c(v8, v8), tolerance = 0)
  expect_equal(legs[["9.8"]], c(v8, v8 + .CS10_DB), tolerance = 0)
  expect_equal(legs[["2.9"]], c(v8, v8 + 0.45), tolerance = 0)
  g <- .cs10_groups()
  expect_equal(length(g), 24L)
  expect_equal(sort(unique(g)), c("A", "B"))
  expect_equal(sum(g == "A"), 12L)
  expect_equal(sum(g == "B"), 12L)
  m <- .cs10_mat(.CS10_ROSTER)
  expect_equal(dim(m), c(6L, 24L))
  expect_equal(rownames(m), .CS10_ROSTER)
})

test_that("the four committed witnesses exist with live rows", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs10_arms.csv", "cs10_ladder.csv", "cs10_scalars.csv",
              "cs10_degenerates.tsv")) {
    expect_true(file.exists(.rs_out10(f)), label = paste0("witness exists: ", f))
    expect_gt(file.info(.rs_out10(f))$size, 0L, label = paste0("witness non-empty: ", f))
  }
  a <- .rs_csv10("cs10_arms.csv")
  expect_equal(nrow(a), 6L)
  l <- .rs_csv10("cs10_ladder.csv")
  expect_equal(nrow(l), 33L)  # (6+5) legs x 3 alphas, flattened rungs
  s <- .rs_csv10("cs10_scalars.csv")
  expect_true(all(c("key", "value") %in% names(s)))
  d <- .rs_tsv10("cs10_degenerates.tsv")
  expect_true(all(c("name", "value") %in% names(d)))
})

test_that("the arms witness byte-matches the integer verdicts and the NA census", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  a <- .rs_csv10("cs10_arms.csv")
  expect_equal(as.character(a$signature), .CS10_ROSTER)
  expect_equal(as.integer(a$pass_bh), .CS10_PASS6)
  expect_equal(.as_num10(a$statistic), .CS10_STAT6, tolerance = 0)
  expect_equal(sum(is.na(.as_num10(a$p_raw))), 1L)
  expect_equal(sum(is.na(.as_num10(a$p_bh))), 1L)
  expect_equal(sum(is.na(as.integer(a$pass_bh))), 0L)
  # Float payload census: in-domain or NA, never dead columns.
  pr <- .as_num10(a$p_raw)
  pb <- .as_num10(a$p_bh)
  expect_true(all(is.na(pr) | (pr >= 0 & pr <= 1)))
  expect_true(all(is.na(pb) | (pb >= 0 & pb <= 1)))
  expect_true(all(is.finite(.as_num10(a$median_group1))))
  expect_true(all(is.finite(.as_num10(a$median_group2))))
})

test_that("the arms witness float columns re-derive live through the face", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  a <- .rs_csv10("cs10_arms.csv")
  live <- .cs10_run(.cs10_mat(.CS10_ROSTER), 0.05)
  expect_equal(as.character(live$signature), as.character(a$signature))
  for (i in seq_len(6L)) {
    if (is.na(live$p_raw[i])) {
      expect_true(is.na(.as_num10(a$p_raw[i])), label = paste0("NA face holds: ", a$signature[i]))
    } else {
      expect_equal(.as_num10(a$p_raw[i]), live$p_raw[i], tolerance = 1e-8,
        label = paste0("p_raw re-derives: ", a$signature[i]))
      expect_equal(.as_num10(a$p_bh[i]), live$p_bh[i], tolerance = 1e-8,
        label = paste0("p_bh re-derives: ", a$signature[i]))
    }
    expect_equal(.as_num10(a$median_group1[i]), live$median_group1[i], tolerance = 1e-8)
    expect_equal(.as_num10(a$median_group2[i]), live$median_group2[i], tolerance = 1e-8)
  }
})

test_that("the designed, decoy and tied arms speak the committed semantics", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  a <- .rs_csv10("cs10_arms.csv")
  row <- function(sig) a[a$signature == sig, , drop = FALSE]
  # Designed differentials pass at the frozen alpha.
  expect_equal(as.integer(row("9.4")$pass_bh), 1L)
  expect_equal(as.integer(row("2.6")$pass_bh), 1L)
  expect_equal(as.integer(row("2.9")$pass_bh), 1L)
  # The decoy shares its distribution, escapes the NA face (finite
  # statistic), reads p = 1, and stays negative.
  expect_equal(.as_num10(row("9.1")$p_raw), 1, tolerance = 1e-8)
  expect_equal(.as_num10(row("9.1")$p_bh), 1, tolerance = 1e-8)
  expect_true(is.finite(.as_num10(row("9.1")$statistic)))
  expect_equal(as.integer(row("9.1")$pass_bh), 0L)
  # The tied leg is the NA face: no fabricated p, medians still spoken.
  expect_true(is.na(.as_num10(row("2.2")$statistic)))
  expect_true(is.na(.as_num10(row("2.2")$p_raw)))
  expect_true(is.na(.as_num10(row("2.2")$p_bh)))
  expect_equal(as.integer(row("2.2")$pass_bh), 0L)
  expect_equal(.as_num10(row("2.2")$median_group1),
                .as_num10(row("2.2")$median_group2), tolerance = 1e-8)
  # The borderline leg fails at the frozen alpha.
  expect_equal(as.integer(row("9.8")$pass_bh), 0L)
})

test_that("the ladder witness commits the flip vectors across both rosters", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  l <- .rs_csv10("cs10_ladder.csv")
  for (rn in c("R6", "R5")) {
    for (al in .CS10_ALPHAS) {
      rung <- l[l$roster == rn & l$alpha == al, , drop = FALSE]
      expect_equal(nrow(rung), length(.CS10_ROSTER) - (rn == "R5"),
        label = paste0("rung rows: ", rn, " @", al))
      passed <- as.character(rung$signature[as.integer(rung$pass) == 1L])
      expect_equal(passed, .CS10_FLIPS[[rn]][[al]],
        label = paste0("flip vector: ", rn, " @", al))
    }
  }
  # The designed legs never flip across the meaningful alpha range; the
  # borderline leg is the committed alpha-bracketing witness.
  r05 <- l[l$roster == "R6" & l$alpha == "0.05", , drop = FALSE]
  r20 <- l[l$roster == "R6" & l$alpha == "0.2", , drop = FALSE]
  expect_equal(as.integer(r05$pass[r05$signature == "9.4"]), 1L)
  expect_equal(as.integer(r05$pass[r05$signature == "2.6"]), 1L)
  expect_equal(as.integer(r20$pass[r20$signature == "9.8"]), 1L)
  expect_equal(as.integer(r05$pass[r05$signature == "9.8"]), 0L)
})

test_that("the ladder witnesses obey the fold-back and no-fabrication laws", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  l <- .rs_csv10("cs10_ladder.csv")
  pb <- .as_num10(l$p_bh)
  pr <- .as_num10(l$p_raw)
  live <- !is.na(pb)
  expect_true(all(pb[live] >= pr[live] - 1e-12))
  expect_true(all(pb <= 1 + 1e-12, na.rm = TRUE))
  # NA never fabricates a pass, at any rung, in either roster.
  expect_equal(sum(as.integer(l$pass) == 1L & is.na(.as_num10(l$p_bh))), 0L)
  # Every rung's NA census: exactly the tied leg goes NA, in both rosters.
  for (rn in c("R6", "R5")) {
    for (al in .CS10_ALPHAS) {
      rung <- l[l$roster == rn & l$alpha == al, , drop = FALSE]
      expect_equal(sum(is.na(.as_num10(rung$p_raw))), 1L,
        label = paste0("rung NA census: ", rn, " @", al))
    }
  }
})

test_that("the input laws abort with the committed classes and clauses", {
  m <- .cs10_mat(.CS10_ROSTER)
  probes <- list(
    three_groups = quote(ms_exposure_test(m, c(rep_len("A", 12L),
                       rep_len("B", 11L), "C"))),
    alpha_zero = quote(ms_exposure_test(m, .cs10_groups(), alpha = 0)),
    alpha_one = quote(ms_exposure_test(m, .cs10_groups(), alpha = 1)),
    alpha_two = quote(ms_exposure_test(m, .cs10_groups(), alpha = 2)),
    groups_len = quote(ms_exposure_test(m, .cs10_groups()[seq_len(23L)])),
    matrix_chr = quote(ms_exposure_test(as.character(m), .cs10_groups())),
    groups_list = quote(ms_exposure_test(m, as.list(.cs10_groups()))))
  expect_equal(names(probes), names(.CS10_LAWS))
  for (nm in names(probes)) {
    e <- tryCatch(eval(probes[[nm]]), error = function(e) e)
    expect_true(inherits(e, "error"), label = paste0("law aborts: ", nm))
    expect_true(inherits(e, "msuiter_error_input"),
      label = paste0("law class: ", nm))
    msg <- paste(conditionMessage(e))
    for (clause in .CS10_LAWS[[nm]]) {
      expect_true(grepl(clause, msg, fixed = TRUE),
        label = paste0(nm, " speaks: ", clause))
    }
  }
})

test_that("the label fallback and the MsSignature equivalence hold", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  # NULL rownames fall back to sig1..sigk (the paste0("sig", seq_len) law).
  m2 <- .cs10_mat(.CS10_ROSTER[1L:2L])
  dimnames(m2) <- NULL
  fb <- ms_exposure_test(m2, .cs10_groups())
  expect_equal(as.character(fb$signature), paste0("sig", seq_len(2L)))
  # Named input speaks its names.
  nm2 <- ms_exposure_test(.cs10_mat(.CS10_ROSTER[1L:2L]), .cs10_groups())
  expect_equal(as.character(nm2$signature), .CS10_ROSTER[1L:2L])
  # The committed degenerates witness pins the fallback and the aborts.
  d <- .rs_tsv10("cs10_degenerates.tsv")
  dv <- setNames(as.character(d$value), as.character(d$name))
  expect_equal(dv[["fallback_sig1"]], "sig1")
  expect_equal(dv[["fallback_sig2"]], "sig2")
  expect_equal(dv[["tied_p_raw"]], "NA")
  expect_equal(dv[["decoy_p_raw"]], "1")
  for (ab in c("alpha_zero_abort", "alpha_one_abort", "alpha_two_abort",
               "three_groups_abort", "groups_len_abort", "matrix_chr_abort",
               "groups_list_abort")) {
    expect_equal(dv[[ab]], "1", label = paste0("abort witnessed: ", ab))
  }
  # MsSignature input is all.equal to the raw-matrix input (the face
  # reads @exposures; construction follows the sanctioned derivation).
  m <- .cs10_mat(.CS10_ROSTER)
  samples <- paste0("s", seq_len(24L))
  chan <- c("cs10chanA", "cs10chanB")
  counts <- matrix(.as_num10(seq_len(48L)), nrow = 2L, ncol = 24L,
    dimnames = list(chan, samples))
  cat1 <- ms_catalog(counts, list(name = "CS10SYN", labels = chan),
    samples, provenance = list(genome = "GRCSYN"))
  msig <- m
  colnames(msig) <- samples
  sigmat <- matrix(.as_num10(seq_len(12L)), nrow = 2L, ncol = 6L,
    dimnames = list(chan, .CS10_ROSTER))
  so <- ms_signature(signatures = sigmat, exposures = msig,
    catalog_summary = msuiter_catalog_summary(cat1),
    engine = "cs10-witness", seed = 0)
  r1 <- .cs10_run(m, 0.05)
  r2 <- ms_exposure_test(so, .cs10_groups(), alpha = 0.05)
  expect_true(isTRUE(all.equal(r2, r1, check.attributes = FALSE)))
})

test_that("the scalars witness pins the frozen scenario constants", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  s <- .rs_csv10("cs10_scalars.csv")
  sv <- setNames(as.character(s$value), as.character(s$key))
  expect_equal(sv[["scenario_shape"]], "cs10-exposure-witness")
  expect_equal(sv[["face"]], "ms_exposure_test")
  expect_equal(sv[["k"]], "6")
  expect_equal(sv[["n_samples"]], "24")
  expect_equal(sv[["alpha_frozen"]], "0.05")
  expect_equal(sv[["db_frozen"]], format(.CS10_DB))
  expect_equal(sv[["roster6"]], paste0(.CS10_ROSTER, collapse = ","))
  expect_equal(sv[["roster5"]], paste0(.CS10_R5, collapse = ","))
  expect_equal(sv[["input_law_count"]], "7")
})
