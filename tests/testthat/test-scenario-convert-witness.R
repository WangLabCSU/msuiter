# test-scenario-convert-witness.R -- the CS-18 convert-witness law units
# (pillar 3). The scenario plants synthetic signature-and-opportunity calls
# (the D3 law: zero COSMIC numeric matrices, zero real-data bytes, zero
# downloads -- the opportunity tables ride only as named frequency vectors
# over the registry labels) and adjudicates the EXPORTED ms_convert()/
# MsSignature face: the ten-arm "option"/"input" validator split over the
# from/to arguments, the accepted re-expression shapes, the precedence
# discriminators with their anti anchors, the boundary contrast pairs and the
# acceptance specs. The witness bytes under bench/scenarios/out/
# (cs18_laws.tsv, cs18_specs.tsv, cs18_precedence.tsv, cs18_degenerates.tsv,
# cs18_scalars.tsv) are the committed verdict: a drift in a fired clause, an
# observed error class, an accepted shape or the precedence order reddens
# here before print. The plants are synthetic -- no RNG consumption, no
# network, no COSMIC bytes; the lane NEVER calls the benchmark driver, the
# declined calibration family, the registry face or any validator internal
# (banned words, grepped over the runner source).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired clauses -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): integer, label, logical, class and
# clause bytes are byte-committed; the face returns a real matrix whose
# kernel error is ~1e-16, so no float payload rides any witness -- the
# accepted render commits a DISCRETE column-sum glyph (0/1/? at a 1e-9
# threshold, seven orders above the observed float error).
# The frozen block and the shared code block below are MINTED mechanically
# from the audited probe ledger (cs18-mint3.R / cs18-shared.R); neither is
# ever hand-edited in place.

.rs_out18 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv18 <- function(fname) {
  read.csv(.rs_out18(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

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

# ===========================================================================
# U1 -- rails: the runner exists and speaks the exported face, never an
# internal (banned-word grep over its full source).
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_convert_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_convert(", "cs18_",
                 "commandArgs", "digest::digest", "serialize = FALSE",
                 "charToRaw", "open = \"wb\"", "na = \"\"", "quote = FALSE",
                 "row.names = FALSE", "RNG-STATE-RAIL", ".ms_fit_sha256")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  ## The bans govern the hand-written region: the minted frozen block is
  ## OBSERVED DATA and legitimately quotes the face's own bytes (the clause
  ## table quotes the S7 message bytes). Slice the two injected regions out
  ## before the absence scan; marker integrity itself is rail-checked here.
  lines <- strsplit(src, "\n", fixed = TRUE)[[1L]]
  .region <- function(beg, end) {
    b <- which(vapply(lines, function(l) grepl(beg, l, fixed = TRUE), logical(1L)))
    e <- which(vapply(lines, function(l) grepl(end, l, fixed = TRUE), logical(1L)))
    expect_identical(length(b), 1L, info = beg)
    expect_identical(length(e), 1L, info = end)
    c(b, e)
  }
  drop <- c(seq(.region("## <<CS18-FROZEN-BEGIN", "## <<CS18-FROZEN-END")[1]:
                .region("## <<CS18-FROZEN-BEGIN", "## <<CS18-FROZEN-END")[2]),
            seq(.region("## <<CS18-SHARED-BEGIN", "## <<CS18-SHARED-END")[1]:
                .region("## <<CS18-SHARED-BEGIN", "## <<CS18-SHARED-END")[2]))
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
  for (f in c("cs18_laws.tsv", "cs18_specs.tsv", "cs18_precedence.tsv",
              "cs18_degenerates.tsv", "cs18_scalars.tsv")) {
    expect_true(file.exists(.rs_out18(f)))
    expect_gt(file.size(.rs_out18(f)), 0)
  }
  lw <- .rs_tsv18("cs18_laws.tsv"); sp <- .rs_tsv18("cs18_specs.tsv")
  pr <- .rs_tsv18("cs18_precedence.tsv"); dg <- .rs_tsv18("cs18_degenerates.tsv")
  sc <- .rs_tsv18("cs18_scalars.tsv")
  expect_identical(nrow(lw), 10L)
  expect_identical(nrow(sp), 10L)
  expect_identical(nrow(pr), 10L)
  expect_identical(nrow(dg), 8L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS18_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS18_SCAL_KEYS))
  for (df in list(lw, sp, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
    expect_false(any(vapply(df, function(cc) any(!nzchar(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the laws witness mirrors the frozen law table: ten arms, classes and
# verbatim clauses, byte for byte.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv18("cs18_laws.tsv")
  expect_identical(lw$arm, .CS18_LAW_ARMS)
  expect_identical(lw$mode, rep("reject", 10L))
  expect_identical(lw$cls, .CS18_LAW_CLS)
  expect_identical(lw$msg, unname(vapply(.CS18_LAW_ARMS,
    function(a) .CS18_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U4 -- live replay of the law arms: every arm still rejects with its
# committed class and its committed clause bytes ride the live message.
# ===========================================================================
test_that("law arms replay live through the face", {
  live <- .cs18_lawrows()
  expect_identical(live$arm, .CS18_LAW_ARMS)
  expect_identical(live$mode, rep("reject", 10L))
  expect_identical(live$cls, .CS18_LAW_CLS)
  expect_identical(live$msg, unname(vapply(.CS18_LAW_ARMS,
    function(a) .CS18_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U5 -- the specs witness mirrors the frozen acceptance table, the
# acceptance arms replay live, the replay identity speaks the core render
# twice and the accepted renders commit their shape and glyph.
# ===========================================================================
test_that("specs witness mirrors frozen and replays live", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv18("cs18_specs.tsv")
  expect_identical(sp$arm, .CS18_SPEC_ARMS)
  expect_identical(sp$mode, rep("accept", 10L))
  expect_identical(sp$cls, .CS18_SPEC_CLS)
  expect_identical(sp$msg, unname(vapply(.CS18_SPEC_ARMS,
    function(a) .CS18_SPEC_DETAILS[[a]], character(1L))))
  live <- .cs18_specrows()
  expect_identical(live$arm, sp$arm)
  expect_identical(live$mode, sp$mode)
  expect_identical(live$cls, sp$cls)
  expect_identical(live$msg, sp$msg)
  ## the replay arm speaks the core render twice, joined by ==
  expect_identical(sp$msg[match("sp-replay-identity", sp$arm)],
                   paste0(sp$msg[match("A1-accept-core", sp$arm)], "==",
                          sp$msg[match("A1-accept-core", sp$arm)]))
  ## the accepted matrix render commits the canonical-rownames bit and glyph
  expect_true(grepl("|TRUE|S1,S2,S3|1,1,1",
                    sp$msg[match("A1-accept-core", sp$arm)], fixed = TRUE))
  ## the zero-column acceptance commits the 0 glyph between the pipes
  expect_true(grepl("|S1,S2,S3|1,0,1",
                    sp$msg[match("S3-accept-zero-col", sp$arm)], fixed = TRUE))
  ## the MsSignature acceptance renders the S7 branch
  expect_identical(sp$msg[match("A6-accept-msg-signature", sp$arm)],
                   "MsSignature|96x3|double|1,1,1|3x2")
})

# ===========================================================================
# U6 -- the precedence witness: committed class, fired anchor PRESENT and
# anti anchor ABSENT in every arm, live replay included.
# ===========================================================================
test_that("precedence witness speaks anchors both ways", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  pr <- .rs_tsv18("cs18_precedence.tsv")
  expect_identical(pr$arm, .CS18_PREC_ARMS)
  expect_identical(pr$mode, rep("reject", 10L))
  expect_identical(pr$cls, .CS18_PREC_CLS)
  expect_identical(pr$fires_ok, rep("TRUE", 10L))
  expect_identical(pr$anti_ok, rep("TRUE", 10L))
  for (i in seq_len(10L)) {
    expect_true(grepl(.CS18_PREC_FIRES[i], pr$msg[i], fixed = TRUE),
                info = .CS18_PREC_ARMS[i])
    expect_false(grepl(.CS18_PREC_ANTI[i], pr$msg[i], fixed = TRUE),
                 info = .CS18_PREC_ARMS[i])
  }
  live <- .cs18_precrows()
  expect_identical(live$msg, pr$msg)
})

# ===========================================================================
# U7 -- the boundary contrast witness: four pairs replayed live against the
# committed bytes; the pair-level discriminators hold (the accepted
# zero-column glyph against the restored full column, the one-column
# from-matrix against the two-column one by the single-column law, the
# from-option law against the to-option law by their own clause heads, the
# shape law against the label law by their own clause heads).
# ===========================================================================
test_that("boundary contrast pairs hold on both sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  dg <- .rs_tsv18("cs18_degenerates.tsv")
  expect_identical(dg$pair, .CS18_DEGEN_PAIR)
  expect_identical(dg$side, .CS18_DEGEN_SIDE)
  expect_identical(dg$arm, .CS18_DEGEN_ARMS)
  expect_identical(dg$mode, .CS18_DEGEN_MODE)
  expect_identical(dg$cls, .CS18_DEGEN_CLS)
  expect_identical(dg$msg, unname(vapply(.CS18_DEGEN_ARMS,
    function(a) .CS18_DEGEN_MSG[[a]], character(1L))))
  live <- .cs18_degenrows()
  expect_identical(live$msg, dg$msg)
  w <- function(arm) dg$msg[match(arm, dg$arm)]
  head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
  ## zero-column glyph pair: the all-zero column rides as 0 on the hi side,
  ## the restored full column as 1 on the lo side
  expect_true(grepl("|S1,S2,S3|1,0,1", w("zero-col-hi"), fixed = TRUE))
  expect_true(grepl("|S1,S2,S3|1,1,1", w("full-col-lo"), fixed = TRUE))
  ## onecol-vs-multicol pair: a one-column from-matrix accepts, a two-column
  ## one dies at the single-column law
  expect_identical(dg$mode[match("onecol-matrix-hi", dg$arm)], "accept")
  expect_identical(dg$mode[match("multicol-matrix-lo", dg$arm)], "reject")
  expect_true(grepl("exactly one frequency column",
                    w("multicol-matrix-lo"), fixed = TRUE))
  ## fromopt-vs-toopt pair: two distinct option laws by their own heads
  expect_identical(head1(w("from-bad-hi")),
                   "from must be a bundled table or a custom frequency vector")
  expect_identical(head1(w("to-bad-lo")),
                   "to must be a bundled table or a custom frequency vector")
  ## shape-vs-names pair: the shape law vs the label law, distinct heads
  expect_identical(head1(w("nonmatrix-hi")),
                   "signatures must be a numeric matrix")
  expect_false(identical(head1(w("nonmatrix-hi")), head1(w("wrongnames-lo"))))
  expect_true(grepl("first names: 'Y1'", w("wrongnames-lo"), fixed = TRUE))
})

# ===========================================================================
# U8 -- the scalars witness: the re-fireable keys replay live to their
# committed bytes; the rng keys ride the committed purity verdict.
# ===========================================================================
test_that("scalars witness replays and the rng rail stays frozen", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sc <- .rs_tsv18("cs18_scalars.tsv")
  expect_identical(sort(sc$key), sort(.CS18_SCAL_KEYS))
  rf <- .cs18_scalref_keys()
  for (k in rf) {
    expect_identical(sc$value[match(k, sc$key)], .cs18_scalval(k), info = k)
    expect_identical(.CS18_SCAL_VALS[[k]], sc$value[match(k, sc$key)], info = k)
  }
  for (k in setdiff(.CS18_SCAL_KEYS, rf)) {
    expect_true(k %in% c("rng-before", "rng-after"))
    expect_identical(sc$value[match(k, sc$key)], .CS18_SCAL_VALS[[k]], info = k)
  }
  ## the discrete glyphs are committed labels, not float payloads
  expect_identical(sc$value[match("glyph-full", sc$key)], "1,1,1")
  expect_identical(sc$value[match("glyph-zero", sc$key)], "1,0,1")
  ## the abort-class scalar speaks the input class the face raises
  expect_identical(sc$value[match("abort-class", sc$key)], "msuiter_error_input")
})

# ===========================================================================
# U9 -- dual-kernel SHA-256: the frozen plant corpus and the spec roster
# hash identically under both governed kernels and speak the hex policy.
# ===========================================================================
test_that("plant and spec corpora agree under both sha256 kernels", {
  for (tag in c("plant", "spec")) {
    txt <- if (identical(tag, "plant")) .cs18_plant_text() else .cs18_spec_text()
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
  expect_identical(length(.CS18_LAW_ARMS), 10L)
  expect_identical(length(.CS18_SPEC_ARMS), 10L)
  expect_identical(length(.CS18_PREC_ARMS), 10L)
  expect_identical(length(.CS18_DEGEN_ARMS), 8L)
  expect_identical(length(.CS18_SCAL_KEYS), 10L)
  expect_identical(length(.CS18_ARM), 38L)
  expect_identical(length(.CS18_CENSUS), 5L)
  allc <- c(.CS18_LAW_ARMS, .CS18_SPEC_ARMS, .CS18_PREC_ARMS, .CS18_DEGEN_ARMS)
  expect_false(any(duplicated(allc)))
  expect_true(all(allc %in% names(.CS18_ARM)))
  for (a in names(.CS18_ARM)) {
    expect_identical(length(parse(text = .CS18_ARM[[a]])), 1L, info = a)
  }
  allcls <- c(.CS18_LAW_CLS, .CS18_PREC_CLS, .CS18_SPEC_CLS, .CS18_DEGEN_CLS)
  tally <- function(cl) paste0(cl, "=", sum(allcls == cl))
  want <- c(tally("msuiter_error_input"), tally("msuiter_error_option"),
            tally("s7:character"), tally("s7:matrix"),
            tally("s7:msuiter::MsSignature"))
  expect_true(all(want %in% .CS18_CENSUS))
  expect_identical(sort(.CS18_CENSUS), sort(want))
})
