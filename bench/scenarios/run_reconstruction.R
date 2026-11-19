# run_reconstruction.R -- the CS-7 reconstruction-witness scenario (pillar 3).
#
# Mandate: plant a seeded SBS96 cohort (the package's own generator,
# count-scale exposures -- deterministic column totals under the
# multinomial arm) plus its deterministic linear-expectation twin, and
# adjudicate the SHIPPED Jiang reconstruction flag of ms_compare -- the
# per-sample cosine of each catalog column against signatures_est %*%
# exposures_est, censused against the cited line 0.969 -- under five
# arms: exact, stochastic-clean, artifakt (planted dictionary rotation),
# degenerate (zero-count column), and a deterministic corruption ladder.
# Every arm is driven through the EXPORTED face alone. The committed
# witness bytes under out/ are the verdict; a byte-rerun must reproduce
# them identically.
#
# Framing law: DECISION RECORD only. What this scenario records is the
# shipped flag's documented discriminative behavior on planted truth:
# clean reconstructions pass the line (hard rail share 1), the planted
# corruption fails it (hard rail share 0), the zero column speaks its NA
# bit, and the corruption ladder's last-pass rung is an OBSERVED,
# COMMITTED fact -- never a calibration claim. 0.969 is a cited upstream
# median, not an anchor, and cosine above it remains necessary-not-
# sufficient (R/ms-compare.R header; research-02).

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
SIG <- c("SBS1", "SBS2", "SBS13", "SBS88")
K <- 4L
N <- 8L
SAMPLES <- paste0("R", formatC(1:8, width = 2L, flag = "0"))
TOT <- c(1600, 1800, 2000, 2200, 2400, 2600, 3000, 3600)
W <- c(0.40, 0.25, 0.20, 0.15)                    # circulant per-sample weights
PLANT_SEED <- 9L
CMP_SEED <- 2L
NULL_N <- 200L
NULL_DRAWS <- 200L
COSINE_LINE <- 0.969
RUNGS <- c(0, 0.10, 0.18, 0.25, 0.32, 0.40, 0.50)
DEAD_COL <- 3L
ART_ROT <- c(2L, 3L, 4L, 1L)                       # planted dictionary rotation

verdict <- new.env(parent = emptyenv())
verdict$fail <- 0L
.check <- function(label, ok) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ")
  cat(label, "\n")
  if (!isTRUE(ok)) verdict$fail <- verdict$fail + 1L
  invisible(isTRUE(ok))
}

# -- shared constructions (mirrored byte-identically in the law test) ------
dict <- local({
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  d <- mat[, SIG, drop = FALSE]
  sweep(d, 2L, colSums(d), "/")
})

exposures <- local({
  E <- matrix(0, nrow = K, ncol = N, dimnames = list(SIG, SAMPLES))
  for (j in seq_len(N)) {
    idx <- ((seq_len(K) - 1L + (j - 1L)) %% K) + 1L
    E[, j] <- W[idx] * TOT[j]
  }
  E
})

exposures_wrong <- exposures[c(2L, 3L, 4L, 1L), , drop = FALSE]

ladder_exposures <- function(w) (1 - w) * exposures + w * exposures_wrong

exact_catalog <- local({
  f <- dict %*% exposures
  dimnames(f) <- list(rownames(dict), SAMPLES)
  f
})

plant <- ms_simulate(signatures = dict, exposures = exposures, seed = PLANT_SEED)

face <- function(estimated, reference, exposures_est, exposures_ref,
                 catalogs, signatures_est) {
  ms_compare(estimated, reference, metric = "cosine", protocol = "jiang",
             exposures_est = exposures_est, exposures_ref = exposures_ref,
             catalogs = catalogs, signatures_est = signatures_est,
             null_n = NULL_N, null_n_draws = NULL_DRAWS, seed = CMP_SEED)
}

payload <- function(cmp) cmp@jiang$reconstruction

per_rows <- data.frame()
arm_rows <- data.frame()
collect <- function(arm, cmp) {
  p <- payload(cmp)
  is_na <- as.integer(is.na(p$per_sample))
  pass <- as.integer(!is.na(p$per_sample) & p$per_sample > COSINE_LINE)
  per_rows <<- rbind(per_rows,
                     data.frame(sample = SAMPLES, arm = arm,
                                per_sample = as.numeric(p$per_sample),
                                is_na = is_na, pass = pass,
                                stringsAsFactors = FALSE))
  arm_rows <<- rbind(arm_rows,
                     data.frame(arm = arm,
                                cosine_line = as.numeric(p$cosine_line),
                                median_cosine = as.numeric(p$median_cosine),
                                share_reasonable = as.numeric(p$share_reasonable),
                                n_na = as.integer(sum(is_na)),
                                stringsAsFactors = FALSE))
  p
}

# ---------------------------------------------------------------------------
# 0. plant-quality gates: the roster must be distinguishable and the
#    exposure design must be full-support (the artifakt rail rests on both)
# ---------------------------------------------------------------------------
cat("== plant quality ==\n")
pn <- colSums(dict * dict)                                  # per-column norms squared
pco <- c()
for (a in 1:(K - 1L)) for (b in (a + 1L):K) {
  pco <- c(pco, sum(dict[, a] * dict[, b]) / sqrt(pn[a] * pn[b]))
}
max_pair <- max(pco)
.check("roster is pairwise distinguishable below the cited line", max_pair < COSINE_LINE)
.check("exposure design is full-support (every cell a strict fraction)",
       all(exposures > 0) && all(exposures < rep(TOT, each = K)))

# ---------------------------------------------------------------------------
# 1. the exact arm: the face reads its own linear expectation
# ---------------------------------------------------------------------------
cat("== exact arm ==\n")
p_exact <- collect("exact",
  face(dict, dict, exposures, exposures, exact_catalog, dict))
.check("exact arm: share_reasonable == 1 (hard rail)",
       identical(as.integer(p_exact$share_reasonable), 1L))

# ---------------------------------------------------------------------------
# 2. the stochastic clean arm at the frozen seed (+ determinism pair)
# ---------------------------------------------------------------------------
cat("== stochastic clean arm ==\n")
p_clean <- collect("clean",
  face(dict, dict, exposures, exposures, plant@counts, dict))
.check("clean arm: share_reasonable == 1 (hard rail)",
       identical(as.integer(p_clean$share_reasonable), 1L))
p_clean_b <- payload(face(dict, dict, exposures, exposures, plant@counts, dict))
same_seed <- identical(unname(p_clean$per_sample), unname(p_clean_b$per_sample))
.check("same seed reproduces the flag bytes", same_seed)
plant_b <- ms_simulate(signatures = dict, exposures = exposures,
                       seed = PLANT_SEED + 1L)
cross_seed <- !identical(unname(plant_b@counts), unname(plant@counts))
.check("a different seed draws a different cohort", cross_seed)

# ---------------------------------------------------------------------------
# 3. the artifakt arm: the planted dictionary rotation trips every sample
# ---------------------------------------------------------------------------
cat("== artifakt arm ==\n")
rot <- dict[, ART_ROT, drop = FALSE]
p_art <- collect("artifakt",
  face(rot, dict, exposures, exposures, exact_catalog, rot))
.check("artifakt arm: share_reasonable == 0 (hard rail)",
       identical(as.integer(p_art$share_reasonable), 0L))
.check("artifakt arm: median below the cited line",
       p_art$median_cosine < COSINE_LINE)

# ---------------------------------------------------------------------------
# 4. the degenerate arm: the zero-count column speaks its NA bit
# ---------------------------------------------------------------------------
cat("== degenerate arm ==\n")
dead <- exact_catalog
dead[, DEAD_COL] <- 0
p_deg <- collect("degenerate",
  face(dict, dict, exposures, exposures, dead, dict))
.check("degenerate arm: exactly one NA", identical(sum(is.na(p_deg$per_sample)), 1L))
.check("degenerate arm: NA sits at the planted column",
       isTRUE(is.na(p_deg$per_sample[DEAD_COL])))
.check("degenerate arm: survivors keep the clean verdict",
       identical(as.integer(p_deg$share_reasonable), 1L))

# ---------------------------------------------------------------------------
# 5. the corruption ladder: monotone decline, committed last-pass rung
# ---------------------------------------------------------------------------
cat("== corruption ladder ==\n")
lad <- data.frame()
for (w in RUNGS) {
  pw <- payload(face(dict, dict, ladder_exposures(w), exposures,
                     exact_catalog, dict))
  share <- as.numeric(pw$share_reasonable)
  lad <- rbind(lad, data.frame(rung = w, share_pass = share,
                               is_pass = as.integer(share == 1),
                               stringsAsFactors = FALSE))
}
.check("ladder rung 0 is the clean verdict", identical(lad$share_pass[1L], 1))
.check("ladder is monotone non-increasing in the corruption weight",
       all(diff(lad$share_pass) <= 0))
last_pass_rung <- if (any(lad$is_pass == 1L)) max(lad$rung[lad$is_pass == 1L]) else NA_real_()
cat(sprintf("  committed last-pass rung: %s (observed, never asserted)\n",
            if (is.na(last_pass_rung)) "NA" else format(last_pass_rung)))

# ---------------------------------------------------------------------------
# [attest] -- declined scope rails, made audible
# ---------------------------------------------------------------------------
cat("[attest] decision-record only: the flag's behavior on planted truth is\n")
cat("[attest]   an OBSERVED, COMMITTED record -- no calibration claims, no generalization.\n")
cat("[attest] 0.969 is a CITED upstream median, not an anchor (R/ms-compare.R\n")
cat("[attest]   header; research-02): cosine above it is necessary, not sufficient.\n")
cat("[attest] no estimation machinery added: no bootstrap, no intervals,\n")
cat("[attest]   no conformal framing (paper declined-word), no new faces.\n")
cat("[attest] the M3b sanity harness (R/calibrate-real.R) is NOT touched:\n")
cat("[attest]   sanity bytes never enter calibration standing.\n")
cat("[attest] dictionary from the bundled reference only (no downloads);\n")
cat("[attest]   the exported ms_compare face only (no internal-helper reach-in).\n")

# ---------------------------------------------------------------------------
# 6. the committed witnesses (finiteness censused here, pre-write)
# ---------------------------------------------------------------------------
ok_payload <- all(per_rows$pass %in% 0:1) && all(per_rows$is_na %in% 0:1) &&
  all(stats::na.omit(per_rows$per_sample) >= 0 &
        stats::na.omit(per_rows$per_sample) <= 1 + 4 * .Machine$double.eps) &&
  all(is.na(per_rows$per_sample) == (per_rows$is_na == 1L)) &&
  all(is.finite(arm_rows$median_cosine)) &&
  all(arm_rows$share_reasonable >= 0 & arm_rows$share_reasonable <= 1) &&
  all(is.finite(lad$share_pass))
if (!ok_payload) {
  cat("  FAIL witness payload census (refusing to commit an unlive column)\n")
  verdict$fail <- verdict$fail + 1L
}

dir.create(OUT, showWarnings = FALSE)
plant_df <- cbind(channel = as.character(rownames(plant@counts)),
                  as.data.frame(plant@counts))
write.csv(plant_df, file.path(OUT, "cs7_plant.csv"), row.names = FALSE)
write.csv(per_rows, file.path(OUT, "cs7_per_sample.csv"), row.names = FALSE)
write.csv(arm_rows, file.path(OUT, "cs7_arms.csv"), row.names = FALSE)
write.csv(lad, file.path(OUT, "cs7_ladder.csv"), row.names = FALSE)
write.csv(data.frame(
  cosine_line = COSINE_LINE,
  dict_roster = paste(SIG, collapse = ","),
  k = K, n_samples = N,
  totals = paste0(TOT, collapse = ","),
  weights = paste0(W, collapse = ","),
  plant_seed = PLANT_SEED, cmp_seed = CMP_SEED,
  null_n = NULL_N, null_n_draws = NULL_DRAWS,
  rung_values = paste0(RUNGS, collapse = ","),
  dead_col = DEAD_COL,
  last_pass_rung = if (is.na(last_pass_rung)) NA_character_ else format(last_pass_rung),
  stringsAsFactors = FALSE),
  file.path(OUT, "cs7_scalars.csv"), row.names = FALSE)
write.table(data.frame(
  check = c("same_seed_reproducible", "cross_seed_plant_differs",
            "artifakt_share_zero", "clean_share_one", "exact_share_one",
            "degenerate_n_na_one"),
  value = c(as.integer(same_seed), as.integer(cross_seed),
            as.integer(identical(as.integer(p_art$share_reasonable), 0L)),
            as.integer(identical(as.integer(p_clean$share_reasonable), 1L)),
            as.integer(identical(as.integer(p_exact$share_reasonable), 1L)),
            as.integer(identical(sum(is.na(p_deg$per_sample)), 1L))),
  stringsAsFactors = FALSE),
  file.path(OUT, "cs7_degenerates.tsv"), sep = "\t", quote = FALSE,
  row.names = FALSE, col.names = TRUE)

cat("== cs7 reconstruction-witness scenario: ",
    if (identical(verdict$fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " == (evidence: ", OUT, ")\n", sep = "")
quit(save = "no", status = if (identical(verdict$fail, 0L)) 0L else 1L)
