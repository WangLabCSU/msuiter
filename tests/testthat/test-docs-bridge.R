# test-docs-bridge.R: DS-2 US-2 docs-bridge article laws (docs/site v2, the
# post-conversion form). The former docs/ corpus now lives ON the site as
# vignettes/articles/*.qmd; the bridge is a NAVIGATION page: every corpus
# article the roster names is reachable by exactly one link, and none of the
# corpus is copied. Both sides stay mechanical, no hand roster (the DS-1
# MSU-MAP law shape): the link roster is RE-DERIVED from the
# vignettes/articles/ directory bytes, and the built half (when the
# lane-built tree is present under docs/dev or MSUITER_DS2_SITE_DIR)
# 404-censuses every internal href and proves every roster anchor is really
# in the rendered page. Link extraction is a pure char walk (no regex engine
# -- the .ds2_cell_split precedent). Constructed-broken controls fire every
# rule; the constructed-perfect regeneration is the green control
# (dead-metric law; vacuous-green ban).

# --- roster re-derivation (the single source of truth: the tree bytes) --------

.br_roster <- function(root) {
  art <- file.path(root, "vignettes", "articles")
  if (!dir.exists(art)) {
    return(list(slugs = character(0), required = character(0)))
  }
  files <- sort(basename(list.files(art, pattern = "[.]qmd$",
                                    include.dirs = FALSE)))
  slugs <- sub("[.]qmd$", "", files)
  list(slugs = slugs, required = slugs)
}

# the canonical bridge href of a corpus article: the SITE article page,
# never the repository source (link-not-fork; relative so the built-half
# 404 census actually exercises every link)
.br_canonical <- function(roster) {
  paste0(roster$slugs, ".html")
}

# the bridge text with markdown link spans removed (a title riding as a
# link LABEL is navigation, not forking; only prose inlining is a fork)
.br_text_without_links <- function(text) {
  ch <- strsplit(text, "")[[1L]]
  out <- character(0)
  i <- 1L
  n <- length(ch)
  while (i <= n) {
    if (identical(ch[i], "[")) {
      j <- i + 1L
      lbl <- character(0)
      while (j <= n && !identical(ch[j], "]")) {
        lbl <- c(lbl, ch[j])
        j <- j + 1L
      }
      if (j < n && identical(ch[j + 1L], "(")) {
        k <- j + 2L
        while (k <= n && !identical(ch[k], ")")) k <- k + 1L
        if (k <= n) {
          i <- k + 1L
          next
        }
      }
      out <- c(out, "[", lbl)
      i <- j + 1L
      next
    }
    out <- c(out, ch[i])
    i <- i + 1L
  }
  paste0(out, collapse = "")
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

.br_law_source <- function(bridge_lines, root) {
  roster <- .br_roster(root)
  if (length(roster$required) == 0L) {
    return(list(violations = "vacuous: roster re-derived empty", inspected = 0L))
  }
  canon <- .br_canonical(roster)
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
  # fork-guard: a repository-source href for a corpus article is a hand-tweaked
  # roster entry (the site page, not the .qmd source, is the public face)
  forkish <- links[grepl("blob/main/vignettes/articles/", links, fixed = TRUE)]
  for (h in forkish) {
    v <- c(v, paste0("repository-source href (fork, not link): ", h))
  }
  qmdish <- links[grepl(".qmd", links, fixed = TRUE)]
  for (h in qmdish) {
    v <- c(v, paste0("source-shaped href off the rendered-site roster: ", h))
  }
  # no-fork: no corpus article's own title/H1 may reappear as bridge PROSE
  # (link labels are navigation and exempt -- spans are stripped first)
  prose <- .br_text_without_links(text)
  corpus <- file.path(root, "vignettes", "articles",
                      paste0(roster$slugs, ".qmd"))
  for (f in corpus) {
    ls <- readLines(f, warn = FALSE)
    heads <- character(0)
    tt <- grep('^title: "', ls)
    if (length(tt)) heads <- c(heads, sub('^title: "', "", sub('"$', "", ls[tt[1L]])))
    h1 <- grep("^# ", ls)
    if (length(h1)) heads <- c(heads, ls[h1[1L]])
    for (hd in heads) {
      if (nzchar(hd) && grepl(hd, prose, fixed = TRUE)) {
        v <- c(v, paste0("bridge inlines corpus heading (fork, not link): ",
                         basename(f), " -- ", hd))
      }
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
  canon <- .br_canonical(.br_roster(root))
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
  readLines(bf, warn = FALSE)
}

# --- green halves -----------------------------------------------------------------------

test_that("US-2 the bridge links the re-derived corpus roster exactly once each", {
  d <- .br_shipped()
  r <- .br_law_source(d, .ms_root)
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
  if (!requireNamespace("xml2", quietly = TRUE)) {
    skip("no xml2 on this arm: built-half census not inspectable (R CMD check context)")
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
  victim <- .br_canonical(.br_roster(.ms_root))[1L]
  keep <- vapply(d, function(l) !grepl(victim, l, fixed = TRUE),
                 logical(1))
  r <- .br_law_source(d[keep], .ms_root)
  expect_true(any(grepl(paste0("no bridge link: ", victim), r$violations,
                        fixed = TRUE)))
})

test_that("US-2 a repository-source href for a corpus article is named (fork guard)", {
  d <- .br_shipped()
  tampered <- c(d,
    "[phantom](https://github.com/WangLabCSU/msuiter/blob/main/vignettes/articles/GHOST.qmd)")
  r <- .br_law_source(tampered, .ms_root)
  expect_true(any(grepl("fork, not link", r$violations, fixed = TRUE)))
})

test_that("US-2 a source-shaped (.qmd) href off the rendered-site roster is named", {
  d <- .br_shipped()
  tampered <- c(d, "[phantom](phantom-article.qmd)")
  r <- .br_law_source(tampered, .ms_root)
  expect_true(any(grepl("off the rendered-site roster", r$violations,
                        fixed = TRUE)))
})

test_that("US-2 forking a corpus heading into the bridge is named", {
  d <- .br_shipped()
  art <- file.path(.ms_root, "vignettes", "articles", "capability-matrix.qmd")
  cap <- readLines(art, warn = FALSE)
  tt <- grep('^title: "', cap)[1L]
  title_line <- sub('^title: "', "", sub('"$', "", cap[tt]))
  r <- .br_law_source(c(d, paste0("# ", title_line)), .ms_root)
  expect_true(any(grepl("inlines corpus heading", r$violations, fixed = TRUE)))
})

test_that("US-2 the constructed-perfect regeneration greens the law (live control)", {
  d <- .br_shipped()
  canon <- .br_canonical(.br_roster(.ms_root))
  synth <- c("---", "title: control", "---", "# navigation only")
  for (h in canon) synth <- c(synth, paste0("[doc](", h, ")"))
  r <- .br_law_source(synth, .ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(r$inspected, length(canon))
  victim <- which(vapply(synth, function(l) grepl(canon[1L], l, fixed = TRUE),
                         logical(1)))
  expect_length(victim, 1L)
  r2 <- .br_law_source(synth[-victim[1L]], .ms_root)
  expect_true(any(grepl("no bridge link", r2$violations, fixed = TRUE)))
})

test_that("US-2 the built-census tool fires on a constructed-broken page (control)", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  if (!requireNamespace("xml2", quietly = TRUE)) {
    skip("no xml2 on this arm: built-half census not inspectable (R CMD check context)")
  }
  root <- .ms_root
  site <- tempfile("ctl-site-")
  dir.create(site, recursive = TRUE)
  dir.create(file.path(site, "articles"), recursive = TRUE)
  dir.create(file.path(site, "reference"), recursive = TRUE)
  writeLines("index", file.path(site, "reference", "index.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  canon <- .br_canonical(.br_roster(root))
  for (h in canon) writeLines("stub", file.path(site, "articles", h))
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
  dir.create(file.path(fake, "vignettes", "articles"), recursive = TRUE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  r <- .br_law_source(d, fake)
  expect_true(any(grepl("vacuous", r$violations, fixed = TRUE)))
})
