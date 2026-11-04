#!/usr/local/bin/Rscript
# attest-kernel-capture-f1.R: capture the protocol-1 (F1) face of the
# PERF-P10 attestation bank from a git-sealed era build.
#
# The law (test-kernel-bit-identity.R) is that the working-tree kernel
# reproduces the sealed protocol-1 bytes on the attested geometry. The
# bank it measures against is produced here ONCE, from a binary built
# from a recorded commit, and is then committed; the tests never run
# this tool -- they read the banked bytes. Re-running this tool against
# the recorded era commit must reproduce the banked bytes (the ledger
# says so; the bit-identity law's control says so about the ledger).
#
# Usage (from the repository root):
#   Rscript tools/attest-kernel-geometry.R                    # fa2 bytes
#   # build the era kernel once (worktree of the recorded commit):
#   #   git worktree add /tmp/era-build <era-commit>
#   #   cargo build -p msuiter-engine --bin msuiter-kernel \
#   #       --target-dir /tmp/era-target                    # in /tmp/era-build
#   Rscript tools/attest-kernel-capture-f1.R \
#       --kernel /tmp/era-target/debug/msuiter-kernel --commit <era-commit>
#
# Refuses a kernel that does not announce protocol=1. Writes
# tests/testthat/fixtures/kernel-geometry/f1/** + f1/F1.sha256 +
# PROVENANCE.tsv. No COSMIC bytes: every input face is the committed
# generator recipe replayed through the shared law helper.

args <- as.character(commandArgs(FALSE))
get.arg <- function(flag) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) {
    stop("missing ", flag, " argument (see the tool header)", call. = FALSE)
  }
  args[[i + 1L]]
}
kernel <- get.arg("--kernel")
era.commit <- get.arg("--commit")
if (!file.exists(kernel)) {
  stop("era kernel not found: ", kernel, call. = FALSE)
}

root <- local({
  d <- normalizePath(getwd())
  found <- NA_character_
  while (is.na(found) && nzchar(d)) {
    desc <- file.path(d, "DESCRIPTION")
    if (file.exists(desc) &&
        any(grepl(pattern = "^Package:[[:space:]]*msuiter", x = readLines(
          desc, warn = FALSE)))) found <- d
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  if (is.na(found)) stop("not inside the msuiter repository", call. = FALSE)
  found
})
source(file.path(root, "tests", "testthat", "helper-kernel-pipeline.R"),
       local = FALSE)
source(file.path(root, "tests", "testthat", "helper-kernel-geometry.R"),
       local = FALSE)

hs <- .kpp_exec_real(kernel, "--version")
version.line <- paste(hs$stdout, collapse = " ")
if (!identical(hs$rc, 0L) ||
    !any(grepl(pattern = "protocol=1", x = version.line))) {
  stop("the capture face is protocol-1 only; kernel announced: ",
       version.line, call. = FALSE)
}

# Minimal evidence handle (the capture CREATES the f1 bank .kbg_ev would
# demand; the shared helpers do the geometry work).
fixtures <- file.path(root, "tests", "testthat", "fixtures", "kernel-geometry")
ev0 <- list(counts = file.path(fixtures, "fa2", "counts.csv"),
            banked = file.path(fixtures, "fa2", "COUNTS.sha256"))
if (!all(file.exists(c(ev0$counts, ev0$banked)))) {
  stop("fa2 bytes absent -- run tools/attest-kernel-geometry.R first",
       call. = FALSE)
}

f1.root <- file.path(fixtures, "f1")
unlink(f1.root, recursive = TRUE)
dir.create(f1.root, recursive = TRUE, showWarnings = FALSE)
ledger <- character()

for (t in .kbg_task_defs()) {
  V <- .kbg_task_v(ev0, t)
  in.dir <- .kbg_stage_single(tempfile("f1cap-in-"), V)
  out.dir <- tempfile("f1cap-out-")
  res <- .kpp_exec_real(kernel, .kbg_single_argv(in.dir, out.dir, 96L, 100L,
                                                 t$k, .kbg_iters, t$seed))
  if (!identical(res$rc, 0L)) {
    stop("era fit died: ", t$tag, " rc=", res$rc, ": ",
         paste(res$stderr, collapse = " | "), call. = FALSE)
  }
  dst <- file.path(f1.root, t$tag)
  dir.create(dst, recursive = TRUE, showWarnings = FALSE)
  for (f in c("W.csv", "H.csv", "trace.csv", "meta.csv")) {
    src <- file.path(out.dir, f)
    if (!file.exists(src)) {
      stop("era face did not write ", f, " for ", t$tag, call. = FALSE)
    }
    file.copy(src, file.path(dst, f), overwrite = TRUE)
    rel <- file.path("f1", t$tag, f)
    ledger <- c(ledger, paste0(.kbg_sha(file.path(dst, f)), "  ", rel))
  }
  cat("captured", t$tag, "\n")
}
writeLines(ledger, con = file.path(f1.root, "F1.sha256"))

kernel.sha <- .kbg_sha(kernel)
prov <- c(
  "# kernel-geometry attestation provenance (audit #74 P1-6 re-bank)",
  paste0("era_commit\t", era.commit),
  paste0("era_version\t", version.line),
  paste0("kernel_sha256\t", kernel.sha),
  paste0("capture_utc\t", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
  paste0("iters\t", .kbg_iters),
  "geometry\t96x100 fa2 (tools/attest-kernel-geometry.R recipe)",
  "faces\tfa2-k2..5 seed 123; boot1..4-k2..5 seed 123+b-1 (shared law helper)"
)
writeLines(prov, con = file.path(fixtures, "PROVENANCE.tsv"))
cat("F1 bank written:", length(ledger), "ledger lines under", f1.root, "\n")
