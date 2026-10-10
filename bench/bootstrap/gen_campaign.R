#!/usr/bin/env Rscript
# GO-05 campaign generator — the SOLE data source for the bootstrap-vs-sigminer
# campaign (U-M7-04 GO-05; pre-registration:
# docs/devlog/2026-10-10-m7-bootstrap-campaign.md). Deterministic under the
# frozen SEED; TDD unit test_generator_double_run_is_byte_identical pins that.
#
# Usage (shape args are the TDD small-shape knobs; the campaign passes the
# frozen K=1000 S=1000 n_sig=50):
#   Rscript --vanilla gen_campaign.R -- --out DIR --k 1000 --s 1000 \
#       --sig 50 --seed 20260928
# Emits DIR/campaign.rds (counts + shared signatures + truth), DIR/seal.json
# (sha256 of the shipped bytes — arms consume these bytes, identity is sealed),
# DIR/Seeds.txt (provenance block).
suppressWarnings(RNGkind("Mersenne-Twister", normal.kind = "Inversion",
  sample.kind = "Rejection"))

args <- commandArgs(TRUE)
flag <- function(name, required = TRUE) {
  i <- match(name, args)
  if (is.na(i)) {
    if (required) stop("missing required --", name, " argument")
    return(NA)
  }
  args[[i + 1L]]
}
out <- flag("--out"); k <- as.integer(flag("--k")); s <- as.integer(flag("--s"))
n_sig <- as.integer(flag("--sig")); seed <- as.integer(flag("--seed"))
stopifnot(length(seed) == 1L && !is.na(seed) && seed >= 0L)
# The frozen master seed (G0 domain) — this line is a TDD-scan target.
if (!is.na(flag("--seed", required = FALSE)) && seed != 20260928L &&
    as.integer(flag("--k")) > 100L) {
  stop("full-shape generation must run under the frozen SEED=20260928")
}
SCALE <- 280                                    # Poisson mean scale: totals ~10^3
N_ACTIVE <- 6                                   # true active signatures per sample

set.seed(seed)
labels <- sprintf("M%04d", seq_len(k))
samples <- sprintf("S%04d", seq_len(s))
sig_names <- sprintf("V%02d", seq_len(n_sig))

# Signatures: dense positive gamma intensities, each column normalized to sum 1
# (well-posed NNLS, honest per-replicate cost; the campaign is a speed claim,
# the generator makes no fidelity claim — the arms' own RNGs do the inference).
sigs <- matrix(rgamma(k * n_sig, shape = 1.2, rate = 1), nrow = k, ncol = n_sig)
sigs <- apply(sigs, 2L, function(column) column / sum(column))
dimnames(sigs) <- list(labels, sig_names)

counts <- matrix(0, nrow = k, ncol = s)
truth_active <- vector("list", s)
truth_lambda <- vector("list", s)
for (j in seq_len(s)) {
  active <- sample.int(n_sig, N_ACTIVE)         # distinct true signatures
  lambda <- runif(N_ACTIVE, 0.2, 1.0)
  mu <- as.numeric(sigs[, active, drop = FALSE] %*% lambda) * SCALE
  counts[, j] <- rpois(k, mu)
  truth_active[[j]] <- sig_names[active]
  truth_lambda[[j]] <- lambda
}
dimnames(counts) <- list(labels, samples)

dir.create(out, recursive = TRUE, showWarnings = FALSE)
campaign_rds <- file.path(out, "campaign.rds")
# NO wall-clock fields inside the saved object: the bytes must be seed-pure
# (double-run byte identity is a TDD unit); provenance lives in seal/Seeds.
saveRDS(list(counts = counts, signatures = sigs, labels = labels,
  samples = samples, sig_names = sig_names, n_active = N_ACTIVE,
  scale = SCALE, seed = seed), file = campaign_rds, compress = TRUE,
  version = 2)

sha256 <- function(path) {
  hit <- Sys.which("shasum")
  if (!is.na(hit)) {
    # this host's shasum prints "<hex>  <path>" with no -r mode switch
    line <- system2(unname(hit), c("-a", "256", path),
      stdout = TRUE, stderr = FALSE)
    if (is.numeric(line)) stop("shasum failed with status ", line)
    return(sub("[[:space:]].*$", "", trimws(line[[1]])))
  }
  hit <- Sys.which("openssl")
  if (!is.na(hit)) {
    line <- system2(unname(hit), c("dgst", "-sha256", "-r", path),
      stdout = TRUE, stderr = FALSE)
    if (is.numeric(line)) stop("openssl dgst failed with status ", line)
    found <- regmatches(line[[1]], "([0-9a-f]{64})", perl = TRUE)
    if (is.na(found[[1]])) stop("openssl output carried no sha256 digest")
    return(found[[1]])
  }
  stop("no sha256 tool on host (shasum/openssl) — declared dependency missing")
}
digest <- sha256(campaign_rds)
hostname <- try(system2("hostname", stdout = TRUE, stderr = FALSE), silent = TRUE)
if (inherits(hostname, "try-error") || is.numeric(hostname) ||
    !length(hostname)) hostname <- "unknown-host"
writeLines(sprintf(paste0("{", '"sha256": "%s", "campaign_rds": "campaign.rds",',
  '"host": "%s", "hw_profile": "%s", "generator": "gen_campaign.R",',
  '"argv": "%s"}'), digest, trimws(hostname[[1]]),
  Sys.getenv("M7_HW_PROFILE", "unset-at-generation-time"),
  paste(commandArgs(TRUE), collapse = " ")), file.path(out, "seal.json"))
writeLines(c(paste0("# campaign data provenance (gen_campaign.R)"),
  paste0("- seed: ", seed),
  paste0("- shape: k=", k, " s=", s, " n_sig=", n_sig,
    " n_active=", N_ACTIVE, " scale=", SCALE),
  paste0("- rng: Mersenne-Twister / Inversion / Rejection (pinned above)"),
  paste0("- R: ", paste0(R.version$major, ".", R.version$minor, ".",
    if (is.null(R.version$nickname)) "" else R.version$nickname)),
  paste0("- sha256: ", digest)), file.path(out, "Seeds.txt"))
cat("[gen] campaign.rds sha256:", digest, "\n")
