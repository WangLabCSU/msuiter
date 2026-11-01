# test-docs-bridge.R: DS-2 US-2 docs-bridge article laws (docs/site v2).
# The bridge is a NAVIGATION page: every docs/ corpus document the card names
# is reachable by exactly one link, and none of the corpus is copied. Both
# sides are mechanical, no hand roster (the DS-1 MSU-MAP law shape): the link
# roster is RE-DERIVED from the docs/ directory bytes and the _pkgdown.yml
# url: key, and the built half (when the lane-built tree is present under
# docs/dev or MSUITER_DS2_SITE_DIR) 404-censuses every internal href and
# proves every roster anchor is really in the rendered page. Link extraction
# is a pure char walk (no regex engine -- the .ds2_cell_split precedent).
# Constructed-broken controls fire every rule; the constructed-perfect
# regeneration is the green control (dead-metric law; vacuous-green ban).

# --- roster re-derivation (the single source of truth: the tree bytes) --------

.br_roster <- function(root) {
  top <- sort(basename(list.files(file.path(root, "docs"),
                                  pattern = "[.]md$", include.dirs = FALSE)))
  top <- top[!(top %in% "README.md")]
  adr <- sort(basename(list.files(file.path(root, "docs", "adr"),
                                  pattern = "[.]md$", include.dirs = FALSE)))
  list(top = top, adr = adr, required = unique(c(top, adr)))
}

.br_href_base <- function(yml) {
  hits <- grep("^url:", yml)
  if (length(hits) != 1L) {
    stop("expected exactly one url: key in _pkgdown.yml")
  }
  base <- trimws(sub("^url:", "", yml[hits[1L]]))
  while (endsWith(base, "/")) base <- substr(base, 1L, nchar(base) - 1L)
  base
}

.br_canonical <- function(base, roster) {
  hrefs <- character(0)
  for (f in roster$top) hrefs <- c(hrefs, paste0(base, "/blob/main/docs/", f))
  for (f in roster$adr) hrefs <- c(hrefs, paste0(base, "/blob/main/docs/adr/", f))
  c(hrefs, paste0(base, "/tree/main/docs/adr"),
    paste0(base, "/tree/main/docs/devlog"))
}

# hrefs of markdown links [label](href): char walk over the joined text
.br_links <- function(text) {
  ch <- strsplit(text, "")[[1L]]
  out <- character(0)
  i <- 1L
  n <- length(ch)
  while (i < n) {
    if (identical(ch[i], "]") && identical(ch[i + 1L], "(")) {
      j <- i + 2L
      cur <- character(0)
      while (j <= n && !identical(ch[j], ")")) {
        cur <- c(cur, ch[j])
        j <- j + 1L
      }
      if (j <= n) {
        out <- c(out, paste0(cur, collapse = ""))
        i <- j + 1L
        next
      }
      i <- j
    } else {
      i <- i + 1L
    }
  }
  out
}

# --- source-side law -------------------------------------------------------------

.br_law_source <- function(bridge_lines, yml, root) {
  roster <- .br_roster(root)
  if (length(roster$required) == 0L) {
    return(list(violations = "vacuous: roster re-derived empty", inspected = 0L))
  }
  canon <- .br_canonical(.br_href_base(yml), roster)
  text <- paste0(bridge_lines, collapse = "\n")
  links <- .br_links(text)
  if (length(links) == 0L) {
    return(list(violations = "vacuous: bridge carries no links at all",
                inspected = 0L))
  }
  v <- character(0)
  for (h in canon) {
    n <- sum(links == h)
    if (n == 0L) {
      v <- c(v, paste0("roster document has no bridge link: ", h))
    } else if (n > 1L) {
      v <- c(v, paste0("bridge link appears ", n, " times (exactly 1): ", h))
    }
  }
  # fork-guard: a docs/-shaped href off the re-derived roster is a
  # hand-tweaked roster entry -- named, not swallowed
  docsish <- links[grepl("/docs/", links, fixed = TRUE)]
  for (h in setdiff(docsish, canon)) {
    v <- c(v, paste0("docs/-shaped href off the re-derived roster: ", h))
  }
  # no-fork: no corpus document's own H1 may reappear as bridge prose
  corpus <- c(file.path(root, "docs", roster$top),
               file.path(root, "docs", "adr", roster$adr))
  for (f in corpus) {
    ls <- readLines(f, warn = FALSE)
    h1 <- grep("^# ", ls)
    if (length(h1) && grepl(ls[h1[1L]], text, fixed = TRUE)) {
      v <- c(v, paste0("bridge inlines corpus heading (fork, not link): ",
                       basename(f), " -- ", ls[h1[1L]]))
    }
  }
  list(violations = v, inspected = length(canon))
}

# --- built-tree half (404 census of internal hrefs + anchor presence) ------------

.br_site_dir <- function() {
  sd <- Sys.getenv("MSUITER_DS2_SITE_DIR", "")
  if (nzchar(sd) && dir.exists(sd)) return(normalizePath(sd))
  cand <- file.path(.ms_root, "docs", "dev")
  if (!is.na(.ms_root) && file.exists(file.path(cand, "reference", "index.html")) &&
      file.exists(file.path(cand, "articles", "index.html"))) {
    return(cand)
  }
  NA_character_
}

.br_law_built <- function(site, root) {
  if (!requireNamespace("xml2", quietly = TRUE)) {
    stop("xml2 not installed: the built-half census cannot run silently")
  }
  page <- file.path(site, "articles", "docs-bridge.html")
  if (!file.exists(page)) {
    return(list(violations = "articles/docs-bridge.html missing from built tree",
                inspected = 0L, internal = 0L))
  }
  html <- paste0(readLines(page, warn = FALSE), collapse = "\n")
  yml <- readLines(file.path(root, "_pkgdown.yml"), warn = FALSE)
  canon <- .br_canonical(.br_href_base(yml), .br_roster(root))
  v <- character(0)
  for (h in canon) if (!grepl(h, html, fixed = TRUE)) {
    v <- c(v, paste0("roster href absent from rendered bridge: ", h))
  }
  xml2 <- asNamespace("xml2")
  doc <- xml2$read_html(page, encoding = "UTF-8", options = "RECOVER")
  nodes <- xml2$xml_find_all(doc, "//*[@href]")
  internal <- 0L
  for (nd in nodes) {
    at <- xml2$xml_attrs(nd)
    nm <- names(unlist(at))
    vl <- as.character(unlist(at))
    if (!length(nm) || !any(nm == "href")) next
    u <- trimws(vl[nm == "href"][1L])
    if (!nzchar(u) || identical(u, "#")) next
    if (startsWith(u, "https://") || startsWith(u, "http://") ||
        startsWith(u, "mailto:")) next
    if (startsWith(u, "/")) {
      v <- c(v, paste0("root-internal href breaks the census: ", u))
      next
    }
    p <- sub("[#?].*$", "", u)
    if (!nzchar(p)) next
    internal <- internal + 1L
    if (!file.exists(normalizePath(file.path(dirname(page), p),
                                   mustWork = FALSE))) {
      v <- c(v, paste0("broken internal href in built bridge: ", u))
    }
  }
  list(violations = v, inspected = length(canon), internal = internal)
}

# --- repository gate -----------------------------------------------------------------

.br_shipped <- function() {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  bf <- file.path(.ms_root, "vignettes", "docs-bridge.Rmd")
  if (!file.exists(bf)) {
    stop("vignettes/docs-bridge.Rmd missing from the checkout (US-2 defect)")
  }
  list(lines = readLines(bf, warn = FALSE),
       yml = readLines(file.path(.ms_root, "_pkgdown.yml"), warn = FALSE))
}

# --- green halves -----------------------------------------------------------------------

test_that("US-2 the bridge links the re-derived docs roster exactly once each", {
  d <- .br_shipped()
  r <- .br_law_source(d$lines, d$yml, .ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_gte(r$inspected, 1L)
  cat("US-2 BRIDGE CENSUS: roster-hrefs=", r$inspected, " violations=0\n",
      sep = "")
})

test_that("US-2 the built bridge (when the lane site is present) 404-censuses clean", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sd <- .br_site_dir()
  if (is.na(sd)) {
    skip("no lane-built site tree (R CMD check context)")
  }
  r <- .br_law_built(sd, .ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_gte(r$inspected, 1L)
  expect_gte(r$internal, 1L)
  cat("US-2 BUILT CENSUS: roster-hrefs=", r$inspected,
      " internal-hrefs=", r$internal, " broken=0\n", sep = "")
})

# --- red halves -------------------------------------------------------------------------

test_that("US-2 deleting one roster row from the bridge reddens the law", {
  d <- .br_shipped()
  victim <- .br_canonical(.br_href_base(d$yml), .br_roster(.ms_root))[1L]
  keep <- vapply(d$lines, function(l) !grepl(victim, l, fixed = TRUE),
                 logical(1))
  r <- .br_law_source(d$lines[keep], d$yml, .ms_root)
  expect_true(any(grepl(paste0("no bridge link: ", victim), r$violations,
                        fixed = TRUE)))
})

test_that("US-2 a hand-tweaked extra docs href off the roster is named", {
  d <- .br_shipped()
  tampered <- c(d$lines,
    "[phantom](https://github.com/WangLabCSU/msuiter/blob/main/docs/GHOST.md)")
  r <- .br_law_source(tampered, d$yml, .ms_root)
  expect_true(any(grepl("off the re-derived roster", r$violations,
                        fixed = TRUE)))
})

test_that("US-2 forking a corpus heading into the bridge is named", {
  d <- .br_shipped()
  cap <- readLines(file.path(.ms_root, "docs", "CAPABILITY-MATRIX.md"),
                   warn = FALSE)
  h1 <- cap[grep("^# ", cap)[1L]]
  r <- .br_law_source(c(d$lines, h1), d$yml, .ms_root)
  expect_true(any(grepl("inlines corpus heading", r$violations, fixed = TRUE)))
})

test_that("US-2 the constructed-perfect regeneration greens the law (live control)", {
  d <- .br_shipped()
  canon <- .br_canonical(.br_href_base(d$yml), .br_roster(.ms_root))
  synth <- c("---", "title: control", "---", "# navigation only")
  for (h in canon) synth <- c(synth, paste0("[doc](", h, ")"))
  r <- .br_law_source(synth, d$yml, .ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(r$inspected, length(canon))
  victim <- which(vapply(synth, function(l) grepl(canon[1L], l, fixed = TRUE),
                         logical(1)))
  expect_length(victim, 1L)
  r2 <- .br_law_source(synth[-victim[1L]], d$yml, .ms_root)
  expect_true(any(grepl("no bridge link", r2$violations, fixed = TRUE)))
})

test_that("US-2 the built-census tool fires on a constructed-broken page (control)", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  root <- .ms_root
  site <- tempfile("ctl-site-")
  dir.create(site, recursive = TRUE)
  dir.create(file.path(site, "articles"), recursive = TRUE)
  dir.create(file.path(site, "reference"), recursive = TRUE)
  writeLines("index", file.path(site, "reference", "index.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  yml <- readLines(file.path(root, "_pkgdown.yml"), warn = FALSE)
  canon <- .br_canonical(.br_href_base(yml), .br_roster(root))
  anchors <- paste0("<p><a href=\"", canon, "\">doc</a></p>")
  writeLines(c("<html><body>", anchors,
               "<a href=\"nowhere.html\">internal</a></body></html>"),
             file.path(site, "articles", "docs-bridge.html"))
  r <- .br_law_built(site, root)
  expect_true(any(grepl("broken internal href", r$violations, fixed = TRUE)))
  expect_gte(r$internal, 1L)
  writeLines(c("<html><body>", anchors,
               "<a href=\"../reference/index.html\">internal</a></body></html>"),
             file.path(site, "articles", "docs-bridge.html"))
  r2 <- .br_law_built(site, root)
  expect_identical(r2$violations, character(0),
                   info = paste0(r2$violations, collapse = "\n"))
})

test_that("US-2 the roster can never silently empty (vacuous-green guard)", {
  d <- .br_shipped()
  fake <- tempfile("ctl-empty-")
  dir.create(fake, recursive = TRUE)
  dir.create(file.path(fake, "docs"))
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  r <- .br_law_source(d$lines, d$yml, fake)
  expect_true(any(grepl("vacuous", r$violations, fixed = TRUE)))
})
