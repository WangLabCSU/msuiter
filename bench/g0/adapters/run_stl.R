#!/usr/bin/env Rscript
# G0 Tier-1 adapter: signature.tools.lib v2.5.2 (Nik-Zainal-Group)
#
# Contract: adapter_protocol.md (2026-09-28 revision). Tier-1 regime: FitMS package defaults
# (KLD / fixedThreshold 5%) + useBootstrap=TRUE + nboot=params$nboot (officially frozen at 200).
#
# ── W1/D2 reconciliation verdict (checked item-by-item against STL v2.5.2 source; see protocol §5) ──
# 1) FitMS real parameter names: catalogues= (samples are **columns**, channels are rows), commonSignatures=,
#    rareSignatures=, useBootstrap=, nboot=, nparallel=, randomSeed=.
#    (the old code's signature/counts/method/nboot/parallelisation parameters do not exist at all.)
# 2) W1 ruling: formal experiments do NOT take the STL organ T1 route (Breast RefSig T1 lacks
#    ground-truth signatures such as SBS40); everything goes the commonSignatures=<fit catalog> route
#    (formal = frozen v3.6 catalog file, mounted as catalog.csv by the harness via G0_CATALOG_PATH).
#    rareSignatures= left empty + maxRareSigsPerSample=0 ⇒ degenerates to whole-catalog common
#    fitting (FitMS docs sanction this usage), no rare-signature search -- the catalog is the deployment regime.
# 3) **channel-order trap**: STL demands its classic order (C>A,C>G,C>T,T>A,T>C,T>G outer ×
#    5' A/C/G/T × 3' A/C/G/T; the SBSchannels of getTypeOfMutationsFromChannels),
#    which differs from the lexicographic order of the repo anchor tools/channel-reference/SBS96.txt. Inputs must
#    be reordered into it (catalog and counts reordered in sync; exposure results carry no channel
#    dimension, no reorder-back needed). After reordering, assert "subs" via the package's own :::getTypeOfMutationsFromChannels.
# 4) Return structure: res$exposures = samples(rows) × signatures(cols) (**includes an "unassigned" column,
#    drop it**; all-zero signature columns are dropped by the package ⇒ map back onto the full catalog
#    columns, absent signatures reported honestly as [0,0] intervals); bootstrap intervals are computed
#    per sample from res$bootstrap_exposures_samples[[sample]] (signatures × nboot, unfiltered bootstrap
#    fits) as the 2.5/97.5 percentiles. Signatures the package filtered (est==0): interval collapses to [0,0], zeroed=1.
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(signature.tools.lib))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  i <- match(flag, args)
  if (is.na(i)) stop(paste("missing arg:", flag))
  return(args[i + 1])
}

fail <- function(msg) {
  # Note: writeLines has no append argument -- appending must use cat
  cat(paste0(format(Sys.time()), " FATAL [run_stl]: ", msg, "\n"),
      file = err_log, append = TRUE, sep = "")
  quit(save = "no", status = 1)
}

counts_path  <- get_arg("--counts")
catalog_path <- get_arg("--catalog")
params_path  <- get_arg("--params")
outdir       <- get_arg("--outdir")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# errors.log lands first (the run_grid cache guard requires out/ to carry errors.log; failure info is
# appended -- deployed behavior is the evidence, protocol §2.1). Clear stale half-written output first.
err_log <- file.path(outdir, "errors.log")
unlink(file.path(outdir, "intervals.csv"))
unlink(file.path(outdir, "manifest.json"))
writeLines(character(0), err_log)

tryCatch({

params <- jsonlite::fromJSON(params_path)
seed   <- as.integer(params$seed)
if (is.na(seed)) fail("params.seed missing or not an integer")
nboot  <- as.integer(ifelse(is.null(params$nboot), 200, params$nboot))  # officially frozen at 200

# ---- STL classic 96-channel order (substitution outer × 5' × 3', matching the package's SBSchannels) ----
stl_channels <- local({
  subs  <- c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G")
  bases <- c("A", "C", "G", "T")
  unlist(lapply(subs, function(s) {
    g <- expand.grid(b3 = bases, b5 = bases, stringsAsFactors = FALSE)  # b3 changes fastest
    paste0(g$b5, "[", s, "]", g$b3)
  }))
})
stopifnot(length(stl_channels) == 96)

# ---- read in + explicit numeric defense (non-numeric columns rejected) ----
read_matrix_csv <- function(path) {
  df <- read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  if (ncol(df) < 2) fail(paste0(path, ": need >= 2 columns (id + data)"))
  ids <- trimws(as.character(df[[1]]))
  if (any(!nzchar(ids)) || anyNA(ids)) fail(paste0(path, ": empty id in first column"))
  if (anyDuplicated(ids)) fail(paste0(path, ": duplicated ids in first column"))
  dat <- df[, -1, drop = FALSE]
  for (cn in colnames(dat)) {
    if (!is.numeric(dat[[cn]])) {
      fail(paste0(path, ": column '", cn, "' is not numeric — non-numeric columns are rejected"))
    }
  }
  m <- as.matrix(dat); rownames(m) <- ids
  if (any(!is.finite(m))) fail(paste0(path, ": non-finite values (NA/NaN/Inf) not allowed"))
  m
}
counts  <- read_matrix_csv(counts_path)    # rows = sample_id, cols = 96 channels (repo-anchor order)
catalog <- read_matrix_csv(catalog_path)   # rows = channel (96), cols = signatures (repo-anchor order)

stopifnot(ncol(counts) == 96, nrow(catalog) == 96)
if (!identical(colnames(counts), rownames(catalog))) {
  fail("channel labels of counts.csv and catalog.csv differ (order-sensitive)")
}
if (!setequal(colnames(counts), stl_channels)) {
  fail("channel labels do not cover the STL SBS96 classic set")
}
if (any(counts < 0)) fail("counts.csv: negative counts not allowed")
if (any(catalog < 0)) fail("catalog.csv: negative entries not allowed")
if (any(colSums(catalog) <= 0)) fail("catalog.csv: signature column with zero mass")
catalog <- sweep(catalog, 2, colSums(catalog), "/")   # column-wise normalize (defense)

# repo-anchor order → STL classic order (catalog and counts reordered in sync; the fit matrix product aligns by position)
counts_stl <- t(counts)[stl_channels, , drop = FALSE]       # channels(rows) × samples(cols)
cat_stl    <- catalog[stl_channels, , drop = FALSE]         # channels(rows) × signatures(cols)
# assert the channel order with the package's own checker (anything but "subs" means organ/type detection is all wrong)
if (!identical(signature.tools.lib:::getTypeOfMutationsFromChannels(counts_stl), "subs")) {
  fail("channel reorder to STL classic order failed getTypeOfMutationsFromChannels check")
}

# 0-mutation samples: STL would hand back an all-0 fit → keep them out of the fit, write NaN rows per the protocol (do not interrupt the batch)
totals <- colSums(counts_stl)
fit_cols <- names(totals[totals > 0])
skip_cols <- names(totals[totals == 0])
if (length(fit_cols) == 0) fail("all samples have zero mutations — nothing to fit")

# ---- Tier-1 fit: FitMS package defaults + bootstrap (with bootstrap off the intervals go silently missing) ----
res <- signature.tools.lib::FitMS(
  catalogues        = counts_stl[, fit_cols, drop = FALSE],
  commonSignatures  = cat_stl,                    # W1 ruling: feed the whole catalog via commonSignatures
  rareSignatures    = cat_stl[, integer(0)],      # left empty ⇒ no rare-signature search
  maxRareSigsPerSample = 0,                       # 0 = common-only fitting (package-doc semantics)
  method            = "KLD",                      # package default
  exposureFilterType = "fixedThreshold",           # package default (threshold_percent=5)
  useBootstrap      = TRUE,
  nboot             = nboot,
  nparallel         = 1,
  randomSeed        = seed,
  verbose           = FALSE)

if (is.null(res)) {   # FitMS's error path is a silent return(NULL) (per the source), so intercept it explicitly
  fail("FitMS returned NULL (see FitMS '[error]' message on stdout) — catalogue/channel shape rejected")
}

# ---- extraction: exposures (samples × signatures + the "unassigned" column, which is dropped) ----
exps <- res$exposures
if (!"unassigned" %in% colnames(exps)) fail("FitMS result lacks expected 'unassigned' column")
exps <- exps[, setdiff(colnames(exps), "unassigned"), drop = FALSE]
samples    <- rownames(exps)
sig_names  <- colnames(catalog)                   # full-catalog columns (incl. absent signatures the package dropped)
boot_by_sample <- res$bootstrap_exposures_samples # per sample: signatures × nboot
if (is.null(boot_by_sample)) fail("bootstrap_exposures_samples missing — was useBootstrap=TRUE set?")

rows <- list(); k <- 1
for (s in samples) {
  bm <- boot_by_sample[[s]]
  if (is.null(bm)) fail(paste0("no bootstrap matrix for sample '", s, "'"))
  for (sg in sig_names) {
    est <- if (sg %in% colnames(exps)) exps[s, sg] else 0   # absent signature ⇒ 0
    if (!is.finite(est)) {  # guardline: a non-finite estimate lands honestly as a NaN row
      rows[[k]] <- data.frame(sample_id = s, signature = sg, estimate = NaN,
                              lo95 = NaN, hi95 = NaN, estimand = "absolute", zeroed = 1); k <- k + 1
      writeLines(paste0(format(Sys.time()), " sample '", s, "' signature '", sg,
                        "': non-finite exposure, NaN row written"), err_log)
      next
    }
    zeroed <- (est == 0)
    if (zeroed) {           # filtered by the package (fixedThreshold 5%) ⇒ interval collapses to [0,0]
      lo <- 0; hi <- 0
    } else {
      if (!sg %in% rownames(bm)) fail(paste0("bootstrap matrix for '", s, "' lacks signature '", sg, "'"))
      b  <- as.numeric(bm[sg, ])
      qq <- stats::quantile(b, probs = c(0.025, 0.975), names = FALSE, na.rm = TRUE)
      lo <- qq[1]; hi <- qq[2]
    }
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = est, lo95 = lo, hi95 = hi,
                            estimand = "absolute", zeroed = as.integer(zeroed)); k <- k + 1
  }
}
for (s in skip_cols) {   # rejected samples (0 mutations): NaN rows
  for (sg in sig_names) {
    rows[[k]] <- data.frame(sample_id = s, signature = sg, estimate = NaN, lo95 = NaN, hi95 = NaN,
                            estimand = "absolute", zeroed = 0); k <- k + 1
  }
  cat(paste0(format(Sys.time()), " sample '", s, "' rejected: zero total mutations (NaN rows written)\n"),
      file = err_log, append = TRUE, sep = "")
}
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "intervals.csv"), row.names = FALSE)

# ---- manifest: tag + commit SHA (baked into /usr/local/share/g0 at the build stage) ----
info <- list(version_tag = "v2.5.2", commit = "unknown")
bi <- "/usr/local/share/g0/build_info.json"
if (file.exists(bi)) {
  j <- jsonlite::fromJSON(bi)
  info$version_tag <- j$tag; info$commit <- j$commit
}
writeLines(jsonlite::toJSON(list(
  tool = "signature.tools.lib", version_tag = info$version_tag,
  version_r = as.character(utils::packageVersion("signature.tools.lib")),
  commit = info$commit, seed = seed, nboot = nboot, method = "KLD",
  nparallel = 1, useBootstrap = TRUE, maxRareSigsPerSample = 0,
  filter = "fixedThreshold 5% (package default); filtered -> [0,0] interval, zeroed=1",
  catalog_mode = "commonSignatures=<catalog.csv> (W1: no organ T1); rare search disabled",
  interval_source = "2.5/97.5 percentiles of bootstrap_exposures_samples (signatures x nboot)",
  channel_order = "input repo-anchor SBS96.txt order -> reordered to STL classic (COSMIC) order in, exposures have no channel dim"
), auto_unbox = TRUE), file.path(outdir, "manifest.json"))

}, error = function(e) fail(paste0("run_stl failed: ", conditionMessage(e))))
quit(save = "no", status = 0)
