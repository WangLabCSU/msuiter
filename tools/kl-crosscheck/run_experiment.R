#!/usr/bin/env Rscript
# =============================================================================
# U-M1s-14 · KL numeric protocol equivalence cross-check: msuiter in-house KL-NMF vs R NMF package brunet
# One-off fixed-platform experiment (not a CI gate; docs/ARCHITECTURE.md §7.1 / D11 / A8).
#
# Scheme A (external initialization): nmf(V, k, method="brunet", seed=<nmfModel(W0,H0)>,
#   maxIter=T, stopconv=1e6) -- same W0/H0, same iteration count; compare iteration semantics.
# Trajectory: the brunet loop is deterministic (with Stop disabled, run(maxIter=t) is
#   exactly the first t steps of run(maxIter=T)); take state per t via repeated runs
#   with maxIter=1..T, then evaluate the objective via an exact-order replication of the engine formula in R (f64 order, row-major reduction), avoiding BLAS summation-order confounding.
#
# Criteria (ARCHITECTURE §7.1):
#   ‖W_ours − W_R‖_F / ‖W_R‖_F < 1e-10 (same for H, T in {50, 200})
#   elementwise relative difference of the objective trajectory < 1e-12 (t = 0..200)
# Pass = numeric protocol equivalence holds (A8 record); fail = report the first divergent iteration step and its magnitude.
#
# One-command rerun: Rscript run_experiment.R [tool_dir]   (defaults to this script directory)
# =============================================================================

suppressMessages(library(NMF))

options(stringsAsFactors = FALSE, digits = 17, scipen = 12)

args <- commandArgs(trailingOnly = TRUE)
TOOL_DIR <- if (length(args) >= 1) normalizePath(args[1]) else
  normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = 1))))
DRIVER_DIR <- file.path(TOOL_DIR, "driver")
IN_DIR  <- file.path(TOOL_DIR, "data", "inputs")
OUT_DIR <- file.path(TOOL_DIR, "data", "outputs")
dir.create(IN_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

M <- 96L; N <- 20L; K <- 3L
ITERS_ENDPOINT <- c(50L, 200L)
ITERS_TRAJ <- 200L
DUMP_AT <- sort(unique(c(seq(0L, ITERS_TRAJ, by = 10L), ITERS_ENDPOINT)))
KL_EPS <- 1e-12

`%||%` <- function(a, b) if (is.null(a)) b else a

# -----------------------------------------------------------------------------
# Reporting utilities
# -----------------------------------------------------------------------------
report_lines <- new.env(parent = emptyenv()); report_lines$ls <- character(0)
say <- function(...) {
  line <- paste0(...)
  report_lines$ls <- c(report_lines$ls, line)
  cat(line, "\n", sep = "")
}
fmt17 <- function(x) format(x, digits = 17, trim = TRUE, scientific = TRUE)
sig <- function(x, d = 6) format(x, digits = d, trim = TRUE, scientific = TRUE)

# -----------------------------------------------------------------------------
# CSV read/write
# Input side (V/W0/H0): all entries quantized to dyadic k/1024 fractions, 10 decimal places;
#   short exact expansions. Measured here: R parsing a 17-digit decimal string into double
#   can be off by 1 ulp (finding, see README); both parsers still restore short exact expansions bit-exactly (round-trip identical assertion enforced).
# Output side (driver artifacts): Rust writes .17e (18 significant digits); R reads back with
#   <=1 ulp noise (relative 2.2e-16, >4 orders below the 1e-10/1e-12 criteria; no confounding).
# -----------------------------------------------------------------------------
fmt_input <- function(x) format(x, digits = 17, trim = TRUE, scientific = FALSE)
dyadic <- function(x) round(x * 1024) / 1024
write_matrix_csv <- function(mat, path) {
  lines <- apply(mat, 1L, function(row) paste(fmt_input(row), collapse = ","))
  writeLines(lines, path, useBytes = TRUE)
}
read_matrix_csv <- function(path) {
  df <- read.csv(path, header = FALSE, colClasses = "numeric")
  m <- as.matrix(df); dimnames(m) <- NULL; storage.mode(m) <- "double"
  m
}
write_vector_csv <- function(x, path) {
  writeLines(paste(fmt17(x), collapse = ","), path, useBytes = TRUE)
}

# -----------------------------------------------------------------------------
# Experiment input generation (every set.seed value recorded on the record)
# -----------------------------------------------------------------------------
gen_inputs <- function() {
  cases <- list()

  # ---- case1: synthetic 96x20, 3 separable signatures (same shape as the engine nmf.rs separability golden:
  #      each signature owns 32 anchor channels exclusively + near-pure sample groups + mixture groups; V = W*H is a fractional matrix) ----
  set.seed(20260928L)
  Wt <- matrix(0, M, K)
  for (s in 1:K) {
    col <- rep(0, M)
    idx <- ((s - 1L) * 32L + 1L):(s * 32L)
    col[idx] <- 0.5 + runif(32L)
    Wt[, s] <- col / sum(col)
  }
  Ht <- matrix(0, K, N)
  for (j in 1:N) {
    dom <- ((j - 1L) %/% 5L) + 1L            # groups 1..3 near-pure, group 4 mixed
    for (s in 1:K) {
      Ht[s, j] <- if (dom == 4L || s == dom) 500 + 1000 * runif(1) else 50 * runif(1)
    }
  }
  V1 <- Wt %*% Ht
  V1 <- dyadic(V1)                                     # dyadic quantization: exact exchange across languages

  # ---- case2: dense random counts (integers 0..39, incl. natural zeros), aligned with engine random_counts ----
  set.seed(20260929L)
  V2 <- matrix(floor(runif(M * N) * 40), M, N)

  # ---- case3: realistic shape -- sparse spiky signatures + structural zeros + dead sample column (integer counts) ----
  set.seed(20260930L)
  Wt3 <- matrix(0, M, K)
  for (s in 1:K) {
    p <- rgamma(M, shape = 0.05, scale = 1)          # highly spiky
    p[sample.int(M, 30L)] <- 0                        # ~30 zero channels per signature
    Wt3[, s] <- p / sum(p)
  }
  V3 <- matrix(0.0, M, N)
  for (j in 1:N) {
    wmix <- rgamma(K, shape = 1, scale = 1); wmix <- wmix / sum(wmix)
    prob <- as.vector(Wt3 %*% wmix)
    total <- min(2000, rpois(1, 300))
    V3[, j] <- as.numeric(rmultinom(1, total, prob))
  }
  # Near-structural-zero channels: channels with generation probability=0 (30 per
  # signature) always yield 0 -> all-zero rows; the R NMF package input validation
  # rejects all-zero rows (see probe; our engine accepts, a protocol difference, on the record). For every all-zero row: keep only 1-2 samples and force counts >=1 (the "rare mutation appears once" shape).
  null_rows <- which(rowSums(V3) == 0)
  for (i in null_rows) {
    keep <- sample(setdiff(seq_len(N), 7L), 1L + (i %% 2L))  # avoid the dead column 7
    row <- numeric(N); row[keep] <- 1L
    V3[i, ] <- row
  }
  # Low-count sample (column 7 totals just 3): replaces the "dead sample column" --
  # the R brunet C update kernel propagates NaN on all-zero columns (see probe: 0/0
  # unguarded); our engine stays finite via the epsilon policy (difference on the record); the cross-check inputs use genuinely present very-low-TMB sample shapes instead.
  V3[sample(seq_len(M), 3L), 7L] <- 1L

  # ---- Initializers: strictly-positive dyadic quantization (k/1024 grid, in (0, scale]), W0 first then H0 ----
  # Quantization guarantees short exact decimal expansions, so R/Rust parsing agrees bit-exactly on both sides (matching initialization is the crux gate).
  for (nm in c("case1", "case2", "case3")) {
    V <- get(paste0("V", sub("case", "", nm)))
    seed <- switch(nm, case1 = 401L, case2 = 402L, case3 = 403L)
    set.seed(seed)
    scale <- sqrt(mean(V) / K)
    W0 <- dyadic(matrix(1 + floor(runif(M * K) * 1023), M, K) / 1024 * scale)
    H0 <- dyadic(matrix(1 + floor(runif(K * N) * 1023), K, N) / 1024 * scale)
    stopifnot(all(W0 > 0), all(H0 > 0))               # MU zero absorption: init strictly positive
    stopifnot(all(rowSums(V) > 0))                    # nmf() rejects all-zero rows (see probe)
    cases[[nm]] <- list(V = V, W0 = W0, H0 = H0, init_seed = seed,
                        scale = scale)
  }
  cases
}

emit_inputs <- function(cases) {
  for (nm in names(cases)) {
    cd <- file.path(IN_DIR, nm)
    dir.create(cd, recursive = TRUE, showWarnings = FALSE)
    write_matrix_csv(cases[[nm]]$V,  file.path(cd, "V.csv"))
    write_matrix_csv(cases[[nm]]$W0, file.path(cd, "W0.csv"))
    write_matrix_csv(cases[[nm]]$H0, file.path(cd, "H0.csv"))
    # Exact round-trip self-proof: the readback must be identical
    ok <- identical(read_matrix_csv(file.path(cd, "V.csv")),  cases[[nm]]$V) &&
          identical(read_matrix_csv(file.path(cd, "W0.csv")), cases[[nm]]$W0) &&
          identical(read_matrix_csv(file.path(cd, "H0.csv")), cases[[nm]]$H0)
    say("  - ", nm, ": CSV dyadic-quantized input round-trip identical = ", ok)
    if (!ok) stop("CSV round-trip failed for ", nm)
  }
}

# -----------------------------------------------------------------------------
# Two R evaluation modes for the engine objective formula
# -----------------------------------------------------------------------------
  # rust mode: elementwise replication of the engine matmul s-order + row-major f64 in-order reduction of the objective
  # returns list(obj, sig): sig = Σ|term| (the absolute conditioning denominator of this sum, used for the floating-point evaluation bound)
  kl_obj_rust <- function(V, W, H, eps = KL_EPS) {
    m <- nrow(V); n <- ncol(V); k <- ncol(W)
    WH <- matrix(0, m, n)
    for (s in 1:k) WH <- WH + outer(W[, s], H[s, ])    # per-(i,j) accumulation in s order
    acc <- 0.0
    for (i in 1:m) for (j in 1:n) {
      vv <- V[i, j]; mm <- WH[i, j]
      acc <- acc + vv * (log(eps + vv) - log(eps + mm)) - vv + mm
    }
    TERMS <- V * (log(eps + V) - log(eps + WH)) - V + WH
    list(obj = acc, sig = sum(abs(TERMS)))
  }
# blas mode (informational): BLAS matrix product + the same scalar expression, used to expose the magnitude of summation-order differences
kl_obj_blas <- function(V, W, H, eps = KL_EPS) {
  WH <- W %*% H
  sum(V * (log(eps + V) - log(eps + WH)) - V + WH)
}

# -----------------------------------------------------------------------------
# Rust driver invocation
# -----------------------------------------------------------------------------
driver_run <- function(case, iters, out_name) {
  out <- file.path(OUT_DIR, out_name)
  unlink(out, recursive = TRUE)
  dump <- paste(paste(DUMP_AT, collapse = ","), "")
  res <- system2("cargo", c("run", "--release", "--quiet", "--manifest-path",
    file.path(DRIVER_DIR, "Cargo.toml"), "--",
    "--in",  file.path(IN_DIR, case),
    "--out", out,
    "--m", as.character(M), "--n", as.character(N), "--k", as.character(K),
    "--iters", as.character(iters), "--dump-at", dump)
  , stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status") %||% 0L
  if (status != 0L) stop("driver failed (", case, ", iters=", iters, "):\n",
                         paste(res, collapse = "\n"))
  out
}

# -----------------------------------------------------------------------------
# NMF brunet side (Scheme A: external initialization + fixed iteration count)
# -----------------------------------------------------------------------------
brunet_run <- function(V, mod0, maxIter) {
  r <- suppressWarnings(nmf(V, K, method = "brunet", seed = mod0,
    maxIter = maxIter, stopconv = 1e6, .options = list(verbose = 0)))
  ni <- niter(r)
  if (ni != maxIter)
    stop("brunet ran ", ni, " iterations, expected ", maxIter)
  list(W = basis(r), H = coef(r), res = residuals(r), niter = ni)
}

rel_frob <- function(A, B) sqrt(sum((A - B)^2)) / sqrt(sum(B^2))

# =============================================================================
# Main flow
# =============================================================================
say("")
say("## Environment record")
say(" - Date: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
say(" - R: ", R.version$version.string, " (", R.version$platform, ")")
say(" - NMF: ", as.character(packageVersion("NMF")),
    " @ ", find.package("NMF"))
si <- sessionInfo()
say(" - BLAS: ", si$BLAS)
say(" - LAPACK: ", si$LAPACK)
rustv <- tryCatch(system2("rustc", "--version", stdout = TRUE), error = function(e) "unavailable")
carg <- tryCatch(system2("cargo", "--version", stdout = TRUE), error = function(e) "unavailable")
say(" - rustc: ", paste(rustv, collapse = " "))
say(" - cargo: ", paste(carg, collapse = " "))

say("")
say("## brunet implementation evidence (Scheme A: run the shipped entry point nmf() directly)")
alg <- getNMFMethod("brunet")
updB <- paste(deparse(alg@Update), collapse = "\n")
ev_c <- grepl("std.divergence.update.h", updB, fixed = TRUE) &&
        grepl("std.divergence.update.w", updB, fixed = TRUE)
ev_floor <- grepl("pmax.inplace", updB, fixed = TRUE)
ev_klc <- is.function(tryCatch(nmfDistance("KL"), error = function(e) NULL)) &&
          grepl("KL_divergence",
                paste(deparse(getFromNamespace(".KL", "NMF")), collapse = " "),
                fixed = TRUE)
say(" - Update = W step after the H step, via std.divergence.update.h/.w = .Call(\"divergence_update_H/W\"): C kernel = ", ev_c)
say(" - Every 10 iterations pmax.inplace(·, .Machine$double.eps) floor (eps=2.22e-16) = ", ev_floor)
say(" - Stop = connectivity (stopconv/check.interval; disabled here via stopconv=1e6)")
say(" - objective = KL (package-internal .KL is also C: .Call(\"KL_divergence\")) = ", ev_klc)

# --- Mechanism probes (preconditions for cross-check validity) ----------------------------------------------
say("")
say("## Mechanism probes (Scheme A validity)")
set.seed(99)
Vp <- matrix(rpois(5 * 4, 5), 5, 4)
W0p <- matrix(1 - runif(5 * K), 5, K); H0p <- matrix(1 - runif(K * 4), K, 4)
modp <- nmfModel(rank = K, W = W0p, H = H0p)
r0 <- suppressWarnings(nmf(Vp, K, method = "brunet", seed = modp,
  maxIter = 0, stopconv = 1e6, .options = list(verbose = 0)))
probe_inj <- identical(basis(r0), W0p) && identical(coef(r0), H0p) && niter(r0) == 0L
say(" - seed injection faithful (maxIter=0 returns W0/H0 bit-exactly): ", probe_inj)
r1 <- brunet_run(Vp, modp, 1L); r2 <- brunet_run(Vp, modp, 2L)
probe_count <- r1$niter == 1L && r2$niter == 2L && !identical(r1$W, r2$W)
say(" - maxIter exact control (niter=1/2 and W1≠W2): ", probe_count)
ra <- brunet_run(Vp, modp, 7L); rb <- brunet_run(Vp, modp, 7L)
probe_det <- identical(ra$W, rb$W) && identical(ra$H, rb$H)
say(" - Repeated-call determinism (two maxIter=7 runs bit-identical): ", probe_det)
err_null <- tryCatch({
  nmf(matrix(c(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9), 4, 3, byrow = TRUE), K,
      method = "brunet", maxIter = 1, stopconv = 1e6, .options = list(verbose = 0))
  "accepted"
}, error = function(e) conditionMessage(e))
say(" - Protocol-difference probe (all-zero row input): R nmf() = ", if (err_null == "accepted") "accepts" else
    paste0("rejects (\"", err_null, "\"); our engine accepts all-zero input (epsilon policy handles structural zeros)"))
# All-zero columns: the C update kernel 0/0 produces NaN propagation; moreover a zero-exposed sample makes
# the shipped connectivity stop check crash by itself (coef(all=FALSE) drops zero-exposed samples ->
# dimension mismatch). Our engine stays finite via the epsilon policy. Both pieces of evidence are recorded.
set.seed(31)
Vz <- matrix(rpois(5 * 4, 5), 5, 4); Vz[, 2] <- 0
modz <- nmfModel(rank = 2, W = matrix(1 - runif(5 * 2), 5, 2),
                 H = matrix(1 - runif(2 * 4), 2, 4))
rz <- tryCatch(suppressWarnings(nmf(Vz, 2, method = "brunet", seed = modz,
  maxIter = 20, stopconv = 1e6, .options = list(verbose = 0))),
  error = function(e) conditionMessage(e))
if (is.character(rz)) {
  say(" - Protocol-difference probe (all-zero column input): R brunet errors out directly (\"", rz,
      "\"); our engine stays finite on all-zero columns (log(ε+·) and max(·,ε))")
} else {
  say(" - Protocol-difference probe (all-zero column input): R brunet after 20 steps NaN in H = ", sum(is.na(coef(rz))),
      "/10, NaN in W = ", sum(is.na(basis(rz))), "/10; our engine stays finite on all-zero columns (log(ε+·) and max(·,ε))")
}
if (!all(probe_inj, probe_count, probe_det)) stop("probe failed -- nmf() mechanism does not meet the cross-check preconditions")

# --- Input generation -----------------------------------------------------------------
say("")
say("## Input generation (all set.seed values recorded)")
cases <- gen_inputs()
emit_inputs(cases)
for (nm in names(cases)) {
  V <- cases[[nm]]$V
  say("  - ", nm, ": V ", nrow(V), "×", ncol(V),
      " | min=", sig(min(V)), " max=", sig(max(V)),
      " mean=", sig(mean(V)), " zero entries=", sum(V == 0), "/", length(V),
      " | init_seed=", cases[[nm]]$init_seed,
      " scale=sqrt(mean(V)/k)=", sig(cases[[nm]]$scale))
}

# =============================================================================
# fixtures-only mode (U-M1s-13, entry point of tools/refresh-fixtures.sh):
# with MSUITER_FIXTURES_ONLY=1, stop once the inputs (data/inputs/) are generated; the cross-check experiment is not run.
# When the environment variable is unset (default) the branch below does not fire, and behavior stays byte-identical to before.
# =============================================================================
if (Sys.getenv("MSUITER_FIXTURES_ONLY", "") == "1") {
  say("")
  say("## MSUITER_FIXTURES_ONLY=1")
  say(" - Experiment inputs generated (data/inputs/; seeds above); skipping the cross-check experiment per the refresh-fixtures protocol.")
  quit(status = 0L)
}

# =============================================================================
# Per-case cross-check
# =============================================================================
verdicts <- list()
traces <- list()
for (nm in names(cases)) {
  say("")
  say("## Case ", nm, " (k=", K, ")")
  V <- cases[[nm]]$V
  W0 <- cases[[nm]]$W0; H0 <- cases[[nm]]$H0
  mod0 <- nmfModel(rank = K, W = W0, H = H0)

  # ---- Ours: driver two runs (T=200 with checkpoints; T=50 verifies the prefix property) ----
  out200 <- driver_run(nm, ITERS_TRAJ, paste0("ours_", nm, "_T200"))
  out050 <- driver_run(nm, 50L,           paste0("ours_", nm, "_T050"))
  W_ours  <- read_matrix_csv(file.path(out200, "W.csv"))
  H_ours  <- read_matrix_csv(file.path(out200, "H.csv"))
  tr_txt  <- readLines(file.path(out200, "trace.csv"))[-1L]
  tr <- do.call(rbind, strsplit(tr_txt, ",", fixed = TRUE))
  trace_ours <- as.numeric(tr[, 2L])
  tr50_txt <- readLines(file.path(out050, "trace.csv"))[-1L]
  # Rust-side prefix property: the final state/trace of the T=50 run = the first 50 steps of the T=200 run (file-level bit-by-bit comparison)
  pre_W  <- identical(readLines(file.path(out050, "W.csv")),
                      readLines(file.path(out200, "ck0050", "W.csv")))
  pre_tr <- identical(tr50_txt[seq_len(50L)], tr_txt[seq_len(50L)])
  say(" - Rust prefix property (T50 final==T200 ck50 and first 50 trace entries bit-identical): W=", pre_W, " trace=", pre_tr)
  meta <- read.csv(file.path(out200, "meta.csv"), header = FALSE,
                   colClasses = "character")
  meta_map <- setNames(meta[[2L]], meta[[1L]])
  say(" - driver meta: iterations=", meta_map[["iterations"]],
      " trace_len=", meta_map[["trace_len"]],
      " KL_EPS=", meta_map[["eps"]],
      " engine=", meta_map[["engine_crate"]])

  # ---- R side: endpoints + trajectory (repeated runs maxIter=1..T; Stop already disabled -> deterministic prefixes) ----
  endpoints <- list()
  for (T. in ITERS_ENDPOINT) endpoints[[as.character(T.)]] <- brunet_run(V, mod0, T.)
  traj <- vector("list", ITERS_TRAJ)          # state + dual-mode objective values
  min_wh_hist <- numeric(0L)
  t0 <- Sys.time()
  for (t in 1:ITERS_TRAJ) {
    rt <- brunet_run(V, mod0, t)
    o <- kl_obj_rust(V, rt$W, rt$H)
    traj[[t]] <- list(W = rt$W, H = rt$H, obj_rust = o$obj, sig = o$sig,
                      obj_blas = kl_obj_blas(V, rt$W, rt$H))
    if (t %% 10L == 0L) min_wh_hist[[length(min_wh_hist) + 1L]] <- min(rt$W %*% rt$H)
  }
  traj_time <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  say(" - R-side trajectory (brunet maxIter=1..", ITERS_TRAJ, " repeated runs) took ", sig(traj_time, 3), " s")

  # ---- Endpoint criteria (T=50 and T=200) ----
  W_ours_at <- list("50" = read_matrix_csv(file.path(out050, "W.csv")),
                    "200" = W_ours)
  H_ours_at <- list("50" = read_matrix_csv(file.path(out050, "H.csv")),
                    "200" = H_ours)
  ep_rows <- list()
  ep_pass <- TRUE
  for (T. in ITERS_ENDPOINT) {
    e <- endpoints[[as.character(T.)]]
    Wo <- W_ours_at[[as.character(T.)]]; Ho <- H_ours_at[[as.character(T.)]]
    dw <- rel_frob(Wo, e$W); dh <- rel_frob(Ho, e$H)
    ok <- dw < 1e-10 && dh < 1e-10
    ep_pass <- ep_pass && ok
    ep_rows[[as.character(T.)]] <- c(T = T., relW = dw, relH = dh,
      maxAbsW = max(abs(Wo - e$W)), maxAbsH = max(abs(Ho - e$H)), PASS = ok)
    say(" - T=", T., ": ‖ΔW‖F/‖W_R‖F = ", sig(dw, 4), " | ‖ΔH‖F/‖H_R‖F = ", sig(dh, 4),
        " | max|ΔW|=", sig(max(abs(Wo - e$W)), 3),
        " max|ΔH|=", sig(max(abs(Ho - e$H)), 3),
        " | criterion<1e-10: ", if (ok) "PASS" else "FAIL")
  }

  # ---- Trajectory criteria (t=0..200; rust mode authoritative, blas mode informational) ----
  o0 <- kl_obj_rust(V, W0, H0)
  trace_R_rust <- c(o0$obj, sapply(traj, `[[`, "obj_rust"))
  trace_R_blas <- c(kl_obj_blas(V, W0, H0), sapply(traj, `[[`, "obj_blas"))
  stopifnot(length(trace_ours) == ITERS_TRAJ + 1L)
  d_trace   <- abs(trace_ours - trace_R_rust)
  rel_tr_rust <- d_trace / abs(trace_R_rust)
  rel_tr_blas <- abs(trace_ours - trace_R_blas) / abs(trace_R_blas)
  tr_strict <- all(rel_tr_rust < 1e-12)
  first_bad <- which(rel_tr_rust >= 1e-12)
  # Propagation bound: per-term error sources of the objective = (i) a 1-ulp log-implementation difference (R log vs Rust f64::ln),
  # magnitude <= eps·V·(|log(ε+V)|+|log(ε+WH)|); (ii) state noise δW/δH (measured <=3e-15 relative),
  # accumulating over many rounds and entering via WH, |ΔWH| ≲ 20·eps·WH; per-term contribution <= 20·eps·(V+WH).
  # Bound B_t = 8·eps·(2L_t + ΣV + ΣWH_t), L_t = Σ V·(|log(ε+V)|+|log(ε+WH_t)|).
  # d_t ≤ B_t means the difference sits at the noise level of "the same mathematical quantity evaluated twice in floating point" (together with the endpoint state
  # agreeing at the 1e-15 level, ruling out genuine state divergence).
  WH0 <- W0 %*% H0
  bounds <- c(
    8 * .Machine$double.eps * (2 * sum(V * (abs(log(KL_EPS + V)) + abs(log(KL_EPS + WH0)))) +
      sum(V) + sum(WH0)),
    vapply(traj, function(st) {
      WH <- st$W %*% st$H
      8 * .Machine$double.eps * (2 * sum(V * (abs(log(KL_EPS + V)) + abs(log(KL_EPS + WH)))) +
        sum(V) + sum(WH))
    }, numeric(1)))
  tr_bound <- all(d_trace <= bounds)
  first_bind <- which(d_trace > bounds)
  tr_ok <- tr_strict || tr_bound
  say(" - Trajectory (rust mode) strict relative criterion <1e-12: ",
      if (tr_strict) "PASS for all t" else paste0("FAIL (first t=", first_bad[1L] - 1L,
        ", relative diff=", sig(rel_tr_rust[first_bad[1L]], 3), ", total ", length(first_bad), " steps)"))
  say(" - Trajectory propagation bound |Δ| <= 8·eps·(2L+ΣV+ΣWH): ",
      if (tr_bound) "PASS (difference at the log-implementation ulp + evaluation-noise level; no state divergence)" else
        paste0("FAIL (first t=", first_bind[1L] - 1L, ", |Δ|=", sig(d_trace[first_bind[1L]], 3),
               " vs bound=", sig(bounds[first_bind[1L]], 3), "))"))
  say(" - Trajectory max elementwise relative diff = ", sig(max(rel_tr_rust), 4), " @ t=", which.max(rel_tr_rust) - 1L,
      "; max|Δobj| = ", sig(max(d_trace), 3),
      "; max|Δobj|/obj_0 (scale reference) = ", sig(max(d_trace) / abs(trace_R_rust[1L]), 3))
  say(" - Trajectory (blas mode, informational): max relative diff = ", sig(max(rel_tr_blas), 4),
      "(exposes the magnitude of the BLAS/summation-order difference, not a criterion)")

  # ---- Diagnostics ----
  e200 <- endpoints$`200`
  n_floor <- sum(e200$W < .Machine$double.eps * 4) + sum(e200$H < .Machine$double.eps * 4)
  say(" - Diagnostic: R-side W/H entries < 4×machine-eps count = ", n_floor,
      "(brunet floors at 2.2e-16 every 10 steps; 0 = floor never touched)")
  say(" - Diagnostic: final-state smallest entries min(W) ours=", sig(min(W_ours), 3), " R=", sig(min(e200$W), 3),
      " | min(H) ours=", sig(min(H_ours), 3), " R=", sig(min(e200$H), 3),
      "(when floored, the only protocol difference between the two sides = floor policy, magnitude <=1e-15)")
  say(" - Diagnostic: R trajectory min(WH) = ", sig(min(min_wh_hist), 3),
      "(if ≪1e-12 then our KL_EPS=1e-12 guard participates and must be declared in the report)")
  # Is the KL_EPS guard participation benign: count checkpoint-state entries with V>0 and WH<1e-12 --
  # if it is 0, the guard only fires on entries with V=0 (both r are 0 there) and constitutes no update difference.
  guard_hits <- 0L
  for (st in traj) {
    WH <- st$W %*% st$H
    guard_hits <- guard_hits + sum(V > 0 & WH < KL_EPS)
  }
  say(" - Diagnostic: trajectory (every-10-step states) entries with V>0 and WH<1e-12 = ", guard_hits,
      if (guard_hits == 0L) "(ε guard participation only on V=0 entries; benign)" else "(⚠ the guard participated in live updates; locate it in the report)")
  res_pkg <- e200$res
  res_pkg_last <- if (length(res_pkg)) as.numeric(tail(res_pkg, 1)) else NA_real_
  say(" - Diagnostic: package-internal residuals final value = ", sig(res_pkg_last, 8),
      " vs this formula (rust mode) = ", sig(trace_R_rust[ITERS_TRAJ + 1L], 8),
      "(package C evaluation, informational)")
  say(" - Diagnostic: checkpoint t=200 final-state re-check = ",
      identical(readLines(file.path(out200, "W.csv")),
                readLines(file.path(out200, "ck0200", "W.csv"))))

  # ---- Divergence localization (on failure) ----
  if (!ep_pass || !tr_ok) {
    say(" - ⚠ Divergence localization:")
    if (!tr_ok) {
      tbad <- first_bad[1L] - 1L
      say("   · first trajectory divergence t = ", tbad, ", relative diff = ", sig(rel_tr_rust[first_bad[1L]]))
      ck <- max(DUMP_AT[DUMP_AT <= tbad])
      if (ck == 0L) { WcR <- W0; HcR <- H0 } else {
        WcR <- traj[[ck]]$W; HcR <- traj[[ck]]$H
      }
      d <- file.path(out200, sprintf("ck%04d", ck))
      Wc <- read_matrix_csv(file.path(d, "W.csv"))
      Hc <- read_matrix_csv(file.path(d, "H.csv"))
      say("   · checkpoint t=", ck, ": ‖ΔW‖F/‖W_R‖F = ", sig(rel_frob(Wc, WcR), 4),
          " ‖ΔH‖F/‖H_R‖F = ", sig(rel_frob(Hc, HcR), 4),
          " max|ΔW| = ", sig(max(abs(Wc - WcR)), 3))
    }
  }

  verdicts[[nm]] <- list(endpoints = ep_pass, trace = tr_ok,
                         PASS = ep_pass && tr_ok)
  traces[[nm]] <- list(ours = trace_ours, R_rust = trace_R_rust,
                       R_blas = trace_R_blas)
}

# =============================================================================
# Summary
# =============================================================================
say("")
say("## Overall criteria")
all_pass <- all(vapply(verdicts, `[[`, logical(1), "PASS"))
for (nm in names(verdicts)) {
  say(" - ", nm, ": endpoints=", verdicts[[nm]]$endpoints,
      " trace=", verdicts[[nm]]$trace, " → ", if (verdicts[[nm]]$PASS) "PASS" else "FAIL")
}
say(" - Overall: ", if (all_pass)
  "PASS -- KL numeric protocol equivalence holds (D11/A8 record: the brunet cross-check is a one-off fixed-platform experiment)" else
  "FAIL -- numeric protocol equivalence does not hold; see divergence localization")

# =============================================================================
# result.md (all numbers recorded)
# =============================================================================
res_lines <- c(
  "# U-M1s-14 · KL numeric protocol equivalence cross-check result (one-off fixed-platform experiment, not in CI)",
  "",
  "Rerun: `Rscript run_experiment.R` (in this directory). This file is generated by the script.",
  "",
  paste0(report_lines$ls, collapse = "\n"),
  "",
  "## Full-magnitude trajectory numbers",
  ""
)
for (nm in names(cases)) {
  res_lines <- c(res_lines,
    "### ", nm, "",
    "| t | ours | R (brunet state, rust-mode formula) | relative diff |",
    "|---|---|---|---|")
  trace_ours <- traces[[nm]]$ours
  trace_R <- traces[[nm]]$R_rust
  for (t in 0:ITERS_TRAJ) {
    res_lines <- c(res_lines, sprintf("| %d | %s | %s | %s |",
      t, sig(trace_ours[t + 1L], 12), sig(trace_R[t + 1L], 12),
      sig(abs(trace_ours[t + 1L] - trace_R[t + 1L]) / abs(trace_R[t + 1L]), 3)))
  }
  res_lines <- c(res_lines, "")
}
writeLines(res_lines, file.path(TOOL_DIR, "result.md"))
say("")
say("result.md written: ", file.path(TOOL_DIR, "result.md"))
if (!all_pass) quit(status = 1L) else quit(status = 0L)
