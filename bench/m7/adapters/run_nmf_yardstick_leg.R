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
## Version-tolerant invocation (death #8 forensics 2026-10-16): the 2023-era
## call shape carried keep.rng/backup/silent; the CRAN-current 0.28 brunet
## bootstrap rejects some of those with "unused argument(s)". The load-
## bearing contract -- fixed iterations (maxIter + eps=0), single run, seed --
## lives in the always-passed core; the repair loop drops exactly what the
## method refuses (by message) and the YARDS line attests the drop list.
fm <- names(formals(NMF::nmf))
if (!all(c("x", "rank", "method") %in% fm) && !"..." %in% fm)
  stop("unexpected NMF::nmf signature: ", paste(fm, collapse = ","))
argl <- list(x = V, rank = k, method = "brunet", nrun = 1L, seed = seed,
             maxIter = iters, eps = 0, keep.rng = FALSE,
             backup = 0L, silent = TRUE)
dropped <- character()
res <- NULL
lasterr <- NULL
for (attempt in 1:8) {
  err <- tryCatch({ res <<- do.call(NMF::nmf, argl); NULL },
                  error = function(e) conditionMessage(e))
  if (is.null(err)) break
  hit <- tryCatch(regmatches(err, "unused argument\\(s\\) (.*)$")[[1]],
                  error = function(e) NA_character_)
  offenders <- character()
  if (length(hit) >= 2L && !is.na(hit[2L]) && nzchar(hit[2L])) {
    offenders <- trimws(gsub("[`'‘’]", "",
                             strsplit(hit[2L], ",")[[1L]]))
    offenders <- intersect(offenders, names(argl))
  }
  if (!length(offenders)) { lasterr <- err; break }
  argl[offenders] <- NULL
  dropped <- c(dropped, offenders)
}
if (!is.null(lasterr))
  stop("NMF::nmf refused after argument repair: ", lasterr)
dt <- proc.time()[["total"]] - t0

nIter <- tryCatch(as.integer(niter(res))[1L], error = function(e) -1L)
cat(sprintf("YARDS r_seconds=%.6f r_niter=%d r_version=%s r_dropped=%s\n",
            dt, nIter, vNMF,
            if (length(dropped)) paste(dropped, collapse = "+") else "-"))
