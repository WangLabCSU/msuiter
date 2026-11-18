# run_stratify.R -- the CS-5 hypermutator-stratify scenario (pillar 3).
#
# Mandate: adjudicate the certified SigProfiler-frozen stratification face
# (ms_stratify_hypermutants, R/stratify.R) against a self-planted synthetic
# cohort -- planted truth only (D3). The face is a faithful upstream
# replication under Framing-B (novelty-scan E9): this scenario demonstrates
# the decision pipeline, it claims no algorithmic originality for the cutoff
# rule, and it never speaks of exclusion or refit as done facts -- the object
# is the DECISION RECORD both M2 stages will consume (R/stratify.R:21-25).
# Declined scope rails [attest]-ed below; no diagnostic-grade (MUTYH/MSI/
# TMB-high) wording appears here or may be inferred from this evidence.
#
# The plant is pure arithmetic (no RNG): a 44-sample deterministic ramp plus
# six order-of-magnitude spikes; the frozen GMM/prune/cutoff rule then yields
# one deterministic verdict that a byte-rerun must reproduce identically.

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

SAMPLES <- paste0("ST", formatC(1:50, width = 2L, flag = "0"))
# Bulk: the face-proven jittered bimodal shape (test-stratify.R
# bimodal_cohort, x2 scale) -- certified-converging under the frozen EM
# tol; pure arithmetic, no RNG. Spikes: six far order-of-magnitude outliers.
BULK <- vapply(0:43L, function(i)
  8400 + 1400 * (i %% 13) + 260 * (i %% 7) + 80 * (i %% 3), numeric(1))
SPIKES <- 81000 + c(0, 15000, 39000, 52000, 64000, 77000)
TOTALS <- setNames(as.numeric(c(BULK, SPIKES)), SAMPLES)
PLANTED_HYPER <- SAMPLES[45:50]

FB_SAMPLES <- paste0("FB", formatC(1:6, width = 2L, flag = "0"))
FB_TOTALS <- setNames(as.numeric(c(9999L, 10000L, 10000L, 10001L,
                                   20000L, 20001L)), FB_SAMPLES)
FB_MANUAL <- 20000L                        # dominates the near-unimodal derived rule
DG_TOTALS <- setNames(rep(777, 6), paste0("SD", 1:6))

verdict <- new.env(parent = emptyenv())
verdict$fail <- 0L
.check <- function(label, ok) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ")
  cat(label, "\n")
  if (!isTRUE(ok)) verdict$fail <- verdict$fail + 1L
  invisible(isTRUE(ok))
}

# ---------------------------------------------------------------------------
# 1. the primary adjudication: planted hypermutants at recall/precision 1
# ---------------------------------------------------------------------------
st <- ms_stratify_hypermutants(TOTALS, seed = 1)
.check("face reports the 50-sample cohort",
       length(st@totals) == 50L)
.check("planted roster caught at recall/precision 1",
       identical(st@hyper, PLANTED_HYPER) && identical(st@n_hyper, 6))
.check("partition is disjoint-exhaustive",
       setequal(c(st@hyper, st@nonhyper), SAMPLES) &&
         identical(intersect(st@hyper, st@nonhyper), character(0)))
.check("strict-greater rule holds row by row",
       all(st@totals[st@hyper] > st@cutoff) &&
         all(st@totals[st@nonhyper] <= st@cutoff))
.check("decision record carries the frozen policy",
       identical(st@policy, "exclude_de_novo_then_refit") &&
         isTRUE(st@gmm$converged))

# 2. the protocol twin re-derives the kernel's verdict byte for byte
twin <- msuiter:::msuiter_stratify_twin(as.numeric(TOTALS), 0, 1)
.check("twin and face agree on cutoff and roster (integer verdicts)",
       identical(twin$cutoff, st@cutoff) &&
         identical(twin$hypermutant_idx,
                  which(names(TOTALS) %in% st@hyper) - 1L))

# 3. seed invariance across the certified range
seeds_ok <- TRUE
for (s in 2:8) {
  stx <- ms_stratify_hypermutants(TOTALS, seed = s)
  seeds_ok <- seeds_ok && identical(stx@cutoff, st@cutoff) &&
    identical(stx@hyper, st@hyper)
}
.check("verdict is seed-invariant over seeds 1..8", seeds_ok)

# 4. the manual floor re-adjudicates; the boundary is strict
fb_fl <- ms_stratify_hypermutants(FB_TOTALS, manual_cutoff = FB_MANUAL, seed = 1)
fb_in <- ms_stratify_hypermutants(FB_TOTALS, manual_cutoff = 0, seed = 1)
.check("floored regime pins the cutoff to the manual floor",
       identical(fb_fl@cutoff, as.numeric(FB_MANUAL)))
.check("boundary is strict: ==floor nonhyper, floor+1 hyper",
       identical(fb_fl@hyper, "FB06") && "FB05" %in% fb_fl@nonhyper)
.check("inert floor lets the derived rule separate the outliers",
       fb_in@cutoff < FB_MANUAL && setequal(fb_in@hyper, c("FB05", "FB06")))

# 5. catalog and totals paths deliver one verdict
lab <- as.character(msuiter:::.ms_io_channel_tables()$SBS96)
mat <- matrix(1L, nrow = 96L, ncol = 50L, dimnames = list(lab, SAMPLES))
mat[1L, ] <- as.integer(TOTALS) - 95L
cat1 <- ms_catalog(mat, list(name = "SBS96", labels = lab), SAMPLES,
                   provenance = list(genome = "GRCh37"))
st_cat <- ms_stratify_hypermutants(cat1, seed = 1)
.check("catalog path and totals path agree on the verdict",
       identical(st_cat@cutoff, st@cutoff) &&
         identical(st_cat@hyper, st@hyper))

# 6. the certified silence and degenerate branches
uni <- setNames(as.numeric(12000L + 130L * (0:19)),
                paste0("SU", formatC(1:20, width = 2L, flag = "0")))
st_uni <- ms_stratify_hypermutants(uni, seed = 1)
.check("unimodal cohort speaks silence (zero hypermutants)",
       identical(as.integer(st_uni@n_hyper), 0L) &&
         identical(st_uni@hyper, character(0)))
st_dg <- ms_stratify_hypermutants(DG_TOTALS, seed = 1)
.check("all-identical cohort speaks the degenerate branch (cutoff == value)",
       identical(st_dg@cutoff, 777) &&
         identical(as.integer(st_dg@n_hyper), 0L))

# ---------------------------------------------------------------------------
# committed evidence (DS-3 gallery auto-admits; byte-stable by construction)
# ---------------------------------------------------------------------------
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
write.table(data.frame(sample = SAMPLES, total = as.integer(TOTALS),
                       planted_hyper = as.integer(SAMPLES %in% PLANTED_HYPER),
                       stringsAsFactors = FALSE),
            file.path(OUT, "stratify_plant_totals.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)
write.csv(data.frame(sample = SAMPLES,
                     total = as.integer(unname(TOTALS[SAMPLES])),
                     is_hyper = as.integer(SAMPLES %in% st@hyper),
                     stringsAsFactors = FALSE),
          file.path(OUT, "stratify_partition.csv"), row.names = FALSE)
write.csv(data.frame(
  cutoff = st@cutoff, n_hyper = st@n_hyper, n_nonhyper = st@n_nonhyper,
  retained_mean = st@gmm$retained_mean, retained_sd = st@gmm$retained_sd,
  retained_n = st@gmm$retained_n, n_fits = st@gmm$n_fits,
  converged = st@gmm$converged, policy = st@policy, seed = st@seed),
  file.path(OUT, "stratify_scalars.csv"), row.names = FALSE)
write.csv(data.frame(
  regime = rep(c("floored", "inert"), each = 6L),
  sample = rep(FB_SAMPLES, 2L),
  total = as.integer(unname(rep(TOTALS[FB_SAMPLES], 2L))),
  manual_cutoff = rep(c(FB_MANUAL, 0L), each = 6L),
  is_hyper = as.integer(c(FB_SAMPLES %in% fb_fl@hyper,
                          FB_SAMPLES %in% fb_in@hyper)),
  stringsAsFactors = FALSE),
  file.path(OUT, "stratify_floor.csv"), row.names = FALSE)
write.csv(data.frame(cohort = "degenerate", cutoff = st_dg@cutoff,
                     n_hyper = st_dg@n_hyper, converged = st_dg@gmm$converged,
                     policy = st_dg@policy),
          file.path(OUT, "stratify_degenerate.csv"), row.names = FALSE)

cat("[attest] decision-record scope: the object is the stratification DECISION RECORD;\n",
    "         exclusion/refit execution is M2 and is not claimed here.\n", sep = "")
cat("[attest] framing scope: faithful upstream replication (Framing-B); no algorithmic\n",
    "         originality claimed for the cutoff rule (novelty-scan E9).\n", sep = "")
cat("[attest] declined scope: no diagnostic-grade (MUTYH/MSI/TMB-high) claims; no NA/dead\n",
    "         branch (none exists in this face); no majority-high cohort (upstream\n",
    "         certified failure mode, GMM memo :86).\n", sep = "")

if (verdict$fail == 0L) {
  cat("VERIFIED: CS-5 stratify scenario -- planted roster at recall 1, twin parity,\n",
      "         strict boundary, certified silence/degenerate branches.\n", sep = "")
  cat("OVERALL PASS\n")
  quit(status = 0)
} else {
  cat("OVERALL FAIL (", verdict$fail, " adjudications)\n", sep = "")
  quit(status = 1)
}
