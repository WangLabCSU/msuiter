# P1 kernel-extension lane, face (d): the stable batch entry msuiter-kernel
# (src/rust/engine/src/bin/msuiter-kernel.rs) viewed from the R side.
#
# The Rust integration suite tests/kernel_cli_protocol.rs pins the protocol
# against the in-process kernel; this file proves the same binary from the
# R/CI perspective: it builds through the package toolchain, speaks the
# frozen protocol=1 handshake, reproduces committed byte-pinned goldens for
# the committed synthetic case1 inputs (tools/kl-crosscheck/data/inputs --
# SYNTHETIC fixtures, seeds on the record there; D3: no COSMIC numerics
# involved), reruns byte-identically, and fails structured.
#
# Repository-only by nature (the binary builds from src/rust sources):
# gated on .ms_root locatable + cargo present, never on an accidental
# miss -- same discipline as test-docs-sync.R / helper-check-layout.R.
# Pinned goldens live under tests/testthat/fixtures/kernel-cli/** which
# .gitattributes keeps at raw bytes (-text; PR #26 Windows CRLF law).

.kernel_repo <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    # In a locatable repo checkout these are committed content: absence is
    # a gate failure (an unbuilt/never-produced surface must not masquerade
    # as a passing audit), never a skip.
    stop(paste0("required committed file missing: ", rel), call. = FALSE)
  }
  f
}

.kernel_have_cargo <- function() {
  tool <- Sys.which("cargo")
  nzchar(tool) && !is.na(tool)
}

# Build (once per test-file session) and locate the stable batch entry.
.kernel_bin_env <- new.env(parent = emptyenv())
.kernel_bin <- function() {
  if (!is.null(.kernel_bin_env$bin)) return(.kernel_bin_env$bin)
  if (!.kernel_have_cargo()) skip("cargo not available on PATH")
  manifest <- .kernel_repo(file.path("src", "rust", "Cargo.toml"))
  target <- Sys.getenv("MSUITER_KERNEL_TARGET_DIR", NA_character_)
  if (is.na(target) || !nzchar(target)) {
    target <- file.path(dirname(manifest), "target")
  }
  build <- system2("cargo",
    c("build", "--quiet", "--manifest-path", manifest,
      "--target-dir", target, "--package", "msuiter-engine",
      "--bin", "msuiter-kernel"),
    stdout = TRUE, stderr = TRUE)
  if (!identical(attr(build, "status") %||% 0L, 0L)) {
    stop("msuiter-kernel build failed:\n", paste(build, collapse = "\n"))
  }
  exe <- paste0("msuiter-kernel",
    if (identical(Sys.info()[["sysname"]], "Windows_NT")) ".exe" else "")
  bin <- file.path(target, "debug", exe)
  if (!file.exists(bin)) stop("built binary not found at ", bin)
  .kernel_bin_env$bin <- bin
  bin
}

.kernel_cli <- function(args) {
  bin <- .kernel_bin()
  res <- suppressWarnings(system2(bin, args, stdout = TRUE, stderr = TRUE))
  list(status = attr(res, "status") %||% 0L,
       stdout = paste(res, collapse = "\n"),
       stderr = "")
}

# Run the CLI with separated stderr (system2 merges stderr into the result
# when both share the pipe -- keep them apart for exit-path tests).
.kernel_cli_split <- function(args) {
  bin <- .kernel_bin()
  errf <- tempfile("kernel-cli-stderr")
  res <- suppressWarnings(system2(bin, args, stdout = TRUE,
    stderr = errf))
  list(status = attr(res, "status") %||% 0L,
       stdout = paste(res, collapse = "\n"),
       stderr = paste(readLines(errf, warn = FALSE), collapse = "\n"))
}

# Full-file raw bytes for byte-identity comparisons (house readBin
# convention: explicit "raw" + size).
.kernel_bytes <- function(p) readBin(p, "raw", file.info(p)$size)

# ---------------------------------------------------------------------------
# Committed synthetic case (kl-crosscheck case1; all input CSVs tracked).
# ---------------------------------------------------------------------------
.case1 <- function() .kernel_repo(file.path("tools", "kl-crosscheck",
  "data", "inputs", "case1"))

test_that("msuiter-kernel announces the frozen protocol=1 handshake", {
  out <- .kernel_cli("--version")
  expect_identical(out$status, 0L)
  expect_match(out$stdout, "protocol=1")
  expect_match(out$stdout, "msuiter-kernel")
  expect_match(out$stdout, "kl_eps=1e-12")
})

test_that("external-init fit reproduces the committed byte-pinned goldens", {
  indir <- .case1()
  gold  <- .kernel_repo(file.path("tests", "testthat", "fixtures",
    "kernel-cli", "golden_case1_T200"))
  outdir <- file.path(tempdir(), paste0("kernel-cli-golden-", Sys.getpid()))
  unlink(outdir, recursive = TRUE)
  dir.create(outdir, recursive = TRUE)
  out <- .kernel_cli_split(c("fit-kl",
    "--in", indir, "--out", outdir,
    "--m", "96", "--n", "20", "--k", "3", "--iters", "200"))
  on.exit(unlink(outdir, recursive = TRUE))
  expect_identical(out$status, 0L)
  # Byte-for-byte against the pinned goldens (raw bytes, -text tree).
  for (f in c("W.csv", "H.csv", "trace.csv", "meta.csv")) {
    got <- .kernel_bytes(file.path(outdir, f))
    want <- .kernel_bytes(file.path(gold, f))
    expect_identical(got, want, info = f)
  }
})

test_that("two runs of the same case are byte-identical (boundary determinism)", {
  indir <- .case1()
  dirs <- file.path(tempdir(), paste0("kernel-cli-det-", Sys.getpid(), "-", 1:2))
  unlink(dirs, recursive = TRUE)
  for (d in dirs) dir.create(d, recursive = TRUE)
  on.exit(unlink(dirs, recursive = TRUE))
  for (d in dirs) {
    out <- .kernel_cli_split(c("fit-kl",
      "--in", indir, "--out", d,
      "--m", "96", "--n", "20", "--k", "3", "--iters", "50"))
    expect_identical(out$status, 0L)
  }
  for (f in c("W.csv", "H.csv", "trace.csv", "meta.csv")) {
    expect_identical(.kernel_bytes(file.path(dirs[1], f)),
                     .kernel_bytes(file.path(dirs[2], f)), info = f)
  }
})

test_that("nndsvda arm is strictly positive and self-describing in meta", {
  skip_if(!.kernel_have_cargo(), "cargo not available")
  indir <- .case1()
  outdir <- file.path(tempdir(), paste0("kernel-cli-nnda-", Sys.getpid()))
  unlink(outdir, recursive = TRUE)
  dir.create(outdir, recursive = TRUE)
  on.exit(unlink(outdir, recursive = TRUE))
  out <- .kernel_cli_split(c("fit-kl",
    "--in", indir, "--out", outdir,
    "--m", "96", "--n", "20", "--k", "3", "--iters", "60",
    "--init", "nndsvda", "--seed", "20261014"))
  expect_identical(out$status, 0L)
  as.mat <- function(f) {
    d <- read.csv(file.path(outdir, f), header = FALSE, colClasses = "numeric")
    as.matrix(d)
  }
  W <- as.mat("W.csv"); H <- as.mat("H.csv")
  expect_true(all(W > 0), info = "nndsvda W lost strict positivity")
  expect_true(all(H > 0), info = "nndsvda H lost strict positivity")
  meta <- paste(readLines(file.path(outdir, "meta.csv"), warn = FALSE),
    collapse = "\n")
  expect_match(meta, "init,nndsvda")
  expect_match(meta, "seed,20261014")
  expect_match(meta, "protocol,1")
})

test_that("missing initializer fails structured (exit 2, error: line)", {
  indir <- .case1()
  broken <- file.path(tempdir(), paste0("kernel-cli-broken-", Sys.getpid()))
  dir.create(broken, recursive = TRUE)
  on.exit(unlink(broken, recursive = TRUE))
  file.copy(file.path(indir, "V.csv"), file.path(broken, "V.csv"),
    overwrite = TRUE)
  outdir <- file.path(broken, "out")
  out <- .kernel_cli_split(c("fit-kl",
    "--in", broken, "--out", outdir,
    "--m", "96", "--n", "20", "--k", "3", "--iters", "10"))
  expect_identical(out$status, 2L)
  expect_match(out$stderr, "^error:")
  expect_match(out$stderr, "W0.csv")
})
