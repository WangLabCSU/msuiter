# run_kselect_witness.R -- the CS-20 kselect-witness scenario (pillar 3).
#
# Mandate: plant synthetic K-selection calls (the D3 law: zero COSMIC
# numeric matrices, zero real-data bytes, zero downloads -- the catalogs ride
# only as synthetic count matrices over synthetic channel labels) and
# adjudicate the EXPORTED ms_select_k() face: the eight-arm gate ladder
# (dots, grid shape, grid bound, dispatch, cv, k-folds, the veto-undecidable
# abort), the accepted arbitration renders, the six precedence discriminators
# with their anti anchors, the boundary contrast pairs and the acceptance
# specs. Every arm is driven through the exported face alone; the accepted
# returns, the abort classes and the fired clauses are the face's own. The
# scenario consumes no RNG, no network and no clock at the adjudication core
# (the FFI seed argument is a face argument, not a draw from R's stream); the
# benchmark runner and the DECLINED calibration family are never invoked here.
#
# Framing law: DECISION RECORD only. The witnesses under out/ are the
# committed verdict of what the shipped face SAID on planted truth. Float
# posture (D11): the evidence frame carries real deviance/stability columns
# whose last bits are ill-conditioned, so no float payload rides any witness
# -- the accepted render commits DISCRETE glyphs (argmin/veto/selected as
# 0/1), a digit-scrubbed clause and an all-NA n_seeds_converged glyph (the
# placeholder documented on the face); integer, label, logical, class and
# clause bytes are byte-committed.
#
# Rails: this runner carries the same frozen block as the law file
# (tests/testthat/test-scenario-kselect-witness.R), injected byte-identically
# from one minted source; every observed class, clause, shape and precedence
# order is rail-checked AS WE GO -- a drift fails the run before any witness
# is written. The witness bytes are written only after every payload census
# speaks; a byte-rerun must reproduce them identically.

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
stopif <- function(cond, msg) if (isTRUE(cond)) stop(msg, call. = FALSE)
## RNG-STATE-RAIL: the adjudication core must never seed or consume RNG;
## the purity verdict rides the scalars witness (committed bytes below).
rng0 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
## <<CS20-FROZEN-BEGIN>>  (minted mechanically from the audited ledger
##    2026-11-25; DO NOT hand-edit: regenerate via cs20-mint3.R) ##
.CS20_LAW_ARMS <- c("L1-dots-unknown", "L2-grid-nonnumeric", "L3-grid-zero", "L4-grid-over-bound", "L5-dispatch-noncatalog", "L6-cv-bad", "L7-kfolds-over-channels", "L8-undecidable")
.CS20_LAW_CLS <- c("msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_kselect")
.CS20_LAW_CLAUSES <- list()
.CS20_LAW_CLAUSES[["L1-dots-unknown"]] <- "unknown argument passed to ms_select_k() | ms_select_k() has no passthrough arguments | unexpected: 'bogus' | check the argument spelling against ?ms_select_k"
.CS20_LAW_CLAUSES[["L2-grid-nonnumeric"]] <- "k_grid must be positive whole numbers | the grid enumerates the candidate signature counts to arbitrate | received: 'x' | pass e.g. k_grid = #:#"
.CS20_LAW_CLAUSES[["L3-grid-zero"]] <- "k_grid must be positive whole numbers | the grid enumerates the candidate signature counts to arbitrate | received: '#', '#' | pass e.g. k_grid = #:#"
.CS20_LAW_CLAUSES[["L4-grid-over-bound"]] <- "every k in k_grid must not exceed min(channels, samples) = # | a rank-k NMF needs k <= min(nrow(counts), ncol(counts)) | offending k: '##', '##', '##', '##', '##', '##', '##', '##', '##', '##', ... (## total) (catalog has ## channels x # samples) | drop the offending ranks from the grid"
.CS20_LAW_CLAUSES[["L5-dispatch-noncatalog"]] <- "catalog must be an MsCatalog object | ms_select_k() dispatches on MsCatalog | received: integer | build the catalog with ms_tally() first"
.CS20_LAW_CLAUSES[["L6-cv-bad"]] <- "cv must be a single TRUE or FALSE | cv switches the SUITOR argmin layer (layer #) of the arbitration | received: 'NA' | pass cv = TRUE (default) or cv = FALSE (veto-only arbitration)"
.CS20_LAW_CLAUSES[["L7-kfolds-over-channels"]] <- "k_folds must not exceed the channel count (##) | every fold must hold out at least one row per column (SUITOR precondition) | k_folds = ###, catalog has ## channels | lower k_folds"
.CS20_LAW_CLAUSES[["L8-undecidable"]] <- "K selection is undecidable: no rank in the grid passes the stability veto | layer-# veto (avg >= #.#, min_cluster >= #.#, sum >= #.#) rejected every candidate rank | veto reasons: k=#: avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#; k=#: avg_stability #.#### < #.#; k=#: avg_stability #.### < #.#; avg + min_cluster_stability #.### < #.# | inspect the attached k_evidence table (condition field), widen the rank grid, or raise the replicate count"
.CS20_SPEC_ARMS <- c("A1-grid-2:5", "A2-grid-2:3", "A3-grid-3", "A4-grid-2:9", "A5-cv-false", "A6-arg-order", "A7-grid-unsorted", "A8-grid-dup")
.CS20_SPEC_CLS <- c("list", "list", "list", "list", "list", "list", "list", "list")
.CS20_SPEC_DETAILS <- list()
.CS20_SPEC_DETAILS[["A1-grid-2:5"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|4|2,3,4,5|0,1,0,0|0,1,0,0|0,1,0,0|N,N,N,N|5,5,5,5|2,3,4,5|avg_stability #.### < #.#;;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.## < #.#; avg + min_cluster_stability -#.#### < #.#"
.CS20_SPEC_DETAILS[["A2-grid-2:3"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_SPEC_DETAILS[["A3-grid-3"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|1|3|1|1|1|N|4|3|"
.CS20_SPEC_DETAILS[["A4-grid-2:9"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|8|2,3,4,5,6,7,8,9|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|N,N,N,N,N,N,N,N|4,4,4,4,4,4,4,4|2,3,4,5,6,7,8,9|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability -#.##### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#"
.CS20_SPEC_DETAILS[["A5-cv-false"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,0|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_SPEC_DETAILS[["A6-arg-order"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,0|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_SPEC_DETAILS[["A7-grid-unsorted"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_SPEC_DETAILS[["A8-grid-dup"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_PREC_ARMS <- c("PR1-anchor-dispatch-over-dots", "PR1-anti-dots-alone", "PR2-anchor-dots-over-grid", "PR2-anti-grid-shape-alone", "PR3-anchor-dispatch-over-cv", "PR3-anti-cv-alone", "PR4-anchor-cv-over-grid", "PR4-anti-grid-shape-alone", "PR5-anchor-cv-over-kfolds", "PR5-anti-kfolds-alone", "PR6-anchor-gridbound-over-kfolds", "PR6-anti-kfolds-alone")
.CS20_PREC_CLS <- c("msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS20_PREC_FIRES <- c("catalog must be an MsCatalog object", "unknown argument passed to ms_select_k()", "unknown argument passed to ms_select_k()", "k_grid must be positive whole numbers", "catalog must be an MsCatalog object", "cv must be a single TRUE or FALSE", "cv must be a single TRUE or FALSE", "k_grid must be positive whole numbers", "cv must be a single TRUE or FALSE", "k_folds must not exceed the channel count", "every k in k_grid must not exceed min(channels, samples)", "k_folds must not exceed the channel count")
.CS20_PREC_ANTI <- c("unknown argument passed to ms_select_k()", "k_grid must be positive whole numbers", "k_grid must be positive whole numbers", "unknown argument passed to ms_select_k()", "cv must be a single TRUE or FALSE", "k_grid must be positive whole numbers", "k_grid must be positive whole numbers", "cv must be a single TRUE or FALSE", "k_folds must not exceed the channel count", "cv must be a single TRUE or FALSE", "k_folds must not exceed the channel count", "every k in k_grid must not exceed min(channels, samples)")
.CS20_DEGEN_PAIR <- c("arbitration-floor", "arbitration-floor", "grid-bound", "grid-bound", "catalog-shape", "catalog-shape", "clause-head", "clause-head")
.CS20_DEGEN_SIDE <- c("hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo")
.CS20_DEGEN_ARMS <- c("arbitration-floor-hi", "arbitration-floor-lo", "grid-bound-hi", "grid-bound-lo", "catalog-shape-hi", "catalog-shape-lo", "clause-head-hi", "clause-head-lo")
.CS20_DEGEN_MODE <- c("accept", "reject", "accept", "reject", "accept", "reject", "reject", "reject")
.CS20_DEGEN_CLS <- c("list", "msuiter_error_kselect", "list", "msuiter_error_input", "list", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS20_DEGEN_MSG <- list()
.CS20_DEGEN_MSG[["arbitration-floor-hi"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_DEGEN_MSG[["arbitration-floor-lo"]] <- "K selection is undecidable: no rank in the grid passes the stability veto | layer-# veto (avg >= #.#, min_cluster >= #.#, sum >= #.#) rejected every candidate rank | veto reasons: k=#: avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#; k=#: avg_stability #.#### < #.#; k=#: avg_stability #.### < #.#; avg + min_cluster_stability #.### < #.# | inspect the attached k_evidence table (condition field), widen the rank grid, or raise the replicate count"
.CS20_DEGEN_MSG[["grid-bound-hi"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|8|2,3,4,5,6,7,8,9|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|N,N,N,N,N,N,N,N|4,4,4,4,4,4,4,4|2,3,4,5,6,7,8,9|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability -#.##### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#;avg_stability #.#### < #.#; min_cluster_stability -#.#### < #.#; avg + min_cluster_stability -#.#### < #.#"
.CS20_DEGEN_MSG[["grid-bound-lo"]] <- "every k in k_grid must not exceed min(channels, samples) = # | a rank-k NMF needs k <= min(nrow(counts), ncol(counts)) | offending k: '##' (catalog has ## channels x # samples) | drop the offending ranks from the grid"
.CS20_DEGEN_MSG[["catalog-shape-hi"]] <- "list|k,k_evidence|3|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_DEGEN_MSG[["catalog-shape-lo"]] <- "catalog must be an MsCatalog object | ms_select_k() dispatches on MsCatalog | received: integer | build the catalog with ms_tally() first"
.CS20_DEGEN_MSG[["clause-head-hi"]] <- "unknown argument passed to ms_select_k() | ms_select_k() has no passthrough arguments | unexpected: 'bogus' | check the argument spelling against ?ms_select_k"
.CS20_DEGEN_MSG[["clause-head-lo"]] <- "k_grid must be positive whole numbers | the grid enumerates the candidate signature counts to arbitrate | received: 'x' | pass e.g. k_grid = #:#"
.CS20_SCAL_KEYS <- c("abort-class", "dispatch-class", "kselect-class", "k-chosen", "evidence-rows", "evidence-cols", "grid-echo", "glyph-argmin", "glyph-veto", "glyph-selected", "names", "classes", "veto-reason-hi", "nseeds-before", "rng-before", "rng-after")
.CS20_SCAL_VALS <- list()
.CS20_SCAL_VALS[["abort-class"]] <- "msuiter_error_input"
.CS20_SCAL_VALS[["dispatch-class"]] <- "msuiter_error_input"
.CS20_SCAL_VALS[["kselect-class"]] <- "msuiter_error_kselect"
.CS20_SCAL_VALS[["k-chosen"]] <- "3"
.CS20_SCAL_VALS[["evidence-rows"]] <- "2"
.CS20_SCAL_VALS[["evidence-cols"]] <- "15"
.CS20_SCAL_VALS[["grid-echo"]] <- "2,3"
.CS20_SCAL_VALS[["glyph-argmin"]] <- "0,1"
.CS20_SCAL_VALS[["glyph-veto"]] <- "0,1"
.CS20_SCAL_VALS[["glyph-selected"]] <- "0,1"
.CS20_SCAL_VALS[["names"]] <- "k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason"
.CS20_SCAL_VALS[["classes"]] <- "integer,numeric,numeric,numeric,list,integer,numeric,numeric,list,numeric,numeric,logical,logical,logical,character"
.CS20_SCAL_VALS[["veto-reason-hi"]] <- "avg_stability #.#### < #.#; avg + min_cluster_stability #.#### < #.#;"
.CS20_SCAL_VALS[["nseeds-before"]] <- "N,N"
.CS20_SCAL_VALS[["rng-before"]] <- "FALSE"
.CS20_SCAL_VALS[["rng-after"]] <- "FALSE"
.CS20_SCAL_REFIRE <- list()
.CS20_SCAL_REFIRE[["abort-class"]] <- ".cs20_cls_of(\"L1-dots-unknown\")"
.CS20_SCAL_REFIRE[["dispatch-class"]] <- ".cs20_cls_of(\"L5-dispatch-noncatalog\")"
.CS20_SCAL_REFIRE[["kselect-class"]] <- ".cs20_cls_of(\"L8-undecidable\")"
.CS20_SCAL_REFIRE[["k-chosen"]] <- "as.character(.cs20_accept_of(\"A2-grid-2:3\")$k)"
.CS20_SCAL_REFIRE[["evidence-rows"]] <- "as.character(nrow(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence))"
.CS20_SCAL_REFIRE[["evidence-cols"]] <- "as.character(ncol(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence))"
.CS20_SCAL_REFIRE[["grid-echo"]] <- "paste(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence$k, collapse = \",\")"
.CS20_SCAL_REFIRE[["glyph-argmin"]] <- ".cs20_glyph(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence$is_argmin)"
.CS20_SCAL_REFIRE[["glyph-veto"]] <- ".cs20_glyph(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence$passes_veto)"
.CS20_SCAL_REFIRE[["glyph-selected"]] <- ".cs20_glyph(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence$selected)"
.CS20_SCAL_REFIRE[["names"]] <- "paste(names(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence), collapse = \",\")"
.CS20_SCAL_REFIRE[["classes"]] <- "paste(vapply(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence, function(cc) class(cc)[1L], character(1L)), collapse = \",\")"
.CS20_SCAL_REFIRE[["veto-reason-hi"]] <- ".cs20_scrub(.cs20_flat1(paste(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence$veto_reason, collapse = \";\")))"
.CS20_SCAL_REFIRE[["nseeds-before"]] <- ".cs20_nseeds(.cs20_accept_of(\"A2-grid-2:3\")$k_evidence$n_seeds_converged)"
.CS20_ARM <- list()
.CS20_ARM[["L1-dots-unknown"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, bogus = 1)"
.CS20_ARM[["L2-grid-nonnumeric"]] <- "ms_select_k(.cs20_plant(\"truth\"), \"x\")"
.CS20_ARM[["L3-grid-zero"]] <- "ms_select_k(.cs20_plant(\"truth\"), c(0, 2))"
.CS20_ARM[["L4-grid-over-bound"]] <- "ms_select_k(.cs20_plant(\"truth\"), 10:20)"
.CS20_ARM[["L5-dispatch-noncatalog"]] <- "ms_select_k(1L, 2:3)"
.CS20_ARM[["L6-cv-bad"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, cv = NA)"
.CS20_ARM[["L7-kfolds-over-channels"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, k_folds = 100L)"
.CS20_ARM[["L8-undecidable"]] <- "ms_select_k(.cs20_plant(\"flat\"), 2:4, replicates = 4L, max_iter = 60L, seed = 1L, k_folds = 5L, n_seeds = 2L)"
.CS20_ARM[["A1-grid-2:5"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:5, replicates = 4L, max_iter = 60L, seed = 1L, k_folds = 5L, n_seeds = 2L)"
.CS20_ARM[["A2-grid-2:3"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["A3-grid-3"]] <- "ms_select_k(.cs20_plant(\"truth\"), 3L, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["A4-grid-2:9"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:9, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["A5-cv-false"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L, cv = FALSE)"
.CS20_ARM[["A6-arg-order"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, cv = FALSE, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["A7-grid-unsorted"]] <- "ms_select_k(.cs20_plant(\"truth\"), c(3L, 2L), replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["A8-grid-dup"]] <- "ms_select_k(.cs20_plant(\"truth\"), c(2L, 2L, 3L), replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["PR1-anchor-dispatch-over-dots"]] <- "ms_select_k(1L, 2:3, bogus = 1)"
.CS20_ARM[["PR1-anti-dots-alone"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, bogus = 1)"
.CS20_ARM[["PR2-anchor-dots-over-grid"]] <- "ms_select_k(.cs20_plant(\"truth\"), \"x\", bogus = 1)"
.CS20_ARM[["PR2-anti-grid-shape-alone"]] <- "ms_select_k(.cs20_plant(\"truth\"), \"x\")"
.CS20_ARM[["PR3-anchor-dispatch-over-cv"]] <- "ms_select_k(1L, 2:3, cv = NA)"
.CS20_ARM[["PR3-anti-cv-alone"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, cv = NA)"
.CS20_ARM[["PR4-anchor-cv-over-grid"]] <- "ms_select_k(.cs20_plant(\"truth\"), \"x\", cv = NA)"
.CS20_ARM[["PR4-anti-grid-shape-alone"]] <- "ms_select_k(.cs20_plant(\"truth\"), \"x\")"
.CS20_ARM[["PR5-anchor-cv-over-kfolds"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, cv = NA, k_folds = 100L)"
.CS20_ARM[["PR5-anti-kfolds-alone"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, k_folds = 100L)"
.CS20_ARM[["PR6-anchor-gridbound-over-kfolds"]] <- "ms_select_k(.cs20_plant(\"truth\"), 10:20, k_folds = 100L)"
.CS20_ARM[["PR6-anti-kfolds-alone"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, k_folds = 100L)"
.CS20_ARM[["arbitration-floor-hi"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["arbitration-floor-lo"]] <- "ms_select_k(.cs20_plant(\"flat\"), 2:4, replicates = 4L, max_iter = 60L, seed = 1L, k_folds = 5L, n_seeds = 2L)"
.CS20_ARM[["grid-bound-hi"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:9, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["grid-bound-lo"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:10, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["catalog-shape-hi"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, replicates = 3L, max_iter = 40L, seed = 1L, k_folds = 4L, n_seeds = 2L)"
.CS20_ARM[["catalog-shape-lo"]] <- "ms_select_k(1L, 2:3)"
.CS20_ARM[["clause-head-hi"]] <- "ms_select_k(.cs20_plant(\"truth\"), 2:3, bogus = 1)"
.CS20_ARM[["clause-head-lo"]] <- "ms_select_k(.cs20_plant(\"truth\"), \"x\")"
.CS20_CENSUS <- c("list=11", "msuiter_error_input=23", "msuiter_error_kselect=2")
## <<CS20-FROZEN-END>> ##

## <<CS20-SHARED-BEGIN>>  (single source: injected byte-identically into
##    the law file and the runner; edit /tmp/cs20-shared.R and re-splice --
##    never hand-edit in place)
## ---------------------------------------------------------------------------
## CS-20 shared block -- the ms_select_k witness plant, render and admissibility
## helpers. Single source: this file is injected byte-identically into the law
## file and the runner by cs20-splice-*.py. Never hand-edit either injection.
## ---------------------------------------------------------------------------
.cs20_truth <- function(m = 48L, n = 9L, k = 3L, cross = 200, group = 3L) {
  anchors <- m %/% k
  w <- matrix(0, nrow = m, ncol = k)
  for (s in seq_len(k)) {
    col <- rep(0, m)
    idx <- ((s - 1L) * anchors + 1L):(s * anchors)
    col[idx] <- 0.5 + seq_len(anchors) / (anchors + 1)
    w[, s] <- col / sum(col)
  }
  h <- matrix(0, nrow = k, ncol = n)
  for (j in seq_len(n)) {
    dom <- ((j - 1L) %/% group) + 1L
    for (s in seq_len(k)) {
      h[s, j] <- if (s == dom) 500 + 1000 * ((j - 1L) %% group + 1L) / (group + 1) else
        cross * ((s * 7L + j * 3L) %% 5L + 1L) / 6
    }
  }
  counts <- round(w %*% h)
  dimnames(counts) <- list(sprintf("CH%03d", seq_len(m)), sprintf("T%02d", seq_len(n)))
  counts
}
## a channel-flat catalogue: no rank in any plausible grid clears the stability
## veto, so the arbitration reaches its undecidable floor
.cs20_flat <- function(m = 48L, n = 12L, base = 20L) {
  counts <- outer(seq_len(m), seq_len(n),
    function(i, j) base + ((i * 7L + j * 11L) %% 13L) - 6L)
  dimnames(counts) <- list(sprintf("CH%03d", seq_len(m)), sprintf("T%02d", seq_len(n)))
  counts
}
.cs20_plant <- function(kind) {
  counts <- switch(kind, truth = .cs20_truth(), flat = .cs20_flat(),
    stop(paste0("unknown plant kind: ", kind)))
  ms_catalog(counts = counts,
    channels = list(name = "SYN000", labels = rownames(counts)),
    samples = colnames(counts), provenance = list(genome = paste0("SYN-", kind)))
}
## D11 posture: integer, label, logical and class bytes are byte-committed; the
## face's arbitration reasons quote measured stability reals, so every digit in
## a committed clause byte becomes '#'. The vocabulary (clause head, field label,
## comparator, article) survives; the measured real, its sign and the threshold
## it was compared against do not. Thresholds are sealed separately as scalars.
.cs20_scrub <- function(s) gsub("[0-9]", "#", s)
.cs20_strip <- function(s) {
  for (b in c("ℹ ", "i ")) s <- gsub(b, "", s, fixed = TRUE)
  s
}
.cs20_flat1 <- function(s) gsub("\t", " ", trimws(s), fixed = TRUE)
.cs20_describe <- function(e) trimws(gsub("\n", " | ",
  paste(as.character(conditionMessage(e)), collapse = " | "), fixed = TRUE))
.cs20_msg <- function(e) .cs20_flat1(.cs20_scrub(.cs20_strip(.cs20_describe(e))))
.cs20_glyph <- function(v) paste0(ifelse(v, "1", "0"), collapse = ",")
.cs20_nseeds <- function(v) paste0(ifelse(is.na(v), "N", as.character(v)),
  collapse = ",")
## the accepted render commits only discrete bytes: the container class, its
## field names, the chosen rank, the evidence schema and shape, the rank echo,
## three logical glyphs, the converged-seed glyph, the two nested list lengths
## and the veto reasons with every measured digit scrubbed away
.cs20_render <- function(x) {
  ev <- x$k_evidence
  paste0(c(class(x)[1L], paste(names(x), collapse = ","), as.character(x$k),
    paste(names(ev), collapse = ","), as.character(nrow(ev)),
    paste(ev$k, collapse = ","), .cs20_glyph(ev$is_argmin),
    .cs20_glyph(ev$passes_veto), .cs20_glyph(ev$selected),
    .cs20_nseeds(ev$n_seeds_converged),
    paste0(lengths(ev$fold_test_deviance), collapse = ","),
    paste0(lengths(ev$per_signature_stability), collapse = ","),
    .cs20_scrub(.cs20_flat1(paste(ev$veto_reason, collapse = ";")))), collapse = "|")
}
.cs20_eval1 <- function(txt, tag) {
  ex <- tryCatch(parse(text = txt), error = identity)
  if (inherits(ex, "error")) stop(paste0("arm ", tag, ": unparsable"))
  if (length(ex) != 1L) stop(paste0("arm ", tag, ": not a single expression"))
  tryCatch(list(ok = TRUE, v = eval(ex[[1L]])), error = identity)
}
.cs20_verdict <- function(r) {
  if (inherits(r, "error")) {
    list(mode = "reject", cls = class(r)[1L], msg = .cs20_msg(r))
  } else {
    list(mode = "accept", cls = class(r$v)[1L], msg = .cs20_render(r$v))
  }
}
.cs20_run <- function(a) .cs20_verdict(.cs20_eval1(.CS20_ARM[[a]], a))
.cs20_cls_of <- function(a) {
  r <- .cs20_eval1(.CS20_ARM[[a]], a)
  if (!inherits(r, "error")) stop(paste0("class probe ", a, ": did not reject"))
  class(r)[1L]
}
.cs20_accept_of <- function(a) {
  r <- .cs20_eval1(.CS20_ARM[[a]], a)
  if (inherits(r, "error")) stop(paste0("accept probe ", a, ": rejected"))
  r$v
}
.cs20_rows <- function(arms) {
  vs <- lapply(arms, .cs20_run)
  data.frame(arm = arms,
    mode = vapply(vs, function(v) v$mode, character(1L)),
    cls = vapply(vs, function(v) v$cls, character(1L)),
    msg = vapply(vs, function(v) v$msg, character(1L)),
    stringsAsFactors = FALSE)
}
.cs20_lawrows <- function() .cs20_rows(.CS20_LAW_ARMS)
.cs20_specrows <- function() .cs20_rows(.CS20_SPEC_ARMS)
.cs20_precrows <- function() {
  df <- .cs20_rows(.CS20_PREC_ARMS)
  df$fires_ok <- vapply(seq_along(df$arm), function(i)
    paste0(grepl(.CS20_PREC_FIRES[i], df$msg[i], fixed = TRUE)), character(1L))
  df$anti_ok <- vapply(seq_along(df$arm), function(i)
    paste0(!grepl(.CS20_PREC_ANTI[i], df$msg[i], fixed = TRUE)), character(1L))
  df
}
.cs20_degenrows <- function() {
  df <- .cs20_rows(.CS20_DEGEN_ARMS)
  data.frame(pair = .CS20_DEGEN_PAIR, side = .CS20_DEGEN_SIDE,
    arm = df$arm, mode = df$mode, cls = df$cls, msg = df$msg,
    stringsAsFactors = FALSE)
}
.cs20_scalval <- function(k) {
  ev <- .cs20_accept_of("A2-grid-2:3")$k_evidence
  switch(k,
    "abort-class" = .cs20_cls_of("L1-dots-unknown"),
    "dispatch-class" = .cs20_cls_of("L5-dispatch-noncatalog"),
    "kselect-class" = .cs20_cls_of("L8-undecidable"),
    "k-chosen" = as.character(.cs20_accept_of("A2-grid-2:3")$k),
    "evidence-rows" = as.character(nrow(ev)),
    "evidence-cols" = as.character(ncol(ev)),
    "grid-echo" = paste(ev$k, collapse = ","),
    "glyph-argmin" = .cs20_glyph(ev$is_argmin),
    "glyph-veto" = .cs20_glyph(ev$passes_veto),
    "glyph-selected" = .cs20_glyph(ev$selected),
    "names" = paste(names(ev), collapse = ","),
    "classes" = paste(vapply(ev, function(cc) class(cc)[1L], character(1L)),
      collapse = ","),
    "veto-reason-hi" = .cs20_scrub(.cs20_flat1(paste(ev$veto_reason, collapse = ";"))),
    "nseeds-before" = .cs20_nseeds(ev$n_seeds_converged),
    stop(paste0("unknown scalar key: ", k)))
}
.cs20_scalref_keys <- function() names(.CS20_SCAL_REFIRE)
.cs20_plant_text <- function() paste(c(
  paste0(.CS20_LAW_ARMS, "=", vapply(.CS20_LAW_ARMS, function(a) .CS20_ARM[[a]], character(1L))),
  paste0(.CS20_SPEC_ARMS, "=", vapply(.CS20_SPEC_ARMS, function(a) .CS20_ARM[[a]], character(1L))),
  paste0(.CS20_PREC_ARMS, "=", vapply(.CS20_PREC_ARMS, function(a) .CS20_ARM[[a]], character(1L))),
  paste0(.CS20_DEGEN_ARMS, "=", vapply(.CS20_DEGEN_ARMS, function(a) .CS20_ARM[[a]], character(1L)))
), collapse = ";")
.cs20_spec_text <- function() paste0(.CS20_SPEC_ARMS, collapse = ";")
.cs20_clean <- function(df) {
  for (cnm in names(df)) attr(df[[cnm]], "names") <- NULL
  df
}
## <<CS20-SHARED-END>>  (do not hand-edit in place: edit the source and
##    re-splice) ##

## ---------------------------------------------------------------------------
## writers, census and the dual-kernel hash rail
## ---------------------------------------------------------------------------
.wtab <- function(nm, df) {
  con <- file(file.path(OUT, nm), open = "wb")
  on.exit(close(con))
  write.table(df, con, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  invisible(nm)
}
.census <- function(nm, df, want.rows, key.col = 1L) {
  stopif(nrow(df) != want.rows, paste0("census ", nm, ": rows ", nrow(df)))
  stopif(any(duplicated(df[[key.col]])), paste0("census ", nm, ": duplicate keys"))
  for (cnm in names(df)) {
    col <- df[[cnm]]
    bad <- !is.character(col) || any(is.na(col)) || any(!nzchar(col)) ||
      any(grepl("\t", col, fixed = TRUE))
    stopif(bad, paste0("census ", nm, ".", cnm, ": non-character/NA/empty/tab"))
  }
  invisible(TRUE)
}
.ck <- function(bytes, tag) {
  a <- .ms_fit_sha256(bytes)
  b <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  stopif(!identical(a, b), paste0("ck: kernel disagreement on ", tag))
  stopif(!grepl("^[0-9a-f]{64}$", a), paste0("ck: hex policy on ", tag))
  stopif(nchar(a) != 64L, paste0("ck: length on ", tag))
  a
}
.file.sha <- function(nm) {
  p <- file.path(OUT, nm)
  con <- file(p, open = "rb")
  on.exit(close(con))
  bytes <- readBin(con, what = raw(), n = file.size(p))
  .ck(bytes, nm)
}

## ---------------------------------------------------------------------------
## build the five witness tables, rail-checked against the frozen block
## ---------------------------------------------------------------------------
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

laws <- .cs20_lawrows()
stopif(!identical(laws$arm, .CS20_LAW_ARMS), "laws: roster drift")
stopif(!identical(laws$mode, rep("reject", 8L)), "laws: a mode drift")
stopif(!identical(laws$cls, .CS20_LAW_CLS), "laws: a class drift")
stopif(!identical(laws$msg, unname(vapply(.CS20_LAW_ARMS,
  function(a) .CS20_LAW_CLAUSES[[a]], character(1L)))), "laws: clause byte drift")
.census("laws", laws, 8L)

specs <- .cs20_specrows()
stopif(!identical(specs$arm, .CS20_SPEC_ARMS), "specs: roster drift")
stopif(!identical(specs$mode, rep("accept", 8L)), "specs: a mode drift")
stopif(!identical(specs$cls, .CS20_SPEC_CLS), "specs: a class drift")
stopif(!identical(specs$msg, unname(vapply(.CS20_SPEC_ARMS,
  function(a) .CS20_SPEC_DETAILS[[a]], character(1L)))), "specs: detail byte drift")
## the wide grid commits four rows, the ascending rank echo, the argmin/veto/
## selected glyphs and the five-followed-by-four fold lengths per rank
stopif(!grepl("|4|2,3,4,5|0,1,0,0|0,1,0,0|0,1,0,0|N,N,N,N|5,5,5,5|2,3,4,5|",
              specs$msg[match("A1-grid-2:5", specs$arm)], fixed = TRUE),
       "specs: the wide-grid render moved")
## the narrow grid commits two rows and the four-fold lengths
stopif(!grepl("|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|",
              specs$msg[match("A2-grid-2:3", specs$arm)], fixed = TRUE),
       "specs: the narrow-grid render moved")
## the single-rank grid commits one row of degenerate one-glyph fields
stopif(!grepl("|1|3|1|1|1|N|4|3|",
              specs$msg[match("A3-grid-3", specs$arm)], fixed = TRUE),
       "specs: the single-rank render moved")
## the saturated grid commits every reachable rank below the channel bound
stopif(!grepl("|8|2,3,4,5,6,7,8,9|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|N,N,N,N,N,N,N,N|4,4,4,4,4,4,4,4|2,3,4,5,6,7,8,9|",
              specs$msg[match("A4-grid-2:9", specs$arm)], fixed = TRUE),
       "specs: the saturated render moved")
## cv = FALSE demotes the SUITOR argmin layer alone: the argmin glyph goes
## all-zero while the veto and selected glyphs keep their layer-two verdict
stopif(!grepl("|2|2,3|0,0|0,1|0,1|N,N|4,4|2,3|",
              specs$msg[match("A5-cv-false", specs$arm)], fixed = TRUE),
       "specs: the cv-false render moved")
## argument order is permutation-invariant under the frozen defaults; the
## unsorted and duplicate grids normalise to the ascending rank echo
stopif(!identical(specs$msg[match("A6-arg-order", specs$arm)],
                  specs$msg[match("A5-cv-false", specs$arm)]),
       "specs: the argument-order render moved")
stopif(!identical(specs$msg[match("A7-grid-unsorted", specs$arm)],
                  specs$msg[match("A2-grid-2:3", specs$arm)]),
       "specs: the unsorted-grid render moved")
stopif(!identical(specs$msg[match("A8-grid-dup", specs$arm)],
                  specs$msg[match("A2-grid-2:3", specs$arm)]),
       "specs: the duplicate-grid render moved")
.census("specs", specs, 8L)

prec <- .cs20_precrows()
stopif(!identical(prec$arm, .CS20_PREC_ARMS), "prec: roster drift")
stopif(!identical(prec$mode, rep("reject", 12L)), "prec: a mode drift")
stopif(!identical(prec$cls, .CS20_PREC_CLS), "prec: a class drift")
stopif(!all(prec$fires_ok == "TRUE"), "prec: a fired anchor missing")
stopif(!all(prec$anti_ok == "TRUE"), "prec: an anti anchor present")
for (i in seq_len(12L)) {
  stopif(!grepl(.CS20_PREC_FIRES[i], prec$msg[i], fixed = TRUE),
         paste0("prec: fire anchor absent in ", .CS20_PREC_ARMS[i]))
  stopif(grepl(.CS20_PREC_ANTI[i], prec$msg[i], fixed = TRUE),
         paste0("prec: anti anchor present in ", .CS20_PREC_ARMS[i]))
}
.census("prec", prec, 12L)

degen <- .cs20_degenrows()
stopif(!identical(degen$pair, .CS20_DEGEN_PAIR), "degen: pair drift")
stopif(!identical(degen$side, .CS20_DEGEN_SIDE), "degen: side drift")
stopif(!identical(degen$arm, .CS20_DEGEN_ARMS), "degen: arm drift")
stopif(!identical(degen$mode, .CS20_DEGEN_MODE), "degen: mode drift")
stopif(!identical(degen$cls, .CS20_DEGEN_CLS), "degen: class drift")
stopif(!identical(degen$msg, unname(vapply(.CS20_DEGEN_ARMS,
  function(a) .CS20_DEGEN_MSG[[a]], character(1L)))), "degen: msg byte drift")
.w <- function(arm) degen$msg[match(arm, degen$arm)]
head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
## arbitration-floor pair: the planted signal clears the layer-two veto on the
## hi side (a plain-list acceptance whose selected glyph is live); the flat
## plant dies at the veto-undecidable abort on the lo side
stopif(!identical(degen$mode[match("arbitration-floor-hi", degen$arm)], "accept"),
       "degen: the passing-floor arm did not accept")
stopif(!grepl("|0,1|0,1|0,1|", .w("arbitration-floor-hi"), fixed = TRUE),
       "degen: the passing-floor render moved")
stopif(!identical(degen$cls[match("arbitration-floor-lo", degen$arm)],
                  "msuiter_error_kselect"),
       "degen: the undecidable class moved")
stopif(!identical(head1(.w("arbitration-floor-lo")),
                  "K selection is undecidable: no rank in the grid passes the stability veto"),
       "degen: the undecidable head moved")
## grid-bound pair: the boundary-reaching grid accepts; the over-bound grid
## dies at the min(channels, samples) bound
stopif(!identical(degen$mode[match("grid-bound-hi", degen$arm)], "accept"),
       "degen: the boundary-reaching arm did not accept")
stopif(!identical(head1(.w("grid-bound-lo")),
                  "every k in k_grid must not exceed min(channels, samples) = #"),
       "degen: the grid-bound head moved")
## catalog-shape pair: a dispatched MsCatalog accepts, an integer dies at the
## dispatch gate
stopif(!identical(degen$mode[match("catalog-shape-hi", degen$arm)], "accept"),
       "degen: the dispatched-catalog arm did not accept")
stopif(!identical(head1(.w("catalog-shape-lo")),
                  "catalog must be an MsCatalog object"),
       "degen: the dispatch head moved")
## clause-head pair: two distinct heads rejecting at opposite ends of the
## ladder (the dots gate ahead of the grid-shape gate)
stopif(!identical(head1(.w("clause-head-hi")),
                  "unknown argument passed to ms_select_k()"),
       "degen: the dots head moved")
stopif(!identical(head1(.w("clause-head-lo")),
                  "k_grid must be positive whole numbers"),
       "degen: the grid-shape head moved")
stopif(identical(head1(.w("clause-head-hi")), head1(.w("clause-head-lo"))),
       "degen: the two clause heads collapsed")
.census("degen", degen, 8L, key.col = 3L)

rng1 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
scal.vals <- vapply(.CS20_SCAL_KEYS, function(k) {
  if (identical(k, "rng-before")) return(format(rng0))
  if (identical(k, "rng-after")) return(format(rng1))
  v <- .cs20_scalval(k)
  stopif(is.na(v) || !nzchar(v), paste0("scalars: empty re-fire for ", k))
  stopif(!identical(v, .CS20_SCAL_VALS[[k]]), paste0("scalars: drift for ", k))
  v
}, character(1L))
scalars <- data.frame(key = .CS20_SCAL_KEYS, value = unname(scal.vals),
                      stringsAsFactors = FALSE)
stopif(!identical(scalars$value[match("rng-before", .CS20_SCAL_KEYS)],
                  .CS20_SCAL_VALS[["rng-before"]]), "scalars: rng-before drift")
stopif(!identical(scalars$value[match("rng-after", .CS20_SCAL_KEYS)],
                  .CS20_SCAL_VALS[["rng-after"]]), "scalars: rng-after drift")
## the accepted container commits its evidence schema shape and rank echo
stopif(!identical(scalars$value[match("evidence-rows", .CS20_SCAL_KEYS)], "2"),
       "scalars: the evidence row count moved")
stopif(!identical(scalars$value[match("evidence-cols", .CS20_SCAL_KEYS)], "15"),
       "scalars: the evidence column count moved")
stopif(!identical(scalars$value[match("k-chosen", .CS20_SCAL_KEYS)], "3"),
       "scalars: the chosen rank moved")
stopif(!identical(scalars$value[match("grid-echo", .CS20_SCAL_KEYS)], "2,3"),
       "scalars: the grid echo moved")
## the placeholder seed column is structurally all-NA on the shipped face, so
## the glyph speaks N and never a converged-seed integer
stopif(!identical(scalars$value[match("nseeds-before", .CS20_SCAL_KEYS)], "N,N"),
       "scalars: the placeholder-seed glyph moved")
## the abort-class scalar speaks the input class the face raises; the
## undecidable floor speaks the kselect class
stopif(!identical(scalars$value[match("abort-class", .CS20_SCAL_KEYS)],
                  "msuiter_error_input"), "scalars: the abort class moved")
stopif(!identical(scalars$value[match("kselect-class", .CS20_SCAL_KEYS)],
                  "msuiter_error_kselect"), "scalars: the kselect class moved")
.census("scalars", scalars, 16L)

## dual-kernel hashes over the frozen corpora (written nowhere, attested)
plant.sha <- .ck(charToRaw(.cs20_plant_text()), "plant-corpus")
spec.sha <- .ck(charToRaw(.cs20_spec_text()), "spec-corpus")

## ---------------------------------------------------------------------------
## all censuses spoke: commit the five witnesses
## ---------------------------------------------------------------------------
.wtab("cs20_laws.tsv", laws)
.wtab("cs20_specs.tsv", specs)
.wtab("cs20_precedence.tsv", prec)
.wtab("cs20_degenerates.tsv", degen)
.wtab("cs20_scalars.tsv", scalars)

cat("[attest] at=", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    " out=", OUT, "\n", sep = "")
for (nm in c("cs20_laws.tsv", "cs20_specs.tsv", "cs20_precedence.tsv",
             "cs20_degenerates.tsv", "cs20_scalars.tsv")) {
  cat("[attest] sha256 ", nm, "=", .file.sha(nm), "\n", sep = "")
}
cat("[attest] plant_sha256=", plant.sha, " spec_sha256=", spec.sha,
    " files=", length(list.files(OUT, pattern = "^cs20_")), "\n", sep = "")
cat("OVERALL PASS\n")
quit(save = "no", status = 0L)
