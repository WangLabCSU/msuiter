# test-scenario-calibration-verdict.R -- the CS-11 calibration-verdict-witness
# law units (pillar 3). The scenario plants pure-rational mean_coverage
# tables and adjudicates the EXPORTED face ms_calibration_verdict() under
# six arms: an all-in lattice, the both-ends-inclusive boundary at the
# frozen window c(lo = 0.930, hi = 0.970), a low+high flip-pair with an
# ascending failing-cell census, the three-source precedence ladder
# (explicit arg > recorded attr > frozen default), the degenerate shapes,
# and the input-law set. The witness bytes under bench/scenarios/out/
# (cs11_arms.csv, cs11_lattice.csv, cs11_precedence.csv, cs11_scalars.csv,
# cs11_degenerates.tsv) are the committed verdict: a drift in the
# inclusivity law, the census order, the precedence ladder, or the input
# guards reddens here before print. The plant is rational arithmetic --
# no RNG, no network, no seed to pin; the lane NEVER calls
# ms_calibration_grid() or ms_fit_bootstrap() (declined words, grepped).
# Framing law: DECISION RECORD only. What the face says on planted truth
# -- the lattice bits, the census vectors, the all-in bit, the measured
# precedence flips -- is an OBSERVED, COMMITTED record, never a coverage
# or calibration claim. Verdict columns are integer/label bytes and
# byte-exact; the float side of the witnesses is the committed INPUT
# labels (exact rationals as source text), never an ill-conditioned
# rendering. The pillar-2 idiom of reaching the package namespace
# directly (msuiter:::) is BANNED here and grepped away.

.rs_out11 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.rs_csv11 <- function(fname) {
  read.csv(.rs_out11(fname), header = TRUE, stringsAsFactors = FALSE,
           na.strings = "", colClasses = "character")
}

.rs_tsv11 <- function(fname) {
  read.csv(.rs_out11(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character")
}

# Witness columns arrive as strings (colClasses = "character" keeps the
# exact rational-source bytes -- the trailing zeros of "0.930" are the
# law; na.strings = "" keeps the committed empty token; the reserved token
# is mapped back to a real NA BEFORE the numeric coercion so the read never
# warns -- output pristineness law).
.as_num11 <- function(x) {
  x <- as.character(x)
  x[x == "NA"] <- NA_character_
  as.numeric(x)
}

# The committed failing-census string: "" (read as the reserved token)
# speaks the empty integer vector; otherwise ascending 1-based indices.
.cs11_failing <- function(s) {
  s <- as.character(s)
  if (length(s) != 1L || is.na(s) || !nzchar(s)) return(integer(0))
  as.integer(strsplit(s, ",", fixed = TRUE)[[1L]])
}

# Frozen scenario constants -- mirrored byte-identically in
# bench/scenarios/run_calibration_verdict.R (single source of truth).
# The frozen window literal as spoken by the face (measured echo).
.CS11_WIN_LO <- 0.930
.CS11_WIN_HI <- 0.970

# The six arms, planted coverage vectors as EXACT RATIONAL SOURCE LABELS
# (the witness coverage column carries these strings verbatim -- no float
# rendering ever touches the committed bytes) and their numeric tie.
.CS11_ARMS <- list(
  allin    = list(label = "0.935,0.948,0.961",
                  value = c(0.935, 0.948, 0.961)),
  boundary = list(label = "0.930,0.970,0.929999,0.970001",
                  value = c(0.930, 0.970, 0.929999, 0.970001)),
  flippair = list(label = "0.95,0.9299,0.955,0.9701",
                  value = c(0.950, 0.9299, 0.955, 0.9701)),
  allout   = list(label = "0.80,0.99,0.50",
                  value = c(0.800, 0.990, 0.500)),
  single   = list(label = "0.95",
                  value = 0.950),
  all2x    = list(label = "0.9299,0.9701",
                  value = c(0.9299, 0.9701)))
# The precedence ladder plant (one table; three disagreeing band sources).
.CS11_PREC_BASE <- c(0.955, 0.965)
.CS11_PREC_ATTR <- c(0.900, 0.961)
.CS11_PREC_ARG <- c(0.900, 0.970)

# MEASURED verdicts (probe v1 through the real exported face).
.CS11_LATTICE <- list(allin = c(1L, 1L, 1L), boundary = c(1L, 1L, 0L, 0L),
                      flippair = c(1L, 0L, 1L, 0L), allout = c(0L, 0L, 0L),
                      single = 1L, all2x = c(0L, 0L))
.CS11_FAILING <- list(allin = integer(0), boundary = c(3L, 4L),
                      flippair = c(2L, 4L), allout = c(1L, 2L, 3L),
                      single = integer(0), all2x = c(1L, 2L))

# The committed input-law clauses (verbatim key clauses of the aborts;
# the cli bullet glyph is conditionMessage rendering, not part of them).
.CS11_CLAUSE_FORM <- paste0("calibration must be a data.frame with an ",
                            "NA-free numeric mean_coverage column")
.CS11_CLAUSE_WINDOW <- paste0("window must be c(lo, hi): two finite ",
                              "numbers in [0, 1] with lo <= hi")
.CS11_LAWS <- list(
  na_column = .CS11_CLAUSE_FORM, missing_col = .CS11_CLAUSE_FORM,
  not_df = .CS11_CLAUSE_FORM, zero_rows = .CS11_CLAUSE_FORM,
  win_reversed = .CS11_CLAUSE_WINDOW, win_nonfinite = .CS11_CLAUSE_WINDOW,
  win_len1 = .CS11_CLAUSE_WINDOW, win_char = .CS11_CLAUSE_WINDOW,
  win_eq_ends = character(0))   # observed NO-ABORT: degenerate lo == hi is legal

# Plant helpers (the runner mirrors them verbatim).
.cs11_tbl <- function(v) {
  data.frame(mean_coverage = v, cell = paste0("cell", seq_along(v)),
             stringsAsFactors = FALSE)
}
.cs11_v <- function(v, window = NULL) ms_calibration_verdict(.cs11_tbl(v),
                                                             window = window)

test_that("the CS-11 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "bench", "scenarios", "run_calibration_verdict.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_calibration_verdict", src, fixed = TRUE))
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  expect_true(grepl("cs11_", src, fixed = TRUE))
  # Hand-engine ban: the lattice, census and all-in bits come from the FACE.
  expect_false(grepl("per_cell_in <-", src, fixed = TRUE))
  expect_false(grepl("failing_cells <-", src, fixed = TRUE))
  # The declined calibration-kernel words must never ride the runner.
  expect_false(grepl("ms_calibration_grid", src, fixed = TRUE))
  expect_false(grepl("ms_fit_bootstrap", src, fixed = TRUE))
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

test_that("the plant and the frozen verdicts are self-consistent", {
  expect_equal(names(.CS11_ARMS),
               c("allin", "boundary", "flippair", "allout", "single", "all2x"))
  for (nm in names(.CS11_ARMS)) {
    arm <- .CS11_ARMS[[nm]]
    lab <- as.numeric(strsplit(arm$label, ",", fixed = TRUE)[[1L]])
    # The committed label text and the numeric plant are the SAME rationals.
    expect_equal(lab, arm$value, tolerance = 0,
                 label = paste0("label ties value: ", nm))
    bits <- .CS11_LATTICE[[nm]]
    expect_equal(length(bits), length(arm$value),
                 label = paste0("lattice width: ", nm))
    # The census is exactly the zero-bit positions, ascending.
    expect_equal(.CS11_FAILING[[nm]], which(bits == 0L),
                 label = paste0("census = zero bits: ", nm))
    expect_false(any(diff(.CS11_FAILING[[nm]]) <= 0L),
                 label = paste0("census ascending: ", nm))
    expect_equal(any(bits == 0L), length(.CS11_FAILING[[nm]]) > 0L,
                 label = paste0("all-bit consistency: ", nm))
  }
  expect_equal(.CS11_FAILING$boundary, c(3L, 4L))
  expect_equal(.CS11_FAILING$flippair, c(2L, 4L))
  expect_equal(.CS11_FAILING$allout, c(1L, 2L, 3L))
  expect_equal(length(.CS11_ARMS$single$value), 1L)
  # The precedence plant flips both ways against the committed windows.
  expect_true(all(.CS11_PREC_BASE >= .CS11_WIN_LO & .CS11_PREC_BASE <= .CS11_WIN_HI))
  expect_equal(.CS11_PREC_BASE[2L] > .CS11_PREC_ATTR[2L], TRUE)
  expect_true(all(.CS11_PREC_BASE >= .CS11_PREC_ARG[1L] &
                  .CS11_PREC_BASE <= .CS11_PREC_ARG[2L]))
  # The frozen window is an in-domain closed interval.
  expect_true(is.finite(.CS11_WIN_LO) && is.finite(.CS11_WIN_HI))
  expect_true(.CS11_WIN_LO < .CS11_WIN_HI && .CS11_WIN_LO >= 0 &&
               .CS11_WIN_HI <= 1)
  t <- .cs11_tbl(c(0.95, 0.96))
  expect_equal(as.character(t$cell), c("cell1", "cell2"))
  expect_equal(names(t), c("mean_coverage", "cell"))
})

test_that("the five committed witnesses exist with live rows", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs11_arms.csv", "cs11_lattice.csv", "cs11_precedence.csv",
               "cs11_scalars.csv", "cs11_degenerates.tsv")) {
    expect_true(file.exists(.rs_out11(f)), label = paste0("witness exists: ", f))
    expect_gt(file.info(.rs_out11(f))$size, 0L, label = paste0("witness non-empty: ", f))
  }
  a <- .rs_csv11("cs11_arms.csv")
  expect_equal(nrow(a), 17L)   # 3+4+4+3+1+2 arm rows
  l <- .rs_csv11("cs11_lattice.csv")
  expect_equal(nrow(l), 9L)    # six arms + three precedence sources
  p <- .rs_csv11("cs11_precedence.csv")
  expect_equal(nrow(p), 3L)
  s <- .rs_csv11("cs11_scalars.csv")
  expect_true(all(c("key", "value") %in% names(s)))
  d <- .rs_tsv11("cs11_degenerates.tsv")
  expect_true(all(c("name", "value") %in% names(d)))
})

test_that("the arms witness byte-matches the frozen lattice, census and bits", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  a <- .rs_csv11("cs11_arms.csv")
  for (nm in names(.CS11_ARMS)) {
    rows <- a[a$arm == nm, , drop = FALSE]
    expect_equal(nrow(rows), length(.CS11_ARMS[[nm]]$value),
                 label = paste0("arm rows: ", nm))
    # The coverage column carries the exact rational SOURCE LABELS.
    expect_equal(as.character(rows$coverage),
                 strsplit(.CS11_ARMS[[nm]]$label, ",", fixed = TRUE)[[1L]],
                 label = paste0("arm labels byte-exact: ", nm))
    expect_equal(as.integer(rows$lattice_bit), .CS11_LATTICE[[nm]],
                 label = paste0("arm lattice bytes: ", nm))
    expect_equal(as.integer(rows$failing_bit), as.integer(.CS11_LATTICE[[nm]] == 0L),
                 label = paste0("arm census bits: ", nm))
    expect_equal(as.integer(rows$all_bit),
                 rep_len(as.integer(length(.CS11_FAILING[[nm]]) == 0L), nrow(rows)),
                 label = paste0("arm all-bit: ", nm))
    expect_equal(as.integer(rows$n_failing[1L]), length(.CS11_FAILING[[nm]]),
                 label = paste0("arm census width: ", nm))
    expect_equal(as.character(rows$cell),
                 paste0("cell", seq_along(.CS11_ARMS[[nm]]$value)),
                 label = paste0("arm cell names: ", nm))
  }
})

test_that("the lattice and precedence witnesses re-derive live through the face", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  l <- .rs_csv11("cs11_lattice.csv")
  for (nm in names(.CS11_ARMS)) {
    rung <- l[l$arm == nm, , drop = FALSE]
    expect_equal(nrow(rung), 1L, label = paste0("lattice row: ", nm))
    live <- .cs11_v(.CS11_ARMS[[nm]]$value)
    expect_equal(as.character(rung$lattice),
                 paste0(.CS11_LATTICE[[nm]], collapse = ","),
                 label = paste0("lattice string: ", nm))
    # Live face is IDENTICAL to the committed record (verdicts are integers).
    expect_equal(as.integer(live$per_cell_in), .CS11_LATTICE[[nm]],
                 label = paste0("live lattice: ", nm))
    expect_equal(live$failing_cells, .CS11_FAILING[[nm]],
                 label = paste0("live census: ", nm))
    expect_equal(.cs11_failing(rung$failing), .CS11_FAILING[[nm]],
                 label = paste0("committed census: ", nm))
    expect_equal(as.logical(rung$all), live$all_in_window,
                 label = paste0("live all-bit: ", nm))
    expect_equal(.as_num11(rung$win_lo), .CS11_WIN_LO, tolerance = 0,
                 label = paste0("frozen lo echo: ", nm))
    expect_equal(.as_num11(rung$win_hi), .CS11_WIN_HI, tolerance = 0,
                 label = paste0("frozen hi echo: ", nm))
  }
  # The face's own shapes: unnamed lattice, named window.
  live <- .cs11_v(.CS11_ARMS$allout$value)
  expect_null(names(live$per_cell_in))
  expect_equal(names(live$window), c("lo", "hi"))
})

test_that("the both-ends-inclusive boundary law holds at the frozen ends", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  a <- .rs_csv11("cs11_arms.csv")
  rows <- a[a$arm == "boundary", , drop = FALSE]
  # The exact ends of the frozen window read IN; the epsilon-flanks read OUT.
  expect_equal(as.character(rows$coverage[1L:2L]), c("0.930", "0.970"))
  expect_equal(as.integer(rows$lattice_bit[1L:2L]), c(1L, 1L))
  expect_equal(as.character(rows$coverage[3L:4L]), c("0.929999", "0.970001"))
  expect_equal(as.integer(rows$lattice_bit[3L:4L]), c(0L, 0L))
  live <- .cs11_v(.CS11_ARMS$boundary$value)
  expect_equal(live$failing_cells, c(3L, 4L))
  expect_false(live$all_in_window)
  d <- .rs_tsv11("cs11_degenerates.tsv")
  dv <- setNames(as.character(d$value), as.character(d$name))
  expect_equal(dv[["boundary_lo_inclusive"]], "1")
  expect_equal(dv[["boundary_hi_inclusive"]], "1")
})

test_that("the precedence ladder flips both ways: arg beats attr beats default", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  p <- .rs_csv11("cs11_precedence.csv")
  expect_equal(as.character(p$source), c("default", "attr", "arg"))
  expect_equal(as.character(p$all), c("TRUE", "FALSE", "TRUE"))
  for (i in seq_len(3L)) {
    expect_equal(.cs11_failing(p$failing[i]),
                 list(integer(0), 2L, integer(0))[[i]],
                 label = paste0("prec census row: ", as.character(p$source[i])))
  }
  expect_equal(as.integer(p$n_failing), c(0L, 1L, 0L))
  expect_equal(.as_num11(p$win_lo), c(.CS11_WIN_LO, .CS11_PREC_ATTR[1L], .CS11_PREC_ARG[1L]),
               tolerance = 0)
  expect_equal(.as_num11(p$win_hi), c(.CS11_WIN_HI, .CS11_PREC_ATTR[2L], .CS11_PREC_ARG[2L]),
               tolerance = 0)
  # Live re-derivation of both measured flips through the exported face.
  t1 <- .cs11_tbl(.CS11_PREC_BASE)
  r1 <- ms_calibration_verdict(t1)                       # frozen default
  expect_true(r1$all_in_window)
  expect_length(r1$failing_cells, 0L)
  attr(t1, "window") <- .CS11_PREC_ATTR
  r2 <- ms_calibration_verdict(t1)                       # attr beats default
  expect_false(r2$all_in_window)
  expect_equal(r2$failing_cells, 2L)
  r3 <- ms_calibration_verdict(t1, window = .CS11_PREC_ARG)  # arg beats attr
  expect_true(r3$all_in_window)
  expect_length(r3$failing_cells, 0L)
})

test_that("the input laws abort with the committed classes and clauses", {
  df_ok <- data.frame(mean_coverage = c(0.95, 0.96))
  probes <- list(
    na_column = quote(ms_calibration_verdict(data.frame(mean_coverage = c(0.5, NA)))),
    missing_col = quote(ms_calibration_verdict(data.frame(x = 1))),
    not_df = quote(ms_calibration_verdict(as.list(c(0.9, 0.95)))),
    zero_rows = quote(ms_calibration_verdict(data.frame(mean_coverage = numeric(0)))),
    win_reversed = quote(ms_calibration_verdict(df_ok, window = c(2, 1))),
    win_nonfinite = quote(ms_calibration_verdict(df_ok, window = c(0.9, Inf))),
    win_len1 = quote(ms_calibration_verdict(df_ok, window = 0.95)),
    win_char = quote(ms_calibration_verdict(df_ok, window = c("a", "b"))),
    win_eq_ends = quote(ms_calibration_verdict(df_ok, window = c(0.9, 0.9))))
  expect_equal(names(probes), names(.CS11_LAWS))
  for (nm in names(probes)) {
    e <- tryCatch(eval(probes[[nm]]), error = function(e) e)
    if (nm == "win_eq_ends") {
      # Observed law: a degenerate closed window (lo == hi) is LEGAL.
      expect_false(inherits(e, "error"),
                   label = "win_eq_ends is witnessed NO-ABORT")
      next
    }
    expect_true(inherits(e, "error"), label = paste0("law aborts: ", nm))
    expect_true(inherits(e, "msuiter_error_input"),
                 label = paste0("law class: ", nm))
    msg <- paste(conditionMessage(e))
    expect_true(grepl(.CS11_LAWS[[nm]], msg, fixed = TRUE),
                 label = paste0(nm, " speaks the committed clause"))
  }
})

test_that("the degenerates witness pins the census laws and the abort witnesses", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  d <- .rs_tsv11("cs11_degenerates.tsv")
  dv <- setNames(as.character(d$value), as.character(d$name))
  expect_equal(dv[["allout_failing"]], "1,2,3")
  expect_equal(dv[["allout_all"]], "FALSE")
  expect_equal(dv[["single_all"]], "TRUE")
  expect_true(is.na(dv[["single_failing"]]))          # committed empty census
  expect_equal(dv[["all2x_failing"]], "1,2")
  expect_equal(dv[["lattice_names_null"]], "TRUE")
  expect_equal(dv[["window_names"]], "lo,hi")
  expect_equal(dv[["win_eq_ends_noabort"]], "1")
  for (ab in c("na_column_abort", "missing_col_abort", "not_df_abort",
               "zero_rows_abort", "win_reversed_abort", "win_nonfinite_abort",
               "win_len1_abort", "win_char_abort")) {
    expect_equal(dv[[ab]], "1", label = paste0("abort witnessed: ", ab))
  }
  expect_equal(dv[["law_form_clause"]], .CS11_CLAUSE_FORM)
  expect_equal(dv[["law_window_clause"]], .CS11_CLAUSE_WINDOW)
  # Live shape laws behind the committed bits.
  live <- .cs11_v(.CS11_ARMS$allout$value)
  expect_equal(live$failing_cells, seq_along(.CS11_ARMS$allout$value))
  expect_false(live$all_in_window)
  one <- .cs11_v(.CS11_ARMS$single$value)
  expect_true(one$all_in_window)
  expect_length(one$failing_cells, 0L)
})

test_that("the scalars witness pins the frozen constants and the plant checksum", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  s <- .rs_csv11("cs11_scalars.csv")
  sv <- setNames(as.character(s$value), as.character(s$key))
  expect_equal(sv[["scenario_shape"]], "cs11-calibration-verdict-witness")
  expect_equal(sv[["face"]], "ms_calibration_verdict")
  expect_equal(.as_num11(sv[["frozen_lo"]]), .CS11_WIN_LO, tolerance = 0)
  expect_equal(.as_num11(sv[["frozen_hi"]]), .CS11_WIN_HI, tolerance = 0)
  expect_equal(sv[["arm_count"]], "6")
  expect_equal(sv[["lattice_rows"]], "9")
  expect_equal(sv[["precedence_rows"]], "3")
  expect_equal(sv[["precedence_flips"]], "2")
  expect_equal(sv[["input_law_probes"]], "9")
  expect_equal(sv[["input_law_aborts"]], "8")
  # The plant checksum rides over the rational LABELS -- re-derived here
  # from the frozen source text, dual-kernel proof lives in the runner.
  plant <- paste0(vapply(names(.CS11_ARMS),
                         function(nm) .CS11_ARMS[[nm]]$label, character(1L)),
                  collapse = ";")
  plant <- paste0(plant, ";", paste0(.CS11_PREC_BASE, collapse = ","))
  expect_equal(sv[["plant_checksum"]],
               digest::digest(charToRaw(plant), algo = "sha256",
                              serialize = FALSE))
})
