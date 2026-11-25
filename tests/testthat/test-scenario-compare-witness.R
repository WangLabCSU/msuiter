# test-scenario-compare-witness.R -- the CS-19 compare-witness law units
# (pillar 3). The scenario plants synthetic dictionary-comparison calls
# (the D3 law: zero COSMIC numeric matrices, zero real-data bytes, zero
# downloads -- the dictionaries ride only as named all-ones matrices over
# synthetic channel labels) and adjudicates the EXPORTED ms_compare()/
# MsComparison face: the twenty-three-arm "input"/"option"/"comparison"
# validator ladder over the estimated/reference arguments, the container
# property-type split (the S7 property check ahead of the custom validator),
# the accepted protocol/metric/protocol_version renders, the precedence
# discriminators with their anti anchors, the boundary contrast pairs and the
# acceptance specs. The witness bytes under bench/scenarios/out/
# (cs19_laws.tsv, cs19_specs.tsv, cs19_precedence.tsv, cs19_degenerates.tsv,
# cs19_scalars.tsv) are the committed verdict: a drift in a fired clause, an
# observed error class, an accepted shape or the precedence order reddens
# here before print. The plants are synthetic -- no RNG consumption, no
# network, no COSMIC bytes; the lane NEVER calls the benchmark driver, the
# declined calibration family, the registry face or any validator internal
# (banned words, grepped over the runner source).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired clauses -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): integer, label, logical, class and
# clause bytes are byte-committed; the face returns real similarity matrices
# whose kernel error is ~1e-16, so no float payload rides any witness -- the
# accepted render commits a DISCRETE similarity glyph (1/0/NA at a 1e-9
# threshold, seven orders above the observed float error).
# The frozen block and the shared code block below are MINTED mechanically
# from the audited probe ledger (cs19-mint3.R / cs19-shared.R); neither is
# ever hand-edited in place.

.rs_out19 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv19 <- function(fname) {
  read.csv(.rs_out19(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

## <<CS19-FROZEN-BEGIN>>  (minted mechanically from the audited ledger
##    2026-11-25; DO NOT hand-edit: regenerate via cs19-mint3.R) ##
.CS19_LAW_ARMS <- c("L1-est-nonmatrix", "L2-est-nonfinite", "L3-ref-nonmatrix", "L4-ref-nonfinite", "L5-channel-mismatch", "L6-too-few-channels", "L7-metric-unknown", "L8-protocol-unknown", "L9-thresholds-bad", "L10-seed-bad", "L11-jiang-no-exposures", "L12-jiang-fit-align", "L13-jiang-catalogs-chan", "L14-jiang-kxn-shape", "L15-sigest-shape", "K1-metrics-empty-list", "K2-metrics-unnamed", "K3-metrics-nonmatrix", "K4-hungarian-nondf", "K5-jiang-nonlist", "K6-null-nonlist", "K7-metrics-nonlist-s7", "K8-meta-nonlist-s7")
.CS19_LAW_CLS <- c("msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_option", "msuiter_error_option", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_comparison", "msuiter_error_comparison", "msuiter_error_comparison", "msuiter_error_comparison", "msuiter_error_comparison", "msuiter_error_comparison", "simpleError", "simpleError")
.CS19_LAW_CLAUSES <- list()
.CS19_LAW_CLAUSES[["L1-est-nonmatrix"]] <- "estimated must be a numeric matrix | ms_compare() compares column signatures of a shared channel space | received: numeric | pass m x k matrices with matching row counts"
.CS19_LAW_CLAUSES[["L2-est-nonfinite"]] <- "estimated must be finite and non-negative | signatures are share vectors; NaN/negative entries are uninterpretable | offending entries: 1 | re-fit or re-normalize the dictionary before comparing"
.CS19_LAW_CLAUSES[["L3-ref-nonmatrix"]] <- "reference must be a numeric matrix | ms_compare() compares column signatures of a shared channel space | received: numeric | pass m x k matrices with matching row counts"
.CS19_LAW_CLAUSES[["L4-ref-nonfinite"]] <- "reference must be finite and non-negative | signatures are share vectors; NaN/negative entries are uninterpretable | offending entries: 1 | re-fit or re-normalize the dictionary before comparing"
.CS19_LAW_CLAUSES[["L5-channel-mismatch"]] <- "estimated and reference must share the channel count | estimated rows: 6; reference rows: 5 | the metrics compare signatures channel-wise in one space | project both dictionaries onto the same channel space"
.CS19_LAW_CLAUSES[["L6-too-few-channels"]] <- "ms_compare needs at least 2 channels | m: 1 | the null faces and the metrics are degenerate at m = 1 | compare dictionaries with at least 2 channels"
.CS19_LAW_CLAUSES[["L7-metric-unknown"]] <- "metric must be among the frozen names | unknown: nope | legal: cosine, correlation, jsd, hellinger | pick metrics from the frozen design-memo set"
.CS19_LAW_CLAUSES[["L8-protocol-unknown"]] <- "protocol must be among the frozen names | unknown: nope | legal: hungarian, islam, jiang | pick protocols from the frozen design-memo set"
.CS19_LAW_CLAUSES[["L9-thresholds-bad"]] <- "thresholds must be non-empty numeric in (0, 1) | received: '1.5' | the sweep thresholds are match lines on the cosine scale | use e.g. the default seq(0.80, 0.90, by = 0.01)"
.CS19_LAW_CLAUSES[["L10-seed-bad"]] <- "seed must be a single non-negative finite number | the seed derives every null Monte Carlo stream | received: 'NA' | record the integer seed used for the nulls"
.CS19_LAW_CLAUSES[["L11-jiang-no-exposures"]] <- "the Jiang protocol needs both exposure matrices | activity > 0 matching has no cosine face (bbaf042) | missing: exposures_est, exposures_ref | pass the k x n count-scale activity matrices"
.CS19_LAW_CLAUSES[["L12-jiang-fit-align"]] <- "the Jiang protocol needs cell-aligned exposure matrices (the true dictionary fitted) | exposures_est signatures: 3 | exposures_ref signatures: 4 | fit the truth dictionary and pass its exposure matrix"
.CS19_LAW_CLAUSES[["L13-jiang-catalogs-chan"]] <- "catalogs must have the same channel count | catalog rows: 2; channel count: 6 | the reconstruction flag reads per-sample catalog columns | pass the catalog the estimated dictionary was fitted to"
.CS19_LAW_CLAUSES[["L14-jiang-kxn-shape"]] <- "exposure matrices must be k x n matching the dictionaries | exposures_est: 3 x 2; exposures_ref: 3 x 1 | expected: 3 x n and 3 x n (shared n) | pass the fit outputs for the compared dictionaries"
.CS19_LAW_CLAUSES[["L15-sigest-shape"]] <- "signatures_est must be m x k_est | received: 6 x 2; expected: 6 x 3 | the reconstruction flag rebuilds catalogs from this dictionary | pass the estimated signature matrix alongside its exposures"
.CS19_LAW_CLAUSES[["K1-metrics-empty-list"]] <- "comparison metrics must be a named non-empty list | each entry is a k_est x k_ref similarity matrix | received: list | pass the metrics list returned by ms_compare()"
.CS19_LAW_CLAUSES[["K2-metrics-unnamed"]] <- "comparison metrics must be a named non-empty list | each entry is a k_est x k_ref similarity matrix | received: list | pass the metrics list returned by ms_compare()"
.CS19_LAW_CLAUSES[["K3-metrics-nonmatrix"]] <- "metric 'cosine' must be a numeric matrix | metrics are k_est x k_ref pairwise similarity matrices | received: character | pass the metrics list returned by ms_compare()"
.CS19_LAW_CLAUSES[["K4-hungarian-nondf"]] <- "'hungarian' must be a data.frame or NULL | protocol sweeps are tidy per-threshold tables | received: numeric | pass the slots assembled by ms_compare()"
.CS19_LAW_CLAUSES[["K5-jiang-nonlist"]] <- "'jiang' must be a named list or NULL | the protocol/null results are named for reproducibility | received: numeric | pass the slots assembled by ms_compare()"
.CS19_LAW_CLAUSES[["K6-null-nonlist"]] <- "'null' must be a named list or NULL | the protocol/null results are named for reproducibility | received: numeric | pass the slots assembled by ms_compare()"
.CS19_LAW_CLAUSES[["K7-metrics-nonlist-s7"]] <- "<msuiter::MsComparison> object properties are invalid: | - @metrics must be <list>, not <double>"
.CS19_LAW_CLAUSES[["K8-meta-nonlist-s7"]] <- "<msuiter::MsComparison> object properties are invalid: | - @meta must be <list>, not <double>"
.CS19_SPEC_ARMS <- c("A1-hungarian", "A2-islam", "A3-both", "A4-jiang", "A5-correlation", "A6-jsd", "A7-hellinger", "A8-all-protocols", "A9-multi-metric", "A10-burden-scalar", "A11-seed-zero", "A12-empty-protocol", "sp-replay-identity")
.CS19_SPEC_CLS <- c("s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:msuiter::MsComparison", "s7:character")
.CS19_SPEC_DETAILS <- list()
.CS19_SPEC_DETAILS[["A1-hungarian"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_SPEC_DETAILS[["A2-islam"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|islam|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_SPEC_DETAILS[["A3-both"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian+islam|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_SPEC_DETAILS[["A4-jiang"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x3|6|jiang|U-M4-01-v1|1,1,1,1,1,1,1,1,1|signature+catalog"
.CS19_SPEC_DETAILS[["A5-correlation"]] <- "msuiter::MsComparison|correlation|3x4|6|hungarian|U-M4-01-v1|NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA|signature"
.CS19_SPEC_DETAILS[["A6-jsd"]] <- "msuiter::MsComparison|jsd|3x4|6|hungarian|U-M4-01-v1|0,0,0,0,0,0,0,0,0,0,0,0|signature"
.CS19_SPEC_DETAILS[["A7-hellinger"]] <- "msuiter::MsComparison|hellinger|3x4|6|hungarian|U-M4-01-v1|0,0,0,0,0,0,0,0,0,0,0,0|signature"
.CS19_SPEC_DETAILS[["A8-all-protocols"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x3|6|hungarian+islam+jiang|U-M4-01-v1|1,1,1,1,1,1,1,1,1|signature+catalog"
.CS19_SPEC_DETAILS[["A9-multi-metric"]] <- "msuiter::MsComparison|cosine,correlation,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_SPEC_DETAILS[["A10-burden-scalar"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature+catalog"
.CS19_SPEC_DETAILS[["A11-seed-zero"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_SPEC_DETAILS[["A12-empty-protocol"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6||U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_SPEC_DETAILS[["sp-replay-identity"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature==msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_PREC_ARMS <- c("PR1-anchor-estshape-over-refshape", "PR1-anti-refshape-alone", "PR2-anchor-channel-over-metric", "PR2-anti-metric-alone", "PR3-anchor-metric-over-protocol", "PR3-anti-protocol-alone", "PR4-anchor-metric-over-thresholds", "PR4-anti-thresholds-alone", "PR5-anchor-estshape-over-estvalue", "PR5-anti-estvalue-alone")
.CS19_PREC_CLS <- c("msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_option", "msuiter_error_option", "msuiter_error_option", "msuiter_error_option", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS19_PREC_FIRES <- c("estimated must be a numeric matrix", "reference must be a numeric matrix", "must share the channel count", "metric must be among the frozen names", "metric must be among the frozen names", "protocol must be among the frozen names", "metric must be among the frozen names", "thresholds must be non-empty", "estimated must be a numeric matrix", "must be finite and non-negative")
.CS19_PREC_ANTI <- c("reference must be a numeric matrix", "estimated must be a numeric matrix", "metric must be among the frozen names", "must share the channel count", "protocol must be among the frozen names", "metric must be among the frozen names", "thresholds must be non-empty", "metric must be among the frozen names", "must be finite and non-negative", "estimated must be a numeric matrix")
.CS19_DEGEN_PAIR <- c("channel-floor", "channel-floor", "jiang-alignment", "jiang-alignment", "option-vs-valid", "option-vs-valid", "shape-vs-value", "shape-vs-value")
.CS19_DEGEN_SIDE <- c("hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo")
.CS19_DEGEN_ARMS <- c("twochannels-hi", "onechannel-lo", "jiang-aligned-hi", "jiang-unaligned-lo", "valid-metric-hi", "unknown-metric-lo", "nonmatrix-shape-hi", "nonfinite-value-lo")
.CS19_DEGEN_MODE <- c("accept", "reject", "accept", "reject", "accept", "reject", "reject", "reject")
.CS19_DEGEN_CLS <- c("s7:msuiter::MsComparison", "msuiter_error_input", "s7:msuiter::MsComparison", "msuiter_error_input", "s7:msuiter::MsComparison", "msuiter_error_option", "msuiter_error_input", "msuiter_error_input")
.CS19_DEGEN_MSG <- list()
.CS19_DEGEN_MSG[["twochannels-hi"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|2|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_DEGEN_MSG[["onechannel-lo"]] <- "ms_compare needs at least 2 channels | m: 1 | the null faces and the metrics are degenerate at m = 1 | compare dictionaries with at least 2 channels"
.CS19_DEGEN_MSG[["jiang-aligned-hi"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x3|6|jiang|U-M4-01-v1|1,1,1,1,1,1,1,1,1|signature+catalog"
.CS19_DEGEN_MSG[["jiang-unaligned-lo"]] <- "the Jiang protocol needs cell-aligned exposure matrices (the true dictionary fitted) | exposures_est signatures: 3 | exposures_ref signatures: 4 | fit the truth dictionary and pass its exposure matrix"
.CS19_DEGEN_MSG[["valid-metric-hi"]] <- "msuiter::MsComparison|cosine,p_null,q_bh|3x4|6|hungarian|U-M4-01-v1|1,1,1,1,1,1,1,1,1,1,1,1|signature"
.CS19_DEGEN_MSG[["unknown-metric-lo"]] <- "metric must be among the frozen names | unknown: nope | legal: cosine, correlation, jsd, hellinger | pick metrics from the frozen design-memo set"
.CS19_DEGEN_MSG[["nonmatrix-shape-hi"]] <- "estimated must be a numeric matrix | ms_compare() compares column signatures of a shared channel space | received: numeric | pass m x k matrices with matching row counts"
.CS19_DEGEN_MSG[["nonfinite-value-lo"]] <- "estimated must be finite and non-negative | signatures are share vectors; NaN/negative entries are uninterpretable | offending entries: 1 | re-fit or re-normalize the dictionary before comparing"
.CS19_SCAL_KEYS <- c("abort-class", "container-classes", "metrics-names", "cosine-dim", "k-est-k-ref", "m", "protocol", "version", "format", "theta-custom", "rng-before", "rng-after")
.CS19_SCAL_VALS <- list()
.CS19_SCAL_VALS[["abort-class"]] <- "msuiter_error_input"
.CS19_SCAL_VALS[["container-classes"]] <- "msuiter_error_comparison,simpleError"
.CS19_SCAL_VALS[["metrics-names"]] <- "cosine,p_null,q_bh"
.CS19_SCAL_VALS[["cosine-dim"]] <- "3x4"
.CS19_SCAL_VALS[["k-est-k-ref"]] <- "3x4"
.CS19_SCAL_VALS[["m"]] <- "6"
.CS19_SCAL_VALS[["protocol"]] <- "hungarian"
.CS19_SCAL_VALS[["version"]] <- "U-M4-01-v1"
.CS19_SCAL_VALS[["format"]] <- "<MsComparison> metrics: cosine,p_null,q_bh | protocols: hungarian"
.CS19_SCAL_VALS[["theta-custom"]] <- "0.8,0.9"
.CS19_SCAL_VALS[["rng-before"]] <- "FALSE"
.CS19_SCAL_VALS[["rng-after"]] <- "FALSE"
.CS19_SCAL_REFIRE <- list()
.CS19_SCAL_REFIRE[["abort-class"]] <- "ms_compare(as.vector(.cs19_est(3L)), .cs19_ref(4L), protocol = \"hungarian\")"
.CS19_SCAL_REFIRE[["container-classes"]] <- "paste0(class(tryCatch(ms_comparison(list()), error = identity))[1L], \",\", class(tryCatch(ms_comparison(1), error = identity))[1L])"
.CS19_SCAL_REFIRE[["metrics-names"]] <- "paste(names(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")@metrics), collapse = \",\")"
.CS19_SCAL_REFIRE[["cosine-dim"]] <- "paste0(dim(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")@metrics$cosine), collapse = \"x\")"
.CS19_SCAL_REFIRE[["k-est-k-ref"]] <- "{ r <- ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\"); paste0(r@meta$k_est, \"x\", r@meta$k_ref) }"
.CS19_SCAL_REFIRE[["m"]] <- "as.character(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")@meta$m)"
.CS19_SCAL_REFIRE[["protocol"]] <- "paste(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")@meta$protocol, collapse = \",\")"
.CS19_SCAL_REFIRE[["version"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")@meta$protocol_version"
.CS19_SCAL_REFIRE[["format"]] <- "format(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\"))"
.CS19_SCAL_REFIRE[["theta-custom"]] <- "paste(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", thresholds = c(0.8, 0.9))@meta$thresholds, collapse = \",\")"
.CS19_ARM <- list()
.CS19_ARM[["L1-est-nonmatrix"]] <- "ms_compare(as.vector(.cs19_est(3L)), .cs19_ref(4L), protocol = \"hungarian\")"
.CS19_ARM[["L2-est-nonfinite"]] <- "{ x <- .cs19_est(3L); x[1L, 1L] <- NA; ms_compare(x, .cs19_ref(4L), protocol = \"hungarian\") }"
.CS19_ARM[["L3-ref-nonmatrix"]] <- "ms_compare(.cs19_est(3L), as.vector(.cs19_ref(4L)), protocol = \"hungarian\")"
.CS19_ARM[["L4-ref-nonfinite"]] <- "{ x <- .cs19_ref(4L); x[1L, 1L] <- Inf; ms_compare(.cs19_est(3L), x, protocol = \"hungarian\") }"
.CS19_ARM[["L5-channel-mismatch"]] <- "ms_compare(.cs19_est(3L), .cs19_mat(rep(1, 5L * 4L), 5L, 4L), protocol = \"hungarian\")"
.CS19_ARM[["L6-too-few-channels"]] <- "ms_compare(.cs19_mat(rep(1, 3L), 1L, 3L), .cs19_mat(rep(1, 4L), 1L, 4L), protocol = \"hungarian\")"
.CS19_ARM[["L7-metric-unknown"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"nope\")"
.CS19_ARM[["L8-protocol-unknown"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"nope\")"
.CS19_ARM[["L9-thresholds-bad"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", thresholds = 1.5)"
.CS19_ARM[["L10-seed-bad"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", seed = NA)"
.CS19_ARM[["L11-jiang-no-exposures"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"jiang\")"
.CS19_ARM[["L12-jiang-fit-align"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(4L, 2L))"
.CS19_ARM[["L13-jiang-catalogs-chan"]] <- "ms_compare(.cs19_j(3L), .cs19_j(3L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(3L, 2L), catalogs = .cs19_mat(rep(1, 2L), 2L, 1L))"
.CS19_ARM[["L14-jiang-kxn-shape"]] <- "ms_compare(.cs19_j(3L), .cs19_j(3L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_mat(rep(1, 3L), 3L, 1L))"
.CS19_ARM[["L15-sigest-shape"]] <- "ms_compare(.cs19_j(3L), .cs19_j(3L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(3L, 2L), signatures_est = .cs19_map(6L, 2L))"
.CS19_ARM[["K1-metrics-empty-list"]] <- "ms_comparison(list())"
.CS19_ARM[["K2-metrics-unnamed"]] <- "ms_comparison(list(.cs19_sq()))"
.CS19_ARM[["K3-metrics-nonmatrix"]] <- "ms_comparison(list(cosine = \"x\"))"
.CS19_ARM[["K4-hungarian-nondf"]] <- "ms_comparison(list(cosine = .cs19_sq()), hungarian = 1)"
.CS19_ARM[["K5-jiang-nonlist"]] <- "ms_comparison(list(cosine = .cs19_sq()), jiang = 1)"
.CS19_ARM[["K6-null-nonlist"]] <- "ms_comparison(list(cosine = .cs19_sq()), null = 1)"
.CS19_ARM[["K7-metrics-nonlist-s7"]] <- "ms_comparison(1)"
.CS19_ARM[["K8-meta-nonlist-s7"]] <- "ms_comparison(list(cosine = .cs19_sq()), meta = 1)"
.CS19_ARM[["A1-hungarian"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")"
.CS19_ARM[["A2-islam"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"islam\")"
.CS19_ARM[["A3-both"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = c(\"hungarian\", \"islam\"))"
.CS19_ARM[["A4-jiang"]] <- "ms_compare(.cs19_j(3L), .cs19_j(3L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(3L, 2L))"
.CS19_ARM[["A5-correlation"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"correlation\")"
.CS19_ARM[["A6-jsd"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"jsd\")"
.CS19_ARM[["A7-hellinger"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"hellinger\")"
.CS19_ARM[["A8-all-protocols"]] <- "ms_compare(.cs19_j(3L), .cs19_j(3L), protocol = c(\"hungarian\", \"islam\", \"jiang\"), exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(3L, 2L))"
.CS19_ARM[["A9-multi-metric"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = c(\"cosine\", \"correlation\"))"
.CS19_ARM[["A10-burden-scalar"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", burden = 100)"
.CS19_ARM[["A11-seed-zero"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", seed = 0)"
.CS19_ARM[["A12-empty-protocol"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = character(0))"
.CS19_ARM[["sp-replay-identity"]] <- "paste0(.cs19_render(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")), \"==\", .cs19_render(ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\")))"
.CS19_ARM[["PR1-anchor-estshape-over-refshape"]] <- "ms_compare(as.vector(.cs19_est(3L)), as.vector(.cs19_ref(4L)), protocol = \"hungarian\")"
.CS19_ARM[["PR1-anti-refshape-alone"]] <- "ms_compare(.cs19_est(3L), as.vector(.cs19_ref(4L)), protocol = \"hungarian\")"
.CS19_ARM[["PR2-anchor-channel-over-metric"]] <- "ms_compare(.cs19_est(3L), .cs19_mat(rep(1, 5L * 4L), 5L, 4L), protocol = \"hungarian\", metric = \"nope\")"
.CS19_ARM[["PR2-anti-metric-alone"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"nope\")"
.CS19_ARM[["PR3-anchor-metric-over-protocol"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"nope\", metric = \"nope\")"
.CS19_ARM[["PR3-anti-protocol-alone"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"nope\")"
.CS19_ARM[["PR4-anchor-metric-over-thresholds"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"nope\", thresholds = 1.5)"
.CS19_ARM[["PR4-anti-thresholds-alone"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", thresholds = 1.5)"
.CS19_ARM[["PR5-anchor-estshape-over-estvalue"]] <- "ms_compare(as.vector(.cs19_est(3L)) * -1, .cs19_ref(4L), protocol = \"hungarian\")"
.CS19_ARM[["PR5-anti-estvalue-alone"]] <- "{ x <- .cs19_est(3L); x[1L, 1L] <- -1; ms_compare(x, .cs19_ref(4L), protocol = \"hungarian\") }"
.CS19_ARM[["twochannels-hi"]] <- "ms_compare(.cs19_mat(rep(1, 2L * 3L), 2L, 3L), .cs19_mat(rep(1, 2L * 4L), 2L, 4L), protocol = \"hungarian\")"
.CS19_ARM[["onechannel-lo"]] <- "ms_compare(.cs19_mat(rep(1, 3L), 1L, 3L), .cs19_mat(rep(1, 4L), 1L, 4L), protocol = \"hungarian\")"
.CS19_ARM[["jiang-aligned-hi"]] <- "ms_compare(.cs19_j(3L), .cs19_j(3L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(3L, 2L))"
.CS19_ARM[["jiang-unaligned-lo"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"jiang\", exposures_est = .cs19_ex(3L, 2L), exposures_ref = .cs19_ex(4L, 2L))"
.CS19_ARM[["valid-metric-hi"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"cosine\")"
.CS19_ARM[["unknown-metric-lo"]] <- "ms_compare(.cs19_est(3L), .cs19_ref(4L), protocol = \"hungarian\", metric = \"nope\")"
.CS19_ARM[["nonmatrix-shape-hi"]] <- "ms_compare(as.vector(.cs19_est(3L)), .cs19_ref(4L), protocol = \"hungarian\")"
.CS19_ARM[["nonfinite-value-lo"]] <- "{ x <- .cs19_est(3L); x[1L, 1L] <- NA; ms_compare(x, .cs19_ref(4L), protocol = \"hungarian\") }"
.CS19_CENSUS <- c("msuiter_error_comparison=6", "msuiter_error_input=23", "msuiter_error_option=7", "s7:character=1", "s7:msuiter::MsComparison=15", "simpleError=2")
## <<CS19-FROZEN-END>> ##

## <<CS19-SHARED-BEGIN>>  (single source: injected byte-identically into
##    the law file and the runner; edit /tmp/cs19-shared.R and re-splice --
##    never hand-edit in place)
## cs19-shared.R -- single source of the CS-19 compare-witness shared block.
## Injected byte-identically into tests/testthat/test-scenario-compare-witness.R
## and bench/scenarios/run_compare_witness.R between the SHARED markers.
## Pure, deterministic, no RNG, no clock, no network: the condition-message
## pipeline plus the exported-face verdict render and the plant builders the
## frozen ARM texts call. The render commits a DISCRETE similarity glyph
## (1/0/NA over a 1e-9 threshold) instead of any float payload -- the D11
## posture for a face that returns real similarity matrices.
.cs19_mat <- function(data, nr, nc) {
  matrix(data, nr, nc,
         dimnames = list(paste0("C", seq_len(nr)), paste0("S", seq_len(nc))))
}
.cs19_est <- function(k = 3L) .cs19_mat(rep(1, 6L * k), 6L, k)
.cs19_ref <- function(k = 4L) .cs19_mat(rep(1, 6L * k), 6L, k)
.cs19_j <- function(k = 3L) .cs19_mat(rep(1, 6L * k), 6L, k)
.cs19_ex <- function(k = 3L, n = 2L) .cs19_mat(rep(1, k * n), k, n)
## The container-arm and jiang-signature builders the frozen ARM texts call.
.cs19_map <- function(nr, nc) .cs19_mat(rep(1, nr * nc), nr, nc)
.cs19_sq <- function() .cs19_mat(rep(1, 4L), 2L, 2L)
## Discrete similarity glyph: 1 for a live similarity cell, 0 for one below
## the threshold, NA for an uninterpretable cell (a constant/singular column
## under the correlation metric). The kernel float error is ~1e-16, seven
## orders under the threshold, so the glyph is a cross-platform label.
.cs19_glyph <- function(v) {
  paste0(ifelse(as.vector(v) > 1e-9, "1", "0"), collapse = ",")
}
.cs19_render <- function(x) {
  ## S7 objects report class(x)[1L] as "msuiter::MsComparison"; the container
  ## render commits only discrete structure (metric names, matrix shape, the
  ## channel count, the protocol join, the version, the similarity glyph and
  ## the null hull) -- never a float payload.
  paste0(c(class(x)[1L],
    paste(names(x@metrics), collapse = ","),
    paste0(dim(x@metrics[[1L]]), collapse = "x"),
    as.character(x@meta$m),
    paste(x@meta$protocol, collapse = "+"),
    as.character(x@meta$protocol_version),
    .cs19_glyph(x@metrics[[1L]]),
    paste(names(x@null), collapse = "+")), collapse = "|")
}
.cs19_describe <- function(e) trimws(gsub("\n", " | ",
  paste(as.character(conditionMessage(e)), collapse = " | "), fixed = TRUE))
.cs19_strip <- function(s) {
  for (b in c("ℹ ", "i ")) s <- gsub(b, "", s, fixed = TRUE)
  s
}
.cs19_eval1 <- function(txt, tag) {
  if (is.na(txt) || !nzchar(txt)) stop(".cs19_eval1: no text for ", tag)
  ex <- parse(text = txt)
  if (length(ex) != 1L) stop(".cs19_eval1: ", tag, " is not a single expression")
  tryCatch(list(ok = TRUE, v = eval(ex[[1L]])), error = identity)
}
.cs19_verdict <- function(arm, r) {
  if (inherits(r, "error")) {
    list(arm = arm, mode = "reject", cls = class(r)[1L],
         msg = gsub("\t", " ", .cs19_strip(.cs19_describe(r)), fixed = TRUE))
  } else {
    rendered <- if (is.character(r)) r else .cs19_render(r)
    list(arm = arm, mode = "accept", cls = paste0("s7:", class(r)[1L]),
         msg = gsub("\t", " ", rendered, fixed = TRUE))
  }
}
.cs19_fire <- function(arm) {
  r <- .cs19_eval1(.CS19_ARM[[arm]], arm)
  .cs19_verdict(arm, if (inherits(r, "error")) r else r$v)
}
.cs19_clean <- function(df) {
  ## witness bytes round-trip nameless through read.csv; strip any vapply
  ## residue names so identical() compares columns byte-true
  for (cnm in names(df)) attr(df[[cnm]], "names") <- NULL
  df
}
.cs19_rows <- function(arms) {
  vs <- lapply(arms, function(a) .cs19_fire(a))
  .cs19_clean(data.frame(arm = arms,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs19_lawrows <- function() .cs19_rows(.CS19_LAW_ARMS)
.cs19_specrows <- function() .cs19_rows(.CS19_SPEC_ARMS)
.cs19_precrows <- function() {
  base <- .cs19_rows(.CS19_PREC_ARMS)
  base$fires_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(grepl(.CS19_PREC_FIRES[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base$anti_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(!grepl(.CS19_PREC_ANTI[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base
}
.cs19_degenrows <- function() {
  vs <- lapply(.CS19_DEGEN_ARMS, function(a) .cs19_fire(a))
  .cs19_clean(data.frame(pair = .CS19_DEGEN_PAIR, side = .CS19_DEGEN_SIDE,
             arm = .CS19_DEGEN_ARMS,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs19_scalval <- function(k) {
  txt <- .CS19_SCAL_REFIRE[[k]]
  if (is.null(txt)) return(NA_character_)
  res <- .cs19_eval1(txt, k)
  if (inherits(res, "error")) {
    if (identical(k, "abort-class")) return(paste0(class(res)[1L]))
    return(.cs19_strip(.cs19_describe(res)))
  }
  paste0(res$v)
}
.cs19_scalref_keys <- function() names(.CS19_SCAL_REFIRE)
.cs19_plant_text <- function() {
  ord <- c(.CS19_LAW_ARMS, .CS19_SPEC_ARMS, .CS19_PREC_ARMS, .CS19_DEGEN_ARMS)
  paste0(vapply(ord, function(a) paste0(a, "=", .CS19_ARM[[a]]),
                character(1L)), collapse = ";")
}
.cs19_spec_text <- function() paste0(.CS19_SPEC_ARMS, collapse = ";")
## <<CS19-SHARED-END>>  (do not hand-edit in place: edit the source and
##    re-splice) ##

# ===========================================================================
# U1 -- rails: the runner exists and speaks the exported face, never an
# internal (banned-word grep over its full source).
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_compare_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_compare(", "cs19_",
                 "commandArgs", "digest::digest", "serialize = FALSE",
                 "charToRaw", "open = \"wb\"", "na = \"\"", "quote = FALSE",
                 "row.names = FALSE", "RNG-STATE-RAIL", ".ms_fit_sha256")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  ## The bans govern the hand-written region: the minted frozen block is
  ## OBSERVED DATA and legitimately quotes the face's own bytes (the clause
  ## table quotes the validator and S7 message bytes). Slice the two injected
  ## regions out before the absence scan; marker integrity itself is
  ## rail-checked here.
  lines <- strsplit(src, "\n", fixed = TRUE)[[1L]]
  .region <- function(beg, end) {
    b <- which(vapply(lines, function(l) grepl(beg, l, fixed = TRUE), logical(1L)))
    e <- which(vapply(lines, function(l) grepl(end, l, fixed = TRUE), logical(1L)))
    expect_identical(length(b), 1L, info = beg)
    expect_identical(length(e), 1L, info = end)
    c(b, e)
  }
  drop <- c(seq(.region("## <<CS19-FROZEN-BEGIN", "## <<CS19-FROZEN-END")[1]:
                .region("## <<CS19-FROZEN-BEGIN", "## <<CS19-FROZEN-END")[2]),
            seq(.region("## <<CS19-SHARED-BEGIN", "## <<CS19-SHARED-END")[1]:
                .region("## <<CS19-SHARED-BEGIN", "## <<CS19-SHARED-END")[2]))
  hand <- paste(lines[-drop], collapse = "\n")
  expect_gt(nchar(hand), 1000L)
  for (ban in c("msuiter:::", "msuiter_validate_", "msuiter_abort",
                "new(", "set.seed", "sample(", "runif(", "rnorm(",
                "download.file", "http", "unlink(", "Sys.setenv",
                "system2(", "readLines(", "expect_",
                "ms_calibration_grid", "ms_fit_bootstrap",
                "ms_calibration_sanity", "ms_select_k", "run_benchmark",
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
  for (f in c("cs19_laws.tsv", "cs19_specs.tsv", "cs19_precedence.tsv",
              "cs19_degenerates.tsv", "cs19_scalars.tsv")) {
    expect_true(file.exists(.rs_out19(f)))
    expect_gt(file.size(.rs_out19(f)), 0)
  }
  lw <- .rs_tsv19("cs19_laws.tsv"); sp <- .rs_tsv19("cs19_specs.tsv")
  pr <- .rs_tsv19("cs19_precedence.tsv"); dg <- .rs_tsv19("cs19_degenerates.tsv")
  sc <- .rs_tsv19("cs19_scalars.tsv")
  expect_identical(nrow(lw), 23L)
  expect_identical(nrow(sp), 13L)
  expect_identical(nrow(pr), 10L)
  expect_identical(nrow(dg), 8L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS19_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS19_SCAL_KEYS))
  for (df in list(lw, sp, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
    expect_false(any(vapply(df, function(cc) any(!nzchar(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the laws witness mirrors the frozen law table: twenty-three arms,
# classes and verbatim clauses, byte for byte.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv19("cs19_laws.tsv")
  expect_identical(lw$arm, .CS19_LAW_ARMS)
  expect_identical(lw$mode, rep("reject", 23L))
  expect_identical(lw$cls, .CS19_LAW_CLS)
  expect_identical(lw$msg, unname(vapply(.CS19_LAW_ARMS,
    function(a) .CS19_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U4 -- live replay of the law arms: every arm still rejects with its
# committed class and its committed clause bytes ride the live message.
# ===========================================================================
test_that("law arms replay live through the face", {
  live <- .cs19_lawrows()
  expect_identical(live$arm, .CS19_LAW_ARMS)
  expect_identical(live$mode, rep("reject", 23L))
  expect_identical(live$cls, .CS19_LAW_CLS)
  expect_identical(live$msg, unname(vapply(.CS19_LAW_ARMS,
    function(a) .CS19_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U5 -- the specs witness mirrors the frozen acceptance table, the
# acceptance arms replay live, the replay identity speaks the core render
# twice and the accepted renders commit their shape, protocol and glyph.
# ===========================================================================
test_that("specs witness mirrors frozen and replays live", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv19("cs19_specs.tsv")
  expect_identical(sp$arm, .CS19_SPEC_ARMS)
  expect_identical(sp$mode, rep("accept", 13L))
  expect_identical(sp$cls, .CS19_SPEC_CLS)
  expect_identical(sp$msg, unname(vapply(.CS19_SPEC_ARMS,
    function(a) .CS19_SPEC_DETAILS[[a]], character(1L))))
  live <- .cs19_specrows()
  expect_identical(live$arm, sp$arm)
  expect_identical(live$mode, sp$mode)
  expect_identical(live$cls, sp$cls)
  expect_identical(live$msg, sp$msg)
  ## the replay arm speaks the core render twice, joined by ==
  expect_identical(sp$msg[match("sp-replay-identity", sp$arm)],
                   paste0(sp$msg[match("A1-hungarian", sp$arm)], "==",
                          sp$msg[match("A1-hungarian", sp$arm)]))
  ## the accepted render commits the metric names, the k_est x k_ref shape,
  ## the channel count, the protocol join and the discrete similarity glyph
  expect_true(grepl("|cosine,p_null,q_bh|3x4|6|hungarian|",
                    sp$msg[match("A1-hungarian", sp$arm)], fixed = TRUE))
  expect_true(grepl("|1,1,1,1,1,1,1,1,1,1,1,1|signature",
                    sp$msg[match("A1-hungarian", sp$arm)], fixed = TRUE))
  ## the combined-protocol render joins the two protocol names
  expect_true(grepl("|hungarian+islam|",
                    sp$msg[match("A3-both", sp$arm)], fixed = TRUE))
  ## the Jiang render commits the k x k shape and the catalog hull
  expect_true(grepl("|3x3|6|jiang|",
                    sp$msg[match("A4-jiang", sp$arm)], fixed = TRUE))
  expect_true(grepl("|signature+catalog",
                    sp$msg[match("A4-jiang", sp$arm)], fixed = TRUE))
  ## the correlation render commits the NA glyph (a singular column);
  ## the jsd and hellinger renders commit the all-zero glyph
  expect_true(grepl("|NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA|",
                    sp$msg[match("A5-correlation", sp$arm)], fixed = TRUE))
  expect_true(grepl("|0,0,0,0,0,0,0,0,0,0,0,0|",
                    sp$msg[match("A6-jsd", sp$arm)], fixed = TRUE))
  expect_true(grepl("|0,0,0,0,0,0,0,0,0,0,0,0|",
                    sp$msg[match("A7-hellinger", sp$arm)], fixed = TRUE))
  ## the multi-metric render commits the four metric names
  expect_true(grepl("|cosine,correlation,p_null,q_bh|",
                    sp$msg[match("A9-multi-metric", sp$arm)], fixed = TRUE))
  ## the empty-protocol render commits the empty protocol field
  expect_true(grepl("|3x4|6||U-M4-01-v1|",
                    sp$msg[match("A12-empty-protocol", sp$arm)], fixed = TRUE))
})

# ===========================================================================
# U6 -- the precedence witness: committed class, fired anchor PRESENT and
# anti anchor ABSENT in every arm, live replay included.
# ===========================================================================
test_that("precedence witness speaks anchors both ways", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  pr <- .rs_tsv19("cs19_precedence.tsv")
  expect_identical(pr$arm, .CS19_PREC_ARMS)
  expect_identical(pr$mode, rep("reject", 10L))
  expect_identical(pr$cls, .CS19_PREC_CLS)
  expect_identical(pr$fires_ok, rep("TRUE", 10L))
  expect_identical(pr$anti_ok, rep("TRUE", 10L))
  for (i in seq_len(10L)) {
    expect_true(grepl(.CS19_PREC_FIRES[i], pr$msg[i], fixed = TRUE),
                info = .CS19_PREC_ARMS[i])
    expect_false(grepl(.CS19_PREC_ANTI[i], pr$msg[i], fixed = TRUE),
                 info = .CS19_PREC_ARMS[i])
  }
  live <- .cs19_precrows()
  expect_identical(live$msg, pr$msg)
})

# ===========================================================================
# U7 -- the boundary contrast witness: four pairs replayed live against the
# committed bytes; the pair-level discriminators hold (the two-channel
# acceptance against the one-channel floor, the aligned Jiang exposures
# against the unaligned ones by the cell-alignment law, the frozen metric
# name against the unknown one by the option law, the shape law against the
# value law by their own clause heads).
# ===========================================================================
test_that("boundary contrast pairs hold on both sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  dg <- .rs_tsv19("cs19_degenerates.tsv")
  expect_identical(dg$pair, .CS19_DEGEN_PAIR)
  expect_identical(dg$side, .CS19_DEGEN_SIDE)
  expect_identical(dg$arm, .CS19_DEGEN_ARMS)
  expect_identical(dg$mode, .CS19_DEGEN_MODE)
  expect_identical(dg$cls, .CS19_DEGEN_CLS)
  expect_identical(dg$msg, unname(vapply(.CS19_DEGEN_ARMS,
    function(a) .CS19_DEGEN_MSG[[a]], character(1L))))
  live <- .cs19_degenrows()
  expect_identical(live$msg, dg$msg)
  w <- function(arm) dg$msg[match(arm, dg$arm)]
  head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
  ## channel-floor pair: two channels accept (the m >= 2 floor rides the
  ## channel count field), one dies at the same floor
  expect_identical(dg$mode[match("twochannels-hi", dg$arm)], "accept")
  expect_true(grepl("|2|hungarian|", w("twochannels-hi"), fixed = TRUE))
  expect_identical(head1(w("onechannel-lo")),
                   "ms_compare needs at least 2 channels")
  ## jiang-alignment pair: aligned exposures accept with the catalog hull,
  ## unaligned die at the cell-alignment law
  expect_identical(dg$mode[match("jiang-aligned-hi", dg$arm)], "accept")
  expect_true(grepl("|signature+catalog", w("jiang-aligned-hi"), fixed = TRUE))
  expect_true(grepl("cell-aligned exposure matrices",
                    w("jiang-unaligned-lo"), fixed = TRUE))
  ## option-vs-valid pair: a frozen metric name accepts, an unknown one dies
  ## at the option law
  expect_identical(dg$mode[match("valid-metric-hi", dg$arm)], "accept")
  expect_identical(head1(w("unknown-metric-lo")),
                   "metric must be among the frozen names")
  ## shape-vs-value pair: the shape law vs the value law, distinct heads
  expect_identical(head1(w("nonmatrix-shape-hi")),
                   "estimated must be a numeric matrix")
  expect_false(identical(head1(w("nonmatrix-shape-hi")),
                         head1(w("nonfinite-value-lo"))))
  expect_true(grepl("must be finite and non-negative",
                    w("nonfinite-value-lo"), fixed = TRUE))
})

# ===========================================================================
# U8 -- the scalars witness: the re-fireable keys replay live to their
# committed bytes; the rng keys ride the committed purity verdict.
# ===========================================================================
test_that("scalars witness replays and the rng rail stays frozen", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sc <- .rs_tsv19("cs19_scalars.tsv")
  expect_identical(sort(sc$key), sort(.CS19_SCAL_KEYS))
  rf <- .cs19_scalref_keys()
  for (k in rf) {
    expect_identical(sc$value[match(k, sc$key)], .cs19_scalval(k), info = k)
    expect_identical(.CS19_SCAL_VALS[[k]], sc$value[match(k, sc$key)], info = k)
  }
  for (k in setdiff(.CS19_SCAL_KEYS, rf)) {
    expect_true(k %in% c("rng-before", "rng-after"))
    expect_identical(sc$value[match(k, sc$key)], .CS19_SCAL_VALS[[k]], info = k)
  }
  ## the container-classes scalar speaks both rejection layers: the custom
  ## comparison validator and the S7 property check that fires ahead of it
  expect_identical(sc$value[match("container-classes", sc$key)],
                   "msuiter_error_comparison,simpleError")
  ## the accepted container commits its similarity shape and metric names
  expect_identical(sc$value[match("cosine-dim", sc$key)], "3x4")
  expect_identical(sc$value[match("metrics-names", sc$key)], "cosine,p_null,q_bh")
  expect_identical(sc$value[match("k-est-k-ref", sc$key)], "3x4")
  ## the abort-class scalar speaks the input class the face raises
  expect_identical(sc$value[match("abort-class", sc$key)], "msuiter_error_input")
})

# ===========================================================================
# U9 -- dual-kernel SHA-256: the frozen plant corpus and the spec roster
# hash identically under both governed kernels and speak the hex policy.
# ===========================================================================
test_that("plant and spec corpora agree under both sha256 kernels", {
  for (tag in c("plant", "spec")) {
    txt <- if (identical(tag, "plant")) .cs19_plant_text() else .cs19_spec_text()
    ## measured corpora: plant several thousand, spec ~130 bytes; the floors
    ## catch an emptied or truncated roster, not a glyph style
    expect_gt(nchar(txt), if (identical(tag, "plant")) 2000L else 100L)
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
  expect_identical(length(.CS19_LAW_ARMS), 23L)
  expect_identical(length(.CS19_SPEC_ARMS), 13L)
  expect_identical(length(.CS19_PREC_ARMS), 10L)
  expect_identical(length(.CS19_DEGEN_ARMS), 8L)
  expect_identical(length(.CS19_SCAL_KEYS), 12L)
  expect_identical(length(.CS19_ARM), 54L)
  expect_identical(length(.CS19_CENSUS), 6L)
  allc <- c(.CS19_LAW_ARMS, .CS19_SPEC_ARMS, .CS19_PREC_ARMS, .CS19_DEGEN_ARMS)
  expect_false(any(duplicated(allc)))
  expect_true(all(allc %in% names(.CS19_ARM)))
  for (a in names(.CS19_ARM)) {
    expect_identical(length(parse(text = .CS19_ARM[[a]])), 1L, info = a)
  }
  allcls <- c(.CS19_LAW_CLS, .CS19_PREC_CLS, .CS19_SPEC_CLS, .CS19_DEGEN_CLS)
  tally <- function(cl) paste0(cl, "=", sum(allcls == cl))
  want <- c(tally("msuiter_error_comparison"), tally("msuiter_error_input"),
            tally("msuiter_error_option"), tally("s7:character"),
            tally("s7:msuiter::MsComparison"), tally("simpleError"))
  expect_true(all(want %in% .CS19_CENSUS))
  expect_identical(sort(.CS19_CENSUS), sort(want))
})
