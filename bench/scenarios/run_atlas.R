#!/usr/bin/env Rscript
# bench/scenarios/run_atlas.R -- the executable atlas-mode scenario
# (Phase-8 CS-1; docs/research/03-applications.md section 1). Drives the five
# variant classes through the public ingestion face, adjudicates the pipeline
# against the a-priori generator truth and persists the evidence tables under
# bench/scenarios/out/. Verdict discipline: every claim is measured here, the
# final line is OVERALL PASS or OVERALL FAIL.

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
source(file.path(ROOT, "tests", "testthat", "helper-tally.R"))
source(file.path(ROOT, "tests", "testthat", "helper-atlas.R"))

.messages <- character()
.message <- function(...) {
  line <- paste0(...)
  .messages <<- c(.messages, line)
  cat(line, "\n")
}
verdict <- TRUE
.check <- function(label, ok) {
  if (!isTRUE(ok)) {
    verdict <<- FALSE
    .message("[FAIL] ", label)
  } else {
    .message("[ ok ] ", label)
  }
}

.message("== atlas-mode scenario: start ==")
fx <- .atlas_cohort(dir = file.path(OUT, "fixture"))
truth <- fx$truth
.message("cohort: samples=", length(truth$samples),
         " planted=", paste(.ATLAS_PLANTED, collapse = ","))

# ---- class ingestion ------------------------------------------------------
mv <- ms_variants(fx$variants, genome = "synth", caller = "atlas-synth",
                  matched_normal = "none")
.check("MsVariants ingests the SBS/DBS record table",
       S7::S7_inherits(mv, MsVariants) && nrow(mv@table) == nrow(fx$variants))
mv_all <- ms_variants(rbind(fx$variants, fx$id_records), genome = "synth",
                      caller = "atlas-synth", matched_normal = "none")
.check("ID carriers pass the same validator",
       nrow(mv_all@table) == nrow(fx$variants) + nrow(fx$id_records))
cn_path <- file.path(OUT, "synth-cn.tsv")
write.table(fx$cn_table, cn_path, sep = "\t", quote = FALSE,
            row.names = FALSE, col.names = TRUE)
segs <- ms_segments(cn_path, caller = "PCAWG")
.check("CN segments parse through the io face",
       nrow(segs) == 2L * length(truth$samples))
sv <- ms_sv(fx$sv_table)
.check("SV breakpoints parse through the io face",
       nrow(sv) == length(truth$samples) && all(sv$svtype == "deletion"))

# ---- tallies and count contracts -----------------------------------------
cat_sbs <- ms_tally(mv, genome = fx$twobit, mode = "SBS96")
cat_dbs <- ms_tally(mv, genome = fx$twobit, mode = "DBS78")
write.csv(as.data.frame(cat_sbs@counts), file.path(OUT, "counts_sbs.csv"))
write.csv(as.data.frame(cat_dbs@counts), file.path(OUT, "counts_dbs.csv"))
.check("SBS96 tallies the emitted plan exactly",
       identical(rowSums(cat_sbs@counts)[truth$sbs_labels],
                 colSums(truth$sbs_plan)) &&
         identical(colSums(cat_sbs@counts)[truth$samples],
                   rowSums(truth$sbs_plan)))
.check("DBS78 tallies the emitted plan exactly",
       identical(rowSums(cat_dbs@counts)[truth$dbs_labels],
                 colSums(truth$dbs_plan)) &&
         identical(colSums(cat_dbs@counts)[truth$samples],
                   rowSums(truth$dbs_plan)))
.message("[attest] ID83: no public ms_tally mode exists (roster modes: ",
         paste0(msuiter:::.ms_tally_modes, collapse = ", "),
         "); ID class is ingested, not tallied -- declared gap")
.message("[attest] CN/SV: segment io validated; no public segment tally face --",
         " declared gap (fit path stays SBS96)")

# ---- QC --------------------------------------------------------------------
qc <- ms_qc_report(cat_sbs)
write.csv(qc, file.path(OUT, "qc_report.csv"), row.names = FALSE)
.check("QC speaks the sanctioned vocabularies",
       all(qc$burden_class %in% c("dead", "low", "standard", "high")) &&
         all(qc$qc_flag %in% c("ok", "watch", "artifact")))

# ---- de novo extraction and hungarian fidelity ---------------------------
ex <- ms_extract(cat_sbs, k = length(.ATLAS_PLANTED))
S <- ex@signatures
S <- S[truth$sbs_labels, , drop = FALSE] # labels are the only legal key
refdb <- ms_refdb_bundled(build = "GRCh37")
mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
truth_mat <- mat[, .ATLAS_PLANTED, drop = FALSE]
cmp <- ms_compare(estimated = S, reference = truth_mat,
                   protocol = "hungarian", thresholds = c(0.7, 0.8, 0.9))
sw <- cmp@hungarian
write.csv(sw, file.path(OUT, "compare_sweep.csv"), row.names = FALSE)
.message("hungarian sweep: ", paste0(sprintf("tau=%.1f recall=%.2f f1=%.2f",
  sw$tau, sw$recall, sw$f1), collapse = "  "))
.check("hungarian recall is complete at tau=0.8",
       sw$recall[sw$tau == 0.8] == 1)

# ---- mixed refit: purity, prevalence, association ------------------------
decocs <- head(setdiff(colnames(mat), .ATLAS_PLANTED), 8L)
wide <- mat[, c(.ATLAS_PLANTED, decocs), drop = FALSE]
fit <- ms_fit(cat_sbs, wide, method = "nnls")
E <- fit@exposures
pbr <- colSums(E[.ATLAS_PLANTED, , drop = FALSE]) / colSums(E)
write.csv(data.frame(sample = colnames(E), pbr = unname(pbr),
                    n = unname(colSums(E))),
          file.path(OUT, "pbr.csv"), row.names = FALSE)
.message("purity: min PBR=", sprintf("%.4f", min(pbr)))
.check("planted purity PBR >= 0.90 in every sample", all(pbr >= 0.90))
prevalence <- rowSums(E > 0) / ncol(E)
common_hits <- names(prevalence)[prevalence > 0.5]
write.csv(as.data.frame(prevalence), file.path(OUT, "prevalence.csv"))
.check("common leg classified common", all(.ATLAS_COMMON %in% common_hits))
.check("rare leg stays rare", !any(.ATLAS_RARE %in% common_hits))
tst <- ms_exposure_test(E, groups = truth$arm, alpha = 0.05)
write.csv(tst, file.path(OUT, "association.csv"), row.names = FALSE)
.message("association: SBS5 pass_bh=",
         as.character(tst$pass_bh[tst$signature == "SBS5"]),
         " p=", sprintf("%.2g", tst$p_raw[tst$signature == "SBS5"]))
.check("planted arm differential is adjudicated",
       isTRUE(tst$pass_bh[tst$signature == "SBS5"]))
.check("decoy control stays negative",
       !isTRUE(tst$pass_bh[tst$signature == decocs[[1]]]))

# ---- presence face (observed, attested) -----------------------------------
pres <- tryCatch(ms_test_presence(cat_sbs, signatures = truth_mat),
                 error = function(e) e)
if (inherits(pres, "error")) {
  .message("[attest] ms_test_presence declined: ",
            sub("\n", " ", conditionMessage(pres)))
} else {
  write.csv(pres, file.path(OUT, "presence.csv"), row.names = FALSE)
  .message("presence face delivered ", nrow(pres), " rows")
}

.message("== atlas-mode scenario: ", if (verdict) "OVERALL PASS" else "OVERALL FAIL",
         " == (evidence: ", OUT, ")")
quit(save = "no", status = if (verdict) 0L else 1L)
