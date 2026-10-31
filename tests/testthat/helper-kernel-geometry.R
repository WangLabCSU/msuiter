# Shared attestation geometry for the PERF-P10 law files
# (test-kernel-trace-shape.R / test-kernel-bit-identity.R /
# test-kernel-batch-bridge.R).
#
# Test-side only: nothing here ships in R/. This helper carries the
# attested true-geometry bytes (fa2 in/counts.csv) and the VERBATIM
# sigminer bootstrapped-input replication (best_practice.R:305-315 via the
# banked 13-census-armC.R census: shared set.seed(152L) freeze, per-boot
# set.seed(123 + b - 1), channels-side catalogue resample). Every numeric
# is generated from a seed on the record; no COSMIC bytes anywhere.
#
# The local attestation evidence lives in the lane sandbox (/tmp). Its
# ABSENCE (a CI context) makes the attestation units skip with a spoken
# reason; its PRESENCE makes any digest drift a gate failure (a stop),
# never a silent re-read.

.kbg_paths <- function() {
  list(
    before = "/tmp/perf10lane/bin/before/msuiter-kernel",
    digest = "/tmp/perf10lane/logs/00-before-binary-digest.txt",
    counts = "/tmp/perf9lane/p9fa2/in/counts.csv",
    banked = "/tmp/parity-research/forensics-logs/05-fa2-counts-digest.txt"
  )
}

# The evidence set, or NULL when the set is incomplete.
.kbg_ev <- function() {
  p <- .kbg_paths()
  if (!all(file.exists(unlist(p, use.names = FALSE)))) return(NULL)
  p
}

.kbg_skip <- function() {
  skip("local attestation evidence incomplete (lane-sandbox /tmp face)")
}

# SHA-256 over exact file bytes through the canonical governed digest
# kernel (code-produced, never hand-typed).
.kbg_sha <- function(path) {
  info <- file.info(path)
  if (is.na(info$size)) {
    stop("cannot hash a missing file: ", path, call. = FALSE)
  }
  msuiter:::.ms_cc_sha256_raw(readBin(path, what = "raw", n = info$size))
}

# Read the "<sha256>  <path>" banked digest files (single hash line).
.kbg_banked_digest <- function(path) {
  lines <- trimws(readLines(path, warn = FALSE))
  lines <- lines[nzchar(lines)]
  if (!length(lines)) {
    stop("banked digest file carries no line: ", path, call. = FALSE)
  }
  sub("[[:space:]].*$", "", lines[[1L]])
}

# One field of a meta.csv receipt by its key (the "key,value" line form;
# values with commas -- engine_crate -- are kept whole).
.kbg_meta_field <- function(path, key) {
  lines <- readLines(path, warn = FALSE)
  hit <- character()
  for (ln in lines[nzchar(lines)]) {
    sp <- .kp_split1(ln)
    if (!is.null(sp) && identical(sp$left, key)) hit <- c(hit, sp$right)
  }
  if (!identical(length(hit), 1L)) {
    stop("meta field '", key, "' on ", path,
         ": expected exactly one row, got ", length(hit), call. = FALSE)
  }
  hit
}

## ---- the attested fa2 bytes and the verbatim bootstrap --------------------

.kbg_x_env <- new.env(parent = emptyenv())

# The raw fa2 counts as the kernel V face (channels x samples, 96 x 100),
# read through the banked census idiom after pinning the byte digest.
.kbg_X <- function(ev) {
  if (!is.null(.kbg_x_env$x)) return(.kbg_x_env$x)
  want <- .kbg_banked_digest(ev$banked)
  got <- .kbg_sha(ev$counts)
  if (!identical(want, got)) {
    stop("attested fa2 bytes drifted: banked ", want, ", live ", got,
         call. = FALSE)
  }
  df <- utils::read.table(ev$counts, sep = ",", header = TRUE,
                          check.names = FALSE, quote = "", comment.char = "")
  ids <- df[[1L]]
  m <- matrix(as.numeric(unlist(df[-1L], use.names = FALSE)),
              nrow = length(ids), ncol = ncol(df) - 1L, byrow = TRUE)
  rownames(m) <- ids
  x <- t(m)                                     # channels x samples
  if (!identical(dim(x), c(96L, 100L)) || any(x < 0) ||
      !all(is.finite(as.vector(x)))) {
    stop("fa2 face lost the attested geometry: dim ",
         paste(dim(x), collapse = "x"), call. = FALSE)
  }
  .kbg_x_env$x <- x
  x
}

# verbatim sigminer R/simulation.R:90-115 (as banked in the PF census):
# one multinomial redraw of each sample's catalogue at its own total.
.kbg_simulate_catalogue <- function(catalog, total) {
  prob <- catalog / sum(catalog)
  out <- rmultinom(1L, total, prob)
  out <- as.integer(table(factor(out, levels = seq_along(prob))))
  names(out) <- names(prob)
  out
}

.kbg_simulate_catalogue_matrix <- function(x) {
  y <- apply(x, 1L, function(catalog) {
    .kbg_simulate_catalogue(catalog, as.integer(sum(catalog)))
  })
  t(y)
}

.kbg_boot_env <- new.env(parent = emptyenv())
.kbg_boot_env$built <- 0L

# The bootstrapped true NMF input for boot b, replaying the banked RNG
# history verbatim (the shared set.seed(152L) freeze before the first
# boot, the per-boot set.seed(123 + b - 1) before its redraw). Boots are
# built in order so every boot sees the exact recorded seed sequence.
.kbg_boot <- function(ev, b) {
  b <- suppressWarnings(as.integer(b))
  if (is.na(b) || b < 1L || b > 4L) {
    stop("boot index must be an integer in 1:4, got: ", b, domain = NA)
  }
  cached <- .kbg_boot_env[[as.character(b)]]
  if (!is.null(cached)) return(cached)
  built <- .kbg_boot_env$built
  if (built == 0L) set.seed(152L)
  X <- .kbg_X(ev)
  for (bb in (built + 1L):b) {
    set.seed(123L + bb - 1L)
    vb <- t(.kbg_simulate_catalogue_matrix(t(X)))  # sample-side redraw
    if (!identical(dim(vb), c(96L, 100L)) || any(vb < 0)) {
      stop("bootstrapped face lost the attested geometry: boot ", bb,
           " is ", paste(dim(vb), collapse = "x"), call. = FALSE)
    }
    .kbg_boot_env[[as.character(bb)]] <- vb
  }
  .kbg_boot_env$built <- b
  .kbg_boot_env[[as.character(b)]]
}

# Zero-fraction of the bootstrapped face (the PF census measured ~0.987
# zero density; the attestation re-measures it rather than quoting it).
.kbg_zero_frac <- function(v) mean(v == 0)

# Stage one single-face input directory (headerless %.17e grid, the
# certified V.csv form) for the nndsvd init face.
.kbg_stage_single <- function(root, V) {
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  writeLines(.kpp_grid(V), con = file.path(root, "V.csv"))
  root
}

# The stable-entry single-face argv for one attested fit.
.kbg_single_argv <- function(indir, outdir, m, n, k, iters, seed) {
  c("fit-kl", "--in", indir, "--out", outdir,
    "--m", as.character(m), "--n", as.character(n),
    "--k", as.character(k), "--iters", as.character(iters),
    "--init", "nndsvd", "--seed", as.character(seed))
}
