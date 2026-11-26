# run_embed_witness.R -- the CS-21 embed-witness scenario (pillar 3).
#
# Mandate: plant synthetic exposure matrices (the D3 law: zero COSMIC numeric
# matrices, zero real-data bytes, zero downloads -- the exposures ride only as
# synthetic count matrices over synthetic signature and sample labels) and
# adjudicate the EXPORTED ms_embed() face: the six-step gate ladder (input,
# method, transform, seed, the cluster bound, the cluster window), the
# accepted projection renders, the six precedence discriminators with their
# anti anchors, the boundary contrast pairs and the acceptance specs. Every
# arm is driven through the exported face alone; the accepted returns, the
# abort classes and the fired clauses are the face's own. The scenario
# consumes no RNG, no network and no clock at the adjudication core -- the
# face seeds its own kernel internally and restores the caller's stream, so
# the purity verdict is itself a witnessed claim; the benchmark runner and
# the DECLINED calibration family are never invoked here.
#
# Framing law: DECISION RECORD only. The witnesses under out/ are the
# committed verdict of what the shipped face SAID on planted truth. Float
# posture (D11): the projection returns real coordinates whose last bits are
# ill-conditioned, so no float payload rides any witness -- the accepted
# render commits DISCRETE facts instead (the container class, its field names
# and per-column classes, the frame shape, the integer cluster vector, an
# all-finite glyph, the index of the zero-total sample and the digit-scrubbed
# head of the sample column); integer, label, logical, class and clause bytes
# are byte-committed.
#
# Rails: this runner carries the same frozen block as the law file
# (tests/testthat/test-scenario-embed-witness.R), injected byte-identically
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
## RNG-STATE-RAIL: the adjudication core must never seed or consume RNG; the
## face snapshots and restores the caller's stream around its kernel, so the
## purity verdict rides the scalars witness (committed bytes below).
rng0 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
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

laws <- .cs21_lawrows()
stopif(!identical(laws$arm, .CS21_LAW_ARMS), "laws: roster drift")
stopif(!identical(laws$mode, rep("reject", 12L)), "laws: a mode drift")
stopif(!identical(laws$cls, .CS21_LAW_CLS), "laws: a class drift")
stopif(!identical(laws$msg, unname(vapply(.CS21_LAW_ARMS,
  function(a) .CS21_LAW_CLAUSES[[a]], character(1L)))), "laws: clause byte drift")
.census("laws", laws, 12L)

specs <- .cs21_specrows()
stopif(!identical(specs$arm, .CS21_SPEC_ARMS), "specs: roster drift")
stopif(!identical(specs$mode,
                  c(rep("accept", 3L), "reject", rep("accept", 4L))),
       "specs: a mode drift")
stopif(!identical(specs$cls, .CS21_SPEC_CLS), "specs: a class drift")
stopif(!identical(specs$msg, unname(vapply(.CS21_SPEC_ARMS,
  function(a) .CS21_SPEC_DETAILS[[a]], character(1L)))), "specs: detail byte drift")
## the design render pins all eight discrete fields byte for byte; the
## variants fold onto its bytes except where the plant itself differs
stopif(!identical(specs$msg[match("A1-clusters-3", specs$arm)],
                  "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##"),
       "specs: the design render moved")
stopif(!identical(specs$msg[match("A2-clusters-2", specs$arm)],
                  "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|2,2,2,1,1,1,2,2,2|1|none|T##"),
       "specs: the two-centre render moved")
stopif(!identical(specs$msg[match("A3-clusters-5", specs$arm)],
                  "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|4,5,5,3,1,1,2,2,2|1|none|T##"),
       "specs: the five-centre render moved")
## the bound's own spec contrast: eight centres ride past the signature
## count, so the face refuses with the scrubbed clusters-bound clause
stopif(!identical(specs$msg[match("A4-clusters-8", specs$arm)],
                  .CS21_LAW_CLAUSES[["L9-clusters-zero"]]),
       "specs: the bound-contrast arm moved")
## transform = none, the default seed and the argument order do not move
## the render: all three fold onto the design bytes
stopif(!identical(specs$msg[match("A5-transform-none", specs$arm)],
                  specs$msg[match("A1-clusters-3", specs$arm)]),
       "specs: the transform-none render moved")
stopif(!identical(specs$msg[match("A6-seed-default", specs$arm)],
                  specs$msg[match("A1-clusters-3", specs$arm)]),
       "specs: the default-seed render moved")
stopif(!identical(specs$msg[match("A7-arg-order", specs$arm)],
                  specs$msg[match("A1-clusters-3", specs$arm)]),
       "specs: the argument-order render moved")
## the nameless plant renames the samples, so only the scrubbed head moves
stopif(!identical(specs$msg[match("A8-nameless-plant", specs$arm)],
                  "data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|sample#"),
       "specs: the nameless-plant render moved")
.census("specs", specs, 8L)

prec <- .cs21_precrows()
stopif(!identical(prec$arm, .CS21_PREC_ARMS), "prec: roster drift")
stopif(!identical(prec$mode, rep("reject", 12L)), "prec: a mode drift")
stopif(!identical(prec$cls, .CS21_PREC_CLS), "prec: a class drift")
stopif(!all(prec$fires_ok == "TRUE"), "prec: a fired anchor missing")
stopif(!all(prec$anti_ok == "TRUE"), "prec: an anti anchor present")
for (i in seq_len(12L)) {
  stopif(!grepl(.CS21_PREC_FIRES[i], prec$msg[i], fixed = TRUE),
         paste0("prec: fire anchor absent in ", .CS21_PREC_ARMS[i]))
  stopif(grepl(.CS21_PREC_ANTI[i], prec$msg[i], fixed = TRUE),
         paste0("prec: anti anchor present in ", .CS21_PREC_ARMS[i]))
}
.census("prec", prec, 12L)

degen <- .cs21_degenrows()
stopif(!identical(degen$pair, .CS21_DEGEN_PAIR), "degen: pair drift")
stopif(!identical(degen$side, .CS21_DEGEN_SIDE), "degen: side drift")
stopif(!identical(degen$arm, .CS21_DEGEN_ARMS), "degen: arm drift")
stopif(!identical(degen$mode, .CS21_DEGEN_MODE), "degen: mode drift")
stopif(!identical(degen$cls, .CS21_DEGEN_CLS), "degen: class drift")
stopif(!identical(degen$msg, unname(vapply(.CS21_DEGEN_ARMS,
  function(a) .CS21_DEGEN_MSG[[a]], character(1L)))), "degen: msg byte drift")
.w <- function(arm) degen$msg[match(arm, degen$arm)]
head1 <- function(txt) strsplit(txt, " | ", fixed = TRUE)[[1L]][1L]
## plant-accept pair: the planted share matrix accepts on the hi side (the
## design render); the bare string dies at the input gate on the lo side
stopif(!identical(degen$mode[match("plant-accept-hi", degen$arm)], "accept"),
       "degen: the planted arm did not accept")
stopif(!grepl("data.frame|sample,embed_1,embed_2,cluster|9x4|character,numeric,numeric,integer|3,3,3,1,1,1,2,2,2|1|none|T##",
              .w("plant-accept-hi"), fixed = TRUE),
       "degen: the planted render moved")
stopif(!identical(degen$cls[match("plant-accept-lo", degen$arm)],
                  "msuiter_error_input"),
       "degen: the input-gate class moved")
stopif(!identical(head1(.w("plant-accept-lo")),
                  "exposures must be a numeric k x n matrix (or an MsSignature)"),
       "degen: the input-gate head moved")
## cluster-window pair: both sides reject, but at opposite cluster gates --
## six centres ride past the signature bound on the hi side, while the
## square k=6 plant passes the bound and dies at the sample-axis window
stopif(!identical(degen$mode[match("cluster-window-hi", degen$arm)], "reject"),
       "degen: the over-bound arm did not reject")
stopif(!identical(head1(.w("cluster-window-hi")),
                  "clusters must be a single integer in [#, n signatures]"),
       "degen: the bound head moved")
stopif(!identical(degen$mode[match("cluster-window-lo", degen$arm)], "reject"),
       "degen: the window arm did not reject")
stopif(!identical(head1(.w("cluster-window-lo")),
                  "kmeans needs the cluster count strictly between # and the sample count"),
       "degen: the window head moved")
## share-guard pair: both sides accept; the all-zero last sample re-shades
## the cluster ladder and its own row becomes the zero-total index
stopif(!identical(degen$mode[match("share-guard-hi", degen$arm)], "accept"),
       "degen: the share-guard hi arm did not accept")
stopif(!identical(degen$mode[match("share-guard-lo", degen$arm)], "accept"),
       "degen: the share-guard lo arm did not accept")
stopif(!grepl("|3,3,3,2,2,2,1,1,1|1|9|", .w("share-guard-lo"), fixed = TRUE),
       "degen: the all-zero render moved")
stopif(identical(.w("share-guard-hi"), .w("share-guard-lo")),
       "degen: the share-guard renders collapsed")
## clause-head pair: two distinct match.arg heads from adjacent rungs --
## method rides position two of the ladder, transform rides position three
stopif(!identical(head1(.w("clause-head-hi")),
                  "arg should be one of umap, kmeans"),
       "degen: the method head moved")
stopif(!identical(head1(.w("clause-head-lo")),
                  "arg should be one of share, none"),
       "degen: the transform head moved")
stopif(identical(head1(.w("clause-head-hi")), head1(.w("clause-head-lo"))),
       "degen: the two clause heads collapsed")
.census("degen", degen, 8L, key.col = 3L)

rng1 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
scal.vals <- vapply(.CS21_SCAL_KEYS, function(k) {
  if (identical(k, "rng-before")) return(format(rng0))
  if (identical(k, "rng-after")) return(format(rng1))
  v <- .cs21_scalval(k)
  stopif(is.na(v) || !nzchar(v), paste0("scalars: empty re-fire for ", k))
  stopif(!identical(v, .CS21_SCAL_VALS[[k]]), paste0("scalars: drift for ", k))
  v
}, character(1L))
scalars <- data.frame(key = .CS21_SCAL_KEYS, value = unname(scal.vals),
                      stringsAsFactors = FALSE)
stopif(!identical(scalars$value[match("rng-before", .CS21_SCAL_KEYS)],
                  .CS21_SCAL_VALS[["rng-before"]]), "scalars: rng-before drift")
stopif(!identical(scalars$value[match("rng-after", .CS21_SCAL_KEYS)],
                  .CS21_SCAL_VALS[["rng-after"]]), "scalars: rng-after drift")
## the accepted render commits its discrete shape facts as scalars too
stopif(!identical(scalars$value[match("clusters-chosen", .CS21_SCAL_KEYS)], "3"),
       "scalars: the chosen cluster count moved")
stopif(!identical(scalars$value[match("rows", .CS21_SCAL_KEYS)], "9"),
       "scalars: the row count moved")
stopif(!identical(scalars$value[match("cols", .CS21_SCAL_KEYS)], "4"),
       "scalars: the column count moved")
stopif(!identical(scalars$value[match("names", .CS21_SCAL_KEYS)],
                  "sample,embed_1,embed_2,cluster"), "scalars: the names moved")
stopif(!identical(scalars$value[match("classes", .CS21_SCAL_KEYS)],
                  "character,numeric,numeric,integer"), "scalars: the classes moved")
stopif(!identical(scalars$value[match("cluster-vector", .CS21_SCAL_KEYS)],
                  "3,3,3,1,1,1,2,2,2"), "scalars: the cluster vector moved")
## the scrubbed sample head speaks the placeholder label; the all-finite
## glyph is live and the zero-total sample rides the share-guard contrast
stopif(!identical(scalars$value[match("sample-head", .CS21_SCAL_KEYS)], "T##"),
       "scalars: the sample head moved")
stopif(!identical(scalars$value[match("finite-glyph", .CS21_SCAL_KEYS)], "1"),
       "scalars: the finite glyph moved")
stopif(!identical(scalars$value[match("zero-row-hi", .CS21_SCAL_KEYS)], "none"),
       "scalars: the planted zero-row moved")
stopif(!identical(scalars$value[match("zero-row-lo", .CS21_SCAL_KEYS)], "9"),
       "scalars: the all-zero zero-row moved")
## the three class scalars: the input gate, the match.arg failure and the
## accepted container each speak their own class
stopif(!identical(scalars$value[match("abort-class", .CS21_SCAL_KEYS)],
                  "msuiter_error_input"), "scalars: the abort class moved")
stopif(!identical(scalars$value[match("match-class", .CS21_SCAL_KEYS)],
                  "simpleError"), "scalars: the match class moved")
stopif(!identical(scalars$value[match("seed-class", .CS21_SCAL_KEYS)],
                  "msuiter_error_input"), "scalars: the seed class moved")
stopif(!identical(scalars$value[match("return-class", .CS21_SCAL_KEYS)],
                  "data.frame"), "scalars: the return class moved")
.census("scalars", scalars, 16L)

## dual-kernel hashes over the frozen corpora (written nowhere, attested)
plant.sha <- .ck(charToRaw(.cs21_plant_text()), "plant-corpus")
spec.sha <- .ck(charToRaw(.cs21_spec_text()), "spec-corpus")

## ---------------------------------------------------------------------------
## all censuses spoke: commit the five witnesses
## ---------------------------------------------------------------------------
.wtab("cs21_laws.tsv", laws)
.wtab("cs21_specs.tsv", specs)
.wtab("cs21_precedence.tsv", prec)
.wtab("cs21_degenerates.tsv", degen)
.wtab("cs21_scalars.tsv", scalars)

cat("[attest] at=", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    " out=", OUT, "\n", sep = "")
for (nm in c("cs21_laws.tsv", "cs21_specs.tsv", "cs21_precedence.tsv",
             "cs21_degenerates.tsv", "cs21_scalars.tsv")) {
  cat("[attest] sha256 ", nm, "=", .file.sha(nm), "\n", sep = "")
}
cat("[attest] plant_sha256=", plant.sha, " spec_sha256=", spec.sha,
    " files=", length(list.files(OUT, pattern = "^cs21_")), "\n", sep = "")
cat("OVERALL PASS\n")
quit(save = "no", status = 0L)
