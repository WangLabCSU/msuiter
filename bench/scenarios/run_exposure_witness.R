# run_exposure_witness.R -- the CS-10 exposure-witness scenario (pillar 3).
#
# Mandate: plant six pure-arithmetic signature legs over 24 samples in two
# 12-sample groups (the D3 law: synthetic 9.x/2.x leg labels and arithmetic
# exposure bytes only -- zero COSMIC numeric matrices, zero downloads) and
# adjudicate the EXPORTED face ms_exposure_test() under six arms: designed
# differentials, a same-distribution decoy (escapes the NA face, stays
# negative), the tied/NA face (no fabricated p), a borderline leg frozen at
# DB = 0.18, the BH ladder over two family rosters x three alphas, and the
# input-law set. Every arm is driven through the EXPORTED face alone -- no
# hand-rolled rank-sum test and no hand-rolled family correction is ever
# invoked here. The whole scenario is RNG-free and network-free: the plant
# is closed-form arithmetic and there is no seed to pin.
#
# Framing law: DECISION RECORD only. What this scenario records is the
# shipped face's documented adjudicative behavior on planted truth: the
# pass bits, the ladder flip vectors, the NA censuses, the measured
# borderline rung -- an OBSERVED, COMMITTED fact, never a calibration or a
# coverage claim. Float posture: the committed witness freezes integer and
# label verdicts; float columns are re-derived live by the law file through
# the same face at tolerance, never sealed as cross-platform bytes. The
# plant checksum re-hashes through BOTH governed SHA-256 kernels -- the
# canonical pure-R one and the digest accelerator -- so a silent byte-rot
# in what was measured reddens the run. The witness bytes under out/ are
# the verdict; a byte-rerun must reproduce them identically.

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
ROSTER <- c("9.4", "2.6", "9.1", "2.2", "9.8", "2.9")
R5 <- setdiff(ROSTER, "2.9")
N <- 12L
DB <- 0.18
ALPHA_FROZEN <- 0.05
ALPHA_LABELS <- c("0.001", "0.05", "0.2")
ALPHA_VALUES <- c(0.001, 0.05, 0.2)

v8 <- (seq_len(N) - 1L) / N
LEGS <- list(
  "9.4" = c(v8, v8 + 0.62),
  "2.6" = c(v8 + 0.50, v8),
  "9.1" = c(v8, rev(v8)),
  "2.2" = c(v8, v8),
  "9.8" = c(v8, v8 + DB),
  "2.9" = c(v8, v8 + 0.45))
GROUPS <- c(rep_len("A", N), rep_len("B", N))

mat_of <- function(names) {
  m <- do.call(rbind, lapply(names, function(k) LEGS[[k]]))
  dimnames(m) <- list(names, NULL)
  m
}
run_of <- function(m, alpha = ALPHA_FROZEN) ms_exposure_test(m, GROUPS, alpha = alpha)

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
cat("== cs10 exposure-witness: six-arm adjudication ==\n")
arm6 <- run_of(mat_of(ROSTER), ALPHA_FROZEN)
p6 <- as.numeric(arm6$p_raw)
pbh6 <- as.numeric(arm6$p_bh)
pass6 <- as.integer(arm6$pass_bh)
st6 <- as.numeric(arm6$statistic)

row6 <- function(sig) arm6[arm6$signature == sig, , drop = FALSE]
.check("designed leg 9.4 passes the frozen alpha",
       identical(as.integer(row6("9.4")$pass_bh), 1L))
.check("designed leg 2.6 passes the frozen alpha",
       identical(as.integer(row6("2.6")$pass_bh), 1L))
.check("family-size leg 2.9 passes the frozen alpha",
       identical(as.integer(row6("2.9")$pass_bh), 1L))
.check("decoy escapes the NA face (finite statistic)",
       is.finite(as.numeric(row6("9.1")$statistic)))
.check("decoy speaks p = 1 and stays negative",
       identical(as.numeric(row6("9.1")$p_raw), 1) &&
         identical(as.integer(row6("9.1")$pass_bh), 0L))
.check("tied leg is the NA face, never a fabricated p",
       is.na(as.numeric(row6("2.2")$statistic)) &&
         is.na(as.numeric(row6("2.2")$p_raw)) &&
         is.na(as.numeric(row6("2.2")$p_bh)) &&
         identical(as.integer(row6("2.2")$pass_bh), 0L))
.check("tied leg still speaks its medians",
       identical(as.numeric(row6("2.2")$median_group1),
                 as.numeric(row6("2.2")$median_group2)))
.check("borderline leg fails the frozen alpha",
       identical(as.integer(row6("9.8")$pass_bh), 0L))
.check("NA censuses: exactly one NA p_raw, one NA p_bh, zero NA passes",
       sum(is.na(p6)) == 1L && sum(is.na(pbh6)) == 1L &&
         sum(is.na(as.integer(arm6$pass_bh))) == 0L)
.check("p-value payload in-domain or NA",
       all(is.na(p6) | (p6 >= 0 & p6 <= 1)) &&
         all(is.na(pbh6) | (pbh6 >= 0 & pbh6 <= 1)))
.check("fold-back law: p_bh never undercuts p_raw",
       all(pbh6[!is.na(pbh6)] >= p6[!is.na(pbh6)] - 1e-12))
.check("fold-back cap: p_bh never exceeds 1",
       all(pbh6 <= 1 + 1e-12, na.rm = TRUE))

# ---------------------------------------------------------------------------
# 2. the BH ladder over two family rosters x three alphas (flip vectors)
# ---------------------------------------------------------------------------
cat("== cs10 exposure-witness: BH ladder ==\n")
FLIPS <- list(
  R6 = list("0.001" = character(0), "0.05" = c("9.4", "2.6", "2.9"),
             "0.2" = c("9.4", "2.6", "9.8", "2.9")),
  R5 = list("0.001" = character(0), "0.05" = c("9.4", "2.6"),
             "0.2" = c("9.4", "2.6", "9.8")))
lad_rows <- NULL
for (rn in c("R6", "R5")) {
  m <- mat_of(if (identical(rn, "R6")) ROSTER else R5)
  for (i in seq_len(length(ALPHA_LABELS))) {
    r <- run_of(m, ALPHA_VALUES[i])
    lad_rows <- rbind(lad_rows, data.frame(
      roster = rn, alpha = ALPHA_LABELS[i],
      signature = as.character(r$signature),
      p_raw = as.numeric(r$p_raw), p_bh = as.numeric(r$p_bh),
      pass = as.integer(r$pass_bh), stringsAsFactors = FALSE))
    .check(paste0("flip vector: ", rn, " @", ALPHA_LABELS[i]),
           identical(as.character(r$signature[r$pass_bh]),
                     FLIPS[[rn]][[ALPHA_LABELS[i]]]))
    .check(paste0("rung NA census: ", rn, " @", ALPHA_LABELS[i]),
           sum(is.na(as.numeric(r$p_raw))) == 1L)
  }
}
.check("designed legs never flip across the meaningful alpha range",
       all(lad_rows$pass[lad_rows$alpha != "0.001" &
             lad_rows$signature %in% c("9.4", "2.6")] == 1L))

# ---------------------------------------------------------------------------
# 3. the label fallback and the MsSignature equivalence
# ---------------------------------------------------------------------------
cat("== cs10 exposure-witness: labels and object input ==\n")
m2 <- mat_of(ROSTER[1L:2L])
dimnames(m2) <- NULL
fb <- ms_exposure_test(m2, GROUPS)
.check("NULL rownames fall back to sig1..sigk",
       identical(as.character(fb$signature), paste0("sig", seq_len(2L))))
nm2 <- ms_exposure_test(mat_of(ROSTER[1L:2L]), GROUPS)
.check("named input speaks its names",
       identical(as.character(nm2$signature), ROSTER[1L:2L]))

samples <- paste0("s", seq_len(2L * N))
chan <- c("cs10chanA", "cs10chanB")
counts <- matrix(as.numeric(seq_len(2L * 2L * N)), nrow = 2L, ncol = 2L * N,
  dimnames = list(chan, samples))
cat1 <- ms_catalog(counts, list(name = "CS10SYN", labels = chan),
  samples, provenance = list(genome = "GRCSYN"))
msig <- mat_of(ROSTER)
colnames(msig) <- samples
sigmat <- matrix(as.numeric(seq_len(2L * length(ROSTER))),
  nrow = 2L, ncol = length(ROSTER), dimnames = list(chan, ROSTER))
so <- ms_signature(signatures = sigmat, exposures = msig,
  catalog_summary = msuiter_catalog_summary(cat1),
  engine = "cs10-witness", seed = 0)
r_obj <- ms_exposure_test(so, GROUPS, alpha = ALPHA_FROZEN)
msig_eq <- isTRUE(all.equal(r_obj, arm6, check.attributes = FALSE))
.check("MsSignature input is all.equal to the raw-matrix input", msig_eq)

# ---------------------------------------------------------------------------
# 4. the input laws (abort classes and committed clauses, verbatim)
# ---------------------------------------------------------------------------
cat("== cs10 exposure-witness: input laws ==\n")
LAW_PROBES <- list(
  three_groups = function() ms_exposure_test(mat_of(ROSTER),
    c(rep_len("A", N), rep_len("B", N - 1L), "C")),
  alpha_zero = function() ms_exposure_test(mat_of(ROSTER), GROUPS, alpha = 0),
  alpha_one = function() ms_exposure_test(mat_of(ROSTER), GROUPS, alpha = 1),
  alpha_two = function() ms_exposure_test(mat_of(ROSTER), GROUPS, alpha = 2),
  groups_len = function() ms_exposure_test(mat_of(ROSTER),
    GROUPS[seq_len(2L * N - 1L)]),
  matrix_chr = function() ms_exposure_test(as.character(mat_of(ROSTER)), GROUPS),
  groups_list = function() ms_exposure_test(mat_of(ROSTER), as.list(GROUPS)))
LAW_CLAUSES <- list(
  three_groups = c("exactly two groups are required",
                   "pairwise splits of multi-group designs are the caller's decision"),
  alpha_zero = "alpha must be a single number in (0, 1)",
  alpha_one = "alpha must be a single number in (0, 1)",
  alpha_two = "alpha must be a single number in (0, 1)",
  groups_len = "groups must have one label per exposure column",
  matrix_chr = "exposures must be a numeric k x n matrix (or an MsSignature)",
  groups_list = "groups must be a character vector or factor over the samples")
abort_bits <- setNames(rep_len(0L, length(LAW_PROBES)), names(LAW_PROBES))
for (nm in names(LAW_PROBES)) {
  e <- tryCatch(LAW_PROBES[[nm]](), error = function(e) e)
  spoke <- inherits(e, "error") && inherits(e, "msuiter_error_input") &&
    all(vapply(LAW_CLAUSES[[nm]], function(cl)
      grepl(cl, paste(conditionMessage(e)), fixed = TRUE), logical(1L)))
  abort_bits[[nm]] <- as.integer(spoke)
  .check(paste0("input law aborts with the committed class and clauses: ", nm),
         spoke)
}

# ---------------------------------------------------------------------------
# 5. the plant-checksum dual-kernel identity (governed-infrastructure rail)
# ---------------------------------------------------------------------------
cat("== cs10 exposure-witness: plant-checksum dual-kernel identity ==\n")
plant_txt <- paste0(paste0(names(LEGS), "=",
  vapply(LEGS, function(l) paste0(as.character(l), collapse = ","),
    character(1L))), collapse = "\n")
plant_txt <- paste0(plant_txt, "\n")
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
cat("[attest]   an OBSERVED, COMMITTED record -- no calibration, no coverage claim.\n")
cat("[attest] NETWORK: never attempted -- the plant is closed-form arithmetic;\n")
cat("[attest]   no download face, no live registry, no external byte is read.\n")
cat("[attest] D3 law: synthetic 9.x/2.x leg labels and pure-arithmetic exposure\n")
cat("[attest]   bytes only; zero COSMIC numeric matrices anywhere in this lane.\n")
cat("[attest] RNG-free executed path: no seed to pin, no draw to re-roll.\n")
cat("[attest] no estimation machinery: no bootstrap, no intervals,\n")
cat("[attest]   no conformal framing (paper declined-word), no new faces.\n")
cat("[attest] FACE-only adjudication: no hand-rolled rank-sum test and no\n")
cat("[attest]   hand-rolled family correction is invoked -- the verdicts are the\n")
cat("[attest]   exported face's own; the plant-checksum rail reaches the two\n")
cat("[attest]   governed SHA-256 kernels by name (infrastructure equality,\n")
cat("[attest]   adjudication-independent).\n")
cat("[attest] D11 posture: the witness byte-freezes integer and label verdicts;\n")
cat("[attest]   float columns are re-derived live at tolerance by the law file,\n")
cat("[attest]   never sealed as cross-platform bytes.\n")

# ---------------------------------------------------------------------------
# 7. the witnesses
# ---------------------------------------------------------------------------
arm_rows <- data.frame(
  signature = as.character(arm6$signature),
  median_group1 = as.numeric(arm6$median_group1),
  median_group2 = as.numeric(arm6$median_group2),
  statistic = st6, p_raw = p6, p_bh = pbh6,
  pass_bh = pass6, stringsAsFactors = FALSE)

degens <- data.frame(
  name = c("designed_94_pass", "designed_26_pass", "designed_29_pass",
           "decoy_statistic_finite", "decoy_p_raw", "decoy_p_bh", "decoy_pass",
           "tied_statistic", "tied_p_raw", "tied_p_bh", "tied_pass",
           "tied_medians_equal", "borderline_fail_005",
           "fallback_sig1", "fallback_sig2",
           "alpha_zero_abort", "alpha_one_abort", "alpha_two_abort",
           "three_groups_abort", "groups_len_abort", "matrix_chr_abort",
           "groups_list_abort", "fold_back_law", "cap_law", "msig_eq",
           "kernels_equal"),
  value = c(
    as.character(as.integer(row6("9.4")$pass_bh)),
    as.character(as.integer(row6("2.6")$pass_bh)),
    as.character(as.integer(row6("2.9")$pass_bh)),
    as.character(as.integer(is.finite(as.numeric(row6("9.1")$statistic)))),
    paste0(as.numeric(row6("9.1")$p_raw)),
    paste0(as.numeric(row6("9.1")$p_bh)),
    as.character(as.integer(row6("9.1")$pass_bh)),
    paste0(as.numeric(row6("2.2")$statistic)),
    paste0(as.numeric(row6("2.2")$p_raw)),
    paste0(as.numeric(row6("2.2")$p_bh)),
    as.character(as.integer(row6("2.2")$pass_bh)),
    as.character(as.integer(identical(as.numeric(row6("2.2")$median_group1),
                                     as.numeric(row6("2.2")$median_group2)))),
    as.character(as.integer(!identical(as.integer(row6("9.8")$pass_bh), 1L))),
    as.character(fb$signature[1L]), as.character(fb$signature[2L]),
    as.character(abort_bits[["alpha_zero"]]),
    as.character(abort_bits[["alpha_one"]]),
    as.character(abort_bits[["alpha_two"]]),
    as.character(abort_bits[["three_groups"]]),
    as.character(abort_bits[["groups_len"]]),
    as.character(abort_bits[["matrix_chr"]]),
    as.character(abort_bits[["groups_list"]]),
    as.character(as.integer(all(pbh6[!is.na(pbh6)] >= p6[!is.na(pbh6)] - 1e-12))),
    as.character(as.integer(all(pbh6 <= 1 + 1e-12, na.rm = TRUE))),
    as.character(as.integer(msig_eq)),
    as.character(as.integer(kernels_equal))),
  stringsAsFactors = FALSE)

scalars <- data.frame(
  key = c("scenario_shape", "face", "k", "n_samples", "alpha_frozen",
          "db_frozen", "roster6", "roster5", "input_law_count", "ladder_rows",
          "plant_canonical", "plant_accelerated"),
  value = c("cs10-exposure-witness", "ms_exposure_test",
            as.character(length(ROSTER)), as.character(2L * N),
            format(ALPHA_FROZEN), format(DB),
            paste0(ROSTER, collapse = ","), paste0(R5, collapse = ","),
            "7", as.character(nrow(lad_rows)),
            h_canonical, if (have_accel) h_accel else "NA"),
  stringsAsFactors = FALSE)

# The finiteness census: refuse to commit a witness with a dead column
# (the witness-finiteness law -- a column that never fires is not evidence).
ok_payload <-
  identical(as.character(arm_rows$signature), ROSTER) &&
  all(arm_rows$pass_bh %in% 0:1) &&
  all(is.finite(arm_rows$median_group1)) && all(is.finite(arm_rows$median_group2)) &&
  all(is.na(arm_rows$p_raw) | (arm_rows$p_raw >= 0 & arm_rows$p_raw <= 1)) &&
  all(is.na(arm_rows$p_bh) | (arm_rows$p_bh >= 0 & arm_rows$p_bh <= 1)) &&
  nrow(lad_rows) == 33L &&
  all(lad_rows$roster %in% c("R6", "R5")) &&
  all(lad_rows$alpha %in% ALPHA_LABELS) &&
  all(lad_rows$pass %in% 0:1) &&
  all(degens$value %in% c("0", "1", "NA", "sig1", "sig2")) &&
  all(degens$name %in% degens$name) && !anyDuplicated(degens$name) &&
  all(c("scenario_shape", "face", "k", "n_samples", "alpha_frozen", "db_frozen",
        "roster6", "roster5", "input_law_count") %in% scalars$key) &&
  identical(scalars$value[scalars$key == "scenario_shape"], "cs10-exposure-witness")
if (!ok_payload) {
  cat("  FAIL witness payload census (refusing to commit an unlive column)\n")
  verdict$fail <- verdict$fail + 1L
}

dir.create(OUT, showWarnings = FALSE)
write.csv(arm_rows, file.path(OUT, "cs10_arms.csv"), row.names = FALSE)
write.csv(lad_rows, file.path(OUT, "cs10_ladder.csv"), row.names = FALSE)
write.table(degens, file.path(OUT, "cs10_degenerates.tsv"), sep = "\t",
            quote = FALSE, row.names = FALSE, col.names = TRUE)
write.csv(scalars, file.path(OUT, "cs10_scalars.csv"), row.names = FALSE)

cat("== cs10 exposure-witness scenario: ",
    if (identical(verdict$fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " == (evidence: ", OUT, ")\n", sep = "")
quit(save = "no", status = if (identical(verdict$fail, 0L)) 0L else 1L)
