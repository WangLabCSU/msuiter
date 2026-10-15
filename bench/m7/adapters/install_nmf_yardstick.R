## ---------------------------------------------------------------------------
## install_nmf_yardstick.R -- seventh-image R-face provisioning (death #8)
##
## The CRAN-only install.packages("NMF") layer died: "dependency 'Biobase'
## is not available". Biobase is Bioconductor-class and exists on no CRAN
## tree (probes 3/6, recorded in install_sigminer.R); the load-bearing
## source on this mirror is the pinned contrib host below -- the same one
## that served the arm trees' Biobase class. R's own repo machinery fetches
## ZERO rows from that host (measured 2026-10-16), so the index is read by
## hand and every node is installed from its index-spelled tarball, the arm
## resolver's idiom: per-URL retries against the recorded proxy flakiness
## (§9b), the warning channel as the install verdict, and the library's own
## DESCRIPTION as the final say.
##
## VERSION GATES: the resolved pair is gated to NMF 0.28 / Biobase 2.60.0
## (BiocGenerics 0.46.0 under it). CRAN-current drift is a build death,
## never a silent remeasure -- a re-bake reproduces the attested pair or
## stops loudly. The 3.17-core Biobase (1.x era) 404s on this host; the
## contrib-era Biobase 2.60.0 (Depends R >= 2.10, Imports: methods) is the
## pair the brunet reference completes against, measured end-to-end (5-
## iteration network-none fits) before this script was written.
## ---------------------------------------------------------------------------
options(repos = c(CRAN = "https://cran.r-project.org"))
BIOC_CONTRIB <- "https://bioconductor.org/packages/3.17/bioc/src/contrib"
MAX_TRY <- 8L                                             # §9b flakiness
GATE_NMF <- "0.28"
GATE_BIOBASE <- "2.60.0"
GATE_BIOCGENERICS <- "0.46.0"

paste0 <- function(..., collapse = NULL) {       # 4.3 base has none; safe
  a <- list(...)                                 # with caller-supplied collapse
  if (is.null(collapse)) do.call(paste, c(a, list(sep = "")))
  else do.call(paste, c(a, list(sep = "", collapse = collapse)))
}
say <- function(...) cat(sprintf(...), "\n", sep = "")
die <- function(...) {
  cat("[yardstick-provision] FATAL ", sprintf(...), "\n", sep = "")
  quit(status = 1L)
}

verOf <- function(pkg) {                     # DESCRIPTION Version, direct scan
  for (l in .libPaths()) { d <- file.path(l, pkg, "DESCRIPTION")
    if (file.exists(d)) {
      ln <- readLines(d, warn = FALSE)
      i <- grepl("^Version:", ln)
      if (any(i)) return(trimws(sub("^Version:", "", ln[which(i)[1]])))
    } }
  NULL
}

got <- function(url, dest) {
  for (t in seq_len(MAX_TRY)) {
    ok <- tryCatch({ suppressWarnings(download.file(url, dest, quiet = TRUE))
                     file.exists(dest) && file.size(dest) > 50L },
                   error = function(e) FALSE)
    if (isTRUE(ok)) return(TRUE)
    Sys.sleep(2)
  }
  FALSE
}

## Recorded install verdict channel (install_sigminer.R, deparse capture):
## the success path returns NULL silently; failure surfaces ONLY as the
## "non-zero exit status" warning. The library DESCRIPTION is then asked.
warnInstall <- function(tf) {
  warn <- NULL
  st <- tryCatch({
    withCallingHandlers(
      suppressMessages(install.packages(tf, repos = NULL, type = "source",
                                       dependencies = NA, quiet = TRUE)),
      warning = function(w) {
        m <- conditionMessage(w)
        if (grepl("non-zero exit status", m, fixed = TRUE)) warn <<- m
        invokeRestart("muffleWarning") })
    if (is.null(warn)) "OK" else substr(warn, 1L, 160L)
  }, error = function(e) paste0("ERR: ", conditionMessage(e)))
  st
}

## ---------------------------------------------------------------- contrib db
## Hand-read PACKAGES.gz: R's repository index machinery fetches zero rows
## from this host (the reason install_sigminer.R parses the index itself).
parsePkgDcf <- function(gzpath, fields) {
  txt <- readLines(gzfile(gzpath), warn = FALSE)
  recs <- split(txt, cumsum(txt == ""))
  out <- list()
  for (f in fields) out[[f]] <- character()
  getf <- function(r, k) {
    hit <- grepl(paste0("^", k, ":"), r)
    if (!any(hit)) return(NA_character_)
    i <- which(hit)[1]
    v <- trimws(sub(paste0("^", k, ":"), "", r[i]))
    if (i < length(r)) {
      j <- i + 1L
      while (j <= length(r) && grepl("^[ \t]", r[j])) {
        v <- paste0(v, " ", trimws(r[j])); j <- j + 1L }
    }
    v
  }
  for (r in recs) {
    p <- getf(r, "Package")
    if (is.na(p) || !nzchar(p)) next
    for (f in fields) out[[f]] <- c(out[[f]], getf(r, f))
  }
  out
}

tf <- tempfile(fileext = ".gz")
if (!got(paste0(BIOC_CONTRIB, "/PACKAGES.gz"), tf))
  die("contrib PACKAGES.gz unreachable after %d tries", MAX_TRY)
db <- parsePkgDcf(tf, c("Package", "Version", "Imports", "Depends"))
n <- length(db[["Package"]])
if (n < 2000L) die("contrib index looks truncated (%d records)", n)
say("[yardstick-provision] contrib index: %d packages", n)

getf <- function(col, p) { i <- which(db[["Package"]] == p)
                           if (!length(i)) NULL else col[i[1]] }

installBioc <- function(pkg, gate) {
  v <- getf(db[["Version"]], pkg)
  if (is.null(v)) die("%s is not in the contrib index", pkg)
  if (!identical(v, gate))
    die("%s index version %s drifts from the gate %s", pkg, v, gate)
  tb <- tempfile(fileext = ".tar.gz")
  url <- paste0(BIOC_CONTRIB, "/", pkg, "_", v, ".tar.gz")
  if (!got(url, tb)) die("tarball unreachable: %s", url)
  st <- warnInstall(tb)
  got_v <- verOf(pkg)
  if (!identical(st, "OK") || !identical(got_v, gate))
    die("%s install not result-gated: %s (library reports %s)",
        pkg, st, if (is.null(got_v)) "(none)" else got_v)
  say("[yardstick-provision] %s %s installed (result-gated)", pkg, got_v)
}

## deps-first: BiocGenerics under Biobase (the measured contrib closure;
## Biobase 2.60.0 Depends BiocGenerics >= 0.27.1, Imports methods)
installBioc("BiocGenerics", GATE_BIOCGENERICS)
installBioc("Biobase", GATE_BIOBASE)

## Biobase/BiocGenerics CRAN-side Imports closure, from the index bytes
fields <- unique(unlist(lapply(c("Biobase", "BiocGenerics"), function(p) {
  s <- c(getf(db[["Imports"]], p), getf(db[["Depends"]], p))
  trimws(gsub("\\(.*\\)", "", strsplit(paste0(unlist(s), collapse = ","),
                ",")[[1L]]))
})))
base <- c("", "R", "methods", "utils", "stats", "tools", "graphics",
          "grDevices", "splines", "stats4", "parallel", "compiler")
need <- setdiff(setdiff(fields, base), c("BiocGenerics", "Biobase"))
need <- need[vapply(need, function(p) is.null(verOf(p)),
                    FUN.VALUE = TRUE, USE.NAMES = FALSE)]
if (length(need)) {
  st <- local({
    ## CRAN closure install through the same warning-channel discipline
    warn <- NULL
    tryCatch({
      withCallingHandlers(
        suppressMessages(install.packages(need,
                                        repos = "https://cran.r-project.org",
                                        quiet = TRUE)),
        warning = function(w) {
          m <- conditionMessage(w)
          if (grepl("non-zero exit status", m, fixed = TRUE)) warn <<- m
          invokeRestart("muffleWarning") })
      if (is.null(warn)) "OK" else substr(warn, 1L, 160L)
    }, error = function(e) paste0("ERR: ", conditionMessage(e)))
  })
  missing <- need[vapply(need, function(p) is.null(verOf(p)),
                         FUN.VALUE = TRUE, USE.NAMES = FALSE)]
  if (!identical(st, "OK") || length(missing))
    die("CRAN-side Biobase imports unresolved: %s (%s)",
        paste0(missing, collapse = ","), st)
  say("[yardstick-provision] CRAN-side closure: %s", paste0(need, collapse = ","))
}

## ---------------------------------------------------------------- NMF face
## The reference core the paper measures against. CRAN, version-gated.
st <- local({
  warn <- NULL
  tryCatch({
    withCallingHandlers(
      suppressMessages(install.packages("NMF", quiet = TRUE)),
      warning = function(w) {
        m <- conditionMessage(w)
        if (grepl("non-zero exit status", m, fixed = TRUE)) warn <<- m
        invokeRestart("muffleWarning") })
    if (is.null(warn)) "OK" else substr(warn, 1L, 160L)
  }, error = function(e) paste0("ERR: ", conditionMessage(e)))
})
nv <- verOf("NMF")
if (is.null(nv)) {                       # one recorded-flakiness replay
  Sys.sleep(3)
  st <- local({
    warn <- NULL
    tryCatch({
      withCallingHandlers(
        suppressMessages(install.packages("NMF", quiet = TRUE)),
        warning = function(w) {
          m <- conditionMessage(w)
          if (grepl("non-zero exit status", m, fixed = TRUE)) warn <<- m
          invokeRestart("muffleWarning") })
      if (is.null(warn)) "OK" else substr(warn, 1L, 160L)
    }, error = function(e) paste0("ERR: ", conditionMessage(e)))
  })
  nv <- verOf("NMF")
}
if (!identical(st, "OK") || is.null(nv) || !identical(nv, GATE_NMF))
  die("NMF install not result-gated: st=%s library=%s (gate %s)",
      st, if (is.null(nv)) "(none)" else nv, GATE_NMF)
bv <- verOf("Biobase")
if (!identical(bv, GATE_BIOBASE))
  die("Biobase gate broken after NMF install: %s",
      if (is.null(bv)) "(none)" else bv)

## Load gate: the reference core must ATTACH (its Imports closure is real)
## and complete the fixed-iteration brunet contract with nothing but base
## facilities -- the same assertion the image's network-none witness makes.
ok <- tryCatch({
  suppressMessages(library(NMF))
  set.seed(1L)
  v <- matrix(abs(rnorm(24)), 6)
  r <- NMF::nmf(v, 2L, method = "brunet", nrun = 1L, seed = 1L,
                maxIter = 5L, eps = 0)
  is(r, "NMFfit") && identical(NMF::niter(r), 5L)
}, error = function(e) {
  cat("[yardstick-provision] brunet load-gate error: ",
      conditionMessage(e), "\n", sep = ""); FALSE })
if (!isTRUE(ok)) die("brunet load gate did not complete")
say("[yardstick-provision] NMF %s + Biobase %s (BiocGenerics %s) provisioned, brunet load gate ok",
    nv, bv, verOf("BiocGenerics"))
