# Shared attestation geometry for the PERF-P10 law files
# (test-kernel-trace-shape.R / test-kernel-bit-identity.R /
# test-kernel-batch-bridge.R).
#
# Test-side only: nothing here ships in R/. This helper carries the
# committed attested-geometry bytes (fixtures/kernel-geometry/fa2/
# counts.csv, the generator being tools/attest-kernel-geometry.R) and the
# VERBATIM sigminer bootstrapped-input replication (best_practice.R:
# 305-315 via the banked 13-census-armC.R census: shared set.seed(152L)
# freeze, per-boot set.seed(123 + b - 1), channels-side catalogue
# resample). Every numeric is generated from a seed on the record; no
# COSMIC bytes anywhere.
#
# The bytes live IN THE REPOSITORY (audit #74 P1-6): the original set
# lived only in a /tmp lane sandbox, was lost, and the law units skipped
# vacuously. There is no skip path any more -- a missing or drifted
# evidence file is a gate FAILURE (a stop), never a silent green. The
# protocol-1 (F1) face is banked from the git-sealed era build named in
# PROVENANCE.tsv; the law is that the working tree reproduces those
# bytes, so the bank itself is what the numerics are measured against.

.kbg_iters <- 2000L        # the attested face's iteration scale

# The fixtures root: the testthat path inside a test run, else a walk up
# from the cwd (the tools/ capture face). NA when neither has it.
.kbg_root <- local({
  found <- NA_character_
  p <- try(testthat::test_path("fixtures", "kernel-geometry"), silent = TRUE)
  if (!inherits(p, "try-error") && nzchar(p) &&
      file.exists(file.path(p, "fa2", "counts.csv"))) {
    found <- normalizePath(p, mustWork = FALSE)
  }
  if (is.na(found)) {
    d <- try(normalizePath(getwd()), silent = TRUE)
    while (is.na(found) && !inherits(d, "try-error") && nzchar(d)) {
      cand <- file.path(d, "tests", "testthat", "fixtures", "kernel-geometry")
      if (file.exists(file.path(cand, "fa2", "counts.csv"))) found <- cand
      parent <- dirname(d)
      if (identical(parent, d)) break
      d <- parent
    }
  }
  found
})

# The task grid the bank must cover, exactly (the law files share it --
# one source of truth for which faces are attested).
.kbg_task_defs <- function() {
  tasks <- list()
  for (k in 2:5L) {
    tasks[[length(tasks) + 1L]] <- list(tag = paste0("fa2-k", k),
                                         kind = "fa2", boot = NA_integer_,
                                         k = as.integer(k), seed = 123L)
  }
  for (b in 1:4L) {
    for (k in 2:5L) {
      tasks[[length(tasks) + 1L]] <- list(tag = paste0("boot", b, "-k", k),
                                          kind = "boot", boot = as.integer(b),
                                          k = as.integer(k),
                                          seed = 123L + b - 1L)
    }
  }
  tasks
}

.kbg_required <- function() {
  req <- c(file.path("fa2", "counts.csv"), file.path("fa2",
                                                    "COUNTS.sha256"),
            "PROVENANCE.tsv", file.path("f1", "F1.sha256"))
  for (t in .kbg_task_defs()) {
    req <- c(req, file.path("f1", t$tag,
                            c("W.csv", "H.csv", "trace.csv", "meta.csv")))
  }
  req
}

# The evidence set, verified against its ledgers. Any absence or digest
# drift STOPS the unit with the spoken offender (no skip lane -- an
# unattested law is a broken law, not a passing one).
.kbg_ev <- function() {
  if (is.na(.kbg_root)) {
    stop(paste0("attestation fixtures unreachable: the kernel-geometry ",
                "root was found neither through testthat nor by walking up"),
         call. = FALSE)
  }
  root <- .kbg_root
  miss <- character()
  for (f in .kbg_required()) {
    if (!file.exists(file.path(root, f))) miss <- c(miss, f)
  }
  if (length(miss)) {
    stop("attestation evidence incomplete under ", root, ": missing ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  # The F1 ledger speaks for every banked byte (the dead-metric control
  # for the ledger itself lives in test-kernel-bit-identity.R).
  ledger <- readLines(file.path(root, "f1", "F1.sha256"), warn = FALSE)
  seen <- character()
  for (ln in trimws(ledger[nzchar(ledger)])) {
    want <- sub("[[:space:]].*$", "", ln)
    rel <- sub("^[^[:space:]]+[[:space:]]+", "", ln)
    live <- .kbg_sha(file.path(root, rel))
    if (!identical(live, want)) {
      stop("banked byte drift: ", rel, " ledger ", want, ", live ", live,
           call. = FALSE)
    }
    seen <- c(seen, rel)
  }
  banked <- character()
  for (t in .kbg_task_defs()) {
    banked <- c(banked, file.path("f1", t$tag,
                                  c("W.csv", "H.csv", "trace.csv", "meta.csv")))
  }
  if (!all(banked %in% seen)) {
    stop("F1 ledger does not speak for: ",
         paste(setdiff(banked, seen), collapse = ", "), call. = FALSE)
  }
  prov <- local({
    lines <- readLines(file.path(root, "PROVENANCE.tsv"), warn = FALSE)
    fields <- list()
    for (ln in lines[nzchar(lines) & !startsWith(ln, "#")]) {
      kv <- strsplit(ln, "\t", fixed = TRUE)[[1L]]
      if (length(kv) >= 2L) fields[[kv[[1L]]]] <- kv[[2L]]
    }
    fields
  })
  for (key in c("era_commit", "era_version")) {
    if (is.null(prov[[key]]) || !nzchar(prov[[key]])) {
      stop("PROVENANCE.tsv does not speak field ", key, call. = FALSE)
    }
  }
  list(root = root, counts = file.path(root, "fa2", "counts.csv"),
       banked = file.path(root, "fa2", "COUNTS.sha256"),
       f1root = file.path(root, "f1"), prov = prov)
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
  # unlist(df[-1L]) is column-major blocks of length(ids): the fill must
  # ride the same order or the grid is shuffled between rows.
  m <- matrix(as.numeric(unlist(df[-1L], use.names = FALSE)),
              nrow = length(ids), ncol = ncol(df) - 1L)
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

# verbatim sigminer R/simulation.R:86-115 (as banked in the PF census):
# one multinomial redraw of each sample's catalogue at its own total --
# the sample()-then-histogram face is the original: the factor levels are
# the CHANNEL indices, so the histogram keeps the full length and the
# total exactly. (A count-vector fed through this histogram would
# histogram the counts instead -- the total law control catches it.)
.kbg_simulate_catalogue <- function(catalog, total) {
  prob <- catalog / sum(catalog)
  out <- sample(seq_along(prob), size = total, replace = TRUE, prob = prob)
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

# The live V face for one task definition (fa2 raw or bootstrapped).
.kbg_task_v <- function(ev, t) {
  if (identical(t$kind, "fa2")) .kbg_X(ev) else .kbg_boot(ev, t$boot)
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
