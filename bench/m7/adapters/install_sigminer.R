#!/usr/bin/env Rscript
## install_sigminer.R — M7 sigminer image: whole-tree Archive-aware installer.
##
## Recorded slice-2 direction (design memo 2026-10-08 §9b closure final
## paragraph): every transitive dependency of sigminer 2.3.1 resolves through
## CRAN's contrib AND Archive trees with per-package fallback —
## contrib -> Archive/<pkg>/<pkg>_<ver>.tar.gz -> Archive/<pkg>_<ver>.tar.gz —
## with name-case candidates [db-canonical | aliases | as-written | lowercase |
## capitalized] and per-URL retries (the recorded proxy flakiness, memo §9b
## item 1: intermittent 502/SSL-connect errors on otherwise-live URLs). The
## Bioconductor-class Imports (maftools, Rhtslib) exist on no CRAN tree —
## probe3/probe6 2026-10-08 — and resolve through the pinned bioc 3.17
## contrib the recorded build already compiled against (lowest-priority
## source; memo §8 package-fetch idiom, §5 governs image pulls only).
##
## Why not the install.packages("pkg==ver") style of the frozen recipe: the
## 2026-10-08 slice-2 probe recorded that this base R (4.3.3) looks a
## "==spec" string up VERBATIM AS A PACKAGE NAME — "package
## 'sigminer==2.3.1' is not available for this version of R" — and
## install.packages() carries no archiveurl argument at all. The recorded
## result-gate semantics therefore become the design itself: a node counts as
## provisioned only when the library's own DESCRIPTION reports the version.
##
## Kept from the #9 hardened build: the packageVersion("sigminer")=="2.3.1"
## exact assert and the two belt-and-braces Archive pins (rbibutils 2.4.1,
## gridBase 0.4-7), now result-gated through the same fetch/install path. The
## old "five documented exports" assert was retired in slice-3: those five
## names exist 0/5 in the witnessed 2.3.1 NAMESPACE (memo §9c.2 fact-check) —
## the tail gate now verifies the WITNESSED export contract instead, straight
## from the tarball bytes the resolver itself downloaded (§9d).
##
## Usage: Rscript install_sigminer.R [--dry-run]
## --dry-run resolves and downloads the FULL transitive graph and reports
## every node's winning URL, then exits without installing (pre-flight for
## the single budgeted docker build).

DRY <- "--dry-run" %in% commandArgs()
options(timeout = 600)

CRAN <- "https://cran.r-project.org"
CONTRIB <- paste0(CRAN, "/src/contrib")
ARCH <- paste0(CRAN, "/src/contrib/Archive")
## Third resolution source, lowest priority (probe5 2026-10-08): the
## Bioconductor-class nodes sigminer imports (maftools, and Rhtslib below it)
## exist on NO CRAN tree — contrib db miss and no Archive directory (the
## 28k-token Archive master index confirms). They live in the pinned
## Bioconductor release the recorded build already compiled against once
## (Dockerfile §9b: Rhtslib bgzf/zlib class, now header-provisioned). Memo §5
## governs image pulls only; this package fetch follows the G0-established
## idiom (memo §8).
BIOC_CONTRIB <- "https://bioconductor.org/packages/3.17/bioc/src/contrib"
LIB <- .libPaths()[1L]
MAX_TRY <- 3L
BASE_R <- paste0(R.version$major, ".", R.version$minor)
ROOT_PIN <- list(name = "sigminer", op = "==", ver = "2.3.1")
EXTRA_PINS <- list(c("rbibutils", "2.4.1"), c("gridBase", "0.4-7"))
## slice-3 (memo §9c.2/§9d): the frozen recipe's five-name export contract
## was fiction (0/5 in every published sigminer). The build gate is now the
## WITNESSED NAMESPACE export set of the exact pinned artifact (read from
## the resolver's own downloaded tarball at the tail) plus this
## function-asserted real extraction/assignment family — the same names the
## host-side contract fixture pins (tests/fixtures/
## sigminer_2.3.1_namespace_exports.txt via tests/test_sigminer_api_contract.py).
CORE_API <- c("bp_extract_signatures", "bp_get_sig_obj", "bp_get_stats",
              "sig_extract", "sig_fit", "sig_fit_bootstrap", "sig_estimate",
              "sig_exposure", "sig_names")
## node-name -> tarball path: the tail assert reads the NAMESPACE witness
## from the very bytes the resolver fetched (no refetch, no second copy).
INSTALLED_TF <- list()
## witnessed NAMESPACE bytes (sha256 of the 2.3.1 Archive tarball's
## sigminer/NAMESPACE, recorded slice-2 §9c.2 from URL
## https://cran.r-project.org/src/contrib/Archive/sigminer/sigminer_2.3.1.tar.gz,
## tarball sha256 b2836c76..1953b): a re-routed or swapped artifact stops
## the build on the hash, not on trust.
NS_SHA256 <- "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df"

say <- function(...) cat(sprintf(...), "\n")
die <- function(...) {
  cat("FATAL:", sprintf(...), "\n", sep = "")
  quit(save = "no", status = 1L)
}
`%||%` <- function(a, b) if (length(a) && !is.na(a)) a else b
sha256File <- function(path) {
  ## pre-flight 2026-10-08 slice-3, on the build base itself: base R 4.3.3
  ## carries NO digest() (that merge landed in 4.4.0 — live probe: "could
  ## not find function digest"), and the system2 stdout/stderr=TRUE list
  ## form returned an atomic vector under Rscript (no $status to read).
  ## The file-redirect form is the deterministic contract: integer exit
  ## status, digest on stdout; sha256sum ships with coreutils on jammy.
  o <- tempfile(); e <- tempfile()
  st <- system2("sha256sum", c("--", path), stdout = o, stderr = e)
  if (!identical(st, 0L))
    die("sha256sum failed on witness bytes (status %s): %s", st,
        paste0(readLines(e, warn = FALSE), collapse = " | "))
  ln <- readLines(o, warn = FALSE)
  if (!length(ln)) die("sha256sum printed no digest for %s", path)
  strsplit(trimws(ln[[1L]]), " ")[[1L]][[1L]]
}
capitalize <- function(x) {
  s <- tolower(x)
  paste0(toupper(substring(s, 1, 1)), substring(s, 2))
}

## ---------------------------------------------------------------- DESCRIPTION
## Blank-delimited multi-record DCF parser (record separator: blank line;
## continuation: blank-led line). readDcfText is the single-record view the
## tarballs' DESCRIPTIONs use; parseDcfRecords also feeds PACKAGES parsing.
parseDcfRecords <- function(lines) {
  recs <- list(); cur <- list(); k <- NULL
  flush <- function() { if (length(cur)) { recs[[length(recs) + 1L]] <<- cur; cur <<- list() }; k <<- NULL }
  for (l in lines) {
    if (!nzchar(trimws(l))) { flush(); next }
    if (!is.null(k) && grepl("^[[:blank:]]", l)) {
      cur[[k]] <- paste0(cur[[k]], "\n", trimws(l))
    } else if (grepl("^[^:[:blank:]]+:", l)) {
      k <- sub(":.*$", "", l)
      cur[[k]] <- sub("^[^:]+:[[:blank:]]*", "", l)
    }
  }
  flush()
  recs
}
readDcfText <- function(path) {
  if (!file.exists(path)) return(list())
  recs <- parseDcfRecords(readLines(path, warn = FALSE))
  if (!length(recs)) return(list())
  one <- recs[[1L]]
  ## a stray blank line inside a DESCRIPTION would split records; fold them
  ## back so field extraction never silently drops a post-blank stanza
  if (length(recs) > 1L)
    for (r in recs[-1L])
      for (k in names(r))
        one[[k]] <- if (is.null(one[[k]])) r[[k]] else paste0(one[[k]], "\n", r[[k]])
  one
}

## ---------------------------------------------------------------- version cmp
## This base R's compareVersion() is string-oriented (splits on [.-]).
cmp <- function(a, b) {
  if (is.null(a) || is.null(b)) return(NULL)
  tryCatch(as.integer(compareVersion(as.character(a), as.character(b))),
            error = function(e) NULL)                        # -1 | 0 | 1 | NULL
}
satisfies <- function(have, op, want) {
  if (is.null(op) || is.null(want)) return(TRUE)
  if (is.null(have)) return(FALSE)
  c <- cmp(have, want)
  if (is.null(c)) return(FALSE)
  switch(op, ">=" = c >= 0L, "<=" = c <= 0L, ">" = c > 0L, "<" = c < 0L,
         "==" = c == 0L, "=" = c == 0L, "!=" = c != 0L, FALSE)
}
## TRUE iff every `R (op x)` requirement inside a Depends field fits BASE_R.
## Paren-aware split (same wrapped-constraint hazard as parseDeps).
rSatisfies <- function(dependsField) {
  if (is.null(dependsField)) return(TRUE)
  for (h in splitDepField(dependsField)) {
    h <- trimws(h)
    if (!grepl("^R([[:blank:]]*\\(|$)", h)) next           # not the R entry
    if (!grepl("\\(", h)) next                              # bare R: no bound
    op <- sub("^[^ (]*[[:blank:]]*\\(([<>=!]+)[[:blank:]]*.*$", "\\1", h)
    want <- sub("^[^ (]*[[:blank:]]*\\([<>=!]+[[:blank:]]*([^)]*)\\).*$", "\\1", h)
    c <- cmp(BASE_R, trimws(want))
    if (is.null(c) || c < 0L) return(FALSE)
  }
  TRUE
}

## ---------------------------------------------------------------- CRAN/bioc db
## One PACKAGES fetch per repo for the session; a failed fetch is remembered
## so the lookup does not re-hammer a flaky proxy per node. contrib is queried
## first so era fidelity follows CRAN wherever CRAN carries the node; the
## pinned Bioconductor release is the recorded fallback source for the
## bioc-class Imports only (maftools/Rhtslib exist on no CRAN tree — probe3/
## probe6 2026-10-08). Memo §5 governs image pulls only; this package fetch
## follows the G0-established idiom (memo §8).
## fetchDb has two layers: available.packages as the fast path, then a raw
## PACKAGES(.gz) download parsed by our own DCF reader — probe7 2026-10-08
## recorded that the bioc server serves no PACKAGES.rds and the rds-first
## read dies on "SSL connect error"/"error reading from connection".
fetchDbRecords <- function(url) {
  for (t in 1L:2L) {
    db <- tryCatch(available.packages(url), error = function(e) NULL,
                   warning = function(w) NULL)
    if (is.data.frame(db) && nrow(db))
      return(data.frame(Package = as.character(db[, "Package"]),
                        Version = as.character(db[, "Version"]),
                        stringsAsFactors = FALSE))
  }
  for (f in c("PACKAGES", "PACKAGES.gz")) {
    tf <- tempfile()
    ok <- FALSE
    for (t in seq_len(MAX_TRY)) {
      ok <- tryCatch({
        suppressWarnings(download.file(paste0(url, "/", f), destfile = tf,
                                         quiet = TRUE, mode = "wb"))
        file.exists(tf) && file.size(tf) > 50L
      }, error = function(e) FALSE)
      if (isTRUE(ok)) break
      Sys.sleep(1)
    }
    if (!isTRUE(ok)) next
    ln <- tryCatch(readLines(tf, warn = FALSE), error = function(e) character())
    if (!length(ln)) next
    recs <- parseDcfRecords(ln)
    pk <- vapply(recs, function(r) if (is.null(r[["Package"]])) NA_character_ else as.character(r[["Package"]]), character(1))
    vv <- vapply(recs, function(r) if (is.null(r[["Version"]])) NA_character_ else as.character(r[["Version"]]), character(1))
    keep <- !is.na(pk) & !is.na(vv) & nzchar(pk) & nzchar(vv)
    if (any(keep))
      return(data.frame(Package = pk[keep], Version = vv[keep],
                        stringsAsFactors = FALSE))
  }
  NULL
}
dbRow <- local({
  dbs <- new.env(hash = TRUE)                       # url -> db | NA (failed)
  function(pkg) {
    for (u in c(CONTRIB, BIOC_CONTRIB)) {
      if (!exists(u, envir = dbs, inherits = FALSE)) assign(u, 0L, envir = dbs)
      cur <- get(u, envir = dbs)
      if (is.numeric(cur) && cur < 3L) {         # flaky PACKAGES fetch: at most
        db <- fetchDbRecords(u)                  # 3 whole re-tries, then give up
        assign(u, if (is.null(db)) cur + 1L else db, envir = dbs)
        cur <- get(u, envir = dbs)
      }
      if (isTRUE(is.data.frame(cur))) {
        i <- which(tolower(cur[, "Package"]) == tolower(pkg))
        if (length(i))
          return(list(name = cur[i[1], "Package"],
                      ver = as.character(cur[i[1], "Version"])))
      }
    }
    NULL
  }
})
dbGet <- function(pkg) dbRow(pkg)
## Canonical Archive directory names discovered from the master index (walk
## section) — seeded here so every nameCands consumer (fetchTarball included)
## sees them once learned. Key: lowercase package name.
aliases <- new.env(hash = TRUE)
nameCands <- function(pkg) {
  canon <- dbGet(pkg)
  al <- if (exists(tolower(pkg), envir = aliases, inherits = FALSE))
          get(tolower(pkg), envir = aliases) else NULL
  unique(c(al, if (!is.null(canon)) canon$name else NULL,
           pkg, tolower(pkg), capitalize(pkg)))
}

## ---------------------------------------------------------------- fetching
## Winner: list(tf=local tarball, url=winning source). Exhausted candidates ×
## all four URL shapes (contrib, Archive-pkgdir, Archive-flat, bioc-contrib) ⇒
## list(err=<verbatim per-URL record>, transient=<lgl>) — the caller's fallback
## chain (later candidates, the Archive listing walk, the BFS deferral, the
## pin-level stop) decides who dies on it. Recorded failure classes: not-
## openable 404 (DETERMINISTIC — retried once, then skipped: probe8 measured
## the live-URL flake class interleaving successes seconds apart, so burning
## retries on 404s only bursts the proxy), intermittent cannot-open/SSL/502
## (TRANSIENT — MAX_TRY retries with linear backoff; probe8 2026-10-08:
## Biobase_2.60.0 7/10, DNAcopy_1.74.1 6/10 on the bioc host).
isTransientStatus <- function(st) {
  grepl("SSL|timed? ?out|502|503|504|Empty reply|Could not resolve|Failed receiving|Could not connect",
        st, ignore.case = TRUE) ||
    (grepl("cannot open URL", st, ignore.case = TRUE) &&
     !grepl("status was 404|status was 403", st))
}
fetchTarball <- function(pkg, ver) {
  tried <- character(); lasterr <- "(never attempted)"; sawTransient <- FALSE
  for (nm in nameCands(pkg)) {
    urls <- c(sprintf("%s/%s_%s.tar.gz", CONTRIB, nm, ver),
              sprintf("%s/%s/%s_%s.tar.gz", ARCH, nm, nm, ver),
              sprintf("%s/%s_%s.tar.gz", ARCH, nm, ver),
              sprintf("%s/%s_%s.tar.gz", BIOC_CONTRIB, nm, ver))
    for (u in urls) {
      deterministic <- FALSE
      for (t in seq_len(MAX_TRY)) {
        if (deterministic) break
        tf <- tempfile(fileext = ".tar.gz")
        st <- tryCatch({
          suppressWarnings(download.file(u, destfile = tf, quiet = TRUE, mode = "wb"))
          if (file.exists(tf) && file.size(tf) > 1024L) "OK" else {
            if (file.exists(tf)) file.remove(tf)
            "TOOSMALL-or-404-body"
          }
        }, error = function(e) paste0("ERR:", conditionMessage(e)),
           warning = function(w) paste0("WARN:", conditionMessage(w)))
        if (identical(st, "OK")) return(list(tf = tf, url = u))
        tried <- c(tried, paste0(u, " x", t, " -> ", st))
        lasterr <- st
        if (grepl("status was 404|status was 403|TOOSMALL-or-404-body", st))
          deterministic <- TRUE                    # live-server "no such file": do not re-burst
        if (isTransientStatus(st)) {
          sawTransient <- TRUE
          if (t < MAX_TRY) Sys.sleep(min(2L * t, 8L))   # linear backoff
        } else deterministic <- TRUE
      }
    }
  }
  list(err = paste0("unresolvable ", pkg, " ", ver, " (last: ", lasterr,
                    "); attempted: ", paste0(unique(tried), collapse = " | ")),
       transient = sawTransient)
}

tarDesc <- local({
  cache <- new.env(hash = TRUE)
  function(tf) {
    if (exists(tf, envir = cache, inherits = FALSE))
      return(get(tf, envir = cache))
    ex <- tempfile(pattern = "x-"); dir.create(ex)
    untar(tf, exdir = ex)
    allf <- list.files(ex, full.names = TRUE, recursive = TRUE)
    cand <- allf[grepl("/DESCRIPTION$", allf)]
    if (!length(cand)) die("tarball %s contains no DESCRIPTION", tf)
    d <- readDcfText(cand[1])
    assign(tf, d, envir = cache)
    d
  }
})

## ---------------------------------------------------------------- deps parse
## One "pkg (op ver)" token → list(name, op, ver). sub()-based (deterministic,
## no capture-index games). op/ver NULL when the token carries no constraint.
parseOneDep <- function(item) {
  item <- trimws(gsub("\n", " ", item))
  if (!nzchar(item) || grepl("^#", item)) return(NULL)
  nm <- trimws(sub("[[:blank:]]*\\(.*$", "", item))
  if (!nzchar(nm) || identical(tolower(nm), "r")) return(NULL)
  if (!grepl("\\(", item)) return(list(name = nm, op = NULL, ver = NULL))
  op <- sub("^[^ (]*[[:blank:]]*\\(([<>=!]+)[[:blank:]]*.*$", "\\1", item)
  want <- sub("^[^ (]*[[:blank:]]*\\([<>=!]+[[:blank:]]*([^)]*)\\).*$", "\\1", item)
  op <- if (identical(op, item)) "" else trimws(op)
  want <- if (identical(want, item)) "" else trimws(want)
  if (!nzchar(op) || !nzchar(want)) return(list(name = nm, op = NULL, ver = NULL))
  list(name = nm, op = op, ver = want)
}
## hard deps only: Depends + Imports + LinkingTo; Suggests/Enhances excluded.
## Comma-split at paren depth 0 only — 80-col wrapped constraints keep their
## commas inside the parens intact (dry-run 2026-10-08 caught the naive join).
splitDepField <- function(s) {
  s <- gsub("\n", " ", s)
  depth <- 0L; tok <- ""; out <- character()
  for (ch in strsplit(s, "")[[1]]) {
    if (identical(ch, "(")) depth <- depth + 1L
    else if (identical(ch, ")")) depth <- depth - 1L
    if (identical(ch, ",") && depth == 0L) { out <- c(out, tok); tok <- "" }
    else tok <- paste0(tok, ch)
  }
  c(out, tok)
}
parseDeps <- function(fields) {
  out <- list()
  for (f in c("Depends", "Imports", "LinkingTo")) {
    s <- fields[[f]]
    if (is.null(s)) next
    for (item in splitDepField(s)) {
      d <- parseOneDep(item)
      if (!is.null(d)) out[[length(out) + 1L]] <- d
    }
  }
  out
}

## ---------------------------------------------------------------- installed
verOf <- function(pkg) {
  for (l in .libPaths()) {
    d <- file.path(l, pkg, "DESCRIPTION")
    if (file.exists(d)) {
      v <- readDcfText(d)[["Version"]]
      if (!is.null(v)) return(trimws(v))
    }
  }
  NULL
}
verOfAny <- function(pkg) {
  v <- verOf(pkg)
  if (!is.null(v)) return(v)
  for (alt in unique(c(tolower(pkg), capitalize(pkg)))) {
    v <- verOf(alt)
    if (!is.null(v)) return(v)
  }
  NULL
}

## ---------------------------------------------------------------- walk
## Last resort: the Archive per-package directory listing, newest first.
## Pure string filters (startsWith/substr) — no unescaped-name regexes.
## Directory fetches carry MAX_TRY retries (recorded proxy flakiness, memo
## §9b item 1 — the viridisLite class: live directory 404s on first try),
## and the Archive master index resolves the canonical directory spelling
## when every candidate case misses (probe6 2026-10-08: 28k-token index at
## ARCH/ carries it; 5.5 MB, fetched lazily at most once, cached).
archIndex <- local({
  st <- NULL                                   # NULL=untried | FALSE | character
  function() {
    if (is.null(st)) {
      tf <- tempfile(fileext = ".html"); got <- FALSE
      for (t in seq_len(MAX_TRY)) {
        ok <- tryCatch({
          suppressWarnings(download.file(paste0(ARCH, "/"), destfile = tf,
                                         quiet = TRUE))
          file.exists(tf) && file.size(tf) > 50L
        }, error = function(e) FALSE)
        if (isTRUE(ok)) { got <- TRUE; break }
      }
      st <<- if (!got) FALSE else {
        toks <- character()
        for (l in readLines(tf, warn = FALSE))
          for (p in strsplit(l, '"')[[1]])
            if (grepl("/$", p)) toks <- c(toks, basename(sub("/$", "", p)))
        toks
      }
    }
    if (identical(st, FALSE)) character() else st
  }
})
findArchDir <- function(name) {
  toks <- archIndex()
  if (!length(toks)) return(NULL)
  hit <- toks[tolower(toks) == tolower(name)]
  if (!length(hit)) NULL else hit[1]
}
walkArchiveListing <- function(name, note = new.env()) {
  grabDir <- function(nm) {
    html <- tempfile(fileext = ".html")
    for (t in seq_len(MAX_TRY)) {
      st <- tryCatch({
        suppressWarnings(download.file(sprintf("%s/%s/", ARCH, nm),
                                       destfile = html, quiet = TRUE))
        if (file.exists(html) && file.size(html) > 50L) "OK" else "TOOSMALL-or-404-body"
      }, error = function(e) paste0("ERR:", conditionMessage(e)))
      if (identical(st, "OK")) return(html)
      if (isTransientStatus(st)) { note$transient <- TRUE
                                   Sys.sleep(min(2L * t, 8L)) }
      else break                                # deterministic miss: next candidate
    }
    NULL
  }
  cands <- nameCands(name)
  cd <- findArchDir(name)
  if (!is.null(cd) && !(cd %in% cands)) cands <- c(cd, cands)
  toks <- character(); win <- NULL
  for (nm in cands) {
    html <- grabDir(nm)
    if (is.null(html)) next
    for (l in readLines(html, warn = FALSE))
      for (p in strsplit(l, '"')[[1]])
        if (grepl("\\.tar\\.gz$", p)) toks <- c(toks, basename(p))
    if (length(toks)) { win <- nm; break }
  }
  if (!length(toks)) return(NULL)
  if (!identical(win, name))
    assign(tolower(name), win, envir = aliases)   # feed fetchTarball candidates
  vers <- character()
  for (nm in unique(c(cands, win))) {
    pre <- paste0(nm, "_")
    for (fn in toks) {
      if (!startsWith(fn, pre) || !endsWith(fn, ".tar.gz")) next
      rest <- substr(fn, nchar(pre) + 1L, nchar(fn) - 7L)
      if (grepl("^[0-9]", rest)) vers <- c(vers, rest)
    }
  }
  vers <- unique(vers)
  if (!length(vers)) return(NULL)
  ord <- order(vapply(vers, function(v) {
    x <- suppressWarnings(as.numeric(gsub("-", ".", v)))
    if (is.na(x)) 0 else x
  }, FUN.VALUE = 0))
  rev(vers[ord])
}

## ---------------------------------------------------------------- resolve
## Returns NULL (already installed and satisfying), the accepted tarball
## list(tf,url), or a failure record list(fail=<verbatim>, transient=<lgl>) —
## transient failures are the BFS deferral's input (probe8: bioc live URLs
## fail ~30% of requests, seconds-apart successes interleaved).
resolveNode <- function(name, op, want, filter = NULL) {
  have <- verOfAny(name)
  if (!is.null(have) && satisfies(have, op, want)) return(NULL)
  canon <- dbGet(name)
  cur <- if (!is.null(canon)) canon$ver else NULL
  cands <- unique(c(if (!is.null(cur)) cur else NULL,
                    if (!is.null(want)) want else NULL))
  rejects <- character()
  note <- new.env()
  for (cv in cands) {
    f <- fetchTarball(name, cv)
    if (!is.null(f$err)) {
      if (isTRUE(f$transient)) note$transient <- TRUE
      rejects <- c(rejects, paste0(cv, ": ", f$err)); next
    }
    if (!satisfies(cv, op, want)) {
      rejects <- c(rejects, paste0(cv, ": fails constraint (", op %||% "", " ",
                                   want %||% "", ")"))
      next
    }
    if (!rSatisfies(tarDesc(f$tf)[["Depends"]])) {
      say("  reject %s %s (Needs-R exceeds base %s)", name, cv, BASE_R)
      rejects <- c(rejects, paste0(cv, ": needs-R"))
      next
    }
    ## graph-consistency filter (joint hard-dep audit, see CONSIST block):
    ## a candidate whose own Imports disagree with settled pins is rejected
    ## even when it individually satisfies this node's constraint.
    if (!is.null(filter) && !isTRUE(filter(f$tf))) {
      rejects <- c(rejects, paste0(cv, ": graph-consistency"))
      next
    }
    return(f)
  }
  say("  walking Archive listing for %s (candidates failed: %s)",
      name, paste0(rejects, collapse = "; "))
  wl <- walkArchiveListing(name, note)
  if (is.null(wl))
    return(list(
      fail = paste0("node ", name, " (", op %||% "", " ", want %||% "",
                    "): candidates [", paste0(cands, collapse = ","),
                    "] failed and no Archive listing usable — ",
                    paste0(rejects, collapse = " | ")),
      transient = isTRUE(note$transient)))
  tried <- 0L
  for (cv in wl) {
    if (tried >= 30L) break
    if (!satisfies(cv, op, want)) next
    tried <- tried + 1L
    f <- fetchTarball(name, cv)
    if (!is.null(f$err)) {
      if (isTRUE(f$transient)) note$transient <- TRUE
      next
    }
    if (!rSatisfies(tarDesc(f$tf)[["Depends"]])) {
      say("  walk reject %s %s (Needs-R exceeds base %s)", name, cv, BASE_R)
      next
    }
    if (!is.null(filter) && !isTRUE(filter(f$tf))) {
      say("  walk reject %s %s (imports vs settled graph)", name, cv)
      next
    }
    return(f)
  }
  list(fail = paste0("node ", name, ": no Archive-listed version satisfies (",
                     op %||% "", " ", want %||% "", ") + base R ", BASE_R),
       transient = isTRUE(note$transient))
}

## ---------------------------------------------------------------- BFS
say("== m7 sigminer installer: base R %s, target lib %s, dry-run %s",
    BASE_R, LIB, DRY)
MAX_DEFER <- 2L
queue <- list(ROOT_PIN)
settled <- list(); seen <- character()
defers <- new.env(hash = TRUE)
while (length(queue)) {
  nd <- queue[[1]]; queue[[1]] <- NULL
  key <- tolower(nd$name)
  if (key %in% seen) next
  seen <- c(seen, key)
  r <- resolveNode(nd$name, nd$op, nd$ver)
  if (!is.null(r) && !is.null(r$fail)) {
    d <- if (exists(key, envir = defers, inherits = FALSE))
            get(key, envir = defers) else 0L
    if (isTRUE(r$transient) && d < MAX_DEFER) {
      assign(key, d + 1L, envir = defers)
      seen <- setdiff(seen, key)                 # re-open for the deferred requeue
      say("  DEFER %-14s transient fetch class — requeued (round %d/%d)",
          nd$name, d + 1L, MAX_DEFER)
      queue <- c(queue, list(nd))
      next
    }
    die("%s — after %d deferral round(s) (transient=%s)",
        r$fail, d, isTRUE(r$transient))
  }
  if (is.null(r)) {
    say("RESOLVE %-14s %s %s INSTALLED (library reports %s)",
        nd$name, nd$op %||% "", nd$ver %||% "", verOfAny(nd$name))
    next
  }
  fld <- tarDesc(r$tf)
  say("RESOLVE %-14s %s via %s", nd$name, fld[["Version"]] %||% nd$ver, r$url)
  kids <- parseDeps(fld)
  settled[[key]] <- list(name = nd$name, ver = fld[["Version"]] %||% nd$ver,
                         tf = r$tf, children = kids)
  queue <- c(queue, lapply(kids, function(k) list(name = k$name, op = k$op, ver = k$ver)))
}

## ---------------------------------------------------------------- consistency
## Joint hard-dep audit (build5 2026-10-08 class): cowplot settled as
## contrib-current 1.2.0 (2025) because sigminer imports it BARE, while its
## own Imports demand ggplot2 (>= 3.5.2) — which the graph had pinned at
## sigminer's own want 3.3.0. install.packages (repos=NULL) enforces exactly
## this and aborted the install without an exception. Per-node resolution is
## individually sound but not jointly sound; the graph's pins must satisfy
## EVERY settled node's hard Imports before anything installs. Repair by
## floating the UNJUSTIFIED side: a pin equal to some requester's explicit
## want is era-sacred (the 2023 tree spoke it); a contrib-current default
## floats freely back through the Archive until its imports agree.
justified <- function(ver, cons) {
  for (cn in cons) if (!is.null(cn$ver) && identical(cn$ver, ver)) return(TRUE)
  FALSE
}
tightest <- function(cons) {                       # single joint (op, want)
  for (cn in cons) if (cn$op %in% c("==", "=")) return(list(op = "==", ver = cn$ver))
  op <- ">="; want <- NULL
  for (cn in cons)
    if (cn$op %in% c(">=", ">") && (is.null(want) || isTRUE(cmp(cn$ver, want) > 0L)))
      want <- cn$ver
  list(op = op, ver = want)
}
importsAgree <- function(tf, skip.key) {           # desc-imports vs settled pins
  for (d in parseDeps(tarDesc(tf))) {
    dk <- tolower(d$name)
    if (!is.null(dk) && dk %in% names(settled) && !identical(dk, skip.key) &&
        !satisfies(settled[[dk]]$ver, d$op, d$ver)) return(FALSE)
  }
  TRUE
}
collectCons <- function() {                        # dep-key -> list(op, ver, from)
  cm <- new.env(hash = TRUE)
  for (k in names(settled))
    for (d in settled[[k]]$children) {
      if (is.null(d$op) || is.null(d$ver)) next
      dk <- tolower(d$name)
      cur <- if (exists(dk, envir = cm, inherits = FALSE)) get(dk, envir = cm) else list()
      assign(dk, c(cur, list(list(op = d$op, ver = d$ver, from = k))), envir = cm)
    }
  cm
}
findViolation <- function(cm) {
  for (dk in ls(cm, envir = cm)) {
    v <- settled[[dk]]$ver
    if (is.null(v)) next                            # base pkg / unsettled: skip
    for (cn in get(dk, envir = cm))
      if (!satisfies(v, cn$op, cn$ver))
        return(list(key = dk, cn = cn, cons = get(dk, envir = cm)))
  }
  NULL
}
MAX_CONSIST <- 3L
for (round in 1L:MAX_CONSIST) {
  cm <- collectCons()
  viol <- findViolation(cm)
  if (is.null(viol)) { if (round > 1L)
    say("  CONSIST graph jointly consistent (round %d)", round); break }
  from.key <- viol$cn$from
  dep.just  <- justified(settled[[viol$key]]$ver, viol$cons)
  from.cons <- if (exists(from.key, envir = cm, inherits = FALSE))
                  get(from.key, envir = cm) else list()
  from.just <- justified(settled[[from.key]]$ver, from.cons)
  say("  CONSIST %s %s breaks (%s %s %s) from %s — dep-justified=%s demander-justified=%s",
      settled[[viol$key]]$name, settled[[viol$key]]$ver, viol$key,
      viol$cn$op, viol$cn$ver, viol$cn$from, dep.just, from.just)
  if (!from.just) {
    ## float the unjustified DEMANDER back through the Archive until its
    ## imports agree with the settled graph (cowplot 1.2.0 -> 1.1.x class)
    r <- resolveNode(settled[[from.key]]$name, NULL, NULL,
                     filter = function(tf) importsAgree(tf, from.key))
    if (is.null(r) || !is.null(r$fail))
      die("consistency: no version of %s has imports agreeing with the settled graph (%s breaks %s %s %s)",
          from.key, viol$key, viol$cn$op %||% "", viol$cn$ver %||% "", viol$cn$from)
    fld <- tarDesc(r$tf)
    say("  CONSIST float %s %s -> %s (imports vs settled graph)",
        settled[[from.key]]$name, settled[[from.key]]$ver, fld[["Version"]] %||% "?")
    settled[[from.key]] <- list(name = settled[[from.key]]$name,
                                ver = fld[["Version"]] %||% settled[[from.key]]$ver,
                                tf = r$tf, children = parseDeps(fld))
    ## the floater must not smuggle in a dependency the BFS never met
    kid.keys <- unlist(lapply(settled[[from.key]]$children,
                              function(d) tolower(d$name)))
    fresh <- setdiff(kid.keys, c(names(settled), seen))
    if (length(fresh))
      die("consistency: floater %s introduced unknown dependency %s — refusing to install blind",
          from.key, paste0(fresh, collapse = ","))
  } else {
    ## demander era-sacred; RAISE the dependency to the tightest joint bound
    tb <- tightest(viol$cons)
    r <- resolveNode(settled[[viol$key]]$name, tb$op, tb$ver)
    if (is.null(r) || !is.null(r$fail))
      die("consistency: cannot raise %s to joint bound (%s %s): %s",
          viol$key, tb$op %||% "", tb$ver %||% "", r$fail %||% "short-circuited")
    fld <- tarDesc(r$tf)
    say("  CONSIST raise %s %s -> %s (joint bound %s %s)",
        settled[[viol$key]]$name, settled[[viol$key]]$ver, fld[["Version"]] %||% "?",
        tb$op %||% "", tb$ver %||% "")
    settled[[viol$key]] <- list(name = settled[[viol$key]]$name,
                                ver = fld[["Version"]] %||% settled[[viol$key]]$ver,
                                tf = r$tf, children = parseDeps(fld))
  }
  if (identical(round, MAX_CONSIST)) {
    cm <- collectCons()
    if (!is.null(findViolation(cm)))
      die("consistency: graph still jointly inconsistent after %d rounds (%s %s vs %s %s %s)",
          MAX_CONSIST, settled[[viol$key]]$name, settled[[viol$key]]$ver,
          viol$key, viol$cn$op %||% "", viol$cn$ver %||% "")
  }
}

## ---------------------------------------------------------------- install
installTarball <- function(entry) {
  ## The base R 4.3.3 contract, from deparse(install.packages) captured
  ## host-side 2026-10-08: the success path is `return(invisible())` —
  ## NULL — and a failed R CMD INSTALL surfaces ONLY as the warning
  ## "installation of package 'x' had non-zero exit status". There is
  ## neither an exception nor a status code here. Spare-1's
  ## "no-exception => OK" printed the cowplot lie; spare-2's return-code
  ## reading printed `STATUS:NA` on a library-confirmed success (cli
  ## 3.6.6) — both read a channel this R does not have. The warning IS
  ## the channel; the library's own DESCRIPTION remains the final say.
  warn <- NULL
  st <- tryCatch({
    withCallingHandlers(
      suppressMessages(install.packages(entry$tf, lib = LIB, repos = NULL,
                                         type = "source", dependencies = NA,
                                         quiet = TRUE)),
      warning = function(w) {
        m <- conditionMessage(w)
        if (grepl("non-zero exit status", m, fixed = TRUE)) warn <<- m
        invokeRestart("muffleWarning")
      })
    if (is.null(warn)) "OK" else paste0("WARN:", substr(warn, 1L, 160L))
  }, error = function(e) paste0("ERR:", conditionMessage(e)))
  got <- verOfAny(entry$name)
  if (!identical(st, "OK") || !identical(got, entry$ver)) {
    ## replay the failed install WITHOUT quiet: the R CMD INSTALL error text
    ## is the honest terminal record for the build log (quiet=TRUE buried it
    ## in the cowplot failure — the ledger must not lose that class again).
    say("  install failed %s %s (%s, library reports %s) — replaying visibly",
        entry$name, entry$ver, st, got %||% "(none)")
    try(withVisible(install.packages(entry$tf, lib = LIB, repos = NULL,
        type = "source", dependencies = NA, quiet = FALSE)), silent = TRUE)
    die("install failed for %s %s: %s (library reports %s)",
        entry$name, entry$ver, st, got %||% "(none)")
  }
  INSTALLED_TF[[entry$name]] <<- entry$tf
  say("INSTALL %-14s %s OK", entry$name, entry$ver)
}

if (DRY) {
  say("DRY-RUN graph complete: %d installable node(s): %s",
      length(settled), paste0(names(settled), collapse = " "))
  quit(save = "no", status = 0L)
}

## topological: install a node only once every child reports from the library
pending <- names(settled)
while (length(pending)) {
  progressed <- FALSE
  for (key in pending) {
    e <- settled[[key]]
    ready <- all(vapply(e$children, function(k) !is.null(verOfAny(k$name)),
                        FUN.VALUE = TRUE))
    if (!ready) next
    installTarball(e)
    settled[[key]] <- NULL
    pending <- setdiff(pending, key)
    progressed <- TRUE
    break                                      # re-evaluate after every success
  }
  if (!progressed) {
    ## only a dependency cycle can stall; R CMD INSTALL does not enforce
    ## package deps, so fall through in residual order with a loud note
    say("NOTE: topo stall at [%s] — installing residual order",
        paste0(pending, collapse = " "))
    for (key in pending) installTarball(settled[[key]])
    break
  }
}

## ------------------------------------------------- belt-and-braces exact pins
## Same flake discipline as the BFS: a transient exhaustion re-tries the whole
## candidate sweep up to PIN_ROUNDS times (seconds-apart successes interleaved
## — probe8), permanent exhaustion stops loudly.
PIN_ROUNDS <- 3L
for (pin in EXTRA_PINS) {
  p <- pin[1]; v <- pin[2]
  if (identical(verOfAny(p), v)) { say("PIN %-14s %s already exact", p, v); next }
  f <- NULL; lastrec <- "(never attempted)"
  for (round in seq_len(PIN_ROUNDS)) {
    fx <- fetchTarball(p, v)
    if (is.null(fx$err)) { f <- fx; break }
    lastrec <- fx$err
    if (!isTRUE(fx$transient)) break
    say("  PINDEFER %-14s %s transient class, round %d/%d", p, v, round, PIN_ROUNDS)
    Sys.sleep(5L)
  }
  if (is.null(f)) die("Archive-only pin not provisioned in library: %s %s — %s",
                      p, v, lastrec)
  st <- tryCatch({
    suppressWarnings(suppressMessages(
      install.packages(f$tf, lib = LIB, repos = NULL, type = "source",
                       dependencies = NA, quiet = TRUE)))
    "OK"
  }, error = function(e) paste0("ERR:", conditionMessage(e)))
  if (!identical(verOfAny(p), v))
    die("Archive-only pin not provisioned in library: %s %s (via %s, %s)",
        p, v, f$url, st)
  say("PIN %-14s %s provisioned via %s", p, v, f$url)
}

## ------------------------------------------- witnessed-NAMESPACE tail asserts
## slice-3 (memo §9c.2/§9d): the five "documented exports" the frozen recipe
## asserted exist 0/5 in the witnessed 2.3.1 NAMESPACE — the gate is now the
## verbatim export contract of the resolver's OWN downloaded bytes: every
## export() name must resolve in the installed namespace, and the core
## extraction/assignment family must resolve AS FUNCTIONS (G0 build-guard
## idiom: any drift stops the build loudly).
v <- verOf("sigminer")
if (!identical(v, "2.3.1"))
  die("SigMiner pin drift: got %s, want 2.3.1", v %||% "(none)")
ns <- tryCatch(asNamespace("sigminer"), error = function(e)
  die("sigminer namespace failed to load: %s", conditionMessage(e)))
tf <- INSTALLED_TF[["sigminer"]]
if (is.null(tf) || !file.exists(tf))
  die("witness tarball for sigminer 2.3.1 unavailable at assert time")
exd <- tempfile("ns-x-"); dir.create(exd)
untar(tf, exdir = exd, files = "sigminer/NAMESPACE")
nsf <- file.path(exd, "sigminer", "NAMESPACE")
if (!file.exists(nsf))
  die("witness tarball carries no sigminer/NAMESPACE")
ns_hash <- sha256File(nsf)
if (!identical(ns_hash, NS_SHA256))
  die("witness NAMESPACE hash drift: got %s want %s", ns_hash, NS_SHA256)
nsl <- readLines(nsf, warn = FALSE)
contract <- sub("^export\\((.*)\\)$", "\\1",
                nsl[grepl("^export\\(", nsl)])
## build8 root cause 2026-10-08 (/tmp/m7_sigminer_build8.log: the tail
## assert FATALed on the export name \"%>%\", quotes and all): the
## NAMESPACE grammar quotes non-syntactic export names -- the witnessed
## bytes carry exactly export("%>%") and export(":=") -- while exists()
## looks up BINDING names, so the stanza quotes must come off before
## resolution (host repro /tmp/m7_dl/repro_dequote.R: %in% and <- resolve
## clean on baseenv, quote-embedded forms never resolve; the live host
## sigminer namespace answers TRUE only to the clean operator names).
## Plain names pass through both subs untouched.
contract <- sub('^"(.*)"$', "\\1", sub("^`(.*)`$", "\\1", contract))
if (length(contract) < 100L)
  die("witness NAMESPACE malformed: %d export() lines", length(contract))
for (fn in contract)
  if (!exists(fn, where = ns))
    die("witnessed sigminer export missing: %s", fn)
for (fn in CORE_API)
  if (!exists(fn, mode = "function", where = ns))
    die("core sigminer function missing: %s", fn)
say("ASSERT sigminer 2.3.1 exact + %d witnessed exports present (%d core functions)",
    length(contract), length(CORE_API))
