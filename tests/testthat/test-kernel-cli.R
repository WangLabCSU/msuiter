# P1 kernel-extension lane, face (d): the stable batch entry msuiter-kernel
# (src/rust/engine/src/bin/msuiter-kernel.rs) viewed from the R side.
#
# The Rust integration suite tests/kernel_cli_protocol.rs pins the protocol
# against the in-process kernel; this file proves the same binary from the
# R/CI perspective: it builds through the package toolchain, speaks the
# frozen protocol=1 handshake, reproduces the committed goldens for the
# committed synthetic case1 inputs (tools/kl-crosscheck/data/inputs --
# SYNTHETIC fixtures, seeds on the record there; D3: no COSMIC numerics
# involved) -- factor matrices byte-for-byte, the objective column at the
# documented cross-libm tolerance -- reruns byte-identically, and fails
# structured.
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

# Exit status of a system2/system result: the "status" attribute is absent
# on success. The base null-default operator %||% exists only from R 4.4.0
# and this file's floor is the package floor R >= 4.3 (DESCRIPTION
# Depends), where the lookup fails outright -- R CMD check forensics,
# run 38509332600, ubuntu-latest/R 4.3 arm: `could not find function
# "%||%"`. Floor-safe extraction lives here once, used by all three
# invocation helpers.
.kernel_status <- function(res) {
  st <- attr(res, "status")
  if (is.null(st)) 0L else as.integer(st)
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
  if (!identical(.kernel_status(build), 0L)) {
    stop("msuiter-kernel build failed:\n", paste(build, collapse = "\n"))
  }
  # Locate the built executable without platform-name assumptions: cargo
  # emits exactly one of msuiter-kernel / msuiter-kernel.exe per target
  # OS, so probing the filesystem beats branching on any OS-identity
  # string. (String branching failed both ways here: Sys.info()'s
  # "sysname" is not "Windows_NT" -- that value is R.version$os, which is
  # what the original code compared, so windows arms looked for the
  # suffix-less name; and both .Platform$os.type and R.version$os.type
  # measured NULL on the unix runners (mac R 4.5.2), so no OS-string form
  # is falsifiable on every platform while file-existence probing is.
  # Forensics: run 38509332600, both windows arms: "built binary not
  # found at ...msuiter-kernel".)
  cands <- file.path(target, "debug",
    paste0("msuiter-kernel", c(".exe", "")))
  hit <- cands[file.exists(cands)]
  if (!length(hit)) {
    stop("built binary not found under ", file.path(target, "debug"))
  }
  bin <- hit[[1L]]
  .kernel_bin_env$bin <- bin
  bin
}

.kernel_cli <- function(args) {
  bin <- .kernel_bin()
  res <- suppressWarnings(system2(bin, args, stdout = TRUE, stderr = TRUE))
  list(status = .kernel_status(res),
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
  list(status = .kernel_status(res),
       stdout = paste(res, collapse = "\n"),
       stderr = paste(readLines(errf, warn = FALSE), collapse = "\n"))
}

# Full-file raw bytes for byte-identity comparisons (house readBin
# convention: explicit "raw" + size).
.kernel_bytes <- function(p) readBin(p, "raw", file.info(p)$size)

# Cross-platform tolerance for the objective column of the committed
# goldens. The factor surfaces are bit-stable (asserted byte-for-byte); the
# objective accumulates a long transcendental chain and its trailing digits
# move at ulp scale between libm instances. Measured cross-ISA ceiling
# 4.02e-10 (x86_64 container vs arm64 lane, t=142; PR #27 forensics
# 2026-10-14); 1e-8 keeps a 20x safety margin while staying three orders
# below any signal this gate could plausibly miss.
.OBJ_RTOL <- 1e-8

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

test_that("external-init fit under --full-trace reproduces the committed
           goldens (bit-stable factors, tol objective)", {
  indir <- .case1()
  gold  <- .kernel_repo(file.path("tests", "testthat", "fixtures",
    "kernel-cli", "golden_case1_T200"))
  outdir <- file.path(tempdir(), paste0("kernel-cli-golden-", Sys.getpid()))
  unlink(outdir, recursive = TRUE)
  dir.create(outdir, recursive = TRUE)
  out <- .kernel_cli_split(c("fit-kl",
    "--in", indir, "--out", outdir,
    "--m", "96", "--n", "20", "--k", "3", "--iters", "200",
    "--full-trace"))
  on.exit(unlink(outdir, recursive = TRUE))
  expect_identical(out$status, 0L)
  # The factor surfaces are bit-stable across platforms: byte-for-byte
  # against the pinned goldens (raw bytes, -text tree). Cross-ISA verified:
  # x86_64 (ubuntu 24.04 container, rustc 1.75 debug) reproduces the
  # arm64 lane outputs bit-identically (PR #27 guards forensics 2026-10-14).
  for (f in c("W.csv", "H.csv")) {
    got <- .kernel_bytes(file.path(outdir, f))
    want <- .kernel_bytes(file.path(gold, f))
    expect_identical(got, want, info = f)
  }
  # The objective column accumulates a long transcendental chain, so its
  # last digits legitimately drift at ulp scale between libm instances
  # (measured cross-ISA max relative deviation 4.02e-10 at t=142; the
  # iteration count and t column stay exact). Contract: exact structure,
  # tolerance on the numerics -- intra-platform bit-identity is pinned
  # separately by the determinism test below.
  gt <- read.csv(file.path(gold, "trace.csv"))
  ot <- read.csv(file.path(outdir, "trace.csv"))
  expect_identical(ot$t, gt$t)
  expect_true(max(abs(ot$objective / gt$objective - 1)) < .OBJ_RTOL,
               info = "trace objective")
  gm <- read.csv(file.path(gold, "meta.csv"), header = FALSE, row.names = 1L,
                 check.names = FALSE, stringsAsFactors = FALSE)
  om <- read.csv(file.path(outdir, "meta.csv"), header = FALSE, row.names = 1L,
                 check.names = FALSE, stringsAsFactors = FALSE)
  expect_identical(sort(rownames(om)), sort(rownames(gm)))
  desc <- setdiff(rownames(gm), c("obj_init", "obj_final"))
  expect_identical(om[desc, , drop = FALSE], gm[desc, , drop = FALSE])
  for (k in c("obj_init", "obj_final")) {
    expect_true(abs(as.numeric(om[k, 1L]) / as.numeric(gm[k, 1L]) - 1) <
                  .OBJ_RTOL, info = k)
  }
})

test_that("the production face is the endpoints ceremony of the same walk
           (P10-A: header plus t in {0, 200}, trace_len 2, bit-stable
           factors, self-consistent witnesses)", {
  indir <- .case1()
  gold  <- .kernel_repo(file.path("tests", "testthat", "fixtures",
    "kernel-cli", "golden_case1_T200"))
  outdir <- file.path(tempdir(), paste0("kernel-cli-ends-", Sys.getpid()))
  unlink(outdir, recursive = TRUE)
  dir.create(outdir, recursive = TRUE)
  out <- .kernel_cli_split(c("fit-kl",
    "--in", indir, "--out", outdir,
    "--m", "96", "--n", "20", "--k", "3", "--iters", "200"))
  on.exit(unlink(outdir, recursive = TRUE))
  expect_identical(out$status, 0L)
  # The factors of the production face are the goldens byte-for-byte: the
  # observer never feeds the updates, so removing witnesses moves nothing.
  for (f in c("W.csv", "H.csv")) {
    expect_identical(.kernel_bytes(file.path(outdir, f)),
                     .kernel_bytes(file.path(gold, f)), info = f)
  }
  lines <- readLines(file.path(outdir, "trace.csv"), warn = FALSE)
  lines <- lines[nzchar(lines)]
  expect_identical(lines[[1L]], "t,objective")
  expect_identical(length(lines) - 1L, 2L)
  ends <- strsplit(lines[-1L], ",", fixed = TRUE)
  expect_identical(vapply(ends, function(x) x[[1L]], "", USE.NAMES = FALSE),
                   c("0", "200"))
  # Cross-ISA contract: the endpoint witnesses match the golden walk's
  # first and last objective at the documented tolerance (same numerics
  # as the --full-trace face above; intra-platform byte identity of the
  # face switch is pinned in test-kernel-protocol2.R).
  gt <- read.csv(file.path(gold, "trace.csv"))
  for (i in 1:2) {
    got <- as.numeric(ends[[i]][[2L]])
    want <- gt$objective[[if (i == 1L) 1L else nrow(gt)]]
    expect_true(abs(got / want - 1) < .OBJ_RTOL, info = paste0("t", i))
  }
  meta <- strsplit(readLines(file.path(outdir, "meta.csv"), warn = FALSE),
                   ",", fixed = TRUE)
  field <- function(key) {
    hit <- meta[vapply(meta, function(x) identical(x[[1L]], key), logical(1L),
                       USE.NAMES = FALSE)]
    expect_identical(length(hit), 1L)
    hit[[1L]][[2L]]
  }
  expect_identical(field("trace_len"), "2")
  # Self-consistency law: trace rows and meta witnesses are the SAME
  # {:.17e} renderings of the SAME doubles -- byte-equal on every
  # platform, tolerance-free.
  expect_identical(ends[[1L]][[2L]], field("obj_init"))
  expect_identical(ends[[2L]][[2L]], field("obj_final"))
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
