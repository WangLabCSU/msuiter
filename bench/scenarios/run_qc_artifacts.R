#!/usr/bin/env Rscript
# run_qc_artifacts.R: CS-4 artifact-forensics scenario (pillar 3, the
# built-in artifact-aware QC face -- research-03 §3/§7: the mechanism
# sentries and the artifact-roster share replace the ad-hoc external
# filtering the field pain-points). Plants a self-built 13-sample
# synthetic cohort on pure arithmetic (no RNG): four oxoG-reading (C>A)
# spiked samples, four FFPE-deamination (C>T) spiked samples, four clean
# samples and one dead zero-total sample; four of the samples carry
# roster-inflated fitted exposures over a roster-named refit dictionary.
# The certified committed faces (ms_qc_sentries / ms_qc_roster_share /
# ms_qc_provenance, over the R/ms-qc-report.R core) must catch exactly the
# planted sets -- recall 1 on both spike families, measured silence on the
# clean and sub-threshold branches, the NA branch on the dead sample.
# D3: planted truth only; zero COSMIC matrices. Framing law (novelty-scan
# R6): methods-demonstration; the declined Degasperi amber/red tiering and
# any diagnostic-grade (MUTYH/MSI) claim are out of scope by law
# (R/ms-qc-sentries.R:13-20 declined list). The law test reads the
# committed bytes and re-derives them through the public faces.

.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  if (length(f) > 0L) dirname(normalizePath(f[[1L]])) else normalizePath(getwd())
}
ROOT <- dirname(dirname(.script_dir()))
OUT <- file.path(ROOT, "bench", "scenarios", "out")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(file.path(ROOT, "R"))) {
  suppressWarnings(suppressMessages(pkgload::load_all(ROOT, quiet = TRUE)))
} else {
  library(msuiter)
}

SAMPLES <- paste0("QC", formatC(1:13, width = 2L, flag = "0"))
GT_PLANTED <- SAMPLES[1:4]
CT_PLANTED <- SAMPLES[5:8]
CLEAN <- SAMPLES[9:12]
DEAD <- SAMPLES[13L]
ROSTER_PLANTED <- SAMPLES[1:4]
BURDEN_BASE <- 1200          # the certified standard-burden house scale
SPIKE_MASS <- 100L           # per guarded channel; 16 channels => +1600
ROSTER_RHO <- c(0.50, 0.25, 0.10, 0.06,   # injected (>= the frozen 0.05)
                0.02, 0.02, 0.00, 0.00,   # sub-threshold / zero controls
                0.02, 0.00, 0.00, 0.00,   # clean-side roster controls
                0.00)                      # dead sample

LABELS <- as.character(msuiter:::.ms_io_channel_tables()$SBS96)
FAM <- sub("^[ACGT]\\[([AC]>[ACGT])\\][ACGT]$", "\\1", LABELS)
GT_IDX <- which(FAM == "C>A")
CT_IDX <- which(FAM == "C>T")

# Clean non-artifact dictionary (SBS1/SBS5/SBS13 real COSMIC references,
# none on the 19-entry artifact roster): every guarded-family share stays
# at most 1/6, far below the frozen 0.30/0.40 lines, so any sentinel hit
# on the clean branch is a genuine false positive.
clean_matrix <- function(mults) {
  v <- rep(1, 96L)
  for (f in names(mults)) v[FAM == f] <- mults[[f]]
  v / sum(v)
}
CLEAN_SIGS <- do.call(cbind, list(
  clean_matrix(c("C>A" = 3, "C>G" = 3, "C>T" = 3, "T>A" = 3, "T>C" = 3, "T>G" = 3)),
  clean_matrix(c("C>G" = 6)),
  clean_matrix(c("T>G" = 6))))
dimnames(CLEAN_SIGS) <- list(LABELS, c("SBS1", "SBS5", "SBS13"))
PATS <- rbind(
  c(1, 0, 0), c(0, 1, 0), c(0, 0, 1), c(1 / 3, 1 / 3, 1 / 3),
  c(0.8, 0.1, 0.1), c(0.1, 0.8, 0.1), c(0.1, 0.1, 0.8),
  c(0.5, 0.5, 0), c(0.5, 0, 0.5), c(0, 0.5, 0.5),
  c(0.6, 0.2, 0.2), c(0.2, 0.6, 0.2))

build_counts <- function() {
  base <- round(CLEAN_SIGS %*% t(PATS) * BURDEN_BASE)
  base <- matrix(as.integer(base), nrow = 96L,
                 dimnames = list(LABELS, SAMPLES[1:12]))
  base[GT_IDX, GT_PLANTED] <- base[GT_IDX, GT_PLANTED] + SPIKE_MASS
  base[CT_IDX, CT_PLANTED] <- base[CT_IDX, CT_PLANTED] + SPIKE_MASS
  cbind(base, QC13 = 0L)
}

# Roster-named refit dictionary (SBS43 plain, SBS45b exercises the stem
# match) and the planted count-scale exposures: the rho mass rides the two
# roster columns exactly at the planted shares.
build_dict <- function() {
  m <- matrix(0, nrow = 96L, ncol = 4L,
              dimnames = list(LABELS, c("SBS1", "SBS5", "SBS43", "SBS45b")))
  m[FAM == "C>G", 1L] <- 6
  m[FAM == "T>G", 2L] <- 6
  m[FAM == "C>A", 3L] <- 6
  m[FAM == "T>A", 4L] <- 6
  sweep(m, 2L, colSums(m), "/")
}
build_exposures <- function() {
  other <- 1 - ROSTER_RHO
  e <- rbind(SBS1 = other * 0.6, SBS5 = other * 0.4,
             SBS43 = ROSTER_RHO * 0.6, `SBS45b` = ROSTER_RHO * 0.4)
  dimnames(e) <- list(c("SBS1", "SBS5", "SBS43", "SBS45b"), SAMPLES)
  e
}

verdict <- TRUE
.check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (!ok) verdict <<- FALSE
  cat(sprintf("[%s] %s\n", if (ok) " ok " else "FAIL", label))
}

counts <- build_counts()
CAT <- ms_catalog(counts, list(name = "SBS96", labels = LABELS), SAMPLES,
                  provenance = list(genome = "GRCh37"))
sen <- ms_qc_sentries(CAT)
sh <- ms_qc_roster_share(CAT, build_dict(), build_exposures())
prov <- ms_qc_provenance(CAT)
bur <- ms_qc_burden(CAT)
ros <- ms_qc_artifact_roster()
chn <- ms_qc_mechanism_channels()

.check("oxoG sentinel catches exactly the four planted C>A-spiked samples",
       identical(sort(sen$sample[sen$gt_verdict == "hit"]), sort(GT_PLANTED)))
.check("FFPE sentinel watches exactly the four planted C>T-spiked samples",
       identical(sort(sen$sample[sen$ct_verdict == "watch"]), sort(CT_PLANTED)))
.clean_rows <- sen[sen$sample %in% c(CLEAN, DEAD), , drop = FALSE]
.check("clean and dead branches speak measured silence (zero sentinel hits)",
       !any(.clean_rows$gt_verdict == "hit") && !any(.clean_rows$ct_verdict == "watch"))
.check("the dead sample speaks the certified NA branch on both sentinels",
       identical(sen$gt_verdict[sen$sample == DEAD], "na") &&
         identical(sen$ct_verdict[sen$sample == DEAD], "na"))
.check("artifact roster share hits exactly the four planted rho >= 0.05 samples",
       identical(sort(sh$sample[sh$artifact_flag == "hit"]), sort(ROSTER_PLANTED)))
.check("every roster hit names a planted roster signature (SBS43 or SBS45b)",
       all(grepl("SBS43", sh$artifact_sigs[sh$artifact_flag == "hit"], fixed = TRUE) |
           grepl("SBS45b", sh$artifact_sigs[sh$artifact_flag == "hit"], fixed = TRUE)))
.check("the certified constants hold (0.30 gt flag, 0.40 ct watch, 0.05 roster flag)",
       identical(unname(unlist(msuiter:::.ms_qc_defaults[c("gt_share_flag",
         "ct_share_watch", "artifact_share_flag")])),
         unname(c(gt_share_flag = 0.30, ct_share_watch = 0.40,
                  artifact_share_flag = 0.05))))
.check("the provenance checklist carries the eight frozen rows and no failure",
       identical(prov$check, c("catalog.class", "channel.space", "provenance.genome",
         "provenance.keys", "refdb.pin", "roster.pin", "thresholds.declared",
         "msuiter.version")) && !any(prov$status == "fail"))
.check("the frozen artifact roster and mechanism-channel rosters ride on-scene",
       identical(nrow(ros), 19L) && identical(nrow(chn), 32L) &&
         identical(sum(chn$mechanism == "oxoG"), 16L) &&
         identical(sum(chn$mechanism == "ffpe"), 16L) &&
         all(c("SBS43", "SBS45") %in% ros$name))
cat("[attest] scope: built-in certified QC faces only; the declined Degasperi\n")
cat("[attest]   amber/red tiering and diagnostic-grade (MUTYH/MSI) claims are OUT of\n")
cat("[attest]   scope by the R/ms-qc-sentries.R declined list and novelty-scan R6.\n")
cat(sprintf("[attest] burden face exercised on-scene (classes %s); the certified\n",
            paste(unique(bur$burden_class), collapse = "/")))
cat("[attest]   ms_qc_report() remains the aggregate face -- this scenario rides\n")
cat("[attest]   its certified siblings, never a second implementation.\n")

sentries_wit <- data.frame(
  sample = sen$sample, gt_share = sen$gt_share, ct_share = sen$ct_share,
  gt_verdict = sen$gt_verdict, ct_verdict = sen$ct_verdict,
  qc_flag = sen$qc_flag,
  planted_family = c(rep("gt", 4L), rep("ct", 4L), rep("clean", 4L), "dead"),
  stringsAsFactors = FALSE)
share_wit <- data.frame(
  sample = sh$sample, exposure_total = sh$exposure_total,
  artifact_share = sh$artifact_share, artifact_sigs = sh$artifact_sigs,
  artifact_flag = sh$artifact_flag,
  planted_roster_hit = as.integer(sh$sample %in% ROSTER_PLANTED),
  stringsAsFactors = FALSE)
prov_wit <- data.frame(check = prov$check, status = prov$status,
                       value = prov$value, stringsAsFactors = FALSE)

write.table(data.frame(label = LABELS, counts, check.names = TRUE,
                       stringsAsFactors = FALSE),
            file.path(OUT, "qc_plant_counts.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
dict <- build_dict()
write.table(data.frame(label = LABELS, dict, check.names = TRUE,
                       stringsAsFactors = FALSE),
            file.path(OUT, "qc_plant_dict.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
expo <- build_exposures()
write.table(data.frame(sig = rownames(expo), expo, check.names = TRUE,
                       stringsAsFactors = FALSE),
            file.path(OUT, "qc_plant_exposures.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
write.csv(sentries_wit, file.path(OUT, "qc_sentries.csv"), row.names = FALSE)
write.csv(share_wit, file.path(OUT, "qc_artifact_share.csv"), row.names = FALSE)
write.csv(prov_wit, file.path(OUT, "qc_provenance.csv"), row.names = FALSE)

cat(sprintf("== QC artifacts: %s (plant=13 sentries=%d share=%d provenance=%d)\n",
            if (verdict) "VERIFIED" else "DEFECT", nrow(sentries_wit),
            nrow(share_wit), nrow(prov_wit)))
cat(if (verdict) "OVERALL PASS\n" else "OVERALL FAIL\n")
quit(save = "no", status = if (verdict) 0L else 1L)
