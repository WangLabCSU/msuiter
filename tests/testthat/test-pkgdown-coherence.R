# test-pkgdown-coherence.R: DS-2 US-3 navbar/article coherence law (docs/site v2).
# pkgdown silently renders what _pkgdown.yml names and silently ignores what it
# does not: an orphaned vignette never reaches the site, a navbar href can
# point into the void, and no build ever complains. This law pins the three
# bijections -- every vignettes/*.Rmd appears exactly once in the articles
# contents, every articles entry owns a real vignette, every navbar structure
# token names a declared component or known built-in -- plus the navbar href
# contract (no root-internal hrefs; internal hrefs must resolve in the built
# tree when the lane-built site is present). Constructed-broken controls name
# the orphan / ghost / dangling href; the constructed-perfect pair greens the
# law. Vacuous-green ban: empty sides are violations, never silent passes.

# --- parsers (pure line walks, this base's tre quirks) -------------------------

.coh_which_pref <- function(vec, p) {
  out <- integer(0)
  for (i in seq_along(vec)) if (startsWith(vec[i], p)) out <- c(out, i)
  out
}

.coh_parse_articles <- function(yml) {
  a <- .coh_which_pref(yml, "articles:")
  if (length(a) != 1L) {
    return(list(ok = FALSE, items = character(0),
                why = paste0("articles: block hits=", length(a))))
  }
  items <- character(0)
  in_contents <- FALSE
  for (i in (a[1L] + 1L):length(yml)) {
    l <- yml[i]
    if (!nzchar(trimws(l)) || startsWith(trimws(l), "#")) next
    if (!startsWith(l, " ") && !startsWith(l, "-")) break
    t <- trimws(l)
    if (identical(t, "contents:")) { in_contents <- TRUE; next }
    if (startsWith(l, "- title:")) { in_contents <- FALSE; next }
    if (in_contents && startsWith(t, "- ")) items <- c(items, trimws(sub("^- ", "", t)))
  }
  list(ok = TRUE, items = items, why = "")
}

# navbar: structure side-tokens + components map (4-space keys, 6-space fields)
.coh_parse_navbar <- function(yml) {
  nb <- .coh_which_pref(yml, "navbar:")
  if (length(nb) != 1L) {
    return(list(ok = FALSE, why = paste0("navbar: block hits=", length(nb)),
                tokens = character(0), components = list()))
  }
  end <- length(yml)
  for (i in (nb[1L] + 1L):length(yml)) {
    l <- yml[i]
    if (nzchar(trimws(l)) && !startsWith(l, " ") && !startsWith(l, "-")) {
      end <- i - 1L
      break
    }
  }
  block <- yml[seq(nb[1L] + 1L, end)]
  tokens <- character(0)
  for (l in block) {
    t <- trimws(l)
    for (side in c("left:", "right:")) {
      if (startsWith(t, side)) {
        spec <- trimws(sub(side, "", t))
        spec <- sub("^\\[", "", sub("\\]$", "", spec))
        for (tok in strsplit(spec, ",")[[1L]]) {
          tok <- trimws(tok)
          if (nzchar(tok)) tokens <- c(tokens, tok)
        }
      }
    }
  }
  components <- list()
  comp0 <- .coh_which_pref(block, "  components:")
  if (length(comp0) == 1L) {
    key <- NULL
    for (i in (comp0[1L] + 1L):length(block)) {
      l <- block[i]
      if (!nzchar(trimws(l))) next
      t <- trimws(l)
      if (startsWith(l, "    ") && !startsWith(l, "     ") &&
          endsWith(t, ":") && !grepl(" ", t, fixed = TRUE)) {
        key <- sub(":$", "", t)
        components[[key]] <- list(text = "", href = "")
        next
      }
      if (!is.null(key) && startsWith(l, "      ")) {
        if (startsWith(t, "text:")) {
          components[[key]]$text <- trimws(sub("^text:", "", t))
        } else if (startsWith(t, "href:")) {
          components[[key]]$href <- trimws(sub("^href:", "", t))
        }
      }
    }
  }
  list(ok = TRUE, why = "", tokens = tokens, components = components)
}

.coh_site_dir <- function() {
  if (is.na(.ms_root)) return(NA_character_)
  sd <- Sys.getenv("MSUITER_DS2_SITE_DIR", "")
  if (nzchar(sd) && dir.exists(sd)) return(normalizePath(sd))
  cand <- file.path(.ms_root, "docs", "dev")
  if (file.exists(file.path(cand, "reference", "index.html")) &&
      file.exists(file.path(cand, "articles", "index.html"))) cand else NA_character_
}

# --- law ---------------------------------------------------------------------------

.coh_builtin <- c("intro", "reference", "news", "github", "search",
                  "vignettes", "articles")

.coh_law <- function(vignettes, art, nb, site_dir = NA_character_) {
  v <- character(0)
  if (length(vignettes) == 0L) v <- c(v, "vacuous: no vignettes found")
  if (!art$ok) v <- c(v, paste0("articles: ", art$why))
  if (art$ok && length(art$items) == 0L) v <- c(v, "vacuous: articles block empty")
  if (length(vignettes) && art$ok && length(art$items)) {
    for (vn in vignettes) {
      n <- sum(art$items == vn)
      if (n == 0L) v <- c(v, paste0("orphan vignette (absent from articles): ", vn))
      if (n > 1L) v <- c(v, paste0("vignette named ", n, " times in articles: ", vn))
    }
    for (an in art$items) {
      if (!an %in% vignettes) {
        v <- c(v, paste0("article entry owns no vignette under vignettes/: ", an))
      }
    }
  }
  if (!nb$ok) {
    v <- c(v, paste0("navbar: ", nb$why))
  } else {
    if (length(nb$tokens) == 0L) v <- c(v, "vacuous: navbar structure empty")
    keys <- names(nb$components)
    for (tok in nb$tokens) {
      if (!tok %in% keys && !tok %in% .coh_builtin) {
        v <- c(v, paste0("navbar token names no declared component and no ",
                         "known built-in: ", tok))
      }
      if (tok %in% keys) {
        comp <- nb$components[[tok]]
        if (!nzchar(comp$text)) v <- c(v, paste0("navbar component lacks text: ", tok))
        if (!nzchar(comp$href)) v <- c(v, paste0("navbar component lacks href: ", tok))
        if (nzchar(comp$href)) {
          ext <- startsWith(comp$href, "http://") || startsWith(comp$href, "https://") ||
                 startsWith(comp$href, "mailto:")
          if (!ext) {
            p <- sub("[#?].*$", "", comp$href)
            if (startsWith(comp$href, "/")) {
              v <- c(v, paste0("root-internal navbar href breaks the census: ", tok))
            } else if (!nzchar(p)) {
              v <- c(v, paste0("empty internal navbar href: ", tok))
            } else if (!is.na(site_dir) &&
                      !file.exists(normalizePath(file.path(site_dir, p),
                                                mustWork = FALSE))) {
              v <- c(v, paste0("navbar href does not resolve in the built tree: ",
                               tok, " -> ", comp$href))
            }
          }
        }
      }
    }
  }
  list(violations = v, vignettes = length(vignettes),
       articles = if (art$ok) length(art$items) else 0L,
       tokens = if (nb$ok) length(nb$tokens) else 0L)
}

# --- green halves ---------------------------------------------------------------------

test_that("US-3 every vignette is registered, every article owns a vignette, navbar is coherent", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  vignettes <- sub("[.]Rmd$", "", sort(basename(list.files(
    file.path(.ms_root, "vignettes"), pattern = "[.]Rmd$"))))
  yml <- readLines(file.path(.ms_root, "_pkgdown.yml"), warn = FALSE)
  r <- .coh_law(vignettes, .coh_parse_articles(yml), .coh_parse_navbar(yml),
                .coh_site_dir())
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_gte(r$vignettes, 1L)
  expect_gte(r$articles, r$vignettes)
  cat("US-3 COHERENCE CENSUS: vignettes=", r$vignettes, " articles=", r$articles,
      " navbar-tokens=", r$tokens, " violations=0\n", sep = "")
})

test_that("US-3 navbar internal hrefs resolve in the built tree when the lane site is present", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sd <- .coh_site_dir()
  if (is.na(sd)) skip("no lane-built site tree (R CMD check context)")
  yml <- readLines(file.path(.ms_root, "_pkgdown.yml"), warn = FALSE)
  nb <- .coh_parse_navbar(yml)
  expect_true(nb$ok)
  internal <- 0L
  for (tok in nb$tokens) {
    h <- nb$components[[tok]]$href
    if (is.null(h) || !nzchar(h)) next
    if (startsWith(h, "http://") || startsWith(h, "https://") ||
        startsWith(h, "mailto:")) next
    internal <- internal + 1L
    expect_true(file.exists(normalizePath(file.path(sd, sub("[#?].*$", "", h)),
                                          mustWork = FALSE)),
                info = paste0("navbar href dead in built tree: ", tok, " -> ", h))
  }
  expect_gte(internal, 1L)   # vacuous-green ban: at least one internal href
  cat("US-3 NAVBAR BUILT CENSUS: internal-hrefs=", internal, " dead=0\n",
      sep = "")
})

# --- red halves ---------------------------------------------------------------------------

test_that("US-3 an orphaned vignette is named by the law (constructed-broken)", {
  yml <- c("navbar:", "  structure:", "    left: [intro]",
           "articles:", "- title: T", "  contents:", "  - intro")
  r <- .coh_law(c("intro", "lonely-orphan"), .coh_parse_articles(yml),
                .coh_parse_navbar(yml))
  expect_true(any(grepl("orphan vignette (absent from articles): lonely-orphan",
                        r$violations, fixed = TRUE)))
})

test_that("US-3 a ghost article entry with no vignette is named", {
  yml <- c("navbar:", "  structure:", "    left: [intro]",
           "articles:", "- title: T", "  contents:", "  - intro", "  - ghost-page")
  r <- .coh_law("intro", .coh_parse_articles(yml), .coh_parse_navbar(yml))
  expect_true(any(grepl("owns no vignette under vignettes/: ghost-page",
                        r$violations, fixed = TRUE)))
})

test_that("US-3 a dangling internal navbar href is named against a synthetic tree", {
  yml <- c("navbar:", "  structure:", "    left: [intro, timemachine]",
           "  components:", "    timemachine:", "      text: Time",
           "      href: timemachine.html",
           "articles:", "- title: T", "  contents:", "  - intro")
  site <- tempfile("ctl-nb-")
  dir.create(site, recursive = TRUE)
  writeLines("x", file.path(site, "index.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  r <- .coh_law("intro", .coh_parse_articles(yml), .coh_parse_navbar(yml), site)
  expect_true(any(grepl("does not resolve in the built tree: timemachine",
                        r$violations, fixed = TRUE)))
})

test_that("US-3 the constructed-perfect pair greens the law (live control)", {
  yml <- c("navbar:", "  structure:", "    left: [intro, guide]",
           "    right: [github]",
           "  components:", "    guide:", "      text: Guide",
           "      href: articles/guide.html",
           "articles:", "- title: Guide", "  contents:", "  - guide",
           "- title: Second", "  contents:", "  - second")
  site <- tempfile("ctl-nb2-")
  dir.create(site, recursive = TRUE)
  dir.create(file.path(site, "articles"), recursive = TRUE)
  writeLines("g", file.path(site, "articles", "guide.html"))
  on.exit(unlink(site, recursive = TRUE), add = TRUE)
  r <- .coh_law(c("guide", "second"), .coh_parse_articles(yml),
                .coh_parse_navbar(yml), site)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(c(r$vignettes, r$articles, r$tokens), c(2L, 2L, 3L))
})

test_that("US-3 empty sides can never pass silently (vacuous guard)", {
  yml <- c("navbar:", "  structure:", "    left: [intro]",
           "articles:", "- title: T", "  contents:", "  - intro")
  r <- .coh_law(character(0), .coh_parse_articles(yml), .coh_parse_navbar(yml))
  expect_true(any(grepl("vacuous: no vignettes found", r$violations,
                        fixed = TRUE)))
})
