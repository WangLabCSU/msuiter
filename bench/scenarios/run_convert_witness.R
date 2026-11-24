# run_convert_witness.R -- the CS-18 convert-witness scenario (pillar 3).
#
# Mandate: plant synthetic signature-and-opportunity calls (the D3 law: zero
# COSMIC numeric matrices, zero real-data bytes, zero downloads -- the
# opportunity tables ride only as named frequency vectors over the registry
# labels) and adjudicate the EXPORTED ms_convert()/MsSignature face: the
# ten-arm "option"/"input" validator split over the from/to arguments, the
# accepted re-expression shapes, the precedence discriminators with their
# anti anchors, the boundary contrast pairs and the acceptance specs. Every
# arm is driven through the exported faces alone; the accepted returns, the
# abort classes and the fired clauses are the face's own. The scenario
# consumes no RNG, no network and no clock at the adjudication core; the
# benchmark runner and the DECLINED calibration family are never invoked
# here.
#
# Framing law: DECISION RECORD only. The witnesses under out/ are the
# committed verdict of what the shipped face SAID on planted truth. Float
# posture (D11): the face returns a real matrix whose kernel error is ~1e-16,
# so no float payload rides any witness -- the accepted render commits a
# DISCRETE column-sum glyph (0/1/? at a 1e-9 threshold, seven orders above
# the observed float error), which is a cross-platform label; integer, label,
# logical, class and clause bytes are byte-committed.
#
# Rails: this runner carries the same frozen block as the law file
# (tests/testthat/test-scenario-convert-witness.R), injected byte-identically
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
## <<CS18-FROZEN-BEGIN>>  (minted mechanically from the audited ledger
##    2026-11-25; DO NOT hand-edit: regenerate via cs18-mint3.R) ##
.CS18_LAW_ARMS <- c("L1-unknown-from", "L2-unknown-to", "L3-multicol-matrix", "L4-wrong-length", "L5-names-mismatch", "L6-nonpositive", "L7-nonfinite", "L8-nonmatrix", "L9-wrong-rownames", "L10-no-rownames")
.CS18_LAW_CLS <- c("msuiter_error_option", "msuiter_error_option", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS18_LAW_CLAUSES <- list()
.CS18_LAW_CLAUSES[["L1-unknown-from"]] <- "from must be a bundled table or a custom frequency vector | panel opportunities are expected as a custom 96-vector ([V] discipline: no bundled panel table) | received: 'nope'; bundled: human-genome, human-exome | pass a named numeric vector for custom opportunities"
.CS18_LAW_CLAUSES[["L2-unknown-to"]] <- "to must be a bundled table or a custom frequency vector | panel opportunities are expected as a custom 96-vector ([V] discipline: no bundled panel table) | received: 'nope'; bundled: human-genome, human-exome | pass a named numeric vector for custom opportunities"
.CS18_LAW_CLAUSES[["L3-multicol-matrix"]] <- "from matrix must have exactly one frequency column | the opportunity is a single 96-vector, not per-signature | received: 2 columns | repeat the column yourself for per-signature opportunities"
.CS18_LAW_CLAUSES[["L4-wrong-length"]] <- "from must be a frequency vector over the 96 channels | an opportunity vector is one frequency per registry channel | received length: 10 | name it by the registry labels or pass a bundled table name"
.CS18_LAW_CLAUSES[["L5-names-mismatch"]] <- "from names must equal the SBS96 registry labels | opportunities are matched by label, never by position | first names: 'X1', 'X2', 'X3' | set names(opps) to the registry labels"
.CS18_LAW_CLAUSES[["L6-nonpositive"]] <- "from must be positive and finite | an opportunity of 0 makes the division undefined | offending entries: 1 | opportunity tables are strictly positive frequencies"
.CS18_LAW_CLAUSES[["L7-nonfinite"]] <- "from must be positive and finite | an opportunity of 0 makes the division undefined | offending entries: 1 | opportunity tables are strictly positive frequencies"
.CS18_LAW_CLAUSES[["L8-nonmatrix"]] <- "signatures must be a numeric matrix | ms_convert() re-expresses SBS96 signatures between opportunities | received: character | pass 96 x k with registry rownames (or an MsSignature)"
.CS18_LAW_CLAUSES[["L9-wrong-rownames"]] <- "signatures must carry the SBS96 registry rownames in canonical order | the opportunity tables are matched by label, never by position | first rownames: 'R1', 'R2', 'R3' | order the matrix by the registry labels"
.CS18_LAW_CLAUSES[["L10-no-rownames"]] <- "signatures must carry the SBS96 registry rownames in canonical order | the opportunity tables are matched by label, never by position | rownames missing | order the matrix by the registry labels"
.CS18_SPEC_ARMS <- c("A1-accept-core", "A2-accept-conv", "A3-accept-rev", "S1-accept-custom-vec", "S2-accept-custom-both", "S3-accept-zero-col", "S4-accept-onecol-matrix", "S5-accept-int-vec", "A6-accept-msg-signature", "sp-replay-identity")
.CS18_SPEC_CLS <- c("s7:matrix", "s7:matrix", "s7:matrix", "s7:matrix", "s7:matrix", "s7:matrix", "s7:matrix", "s7:matrix", "s7:msuiter::MsSignature", "s7:character")
.CS18_SPEC_DETAILS <- list()
.CS18_SPEC_DETAILS[["A1-accept-core"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["A2-accept-conv"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["A3-accept-rev"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["S1-accept-custom-vec"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["S2-accept-custom-both"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["S3-accept-zero-col"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,0,1"
.CS18_SPEC_DETAILS[["S4-accept-onecol-matrix"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["S5-accept-int-vec"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SPEC_DETAILS[["A6-accept-msg-signature"]] <- "MsSignature|96x3|double|1,1,1|3x2"
.CS18_SPEC_DETAILS[["sp-replay-identity"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1==matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_PREC_ARMS <- c("PR1-anchor-sigshape-over-fromopt", "PR1-anti-fromopt-alone", "PR2-anchor-rownames-over-toopt", "PR2-anti-toopt-alone", "PR3-anchor-from-over-to", "PR3-anti-to-over-from", "PR4-anchor-length-over-names", "PR4-anti-names-alone", "PR5-anchor-multicol-over-names", "PR5-anti-names-over-multicol")
.CS18_PREC_CLS <- c("msuiter_error_input", "msuiter_error_option", "msuiter_error_input", "msuiter_error_option", "msuiter_error_option", "msuiter_error_option", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS18_PREC_FIRES <- c("signatures must be a numeric matrix", "from must be a bundled table", "signatures must carry the SBS96 registry rownames", "to must be a bundled table", "from must be a bundled table", "to must be a bundled table", "must be a frequency vector over the 96 channels", "names must equal the SBS96 registry labels", "matrix must have exactly one frequency column", "names must equal the SBS96 registry labels")
.CS18_PREC_ANTI <- c("from must be a bundled table", "signatures must be a numeric matrix", "to must be a bundled table", "signatures must carry the SBS96 registry rownames", "to must be a bundled table", "from must be a bundled table", "names must equal the SBS96 registry labels", "must be a frequency vector over the 96 channels", "names must equal the SBS96 registry labels", "matrix must have exactly one frequency column")
.CS18_DEGEN_PAIR <- c("zero-column-glyph", "zero-column-glyph", "onecol-vs-multicol", "onecol-vs-multicol", "fromopt-vs-toopt", "fromopt-vs-toopt", "shape-vs-names", "shape-vs-names")
.CS18_DEGEN_SIDE <- c("hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo")
.CS18_DEGEN_ARMS <- c("zero-col-hi", "full-col-lo", "onecol-matrix-hi", "multicol-matrix-lo", "from-bad-hi", "to-bad-lo", "nonmatrix-hi", "wrongnames-lo")
.CS18_DEGEN_MODE <- c("accept", "accept", "accept", "reject", "reject", "reject", "reject", "reject")
.CS18_DEGEN_CLS <- c("s7:matrix", "s7:matrix", "s7:matrix", "msuiter_error_input", "msuiter_error_option", "msuiter_error_option", "msuiter_error_input", "msuiter_error_input")
.CS18_DEGEN_MSG <- list()
.CS18_DEGEN_MSG[["zero-col-hi"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,0,1"
.CS18_DEGEN_MSG[["full-col-lo"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_DEGEN_MSG[["onecol-matrix-hi"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_DEGEN_MSG[["multicol-matrix-lo"]] <- "from matrix must have exactly one frequency column | the opportunity is a single 96-vector, not per-signature | received: 2 columns | repeat the column yourself for per-signature opportunities"
.CS18_DEGEN_MSG[["from-bad-hi"]] <- "from must be a bundled table or a custom frequency vector | panel opportunities are expected as a custom 96-vector ([V] discipline: no bundled panel table) | received: 'nope'; bundled: human-genome, human-exome | pass a named numeric vector for custom opportunities"
.CS18_DEGEN_MSG[["to-bad-lo"]] <- "to must be a bundled table or a custom frequency vector | panel opportunities are expected as a custom 96-vector ([V] discipline: no bundled panel table) | received: 'nada'; bundled: human-genome, human-exome | pass a named numeric vector for custom opportunities"
.CS18_DEGEN_MSG[["nonmatrix-hi"]] <- "signatures must be a numeric matrix | ms_convert() re-expresses SBS96 signatures between opportunities | received: character | pass 96 x k with registry rownames (or an MsSignature)"
.CS18_DEGEN_MSG[["wrongnames-lo"]] <- "from names must equal the SBS96 registry labels | opportunities are matched by label, never by position | first names: 'Y1', 'Y2', 'Y3' | set names(opps) to the registry labels"
.CS18_SCAL_KEYS <- c("abort-class", "matrix-render", "msgsig-render", "glyph-full", "glyph-zero", "roundtrip-under-tol", "same-under-tol", "storage-double", "rng-before", "rng-after")
.CS18_SCAL_VALS <- list()
.CS18_SCAL_VALS[["abort-class"]] <- "msuiter_error_input"
.CS18_SCAL_VALS[["matrix-render"]] <- "matrix|96x3|double|TRUE|S1,S2,S3|1,1,1"
.CS18_SCAL_VALS[["msgsig-render"]] <- "MsSignature|96x3|double|1,1,1|3x2"
.CS18_SCAL_VALS[["glyph-full"]] <- "1,1,1"
.CS18_SCAL_VALS[["glyph-zero"]] <- "1,0,1"
.CS18_SCAL_VALS[["roundtrip-under-tol"]] <- "TRUE"
.CS18_SCAL_VALS[["same-under-tol"]] <- "TRUE"
.CS18_SCAL_VALS[["storage-double"]] <- "double"
.CS18_SCAL_VALS[["rng-before"]] <- "FALSE"
.CS18_SCAL_VALS[["rng-after"]] <- "FALSE"
.CS18_SCAL_REFIRE <- list()
.CS18_SCAL_REFIRE[["abort-class"]] <- "ms_convert(as.character(seq_len(8L)), from = \"human-genome\", to = \"human-exome\")"
.CS18_SCAL_REFIRE[["matrix-render"]] <- ".cs18_render(ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-exome\"))"
.CS18_SCAL_REFIRE[["msgsig-render"]] <- ".cs18_render(ms_convert(.cs18_obj(), from = \"human-genome\", to = \"human-exome\"))"
.CS18_SCAL_REFIRE[["glyph-full"]] <- ".cs18_cs(ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-exome\"))"
.CS18_SCAL_REFIRE[["glyph-zero"]] <- "{ s <- .cs18_sig(3L); s[, 2L] <- 0; .cs18_cs(ms_convert(s, from = \"human-genome\", to = \"human-exome\")) }"
.CS18_SCAL_REFIRE[["roundtrip-under-tol"]] <- "{ o <- ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-exome\"); b <- ms_convert(o, from = \"human-exome\", to = \"human-genome\"); max(abs(b - .cs18_sig(3L))) < 1e-9 }"
.CS18_SCAL_REFIRE[["same-under-tol"]] <- "{ o <- ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-genome\"); max(abs(o - .cs18_sig(3L))) < 1e-9 }"
.CS18_SCAL_REFIRE[["storage-double"]] <- "storage.mode(ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-exome\"))"
.CS18_ARM <- list()
.CS18_ARM[["L1-unknown-from"]] <- "ms_convert(.cs18_sig(3L), from = \"nope\", to = \"human-exome\")"
.CS18_ARM[["L2-unknown-to"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"nope\")"
.CS18_ARM[["L3-multicol-matrix"]] <- "ms_convert(.cs18_sig(3L), from = matrix(1, length(.cs18_reg()), 2L), to = \"human-exome\")"
.CS18_ARM[["L4-wrong-length"]] <- "ms_convert(.cs18_sig(3L), from = rep(1, 10L), to = \"human-exome\")"
.CS18_ARM[["L5-names-mismatch"]] <- "{ v <- stats::setNames(rep(1, length(.cs18_reg())), paste0(\"X\", seq_along(.cs18_reg()))); ms_convert(.cs18_sig(3L), from = v, to = \"human-exome\") }"
.CS18_ARM[["L6-nonpositive"]] <- "{ v <- .cs18_nv(rep(1, length(.cs18_reg()))); v[1L] <- 0; ms_convert(.cs18_sig(3L), from = v, to = \"human-exome\") }"
.CS18_ARM[["L7-nonfinite"]] <- "{ v <- .cs18_nv(rep(1, length(.cs18_reg()))); v[1L] <- Inf; ms_convert(.cs18_sig(3L), from = v, to = \"human-exome\") }"
.CS18_ARM[["L8-nonmatrix"]] <- "ms_convert(as.character(seq_len(8L)), from = \"human-genome\", to = \"human-exome\")"
.CS18_ARM[["L9-wrong-rownames"]] <- "{ s <- .cs18_sig(3L); rownames(s) <- paste0(\"R\", seq_len(nrow(s))); ms_convert(s, from = \"human-genome\", to = \"human-exome\") }"
.CS18_ARM[["L10-no-rownames"]] <- "{ s <- .cs18_sig(3L); rownames(s) <- NULL; ms_convert(s, from = \"human-genome\", to = \"human-exome\") }"
.CS18_ARM[["A1-accept-core"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-genome\")"
.CS18_ARM[["A2-accept-conv"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-exome\")"
.CS18_ARM[["A3-accept-rev"]] <- "ms_convert(.cs18_sig(3L), from = \"human-exome\", to = \"human-genome\")"
.CS18_ARM[["S1-accept-custom-vec"]] <- "ms_convert(.cs18_sig(3L), from = .cs18_nv(rep(1, length(.cs18_reg()))), to = \"human-exome\")"
.CS18_ARM[["S2-accept-custom-both"]] <- "ms_convert(.cs18_sig(3L), from = .cs18_nv(rep(1, length(.cs18_reg()))), to = .cs18_nv(rep(2, length(.cs18_reg()))))"
.CS18_ARM[["S3-accept-zero-col"]] <- "{ s <- .cs18_sig(3L); s[, 2L] <- 0; ms_convert(s, from = \"human-genome\", to = \"human-exome\") }"
.CS18_ARM[["S4-accept-onecol-matrix"]] <- "{ m <- matrix(1, length(.cs18_reg()), 1L, dimnames = list(.cs18_reg(), \"S1\")); ms_convert(.cs18_sig(3L), from = m, to = \"human-exome\") }"
.CS18_ARM[["S5-accept-int-vec"]] <- "ms_convert(.cs18_sig(3L), from = .cs18_nv(rep(1L, length(.cs18_reg()))), to = \"human-exome\")"
.CS18_ARM[["A6-accept-msg-signature"]] <- "ms_convert(.cs18_obj(), from = \"human-genome\", to = \"human-exome\")"
.CS18_ARM[["sp-replay-identity"]] <- "paste0(.cs18_render(ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-genome\")), \"==\", .cs18_render(ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-genome\")))"
.CS18_ARM[["PR1-anchor-sigshape-over-fromopt"]] <- "ms_convert(as.character(seq_len(8L)), from = \"nope\", to = \"human-exome\")"
.CS18_ARM[["PR1-anti-fromopt-alone"]] <- "ms_convert(.cs18_sig(3L), from = \"nope\", to = \"human-exome\")"
.CS18_ARM[["PR2-anchor-rownames-over-toopt"]] <- "{ s <- .cs18_sig(3L); rownames(s) <- paste0(\"R\", seq_len(nrow(s))); ms_convert(s, from = \"human-genome\", to = \"nope\") }"
.CS18_ARM[["PR2-anti-toopt-alone"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"nope\")"
.CS18_ARM[["PR3-anchor-from-over-to"]] <- "ms_convert(.cs18_sig(3L), from = \"nope\", to = \"nada\")"
.CS18_ARM[["PR3-anti-to-over-from"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"nada\")"
.CS18_ARM[["PR4-anchor-length-over-names"]] <- "{ v <- stats::setNames(rep(1, 10L), paste0(\"X\", seq_len(10L))); ms_convert(.cs18_sig(3L), from = v, to = \"human-exome\") }"
.CS18_ARM[["PR4-anti-names-alone"]] <- "{ v <- stats::setNames(rep(1, length(.cs18_reg())), paste0(\"Y\", seq_along(.cs18_reg()))); ms_convert(.cs18_sig(3L), from = v, to = \"human-exome\") }"
.CS18_ARM[["PR5-anchor-multicol-over-names"]] <- "{ m <- matrix(1, length(.cs18_reg()), 2L); rownames(m) <- paste0(\"Z\", seq_len(nrow(m))); ms_convert(.cs18_sig(3L), from = m, to = \"human-exome\") }"
.CS18_ARM[["PR5-anti-names-over-multicol"]] <- "{ m <- matrix(1, length(.cs18_reg()), 1L); rownames(m) <- paste0(\"W\", seq_len(nrow(m))); ms_convert(.cs18_sig(3L), from = m, to = \"human-exome\") }"
.CS18_ARM[["zero-col-hi"]] <- "{ s <- .cs18_sig(3L); s[, 2L] <- 0; ms_convert(s, from = \"human-genome\", to = \"human-exome\") }"
.CS18_ARM[["full-col-lo"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"human-exome\")"
.CS18_ARM[["onecol-matrix-hi"]] <- "{ m <- matrix(1, length(.cs18_reg()), 1L, dimnames = list(.cs18_reg(), \"S1\")); ms_convert(.cs18_sig(3L), from = m, to = \"human-exome\") }"
.CS18_ARM[["multicol-matrix-lo"]] <- "ms_convert(.cs18_sig(3L), from = matrix(1, length(.cs18_reg()), 2L), to = \"human-exome\")"
.CS18_ARM[["from-bad-hi"]] <- "ms_convert(.cs18_sig(3L), from = \"nope\", to = \"human-exome\")"
.CS18_ARM[["to-bad-lo"]] <- "ms_convert(.cs18_sig(3L), from = \"human-genome\", to = \"nada\")"
.CS18_ARM[["nonmatrix-hi"]] <- "ms_convert(as.character(seq_len(8L)), from = \"human-genome\", to = \"human-exome\")"
.CS18_ARM[["wrongnames-lo"]] <- "{ v <- stats::setNames(rep(1, length(.cs18_reg())), paste0(\"Y\", seq_along(.cs18_reg()))); ms_convert(.cs18_sig(3L), from = v, to = \"human-exome\") }"
.CS18_CENSUS <- c("msuiter_error_input=17", "msuiter_error_option=8", "s7:character=1", "s7:matrix=11", "s7:msuiter::MsSignature=1")
## <<CS18-FROZEN-END>> ##

## <<CS18-SHARED-BEGIN>>  (single source: injected byte-identically into
##    the law file and the runner; edit /tmp/cs18-shared.R and re-splice --
##    never hand-edit in place)
## cs18-shared.R -- single source of the CS-18 convert-witness shared block.
## Injected byte-identically into tests/testthat/test-scenario-convert-witness.R
## and bench/scenarios/run_convert_witness.R between the SHARED markers.
## Pure, deterministic, no RNG, no clock, no network: the condition-message
## pipeline plus the exported-face verdict render and the plant builders the
## frozen ARM texts call. The render commits a discrete column-sum glyph
## (0/1/?) instead of any float payload -- the D11 posture for a face that
## returns a real matrix.
.cs18_reg <- function() {
  p <- system.file("extdata", "opps_trinuc_freqs.tsv", package = "msuiter")
  cand <- c(p, file.path("inst", "extdata", "opps_trinuc_freqs.tsv"),
            file.path("data-raw", "opps_trinuc_freqs.tsv"))
  cand <- cand[nzchar(cand) & file.exists(cand)]
  if (length(cand) == 0L) stop(".cs18_reg: opportunity table not locatable")
  as.character(utils::read.delim(cand[1L], sep = "\t", header = TRUE,
                                 stringsAsFactors = FALSE)$label)
}
.cs18_sig <- function(k = 3L) {
  reg <- .cs18_reg()
  matrix(1 / length(reg), length(reg), k,
         dimnames = list(reg, paste0("S", seq_len(k))))
}
.cs18_nv <- function(v) stats::setNames(as.numeric(v), .cs18_reg())
.cs18_obj <- function() {
  reg <- .cs18_reg()
  samp <- c("T1", "T2")
  ct <- .cs18_sig(2L); colnames(ct) <- samp
  cat0 <- ms_catalog(counts = ct,
                     channels = list(name = "SBS96", labels = reg),
                     samples = samp, provenance = list(genome = "GRCh38"))
  ms_signature(signatures = .cs18_sig(3L),
               exposures = matrix(1, 3L, 2L,
                                  dimnames = list(paste0("S", 1:3), samp)),
               catalog_summary = msuiter_catalog_summary(cat0),
               engine = "synthetic", seed = 1L)
}
## Discrete column-sum glyph: 0 for an all-zero column, 1 for a normalized
## column, "?" for anything else. The float error of the kernel is ~1e-16,
## seven orders under the threshold, so the glyph is a cross-platform label.
.cs18_cs <- function(v) {
  s <- colSums(v)
  paste0(vapply(s, function(z) {
    if (abs(z) < 1e-9) "0" else if (abs(z - 1) < 1e-9) "1" else "?"
  }, character(1L)), collapse = ",")
}
.cs18_render <- function(x) {
  ## S7 objects report class(x)[1L] as "msuiter::MsSignature"; inherits()
  ## against the bare name is FALSE, so detect via S7_inherits (falling back
  ## to a class-name grep when the S7 namespace is not attached).
  is_sig <- isTRUE(tryCatch(S7::S7_inherits(x, MsSignature),
                            error = function(e) FALSE)) ||
    grepl("MsSignature", class(x)[1L], fixed = TRUE)
  if (is_sig) {
    return(paste0(c("MsSignature",
      paste0(dim(x@signatures), collapse = "x"),
      storage.mode(x@signatures),
      .cs18_cs(x@signatures),
      paste0(dim(x@exposures), collapse = "x")), collapse = "|"))
  }
  paste0(c(class(x)[1L],
    paste0(dim(x), collapse = "x"),
    storage.mode(x),
    paste0(identical(rownames(x), .cs18_reg())),
    paste0(colnames(x), collapse = ","),
    .cs18_cs(x)), collapse = "|")
}
.cs18_describe <- function(e) trimws(gsub("\n", " | ",
  paste(as.character(conditionMessage(e)), collapse = " | "), fixed = TRUE))
.cs18_strip <- function(s) {
  for (b in c("ℹ ", "i ")) s <- gsub(b, "", s, fixed = TRUE)
  s
}
.cs18_eval1 <- function(txt, tag) {
  if (is.na(txt) || !nzchar(txt)) stop(".cs18_eval1: no text for ", tag)
  ex <- parse(text = txt)
  if (length(ex) != 1L) {
    stop(".cs18_eval1: ", tag, " is not a single expression")
  }
  tryCatch(list(ok = TRUE, v = eval(ex[[1L]])), error = identity)
}
.cs18_verdict <- function(arm, r) {
  if (inherits(r, "error")) {
    list(arm = arm, mode = "reject", cls = class(r)[1L],
         msg = gsub("\t", " ", .cs18_strip(.cs18_describe(r)), fixed = TRUE))
  } else {
    rendered <- if (is.character(r)) r else .cs18_render(r)
    list(arm = arm, mode = "accept", cls = paste0("s7:", class(r)[1L]),
         msg = gsub("\t", " ", rendered, fixed = TRUE))
  }
}
.cs18_fire <- function(arm) {
  r <- .cs18_eval1(.CS18_ARM[[arm]], arm)
  .cs18_verdict(arm, if (inherits(r, "error")) r else r$v)
}
.cs18_clean <- function(df) {
  ## witness bytes round-trip nameless through read.csv; strip any vapply
  ## residue names so identical() compares columns byte-true
  for (cnm in names(df)) attr(df[[cnm]], "names") <- NULL
  df
}
.cs18_rows <- function(arms) {
  vs <- lapply(arms, function(a) .cs18_fire(a))
  .cs18_clean(data.frame(arm = arms,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs18_lawrows <- function() .cs18_rows(.CS18_LAW_ARMS)
.cs18_specrows <- function() .cs18_rows(.CS18_SPEC_ARMS)
.cs18_precrows <- function() {
  base <- .cs18_rows(.CS18_PREC_ARMS)
  base$fires_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(grepl(.CS18_PREC_FIRES[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base$anti_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(!grepl(.CS18_PREC_ANTI[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base
}
.cs18_degenrows <- function() {
  vs <- lapply(.CS18_DEGEN_ARMS, function(a) .cs18_fire(a))
  .cs18_clean(data.frame(pair = .CS18_DEGEN_PAIR, side = .CS18_DEGEN_SIDE,
             arm = .CS18_DEGEN_ARMS,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs18_scalval <- function(k) {
  txt <- .CS18_SCAL_REFIRE[[k]]
  if (is.null(txt)) return(NA_character_)
  res <- .cs18_eval1(txt, k)
  if (inherits(res, "error")) {
    if (identical(k, "abort-class")) return(paste0(class(res)[1L]))
    return(.cs18_strip(.cs18_describe(res)))
  }
  paste0(res$v)
}
.cs18_scalref_keys <- function() names(.CS18_SCAL_REFIRE)
.cs18_plant_text <- function() {
  ord <- c(.CS18_LAW_ARMS, .CS18_SPEC_ARMS, .CS18_PREC_ARMS, .CS18_DEGEN_ARMS)
  paste0(vapply(ord, function(a)
    paste0(a, "=", .CS18_ARM[[a]]), character(1L)), collapse = ";")
}
.cs18_spec_text <- function() paste0(.CS18_SPEC_ARMS, collapse = ";")
## <<CS18-SHARED-END>>  (do not hand-edit in place: edit the source and
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

laws <- .cs18_lawrows()
stopif(!identical(laws$arm, .CS18_LAW_ARMS), "laws: roster drift")
stopif(!identical(laws$mode, rep("reject", 10L)), "laws: a mode drift")
stopif(!identical(laws$cls, .CS18_LAW_CLS), "laws: a class drift")
stopif(!identical(laws$msg, unname(vapply(.CS18_LAW_ARMS,
  function(a) .CS18_LAW_CLAUSES[[a]], character(1L)))), "laws: clause byte drift")
.census("laws", laws, 10L)

specs <- .cs18_specrows()
stopif(!identical(specs$arm, .CS18_SPEC_ARMS), "specs: roster drift")
stopif(!identical(specs$mode, rep("accept", 10L)), "specs: a mode drift")
stopif(!identical(specs$cls, .CS18_SPEC_CLS), "specs: a class drift")
stopif(!identical(specs$msg, unname(vapply(.CS18_SPEC_ARMS,
  function(a) .CS18_SPEC_DETAILS[[a]], character(1L)))), "specs: detail byte drift")
## the replay arm speaks the core render twice, joined by ==
stopif(!identical(specs$msg[match("sp-replay-identity", specs$arm)],
                  paste0(specs$msg[match("A1-accept-core", specs$arm)], "==",
                         specs$msg[match("A1-accept-core", specs$arm)])),
       "specs: the replay identity is not the rendered matrix twice")
## the accepted matrix render commits the canonical-rownames bit and the glyph
stopif(!grepl("|TRUE|S1,S2,S3|1,1,1", specs$msg[match("A1-accept-core", specs$arm)],
              fixed = TRUE), "specs: the core render lost its shape")
.census("specs", specs, 10L)

prec <- .cs18_precrows()
stopif(!identical(prec$arm, .CS18_PREC_ARMS), "prec: roster drift")
stopif(!identical(prec$mode, rep("reject", 10L)), "prec: a mode drift")
stopif(!identical(prec$cls, .CS18_PREC_CLS), "prec: a class drift")
stopif(!all(prec$fires_ok == "TRUE"), "prec: a fired anchor missing")
stopif(!all(prec$anti_ok == "TRUE"), "prec: an anti anchor present")
for (i in seq_len(10L)) {
  stopif(!grepl(.CS18_PREC_FIRES[i], prec$msg[i], fixed = TRUE),
         paste0("prec: fire anchor absent in ", .CS18_PREC_ARMS[i]))
  stopif(grepl(.CS18_PREC_ANTI[i], prec$msg[i], fixed = TRUE),
         paste0("prec: anti anchor present in ", .CS18_PREC_ARMS[i]))
}
.census("prec", prec, 10L)

degen <- .cs18_degenrows()
stopif(!identical(degen$pair, .CS18_DEGEN_PAIR), "degen: pair drift")
stopif(!identical(degen$side, .CS18_DEGEN_SIDE), "degen: side drift")
stopif(!identical(degen$arm, .CS18_DEGEN_ARMS), "degen: arm drift")
stopif(!identical(degen$mode, .CS18_DEGEN_MODE), "degen: mode drift")
stopif(!identical(degen$cls, .CS18_DEGEN_CLS), "degen: class drift")
stopif(!identical(degen$msg, unname(vapply(.CS18_DEGEN_ARMS,
  function(a) .CS18_DEGEN_MSG[[a]], character(1L)))), "degen: msg byte drift")
.w <- function(arm) degen$msg[match(arm, degen$arm)]
head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
## zero-column glyph pair: the all-zero column rides as 0 on the hi side, the
## restored full column as 1 on the lo side
stopif(!grepl("|S1,S2,S3|1,0,1", .w("zero-col-hi"), fixed = TRUE),
       "degen: the zero-column glyph moved")
stopif(!grepl("|S1,S2,S3|1,1,1", .w("full-col-lo"), fixed = TRUE),
       "degen: the full-column glyph moved")
## onecol-vs-multicol pair: a one-column from-matrix accepts, a two-column
## one dies at the single-column law
stopif(!grepl("exactly one frequency column", .w("multicol-matrix-lo"), fixed = TRUE),
       "degen: the multicol clause went missing")
## fromopt-vs-toopt pair: two distinct option laws by their own clause heads
stopif(!identical(head1(.w("from-bad-hi")),
                  "from must be a bundled table or a custom frequency vector"),
       "degen: the from-option head moved")
stopif(!identical(head1(.w("to-bad-lo")),
                  "to must be a bundled table or a custom frequency vector"),
       "degen: the to-option head moved")
## shape-vs-names pair: the shape law vs the label law, distinct heads
stopif(!identical(head1(.w("nonmatrix-hi")), "signatures must be a numeric matrix"),
       "degen: the shape head moved")
stopif(!grepl("first names: 'Y1'", .w("wrongnames-lo"), fixed = TRUE),
       "degen: the names decoy went missing")
.census("degen", degen, 8L, key.col = 3L)

rng1 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
scal.vals <- vapply(.CS18_SCAL_KEYS, function(k) {
  if (identical(k, "rng-before")) return(format(rng0))
  if (identical(k, "rng-after")) return(format(rng1))
  v <- .cs18_scalval(k)
  stopif(is.na(v) || !nzchar(v), paste0("scalars: empty re-fire for ", k))
  stopif(!identical(v, .CS18_SCAL_VALS[[k]]), paste0("scalars: drift for ", k))
  v
}, character(1L))
scalars <- data.frame(key = .CS18_SCAL_KEYS, value = unname(scal.vals),
                      stringsAsFactors = FALSE)
stopif(!identical(scalars$value[match("rng-before", .CS18_SCAL_KEYS)],
                  .CS18_SCAL_VALS[["rng-before"]]), "scalars: rng-before drift")
stopif(!identical(scalars$value[match("rng-after", .CS18_SCAL_KEYS)],
                  .CS18_SCAL_VALS[["rng-after"]]), "scalars: rng-after drift")
## the discrete glyphs are committed labels, not float payloads
stopif(!identical(scalars$value[match("glyph-full", .CS18_SCAL_KEYS)], "1,1,1"),
       "scalars: the full glyph moved")
stopif(!identical(scalars$value[match("glyph-zero", .CS18_SCAL_KEYS)], "1,0,1"),
       "scalars: the zero glyph moved")
.census("scalars", scalars, 10L)

## dual-kernel hashes over the frozen corpora (written nowhere, attested)
plant.sha <- .ck(charToRaw(.cs18_plant_text()), "plant-corpus")
spec.sha <- .ck(charToRaw(.cs18_spec_text()), "spec-corpus")

## ---------------------------------------------------------------------------
## all censuses spoke: commit the five witnesses
## ---------------------------------------------------------------------------
.wtab("cs18_laws.tsv", laws)
.wtab("cs18_specs.tsv", specs)
.wtab("cs18_precedence.tsv", prec)
.wtab("cs18_degenerates.tsv", degen)
.wtab("cs18_scalars.tsv", scalars)

cat("[attest] at=", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    " out=", OUT, "\n", sep = "")
for (nm in c("cs18_laws.tsv", "cs18_specs.tsv", "cs18_precedence.tsv",
             "cs18_degenerates.tsv", "cs18_scalars.tsv")) {
  cat("[attest] sha256 ", nm, "=", .file.sha(nm), "\n", sep = "")
}
cat("[attest] plant_sha256=", plant.sha, " spec_sha256=", spec.sha,
    " files=", length(list.files(OUT, pattern = "^cs18_")), "\n", sep = "")
cat("OVERALL PASS\n")
quit(save = "no", status = 0L)
