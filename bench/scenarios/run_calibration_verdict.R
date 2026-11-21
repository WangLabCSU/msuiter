# run_calibration_verdict.R -- the CS-11 calibration-verdict-witness
# scenario (pillar 3).
#
# Mandate: plant pure-rational mean_coverage tables (the D3 law: synthetic
# coverage fractions from hand-picked rationals only -- zero COSMIC numeric
# matrices, zero real calibration bytes, zero downloads) and adjudicate the
# EXPORTED face ms_calibration_verdict() under six arms: an all-in lattice,
# the both-ends-inclusive boundary at the frozen window c(lo = 0.930,
# hi = 0.970), a low+high flip-pair with an ascending failing-cell census,
# the three-source precedence ladder (explicit arg > recorded attr > frozen
# default), the degenerate shapes, and the input-law set. Every arm is
# driven through the EXPORTED face alone -- the lattice bits, the census
# vectors and the all-in bit are the face's own; no hand-rolled windowing is
# ever invoked here. The whole scenario is RNG-free and network-free: the
# plant is closed-form rational arithmetic and there is no seed to pin. The
# lane never invokes the declined calibration-kernel faces (the seeded
# grid/bootstrap estimators) -- the verdict face is the whole scope.
#
# Framing law: DECISION RECORD only. What this scenario records is the
# shipped face's documented adjudicative behavior on planted truth: the
# lattice bits, the census vectors, the all-in bits, the measured
# precedence flips -- an OBSERVED, COMMITTED fact, never a coverage or
# calibration claim. Float posture: the committed witnesses freeze integer
# and label verdicts and the exact rational SOURCE LABELS of the plant;
# the plant checksum re-hashes through BOTH governed SHA-256 kernels -- the
# canonical pure-R one and the digest accelerator -- so a silent byte-rot in
# what was measured reddens the run. The witness bytes under out/ are the
# verdict; a byte-rerun must reproduce them identically.

.script_dir <- local({
  a <- grep("^--file=(.*)$", commandArgs(FALSE), perl = TRUE, value = TRUE)
  if (length(a) == 0L) return(getwd())
  f <- sub("^--file=", "", a[1L])
  if (!grepl("/", f, fixed = TRUE)) return(getwd())
  dirname(f)
})
ROOT <- normalizePath(file.path(.script_dir, "..", ".."), mustWork = TRUE)
OUT <- file.path(ROOT, "bench", "scenarios", "out")

if (requireNamespace("pkgload", quietly = TRUE) &&
    file.exists(file.path(ROOT, "DESCRIPTION"))) {
  suppressWarnings(suppressMessages(
    pkgload::load_all(ROOT, quiet = TRUE, export_all = TRUE)))
} else {
  library(msuiter)
}

# -- frozen scenario constants (mirrored byte-identically in the law test) --
ARMS <- list(
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
LATTICE <- list(allin = c(1L, 1L, 1L), boundary = c(1L, 1L, 0L, 0L),
                flippair = c(1L, 0L, 1L, 0L), allout = c(0L, 0L, 0L),
                single = 1L, all2x = c(0L, 0L))
FAILING <- list(allin = integer(0), boundary = c(3L, 4L),
                flippair = c(2L, 4L), allout = c(1L, 2L, 3L),
                single = integer(0), all2x = c(1L, 2L))
PREC_BASE <- c(0.955, 0.965)
PREC_ATTR <- c(0.900, 0.961)
PREC_ARG <- c(0.900, 0.970)
CLAUSE_FORM <- paste0("calibration must be a data.frame with an ",
                      "NA-free numeric mean_coverage column")
CLAUSE_WINDOW <- paste0("window must be c(lo, hi): two finite ",
                        "numbers in [0, 1] with lo <= hi")

tbl_of <- function(v) {
  data.frame(mean_coverage = v, cell = paste0("cell", seq_along(v)),
             stringsAsFactors = FALSE)
}
v_of <- function(v, window = NULL) ms_calibration_verdict(tbl_of(v),
                                                          window = window)

verdict <- new.env(parent = emptyenv())
verdict$fail <- 0L
.check <- function(label, ok) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ")
  cat(label, "\n")
  if (!isTRUE(ok)) verdict$fail <- verdict$fail + 1L
  invisible(isTRUE(ok))
}

# ---------------------------------------------------------------------------
# 1. the six-arm adjudication through the exported face
# ---------------------------------------------------------------------------
cat("== cs11 calibration-verdict-witness: six-arm adjudication ==\n")
arm_rows <- NULL
lattice_rows <- NULL
live_default <- NULL
for (nm in names(ARMS)) {
  r <- v_of(ARMS[[nm]]$value)
  if (identical(nm, "allin")) live_default <- r
  bits <- as.integer(r$per_cell_in)
  fc <- as.integer(r$failing_cells)
  .check(paste0("arm lattice byte-matches the committed record: ", nm),
         identical(bits, LATTICE[[nm]]))
  .check(paste0("arm census byte-matches the committed record: ", nm),
         identical(fc, FAILING[[nm]]))
  .check(paste0("arm census ascends: ", nm),
         !any(diff(fc) <= 0L))
  .check(paste0("all-in bit agrees with the census: ", nm),
         identical(as.logical(r$all_in_window), identical(length(fc), 0L)))
  labels <- strsplit(ARMS[[nm]]$label, ",", fixed = TRUE)[[1L]]
  .check(paste0("plant labels tie the numeric plant: ", nm),
          identical(as.numeric(labels), as.numeric(ARMS[[nm]]$value)) &&
            identical(length(labels), length(bits)))
  arm_rows <- rbind(arm_rows, data.frame(
    arm = nm, i = seq_along(bits), cell = paste0("cell", seq_along(bits)),
    coverage = labels, lattice_bit = bits,
    failing_bit = as.integer(bits == 0L),
    all_bit = as.integer(length(fc) == 0L),
    n_failing = as.integer(length(fc)), stringsAsFactors = FALSE))
  lattice_rows <- rbind(lattice_rows, data.frame(
    arm = nm, lattice = paste0(bits, collapse = ","),
    all = as.character(r$all_in_window),
    failing = paste0(fc, collapse = ","),
    win_lo = format(r$window[["lo"]]), win_hi = format(r$window[["hi"]]),
    stringsAsFactors = FALSE))
}
.check("the frozen window echo speaks the committed literals",
       identical(as.numeric(c(live_default$window[["lo"]],
                              live_default$window[["hi"]])),
                 c(0.930, 0.970)))
.check("the lattice is unnamed and the window is named lo,hi",
       is.null(names(live_default$per_cell_in)) &&
         identical(names(live_default$window), c("lo", "hi")))

# ---------------------------------------------------------------------------
# 2. the both-ends-inclusive boundary law at the frozen ends
# ---------------------------------------------------------------------------
cat("== cs11 calibration-verdict-witness: inclusive boundary law ==\n")
b_rows <- arm_rows[arm_rows$arm == "boundary", , drop = FALSE]
.check("the exact frozen ends read IN (both-ends-inclusive law)",
       identical(as.character(b_rows$coverage[1L:2L]), c("0.930", "0.970")) &&
         identical(as.integer(b_rows$lattice_bit[1L:2L]), c(1L, 1L)))
.check("the epsilon flanks read OUT",
       identical(as.character(b_rows$coverage[3L:4L]),
                 c("0.929999", "0.970001")) &&
         identical(as.integer(b_rows$lattice_bit[3L:4L]), c(0L, 0L)))

# ---------------------------------------------------------------------------
# 3. the precedence ladder: arg beats attr beats default (both flips live)
# ---------------------------------------------------------------------------
cat("== cs11 calibration-verdict-witness: precedence ladder ==\n")
t1 <- tbl_of(PREC_BASE)
r_default <- ms_calibration_verdict(t1)
attr(t1, "window") <- PREC_ATTR
r_attr <- ms_calibration_verdict(t1)
r_arg <- ms_calibration_verdict(t1, window = PREC_ARG)
.check("default rung: the frozen window admits the whole table",
       isTRUE(r_default$all_in_window) && length(r_default$failing_cells) == 0L)
.check("attr rung flips: the recorded window condemns cell 2",
       !r_attr$all_in_window &&
         identical(as.integer(r_attr$failing_cells), 2L))
.check("arg rung flips back: the explicit window outranks the attr",
       isTRUE(r_arg$all_in_window) && length(r_arg$failing_cells) == 0L)
prec_rows <- data.frame(
  source = c("default", "attr", "arg"),
  win_lo = c(format(r_default$window[["lo"]]), format(r_attr$window[["lo"]]),
             format(r_arg$window[["lo"]])),
  win_hi = c(format(r_default$window[["hi"]]), format(r_attr$window[["hi"]]),
             format(r_arg$window[["hi"]])),
  all = c(as.character(r_default$all_in_window),
          as.character(r_attr$all_in_window),
          as.character(r_arg$all_in_window)),
  failing = c(paste0(r_default$failing_cells, collapse = ","),
              paste0(r_attr$failing_cells, collapse = ","),
              paste0(r_arg$failing_cells, collapse = ",")),
  n_failing = c(length(r_default$failing_cells), length(r_attr$failing_cells),
                length(r_arg$failing_cells)),
  stringsAsFactors = FALSE)
lattice_rows <- rbind(lattice_rows, data.frame(
  arm = c("prec_default", "prec_attr", "prec_arg"),
  lattice = c(paste0(as.integer(r_default$per_cell_in), collapse = ","),
              paste0(as.integer(r_attr$per_cell_in), collapse = ","),
              paste0(as.integer(r_arg$per_cell_in), collapse = ",")),
  all = prec_rows$all, failing = prec_rows$failing,
  win_lo = prec_rows$win_lo, win_hi = prec_rows$win_hi,
  stringsAsFactors = FALSE))

# ---------------------------------------------------------------------------
# 4. the degenerate shapes and the input laws (committed clauses, verbatim)
# ---------------------------------------------------------------------------
cat("== cs11 calibration-verdict-witness: degenerates and input laws ==\n")
r_allout <- v_of(ARMS$allout$value)
r_single <- v_of(ARMS$single$value)
r_all2x <- v_of(ARMS$all2x$value)
.check("all-out arm: the census names every cell, ascending",
       identical(as.integer(r_allout$failing_cells), 1L:3L) &&
         !r_allout$all_in_window)
.check("single-cell arm: one in-window cell speaks the all-in bit",
       isTRUE(r_single$all_in_window) && length(r_single$failing_cells) == 0L)
.check("all-2x arm: both flanking cells condemn together",
       identical(as.integer(r_all2x$failing_cells), c(1L, 2L)) &&
         !r_all2x$all_in_window)

df_ok <- data.frame(mean_coverage = c(0.95, 0.96))
LAW_PROBES <- list(
  na_column = function() ms_calibration_verdict(
    data.frame(mean_coverage = c(0.5, NA))),
  missing_col = function() ms_calibration_verdict(data.frame(x = 1)),
  not_df = function() ms_calibration_verdict(as.list(c(0.9, 0.95))),
  zero_rows = function() ms_calibration_verdict(
    data.frame(mean_coverage = numeric(0))),
  win_reversed = function() ms_calibration_verdict(df_ok, window = c(2, 1)),
  win_nonfinite = function() ms_calibration_verdict(df_ok,
                                                    window = c(0.9, Inf)),
  win_len1 = function() ms_calibration_verdict(df_ok, window = 0.95),
  win_char = function() ms_calibration_verdict(df_ok, window = c("a", "b")),
  win_eq_ends = function() ms_calibration_verdict(df_ok,
                                                  window = c(0.9, 0.9)))
LAW_CLAUSES <- list(na_column = CLAUSE_FORM, missing_col = CLAUSE_FORM,
                    not_df = CLAUSE_FORM, zero_rows = CLAUSE_FORM,
                    win_reversed = CLAUSE_WINDOW, win_nonfinite = CLAUSE_WINDOW,
                    win_len1 = CLAUSE_WINDOW, win_char = CLAUSE_WINDOW,
                    win_eq_ends = character(0))
abort_bits <- setNames(rep_len(0L, length(LAW_PROBES)), names(LAW_PROBES))
for (nm in names(LAW_PROBES)) {
  e <- tryCatch(LAW_PROBES[[nm]](), error = function(e) e)
  if (identical(nm, "win_eq_ends")) {
    # Observed law: a degenerate closed window (lo == hi) is LEGAL.
    abort_bits[[nm]] <- as.integer(!inherits(e, "error"))
    .check("the degenerate closed window is witnessed NO-ABORT",
           !inherits(e, "error"))
    next
  }
  spoke <- inherits(e, "error") && inherits(e, "msuiter_error_input") &&
    all(vapply(LAW_CLAUSES[[nm]], function(cl)
      grepl(cl, paste(conditionMessage(e)), fixed = TRUE), logical(1L)))
  abort_bits[[nm]] <- as.integer(spoke)
  .check(paste0("input law aborts with the committed class and clause: ", nm),
         spoke)
}

# ---------------------------------------------------------------------------
# 5. the plant-checksum dual-kernel identity (governed-infrastructure rail)
# ---------------------------------------------------------------------------
cat("== cs11 calibration-verdict-witness: plant-checksum dual-kernel identity ==\n")
plant_txt <- paste0(vapply(names(ARMS),
                           function(nm) ARMS[[nm]]$label, character(1L)),
                    collapse = ";")
plant_txt <- paste0(plant_txt, ";", paste0(PREC_BASE, collapse = ","))
bytes <- charToRaw(plant_txt)
h_canonical <- .ms_fit_sha256(bytes)
have_accel <- requireNamespace("digest", quietly = TRUE)
h_accel <- if (have_accel) {
  asNamespace("digest")$digest(bytes, algo = "sha256", serialize = FALSE)
} else {
  NA_character_
}
kernels_equal <- identical(h_canonical, h_accel) || !have_accel
.check("the digest accelerator (where installed) agrees with the canonical kernel",
       kernels_equal)
.check("the plant checksum is a 64-hex scalar",
       is.character(h_canonical) && nchar(h_canonical) == 64L &&
         length(grep("^[0-9a-f]{64}$", h_canonical, perl = TRUE)) == 1L)

# ---------------------------------------------------------------------------
# 6. [attest] -- declined scope rails, made audible
# ---------------------------------------------------------------------------
cat("[attest] DECISION RECORD only: the face's behavior on planted truth is\n")
cat("[attest]   an OBSERVED, COMMITTED record -- no coverage claim, no\n")
cat("[attest]   calibration claim, no threshold-fit claim of any kind.\n")
cat("[attest] NETWORK: never attempted -- the plant is closed-form rational\n")
cat("[attest]   arithmetic; no download face, no live registry, no external\n")
cat("[attest]   byte is read.\n")
cat("[attest] D3 law: synthetic coverage fractions from hand-picked rationals\n")
cat("[attest]   only; zero COSMIC numeric matrices, zero real calibration bytes.\n")
cat("[attest] RNG-free executed path: no seed to pin, no draw to re-roll.\n")
cat("[attest] no estimation machinery: no bootstrap, no intervals,\n")
cat("[attest]   no conformal framing (paper declined-word), no new faces;\n")
cat("[attest]   the seeded grid/bootstrap estimators of the calibration\n")
cat("[attest]   module are DECLINED scope and are never invoked here.\n")
cat("[attest] FACE-only adjudication: the lattice bits, the census vectors and\n")
cat("[attest]   the all-in bits are the exported face's own; no hand-rolled\n")
cat("[attest]   windowing is invoked. The plant-checksum rail reaches the two\n")
cat("[attest]   governed SHA-256 kernels by name (infrastructure equality,\n")
cat("[attest]   adjudication-independent).\n")
cat("[attest] D11 posture: the witnesses byte-freeze integer and label verdicts\n")
cat("[attest]   and the exact rational SOURCE LABELS of the plant; no\n")
cat("[attest]   ill-conditioned float rendering is ever committed.\n")

# ---------------------------------------------------------------------------
# 7. the witnesses
# ---------------------------------------------------------------------------
degens <- data.frame(
  name = c("allout_all", "allout_failing", "single_all", "single_failing",
           "all2x_failing", "lattice_names_null", "window_names",
           "boundary_lo_inclusive", "boundary_hi_inclusive",
           "win_eq_ends_noabort",
           "na_column_abort", "missing_col_abort", "not_df_abort",
           "zero_rows_abort", "win_reversed_abort", "win_nonfinite_abort",
           "win_len1_abort", "win_char_abort",
           "law_form_clause", "law_window_clause"),
  value = c(
    as.character(r_allout$all_in_window),
    paste0(as.integer(r_allout$failing_cells), collapse = ","),
    as.character(r_single$all_in_window),
    paste0(as.integer(r_single$failing_cells), collapse = ","),
    paste0(as.integer(r_all2x$failing_cells), collapse = ","),
    as.character(is.null(names(r_allout$per_cell_in))),
    paste0(names(r_allout$window), collapse = ","),
    as.character(as.integer(b_rows$lattice_bit[1L] == 1L)),
    as.character(as.integer(b_rows$lattice_bit[2L] == 1L)),
    as.character(abort_bits[["win_eq_ends"]]),
    as.character(abort_bits[["na_column"]]),
    as.character(abort_bits[["missing_col"]]),
    as.character(abort_bits[["not_df"]]),
    as.character(abort_bits[["zero_rows"]]),
    as.character(abort_bits[["win_reversed"]]),
    as.character(abort_bits[["win_nonfinite"]]),
    as.character(abort_bits[["win_len1"]]),
    as.character(abort_bits[["win_char"]]),
    CLAUSE_FORM, CLAUSE_WINDOW),
  stringsAsFactors = FALSE)

scalars <- data.frame(
  key = c("scenario_shape", "face", "frozen_lo", "frozen_hi",
          "arm_count", "lattice_rows", "precedence_rows", "precedence_flips",
          "input_law_probes", "input_law_aborts", "plant_checksum"),
  value = c("cs11-calibration-verdict-witness", "ms_calibration_verdict",
            format(live_default$window[["lo"]]),
            format(live_default$window[["hi"]]),
            as.character(length(ARMS)), as.character(nrow(lattice_rows)),
            as.character(nrow(prec_rows)), "2",
            as.character(length(LAW_PROBES)),
            as.character(sum(abort_bits[names(LAW_PROBES) != "win_eq_ends"])),
            h_canonical),
  stringsAsFactors = FALSE)

# The finiteness census: refuse to commit a witness with a dead column
# (the witness-finiteness law -- a column that never fires is not evidence).
ok_payload <-
  nrow(arm_rows) == 17L &&
  all(arm_rows$lattice_bit %in% 0:1) && all(arm_rows$failing_bit %in% 0:1) &&
  all(arm_rows$all_bit %in% 0:1) && all(arm_rows$n_failing >= 0L) &&
  identical(as.character(arm_rows$coverage[1L:3L]),
            strsplit(ARMS$allin$label, ",", fixed = TRUE)[[1L]]) &&
  nrow(lattice_rows) == 9L &&
  all(lattice_rows$arm %in% c(names(ARMS), "prec_default", "prec_attr", "prec_arg")) &&
  all(lattice_rows$all %in% c("TRUE", "FALSE")) &&
  nrow(prec_rows) == 3L &&
  identical(as.character(prec_rows$source), c("default", "attr", "arg")) &&
  identical(as.character(prec_rows$all), c("TRUE", "FALSE", "TRUE")) &&
  all(degens$value[nzchar(degens$value)] %in%
        c("0", "1", "TRUE", "FALSE", "lo,hi", "1,2,3", "1,2", "2",
          CLAUSE_FORM, CLAUSE_WINDOW)) &&
  !anyDuplicated(degens$name) &&
  all(scalars$key == unique(scalars$key)) &&
  identical(scalars$value[scalars$key == "scenario_shape"],
            "cs11-calibration-verdict-witness") &&
  identical(scalars$value[scalars$key == "input_law_probes"], "9") &&
  identical(scalars$value[scalars$key == "input_law_aborts"], "8")
if (!ok_payload) {
  cat("  FAIL witness payload census (refusing to commit an unlive column)\n")
  verdict$fail <- verdict$fail + 1L
}

dir.create(OUT, showWarnings = FALSE)
write.csv(arm_rows, file.path(OUT, "cs11_arms.csv"), row.names = FALSE)
write.csv(lattice_rows, file.path(OUT, "cs11_lattice.csv"), row.names = FALSE)
write.csv(prec_rows, file.path(OUT, "cs11_precedence.csv"), row.names = FALSE)
write.csv(scalars, file.path(OUT, "cs11_scalars.csv"), row.names = FALSE)
write.table(degens, file.path(OUT, "cs11_degenerates.tsv"), sep = "\t",
            quote = FALSE, row.names = FALSE, col.names = TRUE)

cat("== cs11 calibration-verdict-witness scenario: ",
    if (identical(verdict$fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " == (evidence: ", OUT, ")\n", sep = "")
quit(save = "no", status = if (identical(verdict$fail, 0L)) 0L else 1L)
