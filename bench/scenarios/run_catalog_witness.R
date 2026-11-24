# run_catalog_witness.R -- the CS-17 catalog-witness scenario (pillar 3).
#
# Mandate: plant synthetic governance-container calls (the D3 law: zero
# COSMIC numeric matrices, zero real-data bytes, zero downloads -- the
# catalog rides only as shape) and adjudicate the EXPORTED ms_catalog()/
# MsCatalog face: the S7 property-gate split against the validator, the
# seventeen-arm "catalog" validator, the second error class the shared
# label digest reaches, the precedence discriminators with their anti
# anchors, the boundary contrast pairs and the acceptance specs. Every arm
# is driven through the exported faces alone; the accepted returns, the
# abort classes and the fired clauses are the face's own. The scenario
# consumes no RNG, no network and no clock at the adjudication core; the
# benchmark runner and the DECLINED calibration family are never invoked
# here.
#
# Framing law: DECISION RECORD only. The witnesses under out/ are the
# committed verdict of what the shipped face SAID on planted truth. Float
# posture (D11): integer, label, logical, class and clause bytes are
# byte-committed; the face produces no float payload columns (counts
# storage mode rides as a glyph, the label digest is hex), so no float
# glyph rides any witness.
#
# Rails: this runner carries the same frozen block as the law file
# (tests/testthat/test-scenario-catalog-witness.R), injected byte-identically
# from one minted source; every observed class, clause, shape and
# precedence order is rail-checked AS WE GO -- a drift fails the run
# before any witness is written. The witness bytes are written only after
# every payload census speaks; a byte-rerun must reproduce them identically.

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
## <<CS17-FROZEN-BEGIN>>  (minted mechanically from the audited ledger
##    2026-11-24; DO NOT hand-edit: regenerate via gen-frozen.cs17.R) ##
.CS17_LAW_ARMS <- c("G1-channels-nonlist", "G2-samples-noncharacter", "G3-provenance-nonlist", "V1-counts-vector", "V1b-counts-character-matrix", "V2-rownames-missing", "V2b-colnames-missing", "V3-rowlabels-dup", "V3b-collabels-dup", "V4-count-NA", "V4b-count-Inf", "V4c-count-NaN", "V5-count-negative", "V6-snap-missing-hash", "V6b-snap-missing-name", "V6c-snap-extra-field", "V6d-snap-empty-list", "V7-name-empty", "V7b-name-NA", "V7c-name-noncharacter", "V8-labels-NA-handhash", "V8b-labels-numeric", "V8c-label-empty-string", "V9-snap-labels-dup", "V13-hash-nonhex", "V13b-hash-noncharacter", "V13c-hash-NA", "V13d-hash-short-hex", "V14-hash-foreign", "V10-nrow-vs-labels", "V10b-ncol-vs-samples", "V11-rowlabel-decoy-permuted", "V12-colnames-vs-samples", "V15-sample-empty", "V15b-sample-NA", "V16-prov-unnamed", "V16b-prov-emptyname", "V17-genome-missing", "V17b-genome-empty", "X1-errorinput-autohash-NAlabels", "E2-NAinteger-label-trap", "U1-hashhelper-via-factory-listlabels")
.CS17_LAW_CLS <- c("simpleError", "simpleError", "simpleError", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_input", "msuiter_error_input", "msuiter_error_catalog")
.CS17_LAW_CLAUSES <- list()
.CS17_LAW_CLAUSES[["G1-channels-nonlist"]] <- paste0("<msuiter::MsCatalog> object properties are inval",
            "id: | - @channels must be <list>, not <character",
            ">")
.CS17_LAW_CLAUSES[["G2-samples-noncharacter"]] <- paste0("<msuiter::MsCatalog> object properties are inval",
            "id: | - @samples must be <character>, not <integ",
            "er>")
.CS17_LAW_CLAUSES[["G3-provenance-nonlist"]] <- paste0("<msuiter::MsCatalog> object properties are inval",
            "id: | - @provenance must be <list>, not <charact",
            "er>")
.CS17_LAW_CLAUSES[["V1-counts-vector"]] <- paste0("counts must be a numeric matrix (channels x samp",
            "les) | MsCatalog stores one count per channel an",
            "d sample | received: numeric | tally variants wi",
            "th ms_tally() to obtain a count matrix")
.CS17_LAW_CLAUSES[["V1b-counts-character-matrix"]] <- paste0("counts must be a numeric matrix (channels x samp",
            "les) | MsCatalog stores one count per channel an",
            "d sample | received: matrix | tally variants wit",
            "h ms_tally() to obtain a count matrix")
.CS17_LAW_CLAUSES[["V2-rownames-missing"]] <- paste0("counts must carry both channel labels (rownames)",
            " and sample labels (colnames) | labels are the o",
            "nly legal matching key (never position) | rownam",
            "es missing: TRUE; colnames missing: FALSE | name",
            " the matrix dimensions before constructing MsCat",
            "alog")
.CS17_LAW_CLAUSES[["V2b-colnames-missing"]] <- paste0("counts must carry both channel labels (rownames)",
            " and sample labels (colnames) | labels are the o",
            "nly legal matching key (never position) | rownam",
            "es missing: FALSE; colnames missing: TRUE | name",
            " the matrix dimensions before constructing MsCat",
            "alog")
.CS17_LAW_CLAUSES[["V3-rowlabels-dup"]] <- paste0("channel and sample labels must be unique | dupli",
            "cated labels make label matching ambiguous | dup",
            "licated channel labels: 'CH1'; duplicated sample",
            " labels: (none) | de-duplicate or rename labels")
.CS17_LAW_CLAUSES[["V3b-collabels-dup"]] <- paste0("channel and sample labels must be unique | dupli",
            "cated labels make label matching ambiguous | dup",
            "licated channel labels: (none); duplicated sampl",
            "e labels: 'S1' | de-duplicate or rename labels")
.CS17_LAW_CLAUSES[["V4-count-NA"]] <- paste0("counts must not contain NA or non-finite values ",
            "| the FFI contract rejects NA; the catalog layer",
            " adds no pseudo-counts | offending cells: '2' | ",
            "fix the upstream tally output")
.CS17_LAW_CLAUSES[["V4b-count-Inf"]] <- paste0("counts must not contain NA or non-finite values ",
            "| the FFI contract rejects NA; the catalog layer",
            " adds no pseudo-counts | offending cells: '7' | ",
            "fix the upstream tally output")
.CS17_LAW_CLAUSES[["V4c-count-NaN"]] <- paste0("counts must not contain NA or non-finite values ",
            "| the FFI contract rejects NA; the catalog layer",
            " adds no pseudo-counts | offending cells: '4' | ",
            "fix the upstream tally output")
.CS17_LAW_CLAUSES[["V5-count-negative"]] <- paste0("counts must be non-negative | negative mutation ",
            "counts are impossible | offending cells: '5' | c",
            "heck the tally pipeline for subtraction errors")
.CS17_LAW_CLAUSES[["V6-snap-missing-hash"]] <- paste0("the channel snapshot must be a list with fields ",
            "name, labels, hash | the snapshot keeps the regi",
            "stry's canonical labels and their digest | recei",
            "ved fields: 'name', 'labels' | construct the cat",
            "alog through ms_catalog(), which slices the snap",
            "shot")
.CS17_LAW_CLAUSES[["V6b-snap-missing-name"]] <- paste0("the channel snapshot must be a list with fields ",
            "name, labels, hash | the snapshot keeps the regi",
            "stry's canonical labels and their digest | recei",
            "ved fields: 'labels', 'hash' | construct the cat",
            "alog through ms_catalog(), which slices the snap",
            "shot")
.CS17_LAW_CLAUSES[["V6c-snap-extra-field"]] <- paste0("the channel snapshot must be a list with fields ",
            "name, labels, hash | the snapshot keeps the regi",
            "stry's canonical labels and their digest | recei",
            "ved fields: 'name', 'labels', 'hash', 'extra' | ",
            "construct the catalog through ms_catalog(), whic",
            "h slices the snapshot")
.CS17_LAW_CLAUSES[["V6d-snap-empty-list"]] <- paste0("the channel snapshot must be a list with fields ",
            "name, labels, hash | the snapshot keeps the regi",
            "stry's canonical labels and their digest | recei",
            "ved fields: (none) | construct the catalog throu",
            "gh ms_catalog(), which slices the snapshot")
.CS17_LAW_CLAUSES[["V7-name-empty"]] <- paste0("the channel snapshot field 'name' must be a sing",
            "le non-empty string | the table name identifies ",
            "the channel set (e.g. SBS96) | received: '' | pa",
            "ss the registry table name, e.g. name = \"SBS96\"")
.CS17_LAW_CLAUSES[["V7b-name-NA"]] <- paste0("the channel snapshot field 'name' must be a sing",
            "le non-empty string | the table name identifies ",
            "the channel set (e.g. SBS96) | received: 'NA' | ",
            "pass the registry table name, e.g. name = \"SBS96",
            "\"")
.CS17_LAW_CLAUSES[["V7c-name-noncharacter"]] <- paste0("the channel snapshot field 'name' must be a sing",
            "le non-empty string | the table name identifies ",
            "the channel set (e.g. SBS96) | received: '5' | p",
            "ass the registry table name, e.g. name = \"SBS96\"")
.CS17_LAW_CLAUSES[["V8-labels-NA-handhash"]] <- paste0("channel labels in the snapshot must be a charact",
            "er vector without NA | channel labels are canoni",
            "cal identities | received: character of length 4",
            " with anyNA = TRUE | pass the canonical labels f",
            "rom the channel registry")
.CS17_LAW_CLAUSES[["V8b-labels-numeric"]] <- paste0("channel labels in the snapshot must be a charact",
            "er vector without NA | channel labels are canoni",
            "cal identities | received: integer of length 4 w",
            "ith anyNA = FALSE | pass the canonical labels fr",
            "om the channel registry")
.CS17_LAW_CLAUSES[["V8c-label-empty-string"]] <- paste0("channel labels in the snapshot must be a charact",
            "er vector without NA | channel labels are canoni",
            "cal identities | received: character of length 4",
            " with anyNA = FALSE | pass the canonical labels ",
            "from the channel registry")
.CS17_LAW_CLAUSES[["V9-snap-labels-dup"]] <- paste0("channel labels in the snapshot must be unique | ",
            "duplicated channel labels are not canonical orde",
            "r | duplicated: 'CH1' | use the canonical regist",
            "ry ordering")
.CS17_LAW_CLAUSES[["V13-hash-nonhex"]] <- paste0("the channel snapshot field 'hash' must be an md5",
            " hex digest | the digest pins the channel table ",
            "inside snapshot summaries (A5) | received: 'ZZzz",
            "0000000000000000000000000000' | let ms_catalog()",
            " compute the hash; do not set it by hand")
.CS17_LAW_CLAUSES[["V13b-hash-noncharacter"]] <- paste0("the channel snapshot field 'hash' must be an md5",
            " hex digest | the digest pins the channel table ",
            "inside snapshot summaries (A5) | received: '42' ",
            "| let ms_catalog() compute the hash; do not set ",
            "it by hand")
.CS17_LAW_CLAUSES[["V13c-hash-NA"]] <- paste0("the channel snapshot field 'hash' must be an md5",
            " hex digest | the digest pins the channel table ",
            "inside snapshot summaries (A5) | received: 'NA' ",
            "| let ms_catalog() compute the hash; do not set ",
            "it by hand")
.CS17_LAW_CLAUSES[["V13d-hash-short-hex"]] <- paste0("the channel snapshot field 'hash' must be an md5",
            " hex digest | the digest pins the channel table ",
            "inside snapshot summaries (A5) | received: 'd3b7",
            "7a574c1e6afda429f0e14afcf4d' | let ms_catalog() ",
            "compute the hash; do not set it by hand")
.CS17_LAW_CLAUSES[["V14-hash-foreign"]] <- paste0("the stored channel hash does not match the store",
            "d labels | snapshot hashes must be derived, not ",
            "asserted | stored: 2b947f5f7703ed9896680aa8bbe27",
            "a7a | rebuild the catalog with ms_catalog()")
.CS17_LAW_CLAUSES[["V10-nrow-vs-labels"]] <- paste0("counts dimensions disagree with the registry sna",
            "pshot or the samples | counts is channels x samp",
            "les | nrow = 3 vs 4 labels; ncol = 2 vs 2 sample",
            "s | align the count matrix with the registry lab",
            "els and sample ids")
.CS17_LAW_CLAUSES[["V10b-ncol-vs-samples"]] <- paste0("counts dimensions disagree with the registry sna",
            "pshot or the samples | counts is channels x samp",
            "les | nrow = 4 vs 4 labels; ncol = 3 vs 2 sample",
            "s | align the count matrix with the registry lab",
            "els and sample ids")
.CS17_LAW_CLAUSES[["V11-rowlabel-decoy-permuted"]] <- paste0("channel labels of counts do not match the regist",
            "ry snapshot | matching is by label, element by e",
            "lement, never by position | first offending labe",
            "ls: 'CH2', 'CH1' | reorder or rename counts rows",
            " to the canonical registry labels")
.CS17_LAW_CLAUSES[["V12-colnames-vs-samples"]] <- paste0("sample labels of counts do not match the samples",
            " property | matching is by label, element by ele",
            "ment, never by position | first offending labels",
            ": 'SX' | align colnames(counts) with the samples",
            " vector")
.CS17_LAW_CLAUSES[["V15-sample-empty"]] <- paste0("sample labels must be non-empty strings without ",
            "NA | sample ids are identities matched by label ",
            "| offending labels: '' | provide one non-empty i",
            "d per sample")
.CS17_LAW_CLAUSES[["V15b-sample-NA"]] <- paste0("sample labels must be non-empty strings without ",
            "NA | sample ids are identities matched by label ",
            "| offending labels: 'NA' | provide one non-empty",
            " id per sample")
.CS17_LAW_CLAUSES[["V16-prov-unnamed"]] <- paste0("catalog provenance must be a named list | proven",
            "ance carries the genome build and tally context ",
            "| received: list | provide at least genome = \"<b",
            "uild>\"")
.CS17_LAW_CLAUSES[["V16b-prov-emptyname"]] <- paste0("catalog provenance must be a named list | proven",
            "ance carries the genome build and tally context ",
            "| received: list | provide at least genome = \"<b",
            "uild>\"")
.CS17_LAW_CLAUSES[["V17-genome-missing"]] <- paste0("catalog provenance must carry the genome build a",
            "s 'genome' | the build is required to query refe",
            "rence signatures | received: (none) | record the",
            " build, e.g. provenance = list(genome = \"GRCh38\"",
            ")")
.CS17_LAW_CLAUSES[["V17b-genome-empty"]] <- paste0("catalog provenance must carry the genome build a",
            "s 'genome' | the build is required to query refe",
            "rence signatures | received: '' | record the bui",
            "ld, e.g. provenance = list(genome = \"GRCh38\")")
.CS17_LAW_CLAUSES[["X1-errorinput-autohash-NAlabels"]] <- paste0("channel labels to hash must be a character vecto",
            "r without NA | the label digest is only defined ",
            "for plain label vectors | received: character wi",
            "th anyNA = TRUE | pass the canonical channel lab",
            "els (character, NA free)")
.CS17_LAW_CLAUSES[["E2-NAinteger-label-trap"]] <- paste0("channel labels to hash must be a character vecto",
            "r without NA | the label digest is only defined ",
            "for plain label vectors | received: character wi",
            "th anyNA = TRUE | pass the canonical channel lab",
            "els (character, NA free)")
.CS17_LAW_CLAUSES[["U1-hashhelper-via-factory-listlabels"]] <- paste0("counts dimensions disagree with the registry sna",
            "pshot or the samples | counts is channels x samp",
            "les | nrow = 4 vs 2 labels; ncol = 2 vs 2 sample",
            "s | align the count matrix with the registry lab",
            "els and sample ids")
.CS17_SPEC_ARMS <- c("A1-accept-core", "A2-accept-skipped-tail-int", "A3-accept-skipped-tail-dbl", "A5-accept-1x1-minimal", "A4-accept-int-plant", "sp-replay-identity")
.CS17_SPEC_CLS <- c("s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog", "s7:character")
.CS17_SPEC_DETAILS <- list()
.CS17_SPEC_DETAILS[["A1-accept-core"]] <- paste0("msuiter::MsCatalog|4|2|double|TRUE|TRUE|d3b77a57",
            "4c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 ch",
            "annels x 2 samples")
.CS17_SPEC_DETAILS[["A2-accept-skipped-tail-int"]] <- paste0("msuiter::MsCatalog|4|2|double|TRUE|TRUE|d3b77a57",
            "4c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 ch",
            "annels x 2 samples; skipped 7/42 variants")
.CS17_SPEC_DETAILS[["A3-accept-skipped-tail-dbl"]] <- paste0("msuiter::MsCatalog|4|2|double|TRUE|TRUE|d3b77a57",
            "4c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 ch",
            "annels x 2 samples; skipped 7/42 variants")
.CS17_SPEC_DETAILS[["A5-accept-1x1-minimal"]] <- paste0("msuiter::MsCatalog|1|1|double|TRUE|TRUE|e10fea09",
            "c4590dfbcf05149c6d3157db|<MsCatalog> CS17T: 1 ch",
            "annels x 1 samples")
.CS17_SPEC_DETAILS[["A4-accept-int-plant"]] <- paste0("msuiter::MsCatalog|4|2|integer|TRUE|TRUE|d3b77a5",
            "74c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 c",
            "hannels x 2 samples")
.CS17_SPEC_DETAILS[["sp-replay-identity"]] <- paste0("msuiter::MsCatalog|4|2|double|TRUE|TRUE|d3b77a57",
            "4c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 ch",
            "annels x 2 samples==msuiter::MsCatalog|4|2|doubl",
            "e|TRUE|TRUE|d3b77a574c1e6afda429f0e14afcf4d1|<Ms",
            "Catalog> CS17T: 4 channels x 2 samples")
.CS17_PREC_ARMS <- c("PR1-anchor-gate-over-validator", "PR1-anti-validator-alone", "PR2-anchor-dims-over-labelmatch", "PR2b-anchor-uniqueness-over-dims", "PR3-anchor-uniqueness-over-finiteness", "PR4-anchor-hashshape-over-truth", "PR5-anchor-namedlaw-over-genomelaw", "PR5-anti-genomelaw-alone", "PR6-anchor-collabel-mismatch-over-samplesanity", "PR6-anti-samplesanity-alone")
.CS17_PREC_CLS <- c("simpleError", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog")
.CS17_PREC_FIRES <- c("- @samples must be <character>, not <integer>", "counts must be a numeric matrix (channels x samples)", "counts dimensions disagree with the registry snapshot or the samples", "channel and sample labels must be unique", "channel and sample labels must be unique", "the channel snapshot field 'hash' must be an md5 hex digest", "catalog provenance must be a named list", "catalog provenance must carry the genome build as 'genome'", "sample labels of counts do not match the samples property", "sample labels must be non-empty strings without NA")
.CS17_PREC_ANTI <- c("counts must be a numeric matrix (channels x samples)", "<msuiter::MsCatalog> object properties are invalid:", "channel and sample labels must be unique", "counts dimensions disagree with the registry snapshot or the samples", "counts must not contain NA or non-finite values", "the stored channel hash does not match the stored labels", "catalog provenance must carry the genome build as 'genome'", "catalog provenance must be a named list", "sample labels must be non-empty strings without NA", "sample labels of counts do not match the samples property")
.CS17_DEGEN_PAIR <- c("empty-boundary", "empty-boundary", "rowlaw-split", "rowlaw-split", "minimal-vs-empty", "minimal-vs-empty", "skipped-tail", "skipped-tail")
.CS17_DEGEN_SIDE <- c("hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo")
.CS17_DEGEN_ARMS <- c("empty-queue-hi", "zero-channels-lo", "rowlabel-uniqueness-hi", "rownames-missing-lo", "minimal-1x1-hi", "empty-4x0-lo", "skipped-tail-hi", "core-nontail-lo")
.CS17_DEGEN_MODE <- c("accept", "reject", "reject", "reject", "accept", "accept", "accept", "accept")
.CS17_DEGEN_CLS <- c("s7:msuiter::MsCatalog", "msuiter_error_catalog", "msuiter_error_catalog", "msuiter_error_catalog", "s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog", "s7:msuiter::MsCatalog")
.CS17_DEGEN_MSG <- list()
.CS17_DEGEN_MSG[["empty-queue-hi"]] <- paste0("msuiter::MsCatalog|4|0|double|TRUE|FALSE|d3b77a5",
            "74c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 c",
            "hannels x 0 samples")
.CS17_DEGEN_MSG[["zero-channels-lo"]] <- paste0("counts must carry both channel labels (rownames)",
            " and sample labels (colnames) | labels are the o",
            "nly legal matching key (never position) | rownam",
            "es missing: TRUE; colnames missing: FALSE | name",
            " the matrix dimensions before constructing MsCat",
            "alog")
.CS17_DEGEN_MSG[["rowlabel-uniqueness-hi"]] <- paste0("channel and sample labels must be unique | dupli",
            "cated labels make label matching ambiguous | dup",
            "licated channel labels: 'CH1'; duplicated sample",
            " labels: (none) | de-duplicate or rename labels")
.CS17_DEGEN_MSG[["rownames-missing-lo"]] <- paste0("counts must carry both channel labels (rownames)",
            " and sample labels (colnames) | labels are the o",
            "nly legal matching key (never position) | rownam",
            "es missing: TRUE; colnames missing: FALSE | name",
            " the matrix dimensions before constructing MsCat",
            "alog")
.CS17_DEGEN_MSG[["minimal-1x1-hi"]] <- paste0("msuiter::MsCatalog|1|1|double|TRUE|TRUE|e10fea09",
            "c4590dfbcf05149c6d3157db|<MsCatalog> CS17T: 1 ch",
            "annels x 1 samples")
.CS17_DEGEN_MSG[["empty-4x0-lo"]] <- paste0("msuiter::MsCatalog|4|0|double|TRUE|FALSE|d3b77a5",
            "74c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 c",
            "hannels x 0 samples")
.CS17_DEGEN_MSG[["skipped-tail-hi"]] <- paste0("msuiter::MsCatalog|4|2|double|TRUE|TRUE|d3b77a57",
            "4c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 ch",
            "annels x 2 samples; skipped 7/42 variants")
.CS17_DEGEN_MSG[["core-nontail-lo"]] <- paste0("msuiter::MsCatalog|4|2|double|TRUE|TRUE|d3b77a57",
            "4c1e6afda429f0e14afcf4d1|<MsCatalog> CS17T: 4 ch",
            "annels x 2 samples")
.CS17_SCAL_KEYS <- c("gate-class", "storage-double", "storage-integer", "hash-canonical", "hash-minimal", "format-core", "tail-int", "tail-dbl", "rng-before", "rng-after")
.CS17_SCAL_VALS <- list()
.CS17_SCAL_VALS[["gate-class"]] <- "simpleError"
.CS17_SCAL_VALS[["storage-double"]] <- "double"
.CS17_SCAL_VALS[["storage-integer"]] <- "integer"
.CS17_SCAL_VALS[["hash-canonical"]] <- "d3b77a574c1e6afda429f0e14afcf4d1"
.CS17_SCAL_VALS[["hash-minimal"]] <- "e10fea09c4590dfbcf05149c6d3157db"
.CS17_SCAL_VALS[["format-core"]] <- "<MsCatalog> CS17T: 4 channels x 2 samples"
.CS17_SCAL_VALS[["tail-int"]] <- paste0("<MsCatalog> CS17T: 4 channels x 2 samples; skipp",
            "ed 7/42 variants")
.CS17_SCAL_VALS[["tail-dbl"]] <- paste0("<MsCatalog> CS17T: 4 channels x 2 samples; skipp",
            "ed 7/42 variants")
.CS17_SCAL_VALS[["rng-before"]] <- "FALSE"
.CS17_SCAL_VALS[["rng-after"]] <- "FALSE"
.CS17_SCAL_REFIRE <- list(

"gate-class" = "MsCatalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = 1:2, provenance = .CS17_PROV)",

"storage-double" = "storage.mode(.cs17_counts())",

"storage-integer" = "storage.mode(.cs17_counts(int = TRUE))",

"hash-canonical" = "msuiter_hash_labels(.CS17_LBL)",

"hash-minimal" = "msuiter_hash_labels(\"CH1\")",

"format-core" = "format(ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV))",

"tail-int" = "format(ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = {p <- .CS17_PROV; p$n_skipped <- 7L; p$n_variants <- 42L; p}))",

"tail-dbl" = "format(ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = {p <- .CS17_PROV; p$n_skipped <- 7; p$n_variants <- 42; p}))"
)
.CS17_ARM <- list(

"G1-channels-nonlist" = "MsCatalog(counts = .cs17_counts(), channels = \"SBS\", samples = .CS17_SAMP, provenance = .CS17_PROV)",

"G2-samples-noncharacter" = "MsCatalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = 1:2, provenance = .CS17_PROV)",

"G3-provenance-nonlist" = "MsCatalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = \"GRCh38\")",

"V1-counts-vector" = "ms_catalog(counts = as.numeric(1:8), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V1b-counts-character-matrix" = "ms_catalog(counts = matrix(c(\"a\", \"b\", \"c\", \"d\"), 2L, 2L, dimnames = list(.CS17_LBL[1:2], .CS17_SAMP)), channels = .cs17_snap(labels = .CS17_LBL[1:2]), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V2-rownames-missing" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(NULL, .CS17_SAMP)), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V2b-colnames-missing" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, NULL)), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V3-rowlabels-dup" = "ms_catalog(counts = .cs17_counts(lab = c(.CS17_LBL[1], .CS17_LBL[1:3])), channels = .cs17_snap(labels = c(.CS17_LBL[1], .CS17_LBL[1:3])), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V3b-collabels-dup" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, c(\"S1\", \"S1\"))), channels = .cs17_snap(), samples = c(\"S1\", \"S1\"), provenance = .CS17_PROV)",

"V4-count-NA" = "ms_catalog(counts = {m <- .cs17_counts(); m[2, 1] <- NA; m}, channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V4b-count-Inf" = "ms_catalog(counts = {m <- .cs17_counts(); m[3, 2] <- Inf; m}, channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V4c-count-NaN" = "ms_catalog(counts = {m <- .cs17_counts(); m[4, 1] <- NaN; m}, channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V5-count-negative" = "ms_catalog(counts = {m <- .cs17_counts(); m[1, 2] <- -7; m}, channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V6-snap-missing-hash" = "MsCatalog(counts = .cs17_counts(), channels = list(name = .CS17_TAB, labels = .CS17_LBL), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V6b-snap-missing-name" = "MsCatalog(counts = .cs17_counts(), channels = list(labels = .CS17_LBL, hash = msuiter_hash_labels(.CS17_LBL)), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V6c-snap-extra-field" = "MsCatalog(counts = .cs17_counts(), channels = c(.cs17_snap(), list(extra = 1)), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V6d-snap-empty-list" = "MsCatalog(counts = .cs17_counts(), channels = list(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V7-name-empty" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$name <- \"\"; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V7b-name-NA" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$name <- NA_character_; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V7c-name-noncharacter" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$name <- 5; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V8-labels-NA-handhash" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(labels = c(.CS17_LBL[1:3], NA_character_), hash = .cs17_zero32()); s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"X1-errorinput-autohash-NAlabels" = "MsCatalog(counts = .cs17_counts(), channels = .cs17_snap(labels = c(.CS17_LBL[1:3], NA_character_)), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V8b-labels-numeric" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$labels <- 1:4; s$hash <- msuiter_hash_labels(as.character(1:4)); s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V8c-label-empty-string" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$labels <- c(.CS17_LBL[1:3], \"\"); s$hash <- msuiter_hash_labels(c(.CS17_LBL[1:3], \"\")); s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V9-snap-labels-dup" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(labels = .CS17_LBL, hash = .cs17_zero32()); s$labels <- c(.CS17_LBL[1:3], .CS17_LBL[1]); s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V13-hash-nonhex" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$hash <- \"ZZzz0000000000000000000000000000\"; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V13b-hash-noncharacter" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$hash <- 42; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V13c-hash-NA" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$hash <- NA_character_; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V13d-hash-short-hex" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$hash <- substr(s$hash, 1L, 31L); s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V14-hash-foreign" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$hash <- msuiter_hash_labels(paste0(\"X\", 1:4)); s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V10-nrow-vs-labels" = "ms_catalog(counts = .cs17_counts(lab = .CS17_LBL[1:3]), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V10b-ncol-vs-samples" = "ms_catalog(counts = matrix(as.numeric(1:12), 4L, 3L, dimnames = list(.CS17_LBL, paste0(\"S\", 1:3))), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V11-rowlabel-decoy-permuted" = "ms_catalog(counts = .cs17_counts(lab = c(.CS17_LBL[2], .CS17_LBL[1], .CS17_LBL[3:4])), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"V12-colnames-vs-samples" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, c(\"S1\", \"SX\"))), channels = .cs17_snap(), samples = c(\"S1\", \"S2\"), provenance = .CS17_PROV)",

"V15-sample-empty" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, c(\"S1\", \"\"))), channels = .cs17_snap(), samples = c(\"S1\", \"\"), provenance = .CS17_PROV)",

"V15b-sample-NA" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, c(\"S1\", NA_character_))), channels = .cs17_snap(), samples = c(\"S1\", NA_character_), provenance = .CS17_PROV)",

"V16-prov-unnamed" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = list(\"GRCh38\"))",

"V16b-prov-emptyname" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = {p <- list(\"GRCh38\"); names(p) <- \"\"; p})",

"V17-genome-missing" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = list(build = \"GRCh38\"))",

"V17b-genome-empty" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = list(genome = \"\"))",

"E1-empty-legal-queue" = "ms_catalog(counts = matrix(numeric(0), length(.CS17_LBL), 0L, dimnames = list(.CS17_LBL, NULL)), channels = .cs17_snap(), samples = character(0), provenance = .CS17_PROV)",

"E1b-zero-channels" = "ms_catalog(counts = matrix(numeric(0), 0L, 0L, dimnames = list(NULL, NULL)), channels = list(name = .CS17_TAB, labels = NULL), samples = character(0), provenance = .CS17_PROV)",

"E2-NAinteger-label-trap" = "ms_catalog(counts = .cs17_counts(lab = c(\"NA\", .CS17_LBL[1:3])), channels = list(name = .CS17_TAB, labels = c(NA_integer_, .CS17_LBL[1:3])), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"PR1-anchor-gate-over-validator" = "MsCatalog(counts = as.numeric(1:8), channels = .cs17_snap(), samples = 1:2, provenance = .CS17_PROV)",

"PR1-anti-validator-alone" = "ms_catalog(counts = as.numeric(1:8), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"PR2-anchor-dims-over-labelmatch" = "ms_catalog(counts = .cs17_counts(lab = c(.CS17_LBL[2], .CS17_LBL[1], .CS17_LBL[3])), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"PR2b-anchor-uniqueness-over-dims" = "ms_catalog(counts = .cs17_counts(lab = c(.CS17_LBL[1], .CS17_LBL[1], .CS17_LBL[2])), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"PR3-anchor-uniqueness-over-finiteness" = "ms_catalog(counts = {m <- .cs17_counts(lab = c(.CS17_LBL[1], .CS17_LBL[1:3])); m[1, 1] <- NA; m}, channels = .cs17_snap(labels = c(.CS17_LBL[1], .CS17_LBL[1:3])), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"PR4-anchor-hashshape-over-truth" = "MsCatalog(counts = .cs17_counts(), channels = {s <- .cs17_snap(); s$hash <- \"nothex00000000000000000000000000\"; s}, samples = .CS17_SAMP, provenance = .CS17_PROV)",

"PR5-anchor-namedlaw-over-genomelaw" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = list(\"GRCh38\"))",

"PR5-anti-genomelaw-alone" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = list(build = \"GRCh38\"))",

"PR6-anchor-collabel-mismatch-over-samplesanity" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, c(\"S1\", \"SX\"))), channels = .cs17_snap(), samples = c(\"S1\", NA_character_), provenance = .CS17_PROV)",

"PR6-anti-samplesanity-alone" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(.CS17_LBL, c(\"S1\", NA_character_))), channels = .cs17_snap(), samples = c(\"S1\", NA_character_), provenance = .CS17_PROV)",

"A1-accept-core" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"A2-accept-skipped-tail-int" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = {p <- .CS17_PROV; p$n_skipped <- 7L; p$n_variants <- 42L; p})",

"A3-accept-skipped-tail-dbl" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = {p <- .CS17_PROV; p$n_skipped <- 7; p$n_variants <- 42; p})",

"A5-accept-1x1-minimal" = "ms_catalog(counts = matrix(1, 1L, 1L, dimnames = list(\"CH1\", \"S1\")), channels = list(name = \"CS17T\", labels = \"CH1\"), samples = \"S1\", provenance = .CS17_PROV)",

"A4-accept-int-plant" = "ms_catalog(counts = {mm <- matrix(1:8, 4L, 2L, dimnames = list(.CS17_LBL, .CS17_SAMP)); mm}, channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)",

"sp-replay-identity" = "paste0(.cs17_render(ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)), \"==\", .cs17_render(ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)))",

"U1-hashhelper-via-factory-listlabels" = "ms_catalog(counts = .cs17_counts(), channels = list(name = .CS17_TAB, labels = list(1, 2)), samples = .CS17_SAMP, provenance = .CS17_PROV)"
,
"empty-queue-hi" = "ms_catalog(counts = matrix(numeric(0), length(.CS17_LBL), 0L, dimnames = list(.CS17_LBL, NULL)), channels = .cs17_snap(), samples = character(0), provenance = .CS17_PROV)"
,
"zero-channels-lo" = "ms_catalog(counts = matrix(numeric(0), 0L, 0L, dimnames = list(NULL, NULL)), channels = list(name = .CS17_TAB, labels = NULL), samples = character(0), provenance = .CS17_PROV)"
,
"rowlabel-uniqueness-hi" = "ms_catalog(counts = .cs17_counts(lab = c(.CS17_LBL[1], .CS17_LBL[1:3])), channels = .cs17_snap(labels = c(.CS17_LBL[1], .CS17_LBL[1:3])), samples = .CS17_SAMP, provenance = .CS17_PROV)"
,
"rownames-missing-lo" = "ms_catalog(counts = matrix(as.numeric(1:8), 4L, 2L, dimnames = list(NULL, .CS17_SAMP)), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)"
,
"minimal-1x1-hi" = "ms_catalog(counts = matrix(1, 1L, 1L, dimnames = list(\"CH1\", \"S1\")), channels = list(name = \"CS17T\", labels = \"CH1\"), samples = \"S1\", provenance = .CS17_PROV)"
,
"empty-4x0-lo" = "ms_catalog(counts = matrix(numeric(0), length(.CS17_LBL), 0L, dimnames = list(.CS17_LBL, NULL)), channels = .cs17_snap(), samples = character(0), provenance = .CS17_PROV)"
,
"skipped-tail-hi" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = {p <- .CS17_PROV; p$n_skipped <- 7L; p$n_variants <- 42L; p})"
,
"core-nontail-lo" = "ms_catalog(counts = .cs17_counts(), channels = .cs17_snap(), samples = .CS17_SAMP, provenance = .CS17_PROV)"
)
.CS17_CENSUS <- c("msuiter_error_catalog=49", "msuiter_error_input=2", "s7:character=1", "s7:msuiter::MsCatalog=10", "simpleError=4")
## <<CS17-FROZEN-END>> ##

## <<CS17-SHARED-BEGIN>>  (single source: injected byte-identically into
##    the law file and the runner; edit /tmp/p6gate/cs17-shared.R and
##    re-splice via splice-cs17.R -- never hand-edit in place)
## cs17-shared.R -- single source of the CS-17 catalog-witness shared block.
## Injected byte-identically into tests/testthat/test-scenario-catalog-witness.R
## and bench/scenarios/run_catalog_witness.R between the SHARED markers.
## Pure, deterministic, no RNG, no clock, no network: the condition-message
## pipeline plus the exported-face verdict render and the plant builders the
## frozen ARM texts call.
.cs17_describe <- function(e) trimws(gsub("\n", " | ",
  paste(as.character(conditionMessage(e)), collapse = " | "), fixed = TRUE))
.cs17_strip <- function(s) {
  for (b in c("ℹ ", "i ")) s <- gsub(b, "", s, fixed = TRUE)
  s
}
.cs17_render <- function(x) paste0(c(
  paste0(class(x)[1L]),
  paste0(nrow(x@counts)), paste0(ncol(x@counts)),
  storage.mode(x@counts),
  paste0(identical(rownames(x@counts), x@channels$labels)),
  paste0(identical(colnames(x@counts), x@samples)),
  x@channels$hash,
  format(x)), collapse = "|")
.cs17_eval1 <- function(txt, tag) {
  if (is.na(txt) || !nzchar(txt)) stop(".cs17_eval1: no text for ", tag)
  ex <- parse(text = txt)
  if (length(ex) != 1L) {
    stop(".cs17_eval1: ", tag, " is not a single expression")
  }
  tryCatch(list(ok = TRUE, v = eval(ex[[1L]])), error = identity)
}
.cs17_verdict <- function(arm, r) {
  if (inherits(r, "error")) {
    list(arm = arm, mode = "reject", cls = class(r)[1L],
         msg = gsub("\t", " ", .cs17_strip(.cs17_describe(r)), fixed = TRUE))
  } else {
    rendered <- if (is.character(r)) r else .cs17_render(r)
    list(arm = arm, mode = "accept", cls = paste0("s7:", class(r)[1L]),
         msg = gsub("\t", " ", rendered, fixed = TRUE))
  }
}
.cs17_fire <- function(arm) {
  r <- .cs17_eval1(.CS17_ARM[[arm]], arm)
  .cs17_verdict(arm, if (inherits(r, "error")) r else r$v)
}
.cs17_clean <- function(df) {
  ## witness bytes round-trip nameless through read.csv; strip any vapply
  ## residue names so identical() compares columns byte-true
  for (cnm in names(df)) attr(df[[cnm]], "names") <- NULL
  df
}
.cs17_rows <- function(arms) {
  vs <- lapply(arms, function(a) .cs17_fire(a))
  .cs17_clean(data.frame(arm = arms,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs17_lawrows <- function() .cs17_rows(.CS17_LAW_ARMS)
.cs17_specrows <- function() .cs17_rows(.CS17_SPEC_ARMS)
.cs17_precrows <- function() {
  base <- .cs17_rows(.CS17_PREC_ARMS)
  base$fires_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(grepl(.CS17_PREC_FIRES[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base$anti_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(!grepl(.CS17_PREC_ANTI[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base
}
.cs17_degenrows <- function() {
  vs <- lapply(.CS17_DEGEN_ARMS, function(a) .cs17_fire(a))
  .cs17_clean(data.frame(pair = .CS17_DEGEN_PAIR, side = .CS17_DEGEN_SIDE,
             arm = .CS17_DEGEN_ARMS,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs17_scalval <- function(k) {
  txt <- .CS17_SCAL_REFIRE[[k]]
  if (is.null(txt)) return(NA_character_)
  res <- .cs17_eval1(txt, k)
  if (inherits(res, "error")) {
    if (identical(k, "gate-class")) return(paste0(class(res)[1L]))
    return(.cs17_strip(.cs17_describe(res)))
  }
  paste0(res$v)
}
.cs17_scalref_keys <- function() names(.CS17_SCAL_REFIRE)
.cs17_plant_text <- function() {
  ord <- c(.CS17_LAW_ARMS, .CS17_SPEC_ARMS, .CS17_PREC_ARMS, .CS17_DEGEN_ARMS)
  paste0(vapply(ord, function(a)
    paste0(a, "=", .CS17_ARM[[a]]), character(1L)), collapse = ";")
}
.cs17_spec_text <- function() paste0(.CS17_SPEC_ARMS, collapse = ";")
## ---- deterministic plant builders (no RNG, no clock, no network) ----------
.CS17_TAB <- "CS17T"
.CS17_LBL <- c("CH1", "CH2", "CH3", "CH4")
.CS17_SAMP <- c("S1", "S2")
.CS17_PROV <- list(genome = "GRCh38")
.cs17_counts <- function(lab = .CS17_LBL, smp = .CS17_SAMP, int = FALSE) {
  nr <- length(lab); nc <- length(smp)
  vals <- if (nr * nc == 0L) {
    if (int) integer(0L) else numeric(0L)
  } else if (int) {
    seq_len(nr * nc)
  } else {
    as.numeric(seq_len(nr * nc))
  }
  matrix(vals, nr, nc,
         dimnames = list(if (nr) lab else NULL, if (nc) smp else NULL))
}
.cs17_snap <- function(name = .CS17_TAB, labels = .CS17_LBL, hash = NULL) {
  if (is.null(hash)) hash <- msuiter_hash_labels(as.character(labels))
  list(name = name, labels = labels, hash = hash)
}
.cs17_zero32 <- function() paste0(rep_len("0", 32L), collapse = "")
## <<CS17-SHARED-END>>  (do not hand-edit in place: edit the source and
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

laws <- .cs17_lawrows()
stopif(!identical(laws$arm, .CS17_LAW_ARMS), "laws: roster drift")
stopif(!identical(laws$mode, rep("reject", 42L)), "laws: a mode drift")
stopif(!identical(laws$cls, .CS17_LAW_CLS), "laws: a class drift")
stopif(!identical(laws$msg, unname(vapply(.CS17_LAW_ARMS,
  function(a) .CS17_LAW_CLAUSES[[a]], character(1L)))), "laws: clause byte drift")
.census("laws", laws, 42L)

specs <- .cs17_specrows()
stopif(!identical(specs$arm, .CS17_SPEC_ARMS), "specs: roster drift")
stopif(!identical(specs$mode, rep("accept", 6L)), "specs: a mode drift")
stopif(!identical(specs$cls, .CS17_SPEC_CLS), "specs: a class drift")
stopif(!identical(specs$msg, unname(vapply(.CS17_SPEC_ARMS,
  function(a) .CS17_SPEC_DETAILS[[a]], character(1L)))), "specs: detail byte drift")
stopif(!identical(specs$msg[match("A2-accept-skipped-tail-int", specs$arm)],
                   specs$msg[match("A3-accept-skipped-tail-dbl", specs$arm)]),
       "specs: dual-kernel tail disagreement")
stopif(!grepl("|integer|", specs$msg[match("A4-accept-int-plant", specs$arm)],
              fixed = TRUE), "specs: the integer plant lost its storage glyph")
.census("specs", specs, 6L)

prec <- .cs17_precrows()
stopif(!identical(prec$arm, .CS17_PREC_ARMS), "prec: roster drift")
stopif(!identical(prec$mode, rep("reject", 10L)), "prec: a mode drift")
stopif(!identical(prec$cls, .CS17_PREC_CLS), "prec: a class drift")
stopif(!all(prec$fires_ok == "TRUE"), "prec: a fired anchor missing")
stopif(!all(prec$anti_ok == "TRUE"), "prec: an anti anchor present")
for (i in seq_len(10L)) {
  stopif(!grepl(.CS17_PREC_FIRES[i], prec$msg[i], fixed = TRUE),
         paste0("prec: fire anchor absent in ", .CS17_PREC_ARMS[i]))
  stopif(grepl(.CS17_PREC_ANTI[i], prec$msg[i], fixed = TRUE),
         paste0("prec: anti anchor present in ", .CS17_PREC_ARMS[i]))
}
.census("prec", prec, 10L)

degen <- .cs17_degenrows()
stopif(!identical(degen$pair, .CS17_DEGEN_PAIR), "degen: pair drift")
stopif(!identical(degen$side, .CS17_DEGEN_SIDE), "degen: side drift")
stopif(!identical(degen$arm, .CS17_DEGEN_ARMS), "degen: arm drift")
stopif(!identical(degen$mode, .CS17_DEGEN_MODE), "degen: mode drift")
stopif(!identical(degen$cls, .CS17_DEGEN_CLS), "degen: class drift")
stopif(!identical(degen$msg, unname(vapply(.CS17_DEGEN_ARMS,
  function(a) .CS17_DEGEN_MSG[[a]], character(1L)))), "degen: msg byte drift")
.w <- function(arm) degen$msg[match(arm, degen$arm)]
stopif(!grepl("; skipped 7/42 variants", .w("skipped-tail-hi"), fixed = TRUE),
       "degen: the skipped tail fell off the hi side")
stopif(grepl("; skipped 7/42 variants", .w("core-nontail-lo"), fixed = TRUE),
       "degen: the skipped tail rode the lo side")
stopif(!grepl("|4|0|", .w("empty-queue-hi"), fixed = TRUE),
       "degen: the legal empty queue lost its shape")
stopif(!grepl("|4|0|double|TRUE|FALSE|", .w("empty-4x0-lo"), fixed = TRUE),
       "degen: the zero-column identity bit moved")
.census("degen", degen, 8L, key.col = 3L)

rng1 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
scal.vals <- vapply(.CS17_SCAL_KEYS, function(k) {
  if (identical(k, "rng-before")) return(format(rng0))
  if (identical(k, "rng-after")) return(format(rng1))
  v <- .cs17_scalval(k)
  stopif(is.na(v) || !nzchar(v), paste0("scalars: empty re-fire for ", k))
  stopif(!identical(v, .CS17_SCAL_VALS[[k]]), paste0("scalars: drift for ", k))
  v
}, character(1L))
scalars <- data.frame(key = .CS17_SCAL_KEYS, value = unname(scal.vals),
                      stringsAsFactors = FALSE)
stopif(!identical(scalars$value[match("rng-before", .CS17_SCAL_KEYS)],
                  .CS17_SCAL_VALS[["rng-before"]]), "scalars: rng-before drift")
stopif(!identical(scalars$value[match("rng-after", .CS17_SCAL_KEYS)],
                  .CS17_SCAL_VALS[["rng-after"]]), "scalars: rng-after drift")
stopif(!identical(scalars$value[match("tail-int", .CS17_SCAL_KEYS)],
                  scalars$value[match("tail-dbl", .CS17_SCAL_KEYS)]),
       "scalars: the dual-kernel tails disagree")
.census("scalars", scalars, 10L)

## dual-kernel hashes over the frozen corpora (written nowhere, attested)
plant.sha <- .ck(charToRaw(.cs17_plant_text()), "plant-corpus")
spec.sha <- .ck(charToRaw(.cs17_spec_text()), "spec-corpus")

## ---------------------------------------------------------------------------
## all censuses spoke: commit the five witnesses
## ---------------------------------------------------------------------------
.wtab("cs17_laws.tsv", laws)
.wtab("cs17_specs.tsv", specs)
.wtab("cs17_precedence.tsv", prec)
.wtab("cs17_degenerates.tsv", degen)
.wtab("cs17_scalars.tsv", scalars)

cat("[attest] at=", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    " out=", OUT, "\n", sep = "")
for (nm in c("cs17_laws.tsv", "cs17_specs.tsv", "cs17_precedence.tsv",
             "cs17_degenerates.tsv", "cs17_scalars.tsv")) {
  cat("[attest] sha256 ", nm, "=", .file.sha(nm), "\n", sep = "")
}
cat("[attest] plant_sha256=", plant.sha, " spec_sha256=", spec.sha,
    " files=", length(list.files(OUT, pattern = "^cs17_")), "\n", sep = "")
cat("OVERALL PASS\n")
quit(save = "no", status = 0L)
