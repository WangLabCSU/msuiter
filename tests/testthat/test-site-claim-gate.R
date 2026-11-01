# test-site-claim-gate.R: DS-2 US-5 site claim-gate conformance law (docs/site v2).
# The ARCHITECTURE.md G0-claim gate (915ad41) is law across every public face:
# the pre-registered coverage headline may not travel to a built site page
# without its gate sentence; no paper DOI exists, so no DOI may ride the site
# unless it byte-echoes committed source text (third-party citations in Rd
# files are legitimate -- a freshly minted one is not); and publication-status
# superlatives ("first-ever", a paper "submitted" claim) need a witness route.
# The scanner walks every *.html under the site tree (char-walk extraction, no
# regex engine -- this base's tre quirks). Controls are load-bearing
# (governance-scan-integrity law): a planted ungated headline MUST redden it,
# a planted ghost DOI MUST redden it, a planted superlative MUST redden it,
# and an empty tree MUST redden it (vacuous-green ban). The gate-sentenced
# and source-backed plantings must stay green -- proving the scanner does not
# merely fire on everything.

# --- forbidden-content definitions (single source of truth, here) --------------

.cg_HEADLINES <- c(
  "first inference layer that measures the empirical coverage of exposure intervals",
  "first coverage-measured intervals")

.cg_GATE_SENTINELS <- c("G0 primary run", "GATED")

.cg_SUPERLATIVE_ABSOLUTE <- c("first-ever", "world-first", "world first")

.cg_STATUS_CONTEXT <- c("manuscript", "paper", "abstract", "preprint",
                        "submission", "nature", "science", "cell",
                        "medrxiv", "biorxv")

.cg_WITNESS_ROUTE <- c("bench/", "fixtures/", "reproduction-proof")

# --- char-walk extractors ---------------------------------------------------------

.cg_find_all <- function(text, needle) {
  ch <- strsplit(text, "")[[1L]]
  nc <- strsplit(needle, "")[[1L]]
  n <- length(ch); m <- length(nc)
  out <- integer(0)
  if (m == 0L || n < m) return(out)
  i <- 1L
  while (i + m - 1L <= n) {
    hit <- TRUE
    for (k in seq_len(m)) if (!identical(ch[[i + k - 1L]], nc[[k]])) {
      hit <- FALSE
      break
    }
    if (hit) out <- c(out, i)
    i <- i + 1L
  }
  out
}

.cg_windows <- function(text, needle, half = 64L) {
  offs <- .cg_find_all(text, needle)
  if (!length(offs)) return(character(0))
  n <- nchar(text); m <- nchar(needle)
  out <- character(0)
  for (o in offs) {
    a <- max(1L, o - half)
    b <- min(n, o + m + half)
    out <- c(out, substr(text, a, b))
  }
  out
}

# tokens of the form doi:10.xxxx/suffix -- maximal run of ident chars after
# the doi: marker
.cg_doi_tokens <- function(text) {
  out <- character(0)
  for (o in .cg_find_all(text, "doi:")) {
    tail <- substr(text, o + 4L, min(nchar(text), o + 48L))
    ch <- strsplit(tail, "")[[1L]]
    run <- character(0)
    for (c0 in ch) {
      if (c0 %in% c(LETTERS, letters, 0:9, ".", "/", "_", "-")) {
        run <- c(run, c0)
      } else {
        break
      }
    }
    if (length(run)) out <- c(out, paste0("doi:", paste0(run, collapse = "")))
  }
  out
}

.cg_site_dir <- function() {
  if (is.na(.ms_root)) return(NA_character_)
  sd <- Sys.getenv("MSUITER_DS2_SITE_DIR", "")
  if (nzchar(sd) && dir.exists(sd)) return(normalizePath(sd))
  cand <- file.path(.ms_root, "docs", "dev")
  if (file.exists(file.path(cand, "reference", "index.html")) &&
      file.exists(file.path(cand, "articles", "index.html"))) cand else NA_character_
}

# --- scanner ------------------------------------------------------------------------

.cg_scan <- function(site_dir, root) {
  v <- character(0)
  htmls <- list.files(site_dir, pattern = "[.]html$", ignore.case = TRUE,
                      full.names = TRUE, recursive = TRUE)
  if (!length(htmls)) {
    return(list(violations = "vacuous: zero HTML pages scanned under the site tree",
                pages = 0L, doi_tokens = 0L))
  }
  if (!dir.exists(root)) {
    return(list(violations = paste0("witness root unreadable: ", root),
                pages = 0L, doi_tokens = 0L))
  }
  # committed-source DOI allowlist, re-derived -- no hand roster
  corpus <- character(0)
  for (d in c("man", "R", "vignettes", "inst", "docs")) {
    fs <- list.files(file.path(root, d),
                     pattern = "[.](R|Rd|Rmd|md|yml|txt|lock)$",
                     full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
    for (f in fs) corpus <- c(corpus, readLines(f, warn = FALSE))
  }
  for (f in c(file.path(root, "inst", "CITATION"), file.path(root, "README.md"),
              file.path(root, "NEWS.md"), file.path(root, "_pkgdown.yml"))) {
    if (file.exists(f)) corpus <- c(corpus, readLines(f, warn = FALSE))
  }
  allowed <- unique(.cg_doi_tokens(paste0(corpus, collapse = "\n")))
  doi_seen <- 0L
  for (h in htmls) {
    text <- paste0(readLines(h, warn = FALSE), collapse = "\n")
    low <- tolower(text)
    for (hl in .cg_HEADLINES) {
      if (grepl(hl, text, fixed = TRUE)) {
        for (sent in .cg_GATE_SENTINELS) {
          if (!grepl(sent, text, fixed = TRUE)) {
            v <- c(v, paste0("ungated G0 headline on page (missing sentinel '",
                             sent, "'): ", basename(h)))
          }
        }
      }
    }
    for (tok in if (grepl("doi:", text, fixed = TRUE)) .cg_doi_tokens(text)
                else character(0)) {
      doi_seen <- doi_seen + 1L
      if (!tok %in% allowed) {
        v <- c(v, paste0("unbacked DOI on page (no byte-echo in committed sources): ",
                         basename(h), " -- ", tok))
      }
    }
    for (sup in .cg_SUPERLATIVE_ABSOLUTE) {
      if (grepl(sup, low, fixed = TRUE)) {
        v <- c(v, paste0("superlative without route on page: ", basename(h),
                         " -- ", sup))
      }
    }
    if (grepl("submitted", low, fixed = TRUE)) for (win in .cg_windows(low,
                                                                        "submitted")) {
      hit_ctx <- FALSE
      for (tok in .cg_STATUS_CONTEXT) {
        if (grepl(tok, win, fixed = TRUE)) hit_ctx <- TRUE
      }
      if (!hit_ctx) next
      has_route <- FALSE
      for (tok in .cg_WITNESS_ROUTE) {
        if (grepl(tok, win, fixed = TRUE)) has_route <- TRUE
      }
      if (!has_route) {
        v <- c(v, paste0("paper-status 'submitted' claim without witness route: ",
                         basename(h), " -- window: ", win))
      }
    }
  }
  list(violations = v, pages = length(htmls), doi_tokens = doi_seen)
}

# --- green halves -----------------------------------------------------------------------

test_that("US-5 the real built site (when present) passes the claim gate with life", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sd <- .cg_site_dir()
  if (is.na(sd)) skip("no lane-built site tree (R CMD check context)")
  r <- .cg_scan(sd, .ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_gte(r$pages, 1L)
  cat("US-5 CLAIM GATE: pages=", r$pages, " doi-tokens=", r$doi_tokens,
      " violations=0\n", sep = "")
})

test_that("US-5 the shipped vignette faces carry no ungated headline and no superlative", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  fs <- list.files(file.path(.ms_root, "vignettes"), pattern = "[.]Rmd$",
                   full.names = TRUE)
  expect_gte(length(fs), 1L)
  v <- character(0)
  for (f in fs) {
    text <- paste0(readLines(f, warn = FALSE), collapse = "\n")
    for (hl in .cg_HEADLINES) {
      if (grepl(hl, text, fixed = TRUE)) {
        for (sent in .cg_GATE_SENTINELS) {
          if (!grepl(sent, text, fixed = TRUE)) {
            v <- c(v, paste0("ungated G0 headline in source face: ", basename(f)))
          }
        }
      }
    }
    for (sup in .cg_SUPERLATIVE_ABSOLUTE) {
      if (grepl(sup, tolower(text), fixed = TRUE)) {
        v <- c(v, paste0("superlative in source face: ", basename(f), " -- ", sup))
      }
    }
  }
  expect_identical(v, character(0), info = paste0(v, collapse = "\n"))
  cat("US-5 SOURCE-FACE GATE: rmd-pages=", length(fs), " violations=0\n",
      sep = "")
})

# --- red halves: planted violations MUST fire ----------------------------------------

test_that("US-5 a planted ungated G0 headline reddens the census (firing control)", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  site <- tempfile("ctl-cg-")
  dir.create(site, recursive = TRUE)
  writeLines(c("<html><body><p>The package is ", .cg_HEADLINES[1L],
               ".</p></body></html>"), file.path(site, "bad.html"))
  writeLines("<html><body><p>quiet page</p></body></html>",
             file.path(site, "ok.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  r <- .cg_scan(site, .ms_root)
  expect_true(any(grepl("ungated G0 headline on page (missing sentinel",
                        r$violations, fixed = TRUE)))
  expect_true(any(grepl("bad.html", r$violations, fixed = TRUE)))
  writeLines(c("<html><body><p>The claim (pre-registered headline, GATED: the",
               .cg_GATE_SENTINELS[1L], " has not landed): ",
               .cg_HEADLINES[1L], ".</p></body></html>"),
             file.path(site, "bad.html"))
  r2 <- .cg_scan(site, .ms_root)
  expect_identical(r2$violations, character(0),
                   info = paste0(r2$violations, collapse = "\n"))
  expect_gte(r2$pages, 2L)
})

test_that("US-5 a planted ghost DOI reddens the census; a source-backed DOI passes", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  site <- tempfile("ctl-cg2-")
  dir.create(site, recursive = TRUE)
  writeLines("<html><body><p>see (doi:10.999999/fabricated.2026) </p></body></html>",
             file.path(site, "ghost.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  r <- .cg_scan(site, .ms_root)
  expect_true(any(grepl("unbacked DOI on page", r$violations, fixed = TRUE)))
  writeLines(c("<html><body><p>Costello et al., NAR 2013 (doi:10.1093/nar/gks1443)",
               "</p></body></html>"), file.path(site, "ghost.html"))
  r2 <- .cg_scan(site, .ms_root)
  expect_identical(r2$violations, character(0),
                   info = paste0(r2$violations, collapse = "\n"))
  expect_gte(r2$doi_tokens, 1L)
})

test_that("US-5 a planted paper-status superlative reddens; a witnessed route passes", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  site <- tempfile("ctl-cg3-")
  dir.create(site, recursive = TRUE)
  writeLines("<html><body><p>first-ever coverage tool</p></body></html>",
             file.path(site, "sup.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  r <- .cg_scan(site, .ms_root)
  expect_true(any(grepl("superlative without route on page: sup.html -- first-ever",
                        r$violations, fixed = TRUE)))
  writeLines(c("<html><body><p>The manuscript was submitted to Nature",
               " (witness: bench/scenarios/witness.json)</p></body></html>"),
             file.path(site, "sup.html"))
  r2 <- .cg_scan(site, .ms_root)
  expect_identical(r2$violations, character(0),
                   info = paste0(r2$violations, collapse = "\n"))
  writeLines(c("<html><body><p>The manuscript was submitted to Nature",
               " this spring</p></body></html>"), file.path(site, "sup.html"))
  r3 <- .cg_scan(site, .ms_root)
  expect_true(any(grepl("without witness route", r3$violations, fixed = TRUE)))
})

test_that("US-5 an empty site tree can never pass (vacuous-green guard)", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  site <- tempfile("ctl-cg-empty-")
  dir.create(site, recursive = TRUE)
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  r <- .cg_scan(site, .ms_root)
  expect_true(any(grepl("zero HTML pages scanned", r$violations, fixed = TRUE)))
})
