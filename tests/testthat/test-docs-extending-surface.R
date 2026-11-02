# test-docs-extending-surface.R: DS-4 US-H3 extending-page API-surface + link law
# (docs/site v4). extending.Rmd presents package entry points as prose tokens
# and the three legacy pages navigate the built site through internal links.
# The law drives the instruments of tools/extending-face.R: every `fn()`- or
# \code{fn}-shaped token the page presents as package API must be an
# export of the NAMESPACE face (or a re-checked sanctioned category: internal
# triple-colon face in the namespace, sanctioned-external with a reason,
# page-self-defined, allowlisted with a reason); every internal link must
# resolve against the built-article name set (vignette basenames + pkgdown
# registrations) and every anchor against the target page's recomputed
# heading slugs. Firing controls: a copied NAMESPACE with an export deleted
# reddens and names it; a renamed-out article reddens and names it; a
# fabricated anchor reddens; a token-free link-free page is vacuous-RED.

# --- instrument access (fail-closed, DS-3 posture) --------------------------------

.ef_tool <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- .ms_src("tools/extending-face.R")
  if (is.na(f) || !file.exists(f)) {
    stop("tools/extending-face.R missing (US-H3 defect)")
  }
  f
}

.ef_env <- function() {
  f <- .ef_tool()
  e <- new.env(parent = globalenv())
  Sys.setenv(MSUITER_TOOL_NO_MAIN = "1")
  on.exit(Sys.unsetenv("MSUITER_TOOL_NO_MAIN"), add = TRUE)
  source(f, local = e)
  need <- c("ef_namespace_exports", "ef_article_set", "ef_slug",
            "ef_allowlist", "ef_externals", "ef_audit")
  for (n in need) {
    if (!exists(n, envir = e, inherits = FALSE)) {
      stop("extending-face tool lost its callable face: ", n)
    }
  }
  e
}

.ef_pages <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "vignettes",
                 c("tour.Rmd", "scenarios.Rmd", "extending.Rmd"))
  miss <- f[!file.exists(f)]
  if (length(miss)) {
    stop("legacy page missing from the checkout (US-H3 defect): ",
         paste0(basename(miss), collapse = ", "))
  }
  f
}

# --- memoized single audit ----------------------------------------------------------------

.ef_state <- new.env()

.ef_run <- function() {
  if (exists("res", envir = .ef_state, inherits = FALSE)) {
    return(get("res", envir = .ef_state))
  }
  e <- .ef_env()
  pages <- .ef_pages()
  a <- e$ef_audit(pages, file.path(.ms_root, "NAMESPACE"), .ms_root)
  res <- list(e = e, pages = pages, audit = a)
  assign("res", res, envir = .ef_state)
  res
}

# --- green halves -------------------------------------------------------------------------

test_that("US-H3 the extending page API surface is real", {
  ctx <- .ef_run()
  a <- ctx$audit
  expect_identical(a$violations, character(0),
                   info = paste0(a$violations, collapse = "\n"))
  expect_true(a$n_tokens >= 8L,
               info = paste0("vacuous token scan: only ", a$n_tokens, " API tokens"))
  expect_true(a$n_exported >= 5L,
               info = paste0("vacuous export join: only ", a$n_exported, " exported"))
  expect_true(a$n_internal >= 1L,
               info = "vacuous internal join: no msuiter::: face exercised")
  cat("US-H3 SURFACE CENSUS: tokens=", a$n_tokens, " exported=", a$n_exported,
      " internal=", a$n_internal, " external=", a$n_external,
      " selfdef=", a$n_selfdef, " allowlisted=", a$n_allowlisted, "\n", sep = "")
})

test_that("US-H3 the registries are spoken-for and unrotten", {
  ctx <- .ef_run()
  e <- ctx$e
  al <- e$ef_allowlist()
  ex <- e$ef_externals()
  expect_true(all(nzchar(al)), info = "allowlisted token without a reason")
  expect_true(all(nzchar(ex)), info = "sanctioned-external without a reason")
  a <- ctx$audit
  unused_al <- setdiff(names(al), a$allowlisted_seen)
  unused_ex <- setdiff(names(ex), a$external_seen)
  expect_identical(unused_al, character(0),
                   info = paste0("allowlist rot (unused): ",
                                 paste0(unused_al, collapse = ", ")))
  expect_identical(unused_ex, character(0),
                   info = paste0("externals rot (unused): ",
                                 paste0(unused_ex, collapse = ", ")))
})

test_that("US-H3 the legacy pages navigate the built site", {
  ctx <- .ef_run()
  a <- ctx$audit
  expect_true(a$n_links >= 3L,
               info = paste0("vacuous link join: only ", a$n_links, " internal links"))
  for (i in seq_along(a$per_page)) {
    expect_true(a$per_page[[i]]$links >= 1L,
                 info = paste0("legacy page carries no internal navigation: ",
                               basename(a$pages[i])))
  }
  cat("US-H3 LINK CENSUS: links=", a$n_links, " ok=", a$n_links_ok,
      " anchors=", a$n_anchors, " violations=0\n", sep = "")
})

# --- red halves: firing controls ----------------------------------------------------------

test_that("US-H3 deleting an export from a copied NAMESPACE face reddens and names it", {
  ctx <- .ef_run()
  ns <- readLines(file.path(.ms_root, "NAMESPACE"), warn = FALSE)
  hit <- grepl("export(ms_extract)", ns, fixed = TRUE)
  expect_length(which(hit), 1L)
  tmp <- tempfile(); writeLines(ns[!hit], tmp)
  a <- ctx$e$ef_audit(ctx$pages, tmp, .ms_root)
  expect_true(any(grepl("ms_extract", a$violations, fixed = TRUE)),
               info = paste0(a$violations, collapse = "\n"))
})

test_that("US-H3 a renamed-out article reddens and names it", {
  ctx <- .ef_run()
  a <- ctx$e$ef_audit(ctx$pages, file.path(.ms_root, "NAMESPACE"), .ms_root,
                      minus_articles = "extending")
  expect_true(any(grepl("extending", a$violations, fixed = TRUE)),
               info = paste0(a$violations, collapse = "\n"))
})

test_that("US-H3 a fabricated anchor is named", {
  ctx <- .ef_run()
  pages <- ctx$pages
  ext <- pages[basename(pages) == "extending.Rmd"]
  lines <- readLines(ext, warn = FALSE)
  hit <- grepl("articles/tour.html", lines, fixed = TRUE)
  expect_true(any(hit))
  bad <- lines
  bad[hit] <- paste0(bad[hit], " or the errors walkthrough [as written](",
                     "#no-such-heading-anywhere)")
  tmp <- tempfile(fileext = ".Rmd"); writeLines(bad, tmp)
  a <- ctx$e$ef_audit(c(pages[basename(pages) != "extending.Rmd"], tmp),
                      file.path(.ms_root, "NAMESPACE"), .ms_root)
  expect_true(any(grepl("no-such-heading-anywhere", a$violations, fixed = TRUE)),
               info = paste0(a$violations, collapse = "\n"))
})

test_that("US-H3 a token-free link-free page is vacuous-RED, never empty-green", {
  ctx <- .ef_run()
  tmp <- tempfile(fileext = ".Rmd")
  writeLines(c("---", "title: t", "---", "", "just prose without any surface."), tmp)
  expect_error(ctx$e$ef_audit(tmp, file.path(.ms_root, "NAMESPACE"), .ms_root),
               "vacuous")
  r <- suppressWarnings(system2(.ms_rscript(),
                                c(.ef_tool(), paste0("--root=", .ms_root),
                                  paste0("--page=", tmp), "--check"),
                                stdout = TRUE, stderr = TRUE))
  st <- attr(r, "status")
  expect_true(!is.null(st) && as.integer(st) != 0L,
               info = "CLI accepted a vacuous page")
  expect_true(grepl("vacuous", paste0(as.character(r), collapse = "\n"), fixed = TRUE))
})
