# test-scenario-embed-witness.R -- the CS-21 embed-witness law units
# (pillar 3). The scenario plants synthetic exposure matrices (the D3 law:
# zero COSMIC numeric matrices, zero real-data bytes, zero downloads -- the
# exposures ride only as synthetic count matrices over synthetic signature
# and sample labels) and adjudicates the EXPORTED ms_embed() face: the
# six-step gate ladder (input, method, transform, seed, the cluster bound,
# the cluster window), the accepted projection renders, the six precedence
# discriminators with their anti anchors, the boundary contrast pairs and the
# acceptance specs. The witness bytes under bench/scenarios/out/
# (cs21_laws.tsv, cs21_specs.tsv, cs21_precedence.tsv, cs21_degenerates.tsv,
# cs21_scalars.tsv) are the committed verdict: a drift in a fired clause, an
# observed error class, an accepted shape or the precedence order reddens
# here before print. The plants are synthetic -- no RNG consumption, no
# network, no COSMIC bytes; the lane NEVER calls the benchmark driver, the
# declined calibration family, the registry face or any validator internal
# (banned words, grepped over the runner source).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired clauses -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): the face returns projection
# coordinates whose last bits are ill-conditioned, so no float payload rides
# any witness -- the accepted render commits DISCRETE facts instead (the
# container class, its field names and per-column classes, the frame shape,
# the integer cluster vector, an all-finite glyph, the index of the
# zero-total sample and the digit-scrubbed head of the sample column);
# integer, label, logical, class and clause bytes are byte-committed.
# The frozen block and the shared code block below are MINTED mechanically
# from the audited probe ledger (cs21-mint4.R / cs21-shared2.R); neither is
# ever hand-edited in place.

.rs_out21 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv21 <- function(fname) {
  read.csv(.rs_out21(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

## <<CS21-FROZEN-BEGIN>>  (minted mechanically from the audited ledger
##    2026-11-26; DO NOT hand-edit: regenerate via cs21-mint4.R) ##
.CS21_LAW_ARMS <- c("L1-input-char", "L2-input-list", "L3-seed-vector", "L4-seed-negative", "L5-seed-na", "L6-seed-inf", "L7-method-bogus", "L8-transform-bogus", "L9-clusters-zero", "L10-clusters-over", "L11-clusters-single", "L12-umap-seed-neg")
.CS21_LAW_CLS <- c("msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "simpleError", "simpleError", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS21_LAW_CLAUSES <- list()
.CS21_LAW_CLAUSES[["L1-input-char"]] <- "exposures must be a numeric k x n matrix (or an MsSignature) | ms_embed() projects samples in the exposure space | received: matrix | pass the fit/refit exposure matrix"
.CS21_LAW_CLAUSES[["L2-input-list"]] <- "exposures must be a numeric k x n matrix (or an MsSignature) | ms_embed() projects samples in the exposure space | received: matrix | pass the fit/refit exposure matrix"
.CS21_LAW_CLAUSES[["L3-seed-vector"]] <- "seed must be a single non-negative finite number | the seed seeds the stochastic embedding (or the kmeans tie-break) | received: #, # | record the integer seed used for the embedding"
.CS21_LAW_CLAUSES[["L4-seed-negative"]] <- "seed must be a single non-negative finite number | the seed seeds the stochastic embedding (or the kmeans tie-break) | received: -# | record the integer seed used for the embedding"
.CS21_LAW_CLAUSES[["L5-seed-na"]] <- "seed must be a single non-negative finite number | the seed seeds the stochastic embedding (or the kmeans tie-break) | received: NA | record the integer seed used for the embedding"
.CS21_LAW_CLAUSES[["L6-seed-inf"]] <- "seed must be a single non-negative finite number | the seed seeds the stochastic embedding (or the kmeans tie-break) | received: Inf | record the integer seed used for the embedding"
.CS21_LAW_CLAUSES[["L7-method-bogus"]] <- "arg should be one of umap, kmeans"
.CS21_LAW_CLAUSES[["L8-transform-bogus"]] <- "arg should be one of share, none"
.CS21_LAW_CLAUSES[["L9-clusters-zero"]] <- "clusters must be a single integer in [#, n signatures] | kmeans partitions the share-simplex samples | received: #; signatures: # | kmeans needs at most one cluster per signature dimension"
.CS21_LAW_CLAUSES[["L10-clusters-over"]] <- "clusters must be a single integer in [#, n signatures] | kmeans partitions the share-simplex samples | received: #; signatures: # | kmeans needs at most one cluster per signature dimension"
.CS21_LAW_CLAUSES[["L11-clusters-single"]] <- "kmeans needs the cluster count strictly between # and the sample count | stats::kmeans refuses one centre and centre-per-sample counts alike | clusters: #; samples: # | lower clusters or carry more samples"
.CS21_LAW_CLAUSES[["L12-umap-seed-neg"]] <- "seed must be a single non-negative finite number | the seed seeds the stochastic embedding (or the kmeans tie-break) | received: -# | record the integer seed used for the embedding"
.CS21_SPEC_ARMS <- c("A1-clusters-3", "A2-clusters-2", "A3-clusters-5", "A4-clusters-8", "A5-transform-none", "A6-seed-default", "A7-arg-order", "A8-nameless-plant")
.CS21_SPEC_CLS <- c("data.frame", "data.frame", "data.frame", "msuiter_error_input", "data.frame", "data.frame", "data.frame", "data.frame")
.CS21_SPEC_DETAILS <- list()
.CS21_SPEC_DETAILS[["A1-clusters-3"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
.CS21_SPEC_DETAILS[["A2-clusters-2"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|2,2,2,1,1,1,2,2,2|1|none|T##"
.CS21_SPEC_DETAILS[["A3-clusters-5"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|4,5,5,3,1,1,2,2,2|1|none|T##"
.CS21_SPEC_DETAILS[["A4-clusters-8"]] <- "clusters must be a single integer in [#, n signatures] | kmeans partitions the share-simplex samples | received: #; signatures: # | kmeans needs at most one cluster per signature dimension"
.CS21_SPEC_DETAILS[["A5-transform-none"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
.CS21_SPEC_DETAILS[["A6-seed-default"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
.CS21_SPEC_DETAILS[["A7-arg-order"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
.CS21_SPEC_DETAILS[["A8-nameless-plant"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|sample#"
.CS21_PREC_ARMS <- c("PR1-anchor-input", "PR1-anti-method", "PR2-anchor-input", "PR2-anti-seed", "PR3-anchor-method", "PR3-anti-transform", "PR4-anchor-transform", "PR4-anti-seed", "PR5-anchor-seed", "PR5-anti-a1", "PR6-anchor-a1", "PR6-anti-a2")
.CS21_PREC_CLS <- c("msuiter_error_input", "simpleError", "msuiter_error_input", "msuiter_error_input", "simpleError", "simpleError", "simpleError", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input")
.CS21_PREC_FIRES <- c("exposures must be a numeric k x n matrix (or an MsSignature)", "arg should be one of umap, kmeans", "exposures must be a numeric k x n matrix (or an MsSignature)", "seed must be a single non-negative finite number", "arg should be one of umap, kmeans", "arg should be one of share, none", "arg should be one of share, none", "seed must be a single non-negative finite number", "seed must be a single non-negative finite number", "clusters must be a single integer in [#, n signatures]", "clusters must be a single integer in [#, n signatures]", "kmeans needs the cluster count strictly between # and the sample count")
.CS21_PREC_ANTI <- c("arg should be one of umap, kmeans", "exposures must be a numeric k x n matrix (or an MsSignature)", "seed must be a single non-negative finite number", "exposures must be a numeric k x n matrix (or an MsSignature)", "arg should be one of share, none", "arg should be one of umap, kmeans", "seed must be a single non-negative finite number", "arg should be one of share, none", "clusters must be a single integer in [#, n signatures]", "seed must be a single non-negative finite number", "kmeans needs the cluster count strictly between # and the sample count", "clusters must be a single integer in [#, n signatures]")
.CS21_DEGEN_PAIR <- c("plant-accept", "plant-accept", "cluster-window", "cluster-window", "share-guard", "share-guard", "clause-head", "clause-head")
.CS21_DEGEN_SIDE <- c("hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo")
.CS21_DEGEN_ARMS <- c("plant-accept-hi", "plant-accept-lo", "cluster-window-hi", "cluster-window-lo", "share-guard-hi", "share-guard-lo", "clause-head-hi", "clause-head-lo")
.CS21_DEGEN_MODE <- c("accept", "reject", "reject", "reject", "accept", "accept", "reject", "reject")
.CS21_DEGEN_CLS <- c("data.frame", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "data.frame", "data.frame", "simpleError", "simpleError")
.CS21_DEGEN_MSG <- list()
.CS21_DEGEN_MSG[["plant-accept-hi"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
.CS21_DEGEN_MSG[["plant-accept-lo"]] <- "exposures must be a numeric k x n matrix (or an MsSignature) | ms_embed() projects samples in the exposure space | received: matrix | pass the fit/refit exposure matrix"
.CS21_DEGEN_MSG[["cluster-window-hi"]] <- "clusters must be a single integer in [#, n signatures] | kmeans partitions the share-simplex samples | received: #; signatures: # | kmeans needs at most one cluster per signature dimension"
.CS21_DEGEN_MSG[["cluster-window-lo"]] <- "kmeans needs the cluster count strictly between # and the sample count | stats::kmeans refuses one centre and centre-per-sample counts alike | clusters: #; samples: # | lower clusters or carry more samples"
.CS21_DEGEN_MSG[["share-guard-hi"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
.CS21_DEGEN_MSG[["share-guard-lo"]] <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,2,2,2,1,1,1|1|9|T##"
.CS21_DEGEN_MSG[["clause-head-hi"]] <- "arg should be one of umap, kmeans"
.CS21_DEGEN_MSG[["clause-head-lo"]] <- "arg should be one of share, none"
.CS21_SCAL_KEYS <- c("abort-class", "match-class", "seed-class", "return-class", "clusters-chosen", "rows", "cols", "names", "classes", "cluster-vector", "sample-head", "finite-glyph", "zero-row-hi", "zero-row-lo", "rng-before", "rng-after")
.CS21_SCAL_VALS <- list()
.CS21_SCAL_VALS[["abort-class"]] <- "msuiter_error_input"
.CS21_SCAL_VALS[["match-class"]] <- "simpleError"
.CS21_SCAL_VALS[["seed-class"]] <- "msuiter_error_input"
.CS21_SCAL_VALS[["return-class"]] <- "data.frame"
.CS21_SCAL_VALS[["clusters-chosen"]] <- "3"
.CS21_SCAL_VALS[["rows"]] <- "9"
.CS21_SCAL_VALS[["cols"]] <- "4"
.CS21_SCAL_VALS[["names"]] <- "sample,embed_1,embed_2,cluster"
.CS21_SCAL_VALS[["classes"]] <- "character,numeric,numeric,integer"
.CS21_SCAL_VALS[["cluster-vector"]] <- "3,3,3,1,1,1,2,2,2"
.CS21_SCAL_VALS[["sample-head"]] <- "T##"
.CS21_SCAL_VALS[["finite-glyph"]] <- "1"
.CS21_SCAL_VALS[["zero-row-hi"]] <- "none"
.CS21_SCAL_VALS[["zero-row-lo"]] <- "9"
.CS21_SCAL_VALS[["rng-before"]] <- "FALSE"
.CS21_SCAL_VALS[["rng-after"]] <- "FALSE"
.CS21_SCAL_REFIRE <- list()
.CS21_SCAL_REFIRE[["abort-class"]] <- ".cs21_cls_of(\"L1-input-char\")"
.CS21_SCAL_REFIRE[["match-class"]] <- ".cs21_cls_of(\"L7-method-bogus\")"
.CS21_SCAL_REFIRE[["seed-class"]] <- ".cs21_cls_of(\"L3-seed-vector\")"
.CS21_SCAL_REFIRE[["return-class"]] <- "class(.cs21_accept_of(\"A1-clusters-3\"))[1L]"
.CS21_SCAL_REFIRE[["clusters-chosen"]] <- "as.character(length(unique(.cs21_accept_of(\"A1-clusters-3\")$cluster)))"
.CS21_SCAL_REFIRE[["rows"]] <- "as.character(nrow(.cs21_accept_of(\"A1-clusters-3\")))"
.CS21_SCAL_REFIRE[["cols"]] <- "as.character(ncol(.cs21_accept_of(\"A1-clusters-3\")))"
.CS21_SCAL_REFIRE[["names"]] <- "paste(names(.cs21_accept_of(\"A1-clusters-3\")), collapse = \",\")"
.CS21_SCAL_REFIRE[["classes"]] <- "paste(vapply(.cs21_accept_of(\"A1-clusters-3\"), function(cc) class(cc)[1L], character(1L)), collapse = \",\")"
.CS21_SCAL_REFIRE[["cluster-vector"]] <- "paste(.cs21_accept_of(\"A1-clusters-3\")$cluster, collapse = \",\")"
.CS21_SCAL_REFIRE[["sample-head"]] <- ".cs21_scrub(.cs21_flat1(as.character(.cs21_accept_of(\"A1-clusters-3\")$sample[1L])))"
.CS21_SCAL_REFIRE[["finite-glyph"]] <- ".cs21_glyph(all(vapply(.cs21_accept_of(\"A1-clusters-3\")[vapply(.cs21_accept_of(\"A1-clusters-3\"), is.numeric, logical(1L))], function(cc) all(is.finite(cc)), logical(1L))))"
.CS21_SCAL_REFIRE[["zero-row-hi"]] <- ".cs21_zerohead(.cs21_accept_of(\"A1-clusters-3\"))"
.CS21_SCAL_REFIRE[["zero-row-lo"]] <- ".cs21_zerohead(.cs21_accept_of(\"share-guard-lo\"))"
.CS21_SCAL_REFIRE[["rng-before"]] <- "local({ suppressWarnings(rm(\".Random.seed\", envir = globalenv())); probe <- function() invisible(ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L, seed = 1)); format(exists(\".Random.seed\", envir = globalenv(), inherits = TRUE)) })"
.CS21_SCAL_REFIRE[["rng-after"]] <- "local({ suppressWarnings(rm(\".Random.seed\", envir = globalenv())); probe <- function() invisible(ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L, seed = 1)); probe(); format(exists(\".Random.seed\", envir = globalenv(), inherits = TRUE)) })"
.CS21_ARM <- list()
.CS21_ARM[["L1-input-char"]] <- "ms_embed(\"x\")"
.CS21_ARM[["L2-input-list"]] <- "ms_embed(list(1, 2))"
.CS21_ARM[["L3-seed-vector"]] <- "ms_embed(.cs21_plant(), seed = c(1, 2))"
.CS21_ARM[["L4-seed-negative"]] <- "ms_embed(.cs21_plant(), seed = -1)"
.CS21_ARM[["L5-seed-na"]] <- "ms_embed(.cs21_plant(), seed = NA)"
.CS21_ARM[["L6-seed-inf"]] <- "ms_embed(.cs21_plant(), seed = Inf)"
.CS21_ARM[["L7-method-bogus"]] <- "ms_embed(.cs21_plant(), \"bogus\")"
.CS21_ARM[["L8-transform-bogus"]] <- "ms_embed(.cs21_plant(), \"kmeans\", \"bogus\")"
.CS21_ARM[["L9-clusters-zero"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 0L)"
.CS21_ARM[["L10-clusters-over"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 6L)"
.CS21_ARM[["L11-clusters-single"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 1L)"
.CS21_ARM[["L12-umap-seed-neg"]] <- "ms_embed(.cs21_plant(), \"umap\", seed = -1)"
.CS21_ARM[["A1-clusters-3"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L, seed = 1)"
.CS21_ARM[["A2-clusters-2"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 2L, seed = 1)"
.CS21_ARM[["A3-clusters-5"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 5L, seed = 1)"
.CS21_ARM[["A4-clusters-8"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 8L, seed = 1)"
.CS21_ARM[["A5-transform-none"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L, transform = \"none\")"
.CS21_ARM[["A6-seed-default"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L)"
.CS21_ARM[["A7-arg-order"]] <- "ms_embed(.cs21_plant(), seed = 1, clusters = 3L, method = \"kmeans\")"
.CS21_ARM[["A8-nameless-plant"]] <- "ms_embed(.cs21_plant(named = FALSE), \"kmeans\", clusters = 3L, seed = 1)"
.CS21_ARM[["PR1-anchor-input"]] <- "ms_embed(\"x\", \"bogus\")"
.CS21_ARM[["PR1-anti-method"]] <- "ms_embed(.cs21_plant(), \"bogus\")"
.CS21_ARM[["PR2-anchor-input"]] <- "ms_embed(\"x\", seed = -1)"
.CS21_ARM[["PR2-anti-seed"]] <- "ms_embed(.cs21_plant(), seed = -1)"
.CS21_ARM[["PR3-anchor-method"]] <- "ms_embed(.cs21_plant(), \"bogus\", \"bogus\")"
.CS21_ARM[["PR3-anti-transform"]] <- "ms_embed(.cs21_plant(), \"kmeans\", \"bogus\")"
.CS21_ARM[["PR4-anchor-transform"]] <- "ms_embed(.cs21_plant(), \"kmeans\", \"bogus\", seed = -1)"
.CS21_ARM[["PR4-anti-seed"]] <- "ms_embed(.cs21_plant(), seed = -1)"
.CS21_ARM[["PR5-anchor-seed"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 0L, seed = -1)"
.CS21_ARM[["PR5-anti-a1"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 0L)"
.CS21_ARM[["PR6-anchor-a1"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 0L)"
.CS21_ARM[["PR6-anti-a2"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 1L)"
.CS21_ARM[["plant-accept-hi"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L, seed = 1)"
.CS21_ARM[["plant-accept-lo"]] <- "ms_embed(\"x\")"
.CS21_ARM[["cluster-window-hi"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 6L)"
.CS21_ARM[["cluster-window-lo"]] <- "ms_embed(.cs21_plant(k = 6L, n = 6L), \"kmeans\", clusters = 6L)"
.CS21_ARM[["share-guard-hi"]] <- "ms_embed(.cs21_plant(), \"kmeans\", clusters = 3L, seed = 1)"
.CS21_ARM[["share-guard-lo"]] <- "ms_embed(.cs21_plant_zero(), \"kmeans\", clusters = 3L, seed = 1)"
.CS21_ARM[["clause-head-hi"]] <- "ms_embed(.cs21_plant(), \"bogus\")"
.CS21_ARM[["clause-head-lo"]] <- "ms_embed(.cs21_plant(), \"kmeans\", \"bogus\")"
.CS21_CENSUS <- c("data.frame=10", "msuiter_error_input=22", "simpleError=8")
## <<CS21-FROZEN-END>> ##

## <<CS21-SHARED-BEGIN>>  (single source: injected byte-identically into
##    the law file and the runner; edit /tmp/cs21-shared2.R and re-splice --
##    never hand-edit in place)
## ---------------------------------------------------------------------------
## CS-21 shared block -- the ms_embed witness plant, render and admissibility
## helpers. Single source: this file is injected byte-identically into the law
## file and the runner by cs21-splice-*.py. Never hand-edit either injection.
## ---------------------------------------------------------------------------
## The plant: a k x n synthetic count matrix whose columns fall into group-sized
## blocks, each block dominated by one signature through a large anchor term; the
## remaining entries are a small deterministic residue. No RNG is drawn. When
## named, rows speak synthetic signature labels and columns synthetic sample
## labels, so the face's own fallback sample naming is witnessed by contrast.
.cs21_plant <- function(k = 5L, n = 9L, group = 3L, named = TRUE) {
  m <- matrix(0, nrow = k, ncol = n)
  for (j in seq_len(n)) {
    g <- ((j - 1L) %/% group) + 1L
    for (s in seq_len(k)) {
      m[s, j] <- if (s == ((g - 1L) %% k) + 1L) 100 + 10 * (((j - 1L) %% group) + 1L) else
        1 + ((s * 7L + j * 3L) %% 5L)
    }
  }
  if (named) dimnames(m) <- list(sprintf("SIG%02d", seq_len(k)), sprintf("T%02d", seq_len(n)))
  m
}
## the same plant with its last sample column zeroed: the share transform must
## leave the all-zero row untouched (never a 0/0) and the face must still project it
.cs21_plant_zero <- function(...) {
  z <- .cs21_plant(...)
  z[, ncol(z)] <- 0
  z
}
## D11 posture: integer, label, logical, class and clause bytes are
## byte-committed; the face quotes measured quantities inside its refusal
## clauses, so every digit in a committed clause byte becomes '#'. The
## vocabulary (clause head, field label, comparator, article) survives; the
## measured value, its sign and the threshold it was compared against do not.
## Thresholds are sealed separately as scalars.
.cs21_scrub <- function(s) gsub("[0-9]", "#", s)
## quote posture: R's match.arg prints its candidate list with typographic
## quotes in a UTF-8 locale and with plain ones elsewhere, so every quote glyph
## is dropped before the bytes are frozen -- the clause vocabulary is what the
## witness commits, not the typography of the host that rendered it.
.cs21_quote <- function(s) gsub("[“”‘’'\"]", "", s)
.cs21_strip <- function(s) {
  for (b in c("ℹ ", "i ")) s <- gsub(b, "", s, fixed = TRUE)
  s
}
.cs21_flat1 <- function(s) gsub("\t", " ", trimws(s), fixed = TRUE)
.cs21_describe <- function(e) trimws(gsub("\n", " | ",
  paste(as.character(conditionMessage(e)), collapse = " | "), fixed = TRUE))
.cs21_msg <- function(e)
  .cs21_flat1(.cs21_scrub(.cs21_quote(.cs21_strip(.cs21_describe(e)))))
.cs21_glyph <- function(v) paste0(ifelse(v, "1", "0"), collapse = ",")
## the first row whose two embed coordinates are exactly zero, or 'none'; the
## share guard's whole point is that a zero-total sample stays exactly zero
## instead of becoming NaN, so the index is a discrete, platform-stable byte
.cs21_zerohead <- function(x) {
  z <- which(x$embed_1 == 0 & x$embed_2 == 0)
  if (length(z) == 0L) "none" else as.character(z[1L])
}
## the accepted render commits only discrete, platform-stable bytes: the
## container class, its field names and per-column classes, the frame shape,
## the integer cluster vector, an all-finite glyph, the zero row and the
## digit-scrubbed head of the sample column. No float payload rides the witness
## (D11): the embed coordinates themselves are never quoted, only the discrete
## facts their values settle.
.cs21_render <- function(x) {
  num <- vapply(x, is.numeric, logical(1L))
  paste0(c(class(x)[1L], paste(names(x), collapse = ","),
    paste0(nrow(x), "x", ncol(x)),
    paste(vapply(x, function(cc) class(cc)[1L], character(1L)), collapse = ","),
    paste(x$cluster, collapse = ","),
    .cs21_glyph(all(vapply(x[num], function(cc) all(is.finite(cc)), logical(1L)))),
    .cs21_zerohead(x),
    .cs21_scrub(.cs21_flat1(as.character(x$sample[1L])))), collapse = "|")
}
.cs21_eval1 <- function(txt, tag) {
  ex <- tryCatch(parse(text = txt), error = identity)
  if (inherits(ex, "error")) stop(paste0("arm ", tag, ": unparsable"))
  if (length(ex) != 1L) stop(paste0("arm ", tag, ": not a single expression"))
  tryCatch(list(ok = TRUE, v = eval(ex[[1L]])), error = identity)
}
.cs21_verdict <- function(r) {
  if (inherits(r, "error")) {
    list(mode = "reject", cls = class(r)[1L], msg = .cs21_msg(r))
  } else {
    list(mode = "accept", cls = class(r$v)[1L], msg = .cs21_render(r$v))
  }
}
.cs21_run <- function(a) .cs21_verdict(.cs21_eval1(.CS21_ARM[[a]], a))
.cs21_cls_of <- function(a) {
  r <- .cs21_eval1(.CS21_ARM[[a]], a)
  if (!inherits(r, "error")) stop(paste0("class probe ", a, ": did not reject"))
  class(r)[1L]
}
.cs21_accept_of <- function(a) {
  r <- .cs21_eval1(.CS21_ARM[[a]], a)
  if (inherits(r, "error")) stop(paste0("accept probe ", a, ": rejected"))
  r$v
}
.cs21_rows <- function(arms) {
  vs <- lapply(arms, .cs21_run)
  data.frame(arm = arms,
    mode = vapply(vs, function(v) v$mode, character(1L)),
    cls = vapply(vs, function(v) v$cls, character(1L)),
    msg = vapply(vs, function(v) v$msg, character(1L)),
    stringsAsFactors = FALSE)
}
.cs21_lawrows <- function() .cs21_rows(.CS21_LAW_ARMS)
.cs21_specrows <- function() .cs21_rows(.CS21_SPEC_ARMS)
.cs21_precrows <- function() {
  df <- .cs21_rows(.CS21_PREC_ARMS)
  df$fires_ok <- vapply(seq_along(df$arm), function(i)
    paste0(grepl(.CS21_PREC_FIRES[i], df$msg[i], fixed = TRUE)), character(1L))
  df$anti_ok <- vapply(seq_along(df$arm), function(i)
    paste0(!grepl(.CS21_PREC_ANTI[i], df$msg[i], fixed = TRUE)), character(1L))
  df
}
.cs21_degenrows <- function() {
  df <- .cs21_rows(.CS21_DEGEN_ARMS)
  data.frame(pair = .CS21_DEGEN_PAIR, side = .CS21_DEGEN_SIDE,
    arm = df$arm, mode = df$mode, cls = df$cls, msg = df$msg,
    stringsAsFactors = FALSE)
}
## the accepted render is read back off one designated acceptance arm; the
## zero-row scalars contrast that arm with the share-guard boundary arm
.cs21_scalval <- function(k) {
  acc <- .cs21_accept_of("A1-clusters-3")
  num <- vapply(acc, is.numeric, logical(1L))
  switch(k,
    "abort-class" = .cs21_cls_of("L1-input-char"),
    "match-class" = .cs21_cls_of("L7-method-bogus"),
    "seed-class" = .cs21_cls_of("L3-seed-vector"),
    "return-class" = class(acc)[1L],
    "clusters-chosen" = as.character(length(unique(acc$cluster))),
    "rows" = as.character(nrow(acc)),
    "cols" = as.character(ncol(acc)),
    "names" = paste(names(acc), collapse = ","),
    "classes" = paste(vapply(acc, function(cc) class(cc)[1L], character(1L)),
      collapse = ","),
    "cluster-vector" = paste(acc$cluster, collapse = ","),
    "sample-head" = .cs21_scrub(.cs21_flat1(as.character(acc$sample[1L]))),
    "finite-glyph" = .cs21_glyph(all(vapply(acc[num],
      function(cc) all(is.finite(cc)), logical(1L)))),
    "zero-row-hi" = .cs21_zerohead(acc),
    "zero-row-lo" = .cs21_zerohead(.cs21_accept_of("share-guard-lo")),
    stop(paste0("unknown scalar key: ", k)))
}
.cs21_scalref_keys <- function() names(.CS21_SCAL_REFIRE)
.cs21_plant_text <- function() paste(c(
  paste0(.CS21_LAW_ARMS, "=", vapply(.CS21_LAW_ARMS, function(a) .CS21_ARM[[a]], character(1L))),
  paste0(.CS21_SPEC_ARMS, "=", vapply(.CS21_SPEC_ARMS, function(a) .CS21_ARM[[a]], character(1L))),
  paste0(.CS21_PREC_ARMS, "=", vapply(.CS21_PREC_ARMS, function(a) .CS21_ARM[[a]], character(1L))),
  paste0(.CS21_DEGEN_ARMS, "=", vapply(.CS21_DEGEN_ARMS, function(a) .CS21_ARM[[a]], character(1L)))
), collapse = ";")
.cs21_spec_text <- function() paste0(.CS21_SPEC_ARMS, collapse = ";")
.cs21_clean <- function(df) {
  for (cnm in names(df)) attr(df[[cnm]], "names") <- NULL
  df
}
## <<CS21-SHARED-END>>  (do not hand-edit in place: edit the source and
##    re-splice) ##

# ===========================================================================
# U1 -- rails: the runner exists and speaks the exported face, never an
# internal (banned-word grep over its full source).
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_embed_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_embed(", "cs21_",
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
  drop <- c(seq(.region("## <<CS21-FROZEN-BEGIN", "## <<CS21-FROZEN-END")[1]:
                .region("## <<CS21-FROZEN-BEGIN", "## <<CS21-FROZEN-END")[2]),
            seq(.region("## <<CS21-SHARED-BEGIN", "## <<CS21-SHARED-END")[1]:
                .region("## <<CS21-SHARED-BEGIN", "## <<CS21-SHARED-END")[2]))
  hand <- paste(lines[-drop], collapse = "\n")
  expect_gt(nchar(hand), 1000L)
  ## the face IS ms_embed, so only the CALL form and the internals stay
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
  for (f in c("cs21_laws.tsv", "cs21_specs.tsv", "cs21_precedence.tsv",
              "cs21_degenerates.tsv", "cs21_scalars.tsv")) {
    expect_true(file.exists(.rs_out21(f)))
    expect_gt(file.size(.rs_out21(f)), 0)
  }
  lw <- .rs_tsv21("cs21_laws.tsv"); sp <- .rs_tsv21("cs21_specs.tsv")
  pr <- .rs_tsv21("cs21_precedence.tsv"); dg <- .rs_tsv21("cs21_degenerates.tsv")
  sc <- .rs_tsv21("cs21_scalars.tsv")
  expect_identical(nrow(lw), 12L)
  expect_identical(nrow(sp), 8L)
  expect_identical(nrow(pr), 12L)
  expect_identical(nrow(dg), 8L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS21_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS21_SCAL_KEYS))
  expect_identical(nrow(sc), 16L)
  for (df in list(lw, sp, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
    expect_false(any(vapply(df, function(cc) any(!nzchar(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the laws witness mirrors the frozen law table: twelve arms, classes
# and verbatim clauses, byte for byte.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv21("cs21_laws.tsv")
  expect_identical(lw$arm, .CS21_LAW_ARMS)
  expect_identical(lw$mode, rep("reject", 12L))
  expect_identical(lw$cls, .CS21_LAW_CLS)
  expect_identical(lw$msg, unname(vapply(.CS21_LAW_ARMS,
    function(a) .CS21_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U4 -- live replay of the law arms: every arm still rejects with its
# committed class and its committed clause bytes ride the live message.
# ===========================================================================
test_that("law arms replay live through the face", {
  live <- .cs21_lawrows()
  expect_identical(live$arm, .CS21_LAW_ARMS)
  expect_identical(live$mode, rep("reject", 12L))
  expect_identical(live$cls, .CS21_LAW_CLS)
  expect_identical(live$msg, unname(vapply(.CS21_LAW_ARMS,
    function(a) .CS21_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U5 -- the specs witness mirrors the frozen acceptance table, the
# acceptance arms replay live and the accepted renders commit the discrete
# shape facts: the container class, its field names and per-column classes,
# the frame shape, the integer cluster vector, the all-finite glyph, the
# zero-total sample index and the digit-scrubbed sample head.
# ===========================================================================
test_that("specs witness mirrors frozen and replays live", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv21("cs21_specs.tsv")
  expect_identical(sp$arm, .CS21_SPEC_ARMS)
  expect_identical(sp$mode, c(rep("accept", 3L), "reject", rep("accept", 4L)))
  expect_identical(sp$cls, .CS21_SPEC_CLS)
  expect_identical(sp$msg, unname(vapply(.CS21_SPEC_ARMS,
    function(a) .CS21_SPEC_DETAILS[[a]], character(1L))))
  live <- .cs21_specrows()
  expect_identical(live$arm, sp$arm)
  expect_identical(live$mode, sp$mode)
  expect_identical(live$cls, sp$cls)
  expect_identical(live$msg, sp$msg)
  w <- function(arm) sp$msg[match(arm, sp$arm)]
  ## the design render pins all eight discrete fields byte for byte
  A1 <- "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"
  expect_identical(w("A1-clusters-3"), A1)
  ## two centres re-shade the same nine samples into a 2-then-1 ladder
  expect_identical(w("A2-clusters-2"),
    "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|2,2,2,1,1,1,2,2,2|1|none|T##")
  ## five centres split the first block again while the ladder holds
  expect_identical(w("A3-clusters-5"),
    "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|4,5,5,3,1,1,2,2,2|1|none|T##")
  ## the bound's own spec contrast: eight centres ride past the signature
  ## count, so the face refuses with the scrubbed clusters-bound clause --
  ## the same bytes the law ladder records for the bound itself
  expect_identical(w("A4-clusters-8"), .CS21_LAW_CLAUSES[["L9-clusters-zero"]])
  expect_identical(w("A4-clusters-8"),
    "clusters must be a single integer in [#, n signatures] | kmeans partitions the share-simplex samples | received: #; signatures: # | kmeans needs at most one cluster per signature dimension")
  ## transform = none, the default seed and the argument order do not move
  ## the render: all three fold onto the design bytes
  expect_identical(w("A5-transform-none"), A1)
  expect_identical(w("A6-seed-default"), A1)
  expect_identical(w("A7-arg-order"), A1)
  ## the nameless plant renames the samples, so only the scrubbed head moves
  ## -- it speaks the sample# placeholder instead of a T## label
  expect_identical(w("A8-nameless-plant"),
    "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|sample#")
})

# ===========================================================================
# U6 -- the precedence witness: committed class, fired anchor PRESENT and
# anti anchor ABSENT in every arm, live replay included.
# ===========================================================================
test_that("precedence witness speaks anchors both ways", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  pr <- .rs_tsv21("cs21_precedence.tsv")
  expect_identical(pr$arm, .CS21_PREC_ARMS)
  expect_identical(pr$mode, rep("reject", 12L))
  expect_identical(pr$cls, .CS21_PREC_CLS)
  expect_identical(pr$fires_ok, rep("TRUE", 12L))
  expect_identical(pr$anti_ok, rep("TRUE", 12L))
  for (i in seq_len(12L)) {
    expect_true(grepl(.CS21_PREC_FIRES[i], pr$msg[i], fixed = TRUE),
                info = .CS21_PREC_ARMS[i])
    expect_false(grepl(.CS21_PREC_ANTI[i], pr$msg[i], fixed = TRUE),
                 info = .CS21_PREC_ARMS[i])
  }
  live <- .cs21_precrows()
  expect_identical(live$msg, pr$msg)
})

# ===========================================================================
# U7 -- the boundary contrast witness: four pairs replayed live against the
# committed bytes; the pair-level discriminators hold (the planted accept
# against the input-gate reject, the over-bound grid against the sample-axis
# window, the planted accept against the all-zero share guard, and the two
# match.arg clause heads from adjacent rungs of the gate ladder).
# ===========================================================================
test_that("boundary contrast pairs hold on both sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  dg <- .rs_tsv21("cs21_degenerates.tsv")
  expect_identical(dg$pair, .CS21_DEGEN_PAIR)
  expect_identical(dg$side, .CS21_DEGEN_SIDE)
  expect_identical(dg$arm, .CS21_DEGEN_ARMS)
  expect_identical(dg$mode, .CS21_DEGEN_MODE)
  expect_identical(dg$cls, .CS21_DEGEN_CLS)
  expect_identical(dg$msg, unname(vapply(.CS21_DEGEN_ARMS,
    function(a) .CS21_DEGEN_MSG[[a]], character(1L))))
  live <- .cs21_degenrows()
  expect_identical(live$msg, dg$msg)
  w <- function(arm) dg$msg[match(arm, dg$arm)]
  head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
  ## plant-accept pair: the planted share matrix accepts on the hi side (the
  ## design render); the bare string dies at the input gate on the lo side
  expect_identical(dg$mode[match("plant-accept-hi", dg$arm)], "accept")
  expect_identical(w("plant-accept-hi"),
    "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##")
  expect_identical(dg$cls[match("plant-accept-lo", dg$arm)],
                   "msuiter_error_input")
  expect_identical(head1(w("plant-accept-lo")),
                   "exposures must be a numeric k x n matrix (or an MsSignature)")
  ## cluster-window pair: both sides reject, but at opposite cluster gates --
  ## six centres ride past the signature bound on the hi side, while the
  ## square k=6 plant passes the bound and dies at the sample-axis window
  expect_identical(dg$mode[match("cluster-window-hi", dg$arm)], "reject")
  expect_identical(head1(w("cluster-window-hi")),
                   "clusters must be a single integer in [#, n signatures]")
  expect_identical(dg$mode[match("cluster-window-lo", dg$arm)], "reject")
  expect_identical(head1(w("cluster-window-lo")),
                   "kmeans needs the cluster count strictly between # and the sample count")
  expect_false(identical(head1(w("cluster-window-hi")),
                         head1(w("cluster-window-lo"))))
  ## share-guard pair: both sides accept; the all-zero last sample re-shades
  ## the cluster ladder and its own row becomes the zero-total index
  expect_identical(dg$mode[match("share-guard-hi", dg$arm)], "accept")
  expect_identical(w("share-guard-hi"),
    "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##")
  expect_identical(dg$mode[match("share-guard-lo", dg$arm)], "accept")
  expect_identical(w("share-guard-lo"),
    "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,2,2,2,1,1,1|1|9|T##")
  expect_false(identical(w("share-guard-hi"), w("share-guard-lo")))
  ## clause-head pair: two distinct match.arg heads from adjacent rungs --
  ## method rides position two of the ladder, transform rides position three
  expect_identical(head1(w("clause-head-hi")), "arg should be one of umap, kmeans")
  expect_identical(head1(w("clause-head-lo")), "arg should be one of share, none")
  expect_false(identical(head1(w("clause-head-hi")),
                         head1(w("clause-head-lo"))))
})

# ===========================================================================
# U8 -- the scalars witness: the re-fireable keys replay live to their
# committed bytes; the rng keys ride the committed purity verdict.
# ===========================================================================
test_that("scalars witness replays and the rng rail stays frozen", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sc <- .rs_tsv21("cs21_scalars.tsv")
  expect_identical(sort(sc$key), sort(.CS21_SCAL_KEYS))
  ## every scalar is re-fireable from the frozen refire table -- the render
  ## keys through the shared probe, the rng rail through its own frozen
  ## expression (the probe must leave the caller's stream untouched)
  for (k in .cs21_scalref_keys()) {
    live <- if (k %in% c("rng-before", "rng-after")) {
      eval(parse(text = .CS21_SCAL_REFIRE[[k]]))
    } else {
      .cs21_scalval(k)
    }
    expect_identical(sc$value[match(k, sc$key)], live, info = k)
    expect_identical(.CS21_SCAL_VALS[[k]], sc$value[match(k, sc$key)], info = k)
  }
  ## the accepted render commits its discrete shape facts as scalars too
  expect_identical(sc$value[match("clusters-chosen", sc$key)], "3")
  expect_identical(sc$value[match("rows", sc$key)], "9")
  expect_identical(sc$value[match("cols", sc$key)], "4")
  expect_identical(sc$value[match("names", sc$key)],
                   "sample,embed_1,embed_2,cluster")
  expect_identical(sc$value[match("classes", sc$key)],
                   "character,numeric,numeric,integer")
  expect_identical(sc$value[match("cluster-vector", sc$key)],
                   "3,3,3,1,1,1,2,2,2")
  ## the scrubbed sample head speaks the placeholder label; the all-finite
  ## glyph is live and the zero-total sample rides the share-guard contrast
  expect_identical(sc$value[match("sample-head", sc$key)], "T##")
  expect_false(grepl("[0-9]", sc$value[match("sample-head", sc$key)]))
  expect_identical(sc$value[match("finite-glyph", sc$key)], "1")
  expect_identical(sc$value[match("zero-row-hi", sc$key)], "none")
  expect_identical(sc$value[match("zero-row-lo", sc$key)], "9")
  ## the three class scalars: the input gate, the match.arg failure and the
  ## accepted container each speak their own class
  expect_identical(sc$value[match("abort-class", sc$key)], "msuiter_error_input")
  expect_identical(sc$value[match("match-class", sc$key)], "simpleError")
  expect_identical(sc$value[match("seed-class", sc$key)], "msuiter_error_input")
  expect_identical(sc$value[match("return-class", sc$key)], "data.frame")
})

# ===========================================================================
# U9 -- dual-kernel SHA-256: the frozen plant corpus and the spec roster
# hash identically under both governed kernels and speak the hex policy.
# ===========================================================================
test_that("plant and spec corpora agree under both sha256 kernels", {
  for (tag in c("plant", "spec")) {
    txt <- if (identical(tag, "plant")) .cs21_plant_text() else .cs21_spec_text()
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
  expect_identical(length(.CS21_LAW_ARMS), 12L)
  expect_identical(length(.CS21_SPEC_ARMS), 8L)
  expect_identical(length(.CS21_PREC_ARMS), 12L)
  expect_identical(length(.CS21_DEGEN_ARMS), 8L)
  expect_identical(length(.CS21_SCAL_KEYS), 16L)
  expect_identical(length(.CS21_ARM), 40L)
  expect_identical(length(.CS21_CENSUS), 3L)
  allc <- c(.CS21_LAW_ARMS, .CS21_SPEC_ARMS, .CS21_PREC_ARMS, .CS21_DEGEN_ARMS)
  expect_false(any(duplicated(allc)))
  expect_true(all(allc %in% names(.CS21_ARM)))
  for (a in names(.CS21_ARM)) {
    expect_identical(length(parse(text = .CS21_ARM[[a]])), 1L, info = a)
  }
  allcls <- c(.CS21_LAW_CLS, .CS21_PREC_CLS, .CS21_SPEC_CLS, .CS21_DEGEN_CLS)
  tally <- function(cl) paste0(cl, "=", sum(allcls == cl))
  want <- c(tally("data.frame"), tally("msuiter_error_input"),
            tally("simpleError"))
  expect_true(all(want %in% .CS21_CENSUS))
  expect_identical(sort(.CS21_CENSUS), sort(want))
})
