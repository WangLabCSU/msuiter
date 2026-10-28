#!/usr/bin/env Rscript
# bench/scenarios/run_treatment.R -- the executable treatment-forensics
# scenario (Phase-8 CS-3; docs/research/03-applications.md section 3: the
# differentiation claim that no mainstream tool offers a treatment-history
# reporting module). Adjudicates the governed therapy classes against the
# officially recognised signatures and the clonal/subclonal timing split on
# the synthetic planted cohort; the design memo
# docs/devlog/2026-10-28-p8-treatment-forensics-design.md owns the contracts.

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
source(file.path(ROOT, "tests", "testthat", "helper-treatment.R"))

verdict <- TRUE
.check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (!ok) verdict <<- FALSE
  cat(sprintf("[%s] %s\n", if (ok) " ok " else "FAIL", label))
}
cat("== treatment-forensics scenario: start ==\n")

fx <- .ms_trt_cohort()
sigs <- sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE)))
clon <- expand.grid(sample = fx$samples, signature = sigs)
clon <- clon[c("sample", "signature")]
clon$clonal_fraction <- 0.5
rep1 <- ms_treatment_report(fx$catalog, fx$treatments, clonality = clon,
                            n_boot = 200, seed = 7)
tab <- as.data.frame(rep1)
tim <- attr(rep1, "timing")
write.csv(tab, file.path(OUT, "treatment_association.csv"), row.names = FALSE)
write.csv(tim, file.path(OUT, "treatment_timing.csv"), row.names = FALSE)
cat(sprintf("association rows=%d, timing rows=%d\n", nrow(tab), nrow(tim)))

truth <- vapply(seq_len(nrow(tab)), function(i)
  fx$planted_truth(tab$treatment[i], tab$signature[i]), logical(1))
.check("planted fidelity: exactly the planted cells associate",
       identical(tab$is_associated, truth))
planted_rows <- which(truth)
cat(sprintf("margin: min planted contrast_lower=%.1f, max non-planted=%.1f\n",
            min(tab$contrast_lower[planted_rows]),
            max(tab$contrast_lower[-planted_rows])))
.check("planted contrasts clear the adjudication floor",
       all(tab$contrast_lower[planted_rows] > msuiter:::.MS_TRT_ASSOC_FLOOR))
m <- match(paste(tim$treatment, tim$signature),
           paste(tab$treatment, tab$signature))
.check("timing split is additive on the association means",
       all(abs(tim$exposure_pre + tim$exposure_post - tab$mean_exposed[m]) < 1e-9))
b <- ms_treatment_report(fx$catalog, fx$treatments, clonality = clon,
                          n_boot = 200, seed = 7)
.check("seeded reruns are byte-identical",
       identical(as.data.frame(b), tab) && identical(attr(b, "timing"), tim))
printed <- paste(capture.output(print(rep1)), collapse = "\n")
.check("print face speaks provenance, ledger and tables",
       grepl("<msuiter treatment report>", printed, fixed = TRUE) &&
         grepl("association=full", printed, fixed = TRUE))
prov <- attr(rep1, "provenance")
cat(sprintf("provenance: refdb=%s build=%s method=%s n_boot=%d seed=%d\n",
            prov$refdb_version, prov$build, prov$method, prov$n_boot, prov$seed))
cat(sprintf("[attest] ID/SV treatment fitting: no public ID83/CN/SV tally or fit path -- SBS96-only face (declared gap)\n"))
cat(sprintf("[attest] longitudinal relapse-pair differencing: needs a paired fit-delta face (named follow-up, not fabricated)\n"))
cat(sprintf("== treatment-forensics scenario: %s == (evidence: %s)\n",
            if (verdict) "OVERALL PASS" else "OVERALL FAIL", OUT))
quit(save = "no", status = if (verdict) 0L else 1L)
