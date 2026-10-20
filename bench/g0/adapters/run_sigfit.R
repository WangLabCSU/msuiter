#!/usr/bin/env Rscript
# G0 Tier-1 adapter: sigfit v2.2.0 (kgori/sigfit, Gori & Baez-Ortega, bioRxiv 372896)
#
# The contract: adapter_protocol.md (the 2026-09-28 revised edition). counts.csv + catalog.csv + params.json in,
# intervals.csv (the two estimands absolute + raw) + manifest.json + errors.log out.
#
# ── The W1/D2 API reconciliation conclusions (verified by direct measurement inside the g0-sigfit:2.2.0 container; see the protocol §5)──
# 1) The correct entry is fit_signatures() (fit_signatures_counts does not exist in 2.2.0);
#    counts rows = samples; signatures must be passed as t(catalog) (rows = signatures).
# 2) fit_signatures' seed/chains/iter/warmup are pass-through to rstan::sampling via ...;
#    when not provided the package defaults apply: chains=4 / iter=2000 / warmup=1000.
# 3) retrieve_pars(mcmc, par="exposures", hpd_prob=0.95) —— hpd_prob (not
#    sig_level/CI/hpd/threshold.lower); it returns mean/lower_95/upper_95 (samples × signatures).
# 4) 2.2.0 **has no built-in zeroing parameter** (no threshold.lower): the zeroing rule is the harness's
#    post-processing; this runner only emits the zeroed flag (in the absolute interval lower<0.01 ⇒ flag 1).
# 5) **The key trap**: under the multinomial model the exposures are fractions (per-sample sum ≈ 1),
#    the absolute counts = the fraction × the sample's total mutation count. Before landing to disk this runner runs
#    the two assertions: fraction-sum=1 and post-restoration total conservation (the coverage judgment is governed by the absolute estimand).
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(sigfit))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  i <- match(flag, args)
  if (is.na(i)) stop(paste("missing arg:", flag))
  return(args[i + 1])
}

fail <- function(msg) {
  # Beware: writeLines has no append parameter — appending must use cat (the old run_stl.R's writing style)
  cat(paste0(format(Sys.time()), " FATAL [run_sigfit]: ", msg, "\n"),
      file = err_log, append = TRUE, sep = "")
  quit(save = "no", status = 1)
}

counts_path  <- get_arg("--counts")
catalog_path <- get_arg("--catalog")
params_path  <- get_arg("--params")
outdir       <- get_arg("--outdir")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# errors.log lands first (the protocol §2.1: the run_grid cache guard requires an errors.log under out/;
# first clear the half-truncated residual output from a previous run, and the failure path never leaves an intervals.csv)
err_log <- file.path(outdir, "errors.log")
unlink(file.path(outdir, "intervals.csv"))
unlink(file.path(outdir, "manifest.json"))
writeLines(character(0), err_log)

tryCatch({

params <- jsonlite::fromJSON(params_path)
seed   <- as.integer(params$seed)
if (is.na(seed)) fail("params.seed missing or not an integer")

# ---- the read-in + the explicit numeric defense (non-numeric columns are rejected) ----
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
counts  <- read_matrix_csv(counts_path)    # rows = sample_id, columns = the 96 channels
catalog <- read_matrix_csv(catalog_path)   # rows = channel (96), columns = signatures

stopifnot(ncol(counts) == 96, nrow(catalog) == 96)
if (!identical(colnames(counts), rownames(catalog))) {
  fail("channel labels of counts.csv and catalog.csv differ (order-sensitive)")
}
if (any(counts < 0)) fail("counts.csv: negative counts not allowed")
if (any(catalog < 0)) fail("catalog.csv: negative entries not allowed")
if (any(colSums(catalog) <= 0)) fail("catalog.csv: signature column with zero mass")
catalog <- sweep(catalog, 2, colSums(catalog), "/")   # normalize each column (defense)

# 0-mutation samples: the tool would reject them → keep them out of the fit, write NaN rows per the protocol (the batch is not interrupted)
totals <- rowSums(counts)
fit_rows <- names(totals[totals > 0])
skip_rows <- names(totals[totals == 0])
if (length(fit_rows) == 0) fail("all samples have zero mutations — nothing to fit")
counts_fit <- counts[fit_rows, , drop = FALSE]

# ---- Tier-1 fit: the package default parameters; the optional params chains/iter/warmup short chains (for the smoke use) ----
extra <- list()
if (!is.null(params$chains)) extra$chains <- as.integer(params$chains)
if (!is.null(params$iter))   extra$iter   <- as.integer(params$iter)
if (!is.null(params$warmup)) extra$warmup <- as.integer(params$warmup)
fit <- do.call(sigfit::fit_signatures,
               c(list(counts = counts_fit, signatures = t(catalog),
                      model = "multinomial", seed = seed), extra))

# ---- the posterior extraction: hpd_prob=0.95 → mean/lower_95/upper_95 (samples × signatures, fractions) ----
pars <- sigfit::retrieve_pars(fit, par = "exposures", hpd_prob = 0.95)
stopifnot(all(c("mean", "lower_95", "upper_95") %in% names(pars)))

# Assertion 1 (the fraction scope): the per-sample exposures fraction sum ≈ 1
if (max(abs(rowSums(pars$mean) - 1)) > 1e-6) {
  fail("posterior exposure fractions do not sum to 1 per sample (multinomial assumption broken)")
}
# Assertion 2 (the restoration conservation): fraction × the sample's total mutation count = the absolute counts, the per-sample sum restoring back to the total
totals_fit <- totals[fit_rows]
mu_abs <- sweep(pars$mean,     1, totals_fit, "*")
lo_abs <- sweep(pars$lower_95, 1, totals_fit, "*")
hi_abs <- sweep(pars$upper_95, 1, totals_fit, "*")
if (max(abs(rowSums(mu_abs) - totals_fit)) > 1e-6 * max(totals_fit)) {
  fail("absolute-count restoration failed: row sums of fraction*total != sample totals")
}

samples   <- rownames(mu_abs)
sig_names <- colnames(mu_abs)

rows <- list(); k <- 1
for (s in samples) {
  for (j in seq_along(sig_names)) {
    sg <- sig_names[j]
    # There is no built-in zeroing parameter (2.2.0): the zeroing is done by the harness as post-processing per the zeroed flag;
    # the runner only honestly stamps the flag (per the protocol the absolute interval lower<0.01 ⇒ zeroed=1)
    zeroed <- if (lo_abs[s, j] < 0.01) 1 else 0
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = mu_abs[s, j], lo95 = lo_abs[s, j], hi95 = hi_abs[s, j],
                            estimand = "absolute", zeroed = zeroed); k <- k + 1
    # raw = the un-zeroed posterior interval; 2.2.0 has no built-in zeroing ⇒ the numbers equal those of absolute;
    # keep both rows to fix the schema and to distinguish from future versions with built-in zeroing (the protocol §2)
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = mu_abs[s, j], lo95 = lo_abs[s, j], hi95 = hi_abs[s, j],
                            estimand = "raw", zeroed = 0); k <- k + 1
  }
}
for (s in skip_rows) {   # the rejected samples: NaN rows (per the protocol §2 guardline scope)
  for (sg in colnames(catalog)) {
    rows[[k]] <- data.frame(sample_id = s, signature = sg, estimate = NaN, lo95 = NaN, hi95 = NaN,
                            estimand = "absolute", zeroed = 0); k <- k + 1
  }
    cat(paste0(format(Sys.time()), " sample '", s, "' rejected: zero total mutations (NaN rows written)\n"),
        file = err_log, append = TRUE, sep = "")
}
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "intervals.csv"), row.names = FALSE)

# ---- manifest: the version must be traceable (tag + commit SHA; a "2.2"-level version string is not enough) ----
pd  <- utils::packageDescription("sigfit")
tag <- if (!is.null(pd$GithubRef)) pd$GithubRef else "v2.2.0"
sha <- if (!is.null(pd$RemoteSha)) pd$RemoteSha else "unknown"
ch  <- if (!is.null(extra$chains)) extra$chains else 4L     # the rstan::sampling defaults
it  <- if (!is.null(extra$iter))   extra$iter   else 2000L
wu  <- if (!is.null(extra$warmup)) extra$warmup else 1000L
writeLines(jsonlite::toJSON(list(
  tool = "sigfit", version_tag = tag, version_r = as.character(utils::packageVersion("sigfit")),
  commit = sha, seed = seed, model = "multinomial", hpd_prob = 0.95,
  chains = ch, iter = it, warmup = wu,
  counts_restoration = "absolute = exposure_fraction * sample_total (multinomial)",
  zero_rule = "no built-in zeroing in 2.2.0; runner flags lower<0.01 -> zeroed=1, harness post-processes"
), auto_unbox = TRUE), file.path(outdir, "manifest.json"))

}, error = function(e) fail(paste0("run_sigfit failed: ", conditionMessage(e))))
quit(save = "no", status = 0)
