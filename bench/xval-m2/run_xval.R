# run_xval.R -- M2 acceptance gate: extraction-layer toy cross-validation of
# msuiter's default extraction pipeline against sigminer's NMF extraction
# (three-way with the known synthetic truth: msuiter vs sigminer vs truth).
#
# Task naming correction (recorded in result.md): the task brief called the
# sigminer entry point `sig_auto_extract(sig_input, k = ...)`. In sigminer
# 2.3.1 the fixed-k NMF extraction with the brunet (KL) default is
#   sig_extract(nmf_matrix, n_sig = k, method = "brunet", seed = 123456)
# (rows = SAMPLES, columns = channels); `sig_auto_extract()` has NO k
# argument -- it is the PCAWG-style auto-K selector (methods L1W.L2H /
# L1KL / L2KL). Both are run here: sig_extract as the designated fixed-k
# comparison, sig_auto_extract(L1KL) as a supplementary auto-K arm.
#
# Design (extraction layer only -- the tally layer was xvalidated at M1s,
# bench/xval/): one synthetic truth (3 separable SBS96 signatures with
# disjoint dominant support + a small shared background, 12 samples in four
# groups of 3), ONE integer counts matrix fed to BOTH engines unchanged:
#   * msuiter:   counts --MsCatalog--> ms_extract(k = 3) default pipeline
#                (D16: KL-NMF ensemble -> Hungarian consensus -> NNLS refit
#                -> SUITOR CV evidence).
#   * sigminer:  t(counts) -> sig_extract(n_sig = 3) [brunet defaults]
#                and -> sig_auto_extract(method = "L1KL") [auto-K].
# Verdict: both engines recover every planted signature from the truth with
# cosine > 0.9 AND the msuiter-vs-sigminer best-match cosine > 0.95 for all
# three pairings (greedy matching on the 3 x 3 cosine grid).
#
# Channel identities are the REAL COSMIC SBS96 labels in msuiter's registry
# order; the script re-verifies (a) that order against sigminer's own
# reference signature DB rownames (flank-major, as proven at M1s for
# sig_tally), and (b) that neither engine permutes the channel order it was
# given (alignment by label remains the contract; order equality is the
# audit).
#
# Run: Rscript bench/xval-m2/run_xval.R  (writes artifacts next to script)

## ---------------------------------------------------------------- setup ----

.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  if (length(f) > 0L) dirname(normalizePath(f)) else normalizePath(getwd())
}
ROOT <- dirname(dirname(.script_dir()))
OUT <- file.path(ROOT, "bench", "xval-m2")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

.message <- function(...) cat(sprintf(...), "\n", sep = "")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(file.path(ROOT, "R"))) {
  pkgload::load_all(ROOT, quiet = TRUE)
} else {
  library(msuiter)
}
suppressPackageStartupMessages(library(sigminer))

.message("msuiter: %s | sigminer: %s | R %s",
  tryCatch(as.character(pkgload::inst_pack_version(ROOT)),
    error = function(e) "dev-load"),
  as.character(packageVersion("sigminer")), getRversion())

SEED <- 20260930L
set.seed(SEED)

## -------------------------------------------------- channel identities ----
# The 96-channel identity frame: msuiter's own SBS96 registry order (the
# reference frame, as at M1s), cross-checked against sigminer's reference
# signature DB rownames read independently from the installed package data.

labs_msuiter <- {
  tables <- get("channel_tables", envir = asNamespace("msuiter"))
  as.character(tables[["SBS96"]]$labels)
}
stopifnot(length(labs_msuiter) == 96L, !anyDuplicated(labs_msuiter))

sg_db <- get_sig_db("SBS") # COSMIC v3.1 reference signatures shipped by sigminer
labs_sgdb <- rownames(sg_db$db)
stopifnot(length(labs_sgdb) == 96L)

.message("== channel order audit ==")
.message("msuiter registry order == sigminer reference DB rownames: %s",
  identical(labs_msuiter, labs_sgdb))
if (!identical(labs_msuiter, labs_sgdb)) {
  .message("first divergence at position %d: %s vs %s",
    which(labs_msuiter != labs_sgdb)[1L],
    labs_msuiter[which(labs_msuiter != labs_sgdb)[1L]],
    labs_sgdb[which(labs_msuiter != labs_sgdb)[1L]])
}
CANON <- labs_msuiter # the one channel frame used everywhere below

## ---------------------------------------------------- synthetic truth ----
# 3 signatures x 96 channels: 27 exclusive anchor channels per signature
# (disjoint dominant support) + 15 shared background channels (small weight
# in every signature). 12 samples x 4 groups of 3: groups 1-3 near-pure
# (one dominant signature + trace cross exposure), group 4 fully mixed.
# Same construction shape as tests/testthat/helper-extract.R (U-M1s-12).

ch <- 96L
ns <- 12L
k <- 3L
anchors <- 27L
shared_n <- 15L

truth_w <- matrix(0, nrow = ch, ncol = k)
for (s in seq_len(k)) {
  idx <- ((s - 1L) * anchors + 1L):(s * anchors)
  truth_w[idx, s] <- 0.5 + runif(anchors)
}
shared_idx <- (k * anchors + 1L):(k * anchors + shared_n)
truth_w[shared_idx, ] <- 0.04 # the small shared background
truth_w <- sweep(truth_w, 2, colSums(truth_w), "/")
stopifnot(all(abs(colSums(truth_w) - 1) < 1e-12))

truth_h <- matrix(0, nrow = k, ncol = ns)
for (j in seq_len(ns)) {
  dom <- ((j - 1L) %/% 3L) + 1L # groups 1..3 near-pure, 4 mixed
  for (s in seq_len(k)) {
    truth_h[s, j] <- if (dom == 4L || s == dom) 800 + 400 * runif(1) else 30 * runif(1)
  }
}
counts <- round(truth_w %*% truth_h) # integer mutation counts
storage.mode(counts) <- "numeric"
dimnames(counts) <- list(CANON, sprintf("S%02d", seq_len(ns)))
stopifnot(all(counts == round(counts)), all(counts >= 0))
.message("\n== synthetic truth ==")
.message("signatures: %d (%d anchor channels each + %d shared background) | samples: %d",
  k, anchors, shared_n, ns)
.message("counts: %d x %d, total = %d, per-sample median = %.0f",
  nrow(counts), ncol(counts), sum(counts), median(colSums(counts)))
.message("shared-background mass fraction per signature: %s",
  paste(sprintf("%.3f", colSums(truth_w[shared_idx, , drop = FALSE])), collapse = ", "))

write.csv(counts, file.path(OUT, "counts_input.csv"))
write.csv(round(truth_w, 6), file.path(OUT, "truth_signatures.csv"))
write.csv(round(truth_h, 2), file.path(OUT, "truth_exposures.csv"))

## ------------------------------------------------------- msuiter engine ----
# The test-path construction (test-m2-e2e.R): direct MsCatalog, then the
# D16 default pipeline at k = 3.
.message("\n== msuiter ms_extract(k=3) default pipeline ==")
cat1 <- ms_catalog(
  counts = counts,
  channels = list(name = "SBS96", labels = CANON),
  samples = colnames(counts),
  provenance = list(genome = "SYN-xval-m2")
)
t0 <- Sys.time()
fit <- ms_extract(cat1, k = k) # default pipeline (consensus-CV, D16)
t_ms <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
sig_ms <- fit@signatures # channels x signatures, columns normalized to sum 1
.message("engine = %s | %.1f s | %d x %d, col sums ~ %s | rows in input order: %s",
  fit@engine, t_ms, nrow(sig_ms), ncol(sig_ms),
  paste(sprintf("%.4f", colSums(sig_ms)), collapse = "/"),
  identical(rownames(sig_ms), CANON))
.message("stability: avg = %.3f | k_evidence rows = %d",
  fit@stability$avg_stability, nrow(fit@k_evidence))

## ------------------------------------------------------ sigminer engine ----
# Convention check + two arms. sigminer's NMF input is samples x channels.
.message("\n== sigminer extraction ==")
nmf_matrix <- t(counts) # rows = samples, columns = channels
stopifnot(identical(colnames(nmf_matrix), CANON))

# Arm 1 (designated): fixed-k NMF, package defaults (brunet = KL, nrun = 10,
# seed = 123456). This is the sigminer counterpart of "k = 3, brunet/kl".
t0 <- Sys.time()
res_sg <- sig_extract(nmf_matrix, n_sig = k, seed = 123456) # nrun/method defaults
t_sg <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
sig_sg <- res_sg$Signature.norm # channels x signatures, columns sum to 1
.message("sig_extract(method=brunet, nrun=10, seed=123456): %.1f s | rows in input order: %s",
  t_sg, identical(rownames(sig_sg), CANON))

# Arm 2 (supplementary): PCAWG-style auto-K, L1KL (the KL arm). K is NOT
# passed -- the point is whether the auto-selector lands on the true K = 3.
t0 <- Sys.time()
dir.create(file.path(OUT, "sigminer-auto"), showWarnings = FALSE, recursive = TRUE)
res_auto <- sig_auto_extract(nmf_matrix = nmf_matrix, method = "L1KL",
  nrun = 10, destdir = file.path(OUT, "sigminer-auto"), skip = FALSE)
t_auto <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
sig_auto <- res_auto$Signature.norm
if (is.null(colnames(sig_auto))) colnames(sig_auto) <- paste0("Sig", seq_len(ncol(sig_auto)))
k_auto <- ncol(sig_auto)
.message("sig_auto_extract(L1KL): %.1f s | auto-selected K = %d | rows in input order: %s",
  t_auto, k_auto, identical(rownames(sig_auto), CANON))

## ---------------------------------------------------------- comparison ----
.cos <- function(a, b) {
  a <- as.numeric(a); b <- as.numeric(b)
  drop(a %*% b / sqrt(crossprod(a) * crossprod(b)))
}

# Greedy 1-1 matching on a cosine grid: returns data.frame(a, b, cosine).
.greedy_match <- function(C) {
  out <- list(); used_r <- logical(nrow(C)); used_c <- logical(ncol(C))
  repeat {
    sub <- C; sub[used_r, ] <- -Inf; sub[, used_c] <- -Inf
    if (all(!is.finite(sub))) break
    w <- arrayInd(which.max(sub), dim(sub))
    used_r[w[1]] <- TRUE; used_c[w[2]] <- TRUE
    out[[length(out) + 1L]] <- data.frame(a = w[1], b = w[2], cosine = C[w[1], w[2]])
  }
  do.call(rbind, out)
}

truth_n <- sweep(truth_w, 2, colSums(truth_w^2)^0.5, "/") # unit columns
.recover <- function(mat) { # mat: channels x sigs -> best-match per truth sig
  mn <- sweep(mat, 2, colSums(mat^2)^0.5, "/")
  C <- crossprod(truth_n, mn) # k x ncol(mat)
  m <- .greedy_match(C)
  m$truth <- sprintf("T%d", m$a); m$extracted <- sprintf("%s", colnames(mat)[m$b])
  m[, c("truth", "extracted", "cosine")]
}

.message("\n== recovery vs known truth (greedy best-match cosine) ==")
rec_ms <- .recover(sig_ms)
rec_sg <- .recover(sig_sg)
rec_auto <- if (k_auto == k) .recover(sig_auto) else NULL
.report_rec <- function(nm, rec, kx) {
  if (is.null(rec)) {
    .message("%-12s: K = %d != true k = 3, recovery matching skipped", nm, kx)
    return(invisible())
  }
  for (i in seq_len(nrow(rec))) {
    .message("%-12s truth %s ~ %s : cosine = %.4f", nm, rec$truth[i],
      rec$extracted[i], rec$cosine[i])
  }
}
.report_rec("msuiter", rec_ms, k)
.report_rec("sigminer", rec_sg, k)
.report_rec("sig-autoKL", rec_auto, k_auto)

# The acceptance pair: msuiter vs sigminer fixed-k brunet, 3 x 3 cosine grid.
.message("\n== msuiter vs sigminer (3 x 3 cosine grid, greedy pairing) ==")
ms_n <- sweep(sig_ms, 2, colSums(sig_ms^2)^0.5, "/")
sg_n <- sweep(sig_sg, 2, colSums(sig_sg^2)^0.5, "/")
C_xval <- crossprod(ms_n, sg_n)
rownames(C_xval) <- colnames(sig_ms); colnames(C_xval) <- colnames(sig_sg)
print(round(C_xval, 4))
pair <- .greedy_match(C_xval)
pair$msuiter <- colnames(sig_ms)[pair$a]; pair$sigminer <- colnames(sig_sg)[pair$b]
pair <- pair[, c("msuiter", "sigminer", "cosine")]
for (i in seq_len(nrow(pair))) {
  .message("pairing %s ~ %s : cosine = %.4f", pair$msuiter[i], pair$sigminer[i],
    pair$cosine[i])
}

# Secondary: exposure-profile agreement on the paired signatures
# (per-sample share of total exposure, cosine across the 12 samples).
exp_ms <- fit@exposures # k x samples
exp_sg <- res_sg$Exposure
if (is.null(rownames(exp_sg))) rownames(exp_sg) <- colnames(sig_sg)
share_ms <- sweep(exp_ms, 2, colSums(exp_ms), "/")
share_sg <- sweep(exp_sg, 2, colSums(exp_sg), "/")
pair$exposure_cosine <- vapply(seq_len(nrow(pair)), function(i)
  .cos(share_ms[pair$msuiter[i], ], share_sg[pair$sigminer[i], ]), numeric(1))
.message("\n== exposure share agreement (paired signatures, 12 samples) ==")
for (i in seq_len(nrow(pair))) {
  .message("%s ~ %s : exposure-share cosine = %.4f", pair$msuiter[i],
    pair$sigminer[i], pair$exposure_cosine[i])
}

# Supplementary auto-K pairing (only meaningful if K landed on 3)
if (identical(k_auto, k)) {
  auto_n <- sweep(sig_auto, 2, colSums(sig_auto^2)^0.5, "/")
  C_auto <- crossprod(ms_n, auto_n)
  pair_auto <- .greedy_match(C_auto)
  .message("\n== supplementary: msuiter vs sig_auto_extract(L1KL, K=%d) best-match cosines ==",
    k_auto)
  .message("%s", paste(sprintf("%.4f", pair_auto$cosine), collapse = ", "))
  write.csv(round(C_auto, 4), file.path(OUT, "cosine_msuiter_vs_autoKL.csv"))
}

## ------------------------------------------------------------- verdict ----
.message("\n== verdict ==")
gate_rec <- all(rec_ms$cosine > 0.9) && all(rec_sg$cosine > 0.9)
gate_pair <- all(pair$cosine > 0.95)
gate_order <- identical(rownames(sig_ms), CANON) && identical(rownames(sig_sg), CANON)
.message("both engines recover truth (cosine > 0.90 per signature): %s", gate_rec)
.message("msuiter ~ sigminer best-match cosine > 0.95 for all %d pairings: %s",
  nrow(pair), gate_pair)
.message("neither engine permuted the input channel order: %s", gate_order)
.message("OVERALL: %s", if (gate_rec && gate_pair) "PASS" else "FAIL")

## ------------------------------------------------------------- persist ----
write.csv(counts, file.path(OUT, "counts_input.csv"))
write.csv(round(C_xval, 6), file.path(OUT, "cosine_msuiter_vs_sigminer.csv"))
write.csv(rec_ms, file.path(OUT, "recovery_msuiter.csv"), row.names = FALSE)
write.csv(rec_sg, file.path(OUT, "recovery_sigminer.csv"), row.names = FALSE)
write.csv(pair, file.path(OUT, "pairing_msuiter_sigminer.csv"), row.names = FALSE)
.save_rds <- function(x, nm) saveRDS(x, file.path(OUT, nm))
.save_rds(list(truth_w = truth_w, truth_h = truth_h, counts = counts,
  labels = CANON, seed = SEED), "truth.rds")
.message("\nartifacts in %s", OUT)
