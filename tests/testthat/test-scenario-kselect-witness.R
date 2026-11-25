# test-scenario-kselect-witness.R -- the CS-20 kselect-witness law units
# (pillar 3). The scenario plants synthetic K-selection calls (the D3 law:
# zero COSMIC numeric matrices, zero real-data bytes, zero downloads -- the
# catalogs ride only as synthetic count matrices over synthetic channel
# labels) and adjudicates the EXPORTED ms_select_k() face: the eight-arm
# gate ladder (dots, grid shape, grid bound, dispatch, cv, k-folds, the
# veto-undecidable abort), the accepted arbitration renders, the six
# precedence discriminators with their anti anchors, the boundary contrast
# pairs and the acceptance specs. The witness bytes under bench/scenarios/out/
# (cs20_laws.tsv, cs20_specs.tsv, cs20_precedence.tsv, cs20_degenerates.tsv,
# cs20_scalars.tsv) are the committed verdict: a drift in a fired clause, an
# observed error class, an accepted shape or the precedence order reddens
# here before print. The plants are synthetic -- no RNG consumption, no
# network, no COSMIC bytes; the lane NEVER calls the benchmark driver, the
# declined calibration family, the registry face or any validator internal
# (banned words, grepped over the runner source).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired clauses -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): the face returns an evidence frame
# of real deviance/stability columns whose last bits are ill-conditioned, so
# no float payload rides any witness -- the accepted render commits DISCRETE
# glyphs (argmin/veto/selected as 0/1), a digit-scrubbed clause and an
# all-NA n_seeds_converged glyph (the placeholder documented on the face);
# integer, label, logical, class and clause bytes are byte-committed.
# The frozen block and the shared code block below are MINTED mechanically
# from the audited probe ledger (cs20-mint3.R / cs20-shared.R); neither is
# ever hand-edited in place.

.rs_out20 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv20 <- function(fname) {
  read.csv(.rs_out20(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

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

# ===========================================================================
# U1 -- rails: the runner exists and speaks the exported face, never an
# internal (banned-word grep over its full source).
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_kselect_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_select_k(", "cs20_",
                 "commandArgs", "digest::digest", "serialize = FALSE",
                 "charToRaw", "open = \"wb\"", "na = \"\"", "quote = FALSE",
                 "row.names = FALSE", "RNG-STATE-RAIL", ".ms_fit_sha256")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  ## The bans govern the hand-written region: the minted frozen block is
  ## OBSERVED DATA and legitimately quotes the face's own bytes (the clause
  ## table quotes the validator message bytes and the face name itself). Slice
  ## the two injected regions out before the absence scan; marker integrity
  ## itself is rail-checked here.
  lines <- strsplit(src, "\n", fixed = TRUE)[[1L]]
  .region <- function(beg, end) {
    b <- which(vapply(lines, function(l) grepl(beg, l, fixed = TRUE), logical(1L)))
    e <- which(vapply(lines, function(l) grepl(end, l, fixed = TRUE), logical(1L)))
    expect_identical(length(b), 1L, info = beg)
    expect_identical(length(e), 1L, info = end)
    c(b, e)
  }
  drop <- c(seq(.region("## <<CS20-FROZEN-BEGIN", "## <<CS20-FROZEN-END")[1]:
                .region("## <<CS20-FROZEN-BEGIN", "## <<CS20-FROZEN-END")[2]),
            seq(.region("## <<CS20-SHARED-BEGIN", "## <<CS20-SHARED-END")[1]:
                .region("## <<CS20-SHARED-BEGIN", "## <<CS20-SHARED-END")[2]))
  hand <- paste(lines[-drop], collapse = "\n")
  expect_gt(nchar(hand), 1000L)
  ## the face IS ms_select_k, so only the CALL form and the internals stay
  ## banned -- the bare face name legitimately rides this lane's own prose
  for (ban in c("msuiter:::", "msuiter_validate_", "msuiter_abort",
                "new(", "set.seed", "sample(", "runif(", "rnorm(",
                "download.file", "http", "unlink(", "Sys.setenv",
                "system2(", "readLines(", "expect_",
                "ms_calibration_grid", "ms_fit_bootstrap",
                "ms_calibration_sanity", "run_benchmark",
                "required_pkgs", "install_required", "load_registry_once",
                "register_engine(", "match_ms_engine",
                "ms_engines(", "ms_registry", "new_class(", "new.env(",
                "set_props")) {
    expect_false(grepl(ban, hand, fixed = TRUE), info = ban)
  }
})

# ===========================================================================
# U2 -- witness existence and shape: five committed TSVs, non-zero, with
# hard row-count gates and an all-character no-NA census (no vacuous green).
# ===========================================================================
test_that("the five witnesses exist with hard shape gates", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs20_laws.tsv", "cs20_specs.tsv", "cs20_precedence.tsv",
              "cs20_degenerates.tsv", "cs20_scalars.tsv")) {
    expect_true(file.exists(.rs_out20(f)))
    expect_gt(file.size(.rs_out20(f)), 0)
  }
  lw <- .rs_tsv20("cs20_laws.tsv"); sp <- .rs_tsv20("cs20_specs.tsv")
  pr <- .rs_tsv20("cs20_precedence.tsv"); dg <- .rs_tsv20("cs20_degenerates.tsv")
  sc <- .rs_tsv20("cs20_scalars.tsv")
  expect_identical(nrow(lw), 8L)
  expect_identical(nrow(sp), 8L)
  expect_identical(nrow(pr), 12L)
  expect_identical(nrow(dg), 8L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS20_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS20_SCAL_KEYS))
  expect_identical(nrow(sc), 16L)
  for (df in list(lw, sp, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
    expect_false(any(vapply(df, function(cc) any(!nzchar(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the laws witness mirrors the frozen law table: eight arms, classes
# and verbatim clauses, byte for byte.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv20("cs20_laws.tsv")
  expect_identical(lw$arm, .CS20_LAW_ARMS)
  expect_identical(lw$mode, rep("reject", 8L))
  expect_identical(lw$cls, .CS20_LAW_CLS)
  expect_identical(lw$msg, unname(vapply(.CS20_LAW_ARMS,
    function(a) .CS20_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U4 -- live replay of the law arms: every arm still rejects with its
# committed class and its committed clause bytes ride the live message.
# ===========================================================================
test_that("law arms replay live through the face", {
  live <- .cs20_lawrows()
  expect_identical(live$arm, .CS20_LAW_ARMS)
  expect_identical(live$mode, rep("reject", 8L))
  expect_identical(live$cls, .CS20_LAW_CLS)
  expect_identical(live$msg, unname(vapply(.CS20_LAW_ARMS,
    function(a) .CS20_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U5 -- the specs witness mirrors the frozen acceptance table, the
# acceptance arms replay live and the accepted renders commit their shape,
# grid echo, arbitration glyphs and the placeholder-seed glyph.
# ===========================================================================
test_that("specs witness mirrors frozen and replays live", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv20("cs20_specs.tsv")
  expect_identical(sp$arm, .CS20_SPEC_ARMS)
  expect_identical(sp$mode, rep("accept", 8L))
  expect_identical(sp$cls, .CS20_SPEC_CLS)
  expect_identical(sp$msg, unname(vapply(.CS20_SPEC_ARMS,
    function(a) .CS20_SPEC_DETAILS[[a]], character(1L))))
  live <- .cs20_specrows()
  expect_identical(live$arm, sp$arm)
  expect_identical(live$mode, sp$mode)
  expect_identical(live$cls, sp$cls)
  expect_identical(live$msg, sp$msg)
  w <- function(arm) sp$msg[match(arm, sp$arm)]
  ## every accepted render opens with the plain-list container and its two
  ## field names, then the chosen rank and the fifteen-column evidence schema
  for (a in .CS20_SPEC_ARMS) {
    expect_true(grepl("list|k,k_evidence|", w(a), fixed = TRUE), info = a)
    expect_true(grepl("|k,cv_test_deviance,cv_test_mse,cv_train_mse,fold_test_deviance,n_seeds_converged,avg_stability,min_cluster_stability,per_signature_stability,wilcoxon_p_vs_prev,wilcoxon_l2_median_delta,passes_veto,is_argmin,selected,veto_reason|",
                      w(a), fixed = TRUE), info = a)
  }
  ## the wide grid commits four rows, the ascending rank echo and the
  ## argmin/veto/selected glyphs with five fold lengths per rank
  expect_true(grepl("|4|2,3,4,5|0,1,0,0|0,1,0,0|0,1,0,0|N,N,N,N|5,5,5,5|2,3,4,5|",
                    w("A1-grid-2:5"), fixed = TRUE))
  ## the narrow grid commits two rows and the four-fold lengths
  expect_true(grepl("|2|2,3|0,1|0,1|0,1|N,N|4,4|2,3|",
                    w("A2-grid-2:3"), fixed = TRUE))
  ## the single-rank grid commits one row with degenerate one-glyph fields
  expect_true(grepl("|1|3|1|1|1|N|4|3|",
                    w("A3-grid-3"), fixed = TRUE))
  ## the saturated grid commits eight rows
  expect_true(grepl("|8|2,3,4,5,6,7,8,9|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|0,1,0,0,0,0,0,0|N,N,N,N,N,N,N,N|4,4,4,4,4,4,4,4|2,3,4,5,6,7,8,9|",
                    w("A4-grid-2:9"), fixed = TRUE))
  ## cv = FALSE demotes the argmin layer alone: the argmin glyph goes all-zero
  ## while the veto and selected glyphs keep their layer-two verdict
  expect_true(grepl("|2|2,3|0,0|0,1|0,1|N,N|4,4|2,3|",
                    w("A5-cv-false"), fixed = TRUE))
  ## argument order and redundant/unsorted grids do not move the render: the
  ## cv-false render is permutation-invariant and both the unsorted and the
  ## duplicate grid normalise to the ascending rank echo
  expect_identical(w("A6-arg-order"), w("A5-cv-false"))
  expect_identical(w("A7-grid-unsorted"), w("A2-grid-2:3"))
  expect_identical(w("A8-grid-dup"), w("A2-grid-2:3"))
})

# ===========================================================================
# U6 -- the precedence witness: committed class, fired anchor PRESENT and
# anti anchor ABSENT in every arm, live replay included.
# ===========================================================================
test_that("precedence witness speaks anchors both ways", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  pr <- .rs_tsv20("cs20_precedence.tsv")
  expect_identical(pr$arm, .CS20_PREC_ARMS)
  expect_identical(pr$mode, rep("reject", 12L))
  expect_identical(pr$cls, .CS20_PREC_CLS)
  expect_identical(pr$fires_ok, rep("TRUE", 12L))
  expect_identical(pr$anti_ok, rep("TRUE", 12L))
  for (i in seq_len(12L)) {
    expect_true(grepl(.CS20_PREC_FIRES[i], pr$msg[i], fixed = TRUE),
                info = .CS20_PREC_ARMS[i])
    expect_false(grepl(.CS20_PREC_ANTI[i], pr$msg[i], fixed = TRUE),
                 info = .CS20_PREC_ARMS[i])
  }
  live <- .cs20_precrows()
  expect_identical(live$msg, pr$msg)
})

# ===========================================================================
# U7 -- the boundary contrast witness: four pairs replayed live against the
# committed bytes; the pair-level discriminators hold (the passing-arbitration
# floor against the veto-undecidable abort, the reachable grid against the
# over-bound one, the dispatched catalog against the undispatchable one, and
# the two clause heads that reject at opposite ends of the ladder).
# ===========================================================================
test_that("boundary contrast pairs hold on both sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  dg <- .rs_tsv20("cs20_degenerates.tsv")
  expect_identical(dg$pair, .CS20_DEGEN_PAIR)
  expect_identical(dg$side, .CS20_DEGEN_SIDE)
  expect_identical(dg$arm, .CS20_DEGEN_ARMS)
  expect_identical(dg$mode, .CS20_DEGEN_MODE)
  expect_identical(dg$cls, .CS20_DEGEN_CLS)
  expect_identical(dg$msg, unname(vapply(.CS20_DEGEN_ARMS,
    function(a) .CS20_DEGEN_MSG[[a]], character(1L))))
  live <- .cs20_degenrows()
  expect_identical(live$msg, dg$msg)
  w <- function(arm) dg$msg[match(arm, dg$arm)]
  head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
  ## arbitration-floor pair: the planted signal clears the veto on the hi side
  ## (a plain-list acceptance whose selected glyph is live); the flat plant
  ## dies at the veto-undecidable abort on the lo side
  expect_identical(dg$mode[match("arbitration-floor-hi", dg$arm)], "accept")
  expect_true(grepl("|0,1|0,1|0,1|", w("arbitration-floor-hi"), fixed = TRUE))
  expect_identical(dg$cls[match("arbitration-floor-lo", dg$arm)],
                   "msuiter_error_kselect")
  expect_identical(head1(w("arbitration-floor-lo")),
                   "K selection is undecidable: no rank in the grid passes the stability veto")
  ## grid-bound pair: the boundary-reaching grid accepts; the over-bound grid
  ## dies at the min(channels, samples) bound
  expect_identical(dg$mode[match("grid-bound-hi", dg$arm)], "accept")
  expect_identical(head1(w("grid-bound-lo")),
                   "every k in k_grid must not exceed min(channels, samples) = #")
  ## catalog-shape pair: a dispatched MsCatalog accepts, an integer dies at
  ## the dispatch gate
  expect_identical(dg$mode[match("catalog-shape-hi", dg$arm)], "accept")
  expect_identical(head1(w("catalog-shape-lo")),
                   "catalog must be an MsCatalog object")
  ## clause-head pair: two distinct heads, both rejecting at opposite ends of
  ## the ladder (the dots gate ahead of the grid-shape gate)
  expect_identical(head1(w("clause-head-hi")),
                   "unknown argument passed to ms_select_k()")
  expect_identical(head1(w("clause-head-lo")),
                   "k_grid must be positive whole numbers")
  expect_false(identical(head1(w("clause-head-hi")),
                         head1(w("clause-head-lo"))))
})

# ===========================================================================
# U8 -- the scalars witness: the re-fireable keys replay live to their
# committed bytes; the rng keys ride the committed purity verdict.
# ===========================================================================
test_that("scalars witness replays and the rng rail stays frozen", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sc <- .rs_tsv20("cs20_scalars.tsv")
  expect_identical(sort(sc$key), sort(.CS20_SCAL_KEYS))
  rf <- .cs20_scalref_keys()
  for (k in rf) {
    expect_identical(sc$value[match(k, sc$key)], .cs20_scalval(k), info = k)
    expect_identical(.CS20_SCAL_VALS[[k]], sc$value[match(k, sc$key)], info = k)
  }
  for (k in setdiff(.CS20_SCAL_KEYS, rf)) {
    expect_true(k %in% c("rng-before", "rng-after"))
    expect_identical(sc$value[match(k, sc$key)], .CS20_SCAL_VALS[[k]], info = k)
  }
  ## the accepted container commits its schema shape and rank echo
  expect_identical(sc$value[match("evidence-rows", sc$key)], "2")
  expect_identical(sc$value[match("evidence-cols", sc$key)], "15")
  expect_identical(sc$value[match("k-chosen", sc$key)], "3")
  expect_identical(sc$value[match("grid-echo", sc$key)], "2,3")
  ## the placeholder seed column is structurally all-NA on the shipped face,
  ## so the glyph speaks N (never a converged-seed integer)
  expect_identical(sc$value[match("nseeds-before", sc$key)], "N,N")
  expect_false(grepl("[0-9]", sc$value[match("nseeds-before", sc$key)]))
  ## the abort-class scalar speaks the input class the face raises; the
  ## undecidable floor speaks the kselect class
  expect_identical(sc$value[match("abort-class", sc$key)], "msuiter_error_input")
  expect_identical(sc$value[match("kselect-class", sc$key)],
                   "msuiter_error_kselect")
})

# ===========================================================================
# U9 -- dual-kernel SHA-256: the frozen plant corpus and the spec roster
# hash identically under both governed kernels and speak the hex policy.
# ===========================================================================
test_that("plant and spec corpora agree under both sha256 kernels", {
  for (tag in c("plant", "spec")) {
    txt <- if (identical(tag, "plant")) .cs20_plant_text() else .cs20_spec_text()
    ## measured corpora: plant several thousand, spec 99 bytes; the floors
    ## catch an emptied or truncated roster, not a glyph style
    expect_gt(nchar(txt), if (identical(tag, "plant")) 2000L else 80L)
    bytes <- charToRaw(txt)
    a <- .ms_fit_sha256(bytes)
    b <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
    expect_identical(a, b, info = tag)
    expect_true(grepl("^[0-9a-f]{64}$", a), info = tag)
    expect_false(grepl("[^0-9a-f]", a, perl = TRUE), info = tag)
    expect_identical(nchar(a), 64L)
  }
})

# ===========================================================================
# U10 -- frozen roster shape: counts, census recomputation, single-expression
# parsability and roster disjointness.
# ===========================================================================
test_that("the frozen roster speaks its own shape", {
  expect_identical(length(.CS20_LAW_ARMS), 8L)
  expect_identical(length(.CS20_SPEC_ARMS), 8L)
  expect_identical(length(.CS20_PREC_ARMS), 12L)
  expect_identical(length(.CS20_DEGEN_ARMS), 8L)
  expect_identical(length(.CS20_SCAL_KEYS), 16L)
  expect_identical(length(.CS20_ARM), 36L)
  expect_identical(length(.CS20_CENSUS), 3L)
  allc <- c(.CS20_LAW_ARMS, .CS20_SPEC_ARMS, .CS20_PREC_ARMS, .CS20_DEGEN_ARMS)
  expect_false(any(duplicated(allc)))
  expect_true(all(allc %in% names(.CS20_ARM)))
  for (a in names(.CS20_ARM)) {
    expect_identical(length(parse(text = .CS20_ARM[[a]])), 1L, info = a)
  }
  allcls <- c(.CS20_LAW_CLS, .CS20_PREC_CLS, .CS20_SPEC_CLS, .CS20_DEGEN_CLS)
  tally <- function(cl) paste0(cl, "=", sum(allcls == cl))
  want <- c(tally("list"), tally("msuiter_error_input"),
            tally("msuiter_error_kselect"))
  expect_true(all(want %in% .CS20_CENSUS))
  expect_identical(sort(.CS20_CENSUS), sort(want))
})
