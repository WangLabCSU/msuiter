# Shared apparatus for the P2 kernel-pipeline TDD family
# (test-kernel-pipeline-status.R / -parse.R / -batch.R / -farm.R).
#
# Test-side only: nothing here ships in R/. The family drives the certified
# batch entry msuiter-kernel --cases (src/rust/engine/src/bin/msuiter-kernel.rs)
# against synthetic fixtures only (D3: every numeric here is generated from
# a set seed on the record; no COSMIC bytes anywhere) and swaps the msuiter
# exec seam through assignInNamespace -- the house mock idiom.
#
# Deliberate divergence from test-kernel-cli.R: this family NEVER reads an
# exit status from an attribute. system2's returned VALUE is the only status
# source (.kpp_bin below checks the cargo build status by value); attribute
# readings may corroborate or falsify, never source. The attribute-only
# pattern is reproduced exactly once, as .kpp_naive_status, solely to
# characterize the hazard class the governance gate closes.

.kpp_have_cargo <- function() {
  tool <- Sys.which("cargo")
  length(tool) > 0L && !is.na(tool[[1L]]) && nzchar(tool[[1L]])
}

# Build (once per test session) and locate the certified batch entry.
# Value-based build status: a failing cargo build stops here with its own
# transcript -- never a fallthrough to a "binary not found" proxy error.
.kpp_bin_env <- new.env(parent = emptyenv())
.kpp_bin <- function() {
  if (!is.null(.kpp_bin_env$bin)) return(.kpp_bin_env$bin)
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  manifest <- file.path(.ms_root, "src", "rust", "Cargo.toml")
  if (!file.exists(manifest)) {
    stop("required committed file missing: src/rust/Cargo.toml", call. = FALSE)
  }
  target <- Sys.getenv("MSUITER_KERNEL_TARGET_DIR", NA)
  if (is.na(target) || !nzchar(target)) {
    target <- file.path(dirname(manifest), "target")
  }
  if (!.kpp_have_cargo()) skip("cargo not available on PATH")
  # File-mode capture with the exit status taken from the system2 VALUE.
  # (This host's renamed-R build drops system2 output text in every capture
  # mode -- probes banked at /tmp/perf2lane/logs/system2_modes_probe.txt;
  # the value channel is intact in file/inherit modes, and on the campaign
  # platforms the file capture delivers the text. The family therefore
  # never asserts real-capture text; stderr-quoting templates are pinned
  # through the mock seam, see G3.)
  b.out <- tempfile("kpp-build-out-")
  b.err <- tempfile("kpp-build-err-")
  rc <- suppressWarnings(system2(
    "cargo",
    c("build", "--quiet", "--manifest-path", manifest,
      "--target-dir", target, "--package", "msuiter-engine",
      "--bin", "msuiter-kernel"),
    stdout = b.out, stderr = b.err))
  rc <- suppressWarnings(as.integer(rc))
  if (is.na(rc) || !identical(rc, 0L)) {
    transcript <- c(
      if (file.exists(b.out)) readLines(b.out, warn = FALSE) else "(empty)",
      if (file.exists(b.err)) readLines(b.err, warn = FALSE) else "(empty)")
    stop("msuiter-kernel build failed (status ", rc, "):\n",
         paste(transcript, collapse = "\n"), call. = FALSE)
  }
  # File-existence probing, never OS-identity strings (see test-kernel-cli.R).
  cands <- file.path(target, "debug", paste0("msuiter-kernel", c(".exe", "")))
  hit <- cands[file.exists(cands)]
  if (!length(hit)) {
    stop("built binary not found under ", file.path(target, "debug"),
         call. = FALSE)
  }
  .kpp_bin_env$bin <- hit[[1L]]
  hit[[1L]]
}

## ---- synthetic fixture builders (D3-safe) --------------------------------

# Small deterministic non-negative input matrix; seed on the record.
.kpp_fixture_v <- function(seed = 7L, m = 8L, n = 6L) {
  set.seed(as.integer(seed))
  matrix(runif(as.integer(m) * as.integer(n)) * 4,
         nrow = as.integer(m), ncol = as.integer(n))
}

# The frozen input grid: one %.17e row per matrix row, comma-separated
# (verbatim .rust_csv_rows semantics of the protocol-1 contract).
.kpp_grid <- function(mat) {
  apply(mat, 1L, function(r) paste(sprintf("%.17e", r), collapse = ","))
}

# Stage INROOT/<case>/V.csv exactly as the batch face expects to find it.
.kpp_stage_case <- function(in.root, case, V) {
  dir <- file.path(in.root, case)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(.kpp_grid(V), con = file.path(dir, "V.csv"))
  dir
}

# The frozen cases-manifest header, verbatim (BATCH_HEADER of the bin).
.kpp_batch_header <- "case,init,seed,replicate,iters,m,n,k"

.kpp_write_manifest <- function(path, rows) {
  writeLines(c(.kpp_batch_header, rows), con = path)
  path
}

.kpp_batch_argv <- function(manifest, in.root, out.root) {
  c("fit-kl", "--cases", manifest, "--root", in.root,
    "--out-root", out.root)
}

# Resolve one required name from the msuiter namespace. Absent binding is
# an EXPLICIT red (a named TDD-red stop), never a silent pass: the family
# must not certify a surface it cannot reach.
.kpp_surface <- function(name) {
  ns <- tryCatch(asNamespace("msuiter"), error = function(e) NULL)
  if (is.null(ns)) stop("msuiter namespace not loaded", call. = FALSE)
  if (!exists(name, envir = ns, inherits = FALSE)) {
    stop(paste0("TDD red: pipeline surface '", name,
                "' is not implemented yet"), call. = FALSE)
  }
  get(name, envir = ns)
}

# A fully valid one-case batch scenario (the mock-seam tests drive the
# consumer surface against this while the seam itself is mocked).
.kpp_valid_scenario <- function(case = "kp-batch", seed = 11L,
                                m = 8L, n = 6L, k = 2L, iters = 12L) {
  bin <- .kpp_bin()
  in.root <- tempfile("kpp-valid-in-")
  out.root <- tempfile("kpp-valid-out-")
  dir.create(in.root, recursive = TRUE, showWarnings = FALSE)
  .kpp_stage_case(in.root, case, .kpp_fixture_v(seed = seed, m = m, n = n))
  manifest <- .kpp_write_manifest(
    file.path(in.root, "cases.csv"),
    paste0(case, ",nndsvd,", seed, ",,", iters, ",", m, ",", n, ",", k))
  list(bin = bin, in.root = in.root, out.root = out.root,
       manifest = manifest, case = case, m = as.integer(m),
       n = as.integer(n), k = as.integer(k), iters = as.integer(iters),
       case.out = file.path(out.root, case, "out"))
}


## ---- the real exec, status by VALUE ---------------------------------------

# One real batch invocation: stdout/stderr to files, the system2 RETURNED
# VALUE captured as the status. Returns list(rc, stdout, stderr).
.kpp_exec_real <- function(bin, argv) {
  out.f <- tempfile("kpp-out-")
  err.f <- tempfile("kpp-err-")
  rc <- suppressWarnings(system2(bin, argv, stdout = out.f, stderr = err.f))
  rc <- suppressWarnings(as.integer(rc))
  if (is.na(rc)) {
    stop("system2 returned no usable exit-status value", call. = FALSE)
  }
  out <- if (file.exists(out.f))
    readLines(out.f, warn = FALSE) else character()
  err <- if (file.exists(err.f))
    readLines(err.f, warn = FALSE) else character()
  list(rc = rc, stdout = out, stderr = err)
}

## ---- the batch-death scenario ---------------------------------------------

# A two-case batch on the certified batch face: row 1 is a fully valid case
# whose outputs land in OUTROOT/kp-good/out/, row 2 carries a faulty init
# token, so the all-or-nothing batch aborts at the first faulty row with
# exit status 2 AFTER the residue of row 1 was written. This is the exact
# "kernel death with parsable residue" surface the governance gate targets.
.kpp_death_scenario <- function(m = 8L, n = 6L, k = 2L, iters = 12L) {
  bin <- .kpp_bin()
  in.root <- tempfile("kpp-death-in-")
  out.root <- tempfile("kpp-death-out-")
  dir.create(in.root, recursive = TRUE, showWarnings = FALSE)
  V <- .kpp_fixture_v(m = m, n = n)
  .kpp_stage_case(in.root, "kp-good", V)
  manifest <- .kpp_write_manifest(
    file.path(in.root, "cases.csv"),
    c(paste0("kp-good,nndsvd,11,,", iters, ",", m, ",", n, ",", k),
      paste0("kp-dead,bogus,12,,", iters, ",", m, ",", n, ",", k)))
  res <- .kpp_exec_real(bin, .kpp_batch_argv(manifest, in.root, out.root))
  list(bin = bin, in.root = in.root, out.root = out.root,
       manifest = manifest, m = as.integer(m), n = as.integer(n),
       k = as.integer(k), iters = as.integer(iters),
       rc = res$rc, stdout = res$stdout, stderr = res$stderr,
       good.out = file.path(out.root, "kp-good", "out"))
}

# Does the residue parse as a complete, valid protocol-1 output set?
# Self-contained reference read (dimension, finiteness, non-negativity,
# trace shape, meta key count) -- the property the silent-consumer hazard
# hinges on: the residue PARSES CLEAN even though the batch died.
.kpp_parses_clean <- function(case.out, m, n, k, iters) {
  ok <- TRUE
  read.grid <- function(path, rows, cols) {
    if (!file.exists(path)) return(NULL)
    lines <- readLines(path, warn = FALSE)
    lines <- lines[nzchar(lines)]
    if (!identical(length(lines), as.integer(rows))) return(NULL)
    fields <- strsplit(lines, ",", fixed = TRUE)
    if (!all(lengths(fields) == as.integer(cols))) return(NULL)
    vals <- suppressWarnings(as.numeric(unlist(fields, use.names = FALSE)))
    if (!all(is.finite(vals)) || any(vals < 0)) return(NULL)
    vals
  }
  ok <- ok && !is.null(read.grid(file.path(case.out, "W.csv"), m, k))
  ok <- ok && !is.null(read.grid(file.path(case.out, "H.csv"), k, n))
  trace.path <- file.path(case.out, "trace.csv")
  if (!file.exists(trace.path)) return(FALSE)
  tl <- readLines(trace.path, warn = FALSE)
  tl <- tl[nzchar(tl)]
  ok <- ok && identical(tl[[1L]], "t,objective")
  ok <- ok && identical(length(tl) - 1L, as.integer(iters) + 1L)
  tv <- suppressWarnings(as.numeric(unlist(
    strsplit(tl[-1L], ",", fixed = TRUE), use.names = FALSE)))
  ok <- ok && all(is.finite(tv))
  meta.path <- file.path(case.out, "meta.csv")
  if (!file.exists(meta.path)) return(FALSE)
  ml <- readLines(meta.path, warn = FALSE)
  ok <- ok && length(ml[nzchar(ml)]) >= 15L
  isTRUE(ok)
}

## ---- the hazard characterization (documented defect, used ONLY as data) --

# Verbatim shape of the attribute-only status extraction found in the wild
# (the .rust_status pattern of the frozen bridge, and the .kernel_status
# helper of test-kernel-cli.R): it reads attr(res, "status") and nothing
# else. On unix system2 NEVER sets that attribute, so EVERY real death --
# including one whose residue parses clean -- classifies as success. The
# governance units assert this misclassification explicitly; it is the
# banked red proof of the hazard class, not a pattern any shipping or
# test-side consumer is allowed to source status from.
.kpp_naive_status <- function(res) {
  st <- attr(res, "status")
  if (is.null(st)) 0L else as.integer(st)
}

## ---- mock seam factory -----------------------------------------------------

# The mocked seam still serves the protocol-1 handshake (the batch runner
# handshakes once per call through the very seam being mocked), while the
# batch invocation itself is routed to the scenario's batch.fn.
.kpp_version_result <- function() {
  res <- 0L
  attr(res, "stdout") <-
    'msuiter-kernel protocol=1 engine="msuiter-engine" kl_eps=1e-12'
  attr(res, "stderr") <- character()
  res
}

.kpp_mock <- function(batch.fn) {
  function(bin, args) {
    if (any(args == "--version")) return(.kpp_version_result())
    batch.fn(bin, args)
  }
}

## ---- exec-seam swapping (house assignInNamespace idiom) --------------------

# Swap msuiter:::kp_exec for the duration of `expr`; restore the original
# binding on exit (error path included). The block is evaluated in the
# CALLER frame so assignments made inside it remain visible to the unit.
# An absent binding (pre-green) is a HARD error, never a silent skip: the
# family must not pass by missing its own subject.
.kpp_with_exec <- function(mock, expr) {
  expr <- substitute(expr)
  env <- parent.frame(1L)
  ns <- tryCatch(asNamespace("msuiter"), error = function(e) NULL)
  if (is.null(ns)) stop("msuiter namespace not loaded", call. = FALSE)
  if (!exists("kp_exec", envir = ns, inherits = FALSE)) {
    stop("exec seam kp_exec absent -- the pipeline module is not loaded",
         call. = FALSE)
  }
  old <- get("kp_exec", envir = ns)
  unlockBinding("kp_exec", env = ns)
  on.exit(eval(expr, envir = env), add = TRUE)
  on.exit({
    assign("kp_exec", old, envir = ns)
    lockBinding("kp_exec", env = ns)
  }, add = TRUE)
  assign("kp_exec", mock, envir = ns)
  invisible(NULL)
}
