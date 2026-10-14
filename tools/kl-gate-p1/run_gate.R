#!/usr/bin/env Rscript
# =============================================================================
# P1 kernel-extension lane, face (a): bit-equivalence gate
# msuiter in-house Apache-2.0 KL-MU kernel (exposed through the stable batch
# entry `msuiter-kernel`) vs R NMF::nmf(method = "brunet"), scheme A
# (external initialization, identical W0/H0, iteration-count controlled,
# brunet early stop disabled) -- the protocol established by
# tools/kl-crosscheck (U-M1s-14), mirrored here against the NEW stable
# boundary surface rather than the scratch driver.
#
# One-shot fixed-platform experiment, NOT a CI-per-run gate
# (docs/ARCHITECTURE.md §7.1 / D11 / A8). What CI enforces is the committed
# evidence record: tests/testthat/test-kernel-gate-evidence.R audits the
# result.md produced here (verdict line, endpoint ratios under 1e-10, seeds
# on the record). Regeneration: Rscript run_gate.R [tool_dir].
#
# Acceptance criterion (parity plan §5 row P1,
# docs/research/09-sigminer-v3-parity-plan.md:71):
#   per case, T in {50, 200}:  |dW|_F / |W_R|_F < 1e-10   (and the H twin)
# Fixed seeds are those of the committed synthetic inputs (kl-crosscheck
# record: V seeds 20260928-29-30, init seeds 401/402/403; the inputs are
# quantized to 10-decimal dyadics so both language parsers restore the
# identical doubles -- see tools/kl-crosscheck/README.md, the 1-ulp
# decimal-parsing finding recorded there).
#
# Numerics in result.md come exclusively from this run (zero-fabrication
# law); outputs are committed next to the record for mechanical re-audit.
# =============================================================================

suppressMessages(library(NMF))

options(stringsAsFactors = FALSE, digits = 17, scipen = 12)

args <- commandArgs(trailingOnly = TRUE)
TOOL_DIR <- if (length(args) >= 1) normalizePath(args[1]) else
  normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = 1))))
ROOT <- normalizePath(file.path(TOOL_DIR, "..", ".."))
IN_DIR   <- file.path(ROOT, "tools", "kl-crosscheck", "data", "inputs")
OUT_DIR  <- file.path(TOOL_DIR, "data", "outputs")
MANIFEST <- file.path(ROOT, "src", "rust", "Cargo.toml")
unlink(OUT_DIR, recursive = TRUE)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

CASES <- c("case1", "case2", "case3")
INIT_SEEDS <- c(case1 = "401", case2 = "402", case3 = "403")
ITERS_ENDPOINT <- c(50L, 200L)

report_lines <- new.env(parent = emptyenv()); report_lines$ls <- character(0)
say <- function(...) {
  line <- paste0(...)
  report_lines$ls <- c(report_lines$ls, line)
  cat(line, "\n", sep = "")
}
sig <- function(x, d = 4) format(x, digits = d, trim = TRUE, scientific = TRUE)

# -----------------------------------------------------------------------------
# CSV IO (kl-crosscheck conventions: headerless numeric CSVs, row-major)
# -----------------------------------------------------------------------------
read_matrix_csv <- function(path) {
  df <- read.csv(path, header = FALSE, colClasses = "numeric")
  m <- as.matrix(df); dimnames(m) <- NULL; storage.mode(m) <- "double"
  m
}

# -----------------------------------------------------------------------------
# Stable batch entry: build once, then pure invocations
# -----------------------------------------------------------------------------
say("## Environment record")
say(" - date: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
rv <- R.version
say(" - R: ", rv$version.string, " (", rv$platform, ")")
say(" - NMF: ", as.character(packageVersion("NMF")), " @ ", find.package("NMF"))
si <- sessionInfo()
say(" - BLAS: ", si$BLAS)
say(" - LAPACK: ", si$LAPACK)
for (cmd in list(c("rustc", "--version"), c("cargo", "--version"))) {
  v <- tryCatch(paste(system2(cmd[1L], cmd[-1L], stdout = TRUE), collapse = " "),
                error = function(e) "unavailable")
  say(" - ", paste(cmd, collapse = " "), ": ", v)
}

KERNEL <- "msuiter-kernel"
build <- system2("cargo", c("build", "--quiet", "--manifest-path", MANIFEST,
  "--target-dir", file.path(dirname(MANIFEST), "target"),
  "--package", "msuiter-engine", "--bin", KERNEL),
  stdout = TRUE, stderr = TRUE)
if (!identical(attr(build, "status") %||% 0L, 0L)) {
  stop("stable batch entry build failed:\n", paste(build, collapse = "\n"))
}
TARGET <- file.path(dirname(MANIFEST), "target")
BIN <- file.path(TARGET, "debug",
  paste0(KERNEL, if (identical(Sys.info()[["sysname"]], "Windows_NT")) ".exe" else ""))
if (!file.exists(BIN)) stop("built binary missing: ", BIN)

KERNEL_VERSION <- paste(system2(BIN, "--version", stdout = TRUE), collapse = " ")
say(" - stable entry: ", KERNEL_VERSION)
if (!grepl("protocol=1", KERNEL_VERSION, fixed = TRUE)) {
  stop("protocol handshake broken: ", KERNEL_VERSION)
}

#' Invoke the stable entry for one committed case. tag names the output
#' directory uniquely per invocation (determinism probes must compare two
#' independent runs, not one file against itself).
kernel_fit <- function(name, T., tag = NULL, extra = character(0), dump = NULL) {
  indir <- file.path(IN_DIR, name)
  outdir <- file.path(OUT_DIR, tag %||% paste0(name, "_T", sprintf("%03d", T.)))
  unlink(outdir, recursive = TRUE)
  flags <- c("fit-kl", "--in", indir, "--out", outdir,
    "--m", "96", "--n", "20", "--k", "3", "--iters", as.character(T.))
  if (!is.null(dump)) flags <- c(flags, "--dump-at", paste(dump, collapse = ","))
  res <- system2(BIN, c(flags, extra), stdout = TRUE, stderr = TRUE)
  if (!identical(attr(res, "status") %||% 0L, 0L)) {
    stop("kernel CLI failed (", name, ", T=", T., "):\n", paste(res, collapse = "\n"))
  }
  outdir
}

read_meta <- function(dir) {
  d <- read.csv(file.path(dir, "meta.csv"), header = FALSE, colClasses = "character")
  setNames(d[[2L]], d[[1L]])
}

rel_frob <- function(A, B) sqrt(sum((A - B)^2)) / sqrt(sum(B^2))

# Full-file raw bytes for byte-identity probes (house readBin convention).
.bytes <- function(p) readBin(p, "raw", file.info(p)$size)

# -----------------------------------------------------------------------------
# Mechanism probes (gate-validity preconditions, kl-crosscheck discipline)
# -----------------------------------------------------------------------------
say("")
say("## Mechanism probes (scheme-A validity on the stable boundary surface)")

# P1 injection fidelity: maxIter 0 returns the seed factors bit-for-bit.
w0 <- read_matrix_csv(file.path(IN_DIR, "case1", "W0.csv"))
h0 <- read_matrix_csv(file.path(IN_DIR, "case1", "H0.csv"))
d0 <- kernel_fit("case1", 0L, tag = "probe_injection")
probe_inj <- identical(read_matrix_csv(file.path(d0, "W.csv")), w0) &&
             identical(read_matrix_csv(file.path(d0, "H.csv")), h0) &&
             read_meta(d0)[["iterations"]] == "0"
say(" - injection fidelity (--iters 0 returns the seeded W0/H0 exactly): ", probe_inj)

# P2 determinism: two independent runs into separate directories.
da <- kernel_fit("case1", 5L, tag = "probe_det_a")
db <- kernel_fit("case1", 5L, tag = "probe_det_b")
probe_det <- all(vapply(c("W.csv", "H.csv", "trace.csv", "meta.csv"), function(f)
  identical(.bytes(file.path(da, f)), .bytes(file.path(db, f))), logical(1)))
say(" - rerun determinism (two independent invocations byte-identical): ", probe_det)

# P3 prefix property: the T=200 checkpoint at t=50 equals the T=50 run.
dpre <- kernel_fit("case1", 200L, tag = "probe_prefix_full", dump = 50L)
dnow <- kernel_fit("case1", 50L, tag = "probe_prefix_cut")
probe_pre <- identical(readLines(file.path(dpre, "ck0050", "W.csv")),
                      readLines(file.path(dnow, "W.csv"))) &&
              identical(readLines(file.path(dpre, "ck0050", "H.csv")),
                        readLines(file.path(dnow, "H.csv")))
say(" - prefix property (T50 run == T200 checkpoint 50, file bytes): ", probe_pre)

# P4 batch mode equals the single-case invocation, byte for byte.
cases_dir <- file.path(OUT_DIR, "batch")
dir.create(cases_dir, recursive = TRUE, showWarnings = FALSE)
manifest <- file.path(cases_dir, "cases.csv")
writeLines(c("case,init,seed,replicate,iters,m,n,k",
             "case2,external,,,200,96,20,3"), manifest)
rb <- system2(BIN, c("fit-kl", "--cases", manifest, "--root", IN_DIR,
  "--out-root", cases_dir), stdout = TRUE, stderr = TRUE)
if (!identical(attr(rb, "status") %||% 0L, 0L)) {
  stop("batch mode failed:\n", paste(rb, collapse = "\n"))
}
single200 <- kernel_fit("case2", 200L, tag = "case2_T200")
probe_batch <- identical(.bytes(file.path(cases_dir, "case2", "out", "W.csv")),
                        .bytes(file.path(single200, "W.csv")))
say(" - batch mode == single-case invocation (case2 W bytes): ", probe_batch)

if (!all(probe_inj, probe_det, probe_pre, probe_batch)) {
  stop("mechanism probes failed -- the boundary surface does not meet the ",
       "gate preconditions; result.md NOT written")
}

# -----------------------------------------------------------------------------
# R side: brunet, scheme A (external init through nmfModel, exact iteration
# count, connectivity stop disabled) -- verbatim kl-crosscheck invocation.
# -----------------------------------------------------------------------------
brunet_run <- function(V, mod0, maxIter) {
  r <- suppressWarnings(nmf(V, 3L, method = "brunet", seed = mod0,
    maxIter = maxIter, stopconv = 1e6, .options = list(verbose = 0)))
  ni <- niter(r)
  if (ni != maxIter) stop("brunet ran ", ni, " iterations, expected ", maxIter)
  list(W = basis(r), H = coef(r), niter = ni)
}

say("")
say("## Endpoint comparison (criterion: each ratio < 1e-10)")
rows <- character(0)
all_pass <- TRUE
for (nm in CASES) {
  V <- read_matrix_csv(file.path(IN_DIR, nm, "V.csv"))
  W0 <- read_matrix_csv(file.path(IN_DIR, nm, "W0.csv"))
  H0 <- read_matrix_csv(file.path(IN_DIR, nm, "H0.csv"))
  mod0 <- nmfModel(rank = 3L, W = W0, H = H0)
  for (T. in ITERS_ENDPOINT) {
    ours_dir <- kernel_fit(nm, T.)
    Wo <- read_matrix_csv(file.path(ours_dir, "W.csv"))
    Ho <- read_matrix_csv(file.path(ours_dir, "H.csv"))
    meta <- read_meta(ours_dir)
    e <- brunet_run(V, mod0, T.)
    dw <- rel_frob(Wo, e$W)
    dh <- rel_frob(Ho, e$H)
    ok <- dw < 1e-10 && dh < 1e-10
    all_pass <- all_pass && ok
    rows <- c(rows, paste0("| ", nm, " | ", T., " | ", sig(dw), " | ", sig(dh),
      " | ", meta[["obj_final"]], " | ", if (ok) "PASS" else "FAIL", " |"))
    say(" - ", nm, " T=", T., ": |dW|F/|W_R|F=", sig(dw),
        " |dH|F/|H_R|F=", sig(dh), "  [", if (ok) "PASS" else "FAIL", "]")
  }
}

# -----------------------------------------------------------------------------
# G2 companion arm (tool-level zero-lock evidence): the NNDSVDa init face of
# the stable entry, checked for the properties the cargo-side g2 suite pins.
# -----------------------------------------------------------------------------
say("")
say("## G2 companion arm (stable-entry NNDSVDa face, seed 20261014)")
dn1 <- kernel_fit("case1", 60L, tag = "probe_g2_a",
  extra = c("--init", "nndsvda", "--seed", "20261014"))
dn2 <- kernel_fit("case1", 60L, tag = "probe_g2_b",
  extra = c("--init", "nndsvda", "--seed", "20261014"))
Wn <- read_matrix_csv(file.path(dn1, "W.csv"))
Hn <- read_matrix_csv(file.path(dn1, "H.csv"))
g2_pos <- all(Wn > 0) && all(Hn > 0)
g2_det <- identical(.bytes(file.path(dn1, "W.csv")), .bytes(file.path(dn2, "W.csv")))
say(" - NNDSVDa strict positivity: ", g2_pos,
    " | rerun determinism: ", g2_det)
if (!g2_pos || !g2_det) stop("G2 companion arm failed")

# -----------------------------------------------------------------------------
# result.md
# -----------------------------------------------------------------------------
verdict <- if (all_pass) {
  "VERDICT: PASS -- numerical protocol equivalence on the stable boundary surface; every measured endpoint ratio below the 1e-10 criterion"
} else {
  "VERDICT: FAIL -- at least one endpoint ratio is at or above the 1e-10 criterion"
}

say("")
say("## Endpoint table (criterion |dW|_F/|W_R|_F < 1e-10, |dH|_F/|H_R|_F < 1e-10)")
say("| case | T | relW | relH | obj_final(ours) | verdict |")
say("|---|---|---|---|---|---|")
for (r in rows) say(r)
say("")
say("## Fixed seeds on the record (committed synthetic inputs, kl-crosscheck provenance)")
for (nm in CASES) say(" - ", nm, ": init_seed=", INIT_SEEDS[[nm]],
  " (V seed and construction: tools/kl-crosscheck README/result.md)")
say(" - G2 companion arm: init=nndsvda seed=20261014, case1, 60 iterations")
say("")
say("## Probes")
say(" - injection: ", probe_inj, " | determinism: ", probe_det,
    " | prefix: ", probe_pre, " | batch: ", probe_batch,
    " | g2-positive: ", g2_pos, " | g2-determinism: ", g2_det)
say("")
say(verdict)

result_path <- file.path(TOOL_DIR, "result.md")
writeLines(c(
  "# P1 bit-equivalence gate -- result",
  "",
  paste0("Generated by `Rscript tools/kl-gate-p1/run_gate.R` on ",
         format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), " (single fixed-platform run)."),
  "Regeneration rewrites this file and data/outputs/ verbatim from the",
  "committed synthetic inputs; numerics below are machine-written, never retyped.",
  "",
  report_lines$ls),
  result_path, useBytes = TRUE)
cat("(result.md written: ", result_path, ")\n", sep = "")

if (!all_pass) quit(status = 1L)
quit(status = 0L)
