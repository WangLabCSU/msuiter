#!/usr/bin/env Rscript
# =============================================================================
# bench/m1s/nmf · M1s acceptance-gate NMF bench(docs/ARCHITECTURE.md §8 budget row:
#   NMF KL(96×1000, k=10, 100 iter)vs R NMF ≥100×. CI only ships sanity bound)
#
# Caliber: the same V/W0/H0(CSV byte-for-byte exchange, integer counts + k/1024 binary-grid init,
#   short exact decimal strings——U-M1s-14 proves both sides parse bit-identically); same iteration count T=100.
#   Ours = driver(path depends on msuiter-engine) calls the untouched kernel fit_kl_with_init;
#   R baseline = NMF package brunet(scheme A:seed=nmfModel(W0,H0) external init,
#   stopconv=1e6 disables early stopping,maxIter=T exact control——U-M1s-14 mechanism proved).
#   Two-sided protocol: warm up 1 run, + timed 3 runs take the median;R side elapsed wall clock (C kernel single-threaded),
#   Ours driver internal Instant timing (kernel single-threaded,engine crate zero-dep, no rayon).
#
# Criterion:median(R) / median(ours) ≥ 100.
# Correctness anchor (informational): both sides T=100 final objective values (KL) relative diff < 1e-6(U-M1s-14 proved
#   96×20 numeric-protocol equivalence ‖ΔW‖≈1e-15; here it is only a run-validity sanity).
#
# One-shot rerun:Rscript bench/m1s/nmf/run_bench.R   (produces this directory result.md)
# The timing environment is written verbatim into result.md(this machine Apple Silicon; power state not controllable).
# =============================================================================

suppressMessages(library(NMF))

options(stringsAsFactors = FALSE, digits = 17, scipen = 12)

HERE <- normalizePath(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = 1))))
DIR_IN <- file.path(HERE, "cache", "input")
DIR_OUT <- file.path(HERE, "cache", "output")
dir.create(DIR_IN, recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

M <- 96L; N <- 1000L; K <- 10L; TITER <- 100L
SEED_DATA <- 20260928L   # V(separable synthetic counts)
SEED_INIT <- 20260929L   # W0/H0(on thek/1024 grid, strictly positive)
`%||%` <- function(a, b) if (is.null(a)) b else a
sig <- function(x, d = 6) format(x, digits = d, trim = TRUE, scientific = TRUE)
median3 <- function(x) as.numeric(median(x))

# ---- Input generation:96×1000 integer counts;10 separable signature blocks + near-pure sample groups ---------------
gen_inputs <- function() {
  set.seed(SEED_DATA)
  Wt <- matrix(0, M, K)
  for (s in 1:K) {
    lo <- (s - 1L) * 10L + 1L
    hi <- min(s * 10L, M)               # s=10 has only 6 anchor channels (91..96)
    col <- rep(0, M)
    col[lo:hi] <- 0.5 + runif(hi - lo + 1L)
    Wt[, s] <- col / sum(col)
  }
  Ht <- matrix(0, K, N)
  for (j in 1:N) {
    dom <- ((j - 1L) %/% 100L) + 1L     # each signature: 100 near-pure samples
    for (s in 1:K) {
      Ht[s, j] <- if (s == dom) 500 + 1000 * runif(1) else 50 * runif(1)
    }
  }
  V <- round(Wt %*% Ht)                 # integer counts; the near-pure sample groups ⇒ minor-signature contributions can round to 0(legitimate KL input)
  stopifnot(all(V >= 0), all(rowSums(V) > 0), all(colSums(V) > 0))

  set.seed(SEED_INIT)
  scale <- sqrt(mean(V) / K)
  W0 <- matrix(1 + floor(runif(M * K) * 1023), M, K) / 1024 * scale
  H0 <- matrix(1 + floor(runif(K * N) * 1023), K, N) / 1024 * scale
  W0 <- round(W0 * 1024) / 1024         # pinned on the k/1024 grid (short exact decimals)
  H0 <- round(H0 * 1024) / 1024
  stopifnot(all(W0 > 0), all(H0 > 0))

  fmt <- function(x) format(x, digits = 17, trim = TRUE, scientific = FALSE)
  write_csv <- function(mat, path) {
    writeLines(apply(mat, 1L, function(row) paste(fmt(row), collapse = ",")),
               path, useBytes = TRUE)
  }
  write_csv(V,  file.path(DIR_IN, "V.csv"))
  write_csv(W0, file.path(DIR_IN, "W0.csv"))
  write_csv(H0, file.path(DIR_IN, "H0.csv"))
  list(V = V, W0 = W0, H0 = H0, scale = scale)
}

# ---- Ours:cargo build driver → 3 timed runs (driver internally already did 1 warm-up) ----------
run_ours <- function() {
  bin <- file.path(HERE, "driver", "target", "release", "nmf-bench-driver")
  # Always run cargo cargo(incremental, idempotent): prevents running a stale binary after source changes.
  system2("cargo", c("build", "--release", "--quiet", "--manifest-path",
    file.path(HERE, "driver", "Cargo.toml")))
  out <- system2(bin, c("--in", shQuote(DIR_IN), "--out", shQuote(DIR_OUT),
    "--iters", as.character(TITER)), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status") %||% 0L
  if (status != 0L) stop("driver failed:\n", paste(out, collapse = "\n"))
  kv <- setNames(sub("^[^,]+,", "", out), sub(",[^,]+$", "", out))
  list(runs = as.numeric(kv[c("run0", "run1", "run2")]),       median_ms = as.numeric(kv[["median_ms"]]),
       meta = read.csv(file.path(DIR_OUT, "meta.csv"), header = FALSE,
                       colClasses = "character"))
}

# ---- R baseline:NMF brunet(scheme A external init, warm up 1 + timed 3 and take the median) --------
run_r_baseline <- function(d) {
  mod0 <- nmfModel(rank = K, W = d$W0, H = d$H0)
  one_timed <- function() {
    t0 <- proc.time()
    r <- suppressWarnings(nmf(d$V, K, method = "brunet", seed = mod0,
      maxIter = TITER, stopconv = 1e6, .options = list(verbose = 0)))
    list(elapsed = (proc.time() - t0)[["elapsed"]],
         niter = NMF::niter(r), resid = tail(NMF::residuals(r), 1))
  }
  invisible(one_timed())                # warm up 1 run (page cache / bytecode)
  runs <- replicate(3L, one_timed(), simplify = FALSE)
  elapsed <- vapply(runs, `[[`, numeric(1), "elapsed")
  list(runs = elapsed, median_s = median3(elapsed),
       niter = runs[[1]]$niter, resid = runs[[1]]$resid)
}

# =============================================================================
# Main flow
# =============================================================================
say <- function(...) cat(..., "\n", sep = "")
env_lines <- function() {
  si <- sessionInfo()
  c(
    paste0("date: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("R: ", R.version$version.string, " (", R.version$platform, ")"),
    paste0("NMF: ", as.character(packageVersion("NMF"))),
    paste0("BLAS: ", si$BLAS, " | LAPACK: ", si$LAPACK),
    paste0("rustc/cargo: ",
           paste(tryCatch(system2("rustc", "--version", stdout = TRUE),
                          error = function(e) "n/a"), collapse = " ")),
    paste0("host: ", R.version$platform, "(Apple Silicon; power state not controllable, figures are for this pinned hardware)")
  )
}

say("== M1s NMF bench: KL 96×1000, k=10, T=100 ==")
for (l in env_lines()) say("  ", l)

say("Input generation (set.seed fully recorded): data=", SEED_DATA, " init=", SEED_INIT)
d <- gen_inputs()
say(sprintf("  V: %d×%d integer counts, min=%g max=%g sum=%g | grid init scale=%.6g",
  M, N, min(d$V), max(d$V), sum(d$V), d$scale))

say("Ours (engine fit_kl_with_init,driver pure-kernel timing)...")
ours <- run_ours()
for (i in seq_along(ours$runs)) say(sprintf("  run%d: %.3f ms", i - 1L, ours$runs[i]))
say(sprintf("  median: %.3f ms", ours$median_ms))

say("R baseline (NMF 0.28 brunet, scheme A)...")
rb <- run_r_baseline(d)
for (i in seq_along(rb$runs)) say(sprintf("  run%d: %.3f s", i, rb$runs[i]))
say(sprintf("  median: %.3f s | niter=%d", rb$median_s, rb$niter))

speedup <- rb$median_s * 1e3 / ours$median_ms
obj_ours <- as.numeric(ours$meta[ours$meta[, 1] == "obj_final", 2])
rel_obj <- abs(obj_ours - as.numeric(rb$resid)) / abs(as.numeric(rb$resid))
verdict <- speedup >= 100

# Informational: per-iteration cost decomposition (fit_kl_with_init each iteration includes one objective-trajectory kl_objective
# = the 3 rd: WH matmul + 96k call ln;R brunet baseline does not compute the objective per iteration).T=1 vs T=100
# median diff → per-iteration slope; the slope includes trajectory overhead, so the pure update cost cannot be isolated from it alone.
bin_drv <- file.path(HERE, "driver", "target", "release", "nmf-bench-driver")
decomp_out <- system2(bin_drv, c("--in", shQuote(DIR_IN), "--out",
  shQuote(DIR_OUT), "--iters", "1"), stdout = TRUE, stderr = TRUE)
t1_ms <- as.numeric(sub("^[^,]+,", "", decomp_out[grepl("^median_ms,", decomp_out)]))
per_iter_ms <- (ours$median_ms - t1_ms) / (TITER - 1L)
say(sprintf("Criterion:speedup = %s / %.3f ms = %.1f×(≥100×? %s)",
  sig(rb$median_s, 4), ours$median_ms, speedup, ifelse(verdict, "PASS", "FAIL")))
say(sprintf("Correctness anchor (informational): KL final values ours=%.10e R=%.10e relative diff=%.3e(<1e-6)",
  obj_ours, as.numeric(rb$resid), rel_obj))

# ---- result.md -------------------------------------------------------------
lines <- c(
  "# B1 · NMF bench(M1s acceptance gate,ARCHITECTURE §8:96×1000, k=10, 100 iter vs R NMF ≥100×)", "",
  "Rerun:`Rscript bench/m1s/nmf/run_bench.R`. Same V/W0/H0(CSV byte-for-byte exchange), same T=100;",
  "Two-sided protocol: warm up 1 run, + timed 3 runs take the median. Ours = driver pure-kernel (`fit_kl_with_init`, single-threaded);",
  "R = NMF 0.28 brunet(external init W0/H0,stopconv=1e6,maxIter=100 exact control).", "",
  "## Environment", "",
  sapply(env_lines(), function(l) paste0("- ", l)), "",
  "## Figures", "",
  paste0("- Input: V 96×1000 integer counts (separable synthetic,seed=", SEED_DATA, ");init W0/H0 k/1024 grid (seed=", SEED_INIT, ")"),
  paste0("- Ours 3 runs (ms):", paste(sprintf("%.3f", ours$runs), collapse = ", "),
         " → median = ", sprintf("%.3f", ours$median_ms), " ms"),
  paste0("- R brunet 3 runs (s):", paste(sprintf("%.3f", rb$runs), collapse = ", "),
         " → median = ", sig(rb$median_s, 4), " s"),
  paste0("- **speedup = ", sprintf("%.1f", speedup), "× ; criterion ≥100×:",
         ifelse(verdict, "PASS", "FAIL"), "**"),
  paste0("- Informational: per-iteration slope ≈ ", sprintf("%.3f", per_iter_ms),
         " ms/iter(T=1 median ", sprintf("%.3f", t1_ms),
         " ms vs T=100 median);fit_kl_with_init each iteration includes one objective-trajectory kl_objective",
         "(the 3 rd: WH matmul + 96k ln,U-M1s-14 required by the numeric protocol),R brunet baseline",
         "does not compute the objective per iteration——a same-granularity fitted comparison would beat this table speedup, but vs 100× still lags by 1  order(s) of magnitude."),
  paste0("- Correctness anchor (informational): T=100 KL final values ours=", sig(obj_ours, 10),
         " R=", sig(as.numeric(rb$resid), 10), " relative diff=", sig(rel_obj, 3),
         ifelse(rel_obj < 1e-6, "(<1e-6, same-iteration semantics confirmed)", "(⚠ exceeds 1e-6, needs recheck)")), ""
)
writeLines(lines, file.path(HERE, "result.md"))
say("result.md written: ", file.path(HERE, "result.md"))
quit(status = ifelse(verdict, 0L, 1L))
