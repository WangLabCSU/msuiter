#!/usr/bin/env Rscript
## R leg of the rust-NMF yardstick (manifest :42): NMF::nmf(brunet) on the
## committed fixture, fixed-iteration wall over proc.time. The python parent
## (run_nmf_yardstick.py) brackets the rust core the same way; the two
## YARDS numbers plus each side's own iteration attestation are the whole
## comparison. Base-R 4.3-safe operators only (R-floor platform-premise law:
## no 4.4+-only base operators, no native pipe, no grepl keyword args..

argv <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default) {
  i <- which(argv == flag)
  if (length(i) == 0L) default else argv[[i[1L] + 1L]]
}
matrixPath <- getArg("--matrix", "")
if (!nzchar(matrixPath)) stop("--matrix is required")
k <- as.integer(getArg("--k", "2"))
iters <- as.integer(getArg("--iters", "2000"))
seed <- as.integer(getArg("--seed", "1234"))

suppressMessages(suppressWarnings(library(NMF)))
vNMF <- as.character(utils::packageVersion("NMF"))
if (is.na(vNMF) || is.null(vNMF)) vNMF <- "(unknown)"

V <- as.matrix(read.csv(matrixPath, header = FALSE, row.names = NULL))
storage.mode(V) <- "double"
V <- abs(V)   ## NMF enforces non-negativity; the fixture is Poisson, so this
              ## is a no-op belt, not a repair

set.seed(seed)
t0 <- proc.time()[["total"]]
res <- NMF::nmf(V, k, method = "brunet", nrun = 1L, seed = seed,
                maxIter = iters, eps = 0, keep.rng = FALSE,
                backup = 0L, silent = TRUE)
dt <- proc.time()[["total"]] - t0

nIter <- tryCatch(as.integer(niter(res))[1L], error = function(e) -1L)
cat(sprintf("YARDS r_seconds=%.6f r_niter=%d r_version=%s\n",
            dt, nIter, vNMF))
